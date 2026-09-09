import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../models/card_definition.dart';
import '../../models/deck_config.dart';
import '../../models/zone_definition.dart';

const Uuid _uuid = Uuid();

/// The Game Definition Editor's "Zones" tab: a repeatable, expandable list
/// of `ZoneDefinition` editors. A controlled component -- the parent
/// `GameDefinitionEditorScreen` owns the actual `zones` list; this widget
/// only reports the full replacement list via [onZonesChanged].
class ZonesTab extends StatelessWidget {
  const ZonesTab({super.key, required this.zones, required this.cards, required this.onZonesChanged});

  final List<ZoneDefinition> zones;
  final List<CardDefinition> cards;
  final ValueChanged<List<ZoneDefinition>> onZonesChanged;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final zone in zones)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _ZoneEditorCard(
              key: ValueKey(zone.id),
              zone: zone,
              allCards: cards,
              onChanged: (updated) => onZonesChanged([for (final z in zones) if (z.id == zone.id) updated else z]),
              onDelete: () => onZonesChanged(zones.where((z) => z.id != zone.id).toList()),
            ),
          ),
        OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add Zone'),
          onPressed: () => onZonesChanged([...zones, ZoneDefinition(id: _uuid.v4(), name: 'New Zone')]),
        ),
      ],
    );
  }
}

class _ZoneEditorCard extends StatefulWidget {
  const _ZoneEditorCard({
    super.key,
    required this.zone,
    required this.allCards,
    required this.onChanged,
    required this.onDelete,
  });

  final ZoneDefinition zone;
  final List<CardDefinition> allCards;
  final ValueChanged<ZoneDefinition> onChanged;
  final VoidCallback onDelete;

  @override
  State<_ZoneEditorCard> createState() => _ZoneEditorCardState();
}

class _ZoneEditorCardState extends State<_ZoneEditorCard> {
  late final TextEditingController _idController = TextEditingController(text: widget.zone.id);
  late final TextEditingController _nameController = TextEditingController(text: widget.zone.name);

  @override
  void dispose() {
    _idController.dispose();
    _nameController.dispose();
    super.dispose();
  }

  void _updateEntry(int index, DeckEntry updated) {
    final entries = widget.zone.entries.toList();
    entries[index] = updated;
    widget.onChanged(widget.zone.copyWith(entries: entries));
  }

  void _removeEntry(int index) {
    final entries = widget.zone.entries.toList()..removeAt(index);
    widget.onChanged(widget.zone.copyWith(entries: entries));
  }

  void _addEntry() {
    if (widget.allCards.isEmpty) return;
    widget.onChanged(widget.zone.copyWith(
      entries: [...widget.zone.entries, DeckEntry(definitionId: widget.allCards.first.id, quantity: 1)],
    ));
  }

