import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_deck/game/deck_widget_zones.dart';
import 'package:flutter_deck/game/game_session.dart';
import 'package:flutter_deck/models/board_widget_instance.dart';
import 'package:flutter_deck/models/card_definition.dart';
import 'package:flutter_deck/models/card_instance.dart';
import 'package:flutter_deck/models/deck_config.dart';
import 'package:flutter_deck/models/game_definition.dart';
import 'package:flutter_deck/models/game_set.dart';
import 'package:flutter_deck/models/pack_setting.dart';
import 'package:flutter_deck/models/player.dart';
import 'package:flutter_deck/models/standard_deck.dart';
import 'package:flutter_deck/models/table_state.dart';
import 'package:flutter_deck/models/zone_definition.dart';

const _cards = [
  CardDefinition(id: 'a', cardTitle: 'A', colorHex: '#000000'),
  CardDefinition(id: 'b', cardTitle: 'B', colorHex: '#000000'),
];

const _players = [
  PlayerInfo(id: 'p1', name: 'Host', role: PlayerRole.host, color: 0xFFD32F2F),
  PlayerInfo(id: 'p2', name: 'Client', role: PlayerRole.client, color: 0xFF1976D2),
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
          'p1': const DeckConfig(
            gameId: 'g1',
            subdecks: [SubDeck(name: 'main_deck', entries: [DeckEntry(definitionId: 'a', quantity: 2)])],
          ),
          'p2': const DeckConfig(
            gameId: 'g1',
            subdecks: [SubDeck(name: 'main_deck', entries: [DeckEntry(definitionId: 'b', quantity: 3)])],
          ),
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
          'p1': const DeckConfig(
            gameId: 'g1',
            subdecks: [SubDeck(name: 'main_deck', entries: [DeckEntry(definitionId: 'a', quantity: 1)])],
          ),
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
          'p1': const DeckConfig(
            gameId: 'g1',
            subdecks: [
              SubDeck(
                name: 'main_deck',
                entries: [
                  DeckEntry(definitionId: 'a', quantity: 1),
                  DeckEntry(definitionId: 'nonexistent', quantity: 5),
                ],
              ),
            ],
          ),
        },
      );
      expect(session.state.cards, hasLength(1));
      expect(session.state.cards.single.definitionId, 'a');
    });

    test('two dealsBuiltDeck zones with distinct deck types each deal from their own subdeck', () {
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
            deckType: 'location_deck',
          ),
        ],
      );
      final session = GameSession.dealFromZones(
        game: game,
        players: [_players[0]],
        localPlayerId: 'p1',
        deckConfigsByPlayerId: {
          'p1': const DeckConfig(
            gameId: 'g1',
            subdecks: [
              SubDeck(name: 'main_deck', entries: [DeckEntry(definitionId: 'a', quantity: 2)]),
              SubDeck(name: 'location_deck', entries: [DeckEntry(definitionId: 'b', quantity: 1)]),
            ],
          ),
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

    test('a chosen deck missing an optional zone\'s subdeck deals that zone empty, not a full-deck fallback', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [
          ZoneDefinition(
            id: 'location_deck',
            name: 'Location Deck',
            dealsBuiltDeck: true,
            deckType: 'location_deck',
            deckOptional: true,
          ),
        ],
      );
      final session = GameSession.dealFromZones(
        game: game,
        players: [_players[0]],
        localPlayerId: 'p1',
        deckConfigsByPlayerId: {
          'p1': const DeckConfig(gameId: 'g1', subdecks: []),
        },
      );
      expect(session.state.cards, isEmpty);
    });
  });

  group('GameSession.dealFromZones -- widget zones', () {
    test(
      'a widget zone deals one simpleCounter BoardWidgetInstance per player, seeded from its starting config',
      () {
        const game = GameDefinition(
          id: 'g1',
          name: 'G',
          cards: _cards,
          zones: [
            ZoneDefinition(
              id: 'life_total',
              name: 'Life Total',
              kind: ZoneKind.widget,
              widgetKind: ZoneWidgetKind.counter,
              counterStartingValue: 20,
              counterStartingColor: 0xFF112233,
              counterStartingTextColor: 0xFF445566,
            ),
          ],
        );
        final session = GameSession.dealFromZones(
          game: game,
          players: _players,
          localPlayerId: 'p1',
        );

        expect(session.state.cards, isEmpty);
        expect(session.state.widgets, hasLength(2));
        for (final player in _players) {
          final instance = session.state.widgets.singleWhere(
            (w) => w.ownerId == player.id,
          );
          expect(instance.kind, BoardWidgetKind.simpleCounter);
          expect(instance.zoneId, 'life_total');
          expect(instance.value, 20);
          expect(instance.backgroundColor, 0xFF112233);
          expect(instance.textColor, 0xFF445566);
        }
        // Distinct instance ids -- each player gets their own counter, not
        // a shared one.
        expect(
          session.state.widgets.map((w) => w.instanceId).toSet(),
          hasLength(2),
        );
      },
    );

    test('a card zone deals no widgets, and a widget zone deals no cards', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [
          ZoneDefinition(id: 'hand_deck', name: 'Deck', entries: [
            DeckEntry(definitionId: 'a', quantity: 2),
          ]),
          ZoneDefinition(
            id: 'life_total',
            name: 'Life Total',
            kind: ZoneKind.widget,
          ),
        ],
      );
      final session = GameSession.dealFromZones(
        game: game,
        players: [_players[0]],
        localPlayerId: 'p1',
      );

      expect(session.state.cards, hasLength(2));
      expect(session.state.cards.every((c) => c.zoneId == 'hand_deck'), isTrue);
      expect(session.state.widgets, hasLength(1));
      expect(session.state.widgets.single.zoneId, 'life_total');
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
          session.returnToZone('h1', 'discard_pile', zoneOwnerId: 'p1', actingPlayerId: 'p1');
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
        session.shuffleZone('discard_pile', zoneOwnerId: 'p1', actingPlayerId: 'p1');
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
        session.shuffleZone('draw_deck', zoneOwnerId: 'p1', actingPlayerId: 'p1');
        expect(session.state, isNot(same(before)));
      });
    },
  );

  group('GameSession.dealFromZones -- shared zones', () {
    test('a shared isDiscardPile zone with empty entries starts empty, not with a full deck', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [
          ZoneDefinition(id: 'deck', name: 'Deck', shared: true, standardDeck: true),
          ZoneDefinition(
            id: 'discard',
            name: 'Discard Pile',
            shared: true,
            faceUp: true,
            isDiscardPile: true,
          ),
        ],
      );
      final session = GameSession.dealFromZones(
        game: game,
        players: [_players[0]],
        localPlayerId: 'p1',
      );

      expect(session.state.cards.where((c) => c.zoneId == 'deck'), hasLength(52));
      expect(session.state.cards.where((c) => c.zoneId == 'discard'), isEmpty);
    });

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
        // A shared zone's dealt cards get the same placeholder x/y an owned
        // zone's cards do -- a zone card's position is never read for
        // display (see ZoneDefinition.side), just kept non-meaningless.
        expect(card.x, 0.5);
        expect(card.y, 0.5);
      }
    });

    test('standardDeck deals one of each generated standard playing card', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [
          ZoneDefinition(id: 'deck', name: 'Deck', shared: true, standardDeck: true),
        ],
      );
      final session = GameSession.dealFromZones(
        game: game,
        players: [_players[0]],
        localPlayerId: 'p1',
      );
      expect(session.state.cards, hasLength(52));
      expect(
        session.state.cards.map((c) => c.definitionId).toSet(),
        buildStandardDeckCards().map((c) => c.id).toSet(),
      );
      // Every generated standard playing card is unownable -- see
      // buildStandardDeckCards -- and dealFromZones must carry that flag
      // through onto the dealt CardInstance.
      expect(session.state.cards.every((c) => c.unownable), isTrue);
    });

    test("a dealt card's unownable flag matches its CardDefinition", () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: [
          CardDefinition(id: 'a', cardTitle: 'A', unownable: true),
          CardDefinition(id: 'b', cardTitle: 'B'),
        ],
        zones: [ZoneDefinition(id: 'deck', name: 'Deck', shared: true)],
      );
      final session = GameSession.dealFromZones(
        game: game,
        players: [_players[0]],
        localPlayerId: 'p1',
      );
      expect(
        session.state.cards.firstWhere((c) => c.definitionId == 'a').unownable,
        isTrue,
      );
      expect(
        session.state.cards.firstWhere((c) => c.definitionId == 'b').unownable,
        isFalse,
      );
    });

    test('deckName resolves against sharedDeckConfigsByZoneId, overriding static entries', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [
          ZoneDefinition(
            id: 'deck',
            name: 'Deck',
            shared: true,
            deckName: 'My Deck',
            entries: [DeckEntry(definitionId: 'a', quantity: 1)],
          ),
        ],
      );
      final session = GameSession.dealFromZones(
        game: game,
        players: [_players[0]],
        localPlayerId: 'p1',
        sharedDeckConfigsByZoneId: {
          'deck': const DeckConfig(
            gameId: 'g1',
            subdecks: [SubDeck(name: 'main_deck', entries: [DeckEntry(definitionId: 'b', quantity: 4)])],
          ),
        },
      );
      expect(session.state.cards, hasLength(4));
      expect(session.state.cards.every((c) => c.definitionId == 'b'), isTrue);
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

  group('GameSession.localPractice', () {
    const solo = [PlayerInfo(id: 'p1', name: 'P1', role: PlayerRole.host, color: 0xFFD32F2F)];

    test('deals via dealFromZones for a single solo player', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [ZoneDefinition(id: 'deck', name: 'Deck', shared: true)],
      );
      final session = GameSession.localPractice(game: game, players: solo);
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
      final session = GameSession.localPractice(game: game, players: solo);
      expect(session.state.cards, hasLength(2));
    });

    test('acts as the first player and can switch active seat between all of them', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: _cards,
        zones: [ZoneDefinition(id: 'hand', name: 'Hand', dealsBuiltDeck: true)],
      );
      const players = [
        PlayerInfo(id: 'p1', name: 'P1', role: PlayerRole.host, color: 0xFFD32F2F),
        PlayerInfo(id: 'p2', name: 'P2', role: PlayerRole.host, color: 0xFF1976D2),
      ];
      final session = GameSession.localPractice(game: game, players: players);
      expect(session.isLocalPractice, isTrue);
      expect(session.localPlayerId, 'p1');
      expect(session.actingPlayerId, 'p1');

      session.setActiveSeat('p2');
      expect(session.actingPlayerId, 'p2');
      // The layout anchor never follows the active seat.
      expect(session.localPlayerId, 'p1');
    });

    test('setActiveSeat is a no-op outside a local practice session', () {
      const game = GameDefinition(id: 'g1', name: 'G', cards: _cards);
      final session = GameSession.dealFromZones(game: game, players: solo, localPlayerId: 'p1');
      expect(session.isLocalPractice, isFalse);
      session.setActiveSeat('someone-else');
      expect(session.actingPlayerId, 'p1');
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

    test('createWidget stamps ownerId only for deckBuilder, never for other kinds', () {
      final session = emptySession();
      session.createWidget('w1', BoardWidgetKind.deckBuilder, 0.5, 0.5, actingPlayerId: 'p1');
      expect(session.state.widgets.single.ownerId, 'p1');
      expect(session.state.widgets.single.zoneId, isNull);

      session.createWidget('w2', BoardWidgetKind.simpleCounter, 0.5, 0.5, actingPlayerId: 'p1');
      final counter = session.state.widgets.firstWhere((w) => w.instanceId == 'w2');
      expect(counter.ownerId, isNull);
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
        session.setWidgetValue('w1', 500000, actingPlayerId: 'p1');
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
      session.attachWidgetToCard('w1', 'c1', 0.42, 0.53, actingPlayerId: 'p1');
      final token = session.state.widgets.single;
      expect(token.x, closeTo(0.42, 1e-9));
      expect(token.y, closeTo(0.53, 1e-9));
      expect(token.attachedCardId, 'c1');
      expect(notified, isTrue);
    });
  });

  group('action log', () {
    const game = GameDefinition(
      id: 'g1',
      name: 'G',
      cards: _cards,
      zones: [
        ZoneDefinition(id: 'draw_deck', name: 'Draw Deck'),
        ZoneDefinition(
          id: 'discard_pile',
          name: 'Discard Pile',
          isDiscardPile: true,
          faceUp: true,
        ),
        ZoneDefinition(
          id: 'life_total',
          name: 'Life Total',
          kind: ZoneKind.widget,
        ),
      ],
    );

    GameSession sessionWith(List<CardInstance> cards) {
      return GameSession(
        game: game,
        localPlayerId: 'p1',
        initialState: TableState(
          gameId: 'g1',
          players: _players,
          cards: cards,
          revision: 0,
        ),
      );
    }

    test('moveCard reveals the name of a face-up hand card played to the table', () {
      final session = sessionWith([
        CardInstance(
          instanceId: 'c1',
          definitionId: 'a',
          x: 0,
          y: 0,
          zIndex: 0,
          faceUp: true,
          zone: CardZone.hand,
          ownerId: 'p1',
        ),
      ]);
      session.moveCard('c1', 0.5, 0.5, actingPlayerId: 'p1');
      expect(session.state.log, hasLength(1));
      expect(session.state.log.single.message, 'Host played "A" to the table from hand.');
    });

    test('moveCard stays generic for a face-down zone card played to the table', () {
      final session = sessionWith([
        CardInstance(
          instanceId: 'c1',
          definitionId: 'a',
          x: 0,
          y: 0,
          zIndex: 0,
          faceUp: false,
          zone: CardZone.zone,
          zoneId: 'draw_deck',
          ownerId: 'p1',
        ),
      ]);
      session.moveCard('c1', 0.5, 0.5, actingPlayerId: 'p1');
      expect(
        session.state.log.single.message,
        'Host played a card to the table from the Draw Deck.',
      );
    });

    test('moveCard does not log a same-zone table reposition', () {
      final session = sessionWith([
        CardInstance(instanceId: 'c1', definitionId: 'a', x: 0, y: 0, zIndex: 0, faceUp: true, zone: CardZone.table),
      ]);
      session.moveCard('c1', 0.5, 0.5, actingPlayerId: 'p1');
      expect(session.state.log, isEmpty);
    });

    test('flipCard always names the real card, even one hidden both before and after', () {
      final session = sessionWith([
        CardInstance(
          instanceId: 'c1',
          definitionId: 'a',
          x: 0,
          y: 0,
          zIndex: 0,
          faceUp: false,
          zone: CardZone.hand,
          ownerId: 'p1',
        ),
      ]);
      session.flipCard('c1', actingPlayerId: 'p1');
      expect(session.state.log.single.message, 'Host flipped "A" face up.');
    });

    test('drawCard is always generic', () {
      final session = sessionWith([
        CardInstance(instanceId: 'c1', definitionId: 'a', x: 0, y: 0, zIndex: 0, faceUp: true, zone: CardZone.table),
      ]);
      session.drawCard('c1', ownerId: 'p1');
      expect(session.state.log.single.message, 'Host drew a card.');
    });

    test('drawFromZone is always generic but names the zone', () {
      final session = sessionWith([
        CardInstance(
          instanceId: 'c1',
          definitionId: 'a',
          x: 0,
          y: 0,
          zIndex: 0,
          faceUp: false,
          zone: CardZone.zone,
          zoneId: 'draw_deck',
          ownerId: 'p1',
        ),
      ]);
      session.drawFromZone('draw_deck', zoneOwnerId: 'p1', toOwnerId: 'p1');
      expect(session.state.log.single.message, 'Host drew a card from the Draw Deck.');
    });

    test('shuffleZone is always generic but names the zone', () {
      final session = sessionWith([
        CardInstance(
          instanceId: 'c1',
          definitionId: 'a',
          x: 0,
          y: 0,
          zIndex: 0,
          faceUp: false,
          zone: CardZone.zone,
          zoneId: 'draw_deck',
          ownerId: 'p1',
        ),
        CardInstance(
          instanceId: 'c2',
          definitionId: 'b',
          x: 0,
          y: 0,
          zIndex: 1,
          faceUp: false,
          zone: CardZone.zone,
          zoneId: 'draw_deck',
          ownerId: 'p1',
        ),
      ]);
      session.shuffleZone('draw_deck', zoneOwnerId: 'p1', actingPlayerId: 'p1');
      expect(session.state.log.single.message, 'Host shuffled the Draw Deck.');
    });

    test('shufflePile is always generic', () {
      final session = sessionWith([
        CardInstance(instanceId: 'c1', definitionId: 'a', x: 0, y: 0, zIndex: 0, faceUp: true, zone: CardZone.table),
        CardInstance(
          instanceId: 'c2',
          definitionId: 'b',
          x: 0,
          y: 0,
          zIndex: 1,
          faceUp: true,
          zone: CardZone.table,
          stackParentId: 'c1',
        ),
      ]);
      session.shufflePile('c1', actingPlayerId: 'p1');
      expect(session.state.log.single.message, 'Host shuffled a pile of cards.');
    });

    test('setWidgetValue logs the zone name for a zone-bound counter', () {
      final session = GameSession(
        game: game,
        localPlayerId: 'p1',
        initialState: TableState(
          gameId: 'g1',
          players: _players,
          cards: const [],
          revision: 0,
          widgets: [
            BoardWidgetInstance(
              instanceId: 'w1',
              kind: BoardWidgetKind.simpleCounter,
              x: 0.5,
              y: 0.5,
              zIndex: 0,
              value: 20,
              ownerId: 'p1',
              zoneId: 'life_total',
            ),
          ],
        ),
      );
      session.setWidgetValue('w1', 18, actingPlayerId: 'p1');
      expect(session.state.log.single.message, 'Host set Life Total to 18.');
    });

    test('setWidgetValue logs generically for a free-floating counter', () {
      final session = sessionWith(const []);
      session.createWidget('w1', BoardWidgetKind.simpleCounter, 0.5, 0.5);
      session.setWidgetValue('w1', 5, actingPlayerId: 'p1');
      expect(session.state.log.single.message, 'Host set a counter to 5.');
    });

    test('setWidgetValue does not log for a non-counter widget', () {
      final session = sessionWith(const []);
      session.createWidget('w1', BoardWidgetKind.token, 0.5, 0.5);
      session.setWidgetValue('w1', 5, actingPlayerId: 'p1');
      expect(session.state.log, isEmpty);
    });

    test('attachWidgetToCard names the widget kind and reveals a visible card', () {
      final session = sessionWith([
        CardInstance(instanceId: 'c1', definitionId: 'a', x: 0.4, y: 0.5, zIndex: 0, faceUp: true, zone: CardZone.table),
      ]);
      session.createWidget('w1', BoardWidgetKind.token, 0, 0);
      session.attachWidgetToCard('w1', 'c1', 0.42, 0.53, actingPlayerId: 'p1');
      expect(session.state.log.last.message, 'Host attached a token to "A".');
    });

    test('attachWidgetToCard stays generic for a hidden card', () {
      final session = sessionWith([
        CardInstance(
          instanceId: 'c1',
          definitionId: 'a',
          x: 0,
          y: 0,
          zIndex: 0,
          faceUp: false,
          zone: CardZone.hand,
          ownerId: 'p1',
        ),
      ]);
      session.createWidget('w1', BoardWidgetKind.token, 0, 0);
      session.attachWidgetToCard('w1', 'c1', 0, 0, actingPlayerId: 'p1');
      expect(session.state.log.last.message, 'Host attached a token to a card.');
    });

    test('startSearchZone logs the zone name', () {
      final session = sessionWith(const []);
      session.startSearchZone('draw_deck', zoneOwnerId: 'p1', searcherId: 'p1');
      expect(session.state.log.single.message, 'Host opened a search on the Draw Deck.');
    });

    test('startSearchPile logs generically', () {
      final session = sessionWith([
        CardInstance(instanceId: 'c1', definitionId: 'a', x: 0, y: 0, zIndex: 0, faceUp: true, zone: CardZone.table),
      ]);
      session.startSearchPile('c1', searcherId: 'p1');
      expect(session.state.log.single.message, 'Host opened a search on a pile of cards.');
    });

    test('stopSearch only logs when a search was actually open', () {
      final session = sessionWith(const []);
      session.stopSearch(searcherId: 'p1');
      expect(session.state.log, isEmpty);

      session.startSearchZone('draw_deck', zoneOwnerId: 'p1', searcherId: 'p1');
      session.stopSearch(searcherId: 'p1');
      expect(session.state.log.last.message, 'Host closed their search.');
    });

    test('syncConnectedPlayerIds logs connect/disconnect only for a player whose state changed', () {
      final session = sessionWith(const []);
      // Matches the already-connected initial state -- no log on the first call.
      session.syncConnectedPlayerIds({'p2'});
      expect(session.state.log, isEmpty);

      session.syncConnectedPlayerIds(<String>{});
      expect(session.state.log.single.message, 'Client disconnected.');

      session.syncConnectedPlayerIds({'p2'});
      expect(session.state.log.last.message, 'Client connected.');
    });

    test('syncConnectedPlayerIds never logs for the host', () {
      final session = sessionWith(const []);
      session.syncConnectedPlayerIds(<String>{});
      expect(session.state.log, hasLength(1));
      expect(session.state.log.single.message, contains('Client'));
    });
  });

  group('GameSession.generatePack', () {
    final game = GameDefinition(
      id: 'g1',
      name: 'G',
      sets: const [
        GameSet(
          id: 's1',
          name: 'Booster Set',
          packSettings: [PackSetting(tag: 'Rare', count: 1), PackSetting(tag: 'Common', count: 2)],
        ),
        GameSet(id: 's2', name: 'Plain Set'),
        GameSet(id: 's3', name: 'Empty Set'),
      ],
      cards: [
        const CardDefinition(id: 'r1', cardTitle: 'R1', setId: 's1', types: ['Rare']),
        const CardDefinition(id: 'c1', cardTitle: 'C1', setId: 's1', types: ['Common']),
        const CardDefinition(id: 'c2', cardTitle: 'C2', setId: 's1', types: ['Common']),
        const CardDefinition(id: 'c3', cardTitle: 'C3', setId: 's1', types: ['Common']),
        for (var i = 0; i < 12; i++) CardDefinition(id: 'p2_$i', cardTitle: 'P2_$i', setId: 's2'),
      ],
    );

    GameSession sessionWith() {
      return GameSession(
        game: game,
        localPlayerId: 'p1',
        initialState: const TableState(gameId: 'g1', players: _players, cards: [], revision: 0),
      );
    }

    test('respects a set\'s configured packSettings', () {
      final session = sessionWith();
      session.generatePack('s1', actingPlayerId: 'p1');
      final handCards = session.state.cards;
      expect(handCards, hasLength(3));
      expect(handCards.where((c) => c.definitionId == 'r1'), hasLength(1));
      expect(handCards.where((c) => ['c1', 'c2', 'c3'].contains(c.definitionId)), hasLength(2));
      for (final c in handCards) {
        expect(c.zone, CardZone.hand);
        expect(c.ownerId, 'p1');
        expect(c.faceUp, isTrue);
      }
      // No duplicate CardDefinitions in the pack.
      expect(handCards.map((c) => c.definitionId).toSet().length, handCards.length);
    });

    test('falls back to 10 random cards when packSettings is empty', () {
      final session = sessionWith();
      session.generatePack('s2', actingPlayerId: 'p1');
      expect(session.state.cards, hasLength(10));
      expect(session.state.cards.map((c) => c.definitionId).toSet().length, 10);
    });

    test('a set with zero cards yields an empty pack with no crash', () {
      final session = sessionWith();
      session.generatePack('s3', actingPlayerId: 'p1');
      expect(session.state.cards, isEmpty);
    });

    test('appends a log entry naming the set', () {
      final session = sessionWith();
      session.generatePack('s1', actingPlayerId: 'p1');
      expect(session.state.log.single.message, 'Host generated a pack from the Booster Set set.');
    });

    test('bumps revision', () {
      final session = sessionWith();
      final before = session.state.revision;
      session.generatePack('s1', actingPlayerId: 'p1');
      expect(session.state.revision, before + 1);
    });
  });

  group('GameSession.loadDeckIntoZone', () {
    const cardsWithUnownable = [
      CardDefinition(id: 'a', cardTitle: 'A', colorHex: '#000000'),
      CardDefinition(id: 'b', cardTitle: 'B', colorHex: '#000000'),
      CardDefinition(id: 'u', cardTitle: 'U', colorHex: '#000000', unownable: true),
    ];

    const game = GameDefinition(
      id: 'g1',
      name: 'G',
      cards: cardsWithUnownable,
      zones: [
        ZoneDefinition(id: 'draw_deck', name: 'Draw Deck', dealsBuiltDeck: true),
        ZoneDefinition(
          id: 'location_deck',
          name: 'Location Deck',
          dealsBuiltDeck: true,
          deckType: 'location_deck',
        ),
        ZoneDefinition(id: 'shuffled_deck', name: 'Shuffled Deck', dealsBuiltDeck: true, autoShuffle: true),
        ZoneDefinition(id: 'face_up_deck', name: 'Face Up Deck', dealsBuiltDeck: true, faceUp: true),
      ],
    );

    GameSession sessionWith() {
      return GameSession(
        game: game,
        localPlayerId: 'p1',
        initialState: const TableState(gameId: 'g1', players: _players, cards: [], revision: 0),
      );
    }

    test('mints the target zone\'s own deckType entries, ignoring other subdecks in the same DeckConfig', () {
      final session = sessionWith();
      session.loadDeckIntoZone(
        'draw_deck',
        const DeckConfig(
          gameId: 'g1',
          subdecks: [
            SubDeck(name: 'main_deck', entries: [DeckEntry(definitionId: 'a', quantity: 2)]),
            SubDeck(name: 'location_deck', entries: [DeckEntry(definitionId: 'b', quantity: 5)]),
          ],
        ),
        actingPlayerId: 'p1',
      );
      expect(session.state.cards, hasLength(2));
      expect(session.state.cards.every((c) => c.definitionId == 'a'), isTrue);
      expect(session.state.cards.every((c) => c.zoneId == 'draw_deck'), isTrue);
    });

    test('filters out entries referencing an unknown definitionId without crashing', () {
      final session = sessionWith();
      session.loadDeckIntoZone(
        'draw_deck',
        const DeckConfig(
          gameId: 'g1',
          subdecks: [
            SubDeck(
              name: 'main_deck',
              entries: [
                DeckEntry(definitionId: 'a', quantity: 1),
                DeckEntry(definitionId: 'nonexistent', quantity: 5),
              ],
            ),
          ],
        ),
        actingPlayerId: 'p1',
      );
      expect(session.state.cards, hasLength(1));
      expect(session.state.cards.single.definitionId, 'a');
    });

    test('sets faceUp from the zone definition, defaulting to face-down', () {
      final session = sessionWith();
      const deck = DeckConfig(
        gameId: 'g1',
        subdecks: [SubDeck(name: 'main_deck', entries: [DeckEntry(definitionId: 'a', quantity: 1)])],
      );
      session.loadDeckIntoZone('draw_deck', deck, actingPlayerId: 'p1');
      expect(session.state.cards.single.faceUp, isFalse);

      session.loadDeckIntoZone('face_up_deck', deck, actingPlayerId: 'p1');
      final faceUpCard = session.state.cards.firstWhere((c) => c.zoneId == 'face_up_deck');
      expect(faceUpCard.faceUp, isTrue);
    });

    test('sets ownerId to the acting player', () {
      final session = sessionWith();
      session.loadDeckIntoZone(
        'draw_deck',
        const DeckConfig(
          gameId: 'g1',
          subdecks: [SubDeck(name: 'main_deck', entries: [DeckEntry(definitionId: 'a', quantity: 1)])],
        ),
        actingPlayerId: 'p2',
      );
      expect(session.state.cards.single.ownerId, 'p2');
    });

    test('carries unownable through from the CardDefinition', () {
      final session = sessionWith();
      session.loadDeckIntoZone(
        'draw_deck',
        const DeckConfig(
          gameId: 'g1',
          subdecks: [SubDeck(name: 'main_deck', entries: [DeckEntry(definitionId: 'u', quantity: 1)])],
        ),
        actingPlayerId: 'p1',
      );
      expect(session.state.cards.single.unownable, isTrue);
    });

    test('deals the full set of cards even when autoShuffle is set on the zone', () {
      final session = sessionWith();
      session.loadDeckIntoZone(
        'shuffled_deck',
        const DeckConfig(
          gameId: 'g1',
          subdecks: [
            SubDeck(
              name: 'main_deck',
              entries: [DeckEntry(definitionId: 'a', quantity: 3), DeckEntry(definitionId: 'b', quantity: 2)],
            ),
          ],
        ),
        actingPlayerId: 'p1',
      );
      expect(session.state.cards.where((c) => c.definitionId == 'a'), hasLength(3));
      expect(session.state.cards.where((c) => c.definitionId == 'b'), hasLength(2));
    });

    test('appends a log entry naming the zone', () {
      final session = sessionWith();
      session.loadDeckIntoZone(
        'draw_deck',
        const DeckConfig(
          gameId: 'g1',
          subdecks: [SubDeck(name: 'main_deck', entries: [DeckEntry(definitionId: 'a', quantity: 1)])],
        ),
        actingPlayerId: 'p1',
      );
      expect(session.state.log.single.message, 'Host loaded a deck into the Draw Deck.');
    });

    test('bumps revision', () {
      final session = sessionWith();
      final before = session.state.revision;
      session.loadDeckIntoZone(
        'draw_deck',
        const DeckConfig(
          gameId: 'g1',
          subdecks: [SubDeck(name: 'main_deck', entries: [DeckEntry(definitionId: 'a', quantity: 1)])],
        ),
        actingPlayerId: 'p1',
      );
      expect(session.state.revision, before + 1);
    });
  });

  group('GameSession deck widget synthetic zones', () {
    const game = GameDefinition(
      id: 'g1',
      name: 'G',
      cards: _cards,
      zones: [
        ZoneDefinition(id: 'main_deck', name: 'Main Deck', dealsBuiltDeck: true, visibleToAll: true),
      ],
    );

    GameSession sessionWith(List<CardInstance> cards, {List<BoardWidgetInstance> widgets = const []}) {
      return GameSession(
        game: game,
        localPlayerId: 'p1',
        initialState: TableState(gameId: 'g1', players: _players, cards: cards, revision: 0, widgets: widgets),
      );
    }

    test('returnToZone against a synthetic id resolves without throwing, using the real zone', () {
      final syntheticId = buildDeckWidgetZoneId(widgetInstanceId: 'dw1', realZoneId: 'main_deck');
      final session = sessionWith([
        CardInstance(
          instanceId: 'c1',
          definitionId: 'a',
          x: 0,
          y: 0,
          zIndex: 0,
          faceUp: true,
          zone: CardZone.hand,
          ownerId: 'p1',
        ),
      ], widgets: [
        BoardWidgetInstance(instanceId: 'dw1', kind: BoardWidgetKind.deckBuilder, x: 0.5, y: 0.5, zIndex: 0, ownerId: 'p1'),
      ]);
      expect(
        () => session.returnToZone('c1', syntheticId, zoneOwnerId: 'p1', actingPlayerId: 'p1'),
        returnsNormally,
      );
      final moved = session.state.cards.single;
      expect(moved.zone, CardZone.zone);
      expect(moved.zoneId, syntheticId);
      expect(moved.ownerId, 'p1');
    });

    test('startSearchZone against a synthetic id resolves without throwing', () {
      final syntheticId = buildDeckWidgetZoneId(widgetInstanceId: 'dw1', realZoneId: 'main_deck');
      final session = sessionWith(const []);
      expect(
        () => session.startSearchZone(syntheticId, zoneOwnerId: 'p1', searcherId: 'p1'),
        returnsNormally,
      );
    });

    test('a card moved into a synthetic sub-zone under a visibleToAll real zone still logs generically', () {
      final syntheticId = buildDeckWidgetZoneId(widgetInstanceId: 'dw1', realZoneId: 'main_deck');
      final session = sessionWith([
        CardInstance(
          instanceId: 'c1',
          definitionId: 'a',
          x: 0,
          y: 0,
          zIndex: 0,
          faceUp: true,
          zone: CardZone.hand,
          ownerId: 'p1',
        ),
      ]);
      session.returnToZone('c1', syntheticId, zoneOwnerId: 'p1', actingPlayerId: 'p1');
      expect(session.state.log.single.message, isNot(contains('"A"')));
    });
  });
}
