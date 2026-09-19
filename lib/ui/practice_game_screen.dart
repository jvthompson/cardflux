import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/save_game_file_ops.dart';
import '../game/game_session.dart';
import '../game/table_controller.dart';
import '../models/card_definition.dart';
import '../models/deck_config.dart';
import '../models/game_definition.dart';
import '../models/player.dart';
import '../models/saved_game.dart';
import '../models/table_state.dart';
import 'home_screen.dart';
import 'table_screen.dart';
import 'widgets/save_game_dialog.dart';

/// Deals [game]/[deckConfigsByPlayerId] into a local, no-networking
/// [GameSession] for [players] (1-4 simulated seats, all controlled by the
/// one real player at this device via hot-seat switching -- see
/// [GameSession.actingPlayerId]/[GameSession.setActiveSeat]) and renders the
/// shared [TableScreen]. Mirrors [HostGameScreen]'s `_init`/`build` shape,
/// minus the `HostServer`/`HostGameEngine` since there's nothing to
/// broadcast to. Built exactly once (in [initState]) so the session survives
/// unrelated rebuilds.
class PracticeGameScreen extends StatefulWidget {
  const PracticeGameScreen({
    super.key,
    required this.game,
    required this.players,
    required this.deckConfigsByPlayerId,
    this.localAvatarPath,
    this.loadedState,
  });

  final GameDefinition game;
  final List<PlayerInfo> players;
  final Map<String, DeckConfig>? deckConfigsByPlayerId;

  /// A previously-saved, already player-remapped [TableState] to resume
  /// instead of dealing a fresh one -- see `HostGameScreen.loadedState` and
  /// `LoadSavedGameScreen`.
  final TableState? loadedState;

  /// The real player's own avatar -- only ever shown for seat 1 (see
  /// `TableScreen._avatarCorner`'s `isLocal`, which stays anchored to
  /// [GameSession.localPlayerId] regardless of which seat is active).
  final String? localAvatarPath;

  @override
  State<PracticeGameScreen> createState() => _PracticeGameScreenState();
}

class _PracticeGameScreenState extends State<PracticeGameScreen> {
  GameSession? _session;
  Map<String, CardDefinition> _definitionsById = {};

  @override
  void initState() {
    super.initState();
    final loadedState = widget.loadedState;
    final resumeClockStart = loadedState == null || loadedState.log.isEmpty
        ? null
        : DateTime.now().subtract(Duration(milliseconds: loadedState.log.last.elapsedMs));
    _session = loadedState != null
        ? GameSession(
            game: widget.game,
            localPlayerId: widget.players.first.id,
            initialState: loadedState,
            isLocalPractice: true,
            clockStart: resumeClockStart,
          )
        : GameSession.localPractice(
            game: widget.game,
            players: widget.players,
            deckConfigsByPlayerId: widget.deckConfigsByPlayerId,
          );
    _definitionsById = {for (final c in widget.game.cards) c.id: c};
  }

  void _leaveGame() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  /// The Game Menu's "Save Game..." action -- see `HostGameScreen._saveGame`,
  /// identical logic minus the network broadcast. Null (hidden) when
  /// [GameDefinition.folderPath] is null (the bundled Standard 52 deck).
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
        controller: HostTableController(session),
        // Seat 1 -- the real player's own profile -- is always dealt as the
        // near/anchor seat, since we assign seats ourselves rather than a
        // host picking a seat via AssignSeatsScreen.
        isMirrored: false,
        zones: widget.game.zones,
        cardBacks: widget.game.cardBacks,
        gameFolderPath: widget.game.folderPath,
        localPlayerAvatarPath: widget.localAvatarPath,
        onLeaveGame: _leaveGame,
        leaveButtonLabel: 'Leave Game',
        leaveConfirmationMessage: 'Leave this practice game and return to the home screen?',
        onSaveGame: widget.game.folderPath == null ? null : _saveGame,
      ),
    );
  }
}
