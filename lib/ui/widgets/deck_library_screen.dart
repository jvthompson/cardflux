import 'dart:convert';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../data/deck_library_loader.dart';
import '../../data/decks_directory_settings.dart';
import '../../data/directory_picker.dart';
import '../../models/deck_config.dart';
import '../../models/game_definition.dart';
import '../../models/zone_definition.dart';
import 'card_back_widget.dart';
import 'card_face_widget.dart' show cardWidth, cardHeight;
import 'move_library_prompt.dart';

const List<XTypeGroup> _deckFileTypes = [
  XTypeGroup(label: 'Deck', extensions: ['json']),
];

/// Lets a player load a pre-built deck for [game] -- one per entry in
/// [zones] (every owned zone marked `ZoneDefinition.dealsBuiltDeck`, see
/// `GameDefinition.deckBuildingZones`), calling [onDeckChosen] once per
/// successful load. Replaces the old file-dialog-only `LoadDeckScreen` with
/// a Deck Library browser -- modeled on `GamePicker`'s directory-scan
/// pattern -- showing every deck saved under the chosen library root's
/// `game.id` subfolder as `*.json` files (remembered across launches via
/// [DecksDirectorySettings]) as a grid of draggable tiles a player drops
/// onto a labeled loading zone. A "Browse for file..." action is kept per
/// zone for a one-off deck or a library that hasn't been set up yet.
///
/// Shared by the host's and the client's Load Deck screens -- both need the
/// identical load/validate step, differing only in what happens with the
/// result and how "waiting for the other player" is shown around it.
class DeckLibraryScreen extends StatefulWidget {
  const DeckLibraryScreen({super.key, required this.game, required this.zones, required this.onDeckChosen});

  final GameDefinition game;
  final List<ZoneDefinition> zones;
  final void Function(String zoneId, DeckConfig deck) onDeckChosen;

  @override
  State<DeckLibraryScreen> createState() => _DeckLibraryScreenState();
}

class _DeckLibraryScreenState extends State<DeckLibraryScreen> {
  final DeckLibraryLoader _loader = DeckLibraryLoader();
  final DecksDirectorySettings _settings = DecksDirectorySettings();

  String? _directoryPath;
  List<DeckLibraryEntry>? _decks;
  bool _busy = false;
  String? _error;

  final Map<String, DeckLibraryEntry> _loadedEntryByZoneId = {};
  final Map<String, String> _loadedFileNameByZoneId = {};
  final Map<String, int> _loadedCardCountByZoneId = {};
  final Map<String, GlobalKey> _zoneDropKeys = {};

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
      _error = null;
    });
    List<DeckLibraryEntry> decks = const [];
    String? error;
    try {
      decks = await _loader.loadDecksForGame(path, widget.game);
      if (decks.isEmpty) error = 'No decks found for ${widget.game.name} in that folder.';
    } catch (e) {
      // Never leave `_busy` stuck true on a bad/inaccessible folder -- that
      // would permanently disable both Refresh and Change Folder...,
      // leaving the user unable to pick a different folder to recover.
      error = 'Could not read that folder: $e';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _decks = decks;
      _error = error;
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

  GlobalKey _zoneDropKey(String zoneId) => _zoneDropKeys.putIfAbsent(zoneId, GlobalKey.new);

  String? _zoneIdAt(Offset globalPoint) {
    for (final entry in _zoneDropKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(globalPoint)) return entry.key;
    }
    return null;
  }

  void _handleDrop(DeckLibraryEntry entry, Offset globalTopLeft) {
    final globalCenter = globalTopLeft + const Offset(cardWidth / 2, cardHeight / 2);
    final zoneId = _zoneIdAt(globalCenter);
    if (zoneId == null) return;
    setState(() {
      _loadedEntryByZoneId[zoneId] = entry;
      _loadedFileNameByZoneId.remove(zoneId);
      _loadedCardCountByZoneId.remove(zoneId);
    });
    widget.onDeckChosen(zoneId, entry.deck);
  }

  Future<void> _browseSingleFile(ZoneDefinition zone) async {
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
      _loadedEntryByZoneId.remove(zone.id);
    });
    widget.onDeckChosen(zone.id, deckConfig);
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

  Widget _buildDeckTileContent(DeckLibraryEntry entry) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: cardWidth,
          height: cardHeight,
          child: CardBackWidget(cardBacks: widget.game.cardBacks),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: cardWidth,
          child: Text(
            entry.displayName,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11),
          ),
        ),
        Text('${entry.cardCount} card(s)', style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurfaceVariant)),
      ],
    );
  }

  Widget _buildDeckTile(DeckLibraryEntry entry) {
    return Draggable<DeckLibraryEntry>(
      data: entry,
      feedback: Material(type: MaterialType.transparency, child: _buildDeckTileContent(entry)),
      childWhenDragging: Opacity(opacity: 0.3, child: _buildDeckTileContent(entry)),
      onDragEnd: (details) => _handleDrop(entry, details.offset),
      child: _buildDeckTileContent(entry),
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
    if (_error != null) {
      return Center(child: Text(_error!, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center));
    }
    final decks = _decks ?? const [];
    if (decks.isEmpty) {
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
      itemCount: decks.length,
      itemBuilder: (context, index) => _buildDeckTile(decks[index]),
    );
  }

  Widget _buildLoadingZone(ZoneDefinition zone) {
    final loadedEntry = _loadedEntryByZoneId[zone.id];
    final loadedFileName = _loadedFileNameByZoneId[zone.id];
    final hasLoaded = loadedEntry != null || loadedFileName != null;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(zone.name, style: const TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Container(
            key: _zoneDropKey(zone.id),
            width: cardWidth,
            height: cardHeight,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white24, width: 1.5),
            ),
            child: hasLoaded ? CardBackWidget(cardBacks: widget.game.cardBacks) : null,
          ),
          const SizedBox(height: 8),
          if (loadedEntry != null)
            Text('Loaded "${loadedEntry.displayName}" -- ${loadedEntry.cardCount} card(s)', textAlign: TextAlign.center)
          else if (loadedFileName != null)
            Text(
              'Loaded "$loadedFileName" -- ${_loadedCardCountByZoneId[zone.id]} card(s)',
              textAlign: TextAlign.center,
            ),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => _browseSingleFile(zone),
            child: Text(hasLoaded ? 'Browse for a different file...' : 'Browse for file...'),
          ),
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
            widget.zones.length > 1
                ? 'Load your decks for ${widget.game.name}'
                : 'Load your deck for ${widget.game.name}',
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
                SizedBox(
                  width: 220,
                  child: SingleChildScrollView(
                    child: Column(children: [for (final zone in widget.zones) _buildLoadingZone(zone)]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
