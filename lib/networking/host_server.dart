import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../models/color_palette.dart';
import '../models/player.dart';
import 'net_message.dart';

const _uuid = Uuid();

/// State for one connected (post-`hello`) client.
class _ConnectedClient {
  _ConnectedClient({required this.socket, required this.name, required this.color});

  final Socket socket;
  final String name;
  final int color;
  StreamSubscription<NetMessage>? sub;
  Timer? heartbeatTimer;
  DateTime lastActivity = DateTime.now();
}

/// Hosts a TCP session for 2-4 total players (this host plus up to
/// `maxPlayers - 1` clients): binds a port, accepts connections up to that
/// cap (rejecting any beyond it), and completes a hello/welcome handshake
/// per client. Game-state messages (fullState/requestX) are surfaced via
/// [incoming] -- tagged with which client actually sent them, since with
/// more than one client there's no single "the opponent" to assume -- but
/// not interpreted here; `HostGameEngine` owns applying them to the
/// authoritative table. Also runs a per-client [heartbeatInterval] ping/pong
/// (M6) so a silently-dead connection (as opposed to a clean process exit,
/// which the socket's own `onDone`/`onError` already reports immediately) is
/// detected within [heartbeatTimeout] instead of relying on the OS's TCP
/// timeout.
class HostServer {
  ServerSocket? _serverSocket;
  final Map<String, _ConnectedClient> _clients = {};
  final _incomingController = StreamController<IncomingMessage>.broadcast();
  final _rosterController = StreamController<List<PlayerInfo>>.broadcast();

  Stream<IncomingMessage> get incoming => _incomingController.stream;
  Stream<List<PlayerInfo>> get rosterStream => _rosterController.stream;

  late final PlayerInfo hostPlayer;
  late final int maxPlayers;
  Uint8List? _hostAvatarBytes;

  /// Every known player's avatar bytes, keyed by player id -- host plus
  /// every client that has ever sent one via `hello`. Deliberately backed by
  /// a separate map from [_clients] (populated in [_handleClient], never
  /// pruned in [_handleClientDisconnect]): a disconnected 3-4 player seat
  /// stays in `TableState.players` (with `PlayerInfo.connected` false) and
  /// should keep showing its avatar rather than losing it the moment its
  /// socket drops.
  final Map<String, Uint8List> _avatarBytesByPlayerId = {};

  Map<String, Uint8List> get avatarsByPlayerId => {
        hostPlayer.id: ?_hostAvatarBytes,
        ..._avatarBytesByPlayerId,
      };

  /// Host-chosen seat order (player ids), set via [setSeatOrder] once the
  /// lobby is full (see `AssignSeatsScreen`) -- null means "use join order"
  /// (today's default, and the only option for a 2-player match, which has
  /// no `AssignSeatsScreen` step at all).
  List<String>? _seatOrder;

  /// Reorders [roster] by [orderedPlayerIds] (every currently-connected
  /// player's id, in the desired seat order) -- every downstream reader of
  /// [roster] (`GameSelectScreen`, `HostLoadDeckScreen`,
  /// `HostGameScreen._init`) picks this up automatically with no code
  /// changes of their own, since none of them cache seat order themselves.
  void setSeatOrder(List<String> orderedPlayerIds) {
    _seatOrder = orderedPlayerIds;
  }

  /// Host first, then every currently-connected client in join order (a
  /// `Map`'s iteration order is insertion order), reordered by
  /// [_seatOrder] once the host has assigned seats -- the stable ordering
  /// `HostGameScreen`/`HostLoadDeckScreen` build seat indices and
  /// `computeHandRowLayout` from. A disconnected client drops out of this
  /// list entirely (freeing its slot for a new joiner) -- this is a
  /// lobby/live-connection concept only; once dealt, `TableState.players`
  /// (built once from this list at deal time) is the durable seat/identity
  /// record instead and no longer shrinks.
  List<PlayerInfo> get roster {
    final joinOrder = [
      hostPlayer,
      for (final entry in _clients.entries)
        PlayerInfo(id: entry.key, name: entry.value.name, role: PlayerRole.client, color: entry.value.color),
    ];
    final order = _seatOrder;
    if (order == null) return joinOrder;
    final byId = {for (final p in joinOrder) p.id: p};
    return [for (final id in order) if (byId[id] != null) byId[id]!];
  }

  /// Binds to all interfaces on [port] and returns the bound port. Resolves
  /// once bound; does not wait for any client to connect.
  Future<int> start({
    required PlayerInfo hostPlayer,
    required int maxPlayers,
    Uint8List? hostAvatarBytes,
    int port = defaultGamePort,
  }) async {
    this.hostPlayer = hostPlayer;
    this.maxPlayers = maxPlayers;
    _hostAvatarBytes = hostAvatarBytes;
    _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    _serverSocket!.listen(_handleClient);
    return _serverSocket!.port;
  }

