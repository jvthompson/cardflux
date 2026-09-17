import 'package:flutter/material.dart';

import '../models/deck_config.dart';
import '../models/game_definition.dart';
import '../models/player.dart';
import 'practice_game_screen.dart';
import 'widgets/deck_library_screen.dart';

/// Steps through [players] one seat at a time, letting the one real player
/// assign each simulated seat its own deck(s) via [DeckLibraryScreen] --
/// the same widget `HostLoadDeckScreen` embeds for the host's own pick, just
/// looped locally instead of driven by a network roster. Accumulates into
/// the same `Map<String playerId, Map<String zoneId, DeckConfig>>` shape
/// `GameSession.dealFromZones` already expects, then hands off to
/// [PracticeGameScreen] once every seat is done.
class PracticeLoadDecksScreen extends StatefulWidget {
  const PracticeLoadDecksScreen({
    super.key,
    required this.game,
    required this.players,
    this.localAvatarPath,
  });

  final GameDefinition game;
  final List<PlayerInfo> players;
  final String? localAvatarPath;

  @override
  State<PracticeLoadDecksScreen> createState() => _PracticeLoadDecksScreenState();
}

class _PracticeLoadDecksScreenState extends State<PracticeLoadDecksScreen> {
  final Map<String, DeckConfig> _decksByPlayerId = {};
  int _seatIndex = 0;

  PlayerInfo get _currentPlayer => widget.players[_seatIndex];

  void _chooseDeck(DeckConfig deck) {
    setState(() => _decksByPlayerId[_currentPlayer.id] = deck);
  }

  bool get _currentSeatComplete => _decksByPlayerId.containsKey(_currentPlayer.id);

  void _continue() {
    if (!_currentSeatComplete) return;
    if (_seatIndex < widget.players.length - 1) {
      setState(() => _seatIndex++);
      return;
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => PracticeGameScreen(
        game: widget.game,
        players: widget.players,
        deckConfigsByPlayerId: _decksByPlayerId,
        localAvatarPath: widget.localAvatarPath,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final player = _currentPlayer;
    final isLastSeat = _seatIndex == widget.players.length - 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.players.length == 1
              ? 'Load Deck -- ${widget.game.name}'
              : 'Load Deck -- ${player.name} (${_seatIndex + 1}/${widget.players.length})',
        ),
      ),
      body: Column(
        children: [
          Expanded(
            // A fresh key per seat forces a brand-new DeckLibraryScreen
            // instance -- so its own per-zone "just loaded" state resets
            // between seats instead of carrying over the previous seat's.
            child: DeckLibraryScreen(
              key: ValueKey(player.id),
              game: widget.game,
              zones: widget.game.deckBuildingZones,
              onDeckChosen: _chooseDeck,
            ),
          ),
          if (_currentSeatComplete)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: FilledButton(
                onPressed: _continue,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
                  child: Text(isLastSeat ? 'Start Game' : 'Next Player'),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
