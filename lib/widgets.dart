import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'deezer.dart';
import 'player.dart';
import 'store.dart';
import 'settings.dart';
import 'detail.dart';
import 'downloads.dart';
import 'screens.dart';

const surface = Color(0xFF16161f);

/// Text that scrolls back and forth when it's wider than the available space
/// (e.g. long titles like "Quevedo: Bzrp Music Sessions"). Otherwise static.
class MarqueeText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  const MarqueeText(this.text, {super.key, this.style});
  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText> with SingleTickerProviderStateMixin {
  final _scroll = ScrollController();
  bool _running = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStart());
  }

  Future<void> _maybeStart() async {
    if (!mounted || _running) return;
    if (!_scroll.hasClients || _scroll.position.maxScrollExtent <= 0) return;
    _running = true;
    while (mounted) {
      await Future.delayed(const Duration(milliseconds: 1400));
      if (!mounted || !_scroll.hasClients) break;
      final max = _scroll.position.maxScrollExtent;
      await _scroll.animateTo(max, duration: Duration(milliseconds: (max * 18).round().clamp(1800, 9000)), curve: Curves.linear);
      if (!mounted || !_scroll.hasClients) break;
      await Future.delayed(const Duration(milliseconds: 1200));
      if (!mounted || !_scroll.hasClients) break;
      await _scroll.animateTo(0, duration: const Duration(milliseconds: 600), curve: Curves.easeOut);
    }
  }

  @override
  void didUpdateWidget(covariant MarqueeText old) {
    super.didUpdateWidget(old);
    if (old.text != widget.text) {
      _running = false;
      if (_scroll.hasClients) _scroll.jumpTo(0);
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeStart());
    }
  }

  @override
  void dispose() { _scroll.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        controller: _scroll,
        scrollDirection: Axis.horizontal,
        physics: const NeverScrollableScrollPhysics(),
        child: Text(widget.text, maxLines: 1, style: widget.style),
      );
}

/// A polished slide-up + fade route (used to open the full-screen player).
Route<T> slideUpRoute<T>(Widget page) => PageRouteBuilder<T>(
      transitionDuration: const Duration(milliseconds: 380),
      reverseTransitionDuration: const Duration(milliseconds: 300),
      pageBuilder: (_, __, ___) => page,
      transitionsBuilder: (_, anim, __, child) {
        final curved = CurvedAnimation(parent: anim, curve: Curves.easeOutCubic, reverseCurve: Curves.easeInCubic);
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, 0.12), end: Offset.zero).animate(curved),
            child: child,
          ),
        );
      },
    );

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
    final playing = context.watch<Player>().current?.deezerId == song.deezerId;
    final liked = lib.isLiked(song.deezerId);
    final downloaded = lib.isDownloaded(song.deezerId);
    return ListTile(
      onTap: () => player.playList(queue, index),
      onLongPress: () => showSongMenu(context, song),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
      leading: showArt ? cover(song.cover, 50) : null,
      title: Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis,
        style: TextStyle(color: playing ? Theme.of(context).colorScheme.primary : null, fontWeight: playing ? FontWeight.w700 : null)),
      subtitle: Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (downloaded) const Icon(Icons.download_done, size: 16, color: Colors.white38),
        if (liked) const Padding(padding: EdgeInsets.only(left: 4), child: Icon(Icons.favorite, size: 18, color: Color(0xFFEC4899))),
        IconButton(icon: const Icon(Icons.more_vert), onPressed: () => showSongMenu(context, song)),
      ]),
    );
  }
}

