import 'package:flutter/material.dart';

import '../../models/player.dart';

/// The Escape-triggered in-game menu -- a modal overlay matching
/// `ZoneSearchOverlay`'s exact visual shape (a translucent scrim plus a
/// centered dark panel), letting either player leave the match gracefully,
/// and, host only, kick a currently-connected player. See
/// `TableScreen._handleKeyEvent` for how Escape toggles this and suppresses
/// every other keyboard shortcut while it's open, and how the scrim (same
/// as the search overlay's) blocks table interaction just by sitting on top
/// of it in the `Stack` -- no `IgnorePointer` needed.
class GameMenuOverlay extends StatelessWidget {
  const GameMenuOverlay({
    super.key,
    required this.onClose,
    required this.onLeaveGame,
    required this.leaveButtonLabel,
    required this.leaveConfirmationMessage,
    this.kickablePlayers = const [],
    this.onKickPlayer,
    this.onSaveGame,
  });

  final VoidCallback onClose;
  final VoidCallback onLeaveGame;

  /// The menu button's (and confirmation dialog's confirm button's) label
  /// -- e.g. "End Game" for the host (leaving ends the whole session) vs.
  /// "Leave Game" for a client or solo practice. Supplied by the caller
  /// (`HostGameScreen`/`ClientGameScreen`/`PracticeScreen`) rather than
  /// inferred here, since this widget has no way to tell "no one to kick"
  /// apart from "not networked at all" on its own.
  final String leaveButtonLabel;

  /// The confirmation dialog's body text -- role-appropriate copy chosen
  /// by the caller (see [leaveButtonLabel]'s doc).
  final String leaveConfirmationMessage;

  /// Every currently-connected non-host player, kickable via
  /// [onKickPlayer]. The "Kick a Player" section renders whenever
  /// [onKickPlayer] is non-null (true only for the host's own
  /// `TableScreen` instance), even when this list is currently empty, so
  /// the host can see the feature exists.
  final List<PlayerInfo> kickablePlayers;
  final void Function(String playerId)? onKickPlayer;

  /// Dumps the current table state to a JSON file for later reload -- see
  /// `SaveGameDialog`. Null for a client's own `TableScreen` instance (only
  /// the host's/practice player's session is authoritative/complete enough
  /// to be worth saving), same gating rationale as [onKickPlayer].
  final VoidCallback? onSaveGame;

  Future<void> _confirmLeave(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(leaveButtonLabel),
        content: Text(leaveConfirmationMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(leaveButtonLabel),
          ),
        ],
      ),
    );
    if (confirmed == true) onLeaveGame();
  }

  Future<void> _confirmKick(BuildContext context, PlayerInfo player) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Kick Player'),
        content: Text(
          'Remove ${player.name} from the game? They can rejoin later if '
          "you don't end the session.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Kick'),
          ),
        ],
      ),
    );
    if (confirmed == true) onKickPlayer?.call(player.id);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // Same light, non-opaque scrim as ZoneSearchOverlay's -- tapping it
        // closes the menu, same as the X button.
        Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.25)),
          ),
        ),
        Center(
          child: SizedBox(
            width: 360,
            child: Material(
              color: const Color(0xFF262626),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Game Menu',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          tooltip: 'Close',
                          onPressed: onClose,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white24),
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        OutlinedButton.icon(
                          icon: const Icon(Icons.logout),
                          label: Text(leaveButtonLabel),
                          onPressed: () => _confirmLeave(context),
                        ),
                        if (onSaveGame != null) ...[
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.save),
                            label: const Text('Save Game...'),
                            onPressed: onSaveGame,
                          ),
                        ],
                        if (onKickPlayer != null) ...[
                          const SizedBox(height: 20),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Kick a Player',
                              style: TextStyle(
                                color: Colors.white70,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (kickablePlayers.isEmpty)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 8),
                              child: Text(
                                'No other players connected right now.',
                                style: TextStyle(color: Colors.white54),
                              ),
                            )
                          else
                            for (final player in kickablePlayers)
                              ListTile(
                                contentPadding: EdgeInsets.zero,
                                title: Text(
                                  player.name,
                                  style: const TextStyle(color: Colors.white),
                                ),
                                trailing: IconButton(
                                  icon: const Icon(
                                    Icons.person_remove,
                                    color: Colors.redAccent,
                                  ),
                                  tooltip: 'Kick ${player.name}',
                                  onPressed: () => _confirmKick(context, player),
                                ),
                              ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
