import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/directory_picker.dart';
import '../../data/game_definition_file_ops.dart';
import '../../models/card_definition.dart';
import '../../models/game_set.dart';
import '../../models/pack_setting.dart';
import '../../models/tag_group.dart';

/// The Game Definition Editor's "Sets" tab. A controlled component -- the
/// parent `GameDefinitionEditorScreen` owns `sets`/`cards`; this widget only
/// reports full replacement lists via [onSetsChanged]/[onCardsChanged].
///
/// "Add Set" implements the locked-in creation flow: pick any folder of
/// card art on disk, that folder's basename becomes the new set's id (and
/// default name), its images get copied into `<gameFolder>/<id>/` (a no-op
/// if the picked folder already *is* that destination), and one
/// [CardDefinition] is auto-created per image, titled after its filename.
class SetsTab extends StatefulWidget {
  const SetsTab({
    super.key,
    required this.folderPath,
    required this.sets,
    required this.cards,
    required this.tagGroups,
    required this.fileOps,
    required this.onSetsChanged,
    required this.onCardsChanged,
  });

  final String folderPath;
  final List<GameSet> sets;
  final List<CardDefinition> cards;
  final List<TagGroup> tagGroups;
  final GameDefinitionFileOps fileOps;
  final ValueChanged<List<GameSet>> onSetsChanged;
  final ValueChanged<List<CardDefinition>> onCardsChanged;

  @override
  State<SetsTab> createState() => _SetsTabState();
}

/// The tags a Pack Generator widget may be configured to pull by, for
/// every set in the game -- only tags declared under a [TagGroup] named
/// "Rarity" (case-insensitive; e.g. "Common"/"Uncommon"/"Rare") qualify.
/// Empty if the game has no such group, or that group has no tags.
List<String> _rarityTags(List<TagGroup> tagGroups) {
  for (final group in tagGroups) {
    if (group.name.trim().toLowerCase() == 'rarity') return group.tags;
  }
  return const [];
}

class _SetsTabState extends State<SetsTab> {
  bool _busy = false;

  Future<void> _addSet() async {
    final sourcePath = await pickDirectoryPath();
    if (sourcePath == null || !mounted) return;

    final id = deriveIdFromFolderPath(sourcePath);
    if (widget.sets.any((s) => s.id == id)) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('A set named "$id" already exists.')));
      return;
    }

    setState(() => _busy = true);
    try {
      final destFolderPath = '${widget.folderPath}${Platform.pathSeparator}$id';
      await widget.fileOps.copySetImages(sourceFolderPath: sourcePath, destFolderPath: destFolderPath);
      final newCards = await widget.fileOps.buildCardsFromImageFolder(
        sourceFolderPath: sourcePath,
        setId: id,
        existingCardIds: widget.cards.map((c) => c.id),
      );
      if (!mounted) return;
      widget.onSetsChanged([...widget.sets, GameSet(id: id, name: id)]);
      widget.onCardsChanged([...widget.cards, ...newCards]);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not add set: $e')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _deleteSet(GameSet set) async {
    final cardCount = widget.cards.where((c) => c.setId == set.id).length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remove Set'),
        content: Text(
          'Remove "${set.name}" and its $cardCount card(s) from this game definition? '
          'This will not delete any files on disk.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (confirmed != true) return;
    widget.onSetsChanged(widget.sets.where((s) => s.id != set.id).toList());
    widget.onCardsChanged(widget.cards.where((c) => c.setId != set.id).toList());
  }

  @override
  Widget build(BuildContext context) {
    final rarityTags = _rarityTags(widget.tagGroups);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        for (final set in widget.sets)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: _SetEditorRow(
              key: ValueKey(set.id),
              set: set,
              cardCount: widget.cards.where((c) => c.setId == set.id).length,
              availableTags: rarityTags,
              hasRarityTags: rarityTags.isNotEmpty &&
                  widget.cards.any((c) => c.setId == set.id && c.types.any(rarityTags.contains)),
              onChanged: (updated) =>
                  widget.onSetsChanged([for (final s in widget.sets) if (s.id == set.id) updated else s]),
              onDelete: () => _deleteSet(set),
            ),
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add Set...'),
          onPressed: _busy ? null : _addSet,
        ),
        if (_busy)
          const Padding(
            padding: EdgeInsets.only(top: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
      ],
    );
  }
}

