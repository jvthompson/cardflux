import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_deck/game/game_session.dart';
import 'package:flutter_deck/models/card_definition.dart';
import 'package:flutter_deck/models/card_instance.dart';
import 'package:flutter_deck/models/deck_config.dart';
import 'package:flutter_deck/models/game_definition.dart';
import 'package:flutter_deck/models/player.dart';
import 'package:flutter_deck/models/table_state.dart';
import 'package:flutter_deck/models/zone_definition.dart';

const _cards = [
  CardDefinition(id: 'a', cardTitle: 'A', colorHex: '#000000'),
  CardDefinition(id: 'b', cardTitle: 'B', colorHex: '#000000'),
];

const _players = [
  PlayerInfo(id: 'p1', name: 'Host', role: PlayerRole.host),
  PlayerInfo(id: 'p2', name: 'Client', role: PlayerRole.client),
];

void main() {
  group('GameSession.dealFromZones -- owned zones', () {
    test('a dealsBuiltDeck zone deals each player their own chosen DeckConfig, into their own stack', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [ZoneDefinition(id: 'draw_deck', name: 'Draw Deck', dealsBuiltDeck: true)],
      );
      final session = GameSession.dealFromZones(
        game: game,
        players: _players,
        localPlayerId: 'p1',
        deckConfigsByPlayerId: {
          'p1': {'draw_deck': const DeckConfig(gameId: 'g1', entries: [DeckEntry(definitionId: 'a', quantity: 2)])},
          'p2': {'draw_deck': const DeckConfig(gameId: 'g1', entries: [DeckEntry(definitionId: 'b', quantity: 3)])},
        },
      );

      expect(session.state.cards, hasLength(5));
      for (final card in session.state.cards) {
        expect(card.zone, CardZone.zone);
        expect(card.zoneId, 'draw_deck');
        expect(card.faceUp, isFalse);
      }
      expect(session.state.cards.where((c) => c.ownerId == 'p1'), hasLength(2));
      expect(session.state.cards.where((c) => c.ownerId == 'p2'), hasLength(3));
    });

    test('a dealsBuiltDeck zone falls back to one of every card when no DeckConfig is supplied', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [ZoneDefinition(id: 'draw_deck', name: 'Draw Deck', dealsBuiltDeck: true)],
      );
      final session = GameSession.dealFromZones(game: game, players: [_players[0]], localPlayerId: 'p1');
      expect(session.state.cards, hasLength(2));
      expect(session.state.cards.map((c) => c.definitionId).toSet(), {'a', 'b'});
    });

    test('a non-dealsBuiltDeck owned zone starts from its own static entries (empty by default)', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [
          ZoneDefinition(id: 'draw_deck', name: 'Draw Deck', dealsBuiltDeck: true),
          ZoneDefinition(id: 'discard_pile', name: 'Discard Pile'),
        ],
      );
      final session = GameSession.dealFromZones(
        game: game,
        players: [_players[0]],
        localPlayerId: 'p1',
        deckConfigsByPlayerId: {
          'p1': {'draw_deck': const DeckConfig(gameId: 'g1', entries: [DeckEntry(definitionId: 'a', quantity: 1)])},
        },
      );
      expect(session.state.cards.where((c) => c.zoneId == 'draw_deck'), hasLength(1));
      expect(session.state.cards.where((c) => c.zoneId == 'discard_pile'), isEmpty);
    });

    test('skips entries referencing an unknown definitionId', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [ZoneDefinition(id: 'draw_deck', name: 'Draw Deck', dealsBuiltDeck: true)],
      );
      final session = GameSession.dealFromZones(
        game: game,
        players: [_players[0]],
        localPlayerId: 'p1',
        deckConfigsByPlayerId: {
          'p1': {
            'draw_deck': const DeckConfig(
              gameId: 'g1',
              entries: [DeckEntry(definitionId: 'a', quantity: 1), DeckEntry(definitionId: 'nonexistent', quantity: 5)],
            ),
          },
        },
      );
      expect(session.state.cards, hasLength(1));
      expect(session.state.cards.single.definitionId, 'a');
    });

    test('two dealsBuiltDeck zones each get their own distinct chosen deck, not one duplicated into both', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [
          ZoneDefinition(id: 'draw_deck', name: 'Draw Deck', dealsBuiltDeck: true),
          ZoneDefinition(id: 'location_deck', name: 'Location Deck', dealsBuiltDeck: true),
        ],
      );
      final session = GameSession.dealFromZones(
        game: game,
        players: [_players[0]],
        localPlayerId: 'p1',
        deckConfigsByPlayerId: {
          'p1': {
            'draw_deck': const DeckConfig(gameId: 'g1', entries: [DeckEntry(definitionId: 'a', quantity: 2)]),
            'location_deck': const DeckConfig(gameId: 'g1', entries: [DeckEntry(definitionId: 'b', quantity: 1)]),
          },
        },
      );

      final drawDeckCards = session.state.cards.where((c) => c.zoneId == 'draw_deck').toList();
      final locationDeckCards = session.state.cards.where((c) => c.zoneId == 'location_deck').toList();
      expect(drawDeckCards, hasLength(2));
      expect(drawDeckCards.every((c) => c.definitionId == 'a'), isTrue);
      expect(locationDeckCards, hasLength(1));
      expect(locationDeckCards.single.definitionId, 'b');
    });
  });

  group('GameSession.dealFromZones -- faceUp', () {
    test('a zone with faceUp: true deals its cards face-up', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [ZoneDefinition(id: 'discard_pile', name: 'Discard Pile', faceUp: true, entries: [DeckEntry(definitionId: 'a', quantity: 1)])],
      );
      final session = GameSession.dealFromZones(game: game, players: [_players[0]], localPlayerId: 'p1');
      expect(session.state.cards.single.faceUp, isTrue);
    });

    test('a zone with no faceUp flag deals its cards face-down', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [ZoneDefinition(id: 'draw_deck', name: 'Draw Deck', dealsBuiltDeck: true)],
      );
      final session = GameSession.dealFromZones(game: game, players: [_players[0]], localPlayerId: 'p1');
      expect(session.state.cards.every((c) => !c.faceUp), isTrue);
    });
  });

  group('GameSession.returnToZone / shuffleZone -- respecting the zone definition', () {
    test('returnToZone sets faceUp from the zone\'s own ZoneDefinition.faceUp', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [ZoneDefinition(id: 'discard_pile', name: 'Discard Pile', faceUp: true)],
      );
      final session = GameSession(
        game: game,
        localPlayerId: 'p1',
        initialState: TableState(
          gameId: 'g1',
          players: [_players[0]],
          cards: [CardInstance(instanceId: 'h1', definitionId: 'a', x: 0, y: 0, zIndex: 0, faceUp: false, zone: CardZone.hand, ownerId: 'p1')],
          revision: 0,
        ),
      );
      session.returnToZone('h1', 'discard_pile', zoneOwnerId: 'p1');
      expect(session.state.cards.firstWhere((c) => c.instanceId == 'h1').faceUp, isTrue);
    });

    test('shuffleZone is a no-op when the zone is not shuffleable', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [ZoneDefinition(id: 'discard_pile', name: 'Discard Pile', shuffleable: false, entries: [DeckEntry(definitionId: 'a', quantity: 2)])],
      );
      final session = GameSession.dealFromZones(game: game, players: [_players[0]], localPlayerId: 'p1');
      final before = session.state;
      session.shuffleZone('discard_pile', zoneOwnerId: 'p1');
      expect(session.state, same(before));
    });

    test('shuffleZone proceeds normally when the zone is shuffleable', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [ZoneDefinition(id: 'draw_deck', name: 'Draw Deck', entries: [DeckEntry(definitionId: 'a', quantity: 2), DeckEntry(definitionId: 'b', quantity: 2)])],
      );
      final session = GameSession.dealFromZones(game: game, players: [_players[0]], localPlayerId: 'p1');
      final before = session.state;
      session.shuffleZone('draw_deck', zoneOwnerId: 'p1');
      expect(session.state, isNot(same(before)));
    });
  });

  group('GameSession.dealFromZones -- shared zones', () {
    test('empty entries default to one of every game card, unowned', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [ZoneDefinition(id: 'deck', name: 'Deck', shared: true)],
      );
      final session = GameSession.dealFromZones(game: game, players: [_players[0]], localPlayerId: 'p1');

      expect(session.state.cards, hasLength(2));
      expect(session.state.cards.map((c) => c.definitionId).toSet(), {'a', 'b'});
      for (final card in session.state.cards) {
        expect(card.zone, CardZone.zone);
        expect(card.zoneId, 'deck');
        expect(card.faceUp, isFalse);
        expect(card.ownerId, isNull);
      }
    });

    test('multiple shared zones land at different positions and stay independently grouped', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [
          ZoneDefinition(id: 'main_deck', name: 'Main Deck', shared: true, entries: [DeckEntry(definitionId: 'a', quantity: 2)]),
          ZoneDefinition(id: 'fate_deck', name: 'Fate Deck', shared: true, entries: [DeckEntry(definitionId: 'b', quantity: 3)]),
        ],
      );
      final session = GameSession.dealFromZones(game: game, players: [_players[0]], localPlayerId: 'p1');

      final mainCards = session.state.cards.where((c) => c.zoneId == 'main_deck').toList();
      final fateCards = session.state.cards.where((c) => c.zoneId == 'fate_deck').toList();
      expect(mainCards, hasLength(2));
      expect(fateCards, hasLength(3));
      // Positioned differently so the two piles don't overlap on the table.
      expect(mainCards.first.y, isNot(fateCards.first.y));
    });

    test('skips entries referencing an unknown definitionId', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: [CardDefinition(id: 'a', cardTitle: 'A', colorHex: '#000000')],
        zones: [
          ZoneDefinition(
            id: 'deck',
            name: 'Deck',
            shared: true,
            entries: [DeckEntry(definitionId: 'a', quantity: 1), DeckEntry(definitionId: 'nonexistent', quantity: 5)],
          ),
        ],
      );
      final session = GameSession.dealFromZones(game: game, players: [_players[0]], localPlayerId: 'p1');
      expect(session.state.cards, hasLength(1));
      expect(session.state.cards.single.definitionId, 'a');
    });
  });

  group('GameSession.localSandbox', () {
    test('deals via dealFromZones for a single solo player', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [ZoneDefinition(id: 'deck', name: 'Deck', shared: true)],
      );
      final session = GameSession.localSandbox(game: game, localPlayerId: 'p1');
      expect(session.state.cards, hasLength(2));
      expect(session.state.cards.every((c) => c.zoneId == 'deck'), isTrue);
    });

    test('a dealsBuiltDeck zone falls back to one of every card with no Load Deck step', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [ZoneDefinition(id: 'draw_deck', name: 'Draw Deck', dealsBuiltDeck: true)],
      );
      final session = GameSession.localSandbox(game: game, localPlayerId: 'p1');
      expect(session.state.cards, hasLength(2));
    });
  });
}
