import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'settings.dart';
import 'store.dart';
import 'player.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<Settings>();
    final lib = context.read<Library>();
    final player = context.read<Player>();
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(padding: const EdgeInsets.only(bottom: 30), children: [
        _h('Profile'),
        ListTile(
          title: const Text('Your name'),
          subtitle: const Text('Shown in the Home welcome'),
          trailing: SizedBox(width: 140, child: TextField(
            controller: TextEditingController(text: s.displayName),
            textAlign: TextAlign.end,
            decoration: const InputDecoration(hintText: 'Name', border: InputBorder.none),
            onSubmitted: (v) => s.update(() => s.displayName = v.trim()),
          )),
        ),

        _h('Appearance'),
        ListTile(
          title: const Text('Accent colour'),
          trailing: Row(mainAxisSize: MainAxisSize.min, children: accents.keys.map((k) {
            final on = s.accent == k;
            return GestureDetector(
              onTap: () => s.update(() => s.accent = k),
              child: Container(
                width: 26, height: 26, margin: const EdgeInsets.only(left: 8),
                decoration: BoxDecoration(shape: BoxShape.circle,
                  gradient: LinearGradient(colors: accents[k]!),
                  border: Border.all(color: on ? Colors.white : Colors.transparent, width: 2)),
              ),
            );
          }).toList()),
        ),
        SwitchListTile(title: const Text('AMOLED black'), value: s.amoled, onChanged: (v) => s.update(() => s.amoled = v)),
        SwitchListTile(title: const Text('Colour from cover'), subtitle: const Text('Tint the player to the album art'),
          value: s.dynamicTheme, onChanged: (v) => s.update(() => s.dynamicTheme = v)),
        SwitchListTile(title: const Text('Scrolling titles'), subtitle: const Text('Long titles scroll side to side'),
          value: s.scrollingTitles, onChanged: (v) => s.update(() => s.scrollingTitles = v)),

        _h('Playback'),
        SwitchListTile(title: const Text('Autoplay radio'), subtitle: const Text('Keep playing similar songs when the queue ends'),
          value: s.autoplay, onChanged: (v) { s.update(() => s.autoplay = v); player.autoplay = v; }),

        _h('Queue sheet'),
        SwitchListTile(title: const Text('Expandable queue'), subtitle: const Text('Drag to grow/shrink while scrolling'),
          value: s.queueExpands, onChanged: (v) => s.update(() => s.queueExpands = v)),
        SwitchListTile(title: const Text('Show titles in queue'), subtitle: const Text('Off = compact art-only rows'),
          value: s.queueShowTitles, onChanged: (v) => s.update(() => s.queueShowTitles = v)),

        _h('NEXT UP bar (home)'),
        SwitchListTile(title: const Text('Show queue bar'), subtitle: const Text('The NEXT UP strip on Home'),
          value: s.queueBarShow, onChanged: (v) => s.update(() => s.queueBarShow = v)),
        SwitchListTile(title: const Text('Shrink on scroll'), subtitle: const Text('Contract to thumbnails as you scroll'),
          value: s.queueBarShrink, onChanged: (v) => s.update(() => s.queueBarShrink = v)),
        SwitchListTile(title: const Text('Show artist'), subtitle: const Text('Artist name under each title'),
          value: s.queueBarArtist, onChanged: (v) => s.update(() => s.queueBarArtist = v)),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
          child: Row(children: [
            const Text('Cover size'),
            Expanded(child: Slider(
              value: s.queueBarSize, min: 68, max: 150, divisions: 41,
              label: '${s.queueBarSize.round()} px',
              onChanged: (v) => s.update(() => s.queueBarSize = v))),
            SizedBox(width: 46, child: Text('${s.queueBarSize.round()}', textAlign: TextAlign.end,
              style: const TextStyle(color: Colors.white54))),
          ]),
        ),

        _h('Home feed'),
        SwitchListTile(title: const Text('Greeting'), subtitle: const Text('“Good afternoon” header'),
          value: s.showGreeting, onChanged: (v) => s.update(() => s.showGreeting = v)),
        SwitchListTile(title: const Text('Mood chips'), subtitle: const Text('Chill · Energy · Focus …'),
          value: s.moodChips, onChanged: (v) => s.update(() => s.moodChips = v)),
        SwitchListTile(title: const Text('Snap quick picks'), subtitle: const Text('Swipe one 3×3 grid at a time'),
          value: s.quickPicksSnap, onChanged: (v) => s.update(() => s.quickPicksSnap = v)),
        SwitchListTile(title: const Text('Quick picks'), subtitle: const Text('Grid of recent & liked songs'),
          value: s.showQuickPicks, onChanged: (v) => s.update(() => s.showQuickPicks = v)),
        SwitchListTile(title: const Text('Made for you'), subtitle: const Text('Personal recommendation row'),
          value: s.showQuickPlay, onChanged: (v) => s.update(() => s.showQuickPlay = v)),
        SwitchListTile(title: const Text('Mixes & radios'), value: s.showMixes, onChanged: (v) => s.update(() => s.showMixes = v)),
        SwitchListTile(title: const Text('Your playlists'), value: s.showPlaylistsHome, onChanged: (v) => s.update(() => s.showPlaylistsHome = v)),
        SwitchListTile(title: const Text('Downloaded shelf'), value: s.showDownloadsHome, onChanged: (v) => s.update(() => s.showDownloadsHome = v)),
        SwitchListTile(title: const Text('Discover section'), subtitle: const Text('Charts, top artists, new releases'),
          value: s.showDiscover, onChanged: (v) => s.update(() => s.showDiscover = v)),
        SwitchListTile(title: const Text('Trending now'), value: s.showTrending, onChanged: (v) => s.update(() => s.showTrending = v)),

        _h('Song menu · big buttons (pick 3)'),
        _chips(context, bigCapable, s.menuBig, (list) => s.update(() => s.menuBig = list), max: 3),
        _h('Song menu · options'),
        _chips(context, allMenuActions.keys.toList(), s.menuOptions, (list) => s.update(() => s.menuOptions = list)),

        _h('Data'),
        ListTile(title: const Text('Clear listening history'),
          trailing: const Icon(Icons.delete_outline), onTap: () { lib.clearHistory(); }),
        const SizedBox(height: 20),
        const Center(child: Text('Sound Circle · native', style: TextStyle(color: Colors.white38, fontSize: 12))),
      ]),
    );
  }

  Widget _h(String t) => Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 6),
      child: Text(t.toUpperCase(), style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 0.6, color: Colors.white38)));

  Widget _chips(BuildContext context, List<String> all, List<String> selected, void Function(List<String>) onChange, {int? max}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(spacing: 8, runSpacing: 8, children: all.map((k) {
        final on = selected.contains(k);
        return GestureDetector(
          onTap: () {
            List<String> next;
            if (on) { next = selected.where((x) => x != k).toList(); }
            else { next = [...selected, k]; if (max != null && next.length > max) next = next.sublist(next.length - max); }
            onChange(next);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(18),
              gradient: on ? LinearGradient(colors: context.read<Settings>().accentColors) : null,
              color: on ? null : const Color(0xFF23232f)),
            child: Text(allMenuActions[k] ?? k, style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: on ? Colors.white : Colors.white70)),
          ),
        );
      }).toList()),
    );
  }
}
