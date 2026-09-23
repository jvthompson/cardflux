import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:uuid/uuid.dart';

import '../models/color_palette.dart';
import '../models/player.dart';
import 'net_message.dart';
import 'upnp_port_mapper.dart';

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
/// timeout. Also kicks off a best-effort [UpnpPortMapper] attempt (see
/// [upnpMapped]) to forward the bound port on the LAN's router automatically
/// -- unlike a manually-configured router rule, this lets more than one PC
/// on the same LAN host a game over the internet at the same time, since
/// each one maps its own port rather than sharing a single fixed rule.
class HostServer {
  ServerSocket? _serverSocket;
  final Map<String, _ConnectedClient> _clients = {};
  final _incomingController = StreamController<IncomingMessage>.broadcast();
  final _rosterController = StreamController<List<PlayerInfo>>.broadcast();

  Stream<IncomingMessage> get incoming => _incomingController.stream;
  Stream<List<PlayerInfo>> get rosterStream => _rosterController.stream;

  /// The bound port, once [start] has resolved -- e.g. for `HostGameScreen`
  /// to republish the Discord invite join secret across a hosted session
  /// without needing it threaded through as a constructor parameter.
  int? get port => _serverSocket?.port;

  final UpnpPortMapper _upnpMapper = UpnpPortMapper();

  /// Resolves once the automatic UPnP port-forwarding attempt kicked off by
  /// [start] has settled: true if the LAN's router accepted a mapping of
  /// this session's port straight to this machine, false if there's no
  /// UPnP-capable gateway or it refused (UPnP disabled, an unmanageable
  /// double-NAT, etc). Never awaited by [start] itself -- gateway discovery
  /// can take a couple of seconds and hosting on the LAN works regardless
  /// -- so `HostSetupScreen` shows this as a background status update
  /// rather than blocking the lobby on it. Either way the host's public
  /// `ip:port` (already shown for manual forwarding) stays correct: a
  /// successful mapping just means that port-forward now also happens to
  /// already be in place.
  Future<bool> get upnpMapped => _upnpMappedCompleter.future;
  final _upnpMappedCompleter = Completer<bool>();

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

  /// Set by `HostGameEngine` once a game has been dealt: given a candidate
  /// id a connecting client's `hello` presents as `rejoinPlayerId`, returns
  /// true if it's a real, currently-disconnected seat in the live
  /// `GameSession` that this new socket should be allowed to reclaim
  /// instead of being minted a brand-new id -- see [_handleClient]. Left
  /// null before a game exists (nothing to reclaim yet) or after the
  /// session ends, in which case a rejoin request always falls back to a
  /// fresh id, exactly like any other new connection. Once non-null, a
  /// `hello` that fails to reclaim a seat is rejected outright (a
  /// `disconnect` with reason `'seatUnavailable'`, then the socket is
  /// destroyed) instead of being admitted with a fresh id -- a game already
  /// in progress has no such thing as "a brand-new player," only seats
  /// dealt at match start, so a fresh id here could never receive a
  /// `fullState` and would be a silent dead end. Deliberately typed with no
  /// `GameSession`/game-model dependency -- this class stays a pure
  /// networking layer.
  bool Function(String candidateId)? reclaimableIdCheck;

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
    final boundPort = _serverSocket!.port;
    _upnpMapper.requestMapping(port: boundPort).then(_upnpMappedCompleter.complete);
    return boundPort;
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
          final rejoinId = msg.payload['rejoinPlayerId'] as String?;
          final reclaimed = rejoinId != null && (reclaimableIdCheck?.call(rejoinId) ?? false);
          if (reclaimableIdCheck != null && !reclaimed) {
            // A game is already dealt (reclaimableIdCheck only gets set once
            // true, by HostGameEngine.start) and this hello didn't match a
            // currently-disconnected seat -- reject outright rather than
            // minting a new id and admitting a connection that could never
            // receive a fullState (HostGameEngine._broadcast only ever
            // iterates the durable, deal-time-fixed session.state.players
            // list, which this new id would never be part of).
            socket.write(
              encodeLine(
                const NetMessage(
                  type: NetMessageType.disconnect,
                  payload: {'reason': 'seatUnavailable'},
                ),
              ),
            );
            socket.destroy();
            return;
          }
          final name = msg.payload['name'] as String? ?? 'Player';
          final color = _resolveColor(msg.payload['color'] as int?);
          final newId = reclaimed ? rejoinId : _uuid.v4();
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
              payload: {
                'hostName': hostPlayer.name,
                'playerId': newId,
                'assignedColor': color,
                'reconnected': reclaimed,
              },
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

  /// Forcibly disconnects [playerId] -- e.g. the host removing a disruptive
  /// player via the in-game menu. Silently does nothing if that id isn't
  /// currently connected. Sends a [NetMessageType.disconnect] with a
  /// `'kicked'` reason first so that client can show a specific message
  /// (see `GameClient.disconnectReason`) instead of a generic dropped-
  /// connection one, then destroys the socket -- the normal `onDone`
  /// disconnect path (`_handleClientDisconnect`) takes it from there,
  /// exactly like a heartbeat-timeout forced close already does.
  void kick(String playerId) {
    if (!_clients.containsKey(playerId)) return;
    sendTo(
      playerId,
      const NetMessage(
        type: NetMessageType.disconnect,
        payload: {'reason': 'kicked'},
      ),
    );
    _clients[playerId]?.socket.destroy();
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
    // Best-effort and not awaited: if the mapping attempt is still in
    // flight (discovery/SOAP round-trips can take several seconds), don't
    // hold up whatever navigated away and triggered this stop -- an
    // orphaned mapping just gets silently overwritten the next time this
    // machine hosts on the same port.
    unawaited(_releaseUpnpMappingIfActive());
    await _serverSocket?.close();
    await _incomingController.close();
    await _rosterController.close();
  }

  Future<void> _releaseUpnpMappingIfActive() async {
    if (await upnpMapped) await _upnpMapper.releaseMapping();
  }
}
