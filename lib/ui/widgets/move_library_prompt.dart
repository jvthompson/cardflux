import 'package:flutter/material.dart';

import '../../data/game_definition_file_ops.dart' show isSamePath;
import '../../data/library_folder_migration.dart';

/// Called right after the user has picked [newRoot] as a Games/Deck Library
/// folder (via the OS folder picker) but before that choice is saved -- asks
/// whether to bring [oldRoot]'s existing contents along, and moves them if
/// so. A no-op (no dialog shown) when [oldRoot] and [newRoot] are the same
/// folder, or when [oldRoot] doesn't exist or has nothing in it -- there's
/// nothing to offer to move in either case. [whatLabel] names what's being
/// moved for the dialog text, e.g. `'game'` or `'deck'`.
Future<void> maybeMoveLibraryFolder(
  BuildContext context, {
  required String oldRoot,
  required String newRoot,
  required String whatLabel,
}) async {
  if (isSamePath(oldRoot, newRoot)) return;
  if (!await directoryHasEntries(oldRoot)) return;
  if (!context.mounted) return;
  final shouldMove = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Move Existing Files?'),
      content: Text('Move your existing $whatLabel library files from\n"$oldRoot"\nto\n"$newRoot"?'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Don't Move")),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Move')),
      ],
    ),
  );
  if (shouldMove == true) await moveDirectoryContents(fromPath: oldRoot, toPath: newRoot);
}
