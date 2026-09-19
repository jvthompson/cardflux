import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:uuid/uuid.dart';

import '../../data/game_definition_file_ops.dart';
import '../../data/image_path_resolver.dart';
import '../../models/card_back_definition.dart';
import '../../models/card_definition.dart';
import '../../models/game_set.dart';
import '../../models/tag_group.dart';
import 'card_back_widget.dart';
import 'card_detail_panel.dart';
import 'card_face_widget.dart' show CardFaceWidget, cardHeight, cardWidth, orientationQuarterTurns;
import 'card_sort_menu.dart';
import 'multi_select_filter_menu.dart';

const Uuid _uuid = Uuid();

/// The Game Definition Editor's "Card View" tab: three resizable columns --
/// a set/type-filtered pool grid (mirroring the Deck Editor's), a large live
/// [_CardPreviewPane], and the [CardDetailPanel] form -- for whichever card
/// is selected in the pool. A controlled component -- the parent
/// `GameDefinitionEditorScreen` owns `cards`; edits/additions/deletions are
/// all reported via [onCardsChanged].
class CardViewTab extends StatefulWidget {
  const CardViewTab({
    super.key,
    required this.folderPath,
    required this.cards,
    required this.sets,
    required this.tagGroups,
    required this.cardBacks,
    required this.fileOps,
    required this.onCardsChanged,
  });

  final String folderPath;
  final List<CardDefinition> cards;
  final List<GameSet> sets;
  final List<TagGroup> tagGroups;
  final List<CardBackDefinition> cardBacks;
  final GameDefinitionFileOps fileOps;
  final ValueChanged<List<CardDefinition>> onCardsChanged;

  @override
  State<CardViewTab> createState() => _CardViewTabState();
}

class _CardViewTabState extends State<CardViewTab> with AutomaticKeepAliveClientMixin<CardViewTab> {
  static const double _minColumnFraction = 0.15;
  static const double _dividerSize = 9;

  @override
  bool get wantKeepAlive => true;

  String? _selectedCardId;

  /// Whether Tab/Shift+Tab should navigate to the previous/next card even
  /// while focus is inside a [CardDetailPanel] text field (overriding normal
  /// field-to-field Tab traversal there) -- session-only UI state, off by
  /// default so the form's fields keep their normal Tab behavior until the
  /// user opts in. See [_handleKeyEvent].
  bool _tabNavigatesInsideForm = false;

  /// Receives every key event while focus is anywhere in this tab (pool
  /// grid, preview, or -- since it wraps the form too -- the detail form),
  /// via [_handleKeyEvent]. [_PoolTile] explicitly requests focus here on
  /// tap (its `GestureDetector` isn't otherwise focusable), so Tab works
  /// immediately after clicking a card.
  final FocusNode _cardNavFocusNode = FocusNode(debugLabel: 'CardViewTab');

  /// Wraps just the [CardDetailPanel] column so [_handleKeyEvent] can tell,
  /// via [FocusScopeNode.hasFocus], whether the current focus is inside the
  /// form -- distinct from being in the pool/preview area.
  final FocusScopeNode _formFocusScope = FocusScopeNode(debugLabel: 'CardDetailFormScope');

  /// Fraction of the available width given to the pool grid column; the
  /// preview column gets [_previewFraction]; the form column gets whatever's
  /// left (`1 - _poolFraction - _previewFraction`). Defaults to 50/25/25.
  /// Kept as fractions (not pixel widths) so the 3-way split scales cleanly
  /// with the window instead of needing separate min/max pixel clamping per
  /// column against the current window width.
  double _poolFraction = 0.5;
  double _previewFraction = 0.25;

  /// Per-group set of which of that group's tags are actively selected to
  /// narrow the pool, keyed by [TagGroup.id] -- every group starts empty
  /// ("no restriction from this group"; see [_isTagVisible]). Unlike the Deck
  /// Editor's equivalent, this can't be `late final` assigned once and left
  /// alone: tag groups are editable live in the Game Settings tab while this
  /// tab's `State` stays alive in the background, so stale entries for
  /// deleted groups/tags need pruning (see [didUpdateWidget]).
  late final Map<String, Set<String>> _selectedTagsByGroup = {
    for (final g in widget.tagGroups) g.id: <String>{},
  };

  /// Per-group set of which of that group's tags are actively excluded --
  /// starts empty (nothing excluded) for every group. Mutually exclusive
  /// with [_selectedTagsByGroup] per tag: toggling a tag into one clears it
  /// from the other (see the `onToggle`/`onToggleExclude` handlers in
  /// [_buildTagGroupFilterBars]), so a tag is never both at once.
  late final Map<String, Set<String>> _excludedTagsByGroup = {
    for (final g in widget.tagGroups) g.id: <String>{},
  };

