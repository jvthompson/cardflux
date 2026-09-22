import 'package:flutter/material.dart';

/// Confirms with the user before installing an update -- same
/// `showDialog<bool>` + `AlertDialog` shape as `showDiscordJoinPrompt`
/// (discord_join_prompt_dialog.dart:20-40).
Future<bool?> showUpdateConfirmDialog(BuildContext context, {required String latestTag}) {
  return showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Update Available'),
      content: Text('Version $latestTag is available. Would you like to update now?'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Later')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Update')),
      ],
    ),
  );
}
