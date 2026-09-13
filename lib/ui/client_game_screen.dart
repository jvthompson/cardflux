import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/game_loader.dart';
import '../data/games_directory_settings.dart';
import '../data/image_path_resolver.dart';
import '../data/player_profile_settings.dart';
import '../game/game_session.dart';
import '../game/seat_utils.dart';
import '../game/table_controller.dart';
import '../models/card_definition.dart';
import '../models/deck_config.dart';
import '../models/game_definition.dart';
import '../models/player.dart';
import '../models/table_state.dart';
import '../networking/game_client.dart';
import '../networking/net_message.dart';
import 'home_screen.dart';
import 'table_screen.dart';
import 'widgets/deck_library_screen.dart';

/// Waits for the host's `gameData` (the [GameDefinition] it's dealing from),
/// shows [LoadDeckScreen] so the local player can pick their own deck file
/// (sent to the host as `requestDeckChosen`), then waits for the first
/// `fullState` broadcast to construct the client's [GameSession] (a client
/// has no local copy of the game until the host sends one -- including
/// custom, non-bundled games loaded from the host's own disk), applies every
/// later snapshot to it via [GameSession.applyRemoteState], and renders the
/// shared [TableScreen] once a session exists.
class ClientGameScreen extends StatefulWidget {
  const ClientGameScreen({
    super.key,
    required this.gameClient,
    required this.localPlayerId,
  });

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
  final Map<String, DeckConfig> _localDecks = {};
  bool _localReady = false;
  bool _navigatedHome = false;
  List<PlayerInfo> _roster = const [];
  int _maxPlayers = 2;
  Set<String> _readyPlayerIds = const {};
  Map<String, Uint8List> _avatarsByPlayerId = const {};
  String? _localAvatarPath;

  @override
  void initState() {
    super.initState();
    _sub = widget.gameClient.incoming.listen(_handleMessage);
    _statusSub = widget.gameClient.statusStream.listen((status) {
      if (status != ClientConnectionStatus.disconnected) return;
      _returnHome(switch (widget.gameClient.disconnectReason) {
        'kicked' => 'You were removed from the game by the host.',
        'hostLeft' => 'The host ended the game.',
        _ => 'Disconnected from host.',
      });
    });
    PlayerProfileSettings().getAvatarPath().then((path) {
      if (!mounted) return;
      setState(() => _localAvatarPath = path);
    });
  }

