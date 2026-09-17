import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../data/deck_library_loader.dart';
import '../../data/decks_directory_settings.dart';
import '../../data/directory_picker.dart';
import '../../game/sound_service.dart';
import '../../models/deck_config.dart';
import '../../models/game_definition.dart';
import '../../models/zone_definition.dart';
import 'card_back_widget.dart';
import 'card_face_widget.dart' show cardWidth, cardHeight;
import 'move_library_prompt.dart';

const List<XTypeGroup> _deckFileTypes = [
  XTypeGroup(label: 'Deck', extensions: ['json']),
];

/// Lets a player load a single pre-built deck for [game], calling
/// [onDeckChosen] once with the whole [DeckConfig] -- its subdecks (see
/// `DeckConfig.subdecks`) supply every zone in [zones] (every owned zone
/// marked `ZoneDefinition.dealsBuiltDeck`, see
/// `GameDefinition.deckBuildingZones`) at once, keyed by
/// [ZoneDefinition.deckType]. Shows every deck saved under the chosen
/// library root's `game.id` subfolder as `*.json` files (remembered across
/// launches via [DecksDirectorySettings]) as a grid of tappable tiles, with
/// a "Browse for file..." fallback for a one-off deck or an unset-up
/// library. A tapped deck missing a required (non-optional) zone's subdeck
/// is rejected with an inline message instead of being chosen; an
/// old-format (pre-subdeck) deck file for this game shows in the grid
/// visibly flagged as incompatible rather than being hidden.
///
/// Shared by the host's and the client's Load Deck screens -- both need the
/// identical load/validate step, differing only in what happens with the
/// result and how "waiting for the other player" is shown around it.
class DeckLibraryScreen extends StatefulWidget {
  const DeckLibraryScreen({super.key, required this.game, required this.zones, required this.onDeckChosen});

  final GameDefinition game;
  final List<ZoneDefinition> zones;
  final void Function(DeckConfig deck) onDeckChosen;

  @override
  State<DeckLibraryScreen> createState() => _DeckLibraryScreenState();
}

class _DeckLibraryScreenState extends State<DeckLibraryScreen> {
  final DeckLibraryLoader _loader = DeckLibraryLoader();
  final DecksDirectorySettings _settings = DecksDirectorySettings();

  String? _directoryPath;
  DeckLibraryScanResult? _scan;
  bool _busy = false;
  String? _folderError;
  String? _selectionError;