  /// If [requested] is unclaimed by the host or any currently-connected
  /// client, keeps it; otherwise silently reassigns the first unclaimed
  /// [boardWidgetColorPalette] entry -- a joining client displays whatever
  /// color it's actually told back in `welcome`, not necessarily what it
  /// asked for.
  int _resolveColor(int? requested) {
    final used = {hostPlayer.color, for (final c in _clients.values) c.color};
    if (requested != null && !used.contains(requested)) return requested;
    for (final c in boardWidgetColorPalette) {
      if (!used.contains(c)) return c;
    }
    return requested ?? boardWidgetColorPalette.first;
  }

  void _handleClient(Socket socket) {
    if (_clients.length >= maxPlayers - 1) {
      socket.destroy();
      return;
    }
    String? playerId;
    late final StreamSubscription<NetMessage> sub;
    sub = decodeMessages(socket).listen(
      (msg) {
        final id = playerId;
        if (id == null) {
          // Only a hello is meaningful before a playerId is assigned.
          if (msg.type != NetMessageType.hello) return;
          if (_clients.length >= maxPlayers - 1) {
            socket.destroy();
            return;
          }
          final name = msg.payload['name'] as String? ?? 'Player';
          final color = _resolveColor(msg.payload['color'] as int?);
          final newId = _uuid.v4();
          playerId = newId;
          final avatarB64 = msg.payload['avatar'] as String?;
          if (avatarB64 != null) {
            try {
              _avatarBytesByPlayerId[newId] = base64Decode(avatarB64);
            } catch (_) {
              // Ignore a malformed avatar payload -- the player still joins.
            }
          }
          final client = _ConnectedClient(socket: socket, name: name, color: color)
            ..sub = sub
            ..heartbeatTimer = Timer.periodic(heartbeatInterval, (_) => _onHeartbeatTick(newId));
          _clients[newId] = client;
          sendTo(
            newId,
            NetMessage(
              type: NetMessageType.welcome,
              payload: {'hostName': hostPlayer.name, 'playerId': newId, 'assignedColor': color},
            ),
          );
          _broadcastRoster();
          return;
        }
        final client = _clients[id];
        if (client == null) return;
        client.lastActivity = DateTime.now();
        if (msg.type == NetMessageType.ping) {
          sendTo(id, const NetMessage(type: NetMessageType.pong));
          return;
        }
        _incomingController.add(IncomingMessage(senderId: id, message: msg));
      },
      onDone: () {
        final id = playerId;
        if (id != null) _handleClientDisconnect(id);
      },
      onError: (_) {
        final id = playerId;
        if (id != null) _handleClientDisconnect(id);
      },
    );
  }

  void _onHeartbeatTick(String playerId) {
    final client = _clients[playerId];
    if (client == null) return;
    if (DateTime.now().difference(client.lastActivity) > heartbeatTimeout) {
      // No traffic at all (not even a ping) within the timeout -- this
      // client is silently gone; force the socket closed so onDone/onError
      // runs the normal disconnect path.
      client.socket.destroy();
      return;
    }
    sendTo(playerId, const NetMessage(type: NetMessageType.ping));
  }

  void _handleClientDisconnect(String playerId) {
    final client = _clients.remove(playerId);
    if (client == null) return;
    client.heartbeatTimer?.cancel();
    _broadcastRoster();
  }

  void _broadcastRoster() {
    final r = roster;
    _rosterController.add(r);
    broadcast(
      NetMessage(
        type: NetMessageType.lobbyRosterUpdate,
        payload: {
          'maxPlayers': maxPlayers,
          'players': r.map((p) => p.toJson()).toList(),
          'avatars': {for (final e in avatarsByPlayerId.entries) e.key: base64Encode(e.value)},
        },
      ),
    );
  }

  void sendTo(String playerId, NetMessage msg) {
    _clients[playerId]?.socket.write(encodeLine(msg));
  }

  void broadcast(NetMessage msg, {String? exceptPlayerId}) {
    for (final entry in _clients.entries) {
      if (entry.key == exceptPlayerId) continue;
      entry.value.socket.write(encodeLine(msg));
    }
  }

  Future<void> stop() async {
    for (final client in _clients.values) {
      client.heartbeatTimer?.cancel();
      await client.sub?.cancel();
      client.socket.destroy();
    }
    _clients.clear();
    await _serverSocket?.close();
    await _incomingController.close();
    await _rosterController.close();
  }
}
