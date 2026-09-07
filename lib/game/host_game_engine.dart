import 'dart:async';

import '../models/card_instance.dart';
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
  HostGameEngine({required this.session, required this.hostServer, required this.hostPlayerId});

  final GameSession session;
  final HostServer hostServer;
  final String hostPlayerId;

  static const StackUtils _stacks = StackUtils();

  StreamSubscription<NetMessage>? _incomingSub;
  int _lastBroadcastRevision = -1;

  void start() {
    session.addListener(_broadcast);
    _incomingSub = hostServer.incoming.listen(_handleMessage);
    _broadcast();
  }

  void dispose() {
    session.removeListener(_broadcast);
    _incomingSub?.cancel();
  }

  void _broadcast() {
    final clientId = hostServer.opponentPlayerId;
    if (clientId == null) return;
    if (session.state.revision == _lastBroadcastRevision) return;
    _lastBroadcastRevision = session.state.revision;
    final visibleZoneIds = {for (final z in session.game.zones) if (z.visibleToAll) z.id};
    final filtered = filterForRecipient(session.state, clientId, visibleZoneIds: visibleZoneIds);
    hostServer.send(NetMessage(type: NetMessageType.fullState, payload: filtered.toJson()));
  }

  void _handleMessage(NetMessage msg) {
    final clientId = hostServer.opponentPlayerId;
    if (clientId == null) return;

    switch (msg.type) {
      case NetMessageType.requestMove:
        final instanceId = msg.payload['instanceId'] as String;
        if (_isAllowedToActOn(instanceId, clientId)) {
          session.moveCard(instanceId, (msg.payload['x'] as num).toDouble(), (msg.payload['y'] as num).toDouble());
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
          session.rotateStack(rootInstanceId, clockwise: msg.payload['clockwise'] as bool);
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
        if (_isAllowedToActOn(instanceId, clientId) && _cardExists(ontoInstanceId)) {
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
        session.drawFromZone(zoneId, zoneOwnerId: _zoneOwnerId(zoneId, clientId), toOwnerId: clientId);
        break;
      case NetMessageType.requestReturnToZone:
        final instanceId = msg.payload['instanceId'] as String;
        final zoneId = msg.payload['zoneId'] as String;
        final toBottom = msg.payload['toBottom'] as bool? ?? false;
        if (_isAllowedToActOn(instanceId, clientId)) {
          session.returnToZone(instanceId, zoneId, zoneOwnerId: _zoneOwnerId(zoneId, clientId), toBottom: toBottom);
        }
        break;
      case NetMessageType.requestShuffleZone:
        final zoneId = msg.payload['zoneId'] as String;
        session.shuffleZone(zoneId, zoneOwnerId: _zoneOwnerId(zoneId, clientId));
        break;
      case NetMessageType.hello:
      case NetMessageType.welcome:
      case NetMessageType.gameData:
      case NetMessageType.fullState:
      case NetMessageType.requestDeckChosen:
      case NetMessageType.ping:
      case NetMessageType.pong:
      case NetMessageType.disconnect:
        // requestDeckChosen is only meaningful before this engine exists
        // (see HostLoadDeckScreen, which subscribes to hostServer.incoming
        // directly during deck selection) -- a late/duplicate one here is a
        // no-op.
        break;
    }
  }

  bool _cardExists(String instanceId) => session.state.cards.any((c) => c.instanceId == instanceId);

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

  /// A client may draw from or shuffle any unowned pile (e.g. a shared
  /// sandbox pile), but only their *own* personal deck -- never another
  /// player's.
  bool _isAllowedToDrawOrShuffle(String pileInstanceId, String requesterPlayerId) {
    final stack = _stacks.stackOf(session.state.cards, pileInstanceId);
    for (final c in stack) {
      if (c.ownerId != null && c.ownerId != requesterPlayerId) return false;
    }
    return true;
  }
}
