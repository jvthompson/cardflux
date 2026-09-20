import 'package:flutter/material.dart';

import '../models/player.dart';

/// Shown while loading a saved game whenever `matchPlayersByName`
/// (`lib/game/save_game_remap.dart`) couldn't unambiguously match every
/// saved player to a currently-joined one by name (a name with no match at
/// all, or a name duplicated on either side). Lets the host manually finish
/// the assignment before the load proceeds -- directly mirrors
/// `assign_seats_screen.dart`'s swap-based dropdown-per-slot interaction
/// (`_order` kept a valid permutation at all times by swapping, rather than
/// a from-scratch design), just matching saved identities to current
/// players instead of seats to players.
class SeatMatchScreen extends StatefulWidget {
  const SeatMatchScreen({super.key, required this.unmatchedSavedPlayers, required this.unmatchedCurrentPlayers});

  /// Saved players (in their original saved order) still needing a current
  /// player assigned to them.
  final List<PlayerInfo> unmatchedSavedPlayers;

  /// Current players left over once every unambiguous name match was
  /// claimed -- same length as [unmatchedSavedPlayers], since the player
  /// counts are already required to match before this screen is ever
  /// reached.
  final List<PlayerInfo> unmatchedCurrentPlayers;

  @override
  State<SeatMatchScreen> createState() => _SeatMatchScreenState();
}

class _SeatMatchScreenState extends State<SeatMatchScreen> {
  late final List<PlayerInfo> _order = List.of(widget.unmatchedCurrentPlayers);

  /// Picking a player already assigned to another saved slot swaps the two
  /// -- keeps [_order] a valid permutation at all times, same as
  /// `AssignSeatsScreen._assign`.
  void _assign(int slotIndex, String playerId) {
    final otherIndex = _order.indexWhere((p) => p.id == playerId);
    if (otherIndex == slotIndex) return;
    setState(() {
      final moved = _order[otherIndex];
      _order[otherIndex] = _order[slotIndex];
      _order[slotIndex] = moved;
    });
  }

  void _confirm() {
    final map = {
      for (var i = 0; i < widget.unmatchedSavedPlayers.length; i++) widget.unmatchedSavedPlayers[i].id: _order[i].id,
    };
    Navigator.of(context).pop(map);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  "This save's players couldn't be matched to your current players by name alone. "
                  'Choose who each saved player is now:',
                ),
                const SizedBox(height: 24),
                for (var i = 0; i < widget.unmatchedSavedPlayers.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(child: Text('Saved as "${widget.unmatchedSavedPlayers[i].name}"')),
                        DropdownButton<String>(
                          value: _order[i].id,
                          items: [
                            for (final p in _order) DropdownMenuItem(value: p.id, child: Text(p.name)),
                          ],
                          onChanged: (id) => id == null ? null : _assign(i, id),
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: _confirm,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Confirm'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
