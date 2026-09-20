import 'package:flutter/material.dart';

import '../data/deck_library_loader.dart';
import '../data/decks_directory_settings.dart';
import '../models/deck_config.dart';
import '../models/game_definition.dart';
import '../networking/host_server.dart';
import 'host_game_screen.dart';
import 'load_saved_game_screen.dart';
import 'navigation.dart';
import 'widgets/game_picker.dart';

/// Host-only screen: pick the bundled standard deck, or browse a folder on
/// disk for custom game JSON files, then proceed straight to
/// [HostGameScreen] -- any owned deck-building zones simply start empty;
/// a player loads a deck into one later by right-clicking it at the table
/// (see `TableScreen._promptLoadDeck`). The [hostServer]/[hostPlayerId] are
/// only threaded through to the eventual [HostGameScreen] -- this screen
/// doesn't touch the connection itself.
class GameSelectScreen extends StatelessWidget {
  const GameSelectScreen({super.key, required this.hostServer, required this.hostPlayerId});

  final HostServer hostServer;
  final String hostPlayerId;

  /// Resolves every shared zone's [ZoneDefinition.deckName] (see
  /// `ZoneDefinition`) against the host's own Deck Library folder, keyed by
  /// zone id -- done once here, up front, since it's the one async step a
  /// Shared Deck zone needs before `GameSession.dealFromZones` (a
  /// synchronous factory) can deal it. A zone whose named deck can't be
  /// found is simply left out of the map; `dealFromZones` falls back to that
  /// zone's own static entries in that case.
  Future<Map<String, DeckConfig>> _resolveSharedDeckConfigs(GameDefinition game) async {
    final zonesWithDeckName = game.zones.where((z) => z.shared && !z.standardDeck && z.deckName != null).toList();
    if (zonesWithDeckName.isEmpty) return const {};
    final rootPath = await DecksDirectorySettings().getPath();
    final available = await DeckLibraryLoader().loadDecksForGame(rootPath, game);
    final byDisplayName = {for (final entry in available.entries) entry.displayName: entry.deck};
    return {
      for (final zone in zonesWithDeckName)
        if (byDisplayName[zone.deckName] != null) zone.id: byDisplayName[zone.deckName]!,
    };
  }

  Future<void> _chooseGame(BuildContext context, GameDefinition game) async {
    final sharedDeckConfigsByZoneId = await _resolveSharedDeckConfigs(game);
    if (!context.mounted) return;
    pushScreen(
      context,
      title: game.name,
      showBackButton: false,
      builder: (_) => HostGameScreen(
        hostServer: hostServer,
        hostPlayerId: hostPlayerId,
        game: game,
        // Empty (not null) per player -- every owned deck-building zone
        // starts empty; a player loads their own deck at the table later.
        deckConfigsByPlayerId: const {},
        sharedDeckConfigsByZoneId: sharedDeckConfigsByZoneId,
      ),
    );
  }

  void _loadSavedGame(BuildContext context) {
    pushScreen(
      context,
      title: 'Load a Saved Game',
      builder: (_) => LoadSavedGameScreen(
        currentPlayers: hostServer.roster,
        onLoaded: (game, state) => pushScreen(
          context,
          title: game.name,
          showBackButton: false,
          builder: (_) => HostGameScreen(
            hostServer: hostServer,
            hostPlayerId: hostPlayerId,
            game: game,
            deckConfigsByPlayerId: null,
            loadedState: state,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
