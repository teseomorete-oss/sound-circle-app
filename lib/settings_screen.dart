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

        _h('Playback'),
        SwitchListTile(title: const Text('Autoplay radio'), subtitle: const Text('Keep playing similar songs when the queue ends'),
          value: s.autoplay, onChanged: (v) { s.update(() => s.autoplay = v); player.autoplay = v; }),

        _h('Home feed'),
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
