import '../models/board_widget_instance.dart';
import '../models/card_instance.dart';
import '../networking/game_client.dart';
import '../networking/net_message.dart';
import 'drag_preview.dart';
import 'game_session.dart';
import 'stack_utils.dart';

/// What [TableScreen] calls to perform a gameplay action, regardless of
/// whether this instance is the host or a client -- the two implementations
/// differ in what happens next, not in the shape of the action.
abstract class TableController {
  void moveCard(String instanceId, double x, double y);
  void moveGroup(
    String primaryInstanceId,
    List<String> passengerRootInstanceIds,
    double x,
    double y,
  );
  void moveStack(String rootInstanceId, double x, double y);
  void rotateStack(String rootInstanceId, {required bool clockwise});

  /// Bumps the stack rooted at [rootInstanceId] to the table's new
  /// running-max zIndex -- a pure z-order change, no position/rotation
  /// touched. See `TableActions.bringToFront`.
  void bringToFront(String rootInstanceId);
  void flipCard(String instanceId);

  /// Reassigns [instanceId]'s ownership to [newOwnerId] -- null releases it
  /// back to unowned (free-for-anyone). See `TableActions.giveCard`.
  void giveCard(String instanceId, String? newOwnerId);
  void stackCard(String instanceId, String ontoInstanceId);
  void moveToHand(String instanceId);
  void reorderHand(String instanceId, int targetIndex);
  void drawCard(String pileInstanceId, {int count = 1});
  void shufflePile(String pileRootInstanceId);
  void drawFromZone(String zoneId, {int count = 1});
  void returnToZone(String instanceId, String zoneId, {bool toBottom});
  void shuffleZone(String zoneId);
  void startSearchZone(String zoneId);
  void startSearchPile(String pileRootInstanceId);
  void stopSearch();
  void createWidget(
    String instanceId,
    BoardWidgetKind kind,
    double x,
    double y,
  );
  void createArrow(String instanceId, double x, double y, double x2, double y2);
  void moveWidget(String instanceId, double x, double y);
  void setWidgetValue(String instanceId, int value);
  void deleteWidget(String instanceId);
  void setWidgetColors(String instanceId, int backgroundColor, int textColor);
  void duplicateWidget(
    String sourceInstanceId,
    String newInstanceId,
    double x,
    double y,
  );
  void attachWidgetToCard(String instanceId, String cardId, double x, double y);

  /// Deals a random pack from set [setId] into the calling player's hand --
  /// see [GameSession.generatePack]. Unowned/neutral action: any player may
  /// call this regardless of who placed the `PackGeneratorWidget`.
  void generatePack(String setId);

  /// Reports that [primaryInstanceId] (plus any [passengerRootInstanceIds]
  /// riding along, see `TableScreen._buildGroupFeedback`) is currently being
  /// dragged toward canonical position ([fx],[fy]) -- purely cosmetic, never
  /// mutates `TableState`/`revision`, so other players can see the drag
  /// in-progress before it commits (see `GameSession.cardDragPreviews`).
  /// Callers should throttle this, not send it on every pointer-move frame.
  void previewCardDrag(
    String primaryInstanceId,
    List<String> passengerRootInstanceIds,
    double fx,
    double fy,
  );

  /// Clears whatever card-drag preview this player was showing -- must be
  /// called unconditionally at the end of every drag (drop, cancel, or
  /// out-of-bounds release), since a no-op drop may never change
  /// `TableState`/`revision` and so would otherwise leave the ghost stuck on
  /// other players' screens.
  void endCardDragPreview();

  /// Reports an in-progress TAB-drawn arrow from ([fx],[fy]) to
  /// ([fx2],[fy2]), canonical fractions -- same cosmetic/throttled contract
  /// as [previewCardDrag].
  void previewArrowDrag(double fx, double fy, double fx2, double fy2);

  /// Mirrors [endCardDragPreview] for an in-progress arrow -- call
  /// unconditionally whenever the TAB-drag ends or is abandoned (TAB
  /// released mid-drag, menu opened, etc.), not just on a successful commit.
  void endArrowDragPreview();
}

