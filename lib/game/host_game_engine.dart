import 'dart:async';

import '../models/board_widget_instance.dart';
import '../models/card_instance.dart';
import '../models/deck_config.dart';
import '../models/player.dart';
import '../networking/host_server.dart';
import '../networking/net_message.dart';
import '../networking/state_filter.dart';
import 'deck_widget_zones.dart';
import 'drag_preview.dart';
import 'game_session.dart';
import 'stack_utils.dart';

/// Owns the host's authoritative [GameSession] in a networked match: applies
/// incoming client requests to it (structural validation only -- no rules
/// engine), and re-broadcasts a per-recipient filtered snapshot after every
/// change, including the host's own local actions.
///
/// Also implements [DragPreviewSink]: the cosmetic drag/arrow-preview
/// channel (see `GameSession.cardDragPreviews`/`arrowDragPreviews`) is kept
/// entirely separate from that request/mutate/broadcast cycle -- it never
/// touches `TableState`/`revision`, so a client's preview is relayed
/// straight through to every *other* client, and the host's own preview
/// (published via `HostTableController`, which has no socket to itself)
/// reaches every client the same way.
class HostGameEngine implements DragPreviewSink {
  HostGameEngine({
    required this.session,
    required this.hostServer,
    required this.hostPlayerId,
  });

  final GameSession session;
  final HostServer hostServer;
  final String hostPlayerId;

  static const StackUtils _stacks = StackUtils();

  StreamSubscription<IncomingMessage>? _incomingSub;
  StreamSubscription<List<PlayerInfo>>? _rosterSub;
  int _lastBroadcastRevision = -1;

  /// Every non-host id [_rosterSub] has already seen connected at least
  /// once, so a freshly-appearing one (a brand-new joiner, or a reconnected
  /// player's new socket) can be told apart from one that was already live
  /// last time around -- see [start]'s doc on why that new arrival needs
  /// its own [NetMessageType.gameData] resend.
  Set<String> _previouslyConnectedIds = {};

  void start() {
    session.addListener(_broadcast);
    _incomingSub = hostServer.incoming.listen(_handleMessage);
    // Lets a reconnecting client's `hello` reclaim its old id instead of
    // being minted a new one -- only a currently-disconnected seat in the
    // already-dealt session qualifies (see `HostServer.reclaimableIdCheck`'s
    // own doc).
    hostServer.reclaimableIdCheck = (id) =>
        session.state.players.any((p) => p.id == id && !p.connected);
    _rosterSub = hostServer.rosterStream.listen((roster) {
      final connectedIds = {
        for (final p in roster)
          if (p.role != PlayerRole.host) p.id,
      };
      // A client that's newly connected (first-time joiner, or a
      // reconnecting player's new socket) missed the one-time `gameData`
      // broadcast(s) sent before it ever connected -- resend it directly,
      // and do so *before* `syncConnectedPlayerIds` below bumps the
      // revision and triggers `_broadcast`'s `fullState` send: a `fullState`
      // arriving at a client before its `gameData` is silently dropped
      // (`ClientGameScreen._handleMessage`), with nothing else to prompt a
      // resend, so ordering here matters. Both writes go out on the same
      // socket via `HostServer.sendTo`, so TCP preserves that order.
      for (final id in connectedIds.difference(_previouslyConnectedIds)) {
        hostServer.sendTo(
          id,
          NetMessage(type: NetMessageType.gameData, payload: session.game.toJson()),
        );
      }
      // A disconnecting player (clean leave, heartbeat timeout, or a kick)
      // may have left a drag/arrow preview stuck in-flight -- clear it here
      // rather than relying on that player to ever send a *PreviewEnd
      // themselves, and rebroadcast so remaining clients drop the stale
      // ghost too.
      for (final id in _previouslyConnectedIds.difference(connectedIds)) {
        clearCardDragPreview(id);
        clearArrowDragPreview(id);
      }
      _previouslyConnectedIds = connectedIds;
      session.syncConnectedPlayerIds(connectedIds);
    });
    _broadcast();
  }

  void dispose() {
    session.removeListener(_broadcast);
    _incomingSub?.cancel();
    _rosterSub?.cancel();
    hostServer.reclaimableIdCheck = null;
  }

