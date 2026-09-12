import 'dart:convert';
import 'dart:io';

import '../models/deck_config.dart';
import '../models/game_definition.dart';

/// One deck file found in the Deck Library, paired with the display
/// metadata `DeckLibraryScreen` needs -- a deck file itself has no name
/// field (see [DeckConfig]), so its filename (minus `.json`) is used, and
/// card count is derived by summing entry quantities.
class DeckLibraryEntry {
  const DeckLibraryEntry({required this.displayName, required this.filePath, required this.deck});

  final String displayName;
  final String filePath;
  final DeckConfig deck;

  int get cardCount => deck.entries.fold<int>(0, (a, e) => a + e.quantity);
}

/// Loads deck files from a user-chosen Deck Library directory (see
/// `DecksDirectorySettings`), one subfolder per game named after
/// [GameDefinition.id] -- mirrors `GameLoader`'s directory-scan shape.
class DeckLibraryLoader {
  /// Scans `<rootPath>/<game.id>/` for every `.json` file directly inside
  /// it (no further recursion), parses each as a [DeckConfig], and keeps
  /// only those whose `gameId` matches [game]'s id (defense in depth -- the
  /// folder-name convention is the primary signal, but a stray/renamed
  /// file's own `gameId` is still checked, matching the validation
  /// `DeckEditorScreen`/the old `LoadDeckScreen` already did). Invalid JSON
  /// or a mismatched `gameId` is silently skipped, same as
  /// `GameLoader.loadFromFolder`.
  Future<List<DeckLibraryEntry>> loadDecksForGame(String rootPath, GameDefinition game) async {
    final dir = Directory('$rootPath/${game.id}');
    if (!await dir.exists()) return const [];

    final entries = <DeckLibraryEntry>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) continue;
      try {
        final raw = await entity.readAsString();
        final deck = DeckConfig.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        if (deck.gameId != game.id) continue;
        final fileName = entity.uri.pathSegments.last;
        final displayName = fileName.substring(0, fileName.length - '.json'.length);
        entries.add(DeckLibraryEntry(displayName: displayName, filePath: entity.path, deck: deck));
      } catch (_) {
        // Skip files that aren't valid deck JSON.
      }
    }
    entries.sort((a, b) => a.displayName.compareTo(b.displayName));
    return entries;
  }
}