void showSongMenu(BuildContext context, Song song) {
  final player = context.read<Player>();
  final lib = context.read<Library>();
  final settings = context.read<Settings>();
  final messenger = ScaffoldMessenger.of(context);
  final liked = lib.isLiked(song.deezerId);
  final downloaded = lib.isDownloaded(song.deezerId);

  void act(String key) {
    Navigator.pop(context);
    switch (key) {
      case 'playNext': player.playNext(song); break;
      case 'queue': player.addToQueue(song); break;
      case 'like': lib.toggleLike(song); break;
      case 'playlist': _addToPlaylist(context, song); break;
      case 'radio': player.playList([song], 0); break;
      case 'download':
        if (downloaded) { Downloads.delete(lib, song); showCoverPopout(context, cover: song.cover, message: 'Removed', icon: Icons.delete_outline); }
        else {
          showCoverPopout(context, cover: song.cover, message: 'Downloading…', icon: Icons.download);
          Downloads.download(player, lib, song).then((ok) {
            if (context.mounted) showCoverPopout(context, cover: song.cover, message: ok ? 'Downloaded' : 'Failed', icon: ok ? Icons.download_done : Icons.error_outline);
          });
        }
        break;
      case 'album': if (song.albumId != null) Navigator.push(context, MaterialPageRoute(builder: (_) => AlbumScreen(albumId: song.albumId!, title: song.album ?? ''))); break;
      case 'artist': if (song.artistId != null) Navigator.push(context, MaterialPageRoute(builder: (_) => ArtistScreen(artistId: song.artistId!, name: song.artist))); break;
      default: messenger.showSnackBar(const SnackBar(content: Text('Noted'), duration: Duration(milliseconds: 900)));
    }
  }

  IconData ic(String k) => {
        'playNext': Icons.skip_next, 'queue': Icons.queue_music, 'like': liked ? Icons.favorite : Icons.favorite_border,
        'playlist': Icons.playlist_add, 'radio': Icons.radio, 'download': downloaded ? Icons.download_done : Icons.download,
        'album': Icons.album, 'artist': Icons.person, 'hide': Icons.not_interested, 'block': Icons.block,
      }[k] ?? Icons.circle;

  String label(String k) => k == 'download' ? (downloaded ? 'Downloaded' : 'Download') : (allMenuActions[k] ?? k);

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF14141f),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
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
                    Text(label(k), style: const TextStyle(fontSize: 12), textAlign: TextAlign.center),
                  ]),
                ),
              ),
            )).toList(),
          ),
        ),
        const Divider(height: 1),
        ...settings.menuOptions
            .where((k) => !(k == 'album' && song.albumId == null) && !(k == 'artist' && song.artistId == null))
            .map((k) => ListTile(dense: true, leading: Icon(ic(k), size: 22), title: Text(label(k)), onTap: () => act(k))),
        const SizedBox(height: 8),
      ]),
    )),
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

/// A small dynamic tab that pops out from the right edge showing a cover +
/// message (used for download feedback instead of a full-width snackbar).
void showCoverPopout(BuildContext context, {String? cover, required String message, IconData icon = Icons.check_circle, Color? accent}) {
  final overlay = Overlay.of(context);
  final entry = OverlayEntry(builder: (ctx) => _CoverPopout(cover: cover, message: message, icon: icon, accent: accent ?? Theme.of(context).colorScheme.primary));
  overlay.insert(entry);
  Future.delayed(const Duration(milliseconds: 2200), () { try { entry.remove(); } catch (_) {} });
}

class _CoverPopout extends StatefulWidget {
  final String? cover; final String message; final IconData icon; final Color accent;
  const _CoverPopout({this.cover, required this.message, required this.icon, required this.accent});
  @override
  State<_CoverPopout> createState() => _CoverPopoutState();
}

