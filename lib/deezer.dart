import 'dart:convert';
import 'package:http/http.dart' as http;

/// A song's metadata (from Deezer). Playback is resolved from YouTube on-device.
class Song {
  final int deezerId;
  final String title;
  final String artist;
  final int? artistId;
  final String? album;
  final int? albumId;
  final String? cover;
  final int? duration;

  Song({
    required this.deezerId,
    required this.title,
    required this.artist,
    this.artistId,
    this.album,
    this.albumId,
    this.cover,
    this.duration,
  });

  factory Song.fromDeezer(Map<String, dynamic> j) {
    final album = j['album'] as Map<String, dynamic>?;
    final artist = j['artist'] as Map<String, dynamic>?;
    return Song(
      deezerId: j['id'] ?? 0,
      title: (j['title_short'] ?? j['title'] ?? '') as String,
      artist: (artist?['name'] ?? '') as String,
      artistId: artist?['id'] as int?,
      album: album?['title'] as String?,
      albumId: album?['id'] as int?,
      cover: (album?['cover_xl'] ?? album?['cover_big'] ?? album?['cover_medium']) as String?,
      duration: j['duration'] as int?,
    );
  }

  Map<String, dynamic> toJson() => {
        'deezerId': deezerId, 'title': title, 'artist': artist, 'artistId': artistId,
        'album': album, 'albumId': albumId, 'cover': cover, 'duration': duration,
      };
  factory Song.fromJson(Map<String, dynamic> j) => Song(
        deezerId: j['deezerId'], title: j['title'], artist: j['artist'], artistId: j['artistId'],
        album: j['album'], albumId: j['albumId'], cover: j['cover'], duration: j['duration'],
      );
}

class Artist {
  final int id;
  final String name;
  final String? picture;
  final int? nbFan;
  final int? nbAlbum;
  Artist({required this.id, required this.name, this.picture, this.nbFan, this.nbAlbum});
  factory Artist.fromDeezer(Map<String, dynamic> j) => Artist(
        id: j['id'], name: j['name'] ?? '',
        picture: (j['picture_xl'] ?? j['picture_big'] ?? j['picture_medium']) as String?,
        nbFan: j['nb_fan'] as int?,
        nbAlbum: j['nb_album'] as int?,
      );
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'picture': picture, 'nbFan': nbFan, 'nbAlbum': nbAlbum};
  factory Artist.fromJson(Map<String, dynamic> j) => Artist(id: j['id'], name: j['name'], picture: j['picture'], nbFan: j['nbFan'], nbAlbum: j['nbAlbum']);
}

class Album {
  final int id;
  final String title;
  final String artist;
  final String? cover;
  final String? releaseDate;
  Album({required this.id, required this.title, required this.artist, this.cover, this.releaseDate});
  factory Album.fromDeezer(Map<String, dynamic> j) => Album(
        id: j['id'], title: j['title'] ?? '',
        artist: (j['artist']?['name'] ?? '') as String,
        cover: (j['cover_xl'] ?? j['cover_big'] ?? j['cover_medium']) as String?,
        releaseDate: j['release_date'] as String?,
      );
}

class LyricLine { final double time; final String text; LyricLine(this.time, this.text); }
class Lyrics { final List<LyricLine>? synced; final String? plain; Lyrics(this.synced, this.plain); }

/// Deezer API — free, no key.
class Deezer {
  static const _base = 'https://api.deezer.com';

  static Future<dynamic> _get(String path) async {
    final r = await http.get(Uri.parse('$_base$path'));
    return jsonDecode(r.body);
  }

  static Future<List<Song>> _tracks(String path) async {
    try {
      final data = ((await _get(path))['data'] as List?) ?? [];
      return data.map((e) => Song.fromDeezer(e as Map<String, dynamic>)).toList();
    } catch (_) { return []; }
  }

  static Future<List<Song>> chart({int limit = 40}) => _tracks('/chart/0/tracks?limit=$limit');
  static Future<List<Song>> search(String q, {int limit = 40}) => _tracks('/search?q=${Uri.encodeComponent(q)}&limit=$limit');
  static Future<List<Song>> artistRadio(int artistId, {int limit = 25}) => _tracks('/artist/$artistId/radio?limit=$limit');
  static Future<List<Song>> artistTop(int artistId, {int limit = 25}) => _tracks('/artist/$artistId/top?limit=$limit');

  static Future<List<Artist>> searchArtists(String q, {int limit = 8}) async {
    try {
      final data = ((await _get('/search/artist?q=${Uri.encodeComponent(q)}&limit=$limit'))['data'] as List?) ?? [];
      return data.map((e) => Artist.fromDeezer(e as Map<String, dynamic>)).toList();
    } catch (_) { return []; }
  }

