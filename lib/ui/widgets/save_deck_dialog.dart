import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/deck_library_loader.dart';
import '../../models/deck_config.dart';
import '../../models/game_definition.dart';

/// Validates a user-typed deck name as a filesystem file name (minus the
/// `.json` extension). Whether `<gameFolder>/<name>.json` already exists is
/// checked separately (async) by the caller -- mirrors
/// `game_definition_editor_entry_screen.dart`'s `_validateGameId`.
String? _validateDeckName(String name) {
  if (name.isEmpty) return 'Enter a deck name.';
  if (name == '.' || name == '..') return 'Invalid name.';
  const reserved = r'/\:*?"<>|';
  if (name.split('').any(reserved.contains)) {
    return 'Name cannot contain: / \\ : * ? " < > |';
  }
  return null;
}

/// Modal name prompt for saving a deck under `<libraryRoot>/<game.id>/`,
/// alongside a list of that game's already-saved decks (loaded the same way
/// `_DeckLibraryPickerDialog` in `deck_editor_screen.dart` loads them) so the
/// player can tap one to reuse its name instead of retyping it. The name
/// field always starts blank. Validates synchronously via
/// [_validateDeckName] on every submit attempt, then asynchronously checks
/// whether `<libraryRoot>/<game.id>/<name>.json` already exists -- if so,
/// flips into an inline overwrite-confirmation state rather than blocking
/// outright.
class _SaveDeckDialog extends StatefulWidget {
  const _SaveDeckDialog({required this.libraryRoot, required this.game});

  final String libraryRoot;
  final GameDefinition game;

  @override
  State<_SaveDeckDialog> createState() => _SaveDeckDialogState();
}

class _SaveDeckDialogState extends State<_SaveDeckDialog> {
  final _nameController = TextEditingController();
  final _loader = DeckLibraryLoader();
  DeckLibraryScanResult? _scan;
  String? _error;
  bool _checking = false;
  bool _confirmingOverwrite = false;
  String _pendingName = '';

  @override
  void initState() {
    super.initState();
    _loader.loadDecksForGame(widget.libraryRoot, widget.game).then((scan) {
      if (mounted) setState(() => _scan = scan);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final syncError = _validateDeckName(name);
    if (syncError != null) {
      setState(() => _error = syncError);
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    final exists = await File(
      '${widget.libraryRoot}${Platform.pathSeparator}${widget.game.id}${Platform.pathSeparator}$name.json',
    ).exists();
    if (exists) {
      // Same reasoning as below -- this swaps the dialog's content from the
      // name TextField to the plain overwrite-confirmation text, tearing
      // the (still-focused) field down mid-route.
      if (mounted) FocusScope.of(context).unfocus();
      setState(() {
        _checking = false;
        _confirmingOverwrite = true;
        _pendingName = name;
      });
      return;
    }
    if (!mounted) return;
    // Drop focus before popping -- the name field is `autofocus`, and
    // popping this route while it (or the framework's own focus machinery)
    // still has it focused can tear down the Focus/FocusScope
    // InheritedElement while something still depends on it, tripping a
    // `_dependents.isEmpty` assertion in debug builds.
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    if (_confirmingOverwrite) {
      return AlertDialog(
        title: const Text('Overwrite Deck?'),
        content: Text('A deck named "$_pendingName" already exists in the library. Overwrite it?'),
        actions: [
          TextButton(
            onPressed: () => setState(() => _confirmingOverwrite = false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              // Same `_dependents.isEmpty` hazard as `_submit()` above --
              // tapping this button focuses it, so drop focus before
              // popping the route out from under it.
              FocusScope.of(context).unfocus();
              Navigator.of(context).pop(_pendingName);
            },
            child: const Text('Overwrite'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Save Deck'),
      content: SizedBox(
        width: 360,
        height: 400,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameController,
              autofocus: true,
              enabled: !_checking,
              decoration: InputDecoration(labelText: 'Deck Name', errorText: _error),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Existing decks -- tap to reuse a name',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
              ),
            ),
            const Divider(),
            Expanded(
              child: _scan == null
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _scan!.entries.isEmpty
                      ? Center(
                          child: Text(
                            'No decks found for ${widget.game.name}.',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        )
                      : ListView(
                          children: [
                            for (final entry in _scan!.entries)
                              ListTile(
                                dense: true,
                                title: Text(entry.displayName),
                                trailing: Text('${entry.cardCount} card(s)'),
                                onTap: () {
                                  _nameController.text = entry.displayName;
                                  setState(() => _error = null);
                                },
                              ),
                          ],
                        ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _checking ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(onPressed: _checking ? null : _submit, child: const Text('Save')),
      ],
    );
  }
}

/// Shows [_SaveDeckDialog] (name entry, tap-existing-name-to-reuse, overwrite
/// confirmation) and, if the player didn't cancel, writes
/// `<libraryRoot>/<game.id>/<name>.json` via `deckConfig.toJson()` -- the
/// same pipeline `DeckEditorScreen._saveDeck()` used to inline, now shared
/// with `DeckWidget`'s own Save button. Shows a "Saved to ..." SnackBar on
/// success. Returns whether a save actually happened (false if cancelled).
Future<bool> promptSaveDeckToLibrary({
  required BuildContext context,
  required String libraryRoot,
  required GameDefinition game,
  required DeckConfig deckConfig,
}) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _SaveDeckDialog(libraryRoot: libraryRoot, game: game),
  );
  if (name == null || !context.mounted) return false;
  final folderPath = '$libraryRoot${Platform.pathSeparator}${game.id}';
  await Directory(folderPath).create(recursive: true);
  final file = File('$folderPath${Platform.pathSeparator}$name.json');
  await file.writeAsString(jsonEncode(deckConfig.toJson()));
  if (!context.mounted) return false;
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to ${file.path}')));
  return true;
}
