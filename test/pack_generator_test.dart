import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_deck/game/pack_generator.dart';
import 'package:flutter_deck/models/card_definition.dart';
import 'package:flutter_deck/models/pack_setting.dart';

List<CardDefinition> _cards(List<(String, List<String>)> idsAndTags) => [
  for (final (id, tags) in idsAndTags) CardDefinition(id: id, cardTitle: id, types: tags),
];

void main() {
  group('selectPackCards', () {
    test('no settings: up to defaultPackCardCount random distinct cards', () {
      final pool = _cards([for (var i = 0; i < 15; i++) ('c$i', const [])]);
      final result = selectPackCards(pool, random: Random(1));
      expect(result.length, defaultPackCardCount);
      expect(result.map((c) => c.id).toSet().length, defaultPackCardCount);
    });

    test('no settings: a pool smaller than defaultPackCardCount returns everything, once', () {
      final pool = _cards([('c1', const []), ('c2', const [])]);
      final result = selectPackCards(pool, random: Random(1));
      expect(result.length, 2);
      expect(result.map((c) => c.id).toSet(), {'c1', 'c2'});
    });

    test('a single tag setting returns exactly count matching cards', () {
      final pool = _cards([
        ('r1', ['Rare']),
        ('r2', ['Rare']),
        ('r3', ['Rare']),
        ('c1', ['Common']),
      ]);
      final result = selectPackCards(
        pool,
        packSettings: const [PackSetting(tag: 'Rare', count: 2)],
        random: Random(1),
      );
      expect(result.length, 2);
      expect(result.every((c) => c.types.contains('Rare')), isTrue);
    });

    test('shortfall: takes whatever is available, no error, no duplicate padding', () {
      final pool = _cards([('r1', ['Rare'])]);
      final result = selectPackCards(
        pool,
        packSettings: const [PackSetting(tag: 'Rare', count: 5)],
        random: Random(1),
      );
      expect(result.length, 1);
      expect(result.single.id, 'r1');
    });

    test('a card matching two configured tags is never double-counted', () {
      final pool = _cards([
        ('both', ['Rare', 'Foil']),
      ]);
      final result = selectPackCards(
        pool,
        packSettings: const [PackSetting(tag: 'Rare', count: 1), PackSetting(tag: 'Foil', count: 1)],
        random: Random(1),
      );
      expect(result.length, 1);
      expect(result.single.id, 'both');
    });

    test('a tag with zero matching cards contributes 0 without affecting other settings', () {
      final pool = _cards([('c1', ['Common'])]);
      final result = selectPackCards(
        pool,
        packSettings: const [PackSetting(tag: 'Rare', count: 3), PackSetting(tag: 'Common', count: 1)],
        random: Random(1),
      );
      expect(result.length, 1);
      expect(result.single.id, 'c1');
    });

    test('empty setCards returns an empty list regardless of settings', () {
      final result = selectPackCards(
        const [],
        packSettings: const [PackSetting(tag: 'Rare', count: 3)],
        random: Random(1),
      );
      expect(result, isEmpty);
    });

    test('a seeded Random gives the same result across repeated calls', () {
      final pool = _cards([for (var i = 0; i < 20; i++) ('c$i', const [])]);
      final a = selectPackCards(pool, random: Random(42));
      final b = selectPackCards(pool, random: Random(42));
      expect(a.map((c) => c.id).toList(), b.map((c) => c.id).toList());
    });
  });
}