  void _broadcast() {
    if (session.state.revision == _lastBroadcastRevision) return;
    _lastBroadcastRevision = session.state.revision;
    final visibleZoneIds = {
      for (final z in session.game.zones)
        if (z.visibleToAll) z.id,
    };
    // Every seat dealt at match start, not just currently-connected clients
    // (see HostServer.roster's doc) -- a stale send to an already-
    // disconnected id is a harmless no-op (HostServer.sendTo).
    for (final player in session.state.players) {
      if (player.id == hostPlayerId) continue; // the host reads state directly via Provider
      final filtered = filterForRecipient(
        session.state,
        player.id,
        visibleZoneIds: visibleZoneIds,
      );
      hostServer.sendTo(
        player.id,
        NetMessage(type: NetMessageType.fullState, payload: filtered.toJson()),
      );
    }
  }

  void _handleMessage(IncomingMessage incoming) {
    final clientId = incoming.senderId;
    final msg = incoming.message;

    switch (msg.type) {
      case NetMessageType.requestMove:
        final instanceId = msg.payload['instanceId'] as String;
        if (_isAllowedToActOn(instanceId, clientId)) {
          session.moveCard(
            instanceId,
            (msg.payload['x'] as num).toDouble(),
            (msg.payload['y'] as num).toDouble(),
            actingPlayerId: clientId,
          );
        }
        break;
      case NetMessageType.requestMoveGroup:
        final primaryInstanceId = msg.payload['primaryInstanceId'] as String;
        if (_isAllowedToActOn(primaryInstanceId, clientId)) {
          final passengerRootInstanceIds =
              (msg.payload['passengerRootInstanceIds'] as List)
                  .cast<String>()
                  .where((id) => _isAllowedToActOn(id, clientId))
                  .toList();
          session.moveGroup(
            primaryInstanceId,
            passengerRootInstanceIds,
            (msg.payload['x'] as num).toDouble(),
            (msg.payload['y'] as num).toDouble(),
            actingPlayerId: clientId,
          );
        }
        break;
      case NetMessageType.requestMoveStack:
        final rootInstanceId = msg.payload['rootInstanceId'] as String;
        if (_isAllowedToActOn(rootInstanceId, clientId)) {
          session.moveStack(
            rootInstanceId,
            (msg.payload['x'] as num).toDouble(),
            (msg.payload['y'] as num).toDouble(),
          );
        }
        break;
      case NetMessageType.requestRotateStack:
        final rootInstanceId = msg.payload['rootInstanceId'] as String;
        if (_isAllowedToActOn(rootInstanceId, clientId)) {
          session.rotateStack(
            rootInstanceId,
            clockwise: msg.payload['clockwise'] as bool,
            actingPlayerId: clientId,
          );
        }
        break;
      case NetMessageType.requestBringToFront:
        final rootInstanceId = msg.payload['rootInstanceId'] as String;
        if (_isAllowedToActOn(rootInstanceId, clientId)) {
          session.bringToFront(rootInstanceId);
        }
        break;
      case NetMessageType.requestFlip:
        final instanceId = msg.payload['instanceId'] as String;
        if (_isAllowedToActOn(instanceId, clientId)) {
          session.flipCard(instanceId, actingPlayerId: clientId);
        }
        break;
      case NetMessageType.requestGiveCard:
        final instanceId = msg.payload['instanceId'] as String;
        final newOwnerId = msg.payload['newOwnerId'] as String?;
        final targetIsValid =
            newOwnerId == null ||
            session.state.players.any((p) => p.id == newOwnerId);
        if (_isAllowedToActOn(instanceId, clientId) && targetIsValid) {
          session.giveCard(instanceId, newOwnerId, actingPlayerId: clientId);
        }
        break;
      case NetMessageType.requestStack:
        final instanceId = msg.payload['instanceId'] as String;
        final ontoInstanceId = msg.payload['ontoInstanceId'] as String;
        if (_isAllowedToActOn(instanceId, clientId) &&
            _cardExists(ontoInstanceId)) {
          session.stackCard(instanceId, ontoInstanceId, actingPlayerId: clientId);
        }
        break;
      case NetMessageType.requestMoveToHand:
        final instanceId = msg.payload['instanceId'] as String;
        if (_isAllowedToActOn(instanceId, clientId)) {
          session.moveToHand(instanceId, ownerId: clientId);
        }
        break;
      case NetMessageType.requestReorderHand:
        final instanceId = msg.payload['instanceId'] as String;
        final targetIndex = msg.payload['targetIndex'] as int;
        if (_isAllowedToActOn(instanceId, clientId)) {
          session.reorderHand(instanceId, targetIndex, ownerId: clientId);
        }
        break;
      case NetMessageType.requestDraw:
        final pileInstanceId = msg.payload['pileInstanceId'] as String;
        final count = msg.payload['count'] as int? ?? 1;
        if (_isAllowedToDrawOrShuffle(pileInstanceId, clientId)) {
          session.drawCard(pileInstanceId, ownerId: clientId, count: count);
        }
        break;
      case NetMessageType.requestShuffle:
        final pileRootInstanceId = msg.payload['pileRootInstanceId'] as String;
        if (_isAllowedToDrawOrShuffle(pileRootInstanceId, clientId)) {
          session.shufflePile(pileRootInstanceId, actingPlayerId: clientId);
        }
        break;
      case NetMessageType.requestDrawFromZone:
        final zoneId = msg.payload['zoneId'] as String;
        final count = msg.payload['count'] as int? ?? 1;
        session.drawFromZone(
          zoneId,
          zoneOwnerId: _zoneOwnerId(zoneId, clientId),
          toOwnerId: clientId,
          count: count,
        );
        break;
      case NetMessageType.requestReturnToZone:
        final instanceId = msg.payload['instanceId'] as String;
        final zoneId = msg.payload['zoneId'] as String;
        final toBottom = msg.payload['toBottom'] as bool? ?? false;
        if (_isAllowedToActOn(instanceId, clientId) &&
            _isAllowedToActOnDeckWidgetZone(zoneId, clientId)) {
          session.returnToZone(
            instanceId,
            zoneId,
            zoneOwnerId: _zoneOwnerId(zoneId, clientId),
            toBottom: toBottom,
            actingPlayerId: clientId,
          );
        }
        break;
      case NetMessageType.requestShuffleZone:
        final zoneId = msg.payload['zoneId'] as String;
        session.shuffleZone(
          zoneId,
          zoneOwnerId: _zoneOwnerId(zoneId, clientId),
          actingPlayerId: clientId,
        );
        break;
      case NetMessageType.requestStartSearchZone:
        final zoneId = msg.payload['zoneId'] as String;
        if (_isAllowedToActOnDeckWidgetZone(zoneId, clientId)) {
          session.startSearchZone(
            zoneId,
            zoneOwnerId: _zoneOwnerId(zoneId, clientId),
            searcherId: clientId,
          );
        }
        break;
      case NetMessageType.requestStartSearchPile:
        final pileRootInstanceId = msg.payload['pileRootInstanceId'] as String;
        if (_isAllowedToDrawOrShuffle(pileRootInstanceId, clientId)) {
          session.startSearchPile(pileRootInstanceId, searcherId: clientId);
        }
        break;
      case NetMessageType.requestStopSearch:
        session.stopSearch(searcherId: clientId);
        break;
      case NetMessageType.requestCreateWidget:
        session.createWidget(
          msg.payload['instanceId'] as String,
          BoardWidgetKind.fromName(msg.payload['kind'] as String),
          (msg.payload['x'] as num).toDouble(),
          (msg.payload['y'] as num).toDouble(),
          actingPlayerId: clientId,
        );
        break;
      case NetMessageType.requestCreateArrow:
        // creatorId comes from the connection itself (clientId), never from
        // the payload -- a client has no way to claim to be a different
        // player (see _isAllowedToDeleteWidget for why this matters).
        session.createArrow(
          msg.payload['instanceId'] as String,
          (msg.payload['x'] as num).toDouble(),
          (msg.payload['y'] as num).toDouble(),
          (msg.payload['x2'] as num).toDouble(),
          (msg.payload['y2'] as num).toDouble(),
          creatorId: clientId,
        );
        break;
      case NetMessageType.requestMoveWidget:
        final instanceId = msg.payload['instanceId'] as String;
        if (_isMovableWidget(instanceId, clientId)) {
          session.moveWidget(
            instanceId,
            (msg.payload['x'] as num).toDouble(),
            (msg.payload['y'] as num).toDouble(),
          );
        }
        break;
      case NetMessageType.requestSetWidgetValue:
        final instanceId = msg.payload['instanceId'] as String;
        if (_isAllowedToActOnWidget(instanceId, clientId)) {
          session.setWidgetValue(instanceId, msg.payload['value'] as int, actingPlayerId: clientId);
        }
        break;
      case NetMessageType.requestDeleteWidget:
        final instanceId = msg.payload['instanceId'] as String;
        if (_isAllowedToDeleteWidget(instanceId, clientId)) {
          session.deleteWidget(instanceId);
        }
        break;
      case NetMessageType.requestSetWidgetColors:
        final instanceId = msg.payload['instanceId'] as String;
        if (_isAllowedToActOnWidget(instanceId, clientId)) {
          session.setWidgetColors(
            instanceId,
            msg.payload['backgroundColor'] as int,
            msg.payload['textColor'] as int,
          );
        }
        break;
      case NetMessageType.requestDuplicateWidget:
        final sourceInstanceId = msg.payload['sourceInstanceId'] as String;
        if (_isMovableWidget(sourceInstanceId, clientId)) {
          session.duplicateWidget(
            sourceInstanceId,
            msg.payload['newInstanceId'] as String,
            (msg.payload['x'] as num).toDouble(),
            (msg.payload['y'] as num).toDouble(),
          );
        }
        break;
      case NetMessageType.requestAttachWidgetToCard:
        final instanceId = msg.payload['instanceId'] as String;
        if (_isMovableWidget(instanceId, clientId)) {
          session.attachWidgetToCard(
            instanceId,
            msg.payload['cardId'] as String,
            (msg.payload['x'] as num).toDouble(),
            (msg.payload['y'] as num).toDouble(),
            actingPlayerId: clientId,
          );
        }
        break;
      case NetMessageType.requestGeneratePack:
        session.generatePack(msg.payload['setId'] as String, actingPlayerId: clientId);
        break;
      case NetMessageType.requestCreateCardFromLibrary:
        session.createCardFromLibrary(
          msg.payload['definitionId'] as String,
          (msg.payload['x'] as num).toDouble(),
          (msg.payload['y'] as num).toDouble(),
          actingPlayerId: clientId,
        );
        break;
      case NetMessageType.requestLoadDeckIntoZone:
        final zoneId = msg.payload['zoneId'] as String;
        final deck = DeckConfig.fromJson((msg.payload['deck'] as Map).cast<String, dynamic>());
        session.loadDeckIntoZone(zoneId, deck, actingPlayerId: clientId);
        break;
      case NetMessageType.cardDragPreview:
        final rawIds = (msg.payload['instanceIds'] as List).cast<String>();
        if (rawIds.isNotEmpty && _isAllowedToActOn(rawIds.first, clientId)) {
          final allowedIds = [
            rawIds.first,
            ...rawIds.skip(1).where((id) => _isAllowedToActOn(id, clientId)),
          ];
          publishCardDragPreview(
            playerId: clientId,
            instanceIds: allowedIds,
            fx: (msg.payload['fx'] as num).toDouble(),
            fy: (msg.payload['fy'] as num).toDouble(),
          );
        }
        break;
      case NetMessageType.cardDragPreviewEnd:
        clearCardDragPreview(clientId);
        break;
      case NetMessageType.arrowDragPreview:
        publishArrowDragPreview(
          playerId: clientId,
          fx: (msg.payload['fx'] as num).toDouble(),
          fy: (msg.payload['fy'] as num).toDouble(),
          fx2: (msg.payload['fx2'] as num).toDouble(),
          fy2: (msg.payload['fy2'] as num).toDouble(),
        );
        break;
      case NetMessageType.arrowDragPreviewEnd:
        clearArrowDragPreview(clientId);
        break;
      case NetMessageType.hello:
      case NetMessageType.welcome:
      case NetMessageType.gameData:
      case NetMessageType.fullState:
      case NetMessageType.lobbyRosterUpdate:
      case NetMessageType.ping:
      case NetMessageType.pong:
      case NetMessageType.disconnect:
        // lobbyRosterUpdate is host->client only (see HostServer's own
        // _broadcastRoster) -- never actually arrives here as a client
        // request; kept for switch exhaustiveness.
        break;
    }
  }

