import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'deezer.dart';

class Playlist {
  final String id;
  String name;
  List<Song> songs;
  String? coverImage;   // local file path (uploaded photo)
  bool coverGradient;   // procedurally-generated cover from the name
  Playlist({required this.id, required this.name, List<Song>? songs, this.coverImage, this.coverGradient = false}) : songs = songs ?? [];
  Map<String, dynamic> toJson() => {
        'id': id, 'name': name, 'songs': songs.map((s) => s.toJson()).toList(),
        'coverImage': coverImage, 'coverGradient': coverGradient,
      };
  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
      id: j['id'], name: j['name'], songs: ((j['songs'] as List?) ?? []).map((e) => Song.fromJson(e)).toList(),
      coverImage: j['coverImage'] as String?, coverGradient: (j['coverGradient'] as bool?) ?? false);
}

/// The user's library: likes, playlists, follows, history. Persisted locally.
class Library extends ChangeNotifier {
  final List<Song> liked = [];
  final List<Playlist> playlists = [];
  final List<Artist> followed = [];
  final List<Song> history = []; // most-recent first
  final List<Song> downloads = [];        // songs saved for offline
  final Map<int, String> _dlPaths = {};   // deezerId -> local file path

  // ---- Listening stats ----
  // Play events (song id + timestamp) so we can answer "top songs this month".
  // Capped so the synced document stays small.
  final List<({int id, DateTime at})> plays = [];
  final Map<int, Song> _songById = {};     // metadata for anything ever played
  static const _maxPlays = 3000;

  SharedPreferences? _prefs;

  // ---- Cloud sync (Firestore) ----
  DocumentReference<Map<String, dynamic>>? _cloud;
  Timer? _cloudDebounce;
  bool syncing = false;

  /// Songs this account had downloaded on another device but that aren't saved
  /// on this one yet — offered as a one-tap restore after signing in.
  final List<Song> restorable = [];
  void clearRestorable() { restorable.clear(); notifyListeners(); }

  /// Called when a song is liked, so the app can save it offline if the user
  /// turned that on. Set from main().
  void Function(Song)? onLiked;

  /// Called when the signed-in user changes. Pulls their library from the cloud
  /// (or seeds the cloud from local on first sign-in), then keeps it in sync.
  Future<void> bindUser(String? uid) async {
    _cloudDebounce?.cancel();
    if (uid == null) { _cloud = null; return; } // guest / logged out → local only
    _cloud = FirebaseFirestore.instance.collection('users').doc(uid);
    syncing = true; notifyListeners();
    try {
      final data = (await _cloud!.get()).data();
      if (data != null && (data['liked'] != null || data['playlists'] != null)) {
        // Cloud is the source of truth — replace the local library with it.
        List<Map<String, dynamic>> ml(String k) =>
            (((data[k] as List?) ?? []).map((e) => (e as Map).cast<String, dynamic>())).toList();
        liked..clear()..addAll(ml('liked').map(Song.fromJson));
        followed..clear()..addAll(ml('followed').map(Artist.fromJson));
        history..clear()..addAll(ml('history').map(Song.fromJson));
        playlists..clear()..addAll(ml('playlists').map(Playlist.fromJson));
        plays..clear()..addAll(ml('plays')
            .map((m) => (id: (m['id'] as num).toInt(), at: DateTime.tryParse('${m['at']}')))
            .where((e) => e.at != null)
            .map((e) => (id: e.id, at: e.at!)));
        _songById..clear()..addEntries(ml('playSongs').map(Song.fromJson).map((s) => MapEntry(s.deezerId, s)));
        _savePlays();
        _save('liked', liked.map((e) => e.toJson()).toList());
        _save('followed', followed.map((e) => e.toJson()).toList());
        _save('history', history.map((e) => e.toJson()).toList());
        _save('playlists', playlists.map((e) => e.toJson()).toList());
        // Offer to re-download anything this account had saved offline elsewhere.
        restorable
          ..clear()
          ..addAll(ml('downloads').map(Song.fromJson).where((s) => !_dlPaths.containsKey(s.deezerId)));
      } else {
        _pushCloud(); // first sign-in: seed the cloud from whatever is local
      }
    } catch (_) {}
    syncing = false; notifyListeners();
  }

  void _scheduleCloud() {
    if (_cloud == null) return;
    _cloudDebounce?.cancel();
    _cloudDebounce = Timer(const Duration(milliseconds: 1200), _pushCloud);
  }