class _SetEditorRow extends StatefulWidget {
  const _SetEditorRow({
    super.key,
    required this.set,
    required this.cardCount,
    required this.availableTags,
    required this.hasRarityTags,
    required this.onChanged,
    required this.onDelete,
  });

  final GameSet set;
  final int cardCount;

  /// This game's Rarity group's tags (see [_rarityTags]) -- the only tags a
  /// Pack Setting may pick from.
  final List<String> availableTags;

  /// Whether at least one card in this set carries one of [availableTags]
  /// -- Pack Settings has nothing meaningful to configure otherwise, so the
  /// whole section is hidden when this is false.
  final bool hasRarityTags;

  final ValueChanged<GameSet> onChanged;
  final VoidCallback onDelete;

  @override
  State<_SetEditorRow> createState() => _SetEditorRowState();
}

class _SetEditorRowState extends State<_SetEditorRow> {
  late final TextEditingController _nameController = TextEditingController(text: widget.set.name);

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _addPackSetting() {
    final tag = widget.availableTags.isEmpty ? '' : widget.availableTags.first;
    widget.onChanged(
      widget.set.copyWith(packSettings: [...widget.set.packSettings, PackSetting(tag: tag, count: 1)]),
    );
  }

  void _updatePackSetting(int index, PackSetting updated) {
    widget.onChanged(
      widget.set.copyWith(packSettings: [for (final (i, p) in widget.set.packSettings.indexed) i == index ? updated : p]),
    );
  }

  void _removePackSetting(int index) {
    widget.onChanged(
      widget.set.copyWith(
        packSettings: [for (final (i, p) in widget.set.packSettings.indexed) if (i != index) p],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      labelText: 'Set Name',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => widget.onChanged(widget.set.copyWith(name: v)),
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 160,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.set.id,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        '${widget.cardCount} card(s)',
                        style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Remove Set', onPressed: widget.onDelete),
              ],
            ),
            if (widget.hasRarityTags) ...[
              const Divider(height: 24),
              Text('Pack Settings', style: Theme.of(context).textTheme.titleSmall),
              const SizedBox(height: 4),
              Text(
                'How many random cards of each Rarity a Pack Generator widget deals from this set. '
                'No settings configured: 10 random cards, rarities ignored.',
                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
              ),
              const SizedBox(height: 8),
              for (final (i, setting) in widget.set.packSettings.indexed)
                _PackSettingRow(
                  setting: setting,
                  availableTags: widget.availableTags,
                  onChanged: (updated) => _updatePackSetting(i, updated),
                  onDelete: () => _removePackSetting(i),
                ),
              TextButton.icon(
                icon: const Icon(Icons.add),
                label: const Text('Add Pack Setting'),
                onPressed: widget.availableTags.isEmpty ? null : _addPackSetting,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PackSettingRow extends StatelessWidget {
  const _PackSettingRow({
    required this.setting,
    required this.availableTags,
    required this.onChanged,
    required this.onDelete,
  });

  final PackSetting setting;
  final List<String> availableTags;
  final ValueChanged<PackSetting> onChanged;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final value = availableTags.contains(setting.tag) ? setting.tag : null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: InputDecorator(
              decoration: const InputDecoration(isDense: true, border: OutlineInputBorder()),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: value,
                  isExpanded: true,
                  hint: const Text('(unknown tag)'),
                  items: [for (final t in availableTags) DropdownMenuItem(value: t, child: Text(t))],
                  onChanged: (v) {
                    if (v != null) onChanged(setting.copyWith(tag: v));
                  },
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: setting.count <= 1 ? null : () => onChanged(setting.copyWith(count: setting.count - 1)),
          ),
          SizedBox(width: 24, child: Text('${setting.count}', textAlign: TextAlign.center)),
          IconButton(icon: const Icon(Icons.add), onPressed: () => onChanged(setting.copyWith(count: setting.count + 1))),
          IconButton(icon: const Icon(Icons.close), tooltip: 'Remove Pack Setting', onPressed: onDelete),
        ],
      ),
    );
  }
}
