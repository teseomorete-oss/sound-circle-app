import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'main.dart';
import 'detail.dart';
import 'deezer.dart';
import 'player.dart';
import 'store.dart';
import 'settings.dart';
import 'widgets.dart';

String greeting() {
  final h = DateTime.now().hour;
  if (h < 12) return 'Good morning';
  if (h < 18) return 'Good afternoon';
  return 'Good evening';
}

// ---------------- Home ----------------
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  List<Song> trending = [];
  List<Album> releases = [];
  List<Artist> topArtists = [];
  List<Song> becausePlayed = [];
  List<Song> quickPicks = [];
  List<Song> recommended = [];
  bool loading = true;

  final _sc = ScrollController();
  final _shrink = ValueNotifier<double>(0);

  @override
  void initState() {
    super.initState();
    _sc.addListener(() => _shrink.value = (_sc.offset / 170).clamp(0.0, 1.0));
    _load();
  }

  @override
  void dispose() { _sc.dispose(); _shrink.dispose(); super.dispose(); }

  Future<void> _load() async {
    final lib = context.read<Library>();
    final names = lib.topArtistNames();
    final results = await Future.wait([
      Deezer.chart(),
      Deezer.newReleases(),
      Future.wait(names.take(10).map((n) => Deezer.searchArtists(n, limit: 1).then((r) => r.isNotEmpty ? r.first : null))),
      names.isNotEmpty
          ? Deezer.searchArtists(names.first, limit: 1).then((r) => r.isNotEmpty ? Deezer.artistRadio(r.first.id, limit: 20) : <Song>[])
          : Future.value(<Song>[]),
      // recommendations: blend radios from the top few artists for variety
      Future.wait(names.take(3).map((n) => Deezer.searchArtists(n, limit: 1)
          .then((r) => r.isNotEmpty ? Deezer.artistRadio(r.first.id, limit: 12) : <Song>[]))),
    ]);
    if (!mounted) return;
    final chart = results[0] as List<Song>;
    final recRaw = (results[4] as List).cast<List<Song>>();
    // interleave the per-artist radios so the feed feels varied, then top up with chart
    final blended = <Song>[];
    final seen = <int>{};
    for (var i = 0; i < 12; i++) {
      for (final list in recRaw) { if (i < list.length && seen.add(list[i].deezerId)) blended.add(list[i]); }
    }
    for (final s in chart) { if (seen.add(s.deezerId)) blended.add(s); }

    // quick picks = recent + liked + recommendations + trending (deduped) → up to 27 (3 grids)
    final qp = <Song>[]; final qpSeen = <int>{};
    for (final s in [...lib.history.take(9), ...lib.liked.take(9), ...blended.take(18), ...chart.take(18)]) {
      if (qpSeen.add(s.deezerId)) qp.add(s);
    }

    setState(() {
      trending = chart;
      releases = results[1] as List<Album>;
      topArtists = (results[2] as List).whereType<Artist>().toList();
      if (topArtists.isEmpty) { Deezer.chartArtists().then((a) => mounted ? setState(() => topArtists = a) : null); }
      becausePlayed = results[3] as List<Song>;
      recommended = blended.isNotEmpty ? blended : chart;
      quickPicks = qp.take(27).toList();
      loading = false;
    });
  }

  List<Widget> _mixes(Library lib) {
    final mixes = <Widget>[];
    final grads = [
      [const Color(0xFF7C3AED), const Color(0xFFEC4899)],
      [const Color(0xFF2563EB), const Color(0xFF06B6D4)],
      [const Color(0xFFF97316), const Color(0xFFF43F5E)],
      [const Color(0xFF16A34A), const Color(0xFF14B8A6)],
      [const Color(0xFFDB2777), const Color(0xFF7C3AED)],
    ];
    var gi = 0;
    if (lib.liked.length >= 3) {
      mixes.add(MixCard(title: 'On Repeat', subtitle: 'Your liked songs', gradient: grads[gi++ % grads.length],
        cover: lib.liked.first.cover, resolve: () async => (lib.liked.toList()..shuffle())));
    }
    for (final a in topArtists.take(4)) {
      mixes.add(MixCard(title: '${a.name} Mix', subtitle: 'Radio', cover: a.picture, gradient: grads[gi++ % grads.length],
        resolve: () => Deezer.artistRadio(a.id, limit: 40)));
    }
    if (trending.isNotEmpty) {
      mixes.add(MixCard(title: 'Discovery', subtitle: 'Fresh picks', gradient: grads[gi++ % grads.length],
        cover: trending.first.cover, resolve: () async => (recommended.isNotEmpty ? recommended : trending)));
    }
    return mixes;
  }

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<Settings>();
    final lib = context.watch<Library>();
    final hi = '${greeting()}${settings.displayName.isNotEmpty ? ', ${settings.displayName}' : ''}';
    final mixes = _mixes(lib);
    return Column(children: [
      const SizedBox(height: 4),
      // NEXT UP sits above the scroll and contracts as you scroll down.
      ValueListenableBuilder<double>(valueListenable: _shrink,
        builder: (_, t, __) => NextUpBar(shrink: t)),
      Expanded(child: RefreshIndicator(
      onRefresh: _load,
      child: loading
          ? ListView(children: const [SizedBox(height: 200), Center(child: CircularProgressIndicator())])
          : ListView(controller: _sc, children: [
              if (settings.showGreeting)
                Padding(padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(hi, style: const TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),

              // Mood chips (YT-Music style)
              if (settings.moodChips)
                SizedBox(height: 44, child: ListView(
                  scrollDirection: Axis.horizontal, padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
                  children: [
                    for (final m in const ['Chill', 'Energy', 'Focus', 'Workout', 'Party', 'Sad', 'Feel good'])
                      Padding(padding: const EdgeInsets.only(right: 8), child: _MoodChip(mood: m)),
                  ],
                )),

              if (settings.showQuickPicks && quickPicks.length >= 3) ...[
                const SectionHeader('Quick picks'),
                QuickPicks(songs: quickPicks),
              ],

              if (lib.history.isNotEmpty) ...[
                const SectionHeader('Recently played'),
                ...lib.history.take(5).toList().asMap().entries.map((e) => SongTile(song: e.value, queue: lib.history, index: e.key)),
              ],

              if (settings.showQuickPlay && recommended.isNotEmpty) ...[
                const SectionHeader('Made for you'),
                CardShelf(children: recommended.take(15).toList().asMap().entries
                    .map((e) => SongCardW(song: e.value, queue: recommended, index: e.key)).toList()),
              ],

              if (settings.showMixes && mixes.isNotEmpty) ...[
                const SectionHeader('Mixes & radios'),
                CardShelf(children: mixes),
              ],

              if (settings.showPlaylistsHome && lib.playlists.isNotEmpty) ...[
                const SectionHeader('Your playlists'),
                CardShelf(children: lib.playlists.map((p) => PlaylistCardW(playlist: p)).toList()),
              ],

              if (settings.showDownloadsHome && lib.downloads.isNotEmpty) ...[
                const SectionHeader('Downloaded'),
                CardShelf(children: lib.downloads.take(15).toList().asMap().entries
                    .map((e) => SongCardW(song: e.value, queue: lib.downloads, index: e.key)).toList()),
              ],

              if (becausePlayed.isNotEmpty) ...[
                SectionHeader('Because you played ${lib.topArtistNames().first}'),
                CardShelf(children: becausePlayed.asMap().entries
                    .map((e) => SongCardW(song: e.value, queue: becausePlayed, index: e.key)).toList()),
              ],

              // ---------- Discover ----------
              if (settings.showDiscover) ...[
                const Padding(padding: EdgeInsets.fromLTRB(16, 26, 16, 0),
                  child: Text('Discover', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w900))),
                if (topArtists.isNotEmpty) ...[
                  SectionHeader(lib.history.isNotEmpty ? 'Your top artists' : 'Popular artists'),
                  CardShelf(children: topArtists.map((a) => ArtistCardW(artist: a)).toList()),
                ],
                if (settings.showTrending && trending.isNotEmpty) ...[
                  const SectionHeader('Trending now'),
                  ...trending.take(10).toList().asMap().entries.map((e) => SongTile(song: e.value, queue: trending, index: e.key)),
                ],
                if (releases.isNotEmpty) ...[
                  const SectionHeader('New releases'),
                  CardShelf(children: releases.map((a) => AlbumCardW(album: a)).toList()),
                ],
              ],
              const SizedBox(height: 24),
            ]),
      )),
    ]);
  }
}

