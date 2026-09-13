import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/player_profile_settings.dart';
import '../game/game_session.dart';
import '../game/host_game_engine.dart';
import '../game/seat_utils.dart';
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
  StreamSubscription<List<PlayerInfo>>? _rosterSub;
  bool _navigatedHome = false;
  String? _localAvatarPath;

  @override
  void initState() {
    super.initState();
    _init();
    PlayerProfileSettings().getAvatarPath().then((path) {
      if (!mounted) return;
      setState(() => _localAvatarPath = path);
    });
  }

  void _init() {
    final players = widget.hostServer.roster;
    // Harmless to send again for the deck-building path -- ClientGameScreen's
    // gameData handling just overwrites `_game` with an identical value.
    widget.hostServer.broadcast(NetMessage(type: NetMessageType.gameData, payload: widget.game.toJson()));
    final session = GameSession.dealFromZones(
      game: widget.game,
      players: players,
      localPlayerId: widget.hostPlayerId,
      deckConfigsByPlayerId: widget.deckConfigsByPlayerId,
    );
    final engine = HostGameEngine(session: session, hostServer: widget.hostServer, hostPlayerId: widget.hostPlayerId);
    engine.start();
    // A 2-player match keeps today's exact behavior: the sole client
    // disconnecting ends the session for the host too. A 3-4 player match
    // never bounces the host home -- the remaining players keep playing
    // (HostGameEngine's own roster subscription flags the departed seat's
    // `PlayerInfo.connected` for the UI instead).
    _rosterSub = widget.hostServer.rosterStream.listen((roster) {
      if (widget.hostServer.maxPlayers == 2 && roster.length < 2) _returnHome();
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
    _rosterSub?.cancel();
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
        // The host can be assigned to any seat via AssignSeatsScreen, not
        // just seat 0 -- look up where they actually landed rather than
        // assuming near/seat-0, which was only ever true before hosts could
        // reorder seats.
        isMirrored: isFarMirrorSeat(
          session.state.players.indexWhere((p) => p.id == widget.hostPlayerId),
          session.state.players.length,
        ),
        zones: widget.game.zones,
        cardBackImagePath: widget.game.cardBackImagePath,
        gameFolderPath: widget.game.folderPath,
        localPlayerAvatarPath: _localAvatarPath,
        avatarBytesByPlayerId: widget.hostServer.avatarsByPlayerId,
      ),
    );
  }
}
