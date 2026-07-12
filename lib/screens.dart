import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'deezer.dart';
import 'player.dart';
import 'store.dart';
import 'settings.dart';
import 'widgets.dart';

String greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}

// ---------------- Home ----------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Song> trending = [];
  List<Album> releases = [];
  List<Artist> topArtists = [];
  List<Song> becausePlayed = [];
  bool loading = true;

  @override
  void initState() { super.initState(); _load(); }

  Future<void> _load() async {
    final lib = context.read<Library>();
    final names = lib.topArtistNames();
    final results = await Future.wait([
      Deezer.chart(),
      Deezer.newReleases(),
      Future.wait(names.take(10).map((n) => Deezer.searchArtists(n, limit: 1).then((r) => r.isNotEmpty ? r.first : null))),
      names.isNotEmpty
          ? Deezer.searchArtists(names.first, limit: 1).then((r) => r.isNotEmpty ? Deezer.artistRadio(r.first.id, limit: 15) : <Song>[])
          : Future.value(<Song>[]),
    ]);
    if (!mounted) return;
    setState(() {
      trending = results[0] as List<Song>;
      releases = results[1] as List<Album>;
      topArtists = (results[2] as List).whereType<Artist>().toList();
      if (topArtists.isEmpty) { Deezer.chartArtists().then((a) => mounted ? setState(() => topArtists = a) : null); }
      becausePlayed = results[3] as List<Song>;
      loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final lib = context.watch<Library>();
    final hi = '${greeting()}${settings.displayName.isNotEmpty ? ', ${settings.displayName}' : ''}';
    return RefreshIndicator(
      onRefresh: _load,
      child: loading
          ? ListView(children: const [SizedBox(height: 200), Center(child: CircularProgressIndicator())])
          : ListView(children: [
              Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                child: Text(hi, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),
              if (lib.history.isNotEmpty) ...[
                const SectionHeader('Recently played'),
                ...lib.history.take(5).toList().asMap().entries.map((e) => SongTile(song: e.value, queue: lib.history, index: e.key)),
              ],
              if (becausePlayed.isNotEmpty) ...[
                SectionHeader('Because you played ${lib.topArtistNames().first}'),
                CardShelf(children: becausePlayed.map((s) => _MiniSong(song: s, queue: becausePlayed, index: becausePlayed.indexOf(s))).toList()),
              ],
              if (topArtists.isNotEmpty) ...[
                SectionHeader(lib.history.isNotEmpty ? 'Your top artists' : 'Popular artists'),
                CardShelf(children: topArtists.map((a) => ArtistCardW(artist: a)).toList()),
              ],
              if (settings.showTrending) ...[
                const SectionHeader('Trending now'),
                ...trending.take(10).toList().asMap().entries.map((e) => SongTile(song: e.value, queue: trending, index: e.key)),
              ],
              if (releases.isNotEmpty) ...[
                const SectionHeader('New releases'),
                CardShelf(children: releases.map((a) => AlbumCardW(album: a)).toList()),
              ],
              const SizedBox(height: 20),
            ]),
    );
  }
}

class _MiniSong extends StatelessWidget {
  final Song song; final List<Song> queue; final int index;
  const _MiniSong({required this.song, required this.queue, required this.index});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => context.read<Player>().playList(queue, index),
        onLongPress: () => showSongMenu(context, song),
        child: Container(width: 140, margin: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            cover(song.cover, 140, radius: 10),
            const SizedBox(height: 6),
            Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white54)),
          ]),
        ),
      );
}

