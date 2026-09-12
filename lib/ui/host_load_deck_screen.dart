import 'dart:async';

import 'package:flutter/material.dart';

import '../models/deck_config.dart';
import '../models/game_definition.dart';
import '../models/player.dart';
import '../networking/host_server.dart';
import '../networking/net_message.dart';
import 'home_screen.dart';
import 'host_game_screen.dart';
import 'widgets/deck_library_screen.dart';

/// Shown right after the host picks [game]: sends every connected client the
/// [GameDefinition] immediately (so each can show its own Load Deck screen),
/// lets the host load their own deck file, and waits for every player's
/// `requestDeckChosen` + `requestReady` before dealing -- see [HostGameScreen]
/// for the actual deal + table screen. Replaces the old quantity-picking
/// `DeckBuildScreen`, which built one shared deck for both players; here
/// each player brings their own.
///
/// Dealing doesn't start the instant every side finishes loading -- each
/// player must explicitly press Ready (see [_markHostReady]/`requestReady`),
/// which locks their own deck selection against further changes. The match
/// begins once every currently-expected player (the host plus every
/// connected client -- see [HostServer.roster]) has pressed Ready.
class HostLoadDeckScreen extends StatefulWidget {
  const HostLoadDeckScreen({super.key, required this.hostServer, required this.hostPlayerId, required this.game});

  final HostServer hostServer;
  final String hostPlayerId;
  final GameDefinition game;

  @override
  State<HostLoadDeckScreen> createState() => _HostLoadDeckScreenState();
}

class _HostLoadDeckScreenState extends State<HostLoadDeckScreen> {
  final Map<String, Map<String, DeckConfig>> _decksByPlayerId = {};
  final Set<String> _readyPlayerIds = {};
  StreamSubscription<IncomingMessage>? _sub;
  StreamSubscription<List<PlayerInfo>>? _rosterSub;
  bool _navigatedAway = false;

  List<PlayerInfo> get _roster => widget.hostServer.roster;

  @override
  void initState() {
    super.initState();
    // Sent before any client can see anything -- each needs the full
    // GameDefinition to show its own Load Deck screen and resolve card art.
    widget.hostServer.broadcast(NetMessage(type: NetMessageType.gameData, payload: widget.game.toJson()));
    _sub = widget.hostServer.incoming.listen(_handleMessage);
    _rosterSub = widget.hostServer.rosterStream.listen(_handleRosterChange);
  }

  void _handleRosterChange(List<PlayerInfo> roster) {
    // A 2-player match keeps today's exact behavior: the sole client
    // disconnecting ends the session for the host too. A 3-4 player match
    // never bounces the host home on a disconnect -- the departing player's
    // slot just reopens and the host keeps waiting.
    if (widget.hostServer.maxPlayers == 2 && roster.length < 2) {
      _returnHome();
      return;
    }
    final connectedIds = {for (final p in roster) p.id};
    _decksByPlayerId.removeWhere((id, _) => id != widget.hostPlayerId && !connectedIds.contains(id));
    _readyPlayerIds.removeWhere((id) => !connectedIds.contains(id));
    if (mounted) setState(() {});
  }

  void _handleMessage(IncomingMessage incoming) {
    final msg = incoming.message;
    if (msg.type == NetMessageType.requestDeckChosen) {
      final zoneId = msg.payload['zoneId'] as String;
      final deck = DeckConfig.fromJson((msg.payload['deck'] as Map).cast<String, dynamic>());
      setState(() => (_decksByPlayerId[incoming.senderId] ??= {})[zoneId] = deck);
      return;
    }
    if (msg.type == NetMessageType.requestReady) {
      setState(() => _readyPlayerIds.add(incoming.senderId));
      _broadcastLobbyReady();
      _maybeBeginGame();
    }
  }

  void _chooseHostDeck(String zoneId, DeckConfig deck) {
    setState(() => (_decksByPlayerId[widget.hostPlayerId] ??= {})[zoneId] = deck);
  }

  bool get _hostDecksComplete =>
      (_decksByPlayerId[widget.hostPlayerId]?.length ?? 0) >= widget.game.deckBuildingZones.length;

  /// Locks the host's own deck selection in -- irreversible from this screen
  /// (mirrors a client's own `_markReady` in `ClientGameScreen`).
  void _markHostReady() {
    if (_readyPlayerIds.contains(widget.hostPlayerId) || !_hostDecksComplete) return;
    setState(() => _readyPlayerIds.add(widget.hostPlayerId));
    _broadcastLobbyReady();
    _maybeBeginGame();
  }

  void _broadcastLobbyReady() {
    widget.hostServer.broadcast(
      NetMessage(type: NetMessageType.lobbyReadyUpdate, payload: {'readyPlayerIds': _readyPlayerIds.toList()}),
    );
  }

  void _maybeBeginGame() {
    final roster = _roster;
    if (roster.length < widget.hostServer.maxPlayers) return;
    if (!roster.every((p) => _readyPlayerIds.contains(p.id))) return;
    if (_navigatedAway || !mounted) return;
    _navigatedAway = true;
    _sub?.cancel();
    _rosterSub?.cancel();
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => HostGameScreen(
        hostServer: widget.hostServer,
        hostPlayerId: widget.hostPlayerId,
        game: widget.game,
        deckConfigsByPlayerId: _decksByPlayerId,
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
    _rosterSub?.cancel();
    if (!_navigatedAway) widget.hostServer.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final zones = widget.game.deckBuildingZones;
    final hostReady = _readyPlayerIds.contains(widget.hostPlayerId);
    final others = _roster.where((p) => p.id != widget.hostPlayerId).toList();
    return Scaffold(
      appBar: AppBar(title: Text('Load Deck -- ${widget.game.name}')),
      body: Column(
        children: [
          Expanded(
            child: IgnorePointer(
              ignoring: hostReady,
              child: Opacity(
                opacity: hostReady ? 0.5 : 1,
                child: DeckLibraryScreen(game: widget.game, zones: zones, onDeckChosen: _chooseHostDeck),
              ),
            ),
          ),
          if (_hostDecksComplete && !hostReady)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: FilledButton(
                onPressed: _markHostReady,
                child: const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  child: Text('Ready'),
                ),
              ),
            ),
          if (hostReady && others.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  for (final p in others)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Text(_statusLineFor(p)),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  String _statusLineFor(PlayerInfo p) {
    if (_readyPlayerIds.contains(p.id)) return '${p.name}: Ready';
    final loaded = _decksByPlayerId[p.id]?.length ?? 0;
    return '${p.name}: loading deck(s) ($loaded/${widget.game.deckBuildingZones.length})';
  }
}
