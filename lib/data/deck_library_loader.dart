import 'dart:convert';
import 'dart:io';

import '../models/deck_config.dart';
import '../models/game_definition.dart';

/// One deck file found in the Deck Library, paired with the display
/// metadata `DeckLibraryScreen` needs -- a deck file itself has no name
/// field (see [DeckConfig]), so its filename (minus `.json`) is used, and
/// card count is derived by summing entry quantities across every subdeck.
class DeckLibraryEntry {
  const DeckLibraryEntry({required this.displayName, required this.filePath, required this.deck});

  final String displayName;
  final String filePath;
  final DeckConfig deck;

  int get cardCount =>
      deck.subdecks.fold<int>(0, (a, s) => a + s.entries.fold<int>(0, (a2, e) => a2 + e.quantity));
}

/// A deck file for this game that failed to parse because it predates the
/// subdeck format (see [LegacyDeckFormatException]) -- kept distinct from a
/// silently-skipped file (wrong game, or genuinely corrupt JSON) so the UI
/// can tell the player it exists and needs to be rebuilt.
class IncompatibleDeckFile {
  const IncompatibleDeckFile({required this.displayName, required this.filePath});

  final String displayName;
  final String filePath;
}

/// Result of scanning a Deck Library folder for one game: every deck that
/// parsed successfully, plus every legacy-format deck found for this same
/// game (see [IncompatibleDeckFile]).
class DeckLibraryScanResult {
  const DeckLibraryScanResult({required this.entries, required this.incompatible});

  final List<DeckLibraryEntry> entries;
  final List<IncompatibleDeckFile> incompatible;
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
  /// `DeckEditorScreen`/the old `LoadDeckScreen` already did). A pre-subdeck
  /// legacy file for this same game is reported separately (see
  /// [DeckLibraryScanResult.incompatible]) rather than silently dropped;
  /// anything else invalid (unparseable JSON, or a mismatched `gameId`) is
  /// still silently skipped, same as `GameLoader.loadFromFolder`.
  Future<DeckLibraryScanResult> loadDecksForGame(String rootPath, GameDefinition game) async {
    final dir = Directory('$rootPath/${game.id}');
    if (!await dir.exists()) return const DeckLibraryScanResult(entries: [], incompatible: []);

    final entries = <DeckLibraryEntry>[];
    final incompatible = <IncompatibleDeckFile>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) continue;
      final fileName = entity.uri.pathSegments.last;
      final displayName = fileName.substring(0, fileName.length - '.json'.length);
      Map<String, dynamic> raw;
      try {
        raw = jsonDecode(await entity.readAsString()) as Map<String, dynamic>;
      } catch (_) {
        continue;
      }
      try {
        final deck = DeckConfig.fromJson(raw);
        if (deck.gameId != game.id) continue;
        entries.add(DeckLibraryEntry(displayName: displayName, filePath: entity.path, deck: deck));
      } on LegacyDeckFormatException {
        if (raw['gameId'] == game.id) {
          incompatible.add(IncompatibleDeckFile(displayName: displayName, filePath: entity.path));
        }
      } catch (_) {
        // Skip files that aren't valid deck JSON at all.
      }
    }
    entries.sort((a, b) => a.displayName.compareTo(b.displayName));
    incompatible.sort((a, b) => a.displayName.compareTo(b.displayName));
    return DeckLibraryScanResult(entries: entries, incompatible: incompatible);
  }
}
