import 'dart:async';
import 'dart:io';

import 'net_message.dart';

enum ClientConnectionStatus { connecting, connected, failed, disconnected }

/// Connects to a hosting player's [HostServer] over TCP and completes the
/// hello/welcome handshake. Game-state messages (fullState/requestX) are
/// surfaced via [incoming] but not interpreted here -- that's wired into
/// GameSession once networking lands in gameplay (M4).
class GameClient {
  Socket? _socket;
  StreamSubscription<NetMessage>? _sub;
  final _incomingController = StreamController<NetMessage>.broadcast();
  final _statusController = StreamController<ClientConnectionStatus>.broadcast();

  Stream<NetMessage> get incoming => _incomingController.stream;
  Stream<ClientConnectionStatus> get statusStream => _statusController.stream;

  String? opponentName;
  String? assignedPlayerId;
  ClientConnectionStatus status = ClientConnectionStatus.connecting;
  String? errorMessage;

  Future<void> connect(String host, int port, String localName) async {
    status = ClientConnectionStatus.connecting;
    try {
      _socket = await Socket.connect(host, port, timeout: const Duration(seconds: 5));
    } catch (e) {
      status = ClientConnectionStatus.failed;
      errorMessage = e.toString();
      _statusController.add(status);
      return;
    }

    _sub = decodeMessages(_socket!).listen(
      (msg) {
        if (msg.type == NetMessageType.welcome) {
          opponentName = msg.payload['name'] as String?;
          assignedPlayerId = msg.payload['playerId'] as String?;
          status = ClientConnectionStatus.connected;
          _statusController.add(status);
        }
        _incomingController.add(msg);
      },
      onDone: _handleDisconnect,
      onError: (_) => _handleDisconnect(),
    );

    send(NetMessage(type: NetMessageType.hello, payload: {'name': localName}));
  }

  void _handleDisconnect() {
    status = ClientConnectionStatus.disconnected;
    _statusController.add(status);
  }

  void send(NetMessage msg) {
    _socket?.write(encodeLine(msg));
  }

  Future<void> disconnect() async {
    await _sub?.cancel();
    _socket?.destroy();
    await _incomingController.close();
    await _statusController.close();
  }
}
