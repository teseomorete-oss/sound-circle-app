import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'player.dart';

/// Android's native equalizer, exposed as sliders plus a few presets.
class EqualizerScreen extends StatefulWidget {
  const EqualizerScreen({super.key});
  @override
  State<EqualizerScreen> createState() => _EqualizerScreenState();
}

class _EqualizerScreenState extends State<EqualizerScreen> {
  bool enabled = false;
  bool levelling = false;
  String preset = 'Flat';

  // Gain multipliers per band, low → high. Applied relative to the band range.
  static const presets = <String, List<double>>{
    'Flat':      [0, 0, 0, 0, 0],
    'Bass boost':[0.85, 0.55, 0, 0, 0.15],
    'Treble':    [0, 0, 0.1, 0.55, 0.8],
    'Vocal':     [-0.2, 0.1, 0.6, 0.45, 0],
    'Podcast':   [-0.4, 0, 0.7, 0.5, -0.1],
    'Party':     [0.6, 0.2, 0, 0.3, 0.6],
  };

  @override
  void initState() {
    super.initState();
    SharedPreferences.getInstance().then((p) async {
      if (!mounted) return;
      final on = p.getBool('eqEnabled') ?? false;
      final lv = p.getBool('eqLevelling') ?? false;
      setState(() { enabled = on; levelling = lv; preset = p.getString('eqPreset') ?? 'Flat'; });
      final player = context.read<Player>();
      await player.setEqualizerEnabled(on);
      await player.setVolumeLevelling(lv);
    });
  }

  Future<void> _apply(String name) async {
    final player = context.read<Player>();
    setState(() => preset = name);
    (await SharedPreferences.getInstance()).setString('eqPreset', name);
    try {
      final params = await player.equalizer.parameters;
      final bands = params.bands;
      final gains = presets[name]!;
      for (var i = 0; i < bands.length; i++) {
        // Spread the 5 preset values across however many bands the device has.
        final t = bands.length == 1 ? 0.0 : i / (bands.length - 1);
        final pos = t * (gains.length - 1);
        final lo = pos.floor(), hi = pos.ceil();
        final f = pos - lo;
        final g = gains[lo] * (1 - f) + gains[hi] * f;
        final range = g >= 0
            ? (params.maxDecibels - 0) * g
            : (0 - params.minDecibels) * g;
        await bands[i].setGain(range.clamp(params.minDecibels, params.maxDecibels));
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final player = context.read<Player>();
    final accent = Theme.of(context).colorScheme.primary;
    return Scaffold(
      appBar: AppBar(title: const Text('Sound')),
      body: ListView(padding: const EdgeInsets.only(bottom: 30), children: [
        SwitchListTile(
          title: const Text('Equalizer'),
          subtitle: const Text('Shape the sound to your taste'),
          value: enabled,
          onChanged: (v) async {
            setState(() => enabled = v);
            (await SharedPreferences.getInstance()).setBool('eqEnabled', v);
            await player.setEqualizerEnabled(v);
            if (v) _apply(preset);
          },
        ),
        SwitchListTile(
          title: const Text('Even out volume'),
          subtitle: const Text('Boosts quieter songs so levels match'),
          value: levelling,
          onChanged: (v) async {
            setState(() => levelling = v);
            (await SharedPreferences.getInstance()).setBool('eqLevelling', v);
            await player.setVolumeLevelling(v);
          },
        ),

        const Padding(padding: EdgeInsets.fromLTRB(16, 18, 16, 8),
          child: Text('Presets', style: TextStyle(fontWeight: FontWeight.w800))),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Wrap(spacing: 8, runSpacing: 8, children: presets.keys.map((k) {
            final on = preset == k;
            return GestureDetector(
              onTap: enabled ? () => _apply(k) : null,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
                  color: on && enabled ? accent : const Color(0xFF1c1c28)),
                child: Text(k, style: TextStyle(
                  fontWeight: FontWeight.w600,
                  color: enabled ? (on ? Colors.white : Colors.white70) : Colors.white24)),
              ),
            );
          }).toList()),
        ),

        const Padding(padding: EdgeInsets.fromLTRB(16, 22, 16, 4),
          child: Text('Bands', style: TextStyle(fontWeight: FontWeight.w800))),
        if (!enabled)
          const Padding(padding: EdgeInsets.all(20),
            child: Text('Turn the equalizer on to adjust the bands.',
              style: TextStyle(color: Colors.white38)))
        else
          FutureBuilder<AndroidEqualizerParameters>(
            future: player.equalizer.parameters,
            builder: (context, snap) {
              if (!snap.hasData) {
                return const Padding(padding: EdgeInsets.all(24),
                  child: Center(child: CircularProgressIndicator()));
              }
              final params = snap.data!;
              return Column(children: params.bands.map((b) => StreamBuilder<double>(
                stream: b.gainStream,
                builder: (context, g) => Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Row(children: [
                    SizedBox(width: 64, child: Text(
                      b.centerFrequency >= 1000
                        ? '${(b.centerFrequency / 1000).toStringAsFixed(b.centerFrequency >= 10000 ? 0 : 1)} kHz'
                        : '${b.centerFrequency.round()} Hz',
                      style: const TextStyle(fontSize: 12, color: Colors.white54))),
                    Expanded(child: Slider(
                      min: params.minDecibels, max: params.maxDecibels,
                      value: (g.data ?? b.gain).clamp(params.minDecibels, params.maxDecibels),
                      onChanged: (v) { b.setGain(v); setState(() => preset = 'Custom'); },
                    )),
                    SizedBox(width: 46, child: Text(
                      '${(g.data ?? b.gain) >= 0 ? '+' : ''}${(g.data ?? b.gain).toStringAsFixed(1)}',
                      textAlign: TextAlign.end,
                      style: const TextStyle(fontSize: 12, color: Colors.white54))),
                  ]),
                ),
              )).toList());
            },
          ),
        const Padding(padding: EdgeInsets.fromLTRB(16, 20, 16, 0),
          child: Text('Effects apply to streamed and downloaded music alike.',
            style: TextStyle(color: Colors.white24, fontSize: 12))),
      ]),
    );
  }
}
