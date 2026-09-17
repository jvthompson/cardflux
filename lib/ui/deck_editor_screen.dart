import 'dart:convert';
import 'dart:io';
import 'dart:math' show pi;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/deck_library_loader.dart';
import '../data/decks_directory_settings.dart';
import '../data/directory_picker.dart';
import '../data/image_path_resolver.dart';
import '../models/card_definition.dart';
import '../models/deck_config.dart';
import '../models/game_definition.dart';
import '../models/tag_group.dart';
import 'widgets/card_back_widget.dart';
import 'widgets/card_face_widget.dart';
import 'widgets/move_library_prompt.dart';
import 'widgets/multi_select_filter_menu.dart';

const List<XTypeGroup> _deckFileTypes = [
  XTypeGroup(label: 'Deck', extensions: ['json']),
];

/// Validates a user-typed deck name as a filesystem file name (minus the
/// `.json` extension). Whether `<gameFolder>/<name>.json` already exists is
/// checked separately (async) by the caller -- mirrors
/// `game_definition_editor_entry_screen.dart`'s `_validateGameId`.
String? _validateDeckName(String name) {
  if (name.isEmpty) return 'Enter a deck name.';
  if (name == '.' || name == '..') return 'Invalid name.';
  const reserved = r'/\:*?"<>|';
  if (name.split('').any(reserved.contains)) {
    return 'Name cannot contain: / \\ : * ? " < > |';
  }
  return null;
}

/// Returns the Deck Library root to save/open decks under (see
/// [DecksDirectorySettings], the same folder `DeckLibraryScreen` scans
/// elsewhere) -- always resolvable, since an unset preference falls back to
/// a default folder alongside the app itself, so no prompt is ever needed
/// here.
Future<String> _resolveDecksLibraryRoot() => DecksDirectorySettings().getPath();

/// Modal name prompt for saving a deck under [libraryRoot]/[gameId]/.
/// Validates synchronously via [_validateDeckName] on every submit attempt,
/// then asynchronously checks whether `<libraryRoot>/<gameId>/<name>.json`
/// already exists -- if so, flips into an inline overwrite-confirmation
/// state rather than blocking outright.
Future<String?> _promptForDeckName(
  BuildContext context, {
  required String libraryRoot,
  required String gameId,
  required String initialName,
}) async {
  final controller = TextEditingController(text: initialName);
  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      String? error;
      bool checking = false;
      bool confirmingOverwrite = false;
      String pendingName = '';
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> submit() async {
            final name = controller.text.trim();
            final syncError = _validateDeckName(name);
            if (syncError != null) {
              setState(() => error = syncError);
              return;
            }
            setState(() {
              checking = true;
              error = null;
            });
            final exists = await File(
              '$libraryRoot${Platform.pathSeparator}$gameId${Platform.pathSeparator}$name.json',
            ).exists();
            if (exists) {
              // Same reasoning as below -- this swaps the dialog's content
              // from the name TextField to the plain overwrite-confirmation
              // text, tearing the (still-focused) field down mid-route.
              if (context.mounted) FocusScope.of(context).unfocus();
              setState(() {
                checking = false;
                confirmingOverwrite = true;
                pendingName = name;
              });
              return;
            }
            if (!context.mounted) return;
            // Drop focus before popping -- the name field is `autofocus`, and
            // popping this route while it (or the framework's own focus
            // machinery) still has it focused can tear down the Focus/
            // FocusScope InheritedElement while something still depends on
            // it, tripping a `_dependents.isEmpty` assertion in debug builds.
            FocusScope.of(context).unfocus();
            Navigator.of(context).pop(name);
          }

          if (confirmingOverwrite) {
            return AlertDialog(
              title: const Text('Overwrite Deck?'),
              content: Text('A deck named "$pendingName" already exists in the library. Overwrite it?'),
              actions: [
                TextButton(
                  onPressed: () => setState(() => confirmingOverwrite = false),
                  child: const Text('Cancel'),
                ),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(pendingName),
                  child: const Text('Overwrite'),
                ),
              ],
            );
          }

          return AlertDialog(
            title: const Text('Save Deck'),
            content: TextField(
              controller: controller,
              autofocus: true,
              enabled: !checking,
              decoration: InputDecoration(labelText: 'Deck Name', errorText: error),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: checking ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(onPressed: checking ? null : submit, child: const Text('Save')),
            ],
          );
        },
      );
    },
  );
  controller.dispose();
  return result;
}