  /// Which of [CardViewTab.sets] are actively selected to narrow the pool --
  /// starts empty ("no restriction"; see [_isSetVisible]), same rationale/
  /// sync as [_selectedTagsByGroup].
  late final Set<String> _selectedSetIds = {};

  /// Current sort key for the pool -- `null` means the original/unsorted
  /// pool order. See [sortCardDefinitions].
  String? _sortKey;

  /// Ids of [TagGroup]s whose tag-chip section is currently collapsed on the
  /// [CardDetailPanel] form -- session-level UI state only (not part of the
  /// saved game definition). An absent/unknown id simply means "visible," so
  /// no seeding or [didUpdateWidget] sync is required for correctness.
  final Set<String> _hiddenDetailTagGroupIds = {};

  @override
  void didUpdateWidget(CardViewTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _hiddenDetailTagGroupIds.removeWhere((id) => !widget.tagGroups.any((g) => g.id == id));
    final groupIds = widget.tagGroups.map((g) => g.id).toSet();
    _selectedTagsByGroup.removeWhere((id, _) => !groupIds.contains(id));
    _excludedTagsByGroup.removeWhere((id, _) => !groupIds.contains(id));
    for (final group in widget.tagGroups) {
      final tagIds = group.tags.toSet();
      _selectedTagsByGroup.putIfAbsent(group.id, () => <String>{}).retainWhere(tagIds.contains);
      _excludedTagsByGroup.putIfAbsent(group.id, () => <String>{}).retainWhere(tagIds.contains);
    }
    final setIds = widget.sets.map((s) => s.id).toSet();
    _selectedSetIds.retainWhere(setIds.contains);
    if (_sortKey != null &&
        _sortKey != cardSortBySet &&
        _sortKey != cardSortByName &&
        !groupIds.contains(_sortKey)) {
      _sortKey = null;
    }
  }

  /// Every currently-excluded tag across every group, combined -- a card
  /// with *any* one of these is hidden outright, regardless of any group's
  /// selection (see [_isTagVisible]).
  Set<String> get _allExcludedTags => {for (final s in _excludedTagsByGroup.values) ...s};

  /// A card is tag-visible unless some group's active selection excludes it.
  /// Within a group, a non-empty selection means OR: the card must have at
  /// least one of that group's selected tags -- *unless* the card has none of
  /// that group's tags at all, in which case that group doesn't apply to it
  /// (mirrors [CardDefinition.types]' own "a card with no tags in a given
  /// group is never hidden by that group's filter" contract). Across groups
  /// this is AND: every group with an active selection must independently be
  /// satisfied. An empty selection in every group means no filtering at all.
  bool _isTagVisible(CardDefinition card) {
    if (card.types.any(_allExcludedTags.contains)) return false;
    for (final group in widget.tagGroups) {
      final selected = _selectedTagsByGroup[group.id];
      if (selected == null || selected.isEmpty) continue;
      final cardTagsInGroup = card.types.where(group.tags.contains);
      if (cardTagsInGroup.isEmpty) continue;
      if (!cardTagsInGroup.any(selected.contains)) return false;
    }
    return true;
  }

  bool _isSetVisible(CardDefinition card) =>
      _selectedSetIds.isEmpty || card.setId == null || _selectedSetIds.contains(card.setId);

  List<CardDefinition> get _visibleCards => sortCardDefinitions(
        widget.cards.where((c) => _isSetVisible(c) && _isTagVisible(c)).toList(),
        sortKey: _sortKey,
        sets: widget.sets,
        tagGroups: widget.tagGroups,
      );

  @override
  void dispose() {
    _cardNavFocusNode.dispose();
    _formFocusScope.dispose();
    super.dispose();
  }

  /// Index of [_selectedCardId] within [_visibleCards], or `-1` if nothing's
  /// selected (or the selected card is filtered out of view).
  int get _selectedVisibleIndex {
    if (_selectedCardId == null) return -1;
    return _visibleCards.indexWhere((c) => c.id == _selectedCardId);
  }

  bool get _canGoPrevious => _selectedVisibleIndex > 0;

  bool get _canGoNext {
    final visible = _visibleCards;
    if (visible.isEmpty) return false;
    final index = _selectedVisibleIndex;
    return index == -1 || index < visible.length - 1;
  }

  void _selectPreviousCard() {
    final visible = _visibleCards;
    final index = _selectedVisibleIndex;
    if (index > 0) setState(() => _selectedCardId = visible[index - 1].id);
  }

