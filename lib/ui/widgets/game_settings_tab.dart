import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../../data/game_definition_file_ops.dart';
import '../../data/image_path_resolver.dart';
import '../../models/card_back_definition.dart';
import '../../models/card_definition.dart';
import '../../models/game_set.dart';
import '../../models/tag_group.dart';
import 'card_face_widget.dart' show cardHeight, cardWidth;
import 'duplicate_card_ids_dialog.dart';

const Uuid _uuid = Uuid();

/// The Game Definition Editor's "Game Settings" tab: the game's display
/// [name], its default cardback art, and its declared tag taxonomy (see
/// `GameDefinition.tagGroups`). A controlled component -- the parent
/// `GameDefinitionEditorScreen` owns the actual state and is the only place
/// `setState` runs; this widget just reports edits via the `onXChanged`
/// callbacks.
class GameSettingsTab extends StatefulWidget {
  const GameSettingsTab({
    super.key,
    required this.folderPath,
    required this.name,
    required this.cardBacks,
    required this.tagGroups,
    required this.cards,
    required this.sets,
    required this.fileOps,
    required this.onNameChanged,
    required this.onCardBacksChanged,
    required this.onTagGroupsChanged,
    required this.onCardsChanged,
  });

  final String folderPath;
  final String name;
  final List<CardBackDefinition> cardBacks;
  final List<TagGroup> tagGroups;
  final List<CardDefinition> cards;
  final List<GameSet> sets;
  final GameDefinitionFileOps fileOps;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<List<CardBackDefinition>> onCardBacksChanged;
  final ValueChanged<List<TagGroup>> onTagGroupsChanged;
  final ValueChanged<List<CardDefinition>> onCardsChanged;

  @override
  State<GameSettingsTab> createState() => _GameSettingsTabState();
}

class _GameSettingsTabState extends State<GameSettingsTab> with AutomaticKeepAliveClientMixin<GameSettingsTab> {
  late final TextEditingController _nameController = TextEditingController(text: widget.name);
  final TextEditingController _newGroupNameController = TextEditingController();
  bool _busy = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void dispose() {
    _nameController.dispose();
    _newGroupNameController.dispose();
    super.dispose();
  }