/// The host applies actions directly to its own authoritative [GameSession]
/// -- HostGameEngine picks up the resulting change and broadcasts it.
class HostTableController implements TableController {
  HostTableController(this._session, {this.previewSink});

  final GameSession _session;

  /// Where the host's own drag/arrow previews are published to reach other
  /// clients -- the host has no socket to itself, so it can't just send a
  /// `NetMessage` like [ClientTableController] does. Null for a local
  /// practice session (see `practice_game_screen.dart`), which has no other
  /// viewers to preview anything to.
  final DragPreviewSink? previewSink;

  static const StackUtils _stacks = StackUtils();

  /// Mirrors `HostGameEngine._isAllowedToActOn` for the host's own local
  /// actions, which (unlike a client's) never go through that network guard
  /// at all -- true for an unowned card or one the host (or, in a local
  /// practice session, whichever seat is currently active -- see
  /// [GameSession.actingPlayerId]) owns, false for one owned by someone else.
  bool _isOwnedOrUnowned(String instanceId) {
    for (final CardInstance c in _session.state.cards) {
      if (c.instanceId == instanceId)
        return c.ownerId == null || c.ownerId == _session.actingPlayerId;
    }
    return false;
  }

  @override
  void moveCard(String instanceId, double x, double y) {
    if (_isOwnedOrUnowned(instanceId))
      _session.moveCard(instanceId, x, y, actingPlayerId: _session.actingPlayerId);
  }

  @override
  void moveGroup(
    String primaryInstanceId,
    List<String> passengerRootInstanceIds,
    double x,
    double y,
  ) {
    if (_isOwnedOrUnowned(primaryInstanceId))
      _session.moveGroup(
        primaryInstanceId,
        passengerRootInstanceIds,
        x,
        y,
        actingPlayerId: _session.actingPlayerId,
      );
  }

  @override
  void moveStack(String rootInstanceId, double x, double y) {
    if (_isOwnedOrUnowned(rootInstanceId))
      _session.moveStack(rootInstanceId, x, y);
  }

  @override
  void rotateStack(String rootInstanceId, {required bool clockwise}) {
    if (_isOwnedOrUnowned(rootInstanceId))
      _session.rotateStack(
        rootInstanceId,
        clockwise: clockwise,
        actingPlayerId: _session.actingPlayerId,
      );
  }

  @override
  void bringToFront(String rootInstanceId) {
    if (_isOwnedOrUnowned(rootInstanceId)) _session.bringToFront(rootInstanceId);
  }

  @override
  void flipCard(String instanceId) {
    if (_isOwnedOrUnowned(instanceId))
      _session.flipCard(instanceId, actingPlayerId: _session.actingPlayerId);
  }

  @override
  void giveCard(String instanceId, String? newOwnerId) {
    if (_isOwnedOrUnowned(instanceId)) {
      _session.giveCard(instanceId, newOwnerId, actingPlayerId: _session.actingPlayerId);
    }
  }

  @override
  void stackCard(String instanceId, String ontoInstanceId) {
    if (_isOwnedOrUnowned(instanceId))
      _session.stackCard(instanceId, ontoInstanceId, actingPlayerId: _session.actingPlayerId);
  }

  @override
  void moveToHand(String instanceId) =>
      _session.moveToHand(instanceId, ownerId: _session.actingPlayerId);

  @override
  void reorderHand(String instanceId, int targetIndex) => _session.reorderHand(
    instanceId,
    targetIndex,
    ownerId: _session.actingPlayerId,
  );

  @override
  void drawCard(String pileInstanceId, {int count = 1}) => _session.drawCard(
    pileInstanceId,
    ownerId: _session.actingPlayerId,
    count: count,
  );

  @override
  void shufflePile(String pileRootInstanceId) =>
      _session.shufflePile(pileRootInstanceId, actingPlayerId: _session.actingPlayerId);

