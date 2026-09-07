import 'dart:async';

import 'package:flutter/material.dart';

import '../models/deck_config.dart';
import '../models/game_definition.dart';
import '../networking/host_server.dart';
import '../networking/net_message.dart';
import 'home_screen.dart';
import 'host_game_screen.dart';
import 'widgets/load_deck_screen.dart';

/// Shown right after the host picks [game]: sends the client the
/// [GameDefinition] immediately (so it can show its own Load Deck screen),
/// lets the host load their own deck file, and waits for the client's
/// `requestDeckChosen` before dealing -- see [HostGameScreen] for the actual
/// deal + table screen. Replaces the old quantity-picking `DeckBuildScreen`,
/// which built one shared deck for both players; here each player brings
/// their own.
class HostLoadDeckScreen extends StatefulWidget {
  const HostLoadDeckScreen({super.key, required this.hostServer, required this.hostPlayerId, required this.game});

  final HostServer hostServer;
  final String hostPlayerId;
  final GameDefinition game;

  @override
  State<HostLoadDeckScreen> createState() => _HostLoadDeckScreenState();
}

class _HostLoadDeckScreenState extends State<HostLoadDeckScreen> {
  DeckConfig? _hostDeck;
  DeckConfig? _clientDeck;
  StreamSubscription<NetMessage>? _sub;
  StreamSubscription<HostConnectionStatus>? _statusSub;
  bool _navigatedAway = false;

  @override
  void initState() {
    super.initState();
    // Sent before the client can see anything -- it needs the full
    // GameDefinition to show its own Load Deck screen and resolve card art.
    widget.hostServer.send(NetMessage(type: NetMessageType.gameData, payload: widget.game.toJson()));
    _sub = widget.hostServer.incoming.listen(_handleMessage);
    _statusSub = widget.hostServer.statusStream.listen((status) {
      if (status == HostConnectionStatus.disconnected) _returnHome();
    });
  }

  void _handleMessage(NetMessage msg) {
    if (msg.type != NetMessageType.requestDeckChosen) return;
    setState(() => _clientDeck = DeckConfig.fromJson(msg.payload));
    _maybeStart();
  }

  void _chooseHostDeck(DeckConfig deck) {
    setState(() => _hostDeck = deck);
    _maybeStart();
  }

  void _maybeStart() {
    final hostDeck = _hostDeck;
    final clientDeck = _clientDeck;
    final clientId = widget.hostServer.opponentPlayerId;
    if (hostDeck == null || clientDeck == null || clientId == null || _navigatedAway || !mounted) return;
    _navigatedAway = true;
    _sub?.cancel();
    _statusSub?.cancel();
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => HostGameScreen(
        hostServer: widget.hostServer,
        hostPlayerId: widget.hostPlayerId,
        game: widget.game,
        deckConfigsByPlayerId: {widget.hostPlayerId: hostDeck, clientId: clientDeck},
      ),
    ));
  }

  void _returnHome() {
    if (_navigatedAway || !mounted) return;
    _navigatedAway = true;
    widget.hostServer.stop();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen(message: 'Opponent disconnected.')),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _sub?.cancel();
    _statusSub?.cancel();
    if (!_navigatedAway) widget.hostServer.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Load Deck -- ${widget.game.name}')),
      body: Column(
        children: [
          Expanded(child: LoadDeckScreen(game: widget.game, onDeckChosen: _chooseHostDeck)),
          if (_hostDeck != null && _clientDeck == null)
            const Padding(
              padding: EdgeInsets.only(bottom: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 12),
                  Text('Waiting for opponent to load their deck...'),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