  /// Picks a new card-back image and appends it as a brand-new
  /// [CardBackDefinition] -- the first one ever added becomes this game's
  /// default (see [GameDefinition.cardBacks]'s doc), with no separate step
  /// needed. Its name defaults to the picked file's own name, editable right
  /// after in its row -- same "pick first, refine after" flow `SetsTab`'s
  /// "Add Set..." uses.
  Future<void> _addCardBack() async {
    final file = await openFile(acceptedTypeGroups: imageFileTypes);
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final fileName = await widget.fileOps.copyPickedImage(sourcePath: file.path, destFolderPath: widget.folderPath);
      final newBack = CardBackDefinition(id: _uuid.v4(), name: stripExtension(fileName), imagePath: fileName);
      widget.onCardBacksChanged([...widget.cardBacks, newBack]);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _updateCardBack(int index, CardBackDefinition updated) {
    widget.onCardBacksChanged([
      for (var i = 0; i < widget.cardBacks.length; i++) if (i == index) updated else widget.cardBacks[i],
    ]);
  }

  void _deleteCardBack(int index) {
    widget.onCardBacksChanged([
      for (var i = 0; i < widget.cardBacks.length; i++) if (i != index) widget.cardBacks[i],
    ]);
  }

  /// See [_reorderGroups]'s identical doc -- reordering this list also
  /// changes which entry is the default (always index 0).
  void _reorderCardBacks(int oldIndex, int newIndex) {
    final backs = [...widget.cardBacks];
    final back = backs.removeAt(oldIndex);
    backs.insert(newIndex, back);
    widget.onCardBacksChanged(backs);
  }

  void _addGroup() {
    final trimmed = _newGroupNameController.text.trim();
    if (trimmed.isEmpty || widget.tagGroups.any((g) => g.name == trimmed)) return;
    widget.onTagGroupsChanged([...widget.tagGroups, TagGroup(id: _uuid.v4(), name: trimmed)]);
    _newGroupNameController.clear();
  }

  void _updateGroup(int index, TagGroup updated) {
    widget.onTagGroupsChanged([for (var i = 0; i < widget.tagGroups.length; i++) if (i == index) updated else widget.tagGroups[i]]);
  }

  void _deleteGroup(int index) {
    widget.onTagGroupsChanged([for (var i = 0; i < widget.tagGroups.length; i++) if (i != index) widget.tagGroups[i]]);
  }

  /// Reorders `tagGroups` itself, so the new order is reflected everywhere
  /// it's consumed in list order: the filter buttons (`MultiSelectFilterMenu`,
  /// Card View tab, Deck Editor) and the "Types" sections on the card detail
  /// form (`CardDetailPanel`). Passed as `onReorderItem`, whose `newIndex` is
  /// already adjusted for the removed item at `oldIndex` (unlike the
  /// deprecated `onReorder`).
  void _reorderGroups(int oldIndex, int newIndex) {
    final groups = [...widget.tagGroups];
    final group = groups.removeAt(oldIndex);
    groups.insert(newIndex, group);
    widget.onTagGroupsChanged(groups);
  }

  @override
  Widget build(BuildContext context) {
    super.build(context); // required by AutomaticKeepAliveClientMixin
    return ListView(
      padding: const EdgeInsets.all(24),
      children: [
        TextField(
          controller: _nameController,
          decoration: const InputDecoration(labelText: 'Game Name', border: OutlineInputBorder()),
          onChanged: widget.onNameChanged,
        ),
        const SizedBox(height: 24),
        const Text('Card Backs', style: TextStyle(fontWeight: FontWeight.bold)),
        Text(
          'The first one is this game\'s default -- drag to reorder and change which one that '
          'is. Each card can then pick a specific back (or "Unique") on the Card View tab.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 8),
        if (widget.cardBacks.isNotEmpty)
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorderItem: _reorderCardBacks,
            children: [
              for (var i = 0; i < widget.cardBacks.length; i++)
                Padding(
                  key: ValueKey(widget.cardBacks[i].id),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: _CardBackEditorRow(
                    folderPath: widget.folderPath,
                    fileOps: widget.fileOps,
                    cardBack: widget.cardBacks[i],
                    isDefault: i == 0,
                    onChanged: (updated) => _updateCardBack(i, updated),
                    onDelete: () => _deleteCardBack(i),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.add),
          label: const Text('Add Card Back...'),
          onPressed: _busy ? null : _addCardBack,
        ),
        const SizedBox(height: 24),
        const Text('Tag Groups', style: TextStyle(fontWeight: FontWeight.bold)),
        Text(
          'Drag to reorder groups or the tags within them -- this also reorders their filter buttons '
          'and the Types fields on each card.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 8),
        if (widget.tagGroups.isNotEmpty)
          ReorderableListView(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            onReorderItem: _reorderGroups,
            children: [
              for (var i = 0; i < widget.tagGroups.length; i++)
                Padding(
                  key: ValueKey(widget.tagGroups[i].id),
                  padding: const EdgeInsets.only(bottom: 12),
                  child: _TagGroupEditor(
                    group: widget.tagGroups[i],
                    onChanged: (updated) => _updateGroup(i, updated),
                    onDelete: () => _deleteGroup(i),
                  ),
                ),
            ],
          ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _newGroupNameController,
                decoration: const InputDecoration(labelText: 'New tag group', border: OutlineInputBorder()),
                onSubmitted: (_) => _addGroup(),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(icon: const Icon(Icons.add), tooltip: 'Add Tag Group', onPressed: _addGroup),
          ],
        ),
        const SizedBox(height: 24),
        const Text('Card IDs', style: TextStyle(fontWeight: FontWeight.bold)),
        Text(
          'Every card needs a unique ID. New imports are checked automatically, but this '
          'looks across all cards for any that still collide, so you can fix them by hand.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
        ),
        const SizedBox(height: 8),
        OutlinedButton.icon(
          icon: const Icon(Icons.copy_all_outlined),
          label: const Text('Check for Duplicate Card IDs...'),
          onPressed: () => showDuplicateCardIdsDialog(
            context,
            cards: widget.cards,
            sets: widget.sets,
            onChanged: widget.onCardsChanged,
          ),
        ),
      ],
    );
  }
}

/// One tag group's editor: an editable name field, a reorderable list of its
/// tags, and a per-group "add tag" row. Every mutation (rename, add/remove/
/// reorder a tag) is reported as a whole replacement [TagGroup] via
/// [onChanged] -- this widget holds no state of its own beyond its text
/// controllers. Keyed by the group's id (not its name, which is editable) so
/// those controllers survive both a rename and a group-level drag-reorder.
class _TagGroupEditor extends StatefulWidget {
  const _TagGroupEditor({required this.group, required this.onChanged, required this.onDelete});

  final TagGroup group;
  final ValueChanged<TagGroup> onChanged;
  final VoidCallback onDelete;

  @override
  State<_TagGroupEditor> createState() => _TagGroupEditorState();
}

class _TagGroupEditorState extends State<_TagGroupEditor> {
  late final TextEditingController _nameController = TextEditingController(text: widget.group.name);
  final TextEditingController _newTagController = TextEditingController();
  bool _expanded = false;
  bool _duplicateTag = false;

  @override
  void dispose() {
    _nameController.dispose();
    _newTagController.dispose();
    super.dispose();
  }

  void _addTag() {
    final trimmed = _newTagController.text.trim();
    if (trimmed.isEmpty) return;
    if (widget.group.tags.contains(trimmed)) {
      setState(() => _duplicateTag = true);
      return;
    }
    widget.onChanged(widget.group.copyWith(tags: [...widget.group.tags, trimmed]));
    _newTagController.clear();
    if (_duplicateTag) setState(() => _duplicateTag = false);
  }

  void _removeTag(String tag) {
    widget.onChanged(widget.group.copyWith(tags: widget.group.tags.where((t) => t != tag).toList()));
  }

  void _reorderTags(int oldIndex, int newIndex) {
    final tags = [...widget.group.tags];
    final tag = tags.removeAt(oldIndex);
    tags.insert(newIndex, tag);
    widget.onChanged(widget.group.copyWith(tags: tags));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: ExpansionTile(
        initiallyExpanded: false,
        onExpansionChanged: (v) => setState(() => _expanded = v),
        title: Text(widget.group.name.isEmpty ? '(unnamed group)' : widget.group.name),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Delete Group', onPressed: widget.onDelete),
            Icon(_expanded ? Icons.expand_less : Icons.expand_more),
          ],
        ),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Group Name', border: OutlineInputBorder(), isDense: true),
                  onChanged: (v) => widget.onChanged(widget.group.copyWith(name: v)),
                ),
                const SizedBox(height: 8),
                if (widget.group.tags.isNotEmpty)
                  ReorderableListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    onReorderItem: _reorderTags,
                    children: [
                      for (final tag in widget.group.tags)
                        ListTile(
                          key: ValueKey(tag),
                          dense: true,
                          shape: RoundedRectangleBorder(
                            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          title: Text(tag),
                          trailing: IconButton(
                            icon: const Icon(Icons.close),
                            tooltip: 'Remove Tag',
                            onPressed: () => _removeTag(tag),
                          ),
                        ),
                    ],
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _newTagController,
                        decoration: InputDecoration(
                          labelText: 'New tag',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          errorText: _duplicateTag ? 'Tag already exists' : null,
                        ),
                        onChanged: (_) {
                          if (_duplicateTag) setState(() => _duplicateTag = false);
                        },
                        onSubmitted: (_) => _addTag(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(icon: const Icon(Icons.add), tooltip: 'Add Tag', onPressed: _addTag),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// One [CardBackDefinition]'s editor row: a thumbnail, an editable name, its
/// own "Choose Image.../Clear" pair (same `copyPickedImage` plumbing every
/// other image picker in this editor uses), and a delete button. Every
/// mutation is reported as a whole replacement [CardBackDefinition] via
/// [onChanged] -- this widget holds no state of its own beyond its name
/// controller and a local busy flag for the image picker.
class _CardBackEditorRow extends StatefulWidget {
  const _CardBackEditorRow({
    required this.folderPath,
    required this.fileOps,
    required this.cardBack,
    required this.isDefault,
    required this.onChanged,
    required this.onDelete,
  });

  final String folderPath;
  final GameDefinitionFileOps fileOps;
  final CardBackDefinition cardBack;

  /// Whether this is `GameDefinition.cardBacks`' first entry -- purely a
  /// display label here, derived from list position by the parent rather
  /// than stored on the model itself.
  final bool isDefault;
  final ValueChanged<CardBackDefinition> onChanged;
  final VoidCallback onDelete;

  @override
  State<_CardBackEditorRow> createState() => _CardBackEditorRowState();
}

class _CardBackEditorRowState extends State<_CardBackEditorRow> {
  late final TextEditingController _nameController = TextEditingController(text: widget.cardBack.name);
  bool _busy = false;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _chooseImage() async {
    final file = await openFile(acceptedTypeGroups: imageFileTypes);
    if (file == null || !mounted) return;
    setState(() => _busy = true);
    try {
      final fileName = await widget.fileOps.copyPickedImage(sourcePath: file.path, destFolderPath: widget.folderPath);
      widget.onChanged(widget.cardBack.copyWith(imagePath: fileName));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final resolved = resolvedImagePathForDisplay(widget.folderPath, bareImagePath: widget.cardBack.imagePath);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _ImagePreviewBox(resolvedPath: resolved),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: _nameController,
                    decoration: InputDecoration(
                      labelText: widget.isDefault ? 'Name (Default)' : 'Name',
                      border: const OutlineInputBorder(),
                      isDense: true,
                    ),
                    onChanged: (v) => widget.onChanged(widget.cardBack.copyWith(name: v)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      OutlinedButton(onPressed: _busy ? null : _chooseImage, child: const Text('Choose Image...')),
                      if (widget.cardBack.imagePath != null)
                        TextButton(
                          onPressed: _busy ? null : () => widget.onChanged(widget.cardBack.copyWith(imagePath: null)),
                          child: const Text('Clear'),
                        ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<CardOrientation>(
                    initialValue: widget.cardBack.orientation,
                    decoration:
                        const InputDecoration(labelText: 'Orientation', border: OutlineInputBorder(), isDense: true),
                    items: [for (final o in CardOrientation.values) DropdownMenuItem(value: o, child: Text(o.name))],
                    onChanged: (v) {
                      if (v != null) widget.onChanged(widget.cardBack.copyWith(orientation: v));
                    },
                  ),
                ],
              ),
            ),
            IconButton(icon: const Icon(Icons.delete_outline), tooltip: 'Remove Card Back', onPressed: widget.onDelete),
          ],
        ),
      ),
    );
  }
}

class _ImagePreviewBox extends StatelessWidget {
  const _ImagePreviewBox({required this.resolvedPath});

  final String? resolvedPath;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: cardWidth,
      height: cardHeight,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outline),
        borderRadius: BorderRadius.circular(6),
      ),
      child: resolvedPath == null
          ? Icon(Icons.image_not_supported_outlined, color: Theme.of(context).colorScheme.outline)
          : ClipRRect(
              borderRadius: BorderRadius.circular(5),
              child: Image.file(
                File(resolvedPath!),
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    Icon(Icons.broken_image_outlined, color: Theme.of(context).colorScheme.outline),
              ),
            ),
    );
  }
}