  /// A zone request never carries an owner -- it always means "my own
  /// instance of this zone, or the shared one," resolved here from the
  /// session's own [GameDefinition.zones] exactly like [HostGameEngine]
  /// resolves it for a networked client's request. "My own" means whichever
  /// seat is currently active in a local practice session -- see
  /// [GameSession.actingPlayerId].
  String? _zoneOwnerId(String zoneId) {
    final zone = _session.game.zones.firstWhere((z) => z.id == zoneId);
    return zone.shared ? null : _session.actingPlayerId;
  }

  @override
  void drawFromZone(String zoneId, {int count = 1}) => _session.drawFromZone(
    zoneId,
    zoneOwnerId: _zoneOwnerId(zoneId),
    toOwnerId: _session.actingPlayerId,
    count: count,
  );

  @override
  void returnToZone(
    String instanceId,
    String zoneId, {
    bool toBottom = false,
  }) => _session.returnToZone(
    instanceId,
    zoneId,
    zoneOwnerId: _zoneOwnerId(zoneId),
    toBottom: toBottom,
    actingPlayerId: _session.actingPlayerId,
  );

  @override
  void shuffleZone(String zoneId) => _session.shuffleZone(
    zoneId,
    zoneOwnerId: _zoneOwnerId(zoneId),
    actingPlayerId: _session.actingPlayerId,
  );

  @override
  void startSearchZone(String zoneId) => _session.startSearchZone(
    zoneId,
    zoneOwnerId: _zoneOwnerId(zoneId),
    searcherId: _session.actingPlayerId,
  );

  /// Mirrors `HostGameEngine._isAllowedToDrawOrShuffle` for the host's own
  /// local actions -- every card in the pile must be unowned or owned by
  /// whichever seat is currently active, exactly like Shuffle's guard.
  bool _isOwnedOrUnownedStack(String rootInstanceId) {
    final stack = _stacks.stackOf(_session.state.cards, rootInstanceId);
    for (final c in stack) {
      if (c.ownerId != null && c.ownerId != _session.actingPlayerId)
        return false;
    }
    return true;
  }

  @override
  void startSearchPile(String pileRootInstanceId) {
    if (_isOwnedOrUnownedStack(pileRootInstanceId))
      _session.startSearchPile(pileRootInstanceId, searcherId: _session.actingPlayerId);
  }

  @override
  void stopSearch() => _session.stopSearch(searcherId: _session.actingPlayerId);

  // Widgets have no ownership concept at all (unlike a card) -- every
  // widget is a shared table utility, so these need no `_isOwnedOrUnowned`
  // guard.
  @override
  void createWidget(
    String instanceId,
    BoardWidgetKind kind,
    double x,
    double y,
  ) => _session.createWidget(instanceId, kind, x, y);

  /// The host's own arrow is attributed to its own player id (or, in a local
  /// practice session, whichever seat is currently active), exactly like
  /// `HostGameEngine` attributes a client-originated arrow to the requesting
  /// client's connection identity rather than anything the client itself
  /// could supply -- see [ClientTableController.createArrow].
  @override
  void createArrow(
    String instanceId,
    double x,
    double y,
    double x2,
    double y2,
  ) => _session.createArrow(
    instanceId,
    x,
    y,
    x2,
    y2,
    creatorId: _session.actingPlayerId,
  );

  @override
  void moveWidget(String instanceId, double x, double y) =>
      _session.moveWidget(instanceId, x, y);

  @override
  void setWidgetValue(String instanceId, int value) =>
      _session.setWidgetValue(instanceId, value, actingPlayerId: _session.actingPlayerId);

  @override
  void deleteWidget(String instanceId) => _session.deleteWidget(instanceId);

  @override
  void setWidgetColors(String instanceId, int backgroundColor, int textColor) =>
      _session.setWidgetColors(instanceId, backgroundColor, textColor);

  @override
  void duplicateWidget(
    String sourceInstanceId,
    String newInstanceId,
    double x,
    double y,
  ) => _session.duplicateWidget(sourceInstanceId, newInstanceId, x, y);

  @override
  void attachWidgetToCard(
    String instanceId,
    String cardId,
    double x,
    double y,
  ) => _session.attachWidgetToCard(
    instanceId,
    cardId,
    x,
    y,
    actingPlayerId: _session.actingPlayerId,
  );

