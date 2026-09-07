import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/game_loader.dart';
import '../game/game_session.dart';
import '../game/host_game_engine.dart';
import '../game/table_controller.dart';
import '../models/card_definition.dart';
import '../networking/host_server.dart';
import 'table_screen.dart';

/// Builds the host's authoritative [GameSession] once the opponent has
/// connected, starts the [HostGameEngine] broadcast loop, and renders the
/// shared [TableScreen]. Built exactly once (in [initState]) so the session
/// -- and the game state it holds -- survives unrelated rebuilds.
class HostGameScreen extends StatefulWidget {
  const HostGameScreen({super.key, required this.hostServer, required this.hostPlayerId});

  final HostServer hostServer;
  final String hostPlayerId;

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

  Future<void> _init() async {
    final game = await GameLoader().loadStandardDeck();
    final session = GameSession.localSandbox(game: game, localPlayerId: widget.hostPlayerId);
    final engine = HostGameEngine(session: session, hostServer: widget.hostServer, hostPlayerId: widget.hostPlayerId);
    engine.start();
    if (!mounted) {
      engine.dispose();
      return;
    }
    setState(() {
      _session = session;
      _engine = engine;
      _definitionsById = {for (final c in game.cards) c.id: c};
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