/// Modal deck picker for opening a deck already saved under
/// `<libraryRoot>/<game.id>/` -- lists every [DeckLibraryEntry] found there
/// (via [DeckLibraryLoader]), lets the user change the Deck Library folder
/// in place, and falls back to browsing for a one-off file elsewhere (the
/// same `openFile` flow the old `_openDeck` used directly). Mirrors
/// `DeckLibraryScreen`'s directory-scan/change-folder/browse-fallback shape,
/// simplified to a single-selection list (no per-zone drag targets -- the
/// editor has just one deck, not one per seat).
class _DeckLibraryPickerDialog extends StatefulWidget {
  const _DeckLibraryPickerDialog({required this.libraryRoot, required this.game});

  final String libraryRoot;
  final GameDefinition game;

  @override
  State<_DeckLibraryPickerDialog> createState() => _DeckLibraryPickerDialogState();
}

class _DeckLibraryPickerDialogState extends State<_DeckLibraryPickerDialog> {
  final DeckLibraryLoader _loader = DeckLibraryLoader();
  late String _libraryRoot = widget.libraryRoot;
  DeckLibraryScanResult? _scan;
  String? _error;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    setState(() {
      _scan = null;
      _error = null;
    });
    try {
      final scan = await _loader.loadDecksForGame(_libraryRoot, widget.game);
      if (!mounted) return;
      setState(() => _scan = scan);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Could not read that folder: $e');
    }
  }

  Future<void> _changeFolder() async {
    final chosen = await pickDirectoryPath();
    if (chosen == null || !mounted) return;
    await maybeMoveLibraryFolder(context, oldRoot: _libraryRoot, newRoot: chosen, whatLabel: 'deck');
    if (!mounted) return;
    await DecksDirectorySettings().setPath(chosen);
    if (!mounted) return;
    setState(() => _libraryRoot = chosen);
    await _refresh();
  }

  Future<void> _browseSingleFile() async {
    final file = await openFile(acceptedTypeGroups: _deckFileTypes);
    if (file == null || !mounted) return;
    DeckConfig deckConfig;
    try {
      final raw = await file.readAsString();
      deckConfig = DeckConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } on LegacyDeckFormatException catch (e) {
      if (!mounted) return;
      setState(() => _error = '$e');
      return;
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'That file is not a valid deck.');
      return;
    }
    if (deckConfig.gameId != widget.game.id) {
      if (!mounted) return;
      setState(() => _error = 'That deck is for a different game (${deckConfig.gameId}).');
      return;
    }
    if (mounted) Navigator.of(context).pop(deckConfig);
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Open Deck -- ${widget.game.name}'),
      content: SizedBox(
        width: 360,
        height: 360,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _libraryRoot,
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                IconButton(
                  tooltip: 'Change Deck Library Folder...',
                  icon: const Icon(Icons.folder_open),
                  onPressed: _changeFolder,
                ),
              ],
            ),
            const Divider(),
            Expanded(
              child: _error != null
                  ? Center(
                      child: Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
                    )
                  : _scan == null
                      ? const Center(child: CircularProgressIndicator(strokeWidth: 2))
                      : (_scan!.entries.isEmpty && _scan!.incompatible.isEmpty)
                          ? Center(
                              child: Text(
                                'No decks found for ${widget.game.name}.',
                                style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                              ),
                            )
                          : ListView(
                              children: [
                                for (final entry in _scan!.entries)
                                  ListTile(
                                    dense: true,
                                    title: Text(entry.displayName),
                                    trailing: Text('${entry.cardCount} card(s)'),
                                    onTap: () => Navigator.of(context).pop(entry.deck),
                                  ),
                                for (final file in _scan!.incompatible)
                                  ListTile(
                                    dense: true,
                                    enabled: false,
                                    title: Text(file.displayName),
                                    subtitle: const Text(
                                      'Old format -- rebuild in the Deck Editor',
                                      style: TextStyle(color: Colors.red),
                                    ),
                                  ),
                              ],
                            ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: _browseSingleFile, child: const Text('Browse for a different file...')),
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
      ],
    );
  }
}

