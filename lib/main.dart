import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:just_audio_background/just_audio_background.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'player.dart';
import 'store.dart';
import 'settings.dart';
import 'screens.dart';
import 'now_playing.dart';
import 'settings_screen.dart';
import 'widgets.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await JustAudioBackground.init(
    androidNotificationChannelId: 'com.soundcircle.audio',
    androidNotificationChannelName: 'Sound Circle',
    androidNotificationOngoing: true,
  );
  final settings = Settings();
  final library = Library();
  await Future.wait([settings.init(), library.init()]);
  final player = Player()..autoplay = settings.autoplay;
  player.onPlayed = library.addHistory;

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: library),
      ChangeNotifierProvider.value(value: player),
    ],
    child: const SoundCircleApp(),
  ));
}

class SoundCircleApp extends StatelessWidget {
  const SoundCircleApp({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<Settings>();
    return MaterialApp(
      title: 'Sound Circle',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: s.bg,
        colorScheme: ColorScheme.dark(
          primary: s.accentColors[0], secondary: s.accentColors[1], surface: const Color(0xFF16161f),
        ),
        sliderTheme: SliderThemeData(activeTrackColor: s.accentColors[0], thumbColor: s.accentColors[0]),
        fontFamily: 'Roboto',
      ),
      home: const RootPage(),
    );
  }
}

class RootPage extends StatefulWidget {
  const RootPage({super.key});
  @override
  State<RootPage> createState() => _RootPageState();
}

class _RootPageState extends State<RootPage> {
  int _tab = 0;
  final _pages = const [HomeScreen(), SearchScreen(), LibraryScreen()];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        title: Row(children: [
          Icon(Icons.graphic_eq, color: context.watch<Settings>().accentColors[0]),
          const SizedBox(width: 8),
          Text('Sound Circle', style: TextStyle(fontWeight: FontWeight.w800, color: context.watch<Settings>().accentColors[0])),
        ]),
        actions: [IconButton(icon: const Icon(Icons.settings), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen())))],
      ),
      body: IndexedStack(index: _tab, children: _pages),
      bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
        const MiniPlayer(),
        NavigationBar(
          backgroundColor: const Color(0xFF0C0C16),
          selectedIndex: _tab,
          onDestinationSelected: (i) => setState(() => _tab = i),
          destinations: const [
            NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.search), label: 'Search'),
            NavigationDestination(icon: Icon(Icons.library_music_outlined), selectedIcon: Icon(Icons.library_music), label: 'Library'),
          ],
        ),
      ]),
    );
  }
}

class MiniPlayer extends StatefulWidget {
  const MiniPlayer({super.key});
  @override
  State<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends State<MiniPlayer> {
  Color? _tint;
  String? _tintFor;

  Future<void> _updateTint(String? cover) async {
    if (cover == _tintFor) return;
    _tintFor = cover;
    if (cover == null || !context.read<Settings>().dynamicTheme) { setState(() => _tint = null); return; }
    try {
      final pg = await PaletteGenerator.fromImageProvider(CachedNetworkImageProvider(cover), size: const Size(64, 64), maximumColorCount: 8);
      if (mounted) setState(() => _tint = pg.vibrantColor?.color ?? pg.dominantColor?.color);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<Player>();
    final s = p.current;
    if (s == null) return const SizedBox.shrink();
    _updateTint(s.cover);
    return Material(
      color: const Color(0xFF101019),
      child: InkWell(
        onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const NowPlayingScreen())),
        child: Container(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(gradient: _tint != null
              ? LinearGradient(colors: [_tint!.withValues(alpha: 0.35), Colors.transparent], stops: const [0, 0.6])
              : null),
          child: Row(children: [
            cover(s.cover, 46, radius: 6),
            const SizedBox(width: 12),
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white60)),
            ])),
            if (p.loading)
              const Padding(padding: EdgeInsets.all(12), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
            else
              IconButton(icon: Icon(p.playing ? Icons.pause : Icons.play_arrow, size: 30), onPressed: p.toggle),
            IconButton(icon: const Icon(Icons.skip_next, size: 28), onPressed: p.next),
          ]),
        ),
      ),
    );
  }
}
