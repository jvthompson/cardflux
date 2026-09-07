import 'dart:async';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../networking/host_server.dart';
import '../networking/network_info.dart';
import 'game_select_screen.dart';

const _uuid = Uuid();

/// Binds a [HostServer], shows the host's LAN IP address(es) and port for
/// the opponent to join, and once connected navigates to [HostGameScreen]
/// to actually start the match.
class HostSetupScreen extends StatefulWidget {
  const HostSetupScreen({super.key, required this.localPlayerName});

  final String localPlayerName;

  @override
  State<HostSetupScreen> createState() => _HostSetupScreenState();
}

class _HostSetupScreenState extends State<HostSetupScreen> {
  final HostServer _server = HostServer();
  final String _hostPlayerId = _uuid.v4();
  List<String> _addresses = [];
  int? _port;
  String? _startError;
  StreamSubscription<HostConnectionStatus>? _navSub;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    try {
      final addresses = await localIPv4Addresses();
      final port = await _server.start(localName: widget.localPlayerName);
      if (!mounted) return;
      setState(() {
        _addresses = addresses;
        _port = port;
      });
      _navSub = _server.statusStream.listen((status) {
        if (status == HostConnectionStatus.connected) _navigateToGame();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _startError = e.toString());
    }
  }

  void _navigateToGame() {
    if (_navigated || !mounted) return;
    _navigated = true;
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => GameSelectScreen(hostServer: _server, hostPlayerId: _hostPlayerId),
    ));
  }

  @override
  void dispose() {
    _navSub?.cancel();
    // GameSelectScreen/DeckBuildScreen/HostGameScreen own the server's
    // lifecycle from here on -- only stop it here if we're leaving without
    // ever getting there.
    if (!_navigated) _server.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Host Game')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _startError != null
                ? Text('Failed to start hosting: $_startError', style: const TextStyle(color: Colors.red))
                : _port == null
                    ? const CircularProgressIndicator()
                    : StreamBuilder<HostConnectionStatus>(
                        stream: _server.statusStream,
                        initialData: _server.status,
                        builder: (context, snapshot) {
                          final status = snapshot.data ?? HostConnectionStatus.waiting;
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('Share this with your opponent:', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              if (_addresses.isEmpty)
                                const Text('No network interfaces found -- try 127.0.0.1 for same-machine testing.')
                              else
                                for (final addr in _addresses)
                                  SelectableText('$addr : $_port', style: const TextStyle(fontSize: 16)),
                              const SizedBox(height: 32),
                              switch (status) {
                                HostConnectionStatus.waiting => const Column(
                                    children: [
                                      CircularProgressIndicator(),
                                      SizedBox(height: 16),
                                      Text('Waiting for opponent to join...'),
                                    ],
                                  ),
                                HostConnectionStatus.connected => Text(
                                    'Connected to ${_server.opponentName ?? "opponent"}!',
                                    style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold),
                                  ),
                                HostConnectionStatus.disconnected => const Text(
                                    'Opponent disconnected.',
                                    style: TextStyle(color: Colors.red),
                                  ),
                              },
                            ],
                          );
                        },
                      ),
          ),
        ),
      ),
    );
  }
}