class _MoodChip extends StatelessWidget {
  final String mood;
  const _MoodChip({required this.mood});
  @override
  Widget build(BuildContext context) => Material(
        color: const Color(0xFF1c1c28),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: () async {
            final messenger = ScaffoldMessenger.of(context);
            final player = context.read<Player>();
            messenger.showSnackBar(SnackBar(content: Text('$mood mix…'), duration: const Duration(milliseconds: 900)));
            final songs = await Deezer.search('$mood music', limit: 40);
            if (songs.isNotEmpty) player.playList(songs, 0);
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: Colors.white.withValues(alpha: 0.08))),
            child: Text(mood, style: const TextStyle(fontWeight: FontWeight.w600, height: 1.0)),
          ),
        ),
      );
}

// ---------------- Search ----------------
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});
  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final _ctrl = TextEditingController();
  final _focus = FocusNode();
  List<Song> songs = [];
  List<Artist> artists = [];
  // structured live suggestions
  List<Artist> sgArtists = [];
  List<Song> sgSongs = [];
  List<String> sgText = [];
  bool loading = false;
  bool showResults = false;
  Timer? _debounce;
  int _reqId = 0;

  bool get _hasSuggestions => sgArtists.isNotEmpty || sgSongs.isNotEmpty || sgText.isNotEmpty;

  @override
  void dispose() { _debounce?.cancel(); _ctrl.dispose(); _focus.dispose(); super.dispose(); }

  void _clearSuggestions() { sgArtists = []; sgSongs = []; sgText = []; }

  void _onChanged(String q) {
    _debounce?.cancel();
    final t = q.trim();
    if (t.isEmpty) { setState(() { _clearSuggestions(); showResults = false; songs = []; artists = []; }); return; }
    setState(() => showResults = false);
    _debounce = Timer(const Duration(milliseconds: 240), () => _suggest(t));
  }

  // Live autocomplete: a row of artists (with photos), then songs (with covers),
  // then plain text completions.
  Future<void> _suggest(String q) async {
    final id = ++_reqId;
    final r = await Future.wait([Deezer.search(q, limit: 12), Deezer.searchArtists(q, limit: 8)]);
    if (!mounted || id != _reqId) return;
    final allSongs = r[0] as List<Song>;
    final allArtists = r[1] as List<Artist>;
    final seen = <String>{};
    final text = <String>[];
    for (final s in allSongs.skip(4)) {
      if (seen.add(s.title.toLowerCase()) && text.length < 6) text.add(s.title);
    }
    setState(() {
      sgArtists = allArtists.take(8).toList();
      sgSongs = allSongs.take(4).toList();
      sgText = text;
    });
  }

  Future<void> _run(String q) async {
    q = q.trim();
    if (q.isEmpty) return;
    _focus.unfocus();
    _ctrl.text = q;
    setState(() { loading = true; showResults = true; _clearSuggestions(); });
    final r = await Future.wait([Deezer.search(q, limit: 40), Deezer.searchArtists(q)]);
    if (!mounted) return;
    setState(() { songs = r[0] as List<Song>; artists = r[1] as List<Artist>; loading = false; });
  }

  Widget _suggestionsView() => ListView(children: [
        if (sgArtists.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.fromLTRB(16, 14, 16, 6),
            child: Text('Artists', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white70))),
          SizedBox(height: 116, child: ListView(scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: sgArtists.map((a) => GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => ArtistScreen(artistId: a.id, name: a.name))),
              child: SizedBox(width: 84, child: Column(children: [
                cover(a.picture, 68, radius: 34, icon: Icons.person),
                const SizedBox(height: 4),
                Text(a.name, maxLines: 2, textAlign: TextAlign.center, overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11)),
              ])),
            )).toList())),
        ],
        if (sgSongs.isNotEmpty) ...[
          const Padding(padding: EdgeInsets.fromLTRB(16, 10, 16, 2),
            child: Text('Songs', style: TextStyle(fontWeight: FontWeight.w700, color: Colors.white70))),
          ...sgSongs.asMap().entries.map((e) => SongTile(song: e.value, queue: sgSongs, index: e.key)),
        ],
        if (sgText.isNotEmpty) ...[
          const Divider(height: 12),
          ...sgText.map((t) => ListTile(
            dense: true,
            leading: const Icon(Icons.search, size: 20, color: Colors.white54),
            title: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: const Icon(Icons.north_west, size: 16, color: Colors.white38),
            onTap: () => _run(t))),
        ],
      ]);

  @override
  Widget build(BuildContext context) {
    return Column(children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: TextField(
          controller: _ctrl, focusNode: _focus, textInputAction: TextInputAction.search,
          onChanged: _onChanged, onSubmitted: _run,
          decoration: InputDecoration(
            hintText: 'Songs, artists, albums…', prefixIcon: const Icon(Icons.search),
            suffixIcon: _ctrl.text.isEmpty ? null : IconButton(icon: const Icon(Icons.close),
              onPressed: () { _ctrl.clear(); _onChanged(''); setState(() {}); }),
            filled: true, fillColor: surface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(26), borderSide: BorderSide.none)),
        ),
      ),
      if (loading) const Padding(padding: EdgeInsets.all(30), child: CircularProgressIndicator()),
      Expanded(
        child: (!showResults && _hasSuggestions)
            ? _suggestionsView()
            : ListView(children: [
                if (artists.isNotEmpty) ...[
                  const SectionHeader('Artists'),
                  CardShelf(children: artists.map((a) => ArtistCardW(artist: a)).toList()),
                ],
                if (songs.isNotEmpty) const SectionHeader('Songs'),
                ...songs.asMap().entries.map((e) => SongTile(song: e.value, queue: songs, index: e.key)),
              ]),
      ),
    ]);
  }
}