/// Standalone deck-authoring screen (not part of the host-a-game flow):
/// browse every card in [game], left-click a card to add a copy to the deck
/// being built, right-click to remove one, and save/open the result as a
/// [DeckConfig] JSON file. Unlike `DeckBuildScreen` (which starts from the
/// full deck for an about-to-start match), a deck here starts empty -- this
/// is for authoring a deck ahead of time, not trimming one down right before
/// playing.
class DeckEditorScreen extends StatefulWidget {
  const DeckEditorScreen({super.key, required this.game});

  final GameDefinition game;

  @override
  State<DeckEditorScreen> createState() => _DeckEditorScreenState();
}

/// One deck-authoring slot: a named subdeck the player builds independently
/// of any other slot, labeled by the zone(s) that consume it (see
/// `ZoneDefinition.deckType`/`deckOptional`). A game with no deck-building
/// zones gets a single implicit `main_deck` slot so it can still be edited.
class _DeckSlot {
  const _DeckSlot({required this.deckType, required this.label, required this.required});

  final String deckType;
  final String label;
  final bool required;
}

class _DeckEditorScreenState extends State<DeckEditorScreen> {
  late final Map<String, CardDefinition> _definitionsById = {for (final c in widget.game.cards) c.id: c};

  /// One slot per distinct [ZoneDefinition.deckType] the game declares (see
  /// [GameDefinition.deckTypes]), or a single implicit `main_deck` slot for a
  /// game with no deck-building zones -- a type is [_DeckSlot.required] if
  /// any zone using it isn't marked `deckOptional`.
  late final List<_DeckSlot> _slots = _buildSlots();

  List<_DeckSlot> _buildSlots() {
    final zones = widget.game.deckBuildingZones;
    if (zones.isEmpty) {
      return const [_DeckSlot(deckType: 'main_deck', label: 'Deck', required: true)];
    }
    final byType = <String, _DeckSlot>{};
    for (final z in zones) {
      final wasRequired = byType[z.deckType]?.required ?? false;
      byType[z.deckType] = _DeckSlot(
        deckType: z.deckType,
        label: byType[z.deckType]?.label ?? z.name,
        required: wasRequired || !z.deckOptional,
      );
    }
    return byType.values.toList();
  }

  late final Map<String, Map<String, int>> _quantitiesBySlot = {
    for (final s in _slots) s.deckType: <String, int>{},
  };
  late String _activeDeckType = _slots.first.deckType;
  Map<String, int> get _activeQuantities => _quantitiesBySlot[_activeDeckType]!;
  String? _hoveredDefinitionId;

  /// Per-group set of which of that group's tags currently show in the pool,
  /// keyed by [TagGroup.id] -- every tag starts selected (nothing hidden).
  /// A game's [GameDefinition.tagGroups] here is fixed for this screen's
  /// lifetime (unlike the Game Definition Editor's Card View tab), so this
  /// can be a plain `late final` seeded once, no `didUpdateWidget` sync.
  late final Map<String, Set<String>> _selectedTagsByGroup = {
    for (final g in widget.game.tagGroups) g.id: g.tags.toSet(),
  };

