import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_deck/game/game_session.dart';
import 'package:flutter_deck/models/board_widget_instance.dart';
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
        zones: [
          ZoneDefinition(
            id: 'draw_deck',
            name: 'Draw Deck',
            dealsBuiltDeck: true,
          ),
        ],
      );
      final session = GameSession.dealFromZones(
        game: game,
        players: _players,
        localPlayerId: 'p1',
        deckConfigsByPlayerId: {
          'p1': {
            'draw_deck': const DeckConfig(
              gameId: 'g1',
              entries: [DeckEntry(definitionId: 'a', quantity: 2)],
            ),
          },
          'p2': {
            'draw_deck': const DeckConfig(
              gameId: 'g1',
              entries: [DeckEntry(definitionId: 'b', quantity: 3)],
            ),
          },
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
        zones: [
          ZoneDefinition(
            id: 'draw_deck',
            name: 'Draw Deck',
            dealsBuiltDeck: true,
          ),
        ],
      );
      final session = GameSession.dealFromZones(
        game: game,
        players: [_players[0]],
        localPlayerId: 'p1',
      );
      expect(session.state.cards, hasLength(2));
      expect(session.state.cards.map((c) => c.definitionId).toSet(), {
        'a',
        'b',
      });
    });

    test('a non-dealsBuiltDeck owned zone starts from its own static entries (empty by default)', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [
          ZoneDefinition(
            id: 'draw_deck',
            name: 'Draw Deck',
            dealsBuiltDeck: true,
          ),
          ZoneDefinition(id: 'discard_pile', name: 'Discard Pile'),
        ],
      );
      final session = GameSession.dealFromZones(
        game: game,
        players: [_players[0]],
        localPlayerId: 'p1',
        deckConfigsByPlayerId: {
          'p1': {
            'draw_deck': const DeckConfig(
              gameId: 'g1',
              entries: [DeckEntry(definitionId: 'a', quantity: 1)],
            ),
          },
        },
      );
      expect(
        session.state.cards.where((c) => c.zoneId == 'draw_deck'),
        hasLength(1),
      );
      expect(
        session.state.cards.where((c) => c.zoneId == 'discard_pile'),
        isEmpty,
      );
    });

    test('skips entries referencing an unknown definitionId', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [
          ZoneDefinition(
            id: 'draw_deck',
            name: 'Draw Deck',
            dealsBuiltDeck: true,
          ),
        ],
      );
      final session = GameSession.dealFromZones(
        game: game,
        players: [_players[0]],
        localPlayerId: 'p1',
        deckConfigsByPlayerId: {
          'p1': {
            'draw_deck': const DeckConfig(
              gameId: 'g1',
              entries: [
                DeckEntry(definitionId: 'a', quantity: 1),
                DeckEntry(definitionId: 'nonexistent', quantity: 5),
              ],
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
        ],
      );
      final session = GameSession.dealFromZones(
        game: game,
        players: [_players[0]],
        localPlayerId: 'p1',
        deckConfigsByPlayerId: {
          'p1': {
            'draw_deck': const DeckConfig(
              gameId: 'g1',
              entries: [DeckEntry(definitionId: 'a', quantity: 2)],
            ),
            'location_deck': const DeckConfig(
              gameId: 'g1',
              entries: [DeckEntry(definitionId: 'b', quantity: 1)],
            ),
          },
        },
      );

      final drawDeckCards = session.state.cards
          .where((c) => c.zoneId == 'draw_deck')
          .toList();
      final locationDeckCards = session.state.cards
          .where((c) => c.zoneId == 'location_deck')
          .toList();
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
        zones: [
          ZoneDefinition(
            id: 'discard_pile',
            name: 'Discard Pile',
            faceUp: true,
            entries: [DeckEntry(definitionId: 'a', quantity: 1)],
          ),
        ],
      );
      final session = GameSession.dealFromZones(
        game: game,
        players: [_players[0]],
        localPlayerId: 'p1',
      );
      expect(session.state.cards.single.faceUp, isTrue);
    });

    test('a zone with no faceUp flag deals its cards face-down', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [
          ZoneDefinition(
            id: 'draw_deck',
            name: 'Draw Deck',
            dealsBuiltDeck: true,
          ),
        ],
      );
      final session = GameSession.dealFromZones(
        game: game,
        players: [_players[0]],
        localPlayerId: 'p1',
      );
      expect(session.state.cards.every((c) => !c.faceUp), isTrue);
    });
  });

  group('GameSession.dealFromZones -- autoShuffle', () {
    test('without autoShuffle, cards are dealt in entries order', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [
          ZoneDefinition(
            id: 'draw_deck',
            name: 'Draw Deck',
            entries: [
              DeckEntry(definitionId: 'a', quantity: 2),
              DeckEntry(definitionId: 'b', quantity: 2),
            ],
          ),
        ],
      );
      final session = GameSession.dealFromZones(
        game: game,
        players: [_players[0]],
        localPlayerId: 'p1',
      );
      expect(session.state.cards.map((c) => c.definitionId).toList(), [
        'a',
        'a',
        'b',
        'b',
      ]);
    });

    test('with autoShuffle, every card is still dealt with the same multiset and distinct sequential zIndex', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [
          ZoneDefinition(
            id: 'draw_deck',
            name: 'Draw Deck',
            autoShuffle: true,
            entries: [
              DeckEntry(definitionId: 'a', quantity: 10),
              DeckEntry(definitionId: 'b', quantity: 10),
            ],
          ),
        ],
      );
      final session = GameSession.dealFromZones(
        game: game,
        players: [_players[0]],
        localPlayerId: 'p1',
      );
      expect(session.state.cards, hasLength(20));
      expect(
        session.state.cards.where((c) => c.definitionId == 'a'),
        hasLength(10),
      );
      expect(
        session.state.cards.where((c) => c.definitionId == 'b'),
        hasLength(10),
      );
      expect(session.state.cards.map((c) => c.zIndex).toSet(), hasLength(20));
    });

    test('with autoShuffle, a shared zone is also randomized', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [
          ZoneDefinition(
            id: 'shared_deck',
            name: 'Shared Deck',
            shared: true,
            autoShuffle: true,
            entries: [
              DeckEntry(definitionId: 'a', quantity: 5),
              DeckEntry(definitionId: 'b', quantity: 5),
            ],
          ),
        ],
      );
      final session = GameSession.dealFromZones(
        game: game,
        players: [_players[0]],
        localPlayerId: 'p1',
      );
      expect(session.state.cards, hasLength(10));
      expect(session.state.cards.every((c) => c.ownerId == null), isTrue);
      expect(
        session.state.cards.where((c) => c.definitionId == 'a'),
        hasLength(5),
      );
    });
  });

  group(
    'GameSession.returnToZone / shuffleZone -- respecting the zone definition',
    () {
      test(
        'returnToZone sets faceUp from the zone\'s own ZoneDefinition.faceUp',
        () {
          const game = GameDefinition(
            id: 'g1',
            name: 'G',
            cards: _cards,
            zones: [
              ZoneDefinition(
                id: 'discard_pile',
                name: 'Discard Pile',
                faceUp: true,
              ),
            ],
          );
          final session = GameSession(
            game: game,
            localPlayerId: 'p1',
            initialState: TableState(
              gameId: 'g1',
              players: [_players[0]],
              cards: [
                CardInstance(
                  instanceId: 'h1',
                  definitionId: 'a',
                  x: 0,
                  y: 0,
                  zIndex: 0,
                  faceUp: false,
                  zone: CardZone.hand,
                  ownerId: 'p1',
                ),
              ],
              revision: 0,
            ),
          );
          session.returnToZone('h1', 'discard_pile', zoneOwnerId: 'p1');
          expect(
            session.state.cards.firstWhere((c) => c.instanceId == 'h1').faceUp,
            isTrue,
          );
        },
      );

      test('shuffleZone is a no-op when the zone is not shuffleable', () {
        const game = GameDefinition(
          id: 'g1',
          name: 'G',
          cards: _cards,
          zones: [
            ZoneDefinition(
              id: 'discard_pile',
              name: 'Discard Pile',
              shuffleable: false,
              entries: [DeckEntry(definitionId: 'a', quantity: 2)],
            ),
          ],
        );
        final session = GameSession.dealFromZones(
          game: game,
          players: [_players[0]],
          localPlayerId: 'p1',
        );
        final before = session.state;
        session.shuffleZone('discard_pile', zoneOwnerId: 'p1');
        expect(session.state, same(before));
      });

      test('shuffleZone proceeds normally when the zone is shuffleable', () {
        const game = GameDefinition(
          id: 'g1',
          name: 'G',
          cards: _cards,
          zones: [
            ZoneDefinition(
              id: 'draw_deck',
              name: 'Draw Deck',
              entries: [
                DeckEntry(definitionId: 'a', quantity: 2),
                DeckEntry(definitionId: 'b', quantity: 2),
              ],
            ),
          ],
        );
        final session = GameSession.dealFromZones(
          game: game,
          players: [_players[0]],
          localPlayerId: 'p1',
        );
        final before = session.state;
        session.shuffleZone('draw_deck', zoneOwnerId: 'p1');
        expect(session.state, isNot(same(before)));
      });
    },
  );

  group('GameSession.dealFromZones -- shared zones', () {
    test('empty entries default to one of every game card, unowned', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [ZoneDefinition(id: 'deck', name: 'Deck', shared: true)],
      );
      final session = GameSession.dealFromZones(
        game: game,
        players: [_players[0]],
        localPlayerId: 'p1',
      );

      expect(session.state.cards, hasLength(2));
      expect(session.state.cards.map((c) => c.definitionId).toSet(), {
        'a',
        'b',
      });
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
          ZoneDefinition(
            id: 'main_deck',
            name: 'Main Deck',
            shared: true,
            entries: [DeckEntry(definitionId: 'a', quantity: 2)],
          ),
          ZoneDefinition(
            id: 'fate_deck',
            name: 'Fate Deck',
            shared: true,
            entries: [DeckEntry(definitionId: 'b', quantity: 3)],
          ),
        ],
      );
      final session = GameSession.dealFromZones(
        game: game,
        players: [_players[0]],
        localPlayerId: 'p1',
      );

      final mainCards = session.state.cards
          .where((c) => c.zoneId == 'main_deck')
          .toList();
      final fateCards = session.state.cards
          .where((c) => c.zoneId == 'fate_deck')
          .toList();
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
            entries: [
              DeckEntry(definitionId: 'a', quantity: 1),
              DeckEntry(definitionId: 'nonexistent', quantity: 5),
            ],
          ),
        ],
      );
      final session = GameSession.dealFromZones(
        game: game,
        players: [_players[0]],
        localPlayerId: 'p1',
      );
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
        zones: [
          ZoneDefinition(
            id: 'draw_deck',
            name: 'Draw Deck',
            dealsBuiltDeck: true,
          ),
        ],
      );
      final session = GameSession.localSandbox(game: game, localPlayerId: 'p1');
      expect(session.state.cards, hasLength(2));
    });
  });

  group('GameSession board widgets', () {
    GameSession emptySession() {
      const game = GameDefinition(id: 'g1', name: 'G', cards: _cards);
      return GameSession(
        game: game,
        localPlayerId: 'p1',
        initialState: const TableState(
          gameId: 'g1',
          players: [],
          cards: [],
          revision: 0,
        ),
      );
    }

    test('createWidget adds a widget and notifies listeners', () {
      final session = emptySession();
      var notified = false;
      session.addListener(() => notified = true);
      session.createWidget('w1', BoardWidgetKind.simpleCounter, 0.5, 0.5);
      expect(session.state.widgets, hasLength(1));
      expect(session.state.widgets.single.instanceId, 'w1');
      expect(notified, isTrue);
    });

    test('moveWidget repositions and notifies listeners', () {
      final session = emptySession();
      session.createWidget('w1', BoardWidgetKind.simpleCounter, 0.1, 0.1);
      var notified = false;
      session.addListener(() => notified = true);
      session.moveWidget('w1', 0.9, 0.9);
      expect(session.state.widgets.single.x, 0.9);
      expect(session.state.widgets.single.y, 0.9);
      expect(notified, isTrue);
    });

    test(
      'setWidgetValue updates the value, clamped, and notifies listeners',
      () {
        final session = emptySession();
        session.createWidget('w1', BoardWidgetKind.simpleCounter, 0, 0);
        var notified = false;
        session.addListener(() => notified = true);
        session.setWidgetValue('w1', 500000);
        expect(session.state.widgets.single.value, boardWidgetCounterMax);
        expect(notified, isTrue);
      },
    );

    test('deleteWidget removes it and notifies listeners', () {
      final session = emptySession();
      session.createWidget('w1', BoardWidgetKind.simpleCounter, 0, 0);
      var notified = false;
      session.addListener(() => notified = true);
      session.deleteWidget('w1');
      expect(session.state.widgets, isEmpty);
      expect(notified, isTrue);
    });

    test('setWidgetColors updates both colors and notifies listeners', () {
      final session = emptySession();
      session.createWidget('w1', BoardWidgetKind.simpleCounter, 0, 0);
      var notified = false;
      session.addListener(() => notified = true);
      session.setWidgetColors('w1', 0xFFD32F2F, 0xFF000000);
      expect(session.state.widgets.single.backgroundColor, 0xFFD32F2F);
      expect(session.state.widgets.single.textColor, 0xFF000000);
      expect(notified, isTrue);
    });

    test('duplicateWidget adds a copy at the given position and notifies listeners', () {
      final session = emptySession();
      session.createWidget('w1', BoardWidgetKind.token, 0.1, 0.1);
      var notified = false;
      session.addListener(() => notified = true);
      session.duplicateWidget('w1', 'w2', 0.9, 0.9);
      expect(session.state.widgets, hasLength(2));
      final copy = session.state.widgets.firstWhere(
        (w) => w.instanceId == 'w2',
      );
      expect(copy.kind, BoardWidgetKind.token);
      expect(copy.x, 0.9);
      expect(copy.y, 0.9);
      expect(notified, isTrue);
    });

    test('attachWidgetToCard leaves the widget at the drop point and notifies listeners', () {
      const game = GameDefinition(id: 'g1', name: 'G', cards: _cards);
      final session = GameSession(
        game: game,
        localPlayerId: 'p1',
        initialState: TableState(
          gameId: 'g1',
          players: const [],
          cards: [
            CardInstance(
              instanceId: 'c1',
              definitionId: 'a',
              x: 0.4,
              y: 0.5,
              zIndex: 0,
              faceUp: true,
              zone: CardZone.table,
            ),
          ],
          revision: 0,
        ),
      );
      session.createWidget('w1', BoardWidgetKind.token, 0, 0);
      var notified = false;
      session.addListener(() => notified = true);
      session.attachWidgetToCard('w1', 'c1', 0.42, 0.53);
      final token = session.state.widgets.single;
      expect(token.x, closeTo(0.42, 1e-9));
      expect(token.y, closeTo(0.53, 1e-9));
      expect(token.attachedCardId, 'c1');
      expect(notified, isTrue);
    });
  });
}
