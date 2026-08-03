import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:youtube_explode_dart/youtube_explode_dart.dart' as yt;
import 'deezer.dart';
import 'store.dart';
import 'widgets.dart';

/// Import a YouTube / YouTube Music playlist by pasting its link. Each video is
/// matched to a track so the result behaves like a normal Sound Circle playlist.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key});
  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  final _url = TextEditingController();
  final _yt = yt.YoutubeExplode();
  bool busy = false;
  String? error;
  String status = '';
  int done = 0, total = 0;
  String? playlistName;
  final List<Song> found = [];
  final List<String> missed = [];

  @override
  void dispose() { _yt.close(); _url.dispose(); super.dispose(); }

  /// Strip the noise YouTube titles carry so the search matches a real track.
  static String _clean(String t) => t
      .replaceAll(RegExp(r'\([^)]*(official|video|audio|lyric|visualizer|hd|4k|mv)[^)]*\)', caseSensitive: false), '')
      .replaceAll(RegExp(r'\[[^\]]*(official|video|audio|lyric|visualizer|hd|4k|mv)[^\]]*\]', caseSensitive: false), '')
      .replaceAll(RegExp(r'\b(official\s*(music\s*)?video|official\s*audio|lyric\s*video|visualizer|hq|hd|4k)\b', caseSensitive: false), '')
      .replaceAll(RegExp(r'\s*[|/]\s*.*$'), '')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .trim();

  Future<void> _import() async {
    final raw = _url.text.trim();
    if (raw.isEmpty) return;
    setState(() { busy = true; error = null; found.clear(); missed.clear(); done = 0; total = 0; status = 'Opening playlist…'; });
    try {
      final pl = await _yt.playlists.get(raw);
      playlistName = pl.title;
      final videos = await _yt.playlists.getVideos(pl.id).take(200).toList();
      if (!mounted) return;
      setState(() { total = videos.length; status = 'Matching songs…'; });

      for (final v in videos) {
        if (!mounted) return;
        final title = _clean(v.title);
        final author = v.author.replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '').trim();
        Song? match = await Deezer.searchOne('$author $title');
        match ??= await Deezer.searchOne(title);
        if (match != null && !found.any((s) => s.deezerId == match!.deezerId)) {
          found.add(match);
        } else if (match == null) {
          missed.add(v.title);
        }
        setState(() => done++);
      }
      if (!mounted) return;
      setState(() { busy = false; status = 'Done'; });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        busy = false;
        error = 'Could not read that playlist. Make sure the link is public '
            'and looks like youtube.com/playlist?list=…';
      });
    }
  }

  void _save() {
    final lib = context.read<Library>();
    final p = lib.createPlaylist(playlistName?.trim().isNotEmpty == true
        ? playlistName!.trim() : 'Imported playlist');
    for (final s in found) { lib.addToPlaylist(p.id, s); }
    toast(context, 'Saved ${found.length} songs', icon: Icons.playlist_add_check);
    Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Import from YouTube')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        const Text('Paste a YouTube or YouTube Music playlist link. '
            'The playlist has to be public or unlisted — not private.',
          style: TextStyle(color: Colors.white54, fontSize: 13)),
        const SizedBox(height: 14),
        TextField(
          controller: _url,
          decoration: const InputDecoration(
            hintText: 'https://www.youtube.com/playlist?list=…',
            filled: true, fillColor: Color(0xFF1c1c28),
            border: OutlineInputBorder(borderSide: BorderSide.none)),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: busy ? null : _import,
          icon: busy
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
            : const Icon(Icons.download),
          label: Text(busy ? 'Importing…' : 'Import'),
          style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
        ),

        if (error != null) Padding(padding: const EdgeInsets.only(top: 14),
          child: Text(error!, style: const TextStyle(color: Colors.redAccent))),

        if (total > 0) ...[
          const SizedBox(height: 20),
          if (playlistName != null)
            Text(playlistName!, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w800)),
          const SizedBox(height: 8),
          LinearProgressIndicator(value: total == 0 ? null : done / total),
          const SizedBox(height: 8),
          Text('$done of $total  ·  ${found.length} matched'
               '${missed.isNotEmpty ? '  ·  ${missed.length} not found' : ''}',
            style: const TextStyle(color: Colors.white54, fontSize: 13)),
          if (!busy && found.isNotEmpty) ...[
            const SizedBox(height: 14),
            FilledButton.icon(
              onPressed: _save,
              icon: const Icon(Icons.playlist_add),
              label: Text('Save as playlist (${found.length} songs)'),
              style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
            ),
          ],
          const SizedBox(height: 16),
          ...found.asMap().entries.map((e) =>
            SongTile(song: e.value, queue: found, index: e.key)),
          if (missed.isNotEmpty) ...[
            const Padding(padding: EdgeInsets.fromLTRB(0, 18, 0, 6),
              child: Text('Not found', style: TextStyle(fontWeight: FontWeight.w700))),
            ...missed.take(20).map((m) => Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Text('· $m', maxLines: 1, overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Colors.white38, fontSize: 13)))),
          ],
        ],
      ]),
    );
  }
}
