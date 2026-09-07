import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_deck/models/card_instance.dart';
import 'package:flutter_deck/models/table_state.dart';
import 'package:flutter_deck/networking/state_filter.dart';

TableState _stateWithTwoHands() {
  return TableState(
    gameId: 'standard_52',
    players: const [],
    cards: [
      CardInstance(
        instanceId: 'mine',
        definitionId: 'hearts_A',
        x: 0,
        y: 0,
        zIndex: 0,
        faceUp: true,
        zone: CardZone.hand,
        ownerId: 'p1',
      ),
      CardInstance(
        instanceId: 'theirs',
        definitionId: 'spades_K',
        x: 0,
        y: 0,
        zIndex: 1,
        faceUp: true,
        zone: CardZone.hand,
        ownerId: 'p2',
      ),
      CardInstance(
        instanceId: 'onTable',
        definitionId: 'clubs_5',
        x: 10,
        y: 10,
        zIndex: 2,
        faceUp: false,
        zone: CardZone.table,
      ),
    ],
    revision: 3,
  );
}

void main() {
  group('filterForRecipient', () {
    test("hides an opponent's hand card identity and forces it face-down", () {
      final trueState = _stateWithTwoHands();
      final filtered = filterForRecipient(trueState, 'p1');

      final theirs = filtered.cards.firstWhere((c) => c.instanceId == 'theirs');
      expect(theirs.faceUp, isFalse);
      expect(theirs.definitionId, hiddenDefinitionId);
      expect(theirs.definitionId, isNot('spades_K'), reason: 'the real identity must never reach the wrong recipient');
    });

    test("leaves the recipient's own hand card untouched", () {
      final trueState = _stateWithTwoHands();
      final filtered = filterForRecipient(trueState, 'p1');

      final mine = filtered.cards.firstWhere((c) => c.instanceId == 'mine');
      expect(mine.faceUp, isTrue);
      expect(mine.definitionId, 'hearts_A');
    });

    test('leaves table (non-hand) cards untouched regardless of recipient', () {
      final trueState = _stateWithTwoHands();
      final filtered = filterForRecipient(trueState, 'p1');

      final onTable = filtered.cards.firstWhere((c) => c.instanceId == 'onTable');
      expect(onTable.faceUp, isFalse);
      expect(onTable.definitionId, 'clubs_5');
    });

    test('filtering for the other player flips which hand is hidden', () {
      final trueState = _stateWithTwoHands();
      final filtered = filterForRecipient(trueState, 'p2');

      final mine = filtered.cards.firstWhere((c) => c.instanceId == 'mine');
      expect(mine.faceUp, isFalse);
      expect(mine.definitionId, hiddenDefinitionId);

      final theirs = filtered.cards.firstWhere((c) => c.instanceId == 'theirs');
      expect(theirs.faceUp, isTrue);
      expect(theirs.definitionId, 'spades_K');
    });

    test('preserves gameId and revision', () {
      final trueState = _stateWithTwoHands();
      final filtered = filterForRecipient(trueState, 'p1');
      expect(filtered.gameId, trueState.gameId);
      expect(filtered.revision, trueState.revision);
    });

    test("hides an opponent's personal deck card identity and forces it face-down", () {
      final trueState = TableState(
        gameId: 'g1',
        players: const [],
        cards: [
          CardInstance(
            instanceId: 'theirDeckCard',
            definitionId: 'clubs_5',
            x: 0,
            y: 0,
            zIndex: 0,
            faceUp: false,
            zone: CardZone.drawPile,
            ownerId: 'p2',
          ),
          CardInstance(
            instanceId: 'myDeckCard',
            definitionId: 'hearts_A',
            x: 0,
            y: 0,
            zIndex: 1,
            faceUp: false,
            zone: CardZone.drawPile,
            ownerId: 'p1',
          ),
          CardInstance(
            instanceId: 'sandboxPileCard',
            definitionId: 'spades_K',
            x: 0,
            y: 0,
            zIndex: 2,
            faceUp: false,
            zone: CardZone.drawPile,
          ),
        ],
        revision: 1,
      );
      final filtered = filterForRecipient(trueState, 'p1');

      final theirs = filtered.cards.firstWhere((c) => c.instanceId == 'theirDeckCard');
      expect(theirs.definitionId, hiddenDefinitionId);

      final mine = filtered.cards.firstWhere((c) => c.instanceId == 'myDeckCard');
      expect(mine.definitionId, 'hearts_A');

      // An unowned drawPile card (e.g. Practice Mode's shared pile) is never
      // redacted for anyone -- there's no owner it could belong to instead.
      final sandbox = filtered.cards.firstWhere((c) => c.instanceId == 'sandboxPileCard');
      expect(sandbox.definitionId, 'spades_K');
    });
  });
}
