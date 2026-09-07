import 'dart:async';

import '../models/card_instance.dart';
import '../networking/host_server.dart';
import '../networking/net_message.dart';
import '../networking/state_filter.dart';
import 'game_session.dart';

/// Owns the host's authoritative [GameSession] in a networked match: applies
/// incoming client requests to it (structural validation only -- no rules
/// engine), and re-broadcasts a per-recipient filtered snapshot after every
/// change, including the host's own local actions.
class HostGameEngine {
  HostGameEngine({required this.session, required this.hostServer, required this.hostPlayerId});

  final GameSession session;
  final HostServer hostServer;
  final String hostPlayerId;

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
    final filtered = filterForRecipient(session.state, clientId);
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
      case NetMessageType.requestDraw:
        session.drawCard(msg.payload['pileInstanceId'] as String, ownerId: clientId);
        break;
      case NetMessageType.requestShuffle:
        session.shufflePile(msg.payload['pileRootInstanceId'] as String);
        break;
      case NetMessageType.hello:
      case NetMessageType.welcome:
      case NetMessageType.gameData:
      case NetMessageType.fullState:
      case NetMessageType.ping:
      case NetMessageType.pong:
      case NetMessageType.disconnect:
        break;
    }
  }

  bool _cardExists(String instanceId) => session.state.cards.any((c) => c.instanceId == instanceId);

  /// Structural + privacy guard: the card must exist, and a client may
  /// never act on a card sitting in another player's private hand.
  bool _isAllowedToActOn(String instanceId, String requesterPlayerId) {
    CardInstance? card;
    for (final c in session.state.cards) {
      if (c.instanceId == instanceId) {
        card = c;
        break;
      }
    }
    if (card == null) return false;
    if (card.zone == CardZone.hand && card.ownerId != null && card.ownerId != requesterPlayerId) {
      return false;
    }
    return true;
  }
}