  void _returnHome([String message = 'Disconnected from host.']) {
    if (_navigatedHome || !mounted) return;
    _navigatedHome = true;
    // This connection is over either way -- release the socket so a fresh
    // "Join Game" attempt from HomeScreen can open a new one.
    widget.gameClient.disconnect();
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => HomeScreen(message: message)),
      (route) => false,
    );
  }

  void _handleMessage(NetMessage msg) {
    if (msg.type == NetMessageType.lobbyRosterUpdate) {
      final players = (msg.payload['players'] as List)
          .map((e) => PlayerInfo.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
      final avatarsJson = (msg.payload['avatars'] as Map?)?.cast<String, dynamic>() ?? const {};
      setState(() {
        _roster = players;
        _maxPlayers = msg.payload['maxPlayers'] as int;
        _avatarsByPlayerId = {
          for (final e in avatarsJson.entries) e.key: base64Decode(e.value as String),
        };
      });
      return;
    }
    if (msg.type == NetMessageType.lobbyReadyUpdate) {
      setState(() => _readyPlayerIds = (msg.payload['readyPlayerIds'] as List).cast<String>().toSet());
      return;
    }
    if (msg.type == NetMessageType.gameData) {
      final game = GameDefinition.fromJson(msg.payload);
      // Triggers a rebuild so `build()` can switch from the waiting spinner
      // to LoadDeckScreen now that a GameDefinition is available.
      setState(() => _game = game);
      // The host's imagePath/cardBackImagePath values are absolute paths
      // resolved on ITS machine -- they only happen to work here if this
      // client's game library sits at the identical path. Fire-and-forget:
      // swap in this machine's own locally-resolved paths for the same game
      // once available, without blocking session bootstrap (below) on it.
      unawaited(_resolveLocalImagePaths(game));
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
        _session = GameSession(
          game: game,
          localPlayerId: widget.localPlayerId,
          initialState: remoteState,
        );
        _definitionsById = {for (final c in game.cards) c.id: c};
      });
    } else {
      _session!.applyRemoteState(remoteState);
    }
  }

  /// Looks up [remoteGame]'s id in this machine's own configured game
  /// library (see `GamesDirectorySettings`) and, if found, re-resolves
  /// `_game`'s (and, if already built, `_definitionsById`'s) image paths
  /// against this client's own local copy -- see `mergeLocalImagePaths`. A
  /// no-op if no games directory is configured, the game isn't found
  /// locally, or this screen has since moved on to a different game.
  Future<void> _resolveLocalImagePaths(GameDefinition remoteGame) async {
    GameDefinition resolved;
    try {
      final root = await GamesDirectorySettings().getPath();
      if (root == null) return;
      final localGames = await GameLoader().loadGamesFromDirectory(root);
      GameDefinition? localMatch;
      for (final g in localGames) {
        if (g.id == remoteGame.id) {
          localMatch = g;
          break;
        }
      }
      if (localMatch == null) return;
      resolved = mergeLocalImagePaths(remote: remoteGame, local: localMatch);
    } catch (_) {
      return;
    }
    if (!mounted || _game?.id != remoteGame.id) return;
    setState(() {
      _game = resolved;
      if (_session != null)
        _definitionsById = {for (final c in resolved.cards) c.id: c};
    });
  }

  void _chooseDeck(String zoneId, DeckConfig deck) {
    setState(() => _localDecks[zoneId] = deck);
    widget.gameClient.send(
      NetMessage(
        type: NetMessageType.requestDeckChosen,
        payload: {'zoneId': zoneId, 'deck': deck.toJson()},
      ),
    );
  }

  /// Locks the local player's own deck selection in -- irreversible from
  /// this screen (mirrors the host's own `_markHostReady` in
  /// `HostLoadDeckScreen`). The match doesn't actually begin until the host
  /// also presses Ready and deals -- signaled implicitly by the eventual
  /// `fullState` broadcast this screen already waits for.
  void _markReady() {
    final game = _game;
    if (_localReady || game == null || _localDecks.length < game.deckBuildingZones.length) return;
    setState(() => _localReady = true);
    widget.gameClient.send(const NetMessage(type: NetMessageType.requestReady));
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
      final zones = game?.deckBuildingZones ?? const [];
      if (game != null && zones.isNotEmpty) {
        final localDecksComplete = _localDecks.length >= zones.length;
        return Scaffold(
          appBar: AppBar(title: Text('Load Deck -- ${game.name}')),
          body: Column(
            children: [
              Expanded(
                child: IgnorePointer(
                  ignoring: _localReady,
                  child: Opacity(
                    opacity: _localReady ? 0.5 : 1,
                    child: DeckLibraryScreen(game: game, zones: zones, onDeckChosen: _chooseDeck),
                  ),
                ),
              ),
              if (localDecksComplete && !_localReady)
                Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: FilledButton(
                    onPressed: _markReady,
                    child: const Padding(
                      padding: EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                      child: Text('Ready'),
                    ),
                  ),
                ),
              if (_localReady)
                Padding(
                  padding: const EdgeInsets.only(bottom: 32),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircularProgressIndicator(),
                      const SizedBox(height: 12),
                      const Text('Waiting for the other player(s)...'),
                      for (final p in _roster.where((p) => p.id != widget.localPlayerId))
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Text(_readyPlayerIds.contains(p.id) ? '${p.name}: Ready' : '${p.name}: not ready'),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      }
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const CircularProgressIndicator(),
              const SizedBox(height: 16),
              const Text('Waiting for host to start the game...'),
              if (_roster.length > 1) ...[
                const SizedBox(height: 8),
                Text('${_roster.length}/$_maxPlayers players joined'),
              ],
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
        isMirrored: _isMirrored,
        zones: _game?.zones ?? const [],
        cardBackImagePath: _game?.cardBackImagePath,
        gameFolderPath: _game?.folderPath,
        localPlayerAvatarPath: _localAvatarPath,
        avatarBytesByPlayerId: _avatarsByPlayerId,
        onLeaveGame: () => _returnHome('You left the game.'),
        leaveButtonLabel: 'Leave Game',
        leaveConfirmationMessage: 'Leave the game? If the host is still '
            'hosting, you can rejoin in the same seat later.',
      ),
    );
  }

  /// Whether the shared free-table area should render flipped for this
  /// client's seat -- see `seat_utils.dart`'s doc. Deliberately reads seat
  /// order from `session.state.players` (the authoritative, already-dealt
  /// list `HostGameScreen` built from `HostServer.roster` -- reflecting any
  /// host-assigned seating from `AssignSeatsScreen`), NOT from [_roster]
  /// (this screen's own lobby-tracked copy, which is only ever refreshed by
  /// a `lobbyRosterUpdate` broadcast on join/leave -- never re-sent after
  /// the host calls `HostServer.setSeatOrder`, so it goes stale exactly when
  /// the host reorders seats away from plain join order). Falls back to
  /// `true` (this app's original, 2-player-only client behavior) if the
  /// session isn't built yet for some reason.
  bool get _isMirrored {
    final players = _session?.state.players ?? const [];
    final n = players.length;
    if (n < 2) return true;
    final mySeat = players.indexWhere((p) => p.id == widget.localPlayerId);
    if (mySeat < 0) return true;
    return isFarMirrorSeat(mySeat, n);
  }
}
