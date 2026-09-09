import 'package:flutter/material.dart';

typedef MultiSelectFilterOption = ({String id, String name});

/// How many options fit in one column of the checklist dropdown before a
/// new column starts -- keeps a long option list (many card types/sets) from
/// turning into one unwieldy tall menu.
const int _maxOptionsPerColumn = 20;

/// A trigger button ("Set", "Type") that opens a checklist-style dropdown of
/// [options], each toggleable without closing the menu, so several options
/// can be flipped in one open/close cycle. Shared by the Deck Editor's and
/// the Game Definition Editor's Card View tab's Set/Type filter bars.
class MultiSelectFilterMenu extends StatelessWidget {
  const MultiSelectFilterMenu({
    super.key,
    required this.label,
    required this.options,
    required this.selectedIds,
    required this.onToggle,
    this.excludedIds,
    this.onToggleExclude,
  });

  final String label;
  final List<MultiSelectFilterOption> options;
  final Set<String> selectedIds;
  final void Function(String id, bool selected) onToggle;

  /// Which options are actively excluded (hidden even if included elsewhere)
  /// -- see [_ExcludeToggle]. Leaving this and [onToggleExclude] both null
  /// (the Set filter's usage) renders the plain single-checkbox row as
  /// before; both must be provided together to enable the red-X column.
  final Set<String>? excludedIds;
  final void Function(String id, bool excluded)? onToggleExclude;

  /// Toggles every option to [select] via repeated [onToggle] calls -- one
  /// per option that actually needs to change. Callers' `onToggle` handlers
  /// each do their own `setState`, but since these all run synchronously in
  /// one button press, Flutter coalesces them into a single rebuild.
  void _toggleAll(bool select) {
    for (final option in options) {
      if (selectedIds.contains(option.id) != select) onToggle(option.id, select);
    }
  }

  /// The plain single-checkbox row used when exclude support isn't enabled
  /// (the Set filter's usage) -- `MenuItemButton`'s own hover/focus chrome,
  /// with the whole row as one tap target.
  Widget _buildPlainOptionRow(MultiSelectFilterOption option) {
    return MenuItemButton(
      closeOnActivate: false,
      leadingIcon: IgnorePointer(
        child: Checkbox(value: selectedIds.contains(option.id), onChanged: (_) {}),
      ),
      onPressed: () => onToggle(option.id, !selectedIds.contains(option.id)),
      child: Text(option.name),
    );
  }

  /// The include+exclude row used when [excludedIds]/[onToggleExclude] are
  /// provided. Deliberately not a `MenuItemButton` -- that widget's whole
  /// area is one `onPressed` target, and nesting two independently-tappable
  /// checkboxes inside it would risk the same kind of subtle MenuAnchor
  /// layout/gesture issue this file has already hit once. A plain `InkWell`
  /// with real `Checkbox`/`IconButton` children is a simpler, well-trodden
  /// pattern (the same one `ListTile` + a trailing `IconButton` relies on)
  /// and isn't wired to `MenuController` at all, so it can't accidentally
  /// close the menu -- no `closeOnActivate` equivalent needed.
  Widget _buildExcludableOptionRow(MultiSelectFilterOption option) {
    final included = selectedIds.contains(option.id);
    final excluded = excludedIds!.contains(option.id);
    return InkWell(
      onTap: () => onToggle(option.id, !included),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            IgnorePointer(child: Checkbox(value: included, onChanged: (_) {})),
            Expanded(child: Text(option.name)),
            _ExcludeToggle(excluded: excluded, onChanged: (v) => onToggleExclude!(option.id, v)),
          ],
        ),
      ),
    );
  }

  Widget _buildOptionRow(MultiSelectFilterOption option) =>
      excludedIds != null && onToggleExclude != null ? _buildExcludableOptionRow(option) : _buildPlainOptionRow(option);

  @override
  Widget build(BuildContext context) {
    final selectedCount = options.where((o) => selectedIds.contains(o.id)).length;
    final allSelected = options.isNotEmpty && selectedCount == options.length;
    final columns = <List<MultiSelectFilterOption>>[
      for (var i = 0; i < options.length; i += _maxOptionsPerColumn)
        options.sublist(i, i + _maxOptionsPerColumn > options.length ? options.length : i + _maxOptionsPerColumn),
    ];
    return MenuAnchor(
      menuChildren: [
        MenuItemButton(
          closeOnActivate: false,
          leadingIcon: IgnorePointer(
            child: Checkbox(value: allSelected, onChanged: (_) {}),
          ),
          onPressed: () => _toggleAll(!allSelected),
          child: Text(allSelected ? 'Deselect All' : 'Select All'),
        ),
        const Divider(height: 1),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var i = 0; i < columns.length; i++) ...[
              if (i > 0) const SizedBox(width: 16),
              // MenuItemButton lays itself out with an internal Expanded label,
              // which needs a bounded width from its parent. A bare Column
              // doesn't provide one (non-stretched children of a Column get
              // unbounded width), so wrap each column in IntrinsicWidth +
              // stretch -- the same trick MenuAnchor's own panel already uses
              // for a normal single-column menu, just applied per column here.
              IntrinsicWidth(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [for (final option in columns[i]) _buildOptionRow(option)],
                ),
              ),
            ],
          ],
        ),
      ],
      builder: (context, controller, child) {
        return OutlinedButton(
          onPressed: () => controller.isOpen ? controller.close() : controller.open(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('$label ($selectedCount)'),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        );
      },
    );
  }
}

/// A checkbox-sized toggle that shows an empty outline when off and a red X
/// when on -- "actively hide cards with this tag," as opposed to the plain
/// include [Checkbox]'s checkmark ("show cards with this tag").
class _ExcludeToggle extends StatelessWidget {
  const _ExcludeToggle({required this.excluded, required this.onChanged});

  final bool excluded;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 40,
      child: IconButton(
        padding: EdgeInsets.zero,
        tooltip: excluded ? 'Stop excluding' : 'Exclude cards with this tag',
        icon: Icon(
          excluded ? Icons.close : Icons.check_box_outline_blank,
          color: excluded ? Colors.red : Colors.black38,
          size: 18,
        ),
        onPressed: () => onChanged(!excluded),
      ),
    );
  }
}
