import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'store.dart';
import 'player.dart';
import 'widgets.dart';

/// "Your listening" — top songs, top artists and time listened, built from the
/// play history the app records locally (and syncs with your account).
class StatsScreen extends StatefulWidget {
  const StatsScreen({super.key});
  @override
  State<StatsScreen> createState() => _StatsScreenState();
}

class _StatsScreenState extends State<StatsScreen> {
  // null = all time
  int? days = 30;
  static const _ranges = [(7, 'Week'), (30, 'Month'), (365, 'Year'), (null, 'All time')];

  String _fmtTime(Duration d) {
    if (d.inMinutes < 60) return '${d.inMinutes} min';
    final h = d.inHours, m = d.inMinutes % 60;
    if (h < 24) return m == 0 ? '$h h' : '$h h $m min';
    return '${d.inDays} d ${h % 24} h';
  }

  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final songs = lib.topSongs(days: days, limit: 25);
    final artists = lib.topArtists(days: days, limit: 12);
    final time = lib.listenedTime(days: days);
    final total = lib.playsSince(days).length;
    final accent = Theme.of(context).colorScheme.primary;

    return Scaffold(
      appBar: AppBar(title: const Text('Your listening')),
      body: ListView(padding: const EdgeInsets.only(bottom: 30), children: [
        // range picker
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
          child: Row(children: _ranges.map((r) {
            final on = days == r.$1;
            return Expanded(child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => setState(() => days = r.$1),
                child: Container(
                  height: 38, alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(19),
                    color: on ? accent : const Color(0xFF1c1c28)),
                  child: Text(r.$2, style: TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 13,
                    color: on ? Colors.white : Colors.white60)),
                ),
              ),
            ));
          }).toList()),
        ),

        if (total == 0)
          const Padding(padding: EdgeInsets.all(40),
            child: Center(child: Text('Nothing here yet.\nPlay some music and check back.',
              textAlign: TextAlign.center, style: TextStyle(color: Colors.white38))))
        else ...[
          // headline numbers
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: Row(children: [
              Expanded(child: _bigStat('Songs played', '$total', Icons.play_arrow, accent)),
              const SizedBox(width: 12),
              Expanded(child: _bigStat('Time listened', _fmtTime(time), Icons.schedule, accent)),
            ]),
          ),

          if (artists.isNotEmpty) ...[
            const SectionHeader('Top artists'),
            SizedBox(height: 150, child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: artists.length,
              itemBuilder: (context, i) {
                final a = artists[i];
                return SizedBox(width: 108, child: Column(children: [
                  Stack(alignment: Alignment.bottomLeft, children: [
                    cover(a.picture, 92, radius: 46, icon: Icons.person),
                    Container(
                      margin: const EdgeInsets.all(2),
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(color: accent, borderRadius: BorderRadius.circular(10)),
                      child: Text('${i + 1}', style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11)),
                    ),
                  ]),
                  const SizedBox(height: 6),
                  Text(a.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                  Text('${a.count} plays', style: const TextStyle(fontSize: 11, color: Colors.white38)),
                ]));
              },
            )),
          ],

          if (songs.isNotEmpty) ...[
            const SectionHeader('Top songs'),
            ...songs.asMap().entries.map((e) {
              final rank = e.key + 1;
              final s = e.value.song;
              return InkWell(
                onTap: () => context.read<Player>().playList(songs.map((x) => x.song).toList(), e.key),
                onLongPress: () => showSongMenu(context, s),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  child: Row(children: [
                    SizedBox(width: 30, child: Text('$rank', textAlign: TextAlign.center,
                      style: TextStyle(fontSize: rank < 10 ? 19 : 16, fontWeight: FontWeight.w900,
                        color: rank <= 3 ? accent : Colors.white38))),
                    const SizedBox(width: 8),
                    cover(s.cover, 46),
                    const SizedBox(width: 12),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                      Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 13, color: Colors.white54)),
                    ])),
                    Text('${e.value.count}×', style: const TextStyle(color: Colors.white38, fontWeight: FontWeight.w700)),
                  ]),
                ),
              );
            }),
          ],
        ],
      ]),
    );
  }

  Widget _bigStat(String label, String value, IconData icon, Color accent) => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(color: const Color(0xFF16161f), borderRadius: BorderRadius.circular(14)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [Icon(icon, size: 16, color: accent), const SizedBox(width: 6),
            Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12))]),
          const SizedBox(height: 8),
          Text(value, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w900)),
        ]),
      );
}
