import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'deezer.dart';
import 'player.dart';
import 'store.dart';
import 'widgets.dart';

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

  Future<void> _loadLyrics(Song s) async {
    if (_lyricsForId == s.deezerId) return;
    _lyricsForId = s.deezerId;
    lyrics = null;
    final l = await LyricsApi.fetch(s);
    if (mounted && _lyricsForId == s.deezerId) setState(() => lyrics = l);
  }

  int _activeLine(double pos) {
    final synced = lyrics?.synced;
    if (synced == null) return -1;
    int idx = -1;
    for (int i = 0; i < synced.length; i++) {
      if (synced[i].time <= pos + 0.4) idx = i; else break;
    }
    return idx;
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<Player>();
    final lib = context.watch<Library>();
    final s = p.current;
    if (s == null) return const SizedBox.shrink();
    final liked = lib.isLiked(s.deezerId);
    if (showLyrics) _loadLyrics(s);

    final durMs = p.duration.inMilliseconds == 0 ? 1 : p.duration.inMilliseconds;
    final posMs = p.position.inMilliseconds.clamp(0, durMs).toDouble();

    return Scaffold(
      body: Stack(children: [
        if (s.cover != null)
          Positioned.fill(child: CachedNetworkImage(imageUrl: s.cover!, fit: BoxFit.cover,
              color: Colors.black.withValues(alpha: 0.6), colorBlendMode: BlendMode.darken)),
        Positioned.fill(child: Container(color: Colors.black.withValues(alpha: 0.5))),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(children: [
              Row(children: [
                IconButton(icon: const Icon(Icons.keyboard_arrow_down, size: 32), onPressed: () => Navigator.pop(context)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.queue_music), onPressed: () => showQueue(context)),
                IconButton(
                  icon: Icon(showLyrics ? Icons.image : Icons.lyrics_outlined),
                  onPressed: () => setState(() => showLyrics = !showLyrics)),
              ]),
              Expanded(
                child: showLyrics
                    ? _lyricsView(p.position.inMilliseconds / 1000.0)
                    : Center(child: cover(s.cover, MediaQuery.of(context).size.width - 80, radius: 16)),
              ),
              const SizedBox(height: 12),
              Row(children: [
                Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  Text(s.artist, style: const TextStyle(fontSize: 15, color: Colors.white70)),
                ])),
                IconButton(
                  iconSize: 30,
                  icon: Icon(liked ? Icons.favorite : Icons.favorite_border, color: liked ? const Color(0xFFEC4899) : Colors.white),
                  onPressed: () => lib.toggleLike(s)),
                IconButton(iconSize: 26, icon: const Icon(Icons.playlist_add), onPressed: () => showSongMenu(context, s)),
              ]),
              SliderTheme(
                data: SliderTheme.of(context).copyWith(trackHeight: 3,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    overlayShape: const RoundSliderOverlayShape(overlayRadius: 14)),
                child: Slider(value: posMs, max: durMs.toDouble(), onChanged: (v) => p.seek(Duration(milliseconds: v.round()))),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                  Text(_fmt(p.position), style: const TextStyle(fontSize: 12, color: Colors.white54)),
                  Text(_fmt(p.duration), style: const TextStyle(fontSize: 12, color: Colors.white54)),
                ]),
              ),
              const SizedBox(height: 8),
              Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                IconButton(iconSize: 42, icon: const Icon(Icons.skip_previous), onPressed: p.prev),
                const SizedBox(width: 16),
                IconButton(iconSize: 64,
                  icon: p.loading
                      ? const SizedBox(width: 42, height: 42, child: CircularProgressIndicator(strokeWidth: 2))
                      : Icon(p.playing ? Icons.pause_circle_filled : Icons.play_circle_fill),
                  onPressed: p.toggle),
                const SizedBox(width: 16),
                IconButton(iconSize: 42, icon: const Icon(Icons.skip_next), onPressed: p.next),
              ]),
              if (p.error != null) Padding(padding: const EdgeInsets.only(top: 6), child: Text(p.error!, style: const TextStyle(color: Colors.redAccent))),
              const SizedBox(height: 10),
            ]),
          ),
        ),
      ]),
    );
  }

  Widget _lyricsView(double pos) {
    if (lyrics == null) return const Center(child: CircularProgressIndicator());
    final synced = lyrics!.synced;
    if (synced != null && synced.isNotEmpty) {
      final active = _activeLine(pos);
      // keep the active line roughly centered
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients && active >= 0) {
          final target = (active * 44.0) - 160;
          _scroll.animateTo(target.clamp(0, _scroll.position.maxScrollExtent),
              duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
        }
      });
      return ListView.builder(
        controller: _scroll,
        itemCount: synced.length,
        itemBuilder: (context, i) {
          final on = i == active;
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(synced[i].text.isEmpty ? '♪' : synced[i].text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: on ? 22 : 18,
                fontWeight: on ? FontWeight.w800 : FontWeight.w500,
                color: on ? Colors.white : Colors.white38)),
          );
        },
      );
    }
    if (lyrics!.plain != null && lyrics!.plain!.trim().isNotEmpty) {
      return SingleChildScrollView(child: Padding(padding: const EdgeInsets.all(8),
        child: Text(lyrics!.plain!, textAlign: TextAlign.center, style: const TextStyle(fontSize: 17, height: 1.6, color: Colors.white70))));
    }
    return const Center(child: Text('No lyrics found', style: TextStyle(color: Colors.white54)));
  }
}
