import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../data/game_loader.dart';
import '../../models/game_definition.dart';

/// Lets the user pick the bundled standard deck or browse a folder on disk
/// for custom game JSON files, then calls [onGameChosen] -- shared by
/// `GameSelectScreen` (host flow, proceeds into `DeckBuildScreen`) and
/// `DeckEditorGameSelectScreen` (proceeds into `DeckEditorScreen`), since
/// picking a game has no dependency on what happens with it afterward.
class GamePicker extends StatefulWidget {
  const GamePicker({super.key, required this.onGameChosen});

  final ValueChanged<GameDefinition> onGameChosen;

  @override
  State<GamePicker> createState() => _GamePickerState();
}

class _GamePickerState extends State<GamePicker> {
  final GameLoader _loader = GameLoader();
  bool _browsing = false;
  String? _browseError;
  List<GameDefinition>? _folderGames;

  Future<void> _browseForFolder() async {
    setState(() {
      _browsing = true;
      _browseError = null;
      _folderGames = null;
    });
    final path = await getDirectoryPath();
    if (!mounted) return;
    if (path == null) {
      setState(() => _browsing = false);
      return;
    }
    final games = await _loader.loadFromFolder(path);
    if (!mounted) return;
    setState(() {
      _browsing = false;
      _folderGames = games;
      if (games.isEmpty) _browseError = 'No valid game JSON files found in that folder.';
    });
  }

  Future<void> _chooseStandardDeck() async {
    final game = await _loader.loadStandardDeck();
    if (!mounted) return;
    widget.onGameChosen(game);
  }

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            FilledButton(
              onPressed: _chooseStandardDeck,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Standard 52-Card Deck'),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: _browsing ? null : _browseForFolder,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: _browsing
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Browse for Custom Game Folder...'),
              ),
            ),
            if (_browseError != null) ...[
              const SizedBox(height: 12),
              Text(_browseError!, style: const TextStyle(color: Colors.red)),
            ],
            if (_folderGames != null && _folderGames!.isNotEmpty) ...[
              const SizedBox(height: 24),
              const Text('Found games:', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              for (final game in _folderGames!)
                Card(
                  child: ListTile(
                    title: Text(game.name),
                    subtitle: Text('${game.cards.length} card(s)'),
                    onTap: () => widget.onGameChosen(game),
                  ),
                ),
            ],
          ],
        ),
      ),
    );
  }
}
