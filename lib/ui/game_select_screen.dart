import 'package:flutter/material.dart';

import '../models/game_definition.dart';
import '../networking/host_server.dart';
import 'deck_build_screen.dart';
import 'widgets/game_picker.dart';

/// Host-only screen (M5): pick the bundled standard deck, or browse a folder
/// on disk for custom game JSON files, then proceed to [DeckBuildScreen].
/// The [hostServer]/[hostPlayerId] are only threaded through to the eventual
/// [HostGameScreen] -- this screen doesn't touch the connection itself.
class GameSelectScreen extends StatelessWidget {
  const GameSelectScreen({super.key, required this.hostServer, required this.hostPlayerId});

  final HostServer hostServer;
  final String hostPlayerId;

  void _chooseGame(BuildContext context, GameDefinition game) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DeckBuildScreen(
        hostServer: hostServer,
        hostPlayerId: hostPlayerId,
        game: game,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Choose a Game')),
      body: Center(
        child: GamePicker(onGameChosen: (game) => _chooseGame(context, game)),
      ),
    );
  }
}
