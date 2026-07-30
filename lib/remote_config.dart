import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Version + announcement banner controlled remotely (Firestore `config/app`),
/// so a new release can be announced without shipping anything.
///
/// Document shape — this is exactly what the Mac control panel writes:
///   latestBuild   (int)     build number of the newest release
///   latestVersion (string)  e.g. "1.8.0"
///   message       (string)  free text shown in the dialog
///   mandatory     (bool)    true = no skip button
///   url           (string)  APK download link
///   enabled       (bool)    master switch
class UpdateInfo {
  final int latestBuild;
  final String latestVersion;
  final String message;
  final bool mandatory;
  final String url;
  UpdateInfo({required this.latestBuild, required this.latestVersion,
    required this.message, required this.mandatory, required this.url});
}

class RemoteConfig {
  static int currentBuild = 0;
  static String currentVersion = '';

  static Future<void> loadCurrent() async {
    try {
      final info = await PackageInfo.fromPlatform();
      currentVersion = info.version;
      currentBuild = int.tryParse(info.buildNumber) ?? 0;
    } catch (_) {}
  }

  /// Returns update info only when a newer build is actually available.
  static Future<UpdateInfo?> check() async {
    try {
      final doc = await FirebaseFirestore.instance.collection('config').doc('app').get();
      final d = doc.data();
      if (d == null || d['enabled'] == false) return null;
      final latest = (d['latestBuild'] as num?)?.toInt() ?? 0;
      if (latest <= currentBuild) return null;
      return UpdateInfo(
        latestBuild: latest,
        latestVersion: (d['latestVersion'] ?? '') as String,
        message: (d['message'] ?? 'A new version of Sound Circle is available.') as String,
        mandatory: (d['mandatory'] as bool?) ?? false,
        url: (d['url'] ?? '') as String,
      );
    } catch (_) { return null; }
  }

  /// Anonymous usage ping so the control panel can show how many people use the
  /// app. Stores only a per-account last-seen + app version — no personal data.
  static Future<void> ping(String? uid) async {
    if (uid == null) return;
    try {
      await FirebaseFirestore.instance.collection('usage').doc(uid).set({
        'lastSeen': FieldValue.serverTimestamp(),
        'version': currentVersion,
        'build': currentBuild,
        'platform': defaultTargetPlatformName,
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  static String get defaultTargetPlatformName {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android: return 'android';
      case TargetPlatform.iOS: return 'ios';
      case TargetPlatform.macOS: return 'macos';
      default: return 'other';
    }
  }
}

/// The update dialog. Skippable unless the panel marked it mandatory.
Future<void> showUpdateDialog(BuildContext context, UpdateInfo u) async {
  await showDialog(
    context: context,
    barrierDismissible: !u.mandatory,
    builder: (_) => PopScope(
      canPop: !u.mandatory,
      child: AlertDialog(
        backgroundColor: const Color(0xFF1a1a2b),
        icon: const Icon(Icons.system_update, size: 32),
        title: Text(u.latestVersion.isEmpty ? 'Update available' : 'Update to ${u.latestVersion}'),
        content: Text(u.message, style: const TextStyle(color: Colors.white70)),
        actions: [
          if (!u.mandatory)
            TextButton(onPressed: () => Navigator.pop(context), child: const Text('Later')),
          FilledButton(
            onPressed: () async {
              if (u.url.isNotEmpty) {
                await launchUrl(Uri.parse(u.url), mode: LaunchMode.externalApplication);
              }
              if (!u.mandatory && context.mounted) Navigator.pop(context);
            },
            child: const Text('Download'),
          ),
        ],
      ),
    ),
  );
}
