import 'package:flutter/material.dart';

import 'navigation.dart';
import 'practice_game_select_screen.dart';

/// Shown right after "Practice Offline": how many decks (1-4) to simulate at
/// this one device -- [PracticeGameSelectScreen] then lets you pick which
/// game and assign a deck to each simulated seat, all controlled by the one
/// real player. Mirrors [PlayerCountScreen]'s shape, but offers 1 (matching
/// today's single-deck practice) through 4, since there's no live roster to
/// wait for.
class PracticePlayerCountScreen extends StatelessWidget {
  const PracticePlayerCountScreen({
    super.key,
    required this.localPlayerName,
    required this.localPlayerColor,
    this.localAvatarPath,
  });

  final String localPlayerName;
  final int localPlayerColor;
  final String? localAvatarPath;

  void _choose(BuildContext context, int playerCount) {
    pushScreen(
      context,
      title: 'Choose a Game',
      builder: (_) => PracticeGameSelectScreen(
        playerCount: playerCount,
        localPlayerName: localPlayerName,
        localPlayerColor: localPlayerColor,
        localAvatarPath: localAvatarPath,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('How many decks?', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                for (final count in [1, 2, 3, 4]) ...[
                  FilledButton(
                    onPressed: () => _choose(context, count),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(count == 1 ? '1 Player' : '$count Players'),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
