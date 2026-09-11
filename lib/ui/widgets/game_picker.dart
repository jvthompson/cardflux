import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../data/game_loader.dart';
import '../../data/games_directory_settings.dart';
import '../../models/game_definition.dart';

/// Lets the user pick a game: the bundled Standard 52-Card Deck (always
/// available, no setup needed -- the same guaranteed default Practice Mode
/// uses) plus whatever's in their configured games directory, remembered
/// across launches via [GamesDirectorySettings] and rescanned on open (or on
/// demand via Refresh) so a game folder dropped in after the app was built
/// shows up with no rebuild -- then calls [onGameChosen]. Shared by
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
  final GamesDirectorySettings _settings = GamesDirectorySettings();

  GameDefinition? _standardDeck;
  String? _directoryPath;
  List<GameDefinition>? _directoryGames;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final standardDeck = await _loader.loadStandardDeck();
    final path = await _settings.getPath();
    if (!mounted) return;
    setState(() {
      _standardDeck = standardDeck;
      _directoryPath = path;
    });
    if (path != null) await _refresh(path);
  }

  Future<void> _refresh(String path) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    List<GameDefinition> games = const [];
    String? error;
    try {
      games = await _loader.loadGamesFromDirectory(path);
      games.sort((a, b) => a.name.compareTo(b.name));
      if (games.isEmpty) error = 'No valid games found in that folder.';
    } catch (e) {
      // Never leave `_busy` stuck true on a bad/inaccessible folder (a
      // permission error, a broken symlink, a cloud-storage placeholder
      // that fails to stat, etc.) -- that would permanently disable both
      // Refresh and Change Folder..., leaving the user unable to pick a
      // different folder to recover.
      error = 'Could not read that folder: $e';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _directoryGames = games;
      _error = error;
    });
  }

  Future<void> _chooseDirectory() async {
    final path = await getDirectoryPath();
    if (path == null || !mounted) return;
    await _settings.setPath(path);
    if (!mounted) return;
    setState(() => _directoryPath = path);
    await _refresh(path);
  }

  @override
  Widget build(BuildContext context) {
    // Skip any directory game that happens to share an id with the bundled
    // standard deck (e.g. a stray copy of it saved into that folder) so it
    // never appears twice.
    final directoryGames = (_directoryGames ?? const <GameDefinition>[])
        .where((g) => g.id != _standardDeck?.id)
        .toList();

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Games', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            if (_standardDeck == null)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else
              Card(
                child: ListTile(
                  title: Text(_standardDeck!.name),
                  subtitle: Text('${_standardDeck!.cards.length} card(s)'),
                  onTap: () => widget.onGameChosen(_standardDeck!),
                ),
              ),
            const SizedBox(height: 16),
            if (_directoryPath == null) ...[
              const Text(
                'Choose a folder to find more games -- one subfolder per game '
                '(each with its own game JSON).',
                style: TextStyle(color: Colors.black45),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: _chooseDirectory,
                child: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text('Choose Games Folder...'),
                ),
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    child: Text(
                      _directoryPath!,
                      style: const TextStyle(
                        color: Colors.black45,
                        fontSize: 12,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  IconButton(
                    tooltip: 'Refresh',
                    icon: const Icon(Icons.refresh),
                    onPressed: _busy ? null : () => _refresh(_directoryPath!),
                  ),
                  IconButton(
                    tooltip: 'Change Folder...',
                    icon: const Icon(Icons.folder_open),
                    onPressed: _busy ? null : _chooseDirectory,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Center(
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                )
              else if (_error != null)
                Text(_error!, style: const TextStyle(color: Colors.red))
              else
                for (final game in directoryGames)
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
