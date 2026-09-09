import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../data/game_definition_file_ops.dart';
import '../../data/image_path_resolver.dart';
import '../../models/card_definition.dart';
import '../../models/game_set.dart';
import '../../models/tag_group.dart';
import 'card_face_widget.dart' show cardHeight, cardWidth, parseHexColor;

/// Every editable field of one [CardDefinition], for the Game Definition
/// Editor's Card View tab. A controlled component -- edits are reported via
/// [onChanged], never applied locally; the parent owns the actual card list.
class CardDetailPanel extends StatefulWidget {
  const CardDetailPanel({
    super.key,
    required this.folderPath,
    required this.card,
    required this.tagGroups,
    required this.allSets,
    required this.fileOps,
    required this.onChanged,
    required this.onDelete,
    required this.hiddenTagGroupIds,
    required this.onToggleTagGroupVisibility,
  });

  final String folderPath;
  final CardDefinition card;
  final List<TagGroup> tagGroups;
  final List<GameSet> allSets;
  final GameDefinitionFileOps fileOps;
  final ValueChanged<CardDefinition> onChanged;
  final VoidCallback onDelete;

  /// Ids of [tagGroups] whose chip section is currently collapsed -- owned
  /// by the parent (`CardViewTab`) so it survives this panel being torn
  /// down and rebuilt on every card selection change (it's keyed by card
  /// id, so its own `State` never persists across cards).
  final Set<String> hiddenTagGroupIds;
  final void Function(String groupId, bool visible) onToggleTagGroupVisibility;

  @override
  State<CardDetailPanel> createState() => _CardDetailPanelState();
}

class _CardDetailPanelState extends State<CardDetailPanel> {
  late final TextEditingController _idController = TextEditingController(text: widget.card.id);
  late final TextEditingController _titleController = TextEditingController(text: widget.card.cardTitle);
  late final TextEditingController _colorController = TextEditingController(text: widget.card.colorHex ?? '');
  late final TextEditingController _suitController = TextEditingController(text: widget.card.suit ?? '');
  late final TextEditingController _rankController = TextEditingController(text: widget.card.rank ?? '');
  bool _busy = false;

  @override
  void dispose() {
    _idController.dispose();
    _titleController.dispose();
    _colorController.dispose();
    _suitController.dispose();
    _rankController.dispose();
    super.dispose();
  }

  /// Where a newly-chosen image gets copied to -- the card's own set
  /// subfolder if it belongs to one, otherwise the game folder root.
  String get _imageDestFolder {
    final setId = widget.card.setId;
    return setId == null ? widget.folderPath : '${widget.folderPath}${Platform.pathSeparator}$setId';
  }