  void _selectNextCard() {
    final visible = _visibleCards;
    if (visible.isEmpty) return;
    final index = _selectedVisibleIndex;
    final nextIndex = index == -1 ? 0 : index + 1;
    if (nextIndex < visible.length) setState(() => _selectedCardId = visible[nextIndex].id);
  }

  /// Handles Tab/Shift+Tab for [_cardNavFocusNode]. Lets every other key
  /// event, and Tab while focus is inside the form with
  /// [_tabNavigatesInsideForm] off, fall through to Flutter's normal
  /// traversal handling -- otherwise selects the previous/next visible card.
  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.tab) {
      return KeyEventResult.ignored;
    }
    if (_formFocusScope.hasFocus && !_tabNavigatesInsideForm) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isShiftPressed) {
      _selectPreviousCard();
    } else {
      _selectNextCard();
    }
    return KeyEventResult.handled;
  }

  void _addBlankCard() {
    // With no explicit Set filter narrowing the pool, fall back to the
    // game's full set list -- so a single-set game still auto-assigns new
    // cards to that one set by default.
    final candidateSetIds = _selectedSetIds.isNotEmpty ? _selectedSetIds : widget.sets.map((s) => s.id).toSet();
    final setId = candidateSetIds.length == 1 ? candidateSetIds.first : null;
    final newCard = CardDefinition(id: _uuid.v4(), cardTitle: 'New Card', setId: setId);
    widget.onCardsChanged([...widget.cards, newCard]);
    setState(() => _selectedCardId = newCard.id);
  }

  void _updateCard(CardDefinition updated) {
    widget.onCardsChanged([for (final c in widget.cards) if (c.id == updated.id) updated else c]);
  }

  /// Resets every Set/Type filter to fully permissive -- nothing selected,
  /// nothing excluded, i.e. "no filtering in effect" (see [_isTagVisible],
  /// [_isSetVisible]). Doesn't touch [_sortKey]: sorting is independent of
  /// filtering.
  void _clearFilters() {
    setState(() {
      _selectedSetIds.clear();
      for (final group in widget.tagGroups) {
        _selectedTagsByGroup[group.id]!.clear();
        _excludedTagsByGroup[group.id]!.clear();
      }
    });
  }

  /// The Set filter (always first) plus one filter button per non-empty tag
  /// group, combined into a single wrapped row with a "Clear Filters" action
  /// above it -- empty (no widget) for a game with neither [CardViewTab.sets]
  /// nor [CardViewTab.tagGroups] declared. Mirrors the Deck Editor's
  /// `_buildFilterBar`.
  Widget _buildFilterBar() {
    final nonEmptyGroups = widget.tagGroups.where((g) => g.tags.isNotEmpty).toList();
    if (widget.sets.isEmpty && nonEmptyGroups.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextButton.icon(
            onPressed: _clearFilters,
            icon: const Icon(Icons.filter_alt_off, size: 18),
            label: const Text('Clear Filters'),
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (widget.sets.isNotEmpty)
                MultiSelectFilterMenu(
                  label: 'Set',
                  options: [
                    for (final set in widget.sets)
                      (id: set.id, name: '${set.name} (${widget.cards.where((c) => c.setId == set.id).length})'),
                  ],
                  selectedIds: _selectedSetIds,
                  onToggle: (id, selected) => setState(() {
                    if (selected) {
                      _selectedSetIds.add(id);
                    } else {
                      _selectedSetIds.remove(id);
                    }
                  }),
                ),
              for (final group in nonEmptyGroups)
                MultiSelectFilterMenu(
                  label: group.name,
                  options: [for (final tag in group.tags) (id: tag, name: tag)],
                  selectedIds: _selectedTagsByGroup[group.id]!,
                  excludedIds: _excludedTagsByGroup[group.id]!,
                  onToggle: (id, selected) => setState(() {
                    final included = _selectedTagsByGroup[group.id]!;
                    if (selected) {
                      included.add(id);
                      _excludedTagsByGroup[group.id]!.remove(id);
                    } else {
                      included.remove(id);
                    }
                  }),
                  onToggleExclude: (id, excluded) => setState(() {
                    final excludedSet = _excludedTagsByGroup[group.id]!;
                    if (excluded) {
                      excludedSet.add(id);
                      _selectedTagsByGroup[group.id]!.remove(id);
                    } else {
                      excludedSet.remove(id);
                    }
                  }),
                ),
              CardSortMenu(
                options: [
                  if (widget.sets.isNotEmpty) (id: cardSortBySet, name: 'Set'),
                  (id: cardSortByName, name: 'Name (A-Z)'),
                  for (final group in nonEmptyGroups) (id: group.id, name: group.name),
                ],
                selectedId: _sortKey,
                onSelected: (id) => setState(() => _sortKey = id),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _deleteCard(String id) {
    widget.onCardsChanged(widget.cards.where((c) => c.id != id).toList());
    if (_selectedCardId == id) setState(() => _selectedCardId = null);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    final visibleCards = _visibleCards;
    CardDefinition? selected;
    for (final c in widget.cards) {
      if (c.id == _selectedCardId) {
        selected = c;
        break;
      }
    }

    return Focus(
      focusNode: _cardNavFocusNode,
      onKeyEvent: _handleKeyEvent,
      child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildFilterBar(),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final card = selected;
              final usableWidth = constraints.maxWidth - _dividerSize * 2;
              final poolWidth = usableWidth * _poolFraction;
              final previewWidth = usableWidth * _previewFraction;
              final formWidth = usableWidth - poolWidth - previewWidth;
              return Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    width: poolWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
                          child: Align(
                            alignment: Alignment.centerLeft,
                            child: OutlinedButton.icon(
                              icon: const Icon(Icons.add),
                              label: const Text('Add Card'),
                              onPressed: _addBlankCard,
                            ),
                          ),
                        ),
                        Expanded(
                          child: GridView.builder(
                            padding: const EdgeInsets.all(12),
                            gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: cardWidth + 24,
                              mainAxisExtent: cardHeight + 28,
                              crossAxisSpacing: 12,
                              mainAxisSpacing: 12,
                            ),
                            itemCount: visibleCards.length,
                            itemBuilder: (context, index) {
                              final card = visibleCards[index];
                              return _PoolTile(
                                folderPath: widget.folderPath,
                                card: card,
                                selected: card.id == _selectedCardId,
                                onTap: () {
                                  _cardNavFocusNode.requestFocus();
                                  setState(() => _selectedCardId = card.id);
                                },
                              );
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  _VerticalSplitHandle(
                    onDragDelta: (dx) => setState(() {
                      final df = dx / usableWidth;
                      final minDf = _minColumnFraction - _poolFraction;
                      final maxDf = _previewFraction - _minColumnFraction;
                      final clamped = df.clamp(minDf, maxDf);
                      _poolFraction += clamped;
                      _previewFraction -= clamped;
                    }),
                  ),
                  SizedBox(
                    width: previewWidth,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: card == null
                              ? Center(
                                  child: Text(
                                    'Select a card to preview',
                                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                                  ))
                              : _CardPreviewPane(folderPath: widget.folderPath, card: card, cardBacks: widget.cardBacks),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.chevron_left),
                                  label: const Text('Previous Card'),
                                  onPressed: _canGoPrevious ? _selectPreviousCard : null,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  icon: const Icon(Icons.chevron_right),
                                  label: const Text('Next Card'),
                                  onPressed: _canGoNext ? _selectNextCard : null,
                                ),
                              ),
                            ],
                          ),
                        ),
                        SwitchListTile(
                          dense: true,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                          title: const Text('Tab navigates inside form fields', style: TextStyle(fontSize: 12)),
                          value: _tabNavigatesInsideForm,
                          onChanged: (v) => setState(() => _tabNavigatesInsideForm = v),
                        ),
                      ],
                    ),
                  ),
                  _VerticalSplitHandle(
                    onDragDelta: (dx) => setState(() {
                      final df = dx / usableWidth;
                      final formFraction = 1 - _poolFraction - _previewFraction;
                      final minDf = _minColumnFraction - _previewFraction;
                      final maxDf = formFraction - _minColumnFraction;
                      final clamped = df.clamp(minDf, maxDf);
                      _previewFraction += clamped;
                    }),
                  ),
                  SizedBox(
                    width: formWidth,
                    child: FocusScope(
                      node: _formFocusScope,
                      child: card == null
                          ? Center(
                              child: Text(
                                'Select a card to edit',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ))
                          : CardDetailPanel(
                              key: ValueKey(card.id),
                              folderPath: widget.folderPath,
                              card: card,
                              tagGroups: widget.tagGroups,
                              allSets: widget.sets,
                              allCardBacks: widget.cardBacks,
                              fileOps: widget.fileOps,
                              onChanged: _updateCard,
                              onDelete: () => _deleteCard(card.id),
                              hiddenTagGroupIds: _hiddenDetailTagGroupIds,
                              onToggleTagGroupVisibility: (groupId, visible) => setState(() {
                                if (visible) {
                                  _hiddenDetailTagGroupIds.remove(groupId);
                                } else {
                                  _hiddenDetailTagGroupIds.add(groupId);
                                }
                              }),
                            ),
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ],
      ),
    );
  }
}

