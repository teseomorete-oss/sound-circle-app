import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'auth.dart';
import 'remote_config.dart';
import 'widgets.dart';

/// Lets anyone send feedback or an idea straight to the Mac control panel.
Future<void> showFeedbackSheet(BuildContext context) async {
  final ctrl = TextEditingController();
  String kind = 'idea';
  bool sending = false;

  await showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: const Color(0xFF14141f),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    builder: (sheetCtx) => StatefulBuilder(builder: (sheetCtx, setSheet) {
      Future<void> send() async {
        final text = ctrl.text.trim();
        if (text.isEmpty || sending) return;
        setSheet(() => sending = true);
        final auth = context.read<Auth>();
        try {
          await FirebaseFirestore.instance.collection('feedback').add({
            'type': kind,
            'text': text,
            'name': auth.name ?? 'Guest',
            'email': auth.email ?? '',
            'uid': auth.uid ?? '',
            'version': RemoteConfig.currentVersion,
            'build': RemoteConfig.currentBuild,
            'createdAt': FieldValue.serverTimestamp(),
            'read': false,
          });
          if (sheetCtx.mounted) Navigator.pop(sheetCtx);
          if (context.mounted) toast(context, 'Thanks — sent!', icon: Icons.favorite);
        } catch (_) {
          setSheet(() => sending = false);
          if (sheetCtx.mounted) {
            ScaffoldMessenger.of(sheetCtx).hideCurrentSnackBar();
          }
          if (context.mounted) toast(context, "Couldn't send — check connection", icon: Icons.error_outline);
        }
      }

      return Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(sheetCtx).viewInsets.bottom),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.lightbulb_outline),
                const SizedBox(width: 10),
                const Text('Feedback & ideas', style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
                const Spacer(),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(sheetCtx)),
              ]),
              const Text('Goes straight to the developer.',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
              const SizedBox(height: 14),
              Wrap(spacing: 8, children: [
                for (final k in const [
                  ('idea', 'Idea', Icons.lightbulb_outline),
                  ('bug', 'Something broken', Icons.bug_report_outlined),
                  ('other', 'Other', Icons.chat_bubble_outline),
                ])
                  ChoiceChip(
                    label: Row(mainAxisSize: MainAxisSize.min, children: [
                      Icon(k.$3, size: 16), const SizedBox(width: 6), Text(k.$2)]),
                    selected: kind == k.$1,
                    onSelected: (_) => setSheet(() => kind = k.$1),
                  ),
              ]),
              const SizedBox(height: 14),
              TextField(
                controller: ctrl,
                maxLines: 5,
                maxLength: 1000,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'What would make Sound Circle better?',
                  filled: true, fillColor: Color(0xFF1c1c28),
                  border: OutlineInputBorder(borderSide: BorderSide.none)),
              ),
              const SizedBox(height: 6),
              SizedBox(width: double.infinity, child: FilledButton.icon(
                onPressed: sending ? null : send,
                icon: sending
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.send),
                label: Text(sending ? 'Sending…' : 'Send'),
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14)),
              )),
            ]),
          ),
        ),
      );
    }),
  );
}
