import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_deck/models/card_definition.dart';
import 'package:flutter_deck/models/card_instance.dart';
import 'package:flutter_deck/models/deck_config.dart';
import 'package:flutter_deck/models/game_definition.dart';
import 'package:flutter_deck/models/player.dart';
import 'package:flutter_deck/models/table_state.dart';

void main() {
  group('CardDefinition', () {
    test('round-trips through JSON', () {
      const def = CardDefinition(
        id: 'hearts_A',
        cardTitle: 'A',
        colorHex: '#D32F2F',
        suit: 'hearts',
        rank: 'A',
      );
      final roundTripped = CardDefinition.fromJson(def.toJson());
      expect(roundTripped.id, def.id);
      expect(roundTripped.cardTitle, def.cardTitle);
      expect(roundTripped.colorHex, def.colorHex);
      expect(roundTripped.suit, def.suit);
      expect(roundTripped.rank, def.rank);
      expect(roundTripped.imagePath, isNull);
    });
  });

  group('CardInstance', () {
    test('round-trips through JSON', () {
      final instance = CardInstance(
        instanceId: 'i1',
        definitionId: 'hearts_A',
        x: 1.5,
        y: 2.5,
        zIndex: 3,
        faceUp: true,
        zone: CardZone.hand,
        ownerId: 'p1',
      );
      final roundTripped = CardInstance.fromJson(instance.toJson());
      expect(roundTripped.instanceId, 'i1');
      expect(roundTripped.definitionId, 'hearts_A');
      expect(roundTripped.x, 1.5);
      expect(roundTripped.y, 2.5);
      expect(roundTripped.zIndex, 3);
      expect(roundTripped.faceUp, true);
      expect(roundTripped.zone, CardZone.hand);
      expect(roundTripped.ownerId, 'p1');
      expect(roundTripped.stackParentId, isNull);
    });

    test('copyWith updates only requested fields', () {
      final instance = CardInstance(
        instanceId: 'i1',
        definitionId: 'hearts_A',
        x: 0,
        y: 0,
        zIndex: 0,
        faceUp: false,
        zone: CardZone.table,
      );
      final moved = instance.copyWith(x: 10, y: 20);
      expect(moved.x, 10);
      expect(moved.y, 20);
      expect(moved.instanceId, instance.instanceId);
      expect(moved.faceUp, instance.faceUp);
    });

    test('copyWith can explicitly clear a nullable field', () {
      final instance = CardInstance(
        instanceId: 'i1',
        definitionId: 'hearts_A',
        x: 0,
        y: 0,
        zIndex: 0,
        faceUp: false,
        zone: CardZone.table,
        stackParentId: 'i0',
      );
      final unstacked = instance.copyWith(stackParentId: null);
      expect(unstacked.stackParentId, isNull);
    });
  });

  group('PlayerInfo', () {
    test('round-trips through JSON', () {
      const player = PlayerInfo(id: 'p1', name: 'Alice', role: PlayerRole.host);
      final roundTripped = PlayerInfo.fromJson(player.toJson());
      expect(roundTripped.id, 'p1');
      expect(roundTripped.name, 'Alice');
      expect(roundTripped.role, PlayerRole.host);
    });
  });

  group('GameDefinition', () {
    test('round-trips through JSON', () {
      const game = GameDefinition(
        id: 'standard_52',
        name: 'Standard 52-Card Deck',
        cards: [CardDefinition(id: 'hearts_A', cardTitle: 'A', colorHex: '#D32F2F')],
      );
      final roundTripped = GameDefinition.fromJson(game.toJson());
      expect(roundTripped.id, 'standard_52');
      expect(roundTripped.cards, hasLength(1));
      expect(roundTripped.cards.first.id, 'hearts_A');
    });

    test('deckMode/fixedDecks default to deckBuilding/empty when absent from JSON', () {
      final json = {
        'id': 'g1',
        'name': 'G',
        'cards': [
          {'id': 'a', 'cardTitle': 'A', 'colorHex': '#000000'},
        ],
      };
      final game = GameDefinition.fromJson(json);
      expect(game.deckMode, GameDeckMode.deckBuilding);
      expect(game.fixedDecks, isEmpty);
    });

    test('round-trips a fixedDeck game with named decks through JSON', () {
      const game = GameDefinition(
        id: 'standard_52',
        name: 'Standard 52-Card Deck',
        cards: [CardDefinition(id: 'hearts_A', cardTitle: 'A', colorHex: '#D32F2F')],
        deckMode: GameDeckMode.fixedDeck,
        fixedDecks: [
          FixedDeckDefinition(name: 'Deck'),
          FixedDeckDefinition(name: 'Fate Deck', entries: [DeckEntry(definitionId: 'hearts_A', quantity: 2)]),
        ],
      );
      final roundTripped = GameDefinition.fromJson(game.toJson());
      expect(roundTripped.deckMode, GameDeckMode.fixedDeck);
      expect(roundTripped.fixedDecks, hasLength(2));
      expect(roundTripped.fixedDecks[0].name, 'Deck');
      expect(roundTripped.fixedDecks[0].entries, isEmpty);
      expect(roundTripped.fixedDecks[1].name, 'Fate Deck');
      expect(roundTripped.fixedDecks[1].entries.single.definitionId, 'hearts_A');
      expect(roundTripped.fixedDecks[1].entries.single.quantity, 2);
    });

    test('toJson omits deckMode/fixedDecks for the default deckBuilding game', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: [CardDefinition(id: 'a', cardTitle: 'A', colorHex: '#000000')],
      );
      final json = game.toJson();
      expect(json.containsKey('deckMode'), isFalse);
      expect(json.containsKey('fixedDecks'), isFalse);
    });
  });

  group('DeckConfig', () {
    test('round-trips through JSON', () {
      const deck = DeckConfig(
        gameId: 'standard_52',
        entries: [DeckEntry(definitionId: 'hearts_A', quantity: 1)],
      );
      final roundTripped = DeckConfig.fromJson(deck.toJson());
      expect(roundTripped.gameId, 'standard_52');
      expect(roundTripped.entries, hasLength(1));
      expect(roundTripped.entries.first.quantity, 1);
    });

    test('DeckConfig.full includes one entry per game card at quantity 1', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: [
          CardDefinition(id: 'a', cardTitle: 'A', colorHex: '#000000'),
          CardDefinition(id: 'b', cardTitle: 'B', colorHex: '#000000'),
        ],
      );
      final deck = DeckConfig.full(game);
      expect(deck.gameId, 'g1');
      expect(deck.entries.map((e) => e.definitionId).toSet(), {'a', 'b'});
      expect(deck.entries.every((e) => e.quantity == 1), isTrue);
    });
  });

  group('TableState', () {
    test('round-trips through JSON', () {
      final state = TableState(
        gameId: 'standard_52',
        players: const [PlayerInfo(id: 'p1', name: 'Alice', role: PlayerRole.host)],
        cards: [
          CardInstance(
            instanceId: 'i1',
            definitionId: 'hearts_A',
            x: 0,
            y: 0,
            zIndex: 0,
            faceUp: false,
            zone: CardZone.drawPile,
          ),
        ],
        revision: 1,
      );
      final roundTripped = TableState.fromJson(state.toJson());
      expect(roundTripped.gameId, 'standard_52');
      expect(roundTripped.players, hasLength(1));
      expect(roundTripped.cards, hasLength(1));
      expect(roundTripped.revision, 1);
    });

    test('copyWith replaces cards and bumps revision', () {
      final state = TableState(
        gameId: 'standard_52',
        players: const [],
        cards: const [],
        revision: 1,
      );
      final next = state.copyWith(cards: [], revision: 2);
      expect(next.revision, 2);
      expect(next.gameId, state.gameId);
    });

    test('fixedDeckNames defaults to empty and is omitted from JSON when absent', () {
      final state = TableState(gameId: 'g1', players: const [], cards: const [], revision: 1);
      expect(state.fixedDeckNames, isEmpty);
      expect(state.toJson().containsKey('fixedDeckNames'), isFalse);
    });

    test('fixedDeckNames round-trips through JSON and survives copyWith', () {
      final state = TableState(
        gameId: 'g1',
        players: const [],
        cards: const [],
        revision: 1,
        fixedDeckNames: const {'root1': 'Deck'},
      );
      final roundTripped = TableState.fromJson(state.toJson());
      expect(roundTripped.fixedDeckNames, {'root1': 'Deck'});

      final next = state.copyWith(revision: 2);
      expect(next.fixedDeckNames, {'root1': 'Deck'});
    });
  });
}
