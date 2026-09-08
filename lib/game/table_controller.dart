import '../models/board_widget_instance.dart';
import '../models/card_instance.dart';
import '../networking/game_client.dart';
import '../networking/net_message.dart';
import 'game_session.dart';

/// What [TableScreen] calls to perform a gameplay action, regardless of
/// whether this instance is the host or a client -- the two implementations
/// differ in what happens next, not in the shape of the action.
abstract class TableController {
  void moveCard(String instanceId, double x, double y);
  void moveGroup(String primaryInstanceId, List<String> passengerRootInstanceIds, double x, double y);
  void moveStack(String rootInstanceId, double x, double y);
  void rotateStack(String rootInstanceId, {required bool clockwise});
  void flipCard(String instanceId);
  void stackCard(String instanceId, String ontoInstanceId);
  void moveToHand(String instanceId);
  void reorderHand(String instanceId, int targetIndex);
  void drawCard(String pileInstanceId);
  void shufflePile(String pileRootInstanceId);
  void drawFromZone(String zoneId);
  void returnToZone(String instanceId, String zoneId, {bool toBottom});
  void shuffleZone(String zoneId);
  void createWidget(String instanceId, BoardWidgetKind kind, double x, double y);
  void moveWidget(String instanceId, double x, double y);
  void setWidgetValue(String instanceId, int value);
  void deleteWidget(String instanceId);
  void setWidgetColors(String instanceId, int backgroundColor, int textColor);
  void duplicateWidget(String sourceInstanceId, String newInstanceId, double x, double y);
  void attachWidgetToCard(String instanceId, String cardId, double x, double y);
}

/// The host applies actions directly to its own authoritative [GameSession]
/// -- HostGameEngine picks up the resulting change and broadcasts it.
class HostTableController implements TableController {
  HostTableController(this._session);

  final GameSession _session;

  /// Mirrors `HostGameEngine._isAllowedToActOn` for the host's own local
  /// actions, which (unlike a client's) never go through that network guard
  /// at all -- true for an unowned card or one the host owns, false for one
  /// owned by the other player.
  bool _isOwnedOrUnowned(String instanceId) {
    for (final CardInstance c in _session.state.cards) {
      if (c.instanceId == instanceId) return c.ownerId == null || c.ownerId == _session.localPlayerId;
    }
    return false;
  }

  @override
  void moveCard(String instanceId, double x, double y) {
    if (_isOwnedOrUnowned(instanceId)) _session.moveCard(instanceId, x, y);
  }

  @override
  void moveGroup(String primaryInstanceId, List<String> passengerRootInstanceIds, double x, double y) {
    if (_isOwnedOrUnowned(primaryInstanceId)) _session.moveGroup(primaryInstanceId, passengerRootInstanceIds, x, y);
  }

  @override
  void moveStack(String rootInstanceId, double x, double y) {
    if (_isOwnedOrUnowned(rootInstanceId)) _session.moveStack(rootInstanceId, x, y);
  }

  @override
  void rotateStack(String rootInstanceId, {required bool clockwise}) {
    if (_isOwnedOrUnowned(rootInstanceId)) _session.rotateStack(rootInstanceId, clockwise: clockwise);
  }

  @override
  void flipCard(String instanceId) {
    if (_isOwnedOrUnowned(instanceId)) _session.flipCard(instanceId);
  }

  @override
  void stackCard(String instanceId, String ontoInstanceId) {
    if (_isOwnedOrUnowned(instanceId)) _session.stackCard(instanceId, ontoInstanceId);
  }

  @override
  void moveToHand(String instanceId) => _session.moveToHand(instanceId);

  @override
  void reorderHand(String instanceId, int targetIndex) => _session.reorderHand(instanceId, targetIndex);

  @override
  void drawCard(String pileInstanceId) => _session.drawCard(pileInstanceId);

  @override
  void shufflePile(String pileRootInstanceId) => _session.shufflePile(pileRootInstanceId);

  /// A zone request never carries an owner -- it always means "my own
  /// instance of this zone, or the shared one," resolved here from the
  /// session's own [GameDefinition.zones] exactly like [HostGameEngine]
  /// resolves it for a networked client's request.
  String? _zoneOwnerId(String zoneId) {
    final zone = _session.game.zones.firstWhere((z) => z.id == zoneId);
    return zone.shared ? null : _session.localPlayerId;
  }

  @override
  void drawFromZone(String zoneId) => _session.drawFromZone(zoneId, zoneOwnerId: _zoneOwnerId(zoneId));

  @override
  void returnToZone(String instanceId, String zoneId, {bool toBottom = false}) =>
      _session.returnToZone(instanceId, zoneId, zoneOwnerId: _zoneOwnerId(zoneId), toBottom: toBottom);

  @override
  void shuffleZone(String zoneId) => _session.shuffleZone(zoneId, zoneOwnerId: _zoneOwnerId(zoneId));