  String? _chosenDisplayName;
  DeckConfig? _chosenDeck;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final path = await _settings.getPath();
    if (!mounted) return;
    setState(() => _directoryPath = path);
    await _refresh(path);
  }

  Future<void> _refresh(String path) async {
    setState(() {
      _busy = true;
      _folderError = null;
    });
    DeckLibraryScanResult scan = const DeckLibraryScanResult(entries: [], incompatible: []);
    String? error;
    try {
      scan = await _loader.loadDecksForGame(path, widget.game);
      if (scan.entries.isEmpty && scan.incompatible.isEmpty) {
        error = 'No decks found for ${widget.game.name} in that folder.';
      }
    } catch (e) {
      // Never leave `_busy` stuck true on a bad/inaccessible folder -- that
      // would permanently disable both Refresh and Change Folder...,
      // leaving the user unable to pick a different folder to recover.
      error = 'Could not read that folder: $e';
    }
    if (!mounted) return;
    if (error != null) SoundService.instance.play(SoundEffect.error);
    setState(() {
      _busy = false;
      _scan = scan;
      _folderError = error;
    });
  }

  Future<void> _chooseDirectory() async {
    final path = await pickDirectoryPath();
    if (path == null || !mounted) return;
    final oldPath = _directoryPath;
    if (oldPath != null) {
      await maybeMoveLibraryFolder(context, oldRoot: oldPath, newRoot: path, whatLabel: 'deck');
      if (!mounted) return;
    }
    await _settings.setPath(path);
    if (!mounted) return;
    setState(() => _directoryPath = path);
    await _refresh(path);
  }

  /// Every required (non-optional) zone whose type has no cards in [deck] --
  /// empty means [deck] satisfies every required zone.
  List<ZoneDefinition> _missingRequiredZones(DeckConfig deck) =>
      widget.zones.where((z) => !z.deckOptional && deck.cardCountFor(z.deckType) == 0).toList();

  void _selectDeck(DeckConfig deck, String displayName) {
    final missing = _missingRequiredZones(deck);
    if (missing.isNotEmpty) {
      SoundService.instance.play(SoundEffect.error);
      setState(() => _selectionError = 'That deck is missing required cards for: ${missing.map((z) => z.name).join(', ')}.');
      return;
    }
    setState(() {
      _selectionError = null;
      _chosenDeck = deck;
      _chosenDisplayName = displayName;
    });
    widget.onDeckChosen(deck);
  }

  void _selectIncompatible(IncompatibleDeckFile file) {
    SoundService.instance.play(SoundEffect.error);
    setState(() {
      _selectionError = 'The deck "${file.displayName}" was saved in an older format and needs to be rebuilt in the Deck Editor.';
    });
  }

  void _clearChosen() {
    setState(() {
      _chosenDeck = null;
      _chosenDisplayName = null;
    });
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
      SoundService.instance.play(SoundEffect.error);
      setState(() => _selectionError = '$e');
      return;
    } catch (_) {
      if (!mounted) return;
      SoundService.instance.play(SoundEffect.error);
      setState(() => _selectionError = 'That file is not a valid deck.');
      return;
    }
    if (deckConfig.gameId != widget.game.id) {
      if (!mounted) return;
      SoundService.instance.play(SoundEffect.error);
      setState(() => _selectionError = 'That deck is for a different game (${deckConfig.gameId}).');
      return;
    }
    _selectDeck(deckConfig, file.name);
  }

  Widget _buildDirectoryRow() {
    return Row(
      children: [
        Expanded(
          child: Text(
            _directoryPath ?? 'No Deck Library folder chosen',
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
            overflow: TextOverflow.ellipsis,
          ),
        ),
        if (_directoryPath != null)
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh),
            onPressed: _busy ? null : () => _refresh(_directoryPath!),
          ),
        IconButton(
          tooltip: 'Choose Deck Library Folder...',
          icon: const Icon(Icons.folder_open),
          onPressed: _busy ? null : _chooseDirectory,
        ),
      ],
    );
  }

  Widget _buildDeckTileContent(String displayName, int cardCount, {bool incompatible = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: cardWidth,
          height: cardHeight,
          child: Opacity(
            opacity: incompatible ? 0.35 : 1,
            child: CardBackWidget(cardBacks: widget.game.cardBacks),
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: cardWidth,
          child: Text(
            displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11),
          ),
        ),
        Text(
          incompatible ? 'Old format' : '$cardCount card(s)',
          style: TextStyle(
            fontSize: 10,
            color: incompatible ? Colors.red : Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildDeckTile(DeckLibraryEntry entry) {
    final selected = _chosenDisplayName == entry.displayName;
    return InkWell(
      onTap: () => _selectDeck(entry.deck, entry.displayName),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: selected ? Theme.of(context).colorScheme.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: _buildDeckTileContent(entry.displayName, entry.cardCount),
      ),
    );
  }

  Widget _buildIncompatibleTile(IncompatibleDeckFile file) {
    return Tooltip(
      message: 'Old format -- rebuild in the Deck Editor',
      child: InkWell(
        onTap: () => _selectIncompatible(file),
        child: _buildDeckTileContent(file.displayName, 0, incompatible: true),
      ),
    );
  }

  Widget _buildDeckGrid() {
    if (_directoryPath == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            'Choose a Deck Library folder to see saved decks for ${widget.game.name} -- '
            'or use Browse for file... below.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
          ),
        ),
      );
    }
    if (_busy) return const Center(child: CircularProgressIndicator(strokeWidth: 2));
    if (_folderError != null) {
      return Center(
        child: Text(_folderError!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
      );
    }
    final entries = _scan?.entries ?? const [];
    final incompatible = _scan?.incompatible ?? const [];
    if (entries.isEmpty && incompatible.isEmpty) {
      return Center(
        child: Text(
          'No decks found for ${widget.game.name} in that folder.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      );
    }
    return GridView.builder(
      padding: const EdgeInsets.all(12),
      gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: cardWidth + 24,
        mainAxisExtent: cardHeight + 44,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: entries.length + incompatible.length,
      itemBuilder: (context, index) => index < entries.length
          ? _buildDeckTile(entries[index])
          : _buildIncompatibleTile(incompatible[index - entries.length]),
    );
  }

  Widget _buildSummaryPanel() {
    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('This game needs', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          for (final zone in widget.zones)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(zone.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  Text(
                    zone.deckOptional ? '${zone.deckType} (optional)' : '${zone.deckType} (required)',
                    style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          const Divider(height: 24),
          if (_chosenDeck != null) ...[
            Text('Loaded "$_chosenDisplayName"', style: const TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            for (final zone in widget.zones)
              Text('${zone.name}: ${_chosenDeck!.cardCountFor(zone.deckType)} card(s)', style: const TextStyle(fontSize: 12)),
            const SizedBox(height: 8),
            TextButton(onPressed: _clearChosen, child: const Text('Choose a different deck')),
          ] else
            Text(
              'Tap a deck to load it.',
              style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 12),
            ),
          if (_selectionError != null) ...[
            const SizedBox(height: 12),
            Text(_selectionError!, style: const TextStyle(color: Colors.red, fontSize: 12)),
          ],
          const SizedBox(height: 12),
          TextButton(onPressed: _browseSingleFile, child: const Text('Browse for file...')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Load your deck for ${widget.game.name}',
            textAlign: TextAlign.center,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _buildDirectoryRow(),
          const Divider(height: 24),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(flex: 2, child: _buildDeckGrid()),
                const VerticalDivider(width: 24),
                SizedBox(width: 240, child: _buildSummaryPanel()),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
