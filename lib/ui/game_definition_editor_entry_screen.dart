import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/game_definition_file_ops.dart';
import '../models/game_definition.dart';
import 'game_definition_editor_screen.dart';

const List<XTypeGroup> _gameDefFileTypes = [
  XTypeGroup(label: 'Game Definition', extensions: ['json']),
];

/// A folder path (containing, or about to contain, `gamedef.json`) plus the
/// [GameDefinition] to start editing there. Loaded WITHOUT resolving image
/// paths -- unlike `GameLoader`/`GamePicker`, which rewrite bare filenames
/// to absolute paths for rendering. The editor needs the original bare
/// filenames so saving writes them back out unchanged.
class NewOrOpenGameResult {
  const NewOrOpenGameResult({required this.folderPath, required this.game});

  final String folderPath;
  final GameDefinition game;
}

Future<NewOrOpenGameResult> _loadGameDefFile(String jsonPath, String folderPath) async {
  final raw = await File(jsonPath).readAsString();
  return NewOrOpenGameResult(
    folderPath: folderPath,
    game: GameDefinition.fromJson(jsonDecode(raw) as Map<String, dynamic>),
  );
}

/// Lets the user pick or create a folder for a brand-new game definition.
/// If that folder already has a `gamedef.json`, offers to open it instead
/// of silently starting a blank definition on top of it.
Future<NewOrOpenGameResult?> pickNewGameDefinitionFolder(BuildContext context) async {
  final folderPath = await getDirectoryPath();
  if (folderPath == null || !context.mounted) return null;

  final existing = await GameDefinitionFileOps().findGameDefFile(folderPath);
  if (existing != null) {
    if (!context.mounted) return null;
    final shouldOpen = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Game Definition Already Exists'),
        content: const Text('This folder already has a gamedef.json. Open it instead?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Open It')),
        ],
      ),
    );
    if (shouldOpen != true || !context.mounted) return null;
    return _loadGameDefFile(existing, folderPath);
  }

  final id = deriveIdFromFolderPath(folderPath);
  return NewOrOpenGameResult(folderPath: folderPath, game: GameDefinition(id: id, name: id, cards: const []));
}

/// Lets the user open an existing game definition JSON file directly.
/// `file_selector` can only filter by extension, not the exact filename
/// `gamedef.json` -- the same limitation `DeckEditorScreen._openDeck` has
/// for deck files -- so a bad/unrelated `.json` is caught by the try/catch
/// below instead.
Future<NewOrOpenGameResult?> pickExistingGameDefinitionFile(BuildContext context) async {
  final file = await openFile(acceptedTypeGroups: _gameDefFileTypes);
  if (file == null || !context.mounted) return null;
  try {
    return await _loadGameDefFile(file.path, File(file.path).parent.path);
  } catch (_) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('That file is not a valid game definition.')),
    );
    return null;
  }
}

/// Entry point for the Game Definition Editor: create a brand-new game
/// definition, or open an existing `gamedef.json`, then proceed into
/// [GameDefinitionEditorScreen].
class GameDefinitionEditorEntryScreen extends StatelessWidget {
  const GameDefinitionEditorEntryScreen({super.key});

  Future<void> _newGame(BuildContext context) async {
    final result = await pickNewGameDefinitionFolder(context);
    if (result == null || !context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GameDefinitionEditorScreen(folderPath: result.folderPath, initialGame: result.game),
    ));
  }

  Future<void> _openGame(BuildContext context) async {
    final result = await pickExistingGameDefinitionFile(context);
    if (result == null || !context.mounted) return;
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GameDefinitionEditorScreen(folderPath: result.folderPath, initialGame: result.game),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Game Definition Editor')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                FilledButton(
                  onPressed: () => _newGame(context),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('New Game Definition...'),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => _openGame(context),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Open Existing...'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
