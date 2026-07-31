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
  static Future<Song?> searchOne(String q) async { final r = await search(q, limit: 1); return r.isEmpty ? null : r.first; }
  static Future<List<Song>> artistRadio(int artistId, {int limit = 25}) => _tracks('/artist/$artistId/radio?limit=$limit');
  /// An artist's popular tracks. Deezer's /top is thin for some artists
  /// (Dr. Dre returns a single song), so top up from their albums and a name
  /// search, de-duplicated, to always show a proper list.
  static Future<List<Song>> artistTop(int artistId, {int limit = 25}) async {
    final top = await _tracks('/artist/$artistId/top?limit=$limit');
    if (top.length >= 8) return top;

    final out = <Song>[...top];
    final seen = <int>{...top.map((s) => s.deezerId)};
    final titles = <String>{...top.map((s) => s.title.toLowerCase())};
    void add(Iterable<Song> songs) {
      for (final s in songs) {
        if (s.artistId != artistId && out.isNotEmpty) continue; // keep it their music
        if (seen.add(s.deezerId) && titles.add(s.title.toLowerCase())) out.add(s);
      }
    }

    try {
      final artistName = top.isNotEmpty ? top.first.artist : (await artist(artistId))?.name;
      // Their albums, newest first — the reliable source of an artist's catalogue.
      final albums = await artistAlbums(artistId, limit: 6);
      final lists = await Future.wait(albums.map((a) => albumTracks(a.id)));
      for (final l in lists) { add(l); if (out.length >= limit) break; }
      if (out.length < limit && artistName != null && artistName.isNotEmpty) {
        add(await search('$artistName', limit: 40));
      }
    } catch (_) {}
    return out.take(limit).toList();
  }

  static Future<List<Artist>> searchArtists(String q, {int limit = 8}) async {
    try {
      final data = ((await _get('/search/artist?q=${Uri.encodeComponent(q)}&limit=$limit'))['data'] as List?) ?? [];
      return data.map((e) => Artist.fromDeezer(e as Map<String, dynamic>)).toList();
    } catch (_) { return []; }
  }

  // Audio dramas / audiobooks that pollute Deezer's global artist chart.
  static final _nonMusic = RegExp(
      r'\?\?\?|!!!|h[oö]rspiel|h[oö]rbuch|\bfolge\s*\d|drei fragezeichen|\bdie drei\b|\bTKKG\b|bibi|'
      r'benjamin bl|conni|pumuckl|feuerwehrmann sam|paw patrol|peppa|five nights|asmr|white noise|'
      r'sleep sounds|schlaflieder|einschlaf|meditation|h[oö]rgeschichte|kinderlieder|gute nacht',
      caseSensitive: false);

  /// Top artists. Deezer's own /chart/0/artists is dominated by German audio
  /// dramas (Die drei ???, TKKG, Bibi…), so we derive the ranking from the
  /// TRACK chart — real music — and only fall back to the artist chart.
  static Future<List<Artist>> chartArtists({int limit = 20}) async {
    try {
      final tracks = await chart(limit: 100);
      final order = <int>[];
      final byId = <int, Artist>{};
      for (final t in tracks) {
        final id = t.artistId;
        if (id == null || t.artist.isEmpty || _nonMusic.hasMatch(t.artist)) continue;
        if (byId.containsKey(id)) continue;
        byId[id] = Artist(id: id, name: t.artist);
        order.add(id);
        if (order.length >= limit) break;
      }
      if (order.isNotEmpty) {
        // Fetch full artist records (pictures + follower counts) in parallel.
        final full = await Future.wait(order.map((id) => artist(id)));
        final out = <Artist>[];
        for (var i = 0; i < order.length; i++) {
          out.add(full[i] ?? byId[order[i]]!);
        }
        return out;
      }
    } catch (_) {}
    try {
      final data = ((await _get('/chart/0/artists?limit=${limit + 30}'))['data'] as List?) ?? [];
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

  /// New releases. Deezer's /editorial/0/releases returns an empty list, so the
  /// album chart is the working source.
  static Future<List<Album>> newReleases({int limit = 20}) async {
    Future<List<Album>> from(String path) async {
      try {
        final data = ((await _get(path))['data'] as List?) ?? [];
        return data
            .map((e) => Album.fromDeezer(e as Map<String, dynamic>))
            .where((a) => !_nonMusic.hasMatch(a.title) && !_nonMusic.hasMatch(a.artist))
            .toList();
      } catch (_) { return []; }
    }
    var out = await from('/chart/0/albums?limit=${limit + 20}');
    if (out.isEmpty) out = await from('/editorial/0/releases?limit=$limit');
    return out.take(limit).toList();
  }
}

class BillboardEntry {
  final int rank; final String song; final String artist; final int? lastWeek; final int? peak; final int? weeks;
  BillboardEntry({required this.rank, required this.song, required this.artist, this.lastWeek, this.peak, this.weeks});
}

/// Billboard Hot 100 via a free, auto-updating public mirror of the weekly chart.
class Billboard {
  static Future<(String?, List<BillboardEntry>)> hot100() async {
    try {
      final r = await http.get(Uri.parse('https://raw.githubusercontent.com/mhollingshead/billboard-hot-100/main/recent.json'));
      final j = jsonDecode(r.body) as Map<String, dynamic>;
      final data = (j['data'] as List?) ?? [];
      final out = <BillboardEntry>[];
      for (var i = 0; i < data.length; i++) {
        final e = data[i] as Map<String, dynamic>;
        out.add(BillboardEntry(
          rank: (e['this_week'] as int?) ?? i + 1,
          song: (e['song'] ?? '') as String,
          artist: (e['artist'] ?? '') as String,
          lastWeek: e['last_week'] as int?, peak: e['peak_position'] as int?, weeks: e['weeks_on_chart'] as int?));
      }
      return (j['date'] as String?, out);
    } catch (_) { return (null, <BillboardEntry>[]); }
  }
}

/// Synced lyrics from lrclib.net (free, no key).
class LyricsApi {
  static Future<Lyrics?> fetch(Song s) async {
    // Try, in order: exact match with duration, exact match without duration,
    // then a search — first with the full title, then with a simplified one
    // ("Song (feat. X) - Remaster" → "Song"). lrclib 404s on near-misses, so a
    // single strict lookup was leaving lots of songs with no lyrics at all.
    final simple = s.title
        .replaceAll(RegExp(r'\s*[\(\[].*?[\)\]]'), '')
        .replaceAll(RegExp(r'\s*-\s*(remaster|remastered|radio edit|single version).*$', caseSensitive: false), '')
        .trim();

    // Duration-matched results FIRST. lrclib often returns a different edit as
    // its top hit (Instant Crush: 367s vs the real 337s), and accepting that
    // gives lyrics that drift badly out of sync.
    Lyrics? out;
    out = await _get({
      'track_name': s.title, 'artist_name': s.artist,
      if (s.album != null) 'album_name': s.album!,
      if (s.duration != null) 'duration': s.duration.toString(),
    });
    out ??= await _search(s.title, s.artist, s.duration);
    if (out == null && simple.isNotEmpty && simple.toLowerCase() != s.title.toLowerCase()) {
      out = await _search(simple, s.artist, s.duration);
    }
    // Only now fall back to an unconstrained lookup.
    out ??= await _get({'track_name': s.title, 'artist_name': s.artist});
    return out;
  }

  static Future<Lyrics?> _get(Map<String, String> params) async {
    try {
      final r = await http.get(Uri.https('lrclib.net', '/api/get', params),
          headers: {'User-Agent': 'SoundCircle'});
      if (r.statusCode != 200) return null;
      return _parse(jsonDecode(r.body) as Map<String, dynamic>);
    } catch (_) { return null; }
  }

  static Future<Lyrics?> _search(String title, String artist, int? duration) async {
    try {
      final r = await http.get(
          Uri.https('lrclib.net', '/api/search', {'track_name': title, 'artist_name': artist}),
          headers: {'User-Agent': 'SoundCircle'});
      if (r.statusCode != 200) return null;
      final list = (jsonDecode(r.body) as List?) ?? [];
      if (list.isEmpty) return null;
      // Prefer a result with synced lyrics and a close duration.
      Map<String, dynamic>? best;
      double bestScore = -1e9;
      for (final e in list.take(10)) {
        final m = (e as Map).cast<String, dynamic>();
        double sc = 0;
        if ((m['syncedLyrics'] as String?)?.trim().isNotEmpty == true) sc += 10;
        final d = (m['duration'] as num?)?.toDouble();
        if (duration != null && d != null) {
          final diff = (d - duration).abs();
          // A close duration means it's the same recording — weight it heavily.
          if (diff <= 2) { sc += 25; }
          else if (diff <= 5) { sc += 15; }
          else if (diff <= 10) { sc += 5; }
          else { sc -= diff; }
        }
        if (sc > bestScore) { bestScore = sc; best = m; }
      }
      return best == null ? null : _parse(best);
    } catch (_) { return null; }
  }

  static Lyrics? _parse(Map<String, dynamic> j) {
    final syncedRaw = j['syncedLyrics'] as String?;
    final plain = j['plainLyrics'] as String?;
    List<LyricLine>? synced;
    if (syncedRaw != null && syncedRaw.trim().isNotEmpty) {
      synced = [];
      for (final line in syncedRaw.split('\n')) {
        final m = RegExp(r'\[(\d+):(\d+)[.:](\d+)\]\s*(.*)').firstMatch(line);
        if (m != null) {
          final t = int.parse(m[1]!) * 60 + int.parse(m[2]!) + int.parse(m[3]!) / 100;
          synced.add(LyricLine(t, (m[4] ?? '').trim()));
        }
      }
      if (synced.isEmpty) synced = null;
    }
    if (synced == null && (plain == null || plain.trim().isEmpty)) return null;
    return Lyrics(synced, plain);
  }
}
