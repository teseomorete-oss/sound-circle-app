import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'deezer.dart';

class Playlist {
  final String id;
  String name;
  List<Song> songs;
  Playlist({required this.id, required this.name, List<Song>? songs}) : songs = songs ?? [];
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'songs': songs.map((s) => s.toJson()).toList()};
  factory Playlist.fromJson(Map<String, dynamic> j) => Playlist(
      id: j['id'], name: j['name'], songs: ((j['songs'] as List?) ?? []).map((e) => Song.fromJson(e)).toList());
}

/// The user's library: likes, playlists, follows, history. Persisted locally.
class Library extends ChangeNotifier {
  final List<Song> liked = [];
  final List<Playlist> playlists = [];
  final List<Artist> followed = [];
  final List<Song> history = []; // most-recent first

  SharedPreferences? _prefs;

  Future<void> init() async {
    _prefs = await SharedPreferences.getInstance();
    _load('liked', (l) => liked..addAll(l.map((e) => Song.fromJson(e as Map<String, dynamic>))));
    _load('history', (l) => history..addAll(l.map((e) => Song.fromJson(e as Map<String, dynamic>))));
    _load('followed', (l) => followed..addAll(l.map((e) => Artist.fromJson(e as Map<String, dynamic>))));
    _load('playlists', (l) => playlists..addAll(l.map((e) => Playlist.fromJson(e as Map<String, dynamic>))));
    notifyListeners();
  }

  void _load(String key, void Function(List) fill) {
    try {
      final raw = _prefs?.getString(key);
      if (raw != null) fill(jsonDecode(raw) as List);
    } catch (_) {}
  }

  void _save(String key, List<dynamic> data) => _prefs?.setString(key, jsonEncode(data));

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
  void _savePlaylists() { _save('playlists', playlists.map((e) => e.toJson()).toList()); notifyListeners(); }
}
