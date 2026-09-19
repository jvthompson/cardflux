import 'dart:io';

/// Writes exported action-log text files under `<gameFolderPath>/gamelogs/`
/// -- the game's own on-disk folder (`game_library/<gameId>/`, see
/// `GameDefinition.folderPath`), mirroring `SaveGameFileOps`'s identical
/// "write straight into the game's folder" convention. Unlike save games,
/// any player (not just the host/practice session) may export a log --
/// each player's own machine gets its own copy under its own local
/// `gameFolderPath`.
class GameLogFileOps {
  String _logsDir(String gameFolderPath) => '$gameFolderPath${Platform.pathSeparator}gamelogs';

  String _filePath(String gameFolderPath, String fileName) =>
      '${_logsDir(gameFolderPath)}${Platform.pathSeparator}$fileName';

  /// Writes [contents] to `<gameFolderPath>/gamelogs/<fileName>`, creating
  /// that folder first if needed.
  Future<void> writeLog({
    required String gameFolderPath,
    required String fileName,
    required String contents,
  }) async {
    final dir = Directory(_logsDir(gameFolderPath));
    await dir.create(recursive: true);
    final file = File(_filePath(gameFolderPath, fileName));
    await file.writeAsString(contents);
  }
}
