import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_deck/game/table_actions.dart';
import 'package:flutter_deck/models/active_search.dart';
import 'package:flutter_deck/models/board_widget_instance.dart';
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
      CardInstance(
        instanceId: 'root',
        definitionId: 'd1',
        x: 0,
        y: 0,
        zIndex: 0,
        faceUp: false,
        zone: CardZone.table,
      ),
      CardInstance(
        instanceId: 'a',
        definitionId: 'd2',
        x: 0,
        y: 0,
        zIndex: 1,
        faceUp: false,
        zone: CardZone.table,
        stackParentId: 'root',
      ),
      CardInstance(
        instanceId: 'b',
        definitionId: 'd3',
        x: 0,
        y: 0,
        zIndex: 2,
        faceUp: false,
        zone: CardZone.table,
        stackParentId: 'root',
      ),
    ],
    revision: 0,
  );
}

TableState _threeCardZone({required String zoneId, String? ownerId}) {
  return TableState(
    gameId: 'g',
    players: const [],
    cards: [
      CardInstance(
        instanceId: 'z1',
        definitionId: 'd1',
        x: 0,
        y: 0,
        zIndex: 0,
        faceUp: false,
        zone: CardZone.zone,
        zoneId: zoneId,
        ownerId: ownerId,
      ),
      CardInstance(
        instanceId: 'z2',
        definitionId: 'd2',
        x: 0,
        y: 0,
        zIndex: 1,
        faceUp: false,
        zone: CardZone.zone,
        zoneId: zoneId,
        ownerId: ownerId,
      ),
      CardInstance(
        instanceId: 'z3',
        definitionId: 'd3',
        x: 0,
        y: 0,
        zIndex: 2,
        faceUp: false,
        zone: CardZone.zone,
        zoneId: zoneId,
        ownerId: ownerId,
      ),
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

    test('drags along any widget attached to the moved card', () {
      final withToken = _threeCardPile().copyWith(
        widgets: [
          BoardWidgetInstance(
            instanceId: 'w1',
            kind: BoardWidgetKind.token,
            x: 0,
            y: 0,
            zIndex: 0,
            attachedCardId: 'a',
          ),
        ],
      );
      final next = _actions.moveCard(
        withToken,
        instanceId: 'a',
        x: 0.7,
        y: 0.8,
      );
      final token = next.widgets.single;
      expect(token.x, 0.7);
      expect(token.y, 0.8);
      expect(token.attachedCardId, 'a');
    });

    test(
      'preserves a nonzero attach offset -- doesn\'t re-center onto the card',
      () {
        final withToken = _threeCardPile().copyWith(
          widgets: [
            BoardWidgetInstance(
              instanceId: 'w1',
              kind: BoardWidgetKind.token,
              x: 0,
              y: 0,
              zIndex: 0,
              attachedCardId: 'a',
              attachOffsetX: 0.02,
              attachOffsetY: -0.03,
            ),
          ],
        );
        final next = _actions.moveCard(
          withToken,
          instanceId: 'a',
          x: 0.7,
          y: 0.8,
        );
        final token = next.widgets.single;
        expect(token.x, closeTo(0.72, 1e-9));
        expect(token.y, closeTo(0.77, 1e-9));
      },
    );

    test('clears ownerId for an unownable card even if it previously had a real owner', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(
            instanceId: 'u1',
            definitionId: 'd1',
            x: 0,
            y: 0,
            zIndex: 0,
            faceUp: false,
            zone: CardZone.hand,
            ownerId: 'p1',
            unownable: true,
          ),
        ],
        revision: 0,
      );
      final next = _actions.moveCard(state, instanceId: 'u1', x: 0.4, y: 0.5);
      final moved = next.cards.single;
      expect(moved.ownerId, isNull);
      expect(moved.zone, CardZone.table);
    });

    test('preserves ownerId when the card is not unownable', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(
            instanceId: 'o1',
            definitionId: 'd1',
            x: 0,
            y: 0,
            zIndex: 0,
            faceUp: false,
            zone: CardZone.hand,
            ownerId: 'p1',
          ),
        ],
        revision: 0,
      );
      final next = _actions.moveCard(state, instanceId: 'o1', x: 0.4, y: 0.5);
      expect(next.cards.single.ownerId, 'p1');
    });
  });

  group('moveStack', () {
    test(
      'repositions every card in the stack, keeping zone/stackParentId intact',
      () {
        final state = _threeCardPile();
        final next = _actions.moveStack(
          state,
          rootInstanceId: 'root',
          x: 0.3,
          y: 0.4,
        );
        for (final id in ['root', 'a', 'b']) {
          final c = next.cards.firstWhere((c) => c.instanceId == id);
          expect(c.x, 0.3);
          expect(c.y, 0.4);
          expect(c.zone, CardZone.table);
        }
        final before = {
          for (final c in state.cards) c.instanceId: c.stackParentId,
        };
        final after = {
          for (final c in next.cards) c.instanceId: c.stackParentId,
        };
        expect(after, before);
        expect(next.revision, state.revision + 1);
      },
    );

    test('bumps only the current top-of-stack member to the new running-max zIndex', () {
      // 'b' (zIndex 2) is already the stack's top -- moving the stack should
      // push it even higher (to 3, the new global max) while leaving 'root'
      // and 'a' exactly where they were, so the pile's own internal draw
      // order is unaffected but its cross-pile rank moves to the front.
      final state = _threeCardPile();
      final next = _actions.moveStack(
        state,
        rootInstanceId: 'root',
        x: 0.3,
        y: 0.4,
      );
      expect(next.cards.firstWhere((c) => c.instanceId == 'root').zIndex, 0);
      expect(next.cards.firstWhere((c) => c.instanceId == 'a').zIndex, 1);
      expect(next.cards.firstWhere((c) => c.instanceId == 'b').zIndex, 3);
    });

    test('is a no-op for an unknown root', () {
      final state = _threeCardPile();
      final next = _actions.moveStack(
        state,
        rootInstanceId: 'nonexistent',
        x: 0.3,
        y: 0.4,
      );
      expect(next, same(state));
    });

    test('drags along any widget attached to a member of the stack', () {
      final withToken = _threeCardPile().copyWith(
        widgets: [
          BoardWidgetInstance(
            instanceId: 'w1',
            kind: BoardWidgetKind.token,
            x: 0,
            y: 0,
            zIndex: 0,
            attachedCardId: 'b',
          ),
        ],
      );
      final next = _actions.moveStack(
        withToken,
        rootInstanceId: 'root',
        x: 0.3,
        y: 0.4,
      );
      final token = next.widgets.single;
      expect(token.x, 0.3);
      expect(token.y, 0.4);
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
          CardInstance(
            instanceId: 'primary',
            definitionId: 'd1',
            x: 0.1,
            y: 0.1,
            zIndex: 0,
            faceUp: false,
            zone: CardZone.table,
          ),
          CardInstance(
            instanceId: 'passenger',
            definitionId: 'd2',
            x: 0.3,
            y: 0.1,
            zIndex: 1,
            faceUp: false,
            zone: CardZone.table,
          ),
          CardInstance(
            instanceId: 'pRoot',
            definitionId: 'd3',
            x: 0.5,
            y: 0.1,
            zIndex: 2,
            faceUp: false,
            zone: CardZone.table,
          ),
          CardInstance(
            instanceId: 'pTop',
            definitionId: 'd4',
            x: 0.5,
            y: 0.1,
            zIndex: 3,
            faceUp: false,
            zone: CardZone.table,
            stackParentId: 'pRoot',
          ),
          CardInstance(
            instanceId: 'untouched',
            definitionId: 'd5',
            x: 0.9,
            y: 0.9,
            zIndex: 4,
            faceUp: false,
            zone: CardZone.table,
          ),
        ],
        revision: 0,
      );
    }

    test(
      'moves the primary card to the target position and fully detaches it',
      () {
        final state = _threeCardPile();
        final next = _actions.moveGroup(
          state,
          primaryInstanceId: 'a',
          passengerRootInstanceIds: const [],
          x: 0.7,
          y: 0.8,
        );
        final moved = next.cards.firstWhere((c) => c.instanceId == 'a');
        expect(moved.x, 0.7);
        expect(moved.y, 0.8);
        expect(moved.zone, CardZone.table);
        expect(moved.stackParentId, isNull);
      },
    );

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
      final passenger = next.cards.firstWhere(
        (c) => c.instanceId == 'passenger',
      );
      expect(passenger.x, closeTo(0.35, 1e-9));
      expect(passenger.y, closeTo(0.25, 1e-9));
      final untouched = next.cards.firstWhere(
        (c) => c.instanceId == 'untouched',
      );
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
      final primaryZ = next.cards
          .firstWhere((c) => c.instanceId == 'primary')
          .zIndex;
      final passengerZ = next.cards
          .firstWhere((c) => c.instanceId == 'passenger')
          .zIndex;
      final pRootZ = next.cards
          .firstWhere((c) => c.instanceId == 'pRoot')
          .zIndex;
      final pTopZ = next.cards.firstWhere((c) => c.instanceId == 'pTop').zIndex;
      // Ascending, in the order passed in (primary first, then each
      // passenger root in list order) and all above the pre-move max (4).
      expect(primaryZ, greaterThan(4));
      expect(passengerZ, greaterThan(primaryZ));
      expect(pTopZ, greaterThan(passengerZ));
      // Only pTop (the pile's own current top) is bumped -- pRoot keeps its
      // original zIndex, matching moveStack's minimal-touch behavior.
      expect(pRootZ, 2);
      final untouchedZ = next.cards
          .firstWhere((c) => c.instanceId == 'untouched')
          .zIndex;
      expect(untouchedZ, 4);
    });

    test('is a no-op for an unknown primary', () {
      final state = twoLooseCardsAndAPile();
      final next = _actions.moveGroup(
        state,
        primaryInstanceId: 'nonexistent',
        passengerRootInstanceIds: const [],
        x: 0,
        y: 0,
      );
      expect(next, same(state));
    });

    test('drags along a widget attached to a passenger card, following its translated position', () {
      final withToken = twoLooseCardsAndAPile().copyWith(
        widgets: [
          BoardWidgetInstance(
            instanceId: 'w1',
            kind: BoardWidgetKind.token,
            x: 0,
            y: 0,
            zIndex: 0,
            attachedCardId: 'passenger',
          ),
        ],
      );
      final next = _actions.moveGroup(
        withToken,
        primaryInstanceId: 'primary',
        passengerRootInstanceIds: const ['passenger', 'pRoot'],
        x: 0.15,
        y: 0.25,
      );
      final passenger = next.cards.firstWhere(
        (c) => c.instanceId == 'passenger',
      );
      final token = next.widgets.single;
      expect(token.x, passenger.x);
      expect(token.y, passenger.y);
    });

    test('clears ownerId for an unownable primary card, but never touches passengers\' ownership', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(
            instanceId: 'primary',
            definitionId: 'd1',
            x: 0.1,
            y: 0.1,
            zIndex: 0,
            faceUp: false,
            zone: CardZone.table,
            ownerId: 'p1',
            unownable: true,
          ),
          CardInstance(
            instanceId: 'passenger',
            definitionId: 'd2',
            x: 0.2,
            y: 0.1,
            zIndex: 1,
            faceUp: false,
            zone: CardZone.table,
            ownerId: 'p2',
          ),
        ],
        revision: 0,
      );
      final next = _actions.moveGroup(
        state,
        primaryInstanceId: 'primary',
        passengerRootInstanceIds: const ['passenger'],
        x: 0.15,
        y: 0.25,
      );
      expect(next.cards.firstWhere((c) => c.instanceId == 'primary').ownerId, isNull);
      expect(next.cards.firstWhere((c) => c.instanceId == 'passenger').ownerId, 'p2');
    });
  });

  group('rotateStack', () {
    test(
      'a lone card (a stack of one) rotates clockwise past 3 without '
      'wrapping back to 0 (so it keeps spinning the same direction)',
      () {
        final state = TableState(
          gameId: 'g',
          players: const [],
          cards: [
            CardInstance(
              instanceId: 'solo',
              definitionId: 'd1',
              x: 0,
              y: 0,
              zIndex: 0,
              faceUp: false,
              zone: CardZone.table,
              rotationTurns: 3,
            ),
          ],
          revision: 0,
        );
        final next = _actions.rotateStack(
          state,
          rootInstanceId: 'solo',
          clockwise: true,
        );
        expect(next.cards.single.rotationTurns, 4);
      },
    );

    test(
      'counter-clockwise from 0 goes negative without wrapping to 3 (so it '
      'keeps spinning the same direction)',
      () {
        final state = TableState(
          gameId: 'g',
          players: const [],
          cards: [
            CardInstance(
              instanceId: 'solo',
              definitionId: 'd1',
              x: 0,
              y: 0,
              zIndex: 0,
              faceUp: false,
              zone: CardZone.table,
            ),
          ],
          revision: 0,
        );
        final next = _actions.rotateStack(
          state,
          rootInstanceId: 'solo',
          clockwise: false,
        );
        expect(next.cards.single.rotationTurns, -1);
      },
    );

    test('rotates every card in a multi-card pile by the same delta', () {
      final state = _threeCardPile();
      final next = _actions.rotateStack(
        state,
        rootInstanceId: 'root',
        clockwise: true,
      );
      for (final id in ['root', 'a', 'b']) {
        expect(
          next.cards.firstWhere((c) => c.instanceId == id).rotationTurns,
          1,
        );
      }
      expect(next.revision, state.revision + 1);
    });

    test('does not rotate a card outside the requested stack', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(
            instanceId: 'a',
            definitionId: 'd1',
            x: 0,
            y: 0,
            zIndex: 0,
            faceUp: false,
            zone: CardZone.table,
          ),
          CardInstance(
            instanceId: 'b',
            definitionId: 'd2',
            x: 0,
            y: 0,
            zIndex: 1,
            faceUp: false,
            zone: CardZone.table,
          ),
        ],
        revision: 0,
      );
      final next = _actions.rotateStack(
        state,
        rootInstanceId: 'a',
        clockwise: true,
      );
      expect(
        next.cards.firstWhere((c) => c.instanceId == 'b').rotationTurns,
        0,
      );
    });

    test('is a no-op for an unknown root', () {
      final state = _threeCardPile();
      final next = _actions.rotateStack(
        state,
        rootInstanceId: 'nonexistent',
        clockwise: true,
      );
      expect(next, same(state));
    });

    test(
      'never rotates a card outside CardZone.table, even if named in the stack',
      () {
        // A zone card can't really be "in a stackParentId chain" today, but the
        // action still defensively ignores anything not on the table.
        final state = TableState(
          gameId: 'g',
          players: const [],
          cards: [
            CardInstance(
              instanceId: 'z1',
              definitionId: 'd1',
              x: 0,
              y: 0,
              zIndex: 0,
              faceUp: false,
              zone: CardZone.zone,
              zoneId: 'deck',
            ),
          ],
          revision: 0,
        );
        final next = _actions.rotateStack(
          state,
          rootInstanceId: 'z1',
          clockwise: true,
        );
        expect(next.cards.single.rotationTurns, 0);
      },
    );

    test('bumps only the current top-of-stack member to the new running-max zIndex', () {
      final state = _threeCardPile();
      final next = _actions.rotateStack(
        state,
        rootInstanceId: 'root',
        clockwise: true,
      );
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
      expect(
        flippedBack.cards.firstWhere((c) => c.instanceId == 'a').faceUp,
        isFalse,
      );
    });

    test('bumps the flipped card to the new running-max zIndex', () {
      final state = _threeCardPile();
      final next = _actions.flipCard(state, instanceId: 'a');
      expect(next.cards.firstWhere((c) => c.instanceId == 'a').zIndex, 3);
      expect(next.cards.firstWhere((c) => c.instanceId == 'root').zIndex, 0);
      expect(next.cards.firstWhere((c) => c.instanceId == 'b').zIndex, 2);
    });
  });

  group('giveCard', () {
    test('reassigns ownerId to the given player, leaving position/zone/face/stack untouched', () {
      final state = _threeCardPile();
      final next = _actions.giveCard(state, instanceId: 'a', newOwnerId: 'p2');
      final given = next.cards.firstWhere((c) => c.instanceId == 'a');
      expect(given.ownerId, 'p2');
      expect(given.zone, CardZone.table);
      expect(given.x, 0);
      expect(given.y, 0);
      expect(given.faceUp, isFalse);
      expect(given.stackParentId, 'root');
    });

    test('reassigns ownerId to null to release ownership back to unowned', () {
      final state = _threeCardPile();
      final owned = state.copyWith(
        cards: state.cards
            .map((c) => c.instanceId == 'a' ? c.copyWith(ownerId: 'p1') : c)
            .toList(),
      );
      final next = _actions.giveCard(owned, instanceId: 'a', newOwnerId: null);
      expect(next.cards.firstWhere((c) => c.instanceId == 'a').ownerId, isNull);
    });

    test('bumps zIndex and revision, and does not touch any other card', () {
      final state = _threeCardPile();
      final next = _actions.giveCard(state, instanceId: 'a', newOwnerId: 'p2');
      expect(next.revision, state.revision + 1);
      expect(next.cards.firstWhere((c) => c.instanceId == 'a').zIndex, 3);
      expect(
        next.cards.firstWhere((c) => c.instanceId == 'root'),
        same(state.cards.firstWhere((c) => c.instanceId == 'root')),
      );
      expect(
        next.cards.firstWhere((c) => c.instanceId == 'b'),
        same(state.cards.firstWhere((c) => c.instanceId == 'b')),
      );
    });

    test('always results in ownerId: null for an unownable card, regardless of the requested target', () {
      final state = _threeCardPile();
      final unownable = state.copyWith(
        cards: state.cards
            .map((c) => c.instanceId == 'a' ? c.copyWith(unownable: true) : c)
            .toList(),
      );
      final next = _actions.giveCard(unownable, instanceId: 'a', newOwnerId: 'p2');
      expect(next.cards.firstWhere((c) => c.instanceId == 'a').ownerId, isNull);
    });
  });

  group('stackCard', () {
    test('snaps position/zone and links stackParentId', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(
            instanceId: 'x',
            definitionId: 'd1',
            x: 10,
            y: 10,
            zIndex: 0,
            faceUp: false,
            zone: CardZone.table,
          ),
          CardInstance(
            instanceId: 'y',
            definitionId: 'd2',
            x: 99,
            y: 99,
            zIndex: 1,
            faceUp: false,
            zone: CardZone.table,
          ),
        ],
        revision: 0,
      );
      final next = _actions.stackCard(
        state,
        instanceId: 'y',
        ontoInstanceId: 'x',
      );
      final stacked = next.cards.firstWhere((c) => c.instanceId == 'y');
      expect(stacked.x, 10);
      expect(stacked.y, 10);
      expect(stacked.stackParentId, 'x');
    });

    test('clears ownerId for an unownable card being stacked onto the table', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(
            instanceId: 'x',
            definitionId: 'd1',
            x: 10,
            y: 10,
            zIndex: 0,
            faceUp: false,
            zone: CardZone.table,
          ),
          CardInstance(
            instanceId: 'y',
            definitionId: 'd2',
            x: 99,
            y: 99,
            zIndex: 1,
            faceUp: false,
            zone: CardZone.hand,
            ownerId: 'p1',
            unownable: true,
          ),
        ],
        revision: 0,
      );
      final next = _actions.stackCard(state, instanceId: 'y', ontoInstanceId: 'x');
      expect(next.cards.firstWhere((c) => c.instanceId == 'y').ownerId, isNull);
    });

    test('clears zoneId when stacking a zone card onto a free-table pile', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(
            instanceId: 'x',
            definitionId: 'd1',
            x: 10,
            y: 10,
            zIndex: 0,
            faceUp: false,
            zone: CardZone.table,
          ),
          CardInstance(
            instanceId: 'y',
            definitionId: 'd2',
            x: 99,
            y: 99,
            zIndex: 1,
            faceUp: false,
            zone: CardZone.zone,
            zoneId: 'discard_pile',
            ownerId: 'p1',
          ),
        ],
        revision: 0,
      );
      final next = _actions.stackCard(
        state,
        instanceId: 'y',
        ontoInstanceId: 'x',
      );
      expect(next.cards.firstWhere((c) => c.instanceId == 'y').zoneId, isNull);
    });

    test('is a no-op when stacking a card onto itself', () {
      final state = _threeCardPile();
      final next = _actions.stackCard(
        state,
        instanceId: 'a',
        ontoInstanceId: 'a',
      );
      expect(next, same(state));
    });

    test('is a no-op when the target does not exist', () {
      final state = _threeCardPile();
      final next = _actions.stackCard(
        state,
        instanceId: 'a',
        ontoInstanceId: 'nope',
      );
      expect(next, same(state));
    });

    test('drags along a widget attached to the card being stacked', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(
            instanceId: 'x',
            definitionId: 'd1',
            x: 10,
            y: 10,
            zIndex: 0,
            faceUp: false,
            zone: CardZone.table,
          ),
          CardInstance(
            instanceId: 'y',
            definitionId: 'd2',
            x: 99,
            y: 99,
            zIndex: 1,
            faceUp: false,
            zone: CardZone.table,
          ),
        ],
        revision: 0,
        widgets: [
          BoardWidgetInstance(
            instanceId: 'w1',
            kind: BoardWidgetKind.token,
            x: 99,
            y: 99,
            zIndex: 0,
            attachedCardId: 'y',
          ),
        ],
      );
      final next = _actions.stackCard(
        state,
        instanceId: 'y',
        ontoInstanceId: 'x',
      );
      final token = next.widgets.single;
      expect(token.x, 10);
      expect(token.y, 10);
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

    test(
      'resets a nonzero rotation -- a card never shows up sideways in a hand',
      () {
        final state = TableState(
          gameId: 'g',
          players: const [],
          cards: [
            CardInstance(
              instanceId: 'a',
              definitionId: 'd1',
              x: 0,
              y: 0,
              zIndex: 0,
              faceUp: false,
              zone: CardZone.table,
              rotationTurns: 2,
            ),
          ],
          revision: 0,
        );
        final next = _actions.moveToHand(state, instanceId: 'a', ownerId: 'p1');
        expect(next.cards.single.rotationTurns, 0);
      },
    );
  });

  group('reorderHand', () {
    TableState threeHandCards() {
      return TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(
            instanceId: 'h1',
            definitionId: 'd1',
            x: 0,
            y: 0,
            zIndex: 10,
            faceUp: true,
            zone: CardZone.hand,
            ownerId: 'p1',
          ),
          CardInstance(
            instanceId: 'h2',
            definitionId: 'd2',
            x: 0,
            y: 0,
            zIndex: 11,
            faceUp: true,
            zone: CardZone.hand,
            ownerId: 'p1',
          ),
          CardInstance(
            instanceId: 'h3',
            definitionId: 'd3',
            x: 0,
            y: 0,
            zIndex: 12,
            faceUp: true,
            zone: CardZone.hand,
            ownerId: 'p1',
          ),
          // Untouched control: a different owner's hand card.
          CardInstance(
            instanceId: 'other',
            definitionId: 'd4',
            x: 0,
            y: 0,
            zIndex: 20,
            faceUp: true,
            zone: CardZone.hand,
            ownerId: 'p2',
          ),
        ],
        revision: 0,
      );
    }

    List<String> displayOrder(TableState state, String ownerId) {
      final hand =
          state.cards
              .where((c) => c.zone == CardZone.hand && c.ownerId == ownerId)
              .toList()
            ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
      return hand.map((c) => c.instanceId).toList();
    }

    test('moving the last card to the front shifts the rest right', () {
      final state = threeHandCards();
      final next = _actions.reorderHand(
        state,
        instanceId: 'h3',
        ownerId: 'p1',
        targetIndex: 0,
      );
      expect(displayOrder(next, 'p1'), ['h3', 'h1', 'h2']);
      expect(next.revision, state.revision + 1);
    });

    test('moving the first card between the other two', () {
      final state = threeHandCards();
      final next = _actions.reorderHand(
        state,
        instanceId: 'h1',
        ownerId: 'p1',
        targetIndex: 1,
      );
      expect(displayOrder(next, 'p1'), ['h2', 'h1', 'h3']);
    });

    test('targetIndex past the end just appends', () {
      final state = threeHandCards();
      final next = _actions.reorderHand(
        state,
        instanceId: 'h1',
        ownerId: 'p1',
        targetIndex: 99,
      );
      expect(displayOrder(next, 'p1'), ['h2', 'h3', 'h1']);
    });

    test("does not touch another player's hand or any other card", () {
      final state = threeHandCards();
      final next = _actions.reorderHand(
        state,
        instanceId: 'h3',
        ownerId: 'p1',
        targetIndex: 0,
      );
      final other = next.cards.firstWhere((c) => c.instanceId == 'other');
      expect(other.zIndex, 20);
    });

    test('is a no-op when instanceId is not in the owner\'s hand', () {
      final state = threeHandCards();
      final next = _actions.reorderHand(
        state,
        instanceId: 'other',
        ownerId: 'p1',
        targetIndex: 0,
      );
      expect(next, same(state));
    });
  });

  group('drawCard', () {
    test('moves the top card into the given owner hand, face-up, detached', () {
      final state = _threeCardPile();
      final next = _actions.drawCard(
        state,
        pileInstanceId: 'root',
        ownerId: 'p1',
      );
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

    test(
      'the anchor card is only drawn once it is the last card in the pile',
      () {
        var state = _threeCardPile();
        state = _actions.drawCard(
          state,
          pileInstanceId: 'root',
          ownerId: 'p1',
        ); // draws 'b'
        state = _actions.drawCard(
          state,
          pileInstanceId: 'root',
          ownerId: 'p1',
        ); // draws 'a'
        // Only 'root' remains in the pile now — drawing again must draw it.
        final next = _actions.drawCard(
          state,
          pileInstanceId: 'root',
          ownerId: 'p1',
        );
        final root = next.cards.firstWhere((c) => c.instanceId == 'root');
        expect(root.zone, CardZone.hand);
        expect(root.ownerId, 'p1');
      },
    );

    test('is a no-op on an empty/nonexistent pile', () {
      final state = _threeCardPile();
      final next = _actions.drawCard(
        state,
        pileInstanceId: 'does-not-exist',
        ownerId: 'p1',
      );
      expect(next, same(state));
    });

    test(
      'resets a nonzero rotation -- a card never shows up sideways in a hand',
      () {
        final state = TableState(
          gameId: 'g',
          players: const [],
          cards: [
            CardInstance(
              instanceId: 'solo',
              definitionId: 'd1',
              x: 0,
              y: 0,
              zIndex: 0,
              faceUp: false,
              zone: CardZone.table,
              rotationTurns: 1,
            ),
          ],
          revision: 0,
        );
        final next = _actions.drawCard(
          state,
          pileInstanceId: 'solo',
          ownerId: 'p1',
        );
        expect(next.cards.single.rotationTurns, 0);
      },
    );

    test('count draws that many cards, top-first, in a single revision bump -- including the anchor once it is last', () {
      final state = _threeCardPile();
      final next = _actions.drawCard(
        state,
        pileInstanceId: 'root',
        ownerId: 'p1',
        count: 3,
      );
      expect(next.revision, state.revision + 1);
      for (final id in ['root', 'a', 'b']) {
        expect(next.cards.firstWhere((c) => c.instanceId == id).zone, CardZone.hand);
      }
      // Drawn top-first: 'b' (zIndex 2) first, then 'a', then the anchor
      // 'root' last -- each gets its own new zIndex in that order.
      final b = next.cards.firstWhere((c) => c.instanceId == 'b').zIndex;
      final a = next.cards.firstWhere((c) => c.instanceId == 'a').zIndex;
      final root = next.cards.firstWhere((c) => c.instanceId == 'root').zIndex;
      expect(b, lessThan(a));
      expect(a, lessThan(root));
    });

    test('clamps count to however many cards are actually in the pile', () {
      final state = _threeCardPile();
      final next = _actions.drawCard(
        state,
        pileInstanceId: 'root',
        ownerId: 'p1',
        count: 9,
      );
      expect(next.revision, state.revision + 1);
      expect(next.cards.every((c) => c.zone == CardZone.hand), isTrue);
    });

    test('count: 0 is a no-op', () {
      final state = _threeCardPile();
      final next = _actions.drawCard(
        state,
        pileInstanceId: 'root',
        ownerId: 'p1',
        count: 0,
      );
      expect(next, same(state));
    });
  });

  group('drawFromZone', () {
    test('moves the top card of the zone into the given owner hand, face-up, detached', () {
      final state = _threeCardZone(zoneId: 'draw_deck', ownerId: 'p1');
      final next = _actions.drawFromZone(
        state,
        zoneId: 'draw_deck',
        zoneOwnerId: 'p1',
        toOwnerId: 'p1',
      );
      // Highest zIndex in the zone is 'z3'.
      final drawn = next.cards.firstWhere((c) => c.instanceId == 'z3');
      expect(drawn.zone, CardZone.hand);
      expect(drawn.ownerId, 'p1');
      expect(drawn.faceUp, isTrue);
      expect(drawn.zoneId, isNull);
    });

    test('a shared zone (null owner) is drawable by anyone', () {
      final state = _threeCardZone(zoneId: 'deck');
      final next = _actions.drawFromZone(
        state,
        zoneId: 'deck',
        zoneOwnerId: null,
        toOwnerId: 'p2',
      );
      final drawn = next.cards.firstWhere((c) => c.instanceId == 'z3');
      expect(drawn.zone, CardZone.hand);
      expect(drawn.ownerId, 'p2');
    });

    test('is a no-op on an empty/nonexistent zone', () {
      final state = _threeCardZone(zoneId: 'draw_deck', ownerId: 'p1');
      final next = _actions.drawFromZone(
        state,
        zoneId: 'discard_pile',
        zoneOwnerId: 'p1',
        toOwnerId: 'p1',
      );
      expect(next, same(state));
    });

    test(
      'resets a nonzero rotation -- a card never shows up sideways in a hand',
      () {
        final state = TableState(
          gameId: 'g',
          players: const [],
          cards: [
            CardInstance(
              instanceId: 'z1',
              definitionId: 'd1',
              x: 0,
              y: 0,
              zIndex: 0,
              faceUp: false,
              zone: CardZone.zone,
              zoneId: 'draw_deck',
              ownerId: 'p1',
              rotationTurns: 2,
            ),
          ],
          revision: 0,
        );
        final next = _actions.drawFromZone(
          state,
          zoneId: 'draw_deck',
          zoneOwnerId: 'p1',
          toOwnerId: 'p1',
        );
        expect(next.cards.single.rotationTurns, 0);
      },
    );

    test('count draws that many cards, top-first, in a single revision bump', () {
      final state = _threeCardZone(zoneId: 'draw_deck', ownerId: 'p1');
      final next = _actions.drawFromZone(
        state,
        zoneId: 'draw_deck',
        zoneOwnerId: 'p1',
        toOwnerId: 'p1',
        count: 2,
      );
      expect(next.revision, state.revision + 1);
      // Top-first: 'z3' (zIndex 2) then 'z2' (zIndex 1); 'z1' stays put.
      expect(next.cards.firstWhere((c) => c.instanceId == 'z3').zone, CardZone.hand);
      expect(next.cards.firstWhere((c) => c.instanceId == 'z2').zone, CardZone.hand);
      expect(next.cards.firstWhere((c) => c.instanceId == 'z1').zone, CardZone.zone);
      final z3 = next.cards.firstWhere((c) => c.instanceId == 'z3').zIndex;
      final z2 = next.cards.firstWhere((c) => c.instanceId == 'z2').zIndex;
      expect(z3, lessThan(z2));
    });

    test('clamps count to however many cards are actually in the zone', () {
      final state = _threeCardZone(zoneId: 'draw_deck', ownerId: 'p1');
      final next = _actions.drawFromZone(
        state,
        zoneId: 'draw_deck',
        zoneOwnerId: 'p1',
        toOwnerId: 'p1',
        count: 9,
      );
      expect(next.revision, state.revision + 1);
      expect(next.cards.every((c) => c.zone == CardZone.hand), isTrue);
    });

    test('count: 0 is a no-op', () {
      final state = _threeCardZone(zoneId: 'draw_deck', ownerId: 'p1');
      final next = _actions.drawFromZone(
        state,
        zoneId: 'draw_deck',
        zoneOwnerId: 'p1',
        toOwnerId: 'p1',
        count: 0,
      );
      expect(next, same(state));
    });
  });

  group('returnToZone', () {
    test('places the card on top (drawn next) by default, face-down, owned by the zone', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(
            instanceId: 'z1',
            definitionId: 'd1',
            x: 0,
            y: 0,
            zIndex: 0,
            faceUp: false,
            zone: CardZone.zone,
            zoneId: 'draw_deck',
            ownerId: 'p1',
          ),
          CardInstance(
            instanceId: 'inHand',
            definitionId: 'd2',
            x: 0,
            y: 0,
            zIndex: 5,
            faceUp: true,
            zone: CardZone.hand,
            ownerId: 'p1',
          ),
        ],
        revision: 0,
      );
      final next = _actions.returnToZone(
        state,
        instanceId: 'inHand',
        zoneId: 'draw_deck',
        zoneOwnerId: 'p1',
        faceUp: false,
      );
      final returned = next.cards.firstWhere((c) => c.instanceId == 'inHand');
      expect(returned.zone, CardZone.zone);
      expect(returned.zoneId, 'draw_deck');
      expect(returned.ownerId, 'p1');
      expect(returned.faceUp, isFalse);

      // Drawing next should immediately return this exact card -- it's on top.
      final drawn = _actions.drawFromZone(
        next,
        zoneId: 'draw_deck',
        zoneOwnerId: 'p1',
        toOwnerId: 'p1',
      );
      expect(
        drawn.cards.firstWhere((c) => c.instanceId == 'inHand').zone,
        CardZone.hand,
      );
    });

    test('a shared zone stays unowned even if a player id is passed as zoneOwnerId', () {
      final state = _threeCardZone(zoneId: 'deck');
      final inHand = CardInstance(
        instanceId: 'inHand',
        definitionId: 'd2',
        x: 0,
        y: 0,
        zIndex: 5,
        faceUp: true,
        zone: CardZone.hand,
        ownerId: 'p1',
      );
      final withHandCard = state.copyWith(cards: [...state.cards, inHand]);
      final next = _actions.returnToZone(
        withHandCard,
        instanceId: 'inHand',
        zoneId: 'deck',
        zoneOwnerId: null,
        faceUp: false,
      );
      expect(
        next.cards.firstWhere((c) => c.instanceId == 'inHand').ownerId,
        isNull,
      );
    });

    test('sets faceUp according to the faceUp argument -- true for a discard-pile-style zone', () {
      final state = _threeCardZone(zoneId: 'discard_pile', ownerId: 'p1');
      final inHand = CardInstance(
        instanceId: 'inHand',
        definitionId: 'd2',
        x: 0,
        y: 0,
        zIndex: 5,
        faceUp: false,
        zone: CardZone.hand,
        ownerId: 'p1',
      );
      final withHandCard = state.copyWith(cards: [...state.cards, inHand]);
      final next = _actions.returnToZone(
        withHandCard,
        instanceId: 'inHand',
        zoneId: 'discard_pile',
        zoneOwnerId: 'p1',
        faceUp: true,
      );
      expect(
        next.cards.firstWhere((c) => c.instanceId == 'inHand').faceUp,
        isTrue,
      );
    });

    test('snaps to the position an existing zone card already shares', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(
            instanceId: 'z1',
            definitionId: 'd1',
            x: 0.8,
            y: 0.5,
            zIndex: 0,
            faceUp: false,
            zone: CardZone.zone,
            zoneId: 'deck',
          ),
          CardInstance(
            instanceId: 'onTable',
            definitionId: 'd2',
            x: 0.1,
            y: 0.1,
            zIndex: 5,
            faceUp: true,
            zone: CardZone.table,
          ),
        ],
        revision: 0,
      );
      final next = _actions.returnToZone(
        state,
        instanceId: 'onTable',
        zoneId: 'deck',
        zoneOwnerId: null,
        faceUp: false,
      );
      final returned = next.cards.firstWhere((c) => c.instanceId == 'onTable');
      expect(returned.x, 0.8);
      expect(returned.y, 0.5);
    });

    test('an empty zone keeps the returned card at its own current x/y', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(
            instanceId: 'onTable',
            definitionId: 'd2',
            x: 0.1,
            y: 0.2,
            zIndex: 5,
            faceUp: true,
            zone: CardZone.table,
          ),
        ],
        revision: 0,
      );
      final next = _actions.returnToZone(
        state,
        instanceId: 'onTable',
        zoneId: 'discard_pile',
        zoneOwnerId: 'p1',
        faceUp: false,
      );
      final returned = next.cards.firstWhere((c) => c.instanceId == 'onTable');
      expect(returned.x, 0.1);
      expect(returned.y, 0.2);
      expect(returned.zone, CardZone.zone);
      expect(returned.zoneId, 'discard_pile');
    });

    test('toBottom places the card below every other card in the zone', () {
      final state = _threeCardZone(zoneId: 'draw_deck', ownerId: 'p1');
      final inHand = CardInstance(
        instanceId: 'inHand',
        definitionId: 'd2',
        x: 0,
        y: 0,
        zIndex: 5,
        faceUp: true,
        zone: CardZone.hand,
        ownerId: 'p1',
      );
      final withHandCard = state.copyWith(cards: [...state.cards, inHand]);
      final next = _actions.returnToZone(
        withHandCard,
        instanceId: 'inHand',
        zoneId: 'draw_deck',
        zoneOwnerId: 'p1',
        faceUp: false,
        toBottom: true,
      );
      final returned = next.cards.firstWhere((c) => c.instanceId == 'inHand');
      final others = next.cards.where(
        (c) => c.instanceId != 'inHand' && c.zoneId == 'draw_deck',
      );
      expect(
        returned.zIndex,
        lessThan(others.map((c) => c.zIndex).reduce((x, y) => x < y ? x : y)),
      );
    });

    test('is a no-op when the card is already in that exact zone', () {
      final state = _threeCardZone(zoneId: 'draw_deck', ownerId: 'p1');
      final next = _actions.returnToZone(
        state,
        instanceId: 'z1',
        zoneId: 'draw_deck',
        zoneOwnerId: 'p1',
        faceUp: false,
      );
      expect(next, same(state));
    });

    test(
      'resets a nonzero rotation -- a card never shows up sideways in a deck',
      () {
        final state = TableState(
          gameId: 'g',
          players: const [],
          cards: [
            CardInstance(
              instanceId: 'onTable',
              definitionId: 'd1',
              x: 0,
              y: 0,
              zIndex: 0,
              faceUp: false,
              zone: CardZone.table,
              rotationTurns: 1,
            ),
          ],
          revision: 0,
        );
        final next = _actions.returnToZone(
          state,
          instanceId: 'onTable',
          zoneId: 'draw_deck',
          zoneOwnerId: 'p1',
          faceUp: false,
        );
        expect(next.cards.single.rotationTurns, 0);
      },
    );
  });

  group('shuffleZone', () {
    test('flips every card in the zone face-down and reassigns zIndex without changing membership', () {
      final state = _threeCardZone(zoneId: 'draw_deck', ownerId: 'p1');
      final next = _actions.shuffleZone(
        state,
        zoneId: 'draw_deck',
        zoneOwnerId: 'p1',
        seed: 42,
      );
      expect(
        next.cards.map((c) => c.instanceId).toSet(),
        state.cards.map((c) => c.instanceId).toSet(),
      );
      for (final c in next.cards) {
        expect(c.faceUp, isFalse);
      }
      expect(
        next.cards.map((c) => c.zIndex).toSet(),
        hasLength(next.cards.length),
      );
    });

    test('is a no-op for a zone of 1 or fewer cards', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(
            instanceId: 'solo',
            definitionId: 'd1',
            x: 0,
            y: 0,
            zIndex: 0,
            faceUp: true,
            zone: CardZone.zone,
            zoneId: 'draw_deck',
            ownerId: 'p1',
          ),
        ],
        revision: 0,
      );
      final next = _actions.shuffleZone(
        state,
        zoneId: 'draw_deck',
        zoneOwnerId: 'p1',
      );
      expect(next, same(state));
    });
  });

  group('shufflePile', () {
    test('flips every card in the stack face-down and reassigns zIndex without changing membership', () {
      final state = _threeCardPile();
      final next = _actions.shufflePile(
        state,
        pileRootInstanceId: 'root',
        seed: 42,
      );
      expect(
        next.cards.map((c) => c.instanceId).toSet(),
        state.cards.map((c) => c.instanceId).toSet(),
      );
      for (final c in next.cards) {
        expect(c.faceUp, isFalse);
      }
      // zIndex values must still be distinct after shuffling.
      expect(
        next.cards.map((c) => c.zIndex).toSet(),
        hasLength(next.cards.length),
      );
    });

    test('is a no-op for a stack of 1 or fewer cards', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(
            instanceId: 'solo',
            definitionId: 'd1',
            x: 0,
            y: 0,
            zIndex: 0,
            faceUp: true,
            zone: CardZone.table,
          ),
        ],
        revision: 0,
      );
      final next = _actions.shufflePile(state, pileRootInstanceId: 'solo');
      expect(next, same(state));
    });
  });

  group('startSearch/stopSearch', () {
    test('startSearch adds an entry and bumps revision', () {
      final state = _threeCardZone(zoneId: 'draw_deck', ownerId: 'p1');
      final next = _actions.startSearch(
        state,
        searcherId: 'p1',
        targetType: SearchTargetType.zone,
        targetId: 'draw_deck',
        targetOwnerId: 'p1',
      );
      expect(next.searches, hasLength(1));
      expect(next.searches.single.searcherId, 'p1');
      expect(next.searches.single.targetType, SearchTargetType.zone);
      expect(next.searches.single.targetId, 'draw_deck');
      expect(next.searches.single.targetOwnerId, 'p1');
      expect(next.revision, state.revision + 1);
    });

    test('startSearch replaces a searcher\'s existing entry rather than adding a second one', () {
      final state = _threeCardZone(zoneId: 'draw_deck', ownerId: 'p1');
      final first = _actions.startSearch(
        state,
        searcherId: 'p1',
        targetType: SearchTargetType.zone,
        targetId: 'draw_deck',
        targetOwnerId: 'p1',
      );
      final second = _actions.startSearch(
        first,
        searcherId: 'p1',
        targetType: SearchTargetType.pile,
        targetId: 'root',
      );
      expect(second.searches, hasLength(1));
      expect(second.searches.single.targetType, SearchTargetType.pile);
      expect(second.searches.single.targetId, 'root');
    });

    test('startSearch leaves other searchers\' entries alone', () {
      final state = _threeCardZone(zoneId: 'draw_deck', ownerId: 'p1');
      final withP1 = _actions.startSearch(
        state,
        searcherId: 'p1',
        targetType: SearchTargetType.zone,
        targetId: 'draw_deck',
        targetOwnerId: 'p1',
      );
      final withBoth = _actions.startSearch(
        withP1,
        searcherId: 'p2',
        targetType: SearchTargetType.zone,
        targetId: 'draw_deck',
        targetOwnerId: 'p2',
      );
      expect(withBoth.searches, hasLength(2));
      expect(withBoth.searches.map((s) => s.searcherId), ['p1', 'p2']);
    });

    test('stopSearch removes that searcher\'s entry and bumps revision', () {
      final state = _threeCardZone(zoneId: 'draw_deck', ownerId: 'p1');
      final opened = _actions.startSearch(
        state,
        searcherId: 'p1',
        targetType: SearchTargetType.zone,
        targetId: 'draw_deck',
        targetOwnerId: 'p1',
      );
      final closed = _actions.stopSearch(opened, searcherId: 'p1');
      expect(closed.searches, isEmpty);
      expect(closed.revision, opened.revision + 1);
    });

    test('stopSearch is a no-op when that searcher has no active search', () {
      final state = _threeCardZone(zoneId: 'draw_deck', ownerId: 'p1');
      final next = _actions.stopSearch(state, searcherId: 'p1');
      expect(next, same(state));
    });
  });

  group('createWidget', () {
    test('adds a widget at the given position with an ascending zIndex, bumping revision', () {
      const state = TableState(
        gameId: 'g',
        players: [],
        cards: [],
        revision: 0,
      );
      final next = _actions.createWidget(
        state,
        instanceId: 'w1',
        kind: BoardWidgetKind.simpleCounter,
        x: 0.2,
        y: 0.3,
      );
      expect(next.widgets, hasLength(1));
      final w = next.widgets.single;
      expect(w.instanceId, 'w1');
      expect(w.kind, BoardWidgetKind.simpleCounter);
      expect(w.x, 0.2);
      expect(w.y, 0.3);
      expect(w.value, 0);
      expect(next.revision, state.revision + 1);

      final withSecond = _actions.createWidget(
        next,
        instanceId: 'w2',
        kind: BoardWidgetKind.simpleCounter,
        x: 0.5,
        y: 0.5,
      );
      expect(
        withSecond.widgets.firstWhere((w) => w.instanceId == 'w2').zIndex,
        greaterThan(w.zIndex),
      );
    });
  });

  group('createArrow', () {
    test('adds an arrow widget with both endpoints and a creator, bumping revision', () {
      const state = TableState(
        gameId: 'g',
        players: [],
        cards: [],
        revision: 0,
      );
      final next = _actions.createArrow(
        state,
        instanceId: 'a1',
        x: 0.1,
        y: 0.2,
        x2: 0.6,
        y2: 0.7,
        creatorId: 'p1',
      );
      expect(next.widgets, hasLength(1));
      final a = next.widgets.single;
      expect(a.instanceId, 'a1');
      expect(a.kind, BoardWidgetKind.arrow);
      expect(a.x, 0.1);
      expect(a.y, 0.2);
      expect(a.x2, 0.6);
      expect(a.y2, 0.7);
      expect(a.creatorId, 'p1');
      expect(next.revision, state.revision + 1);
    });

    test('stacks its zIndex above any existing widget', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: const [],
        revision: 0,
        widgets: [
          BoardWidgetInstance(
            instanceId: 'w1',
            kind: BoardWidgetKind.simpleCounter,
            x: 0,
            y: 0,
            zIndex: 5,
          ),
        ],
      );
      final next = _actions.createArrow(
        state,
        instanceId: 'a1',
        x: 0,
        y: 0,
        x2: 1,
        y2: 1,
        creatorId: 'p1',
      );
      final arrow = next.widgets.firstWhere((w) => w.instanceId == 'a1');
      expect(arrow.zIndex, greaterThan(5));
    });
  });

  group('deleteWidget with an arrow', () {
    test(
      'removes it like any other widget kind -- deletion stays kind-agnostic',
      () {
        final state = TableState(
          gameId: 'g',
          players: const [],
          cards: const [],
          revision: 0,
          widgets: [
            BoardWidgetInstance(
              instanceId: 'a1',
              kind: BoardWidgetKind.arrow,
              x: 0,
              y: 0,
              x2: 1,
              y2: 1,
              zIndex: 0,
              creatorId: 'p1',
            ),
          ],
        );
        final next = _actions.deleteWidget(state, instanceId: 'a1');
        expect(next.widgets, isEmpty);
        expect(next.revision, state.revision + 1);
      },
    );
  });

  group('moveWidget', () {
    test('updates position and bumps revision', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: const [],
        revision: 0,
        widgets: [
          BoardWidgetInstance(
            instanceId: 'w1',
            kind: BoardWidgetKind.simpleCounter,
            x: 0,
            y: 0,
            zIndex: 0,
          ),
        ],
      );
      final next = _actions.moveWidget(state, instanceId: 'w1', x: 0.7, y: 0.8);
      final moved = next.widgets.single;
      expect(moved.x, 0.7);
      expect(moved.y, 0.8);
      expect(next.revision, state.revision + 1);
    });

    test('is a no-op (aside from revision) for an unknown id', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: const [],
        revision: 0,
        widgets: [
          BoardWidgetInstance(
            instanceId: 'w1',
            kind: BoardWidgetKind.simpleCounter,
            x: 0,
            y: 0,
            zIndex: 0,
          ),
        ],
      );
      final next = _actions.moveWidget(
        state,
        instanceId: 'nonexistent',
        x: 0.7,
        y: 0.8,
      );
      expect(next.widgets.single.x, 0);
      expect(next.widgets.single.y, 0);
    });

    test(
      'clears attachedCardId -- dragging the widget itself always detaches it',
      () {
        final state = TableState(
          gameId: 'g',
          players: const [],
          cards: const [],
          revision: 0,
          widgets: [
            BoardWidgetInstance(
              instanceId: 'w1',
              kind: BoardWidgetKind.token,
              x: 0,
              y: 0,
              zIndex: 0,
              attachedCardId: 'c1',
            ),
          ],
        );
        final next = _actions.moveWidget(
          state,
          instanceId: 'w1',
          x: 0.7,
          y: 0.8,
        );
        expect(next.widgets.single.attachedCardId, isNull);
      },
    );
  });

  group('attachWidgetToCard', () {
    test('leaves the widget exactly at the drop point (not snapped to the card center) and records the offset', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: [
          CardInstance(
            instanceId: 'c1',
            definitionId: 'd1',
            x: 0.4,
            y: 0.5,
            zIndex: 0,
            faceUp: true,
            zone: CardZone.table,
          ),
        ],
        revision: 0,
        widgets: [
          BoardWidgetInstance(
            instanceId: 'w1',
            kind: BoardWidgetKind.token,
            x: 0,
            y: 0,
            zIndex: 0,
          ),
        ],
      );
      final next = _actions.attachWidgetToCard(
        state,
        instanceId: 'w1',
        cardId: 'c1',
        x: 0.42,
        y: 0.53,
      );
      final token = next.widgets.single;
      expect(token.x, closeTo(0.42, 1e-9));
      expect(token.y, closeTo(0.53, 1e-9));
      expect(token.attachedCardId, 'c1');
      expect(token.attachOffsetX, closeTo(0.02, 1e-9));
      expect(token.attachOffsetY, closeTo(0.03, 1e-9));
      expect(next.revision, state.revision + 1);
    });

    test('is a no-op for an unknown card id', () {
      const state = TableState(
        gameId: 'g',
        players: [],
        cards: [],
        revision: 0,
      );
      final next = _actions.attachWidgetToCard(
        state,
        instanceId: 'w1',
        cardId: 'nonexistent',
        x: 0.5,
        y: 0.5,
      );
      expect(next, same(state));
    });
  });

  group('setWidgetValue', () {
    TableState state() => TableState(
      gameId: 'g',
      players: const [],
      cards: const [],
      revision: 0,
      widgets: [
        BoardWidgetInstance(
          instanceId: 'w1',
          kind: BoardWidgetKind.simpleCounter,
          x: 0,
          y: 0,
          zIndex: 0,
        ),
      ],
    );

    test('sets an in-range absolute value', () {
      final next = _actions.setWidgetValue(
        state(),
        instanceId: 'w1',
        value: 42,
      );
      expect(next.widgets.single.value, 42);
      expect(next.revision, 1);
    });

    test('clamps a negative value to boardWidgetCounterMin', () {
      final next = _actions.setWidgetValue(
        state(),
        instanceId: 'w1',
        value: -10,
      );
      expect(next.widgets.single.value, boardWidgetCounterMin);
    });

    test('clamps a value above boardWidgetCounterMax', () {
      final next = _actions.setWidgetValue(
        state(),
        instanceId: 'w1',
        value: 500000,
      );
      expect(next.widgets.single.value, boardWidgetCounterMax);
    });
  });

  group('deleteWidget', () {
    test('removes the widget', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: const [],
        revision: 0,
        widgets: [
          BoardWidgetInstance(
            instanceId: 'w1',
            kind: BoardWidgetKind.simpleCounter,
            x: 0,
            y: 0,
            zIndex: 0,
          ),
        ],
      );
      final next = _actions.deleteWidget(state, instanceId: 'w1');
      expect(next.widgets, isEmpty);
      expect(next.revision, state.revision + 1);
    });

    test('no-ops on an unknown id', () {
      const state = TableState(
        gameId: 'g',
        players: [],
        cards: [],
        revision: 0,
      );
      final next = _actions.deleteWidget(state, instanceId: 'nonexistent');
      expect(next.widgets, isEmpty);
    });
  });

  group('setWidgetColors', () {
    test('sets both colors and bumps revision', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: const [],
        revision: 0,
        widgets: [
          BoardWidgetInstance(
            instanceId: 'w1',
            kind: BoardWidgetKind.simpleCounter,
            x: 0,
            y: 0,
            zIndex: 0,
          ),
        ],
      );
      final next = _actions.setWidgetColors(
        state,
        instanceId: 'w1',
        backgroundColor: 0xFFD32F2F,
        textColor: 0xFF000000,
      );
      final w = next.widgets.single;
      expect(w.backgroundColor, 0xFFD32F2F);
      expect(w.textColor, 0xFF000000);
      expect(next.revision, state.revision + 1);
    });
  });

  group('duplicateWidget', () {
    test('creates a copy of the source at the given position, on top, with a new id', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: const [],
        revision: 0,
        widgets: [
          BoardWidgetInstance(
            instanceId: 'w1',
            kind: BoardWidgetKind.token,
            x: 0.1,
            y: 0.1,
            zIndex: 0,
            backgroundColor: 0xFFD32F2F,
            textColor: 0xFF000000,
          ),
        ],
      );
      final next = _actions.duplicateWidget(
        state,
        sourceInstanceId: 'w1',
        newInstanceId: 'w2',
        x: 0.5,
        y: 0.6,
      );
      expect(next.widgets, hasLength(2));
      final copy = next.widgets.firstWhere((w) => w.instanceId == 'w2');
      expect(copy.kind, BoardWidgetKind.token);
      expect(copy.x, 0.5);
      expect(copy.y, 0.6);
      expect(copy.backgroundColor, 0xFFD32F2F);
      expect(copy.textColor, 0xFF000000);
      final source = next.widgets.firstWhere((w) => w.instanceId == 'w1');
      expect(source.x, 0.1);
      expect(source.y, 0.1);
      expect(next.revision, state.revision + 1);
    });

    test('is a no-op for an unknown source id', () {
      const state = TableState(
        gameId: 'g',
        players: [],
        cards: [],
        revision: 0,
      );
      final next = _actions.duplicateWidget(
        state,
        sourceInstanceId: 'nonexistent',
        newInstanceId: 'w2',
        x: 0.5,
        y: 0.5,
      );
      expect(next, same(state));
    });
  });

  group('dealNewCards', () {
    CardInstance newCard(String id) => CardInstance(
      instanceId: id,
      definitionId: 'd1',
      x: 0.5,
      y: 0.5,
      zIndex: 0,
      faceUp: true,
      zone: CardZone.hand,
      ownerId: 'p1',
    );

    test('appends the given cards with ascending zIndex above the current max', () {
      final state = _threeCardPile(); // existing zIndexes 0, 1, 2
      final next = _actions.dealNewCards(state, newCards: [newCard('n1'), newCard('n2')]);
      expect(next.cards.length, state.cards.length + 2);
      final n1 = next.cards.firstWhere((c) => c.instanceId == 'n1');
      final n2 = next.cards.firstWhere((c) => c.instanceId == 'n2');
      expect(n1.zIndex, 3);
      expect(n2.zIndex, 4);
      expect(n1.zone, CardZone.hand);
      expect(n1.ownerId, 'p1');
    });

    test('bumps revision', () {
      final state = _threeCardPile();
      final next = _actions.dealNewCards(state, newCards: [newCard('n1')]);
      expect(next.revision, state.revision + 1);
    });

    test('is a no-op for an empty list', () {
      final state = _threeCardPile();
      final next = _actions.dealNewCards(state, newCards: []);
      expect(next, same(state));
    });
  });
}
