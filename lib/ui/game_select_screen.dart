import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/game_loader.dart';
import '../models/game_definition.dart';
import '../networking/host_server.dart';
import 'deck_build_screen.dart';

/// Host-only screen (M5): pick the bundled standard deck, or browse a folder
/// on disk for custom game JSON files, then proceed to [DeckBuildScreen].
/// The [hostServer]/[hostPlayerId] are only threaded through to the eventual
/// [HostGameScreen] -- this screen doesn't touch the connection itself.
class GameSelectScreen extends StatefulWidget {
  const GameSelectScreen({super.key, required this.hostServer, required this.hostPlayerId});

  final HostServer hostServer;
  final String hostPlayerId;

  @override
  State<GameSelectScreen> createState() => _GameSelectScreenState();
}

class _GameSelectScreenState extends State<GameSelectScreen> {
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

  void _chooseGame(GameDefinition game) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DeckBuildScreen(
        hostServer: widget.hostServer,
        hostPlayerId: widget.hostPlayerId,
        game: game,
      ),
    ));
  }

  Future<void> _chooseStandardDeck() async {
    final game = await _loader.loadStandardDeck();
    if (!mounted) return;
    _chooseGame(game);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a Game')),
      body: Center(
        child: ConstrainedBox(
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
                        onTap: () => _chooseGame(game),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
