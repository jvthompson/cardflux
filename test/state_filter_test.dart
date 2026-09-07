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
      final filtered = filterForRecipient(trueState, 'p1', visibleZoneIds: const {});

      final theirs = filtered.cards.firstWhere((c) => c.instanceId == 'theirs');
      expect(theirs.faceUp, isFalse);
      expect(theirs.definitionId, hiddenDefinitionId);
      expect(theirs.definitionId, isNot('spades_K'), reason: 'the real identity must never reach the wrong recipient');
    });

    test("leaves the recipient's own hand card untouched", () {
      final trueState = _stateWithTwoHands();
      final filtered = filterForRecipient(trueState, 'p1', visibleZoneIds: const {});

      final mine = filtered.cards.firstWhere((c) => c.instanceId == 'mine');
      expect(mine.faceUp, isTrue);
      expect(mine.definitionId, 'hearts_A');
    });

    test('leaves table (non-hand) cards untouched regardless of recipient', () {
      final trueState = _stateWithTwoHands();
      final filtered = filterForRecipient(trueState, 'p1', visibleZoneIds: const {});

      final onTable = filtered.cards.firstWhere((c) => c.instanceId == 'onTable');
      expect(onTable.faceUp, isFalse);
      expect(onTable.definitionId, 'clubs_5');
    });

    test('filtering for the other player flips which hand is hidden', () {
      final trueState = _stateWithTwoHands();
      final filtered = filterForRecipient(trueState, 'p2', visibleZoneIds: const {});

      final mine = filtered.cards.firstWhere((c) => c.instanceId == 'mine');
      expect(mine.faceUp, isFalse);
      expect(mine.definitionId, hiddenDefinitionId);

      final theirs = filtered.cards.firstWhere((c) => c.instanceId == 'theirs');
      expect(theirs.faceUp, isTrue);
      expect(theirs.definitionId, 'spades_K');
    });

    test('preserves gameId and revision', () {
      final trueState = _stateWithTwoHands();
      final filtered = filterForRecipient(trueState, 'p1', visibleZoneIds: const {});
      expect(filtered.gameId, trueState.gameId);
      expect(filtered.revision, trueState.revision);
    });

    test("hides an opponent's owned zone card identity and forces it face-down", () {
      final trueState = TableState(
        gameId: 'g1',
        players: const [],
        cards: [
          CardInstance(
            instanceId: 'theirZoneCard',
            definitionId: 'clubs_5',
            x: 0,
            y: 0,
            zIndex: 0,
            faceUp: false,
            zone: CardZone.zone,
            zoneId: 'draw_deck',
            ownerId: 'p2',
          ),
          CardInstance(
            instanceId: 'myZoneCard',
            definitionId: 'hearts_A',
            x: 0,
            y: 0,
            zIndex: 1,
            faceUp: false,
            zone: CardZone.zone,
            zoneId: 'draw_deck',
            ownerId: 'p1',
          ),
          CardInstance(
            instanceId: 'sharedZoneCard',
            definitionId: 'spades_K',
            x: 0,
            y: 0,
            zIndex: 2,
            faceUp: false,
            zone: CardZone.zone,
            zoneId: 'deck',
          ),
        ],
        revision: 1,
      );
      final filtered = filterForRecipient(trueState, 'p1', visibleZoneIds: const {});

      final theirs = filtered.cards.firstWhere((c) => c.instanceId == 'theirZoneCard');
      expect(theirs.definitionId, hiddenDefinitionId);

      final mine = filtered.cards.firstWhere((c) => c.instanceId == 'myZoneCard');
      expect(mine.definitionId, 'hearts_A');

      // An unowned zone card (a shared deck, e.g. Standard 52's Deck) is
      // never redacted for anyone -- there's no owner it could belong to
      // instead.
      final shared = filtered.cards.firstWhere((c) => c.instanceId == 'sharedZoneCard');
      expect(shared.definitionId, 'spades_K');
    });

    test('a zone in visibleZoneIds is not redacted for a non-owner, but remains not interactable', () {
      final trueState = TableState(
        gameId: 'g1',
        players: const [],
        cards: [
          CardInstance(
            instanceId: 'theirDiscard',
            definitionId: 'clubs_5',
            x: 0,
            y: 0,
            zIndex: 0,
            faceUp: true,
            zone: CardZone.zone,
            zoneId: 'discard_pile',
            ownerId: 'p2',
          ),
          CardInstance(
            instanceId: 'theirDrawDeck',
            definitionId: 'hearts_A',
            x: 0,
            y: 0,
            zIndex: 1,
            faceUp: false,
            zone: CardZone.zone,
            zoneId: 'draw_deck',
            ownerId: 'p2',
          ),
        ],
        revision: 1,
      );
      final filtered = filterForRecipient(trueState, 'p1', visibleZoneIds: {'discard_pile'});

      // discard_pile is visible -- real face and identity pass through.
      final discard = filtered.cards.firstWhere((c) => c.instanceId == 'theirDiscard');
      expect(discard.faceUp, isTrue);
      expect(discard.definitionId, 'clubs_5');
      // Still owned by p2, not p1 -- HostGameEngine's ownership resolution
      // (never client-claimed) is what actually keeps it non-interactable,
      // unaffected by this filter.
      expect(discard.ownerId, 'p2');

      // draw_deck isn't in visibleZoneIds -- still redacted as before.
      final drawDeck = filtered.cards.firstWhere((c) => c.instanceId == 'theirDrawDeck');
      expect(drawDeck.definitionId, hiddenDefinitionId);
    });
  });
}
