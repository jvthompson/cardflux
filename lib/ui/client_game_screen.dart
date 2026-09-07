import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/game_loader.dart';
import '../game/game_session.dart';
import '../game/table_controller.dart';
import '../models/card_definition.dart';
import '../models/table_state.dart';
import '../networking/game_client.dart';
import '../networking/net_message.dart';
import 'table_screen.dart';

/// Waits for the host's first `fullState` broadcast to construct the
/// client's [GameSession] (a client has no local copy of the game until the
/// host deals one), applies every later snapshot to it via
/// [GameSession.applyRemoteState], and renders the shared [TableScreen] once
/// a session exists.
class ClientGameScreen extends StatefulWidget {
  const ClientGameScreen({super.key, required this.gameClient, required this.localPlayerId});

  final GameClient gameClient;
  final String localPlayerId;

  @override
  State<ClientGameScreen> createState() => _ClientGameScreenState();
}

class _ClientGameScreenState extends State<ClientGameScreen> {
  GameSession? _session;
  Map<String, CardDefinition> _definitionsById = {};
  StreamSubscription<NetMessage>? _sub;
  bool _loadingFirstState = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.gameClient.incoming.listen(_handleMessage);
  }

  Future<void> _handleMessage(NetMessage msg) async {
    if (msg.type != NetMessageType.fullState) return;
    final remoteState = TableState.fromJson(msg.payload);

    if (_session == null) {
      if (_loadingFirstState) return;
      _loadingFirstState = true;
      // M4 scope: the host only ever deals the bundled standard deck.
      final game = await GameLoader().loadStandardDeck();
      if (!mounted) return;
      setState(() {
        _session = GameSession(localPlayerId: widget.localPlayerId, initialState: remoteState);
        _definitionsById = {for (final c in game.cards) c.id: c};
      });
    } else {
      _session!.applyRemoteState(remoteState);
    }
  }

  @override
  void dispose() {
    _sub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Waiting for host to start the game...'),
            ],
          ),
        ),
      );
    }
    return ChangeNotifierProvider.value(
      value: session,
      child: TableScreen(
        definitionsById: _definitionsById,
        controller: ClientTableController(widget.gameClient),
      ),
    );
  }
}
