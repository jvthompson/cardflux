import 'package:flutter/material.dart';

import '../models/player.dart';
import '../networking/host_server.dart';
import 'game_select_screen.dart';
import 'navigation.dart';

/// Shown once the lobby is full, for 3-4 player matches only (a 2-player
/// match has exactly one sensible arrangement -- host bottom, client top --
/// so `HostSetupScreen` skips straight to [GameSelectScreen] instead). Lets
/// the host assign which connected player occupies which seat before
/// dealing -- seat order otherwise defaults to join order, which is what
/// let the "who sits where" arrangement feel arbitrary/inconsistent before
/// this screen existed. See `seat_utils.dart`'s `computeHandRowLayout` doc
/// for exactly how seat index maps to on-screen position for every player.
class AssignSeatsScreen extends StatefulWidget {
  const AssignSeatsScreen({super.key, required this.hostServer, required this.hostPlayerId});

  final HostServer hostServer;
  final String hostPlayerId;

  @override
  State<AssignSeatsScreen> createState() => _AssignSeatsScreenState();
}

class _AssignSeatsScreenState extends State<AssignSeatsScreen> {
  // `late` is required here, not just cosmetic -- `widget` isn't available
  // until after this State is attached, so a plain (non-late) field
  // initializer referencing it fails to compile.
  late final List<PlayerInfo> _order = List.of(widget.hostServer.roster);

  List<String> get _slotLabels => switch (_order.length) {
        3 => const [
            'Seat 1 -- alone at the bottom on their own screen',
            'Seat 2 -- top-left',
            'Seat 3 -- top-right',
          ],
        4 => const [
            'Seat 1 -- bottom-left',
            'Seat 2 -- bottom-right',
            'Seat 3 -- top-left',
            'Seat 4 -- top-right',
          ],
        _ => [for (var i = 0; i < _order.length; i++) 'Seat ${i + 1}'],
      };

  /// Picking a player already in another slot swaps the two -- keeps
  /// [_order] a valid permutation at all times, so there's no separate
  /// "is this assignment valid" check needed before Start.
  void _assign(int slotIndex, String playerId) {
    final otherIndex = _order.indexWhere((p) => p.id == playerId);
    if (otherIndex == slotIndex) return;
    setState(() {
      final moved = _order[otherIndex];
      _order[otherIndex] = _order[slotIndex];
      _order[slotIndex] = moved;
    });
  }

  void _start() {
    widget.hostServer.setSeatOrder(_order.map((p) => p.id).toList());
    pushReplacementScreen(
      context,
      title: 'Choose a Game',
      builder: (_) => GameSelectScreen(hostServer: widget.hostServer, hostPlayerId: widget.hostPlayerId),
    );
  }

  /// A quick top-down text mockup of the resulting arrangement -- purely
  /// illustrative, mirrors the shape `computeHandRowLayout` renders on the
  /// actual table for every player once dealt.
  Widget _preview() {
    final top = _order.length == 4 ? _order.sublist(2) : _order.sublist(1);
    final bottom = _order.length == 4 ? _order.sublist(0, 2) : [_order[0]];
    Widget row(List<PlayerInfo> row) => Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (final p in row)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    CircleAvatar(radius: 6, backgroundColor: Color(p.color)),
                    const SizedBox(height: 4),
                    Text(p.name),
                  ],
                ),
              ),
          ],
        );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      decoration: BoxDecoration(border: Border.all(color: Colors.white24), borderRadius: BorderRadius.circular(8)),
      child: Column(
        children: [
          row(top),
          const Padding(padding: EdgeInsets.symmetric(vertical: 16), child: Text('(shared table)', style: TextStyle(color: Colors.white38))),
          row(bottom),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final labels = _slotLabels;
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
                _preview(),
                const SizedBox(height: 24),
                for (var i = 0; i < _order.length; i++)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(child: Text(labels[i])),
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
                  onPressed: _start,
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Start'),
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
