import 'package:flutter/material.dart';

import '../data/save_game_file_ops.dart';
import '../game/save_game_remap.dart';
import '../models/card_definition.dart';
import '../models/game_definition.dart';
import '../models/player.dart';
import '../models/standard_deck.dart';
import '../models/table_state.dart';
import 'seat_match_screen.dart';
import 'widgets/game_picker.dart';

/// Zero-padded `YYYY-MM-DD HH:MM` for a saved game's timestamp -- no `intl`
/// dependency in this project, so a small manual formatter is simplest.
String _formatSavedAt(DateTime dt) {
  final local = dt.toLocal();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} ${two(local.hour)}:${two(local.minute)}';
}

/// Host-only (and Practice-mode-local-player) flow for loading a previously
/// saved game: pick which game's saves to browse (reuses the shared
/// [GamePicker]), then pick a save whose player count matches
/// [currentPlayers] -- this is where "can't load a save with a different
/// player count" is enforced, by construction (a mismatched save just isn't
/// selectable). Handles name-matching returning players to [currentPlayers]
/// (via `matchPlayersByName`), falling through to [SeatMatchScreen] for
/// anything ambiguous, then reports the final ready-to-use [GameDefinition]
/// and remapped [TableState] via [onLoaded] -- the caller navigates onward
/// (into `HostGameScreen`/`PracticeGameScreen` with `loadedState:` set).
class LoadSavedGameScreen extends StatefulWidget {
  const LoadSavedGameScreen({super.key, required this.currentPlayers, required this.onLoaded});

  final List<PlayerInfo> currentPlayers;
  final void Function(GameDefinition game, TableState state) onLoaded;

  @override
  State<LoadSavedGameScreen> createState() => _LoadSavedGameScreenState();
}

class _LoadSavedGameScreenState extends State<LoadSavedGameScreen> {
  final _fileOps = SaveGameFileOps();
  GameDefinition? _chosenGame;
  List<SaveGameLibraryEntry>? _entries;
  bool _busy = false;

  void _chooseGame(GameDefinition game) {
    if (game.folderPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This game has no folder on disk, so it has no saved games.')),
      );
      return;
    }
    setState(() {
      _chosenGame = game;
      _entries = null;
    });
    _fileOps.listSaveGames(game.folderPath!).then((entries) {
      if (mounted) setState(() => _entries = entries);
    });
  }

  /// Every [CardDefinition.id] a card can legally reference in [game] --
  /// mirrors `GameSession.dealFromZones`' own `validIds` computation exactly,
  /// so a card kept here is guaranteed dealable.
  Set<String> _validDefinitionIds(GameDefinition game) {
    final standardDeckCards =
        game.zones.any((z) => z.shared && z.standardDeck) ? buildStandardDeckCards() : const <CardDefinition>[];
    return {
      for (final c in game.cards) c.id,
      for (final c in standardDeckCards) c.id,
    };
  }

  Future<void> _pickSave(SaveGameLibraryEntry entry) async {
    final game = _chosenGame!;
    setState(() => _busy = true);
    final save = await _fileOps.readSaveGame(entry.filePath);
    if (!mounted) return;

    final match = matchPlayersByName(savedPlayers: save.state.players, currentPlayers: widget.currentPlayers);
    var idMap = match.matchedSavedIdToCurrentId;
    if (match.unmatchedSavedPlayers.isNotEmpty) {
      final manual = await Navigator.of(context).push<Map<String, String>>(
        MaterialPageRoute(
          builder: (_) => SeatMatchScreen(
            unmatchedSavedPlayers: match.unmatchedSavedPlayers,
            unmatchedCurrentPlayers: match.unmatchedCurrentPlayers,
          ),
        ),
      );
      if (manual == null) {
        if (mounted) setState(() => _busy = false);
        return;
      }
      idMap = {...idMap, ...manual};
    }
    if (!mounted) return;

    final result = buildLoadedTableState(
      saved: save.state,
      currentPlayers: widget.currentPlayers,
      savedIdToCurrentId: idMap,
      validDefinitionIds: _validDefinitionIds(game),
    );

    if (result.droppedCardCount > 0) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Some Cards No Longer Exist'),
          content: Text(
            '${result.droppedCardCount} card(s) in this save reference content that '
            "no longer exists in ${game.name} (it's been edited since this save) and will "
            'be skipped. Continue loading?',
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Continue')),
          ],
        ),
      );
      if (proceed != true) {
        if (mounted) setState(() => _busy = false);
        return;
      }
    }
    if (!mounted) return;
    widget.onLoaded(game, result.state);
  }

  @override
  Widget build(BuildContext context) {
    final game = _chosenGame;
    return Scaffold(
      appBar: AppBar(
        title: Text(game == null ? 'Load a Saved Game' : 'Load a Saved Game -- ${game.name}'),
        leading: game == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => setState(() {
                  _chosenGame = null;
                  _entries = null;
                }),
              ),
      ),
      body: game == null
          ? Center(child: GamePicker(onGameChosen: _chooseGame))
          : AbsorbPointer(
              absorbing: _busy,
              child: _buildSaveList(game),
            ),
    );
  }

  Widget _buildSaveList(GameDefinition game) {
    final entries = _entries;
    if (entries == null) {
      return const Center(child: CircularProgressIndicator());
    }
    if (entries.isEmpty) {
      return Center(
        child: Text(
          'No saved games found for ${game.name}.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 480),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.all(16),
          children: [
            for (final entry in entries)
              _SaveGameTile(
                entry: entry,
                compatible: entry.playerCount == widget.currentPlayers.length,
                requiredPlayerCount: widget.currentPlayers.length,
                onTap: () => _pickSave(entry),
              ),
          ],
        ),
      ),
    );
  }
}

class _SaveGameTile extends StatelessWidget {
  const _SaveGameTile({
    required this.entry,
    required this.compatible,
    required this.requiredPlayerCount,
    required this.onTap,
  });

  final SaveGameLibraryEntry entry;
  final bool compatible;
  final int requiredPlayerCount;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: ListTile(
        title: Text(entry.displayName),
        subtitle: Text(
          compatible
              ? 'Saved ${_formatSavedAt(entry.savedAt)} -- ${entry.playerCount} player(s)'
              : 'Saved ${_formatSavedAt(entry.savedAt)} -- needs $requiredPlayerCount player(s), '
                  'this save has ${entry.playerCount}',
        ),
        enabled: compatible,
        onTap: compatible ? onTap : null,
      ),
    );
  }
}
