import 'dart:convert';
import 'dart:io';

import '../models/deck_config.dart';
import '../models/game_definition.dart';

/// One deck file found in the Deck Library, paired with the display
/// metadata `DeckLibraryScreen` needs -- a deck file itself has no name
/// field (see [DeckConfig]), so its filename (minus `.json`) is used, and
/// card count is derived by summing entry quantities across every subdeck.
class DeckLibraryEntry {
  const DeckLibraryEntry({
    required this.displayName,
    required this.filePath,
    required this.deck,
    this.isBuiltIn = false,
  });

  final String displayName;
  final String filePath;
  final DeckConfig deck;

  /// True when this deck was found under the game's own
  /// `game_library/<id>/decks` folder rather than the player's Deck Library
  /// -- shipped with the game, not saved by a player (see
  /// [DeckLibraryLoader.loadBuiltInDecksForGame]).
  final bool isBuiltIn;

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
/// [GameDefinition.id] -- mirrors `GameLoader`'s directory-scan shape. Also
/// loads read-only decks built into a game itself, shipped alongside its
/// `gamedef.json` under a `decks` subfolder (see [loadBuiltInDecksForGame]).
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
  Future<DeckLibraryScanResult> loadDecksForGame(String rootPath, GameDefinition game) =>
      _scanDirectory(Directory('$rootPath/${game.id}'), game, isBuiltIn: false);

  /// Scans `<game.folderPath>/decks/` for decks shipped with the game itself
  /// -- same file format and folder-scan rules as [loadDecksForGame], just
  /// rooted under the game's own folder instead of the player's Deck
  /// Library. Empty for the bundled Standard-52 game, which has no disk
  /// folder ([GameDefinition.folderPath] is null for it).
  Future<DeckLibraryScanResult> loadBuiltInDecksForGame(GameDefinition game) {
    final folderPath = game.folderPath;
    if (folderPath == null) return Future.value(const DeckLibraryScanResult(entries: [], incompatible: []));
    return _scanDirectory(Directory('$folderPath/decks'), game, isBuiltIn: true);
  }

  /// Every deck available for [game]: the player's own saved decks (from
  /// `<rootPath>/<game.id>`), followed by every built-in deck shipped with
  /// the game (see [loadBuiltInDecksForGame]) -- built-in decks always sort
  /// after player-made ones, regardless of name, so a game author can't
  /// crowd out a player's own decks just by naming things earlier
  /// alphabetically.
  Future<DeckLibraryScanResult> loadAllDecksForGame(String rootPath, GameDefinition game) async {
    final owned = await loadDecksForGame(rootPath, game);
    final builtIn = await loadBuiltInDecksForGame(game);
    return DeckLibraryScanResult(
      entries: [...owned.entries, ...builtIn.entries],
      incompatible: [...owned.incompatible, ...builtIn.incompatible],
    );
  }

  Future<DeckLibraryScanResult> _scanDirectory(Directory dir, GameDefinition game, {required bool isBuiltIn}) async {
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
        entries.add(
          DeckLibraryEntry(displayName: displayName, filePath: entity.path, deck: deck, isBuiltIn: isBuiltIn),
        );
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
