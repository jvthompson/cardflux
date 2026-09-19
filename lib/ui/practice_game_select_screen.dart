import 'package:flutter/material.dart';

import '../models/color_palette.dart';
import '../models/game_definition.dart';
import '../models/player.dart';
import 'load_saved_game_screen.dart';
import 'practice_game_screen.dart';
import 'practice_load_decks_screen.dart';
import 'widgets/game_picker.dart';

/// Pick a game from the library (or the bundled Standard Deck) for a local
/// [playerCount]-seat practice session -- mirrors [GameSelectScreen], minus
/// any networking. Builds the simulated seat roster once a game is chosen:
/// seat 1 is the real player's own profile, seats 2-4 (if any) get an
/// auto-generated name and the next unclaimed [boardWidgetColorPalette]
/// color, same clash-avoidance idea `HostServer` uses for joining clients.
class PracticeGameSelectScreen extends StatelessWidget {
  const PracticeGameSelectScreen({
    super.key,
    required this.playerCount,
    required this.localPlayerName,
    required this.localPlayerColor,
    this.localAvatarPath,
  });

  final int playerCount;
  final String localPlayerName;
  final int localPlayerColor;
  final String? localAvatarPath;

  List<PlayerInfo> _buildPlayers() {
    final players = <PlayerInfo>[
      PlayerInfo(id: 'seat1', name: localPlayerName, role: PlayerRole.host, color: localPlayerColor),
    ];
    final usedColors = {localPlayerColor};
    for (var seat = 2; seat <= playerCount; seat++) {
      final color = boardWidgetColorPalette.firstWhere(
        (c) => !usedColors.contains(c),
        orElse: () => boardWidgetColorPalette.first,
      );
      usedColors.add(color);
      players.add(PlayerInfo(id: 'seat$seat', name: 'Player $seat', role: PlayerRole.host, color: color));
    }
    return players;
  }

  void _chooseGame(BuildContext context, GameDefinition game) {
    final players = _buildPlayers();
    if (!game.needsDeckBuilding) {
      Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => PracticeGameScreen(
          game: game,
          players: players,
          deckConfigsByPlayerId: null,
          localAvatarPath: localAvatarPath,
        ),
      ));
      return;
    }
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PracticeLoadDecksScreen(game: game, players: players, localAvatarPath: localAvatarPath),
    ));
  }

  void _loadSavedGame(BuildContext context) {
    final players = _buildPlayers();
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => LoadSavedGameScreen(
        currentPlayers: players,
        onLoaded: (game, state) => Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => PracticeGameScreen(
            game: game,
            players: players,
            deckConfigsByPlayerId: null,
            loadedState: state,
            localAvatarPath: localAvatarPath,
          ),
        )),
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a Game')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.folder_open),
                label: const Text('Load a Saved Game...'),
                onPressed: () => _loadSavedGame(context),
              ),
            ),
          ),
          Expanded(
            child: Center(
              child: GamePicker(onGameChosen: (game) => _chooseGame(context, game)),
            ),
          ),
        ],
      ),
    );
  }
}
