import 'package:flutter/material.dart';

import 'host_setup_screen.dart';

/// Shown right after "Host Game": how many total players (including the
/// host) this match will have -- [HostSetupScreen] then waits for exactly
/// that many to be connected before letting the host proceed to game
/// selection.
class PlayerCountScreen extends StatelessWidget {
  const PlayerCountScreen({super.key, required this.localPlayerName, required this.localPlayerColor});

  final String localPlayerName;
  final int localPlayerColor;

  void _choose(BuildContext context, int maxPlayers) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => HostSetupScreen(
        localPlayerName: localPlayerName,
        localPlayerColor: localPlayerColor,
        maxPlayers: maxPlayers,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Host Game')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('How many players?', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                for (final count in [2, 3, 4]) ...[
                  FilledButton(
                    onPressed: () => _choose(context, count),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text('$count Players'),
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