// ---------------- Search ----------------
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  List<Song> songs = [];
  List<Artist> artists = [];
  bool loading = false;

  Future<void> _run(String q) async {
    if (q.trim().isEmpty) return;
    setState(() => loading = true);
    final r = await Future.wait([Deezer.search(q.trim()), Deezer.searchArtists(q.trim())]);
    if (!mounted) return;
    setState(() { songs = r[0] as List<Song>; artists = r[1] as List<Artist>; loading = false; });
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: TextField(
          controller: _ctrl, textInputAction: TextInputAction.search, onSubmitted: _run,
          decoration: InputDecoration(
            hintText: 'Songs, artists, albums…', prefixIcon: const Icon(Icons.search),
            filled: true, fillColor: surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none)),
        ),
      ),
      if (loading) const Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()),
      Expanded(
        child: ListView(children: [
          if (artists.isNotEmpty) ...[
            const SectionHeader('Artists'),
            CardShelf(children: artists.map((a) => ArtistCardW(artist: a)).toList()),
          ],
          if (songs.isNotEmpty) const SectionHeader('Songs'),
          ...songs.asMap().entries.map((e) => SongTile(song: e.value, queue: songs, index: e.key)),
        ]),
      ),
    ]);
  }
}

// ---------------- Library ----------------
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final player = context.read<Player>();
    return ListView(children: [
      const Padding(padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text('Library', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),

      Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Playlists', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          TextButton.icon(onPressed: () async {
            final name = await promptName(context);
            if (name != null && name.isNotEmpty) lib.createPlaylist(name);
          }, icon: const Icon(Icons.add, size: 18), label: const Text('New')),
        ]),
      ),
      if (lib.playlists.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('No playlists yet.', style: TextStyle(color: Colors.white54)))
      else
        ...lib.playlists.map((p) => ListTile(
              leading: cover(p.songs.isNotEmpty ? p.songs.first.cover : null, 50, icon: Icons.queue_music),
              title: Text(p.name),
              subtitle: Text('${p.songs.length} songs'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlaylistScreen(id: p.id))),
            )),

      const SectionHeader('Liked songs'),
      if (lib.liked.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('Songs you like show up here.', style: TextStyle(color: Colors.white54)))
      else ...[
        ListTile(
          leading: const CircleAvatar(backgroundColor: Color(0xFFA855F7), child: Icon(Icons.favorite, color: Colors.white)),
          title: const Text('Play liked songs'),
          onTap: () => player.playList(lib.liked, 0),
        ),
        ...lib.liked.take(30).toList().asMap().entries.map((e) => SongTile(song: e.value, queue: lib.liked, index: e.key)),
      ],

      if (lib.followed.isNotEmpty) ...[
        const SectionHeader('Following'),
        CardShelf(children: lib.followed.map((a) => ArtistCardW(artist: a)).toList()),
      ],
      const SizedBox(height: 20),
    ]);
  }
}

class PlaylistScreen extends StatelessWidget {
  final String id;
  const PlaylistScreen({super.key, required this.id});
  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final player = context.read<Player>();
    final p = lib.playlists.firstWhere((x) => x.id == id, orElse: () => Playlist(id: '', name: 'Playlist'));
    return Scaffold(
      appBar: AppBar(title: Text(p.name), actions: [
        IconButton(icon: const Icon(Icons.edit), onPressed: () async {
          final name = await promptName(context, initial: p.name);
          if (name != null && name.isNotEmpty) lib.renamePlaylist(id, name);
        }),
        IconButton(icon: const Icon(Icons.delete_outline), onPressed: () { lib.deletePlaylist(id); Navigator.pop(context); }),
      ]),
      body: ListView(children: [
        Padding(padding: const EdgeInsets.all(16), child: FilledButton.icon(
          onPressed: p.songs.isEmpty ? null : () => player.playList(p.songs, 0),
          icon: const Icon(Icons.play_arrow), label: const Text('Play'))),
        ...p.songs.asMap().entries.map((e) => Dismissible(
              key: ValueKey(e.value.deezerId),
              direction: DismissDirection.endToStart,
              background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete)),
              onDismissed: (_) => lib.removeFromPlaylist(id, e.value.deezerId),
              child: SongTile(song: e.value, queue: p.songs, index: e.key),
            )),
      ]),
    );
  }
}
