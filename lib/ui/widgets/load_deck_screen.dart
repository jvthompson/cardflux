import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../models/deck_config.dart';
import '../../models/game_definition.dart';
import '../../models/zone_definition.dart';

const List<XTypeGroup> _deckFileTypes = [
  XTypeGroup(label: 'Deck', extensions: ['json']),
];

/// Lets a player load a pre-built deck file (the same JSON the standalone
/// Deck Editor produces) for [game] -- one file per entry in [zones] (every
/// owned zone marked `ZoneDefinition.dealsBuiltDeck`, see
/// `GameDefinition.deckBuildingZones`; most games have exactly one, some
/// (e.g. METW's Draw Deck + Location Deck) have more), calling
/// [onDeckChosen] once per successful load. Shared by the host's and the
/// client's Load Deck screens -- both need the identical load/validate step,
/// differing only in what happens with the result and how "waiting for the
/// other player" is shown around it. Reuses the exact load/validate pattern
/// from `DeckEditorScreen._openDeck`.
///
/// A deck file itself carries no notion of which zone it's for (just
/// `{gameId, entries}`) -- it's the button the player clicks that decides
/// where a loaded file goes, so the same saved file can be loaded into any
/// of [zones] if a player wants to reuse it.
class LoadDeckScreen extends StatefulWidget {
  const LoadDeckScreen({super.key, required this.game, required this.zones, required this.onDeckChosen});

  final GameDefinition game;
  final List<ZoneDefinition> zones;
  final void Function(String zoneId, DeckConfig deck) onDeckChosen;

  @override
  State<LoadDeckScreen> createState() => _LoadDeckScreenState();
}

class _LoadDeckScreenState extends State<LoadDeckScreen> {
  final Map<String, String> _loadedFileNameByZoneId = {};
  final Map<String, int> _loadedCardCountByZoneId = {};
  String? _error;

  Future<void> _loadDeck(ZoneDefinition zone) async {
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
      _loadedFileNameByZoneId[zone.id] = file.name;
      _loadedCardCountByZoneId[zone.id] = deckConfig.entries.fold<int>(0, (a, e) => a + e.quantity);
    });
    widget.onDeckChosen(zone.id, deckConfig);
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
                widget.zones.length > 1 ? 'Load your decks for ${widget.game.name}' : 'Load your deck for ${widget.game.name}',
                textAlign: TextAlign.center,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              for (final zone in widget.zones) ...[
                FilledButton(
                  onPressed: () => _loadDeck(zone),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Text(_loadedFileNameByZoneId[zone.id] == null ? 'Load ${zone.name}...' : 'Change ${zone.name}...'),
                  ),
                ),
                if (_loadedFileNameByZoneId[zone.id] != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    'Loaded "${_loadedFileNameByZoneId[zone.id]}" -- ${_loadedCardCountByZoneId[zone.id]} card(s)',
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 12),
              ],
              if (_error != null) Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
    );
  }
}
