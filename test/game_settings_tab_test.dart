import 'package:flutter/material.dart';
import 'package:flutter_deck/data/game_definition_file_ops.dart';
import 'package:flutter_deck/models/tag_group.dart';
import 'package:flutter_deck/ui/widgets/game_settings_tab.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders nested group/tag reorderable lists without a layout exception', (tester) async {
    var groups = [
      const TagGroup(id: 'g1', name: 'Card Type', tags: ['Character', 'Item', 'Action']),
      const TagGroup(id: 'g2', name: 'Ink Color', tags: ['Amber', 'Ruby']),
    ];

    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) => GameSettingsTab(
            folderPath: '.',
            name: 'Test Game',
            cardBackImagePath: null,
            tagGroups: groups,
            fileOps: GameDefinitionFileOps(),
            onNameChanged: (_) {},
            onCardBackImagePathChanged: (_) {},
            onTagGroupsChanged: (v) => setState(() => groups = v),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Card Type'), findsOneWidget);
    expect(find.text('Ink Color'), findsOneWidget);
    // Groups start collapsed -- their tags aren't in the tree yet.
    expect(find.text('Character'), findsNothing);
    expect(find.text('Amber'), findsNothing);

    await tester.tap(find.text('Card Type'));
    await tester.pumpAndSettle();
    // Expanding "Card Type" pushed "Ink Color" out of the default test
    // viewport -- scroll it into view (it's inside the tab's own ListView)
    // before tapping it.
    await tester.ensureVisible(find.text('Ink Color'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Ink Color'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Character'), findsOneWidget);
    expect(find.text('Amber'), findsOneWidget);
  });

  testWidgets('adding a tag group, adding a tag, and removing a tag all work', (tester) async {
    var groups = <TagGroup>[];

    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) => GameSettingsTab(
            folderPath: '.',
            name: 'Test Game',
            cardBackImagePath: null,
            tagGroups: groups,
            fileOps: GameDefinitionFileOps(),
            onNameChanged: (_) {},
            onCardBackImagePathChanged: (_) {},
            onTagGroupsChanged: (v) => setState(() => groups = v),
          ),
        ),
      ),
    );

    // Add a new tag group.
    await tester.enterText(find.widgetWithText(TextField, 'New tag group'), 'Card Type');
    await tester.tap(find.widgetWithIcon(IconButton, Icons.add).first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(groups, hasLength(1));
    expect(groups.single.name, 'Card Type');
    expect(groups.single.tags, isEmpty);

    // New groups start collapsed -- expand it before reaching its "New tag"
    // field.
    await tester.tap(find.text('Card Type'));
    await tester.pumpAndSettle();

    // Add a tag to that group. Its own "Add Tag" button renders before the
    // top-level "Add Tag Group" button (inside the groups ReorderableListView,
    // which appears earlier in the tree), so it's `.first` here.
    await tester.enterText(find.widgetWithText(TextField, 'New tag'), 'Character');
    await tester.tap(find.widgetWithIcon(IconButton, Icons.add).first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(groups.single.tags, ['Character']);
    expect(find.text('Character'), findsOneWidget);

    // Remove that tag.
    await tester.tap(find.widgetWithIcon(IconButton, Icons.close));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(groups.single.tags, isEmpty);
  });

  testWidgets('renaming a group reports the update without losing its tags', (tester) async {
    var groups = [const TagGroup(id: 'g1', name: 'default', tags: ['Character', 'Item'])];

    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) => GameSettingsTab(
            folderPath: '.',
            name: 'Test Game',
            cardBackImagePath: null,
            tagGroups: groups,
            fileOps: GameDefinitionFileOps(),
            onNameChanged: (_) {},
            onCardBackImagePathChanged: (_) {},
            onTagGroupsChanged: (v) => setState(() => groups = v),
          ),
        ),
      ),
    );

    // Expand the group (starts collapsed) before reaching its name field.
    await tester.tap(find.text('default'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Group Name'), 'Card Type');
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(groups.single.id, 'g1');
    expect(groups.single.name, 'Card Type');
    expect(groups.single.tags, ['Character', 'Item']);
  });
}
