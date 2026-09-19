import 'package:flutter_deck/models/card_definition.dart';
import 'package:flutter_deck/models/game_set.dart';
import 'package:flutter_deck/models/tag_group.dart';
import 'package:flutter_deck/ui/widgets/card_sort_menu.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const setA = GameSet(id: 'set_a', name: 'Set A');
  const setB = GameSet(id: 'set_b', name: 'Set B');
  const raceGroup = TagGroup(id: 'race', name: 'Race', tags: ['Dunadan', 'Elf', 'Hobbit']);

  const dunadanCard = CardDefinition(id: 'd', cardTitle: 'Dunadan Card', setId: 'set_b', types: ['Dunadan']);
  const elfCard = CardDefinition(id: 'e', cardTitle: 'Elf Card', setId: 'set_a', types: ['Elf']);
  const noRaceCard = CardDefinition(id: 'n', cardTitle: 'No Race Card', setId: 'set_a', types: ['Resource']);
  const noSetCard = CardDefinition(id: 'u', cardTitle: 'No Set Card');

  final cards = [noSetCard, dunadanCard, noRaceCard, elfCard];

  test('null sortKey returns the list unchanged', () {
    final result = sortCardDefinitions(cards, sortKey: null, sets: [setA, setB], tagGroups: [raceGroup]);
    expect(result, same(cards));
  });

  test('cardSortByName orders alphabetically', () {
    final result = sortCardDefinitions(cards, sortKey: cardSortByName, sets: [setA, setB], tagGroups: [raceGroup]);
    expect(result.map((c) => c.cardTitle).toList(), [
      'Dunadan Card',
      'Elf Card',
      'No Race Card',
      'No Set Card',
    ]);
  });

  test('cardSortBySet follows the sets list order, unset cards last', () {
    final result = sortCardDefinitions(cards, sortKey: cardSortBySet, sets: [setA, setB], tagGroups: [raceGroup]);
    expect(result.map((c) => c.id).toList(), ['e', 'n', 'd', 'u']);
  });

  test('sorting by a tag group id follows that group\'s authored tag order, non-matching cards last', () {
    final result = sortCardDefinitions(cards, sortKey: raceGroup.id, sets: [setA, setB], tagGroups: [raceGroup]);
    // Dunadan (index 0) < Elf (index 1) < cards with no Race tag (tied, broken by name).
    expect(result.map((c) => c.id).toList(), ['d', 'e', 'n', 'u']);
  });
}
