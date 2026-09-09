import 'dart:convert';
import 'dart:io';
import 'dart:math' show pi;

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../models/card_definition.dart';
import '../models/deck_config.dart';
import '../models/game_definition.dart';
import '../models/tag_group.dart';
import 'widgets/card_face_widget.dart';
import 'widgets/multi_select_filter_menu.dart';

const List<XTypeGroup> _deckFileTypes = [
  XTypeGroup(label: 'Deck', extensions: ['json']),
];

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

class _DeckEditorScreenState extends State<DeckEditorScreen> {
  late final Map<String, CardDefinition> _definitionsById = {for (final c in widget.game.cards) c.id: c};

  final Map<String, int> _quantities = {};
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

  int get _totalCards => _quantities.values.fold(0, (a, b) => a + b);

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
    return tagsOk && setOk;
  }

  List<CardDefinition> get _visibleCards => widget.game.cards.where(_isVisible).toList();

  void _addCopy(String definitionId) {
    setState(() => _quantities[definitionId] = (_quantities[definitionId] ?? 0) + 1);
  }

  void _removeCopy(String definitionId) {
    final current = _quantities[definitionId];
    if (current == null) return;
    setState(() {
      if (current <= 1) {
        _quantities.remove(definitionId);
      } else {
        _quantities[definitionId] = current - 1;
      }
    });
  }

  Future<void> _saveDeck() async {
    final deckConfig = DeckConfig(
      gameId: widget.game.id,
      entries: [
        for (final entry in _quantities.entries) DeckEntry(definitionId: entry.key, quantity: entry.value),
      ],
    );
    final location = await getSaveLocation(
      suggestedName: '${widget.game.name} Deck.json',
      acceptedTypeGroups: _deckFileTypes,
    );
    if (location == null || !mounted) return;
    final path = location.path;
    final file = File(path.toLowerCase().endsWith('.json') ? path : '$path.json');
    await file.writeAsString(jsonEncode(deckConfig.toJson()));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to ${file.path}')));
  }

  Future<void> _openDeck() async {
    final file = await openFile(acceptedTypeGroups: _deckFileTypes);
    if (file == null || !mounted) return;
    DeckConfig deckConfig;
    try {
      final raw = await file.readAsString();
      deckConfig = DeckConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('That file is not a valid deck.')));
      return;
    }
    if (deckConfig.gameId != widget.game.id) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('That deck is for a different game (${deckConfig.gameId}).')),
      );
      return;
    }
    setState(() {
      _quantities
        ..clear()
        ..addEntries(deckConfig.entries.where((e) => _definitionsById.containsKey(e.definitionId)).map(
              (e) => MapEntry(e.definitionId, e.quantity),
            ));
    });
  }

  /// The set-filter dropdown shown above the type filter dropdown -- empty
  /// (no widget) for a game that declares no [GameDefinition.sets]. Set
  /// filtering takes precedence over Type filtering (see [_isVisible]), so
  /// it's shown first/above.
  Widget _buildSetFilterBar() {
    if (widget.game.sets.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: MultiSelectFilterMenu(
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
      ),
    );
  }

  /// One filter button per non-empty tag group, wrapped so any number of
  /// groups flows onto further lines -- empty (no widget) for a game that
  /// declares no [GameDefinition.tagGroups], so the feature is entirely
  /// invisible unless a game opts in.
  Widget _buildTagGroupFilterBars() {
    final nonEmptyGroups = widget.game.tagGroups.where((g) => g.tags.isNotEmpty).toList();
    if (nonEmptyGroups.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
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
    );
  }

  /// One pool tile: the real card face at its native table size (not
  /// scaled), with the same left-click-to-add/right-click-to-remove wiring
  /// and hover-preview tracking the old text row had, plus a quantity badge
  /// overlaid on the face and a title underneath (still needed for real-art
  /// cards whose image has no title baked in).
  Widget _buildPoolCard(CardDefinition card) {
    final quantity = _quantities[card.id] ?? 0;
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

  Widget _buildPreviewPanel() {
    final hovered = _hoveredDefinitionId == null ? null : _definitionsById[_hoveredDefinitionId];
    return Container(
      color: Colors.black.withValues(alpha: 0.05),
      alignment: Alignment.center,
      child: hovered == null
          ? const Text('Hover a card to preview', style: TextStyle(color: Colors.black45))
          : Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                children: [
                  Expanded(
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: RotatedBox(
                        quarterTurns: orientationQuarterTurns(hovered.orientation),
                        child: SizedBox(width: cardWidth, height: cardHeight, child: CardFaceWidget(definition: hovered)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(hovered.cardTitle, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18), textAlign: TextAlign.center),
                ],
              ),
            ),
    );
  }

  Widget _buildDeckPanel() {
    final entries = _quantities.entries.toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: Text('Deck -- $_totalCards card(s)', style: const TextStyle(fontWeight: FontWeight.bold)),
        ),
        const Divider(height: 1),
        Expanded(
          child: entries.isEmpty
              ? const Center(child: Text('Left-click a card to add it', style: TextStyle(color: Colors.black45)))
              : ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final title = _definitionsById[entry.key]?.cardTitle ?? entry.key;
                    return ListTile(
                      dense: true,
                      title: Text(title),
                      trailing: Text('×${entry.value}'),
                    );
                  },
                ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
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
                      _buildSetFilterBar(),
                      _buildTagGroupFilterBars(),
                      Expanded(
                        child: GridView.builder(
                          padding: const EdgeInsets.all(12),
                          gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: cardWidth + 24,
                            mainAxisExtent: cardHeight + 28,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemCount: _visibleCards.length,
                          itemBuilder: (context, index) => _buildPoolCard(_visibleCards[index]),
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