  // Widgets have no ownership concept at all (unlike a card) -- every
  // widget is a shared table utility, so these need no `_isOwnedOrUnowned`
  // guard.
  @override
  void createWidget(String instanceId, BoardWidgetKind kind, double x, double y) =>
      _session.createWidget(instanceId, kind, x, y);

  @override
  void moveWidget(String instanceId, double x, double y) => _session.moveWidget(instanceId, x, y);

  @override
  void setWidgetValue(String instanceId, int value) => _session.setWidgetValue(instanceId, value);

  @override
  void deleteWidget(String instanceId) => _session.deleteWidget(instanceId);

  @override
  void setWidgetColors(String instanceId, int backgroundColor, int textColor) =>
      _session.setWidgetColors(instanceId, backgroundColor, textColor);

  @override
  void duplicateWidget(String sourceInstanceId, String newInstanceId, double x, double y) =>
      _session.duplicateWidget(sourceInstanceId, newInstanceId, x, y);

  @override
  void attachWidgetToCard(String instanceId, String cardId, double x, double y) =>
      _session.attachWidgetToCard(instanceId, cardId, x, y);
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
  void moveGroup(String primaryInstanceId, List<String> passengerRootInstanceIds, double x, double y) {
    _client.send(NetMessage(
      type: NetMessageType.requestMoveGroup,
      payload: {
        'primaryInstanceId': primaryInstanceId,
        'passengerRootInstanceIds': passengerRootInstanceIds,
        'x': x,
        'y': y,
      },
    ));
  }

  @override
  void moveStack(String rootInstanceId, double x, double y) {
    _client.send(NetMessage(
      type: NetMessageType.requestMoveStack,
      payload: {'rootInstanceId': rootInstanceId, 'x': x, 'y': y},
    ));
  }

  @override
  void rotateStack(String rootInstanceId, {required bool clockwise}) {
    _client.send(NetMessage(
      type: NetMessageType.requestRotateStack,
      payload: {'rootInstanceId': rootInstanceId, 'clockwise': clockwise},
    ));
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
  void moveToHand(String instanceId) {
    _client.send(NetMessage(type: NetMessageType.requestMoveToHand, payload: {'instanceId': instanceId}));
  }

  @override
  void reorderHand(String instanceId, int targetIndex) {
    _client.send(NetMessage(
      type: NetMessageType.requestReorderHand,
      payload: {'instanceId': instanceId, 'targetIndex': targetIndex},
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

  @override
  void drawFromZone(String zoneId) {
    _client.send(NetMessage(type: NetMessageType.requestDrawFromZone, payload: {'zoneId': zoneId}));
  }

  @override
  void returnToZone(String instanceId, String zoneId, {bool toBottom = false}) {
    _client.send(NetMessage(
      type: NetMessageType.requestReturnToZone,
      payload: {'instanceId': instanceId, 'zoneId': zoneId, 'toBottom': toBottom},
    ));
  }

  @override
  void shuffleZone(String zoneId) {
    _client.send(NetMessage(type: NetMessageType.requestShuffleZone, payload: {'zoneId': zoneId}));
  }

  @override
  void createWidget(String instanceId, BoardWidgetKind kind, double x, double y) {
    _client.send(NetMessage(
      type: NetMessageType.requestCreateWidget,
      payload: {'instanceId': instanceId, 'kind': kind.name, 'x': x, 'y': y},
    ));
  }

  @override
  void moveWidget(String instanceId, double x, double y) {
    _client.send(NetMessage(
      type: NetMessageType.requestMoveWidget,
      payload: {'instanceId': instanceId, 'x': x, 'y': y},
    ));
  }

  @override
  void setWidgetValue(String instanceId, int value) {
    _client.send(NetMessage(
      type: NetMessageType.requestSetWidgetValue,
      payload: {'instanceId': instanceId, 'value': value},
    ));
  }

  @override
  void deleteWidget(String instanceId) {
    _client.send(NetMessage(type: NetMessageType.requestDeleteWidget, payload: {'instanceId': instanceId}));
  }

  @override
  void setWidgetColors(String instanceId, int backgroundColor, int textColor) {
    _client.send(NetMessage(
      type: NetMessageType.requestSetWidgetColors,
      payload: {'instanceId': instanceId, 'backgroundColor': backgroundColor, 'textColor': textColor},
    ));
  }

  @override
  void duplicateWidget(String sourceInstanceId, String newInstanceId, double x, double y) {
    _client.send(NetMessage(
      type: NetMessageType.requestDuplicateWidget,
      payload: {'sourceInstanceId': sourceInstanceId, 'newInstanceId': newInstanceId, 'x': x, 'y': y},
    ));
  }

  @override
  void attachWidgetToCard(String instanceId, String cardId, double x, double y) {
    _client.send(NetMessage(
      type: NetMessageType.requestAttachWidgetToCard,
      payload: {'instanceId': instanceId, 'cardId': cardId, 'x': x, 'y': y},
    ));
  }
}
