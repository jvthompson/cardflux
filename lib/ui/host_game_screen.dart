import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/game_session.dart';
import '../game/host_game_engine.dart';
import '../game/table_controller.dart';
import '../models/card_definition.dart';
import '../models/deck_config.dart';
import '../models/game_definition.dart';
import '../networking/host_server.dart';
import '../networking/net_message.dart';
import 'table_screen.dart';

/// Deals [game]/[deckConfig] (chosen on [GameSelectScreen]/[DeckBuildScreen])
/// into the host's authoritative [GameSession], sends the client the full
/// [GameDefinition] it'll need to render cards, starts the [HostGameEngine]
/// broadcast loop, and renders the shared [TableScreen]. Built exactly once
/// (in [initState]) so the session -- and the game state it holds -- survives
/// unrelated rebuilds.
class HostGameScreen extends StatefulWidget {
  const HostGameScreen({
    super.key,
    required this.hostServer,
    required this.hostPlayerId,
    required this.game,
    required this.deckConfig,
  });

  final HostServer hostServer;
  final String hostPlayerId;
  final GameDefinition game;
  final DeckConfig deckConfig;

  @override
  State<HostGameScreen> createState() => _HostGameScreenState();
}

class _HostGameScreenState extends State<HostGameScreen> {
  GameSession? _session;
  HostGameEngine? _engine;
  Map<String, CardDefinition> _definitionsById = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    final session = GameSession.dealDeck(
      game: widget.game,
      deckConfig: widget.deckConfig,
      localPlayerId: widget.hostPlayerId,
    );
    final engine = HostGameEngine(session: session, hostServer: widget.hostServer, hostPlayerId: widget.hostPlayerId);
    // Sent before the engine's first broadcast so the client can resolve
    // definitionIds in the fullState snapshot that follows.
    widget.hostServer.send(NetMessage(type: NetMessageType.gameData, payload: widget.game.toJson()));
    engine.start();
    setState(() {
      _session = session;
      _engine = engine;
      _definitionsById = {for (final c in widget.game.cards) c.id: c};
    });
  }

  @override
  void dispose() {
    _engine?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ChangeNotifierProvider.value(
      value: session,
      child: TableScreen(
        definitionsById: _definitionsById,
        controller: HostTableController(session),
      ),
    );
  }
}
