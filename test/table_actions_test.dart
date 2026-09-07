import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_deck/game/table_actions.dart';
import 'package:flutter_deck/models/card_instance.dart';
import 'package:flutter_deck/models/table_state.dart';

const _actions = TableActions();

TableState _threeCardPile() {
  // root <- a, root <- b (star topology, matching GameSession.localSandbox).
  return TableState(
    gameId: 'g',
    players: const [],
    cards: [
      CardInstance(instanceId: 'root', definitionId: 'd1', x: 0, y: 0, zIndex: 0, faceUp: false, zone: CardZone.drawPile),
      CardInstance(instanceId: 'a', definitionId: 'd2', x: 0, y: 0, zIndex: 1, faceUp: false, zone: CardZone.drawPile, stackParentId: 'root'),
      CardInstance(instanceId: 'b', definitionId: 'd3', x: 0, y: 0, zIndex: 2, faceUp: false, zone: CardZone.drawPile, stackParentId: 'root'),
    ],
    revision: 0,
  );
}

void main() {
  group('moveCard', () {
    test('updates position, detaches from stack, and moves to table zone', () {
      final state = _threeCardPile();
      final next = _actions.moveCard(state, instanceId: 'a', x: 50, y: 60);
      final moved = next.cards.firstWhere((c) => c.instanceId == 'a');
      expect(moved.x, 50);
      expect(moved.y, 60);
      expect(moved.zone, CardZone.table);
      expect(moved.stackParentId, isNull);
      expect(next.revision, state.revision + 1);
    });
  });

  group('flipCard', () {
    test('toggles faceUp', () {
      final state = _threeCardPile();
      final next = _actions.flipCard(state, instanceId: 'a');
      expect(next.cards.firstWhere((c) => c.instanceId == 'a').faceUp, isTrue);
      final flippedBack = _actions.flipCard(next, instanceId: 'a');
      expect(flippedBack.cards.firstWhere((c) => c.instanceId == 'a').faceUp, isFalse);
    });
  });

  group('stackCard', () {
    test('snaps position/zone and links stackParentId', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(instanceId: 'x', definitionId: 'd1', x: 10, y: 10, zIndex: 0, faceUp: false, zone: CardZone.table),
          CardInstance(instanceId: 'y', definitionId: 'd2', x: 99, y: 99, zIndex: 1, faceUp: false, zone: CardZone.table),
        ],
        revision: 0,
      );
      final next = _actions.stackCard(state, instanceId: 'y', ontoInstanceId: 'x');
      final stacked = next.cards.firstWhere((c) => c.instanceId == 'y');
      expect(stacked.x, 10);
      expect(stacked.y, 10);
      expect(stacked.stackParentId, 'x');
    });

    test('is a no-op when stacking a card onto itself', () {
      final state = _threeCardPile();
      final next = _actions.stackCard(state, instanceId: 'a', ontoInstanceId: 'a');
      expect(next, same(state));
    });

    test('is a no-op when the target does not exist', () {
      final state = _threeCardPile();
      final next = _actions.stackCard(state, instanceId: 'a', ontoInstanceId: 'nope');
      expect(next, same(state));
    });
  });

  group('drawCard', () {
    test('moves the top card into the given owner hand, face-up, detached', () {
      final state = _threeCardPile();
      final next = _actions.drawCard(state, pileInstanceId: 'root', ownerId: 'p1');
      // Highest zIndex among non-root candidates is 'b' (zIndex 2).
      final drawn = next.cards.firstWhere((c) => c.instanceId == 'b');
      expect(drawn.zone, CardZone.hand);
      expect(drawn.ownerId, 'p1');
      expect(drawn.faceUp, isTrue);
      expect(drawn.stackParentId, isNull);
      // The pile anchor itself must not be the one drawn while others remain.
      final root = next.cards.firstWhere((c) => c.instanceId == 'root');
      expect(root.zone, CardZone.drawPile);
    });

    test('the anchor card is only drawn once it is the last card in the pile', () {
      var state = _threeCardPile();
      state = _actions.drawCard(state, pileInstanceId: 'root', ownerId: 'p1'); // draws 'b'
      state = _actions.drawCard(state, pileInstanceId: 'root', ownerId: 'p1'); // draws 'a'
      // Only 'root' remains in the pile now — drawing again must draw it.
      final next = _actions.drawCard(state, pileInstanceId: 'root', ownerId: 'p1');
      final root = next.cards.firstWhere((c) => c.instanceId == 'root');
      expect(root.zone, CardZone.hand);
      expect(root.ownerId, 'p1');
    });

    test('is a no-op on an empty/nonexistent pile', () {
      final state = _threeCardPile();
      final next = _actions.drawCard(state, pileInstanceId: 'does-not-exist', ownerId: 'p1');
      expect(next, same(state));
    });
  });

  group('shufflePile', () {
    test('flips every card in the stack face-down and reassigns zIndex without changing membership', () {
      final state = _threeCardPile();
      final next = _actions.shufflePile(state, pileRootInstanceId: 'root', seed: 42);
      expect(next.cards.map((c) => c.instanceId).toSet(), state.cards.map((c) => c.instanceId).toSet());
      for (final c in next.cards) {
        expect(c.faceUp, isFalse);
      }
      // zIndex values must still be distinct after shuffling.
      expect(next.cards.map((c) => c.zIndex).toSet(), hasLength(next.cards.length));
    });

    test('is a no-op for a stack of 1 or fewer cards', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(instanceId: 'solo', definitionId: 'd1', x: 0, y: 0, zIndex: 0, faceUp: true, zone: CardZone.drawPile),
        ],
        revision: 0,
      );
      final next = _actions.shufflePile(state, pileRootInstanceId: 'solo');
      expect(next, same(state));
    });
  });
}