/// A draggable divider between two of this tab's three columns (pool grid /
/// preview / form) -- a thin visible line centered inside a wider invisible
/// hit area (so it's easy to grab without needing pixel-perfect precision),
/// reporting the raw horizontal drag delta so the caller can adjust and
/// clamp the adjacent columns' widths.
class _VerticalSplitHandle extends StatelessWidget {
  const _VerticalSplitHandle({required this.onDragDelta});

  final ValueChanged<double> onDragDelta;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) => onDragDelta(details.delta.dx),
        child: const SizedBox(width: 9, child: Center(child: VerticalDivider(width: 1))),
      ),
    );
  }
}

class _PoolTile extends StatelessWidget {
  const _PoolTile({required this.folderPath, required this.card, required this.selected, required this.onTap});

  final String folderPath;
  final CardDefinition card;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final resolved = resolvedImagePathForDisplay(folderPath, bareImagePath: card.imagePath, setId: card.setId);
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: selected ? Colors.blue : Colors.transparent, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            padding: const EdgeInsets.all(2),
            child: RotatedBox(
              quarterTurns: orientationQuarterTurns(card.orientation),
              child: SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: CardFaceWidget(definition: card.copyWith(imagePath: resolved)),
              ),
            ),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: cardWidth,
            child: Text(
              card.cardTitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}

