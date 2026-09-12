import 'dart:async';
import 'dart:io';

import 'net_message.dart';

enum ClientConnectionStatus { connecting, connected, failed, disconnected }

/// Connects to a hosting player's [HostServer] over TCP and completes the
/// hello/welcome handshake. Game-state messages (fullState/requestX) are
/// surfaced via [incoming] but not interpreted here -- that's wired into
/// GameSession once networking lands in gameplay (M4). Also runs a
/// [heartbeatInterval] ping/pong with the host (M6) so a silently-dead
/// connection is detected within [heartbeatTimeout] instead of relying on
/// the OS's TCP timeout.
class GameClient {
  Socket? _socket;
  StreamSubscription<NetMessage>? _sub;
  Timer? _heartbeatTimer;
  DateTime _lastActivity = DateTime.now();
  final _incomingController = StreamController<NetMessage>.broadcast();
  final _statusController = StreamController<ClientConnectionStatus>.broadcast();

  Stream<NetMessage> get incoming => _incomingController.stream;
  Stream<ClientConnectionStatus> get statusStream => _statusController.stream;

  String? opponentName;
  String? assignedPlayerId;
  int? assignedColor;
  ClientConnectionStatus status = ClientConnectionStatus.connecting;
  String? errorMessage;

  Future<void> connect(String host, int port, String localName, int localColor) async {
    status = ClientConnectionStatus.connecting;
    try {
      _socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
    } catch (e) {
      status = ClientConnectionStatus.failed;
      errorMessage = e.toString();
      _statusController.add(status);
      return;
    }

    _lastActivity = DateTime.now();
    _heartbeatTimer = Timer.periodic(heartbeatInterval, (_) => _onHeartbeatTick());
    _sub = decodeMessages(_socket!).listen(
      (msg) {
        _lastActivity = DateTime.now();
        if (msg.type == NetMessageType.ping) {
          send(NetMessage(type: NetMessageType.pong));
          return;
        }
        if (msg.type == NetMessageType.welcome) {
          opponentName = msg.payload['hostName'] as String?;
          assignedPlayerId = msg.payload['playerId'] as String?;
          assignedColor = msg.payload['assignedColor'] as int?;
          status = ClientConnectionStatus.connected;
          _statusController.add(status);
        }
        _incomingController.add(msg);
      },
      onDone: _handleDisconnect,
      onError: (_) => _handleDisconnect(),
    );

    send(NetMessage(type: NetMessageType.hello, payload: {'name': localName, 'color': localColor}));
  }

  void _onHeartbeatTick() {
    if (DateTime.now().difference(_lastActivity) > heartbeatTimeout) {
      // No traffic at all (not even a ping) within the timeout -- the host
      // is silently gone; force the socket closed so onDone/onError runs
      // the normal disconnect path.
      _socket?.destroy();
      return;
    }
    send(NetMessage(type: NetMessageType.ping));
  }

  void _handleDisconnect() {
    if (status == ClientConnectionStatus.disconnected) return;
    status = ClientConnectionStatus.disconnected;
    _statusController.add(status);
    _heartbeatTimer?.cancel();
  }

  void send(NetMessage msg) {
    _socket?.write(encodeLine(msg));
  }

  Future<void> disconnect() async {
    _heartbeatTimer?.cancel();
    await _sub?.cancel();
    _socket?.destroy();
    await _incomingController.close();
    await _statusController.close();
  }
}