  // Audio dramas / audiobooks that pollute Deezer's global artist chart.
  static final _nonMusic = RegExp(
      r'\?\?\?|h[oö]rspiel|h[oö]rbuch|\bfolge\s*\d|drei fragezeichen|\bTKKG\b|bibi|benjamin bl|conni|five nights|asmr|white noise|sleep sounds',
      caseSensitive: false);

  static Future<List<Artist>> chartArtists({int limit = 20}) async {
    try {
      final data = ((await _get('/chart/0/artists?limit=${limit + 12}'))['data'] as List?) ?? [];
      return data
          .map((e) => Artist.fromDeezer(e as Map<String, dynamic>))
          .where((a) => !_nonMusic.hasMatch(a.name))
          .take(limit)
          .toList();
    } catch (_) { return []; }
  }

  static Future<Artist?> artist(int id) async {
    try { return Artist.fromDeezer((await _get('/artist/$id')) as Map<String, dynamic>); } catch (_) { return null; }
  }

  static Future<List<Artist>> relatedArtists(int id, {int limit = 12}) async {
    try {
      final data = ((await _get('/artist/$id/related?limit=$limit'))['data'] as List?) ?? [];
      return data.map((e) => Artist.fromDeezer(e as Map<String, dynamic>)).toList();
    } catch (_) { return []; }
  }

  static Future<List<Album>> artistAlbums(int id, {int limit = 30}) async {
    try {
      final data = ((await _get('/artist/$id/albums?limit=$limit'))['data'] as List?) ?? [];
      final seen = <String>{};
      final out = <Album>[];
      for (final a in data) {
        final al = Album.fromDeezer(a as Map<String, dynamic>);
        final key = al.title.replaceAll(RegExp(r'\s*\(.*?\)\s*'), '').toLowerCase();
        if (seen.add(key)) out.add(al);
      }
      return out;
    } catch (_) { return []; }
  }

  static Future<List<Song>> albumTracks(int id) async {
    try {
      final a = (await _get('/album/$id')) as Map<String, dynamic>;
      final cover = (a['cover_xl'] ?? a['cover_big']) as String?;
      final data = (a['tracks']?['data'] as List?) ?? [];
      return data.map((t) {
        final s = Song.fromDeezer(t as Map<String, dynamic>);
        return Song(deezerId: s.deezerId, title: s.title, artist: s.artist, artistId: s.artistId,
            album: a['title'] as String?, albumId: id, cover: cover, duration: s.duration);
      }).toList();
    } catch (_) { return []; }
  }

  static Future<List<Album>> newReleases({int limit = 20}) async {
    try {
      final data = ((await _get('/editorial/0/releases?limit=$limit'))['data'] as List?) ?? [];
      return data.map((e) => Album.fromDeezer(e as Map<String, dynamic>)).toList();
    } catch (_) { return []; }
  }
}

/// Synced lyrics from lrclib.net (free, no key).
class LyricsApi {
  static Future<Lyrics?> fetch(Song s) async {
    try {
      final p = {
        'track_name': s.title,
        'artist_name': s.artist,
        if (s.album != null) 'album_name': s.album!,
        if (s.duration != null) 'duration': s.duration.toString(),
      };
      final uri = Uri.https('lrclib.net', '/api/get', p);
      var r = await http.get(uri, headers: {'User-Agent': 'SoundCircle'});
      if (r.statusCode != 200) {
        // fall back to search
        final sr = await http.get(Uri.https('lrclib.net', '/api/search',
            {'track_name': s.title, 'artist_name': s.artist}), headers: {'User-Agent': 'SoundCircle'});
        final list = jsonDecode(sr.body) as List?;
        if (list == null || list.isEmpty) return null;
        r = http.Response(jsonEncode(list.first), 200);
      }
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final syncedRaw = j['syncedLyrics'] as String?;
      final plain = j['plainLyrics'] as String?;
      List<LyricLine>? synced;
      if (syncedRaw != null && syncedRaw.trim().isNotEmpty) {
        synced = [];
        for (final line in syncedRaw.split('\n')) {
          final m = RegExp(r'\[(\d+):(\d+)\.(\d+)\]\s*(.*)').firstMatch(line);
          if (m != null) {
            final t = int.parse(m[1]!) * 60 + int.parse(m[2]!) + int.parse(m[3]!) / 100;
            synced.add(LyricLine(t, m[4] ?? ''));
          }
        }
      }
      return Lyrics(synced, plain);
    } catch (_) { return null; }
  }
}
