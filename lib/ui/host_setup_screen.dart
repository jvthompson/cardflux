import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/player.dart';
import '../networking/host_server.dart';
import '../networking/network_info.dart';
import 'assign_seats_screen.dart';
import 'game_select_screen.dart';
import 'navigation.dart';

const _uuid = Uuid();

/// Binds a [HostServer] for [maxPlayers] total players, shows the host's LAN
/// IP address(es) plus their public IP (for players joining over the
/// internet) and port for the other player(s) to join, and once the full
/// roster (this host plus `maxPlayers - 1` clients) is connected, navigates
/// to [GameSelectScreen] to actually start the match.
class HostSetupScreen extends StatefulWidget {
  const HostSetupScreen({
    super.key,
    required this.localPlayerName,
    required this.localPlayerColor,
    this.localAvatarPath,
    required this.maxPlayers,
  });

  final String localPlayerName;
  final int localPlayerColor;
  final String? localAvatarPath;
  final int maxPlayers;

  @override
  State<HostSetupScreen> createState() => _HostSetupScreenState();
}

class _HostSetupScreenState extends State<HostSetupScreen> {
  final HostServer _server = HostServer();
  final String _hostPlayerId = _uuid.v4();
  List<String> _addresses = [];
  int? _port;
  String? _startError;
  String? _publicIP;
  bool _publicIPLoading = true;
  StreamSubscription<List<PlayerInfo>>? _rosterSub;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _start();
    _loadPublicIP();
  }

  Future<void> _loadPublicIP() async {
    final ip = await fetchPublicIPv4();
    if (!mounted) return;
    setState(() {
      _publicIP = ip;
      _publicIPLoading = false;
    });
  }

  Future<void> _start() async {
    try {
      final addresses = await localIPv4Addresses();
      Uint8List? avatarBytes;
      final avatarPath = widget.localAvatarPath;
      if (avatarPath != null) {
        try {
          avatarBytes = await File(avatarPath).readAsBytes();
        } catch (_) {
          // No avatar available -- the host just shows the color fallback.
        }
      }
      final port = await _server.start(
        hostPlayer: PlayerInfo(
          id: _hostPlayerId,
          name: widget.localPlayerName,
          role: PlayerRole.host,
          color: widget.localPlayerColor,
        ),
        maxPlayers: widget.maxPlayers,
        hostAvatarBytes: avatarBytes,
      );
      if (!mounted) return;
      setState(() {
        _addresses = addresses;
        _port = port;
      });
      _rosterSub = _server.rosterStream.listen((roster) {
        if (roster.length >= widget.maxPlayers) _navigateToGame();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _startError = e.toString());
    }
  }

  void _navigateToGame() {
    if (_navigated || !mounted) return;
    _navigated = true;
    // A 2-player match has exactly one sensible seating (host bottom,
    // client top) -- skip straight to game selection, same as before
    // AssignSeatsScreen existed.
    pushReplacementScreen(
      context,
      title: widget.maxPlayers > 2 ? 'Assign Seats' : 'Choose a Game',
      builder: (_) => widget.maxPlayers > 2
          ? AssignSeatsScreen(hostServer: _server, hostPlayerId: _hostPlayerId)
          : GameSelectScreen(hostServer: _server, hostPlayerId: _hostPlayerId),
    );
  }

  @override
  void dispose() {
    _rosterSub?.cancel();
    // GameSelectScreen/HostLoadDeckScreen/HostGameScreen own the server's
    // lifecycle from here on -- only stop it here if we're leaving without
    // ever getting there.
    if (!_navigated) _server.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: _startError != null
                ? Text('Failed to start hosting: $_startError', style: const TextStyle(color: Colors.red))
                : _port == null
                    ? const CircularProgressIndicator()
                    : StreamBuilder<List<PlayerInfo>>(
                        stream: _server.rosterStream,
                        initialData: _server.roster,
                        builder: (context, snapshot) {
                          final roster = snapshot.data ?? _server.roster;
                          final waitingFor = widget.maxPlayers - roster.length;
                          return Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const Text('Same network (LAN):', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              if (_addresses.isEmpty)
                                const Text('No network interfaces found -- try 127.0.0.1 for same-machine testing.')
                              else
                                for (final addr in _addresses)
                                  SelectableText('$addr : $_port', style: const TextStyle(fontSize: 16)),
                              const SizedBox(height: 16),
                              const Text('Over the internet:', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              if (_publicIPLoading)
                                const Text('Looking up public IP...')
                              else if (_publicIP == null)
                                const Text("Couldn't determine your public IP -- check your internet connection.")
                              else ...[
                                SelectableText('$_publicIP : $_port', style: const TextStyle(fontSize: 16)),
                                const SizedBox(height: 4),
                                const Text(
                                  "Requires port-forwarding this port to this PC on your router.",
                                  style: TextStyle(fontSize: 12, color: Colors.grey),
                                ),
                              ],
                              const SizedBox(height: 24),
                              const Text('Players:', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 8),
                              for (final p in roster)
                                Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 4),
                                  child: Row(
                                    children: [
                                      CircleAvatar(radius: 6, backgroundColor: Color(p.color)),
                                      const SizedBox(width: 8),
                                      Text(p.name),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 24),
                              if (waitingFor > 0) ...[
                                const CircularProgressIndicator(),
                                const SizedBox(height: 16),
                                Text('Waiting for $waitingFor more player${waitingFor == 1 ? '' : 's'}...'),
                              ],
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
