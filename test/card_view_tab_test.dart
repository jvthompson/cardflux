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
            cardBacks: const [],
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
            cardBacks: const [],
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

  testWidgets('hiding a tag group on the detail form persists across card selection and tab switches', (tester) async {
    // The default test surface is narrow enough that CardDetailPanel's image
    // row overflows once a card is actually selected (a pre-existing layout
    // issue unrelated to this test) -- widen it so that doesn't mask the
    // behavior under test.
    tester.view.physicalSize = const Size(2000, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    const cardTypeGroup = TagGroup(id: 'card_type', name: 'Card Type', tags: ['Character', 'Resource']);
    const adrazar = CardDefinition(id: 'adrazar', cardTitle: 'Adrazar', types: ['Character']);
    const boromir = CardDefinition(id: 'boromir', cardTitle: 'Boromir', types: ['Character']);

    Widget buildTab() => CardViewTab(
          folderPath: '.',
          cards: const [adrazar, boromir],
          sets: const [],
          tagGroups: const [cardTypeGroup],
          cardBacks: const [],
          fileOps: GameDefinitionFileOps(),
          onCardsChanged: (_) {},
        );

    await tester.pumpWidget(
      MaterialApp(
        home: DefaultTabController(
          length: 2,
          child: Scaffold(
            body: Column(
              children: [
                const TabBar(tabs: [Tab(text: 'Other'), Tab(text: 'Card View')]),
                Expanded(
                  child: TabBarView(
                    children: [const Center(child: Text('Other tab')), buildTab()],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // TabBarView starts on the first tab -- switch to Card View before
    // interacting with it.
    await tester.tap(find.text('Card View'));
    await tester.pumpAndSettle();

    // Select Adrazar and confirm the group's header and chips both show.
    await tester.tap(find.text('Adrazar').first, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Card Type'), findsOneWidget);
    expect(find.text('Character'), findsWidgets);
    expect(find.text('Hide'), findsOneWidget);

    // Hide the group -- its chips disappear, but the toggle (now "Show")
    // stays reachable.
    await tester.tap(find.text('Hide'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Card Type'), findsOneWidget);
    expect(find.text('Show'), findsOneWidget);
    expect(find.text('Hide'), findsNothing);

    // Switch to a different card, then back -- CardDetailPanel is torn down
    // and rebuilt each time (keyed by card id), so this proves the hidden
    // state lives above it, not inside it.
    await tester.tap(find.text('Boromir').first, warnIfMissed: false);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Adrazar').first, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Show'), findsOneWidget);
    expect(find.text('Hide'), findsNothing);

    // Switch to the other tab and back -- CardViewTab's own State must
    // survive via AutomaticKeepAliveClientMixin.
    await tester.tap(find.text('Other'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Card View'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Show'), findsOneWidget);
    expect(find.text('Hide'), findsNothing);
  });
}