  void _pushCloud() {
    _cloud?.set({
      'liked': liked.map((e) => e.toJson()).toList(),
      'followed': followed.map((e) => e.toJson()).toList(),
      'history': history.map((e) => e.toJson()).toList(),
      'playlists': playlists.map((e) => e.toJson()).toList(),
      // Just the song list — the audio files themselves stay on each device.
      'downloads': downloads.map((e) => e.toJson()).toList(),
      'plays': plays.map((p) => {'id': p.id, 'at': p.at.toIso8601String()}).toList(),
      'playSongs': _songById.values.map((e) => e.toJson()).toList(),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _load('liked', (l) => liked..addAll(l.map((e) => Song.fromJson(e as Map<String, dynamic>))));
    _load('history', (l) => history..addAll(l.map((e) => Song.fromJson(e as Map<String, dynamic>))));
    _load('followed', (l) => followed..addAll(l.map((e) => Artist.fromJson(e as Map<String, dynamic>))));
    _load('playlists', (l) => playlists..addAll(l.map((e) => Playlist.fromJson(e as Map<String, dynamic>))));
    _load('plays', (l) { for (final e in l) {
      final m = e as Map<String, dynamic>;
      final at = DateTime.tryParse('${m['at']}');
      if (at != null) plays.add((id: (m['id'] as num).toInt(), at: at));
    }});
    _load('playSongs', (l) { for (final e in l) {
      final s = Song.fromJson(e as Map<String, dynamic>);
      _songById[s.deezerId] = s;
    }});
    _load('downloads', (l) => l.forEach((e) {
      final m = e as Map<String, dynamic>;
      final s = Song.fromJson(m['song'] as Map<String, dynamic>);
      downloads.add(s); _dlPaths[s.deezerId] = m['path'] as String;
    }));
    notifyListeners();
  }

  bool isDownloaded(int deezerId) => _dlPaths.containsKey(deezerId);
  String? downloadPath(int deezerId) => _dlPaths[deezerId];
  void addDownload(Song s, String path) {
    if (_dlPaths.containsKey(s.deezerId)) return;
    _dlPaths[s.deezerId] = path;
    downloads.insert(0, s);
    _save('downloads', downloads.map((e) => {'song': e.toJson(), 'path': _dlPaths[e.deezerId]}).toList());
    notifyListeners();
  }
  void removeDownload(int deezerId) {
    _dlPaths.remove(deezerId);
    downloads.removeWhere((s) => s.deezerId == deezerId);
    _save('downloads', downloads.map((e) => {'song': e.toJson(), 'path': _dlPaths[e.deezerId]}).toList());
    notifyListeners();
  }

  void _load(String key, void Function(List) fill) {
    try {
      final raw = _prefs?.getString(key);
      if (raw != null) fill(jsonDecode(raw) as List);
    } catch (_) {}
  }

  void _save(String key, List<dynamic> data) {
    _prefs?.setString(key, jsonEncode(data));
    _scheduleCloud(); // for downloads only the song list travels, not the files
  }

  // ---- Likes ----
  bool isLiked(int deezerId) => liked.any((s) => s.deezerId == deezerId);
  void toggleLike(Song s) {
    final i = liked.indexWhere((x) => x.deezerId == s.deezerId);
    if (i >= 0) { liked.removeAt(i); } else { liked.insert(0, s); onLiked?.call(s); }
    _save('liked', liked.map((e) => e.toJson()).toList());
    notifyListeners();
  }

  // ---- History ----
  void addHistory(Song s) {
    history.removeWhere((x) => x.deezerId == s.deezerId);
    history.insert(0, s);
    if (history.length > 100) history.removeRange(100, history.length);
    _save('history', history.map((e) => e.toJson()).toList());

    // Record the play for stats.
    plays.add((id: s.deezerId, at: DateTime.now()));
    if (plays.length > _maxPlays) plays.removeRange(0, plays.length - _maxPlays);
    _songById[s.deezerId] = s;
    _savePlays();
    notifyListeners();
  }

  void _savePlays() {
    _save('plays', plays.map((p) => {'id': p.id, 'at': p.at.toIso8601String()}).toList());
    // Keep metadata only for songs we still reference.
    final live = plays.map((p) => p.id).toSet();
    _songById.removeWhere((k, v) => !live.contains(k));
    _save('playSongs', _songById.values.map((e) => e.toJson()).toList());
  }

  /// Plays within the last [days] (null = all time), newest first.
  List<({int id, DateTime at})> playsSince(int? days) {
    if (days == null) return plays;
    final cutoff = DateTime.now().subtract(Duration(days: days));
    return plays.where((p) => p.at.isAfter(cutoff)).toList();
  }

  Song? songFor(int id) => _songById[id] ??
      history.where((s) => s.deezerId == id).firstOrNull ??
      liked.where((s) => s.deezerId == id).firstOrNull;

  /// Ranked (song, playCount) pairs.
  List<({Song song, int count})> topSongs({int? days, int limit = 20}) {
    final counts = <int, int>{};
    for (final p in playsSince(days)) { counts[p.id] = (counts[p.id] ?? 0) + 1; }
    final out = <({Song song, int count})>[];
    final ids = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    for (final id in ids) {
      final s = songFor(id);
      if (s != null) out.add((song: s, count: counts[id]!));
      if (out.length >= limit) break;
    }
    return out;
  }

  /// Ranked (artist name, playCount) pairs.
  List<({String name, int count, String? picture})> topArtists({int? days, int limit = 20}) {
    final counts = <String, int>{};
    for (final p in playsSince(days)) {
      final s = songFor(p.id);
      if (s == null || s.artist.isEmpty) continue;
      counts[s.artist] = (counts[s.artist] ?? 0) + 1;
    }
    final names = counts.keys.toList()..sort((a, b) => counts[b]!.compareTo(counts[a]!));
    return names.take(limit).map((n) {
      final pic = followed.where((a) => a.name == n).firstOrNull?.picture;
      return (name: n, count: counts[n]!, picture: pic);
    }).toList();
  }

  /// Rough listening time, from each play's track length.
  Duration listenedTime({int? days}) {
    var secs = 0;
    for (final p in playsSince(days)) { secs += songFor(p.id)?.duration ?? 0; }
    return Duration(seconds: secs);
  }

  void clearHistory() { history.clear(); _save('history', []); notifyListeners(); }

  /// Your most-played/liked artists (for the feed's "Your top artists").
  List<String> topArtistNames({int limit = 12}) {
    final w = <String, int>{};
    for (final s in history) { if (s.artist.isNotEmpty) w[s.artist] = (w[s.artist] ?? 0) + 3; }
    for (final s in liked) { if (s.artist.isNotEmpty) w[s.artist] = (w[s.artist] ?? 0) + 2; }
    for (final a in followed) { w[a.name] = (w[a.name] ?? 0) + 2; }
    final list = w.keys.toList()..sort((a, b) => w[b]!.compareTo(w[a]!));
    return list.take(limit).toList();
  }

  // ---- Follows ----
  bool isFollowing(int artistId) => followed.any((a) => a.id == artistId);
  void toggleFollow(Artist a) {
    final i = followed.indexWhere((x) => x.id == a.id);
    if (i >= 0) { followed.removeAt(i); } else { followed.insert(0, a); }
    _save('followed', followed.map((e) => e.toJson()).toList());
    notifyListeners();
  }

  // ---- Playlists ----
  Playlist createPlaylist(String name) {
    final p = Playlist(id: DateTime.now().microsecondsSinceEpoch.toString(), name: name);
    playlists.insert(0, p);
    _savePlaylists();
    return p;
  }
  void deletePlaylist(String id) { playlists.removeWhere((p) => p.id == id); _savePlaylists(); }
  void renamePlaylist(String id, String name) {
    final p = playlists.firstWhere((p) => p.id == id, orElse: () => Playlist(id: '', name: ''));
    if (p.id.isNotEmpty) { p.name = name; _savePlaylists(); }
  }
  void addToPlaylist(String id, Song s) {
    final p = playlists.firstWhere((p) => p.id == id, orElse: () => Playlist(id: '', name: ''));
    if (p.id.isNotEmpty && !p.songs.any((x) => x.deezerId == s.deezerId)) { p.songs.add(s); _savePlaylists(); }
  }
  void removeFromPlaylist(String id, int deezerId) {
    final p = playlists.firstWhere((p) => p.id == id, orElse: () => Playlist(id: '', name: ''));
    if (p.id.isNotEmpty) { p.songs.removeWhere((x) => x.deezerId == deezerId); _savePlaylists(); }
  }
  void setPlaylistCover(String id, {String? image, bool? gradient}) {
    final p = playlists.firstWhere((p) => p.id == id, orElse: () => Playlist(id: '', name: ''));
    if (p.id.isEmpty) return;
    if (image != null) { p.coverImage = image; p.coverGradient = false; }
    else if (gradient == true) { p.coverGradient = true; p.coverImage = null; }
    else { p.coverImage = null; p.coverGradient = false; } // auto (first song)
    _savePlaylists();
  }
  void _savePlaylists() { _save('playlists', playlists.map((e) => e.toJson()).toList()); notifyListeners(); }
}
