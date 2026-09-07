import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_deck/game/game_session.dart';
import 'package:flutter_deck/models/card_definition.dart';
import 'package:flutter_deck/models/card_instance.dart';
import 'package:flutter_deck/models/deck_config.dart';
import 'package:flutter_deck/models/game_definition.dart';
import 'package:flutter_deck/models/player.dart';

const _game = GameDefinition(
  id: 'g1',
  name: 'Test Game',
  cards: [
    CardDefinition(id: 'a', cardTitle: 'A', colorHex: '#000000'),
    CardDefinition(id: 'b', cardTitle: 'B', colorHex: '#000000'),
  ],
);

void main() {
  group('GameSession.dealDeck', () {
    test('deals one instance per DeckEntry quantity into a single face-down pile', () {
      final deckConfig = DeckConfig(
        gameId: 'g1',
        entries: const [DeckEntry(definitionId: 'a', quantity: 3), DeckEntry(definitionId: 'b', quantity: 1)],
      );
      final session = GameSession.dealDeck(game: _game, deckConfig: deckConfig, localPlayerId: 'p1');

      expect(session.state.cards, hasLength(4));
      for (final card in session.state.cards) {
        expect(card.zone, CardZone.drawPile);
        expect(card.faceUp, isFalse);
      }
      // Star topology: exactly one root with no parent, the rest anchored to it.
      final roots = session.state.cards.where((c) => c.stackParentId == null);
      expect(roots, hasLength(1));
      final rootId = roots.single.instanceId;
      for (final card in session.state.cards) {
        if (card.instanceId != rootId) expect(card.stackParentId, rootId);
      }
    });

    test('skips entries referencing an unknown definitionId', () {
      final deckConfig = DeckConfig(
        gameId: 'g1',
        entries: const [DeckEntry(definitionId: 'a', quantity: 1), DeckEntry(definitionId: 'nonexistent', quantity: 5)],
      );
      final session = GameSession.dealDeck(game: _game, deckConfig: deckConfig, localPlayerId: 'p1');
      expect(session.state.cards, hasLength(1));
      expect(session.state.cards.single.definitionId, 'a');
    });
  });

  group('GameSession.localSandbox', () {
    test('deals exactly one instance per game card, matching DeckConfig.full', () {
      final session = GameSession.localSandbox(game: _game, localPlayerId: 'p1');
      expect(session.state.cards, hasLength(2));
      expect(session.state.cards.map((c) => c.definitionId).toSet(), {'a', 'b'});
    });
  });

  group('GameSession.dealPlayerDecks', () {
    test('deals each owner into their own independently-rooted face-down stack', () {
      final session = GameSession.dealPlayerDecks(
        game: _game,
        deckConfigsByPlayerId: {
          'p1': const DeckConfig(gameId: 'g1', entries: [DeckEntry(definitionId: 'a', quantity: 2)]),
          'p2': const DeckConfig(gameId: 'g1', entries: [DeckEntry(definitionId: 'b', quantity: 3)]),
        },
        players: const [
          PlayerInfo(id: 'p1', name: 'Host', role: PlayerRole.host),
          PlayerInfo(id: 'p2', name: 'Client', role: PlayerRole.client),
        ],
        localPlayerId: 'p1',
      );

      expect(session.state.cards, hasLength(5));
      for (final card in session.state.cards) {
        expect(card.zone, CardZone.drawPile);
        expect(card.faceUp, isFalse);
      }

      final p1Cards = session.state.cards.where((c) => c.ownerId == 'p1').toList();
      final p2Cards = session.state.cards.where((c) => c.ownerId == 'p2').toList();
      expect(p1Cards, hasLength(2));
      expect(p2Cards, hasLength(3));

      // Each owner forms their own separate star topology -- one root per
      // owner, never chained to the other owner's cards.
      final p1Roots = p1Cards.where((c) => c.stackParentId == null);
      final p2Roots = p2Cards.where((c) => c.stackParentId == null);
      expect(p1Roots, hasLength(1));
      expect(p2Roots, hasLength(1));
      for (final card in p1Cards) {
        if (card.instanceId != p1Roots.single.instanceId) expect(card.stackParentId, p1Roots.single.instanceId);
      }
      for (final card in p2Cards) {
        if (card.instanceId != p2Roots.single.instanceId) expect(card.stackParentId, p2Roots.single.instanceId);
      }
    });

    test('skips entries referencing an unknown definitionId', () {
      final session = GameSession.dealPlayerDecks(
        game: _game,
        deckConfigsByPlayerId: {
          'p1': const DeckConfig(
            gameId: 'g1',
            entries: [DeckEntry(definitionId: 'a', quantity: 1), DeckEntry(definitionId: 'nonexistent', quantity: 5)],
          ),
        },
        players: const [PlayerInfo(id: 'p1', name: 'Host', role: PlayerRole.host)],
        localPlayerId: 'p1',
      );
      expect(session.state.cards, hasLength(1));
      expect(session.state.cards.single.definitionId, 'a');
    });
  });

  group('GameSession.dealFixedDecks', () {
    const players = [PlayerInfo(id: 'p1', name: 'Host', role: PlayerRole.host)];

    test('a deck with empty entries defaults to one of every game card, named and unowned', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: [
          CardDefinition(id: 'a', cardTitle: 'A', colorHex: '#000000'),
          CardDefinition(id: 'b', cardTitle: 'B', colorHex: '#000000'),
        ],
        deckMode: GameDeckMode.fixedDeck,
        fixedDecks: [FixedDeckDefinition(name: 'Deck')],
      );
      final session = GameSession.dealFixedDecks(game: game, players: players, localPlayerId: 'p1');

      expect(session.state.cards, hasLength(2));
      expect(session.state.cards.map((c) => c.definitionId).toSet(), {'a', 'b'});
      for (final card in session.state.cards) {
        expect(card.zone, CardZone.drawPile);
        expect(card.faceUp, isFalse);
        expect(card.ownerId, isNull);
      }
      final roots = session.state.cards.where((c) => c.stackParentId == null);
      expect(roots, hasLength(1));
      expect(session.state.fixedDeckNames, {roots.single.instanceId: 'Deck'});
    });

    test('multiple named decks land in separate stacks with their own names', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: [
          CardDefinition(id: 'a', cardTitle: 'A', colorHex: '#000000'),
          CardDefinition(id: 'b', cardTitle: 'B', colorHex: '#000000'),
        ],
        deckMode: GameDeckMode.fixedDeck,
        fixedDecks: [
          FixedDeckDefinition(name: 'Main Deck', entries: [DeckEntry(definitionId: 'a', quantity: 2)]),
          FixedDeckDefinition(name: 'Fate Deck', entries: [DeckEntry(definitionId: 'b', quantity: 3)]),
        ],
      );
      final session = GameSession.dealFixedDecks(game: game, players: players, localPlayerId: 'p1');

      expect(session.state.cards, hasLength(5));
      final mainCards = session.state.cards.where((c) => c.definitionId == 'a').toList();
      final fateCards = session.state.cards.where((c) => c.definitionId == 'b').toList();
      expect(mainCards, hasLength(2));
      expect(fateCards, hasLength(3));

      final mainRoot = mainCards.firstWhere((c) => c.stackParentId == null);
      final fateRoot = fateCards.firstWhere((c) => c.stackParentId == null);
      for (final c in mainCards) {
        if (c.instanceId != mainRoot.instanceId) expect(c.stackParentId, mainRoot.instanceId);
      }
      for (final c in fateCards) {
        if (c.instanceId != fateRoot.instanceId) expect(c.stackParentId, fateRoot.instanceId);
      }
      expect(session.state.fixedDeckNames, {
        mainRoot.instanceId: 'Main Deck',
        fateRoot.instanceId: 'Fate Deck',
      });
      // Positioned differently so the two piles don't overlap on the table.
      expect(mainRoot.y, isNot(fateRoot.y));
    });

    test('skips entries referencing an unknown definitionId', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: [CardDefinition(id: 'a', cardTitle: 'A', colorHex: '#000000')],
        deckMode: GameDeckMode.fixedDeck,
        fixedDecks: [
          FixedDeckDefinition(
            name: 'Deck',
            entries: [DeckEntry(definitionId: 'a', quantity: 1), DeckEntry(definitionId: 'nonexistent', quantity: 5)],
          ),
        ],
      );
      final session = GameSession.dealFixedDecks(game: game, players: players, localPlayerId: 'p1');
      expect(session.state.cards, hasLength(1));
      expect(session.state.cards.single.definitionId, 'a');
    });
  });

  group('GameSession.localSandbox with a fixedDeck game', () {
    test('deals via dealFixedDecks instead of the full-pool shared pile', () {
      const game = GameDefinition(
        id: 'g1',
        name: 'G',
        cards: [
          CardDefinition(id: 'a', cardTitle: 'A', colorHex: '#000000'),
          CardDefinition(id: 'b', cardTitle: 'B', colorHex: '#000000'),
        ],
        deckMode: GameDeckMode.fixedDeck,
        fixedDecks: [FixedDeckDefinition(name: 'Deck')],
      );
      final session = GameSession.localSandbox(game: game, localPlayerId: 'p1');
      expect(session.state.cards, hasLength(2));
      expect(session.state.fixedDeckNames.values, ['Deck']);
    });
  });
}
