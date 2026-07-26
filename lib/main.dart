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
  player.localPath = library.downloadPath; // play offline files when available
  player.onError = (message, offline) {
    final m = scaffoldMessengerKey.currentState;
    if (m == null) return;
    m.hideCurrentSnackBar();
    m.showSnackBar(SnackBar(
      content: Text(offline ? 'Sorry, no internet connection' : message),
      duration: const Duration(seconds: 4),
      action: offline
          ? SnackBarAction(label: 'Downloads', onPressed: () {
              final ctx = navigatorKey.currentContext;
              if (ctx != null) Navigator.push(ctx, MaterialPageRoute(builder: (_) => const SongListScreen(kind: SongListKind.downloads)));
            })
          : null,
    ));
  };

  runApp(MultiProvider(
    providers: [
      ChangeNotifierProvider.value(value: settings),
      ChangeNotifierProvider.value(value: library),
      ChangeNotifierProvider.value(value: player),
    ],
    child: const SoundCircleApp(),
  ));
}

final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
final navigatorKey = GlobalKey<NavigatorState>();

class SoundCircleApp extends StatelessWidget {
  const SoundCircleApp({super.key});
  @override
  Widget build(BuildContext context) {
    final s = context.watch<Settings>();
    return MaterialApp(
      title: 'Sound Circle',
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      navigatorKey: navigatorKey,
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
    final s = context.watch<Settings>();
    final accent = s.accentColors[0];
    final p = context.watch<Player>();
    final hasQueue = p.hasManualQueue && s.queueBarShow;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 16,
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        shadowColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        // Vertical fade that ends exactly on the page colour → no seam / black line.
        flexibleSpace: Container(decoration: BoxDecoration(gradient: LinearGradient(
          begin: Alignment.topCenter, end: Alignment.bottomCenter,
          colors: [Color.lerp(s.bg, accent, 0.22)!, s.bg]))),
        title: Row(children: [
          Icon(Icons.graphic_eq, color: accent),
          const SizedBox(width: 8),
          Text('Sound Circle', style: TextStyle(fontWeight: FontWeight.w800, color: accent)),
        ]),
        actions: [
          if (hasQueue)
            IconButton(
              tooltip: s.queueBarOpen ? 'Hide queue bar' : 'Show queue bar',
              icon: Badge(
                isLabelVisible: !s.queueBarOpen,
                label: Text('${p.manualQueue.length}'),
                child: Icon(s.queueBarOpen ? Icons.playlist_remove : Icons.queue_music),
              ),
              onPressed: () => s.update(() => s.queueBarOpen = !s.queueBarOpen)),
          IconButton(icon: const Icon(Icons.settings), onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SettingsScreen()))),
        ],
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

    // Offline / error banner instead of the normal bar.
    if (p.error != null && p.needsDownloads) {
      return Material(color: const Color(0xFF2a1420),
        child: Padding(padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
          child: Row(children: [
            const Icon(Icons.wifi_off, color: Colors.redAccent, size: 20),
            const SizedBox(width: 10),
            const Expanded(child: Text('No internet connection', style: TextStyle(fontWeight: FontWeight.w600))),
            TextButton.icon(
              onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SongListScreen(kind: SongListKind.downloads))),
              icon: const Icon(Icons.download_done, size: 18), label: const Text('Downloads')),
          ]),
        ),
      );
    }

    return Material(
      color: const Color(0xFF101019),
      child: InkWell(
        onTap: () => Navigator.of(context).push(slideUpRoute(const NowPlayingScreen())),
        child: Container(
          height: 62,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(gradient: _tint != null
              ? LinearGradient(colors: [_tint!.withValues(alpha: 0.35), Colors.transparent], stops: const [0, 0.6])
              : null),
          child: Row(children: [
            Hero(tag: 'npCover', child: cover(s.cover, 46, radius: 6)),
            const SizedBox(width: 12),
            Expanded(child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
              context.watch<Settings>().scrollingTitles
                  ? MarqueeText(s.title, style: const TextStyle(fontWeight: FontWeight.w600))
                  : Text(s.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
              Text(s.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.white60)),
            ])),
            IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.skip_previous, size: 26), onPressed: p.prev),
            if (p.loading)
              const Padding(padding: EdgeInsets.all(10), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)))
            else
              IconButton(visualDensity: VisualDensity.compact, icon: Icon(p.playing ? Icons.pause : Icons.play_arrow, size: 30), onPressed: p.toggle),
            IconButton(visualDensity: VisualDensity.compact, icon: const Icon(Icons.skip_next, size: 26), onPressed: p.next),
          ]),
        ),
      ),
    );
  }
}