class _CoverPopoutState extends State<_CoverPopout> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 340));
  @override
  void initState() {
    super.initState();
    _c.forward();
    Future.delayed(const Duration(milliseconds: 1750), () { if (mounted) _c.reverse(); });
  }
  @override
  void dispose() { _c.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final curve = CurvedAnimation(parent: _c, curve: Curves.easeOutBack, reverseCurve: Curves.easeInCubic);
    final mq = MediaQuery.of(context);
    return Positioned(
      right: 0, top: mq.padding.top + 70,
      child: SlideTransition(
        position: Tween(begin: const Offset(1.1, 0), end: Offset.zero).animate(curve),
        child: FadeTransition(opacity: _c,
          child: Material(color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.fromLTRB(8, 8, 16, 8),
              decoration: BoxDecoration(
                color: const Color(0xFF1c1c28),
                borderRadius: const BorderRadius.horizontal(left: Radius.circular(16)),
                border: Border.all(color: widget.accent.withValues(alpha: 0.5)),
                boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 16, offset: Offset(-2, 4))]),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                cover(widget.cover, 40, radius: 8),
                const SizedBox(width: 10),
                Icon(widget.icon, color: widget.accent, size: 20),
                const SizedBox(width: 6),
                Text(widget.message, style: const TextStyle(fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

String fanCount(int? n) {
  if (n == null) return '';
  if (n >= 1000000) return '${(n / 1000000).toStringAsFixed(n >= 10000000 ? 0 : 1)}M';
  if (n >= 1000) return '${(n / 1000).toStringAsFixed(n >= 10000 ? 0 : 1)}K';
  return '$n';
}

/// A song card for horizontal shelves (Schnellauswahl / recommendations).
class SongCardW extends StatelessWidget {
  final Song song; final List<Song> queue; final int index; final double width;
  const SongCardW({super.key, required this.song, required this.queue, required this.index, this.width = 150});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => context.read<Player>().playList(queue, index),
        onLongPress: () => showSongMenu(context, song),
        child: Container(width: width, margin: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            cover(song.cover, width, radius: 10),
            const SizedBox(height: 6),
            Text(song.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text(song.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white54)),
          ]),
        ),
      );
}

/// "Quick picks": a 3-row grid of big square cover cards that scrolls
/// horizontally (title + artist overlaid on the artwork).
class QuickPicks extends StatelessWidget {
  final List<Song> songs;
  const QuickPicks({super.key, required this.songs});
  @override
  Widget build(BuildContext context) {
    const pad = 12.0, gap = 10.0;
    final w = MediaQuery.of(context).size.width;
    final cell = (w - pad * 2 - gap * 2) / 3; // three columns fill the width
    final gridH = cell * 3 + gap * 2;
    return SizedBox(
      height: gridH,
      child: GridView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: pad),
        physics: const BouncingScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3, mainAxisSpacing: gap, crossAxisSpacing: gap, childAspectRatio: 1),
        itemCount: songs.length,
        itemBuilder: (context, i) {
          final s = songs[i];
          return GestureDetector(
            onTap: () => context.read<Player>().playList(songs, i),
            onLongPress: () => showSongMenu(context, s),
            child: ClipRRect(borderRadius: BorderRadius.circular(12),
              child: Stack(fit: StackFit.expand, children: [
                if (s.cover != null)
                  CachedNetworkImage(imageUrl: s.cover!, fit: BoxFit.cover,
                    placeholder: (_, __) => Container(color: surface),
                    errorWidget: (_, __, ___) => Container(color: surface, child: const Icon(Icons.music_note)))
                else Container(color: surface, child: const Icon(Icons.music_note)),
                const DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(
                  begin: Alignment.center, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black87]))),
                Positioned(left: 8, right: 8, bottom: 8, child: Column(
                  mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 13, color: Colors.white)),
                    Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 11, color: Colors.white70)),
                  ])),
              ])),
          );
        },
      ),
    );
  }
}

