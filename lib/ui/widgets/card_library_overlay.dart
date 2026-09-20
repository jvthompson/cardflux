import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../app_theme.dart';
import '../../models/card_definition.dart';
import '../../models/game_set.dart';
import '../../models/tag_group.dart';
import 'card_face_widget.dart';
import 'card_sort_menu.dart';
import 'multi_select_filter_menu.dart';

/// Every card in the game, right-click-the-table -> Card Library -- the same
/// sort/filter tools as the Deck Editor's pool (`cardMatchesFilters`,
/// `sortCardDefinitions`, `MultiSelectFilterMenu`, `CardSortMenu`), but no
/// big preview panel: the table's own spacebar preview covers that (see
/// `TableScreen`'s `onCardHover`). A floating panel, not a pushed route, for
/// the same reason as `ZoneSearchOverlay` (its doc comment applies
/// identically here) -- it stays in the same `Overlay` subtree as the board
/// so its `Draggable` cards can be released onto the table, and so the
/// table's Space-preview machinery (which only tracks hovers within that
/// subtree) can see them hovered.
///
/// Unlike `ZoneSearchOverlay` (which receives an already-filtered/sorted
/// list), this owns its own filter/sort/search state -- there's no
/// upstream owner of "what the library is currently showing."
class CardLibraryOverlay extends StatefulWidget {
  const CardLibraryOverlay({
    super.key,
    required this.cards,
    required this.sets,
    required this.tagGroups,
    required this.screenSize,
    required this.onClose,
    required this.onCardDragEnd,
    required this.onCardHover,
  });

  final List<CardDefinition> cards;
  final List<GameSet> sets;
  final List<TagGroup> tagGroups;
  final Size screenSize;
  final VoidCallback onClose;

  /// A tile's drag was released at [globalTopLeft] -- the caller (see
  /// `TableScreen._handleLibraryCardDragEnd`) decides whether that's over
  /// the table (create a copy there) or anywhere else (no-op).
  final void Function(String definitionId, Offset globalTopLeft) onCardDragEnd;

  /// Reports mouse enter/exit over a tile -- wired by `TableScreen` so
  /// holding Space over a library card shows a large preview, the same as
  /// every other hoverable card on the table.
  final void Function(String definitionId, bool hovering) onCardHover;

  @override
  State<CardLibraryOverlay> createState() => _CardLibraryOverlayState();
}

class _CardLibraryOverlayState extends State<CardLibraryOverlay> {
  late final Map<String, Set<String>> _selectedTagsByGroup = {
    for (final g in widget.tagGroups) g.id: <String>{},
  };
  late final Map<String, Set<String>> _excludedTagsByGroup = {
    for (final g in widget.tagGroups) g.id: <String>{},
  };
  late final Set<String> _selectedSetIds = {};
  String? _sortKey;
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  /// See [cardMatchesFilters] -- the same predicate the Deck Editor's pool
  /// and the Card View tab use, so this filters identically to both.
  bool _isVisible(CardDefinition card) => cardMatchesFilters(
        card,
        tagGroups: widget.tagGroups,
        selectedTagsByGroup: _selectedTagsByGroup,
        excludedTagsByGroup: _excludedTagsByGroup,
        selectedSetIds: _selectedSetIds,
        searchQuery: _searchQuery,
      );

  List<CardDefinition> get _visibleCards => sortCardDefinitions(
        widget.cards.where(_isVisible).toList(),
        sortKey: _sortKey,
        sets: widget.sets,
        tagGroups: widget.tagGroups,
      );

  void _clearFilters() {
    setState(() {
      _selectedSetIds.clear();
      for (final group in widget.tagGroups) {
        _selectedTagsByGroup[group.id]!.clear();
        _excludedTagsByGroup[group.id]!.clear();
      }
    });
  }

  Widget _buildFilterBar() {
    final nonEmptyGroups = widget.tagGroups.where((g) => g.tags.isNotEmpty).toList();
    if (widget.sets.isEmpty && nonEmptyGroups.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
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
                      (
                        id: set.id,
                        name: '${set.name} (${widget.cards.where((c) => c.setId == set.id).length})',
                      ),
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

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          labelText: 'Search',
          hintText: 'Search by name or ID',
          prefixIcon: const Icon(Icons.search),
          suffixIcon: _searchQuery.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.clear),
                  tooltip: 'Clear search',
                  onPressed: () => setState(() {
                    _searchController.clear();
                    _searchQuery = '';
                  }),
                ),
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        onChanged: (value) => setState(() => _searchQuery = value),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final width = math.min(1280.0, widget.screenSize.width - 40);
    final height = math.min(720.0, widget.screenSize.height - 40);
    final visibleCards = _visibleCards;

    return Stack(
      children: [
        // A light scrim, not opaque -- the board stays visible around the
        // window's edges, matching ZoneSearchOverlay. Tapping it closes the
        // window, same as the X button.
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.25)),
          ),
        ),
        Center(
          child: SizedBox(
            width: width,
            height: height,
            child: Material(
              color: const Color(0xFF262626),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              // Dark theme so the reused filter/sort controls (normally
              // shown on the app's light background elsewhere) stay legible
              // against this panel's dark fill, without hand-tuning their
              // colors here.
              child: Theme(
                data: AppTheme.dark,
                child: Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                      child: Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Card Library',
                              style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                            ),
                          ),
                          Text(
                            '${visibleCards.length} of ${widget.cards.length} card'
                            '${widget.cards.length == 1 ? '' : 's'}',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          IconButton(
                            icon: const Icon(Icons.close, color: Colors.white),
                            tooltip: 'Close',
                            onPressed: widget.onClose,
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1, color: Colors.white24),
                    _buildFilterBar(),
                    _buildSearchField(),
                    Expanded(
                      child: visibleCards.isEmpty
                          ? const Center(
                              child: Text(
                                'No cards match the current filters.',
                                style: TextStyle(color: Colors.white54),
                              ),
                            )
                          : GridView.builder(
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
                                return _LibraryTile(
                                  card: card,
                                  onDragEnd: (offset) => widget.onCardDragEnd(card.id, offset),
                                  onHover: (hovering) => widget.onCardHover(card.id, hovering),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _LibraryTile extends StatelessWidget {
  const _LibraryTile({required this.card, required this.onDragEnd, required this.onHover});

  final CardDefinition card;
  final ValueChanged<Offset> onDragEnd;
  final ValueChanged<bool> onHover;

  @override
  Widget build(BuildContext context) {
    // Always the front face -- this is a catalog of card kinds, not a
    // physical instance with its own face-up/down state.
    final face = CardFaceWidget(definition: card);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          onEnter: (_) => onHover(true),
          onExit: (_) => onHover(false),
          child: Draggable<String>(
            data: card.id,
            feedback: Material(type: MaterialType.transparency, child: face),
            childWhenDragging: Opacity(opacity: 0.3, child: face),
            onDragEnd: (details) => onDragEnd(details.offset),
            child: face,
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
            style: const TextStyle(fontSize: 11, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
