import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../networking/game_client.dart';
import '../networking/net_message.dart';
import 'client_game_screen.dart';

/// Lets the joining player enter the host's IP address and port, connects a
/// [GameClient], and once connected navigates to [ClientGameScreen] to
/// actually start the match.
class JoinScreen extends StatefulWidget {
  const JoinScreen({
    super.key,
    required this.localPlayerName,
    required this.localPlayerColor,
    this.localAvatarPath,
  });

  final String localPlayerName;
  final int localPlayerColor;
  final String? localAvatarPath;

  @override
  State<JoinScreen> createState() => _JoinScreenState();
}

class _JoinScreenState extends State<JoinScreen> {
  final _ipController = TextEditingController();
  final _portController = TextEditingController(text: '$defaultGamePort');
  final GameClient _client = GameClient();
  bool _connecting = false;
  StreamSubscription<ClientConnectionStatus>? _navSub;
  bool _navigated = false;

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _navSub?.cancel();
    // ClientGameScreen owns the client's lifecycle from here on -- only
    // disconnect here if we're leaving without ever getting there.
    if (!_navigated) _client.disconnect();
    super.dispose();
  }

  Future<void> _connect() async {
    // Left blank -- assume same-machine testing rather than making the user
    // type it every time.
    final typed = _ipController.text.trim();
    final host = typed.isEmpty ? '127.0.0.1' : typed;
    final port = int.tryParse(_portController.text.trim()) ?? defaultGamePort;
    setState(() => _connecting = true);
    _navSub = _client.statusStream.listen((status) {
      if (status == ClientConnectionStatus.connected) _navigateToGame();
    });
    Uint8List? avatarBytes;
    final avatarPath = widget.localAvatarPath;
    if (avatarPath != null) {
      try {
        avatarBytes = await File(avatarPath).readAsBytes();
      } catch (_) {
        // No avatar available -- this client just shows the color fallback.
      }
    }
    await _client.connect(
      host,
      port,
      widget.localPlayerName,
      widget.localPlayerColor,
      localAvatarBytes: avatarBytes,
    );
    if (mounted) setState(() {});
  }

  void _navigateToGame() {
    if (_navigated || !mounted) return;
    final playerId = _client.assignedPlayerId;
    if (playerId == null) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ClientGameScreen(gameClient: _client, localPlayerId: playerId),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Join Game')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: !_connecting
                ? Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextField(
                        controller: _ipController,
                        decoration: const InputDecoration(
                          labelText: 'Host IP address',
                          hintText: 'e.g. 192.168.1.42 -- blank = 127.0.0.1',
                          border: OutlineInputBorder(),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _portController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(labelText: 'Port', border: OutlineInputBorder()),
                      ),
                      const SizedBox(height: 24),
                      FilledButton(
                        onPressed: _connect,
                        child: const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text('Connect'),
                        ),
                      ),
                    ],
                  )
                : StreamBuilder<ClientConnectionStatus>(
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
                                'Connected to ${_client.opponentName ?? "host"}!',
                                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                              ),
                            ],
                          ClientConnectionStatus.failed => [
                              Text('Failed to connect: ${_client.errorMessage}', style: const TextStyle(color: Colors.red)),
                              const SizedBox(height: 16),
                              OutlinedButton(
                                onPressed: () => setState(() => _connecting = false),
                                child: const Text('Try again'),
                              ),
                            ],
                          ClientConnectionStatus.disconnected => const [
                              Text('Disconnected from host.', style: TextStyle(color: Colors.red)),
                            ],
                        },
                      );
                    },
                  ),
          ),
        ),
      ),
    );
  }
}