/// A gradient "mix"/radio card. onTap resolves songs and starts playback.
class MixCard extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? cover;
  final List<Color> gradient;
  final Future<List<Song>> Function() resolve;
  const MixCard({super.key, required this.title, this.subtitle, this.cover, required this.gradient, required this.resolve});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () async {
          final messenger = ScaffoldMessenger.of(context);
          final player = context.read<Player>();
          messenger.showSnackBar(SnackBar(content: Text('Starting $title…'), duration: const Duration(milliseconds: 1000)));
          final songs = await resolve();
          if (songs.isEmpty) { messenger.showSnackBar(const SnackBar(content: Text('Nothing to play'), duration: Duration(milliseconds: 1000))); return; }
          player.playList(songs, 0);
        },
        child: Container(
          width: 150, margin: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Container(
              width: 150, height: 150,
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(10),
                gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight)),
              child: Stack(children: [
                if (cover != null) Positioned.fill(child: ClipRRect(borderRadius: BorderRadius.circular(10),
                  child: Opacity(opacity: 0.5, child: CachedNetworkImage(imageUrl: cover!, fit: BoxFit.cover)))),
                const Positioned(right: 8, top: 8, child: Icon(Icons.graphic_eq, color: Colors.white70, size: 18)),
                Positioned(left: 10, bottom: 10, right: 10,
                  child: Text(title, maxLines: 2, overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: Colors.white,
                      shadows: [Shadow(blurRadius: 6, color: Colors.black54)]))),
              ]),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 6),
              Text(subtitle!, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white54)),
            ],
          ]),
        ),
      );
}

/// "NEXT UP" strip at the top of Home — horizontal, drag to reorder, tap to
/// jump, X to remove. Shows only the manual queue.
class NextUpBar extends StatefulWidget {
  final double shrink; // 0 = full, 1 = collapsed (driven by page scroll)
  const NextUpBar({super.key, this.shrink = 0});
  @override
  State<NextUpBar> createState() => _NextUpBarState();
}

class _NextUpBarState extends State<NextUpBar> {
  bool hidden = false;
  @override
  Widget build(BuildContext context) {
    final p = context.watch<Player>();
    final q = p.manualQueue;
    if (q.isEmpty || hidden) return const SizedBox.shrink();
    return _bar(context, p, q, widget.shrink.clamp(0.0, 1.0));
  }

  // As the page scrolls the bar shrinks — covers get smaller and the labels &
  // header fade out — but it never disappears; a compact thumbnail strip stays.
  Widget _bar(BuildContext context, Player p, List<Song> q, double t) {
    double lerp(double a, double b) => a + (b - a) * t;
    final cs = lerp(104, 46);            // cover size
    final listH = lerp(150, 58);         // strip height
    final labelF = (1 - t * 2.2).clamp(0.0, 1.0);  // title/artist fade
    final headerF = (1 - t * 1.8).clamp(0.0, 1.0); // header fade
    return Container(
      decoration: const BoxDecoration(border: Border(bottom: BorderSide(color: Colors.white10))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        ClipRect(child: Align(heightFactor: headerF, alignment: Alignment.topCenter,
          child: Opacity(opacity: headerF, child: Padding(padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
            child: Row(children: [
              const Icon(Icons.queue_music, size: 18, color: Colors.white54),
              const SizedBox(width: 8),
              Text('NEXT UP · ${q.length}', style: const TextStyle(fontWeight: FontWeight.w800, letterSpacing: 0.5, color: Colors.white70)),
              const Spacer(),
              IconButton(iconSize: 20, visualDensity: VisualDensity.compact,
                icon: const Icon(Icons.close), onPressed: () => setState(() => hidden = true)),
            ]))))),
        Padding(padding: const EdgeInsets.only(bottom: 8), child: SizedBox(
          height: listH,
          child: ReorderableListView.builder(
            scrollDirection: Axis.horizontal,
            buildDefaultDragHandles: true,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            proxyDecorator: (child, i, anim) => Material(color: Colors.transparent, child: child),
            itemCount: q.length,
            onReorder: (o, n) => context.read<Player>().reorderQueue(o, n),
            itemBuilder: (context, i) {
              final s = q[i];
              return Padding(
                key: ValueKey('nx${s.deezerId}_$i'),
                padding: const EdgeInsets.symmetric(horizontal: 5),
                child: SizedBox(width: cs,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Stack(children: [
                      GestureDetector(onTap: () => context.read<Player>().playUpNext(i), child: cover(s.cover, cs, radius: 10)),
                      Positioned(right: 1, top: 1, child: GestureDetector(
                        onTap: () => context.read<Player>().removeUpNext(i),
                        child: Container(decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          padding: const EdgeInsets.all(2), child: const Icon(Icons.close, size: 13)))),
                    ]),
                    if (labelF > 0.02) ClipRect(child: Align(heightFactor: labelF, alignment: Alignment.topCenter,
                      child: Opacity(opacity: labelF, child: Padding(padding: const EdgeInsets.only(top: 4),
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                          Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                          Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                        ]))))),
                  ]),
                ),
              );
            },
          ),
        )),
      ]),
    );
  }
}

