import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import 'deezer.dart';
import 'player.dart';
import 'store.dart';
import 'settings.dart';
import 'widgets.dart';
import 'detail.dart';
import 'downloads.dart';

String _fmt(Duration d) => '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';

class NowPlayingScreen extends StatefulWidget {
  const NowPlayingScreen({super.key});
  @override
  State<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends State<NowPlayingScreen> {
  bool showLyrics = false;
  Lyrics? lyrics;
  int? _lyricsForId;
  final _scroll = ScrollController();

  Color _bg = const Color(0xFF3a3a4a);
  String? _colorFor;

  Future<void> _updateColor(Song s) async {
    if (_colorFor == s.cover) return;
    _colorFor = s.cover;
    if (s.cover == null) return;
    try {
      final pg = await PaletteGenerator.fromImageProvider(CachedNetworkImageProvider(s.cover!), size: const Size(80, 80), maximumColorCount: 12);
      final c = pg.vibrantColor?.color ?? pg.dominantColor?.color ?? pg.mutedColor?.color;
      if (c != null && mounted) setState(() => _bg = c);
    } catch (_) {}
  }

  void _toggleDownload(Song s, Library lib) {
    final player = context.read<Player>();
    if (lib.isDownloaded(s.deezerId)) {
      Downloads.delete(lib, s);
      showCoverPopout(context, cover: s.cover, message: 'Removed', icon: Icons.delete_outline);
    } else {
      showCoverPopout(context, cover: s.cover, message: 'Downloading…', icon: Icons.download);
      Downloads.download(player, lib, s).then((ok) {
        if (mounted) showCoverPopout(context, cover: s.cover, message: ok ? 'Downloaded' : 'Failed', icon: ok ? Icons.download_done : Icons.error_outline);
      });
    }
  }

  Future<void> _loadLyrics(Song s) async {
    if (_lyricsForId == s.deezerId) return;
    _lyricsForId = s.deezerId;
    lyrics = null;
    final l = await LyricsApi.fetch(s);
    if (mounted && _lyricsForId == s.deezerId) setState(() => lyrics = l);
  }

  // Measured line geometry so we can smoothly centre even off-screen lines.
  List<double>? _lineTops;
  List<double>? _lineHeights;
  double? _measuredWidth;
  int? _measuredForId;

  void _measure(double width, List<LyricLine> lines) {
    final tops = <double>[]; final heights = <double>[];
    double y = 0;
    for (final l in lines) {
      final tp = TextPainter(
        text: TextSpan(text: l.text.isEmpty ? '♪' : l.text,
          style: const TextStyle(fontSize: 27, height: 1.2, fontWeight: FontWeight.w800)),
        textDirection: TextDirection.ltr)..layout(maxWidth: width);
      final h = tp.height + 20; // vertical padding 10*2
      tops.add(y); heights.add(h); y += h;
    }
    _lineTops = tops; _lineHeights = heights;
  }

  int _activeLine(double pos) {
    final synced = lyrics?.synced;
    if (synced == null) return -1;
    int idx = -1;
    // Highlight the line whose start time has been reached (no artificial lead —
    // the previous +0.4s made lyrics run ahead of the vocals on many songs).
    for (int i = 0; i < synced.length; i++) {
      if (synced[i].time <= pos) idx = i; else break;
    }
    return idx;
  }

  // Blend the art colour toward black so text stays readable.
  Color get _bgDark => Color.lerp(_bg, Colors.black, 0.45)!;
  Color get _bgDeep => Color.lerp(_bg, Colors.black, 0.78)!;

  @override
  Widget build(BuildContext context) {
    final p = context.watch<Player>();
    final lib = context.watch<Library>();
    final s = p.current;
    if (s == null) return const SizedBox.shrink();
    _updateColor(s);
    final liked = lib.isLiked(s.deezerId);
    if (showLyrics) _loadLyrics(s);

    final durMs = p.duration.inMilliseconds == 0 ? 1 : p.duration.inMilliseconds;
    final posMs = p.position.inMilliseconds.clamp(0, durMs).toDouble();
    final art = MediaQuery.of(context).size.width - 72;

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: showLyrics ? [_bgDark, _bgDeep] : [_bgDark, _bgDeep, Colors.black]),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 22),
            child: Column(children: [
              // top bar
              Row(children: [
                IconButton(icon: const Icon(Icons.keyboard_arrow_down, size: 30), onPressed: () => Navigator.pop(context)),
                const Spacer(),
                Text(showLyrics ? 'LYRICS' : 'NOW PLAYING', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.queue_music), onPressed: () => showQueue(context)),
              ]),

              // art or lyrics
              Expanded(child: showLyrics ? _lyricsView(p.position.inMilliseconds / 1000.0) : Center(
                child: Hero(tag: 'npCover',
                  child: ClipRRect(borderRadius: BorderRadius.circular(12),
                    child: s.cover != null
                      ? CachedNetworkImage(imageUrl: s.cover!, width: art, height: art, fit: BoxFit.cover)
                      : Container(width: art, height: art, color: Colors.white10, child: const Icon(Icons.music_note, size: 90))),
                ),
              )),

              const SizedBox(height: 8),
              // title + like
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  context.watch<Settings>().scrollingTitles
                      ? MarqueeText(s.title, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800))
                      : Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 23, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  GestureDetector(
                    onTap: s.artistId == null ? null : () {
                      Navigator.pop(context);
                      Navigator.push(context, MaterialPageRoute(builder: (_) => ArtistScreen(artistId: s.artistId!, name: s.artist)));
                    },
                    child: Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 15, color: Colors.white70, decoration: TextDecoration.none)),
                  ),
                ])),
                IconButton(iconSize: 30,
                  icon: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? const Color(0xFF1DB954) : Colors.white),
                  onPressed: () => lib.toggleLike(s)),
              ]),

              const SizedBox(height: 6),
              // progress
              SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4, activeTrackColor: Colors.white, inactiveTrackColor: Colors.white24,
                  thumbColor: Colors.white, thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 14)),
                child: Slider(value: posMs, max: durMs.toDouble(), onChanged: (v) => p.seek(Duration(milliseconds: v.round()))),
              ),
              Padding(padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(_fmt(p.position), style: const TextStyle(fontSize: 11, color: Colors.white60)),
                  Text(_fmt(p.duration), style: const TextStyle(fontSize: 11, color: Colors.white60)),
                ])),

              const SizedBox(height: 6),
              // controls
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                IconButton(iconSize: 24, visualDensity: VisualDensity.compact, color: p.shuffle ? const Color(0xFF1DB954) : Colors.white70,
                  icon: const Icon(Icons.shuffle), onPressed: p.toggleShuffle),
                IconButton(iconSize: 38, visualDensity: VisualDensity.compact, icon: const Icon(Icons.skip_previous), onPressed: p.prev),
                Container(width: 66, height: 66, decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
                  child: p.loading
                    ? const Padding(padding: EdgeInsets.all(20), child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : IconButton(iconSize: 38, color: Colors.black,
                        icon: Icon(p.playing ? Icons.pause : Icons.play_arrow), onPressed: p.toggle)),
                IconButton(iconSize: 38, visualDensity: VisualDensity.compact, icon: const Icon(Icons.skip_next), onPressed: p.next),
                IconButton(iconSize: 24, visualDensity: VisualDensity.compact, color: p.repeatOne ? const Color(0xFF1DB954) : Colors.white70,
                  icon: Icon(p.repeatOne ? Icons.repeat_one : Icons.repeat), onPressed: p.toggleRepeat),
              ]),

              const SizedBox(height: 16),
              // bottom bar: download (left) · lyrics (center) · more (right)
              Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                IconButton(
                  tooltip: lib.isDownloaded(s.deezerId) ? 'Downloaded' : 'Download',
                  icon: Icon(
                    lib.isDownloaded(s.deezerId) ? Icons.download_done : Icons.download_outlined,
                    color: lib.isDownloaded(s.deezerId) ? const Color(0xFF1DB954) : Colors.white70),
                  onPressed: () => _toggleDownload(s, lib),
                ),
                TextButton.icon(
                  onPressed: () => setState(() => showLyrics = !showLyrics),
                  icon: Icon(showLyrics ? Icons.image_outlined : Icons.lyrics_outlined, size: 18,
                    color: showLyrics ? Colors.white : Colors.white70),
                  label: Text(showLyrics ? 'Cover' : 'Lyrics',
                    style: TextStyle(color: showLyrics ? Colors.white : Colors.white70, fontWeight: FontWeight.w600)),
                ),
                IconButton(icon: const Icon(Icons.more_horiz, color: Colors.white70), onPressed: () => showSongMenu(context, s)),
              ]),
              if (p.error != null) Padding(padding: const EdgeInsets.only(bottom: 4), child: Text(p.error!, style: const TextStyle(color: Colors.redAccent))),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _lyricsView(double pos) {
    if (lyrics == null) return const Center(child: CircularProgressIndicator(color: Colors.white));
    final synced = lyrics!.synced;
    if (synced != null && synced.isNotEmpty) {
      final active = _activeLine(pos);
      return LayoutBuilder(builder: (context, box) {
        if (_measuredForId != _lyricsForId || _measuredWidth != box.maxWidth) {
          _measure(box.maxWidth, synced);
          _measuredForId = _lyricsForId; _measuredWidth = box.maxWidth;
        }
        final pad = box.maxHeight * 0.42; // lets first & last lines reach the middle
        // Centre the active line: scroll so its middle sits at the viewport middle.
        // The text above scrolls up; the active line stays put in the centre.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!_scroll.hasClients || active < 0 || _lineTops == null || active >= _lineTops!.length) return;
          final target = pad + _lineTops![active] + _lineHeights![active] / 2 - box.maxHeight / 2;
          final clamped = target.clamp(0.0, _scroll.position.maxScrollExtent);
          if ((_scroll.offset - clamped).abs() > 2) {
            _scroll.animateTo(clamped, duration: const Duration(milliseconds: 550), curve: Curves.easeOutCubic);
          }
        });
        return ListView.builder(
          controller: _scroll,
          padding: EdgeInsets.symmetric(vertical: pad),
          itemCount: synced.length,
          itemBuilder: (context, i) {
            final on = i == active;
            final passed = i < active;
            return GestureDetector(
              onTap: () => context.read<Player>().seek(Duration(milliseconds: (synced[i].time * 1000).round())),
              behavior: HitTestBehavior.opaque,
              child: AnimatedScale(
                scale: on ? 1.0 : 0.94,
                alignment: Alignment.centerLeft,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: AnimatedDefaultTextStyle(
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.easeOut,
                    style: TextStyle(
                      fontSize: 27, height: 1.2,
                      fontWeight: FontWeight.w800,
                      color: on ? Colors.white : (passed ? Colors.white54 : Colors.white38)),
                    child: Text(synced[i].text.isEmpty ? '♪' : synced[i].text, textAlign: TextAlign.left),
                  ),
                ),
              ),
            );
          },
        );
      });
    }
    if (lyrics!.plain != null && lyrics!.plain!.trim().isNotEmpty) {
      return SingleChildScrollView(padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(lyrics!.plain!, style: const TextStyle(fontSize: 22, height: 1.5, fontWeight: FontWeight.w700, color: Colors.white)));
    }
    return const Center(child: Text('No lyrics found', style: TextStyle(color: Colors.white54)));
  }
}
