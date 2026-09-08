import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_deck/models/board_widget_instance.dart';
import 'package:flutter_deck/models/card_definition.dart';
import 'package:flutter_deck/models/card_instance.dart';
import 'package:flutter_deck/models/deck_config.dart';
import 'package:flutter_deck/models/game_definition.dart';
import 'package:flutter_deck/models/player.dart';
import 'package:flutter_deck/models/table_state.dart';
import 'package:flutter_deck/models/zone_definition.dart';

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

    test('types defaults to empty and round-trips through JSON', () {
      const untyped = CardDefinition(id: 'a', cardTitle: 'A');
      expect(untyped.types, isEmpty);
      expect(untyped.toJson().containsKey('types'), isFalse);

      const typed = CardDefinition(id: 'b', cardTitle: 'B', types: ['Hearts', 'Face']);
      final roundTripped = CardDefinition.fromJson(typed.toJson());
      expect(roundTripped.types, ['Hearts', 'Face']);
    });

    test('orientation defaults to portrait and is omitted from JSON', () {
      const def = CardDefinition(id: 'a', cardTitle: 'A');
      expect(def.orientation, CardOrientation.portrait);
      expect(def.toJson().containsKey('orientation'), isFalse);
    });

    test('orientation round-trips left and right through JSON', () {
      const right = CardDefinition(id: 'a', cardTitle: 'A', orientation: CardOrientation.right);
      expect(CardDefinition.fromJson(right.toJson()).orientation, CardOrientation.right);
      expect(right.toJson()['orientation'], 'right');

      const left = CardDefinition(id: 'b', cardTitle: 'B', orientation: CardOrientation.left);
      expect(CardDefinition.fromJson(left.toJson()).orientation, CardOrientation.left);
      expect(left.toJson()['orientation'], 'left');
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
      expect(roundTripped.zoneId, isNull);
    });

    test('zoneId round-trips through JSON', () {
      final instance = CardInstance(
        instanceId: 'i1',
        definitionId: 'hearts_A',
        x: 0,
        y: 0,
        zIndex: 0,
        faceUp: false,
        zone: CardZone.zone,
        zoneId: 'draw_deck',
        ownerId: 'p1',
      );
      final roundTripped = CardInstance.fromJson(instance.toJson());
      expect(roundTripped.zone, CardZone.zone);
      expect(roundTripped.zoneId, 'draw_deck');
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
        zoneId: 'draw_deck',
      );
      final unstacked = instance.copyWith(stackParentId: null, zoneId: null);
      expect(unstacked.stackParentId, isNull);
      expect(unstacked.zoneId, isNull);
    });

    test('rotationTurns defaults to 0 and round-trips a nonzero value through JSON', () {
      final instance = CardInstance(
        instanceId: 'i1',
        definitionId: 'hearts_A',
        x: 0,
        y: 0,
        zIndex: 0,
        faceUp: false,
        zone: CardZone.table,
      );
      expect(instance.rotationTurns, 0);
      expect(instance.toJson().containsKey('rotationTurns'), isFalse);

      final rotated = instance.copyWith(rotationTurns: 3);
      final roundTripped = CardInstance.fromJson(rotated.toJson());
      expect(roundTripped.rotationTurns, 3);
    });
  });

  group('BoardWidgetInstance', () {
    test('round-trips through JSON', () {
      final instance = BoardWidgetInstance(
        instanceId: 'w1',
        kind: BoardWidgetKind.simpleCounter,
        x: 0.4,
        y: 0.6,
        zIndex: 2,
        value: 42,
      );
      final roundTripped = BoardWidgetInstance.fromJson(instance.toJson());
      expect(roundTripped.instanceId, 'w1');
      expect(roundTripped.kind, BoardWidgetKind.simpleCounter);
      expect(roundTripped.x, 0.4);
      expect(roundTripped.y, 0.6);
      expect(roundTripped.zIndex, 2);
      expect(roundTripped.value, 42);
    });

    test('value defaults to 0 and is omitted from JSON', () {
      final instance = BoardWidgetInstance(instanceId: 'w1', kind: BoardWidgetKind.simpleCounter, x: 0, y: 0, zIndex: 0);
      expect(instance.value, 0);
      expect(instance.toJson().containsKey('value'), isFalse);
      expect(BoardWidgetInstance.fromJson(instance.toJson()).value, 0);
    });

    test('copyWith updates only requested fields', () {
      final instance = BoardWidgetInstance(instanceId: 'w1', kind: BoardWidgetKind.simpleCounter, x: 0, y: 0, zIndex: 0);
      final moved = instance.copyWith(x: 0.5, y: 0.5, value: 7);
      expect(moved.x, 0.5);
      expect(moved.y, 0.5);
      expect(moved.value, 7);
      expect(moved.instanceId, instance.instanceId);
      expect(moved.kind, instance.kind);
    });

    test('backgroundColor/textColor default and are omitted from JSON', () {
      final instance = BoardWidgetInstance(instanceId: 'w1', kind: BoardWidgetKind.simpleCounter, x: 0, y: 0, zIndex: 0);
      expect(instance.backgroundColor, defaultBoardWidgetBackgroundColor);
      expect(instance.textColor, defaultBoardWidgetTextColor);
      expect(instance.toJson().containsKey('backgroundColor'), isFalse);
      expect(instance.toJson().containsKey('textColor'), isFalse);
    });

    test('backgroundColor/textColor round-trip a custom value through JSON', () {
      final instance = BoardWidgetInstance(
        instanceId: 'w1',
        kind: BoardWidgetKind.simpleCounter,
        x: 0,
        y: 0,
        zIndex: 0,
        backgroundColor: 0xFFD32F2F,
        textColor: 0xFF000000,
      );
      final roundTripped = BoardWidgetInstance.fromJson(instance.toJson());
      expect(roundTripped.backgroundColor, 0xFFD32F2F);
      expect(roundTripped.textColor, 0xFF000000);
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

  group('ZoneDefinition', () {
    test('round-trips through JSON', () {
      const zone = ZoneDefinition(
        id: 'discard_pile',
        name: 'Discard Pile',
        entries: [DeckEntry(definitionId: 'hearts_A', quantity: 2)],
      );
      final roundTripped = ZoneDefinition.fromJson(zone.toJson());
      expect(roundTripped.id, 'discard_pile');
      expect(roundTripped.name, 'Discard Pile');
      expect(roundTripped.shared, isFalse);
      expect(roundTripped.dealsBuiltDeck, isFalse);
      expect(roundTripped.entries.single.definitionId, 'hearts_A');
      expect(roundTripped.entries.single.quantity, 2);
    });

    test('shared/dealsBuiltDeck/faceUp/visibleToAll default to false, shuffleable to true, entries to empty when absent from JSON', () {
      final zone = ZoneDefinition.fromJson({'id': 'deck', 'name': 'Deck'});
      expect(zone.shared, isFalse);
      expect(zone.dealsBuiltDeck, isFalse);
      expect(zone.entries, isEmpty);
      expect(zone.faceUp, isFalse);
      expect(zone.shuffleable, isTrue);
      expect(zone.visibleToAll, isFalse);
    });

    test('faceUp/shuffleable/visibleToAll round-trip through JSON', () {
      final zone = ZoneDefinition.fromJson({
        'id': 'discard_pile',
        'name': 'Discard Pile',
        'faceUp': true,
        'shuffleable': false,
        'visibleToAll': true,
      });
      expect(zone.faceUp, isTrue);
      expect(zone.shuffleable, isFalse);
      expect(zone.visibleToAll, isTrue);
      final roundTripped = ZoneDefinition.fromJson(zone.toJson());
      expect(roundTripped.faceUp, isTrue);
      expect(roundTripped.shuffleable, isFalse);
      expect(roundTripped.visibleToAll, isTrue);
    });

    test('toJson omits false flags, true shuffleable, and empty entries', () {
      const zone = ZoneDefinition(id: 'deck', name: 'Deck');
      final json = zone.toJson();
      expect(json.containsKey('shared'), isFalse);
      expect(json.containsKey('dealsBuiltDeck'), isFalse);
      expect(json.containsKey('entries'), isFalse);
      expect(json.containsKey('faceUp'), isFalse);
      expect(json.containsKey('shuffleable'), isFalse);
      expect(json.containsKey('visibleToAll'), isFalse);
      expect(json.containsKey('isDiscardPile'), isFalse);
    });

    test('isDiscardPile defaults to false and round-trips true through JSON', () {
      final zone = ZoneDefinition.fromJson({'id': 'discard_pile', 'name': 'Discard Pile'});
      expect(zone.isDiscardPile, isFalse);

      const marked = ZoneDefinition(id: 'discard_pile', name: 'Discard Pile', isDiscardPile: true);
      final roundTripped = ZoneDefinition.fromJson(marked.toJson());
      expect(roundTripped.isDiscardPile, isTrue);
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

    test('zones defaults to empty when absent from JSON', () {
      final json = {
        'id': 'g1',
        'name': 'G',
        'cards': [
          {'id': 'a', 'cardTitle': 'A', 'colorHex': '#000000'},
        ],
      };
      final game = GameDefinition.fromJson(json);
      expect(game.zones, isEmpty);
      expect(game.needsDeckBuilding, isFalse);
    });

    test('opponentCardBorderColor defaults to red when absent from JSON', () {
      final json = {
        'id': 'g1',
        'name': 'G',
        'cards': [
          {'id': 'a', 'cardTitle': 'A', 'colorHex': '#000000'},
        ],
      };
      final game = GameDefinition.fromJson(json);
      expect(game.opponentCardBorderColor, defaultOpponentCardBorderColor);
      expect(game.toJson().containsKey('opponentCardBorderColor'), isFalse);
    });

    test('opponentCardBorderColor round-trips a custom color through JSON', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: [CardDefinition(id: 'a', cardTitle: 'A', colorHex: '#000000')],
        opponentCardBorderColor: '#00FF00',
      );
      final roundTripped = GameDefinition.fromJson(game.toJson());
      expect(roundTripped.opponentCardBorderColor, '#00FF00');
      expect(game.toJson()['opponentCardBorderColor'], '#00FF00');
    });

    test('cardTypes defaults to empty when absent from JSON', () {
      final json = {
        'id': 'g1',
        'name': 'G',
        'cards': [
          {'id': 'a', 'cardTitle': 'A', 'colorHex': '#000000'},
        ],
      };
      final game = GameDefinition.fromJson(json);
      expect(game.cardTypes, isEmpty);
      expect(game.toJson().containsKey('cardTypes'), isFalse);
    });

    test('cardTypes round-trips through JSON', () {
      const game = GameDefinition(
        id: 'standard_52',
        name: 'Standard 52-Card Deck',
        cards: [CardDefinition(id: 'hearts_A', cardTitle: 'A', colorHex: '#D32F2F', types: ['Hearts'])],
        cardTypes: ['Hearts', 'Diamonds', 'Clubs', 'Spades'],
      );
      final roundTripped = GameDefinition.fromJson(game.toJson());
      expect(roundTripped.cardTypes, ['Hearts', 'Diamonds', 'Clubs', 'Spades']);
      expect(roundTripped.cards.first.types, ['Hearts']);
    });

    test('round-trips zones through JSON', () {
      const game = GameDefinition(
        id: 'metw',
        name: 'METW',
        cards: [CardDefinition(id: 'a', cardTitle: 'A', colorHex: '#000000')],
        zones: [
          ZoneDefinition(id: 'draw_deck', name: 'Draw Deck', dealsBuiltDeck: true),
          ZoneDefinition(id: 'discard_pile', name: 'Discard Pile'),
        ],
      );
      final roundTripped = GameDefinition.fromJson(game.toJson());
      expect(roundTripped.zones, hasLength(2));
      expect(roundTripped.zones[0].id, 'draw_deck');
      expect(roundTripped.zones[0].dealsBuiltDeck, isTrue);
      expect(roundTripped.zones[1].id, 'discard_pile');
      expect(roundTripped.zones[1].dealsBuiltDeck, isFalse);
    });

    test('needsDeckBuilding is true iff some owned zone deals a built deck', () {
      const deckBuilding = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: [],
        zones: [ZoneDefinition(id: 'draw_deck', name: 'Draw Deck', dealsBuiltDeck: true)],
      );
      expect(deckBuilding.needsDeckBuilding, isTrue);

      const fixedOnly = GameDefinition(
        id: 'g2',
        name: 'G',
        cards: [],
        zones: [ZoneDefinition(id: 'deck', name: 'Deck', shared: true)],
      );
      expect(fixedOnly.needsDeckBuilding, isFalse);

      // A shared zone marked dealsBuiltDeck doesn't count -- only an owned
      // zone can receive a per-player Load Deck selection.
      const sharedBuiltFlag = GameDefinition(
        id: 'g3',
        name: 'G',
        cards: [],
        zones: [ZoneDefinition(id: 'deck', name: 'Deck', shared: true, dealsBuiltDeck: true)],
      );
      expect(sharedBuiltFlag.needsDeckBuilding, isFalse);
    });

    test('deckBuildingZones enumerates every owned dealsBuiltDeck zone, in JSON order', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: [],
        zones: [
          ZoneDefinition(id: 'draw_deck', name: 'Draw Deck', dealsBuiltDeck: true),
          ZoneDefinition(id: 'location_deck', name: 'Location Deck', dealsBuiltDeck: true),
          ZoneDefinition(id: 'discard_pile', name: 'Discard Pile'),
          ZoneDefinition(id: 'deck', name: 'Deck', shared: true, dealsBuiltDeck: true),
        ],
      );
      expect(game.deckBuildingZones.map((z) => z.id), ['draw_deck', 'location_deck']);
      expect(game.needsDeckBuilding, isTrue);
    });

    test('toJson omits zones when empty', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: [CardDefinition(id: 'a', cardTitle: 'A', colorHex: '#000000')],
      );
      expect(game.toJson().containsKey('zones'), isFalse);
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
            zone: CardZone.zone,
            zoneId: 'deck',
          ),
        ],
        revision: 1,
      );
      final roundTripped = TableState.fromJson(state.toJson());
      expect(roundTripped.gameId, 'standard_52');
      expect(roundTripped.players, hasLength(1));
      expect(roundTripped.cards, hasLength(1));
      expect(roundTripped.cards.single.zoneId, 'deck');
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

    test('widgets defaults to empty and is omitted from JSON', () {
      final state = TableState(gameId: 'g', players: const [], cards: const [], revision: 0);
      expect(state.widgets, isEmpty);
      expect(state.toJson().containsKey('widgets'), isFalse);
    });

    test('widgets round-trips through JSON', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: const [],
        revision: 0,
        widgets: [BoardWidgetInstance(instanceId: 'w1', kind: BoardWidgetKind.simpleCounter, x: 0.2, y: 0.3, zIndex: 0, value: 5)],
      );
      final roundTripped = TableState.fromJson(state.toJson());
      expect(roundTripped.widgets, hasLength(1));
      expect(roundTripped.widgets.single.instanceId, 'w1');
      expect(roundTripped.widgets.single.value, 5);
    });
  });
}