// ---------------- Library ----------------
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    return ListView(children: [
      const Padding(padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text('Library', style: TextStyle(fontSize: 26, fontWeight: FontWeight.w800))),

      // Liked & Downloads as auto-playlists (like YT Music)
      _AutoPlaylistTile(
        gradient: const [Color(0xFFEC4899), Color(0xFF7C3AED)], icon: Icons.favorite,
        title: 'Liked Songs', subtitle: 'Auto playlist · ${lib.liked.length} songs',
        onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SongListScreen(kind: SongListKind.liked))),
      ),
      if (lib.downloads.isNotEmpty)
        _AutoPlaylistTile(
          gradient: const [Color(0xFF16A34A), Color(0xFF0F766E)], icon: Icons.download_done,
          title: 'Downloaded', subtitle: 'Offline · ${lib.downloads.length} songs',
          onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => const SongListScreen(kind: SongListKind.downloads))),
        ),

      Padding(
        padding: const EdgeInsets.fromLTRB(16, 18, 16, 4),
        child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          const Text('Playlists', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
          TextButton.icon(onPressed: () async {
            final name = await promptName(context);
            if (name != null && name.isNotEmpty) lib.createPlaylist(name);
          }, icon: const Icon(Icons.add, size: 18), label: const Text('New')),
        ]),
      ),
      if (lib.playlists.isEmpty)
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: Text('No playlists yet.', style: TextStyle(color: Colors.white54)))
      else
        ...lib.playlists.map((p) => ListTile(
              leading: cover(p.songs.isNotEmpty ? p.songs.first.cover : null, 50, icon: Icons.queue_music),
              title: Text(p.name),
              subtitle: Text('${p.songs.length} songs'),
              onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => PlaylistScreen(id: p.id))),
            )),

      if (lib.followed.isNotEmpty) ...[
        const SectionHeader('Following'),
        CardShelf(children: lib.followed.map((a) => ArtistCardW(artist: a)).toList()),
      ],
      const SizedBox(height: 20),
    ]);
  }
}

