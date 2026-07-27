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

  SharedPreferences? _prefs;

  // ---- Cloud sync (Firestore) ----
  DocumentReference<Map<String, dynamic>>? _cloud;
  Timer? _cloudDebounce;
  bool syncing = false;

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
        _save('liked', liked.map((e) => e.toJson()).toList());
        _save('followed', followed.map((e) => e.toJson()).toList());
        _save('history', history.map((e) => e.toJson()).toList());
        _save('playlists', playlists.map((e) => e.toJson()).toList());
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
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _load('liked', (l) => liked..addAll(l.map((e) => Song.fromJson(e as Map<String, dynamic>))));
    _load('history', (l) => history..addAll(l.map((e) => Song.fromJson(e as Map<String, dynamic>))));
    _load('followed', (l) => followed..addAll(l.map((e) => Artist.fromJson(e as Map<String, dynamic>))));
    _load('playlists', (l) => playlists..addAll(l.map((e) => Playlist.fromJson(e as Map<String, dynamic>))));
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
    if (key != 'downloads') _scheduleCloud(); // downloads are per-device (local files)
  }

  // ---- Likes ----
  bool isLiked(int deezerId) => liked.any((s) => s.deezerId == deezerId);
  void toggleLike(Song s) {
    final i = liked.indexWhere((x) => x.deezerId == s.deezerId);
    if (i >= 0) { liked.removeAt(i); } else { liked.insert(0, s); }
    _save('liked', liked.map((e) => e.toJson()).toList());
    notifyListeners();
  }

  // ---- History ----
  void addHistory(Song s) {
    history.removeWhere((x) => x.deezerId == s.deezerId);
    history.insert(0, s);
    if (history.length > 100) history.removeRange(100, history.length);
    _save('history', history.map((e) => e.toJson()).toList());
    notifyListeners();
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
