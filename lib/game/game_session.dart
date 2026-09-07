import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/card_instance.dart';
import '../models/game_definition.dart';
import '../models/player.dart';
import '../models/table_state.dart';
import 'table_actions.dart';

const _uuid = Uuid();

/// Wraps the current [TableState] for consumption via `provider`. Used
/// identically by the host (authoritative) and by a client (fed by incoming
/// `fullState` messages via [applyRemoteState] instead of local action
/// calls -- see TableController for how the two differ in practice).
class GameSession extends ChangeNotifier {
  GameSession({required this.localPlayerId, required TableState initialState}) : _state = initialState;

  final String localPlayerId;
  final TableActions _actions = const TableActions();
  TableState _state;

  TableState get state => _state;

  /// Builds a fresh single-player sandbox session (M2): every card from
  /// [game] dealt face-down into one shared draw pile at the table center.
  factory GameSession.localSandbox({
    required GameDefinition game,
    required String localPlayerId,
    double pileX = 400,
    double pileY = 300,
  }) {
    final cards = <CardInstance>[];
    String? rootId;
    for (var i = 0; i < game.cards.length; i++) {
      final instanceId = _uuid.v4();
      cards.add(CardInstance(
        instanceId: instanceId,
        definitionId: game.cards[i].id,
        x: pileX,
        y: pileY,
        zIndex: i,
        faceUp: false,
        zone: CardZone.drawPile,
        // All cards anchor directly to the first card, forming one pile.
        stackParentId: i == 0 ? null : rootId,
      ));
      rootId ??= instanceId;
    }
    final state = TableState(
      gameId: game.id,
      players: [PlayerInfo(id: localPlayerId, name: 'You', role: PlayerRole.host)],
      cards: cards,
      revision: 0,
    );
    return GameSession(localPlayerId: localPlayerId, initialState: state);
  }

  void moveCard(String instanceId, double x, double y) {
    _state = _actions.moveCard(_state, instanceId: instanceId, x: x, y: y);
    notifyListeners();
  }

  void flipCard(String instanceId) {
    _state = _actions.flipCard(_state, instanceId: instanceId);
    notifyListeners();
  }

  void stackCard(String instanceId, String ontoInstanceId) {
    _state = _actions.stackCard(_state, instanceId: instanceId, ontoInstanceId: ontoInstanceId);
    notifyListeners();
  }

  /// Draws into [ownerId]'s hand, defaulting to this session's own local
  /// player -- the host overrides this to the requesting client's id when
  /// applying a networked draw request on their behalf.
  void drawCard(String pileInstanceId, {String? ownerId}) {
    _state = _actions.drawCard(_state, pileInstanceId: pileInstanceId, ownerId: ownerId ?? localPlayerId);
    notifyListeners();
  }

  void shufflePile(String pileRootInstanceId) {
    _state = _actions.shufflePile(_state, pileRootInstanceId: pileRootInstanceId);
    notifyListeners();
  }

  /// Replaces the entire state wholesale — used once networking lands (M4)
  /// to apply an incoming `fullState` snapshot from the host.
  void applyRemoteState(TableState newState) {
    if (newState.revision <= _state.revision) return;
    _state = newState;
    notifyListeners();
  }
}
