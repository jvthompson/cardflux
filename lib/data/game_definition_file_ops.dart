import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';

import '../models/card_definition.dart';
import '../models/game_definition.dart';

/// Image file extensions the Game Definition Editor treats as card/cardback
/// art -- matches the extensions `.gitignore` already excludes game card art
/// by (see `game_library/**/*.jpg` etc.).
const Set<String> imageExtensions = {'.jpg', '.jpeg', '.png', '.webp'};

/// `file_selector` type filter for picking a single card/cardback image --
/// shared by every image-picking button in the Game Definition Editor.
const List<XTypeGroup> imageFileTypes = [
  XTypeGroup(label: 'Image', extensions: ['jpg', 'jpeg', 'png', 'webp']),
];

/// The final path segment of [path], with any trailing separator trimmed --
/// tolerates both `/` and `\` regardless of platform, since a picked folder
/// path's separator style isn't guaranteed to match [Platform.pathSeparator]
/// in every corner case (e.g. a path typed/copied from elsewhere).
String basenameOf(String path) {
  final trimmed = path.replaceAll(RegExp(r'[/\\]+$'), '');
  final lastSeparator = trimmed.lastIndexOf(RegExp(r'[/\\]'));
  return lastSeparator == -1 ? trimmed : trimmed.substring(lastSeparator + 1);
}

/// The `GameDefinition.id`/`GameSet.id` a brand-new game or set takes on
/// when its folder is first chosen -- just that folder's own name, matching
/// the established convention (e.g. `game_library/metw/` -> id `metw`).
String deriveIdFromFolderPath(String folderPath) => basenameOf(folderPath);

/// [fileName] minus its extension (the last `.` only, so a filename with
/// extra dots keeps them, e.g. `my.card.png` -> `my.card`).
String stripExtension(String fileName) {
  final lastDot = fileName.lastIndexOf('.');
  return lastDot <= 0 ? fileName : fileName.substring(0, lastDot);
}

/// Whether [fileName]'s extension is one this editor treats as card art.
bool isImageFile(String fileName) {
  final lastDot = fileName.lastIndexOf('.');
  if (lastDot == -1) return false;
  return imageExtensions.contains(fileName.substring(lastDot).toLowerCase());
}

/// Whether [a] and [b] refer to the same file/folder on disk -- used to make
/// "copy into place" operations a safe no-op when the source already *is*
/// the destination (e.g. the user picked a folder that's already
/// `<gameFolder>/<setId>/`), rather than erroring or self-overwriting.
bool isSamePath(String a, String b) {
  return File(a).absolute.path.toLowerCase() == File(b).absolute.path.toLowerCase();
}

/// All the `dart:io` folder-creation/file-copy logic the Game Definition
/// Editor needs -- kept as its own small data-layer class, in the same
/// spirit as [GameLoader]/`GamesDirectorySettings`, rather than inlined into
/// UI code.
class GameDefinitionFileOps {
  /// Scans [folderPath] for a file named exactly `gamedef.json`
  /// (case-insensitive), returning its full path, or null if none exists.
  Future<String?> findGameDefFile(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return null;
    await for (final entity in dir.list()) {
      if (entity is File && entity.uri.pathSegments.last.toLowerCase() == 'gamedef.json') {
        return entity.path;
      }
    }
    return null;
  }

  /// Copies the file at [sourcePath] to `<destFolderPath>/<fileName>`,
  /// creating [destFolderPath] first if needed. A no-op if [sourcePath]
  /// already *is* that destination file.
  Future<void> copyIntoFolder({
    required String sourcePath,
    required String destFolderPath,
    required String fileName,
  }) async {
    final destPath = '$destFolderPath${Platform.pathSeparator}$fileName';
    if (isSamePath(sourcePath, destPath)) return;
    await Directory(destFolderPath).create(recursive: true);
    await File(sourcePath).copy(destPath);
  }

  /// Copies a single picked image ([sourcePath]) into [destFolderPath],
  /// keeping its original filename, and returns that bare filename -- what
  /// the caller should store in `CardDefinition.imagePath`/
  /// `GameDefinition.cardBackImagePath`.
  Future<String> copyPickedImage({required String sourcePath, required String destFolderPath}) async {
    final fileName = basenameOf(sourcePath);
    await copyIntoFolder(sourcePath: sourcePath, destFolderPath: destFolderPath, fileName: fileName);
    return fileName;
  }

  /// Copies every image file directly inside [sourceFolderPath] into
  /// [destFolderPath] (creating it if needed). A no-op entirely if the two
  /// folders are already the same one on disk.
  Future<void> copySetImages({required String sourceFolderPath, required String destFolderPath}) async {
    if (isSamePath(sourceFolderPath, destFolderPath)) return;
    final dir = Directory(sourceFolderPath);
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is File && isImageFile(entity.uri.pathSegments.last)) {
        await copyIntoFolder(
          sourcePath: entity.path,
          destFolderPath: destFolderPath,
          fileName: entity.uri.pathSegments.last,
        );
      }
    }
  }

  /// One [CardDefinition] per image file found directly inside
  /// [sourceFolderPath], sorted by filename for determinism -- `id` and
  /// `cardTitle` both default to the filename minus its extension,
  /// `imagePath` is the bare filename, and every card is tagged with
  /// [setId].
  Future<List<CardDefinition>> buildCardsFromImageFolder({
    required String sourceFolderPath,
    required String setId,
  }) async {
    final dir = Directory(sourceFolderPath);
    if (!await dir.exists()) return const [];
    final fileNames = <String>[];
    await for (final entity in dir.list()) {
      final fileName = entity.uri.pathSegments.last;
      if (entity is File && isImageFile(fileName)) fileNames.add(fileName);
    }
    fileNames.sort();
    return [
      for (final fileName in fileNames)
        CardDefinition(id: stripExtension(fileName), cardTitle: stripExtension(fileName), imagePath: fileName, setId: setId),
    ];
  }

  /// Writes [game] to `<folderPath>/gamedef.json`, creating [folderPath]
  /// first if needed. Pretty-printed to match the existing hand-authored
  /// game definitions in `game_library/`.
  Future<void> writeGameDefinition({required String folderPath, required GameDefinition game}) async {
    await Directory(folderPath).create(recursive: true);
    final file = File('$folderPath${Platform.pathSeparator}gamedef.json');
    await file.writeAsString(const JsonEncoder.withIndent('  ').convert(game.toJson()));
  }
}