  Future<void> _chooseImage() async {
    final file = await openFile(acceptedTypeGroups: imageFileTypes);
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final fileName = await widget.fileOps.copyPickedImage(sourcePath: file.path, destFolderPath: _imageDestFolder);
      widget.onChanged(widget.card.copyWith(imagePath: fileName));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _toggleType(String type, bool selected) {
    final types = widget.card.types.toList();
    if (selected) {
      if (!types.contains(type)) types.add(type);
    } else {
      types.remove(type);
    }
    widget.onChanged(widget.card.copyWith(types: types));
  }

  void _removeExtraField(String key) {
    final fields = {...widget.card.extraFields}..remove(key);
    widget.onChanged(widget.card.copyWith(extraFields: fields));
  }

  void _addExtraField() {
    final fields = {...widget.card.extraFields};
    var newKey = 'field';
    var suffix = 1;
    while (fields.containsKey(newKey)) {
      newKey = 'field$suffix';
      suffix++;
    }
    fields[newKey] = '';
    widget.onChanged(widget.card.copyWith(extraFields: fields));
  }

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Card'),
        content: Text('Delete "${widget.card.cardTitle}"? This does not delete its image file.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed == true) widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final card = widget.card;
    final resolvedImage =
        resolvedImagePathForDisplay(widget.folderPath, bareImagePath: card.imagePath, setId: card.setId);
    Color? swatchColor;
    try {
      if (card.colorHex != null) swatchColor = parseHexColor(card.colorHex!);
    } catch (_) {
      swatchColor = null;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        TextField(
          controller: _idController,
          decoration: const InputDecoration(labelText: 'Card ID', border: OutlineInputBorder(), isDense: true),
          onChanged: (v) => widget.onChanged(card.copyWith(id: v)),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _titleController,
          decoration: const InputDecoration(labelText: 'Card Title', border: OutlineInputBorder(), isDense: true),
          onChanged: (v) => widget.onChanged(card.copyWith(cardTitle: v)),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _colorController,
                decoration:
                    const InputDecoration(labelText: 'Color Hex (#RRGGBB)', border: OutlineInputBorder(), isDense: true),
                onChanged: (v) => widget.onChanged(card.copyWith(colorHex: v.trim().isEmpty ? null : v.trim())),
              ),
            ),
            const SizedBox(width: 8),
            Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: swatchColor ?? Colors.transparent,
                border: Border.all(color: Colors.black26),
                borderRadius: BorderRadius.circular(4),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _suitController,
                decoration: const InputDecoration(labelText: 'Suit', border: OutlineInputBorder(), isDense: true),
                onChanged: (v) => widget.onChanged(card.copyWith(suit: v.trim().isEmpty ? null : v.trim())),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _rankController,
                decoration: const InputDecoration(labelText: 'Rank', border: OutlineInputBorder(), isDense: true),
                onChanged: (v) => widget.onChanged(card.copyWith(rank: v.trim().isEmpty ? null : v.trim())),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        DropdownButtonFormField<CardOrientation>(
          initialValue: card.orientation,
          decoration: const InputDecoration(labelText: 'Orientation', border: OutlineInputBorder(), isDense: true),
          items: [for (final o in CardOrientation.values) DropdownMenuItem(value: o, child: Text(o.name))],
          onChanged: (v) {
            if (v != null) widget.onChanged(card.copyWith(orientation: v));
          },
        ),
        if (widget.allSets.isNotEmpty) ...[
          const SizedBox(height: 12),
          DropdownButtonFormField<String?>(
            initialValue: card.setId,
            decoration: const InputDecoration(labelText: 'Set', border: OutlineInputBorder(), isDense: true),
            items: [
              const DropdownMenuItem<String?>(value: null, child: Text('(none)')),
              for (final set in widget.allSets) DropdownMenuItem<String?>(value: set.id, child: Text(set.name)),
            ],
            onChanged: (v) => widget.onChanged(card.copyWith(setId: v)),
          ),
        ],
        const SizedBox(height: 16),
        const Text('Image', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: cardWidth,
              height: cardHeight,
              decoration: BoxDecoration(border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(6)),
              child: resolvedImage == null
                  ? const Icon(Icons.image_not_supported_outlined, color: Colors.black26)
                  : ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Image.file(
                        File(resolvedImage),
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(Icons.broken_image_outlined, color: Colors.black26),
                      ),
                    ),
            ),
            const SizedBox(width: 16),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                OutlinedButton(onPressed: _busy ? null : _chooseImage, child: const Text('Choose Image...')),
                if (card.imagePath != null)
                  TextButton(
                    onPressed: _busy ? null : () => widget.onChanged(card.copyWith(imagePath: null)),
                    child: const Text('Clear'),
                  ),
              ],
            ),
          ],
        ),
        for (final group in widget.tagGroups)
          if (group.tags.isNotEmpty) ...[
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(
                    group.name,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                FilterChip(
                  label: Text(widget.hiddenTagGroupIds.contains(group.id) ? 'Show' : 'Hide'),
                  avatar: Icon(
                    widget.hiddenTagGroupIds.contains(group.id)
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                    size: 18,
                  ),
                  selected: !widget.hiddenTagGroupIds.contains(group.id),
                  onSelected: (visible) => widget.onToggleTagGroupVisibility(group.id, visible),
                ),
              ],
            ),
            if (!widget.hiddenTagGroupIds.contains(group.id)) ...[
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final tag in group.tags)
                    FilterChip(
                      label: Text(tag),
                      selected: card.types.contains(tag),
                      onSelected: (sel) => _toggleType(tag, sel),
                    ),
                ],
              ),
            ],
          ],
        const SizedBox(height: 16),
        const Text('Extra Fields', style: TextStyle(fontWeight: FontWeight.bold)),
        const SizedBox(height: 8),
        for (final entry in card.extraFields.entries.toList())
          _ExtraFieldRow(
            key: ValueKey(entry.key),
            fieldKey: entry.key,
            value: entry.value,
            onChanged: (newKey, newValue) {
              final fields = {...card.extraFields};
              fields.remove(entry.key);
              fields[newKey] = newValue;
              widget.onChanged(card.copyWith(extraFields: fields));
            },
            onDelete: () => _removeExtraField(entry.key),
          ),
        TextButton.icon(icon: const Icon(Icons.add), label: const Text('Add Field'), onPressed: _addExtraField),
        const SizedBox(height: 24),
        FilledButton.tonalIcon(
          icon: const Icon(Icons.delete_outline),
          label: const Text('Delete Card'),
          onPressed: _confirmDelete,
        ),
      ],
    );
  }
}

class _ExtraFieldRow extends StatefulWidget {
  const _ExtraFieldRow({
    super.key,
    required this.fieldKey,
    required this.value,
    required this.onChanged,
    required this.onDelete,
  });

  final String fieldKey;
  final String value;
  final void Function(String newKey, String newValue) onChanged;
  final VoidCallback onDelete;

  @override
  State<_ExtraFieldRow> createState() => _ExtraFieldRowState();
}

class _ExtraFieldRowState extends State<_ExtraFieldRow> {
  late final TextEditingController _keyController = TextEditingController(text: widget.fieldKey);
  late final TextEditingController _valueController = TextEditingController(text: widget.value);

  @override
  void dispose() {
    _keyController.dispose();
    _valueController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _keyController,
              decoration: const InputDecoration(labelText: 'Key', isDense: true, border: OutlineInputBorder()),
              onChanged: (v) => widget.onChanged(v, _valueController.text),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _valueController,
              decoration: const InputDecoration(labelText: 'Value', isDense: true, border: OutlineInputBorder()),
              onChanged: (v) => widget.onChanged(_keyController.text, v),
            ),
          ),
          IconButton(icon: const Icon(Icons.close), tooltip: 'Remove Field', onPressed: widget.onDelete),
        ],
      ),
    );
  }
}
