import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'deezer.dart';
import 'player.dart';
import 'store.dart';
import 'widgets.dart';
import 'main.dart';

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
  List<Artist> related = [];
  bool loading = true;

  @override
  void initState() {
    super.initState();
    Future.wait([
      Deezer.artist(widget.artistId).then((a) => artist = a),
      Deezer.artistTop(widget.artistId).then((t) => top = t),
      Deezer.artistAlbums(widget.artistId).then((a) => albums = a),
      Deezer.relatedArtists(widget.artistId).then((a) => related = a),
    ]).whenComplete(() => mounted ? setState(() => loading = false) : null);
  }

  String _description() {
    final a = artist;
    if (a == null) return '';
    final parts = <String>[];
    if (a.nbFan != null && a.nbFan! > 0) parts.add('${fanCount(a.nbFan)} fans');
    if (a.nbAlbum != null && a.nbAlbum! > 0) parts.add('${a.nbAlbum} releases');
    final tail = parts.isEmpty ? '' : ' — ${parts.join(' · ')}';
    return '${a.name} is one of the artists in your Sound Circle$tail. '
        'Explore their top tracks, albums, and dive into a radio of similar music.';
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final following = lib.isFollowing(widget.artistId);
    final pic = artist?.picture;
    final accent = Theme.of(context).colorScheme.primary;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    return Scaffold(
      bottomNavigationBar: const MiniPlayer(), // keep the playing bar visible here too
      body: Stack(children: [
        CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 320,
          pinned: true,
          flexibleSpace: Stack(fit: StackFit.expand, children: [
            if (pic != null) CachedNetworkImage(imageUrl: pic, fit: BoxFit.cover),
            // Fade anchored to the BOTTOM of the header (the seam with the page),
            // so it always melts into the black UI — never showing the photo's edge.
            Positioned(left: 0, right: 0, bottom: 0, child: IgnorePointer(child: Container(
              height: 300,
              decoration: BoxDecoration(gradient: LinearGradient(
                begin: Alignment.topCenter, end: Alignment.bottomCenter,
                stops: const [0.0, 0.55, 1.0],
                colors: [Colors.transparent, bg.withValues(alpha: 0.7), bg])),
            ))),
            FlexibleSpaceBar(
              titlePadding: const EdgeInsets.only(left: 16, bottom: 14, right: 16),
              title: Text(artist?.name ?? widget.name, style: const TextStyle(fontWeight: FontWeight.w800)),
            ),
          ]),
        ),
        if (loading)
          const SliverToBoxAdapter(child: Padding(padding: EdgeInsets.all(40), child: Center(child: CircularProgressIndicator())))
        else ...[
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Row(children: [
                if (artist?.nbFan != null)
                  Text('${fanCount(artist!.nbFan)} followers', style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w600)),
                const Spacer(),
                if (top.isNotEmpty)
                  IconButton.filled(onPressed: () => context.read<Player>().playList(top, 0), icon: const Icon(Icons.play_arrow)),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: following ? accent : Colors.white,
                    side: BorderSide(color: following ? accent : Colors.white38)),
                  onPressed: () => artist != null ? lib.toggleFollow(artist!) : null,
                  icon: Icon(following ? Icons.check : Icons.add, size: 18),
                  label: Text(following ? 'Following' : 'Follow'),
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
          // Mixes & radios built from this artist
          if (top.isNotEmpty || artist != null) ...[
            const SliverToBoxAdapter(child: SectionHeader('Mixes & radios')),
            SliverToBoxAdapter(child: CardShelf(children: [
              MixCard(title: '${artist?.name ?? widget.name} Radio', subtitle: 'Endless mix', cover: pic,
                gradient: [accent, const Color(0xFF1E293B)],
                resolve: () => Deezer.artistRadio(widget.artistId, limit: 40)),
              if (top.isNotEmpty)
                MixCard(title: 'This Is ${artist?.name ?? widget.name}', subtitle: 'Their essentials', cover: top.first.cover,
                  gradient: [const Color(0xFF7C3AED), const Color(0xFFEC4899)],
                  resolve: () => Deezer.artistTop(widget.artistId, limit: 40)),
            ])),
          ],
          if (albums.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionHeader('Albums')),
            // Bigger album covers than the song shelves.
            SliverToBoxAdapter(child: SizedBox(
              height: 230,
              child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12),
                children: albums.map((a) => _BigAlbumCard(album: a)).toList()),
            )),
          ],
          if (related.isNotEmpty) ...[
            const SliverToBoxAdapter(child: SectionHeader('Fans also like')),
            SliverToBoxAdapter(child: CardShelf(children: related.map((a) => ArtistCardW(artist: a)).toList())),
          ],
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text('About', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800, color: accent)),
          )),
          SliverToBoxAdapter(child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(_description(), style: const TextStyle(color: Colors.white60, height: 1.5)),
          )),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),
        ],
        ]),
        // Persistent top fade so the collapsed header/status bar stays readable while scrolling.
        Positioned(top: 0, left: 0, right: 0, child: IgnorePointer(child: Container(
          height: 130,
          decoration: BoxDecoration(gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [bg.withValues(alpha: 0.55), Colors.transparent])),
        ))),
      ]),
    );
  }
}

// A larger album card used on the artist page.
class _BigAlbumCard extends StatelessWidget {
  final Album album;
  const _BigAlbumCard({required this.album});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumScreen(albumId: album.id, title: album.title))),
        child: Container(width: 168, margin: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            cover(album.cover, 168, radius: 12, icon: Icons.album),
            const SizedBox(height: 6),
            Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            if (album.releaseDate != null && album.releaseDate!.length >= 4)
              Text(album.releaseDate!.substring(0, 4), style: const TextStyle(fontSize: 12, color: Colors.white54)),
          ]),
        ),
      );
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
      bottomNavigationBar: const MiniPlayer(),
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
