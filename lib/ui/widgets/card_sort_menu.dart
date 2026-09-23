import 'package:flutter/material.dart';

import '../../models/card_definition.dart';
import '../../models/game_set.dart';
import '../../models/tag_group.dart';

typedef CardSortOption = ({String id, String name});

/// Reserved [CardSortOption.id] for sorting by [GameSet] order, as declared
/// in the game definition's `sets` list.
const String cardSortBySet = 'set';

/// Reserved [CardSortOption.id] for sorting alphabetically by
/// [CardDefinition.cardTitle].
const String cardSortByName = 'name';

/// Returns [cards] sorted per [sortKey] -- unchanged (original pool order)
/// when null. [cardSortBySet] orders by each card's index in [sets] (no/
/// unrecognized set sorts last); [cardSortByName] orders alphabetically by
/// title; any other id is looked up in [tagGroups] and orders by the lowest
/// index among the card's tags that appear in that group's own (JSON-authored)
/// tag order, so sorting by a tag group mirrors how its tags are ordered in
/// the game definition -- a card with none of that group's tags sorts last.
/// Every case breaks ties alphabetically by title for a stable result.
List<CardDefinition> sortCardDefinitions(
  List<CardDefinition> cards, {
  required String? sortKey,
  required List<GameSet> sets,
  required List<TagGroup> tagGroups,
}) {
  if (sortKey == null) return cards;

  int Function(CardDefinition) rank;
  if (sortKey == cardSortBySet) {
    final order = {for (var i = 0; i < sets.length; i++) sets[i].id: i};
    rank = (c) => c.setId == null ? sets.length : (order[c.setId] ?? sets.length);
  } else if (sortKey == cardSortByName) {
    rank = (_) => 0;
  } else {
    TagGroup? group;
    for (final g in tagGroups) {
      if (g.id == sortKey) {
        group = g;
        break;
      }
    }
    final tags = group?.tags ?? const [];
    final order = {for (var i = 0; i < tags.length; i++) tags[i]: i};
    rank = (c) {
      var best = tags.length;
      for (final tag in c.types) {
        final index = order[tag];
        if (index != null && index < best) best = index;
      }
      return best;
    };
  }

  final sorted = [...cards];
  sorted.sort((a, b) {
    final byRank = rank(a).compareTo(rank(b));
    if (byRank != 0) return byRank;
    return a.cardTitle.toLowerCase().compareTo(b.cardTitle.toLowerCase());
  });
  return sorted;
}

/// Whether [card] passes every active filter -- shared by the Deck Editor's
/// pool, the Game Definition Editor's Card View tab, and the table's Card
/// Library, so all three filter identically rather than each maintaining
/// their own copy. A card is tag-visible unless some group's active
/// selection excludes it. Within a group, a non-empty selection means OR:
/// the card must have at least one of that group's selected tags, *including*
/// when the card has none of that group's tags at all -- a card that belongs
/// to a mutually-exclusive taxonomy (e.g. a "Clan" card with no "Inner
/// Sphere" tag) is correctly hidden by an Inner Sphere selection, the same as
/// any other non-match. Across groups this is AND: every group with an
/// active [selectedTagsByGroup] entry must independently be satisfied. A
/// card with any tag in [excludedTagsByGroup] (combined across every group)
/// is hidden outright, regardless of any group's selection. An empty
/// [selectedSetIds] means no set filtering, and a card with no set is never
/// hidden by it. [searchQuery] (default: no search filter) does a
/// case-insensitive substring match against the card's title and id.
bool cardMatchesFilters(
  CardDefinition card, {
  required List<TagGroup> tagGroups,
  required Map<String, Set<String>> selectedTagsByGroup,
  required Map<String, Set<String>> excludedTagsByGroup,
  required Set<String> selectedSetIds,
  String searchQuery = '',
}) {
  final allExcludedTags = {for (final s in excludedTagsByGroup.values) ...s};
  if (card.types.any(allExcludedTags.contains)) return false;
  for (final group in tagGroups) {
    final selected = selectedTagsByGroup[group.id];
    if (selected == null || selected.isEmpty) continue;
    if (!card.types.any(selected.contains)) return false;
  }
  if (selectedSetIds.isNotEmpty && card.setId != null && !selectedSetIds.contains(card.setId)) {
    return false;
  }
  final query = searchQuery.trim().toLowerCase();
  if (query.isEmpty) return true;
  return card.cardTitle.toLowerCase().contains(query) || card.id.toLowerCase().contains(query);
}

/// A trigger button ("Sort" / "Sort: Name (A-Z)") that opens a single-select
/// dropdown of [options] plus a leading "Default order" entry (`null` id) --
/// styled to match [MultiSelectFilterMenu]'s trigger button. Shared by the
/// Deck Editor's and the Game Definition Editor's Card View tab's pool.
class CardSortMenu extends StatelessWidget {
  const CardSortMenu({super.key, required this.options, required this.selectedId, required this.onSelected});

  final List<CardSortOption> options;
  final String? selectedId;
  final ValueChanged<String?> onSelected;

  Widget _buildOptionRow({required String? id, required String name}) {
    final selected = id == selectedId;
    return MenuItemButton(
      leadingIcon: SizedBox(width: 20, child: selected ? const Icon(Icons.check, size: 18) : null),
      onPressed: () => onSelected(id),
      child: Text(name),
    );
  }

  @override
  Widget build(BuildContext context) {
    String currentLabel = 'Sort';
    for (final option in options) {
      if (option.id == selectedId) {
        currentLabel = 'Sort: ${option.name}';
        break;
      }
    }
    return MenuAnchor(
      menuChildren: [
        _buildOptionRow(id: null, name: 'Default order'),
        const Divider(height: 1),
        for (final option in options) _buildOptionRow(id: option.id, name: option.name),
      ],
      builder: (context, controller, child) {
        return OutlinedButton(
          onPressed: () => controller.isOpen ? controller.close() : controller.open(),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(currentLabel),
              const Icon(Icons.arrow_drop_down),
            ],
          ),
        );
      },
    );
  }
}
