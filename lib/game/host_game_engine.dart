import 'dart:async';

import '../models/board_widget_instance.dart';
import '../models/card_instance.dart';
import '../models/player.dart';
import '../networking/host_server.dart';
import '../networking/net_message.dart';
import '../networking/state_filter.dart';
import 'game_session.dart';
import 'stack_utils.dart';

/// Owns the host's authoritative [GameSession] in a networked match: applies
/// incoming client requests to it (structural validation only -- no rules
/// engine), and re-broadcasts a per-recipient filtered snapshot after every
/// change, including the host's own local actions.
class HostGameEngine {
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

  void start() {
    session.addListener(_broadcast);
    _incomingSub = hostServer.incoming.listen(_handleMessage);
    _rosterSub = hostServer.rosterStream.listen(
      (roster) => session.syncConnectedPlayerIds({for (final p in roster) if (p.role != PlayerRole.host) p.id}),
    );
    _broadcast();
  }

  void dispose() {
    session.removeListener(_broadcast);
    _incomingSub?.cancel();
    _rosterSub?.cancel();
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
          );
        }
        break;
      case NetMessageType.requestFlip:
        final instanceId = msg.payload['instanceId'] as String;
        if (_isAllowedToActOn(instanceId, clientId)) {
          session.flipCard(instanceId);
        }
        break;
      case NetMessageType.requestStack:
        final instanceId = msg.payload['instanceId'] as String;
        final ontoInstanceId = msg.payload['ontoInstanceId'] as String;
        if (_isAllowedToActOn(instanceId, clientId) &&
            _cardExists(ontoInstanceId)) {
          session.stackCard(instanceId, ontoInstanceId);
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
        if (_isAllowedToDrawOrShuffle(pileInstanceId, clientId)) {
          session.drawCard(pileInstanceId, ownerId: clientId);
        }
        break;
      case NetMessageType.requestShuffle:
        final pileRootInstanceId = msg.payload['pileRootInstanceId'] as String;
        if (_isAllowedToDrawOrShuffle(pileRootInstanceId, clientId)) {
          session.shufflePile(pileRootInstanceId);
        }
        break;
      case NetMessageType.requestDrawFromZone:
        final zoneId = msg.payload['zoneId'] as String;
        session.drawFromZone(
          zoneId,
          zoneOwnerId: _zoneOwnerId(zoneId, clientId),
          toOwnerId: clientId,
        );
        break;
      case NetMessageType.requestReturnToZone:
        final instanceId = msg.payload['instanceId'] as String;
        final zoneId = msg.payload['zoneId'] as String;
        final toBottom = msg.payload['toBottom'] as bool? ?? false;
        if (_isAllowedToActOn(instanceId, clientId)) {
          session.returnToZone(
            instanceId,
            zoneId,
            zoneOwnerId: _zoneOwnerId(zoneId, clientId),
            toBottom: toBottom,
          );
        }
        break;
      case NetMessageType.requestShuffleZone:
        final zoneId = msg.payload['zoneId'] as String;
        session.shuffleZone(
          zoneId,
          zoneOwnerId: _zoneOwnerId(zoneId, clientId),
        );
        break;
      case NetMessageType.requestStartSearchZone:
        final zoneId = msg.payload['zoneId'] as String;
        session.startSearchZone(
          zoneId,
          zoneOwnerId: _zoneOwnerId(zoneId, clientId),
          searcherId: clientId,
        );
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
        session.moveWidget(
          msg.payload['instanceId'] as String,
          (msg.payload['x'] as num).toDouble(),
          (msg.payload['y'] as num).toDouble(),
        );
        break;
      case NetMessageType.requestSetWidgetValue:
        session.setWidgetValue(
          msg.payload['instanceId'] as String,
          msg.payload['value'] as int,
        );
        break;
      case NetMessageType.requestDeleteWidget:
        final instanceId = msg.payload['instanceId'] as String;
        if (_isAllowedToDeleteWidget(instanceId, clientId)) {
          session.deleteWidget(instanceId);
        }
        break;
      case NetMessageType.requestSetWidgetColors:
        session.setWidgetColors(
          msg.payload['instanceId'] as String,
          msg.payload['backgroundColor'] as int,
          msg.payload['textColor'] as int,
        );
        break;
      case NetMessageType.requestDuplicateWidget:
        session.duplicateWidget(
          msg.payload['sourceInstanceId'] as String,
          msg.payload['newInstanceId'] as String,
          (msg.payload['x'] as num).toDouble(),
          (msg.payload['y'] as num).toDouble(),
        );
        break;
      case NetMessageType.requestAttachWidgetToCard:
        session.attachWidgetToCard(
          msg.payload['instanceId'] as String,
          msg.payload['cardId'] as String,
          (msg.payload['x'] as num).toDouble(),
          (msg.payload['y'] as num).toDouble(),
        );
        break;
      case NetMessageType.hello:
      case NetMessageType.welcome:
      case NetMessageType.gameData:
      case NetMessageType.fullState:
      case NetMessageType.requestDeckChosen:
      case NetMessageType.requestReady:
      case NetMessageType.lobbyRosterUpdate:
      case NetMessageType.lobbyReadyUpdate:
      case NetMessageType.ping:
      case NetMessageType.pong:
      case NetMessageType.disconnect:
        // requestDeckChosen/requestReady/lobby* are only meaningful before
        // this engine exists (see HostLoadDeckScreen, which subscribes to
        // hostServer.incoming directly during deck selection) -- a
        // late/duplicate one here is a no-op.
        break;
    }
  }

  bool _cardExists(String instanceId) =>
      session.state.cards.any((c) => c.instanceId == instanceId);

  /// A zone request never carries an owner -- it always means "the
  /// requester's own instance of this zone, or the shared one" -- resolved
  /// here from the game's own [ZoneDefinition]s rather than trusted from the
  /// client, so a client can never claim to act on another player's zone.
  String? _zoneOwnerId(String zoneId, String requesterPlayerId) {
    final zone = session.game.zones.firstWhere((z) => z.id == zoneId);
    return zone.shared ? null : requesterPlayerId;
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

  /// Mirrors [_isAllowedToActOn]'s shape for a widget instead of a card: a
  /// widget with no [BoardWidgetInstance.creatorId] (every kind except an
  /// arrow, today) is always fair game -- widgets stay deliberately
  /// ownerless by default (see `table_controller.dart`'s doc comment) --
  /// but an arrow may only be deleted by the player who drew it.
  bool _isAllowedToDeleteWidget(String instanceId, String requesterPlayerId) {
    BoardWidgetInstance? w;
    for (final widget in session.state.widgets) {
      if (widget.instanceId == instanceId) {
        w = widget;
        break;
      }
    }
    if (w == null) return false;
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
}
