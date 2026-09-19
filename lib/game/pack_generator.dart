import 'dart:math';

import '../models/card_definition.dart';
import '../models/pack_setting.dart';

/// Pack size used when a set has no [PackSetting]s configured -- see
/// [selectPackCards].
const int defaultPackCardCount = 10;

/// Picks a random, non-duplicate assortment of [CardDefinition]s from
/// [setCards] according to [packSettings] (each a `{tag, count}` pair --
/// see [PackSetting]): for every setting, up to [PackSetting.count] random
/// cards from [setCards] matching that tag (via [CardDefinition.types])
/// that haven't already been picked for this pack under an earlier setting
/// are added -- so a card matching more than one configured tag is never
/// double-counted, and the result never contains two copies of the same
/// [CardDefinition]. If a tag's pool (after excluding already-picked cards)
/// has fewer than [PackSetting.count] candidates, all of them are taken --
/// no error, no padding.
///
/// If [packSettings] is empty, ignores tags entirely and returns up to
/// [defaultPackCardCount] random cards from [setCards].
///
/// [random] is injectable for deterministic tests; omitted means a fresh,
/// non-seeded `Random()`.
List<CardDefinition> selectPackCards(
  List<CardDefinition> setCards, {
  List<PackSetting> packSettings = const [],
  Random? random,
}) {
  final rng = random ?? Random();
  final picked = <CardDefinition>[];
  final pickedIds = <String>{};

  void takeRandom(List<CardDefinition> pool, int count) {
    final shuffled = [...pool]..shuffle(rng);
    for (final card in shuffled.take(count)) {
      if (pickedIds.add(card.id)) picked.add(card);
    }
  }

  if (packSettings.isEmpty) {
    takeRandom(setCards, defaultPackCardCount);
    return picked;
  }

  for (final setting in packSettings) {
    final pool = setCards.where((c) => !pickedIds.contains(c.id) && c.types.contains(setting.tag)).toList();
    takeRandom(pool, setting.count);
  }
  return picked;
}
