import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'deezer.dart';
import 'player.dart';
import 'store.dart';
import 'settings.dart';
import 'detail.dart';

const surface = Color(0xFF16161f);

Widget cover(String? url, double size, {double radius = 8, IconData icon = Icons.music_note}) {
  return ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: url != null
        ? CachedNetworkImage(imageUrl: url, width: size, height: size, fit: BoxFit.cover,
            placeholder: (_, __) => Container(width: size, height: size, color: surface),
            errorWidget: (_, __, ___) => Container(width: size, height: size, color: surface, child: Icon(icon, size: size * 0.4)))
        : Container(width: size, height: size, color: surface, child: Icon(icon, size: size * 0.4)),
  );
}

class SongTile extends StatelessWidget {
  final Song song;
  final List<Song> queue;
  final int index;
  final bool showArt;
  const SongTile({super.key, required this.song, required this.queue, required this.index, this.showArt = true});

  @override
  Widget build(BuildContext context) {
    final player = context.read<Player>();
    final lib = context.watch<Library>();
    final liked = lib.isLiked(song.deezerId);
    return ListTile(
      onTap: () => player.playList(queue, index),
      onLongPress: () => showSongMenu(context, song),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading: showArt ? cover(song.cover, 50) : null,
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (liked) const Icon(Icons.favorite, size: 18, color: Color(0xFFEC4899)),
        IconButton(icon: const Icon(Icons.more_vert), onPressed: () => showSongMenu(context, song)),
      ]),
    );
  }
}

void showSongMenu(BuildContext context, Song song) {
  final player = context.read<Player>();
  final lib = context.read<Library>();
  final settings = context.read<Settings>();
  final liked = lib.isLiked(song.deezerId);

  void act(String key) {
    Navigator.pop(context);
    switch (key) {
      case 'playNext': player.playNext(song); break;
      case 'queue': player.addToQueue(song); break;
      case 'like': lib.toggleLike(song); break;
      case 'playlist': _addToPlaylist(context, song); break;
      case 'radio': player.playList([song], 0); break;
      case 'album': if (song.albumId != null) Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumScreen(albumId: song.albumId!, title: song.album ?? ''))); break;
      case 'artist': if (song.artistId != null) Navigator.push(context, MaterialPageRoute(builder: (_) => ArtistScreen(artistId: song.artistId!, name: song.artist))); break;
      default: ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Noted'), duration: Duration(milliseconds: 900)));
    }
  }

  IconData ic(String k) => {
        'playNext': Icons.skip_next, 'queue': Icons.queue_music, 'like': liked ? Icons.favorite : Icons.favorite_border,
        'playlist': Icons.playlist_add, 'radio': Icons.radio, 'album': Icons.album, 'artist': Icons.person,
        'hide': Icons.not_interested, 'block': Icons.block,
      }[k] ?? Icons.circle;

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF14141f),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: cover(song.cover, 46),
          title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis),
          subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const Divider(height: 1),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: settings.menuBig.take(3).map((k) => Expanded(
              child: InkWell(
                onTap: () => act(k),
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(children: [
                    Icon(ic(k), color: k == 'like' && liked ? const Color(0xFFEC4899) : null),
                    const SizedBox(height: 6),
                    Text(allMenuActions[k] ?? k, style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
                  ]),
                ),
              ),
            )).toList(),
          ),
        ),
        const Divider(height: 1),
        ...settings.menuOptions
            .where((k) => !(k == 'album' && song.albumId == null) && !(k == 'artist' && song.artistId == null))
            .map((k) => ListTile(dense: true, leading: Icon(ic(k), size: 22), title: Text(allMenuActions[k] ?? k), onTap: () => act(k))),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

void _addToPlaylist(BuildContext context, Song song) {
  final lib = context.read<Library>();
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF14141f),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => SafeArea(
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        ListTile(
          leading: const Icon(Icons.add),
          title: const Text('New playlist'),
          onTap: () async {
            Navigator.pop(context);
            final name = await _promptName(context);
            if (name != null && name.isNotEmpty) { final p = lib.createPlaylist(name); lib.addToPlaylist(p.id, song); _toast(context, 'Added to $name'); }
          },
        ),
        const Divider(height: 1),
        ...lib.playlists.map((p) => ListTile(
              leading: const Icon(Icons.queue_music),
              title: Text(p.name),
              subtitle: Text('${p.songs.length} songs'),
              onTap: () { lib.addToPlaylist(p.id, song); Navigator.pop(context); _toast(context, 'Added to ${p.name}'); },
            )),
        const SizedBox(height: 8),
      ]),
    ),
  );
}

Future<String?> _promptName(BuildContext context, {String initial = ''}) {
  final ctrl = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1a1a2b),
      title: const Text('Playlist name'),
      content: TextField(controller: ctrl, autofocus: true, decoration: const InputDecoration(hintText: 'My playlist')),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(onPressed: () => Navigator.pop(context, ctrl.text.trim()), child: const Text('Save')),
      ],
    ),
  );
}

void _toast(BuildContext context, String msg) =>
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg), duration: const Duration(milliseconds: 1100)));

Future<String?> promptName(BuildContext context, {String initial = ''}) => _promptName(context, initial: initial);

class SectionHeader extends StatelessWidget {
  final String text;
  const SectionHeader(this.text, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 10),
        child: Text(text, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
      );
}

// Horizontal shelf of album/artist cards.
class CardShelf extends StatelessWidget {
  final List<Widget> children;
  const CardShelf({super.key, required this.children});
  @override
  Widget build(BuildContext context) => SizedBox(
        height: 200,
        child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 12), children: children),
      );
}

class AlbumCardW extends StatelessWidget {
  final Album album;
  const AlbumCardW({super.key, required this.album});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumScreen(albumId: album.id, title: album.title))),
        child: Container(
          width: 140,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            cover(album.cover, 140, radius: 10, icon: Icons.album),
            const SizedBox(height: 6),
            Text(album.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(album.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white54)),
          ]),
        ),
      );
}

class ArtistCardW extends StatelessWidget {
  final Artist artist;
  const ArtistCardW({super.key, required this.artist});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ArtistScreen(artistId: artist.id, name: artist.name))),
        child: Container(
          width: 140,
          margin: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(children: [
            cover(artist.picture, 140, radius: 70, icon: Icons.person),
            const SizedBox(height: 6),
            Text(artist.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          ]),
        ),
      );
}
