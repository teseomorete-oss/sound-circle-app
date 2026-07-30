import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import 'deezer.dart';

/// Playback: resolves songs to YouTube audio on-device, then feeds them into the
/// NATIVE player's own gapless playlist with one track pre-loaded ahead. That
/// way Android advances to the next song by itself — even with the screen off /
/// app suspended — instead of relying on Dart code that gets frozen in the
/// background. A hidden "radio" keeps it endless.
class Player extends ChangeNotifier {
  final _yt = YoutubeExplode();
  final _audio = AudioPlayer();
  final _playlist = ConcatenatingAudioSource(children: []);
  bool _playlistSet = false;

  Song? current;
  bool loading = false;
  String? error;
  bool needsDownloads = false; // last failure was likely offline → offer downloads

  final List<Song> _loaded = [];   // songs currently in the native playlist
  final List<Song> _upNext = [];   // manual queue (Play next / Add to queue) — SHOWN
  final List<Song> _context = [];  // rest of the album/playlist being played — hidden
  final List<Song> _radio = [];    // hidden autoplay buffer
  final Set<int> _manualIds = {};  // ids the user explicitly queued (never played yet)
  bool autoplay = true;

  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  final Map<int, Uri> _urlCache = {};
  void Function(Song)? onPlayed;
  void Function(String message, bool offline)? onError;
  String? Function(int deezerId)? localPath; // returns a downloaded file path if offline-saved

  AudioPlayer get audio => _audio;
  bool get playing => _audio.playing;

  /// The songs the user manually queued (Play next / Add to queue) that haven't
  /// played yet — including one that may already be pre-loaded after the current
  /// track. The hidden autoplay radio is deliberately NOT included here.
  List<Song> _aheadManual() {
    final ci = _audio.currentIndex ?? -1;
    if (ci < 0 || _loaded.length <= ci + 1) return [];
    return _loaded.sublist(ci + 1).where((s) => _manualIds.contains(s.deezerId)).toList();
  }

  List<Song> get manualQueue => [..._aheadManual(), ..._upNext];
  bool get hasManualQueue => manualQueue.isNotEmpty;
  List<Song> get radioNext => List.unmodifiable(_radio);

  /// Remove an item from the visible manual queue (by its position in [manualQueue]).
  void removeUpNext(int i) {
    final aheadManual = _aheadManual();
    if (i < aheadManual.length) {
      final s = aheadManual[i];
      final idx = _loaded.indexOf(s);
      if (idx >= 0) { _playlist.removeAt(idx); _loaded.removeAt(idx); }
      _manualIds.remove(s.deezerId);
    } else {
      final j = i - aheadManual.length;
      if (j >= 0 && j < _upNext.length) { _manualIds.remove(_upNext[j].deezerId); _upNext.removeAt(j); }
    }
    notifyListeners();
  }

