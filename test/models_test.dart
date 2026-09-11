import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_deck/models/active_search.dart';
import 'package:flutter_deck/models/board_widget_instance.dart';
import 'package:flutter_deck/models/card_definition.dart';
import 'package:flutter_deck/models/card_instance.dart';
import 'package:flutter_deck/models/deck_config.dart';
import 'package:flutter_deck/models/game_definition.dart';
import 'package:flutter_deck/models/game_set.dart';
import 'package:flutter_deck/models/player.dart';
import 'package:flutter_deck/models/table_state.dart';
import 'package:flutter_deck/models/tag_group.dart';
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

      const typed = CardDefinition(
        id: 'b',
        cardTitle: 'B',
        types: ['Hearts', 'Face'],
      );
      final roundTripped = CardDefinition.fromJson(typed.toJson());
      expect(roundTripped.types, ['Hearts', 'Face']);
    });

    test('orientation defaults to portrait and is omitted from JSON', () {
      const def = CardDefinition(id: 'a', cardTitle: 'A');
      expect(def.orientation, CardOrientation.portrait);
      expect(def.toJson().containsKey('orientation'), isFalse);
    });

    test('orientation round-trips left and right through JSON', () {
      const right = CardDefinition(
        id: 'a',
        cardTitle: 'A',
        orientation: CardOrientation.right,
      );
      expect(
        CardDefinition.fromJson(right.toJson()).orientation,
        CardOrientation.right,
      );
      expect(right.toJson()['orientation'], 'right');

      const left = CardDefinition(
        id: 'b',
        cardTitle: 'B',
        orientation: CardOrientation.left,
      );
      expect(
        CardDefinition.fromJson(left.toJson()).orientation,
        CardOrientation.left,
      );
      expect(left.toJson()['orientation'], 'left');
    });

    test('setId defaults to null and round-trips through JSON', () {
      const untagged = CardDefinition(id: 'a', cardTitle: 'A');
      expect(untagged.setId, isNull);
      expect(untagged.toJson().containsKey('setId'), isFalse);

      const tagged = CardDefinition(id: 'b', cardTitle: 'B', setId: 'core_set');
      final roundTripped = CardDefinition.fromJson(tagged.toJson());
      expect(roundTripped.setId, 'core_set');
    });

    test('copyWith with no arguments returns an equal-fielded copy', () {
      const original = CardDefinition(
        id: 'a',
        cardTitle: 'A',
        colorHex: '#000000',
        suit: 'hearts',
        rank: 'A',
        imagePath: 'a.jpg',
        types: ['Hearts'],
        orientation: CardOrientation.right,
        setId: 'core_set',
      );
      final copy = original.copyWith();
      expect(copy.id, original.id);
      expect(copy.cardTitle, original.cardTitle);
      expect(copy.colorHex, original.colorHex);
      expect(copy.suit, original.suit);
      expect(copy.rank, original.rank);
      expect(copy.imagePath, original.imagePath);
      expect(copy.types, original.types);
      expect(copy.orientation, original.orientation);
      expect(copy.setId, original.setId);
    });

    test('copyWith updates only the requested field', () {
      const original = CardDefinition(id: 'a', cardTitle: 'A');
      final renamed = original.copyWith(cardTitle: 'New Title');
      expect(renamed.cardTitle, 'New Title');
      expect(renamed.id, 'a');
    });

    test('copyWith(field: null) explicitly clears a nullable field, distinct from omitting it', () {
      const original = CardDefinition(
        id: 'a',
        cardTitle: 'A',
        colorHex: '#000000',
        setId: 'core_set',
      );

      final unchanged = original.copyWith(cardTitle: 'A2');
      expect(
        unchanged.colorHex,
        '#000000',
        reason: 'omitting colorHex should leave it alone',
      );
      expect(
        unchanged.setId,
        'core_set',
        reason: 'omitting setId should leave it alone',
      );

      final cleared = original.copyWith(colorHex: null, setId: null);
      expect(cleared.colorHex, isNull);
      expect(cleared.setId, isNull);
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
      final instance = BoardWidgetInstance(
        instanceId: 'w1',
        kind: BoardWidgetKind.simpleCounter,
        x: 0,
        y: 0,
        zIndex: 0,
      );
      expect(instance.value, 0);
      expect(instance.toJson().containsKey('value'), isFalse);
      expect(BoardWidgetInstance.fromJson(instance.toJson()).value, 0);
    });

    test('copyWith updates only requested fields', () {
      final instance = BoardWidgetInstance(
        instanceId: 'w1',
        kind: BoardWidgetKind.simpleCounter,
        x: 0,
        y: 0,
        zIndex: 0,
      );
      final moved = instance.copyWith(x: 0.5, y: 0.5, value: 7);
      expect(moved.x, 0.5);
      expect(moved.y, 0.5);
      expect(moved.value, 7);
      expect(moved.instanceId, instance.instanceId);
      expect(moved.kind, instance.kind);
    });

    test('backgroundColor/textColor default and are omitted from JSON', () {
      final instance = BoardWidgetInstance(
        instanceId: 'w1',
        kind: BoardWidgetKind.simpleCounter,
        x: 0,
        y: 0,
        zIndex: 0,
      );
      expect(instance.backgroundColor, defaultBoardWidgetBackgroundColor);
      expect(instance.textColor, defaultBoardWidgetTextColor);
      expect(instance.toJson().containsKey('backgroundColor'), isFalse);
      expect(instance.toJson().containsKey('textColor'), isFalse);
    });

    test(
      'backgroundColor/textColor round-trip a custom value through JSON',
      () {
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
      },
    );

    test('attachedCardId defaults to null, is omitted from JSON, and round-trips a value', () {
      final instance = BoardWidgetInstance(
        instanceId: 'w1',
        kind: BoardWidgetKind.token,
        x: 0,
        y: 0,
        zIndex: 0,
      );
      expect(instance.attachedCardId, isNull);
      expect(instance.toJson().containsKey('attachedCardId'), isFalse);

      final attached = instance.copyWith(attachedCardId: 'c1');
      expect(attached.attachedCardId, 'c1');
      final roundTripped = BoardWidgetInstance.fromJson(attached.toJson());
      expect(roundTripped.attachedCardId, 'c1');
    });

    test('copyWith can explicitly clear attachedCardId back to null', () {
      final instance = BoardWidgetInstance(
        instanceId: 'w1',
        kind: BoardWidgetKind.token,
        x: 0,
        y: 0,
        zIndex: 0,
        attachedCardId: 'c1',
      );
      final detached = instance.copyWith(attachedCardId: null);
      expect(detached.attachedCardId, isNull);
    });

    test('attachOffsetX/attachOffsetY default to 0, are omitted from JSON, and round-trip a value', () {
      final instance = BoardWidgetInstance(
        instanceId: 'w1',
        kind: BoardWidgetKind.token,
        x: 0,
        y: 0,
        zIndex: 0,
      );
      expect(instance.attachOffsetX, 0);
      expect(instance.attachOffsetY, 0);
      expect(instance.toJson().containsKey('attachOffsetX'), isFalse);
      expect(instance.toJson().containsKey('attachOffsetY'), isFalse);

      final offset = instance.copyWith(attachOffsetX: 0.1, attachOffsetY: -0.2);
      final roundTripped = BoardWidgetInstance.fromJson(offset.toJson());
      expect(roundTripped.attachOffsetX, closeTo(0.1, 1e-9));
      expect(roundTripped.attachOffsetY, closeTo(-0.2, 1e-9));
    });

    test('token kind round-trips through JSON', () {
      final instance = BoardWidgetInstance(
        instanceId: 'w1',
        kind: BoardWidgetKind.token,
        x: 0.2,
        y: 0.3,
        zIndex: 0,
      );
      final roundTripped = BoardWidgetInstance.fromJson(instance.toJson());
      expect(roundTripped.kind, BoardWidgetKind.token);
    });

    test('x2/y2/creatorId default to null, are omitted from JSON, and round-trip a value', () {
      final instance = BoardWidgetInstance(
        instanceId: 'w1',
        kind: BoardWidgetKind.token,
        x: 0,
        y: 0,
        zIndex: 0,
      );
      expect(instance.x2, isNull);
      expect(instance.y2, isNull);
      expect(instance.creatorId, isNull);
      expect(instance.toJson().containsKey('x2'), isFalse);
      expect(instance.toJson().containsKey('y2'), isFalse);
      expect(instance.toJson().containsKey('creatorId'), isFalse);

      final arrow = instance.copyWith(x2: 0.4, y2: 0.9, creatorId: 'p1');
      final roundTripped = BoardWidgetInstance.fromJson(arrow.toJson());
      expect(roundTripped.x2, closeTo(0.4, 1e-9));
      expect(roundTripped.y2, closeTo(0.9, 1e-9));
      expect(roundTripped.creatorId, 'p1');
    });

    test('copyWith can explicitly clear x2/y2/creatorId back to null', () {
      final instance = BoardWidgetInstance(
        instanceId: 'w1',
        kind: BoardWidgetKind.arrow,
        x: 0,
        y: 0,
        zIndex: 0,
        x2: 1,
        y2: 1,
        creatorId: 'p1',
      );
      final cleared = instance.copyWith(x2: null, y2: null, creatorId: null);
      expect(cleared.x2, isNull);
      expect(cleared.y2, isNull);
      expect(cleared.creatorId, isNull);
    });

    test('arrow kind round-trips through JSON with both endpoints', () {
      final instance = BoardWidgetInstance(
        instanceId: 'a1',
        kind: BoardWidgetKind.arrow,
        x: 0.1,
        y: 0.2,
        x2: 0.6,
        y2: 0.7,
        creatorId: 'p1',
        zIndex: 0,
      );
      final roundTripped = BoardWidgetInstance.fromJson(instance.toJson());
      expect(roundTripped.kind, BoardWidgetKind.arrow);
      expect(roundTripped.x2, closeTo(0.6, 1e-9));
      expect(roundTripped.y2, closeTo(0.7, 1e-9));
      expect(roundTripped.creatorId, 'p1');
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
      expect(zone.autoShuffle, isFalse);
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
      expect(json.containsKey('autoShuffle'), isFalse);
    });

    test(
      'isDiscardPile defaults to false and round-trips true through JSON',
      () {
        final zone = ZoneDefinition.fromJson({
          'id': 'discard_pile',
          'name': 'Discard Pile',
        });
        expect(zone.isDiscardPile, isFalse);

        const marked = ZoneDefinition(
          id: 'discard_pile',
          name: 'Discard Pile',
          isDiscardPile: true,
        );
        final roundTripped = ZoneDefinition.fromJson(marked.toJson());
        expect(roundTripped.isDiscardPile, isTrue);
      },
    );

    test('autoShuffle defaults to false and round-trips true through JSON', () {
      final zone = ZoneDefinition.fromJson({
        'id': 'draw_deck',
        'name': 'Draw Deck',
      });
      expect(zone.autoShuffle, isFalse);

      const shuffled = ZoneDefinition(
        id: 'draw_deck',
        name: 'Draw Deck',
        autoShuffle: true,
      );
      final roundTripped = ZoneDefinition.fromJson(shuffled.toJson());
      expect(roundTripped.autoShuffle, isTrue);
    });

    test('copyWith with no arguments returns an equal-fielded copy', () {
      const original = ZoneDefinition(
        id: 'draw_deck',
        name: 'Draw Deck',
        shared: true,
        dealsBuiltDeck: true,
        entries: [DeckEntry(definitionId: 'a', quantity: 2)],
        faceUp: true,
        shuffleable: false,
        visibleToAll: true,
        isDiscardPile: true,
        autoShuffle: true,
      );
      final copy = original.copyWith();
      expect(copy.id, original.id);
      expect(copy.name, original.name);
      expect(copy.shared, original.shared);
      expect(copy.dealsBuiltDeck, original.dealsBuiltDeck);
      expect(copy.entries, original.entries);
      expect(copy.faceUp, original.faceUp);
      expect(copy.shuffleable, original.shuffleable);
      expect(copy.visibleToAll, original.visibleToAll);
      expect(copy.isDiscardPile, original.isDiscardPile);
      expect(copy.autoShuffle, original.autoShuffle);
    });

    test('copyWith updates only the requested field', () {
      const original = ZoneDefinition(id: 'deck', name: 'Deck');
      final updated = original.copyWith(
        shuffleable: false,
        isDiscardPile: true,
        autoShuffle: true,
      );
      expect(updated.shuffleable, isFalse);
      expect(updated.isDiscardPile, isTrue);
      expect(updated.autoShuffle, isTrue);
      expect(updated.id, 'deck');
      expect(updated.name, 'Deck');
      expect(updated.shared, isFalse);
    });
  });

  group('GameDefinition', () {
    test('round-trips through JSON', () {
      const game = GameDefinition(
        id: 'standard_52',
        name: 'Standard 52-Card Deck',
        cards: [
          CardDefinition(id: 'hearts_A', cardTitle: 'A', colorHex: '#D32F2F'),
        ],
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

    test('tagGroups defaults to empty when absent from JSON', () {
      final json = {
        'id': 'g1',
        'name': 'G',
        'cards': [
          {'id': 'a', 'cardTitle': 'A', 'colorHex': '#000000'},
        ],
      };
      final game = GameDefinition.fromJson(json);
      expect(game.tagGroups, isEmpty);
      expect(game.toJson().containsKey('tagGroups'), isFalse);
    });

    test('tagGroups round-trips through JSON', () {
      const game = GameDefinition(
        id: 'standard_52',
        name: 'Standard 52-Card Deck',
        cards: [
          CardDefinition(
            id: 'hearts_A',
            cardTitle: 'A',
            colorHex: '#D32F2F',
            types: ['Hearts'],
          ),
        ],
        tagGroups: [
          TagGroup(
            id: 'suits',
            name: 'Suit',
            tags: ['Hearts', 'Diamonds', 'Clubs', 'Spades'],
          ),
        ],
      );
      final roundTripped = GameDefinition.fromJson(game.toJson());
      expect(roundTripped.tagGroups, hasLength(1));
      expect(roundTripped.tagGroups.single.id, 'suits');
      expect(roundTripped.tagGroups.single.name, 'Suit');
      expect(roundTripped.tagGroups.single.tags, [
        'Hearts',
        'Diamonds',
        'Clubs',
        'Spades',
      ]);
      expect(roundTripped.cards.first.types, ['Hearts']);
    });

    test('round-trips zones through JSON', () {
      const game = GameDefinition(
        id: 'metw',
        name: 'METW',
        cards: [CardDefinition(id: 'a', cardTitle: 'A', colorHex: '#000000')],
        zones: [
          ZoneDefinition(
            id: 'draw_deck',
            name: 'Draw Deck',
            dealsBuiltDeck: true,
          ),
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

    test(
      'needsDeckBuilding is true iff some owned zone deals a built deck',
      () {
        const deckBuilding = GameDefinition(
          id: 'g1',
          name: 'G',
          cards: [],
          zones: [
            ZoneDefinition(
              id: 'draw_deck',
              name: 'Draw Deck',
              dealsBuiltDeck: true,
            ),
          ],
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
          zones: [
            ZoneDefinition(
              id: 'deck',
              name: 'Deck',
              shared: true,
              dealsBuiltDeck: true,
            ),
          ],
        );
        expect(sharedBuiltFlag.needsDeckBuilding, isFalse);
      },
    );

    test('deckBuildingZones enumerates every owned dealsBuiltDeck zone, in JSON order', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: [],
        zones: [
          ZoneDefinition(
            id: 'draw_deck',
            name: 'Draw Deck',
            dealsBuiltDeck: true,
          ),
          ZoneDefinition(
            id: 'location_deck',
            name: 'Location Deck',
            dealsBuiltDeck: true,
          ),
          ZoneDefinition(id: 'discard_pile', name: 'Discard Pile'),
          ZoneDefinition(
            id: 'deck',
            name: 'Deck',
            shared: true,
            dealsBuiltDeck: true,
          ),
        ],
      );
      expect(game.deckBuildingZones.map((z) => z.id), [
        'draw_deck',
        'location_deck',
      ]);
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

    test('sets defaults to empty and toJson keeps writing the flat cards shape unchanged', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: [CardDefinition(id: 'a', cardTitle: 'A', colorHex: '#000000')],
      );
      expect(game.sets, isEmpty);
      final json = game.toJson();
      expect(json.containsKey('sets'), isFalse);
      expect(json.containsKey('cards'), isTrue);
      final roundTripped = GameDefinition.fromJson(json);
      expect(roundTripped.sets, isEmpty);
      expect(roundTripped.cards.single.setId, isNull);
    });

    test(
      'sets round-trip through JSON, with cards tagged and grouped by set',
      () {
        const game = GameDefinition(
          id: 'g1',
          name: 'G',
          sets: [
            GameSet(id: 's1', name: 'Set One'),
            GameSet(id: 's2', name: 'Set Two'),
          ],
          cards: [
            CardDefinition(id: 'a', cardTitle: 'A', setId: 's1'),
            CardDefinition(id: 'b', cardTitle: 'B', setId: 's2'),
          ],
        );

        final json = game.toJson();
        expect(json.containsKey('sets'), isTrue);
        expect(json.containsKey('cards'), isFalse);
        final setsJson = json['sets'] as List;
        expect(setsJson, hasLength(2));
        final firstSetCards = (setsJson[0] as Map)['cards'] as List;
        expect((firstSetCards.single as Map).containsKey('setId'), isFalse);

        final roundTripped = GameDefinition.fromJson(json);
        expect(roundTripped.sets.map((s) => s.id), ['s1', 's2']);
        expect(roundTripped.sets.map((s) => s.name), ['Set One', 'Set Two']);
        expect(roundTripped.cards, hasLength(2));
        expect(roundTripped.cards[0].setId, 's1');
        expect(roundTripped.cards[1].setId, 's2');
      },
    );
  });

  group('GameSet', () {
    test('round-trips through JSON', () {
      const set = GameSet(id: 'core_set', name: 'The Wizards');
      final roundTripped = GameSet.fromJson(set.toJson());
      expect(roundTripped.id, 'core_set');
      expect(roundTripped.name, 'The Wizards');
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
        players: const [
          PlayerInfo(id: 'p1', name: 'Alice', role: PlayerRole.host),
        ],
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
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: const [],
        revision: 0,
      );
      expect(state.widgets, isEmpty);
      expect(state.toJson().containsKey('widgets'), isFalse);
    });

    test('widgets round-trips through JSON', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: const [],
        revision: 0,
        widgets: [
          BoardWidgetInstance(
            instanceId: 'w1',
            kind: BoardWidgetKind.simpleCounter,
            x: 0.2,
            y: 0.3,
            zIndex: 0,
            value: 5,
          ),
        ],
      );
      final roundTripped = TableState.fromJson(state.toJson());
      expect(roundTripped.widgets, hasLength(1));
      expect(roundTripped.widgets.single.instanceId, 'w1');
      expect(roundTripped.widgets.single.value, 5);
    });

    test('searches defaults to empty and is omitted from JSON', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: const [],
        revision: 0,
      );
      expect(state.searches, isEmpty);
      expect(state.toJson().containsKey('searches'), isFalse);
    });

    test('searches round-trips through JSON', () {
      final state = TableState(
        gameId: 'g',
        players: const [],
        cards: const [],
        revision: 0,
        searches: const [
          ActiveSearch(
            searcherId: 'p1',
            targetType: SearchTargetType.zone,
            targetId: 'deck',
            targetOwnerId: 'p1',
          ),
        ],
      );
      final roundTripped = TableState.fromJson(state.toJson());
      expect(roundTripped.searches, hasLength(1));
      expect(roundTripped.searches.single.searcherId, 'p1');
      expect(roundTripped.searches.single.targetType, SearchTargetType.zone);
      expect(roundTripped.searches.single.targetId, 'deck');
      expect(roundTripped.searches.single.targetOwnerId, 'p1');
    });
  });

  group('ActiveSearch', () {
    test('targetOwnerId defaults to null and is omitted from JSON', () {
      const search = ActiveSearch(
        searcherId: 'p1',
        targetType: SearchTargetType.pile,
        targetId: 'root1',
      );
      expect(search.targetOwnerId, isNull);
      expect(search.toJson().containsKey('targetOwnerId'), isFalse);
      expect(ActiveSearch.fromJson(search.toJson()).targetOwnerId, isNull);
    });

    test('round-trips a pile target through JSON', () {
      const search = ActiveSearch(
        searcherId: 'p1',
        targetType: SearchTargetType.pile,
        targetId: 'root1',
      );
      final roundTripped = ActiveSearch.fromJson(search.toJson());
      expect(roundTripped.searcherId, 'p1');
      expect(roundTripped.targetType, SearchTargetType.pile);
      expect(roundTripped.targetId, 'root1');
    });
  });
}
