import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'deezer.dart';
import 'player.dart';
import 'store.dart';

/// Saves a song's audio to a local file for offline playback, streaming the
/// bytes through youtube_explode's client (a plain http GET gets rejected).
class Downloads {
  static Future<bool> download(Player player, Library lib, Song s) async {
    if (lib.isDownloaded(s.deezerId)) return true;
    try {
      final stream = await player.audioByteStream(s);
      if (stream == null) return false;
      final dir = await getApplicationDocumentsDirectory();
      final dlDir = Directory('${dir.path}/downloads');
      if (!await dlDir.exists()) await dlDir.create(recursive: true);
      final file = File('${dlDir.path}/${s.deezerId}.m4a');
      final sink = file.openWrite();
      await stream.pipe(sink);
      await sink.flush();
      await sink.close();
      if (await file.length() < 10000) { try { await file.delete(); } catch (_) {} return false; }
      lib.addDownload(s, file.path);
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Re-download a list of songs one by one, reporting progress.
  static Future<int> restoreAll(Player player, Library lib, List<Song> songs,
      {void Function(int done, int total, Song current)? onProgress,
      bool Function()? cancelled}) async {
    var ok = 0;
    for (var i = 0; i < songs.length; i++) {
      if (cancelled?.call() ?? false) break;
      onProgress?.call(i, songs.length, songs[i]);
      if (await download(player, lib, songs[i])) ok++;
    }
    return ok;
  }

  static Future<void> delete(Library lib, Song s) async {
    final p = lib.downloadPath(s.deezerId);
    if (p != null) { try { await File(p).delete(); } catch (_) {} }
    lib.removeDownload(s.deezerId);
  }
}
