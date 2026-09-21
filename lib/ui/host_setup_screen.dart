import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/player.dart';
import '../networking/host_server.dart';
import '../networking/network_info.dart';
import '../services/discord/discord_presence_service.dart';
import '../services/discord/discord_social_service.dart';
import 'assign_seats_screen.dart';
import 'game_select_screen.dart';
import 'navigation.dart';

const _uuid = Uuid();

enum _ShareMode { manual, discord }

/// Binds a [HostServer] for [maxPlayers] total players, shows the host's LAN
/// IP address(es) plus their public IP (for players joining over the
/// internet) and port for the other player(s) to join -- or, in "Invite via
/// Discord" mode, lets the host send a Discord activity invite straight to
/// a friend instead of sharing the address by hand -- and once the full
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

  /// Identifies this hosted session across Discord's activity Party --
  /// only needs to be unique per session, reusing the same `uuid` package
  /// already used for `_hostPlayerId`.
  final String _partyId = _uuid.v4();

  _ShareMode _mode = _ShareMode.manual;
  bool _discordConnecting = false;
  String? _discordError;
  List<DiscordFriend>? _friends;
  final Set<int> _invitedFriendIds = {};

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
    _publishHostingPresence();
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
      _publishHostingPresence();
      _rosterSub = _server.rosterStream.listen((roster) {
        _publishHostingPresence();
        if (roster.length >= widget.maxPlayers) _navigateToGame();
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _startError = e.toString());
    }
  }

  /// Publishes Rich Presence with Party/Secrets info so a Discord invite
  /// (or "Ask to Join" on this host's profile) carries enough to actually
  /// connect a friend -- a no-op until both the port and public IP are
  /// known, and again whenever the roster changes (so the party size shown
  /// in Discord stays current).
  void _publishHostingPresence() {
    final port = _port;
    final ip = _publicIP;
    if (port == null || ip == null) return;
    DiscordPresenceService.instance.setPlaying(
      gameName: 'a game',
      playerCount: _server.roster.length,
      maxPlayers: widget.maxPlayers,
      party: DiscordPartyInfo(
        partyId: _partyId,
        currentSize: _server.roster.length,
        maxSize: widget.maxPlayers,
        joinSecret: '$ip:$port',
      ),
    );
  }

  Future<void> _openInviteMode() async {
    if (_friends != null || _discordConnecting) return;
    setState(() {
      _discordConnecting = true;
      _discordError = null;
    });
    final ok = await DiscordSocialService.instance.ensureAuthorizedAndConnected();
    if (!mounted) return;
    if (!ok) {
      setState(() {
        _discordConnecting = false;
        _discordError = "Couldn't connect to Discord -- try again.";
      });
      return;
    }
    final friends = await DiscordSocialService.instance.fetchInvitableFriends();
    if (!mounted) return;
    setState(() {
      _friends = friends;
      _discordConnecting = false;
    });
  }

  Future<void> _sendInvite(DiscordFriend friend) async {
    final ip = _publicIP;
    final port = _port;
    if (ip == null || port == null) return;
    final sent = await DiscordSocialService.instance.sendGameInvite(friendUserId: friend.userId, joinSecret: '$ip:$port');
    if (!mounted) return;
    if (sent) {
      setState(() => _invitedFriendIds.add(friend.userId));
    } else {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Couldn't send an invite to ${friend.displayName} -- try again.")));
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
                              SegmentedButton<_ShareMode>(
                                segments: const [
                                  ButtonSegment(value: _ShareMode.manual, label: Text('Manual IP')),
                                  ButtonSegment(value: _ShareMode.discord, label: Text('Invite via Discord')),
                                ],
                                selected: {_mode},
                                onSelectionChanged: (selection) {
                                  setState(() => _mode = selection.first);
                                  if (_mode == _ShareMode.discord) _openInviteMode();
                                },
                              ),
                              const SizedBox(height: 16),
                              if (_mode == _ShareMode.manual) _buildManualPanel() else _buildDiscordPanel(),
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

  Widget _buildManualPanel() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Same network (LAN):', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        if (_addresses.isEmpty)
          const Text('No network interfaces found -- try 127.0.0.1 for same-machine testing.')
        else
          for (final addr in _addresses) SelectableText('$addr : $_port', style: const TextStyle(fontSize: 16)),
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
      ],
    );
  }

  Widget _buildDiscordPanel() {
    if (_discordConnecting) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [CircularProgressIndicator(), SizedBox(height: 12), Text('Connecting to Discord...')],
      );
    }
    if (_discordError != null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(_discordError!, style: const TextStyle(color: Colors.red)),
          const SizedBox(height: 12),
          OutlinedButton(onPressed: _openInviteMode, child: const Text('Retry')),
        ],
      );
    }
    final friends = _friends;
    if (friends == null) return const SizedBox.shrink();
    if (friends.isEmpty) {
      return const Text('No Discord friends found to invite.');
    }
    final publicIpReady = _publicIP != null && _port != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('Invite a friend:', style: TextStyle(fontWeight: FontWeight.bold)),
        if (!publicIpReady) ...[
          const SizedBox(height: 8),
          Text(_publicIPLoading ? 'Looking up public IP...' : "Couldn't determine your public IP.", style: const TextStyle(fontSize: 12)),
        ],
        const SizedBox(height: 8),
        for (final friend in friends)
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              backgroundImage: friend.avatarUrl != null ? NetworkImage(friend.avatarUrl!) : null,
              child: friend.avatarUrl == null ? Text(friend.username.substring(0, 1).toUpperCase()) : null,
            ),
            title: Text(friend.displayName),
            subtitle: Text(_statusLabel(friend.status)),
            trailing: _invitedFriendIds.contains(friend.userId)
                ? const Chip(label: Text('Invite sent'))
                : FilledButton(
                    onPressed: publicIpReady ? () => _sendInvite(friend) : null,
                    child: const Text('Invite'),
                  ),
          ),
      ],
    );
  }

  /// `Discord_StatusType` (cdiscord.h): Online=0, Offline=1, Blocked=2,
  /// Idle=3, Dnd=4, Invisible=5, Streaming=6, Unknown=7. An Invisible
  /// friend is reported as Offline to us (see `DiscordFriend`'s doc) --
  /// shown as "Offline" here too since that's genuinely all we know.
  String _statusLabel(int status) => switch (status) {
    0 => 'Online',
    1 => 'Offline',
    3 => 'Idle',
    4 => 'Do Not Disturb',
    6 => 'Streaming',
    _ => '',
  };
}
