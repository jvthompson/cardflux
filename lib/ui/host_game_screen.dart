import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/game_session.dart';
import '../game/host_game_engine.dart';
import '../game/table_controller.dart';
import '../models/card_definition.dart';
import '../models/deck_config.dart';
import '../models/game_definition.dart';
import '../models/player.dart';
import '../networking/host_server.dart';
import '../networking/net_message.dart';
import 'home_screen.dart';
import 'table_screen.dart';

/// Deals [game]/[deckConfigsByPlayerId] into the host's authoritative
/// [GameSession], starts the [HostGameEngine] broadcast loop, and renders
/// the shared [TableScreen]. Built exactly once (in [initState]) so the
/// session -- and the game state it holds -- survives unrelated rebuilds.
///
/// When `game.needsDeckBuilding`, [deckConfigsByPlayerId] holds each
/// player's own deck(s), keyed by player id then by zone id (a game can have
/// more than one deck-building zone, see `GameDefinition.deckBuildingZones`)
/// -- chosen on [GameSelectScreen]/`HostLoadDeckScreen`, which already sent
/// the client [game] before either player picked a deck. Otherwise
/// [GameSelectScreen] skips straight here with [deckConfigsByPlayerId] null
/// -- nobody built anything, so this screen sends [game] itself and every
/// zone deals from its own static entries.
class HostGameScreen extends StatefulWidget {
  const HostGameScreen({
    super.key,
    required this.hostServer,
    required this.hostPlayerId,
    required this.game,
    required this.deckConfigsByPlayerId,
  });

  final HostServer hostServer;
  final String hostPlayerId;
  final GameDefinition game;
  final Map<String, Map<String, DeckConfig>>? deckConfigsByPlayerId;

  @override
  State<HostGameScreen> createState() => _HostGameScreenState();
}

class _HostGameScreenState extends State<HostGameScreen> {
  GameSession? _session;
  HostGameEngine? _engine;
  Map<String, CardDefinition> _definitionsById = {};
  StreamSubscription<HostConnectionStatus>? _statusSub;
  bool _navigatedHome = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  void _init() {
    final clientId = widget.hostServer.opponentPlayerId!;
    final players = [
      PlayerInfo(id: widget.hostPlayerId, name: 'You', role: PlayerRole.host),
      PlayerInfo(id: clientId, name: widget.hostServer.opponentName ?? 'Opponent', role: PlayerRole.client),
    ];
    // Harmless to send again for the deck-building path -- ClientGameScreen's
    // gameData handling just overwrites `_game` with an identical value.
    widget.hostServer.send(NetMessage(type: NetMessageType.gameData, payload: widget.game.toJson()));
    final session = GameSession.dealFromZones(
      game: widget.game,
      players: players,
      localPlayerId: widget.hostPlayerId,
      deckConfigsByPlayerId: widget.deckConfigsByPlayerId,
    );
    final engine = HostGameEngine(session: session, hostServer: widget.hostServer, hostPlayerId: widget.hostPlayerId);
    engine.start();
    _statusSub = widget.hostServer.statusStream.listen((status) {
      if (status == HostConnectionStatus.disconnected) _returnHome();
    });
    setState(() {
      _session = session;
      _engine = engine;
      _definitionsById = {for (final c in widget.game.cards) c.id: c};
    });
  }

  void _returnHome() {
    if (_navigatedHome || !mounted) return;
    _navigatedHome = true;
    // This hosting session is over either way -- release the port so a
    // fresh "Host Game" attempt from HomeScreen can rebind it.
    widget.hostServer.stop();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen(message: 'Opponent disconnected.')),
      (route) => false,
    );
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    _engine?.dispose();
    if (!_navigatedHome) widget.hostServer.stop();
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
        isMirrored: false,
        zones: widget.game.zones,
        opponentCardBorderColor: widget.game.opponentCardBorderColor,
        cardBackImagePath: widget.game.cardBackImagePath,
      ),
    );
  }
}