  @override
  Widget build(BuildContext context) {
    final zone = widget.zone;
    return Card(
      child: ExpansionTile(
        title: Text(zone.name.isEmpty ? '(unnamed zone)' : zone.name),
        subtitle: Text(zone.id),
        trailing: IconButton(
          icon: const Icon(Icons.delete_outline),
          tooltip: 'Delete Zone',
          onPressed: widget.onDelete,
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _idController,
                  decoration: const InputDecoration(labelText: 'Zone ID', border: OutlineInputBorder()),
                  onChanged: (v) => widget.onChanged(zone.copyWith(id: v)),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Zone Name', border: OutlineInputBorder()),
                  onChanged: (v) => widget.onChanged(zone.copyWith(name: v)),
                ),
                SwitchListTile(
                  title: const Text('Shared'),
                  subtitle: const Text('One public pile for everyone, instead of one private pile per player'),
                  value: zone.shared,
                  onChanged: (v) => widget.onChanged(zone.copyWith(shared: v)),
                ),
                SwitchListTile(
                  title: const Text('Deals Built Deck'),
                  subtitle: const Text("Receives the player's own loaded deck at game start (owned zones only)"),
                  value: zone.dealsBuiltDeck,
                  onChanged: zone.shared ? null : (v) => widget.onChanged(zone.copyWith(dealsBuiltDeck: v)),
                ),
                SwitchListTile(
                  title: const Text('Face Up'),
                  subtitle: const Text('Cards in this zone show their real face'),
                  value: zone.faceUp,
                  onChanged: (v) => widget.onChanged(zone.copyWith(faceUp: v)),
                ),
                SwitchListTile(
                  title: const Text('Shuffleable'),
                  subtitle: const Text('Show a shuffle button for this zone'),
                  value: zone.shuffleable,
                  onChanged: (v) => widget.onChanged(zone.copyWith(shuffleable: v)),
                ),
                SwitchListTile(
                  title: const Text('Visible To All'),
                  subtitle: const Text('Let opponents see the real cards in this owned zone'),
                  value: zone.visibleToAll,
                  onChanged: zone.shared ? null : (v) => widget.onChanged(zone.copyWith(visibleToAll: v)),
                ),
                SwitchListTile(
                  title: const Text('Is Discard Pile'),
                  subtitle: const Text('Pressing D sends a hovered table card here'),
                  value: zone.isDiscardPile,
                  onChanged: (v) => widget.onChanged(zone.copyWith(isDiscardPile: v)),
                ),
                const SizedBox(height: 8),
                Opacity(
                  opacity: zone.dealsBuiltDeck ? 0.4 : 1,
                  child: IgnorePointer(
                    ignoring: zone.dealsBuiltDeck,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Starting Contents', style: TextStyle(fontWeight: FontWeight.bold)),
                        ),
                        if (zone.dealsBuiltDeck)
                          const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Text(
                              'Ignored while Deals Built Deck is on.',
                              style: TextStyle(color: Colors.black45, fontSize: 12),
                            ),
                          ),
                        for (var i = 0; i < zone.entries.length; i++)
                          _EntryRow(
                            entry: zone.entries[i],
                            allCards: widget.allCards,
                            onChanged: (updated) => _updateEntry(i, updated),
                            onDelete: () => _removeEntry(i),
                          ),
                        TextButton.icon(
                          icon: const Icon(Icons.add),
                          label: const Text('Add Entry'),
                          onPressed: widget.allCards.isEmpty ? null : _addEntry,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.allCards, required this.onChanged, required this.onDelete});

  final DeckEntry entry;
  final List<CardDefinition> allCards;
  final ValueChanged<DeckEntry> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final knownIds = allCards.map((c) => c.id).toSet();
    final value = knownIds.contains(entry.definitionId) ? entry.definitionId : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            // Plain DropdownButton (not DropdownButtonFormField), deliberately --
            // this row has no key, so deleting/reordering an entry can reuse this
            // Element for a different entry at the same index; DropdownButton's
            // `value:` is always controlled (unlike DropdownButtonFormField's
            // now-deprecated `value:`, whose replacement `initialValue:` would
            // keep showing a stale selection after such a reuse).
            child: InputDecorator(
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: value,
                  isExpanded: true,
                  hint: const Text('(unknown card)'),
                  items: [for (final c in allCards) DropdownMenuItem(value: c.id, child: Text(c.cardTitle))],
                  onChanged: (v) {
                    if (v != null) onChanged(DeckEntry(definitionId: v, quantity: entry.quantity));
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: entry.quantity <= 1
                ? null
                : () => onChanged(DeckEntry(definitionId: entry.definitionId, quantity: entry.quantity - 1)),
          ),
          SizedBox(width: 24, child: Text('${entry.quantity}', textAlign: TextAlign.center)),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => onChanged(DeckEntry(definitionId: entry.definitionId, quantity: entry.quantity + 1)),
          ),
          IconButton(icon: const Icon(Icons.close), tooltip: 'Remove Entry', onPressed: onDelete),
        ],
      ),
    );
  }
}