  @override
  void generatePack(String setId) => _session.generatePack(setId, actingPlayerId: _session.actingPlayerId);

  @override
  void previewCardDrag(
    String primaryInstanceId,
    List<String> passengerRootInstanceIds,
    double fx,
    double fy,
  ) {
    previewSink?.publishCardDragPreview(
      playerId: _session.actingPlayerId,
      instanceIds: [primaryInstanceId, ...passengerRootInstanceIds],
      fx: fx,
      fy: fy,
    );
  }

  @override
  void endCardDragPreview() =>
      previewSink?.clearCardDragPreview(_session.actingPlayerId);

  @override
  void previewArrowDrag(double fx, double fy, double fx2, double fy2) {
    previewSink?.publishArrowDragPreview(
      playerId: _session.actingPlayerId,
      fx: fx,
      fy: fy,
      fx2: fx2,
      fy2: fy2,
    );
  }

  @override
  void endArrowDragPreview() =>
      previewSink?.clearArrowDragPreview(_session.actingPlayerId);
}

/// A client never mutates its local [GameSession] directly from a gesture
/// -- it sends a request to the host and waits for the next `fullState`
/// broadcast (applied via [GameSession.applyRemoteState]) to reflect it.
class ClientTableController implements TableController {
  ClientTableController(this._client);

  final GameClient _client;

