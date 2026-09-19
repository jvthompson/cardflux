import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/player_profile_settings.dart';
import '../data/save_game_file_ops.dart';
import '../game/game_session.dart';
import '../game/host_game_engine.dart';
import '../game/seat_utils.dart';
import '../game/table_controller.dart';
import '../models/card_definition.dart';
import '../models/deck_config.dart';
import '../models/game_definition.dart';
import '../models/saved_game.dart';
import '../models/table_state.dart';
import '../networking/host_server.dart';
import '../networking/net_message.dart';
import 'home_screen.dart';
import 'table_screen.dart';
import 'widgets/save_game_dialog.dart';

/// Deals [game]/[deckConfigsByPlayerId] into the host's authoritative
/// [GameSession], starts the [HostGameEngine] broadcast loop, and renders
/// the shared [TableScreen]. Built exactly once (in [initState]) so the
/// session -- and the game state it holds -- survives unrelated rebuilds.
///
/// When `game.needsDeckBuilding`, [deckConfigsByPlayerId] holds each
/// player's own chosen deck, keyed by player id -- its subdecks (see
/// `DeckConfig.subdecks`) supply every deck-building zone at once (a game
/// can have more than one, see `GameDefinition.deckBuildingZones`) --
/// chosen on [GameSelectScreen]/`HostLoadDeckScreen`, which already sent
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
    this.sharedDeckConfigsByZoneId = const {},
    this.loadedState,
  });

  final HostServer hostServer;
  final String hostPlayerId;
  final GameDefinition game;
  final Map<String, DeckConfig>? deckConfigsByPlayerId;

  /// Every Shared Deck zone's [DeckConfig], resolved from its `deckName` by
  /// `GameSelectScreen` before this screen was ever built -- passed straight
  /// to `GameSession.dealFromZones`.
  final Map<String, DeckConfig> sharedDeckConfigsByZoneId;

  /// A previously-saved, already player-remapped [TableState] to resume
  /// instead of dealing a fresh one -- set only when the host picked "Load a
  /// Saved Game..." on [GameSelectScreen] instead of a game tile. When set,
  /// [deckConfigsByPlayerId]/[sharedDeckConfigsByZoneId] are ignored (a
  /// loaded save already has real dealt cards, no deck-building needed). See
  /// `LoadSavedGameScreen`.
  final TableState? loadedState;

  @override
  State<HostGameScreen> createState() => _HostGameScreenState();
}

class _HostGameScreenState extends State<HostGameScreen> {
  GameSession? _session;
  HostGameEngine? _engine;
  Map<String, CardDefinition> _definitionsById = {};
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
    final loadedState = widget.loadedState;
    final session = loadedState != null
        ? GameSession(game: widget.game, localPlayerId: widget.hostPlayerId, initialState: loadedState)
        : GameSession.dealFromZones(
            game: widget.game,
            players: players,
            localPlayerId: widget.hostPlayerId,
            deckConfigsByPlayerId: widget.deckConfigsByPlayerId,
            sharedDeckConfigsByZoneId: widget.sharedDeckConfigsByZoneId,
          );
    final engine = HostGameEngine(session: session, hostServer: widget.hostServer, hostPlayerId: widget.hostPlayerId);
    engine.start();
    // No player count auto-ends the session on disconnect, for any match
    // size: a departed seat just dims (`PlayerInfo.connected`, synced by
    // HostGameEngine's own roster subscription) while everyone else keeps
    // playing, and the departed player can rejoin later (same seat, same
    // hand) via `HostServer.reclaimableIdCheck` -- see JoinScreen.
    setState(() {
      _session = session;
      _engine = engine;
      _definitionsById = {for (final c in widget.game.cards) c.id: c};
    });
  }

  @override
  void dispose() {
    _engine?.dispose();
    widget.hostServer.stop();
    super.dispose();
  }

  /// The Game Menu's "End Game" action: tells every connected client why
  /// (so they show a specific message instead of a generic dropped-
  /// connection one -- see `GameClient.disconnectReason`) before navigating
  /// home, which triggers this screen's own [dispose] to actually tear down
  /// the engine/server.
  void _leaveGame() {
    widget.hostServer.broadcast(
      const NetMessage(
        type: NetMessageType.disconnect,
        payload: {'reason': 'hostLeft'},
      ),
    );
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen(message: 'You ended the game.')),
      (route) => false,
    );
  }

  /// The Game Menu's "Save Game..." action -- writes the host's own
  /// authoritative, unfiltered `session.state` (see `SaveGameDialog`,
  /// `SaveGameFileOps`). Null (hidden) when [GameDefinition.folderPath] is
  /// null -- the bundled Standard 52 deck has no folder to save into.
  Future<void> _saveGame() async {
    final folderPath = widget.game.folderPath;
    final session = _session;
    if (folderPath == null || session == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => SaveGameDialog(gameFolderPath: folderPath, gameName: widget.game.name),
    );
    if (name == null || !mounted) return;
    final save = SavedGame(savedAt: DateTime.now(), state: session.state.copyWith(searches: const []));
    await SaveGameFileOps().writeSaveGame(gameFolderPath: folderPath, name: name, save: save);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved "$name"')));
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
        controller: HostTableController(session, previewSink: _engine),
        // The host can be assigned to any seat via AssignSeatsScreen, not
        // just seat 0 -- look up where they actually landed rather than
        // assuming near/seat-0, which was only ever true before hosts could
        // reorder seats.
        isMirrored: isFarMirrorSeat(
          session.state.players.indexWhere((p) => p.id == widget.hostPlayerId),
          session.state.players.length,
        ),
        zones: widget.game.zones,
        cardBacks: widget.game.cardBacks,
        gameFolderPath: widget.game.folderPath,
        localPlayerAvatarPath: _localAvatarPath,
        avatarBytesByPlayerId: widget.hostServer.avatarsByPlayerId,
        onLeaveGame: _leaveGame,
        leaveButtonLabel: 'End Game',
        leaveConfirmationMessage: 'End the game for everyone? Every connected '
            'player will be disconnected -- you can start a new session any '
            'time.',
        onKickPlayer: widget.hostServer.kick,
        onSaveGame: widget.game.folderPath == null ? null : _saveGame,
      ),
    );
  }
}
