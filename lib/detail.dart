import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'deezer.dart';
import 'player.dart';
import 'store.dart';
import 'widgets.dart';

class ArtistScreen extends StatefulWidget {
  final int artistId;
  final String name;
  const ArtistScreen({super.key, required this.artistId, required this.name});
  @override
  State<ArtistScreen> createState() => _ArtistScreenState();
}

class _ArtistScreenState extends State<ArtistScreen> {
  Artist? artist;
  List<Song> top = [];
  List<Album> albums = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    Future.wait([
      Deezer.artist(widget.artistId).then((a) => artist = a),
      Deezer.artistTop(widget.artistId).then((t) => top = t),
      Deezer.artistAlbums(widget.artistId).then((a) => albums = a),
    ]).whenComplete(() => mounted ? setState(() => loading = false) : null);
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final following = lib.isFollowing(widget.artistId);
    final pic = artist?.picture;
    return Scaffold(
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 300,
          pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            title: Text(artist?.name ?? widget.name),
            background: Stack(fit: StackFit.expand, children: [
              if (pic != null) CachedNetworkImage(imageUrl: pic, fit: BoxFit.cover),
              const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black87]))),
            ]),
          ),
        ),
        if (loading)
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())))
        else ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(children: [
                if (top.isNotEmpty)
                  FilledButton.icon(onPressed: () => context.read<Player>().playList(top, 0), icon: const Icon(Icons.play_arrow), label: const Text('Play')),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () => artist != null ? lib.toggleFollow(artist!) : null,
                  child: Text(following ? '✓ Following' : '+ Follow'),
                ),
              ]),
            ),
          ),
          if (top.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionHeader('Popular')),
            SliverList(delegate: SliverChildBuilderDelegate(
              (context, i) => SongTile(song: top[i], queue: top, index: i),
              childCount: top.length > 8 ? 8 : top.length)),
          ],
          if (albums.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionHeader('Albums')),
            SliverToBoxAdapter(child: CardShelf(children: albums.map((a) => AlbumCardW(album: a)).toList())),
          ],
          const SliverToBoxAdapter(child: SizedBox(height: 20)),
        ],
      ]),
    );
  }
}

class AlbumScreen extends StatefulWidget {
  final int albumId;
  final String title;
  const AlbumScreen({super.key, required this.albumId, required this.title});
  @override
  State<AlbumScreen> createState() => _AlbumScreenState();
}

class _AlbumScreenState extends State<AlbumScreen> {
  List<Song> tracks = [];
  bool loading = true;
  @override
  void initState() {
    super.initState();
    Deezer.albumTracks(widget.albumId).then((t) => mounted ? setState(() { tracks = t; loading = false; }) : null);
  }

  @override
  Widget build(BuildContext context) {
    final cv = tracks.isNotEmpty ? tracks.first.cover : null;
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : ListView(children: [
              Padding(
                padding: const EdgeInsets.all(20),
                child: Column(children: [
                  cover(cv, 220, radius: 14, icon: Icons.album),
                  const SizedBox(height: 16),
                  Text(widget.title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800), textAlign: TextAlign.center),
                  if (tracks.isNotEmpty) Text(tracks.first.artist, style: const TextStyle(color: Colors.white60)),
                  const SizedBox(height: 12),
                  FilledButton.icon(
                    onPressed: tracks.isEmpty ? null : () => context.read<Player>().playList(tracks, 0),
                    icon: const Icon(Icons.play_arrow), label: const Text('Play')),
                ]),
              ),
              ...tracks.asMap().entries.map((e) => SongTile(song: e.value, queue: tracks, index: e.key, showArt: false)),
              const SizedBox(height: 20),
            ]),
    );
  }
}
