import 'package:flutter_deck/models/card_definition.dart';
import 'package:flutter_deck/ui/widgets/duplicate_card_images_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mergeDuplicateImageCards', () {
    test('merges same-set same-image cards, unioning tags and keeping the first card\'s other fields', () {
      final cards = [
        const CardDefinition(id: 'a', cardTitle: 'A', imagePath: 'x.png', setId: 's1', types: ['Hero']),
        const CardDefinition(id: 'b', cardTitle: 'A (dup)', imagePath: 'x.png', setId: 's1', types: ['Ally', 'Hero']),
      ];

      final result = mergeDuplicateImageCards(cards);

      expect(result, hasLength(1));
      expect(result.single.id, 'a');
      expect(result.single.cardTitle, 'A');
      expect(result.single.types, ['Hero', 'Ally']);
    });

    test('does not merge cards with a null imagePath, even if everything else matches', () {
      final cards = [
        const CardDefinition(id: 'a', cardTitle: 'A', setId: 's1'),
        const CardDefinition(id: 'b', cardTitle: 'B', setId: 's1'),
      ];

      expect(mergeDuplicateImageCards(cards), hasLength(2));
    });

    test('does not merge cards with the same image in different sets', () {
      final cards = [
        const CardDefinition(id: 'a', cardTitle: 'A', imagePath: 'x.png', setId: 's1'),
        const CardDefinition(id: 'b', cardTitle: 'B', imagePath: 'x.png', setId: 's2'),
      ];

      expect(mergeDuplicateImageCards(cards), hasLength(2));
    });

    test('merges same-image cards that both have no set (flat-schema game)', () {
      final cards = [
        const CardDefinition(id: 'a', cardTitle: 'A', imagePath: 'x.png'),
        const CardDefinition(id: 'b', cardTitle: 'B', imagePath: 'x.png'),
      ];

      expect(mergeDuplicateImageCards(cards), hasLength(1));
    });

    test('merges 3+ cards in one group into a single entry with all tags unioned', () {
      final cards = [
        const CardDefinition(id: 'a', cardTitle: 'A', imagePath: 'x.png', setId: 's1', types: ['One']),
        const CardDefinition(id: 'b', cardTitle: 'B', imagePath: 'x.png', setId: 's1', types: ['Two']),
        const CardDefinition(id: 'c', cardTitle: 'C', imagePath: 'x.png', setId: 's1', types: ['One', 'Three']),
      ];

      final result = mergeDuplicateImageCards(cards);

      expect(result, hasLength(1));
      expect(result.single.id, 'a');
      expect(result.single.types, ['One', 'Two', 'Three']);
    });

    test('handles multiple separate duplicate groups plus an untouched card in one pass, preserving order', () {
      final cards = [
        const CardDefinition(id: 'a1', cardTitle: 'A', imagePath: 'a.png', setId: 's1'),
        const CardDefinition(id: 'solo', cardTitle: 'Solo', imagePath: 'solo.png', setId: 's1'),
        const CardDefinition(id: 'a2', cardTitle: 'A (dup)', imagePath: 'a.png', setId: 's1'),
        const CardDefinition(id: 'b1', cardTitle: 'B', imagePath: 'b.png', setId: 's1'),
        const CardDefinition(id: 'b2', cardTitle: 'B (dup)', imagePath: 'b.png', setId: 's1'),
      ];

      final result = mergeDuplicateImageCards(cards);

      expect(result.map((c) => c.id), ['a1', 'solo', 'b1']);
    });

    test('returns cards unchanged (same order, same ids) when there are no duplicates', () {
      final cards = [
        const CardDefinition(id: 'a', cardTitle: 'A', imagePath: 'a.png', setId: 's1'),
        const CardDefinition(id: 'b', cardTitle: 'B', imagePath: 'b.png', setId: 's1'),
      ];

      expect(mergeDuplicateImageCards(cards).map((c) => c.id), ['a', 'b']);
    });
  });
}
