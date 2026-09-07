import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../models/deck_config.dart';
import '../../models/game_definition.dart';

const List<XTypeGroup> _deckFileTypes = [
  XTypeGroup(label: 'Deck', extensions: ['json']),
];

/// Lets a player load a pre-built deck file (the same JSON the standalone
/// Deck Editor produces) for [game], then calls [onDeckChosen]. Shared by
/// the host's and the client's Load Deck screens -- both need the identical
/// load/validate step, differing only in what happens with the result and
/// how "waiting for the other player" is shown around it. Reuses the exact
/// load/validate pattern from `DeckEditorScreen._openDeck`.
class LoadDeckScreen extends StatefulWidget {
  const LoadDeckScreen({super.key, required this.game, required this.onDeckChosen});

  final GameDefinition game;
  final ValueChanged<DeckConfig> onDeckChosen;

  @override
  State<LoadDeckScreen> createState() => _LoadDeckScreenState();
}

class _LoadDeckScreenState extends State<LoadDeckScreen> {
  String? _loadedFileName;
  int? _loadedCardCount;
  String? _error;

  Future<void> _loadDeck() async {
    final file = await openFile(acceptedTypeGroups: _deckFileTypes);
    if (file == null || !mounted) return;
    DeckConfig deckConfig;
    try {
      final raw = await file.readAsString();
      deckConfig = DeckConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
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
    setState(() {
      _error = null;
      _loadedFileName = file.name;
      _loadedCardCount = deckConfig.entries.fold<int>(0, (a, e) => a + e.quantity);
    });
    widget.onDeckChosen(deckConfig);
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Load your deck for ${widget.game.name}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: _loadDeck,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(_loadedFileName == null ? 'Load Deck...' : 'Change Deck...'),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
              ],
              if (_loadedFileName != null) ...[
                const SizedBox(height: 12),
                Text('Loaded "$_loadedFileName" -- $_loadedCardCount card(s)', textAlign: TextAlign.center),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
