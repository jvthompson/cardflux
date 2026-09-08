import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_deck/game/table_actions.dart';
import 'package:flutter_deck/models/card_instance.dart';
import 'package:flutter_deck/models/table_state.dart';

const _actions = TableActions();

TableState _threeCardPile() {
  // root <- a, root <- b (star topology, matching a free-table pile built
  // via stackCard).
  return TableState(
    gameId: 'g',
    players: const [],
    cards: [
      CardInstance(instanceId: 'root', definitionId: 'd1', x: 0, y: 0, zIndex: 0, faceUp: false, zone: CardZone.table),
      CardInstance(instanceId: 'a', definitionId: 'd2', x: 0, y: 0, zIndex: 1, faceUp: false, zone: CardZone.table, stackParentId: 'root'),
      CardInstance(instanceId: 'b', definitionId: 'd3', x: 0, y: 0, zIndex: 2, faceUp: false, zone: CardZone.table, stackParentId: 'root'),
    ],
    revision: 0,
  );
}

TableState _threeCardZone({required String zoneId, String? ownerId}) {
  return TableState(
    gameId: 'g',
    players: const [],
    cards: [
      CardInstance(instanceId: 'z1', definitionId: 'd1', x: 0, y: 0, zIndex: 0, faceUp: false, zone: CardZone.zone, zoneId: zoneId, ownerId: ownerId),
      CardInstance(instanceId: 'z2', definitionId: 'd2', x: 0, y: 0, zIndex: 1, faceUp: false, zone: CardZone.zone, zoneId: zoneId, ownerId: ownerId),
      CardInstance(instanceId: 'z3', definitionId: 'd3', x: 0, y: 0, zIndex: 2, faceUp: false, zone: CardZone.zone, zoneId: zoneId, ownerId: ownerId),
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

    test('clears zoneId when dragging a card off a zone -- it must not linger in that zone group', () {
      final state = _threeCardZone(zoneId: 'deck');
      final next = _actions.moveCard(state, instanceId: 'z1', x: 0.5, y: 0.5);
      final moved = next.cards.firstWhere((c) => c.instanceId == 'z1');
      expect(moved.zone, CardZone.table);
      expect(moved.zoneId, isNull);
    });
  });

  group('moveStack', () {
    test('repositions every card in the stack, keeping zone/stackParentId intact', () {
      final state = _threeCardPile();
      final next = _actions.moveStack(state, rootInstanceId: 'root', x: 0.3, y: 0.4);
      for (final id in ['root', 'a', 'b']) {
        final c = next.cards.firstWhere((c) => c.instanceId == id);
        expect(c.x, 0.3);
        expect(c.y, 0.4);
        expect(c.zone, CardZone.table);
      }
      final before = {for (final c in state.cards) c.instanceId: c.stackParentId};
      final after = {for (final c in next.cards) c.instanceId: c.stackParentId};
      expect(after, before);
      expect(next.revision, state.revision + 1);
    });

    test('bumps only the current top-of-stack member to the new running-max zIndex', () {
      // 'b' (zIndex 2) is already the stack's top -- moving the stack should
      // push it even higher (to 3, the new global max) while leaving 'root'
      // and 'a' exactly where they were, so the pile's own internal draw
      // order is unaffected but its cross-pile rank moves to the front.
      final state = _threeCardPile();
      final next = _actions.moveStack(state, rootInstanceId: 'root', x: 0.3, y: 0.4);
      expect(next.cards.firstWhere((c) => c.instanceId == 'root').zIndex, 0);
      expect(next.cards.firstWhere((c) => c.instanceId == 'a').zIndex, 1);
      expect(next.cards.firstWhere((c) => c.instanceId == 'b').zIndex, 3);
    });

    test('is a no-op for an unknown root', () {
      final state = _threeCardPile();
      final next = _actions.moveStack(state, rootInstanceId: 'nonexistent', x: 0.3, y: 0.4);
      expect(next, same(state));
    });
  });

  group('moveGroup', () {
    TableState twoLooseCardsAndAPile() {
      // 'primary' is a lone loose card; 'passenger' is another lone loose
      // card sitting to its right; 'pRoot'/'pTop' form a 2-card official
      // pile further right still -- a mix of loose cards and an official
      // pile as passengers, like dragging the bottom of a cascade that also
      // happens to have a real pile resting on part of it.
      return TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(instanceId: 'primary', definitionId: 'd1', x: 0.1, y: 0.1, zIndex: 0, faceUp: false, zone: CardZone.table),
          CardInstance(instanceId: 'passenger', definitionId: 'd2', x: 0.3, y: 0.1, zIndex: 1, faceUp: false, zone: CardZone.table),
          CardInstance(instanceId: 'pRoot', definitionId: 'd3', x: 0.5, y: 0.1, zIndex: 2, faceUp: false, zone: CardZone.table),
          CardInstance(instanceId: 'pTop', definitionId: 'd4', x: 0.5, y: 0.1, zIndex: 3, faceUp: false, zone: CardZone.table, stackParentId: 'pRoot'),
          CardInstance(instanceId: 'untouched', definitionId: 'd5', x: 0.9, y: 0.9, zIndex: 4, faceUp: false, zone: CardZone.table),
        ],
        revision: 0,
      );
    }

    test('moves the primary card to the target position and fully detaches it', () {
      final state = _threeCardPile();
      final next = _actions.moveGroup(state, primaryInstanceId: 'a', passengerRootInstanceIds: const [], x: 0.7, y: 0.8);
      final moved = next.cards.firstWhere((c) => c.instanceId == 'a');
      expect(moved.x, 0.7);
      expect(moved.y, 0.8);
      expect(moved.zone, CardZone.table);
      expect(moved.stackParentId, isNull);
    });

    test('translates each passenger by the same delta the primary moved by, preserving relative offsets', () {
      final state = twoLooseCardsAndAPile();
      // primary moves from (0.1,0.1) to (0.15,0.25) -- delta (0.05, 0.15).
      final next = _actions.moveGroup(
        state,
        primaryInstanceId: 'primary',
        passengerRootInstanceIds: const ['passenger', 'pRoot'],
        x: 0.15,
        y: 0.25,
      );
      final passenger = next.cards.firstWhere((c) => c.instanceId == 'passenger');
      expect(passenger.x, closeTo(0.35, 1e-9));
      expect(passenger.y, closeTo(0.25, 1e-9));
      final untouched = next.cards.firstWhere((c) => c.instanceId == 'untouched');
      expect(untouched.x, 0.9);
      expect(untouched.y, 0.9);
    });

    test('moves every member of a passenger pile as a whole, preserving its internal structure', () {
      final state = twoLooseCardsAndAPile();
      final next = _actions.moveGroup(
        state,
        primaryInstanceId: 'primary',
        passengerRootInstanceIds: const ['passenger', 'pRoot'],
        x: 0.15,
        y: 0.25,
      );
      final pRoot = next.cards.firstWhere((c) => c.instanceId == 'pRoot');
      final pTop = next.cards.firstWhere((c) => c.instanceId == 'pTop');
      expect(pRoot.x, closeTo(0.55, 1e-9));
      expect(pRoot.y, closeTo(0.25, 1e-9));
      expect(pTop.x, pRoot.x);
      expect(pTop.y, pRoot.y);
      expect(pTop.stackParentId, 'pRoot');
    });

    test('bumps only the primary and each passenger stack\'s own top to a fresh ascending zIndex', () {
      final state = twoLooseCardsAndAPile();
      final next = _actions.moveGroup(
        state,
        primaryInstanceId: 'primary',
        passengerRootInstanceIds: const ['passenger', 'pRoot'],
        x: 0.15,
        y: 0.25,
      );
      final primaryZ = next.cards.firstWhere((c) => c.instanceId == 'primary').zIndex;
      final passengerZ = next.cards.firstWhere((c) => c.instanceId == 'passenger').zIndex;
      final pRootZ = next.cards.firstWhere((c) => c.instanceId == 'pRoot').zIndex;
      final pTopZ = next.cards.firstWhere((c) => c.instanceId == 'pTop').zIndex;
      // Ascending, in the order passed in (primary first, then each
      // passenger root in list order) and all above the pre-move max (4).
      expect(primaryZ, greaterThan(4));
      expect(passengerZ, greaterThan(primaryZ));
      expect(pTopZ, greaterThan(passengerZ));
      // Only pTop (the pile's own current top) is bumped -- pRoot keeps its
      // original zIndex, matching moveStack's minimal-touch behavior.
      expect(pRootZ, 2);
      final untouchedZ = next.cards.firstWhere((c) => c.instanceId == 'untouched').zIndex;
      expect(untouchedZ, 4);
    });

    test('is a no-op for an unknown primary', () {
      final state = twoLooseCardsAndAPile();
      final next = _actions.moveGroup(state, primaryInstanceId: 'nonexistent', passengerRootInstanceIds: const [], x: 0, y: 0);
      expect(next, same(state));
    });
  });

  group('rotateStack', () {
    test('a lone card (a stack of one) rotates clockwise and wraps 3 -> 0', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [CardInstance(instanceId: 'solo', definitionId: 'd1', x: 0, y: 0, zIndex: 0, faceUp: false, zone: CardZone.table, rotationTurns: 3)],
        revision: 0,
      );
      final next = _actions.rotateStack(state, rootInstanceId: 'solo', clockwise: true);
      expect(next.cards.single.rotationTurns, 0);
    });

    test('counter-clockwise wraps 0 -> 3', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [CardInstance(instanceId: 'solo', definitionId: 'd1', x: 0, y: 0, zIndex: 0, faceUp: false, zone: CardZone.table)],
        revision: 0,
      );
      final next = _actions.rotateStack(state, rootInstanceId: 'solo', clockwise: false);
      expect(next.cards.single.rotationTurns, 3);
    });

    test('rotates every card in a multi-card pile by the same delta', () {
      final state = _threeCardPile();
      final next = _actions.rotateStack(state, rootInstanceId: 'root', clockwise: true);
      for (final id in ['root', 'a', 'b']) {
        expect(next.cards.firstWhere((c) => c.instanceId == id).rotationTurns, 1);
      }
      expect(next.revision, state.revision + 1);
    });

    test('does not rotate a card outside the requested stack', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(instanceId: 'a', definitionId: 'd1', x: 0, y: 0, zIndex: 0, faceUp: false, zone: CardZone.table),
          CardInstance(instanceId: 'b', definitionId: 'd2', x: 0, y: 0, zIndex: 1, faceUp: false, zone: CardZone.table),
        ],
        revision: 0,
      );
      final next = _actions.rotateStack(state, rootInstanceId: 'a', clockwise: true);
      expect(next.cards.firstWhere((c) => c.instanceId == 'b').rotationTurns, 0);
    });

    test('is a no-op for an unknown root', () {
      final state = _threeCardPile();
      final next = _actions.rotateStack(state, rootInstanceId: 'nonexistent', clockwise: true);
      expect(next, same(state));
    });

    test('never rotates a card outside CardZone.table, even if named in the stack', () {
      // A zone card can't really be "in a stackParentId chain" today, but the
      // action still defensively ignores anything not on the table.
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [CardInstance(instanceId: 'z1', definitionId: 'd1', x: 0, y: 0, zIndex: 0, faceUp: false, zone: CardZone.zone, zoneId: 'deck')],
        revision: 0,
      );
      final next = _actions.rotateStack(state, rootInstanceId: 'z1', clockwise: true);
      expect(next.cards.single.rotationTurns, 0);
    });

    test('bumps only the current top-of-stack member to the new running-max zIndex', () {
      final state = _threeCardPile();
      final next = _actions.rotateStack(state, rootInstanceId: 'root', clockwise: true);
      expect(next.cards.firstWhere((c) => c.instanceId == 'root').zIndex, 0);
      expect(next.cards.firstWhere((c) => c.instanceId == 'a').zIndex, 1);
      expect(next.cards.firstWhere((c) => c.instanceId == 'b').zIndex, 3);
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

    test('bumps the flipped card to the new running-max zIndex', () {
      final state = _threeCardPile();
      final next = _actions.flipCard(state, instanceId: 'a');
      expect(next.cards.firstWhere((c) => c.instanceId == 'a').zIndex, 3);
      expect(next.cards.firstWhere((c) => c.instanceId == 'root').zIndex, 0);
      expect(next.cards.firstWhere((c) => c.instanceId == 'b').zIndex, 2);
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

    test('clears zoneId when stacking a zone card onto a free-table pile', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(instanceId: 'x', definitionId: 'd1', x: 10, y: 10, zIndex: 0, faceUp: false, zone: CardZone.table),
          CardInstance(instanceId: 'y', definitionId: 'd2', x: 99, y: 99, zIndex: 1, faceUp: false, zone: CardZone.zone, zoneId: 'discard_pile', ownerId: 'p1'),
        ],
        revision: 0,
      );
      final next = _actions.stackCard(state, instanceId: 'y', ontoInstanceId: 'x');
      expect(next.cards.firstWhere((c) => c.instanceId == 'y').zoneId, isNull);
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
      expect(moved.rotationTurns, 0);
      // Untouched cards remain exactly as they were.
      final root = next.cards.firstWhere((c) => c.instanceId == 'root');
      expect(root.zone, CardZone.table);
      expect(next.revision, state.revision + 1);
    });

    test('clears zoneId when dragging a zone card straight into the hand', () {
      final state = _threeCardZone(zoneId: 'deck');
      final next = _actions.moveToHand(state, instanceId: 'z1', ownerId: 'p1');
      expect(next.cards.firstWhere((c) => c.instanceId == 'z1').zoneId, isNull);
    });

    test('resets a nonzero rotation -- a card never shows up sideways in a hand', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [CardInstance(instanceId: 'a', definitionId: 'd1', x: 0, y: 0, zIndex: 0, faceUp: false, zone: CardZone.table, rotationTurns: 2)],
        revision: 0,
      );
      final next = _actions.moveToHand(state, instanceId: 'a', ownerId: 'p1');
      expect(next.cards.single.rotationTurns, 0);
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
      expect(root.zone, CardZone.table);
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

    test('resets a nonzero rotation -- a card never shows up sideways in a hand', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [CardInstance(instanceId: 'solo', definitionId: 'd1', x: 0, y: 0, zIndex: 0, faceUp: false, zone: CardZone.table, rotationTurns: 1)],
        revision: 0,
      );
      final next = _actions.drawCard(state, pileInstanceId: 'solo', ownerId: 'p1');
      expect(next.cards.single.rotationTurns, 0);
    });
  });

  group('drawFromZone', () {
    test('moves the top card of the zone into the given owner hand, face-up, detached', () {
      final state = _threeCardZone(zoneId: 'draw_deck', ownerId: 'p1');
      final next = _actions.drawFromZone(state, zoneId: 'draw_deck', zoneOwnerId: 'p1', toOwnerId: 'p1');
      // Highest zIndex in the zone is 'z3'.
      final drawn = next.cards.firstWhere((c) => c.instanceId == 'z3');
      expect(drawn.zone, CardZone.hand);
      expect(drawn.ownerId, 'p1');
      expect(drawn.faceUp, isTrue);
      expect(drawn.zoneId, isNull);
    });

    test('a shared zone (null owner) is drawable by anyone', () {
      final state = _threeCardZone(zoneId: 'deck');
      final next = _actions.drawFromZone(state, zoneId: 'deck', zoneOwnerId: null, toOwnerId: 'p2');
      final drawn = next.cards.firstWhere((c) => c.instanceId == 'z3');
      expect(drawn.zone, CardZone.hand);
      expect(drawn.ownerId, 'p2');
    });

    test('is a no-op on an empty/nonexistent zone', () {
      final state = _threeCardZone(zoneId: 'draw_deck', ownerId: 'p1');
      final next = _actions.drawFromZone(state, zoneId: 'discard_pile', zoneOwnerId: 'p1', toOwnerId: 'p1');
      expect(next, same(state));
    });

    test('resets a nonzero rotation -- a card never shows up sideways in a hand', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [CardInstance(instanceId: 'z1', definitionId: 'd1', x: 0, y: 0, zIndex: 0, faceUp: false, zone: CardZone.zone, zoneId: 'draw_deck', ownerId: 'p1', rotationTurns: 2)],
        revision: 0,
      );
      final next = _actions.drawFromZone(state, zoneId: 'draw_deck', zoneOwnerId: 'p1', toOwnerId: 'p1');
      expect(next.cards.single.rotationTurns, 0);
    });
  });

  group('returnToZone', () {
    test('places the card on top (drawn next) by default, face-down, owned by the zone', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(instanceId: 'z1', definitionId: 'd1', x: 0, y: 0, zIndex: 0, faceUp: false, zone: CardZone.zone, zoneId: 'draw_deck', ownerId: 'p1'),
          CardInstance(instanceId: 'inHand', definitionId: 'd2', x: 0, y: 0, zIndex: 5, faceUp: true, zone: CardZone.hand, ownerId: 'p1'),
        ],
        revision: 0,
      );
      final next = _actions.returnToZone(state, instanceId: 'inHand', zoneId: 'draw_deck', zoneOwnerId: 'p1', faceUp: false);
      final returned = next.cards.firstWhere((c) => c.instanceId == 'inHand');
      expect(returned.zone, CardZone.zone);
      expect(returned.zoneId, 'draw_deck');
      expect(returned.ownerId, 'p1');
      expect(returned.faceUp, isFalse);

      // Drawing next should immediately return this exact card -- it's on top.
      final drawn = _actions.drawFromZone(next, zoneId: 'draw_deck', zoneOwnerId: 'p1', toOwnerId: 'p1');
      expect(drawn.cards.firstWhere((c) => c.instanceId == 'inHand').zone, CardZone.hand);
    });

    test('a shared zone stays unowned even if a player id is passed as zoneOwnerId', () {
      final state = _threeCardZone(zoneId: 'deck');
      final inHand = CardInstance(instanceId: 'inHand', definitionId: 'd2', x: 0, y: 0, zIndex: 5, faceUp: true, zone: CardZone.hand, ownerId: 'p1');
      final withHandCard = state.copyWith(cards: [...state.cards, inHand]);
      final next = _actions.returnToZone(withHandCard, instanceId: 'inHand', zoneId: 'deck', zoneOwnerId: null, faceUp: false);
      expect(next.cards.firstWhere((c) => c.instanceId == 'inHand').ownerId, isNull);
    });

    test('sets faceUp according to the faceUp argument -- true for a discard-pile-style zone', () {
      final state = _threeCardZone(zoneId: 'discard_pile', ownerId: 'p1');
      final inHand = CardInstance(instanceId: 'inHand', definitionId: 'd2', x: 0, y: 0, zIndex: 5, faceUp: false, zone: CardZone.hand, ownerId: 'p1');
      final withHandCard = state.copyWith(cards: [...state.cards, inHand]);
      final next = _actions.returnToZone(withHandCard, instanceId: 'inHand', zoneId: 'discard_pile', zoneOwnerId: 'p1', faceUp: true);
      expect(next.cards.firstWhere((c) => c.instanceId == 'inHand').faceUp, isTrue);
    });

    test('snaps to the position an existing zone card already shares', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(instanceId: 'z1', definitionId: 'd1', x: 0.8, y: 0.5, zIndex: 0, faceUp: false, zone: CardZone.zone, zoneId: 'deck'),
          CardInstance(instanceId: 'onTable', definitionId: 'd2', x: 0.1, y: 0.1, zIndex: 5, faceUp: true, zone: CardZone.table),
        ],
        revision: 0,
      );
      final next = _actions.returnToZone(state, instanceId: 'onTable', zoneId: 'deck', zoneOwnerId: null, faceUp: false);
      final returned = next.cards.firstWhere((c) => c.instanceId == 'onTable');
      expect(returned.x, 0.8);
      expect(returned.y, 0.5);
    });

    test('an empty zone keeps the returned card at its own current x/y', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(instanceId: 'onTable', definitionId: 'd2', x: 0.1, y: 0.2, zIndex: 5, faceUp: true, zone: CardZone.table),
        ],
        revision: 0,
      );
      final next = _actions.returnToZone(state, instanceId: 'onTable', zoneId: 'discard_pile', zoneOwnerId: 'p1', faceUp: false);
      final returned = next.cards.firstWhere((c) => c.instanceId == 'onTable');
      expect(returned.x, 0.1);
      expect(returned.y, 0.2);
      expect(returned.zone, CardZone.zone);
      expect(returned.zoneId, 'discard_pile');
    });

    test('toBottom places the card below every other card in the zone', () {
      final state = _threeCardZone(zoneId: 'draw_deck', ownerId: 'p1');
      final inHand = CardInstance(instanceId: 'inHand', definitionId: 'd2', x: 0, y: 0, zIndex: 5, faceUp: true, zone: CardZone.hand, ownerId: 'p1');
      final withHandCard = state.copyWith(cards: [...state.cards, inHand]);
      final next = _actions.returnToZone(withHandCard, instanceId: 'inHand', zoneId: 'draw_deck', zoneOwnerId: 'p1', faceUp: false, toBottom: true);
      final returned = next.cards.firstWhere((c) => c.instanceId == 'inHand');
      final others = next.cards.where((c) => c.instanceId != 'inHand' && c.zoneId == 'draw_deck');
      expect(returned.zIndex, lessThan(others.map((c) => c.zIndex).reduce((x, y) => x < y ? x : y)));
    });

    test('is a no-op when the card is already in that exact zone', () {
      final state = _threeCardZone(zoneId: 'draw_deck', ownerId: 'p1');
      final next = _actions.returnToZone(state, instanceId: 'z1', zoneId: 'draw_deck', zoneOwnerId: 'p1', faceUp: false);
      expect(next, same(state));
    });

    test('resets a nonzero rotation -- a card never shows up sideways in a deck', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(instanceId: 'onTable', definitionId: 'd1', x: 0, y: 0, zIndex: 0, faceUp: false, zone: CardZone.table, rotationTurns: 1),
        ],
        revision: 0,
      );
      final next = _actions.returnToZone(state, instanceId: 'onTable', zoneId: 'draw_deck', zoneOwnerId: 'p1', faceUp: false);
      expect(next.cards.single.rotationTurns, 0);
    });
  });

  group('shuffleZone', () {
    test('flips every card in the zone face-down and reassigns zIndex without changing membership', () {
      final state = _threeCardZone(zoneId: 'draw_deck', ownerId: 'p1');
      final next = _actions.shuffleZone(state, zoneId: 'draw_deck', zoneOwnerId: 'p1', seed: 42);
      expect(next.cards.map((c) => c.instanceId).toSet(), state.cards.map((c) => c.instanceId).toSet());
      for (final c in next.cards) {
        expect(c.faceUp, isFalse);
      }
      expect(next.cards.map((c) => c.zIndex).toSet(), hasLength(next.cards.length));
    });

    test('is a no-op for a zone of 1 or fewer cards', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(instanceId: 'solo', definitionId: 'd1', x: 0, y: 0, zIndex: 0, faceUp: true, zone: CardZone.zone, zoneId: 'draw_deck', ownerId: 'p1'),
        ],
        revision: 0,
      );
      final next = _actions.shuffleZone(state, zoneId: 'draw_deck', zoneOwnerId: 'p1');
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
          CardInstance(instanceId: 'solo', definitionId: 'd1', x: 0, y: 0, zIndex: 0, faceUp: true, zone: CardZone.table),
        ],
        revision: 0,
      );
      final next = _actions.shufflePile(state, pileRootInstanceId: 'solo');
      expect(next, same(state));
    });
  });
}
