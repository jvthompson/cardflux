import 'package:flutter/material.dart';
import 'package:flutter_deck/data/game_definition_file_ops.dart';
import 'package:flutter_deck/models/card_definition.dart';
import 'package:flutter_deck/models/tag_group.dart';
import 'package:flutter_deck/ui/widgets/card_view_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Regression test for a real bug: a card with tags spanning multiple tag
  // groups (e.g. a METW Character card that's also a Dunadan and a Scout)
  // was being hidden as soon as ANY one of its groups had that particular
  // tag deselected, even though a different group's filter still matched.
  // Tag-group filters must OR together across every selected tag globally,
  // not AND independently per group.
  testWidgets('a card with tags in two groups stays visible if only one of its tags is selected', (tester) async {
    const cardTypeGroup = TagGroup(id: 'card_type', name: 'Card Type', tags: ['Character', 'Resource']);
    const raceGroup = TagGroup(id: 'race', name: 'Race', tags: ['Dunadan', 'Elf']);
    const adrazar = CardDefinition(id: 'adrazar', cardTitle: 'Adrazar', types: ['Character', 'Dunadan']);
    const untagged = CardDefinition(id: 'blank', cardTitle: 'Untagged Card');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardViewTab(
            folderPath: '.',
            cards: const [adrazar, untagged],
            sets: const [],
            tagGroups: const [cardTypeGroup, raceGroup],
            fileOps: GameDefinitionFileOps(),
            onCardsChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Deselect every Race tag (leaving Card Type's "Character" the only tag
    // selected anywhere) via that group's Select All / Deselect All toggle.
    await tester.tap(find.text('Race (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deselect All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Race (0)')); // close the menu
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    // Adrazar has "Dunadan" (deselected in Race) but also "Character"
    // (still selected in Card Type) -- it must still show.
    expect(find.text('Adrazar'), findsWidgets);
    // A card with no tags at all is never hidden by tag filters.
    expect(find.text('Untagged Card'), findsWidgets);

    // Now also deselect Card Type entirely -- with nothing selected in any
    // group, Adrazar (which has tags) must disappear, but the untagged card
    // must still show.
    await tester.tap(find.text('Card Type (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deselect All'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Card Type (0)'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Adrazar'), findsNothing);
    expect(find.text('Untagged Card'), findsWidgets);
  });

  testWidgets('excluding a tag hides a card even though it also has an included tag from another group', (tester) async {
    const cardTypeGroup = TagGroup(id: 'card_type', name: 'Card Type', tags: ['Character', 'Resource']);
    const raceGroup = TagGroup(id: 'race', name: 'Race', tags: ['Dunadan', 'Elf']);
    const adrazar = CardDefinition(id: 'adrazar', cardTitle: 'Adrazar', types: ['Character', 'Dunadan']);
    const untagged = CardDefinition(id: 'blank', cardTitle: 'Untagged Card');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardViewTab(
            folderPath: '.',
            cards: const [adrazar, untagged],
            sets: const [],
            tagGroups: const [cardTypeGroup, raceGroup],
            fileOps: GameDefinitionFileOps(),
            onCardsChanged: (_) {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Everything starts included, so Adrazar shows to begin with.
    expect(find.text('Adrazar'), findsWidgets);

    // Exclude "Dunadan" in the Race group -- Adrazar still has "Character"
    // included in Card Type, but the exclude veto must win regardless.
    await tester.tap(find.text('Race (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Exclude cards with this tag').first); // Dunadan is first
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(10, 10)); // close the menu by tapping outside it
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Adrazar'), findsNothing);
    expect(find.text('Untagged Card'), findsWidgets);
  });
}