  @override
  void moveCard(String instanceId, double x, double y) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestMove,
        payload: {'instanceId': instanceId, 'x': x, 'y': y},
      ),
    );
  }

  @override
  void moveGroup(
    String primaryInstanceId,
    List<String> passengerRootInstanceIds,
    double x,
    double y,
  ) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestMoveGroup,
        payload: {
          'primaryInstanceId': primaryInstanceId,
          'passengerRootInstanceIds': passengerRootInstanceIds,
          'x': x,
          'y': y,
        },
      ),
    );
  }

  @override
  void moveStack(String rootInstanceId, double x, double y) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestMoveStack,
        payload: {'rootInstanceId': rootInstanceId, 'x': x, 'y': y},
      ),
    );
  }

  @override
  void rotateStack(String rootInstanceId, {required bool clockwise}) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestRotateStack,
        payload: {'rootInstanceId': rootInstanceId, 'clockwise': clockwise},
      ),
    );
  }

  @override
  void bringToFront(String rootInstanceId) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestBringToFront,
        payload: {'rootInstanceId': rootInstanceId},
      ),
    );
  }

  @override
  void flipCard(String instanceId) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestFlip,
        payload: {'instanceId': instanceId},
      ),
    );
  }

  @override
  void giveCard(String instanceId, String? newOwnerId) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestGiveCard,
        payload: {'instanceId': instanceId, 'newOwnerId': newOwnerId},
      ),
    );
  }

  @override
  void stackCard(String instanceId, String ontoInstanceId) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestStack,
        payload: {'instanceId': instanceId, 'ontoInstanceId': ontoInstanceId},
      ),
    );
  }

  @override
  void moveToHand(String instanceId) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestMoveToHand,
        payload: {'instanceId': instanceId},
      ),
    );
  }

  @override
  void reorderHand(String instanceId, int targetIndex) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestReorderHand,
        payload: {'instanceId': instanceId, 'targetIndex': targetIndex},
      ),
    );
  }

  @override
  void drawCard(String pileInstanceId, {int count = 1}) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestDraw,
        payload: {'pileInstanceId': pileInstanceId, 'count': count},
      ),
    );
  }

  @override
  void shufflePile(String pileRootInstanceId) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestShuffle,
        payload: {'pileRootInstanceId': pileRootInstanceId},
      ),
    );
  }

  @override
  void drawFromZone(String zoneId, {int count = 1}) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestDrawFromZone,
        payload: {'zoneId': zoneId, 'count': count},
      ),
    );
  }

  @override
  void returnToZone(String instanceId, String zoneId, {bool toBottom = false}) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestReturnToZone,
        payload: {
          'instanceId': instanceId,
          'zoneId': zoneId,
          'toBottom': toBottom,
        },
      ),
    );
  }

  @override
  void shuffleZone(String zoneId) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestShuffleZone,
        payload: {'zoneId': zoneId},
      ),
    );
  }

  @override
  void startSearchZone(String zoneId) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestStartSearchZone,
        payload: {'zoneId': zoneId},
      ),
    );
  }

  @override
  void startSearchPile(String pileRootInstanceId) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestStartSearchPile,
        payload: {'pileRootInstanceId': pileRootInstanceId},
      ),
    );
  }

  @override
  void stopSearch() {
    _client.send(NetMessage(type: NetMessageType.requestStopSearch));
  }

  @override
  void createWidget(
    String instanceId,
    BoardWidgetKind kind,
    double x,
    double y,
  ) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestCreateWidget,
        payload: {'instanceId': instanceId, 'kind': kind.name, 'x': x, 'y': y},
      ),
    );
  }

  /// No id in the payload -- the host stamps `creatorId` from the
  /// connection itself (`HostGameEngine`), never from anything a client
  /// sends, so a client can never claim to be a different player.
  @override
  void createArrow(
    String instanceId,
    double x,
    double y,
    double x2,
    double y2,
  ) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestCreateArrow,
        payload: {'instanceId': instanceId, 'x': x, 'y': y, 'x2': x2, 'y2': y2},
      ),
    );
  }

  @override
  void moveWidget(String instanceId, double x, double y) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestMoveWidget,
        payload: {'instanceId': instanceId, 'x': x, 'y': y},
      ),
    );
  }

  @override
  void setWidgetValue(String instanceId, int value) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestSetWidgetValue,
        payload: {'instanceId': instanceId, 'value': value},
      ),
    );
  }

  @override
  void deleteWidget(String instanceId) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestDeleteWidget,
        payload: {'instanceId': instanceId},
      ),
    );
  }

  @override
  void setWidgetColors(String instanceId, int backgroundColor, int textColor) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestSetWidgetColors,
        payload: {
          'instanceId': instanceId,
          'backgroundColor': backgroundColor,
          'textColor': textColor,
        },
      ),
    );
  }

  @override
  void duplicateWidget(
    String sourceInstanceId,
    String newInstanceId,
    double x,
    double y,
  ) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestDuplicateWidget,
        payload: {
          'sourceInstanceId': sourceInstanceId,
          'newInstanceId': newInstanceId,
          'x': x,
          'y': y,
        },
      ),
    );
  }

  @override
  void attachWidgetToCard(
    String instanceId,
    String cardId,
    double x,
    double y,
  ) {
    _client.send(
      NetMessage(
        type: NetMessageType.requestAttachWidgetToCard,
        payload: {'instanceId': instanceId, 'cardId': cardId, 'x': x, 'y': y},
      ),
    );
  }

  @override
  void generatePack(String setId) {
    _client.send(
      NetMessage(type: NetMessageType.requestGeneratePack, payload: {'setId': setId}),
    );
  }

  /// No id in the payload -- the host stamps the dragging player's id from
  /// the connection itself, same as [createArrow]'s `creatorId`. Sent
  /// fire-and-forget, unlike every `requestX` above: this never expects a
  /// `fullState` reply.
  @override
  void previewCardDrag(
    String primaryInstanceId,
    List<String> passengerRootInstanceIds,
    double fx,
    double fy,
  ) {
    _client.send(
      NetMessage(
        type: NetMessageType.cardDragPreview,
        payload: {
          'instanceIds': [primaryInstanceId, ...passengerRootInstanceIds],
          'fx': fx,
          'fy': fy,
        },
      ),
    );
  }

  @override
  void endCardDragPreview() {
    _client.send(const NetMessage(type: NetMessageType.cardDragPreviewEnd));
  }

  @override
  void previewArrowDrag(double fx, double fy, double fx2, double fy2) {
    _client.send(
      NetMessage(
        type: NetMessageType.arrowDragPreview,
        payload: {'fx': fx, 'fy': fy, 'fx2': fx2, 'fy2': fy2},
      ),
    );
  }

  @override
  void endArrowDragPreview() {
    _client.send(const NetMessage(type: NetMessageType.arrowDragPreviewEnd));
  }
}
