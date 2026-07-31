import 'dart:math';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:share_plus/share_plus.dart';
import 'auth.dart';
import 'deezer.dart';
import 'player.dart';
import 'widgets.dart';

/// A playlist several people can add to. Lives in Firestore under `shared/{code}`
/// so anyone with the code can open it — no invitations to manage.
class SharedPlaylist {
  final String code;
  final String name;
  final String ownerName;
  final List<Song> songs;
  final List<String> members;
  SharedPlaylist({required this.code, required this.name, required this.ownerName,
    required this.songs, required this.members});

  factory SharedPlaylist.fromDoc(String code, Map<String, dynamic> d) => SharedPlaylist(
        code: code,
        name: (d['name'] ?? 'Shared playlist') as String,
        ownerName: (d['ownerName'] ?? '') as String,
        songs: (((d['songs'] as List?) ?? [])
            .map((e) => Song.fromJson((e as Map).cast<String, dynamic>()))).toList(),
        members: (((d['members'] as List?) ?? []).map((e) => '$e')).toList(),
      );
}

class Shared {
  static final _db = FirebaseFirestore.instance;
  static CollectionReference<Map<String, dynamic>> get _col => _db.collection('shared');

  /// Six characters, no confusable 0/O/1/I.
  static String _newCode() {
    const alphabet = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final r = Random.secure();
    return List.generate(6, (_) => alphabet[r.nextInt(alphabet.length)]).join();
  }

  static Future<String?> create(String name, String ownerName, String uid) async {
    try {
      final code = _newCode();
      await _col.doc(code).set({
        'name': name,
        'ownerName': ownerName,
        'ownerUid': uid,
        'songs': <dynamic>[],
        'members': [uid],
        'memberNames': [ownerName],
        'createdAt': FieldValue.serverTimestamp(),
      });
      return code;
    } catch (_) { return null; }
  }

  static Stream<SharedPlaylist?> watch(String code) => _col.doc(code).snapshots().map(
      (d) => d.exists ? SharedPlaylist.fromDoc(code, d.data()!) : null);

  static Future<SharedPlaylist?> get(String code) async {
    try {
      final d = await _col.doc(code.toUpperCase()).get();
      return d.exists ? SharedPlaylist.fromDoc(code.toUpperCase(), d.data()!) : null;
    } catch (_) { return null; }
  }

  static Future<bool> join(String code, String uid, String name) async {
    try {
      await _col.doc(code.toUpperCase()).update({
        'members': FieldValue.arrayUnion([uid]),
        'memberNames': FieldValue.arrayUnion([name]),
      });
      return true;
    } catch (_) { return false; }
  }

  static Future<void> addSong(String code, Song s, String byName) async {
    await _col.doc(code).update({
      'songs': FieldValue.arrayUnion([{...s.toJson(), 'addedBy': byName}]),
    });
  }

  static Future<void> removeSong(String code, Song s) async {
    final d = await _col.doc(code).get();
    final songs = ((d.data()?['songs'] as List?) ?? []).toList();
    songs.removeWhere((e) => (e as Map)['deezerId'] == s.deezerId);
    await _col.doc(code).update({'songs': songs});
  }
}

/// Screen for one shared playlist — live, so additions appear as they happen.
class SharedPlaylistScreen extends StatelessWidget {
  final String code;
  const SharedPlaylistScreen({super.key, required this.code});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<SharedPlaylist?>(
      stream: Shared.watch(code),
      builder: (context, snap) {
        final p = snap.data;
        if (snap.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
        }
        if (p == null) {
          return Scaffold(appBar: AppBar(),
            body: const Center(child: Text('This playlist no longer exists',
              style: TextStyle(color: Colors.white54))));
        }
        return Scaffold(
          appBar: AppBar(
            title: Text(p.name),
            actions: [
              IconButton(
                icon: const Icon(Icons.ios_share),
                tooltip: 'Share code',
                onPressed: () => Share.share(
                  'Join my Sound Circle playlist "${p.name}"\n\nCode: ${p.code}\n\n'
                  'Open Sound Circle → Library → Shared → Join',
                ),
              ),
            ],
          ),
          body: ListView(children: [
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                gradient: LinearGradient(colors: gradientFor(p.name),
                  begin: Alignment.topLeft, end: Alignment.bottomRight)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  const Icon(Icons.group, color: Colors.white),
                  const SizedBox(width: 8),
                  Text('${p.members.length} ${p.members.length == 1 ? 'person' : 'people'}',
                    style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white)),
                  const Spacer(),
                  Text('${p.songs.length} songs', style: const TextStyle(color: Colors.white70)),
                ]),
                const SizedBox(height: 12),
                Row(children: [
                  const Text('CODE  ', style: TextStyle(fontSize: 11, color: Colors.white70, letterSpacing: 1)),
                  SelectableText(p.code, style: const TextStyle(
                    fontSize: 22, fontWeight: FontWeight.w900, letterSpacing: 4, color: Colors.white)),
                ]),
              ]),
            ),
            if (p.songs.isNotEmpty)
              Padding(padding: const EdgeInsets.symmetric(horizontal: 16),
                child: FilledButton.icon(
                  onPressed: () => context.read<Player>().playList(p.songs, 0),
                  icon: const Icon(Icons.play_arrow), label: const Text('Play'))),
            const SizedBox(height: 8),
            if (p.songs.isEmpty)
              const Padding(padding: EdgeInsets.all(30),
                child: Center(child: Text('No songs yet.\nAdd some from any song\'s menu.',
                  textAlign: TextAlign.center, style: TextStyle(color: Colors.white38))))
            else
              ...p.songs.asMap().entries.map((e) => Dismissible(
                key: ValueKey('sh${e.value.deezerId}'),
                direction: DismissDirection.endToStart,
                background: Container(color: Colors.red, alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20), child: const Icon(Icons.delete)),
                onDismissed: (_) => Shared.removeSong(p.code, e.value),
                child: SongTile(song: e.value, queue: p.songs, index: e.key),
              )),
            const SizedBox(height: 20),
          ]),
        );
      },
    );
  }
}

