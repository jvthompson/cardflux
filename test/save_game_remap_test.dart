import 'package:flutter_deck/game/save_game_remap.dart';
import 'package:flutter_deck/models/board_widget_instance.dart';
import 'package:flutter_deck/models/card_instance.dart';
import 'package:flutter_deck/models/player.dart';
import 'package:flutter_deck/models/table_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _savedAlice = PlayerInfo(id: 'saved_alice', name: 'Alice', role: PlayerRole.host, color: 0xFFD32F2F);
const _savedBob = PlayerInfo(id: 'saved_bob', name: 'Bob', role: PlayerRole.client, color: 0xFF1976D2);

const _currentAlice = PlayerInfo(id: 'cur_alice', name: 'Alice', role: PlayerRole.client, color: 0xFF388E3C);
const _currentBob = PlayerInfo(id: 'cur_bob', name: 'Bob', role: PlayerRole.host, color: 0xFF7B1FA2);

void main() {
  group('matchPlayersByName', () {
    test('matches unique names on both sides', () {
      final result = matchPlayersByName(
        savedPlayers: [_savedAlice, _savedBob],
        currentPlayers: [_currentBob, _currentAlice],
      );
      expect(result.matchedSavedIdToCurrentId, {'saved_alice': 'cur_alice', 'saved_bob': 'cur_bob'});
      expect(result.unmatchedSavedPlayers, isEmpty);
      expect(result.unmatchedCurrentPlayers, isEmpty);
    });

    test('a saved name absent from current players is left unmatched', () {
      final result = matchPlayersByName(
        savedPlayers: [_savedAlice],
        currentPlayers: [_currentBob],
      );
      expect(result.matchedSavedIdToCurrentId, isEmpty);
      expect(result.unmatchedSavedPlayers, [_savedAlice]);
      expect(result.unmatchedCurrentPlayers, [_currentBob]);
    });

    test('a name duplicated on the saved side leaves both copies unmatched', () {
      const savedAlice2 = PlayerInfo(id: 'saved_alice2', name: 'Alice', role: PlayerRole.client, color: 0xFF000000);
      final result = matchPlayersByName(
        savedPlayers: [_savedAlice, savedAlice2],
        currentPlayers: [_currentAlice],
      );
      expect(result.matchedSavedIdToCurrentId, isEmpty);
      expect(result.unmatchedSavedPlayers, [_savedAlice, savedAlice2]);
      expect(result.unmatchedCurrentPlayers, [_currentAlice]);
    });

    test('a name duplicated on the current side leaves the saved player unmatched with both copies in the pool', () {
      const currentAlice2 = PlayerInfo(id: 'cur_alice2', name: 'Alice', role: PlayerRole.client, color: 0xFF000000);
      final result = matchPlayersByName(
        savedPlayers: [_savedAlice],
        currentPlayers: [_currentAlice, currentAlice2],
      );
      expect(result.matchedSavedIdToCurrentId, isEmpty);
      expect(result.unmatchedSavedPlayers, [_savedAlice]);
      expect(result.unmatchedCurrentPlayers, [_currentAlice, currentAlice2]);
    });
  });

  group('buildLoadedTableState', () {
    final savedState = TableState(
      gameId: 'g1',
      players: const [_savedAlice, _savedBob],
      cards: [
        CardInstance(
          instanceId: 'c1',
          definitionId: 'card_a',
          x: 0.1,
          y: 0.2,
          zIndex: 1,
          faceUp: true,
          zone: CardZone.hand,
          ownerId: 'saved_alice',
        ),
        CardInstance(
          instanceId: 'c2',
          definitionId: 'card_b',
          x: 0.3,
          y: 0.4,
          zIndex: 2,
          faceUp: false,
          zone: CardZone.table,
          ownerId: 'saved_bob',
          stackParentId: 'c1',
        ),
        CardInstance(
          instanceId: 'c3',
          definitionId: 'gone_card',
          x: 0.5,
          y: 0.5,
          zIndex: 3,
          faceUp: false,
          zone: CardZone.table,
        ),
      ],
      revision: 42,
      widgets: [
        BoardWidgetInstance(
          instanceId: 'w1',
          kind: BoardWidgetKind.token,
          x: 0.1,
          y: 0.1,
          zIndex: 1,
          ownerId: 'saved_alice',
          creatorId: 'saved_bob',
          attachedCardId: 'c3',
        ),
      ],
      searches: const [],
    );

    final idMap = {'saved_alice': 'cur_alice', 'saved_bob': 'cur_bob'};
    final validIds = {'card_a', 'card_b'};

    test('rebuilds players in saved seat order, filled by the current identity behind each seat', () {
      final result = buildLoadedTableState(
        saved: savedState,
        currentPlayers: [_currentBob, _currentAlice],
        savedIdToCurrentId: idMap,
        validDefinitionIds: validIds,
      );
      expect(result.state.players.map((p) => p.id), ['cur_alice', 'cur_bob']);
    });

    test('rewrites ownerId/creatorId through the id map', () {
      final result = buildLoadedTableState(
        saved: savedState,
        currentPlayers: [_currentAlice, _currentBob],
        savedIdToCurrentId: idMap,
        validDefinitionIds: validIds,
      );
      final c1 = result.state.cards.firstWhere((c) => c.instanceId == 'c1');
      expect(c1.ownerId, 'cur_alice');
      final w1 = result.state.widgets.single;
      expect(w1.ownerId, 'cur_alice');
      expect(w1.creatorId, 'cur_bob');
    });

    test('drops a card with an unrecognized definitionId and counts it', () {
      final result = buildLoadedTableState(
        saved: savedState,
        currentPlayers: [_currentAlice, _currentBob],
        savedIdToCurrentId: idMap,
        validDefinitionIds: validIds,
      );
      expect(result.droppedCardCount, 1);
      expect(result.state.cards.map((c) => c.instanceId), isNot(contains('c3')));
    });

    test('clears a dangling attachedCardId pointing at a dropped card', () {
      final result = buildLoadedTableState(
        saved: savedState,
        currentPlayers: [_currentAlice, _currentBob],
        savedIdToCurrentId: idMap,
        validDefinitionIds: validIds,
      );
      expect(result.state.widgets.single.attachedCardId, isNull);
    });

    test('clears a dangling stackParentId pointing at a dropped card', () {
      final savedWithDroppedParent = TableState(
        gameId: 'g1',
        players: const [_savedAlice],
        cards: [
          CardInstance(
            instanceId: 'child',
            definitionId: 'card_a',
            x: 0,
            y: 0,
            zIndex: 1,
            faceUp: true,
            zone: CardZone.table,
            stackParentId: 'missing_parent',
          ),
          CardInstance(
            instanceId: 'missing_parent',
            definitionId: 'gone_card',
            x: 0,
            y: 0,
            zIndex: 0,
            faceUp: true,
            zone: CardZone.table,
          ),
        ],
        revision: 1,
      );
      final result = buildLoadedTableState(
        saved: savedWithDroppedParent,
        currentPlayers: [_currentAlice],
        savedIdToCurrentId: {'saved_alice': 'cur_alice'},
        validDefinitionIds: {'card_a'},
      );
      expect(result.state.cards.single.instanceId, 'child');
      expect(result.state.cards.single.stackParentId, isNull);
    });

    test('searches is always empty, revision and gameId pass through unchanged', () {
      final result = buildLoadedTableState(
        saved: savedState,
        currentPlayers: [_currentAlice, _currentBob],
        savedIdToCurrentId: idMap,
        validDefinitionIds: validIds,
      );
      expect(result.state.searches, isEmpty);
      expect(result.state.revision, 42);
      expect(result.state.gameId, 'g1');
    });
  });
}
