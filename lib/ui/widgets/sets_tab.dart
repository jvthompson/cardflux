import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../data/game_definition_file_ops.dart';
import '../../models/card_definition.dart';
import '../../models/game_set.dart';

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
    required this.fileOps,
    required this.onSetsChanged,
    required this.onCardsChanged,
  });

  final String folderPath;
  final List<GameSet> sets;
  final List<CardDefinition> cards;
  final GameDefinitionFileOps fileOps;
  final ValueChanged<List<GameSet>> onSetsChanged;
  final ValueChanged<List<CardDefinition>> onCardsChanged;

  @override
  State<SetsTab> createState() => _SetsTabState();
}

class _SetsTabState extends State<SetsTab> {
  bool _busy = false;

  Future<void> _addSet() async {
    final sourcePath = await getDirectoryPath();
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
      final newCards = await widget.fileOps.buildCardsFromImageFolder(sourceFolderPath: sourcePath, setId: id);
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
    required this.onChanged,
    required this.onDelete,
  });

  final GameSet set;
  final int cardCount;
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

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Set Name', border: OutlineInputBorder(), isDense: true),
                onChanged: (v) => widget.onChanged(GameSet(id: widget.set.id, name: v)),
              ),
            ),
            const SizedBox(width: 16),
            SizedBox(
              width: 160,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(widget.set.id, style: const TextStyle(fontFamily: 'monospace', color: Colors.black54)),
                  Text('${widget.cardCount} card(s)', style: const TextStyle(color: Colors.black45, fontSize: 12)),
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Remove Set', onPressed: widget.onDelete),
          ],
        ),
      ),
    );
  }
}
