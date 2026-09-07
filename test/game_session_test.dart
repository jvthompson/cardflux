import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_deck/game/game_session.dart';
import 'package:flutter_deck/models/card_definition.dart';
import 'package:flutter_deck/models/card_instance.dart';
import 'package:flutter_deck/models/deck_config.dart';
import 'package:flutter_deck/models/game_definition.dart';

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
}