  /// Per-group set of which of that group's tags are actively excluded --
  /// starts empty (nothing excluded) for every group. Mutually exclusive
  /// with [_selectedTagsByGroup] per tag: toggling a tag into one clears it
  /// from the other (see the `onToggle`/`onToggleExclude` handlers in
  /// [_buildTagGroupFilterBars]), so a tag is never both at once.
  late final Map<String, Set<String>> _excludedTagsByGroup = {
    for (final g in widget.game.tagGroups) g.id: <String>{},
  };

  /// Which of [GameDefinition.sets] currently show in the pool -- every set
  /// starts selected. Ignored entirely when the game declares no sets at
  /// all, in which case the filter bar doesn't render.
  late final Set<String> _selectedSetIds = widget.game.sets.map((s) => s.id).toSet();

  /// Case-insensitive substring search against card title and ID, combined
  /// with the tag/set filters in [_isVisible]; empty means no search filter.
  String _searchQuery = '';

  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  int get _totalCards => _activeQuantities.values.fold(0, (a, b) => a + b);

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
  /// [_allSelectedTags] (see [_isVisible]).
  Set<String> get _allExcludedTags => {for (final s in _excludedTagsByGroup.values) ...s};

  /// A card with no tags at all is never hidden by the tag filters, and a
  /// card with no set is never hidden by the set filter.
  bool _isVisible(CardDefinition card) {
    if (card.types.any(_allExcludedTags.contains)) return false;
    final tagsOk = widget.game.tagGroups.isEmpty || card.types.isEmpty || card.types.any(_allSelectedTags.contains);
    final setOk = widget.game.sets.isEmpty || card.setId == null || _selectedSetIds.contains(card.setId);
    final query = _searchQuery.trim().toLowerCase();
    final searchOk =
        query.isEmpty || card.cardTitle.toLowerCase().contains(query) || card.id.toLowerCase().contains(query);
    return tagsOk && setOk && searchOk;
  }

  List<CardDefinition> get _visibleCards => widget.game.cards.where(_isVisible).toList();

  void _addCopy(String definitionId) {
    setState(() => _activeQuantities[definitionId] = (_activeQuantities[definitionId] ?? 0) + 1);
  }

  void _removeCopy(String definitionId) {
    final current = _activeQuantities[definitionId];
    if (current == null) return;
    setState(() {
      if (current <= 1) {
        _activeQuantities.remove(definitionId);
      } else {
        _activeQuantities[definitionId] = current - 1;
      }
    });
  }

