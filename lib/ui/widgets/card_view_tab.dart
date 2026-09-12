import 'dart:io';

import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/game_definition_file_ops.dart';
import '../../data/image_path_resolver.dart';
import '../../models/card_definition.dart';
import '../../models/game_set.dart';
import '../../models/tag_group.dart';
import 'card_detail_panel.dart';
import 'card_face_widget.dart' show CardFaceWidget, cardHeight, cardWidth, orientationQuarterTurns;
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
    required this.fileOps,
    required this.onCardsChanged,
  });

  final String folderPath;
  final List<CardDefinition> cards;
  final List<GameSet> sets;
  final List<TagGroup> tagGroups;
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

  /// Fraction of the available width given to the pool grid column; the
  /// preview column gets [_previewFraction]; the form column gets whatever's
  /// left (`1 - _poolFraction - _previewFraction`). Defaults to 50/25/25.
  /// Kept as fractions (not pixel widths) so the 3-way split scales cleanly
  /// with the window instead of needing separate min/max pixel clamping per
  /// column against the current window width.
  double _poolFraction = 0.5;
  double _previewFraction = 0.25;

  /// Per-group set of which of that group's tags currently show in the pool,
  /// keyed by [TagGroup.id] -- every tag starts selected. Unlike the Deck
  /// Editor's equivalent, this can't be `late final`: tag groups are editable
  /// live in the Game Settings tab while this tab's `State` stays alive in
  /// the background, so newly added groups/tags need to default to selected
  /// too (see [didUpdateWidget]).
  late final Map<String, Set<String>> _selectedTagsByGroup = {
    for (final g in widget.tagGroups) g.id: g.tags.toSet(),
  };

  /// Per-group set of which of that group's tags are actively excluded --
  /// starts empty (nothing excluded) for every group. Mutually exclusive
  /// with [_selectedTagsByGroup] per tag: toggling a tag into one clears it
  /// from the other (see the `onToggle`/`onToggleExclude` handlers in
  /// [_buildTagGroupFilterBars]), so a tag is never both at once.
  late final Map<String, Set<String>> _excludedTagsByGroup = {
    for (final g in widget.tagGroups) g.id: <String>{},
  };

  /// Which of [CardViewTab.sets] currently show in the pool -- every set
  /// starts selected, same rationale/sync as [_selectedTagsByGroup].
  late final Set<String> _selectedSetIds = widget.sets.map((s) => s.id).toSet();

  /// Ids of [TagGroup]s whose tag-chip section is currently collapsed on the
  /// [CardDetailPanel] form -- session-level UI state only (not part of the
  /// saved game definition). An absent/unknown id simply means "visible," so
  /// no seeding or [didUpdateWidget] sync is required for correctness.
  final Set<String> _hiddenDetailTagGroupIds = {};

  @override
  void didUpdateWidget(CardViewTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    _hiddenDetailTagGroupIds.removeWhere((id) => !widget.tagGroups.any((g) => g.id == id));
    for (final group in widget.tagGroups) {
      final selected = _selectedTagsByGroup[group.id];
      if (selected == null) {
        _selectedTagsByGroup[group.id] = group.tags.toSet();
      } else {
        TagGroup? oldGroup;
        for (final g in oldWidget.tagGroups) {
          if (g.id == group.id) {
            oldGroup = g;
            break;
          }
        }
        for (final tag in group.tags) {
          if (oldGroup == null || !oldGroup.tags.contains(tag)) selected.add(tag);
        }
      }
      _excludedTagsByGroup.putIfAbsent(group.id, () => <String>{});
    }
    for (final set in widget.sets) {
      if (!oldWidget.sets.any((s) => s.id == set.id)) _selectedSetIds.add(set.id);
    }
  }

  /// Every currently-selected tag across every group, combined -- a card is
  /// tag-visible if it has *any* one of these, regardless of which group
  /// that tag or the card's other tags belong to. Groups only partition the
  /// filter *buttons*; they don't each independently gate a card, since a
  /// card commonly has tags spanning several groups at once (e.g. a
  /// Character card that's also a Dunadan and a Scout) and requiring it to
  /// match every group separately would hide it as soon as any one group's
  /// selection didn't happen to include one of its tags.
  Set<String> get _allSelectedTags => {for (final s in _selectedTagsByGroup.values) ...s};

  /// Every currently-excluded tag across every group, combined -- a card
  /// with *any* one of these is hidden outright, taking priority over
  /// [_allSelectedTags] (see [_isTagVisible]).
  Set<String> get _allExcludedTags => {for (final s in _excludedTagsByGroup.values) ...s};

  bool _isTagVisible(CardDefinition card) {
    if (card.types.any(_allExcludedTags.contains)) return false;
    return widget.tagGroups.isEmpty || card.types.isEmpty || card.types.any(_allSelectedTags.contains);
  }

  bool _isSetVisible(CardDefinition card) =>
      widget.sets.isEmpty || card.setId == null || _selectedSetIds.contains(card.setId);

  List<CardDefinition> get _visibleCards =>
      widget.cards.where((c) => _isSetVisible(c) && _isTagVisible(c)).toList();

  void _addBlankCard() {
    final setId = _selectedSetIds.length == 1 ? _selectedSetIds.first : null;
    final newCard = CardDefinition(id: _uuid.v4(), cardTitle: 'New Card', setId: setId);
    widget.onCardsChanged([...widget.cards, newCard]);
    setState(() => _selectedCardId = newCard.id);
  }

  void _updateCard(CardDefinition updated) {
    widget.onCardsChanged([for (final c in widget.cards) if (c.id == updated.id) updated else c]);
  }

  /// The set-filter dropdown shown above the pool grid -- empty (no widget)
  /// for a game that declares no [CardViewTab.sets], mirroring the Deck
  /// Editor's `_buildSetFilterBar`.
  Widget _buildSetFilterBar() {
    if (widget.sets.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: MultiSelectFilterMenu(
          label: 'Set',
          options: [for (final set in widget.sets) (id: set.id, name: set.name)],
          selectedIds: _selectedSetIds,
          onToggle: (id, selected) => setState(() {
            if (selected) {
              _selectedSetIds.add(id);
            } else {
              _selectedSetIds.remove(id);
            }
          }),
        ),
      ),
    );
  }

  /// One filter button per non-empty tag group, wrapped so any number of
  /// groups flows onto further lines -- empty (no widget) for a game that
  /// declares no [CardViewTab.tagGroups], mirroring the Deck Editor's
  /// `_buildTagGroupFilterBars`.
  Widget _buildTagGroupFilterBars() {
    final nonEmptyGroups = widget.tagGroups.where((g) => g.tags.isNotEmpty).toList();
    if (nonEmptyGroups.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSetFilterBar(),
        _buildTagGroupFilterBars(),
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
                                onTap: () => setState(() => _selectedCardId = card.id),
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
                    child: card == null
                        ? Center(
                            child: Text(
                              'Select a card to preview',
                              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                            ))
                        : _CardPreviewPane(folderPath: widget.folderPath, card: card),
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
                ],
              );
            },
          ),
        ),
      ],
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
/// [CardDetailPanel] form column are visually confirmed immediately.
///
/// Unlike [CardFaceWidget] (used for grid tiles, which forces every card
/// into a uniform 70x100 box via `BoxFit.cover`, cropping mismatched
/// aspect ratios), this shows the actual image uncropped at its own aspect
/// ratio, scaled up to fill as much of the preview area as possible.
class _CardPreviewPane extends StatelessWidget {
  const _CardPreviewPane({required this.folderPath, required this.card});

  final String folderPath;
  final CardDefinition card;

  @override
  Widget build(BuildContext context) {
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
}