  bool _cardExists(String instanceId) =>
      session.state.cards.any((c) => c.instanceId == instanceId);

  /// A zone request never carries an owner -- it always means "the
  /// requester's own instance of this zone, or the shared one" -- resolved
  /// here from the game's own [ZoneDefinition]s rather than trusted from the
  /// client, so a client can never claim to act on another player's zone.
  ///
  /// A DeckWidget synthetic sub-zone id (see `deck_widget_zones.dart`)
  /// breaks that "always resolves to your own instance" invariant on
  /// purpose -- it always belongs to whichever player owns that specific
  /// widget instance, not to the requester -- so
  /// [_isAllowedToActOnDeckWidgetZone] exists to gate that everywhere this
  /// is used.
  String? _zoneOwnerId(String zoneId, String requesterPlayerId) {
    final parsed = parseDeckWidgetZoneId(zoneId);
    if (parsed != null) return _findWidget(parsed.widgetInstanceId)?.ownerId;
    final zone = session.game.zones.firstWhere((z) => z.id == zoneId);
    return zone.shared ? null : requesterPlayerId;
  }

  /// True unconditionally for an ordinary zone id (unchanged behavior). For
  /// a DeckWidget synthetic sub-zone id, true only if that widget still
  /// exists and [requesterPlayerId] is its owner -- without this, the
  /// [_zoneOwnerId] override above would let any client drop into or search
  /// another player's deck widget, since a synthetic id's owner is fixed to
  /// the widget rather than the requester.
  bool _isAllowedToActOnDeckWidgetZone(String zoneId, String requesterPlayerId) {
    final parsed = parseDeckWidgetZoneId(zoneId);
    if (parsed == null) return true;
    final w = _findWidget(parsed.widgetInstanceId);
    return w != null && w.ownerId == requesterPlayerId;
  }

