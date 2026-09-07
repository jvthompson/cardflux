import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/game_session.dart';
import '../game/table_controller.dart';
import '../models/card_definition.dart';
import '../models/deck_config.dart';
import '../models/game_definition.dart';
import '../models/table_state.dart';
import '../networking/game_client.dart';
import '../networking/net_message.dart';
import 'home_screen.dart';
import 'table_screen.dart';
import 'widgets/load_deck_screen.dart';

/// Waits for the host's `gameData` (the [GameDefinition] it's dealing from),
/// shows [LoadDeckScreen] so the local player can pick their own deck file
/// (sent to the host as `requestDeckChosen`), then waits for the first
/// `fullState` broadcast to construct the client's [GameSession] (a client
/// has no local copy of the game until the host sends one -- including
/// custom, non-bundled games loaded from the host's own disk), applies every
/// later snapshot to it via [GameSession.applyRemoteState], and renders the
/// shared [TableScreen] once a session exists.
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
  StreamSubscription<ClientConnectionStatus>? _statusSub;
  GameDefinition? _game;
  DeckConfig? _localDeck;
  bool _navigatedHome = false;

  @override
  void initState() {
    super.initState();
    _sub = widget.gameClient.incoming.listen(_handleMessage);
    _statusSub = widget.gameClient.statusStream.listen((status) {
      if (status == ClientConnectionStatus.disconnected) _returnHome();
    });
  }

  void _returnHome() {
    if (_navigatedHome || !mounted) return;
    _navigatedHome = true;
    // This connection is over either way -- release the socket so a fresh
    // "Join Game" attempt from HomeScreen can open a new one.
    widget.gameClient.disconnect();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen(message: 'Disconnected from host.')),
      (route) => false,
    );
  }

  void _handleMessage(NetMessage msg) {
    if (msg.type == NetMessageType.gameData) {
      // Triggers a rebuild so `build()` can switch from the waiting spinner
      // to LoadDeckScreen now that a GameDefinition is available.
      setState(() => _game = GameDefinition.fromJson(msg.payload));
      return;
    }
    if (msg.type != NetMessageType.fullState) return;
    final remoteState = TableState.fromJson(msg.payload);

    if (_session == null) {
      final game = _game;
      // Haven't received the host's game data yet -- wait for the next
      // fullState broadcast rather than building a session with no
      // definitions to render.
      if (game == null) return;
      setState(() {
        _session = GameSession(game: game, localPlayerId: widget.localPlayerId, initialState: remoteState);
        _definitionsById = {for (final c in game.cards) c.id: c};
      });
    } else {
      _session!.applyRemoteState(remoteState);
    }
  }

  void _chooseDeck(DeckConfig deck) {
    setState(() => _localDeck = deck);
    widget.gameClient.send(NetMessage(type: NetMessageType.requestDeckChosen, payload: deck.toJson()));
  }

  @override
  void dispose() {
    _sub?.cancel();
    _statusSub?.cancel();
    if (!_navigatedHome) widget.gameClient.disconnect();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      final game = _game;
      if (game != null && game.needsDeckBuilding && _localDeck == null) {
        return Scaffold(
          appBar: AppBar(title: Text('Load Deck -- ${game.name}')),
          body: LoadDeckScreen(game: game, onDeckChosen: _chooseDeck),
        );
      }
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
        isMirrored: true,
        zones: _game?.zones ?? const [],
        opponentCardBorderColor: _game?.opponentCardBorderColor ?? defaultOpponentCardBorderColor,
        cardBackImagePath: _game?.cardBackImagePath,
      ),
    );
  }
}