class _AutoPlaylistTile extends StatelessWidget {
  final List<Color> gradient; final IconData icon; final String title; final String subtitle; final VoidCallback onTap;
  const _AutoPlaylistTile({required this.gradient, required this.icon, required this.title, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) => ListTile(
        onTap: onTap,
        leading: Container(width: 50, height: 50,
          decoration: BoxDecoration(borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight)),
          child: Icon(icon, color: Colors.white)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Row(children: [const Icon(Icons.push_pin, size: 12, color: Colors.white38), const SizedBox(width: 4), Text(subtitle)]),
      );
}

enum SongListKind { liked, downloads }

/// Liked songs / Downloads presented as a playlist (gradient header + list).
class SongListScreen extends StatelessWidget {
  final SongListKind kind;
  const SongListScreen({super.key, required this.kind});
  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final player = context.read<Player>();
    final liked = kind == SongListKind.liked;
    final songs = liked ? lib.liked : lib.downloads;
    final title = liked ? 'Liked Songs' : 'Downloaded';
    final grad = liked ? [const Color(0xFFEC4899), const Color(0xFF7C3AED)] : [const Color(0xFF16A34A), const Color(0xFF0F766E)];
    return Scaffold(
      bottomNavigationBar: const MiniPlayer(),
      body: CustomScrollView(slivers: [
        SliverAppBar(
          expandedHeight: 230, pinned: true,
          flexibleSpace: FlexibleSpaceBar(
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
            background: Container(
              decoration: BoxDecoration(gradient: LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight, colors: grad)),
              child: Center(child: Icon(liked ? Icons.favorite : Icons.download_done, size: 84, color: Colors.white70)),
            ),
          ),
        ),
        SliverToBoxAdapter(child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Row(children: [
            Text('${songs.length} songs', style: const TextStyle(color: Colors.white60, fontWeight: FontWeight.w600)),
            const Spacer(),
            IconButton.filled(onPressed: songs.isEmpty ? null : () => player.playList(songs, 0), icon: const Icon(Icons.play_arrow)),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: songs.isEmpty ? null : () { final sh = songs.toList()..shuffle(); player.playList(sh, 0); },
              icon: const Icon(Icons.shuffle, size: 18), label: const Text('Shuffle')),
          ]),
        )),
        if (songs.isEmpty)
          SliverToBoxAdapter(child: Padding(padding: const EdgeInsets.all(40),
            child: Center(child: Text(liked ? 'Songs you like show up here.' : 'Your offline songs show up here.',
              style: const TextStyle(color: Colors.white38)))))
        else
          SliverList(delegate: SliverChildBuilderDelegate(
            (context, i) => SongTile(song: songs[i], queue: songs, index: i),
            childCount: songs.length)),
        const SliverToBoxAdapter(child: SizedBox(height: 20)),
      ]),
    );
  }
}