class PlaylistCardW extends StatelessWidget {
  final Playlist playlist;
  const PlaylistCardW({super.key, required this.playlist});
  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlaylistScreen(id: playlist.id))),
        child: Container(width: 140, margin: const EdgeInsets.symmetric(horizontal: 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            cover(playlist.songs.isNotEmpty ? playlist.songs.first.cover : null, 140, radius: 10, icon: Icons.queue_music),
            const SizedBox(height: 6),
            Text(playlist.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
            Text('${playlist.songs.length} songs', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white54)),
          ]),
        ),
      );
}

// ---- Visible queue (manual songs only) ----
void showQueue(BuildContext context) {
  final settings = context.read<Settings>();
  final expands = settings.queueExpands;
  Widget content(ScrollController? scroll) => Consumer2<Player, Settings>(builder: (context, p, s, _) {
        final up = p.manualQueue;
        final titles = s.queueShowTitles;
        return ListView(controller: scroll, padding: EdgeInsets.zero, children: [
          Padding(padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Queue', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800)),
              if (up.isNotEmpty) TextButton.icon(
                onPressed: () { for (var i = up.length - 1; i >= 0; i--) p.removeUpNext(i); },
                icon: const Icon(Icons.clear_all, size: 18), label: const Text('Clear')),
            ])),
          if (p.current != null) ...[
            const _MiniHeader('Now playing'),
            ListTile(
              leading: cover(p.current!.cover, 46),
              title: Text(p.current!.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: titles ? Text(p.current!.artist, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
              trailing: Icon(Icons.equalizer, color: Theme.of(context).colorScheme.primary),
            ),
          ],
          if (up.isNotEmpty) ...[
            const _MiniHeader('Next in queue · manually added'),
            ...up.asMap().entries.map((e) => ListTile(
              key: ValueKey('q${e.value.deezerId}_${e.key}'),
              dense: !titles,
              leading: cover(e.value.cover, titles ? 46 : 38),
              title: Text(e.value.title, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: titles ? Text(e.value.artist, maxLines: 1, overflow: TextOverflow.ellipsis) : null,
              onTap: () => p.playUpNext(e.key),
              trailing: IconButton(icon: const Icon(Icons.close, size: 18), onPressed: () => p.removeUpNext(e.key)),
            )),
          ],
          if (up.isEmpty)
            const Padding(padding: EdgeInsets.all(30), child: Center(child: Text('Nothing queued.\nAdd songs with “Play next” or “Add to queue”.', textAlign: TextAlign.center, style: TextStyle(color: Colors.white38)))),
          const SizedBox(height: 20),
        ]);
      });

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF14141f),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (_) => expands
        ? DraggableScrollableSheet(
            expand: false, initialChildSize: 0.6, minChildSize: 0.35, maxChildSize: 0.92, snap: true,
            builder: (context, scroll) => content(scroll),
          )
        : SizedBox(
            height: MediaQuery.of(context).size.height * 0.62,
            child: content(null),
          ),
  );
}

class _MiniHeader extends StatelessWidget {
  final String text;
  const _MiniHeader(this.text);
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
    child: Text(text.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Colors.white38)));
}
