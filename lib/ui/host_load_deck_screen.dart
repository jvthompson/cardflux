import 'dart:async';

import 'package:flutter/material.dart';

import '../models/deck_config.dart';
import '../models/game_definition.dart';
import '../networking/host_server.dart';
import '../networking/net_message.dart';
import 'home_screen.dart';
import 'host_game_screen.dart';
import 'widgets/deck_library_screen.dart';

/// Shown right after the host picks [game]: sends the client the
/// [GameDefinition] immediately (so it can show its own Load Deck screen),
/// lets the host load their own deck file, and waits for the client's
/// `requestDeckChosen` before dealing -- see [HostGameScreen] for the actual
/// deal + table screen. Replaces the old quantity-picking `DeckBuildScreen`,
/// which built one shared deck for both players; here each player brings
/// their own.
///
/// Dealing doesn't start the instant both sides finish loading -- each side
/// must explicitly press Ready (see [_markHostReady]/`requestReady`), which
/// locks their own deck selection against further changes. The match begins
/// once both the host and the client have pressed Ready.
class HostLoadDeckScreen extends StatefulWidget {
  const HostLoadDeckScreen({super.key, required this.hostServer, required this.hostPlayerId, required this.game});

  final HostServer hostServer;
  final String hostPlayerId;
  final GameDefinition game;

  @override
  State<HostLoadDeckScreen> createState() => _HostLoadDeckScreenState();
}

class _HostLoadDeckScreenState extends State<HostLoadDeckScreen> {
  final Map<String, DeckConfig> _hostDecks = {};
  final Map<String, DeckConfig> _clientDecks = {};
  bool _hostReady = false;
  bool _clientReady = false;
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
    if (msg.type == NetMessageType.requestDeckChosen) {
      final zoneId = msg.payload['zoneId'] as String;
      final deck = DeckConfig.fromJson((msg.payload['deck'] as Map).cast<String, dynamic>());
      setState(() => _clientDecks[zoneId] = deck);
      return;
    }
    if (msg.type == NetMessageType.requestReady) {
      setState(() => _clientReady = true);
      _maybeBeginGame();
    }
  }

  void _chooseHostDeck(String zoneId, DeckConfig deck) {
    setState(() => _hostDecks[zoneId] = deck);
  }

  bool get _hostDecksComplete => _hostDecks.length >= widget.game.deckBuildingZones.length;

  /// Locks the host's own deck selection in -- irreversible from this screen
  /// (mirrors the client's own `_markReady` in `ClientGameScreen`).
  void _markHostReady() {
    if (_hostReady || !_hostDecksComplete) return;
    setState(() => _hostReady = true);
    _maybeBeginGame();
  }

  void _maybeBeginGame() {
    final clientId = widget.hostServer.opponentPlayerId;
    if (!_hostReady || !_clientReady || clientId == null || _navigatedAway || !mounted) return;
    _navigatedAway = true;
    _sub?.cancel();
    _statusSub?.cancel();
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => HostGameScreen(
        hostServer: widget.hostServer,
        hostPlayerId: widget.hostPlayerId,
        game: widget.game,
        deckConfigsByPlayerId: {widget.hostPlayerId: _hostDecks, clientId: _clientDecks},
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
    final zones = widget.game.deckBuildingZones;
    return Scaffold(
      appBar: AppBar(title: Text('Load Deck -- ${widget.game.name}')),
      body: Column(
        children: [
          Expanded(
            child: IgnorePointer(
              ignoring: _hostReady,
              child: Opacity(
                opacity: _hostReady ? 0.5 : 1,
                child: DeckLibraryScreen(game: widget.game, zones: zones, onDeckChosen: _chooseHostDeck),
              ),
            ),
          ),
          if (_hostDecksComplete && !_hostReady)
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: FilledButton(
                onPressed: _markHostReady,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  child: Text('Ready'),
                ),
              ),
            ),
          if (_hostReady && !_clientReady)
            Padding(
              padding: const EdgeInsets.only(bottom: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(
                    _clientDecks.length < zones.length
                        ? 'Waiting for opponent to load their deck(s) and select Ready... (${_clientDecks.length}/${zones.length})'
                        : 'Waiting for opponent to select Ready...',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
