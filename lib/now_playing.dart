import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
  bool lyricsLoaded = false; // distinguishes 'still loading' from 'none found'
  // Per-song timing nudge. Some YouTube uploads have a longer/shorter intro than
  // the recording the lyrics were timed against, so the words drift.
  double lyricsOffset = 0;
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
    lyricsLoaded = false;
    _scrolledTo = -2; // new song → re-anchor the scroll
    if (_scroll.hasClients) _scroll.jumpTo(0);
    final prefs = await SharedPreferences.getInstance();
    lyricsOffset = prefs.getDouble('lyrOff_${s.deezerId}') ?? 0;
    final l = await LyricsApi.fetch(s);
    if (mounted && _lyricsForId == s.deezerId) setState(() { lyrics = l; lyricsLoaded = true; });
  }

  // Measured line geometry so we can smoothly centre even off-screen lines.
  List<double>? _lineTops;
  List<double>? _lineHeights;
  int _scrolledTo = -2; // last line we scrolled to (-2 = never)
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

  // Seconds until the next lyric line — used to detect long instrumental gaps.
  double _gapAhead(double pos) {
    final synced = lyrics?.synced;
    if (synced == null || synced.isEmpty) return 0;
    for (final l in synced) { if (l.time > pos + 0.1) return l.time - pos; }
    return 0;
  }

  Future<void> _nudge(double delta) async {
    final id = _lyricsForId;
    setState(() => lyricsOffset = (lyricsOffset + delta).clamp(-15.0, 15.0));
    if (id != null) {
      (await SharedPreferences.getInstance()).setDouble('lyrOff_$id', lyricsOffset);
    }
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
                if (!showLyrics)
                  const Text('NOW PLAYING', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1))
                else
                  // Nudge the lyric timing when an upload runs early/late.
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    IconButton(
                      iconSize: 18, visualDensity: VisualDensity.compact,
                      tooltip: 'Lyrics earlier',
                      icon: const Icon(Icons.remove),
                      onPressed: () => _nudge(-0.5)),
                    GestureDetector(
                      onTap: () => _nudge(-lyricsOffset), // tap to reset
                      child: Text(
                        lyricsOffset == 0 ? 'LYRICS' : '${lyricsOffset > 0 ? '+' : ''}${lyricsOffset.toStringAsFixed(1)}s',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 1,
                          color: lyricsOffset == 0 ? Colors.white : Theme.of(context).colorScheme.primary)),
                    ),
                    IconButton(
                      iconSize: 18, visualDensity: VisualDensity.compact,
                      tooltip: 'Lyrics later',
                      icon: const Icon(Icons.add),
                      onPressed: () => _nudge(0.5)),
                  ]),
                const Spacer(),
                IconButton(icon: const Icon(Icons.queue_music), onPressed: () => showQueue(context)),
              ]),

              // art or lyrics
              Expanded(child: showLyrics ? _lyricsView(p.position.inMilliseconds / 1000.0 - lyricsOffset) : Center(
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
    if (lyrics == null) {
      if (!lyricsLoaded) return const Center(child: CircularProgressIndicator(color: Colors.white));
      return const Center(child: Padding(padding: EdgeInsets.all(24),
        child: Text('No lyrics found for this song', textAlign: TextAlign.center,
          style: TextStyle(color: Colors.white54, fontSize: 16))));
    }
    final synced = lyrics!.synced;
    if (synced != null && synced.isNotEmpty) {
      final active = _activeLine(pos);
      return LayoutBuilder(builder: (context, box) {
        if (_measuredForId != _lyricsForId || _measuredWidth != box.maxWidth) {
          _measure(box.maxWidth, synced);
          _measuredForId = _lyricsForId; _measuredWidth = box.maxWidth;
        }
        // Lyrics begin at the TOP. As the song plays the highlighted line drifts
        // down until it reaches the middle, then it stays there and the text
        // scrolls up underneath it. (Negative targets clamp to 0, which is what
        // keeps the early lines pinned at the top instead of jumping to centre.)
        const padTop = 16.0;
        final padBottom = box.maxHeight * 0.55; // last lines can still reach the middle
        // Scroll ONCE per line change. (Re-issuing animateTo every frame — the
        // position stream ticks ~60x/sec — restarted the animation constantly,
        // so it never arrived and the active line drifted out of view.)
        if (active != _scrolledTo) {
          _scrolledTo = active;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_scroll.hasClients) return;
            // Before the first line (intro), sit at the very top.
            final double target = (active < 0 || _lineTops == null || active >= _lineTops!.length)
                ? 0
                : padTop + _lineTops![active] + _lineHeights![active] / 2 - box.maxHeight / 2;
            final clamped = target.clamp(0.0, _scroll.position.maxScrollExtent);
            if ((_scroll.offset - clamped).abs() > 2) {
              _scroll.animateTo(clamped, duration: const Duration(milliseconds: 600), curve: Curves.easeOutCubic);
            }
          });
        }
        final accent = Theme.of(context).colorScheme.primary;
        // Bright, readable accent tint for the currently-sung line.
        final activeColor = Color.lerp(accent, Colors.white, 0.15)!;
        final playing = context.watch<Player>().playing;
        final gap = _gapAhead(pos);
        final showNotes = playing && gap > 6; // long instrumental → animated notes

        final list = ListView.builder(
          controller: _scroll,
          padding: EdgeInsets.only(top: padTop, bottom: padBottom),
          itemCount: synced.length,
          itemBuilder: (context, i) {
            final on = i == active;
            final passed = i < active;
            return GestureDetector(
              onTap: () => context.read<Player>().seek(Duration(milliseconds: ((synced[i].time + lyricsOffset) * 1000).round())),
              behavior: HitTestBehavior.opaque,
              child: AnimatedScale(
                scale: on ? 1.0 : 0.94,
                alignment: Alignment.centerLeft,
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeOut,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    AnimatedDefaultTextStyle(
                      duration: const Duration(milliseconds: 300),
                      curve: Curves.easeOut,
                      style: TextStyle(
                        fontSize: 27, height: 1.2,
                        fontWeight: FontWeight.w800,
                        color: on ? activeColor : (passed ? Colors.white38 : Colors.white30)),
                      child: Text(synced[i].text.isEmpty ? '♪' : synced[i].text, textAlign: TextAlign.left),
                    ),
                    // Long instrumental after this line → notes get their own space.
                    if (showNotes && on)
                      Padding(padding: const EdgeInsets.only(top: 8), child: BouncingNotes(color: activeColor)),
                  ]),
                ),
              ),
            );
          },
        );
        // During the intro the notes sit ABOVE the first line, in their own row,
        // so they never overlap the text. (Mid-song gaps render them inside the
        // active line's item — see the itemBuilder — which reserves real space.)
        if (showNotes && active < 0) {
          return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.fromLTRB(2, 10, 0, 4), child: BouncingNotes(color: activeColor)),
            Expanded(child: list),
          ]);
        }
        return list;
      });
    }
    if (lyrics!.plain != null && lyrics!.plain!.trim().isNotEmpty) {
      return SingleChildScrollView(padding: const EdgeInsets.symmetric(vertical: 20),
        child: Text(lyrics!.plain!, style: const TextStyle(fontSize: 22, height: 1.5, fontWeight: FontWeight.w700, color: Colors.white)));
    }
    return const Center(child: Text('No lyrics found', style: TextStyle(color: Colors.white54)));
  }
}

/// A compact equaliser that pulses while an instrumental section plays — tidier
/// than scattered notes and matches the Sound Circle waveform mark.
class BouncingNotes extends StatefulWidget {
  final Color color;
  const BouncingNotes({super.key, required this.color});
  @override
  State<BouncingNotes> createState() => _BouncingNotesState();
}

class _BouncingNotesState extends State<BouncingNotes> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  static const _bars = 4;

  @override
  void dispose() { _c.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => SizedBox(
          height: 22,
          child: Row(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(_bars, (i) {
              final phase = _c.value * 2 * math.pi + i * 0.9;
              final h = 7 + 15 * (0.5 + 0.5 * math.sin(phase));
              return Container(
                width: 4, height: h,
                margin: const EdgeInsets.only(right: 4),
                decoration: BoxDecoration(
                  color: widget.color.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(2)),
              );
            })),
        ),
      );
}
