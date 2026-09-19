import 'dart:convert';
import 'dart:io';

import '../models/saved_game.dart';
import 'game_definition_file_ops.dart' show stripExtension;

/// One save file found under a game's `savegames` folder, paired with the
/// display metadata [LoadSavedGameScreen]/[SaveGameDialog] need without
/// having to fully re-parse every card in it -- mirrors [DeckLibraryEntry]'s
/// shape.
class SaveGameLibraryEntry {
  const SaveGameLibraryEntry({
    required this.displayName,
    required this.filePath,
    required this.savedAt,
    required this.playerCount,
  });

  final String displayName;
  final String filePath;
  final DateTime savedAt;
  final int playerCount;
}

/// Reads/writes [SavedGame] files under `<gameFolderPath>/savegames/` -- the
/// game's own on-disk folder (`game_library/<gameId>/`, see
/// [GameDefinition.folderPath]), not a separate configurable library root,
/// mirroring [GameDefinitionFileOps.writeGameDefinition]'s own "write
/// straight into the game's folder" convention rather than
/// `DecksDirectorySettings`' relocatable-root one. Only usable when a game
/// actually has a folder -- null for the bundled Standard 52 deck, which
/// callers must check for before reaching here.
class SaveGameFileOps {
  String _savesDir(String gameFolderPath) => '$gameFolderPath${Platform.pathSeparator}savegames';

  String _filePath(String gameFolderPath, String name) =>
      '${_savesDir(gameFolderPath)}${Platform.pathSeparator}$name.json';

  Future<bool> saveExists(String gameFolderPath, String name) => File(_filePath(gameFolderPath, name)).exists();

  /// Writes [save] to `<gameFolderPath>/savegames/<name>.json`, creating that
  /// folder first if needed. Pretty-printed to match
  /// [GameDefinitionFileOps.writeGameDefinition]'s existing convention.
  Future<void> writeSaveGame({required String gameFolderPath, required String name, required SavedGame save}) async {
    final dir = Directory(_savesDir(gameFolderPath));
    await dir.create(recursive: true);
    final file = File(_filePath(gameFolderPath, name));
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(save.toJson()));
  }

  Future<SavedGame> readSaveGame(String filePath) async {
    final raw = jsonDecode(await File(filePath).readAsString()) as Map<String, dynamic>;
    return SavedGame.fromJson(raw);
  }

  /// Scans `<gameFolderPath>/savegames/` for every `.json` file directly
  /// inside it (no further recursion), newest-first. A file that fails to
  /// parse as a [SavedGame] is silently skipped, same leniency
  /// [DeckLibraryLoader]/`GameLoader` already use for a bad file in a
  /// scanned folder. Returns `const []` when the folder doesn't exist yet
  /// (no saves for this game so far).
  Future<List<SaveGameLibraryEntry>> listSaveGames(String gameFolderPath) async {
    final dir = Directory(_savesDir(gameFolderPath));
    if (!await dir.exists()) return const [];

    final entries = <SaveGameLibraryEntry>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) continue;
      try {
        final save = await readSaveGame(entity.path);
        entries.add(SaveGameLibraryEntry(
          displayName: stripExtension(entity.uri.pathSegments.last),
          filePath: entity.path,
          savedAt: save.savedAt,
          playerCount: save.state.players.length,
        ));
      } catch (_) {
        // Not valid save-game JSON -- skip it.
      }
    }
    entries.sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return entries;
  }
}