/// A large, live preview of the card currently being edited -- fills the
/// middle column so image/color/suit/rank/orientation changes made in the
/// [CardDetailPanel] form column are visually confirmed immediately. Shows
/// just the front when [card] uses this game's plain default back
/// (`cardBackId == null`), or front and back side by side (each
/// independently rotated by its own orientation -- see
/// `resolveCardBackImagePath`) whenever it doesn't, so a custom back is
/// always visible while authoring it.
///
/// Unlike [CardFaceWidget] (used for grid tiles, which forces every card
/// into a uniform 70x100 box via `BoxFit.cover`, cropping mismatched
/// aspect ratios), this shows the actual image uncropped at its own aspect
/// ratio, scaled up to fill as much of the preview area as possible.
class _CardPreviewPane extends StatelessWidget {
  const _CardPreviewPane({required this.folderPath, required this.card, required this.cardBacks});

  final String folderPath;
  final CardDefinition card;
  final List<CardBackDefinition> cardBacks;

  Widget _labeled(BuildContext context, String label, Widget pane) {
    return Column(
      children: [
        Expanded(child: pane),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
      ],
    );
  }

  Widget _frontPane() {
    final resolved = resolvedImagePathForDisplay(folderPath, bareImagePath: card.imagePath, setId: card.setId);
    return Container(
      color: Colors.black.withValues(alpha: 0.05),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      child: RotatedBox(
        quarterTurns: orientationQuarterTurns(card.orientation),
        child: resolved == null
            ? FittedBox(
                fit: BoxFit.contain,
                child: SizedBox(width: cardWidth, height: cardHeight, child: CardFaceWidget(definition: card)),
              )
            : Image.file(
                File(resolved),
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => FittedBox(
                  fit: BoxFit.contain,
                  child: SizedBox(width: cardWidth, height: cardHeight, child: CardFaceWidget(definition: card)),
                ),
              ),
      ),
    );
  }

  Widget _backPane() {
    // The "Unique" lookup needs an absolute path to check disk existence,
    // but `card.imagePath` is still bare here (pre-load, editor-only) --
    // build a display-only resolved copy, never persisted, just for this.
    final resolvedFront = resolvedImagePathForDisplay(folderPath, bareImagePath: card.imagePath, setId: card.setId);
    final displayCard = resolvedFront == null ? card : card.copyWith(imagePath: resolvedFront);
    final orientation = resolveCardBackImagePath(cardBacks: cardBacks, card: displayCard).orientation;
    return Container(
      color: Colors.black.withValues(alpha: 0.05),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(20),
      child: RotatedBox(
        quarterTurns: orientationQuarterTurns(orientation),
        child: FittedBox(
          fit: BoxFit.contain,
          child: SizedBox(
            width: cardWidth,
            height: cardHeight,
            child: CardBackWidget(cardBacks: cardBacks, card: displayCard),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (card.cardBackId == null) return _frontPane();
    return Row(
      children: [
        Expanded(child: _labeled(context, 'Front', _frontPane())),
        const SizedBox(width: 12),
        Expanded(child: _labeled(context, 'Back', _backPane())),
      ],
    );
  }
}
