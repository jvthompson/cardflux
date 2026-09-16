import 'package:flutter/material.dart';

import '../../models/card_definition.dart';
import '../../models/game_set.dart';

/// Finds every [CardDefinition] in [cards] sharing an `id` with at least one
/// other card and lets the user re-key them by hand -- a manual escape hatch
/// for collisions that predate (or otherwise slip past) the auto-dedup
/// `GameDefinitionFileOps.buildCardsFromImageFolder` applies on import. Shows
/// a plain `SnackBar` and opens nothing if there are no duplicates. [sets] is
/// only used to show each duplicate's set name for context. Edits are local
/// to the dialog until "Save" is pressed, which reports the whole edited
/// list via [onChanged] in one go; "Cancel" discards them.
Future<void> showDuplicateCardIdsDialog(
  BuildContext context, {
  required List<CardDefinition> cards,
  required List<GameSet> sets,
  required ValueChanged<List<CardDefinition>> onChanged,
}) async {
  if (!_hasDuplicateIds(cards)) {
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No duplicate card IDs found.')));
    return;
  }
  final setNames = {for (final s in sets) s.id: s.name};
  await showDialog<void>(
    context: context,
    builder: (context) => _DuplicateCardIdsDialog(cards: cards, setNames: setNames, onChanged: onChanged),
  );
}

bool _hasDuplicateIds(List<CardDefinition> cards) {
  final seen = <String>{};
  for (final card in cards) {
    if (!seen.add(card.id)) return true;
  }
  return false;
}

/// Groups [cards] by `id`, keeping only ids shared by more than one card, in
/// first-seen order.
Map<String, List<int>> _duplicateGroups(List<CardDefinition> cards) {
  final groups = <String, List<int>>{};
  for (var i = 0; i < cards.length; i++) {
    groups.putIfAbsent(cards[i].id, () => []).add(i);
  }
  groups.removeWhere((id, indices) => indices.length < 2);
  return groups;
}

class _DuplicateCardIdsDialog extends StatefulWidget {
  const _DuplicateCardIdsDialog({required this.cards, required this.setNames, required this.onChanged});

  final List<CardDefinition> cards;

  /// [GameSet.id] -> [GameSet.name], for showing each duplicate's set as
  /// context alongside its title.
  final Map<String, String> setNames;
  final ValueChanged<List<CardDefinition>> onChanged;

  @override
  State<_DuplicateCardIdsDialog> createState() => _DuplicateCardIdsDialogState();
}

class _DuplicateCardIdsDialogState extends State<_DuplicateCardIdsDialog> {
  /// Working copy, edited locally as the user types; only reported up via
  /// [DuplicateCardIdsDialog.onChanged] when Save is pressed.
  late final List<CardDefinition> _cards = List.of(widget.cards);

  /// Which cards were duplicates when the dialog opened, grouped by their
  /// original id -- computed once and frozen for the dialog's lifetime.
  /// Editing an id to make it unique would otherwise make its row vanish
  /// mid-edit if this were recomputed live off [_cards].
  late final Map<String, List<int>> _groups = _duplicateGroups(_cards);

  void _updateCardId(int index, String newId) {
    setState(() => _cards[index] = _cards[index].copyWith(id: newId));
  }

  void _save() {
    widget.onChanged(_cards);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Duplicate Card IDs'),
      content: SizedBox(
        width: 480,
        child: ListView(
          shrinkWrap: true,
          children: [
            for (final entry in _groups.entries) ...[
              Text(
                '"${entry.key}" -- ${entry.value.length} cards',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              for (final index in entry.value)
                _DuplicateCardIdRow(
                  key: ValueKey(index),
                  card: _cards[index],
                  setName: _cards[index].setId == null ? null : widget.setNames[_cards[index].setId],
                  onChanged: (v) => _updateCardId(index, v),
                ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(onPressed: _save, child: const Text('Save')),
      ],
    );
  }
}

class _DuplicateCardIdRow extends StatefulWidget {
  const _DuplicateCardIdRow({super.key, required this.card, required this.setName, required this.onChanged});

  final CardDefinition card;

  /// The card's set name, or null if it belongs to no set (or that set
  /// couldn't be resolved).
  final String? setName;
  final ValueChanged<String> onChanged;

  @override
  State<_DuplicateCardIdRow> createState() => _DuplicateCardIdRowState();
}

class _DuplicateCardIdRowState extends State<_DuplicateCardIdRow> {
  late final TextEditingController _controller = TextEditingController(text: widget.card.id);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: [
          Expanded(
            flex: 2,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.card.cardTitle, overflow: TextOverflow.ellipsis),
                Text(
                  widget.setName ?? '(no set)',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 3,
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(labelText: 'Card ID', border: OutlineInputBorder(), isDense: true),
              onChanged: widget.onChanged,
            ),
          ),
        ],
      ),
    );
  }
}