  Future<void> _saveDeck() async {
    final missingRequired = [
      for (final s in _slots)
        if (s.required && (_quantitiesBySlot[s.deckType]?.values.fold<int>(0, (a, b) => a + b) ?? 0) == 0) s.label,
    ];
    if (missingRequired.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Add at least one card to: ${missingRequired.join(', ')} before saving.')),
      );
      return;
    }
    final root = await _resolveDecksLibraryRoot();
    if (!mounted) return;
    final name = await _promptForDeckName(
      context,
      libraryRoot: root,
      gameId: widget.game.id,
      initialName: '${widget.game.name} Deck',
    );
    if (name == null || !mounted) return;
    final deckConfig = DeckConfig(
      gameId: widget.game.id,
      subdecks: [
        for (final s in _slots)
          SubDeck(
            name: s.deckType,
            entries: [
              for (final entry in (_quantitiesBySlot[s.deckType] ?? const {}).entries)
                DeckEntry(definitionId: entry.key, quantity: entry.value),
            ],
          ),
      ],
    );
    final folderPath = '$root${Platform.pathSeparator}${widget.game.id}';
    await Directory(folderPath).create(recursive: true);
    final file = File('$folderPath${Platform.pathSeparator}$name.json');
    await file.writeAsString(jsonEncode(deckConfig.toJson()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to ${file.path}')));
  }

  Future<void> _openDeck() async {
    final root = await _resolveDecksLibraryRoot();
    if (!mounted) return;
    final deckConfig = await showDialog<DeckConfig>(
      context: context,
      builder: (_) => _DeckLibraryPickerDialog(libraryRoot: root, game: widget.game),
    );
    if (deckConfig == null || !mounted) return;
    if (deckConfig.gameId != widget.game.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('That deck is for a different game (${deckConfig.gameId}).')),
      );
      return;
    }
    setState(() {
      for (final s in _slots) {
        _quantitiesBySlot[s.deckType]!
          ..clear()
          ..addEntries(
            deckConfig
                .entriesFor(s.deckType)
                .where((e) => _definitionsById.containsKey(e.definitionId))
                .map((e) => MapEntry(e.definitionId, e.quantity)),
          );
      }
    });
  }

  /// Resets every Set/Type filter to fully permissive -- every option
  /// selected, nothing excluded -- i.e. "no filtering in effect." An empty
  /// selection would instead hide every card that has tags (see
  /// [_isVisible]), so "off" means select-all, not select-none.
  void _clearFilters() {
    setState(() {
      _selectedSetIds
        ..clear()
        ..addAll(widget.game.sets.map((s) => s.id));
      for (final group in widget.game.tagGroups) {
        _selectedTagsByGroup[group.id] = group.tags.toSet();
        _excludedTagsByGroup[group.id]!.clear();
      }
    });
  }

  /// The Set filter (always first) plus one filter button per non-empty tag
  /// group, combined into a single wrapped row with a "Clear Filters" action
  /// above it -- empty (no widget) for a game with neither sets nor tag
  /// groups declared.
  Widget _buildFilterBar() {
    final nonEmptyGroups = widget.game.tagGroups.where((g) => g.tags.isNotEmpty).toList();
    if (widget.game.sets.isEmpty && nonEmptyGroups.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
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
              if (widget.game.sets.isNotEmpty)
                MultiSelectFilterMenu(
                  label: 'Set',
                  options: [for (final set in widget.game.sets) (id: set.id, name: set.name)],
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
            ],
          ),
        ],
      ),
    );
  }

  /// Case-insensitive search box for card title/ID, shown beneath the set
  /// and tag filter bars -- see [_isVisible] for how [_searchQuery] combines
  /// with the other filters.
  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
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

  /// One pool tile: the real card face at its native table size (not
  /// scaled), with the same left-click-to-add/right-click-to-remove wiring
  /// and hover-preview tracking the old text row had, plus a quantity badge
  /// overlaid on the face and a title underneath (still needed for real-art
  /// cards whose image has no title baked in).
  Widget _buildPoolCard(CardDefinition card) {
    final quantity = _activeQuantities[card.id] ?? 0;
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredDefinitionId = card.id),
      onExit: (_) => setState(() {
        if (_hoveredDefinitionId == card.id) _hoveredDefinitionId = null;
      }),
      child: GestureDetector(
        onTap: () => _addCopy(card.id),
        onSecondaryTap: () => _removeCopy(card.id),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Stack(
              clipBehavior: Clip.none,
              children: [
                Transform.rotate(
                  angle: orientationTurns(card.orientation) * 2 * pi,
                  child: SizedBox(width: cardWidth, height: cardHeight, child: CardFaceWidget(definition: card)),
                ),
                if (quantity > 0)
                  Positioned(
                    top: -6,
                    right: -6,
                    child: CircleAvatar(
                      radius: 11,
                      backgroundColor: Colors.black87,
                      child: Text('$quantity', style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold)),
                    ),
                  ),
              ],
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
      ),
    );
  }

  Widget _frontPreview(CardDefinition card) {
    return FittedBox(
      fit: BoxFit.contain,
      child: RotatedBox(
        quarterTurns: orientationQuarterTurns(card.orientation),
        child: SizedBox(width: cardWidth, height: cardHeight, child: CardFaceWidget(definition: card)),
      ),
    );
  }

  Widget _backPreview(CardDefinition card) {
    // `widget.game` is loaded via `GameLoader`/`GamePicker`, so `imagePath` is
    // already absolute here -- unlike the Game Definition Editor's Card View
    // tab, no display-only resolved copy is needed for the "Unique" lookup.
    final orientation = resolveCardBackImagePath(cardBacks: widget.game.cardBacks, card: card).orientation;
    return FittedBox(
      fit: BoxFit.contain,
      child: RotatedBox(
        quarterTurns: orientationQuarterTurns(orientation),
        child: SizedBox(width: cardWidth, height: cardHeight, child: CardBackWidget(cardBacks: widget.game.cardBacks, card: card)),
      ),
    );
  }

  Widget _labeledPreview(String label, Widget pane) {
    return Column(
      children: [
        Expanded(child: pane),
        const SizedBox(height: 8),
        Text(label, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12)),
      ],
    );
  }

  Widget _buildPreviewPanel() {
    final hovered = _hoveredDefinitionId == null ? null : _definitionsById[_hoveredDefinitionId];
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      alignment: Alignment.center,
      child: hovered == null
          ? Text('Hover a card to preview', style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant))
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Expanded(
                    child: hovered.cardBackId == null
                        ? _frontPreview(hovered)
                        : Row(
                            children: [
                              Expanded(child: _labeledPreview('Front', _frontPreview(hovered))),
                              const SizedBox(width: 12),
                              Expanded(child: _labeledPreview('Back', _backPreview(hovered))),
                            ],
                          ),
                  ),
                  const SizedBox(height: 16),
                  Text(hovered.cardTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18), textAlign: TextAlign.center),
                ],
              ),
            ),
    );
  }

  /// Switches which subdeck [_activeDeckType] is currently being edited --
  /// shown only when the game declares more than one deck type, labeled by
  /// the zone name(s) that consume each one, per the Deck Editor's "refer to
  /// them by the Zone Name" convention.
  Widget _buildSlotSwitcher() {
    if (_slots.length <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: SegmentedButton<String>(
        segments: [for (final s in _slots) ButtonSegment(value: s.deckType, label: Text(s.label))],
        selected: {_activeDeckType},
        onSelectionChanged: (selection) => setState(() => _activeDeckType = selection.first),
      ),
    );
  }

  Widget _buildDeckPanel() {
    final entries = _activeQuantities.entries.toList();
    final activeLabel = _slots.firstWhere((s) => s.deckType == _activeDeckType).label;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSlotSwitcher(),
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text('$activeLabel -- $_totalCards card(s)', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        const Divider(height: 1),
        Expanded(
          child: entries.isEmpty
              ? Center(
                  child: Text(
                    'Left-click a card to add it',
                    style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                )
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final title = _definitionsById[entry.key]?.cardTitle ?? entry.key;
                    return MouseRegion(
                      onEnter: (_) => setState(() => _hoveredDefinitionId = entry.key),
                      onExit: (_) => setState(() {
                        if (_hoveredDefinitionId == entry.key) _hoveredDefinitionId = null;
                      }),
                      child: ListTile(
                        dense: true,
                        title: Text(title),
                        trailing: Text('×${entry.value}'),
                        onTap: () => _removeCopy(entry.key),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final visibleCards = _visibleCards;
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Deck -- ${widget.game.name}'),
        actions: [
          IconButton(icon: const Icon(Icons.folder_open), tooltip: 'Open Deck...', onPressed: _openDeck),
          IconButton(icon: const Icon(Icons.save), tooltip: 'Save Deck...', onPressed: _saveDeck),
        ],
      ),
      body: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildFilterBar(),
                      _buildSearchField(),
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
                          itemBuilder: (context, index) => _buildPoolCard(visibleCards[index]),
                        ),
                      ),
                    ],
                  ),
                ),
                const VerticalDivider(width: 1),
                SizedBox(width: 280, child: _buildDeckPanel()),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(child: _buildPreviewPanel()),
        ],
      ),
    );
  }
}
