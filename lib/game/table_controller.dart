import '../networking/game_client.dart';
import '../networking/net_message.dart';
import 'game_session.dart';

/// What [TableScreen] calls to perform a gameplay action, regardless of
/// whether this instance is the host or a client -- the two implementations
/// differ in what happens next, not in the shape of the action.
abstract class TableController {
  void moveCard(String instanceId, double x, double y);
  void flipCard(String instanceId);
  void stackCard(String instanceId, String ontoInstanceId);
  void drawCard(String pileInstanceId);
  void shufflePile(String pileRootInstanceId);
}

/// The host applies actions directly to its own authoritative [GameSession]
/// -- HostGameEngine picks up the resulting change and broadcasts it.
class HostTableController implements TableController {
  HostTableController(this._session);

  final GameSession _session;

  @override
  void moveCard(String instanceId, double x, double y) => _session.moveCard(instanceId, x, y);

  @override
  void flipCard(String instanceId) => _session.flipCard(instanceId);

  @override
  void stackCard(String instanceId, String ontoInstanceId) => _session.stackCard(instanceId, ontoInstanceId);

  @override
  void drawCard(String pileInstanceId) => _session.drawCard(pileInstanceId);

  @override
  void shufflePile(String pileRootInstanceId) => _session.shufflePile(pileRootInstanceId);
}

/// A client never mutates its local [GameSession] directly from a gesture
/// -- it sends a request to the host and waits for the next `fullState`
/// broadcast (applied via [GameSession.applyRemoteState]) to reflect it.
class ClientTableController implements TableController {
  ClientTableController(this._client);

  final GameClient _client;

  @override
  void moveCard(String instanceId, double x, double y) {
    _client.send(NetMessage(type: NetMessageType.requestMove, payload: {'instanceId': instanceId, 'x': x, 'y': y}));
  }

  @override
  void flipCard(String instanceId) {
    _client.send(NetMessage(type: NetMessageType.requestFlip, payload: {'instanceId': instanceId}));
  }

  @override
  void stackCard(String instanceId, String ontoInstanceId) {
    _client.send(NetMessage(
      type: NetMessageType.requestStack,
      payload: {'instanceId': instanceId, 'ontoInstanceId': ontoInstanceId},
    ));
  }

  @override
  void drawCard(String pileInstanceId) {
    _client.send(NetMessage(type: NetMessageType.requestDraw, payload: {'pileInstanceId': pileInstanceId}));
  }

  @override
  void shufflePile(String pileRootInstanceId) {
    _client.send(NetMessage(
      type: NetMessageType.requestShuffle,
      payload: {'pileRootInstanceId': pileRootInstanceId},
    ));
  }
}