class PlaylistScreen extends StatelessWidget {
  final String id;
  const PlaylistScreen({super.key, required this.id});
  @override
  Widget build(BuildContext context) {
    final lib = context.watch<Library>();
    final player = context.read<Player>();
    final p = lib.playlists.firstWhere((x) => x.id == id, orElse: () => Playlist(id: '', name: 'Playlist'));
    return Scaffold(
      bottomNavigationBar: const MiniPlayer(),
      appBar: AppBar(title: Text(p.name), actions: [
        IconButton(icon: const Icon(Icons.edit), onPressed: () async {
          final name = await promptName(context, initial: p.name);
          if (name != null && name.isNotEmpty) lib.renamePlaylist(id, name);
        }),
        IconButton(icon: const Icon(Icons.delete_outline), onPressed: () { lib.deletePlaylist(id); Navigator.pop(context); }),
      ]),
      body: ListView(children: [
        Padding(padding: const EdgeInsets.all(16), child: FilledButton.icon(
          onPressed: p.songs.isEmpty ? null : () => player.playList(p.songs, 0),
          icon: const Icon(Icons.play_arrow), label: const Text('Play'))),
        ...p.songs.asMap().entries.map((e) => Dismissible(
              key: ValueKey(e.value.deezerId),
              direction: DismissDirection.endToStart,
              background: Container(color: Colors.red, alignment: Alignment.centerRight, padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete)),
              onDismissed: (_) => lib.removeFromPlaylist(id, e.value.deezerId),
              child: SongTile(song: e.value, queue: p.songs, index: e.key),
            )),
      ]),
    );
  }
}