  /// Structural + ownership guard: the card must exist, and a client may
  /// never act on a card owned by someone else -- in a hand, a personal
  /// zone, or sitting out on the free table. An unowned card (`ownerId ==
  /// null`, e.g. one never drawn from a shared pile) is always fair game.
  bool _isAllowedToActOn(String instanceId, String requesterPlayerId) {
    CardInstance? card;
    for (final c in session.state.cards) {
      if (c.instanceId == instanceId) {
        card = c;
        break;
      }
    }
    if (card == null) return false;
    return card.ownerId == null || card.ownerId == requesterPlayerId;
  }

  BoardWidgetInstance? _findWidget(String instanceId) {
    for (final w in session.state.widgets) {
      if (w.instanceId == instanceId) return w;
    }
    return null;
  }

  /// False for a widget dealt from a `ZoneKind.widget` zone (non-null
  /// `BoardWidgetInstance.zoneId`) -- it's a fixed part of its owner's panel,
  /// never a movable/attachable/duplicable/deletable table object, for any
  /// requester (see `TableScreen`'s `draggable: false` client-side mirror of
  /// this same rule). Otherwise: an unowned free widget (`ownerId` null --
  /// Counter/Token/PackGenerator) stays fair game for anyone, unchanged from
  /// before ownership existed; an owned free widget (`ownerId` non-null,
  /// `zoneId` null -- a DeckWidget) is movable only by its own owner. True
  /// for an unknown id, unchanged from today's unrestricted behavior.
  bool _isMovableWidget(String instanceId, String requesterPlayerId) {
    final w = _findWidget(instanceId);
    if (w == null) return true;
    if (w.zoneId != null) return false;
    return w.ownerId == null || w.ownerId == requesterPlayerId;
  }

