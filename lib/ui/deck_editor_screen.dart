import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../models/card_definition.dart';
import '../models/deck_config.dart';
import '../models/game_definition.dart';
import 'widgets/card_face_widget.dart';

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

  int get _totalCards => _quantities.values.fold(0, (a, b) => a + b);

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

  Widget _buildPoolRow(CardDefinition card) {
    final color = Color(int.parse((card.colorHex ?? '#9E9E9E').replaceFirst('#', '0xFF')));
    final quantity = _quantities[card.id] ?? 0;
    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredDefinitionId = card.id),
      onExit: (_) => setState(() {
        if (_hoveredDefinitionId == card.id) _hoveredDefinitionId = null;
      }),
      child: GestureDetector(
        onTap: () => _addCopy(card.id),
        onSecondaryTap: () => _removeCopy(card.id),
        child: ListTile(
          leading: CircleAvatar(backgroundColor: color, child: Text(card.cardTitle, style: const TextStyle(color: Colors.white, fontSize: 12))),
          title: Text(card.cardTitle),
          subtitle: card.suit != null ? Text(card.suit!) : null,
          trailing: quantity > 0 ? Text('×$quantity', style: const TextStyle(fontWeight: FontWeight.bold)) : null,
        ),
      ),
    );
  }

  Widget _buildPreviewPanel() {
    final hovered = _hoveredDefinitionId == null ? null : _definitionsById[_hoveredDefinitionId];
    return Container(
      width: 320,
      color: Colors.black.withValues(alpha: 0.05),
      alignment: Alignment.center,
      child: hovered == null
          ? const Text('Hover a card to preview', style: TextStyle(color: Colors.black45))
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    width: 240,
                    height: 240 * (cardHeight / cardWidth),
                    child: FittedBox(
                      fit: BoxFit.contain,
                      child: SizedBox(width: cardWidth, height: cardHeight, child: CardFaceWidget(definition: hovered)),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(hovered.cardTitle, style: const TextStyle(fontWeight: FontWeight.bold), textAlign: TextAlign.center),
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
            child: ListView.builder(
              itemCount: widget.game.cards.length,
              itemBuilder: (context, index) => _buildPoolRow(widget.game.cards[index]),
            ),
          ),
          const VerticalDivider(width: 1),
          _buildPreviewPanel(),
          const VerticalDivider(width: 1),
          SizedBox(width: 280, child: _buildDeckPanel()),
        ],
      ),
    );
  }
}
