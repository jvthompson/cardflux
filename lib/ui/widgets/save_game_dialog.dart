import 'package:flutter/material.dart';

import '../../data/save_game_file_ops.dart';

/// Validates a user-typed save name as a filesystem file name (minus the
/// `.json` extension) -- same rules as the Deck Editor's own
/// `_validateDeckName`, duplicated here rather than shared since it's one
/// small top-level function used by two otherwise-unrelated features.
String? validateSaveGameName(String name) {
  if (name.isEmpty) return 'Enter a name.';
  if (name == '.' || name == '..') return 'Invalid name.';
  const reserved = r'/\:*?"<>|';
  if (name.split('').any(reserved.contains)) {
    return 'Name cannot contain: / \\ : * ? " < > |';
  }
  return null;
}

/// Modal name prompt for saving the current game state under
/// `<gameFolderPath>/savegames/`, alongside a list of that game's
/// already-saved games (tap to reuse a name) -- mirrors
/// `deck_editor_screen.dart`'s `_SaveDeckDialog` almost exactly. Only
/// resolves the chosen name; the caller does the actual write (via
/// [SaveGameFileOps]), same division of labor as the deck-save flow.
class SaveGameDialog extends StatefulWidget {
  const SaveGameDialog({super.key, required this.gameFolderPath, required this.gameName});

  final String gameFolderPath;
  final String gameName;

  @override
  State<SaveGameDialog> createState() => _SaveGameDialogState();
}

class _SaveGameDialogState extends State<SaveGameDialog> {
  final _nameController = TextEditingController();
  final _fileOps = SaveGameFileOps();
  List<SaveGameLibraryEntry>? _existing;
  String? _error;
  bool _checking = false;
  bool _confirmingOverwrite = false;
  String _pendingName = '';

  @override
  void initState() {
    super.initState();
    _fileOps.listSaveGames(widget.gameFolderPath).then((entries) {
      if (mounted) setState(() => _existing = entries);
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final name = _nameController.text.trim();
    final syncError = validateSaveGameName(name);
    if (syncError != null) {
      setState(() => _error = syncError);
      return;
    }
    setState(() {
      _checking = true;
      _error = null;
    });
    final exists = await _fileOps.saveExists(widget.gameFolderPath, name);
    if (exists) {
      if (mounted) FocusScope.of(context).unfocus();
      setState(() {
        _checking = false;
        _confirmingOverwrite = true;
        _pendingName = name;
      });
      return;
    }
    if (!mounted) return;
    FocusScope.of(context).unfocus();
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    if (_confirmingOverwrite) {
      return AlertDialog(
        title: const Text('Overwrite Save?'),
        content: Text('A save named "$_pendingName" already exists for ${widget.gameName}. Overwrite it?'),
        actions: [
          TextButton(
            onPressed: () => setState(() => _confirmingOverwrite = false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              FocusScope.of(context).unfocus();
              Navigator.of(context).pop(_pendingName);
            },
            child: const Text('Overwrite'),
          ),
        ],
      );
    }

    return AlertDialog(
      title: const Text('Save Game'),
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
              decoration: InputDecoration(labelText: 'Save Name', errorText: _error),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Existing saves -- tap to reuse a name',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
              ),
            ),
            const Divider(),
            Expanded(
              child: _existing == null
                  ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                  : _existing!.isEmpty
                      ? Center(
                          child: Text(
                            'No saved games yet for ${widget.gameName}.',
                            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                          ),
                        )
                      : ListView(
                          children: [
                            for (final entry in _existing!)
                              ListTile(
                                dense: true,
                                title: Text(entry.displayName),
                                trailing: Text('${entry.playerCount} player(s)'),
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