  /// A zone-bound OR owned-free widget's value/colors may only be changed
  /// by its own owner (mirrors [_isAllowedToActOn]'s card-ownership shape);
  /// an unowned free-table widget stays fair game for anyone, exactly as
  /// before this existed.
  bool _isAllowedToActOnWidget(String instanceId, String requesterPlayerId) {
    final w = _findWidget(instanceId);
    if (w == null) return false;
    return w.ownerId == null || w.ownerId == requesterPlayerId;
  }

  /// Mirrors [_isAllowedToActOn]'s shape for a widget instead of a card: a
  /// widget with no [BoardWidgetInstance.creatorId] (every kind except an
  /// arrow, today) is always fair game -- widgets stay deliberately
  /// ownerless by default (see `table_controller.dart`'s doc comment) --
  /// but an arrow may only be deleted by the player who drew it. A
  /// zone-bound widget, or an owned free widget belonging to someone else
  /// (see [_isMovableWidget]), can never be deleted by this requester.
  bool _isAllowedToDeleteWidget(String instanceId, String requesterPlayerId) {
    final w = _findWidget(instanceId);
    if (w == null || !_isMovableWidget(instanceId, requesterPlayerId)) return false;
    return w.creatorId == null || w.creatorId == requesterPlayerId;
  }

