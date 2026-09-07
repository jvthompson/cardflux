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

  group('moveStack', () {
    test('repositions every card in the stack, keeping zone/stackParentId/zIndex intact', () {
      final state = _threeCardPile();
      final next = _actions.moveStack(state, rootInstanceId: 'root', x: 0.3, y: 0.4);
      for (final id in ['root', 'a', 'b']) {
        final c = next.cards.firstWhere((c) => c.instanceId == id);
        expect(c.x, 0.3);
        expect(c.y, 0.4);
        expect(c.zone, CardZone.drawPile);
      }
      final before = {for (final c in state.cards) c.instanceId: (c.stackParentId, c.zIndex)};
      final after = {for (final c in next.cards) c.instanceId: (c.stackParentId, c.zIndex)};
      expect(after, before);
      expect(next.revision, state.revision + 1);
    });

    test('is a no-op for an unknown root', () {
      final state = _threeCardPile();
      final next = _actions.moveStack(state, rootInstanceId: 'nonexistent', x: 0.3, y: 0.4);
      expect(next, same(state));
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

  group('moveToHand', () {
    test('moves the given card into the owner hand, face-up, detached from its stack', () {
      final state = _threeCardPile();
      final next = _actions.moveToHand(state, instanceId: 'a', ownerId: 'p1');
      final moved = next.cards.firstWhere((c) => c.instanceId == 'a');
      expect(moved.zone, CardZone.hand);
      expect(moved.ownerId, 'p1');
      expect(moved.faceUp, isTrue);
      expect(moved.stackParentId, isNull);
      // Untouched cards remain exactly as they were.
      final root = next.cards.firstWhere((c) => c.instanceId == 'root');
      expect(root.zone, CardZone.drawPile);
      expect(next.revision, state.revision + 1);
    });
  });

  group('reorderHand', () {
    TableState threeHandCards() {
      return TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(instanceId: 'h1', definitionId: 'd1', x: 0, y: 0, zIndex: 10, faceUp: true, zone: CardZone.hand, ownerId: 'p1'),
          CardInstance(instanceId: 'h2', definitionId: 'd2', x: 0, y: 0, zIndex: 11, faceUp: true, zone: CardZone.hand, ownerId: 'p1'),
          CardInstance(instanceId: 'h3', definitionId: 'd3', x: 0, y: 0, zIndex: 12, faceUp: true, zone: CardZone.hand, ownerId: 'p1'),
          // Untouched control: a different owner's hand card.
          CardInstance(instanceId: 'other', definitionId: 'd4', x: 0, y: 0, zIndex: 20, faceUp: true, zone: CardZone.hand, ownerId: 'p2'),
        ],
        revision: 0,
      );
    }

    List<String> displayOrder(TableState state, String ownerId) {
      final hand = state.cards.where((c) => c.zone == CardZone.hand && c.ownerId == ownerId).toList()
        ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
      return hand.map((c) => c.instanceId).toList();
    }

    test('moving the last card to the front shifts the rest right', () {
      final state = threeHandCards();
      final next = _actions.reorderHand(state, instanceId: 'h3', ownerId: 'p1', targetIndex: 0);
      expect(displayOrder(next, 'p1'), ['h3', 'h1', 'h2']);
      expect(next.revision, state.revision + 1);
    });

    test('moving the first card between the other two', () {
      final state = threeHandCards();
      final next = _actions.reorderHand(state, instanceId: 'h1', ownerId: 'p1', targetIndex: 1);
      expect(displayOrder(next, 'p1'), ['h2', 'h1', 'h3']);
    });

    test('targetIndex past the end just appends', () {
      final state = threeHandCards();
      final next = _actions.reorderHand(state, instanceId: 'h1', ownerId: 'p1', targetIndex: 99);
      expect(displayOrder(next, 'p1'), ['h2', 'h3', 'h1']);
    });

    test("does not touch another player's hand or any other card", () {
      final state = threeHandCards();
      final next = _actions.reorderHand(state, instanceId: 'h3', ownerId: 'p1', targetIndex: 0);
      final other = next.cards.firstWhere((c) => c.instanceId == 'other');
      expect(other.zIndex, 20);
    });

    test('is a no-op when instanceId is not in the owner\'s hand', () {
      final state = threeHandCards();
      final next = _actions.reorderHand(state, instanceId: 'other', ownerId: 'p1', targetIndex: 0);
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

  group('returnToDeck', () {
    test('places the card on top (drawn next) by default, face-down, owned by ownerId', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(instanceId: 'root', definitionId: 'd1', x: 0, y: 0, zIndex: 0, faceUp: false, zone: CardZone.drawPile, ownerId: 'p1'),
          CardInstance(instanceId: 'inHand', definitionId: 'd2', x: 0, y: 0, zIndex: 5, faceUp: true, zone: CardZone.hand, ownerId: 'p1'),
        ],
        revision: 0,
      );
      final next = _actions.returnToDeck(state, instanceId: 'inHand', deckRootInstanceId: 'root', ownerId: 'p1');
      final returned = next.cards.firstWhere((c) => c.instanceId == 'inHand');
      expect(returned.zone, CardZone.drawPile);
      expect(returned.ownerId, 'p1');
      expect(returned.faceUp, isFalse);
      expect(returned.stackParentId, 'root');

      // Drawing next should immediately return this exact card -- it's on top.
      final drawn = _actions.drawCard(next, pileInstanceId: 'root', ownerId: 'p1');
      expect(drawn.cards.firstWhere((c) => c.instanceId == 'inHand').zone, CardZone.hand);
    });

    test('an existing deck keeps its own ownerId regardless of the passed-in ownerId', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(instanceId: 'root', definitionId: 'd1', x: 0, y: 0, zIndex: 0, faceUp: false, zone: CardZone.drawPile, ownerId: 'p1'),
          CardInstance(instanceId: 'inHand', definitionId: 'd2', x: 0, y: 0, zIndex: 5, faceUp: true, zone: CardZone.hand, ownerId: 'p2'),
        ],
        revision: 0,
      );
      // p2 is returning a card, but the deck itself belongs to p1 -- the
      // returned card should take on the deck's ownership, not p2's.
      final next = _actions.returnToDeck(state, instanceId: 'inHand', deckRootInstanceId: 'root', ownerId: 'p2');
      expect(next.cards.firstWhere((c) => c.instanceId == 'inHand').ownerId, 'p1');
    });

    test('a shared/unowned deck stays unowned even if the acting player passes their own id', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(instanceId: 'root', definitionId: 'd1', x: 0, y: 0, zIndex: 0, faceUp: false, zone: CardZone.drawPile),
          CardInstance(instanceId: 'inHand', definitionId: 'd2', x: 0, y: 0, zIndex: 5, faceUp: true, zone: CardZone.hand, ownerId: 'p1'),
        ],
        revision: 0,
      );
      final next = _actions.returnToDeck(state, instanceId: 'inHand', deckRootInstanceId: 'root', ownerId: 'p1');
      expect(next.cards.firstWhere((c) => c.instanceId == 'inHand').ownerId, isNull);
    });

    test('snaps to the deck root\'s x/y instead of keeping the card\'s old position', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(instanceId: 'root', definitionId: 'd1', x: 0.8, y: 0.5, zIndex: 0, faceUp: false, zone: CardZone.drawPile),
          CardInstance(instanceId: 'onTable', definitionId: 'd2', x: 0.1, y: 0.1, zIndex: 5, faceUp: true, zone: CardZone.table),
        ],
        revision: 0,
      );
      final next = _actions.returnToDeck(state, instanceId: 'onTable', deckRootInstanceId: 'root', ownerId: 'p1');
      final returned = next.cards.firstWhere((c) => c.instanceId == 'onTable');
      expect(returned.x, 0.8);
      expect(returned.y, 0.5);
    });

    test('an empty deck keeps the returned card at its own current x/y', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(instanceId: 'onTable', definitionId: 'd2', x: 0.1, y: 0.2, zIndex: 5, faceUp: true, zone: CardZone.table),
        ],
        revision: 0,
      );
      final next = _actions.returnToDeck(state, instanceId: 'onTable', deckRootInstanceId: null, ownerId: 'p1');
      final returned = next.cards.firstWhere((c) => c.instanceId == 'onTable');
      expect(returned.x, 0.1);
      expect(returned.y, 0.2);
    });

    test('toBottom places the card below every other card in the deck', () {
      final state = _threeCardPile();
      final next = _actions.returnToDeck(
        state,
        instanceId: 'a',
        deckRootInstanceId: 'root',
        ownerId: 'p1',
        toBottom: true,
      );
      final returned = next.cards.firstWhere((c) => c.instanceId == 'a');
      final others = next.cards.where((c) => c.instanceId != 'a');
      expect(returned.zIndex, lessThan(others.map((c) => c.zIndex).reduce((x, y) => x < y ? x : y)));
    });

    test('an empty deck (null root) makes the returned card the new root', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(instanceId: 'inHand', definitionId: 'd2', x: 0, y: 0, zIndex: 0, faceUp: true, zone: CardZone.hand, ownerId: 'p1'),
        ],
        revision: 0,
      );
      final next = _actions.returnToDeck(state, instanceId: 'inHand', deckRootInstanceId: null, ownerId: 'p1');
      final returned = next.cards.firstWhere((c) => c.instanceId == 'inHand');
      expect(returned.zone, CardZone.drawPile);
      expect(returned.stackParentId, isNull);
    });

    test('is a no-op when returning the deck root onto itself', () {
      final state = _threeCardPile();
      final next = _actions.returnToDeck(state, instanceId: 'root', deckRootInstanceId: 'root', ownerId: 'p1');
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
