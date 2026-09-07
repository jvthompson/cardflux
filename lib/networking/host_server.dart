import 'dart:async';
import 'dart:io';

import 'package:uuid/uuid.dart';

import 'net_message.dart';

const _uuid = Uuid();

enum HostConnectionStatus { waiting, connected, disconnected }

/// Hosts a TCP session: binds a port, accepts exactly one opponent
/// connection, and completes a hello/welcome handshake. Game-state messages
/// (fullState/requestX) are surfaced via [incoming] but not interpreted here
/// -- HostGameEngine (M4) owns applying them to the authoritative table.
class HostServer {
  ServerSocket? _serverSocket;
  Socket? _clientSocket;
  StreamSubscription<NetMessage>? _sub;
  final _incomingController = StreamController<NetMessage>.broadcast();
  final _statusController = StreamController<HostConnectionStatus>.broadcast();

  Stream<NetMessage> get incoming => _incomingController.stream;
  Stream<HostConnectionStatus> get statusStream => _statusController.stream;

  String? opponentName;
  String? opponentPlayerId;
  HostConnectionStatus status = HostConnectionStatus.waiting;

  /// Binds to all interfaces on [port] and returns the bound port. Resolves
  /// once bound; does not wait for a client to connect.
  Future<int> start({required String localName, int port = defaultGamePort}) async {
    _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
    _serverSocket!.listen((socket) => _handleClient(socket, localName));
    return _serverSocket!.port;
  }

  void _handleClient(Socket socket, String localName) {
    // Two-player only -- reject a second concurrent connection attempt.
    if (_clientSocket != null) {
      socket.destroy();
      return;
    }
    _clientSocket = socket;
    _sub = decodeMessages(socket).listen(
      (msg) {
        if (msg.type == NetMessageType.hello) {
          opponentName = msg.payload['name'] as String?;
          opponentPlayerId = _uuid.v4();
          send(NetMessage(
            type: NetMessageType.welcome,
            payload: {'name': localName, 'playerId': opponentPlayerId},
          ));
          status = HostConnectionStatus.connected;
          _statusController.add(status);
        }
        _incomingController.add(msg);
      },
      onDone: _handleDisconnect,
      onError: (_) => _handleDisconnect(),
    );
  }

  void _handleDisconnect() {
    status = HostConnectionStatus.disconnected;
    _statusController.add(status);
    _clientSocket = null;
  }

  void send(NetMessage msg) {
    _clientSocket?.write(encodeLine(msg));
  }

  Future<void> stop() async {
    await _sub?.cancel();
    _clientSocket?.destroy();
    await _serverSocket?.close();
    await _incomingController.close();
    await _statusController.close();
  }
}