  /// A client may draw from or shuffle any unowned pile (e.g. a shared
  /// sandbox pile), but only their *own* personal deck -- never another
  /// player's.
  bool _isAllowedToDrawOrShuffle(
    String pileInstanceId,
    String requesterPlayerId,
  ) {
    final stack = _stacks.stackOf(session.state.cards, pileInstanceId);
    for (final c in stack) {
      if (c.ownerId != null && c.ownerId != requesterPlayerId) return false;
    }
    return true;
  }

  /// [playerId] is the *host's own* id only when [HostTableController]
  /// itself is publishing the host's own drag (it has no socket to itself,
  /// so it calls straight in here); every other caller is a relayed
  /// client's preview, which must be excluded from its own echo.
  @override
  void publishCardDragPreview({
    required String playerId,
    required List<String> instanceIds,
    required double fx,
    required double fy,
  }) {
    session.cardDragPreviews.value = {
      ...session.cardDragPreviews.value,
      playerId: CardDragPreview(
        playerId: playerId,
        instanceIds: instanceIds,
        fx: fx,
        fy: fy,
      ),
    };
    hostServer.broadcast(
      NetMessage(
        type: NetMessageType.cardDragPreview,
        payload: {'playerId': playerId, 'instanceIds': instanceIds, 'fx': fx, 'fy': fy},
      ),
      exceptPlayerId: playerId == hostPlayerId ? null : playerId,
    );
  }

  @override
  void clearCardDragPreview(String playerId) {
    if (!session.cardDragPreviews.value.containsKey(playerId)) return;
    session.cardDragPreviews.value = {...session.cardDragPreviews.value}
      ..remove(playerId);
    hostServer.broadcast(
      NetMessage(
        type: NetMessageType.cardDragPreviewEnd,
        payload: {'playerId': playerId},
      ),
      exceptPlayerId: playerId == hostPlayerId ? null : playerId,
    );
  }

  @override
  void publishArrowDragPreview({
    required String playerId,
    required double fx,
    required double fy,
    required double fx2,
    required double fy2,
  }) {
    session.arrowDragPreviews.value = {
      ...session.arrowDragPreviews.value,
      playerId: ArrowDragPreview(
        playerId: playerId,
        fx: fx,
        fy: fy,
        fx2: fx2,
        fy2: fy2,
      ),
    };
    hostServer.broadcast(
      NetMessage(
        type: NetMessageType.arrowDragPreview,
        payload: {'playerId': playerId, 'fx': fx, 'fy': fy, 'fx2': fx2, 'fy2': fy2},
      ),
      exceptPlayerId: playerId == hostPlayerId ? null : playerId,
    );
  }

  @override
  void clearArrowDragPreview(String playerId) {
    if (!session.arrowDragPreviews.value.containsKey(playerId)) return;
    session.arrowDragPreviews.value = {...session.arrowDragPreviews.value}
      ..remove(playerId);
    hostServer.broadcast(
      NetMessage(
        type: NetMessageType.arrowDragPreviewEnd,
        payload: {'playerId': playerId},
      ),
      exceptPlayerId: playerId == hostPlayerId ? null : playerId,
    );
  }
}
