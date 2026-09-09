import 'package:flutter/material.dart';
import 'package:flutter_deck/ui/widgets/multi_select_filter_menu.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: Align(child: child)));

void main() {
  testWidgets('opens without a layout exception for a single-column list', (tester) async {
    final options = [for (var i = 0; i < 5; i++) (id: 'id$i', name: 'Type $i')];
    await tester.pumpWidget(
      _wrap(
        MultiSelectFilterMenu(label: 'Type', options: options, selectedIds: options.map((o) => o.id).toSet(), onToggle: (_, _) {}),
      ),
    );

    await tester.tap(find.text('Type (5)'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Type 0'), findsOneWidget);
  });

  testWidgets('opens without a layout exception once the list splits into multiple columns', (tester) async {
    // 25 options spans two columns at the 20-per-column split, which is
    // exactly the shape that triggered a RenderFlex "unbounded width"
    // exception when MenuItemButton (which lays itself out with an internal
    // Expanded label) was nested in a plain Column instead of one wrapped in
    // IntrinsicWidth + CrossAxisAlignment.stretch.
    final options = [for (var i = 0; i < 25; i++) (id: 'id$i', name: 'Type $i')];
    await tester.pumpWidget(
      _wrap(
        MultiSelectFilterMenu(label: 'Type', options: options, selectedIds: options.map((o) => o.id).toSet(), onToggle: (_, _) {}),
      ),
    );

    await tester.tap(find.text('Type (25)'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Type 0'), findsOneWidget);
    expect(find.text('Type 24'), findsOneWidget);
  });

  testWidgets('toggling an option calls onToggle without throwing', (tester) async {
    final options = [for (var i = 0; i < 25; i++) (id: 'id$i', name: 'Type $i')];
    final selected = options.map((o) => o.id).toSet();
    String? toggledId;
    bool? toggledValue;

    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) => MultiSelectFilterMenu(
            label: 'Type',
            options: options,
            selectedIds: selected,
            onToggle: (id, value) => setState(() {
              toggledId = id;
              toggledValue = value;
              if (value) {
                selected.add(id);
              } else {
                selected.remove(id);
              }
            }),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Type (25)'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Type 0'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(toggledId, 'id0');
    expect(toggledValue, isFalse);
  });

  testWidgets('Select All / Deselect All is the first item and toggles every option', (tester) async {
    final options = [for (var i = 0; i < 5; i++) (id: 'id$i', name: 'Type $i')];
    final selected = <String>{options[0].id};

    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) => MultiSelectFilterMenu(
            label: 'Type',
            options: options,
            selectedIds: selected,
            onToggle: (id, value) => setState(() {
              if (value) {
                selected.add(id);
              } else {
                selected.remove(id);
              }
            }),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Type (1)'));
    await tester.pumpAndSettle();

    // Not everything is selected yet, so the control offers "Select All",
    // and it appears above every actual option.
    expect(find.text('Select All'), findsOneWidget);
    final selectAllTop = tester.getTopLeft(find.text('Select All')).dy;
    final firstOptionTop = tester.getTopLeft(find.text('Type 0')).dy;
    expect(selectAllTop, lessThan(firstOptionTop));

    await tester.tap(find.text('Select All'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(selected, options.map((o) => o.id).toSet());
    expect(find.text('Type (5)'), findsOneWidget);
    expect(find.text('Deselect All'), findsOneWidget);

    await tester.tap(find.text('Deselect All'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(selected, isEmpty);
    expect(find.text('Type (0)'), findsOneWidget);
  });

  testWidgets('omitting excludedIds/onToggleExclude renders no exclude column', (tester) async {
    final options = [for (var i = 0; i < 3; i++) (id: 'id$i', name: 'Type $i')];
    await tester.pumpWidget(
      _wrap(
        MultiSelectFilterMenu(label: 'Type', options: options, selectedIds: options.map((o) => o.id).toSet(), onToggle: (_, _) {}),
      ),
    );

    await tester.tap(find.text('Type (3)'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byTooltip('Exclude cards with this tag'), findsNothing);
    expect(find.byTooltip('Stop excluding'), findsNothing);
  });

  testWidgets('exclude toggle fires onToggleExclude and clearing it restores independence from include', (tester) async {
    final options = [for (var i = 0; i < 3; i++) (id: 'id$i', name: 'Type $i')];
    final included = options.map((o) => o.id).toSet();
    final excluded = <String>{};

    await tester.pumpWidget(
      _wrap(
        StatefulBuilder(
          builder: (context, setState) => MultiSelectFilterMenu(
            label: 'Type',
            options: options,
            selectedIds: included,
            excludedIds: excluded,
            // Mutual exclusivity lives in the caller's handlers, mirroring
            // how CardViewTab/DeckEditorScreen wire this up for real.
            onToggle: (id, value) => setState(() {
              if (value) {
                included.add(id);
                excluded.remove(id);
              } else {
                included.remove(id);
              }
            }),
            onToggleExclude: (id, value) => setState(() {
              if (value) {
                excluded.add(id);
                included.remove(id);
              } else {
                excluded.remove(id);
              }
            }),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Type (3)'));
    await tester.pumpAndSettle();

    // Exclude "Type 1": its checkmark should clear as a side effect.
    await tester.tap(find.byTooltip('Exclude cards with this tag').at(1));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(excluded, {'id1'});
    expect(included, {'id0', 'id2'});
    expect(find.text('Type (2)'), findsOneWidget);

    // Re-including "Type 1" (via its row/checkbox) should clear the exclude.
    await tester.tap(find.text('Type 1'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(excluded, isEmpty);
    expect(included, {'id0', 'id1', 'id2'});
  });
}