/// Create or join a shared playlist.
Future<void> showSharedSheet(BuildContext context) async {
  final auth = context.read<Auth>();
  if (auth.uid == null) {
    toast(context, 'Sign in to use shared playlists', icon: Icons.person_outline);
    return;
  }
  final nameCtrl = TextEditingController();
  final codeCtrl = TextEditingController();
  String? error;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF14141f),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheet) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
      child: SafeArea(child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            const Icon(Icons.group_add),
            const SizedBox(width: 10),
            const Text('Shared playlist', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
            const Spacer(),
            IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(sheetCtx)),
          ]),
          const Text('Everyone with the code can add songs.',
            style: TextStyle(color: Colors.white54, fontSize: 13)),
          const SizedBox(height: 18),

          const Text('Create one', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(controller: nameCtrl, decoration: const InputDecoration(
              hintText: 'Playlist name', filled: true, fillColor: Color(0xFF1c1c28),
              border: OutlineInputBorder(borderSide: BorderSide.none)))),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: () async {
                if (nameCtrl.text.trim().isEmpty) return;
                final code = await Shared.create(
                  nameCtrl.text.trim(), auth.name ?? 'Someone', auth.uid!);
                if (!sheetCtx.mounted) return;
                Navigator.pop(sheetCtx);
                if (code == null) { toast(context, 'Could not create', icon: Icons.error_outline); return; }
                if (context.mounted) {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => SharedPlaylistScreen(code: code)));
                }
              },
              child: const Text('Create')),
          ]),

          const Divider(height: 34),
          const Text('Join with a code', style: TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(child: TextField(
              controller: codeCtrl,
              textCapitalization: TextCapitalization.characters,
              decoration: const InputDecoration(
                hintText: 'e.g. K4M2XP', filled: true, fillColor: Color(0xFF1c1c28),
                border: OutlineInputBorder(borderSide: BorderSide.none)))),
            const SizedBox(width: 10),
            FilledButton(
              onPressed: () async {
                final code = codeCtrl.text.trim().toUpperCase();
                if (code.isEmpty) return;
                final found = await Shared.get(code);
                if (found == null) { setSheet(() => error = "No playlist with that code"); return; }
                await Shared.join(code, auth.uid!, auth.name ?? 'Someone');
                if (!sheetCtx.mounted) return;
                Navigator.pop(sheetCtx);
                if (context.mounted) {
                  Navigator.push(context, MaterialPageRoute(
                    builder: (_) => SharedPlaylistScreen(code: code)));
                }
              },
              child: const Text('Join')),
          ]),
          if (error != null) Padding(padding: const EdgeInsets.only(top: 10),
            child: Text(error!, style: const TextStyle(color: Colors.redAccent))),
        ]),
      )),
    )),
  );
}

/// Pick one of the shared playlists you're in, to add a song to.
Future<void> addToShared(BuildContext context, Song song) async {
  final auth = context.read<Auth>();
  if (auth.uid == null) { toast(context, 'Sign in first', icon: Icons.person_outline); return; }
  final snap = await FirebaseFirestore.instance.collection('shared')
      .where('members', arrayContains: auth.uid).get();
  if (!context.mounted) return;
  if (snap.docs.isEmpty) { showSharedSheet(context); return; }

  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF14141f),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheetCtx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [
      const Padding(padding: EdgeInsets.fromLTRB(20, 16, 20, 6),
        child: Row(children: [Icon(Icons.group), SizedBox(width: 10),
          Text('Add to shared playlist', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800))])),
      ...snap.docs.map((d) {
        final p = SharedPlaylist.fromDoc(d.id, d.data());
        return ListTile(
          leading: Container(width: 44, height: 44,
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(8),
              gradient: LinearGradient(colors: gradientFor(p.name))),
            child: const Icon(Icons.group, size: 20)),
          title: Text(p.name),
          subtitle: Text('${p.songs.length} songs · ${p.members.length} people'),
          onTap: () async {
            Navigator.pop(sheetCtx);
            await Shared.addSong(p.code, song, auth.name ?? 'Someone');
            if (context.mounted) toast(context, 'Added to ${p.name}', cover: song.cover);
          },
        );
      }),
      const SizedBox(height: 10),
    ])),
  );
}
