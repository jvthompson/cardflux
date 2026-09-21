import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../data/player_profile_settings.dart';
import '../data/reconnect_settings.dart';
import '../networking/game_client.dart';
import 'client_game_screen.dart';
import 'navigation.dart';

/// Shown when a Discord "join secret" is received (see
/// `DiscordSocialService.joinSecretReceived`) -- a friend accepted a game
/// invite, whether by clicking Join in their own Discord client (possibly
/// cold-launching Cardflux for them) or from within the app. Confirms with
/// the user, then connects and joins exactly like `JoinScreen` does for a
/// manually typed address -- [joinSecret] is simply `'host:port'`, the
/// same info `JoinScreen` would otherwise need typed in by hand.
Future<void> showDiscordJoinPrompt(BuildContext context, String joinSecret) async {
  final parts = joinSecret.split(':');
  if (parts.length != 2) return;
  final host = parts[0];
  final port = int.tryParse(parts[1]);
  if (host.isEmpty || port == null) return;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: const Text('Discord Game Invite'),
      content: Text('Join the Cardflux game at $host:$port?'),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Dismiss')),
        FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Join')),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  await pushScreen(context, title: 'Joining...', builder: (_) => _DiscordAutoJoinScreen(host: host, port: port));
}

class _DiscordAutoJoinScreen extends StatefulWidget {
  const _DiscordAutoJoinScreen({required this.host, required this.port});

  final String host;
  final int port;

  @override
  State<_DiscordAutoJoinScreen> createState() => _DiscordAutoJoinScreenState();
}

class _DiscordAutoJoinScreenState extends State<_DiscordAutoJoinScreen> {
  final GameClient _client = GameClient();
  StreamSubscription<ClientConnectionStatus>? _navSub;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _connect();
  }

  @override
  void dispose() {
    _navSub?.cancel();
    // ClientGameScreen owns the client's lifecycle from here on -- only
    // disconnect here if we're leaving without ever getting there.
    if (!_navigated) _client.disconnect();
    super.dispose();
  }

  Future<void> _connect() async {
    final hostKey = '${widget.host}:${widget.port}';
    _navSub = _client.statusStream.listen((status) {
      if (status == ClientConnectionStatus.connected) _navigateToGame(hostKey);
    });
    final profile = PlayerProfileSettings();
    final name = await profile.getName() ?? 'Player';
    final color = await profile.getColor() ?? 0xFF2196F3;
    final avatarPath = await profile.getAvatarPath();
    Uint8List? avatarBytes;
    if (avatarPath != null) {
      try {
        avatarBytes = await File(avatarPath).readAsBytes();
      } catch (_) {
        // No avatar available -- this client just shows the color fallback.
      }
    }
    // Same rejoin-offer logic as JoinScreen._connect.
    final rejoinPlayerId = await ReconnectSettings().getPlayerIdFor(hostKey);
    await _client.connect(
      widget.host,
      widget.port,
      name,
      color,
      localAvatarBytes: avatarBytes,
      rejoinPlayerId: rejoinPlayerId,
    );
    if (mounted) setState(() {});
  }

  void _navigateToGame(String hostKey) {
    if (_navigated || !mounted) return;
    final playerId = _client.assignedPlayerId;
    if (playerId == null) return;
    _navigated = true;
    unawaited(ReconnectSettings().save(hostKey: hostKey, playerId: playerId));
    pushReplacementScreen(
      context,
      title: 'Game',
      showBackButton: false,
      builder: (_) => ClientGameScreen(gameClient: _client, localPlayerId: playerId),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: StreamBuilder<ClientConnectionStatus>(
          stream: _client.statusStream,
          initialData: _client.status,
          builder: (context, snapshot) {
            final status = snapshot.data ?? ClientConnectionStatus.connecting;
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: switch (status) {
                ClientConnectionStatus.connecting => const [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Connecting...'),
                ],
                ClientConnectionStatus.connected => [
                  Text(
                    _client.reconnected
                        ? 'Reconnected to ${_client.opponentName ?? "host"}!'
                        : 'Connected to ${_client.opponentName ?? "host"}!',
                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                  ),
                ],
                ClientConnectionStatus.failed => [
                  Text('Failed to connect: ${_client.errorMessage}', style: const TextStyle(color: Colors.red)),
                  const SizedBox(height: 16),
                  OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                ],
                ClientConnectionStatus.disconnected => [
                  Text(
                    switch (_client.disconnectReason) {
                      'seatUnavailable' =>
                        "This game is already in progress and your seat couldn't be found. Make sure "
                            "you're joining the same host.",
                      _ => 'Disconnected from host.',
                    },
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
                ],
              },
            );
          },
        ),
      ),
    );
  }
}