  /// Drag-reorder the manual queue (indices into [manualQueue]).
  void reorderQueue(int oldIndex, int newIndex) {
    final q = manualQueue;
    if (oldIndex < 0 || oldIndex >= q.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    newIndex = newIndex.clamp(0, q.length - 1);
    if (oldIndex == newIndex) return;
    // Rebuild a single ordered manual list, then re-seat it: drop the pre-loaded
    // ahead item back into _upNext so ordering is simple and consistent.
    final aheadManual = _aheadManual();
    for (final s in aheadManual) {
      final idx = _loaded.indexOf(s);
      if (idx >= 0) { _playlist.removeAt(idx); _loaded.removeAt(idx); }
    }
    final combined = [...aheadManual, ..._upNext];
    final moved = combined.removeAt(oldIndex);
    combined.insert(newIndex, moved);
    _upNext..clear()..addAll(combined);
    notifyListeners();
    _ensureLookahead();
  }

  /// Jump straight to a manual-queue item.
  Future<void> playUpNext(int i) async {
    final aheadManual = _aheadManual();
    if (i < aheadManual.length) {
      final idx = _loaded.indexOf(aheadManual[i]);
      if (idx >= 0) await _audio.seek(Duration.zero, index: idx);
    } else {
      final j = i - aheadManual.length;
      if (j >= 0 && j < _upNext.length) {
        final s = _upNext.removeAt(j);
        await playNext(s);
        await next();
      }
    }
  }

  Player() {
    _audio.positionStream.listen((p) { position = p; notifyListeners(); });
    _audio.durationStream.listen((d) { duration = d ?? Duration.zero; notifyListeners(); });
    _audio.playerStateStream.listen((st) {
      // Reached the very end of the loaded playlist → try to extend with radio.
      if (st.processingState == ProcessingState.completed) {
        _ensureLookahead().then((_) { if (_audio.hasNext) _audio.seekToNext(); });
      }
      notifyListeners();
    });
    // Native advanced to the next (pre-loaded) track — sync our state.
    _audio.currentIndexStream.listen((i) {
      if (i == null || i >= _loaded.length) return;
      final s = _loaded[i];
      _manualIds.remove(s.deezerId); // it's now playing, no longer "up next"
      if (s.deezerId != current?.deezerId) {
        current = s; error = null; loading = false;
        onPlayed?.call(s);
        _fillRadio();
        notifyListeners();
      }
      _ensureLookahead();
    });
  }

  // Pick the YouTube result that best matches the Deezer track — by title/artist
  // words and, crucially, by duration — so e.g. "Algo Va A Pasar" doesn't get a
  // random Quevedo upload. Falls back to the first result if nothing scores well.
  Future<Video?> _bestVideo(Song s) async {
    final results = await _yt.search.search('${s.artist} ${s.title}');
    if (results.isEmpty) return null;
    final titleL = s.title.toLowerCase();
    final artistL = s.artist.toLowerCase();
    // significant words of the title (ignore short filler)
    final titleWords = titleL.split(RegExp(r'[^a-z0-9áéíóúñ]+')).where((w) => w.length > 2).toSet();
    Video? best; double bestScore = -1e9;
    for (final v in results.take(7)) {
      final vt = v.title.toLowerCase();
      final va = v.author.toLowerCase();
      double score = 0;
      // title word overlap
      if (titleWords.isNotEmpty) {
        final hit = titleWords.where((w) => vt.contains(w)).length / titleWords.length;
        score += hit * 4;
      }
      if (vt.contains(artistL) || va.contains(artistL)) score += 3;
      // duration proximity (the strongest signal)
      final d = v.duration?.inSeconds;
      if (s.duration != null && d != null && d > 0) {
        final diff = (d - s.duration!).abs();
        if (diff <= 2) { score += 5; }
        else if (diff <= 6) { score += 3; }
        else if (diff <= 15) { score += 1; }
        else if (diff > 40) { score -= 4; }
      }
      // Hard-reject karaoke/instrumental/cover style uploads — these often match
      // the duration perfectly, so a small penalty wasn't enough to beat them.
      for (final bad in const ['karaoke', 'instrumental', 'backing track', 'sin voz', 'pista']) {
        if (vt.contains(bad) && !titleL.contains(bad)) score -= 25;
      }
      for (final bad in const ['live', 'en vivo', 'cover', 'remix', 'sped up', 'slowed',
                               'reverb', 'mashup', '8d', 'tutorial', 'reaction', 'parodia']) {
        if (vt.contains(bad) && !titleL.contains(bad)) score -= 6;
      }
      // Prefer official uploads: artist topic channels and VEVO are the real thing.
      if (va.contains('topic') || va.contains('vevo') || va.contains('official')) score += 4;
      if (score > bestScore) { bestScore = score; best = v; }
    }
    return best ?? results.first;
  }

  // Resolve a song → a playable audio stream URL. Uses the ANDROID_VR client,
  // whose stream URLs don't need signature deciphering and play in ExoPlayer
  // without the 403 that the default android/ios stream URLs cause.
  Future<Uri?> _resolveYt(Song s) async {
    final video = await _bestVideo(s);
    if (video == null) return null;
    StreamManifest? manifest;
    for (final client in [YoutubeApiClient.androidVr, YoutubeApiClient.ios, YoutubeApiClient.android]) {
      try {
        final m = await _yt.videos.streamsClient.getManifest(video.id, ytClients: [client]);
        if (m.audioOnly.isNotEmpty) { manifest = m; break; }
      } catch (_) {}
    }
    if (manifest == null) return null;
    return manifest.audioOnly.withHighestBitrate().url;
  }

  Future<Uri?> _resolveUrl(Song s) async {
    final local = localPath?.call(s.deezerId);
    if (local != null) return Uri.file(local);
    if (_urlCache.containsKey(s.deezerId)) return _urlCache[s.deezerId];
    final url = await _resolveYt(s);
    if (url != null) _urlCache[s.deezerId] = url;
    return url;
  }

  /// A byte stream of a song's audio (used by the downloader) — goes through
  /// youtube_explode's own client so YouTube's range/headers requirements are met.
  Future<Stream<List<int>>?> audioByteStream(Song s) async {
    final video = await _bestVideo(s);
    if (video == null) return null;
    for (final client in [YoutubeApiClient.androidVr, YoutubeApiClient.ios, YoutubeApiClient.android]) {
      try {
        final m = await _yt.videos.streamsClient.getManifest(video.id, ytClients: [client]);
        if (m.audioOnly.isNotEmpty) return _yt.videos.streamsClient.get(m.audioOnly.withHighestBitrate());
      } catch (_) {}
    }
    return null;
  }

  AudioSource _src(Song s, Uri url) => AudioSource.uri(url, tag: MediaItem(
        id: s.deezerId.toString(), title: s.title, artist: s.artist, album: s.album,
        artUri: s.cover != null ? Uri.parse(s.cover!) : null,
        // Duration lets the lock screen draw a seek bar / remaining time.
        duration: s.duration != null ? Duration(seconds: s.duration!) : null,
        displayTitle: s.title,
        displaySubtitle: s.artist,
        displayDescription: s.album,
      ));

  Future<void> playList(List<Song> songs, int index) async {
    // Starting a fresh context wipes the old manual queue and radio. The rest of
    // this list plays automatically but is kept hidden from the manual queue.
    _upNext.clear();
    _radio.clear();
    _manualIds.clear();
    _context..clear()..addAll(songs.sublist(index + 1));
    await _startWith(songs[index]);
  }

  Future<void> _startWith(Song s) async {
    current = s; loading = true; error = null; needsDownloads = false; notifyListeners();
    try {
      final url = await _resolveUrl(s);
      if (url == null) throw 'No source';
      await _playlist.clear();
      _loaded.clear();
      await _playlist.add(_src(s, url));
      _loaded.add(s);
      if (!_playlistSet) { await _audio.setAudioSource(_playlist); _playlistSet = true; }
      else { await _audio.seek(Duration.zero, index: 0); }
      loading = false; notifyListeners();
      _audio.play();
      onPlayed?.call(s);
      _fillRadio();
      _ensureLookahead();
    } catch (e) {
      loading = false;
      final online = await _online();
      error = online ? 'Couldn\'t play "${s.title}"' : 'No internet connection';
      needsDownloads = !online;
      notifyListeners();
      onError?.call(error!, !online);
    }
  }

  // Lightweight connectivity probe (no extra package).
  Future<bool> _online() async {
    try {
      final r = await InternetAddress.lookup('one.one.one.one').timeout(const Duration(seconds: 3));
      return r.isNotEmpty && r.first.rawAddress.isNotEmpty;
    } catch (_) { return false; }
  }

  // Is this song already coming up (pre-loaded ahead or in the manual queue)?
  bool _alreadyUpcoming(Song s) {
    final ci = _audio.currentIndex ?? -1;
    final ahead = (ci >= 0 && _loaded.length > ci + 1) ? _loaded.sublist(ci + 1) : const <Song>[];
    return ahead.any((x) => x.deezerId == s.deezerId) || _upNext.any((x) => x.deezerId == s.deezerId);
  }

  // Insert right after the current track so it plays next (background-safe).
  Future<void> playNext(Song s) async {
    final ci = _audio.currentIndex;
    if (ci == null) { await _startWith(s); return; }
    if (_alreadyUpcoming(s)) { _manualIds.add(s.deezerId); notifyListeners(); return; } // don't duplicate
    final url = await _resolveUrl(s);
    if (url == null) return;
    await _playlist.insert(ci + 1, _src(s, url));
    _loaded.insert(ci + 1, s);
    _manualIds.add(s.deezerId);
    notifyListeners();
  }

  void addToQueue(Song s) {
    if (_alreadyUpcoming(s)) { _manualIds.add(s.deezerId); notifyListeners(); return; } // already queued/next
    _upNext.add(s); _manualIds.add(s.deezerId); notifyListeners(); _ensureLookahead();
  }
  void removeFromQueue(int i) { if (i >= 0 && i < _upNext.length) { _manualIds.remove(_upNext[i].deezerId); _upNext.removeAt(i); notifyListeners(); } }

  void toggle() { _audio.playing ? _audio.pause() : _audio.play(); notifyListeners(); }
  void seek(Duration d) => _audio.seek(d);

  bool get repeatOne => _audio.loopMode == LoopMode.one;
  void toggleRepeat() { _audio.setLoopMode(repeatOne ? LoopMode.off : LoopMode.one); notifyListeners(); }

  bool shuffle = false;
  void toggleShuffle() { shuffle = !shuffle; if (shuffle) { _radio.shuffle(); _upNext.shuffle(); } notifyListeners(); }

  Future<void> next() async {
    if (_audio.hasNext) { await _audio.seekToNext(); return; }
    await _ensureLookahead();
    if (_audio.hasNext) await _audio.seekToNext();
  }

  Future<void> prev() async {
    // Restart the track if we're a few seconds in, otherwise go to the previous.
    if (_audio.position.inSeconds > 3 || !_audio.hasPrevious) { await _audio.seek(Duration.zero); }
    else { await _audio.seekToPrevious(); }
  }

  // Always keep exactly one resolved track loaded after the current one, so the
  // OS can advance to it on its own with the app asleep.
  bool _looking = false;
  Future<void> _ensureLookahead() async {
    if (_looking) return;
    final ci = _audio.currentIndex;
    if (ci == null || _loaded.length > ci + 1) return;
    _looking = true;
    try {
      Song? nxt;
      if (_upNext.isNotEmpty) { nxt = _upNext.removeAt(0); notifyListeners(); } // manual queue first
      else if (_context.isNotEmpty) { nxt = _context.removeAt(0); }             // then album/playlist rest
      else { if (_radio.isEmpty) await _fillRadio(); if (_radio.isNotEmpty) nxt = _radio.removeAt(0); }
      if (nxt != null) {
        final url = await _resolveUrl(nxt);
        if (url != null) { await _playlist.add(_src(nxt, url)); _loaded.add(nxt); }
      }
    } catch (_) {} finally { _looking = false; }
  }

  Future<void> _fillRadio() async {
    if (!autoplay || current?.artistId == null || _radio.length >= 3) return;
    final songs = await Deezer.artistRadio(current!.artistId!);
    final seen = {..._loaded.map((e) => e.deezerId), ..._upNext.map((e) => e.deezerId), ..._context.map((e) => e.deezerId), ..._radio.map((e) => e.deezerId)};
    for (final s in songs) { if (seen.add(s.deezerId)) _radio.add(s); }
  }

  @override
  void dispose() { _audio.dispose(); _yt.close(); super.dispose(); }
}
