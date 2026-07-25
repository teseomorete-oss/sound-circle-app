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

  final List<Song> _loaded = [];   // songs currently in the native playlist
  final List<Song> _upNext = [];   // manual queue (Play next / Add to queue)
  final List<Song> _radio = [];    // hidden autoplay buffer
  bool autoplay = true;

  Duration position = Duration.zero;
  Duration duration = Duration.zero;

  final Map<int, Uri> _urlCache = {};
  void Function(Song)? onPlayed;
  String? Function(int deezerId)? localPath; // returns a downloaded file path if offline-saved

  AudioPlayer get audio => _audio;
  bool get playing => _audio.playing;

  /// The manually-queued songs coming up (Play next / Add to queue), including
  /// the one already pre-loaded after the current track.
  List<Song> get upNext {
    final ci = _audio.currentIndex ?? -1;
    final ahead = (ci >= 0 && _loaded.length > ci + 1) ? _loaded.sublist(ci + 1) : <Song>[];
    return [...ahead, ..._upNext];
  }
  List<Song> get radioNext => List.unmodifiable(_radio);

  /// Remove an item from the visible up-next list (by its position in [upNext]).
  void removeUpNext(int i) {
    final ci = _audio.currentIndex ?? -1;
    final aheadCount = (ci >= 0 && _loaded.length > ci + 1) ? _loaded.length - ci - 1 : 0;
    if (i < aheadCount) {
      final idx = ci + 1 + i;
      _playlist.removeAt(idx);
      _loaded.removeAt(idx);
    } else {
      final j = i - aheadCount;
      if (j >= 0 && j < _upNext.length) _upNext.removeAt(j);
    }
    notifyListeners();
  }

  /// Jump straight to an up-next item.
  Future<void> playUpNext(int i) async {
    final ci = _audio.currentIndex ?? -1;
    final aheadCount = (ci >= 0 && _loaded.length > ci + 1) ? _loaded.length - ci - 1 : 0;
    if (i < aheadCount) {
      await _audio.seek(Duration.zero, index: ci + 1 + i);
    } else {
      final j = i - aheadCount;
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
      if (s.deezerId != current?.deezerId) {
        current = s; error = null; loading = false;
        onPlayed?.call(s);
        _fillRadio();
        notifyListeners();
      }
      _ensureLookahead();
    });
  }

  // Resolve a song → a playable audio stream URL. Uses the ANDROID_VR client,
  // whose stream URLs don't need signature deciphering and play in ExoPlayer
  // without the 403 that the default android/ios stream URLs cause.
  Future<Uri?> _resolveYt(Song s) async {
    final results = await _yt.search.search('${s.artist} ${s.title} audio');
    final video = results.firstOrNull;
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
    final results = await _yt.search.search('${s.artist} ${s.title} audio');
    final video = results.firstOrNull;
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
      ));

  Future<void> playList(List<Song> songs, int index) async {
    _upNext..clear()..addAll(songs.sublist(index + 1));
    _radio.clear();
    await _startWith(songs[index]);
  }

  Future<void> _startWith(Song s) async {
    current = s; loading = true; error = null; notifyListeners();
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
      loading = false; error = 'Could not play "${s.title}"'; notifyListeners();
    }
  }

  // Insert right after the current track so it plays next (background-safe).
  Future<void> playNext(Song s) async {
    final ci = _audio.currentIndex;
    if (ci == null) { await _startWith(s); return; }
    final url = await _resolveUrl(s);
    if (url == null) return;
    await _playlist.insert(ci + 1, _src(s, url));
    _loaded.insert(ci + 1, s);
    notifyListeners();
  }

  void addToQueue(Song s) { _upNext.add(s); notifyListeners(); _ensureLookahead(); }
  void removeFromQueue(int i) { if (i >= 0 && i < _upNext.length) { _upNext.removeAt(i); notifyListeners(); } }

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
      if (_upNext.isNotEmpty) { nxt = _upNext.removeAt(0); notifyListeners(); }
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
    final seen = {..._loaded.map((e) => e.deezerId), ..._upNext.map((e) => e.deezerId), ..._radio.map((e) => e.deezerId)};
    for (final s in songs) { if (seen.add(s.deezerId)) _radio.add(s); }
  }

  @override
  void dispose() { _audio.dispose(); _yt.close(); super.dispose(); }
}
