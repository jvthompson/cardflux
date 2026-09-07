import '../models/card_instance.dart';

/// Shared helpers for reasoning about stacks of cards linked via
/// [CardInstance.stackParentId] chains. Used by both [TableActions] (to
/// apply draw/shuffle) and the table UI (to decide what to render as a pile
/// vs a loose card).
class StackUtils {
  const StackUtils();

  /// Walks [card]'s stackParentId chain up to its root and returns the root
  /// card's instanceId. A card with no parent is its own root.
  String rootIdOf(List<CardInstance> cards, CardInstance card) {
    var current = card;
    final visited = <String>{};
    while (current.stackParentId != null && visited.add(current.instanceId)) {
      final parent = _findById(cards, current.stackParentId!);
      if (parent == null) break;
      current = parent;
    }
    return current.instanceId;
  }

  /// Every card whose stack is rooted at [rootInstanceId], including the
  /// root itself.
  List<CardInstance> stackOf(List<CardInstance> cards, String rootInstanceId) {
    return cards.where((c) => c.instanceId == rootInstanceId || rootIdOf(cards, c) == rootInstanceId).toList();
  }

  /// Groups every card into its stack, keyed by root instanceId. Cards with
  /// no stackParentId and nothing stacked on them appear as singleton groups.
  Map<String, List<CardInstance>> groupByStack(List<CardInstance> cards) {
    final groups = <String, List<CardInstance>>{};
    for (final c in cards) {
      final root = rootIdOf(cards, c);
      groups.putIfAbsent(root, () => []).add(c);
    }
    return groups;
  }

  /// The card with the highest zIndex within [stack] — the visually topmost
  /// and only one that should be interactive.
  CardInstance topOf(List<CardInstance> stack) {
    return stack.reduce((a, b) => a.zIndex >= b.zIndex ? a : b);
  }

  CardInstance? _findById(List<CardInstance> cards, String id) {
    for (final c in cards) {
      if (c.instanceId == id) return c;
    }
    return null;
  }
}
