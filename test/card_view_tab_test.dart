import 'package:flutter/material.dart';
import 'package:flutter_deck/data/game_definition_file_ops.dart';
import 'package:flutter_deck/models/card_definition.dart';
import 'package:flutter_deck/models/tag_group.dart';
import 'package:flutter_deck/ui/widgets/card_view_tab.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // Filters start cleared (nothing selected anywhere) and show everything.
  // Selecting a tag in one group narrows the pool to cards having a tag from
  // that group (OR within the group); selecting a tag in a *different* group
  // narrows further (AND across groups) -- except for a card that has none
  // of that group's tags at all, which that group's filter doesn't apply to.
  testWidgets('tag filters start cleared, OR within a group, AND across groups', (tester) async {
    const cardTypeGroup = TagGroup(id: 'card_type', name: 'Card Type', tags: ['Character', 'Resource']);
    const raceGroup = TagGroup(id: 'race', name: 'Race', tags: ['Dunadan', 'Elf']);
    const adrazar = CardDefinition(id: 'adrazar', cardTitle: 'Adrazar', types: ['Character', 'Dunadan']);
    const merry = CardDefinition(id: 'merry', cardTitle: 'Merry', types: ['Character', 'Elf']);
    const untagged = CardDefinition(id: 'blank', cardTitle: 'Untagged Card');

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CardViewTab(
            folderPath: '.',
            cards: const [adrazar, merry, untagged],
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

    // Nothing selected anywhere -- everything shows, and the buttons read
    // "(0)" to reflect that no restriction is active.
    expect(find.text('Card Type (0)'), findsOneWidget);
    expect(find.text('Race (0)'), findsOneWidget);
    expect(find.text('Adrazar'), findsWidgets);
    expect(find.text('Merry'), findsWidgets);
    expect(find.text('Untagged Card'), findsWidgets);

    // Select "Dunadan" in Race -- only cards with a Race tag are now subject
    // to this filter; Adrazar (Dunadan) stays, Merry (Elf) is hidden, and the
    // untagged card (no Race tag at all) is exempt from this group's filter.
    await tester.tap(find.text('Race (0)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dunadan'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Race (1)')); // close the menu
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Adrazar'), findsWidgets);
    expect(find.text('Merry'), findsNothing);
    expect(find.text('Untagged Card'), findsWidgets);

    // Also select "Elf" in Race (OR within the group) -- Merry comes back.
    await tester.tap(find.text('Race (1)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Elf'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Race (2)'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Adrazar'), findsWidgets);
    expect(find.text('Merry'), findsWidgets);

    // Now also select "Resource" in Card Type (AND across groups) -- neither
    // Adrazar nor Merry has a Resource tag, so both drop out even though
    // Race still matches; the untagged card is exempt from both groups.
    await tester.tap(find.text('Card Type (0)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Resource'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Card Type (1)'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Adrazar'), findsNothing);
    expect(find.text('Merry'), findsNothing);
    expect(find.text('Untagged Card'), findsWidgets);

    // "Clear Filters" restores the cleared, show-everything state.
    await tester.tap(find.text('Clear Filters'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Card Type (0)'), findsOneWidget);
    expect(find.text('Race (0)'), findsOneWidget);
    expect(find.text('Adrazar'), findsWidgets);
    expect(find.text('Merry'), findsWidgets);
    expect(find.text('Untagged Card'), findsWidgets);
  });

  testWidgets('excluding a tag hides a card even with no inclusion filter active', (tester) async {
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

    // No filters are active yet, so Adrazar shows to begin with.
    expect(find.text('Adrazar'), findsWidgets);

    // Exclude "Dunadan" in the Race group -- no group has an active
    // *inclusion* selection, but the exclude veto is independent and wins
    // regardless.
    await tester.tap(find.text('Race (0)'));
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
