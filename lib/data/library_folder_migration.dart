import 'dart:io';

/// Whether [path] exists and directly or indirectly contains at least one
/// entry -- used to decide whether it's worth offering to move a library
/// folder's contents at all (an empty or missing folder has nothing to move).
Future<bool> directoryHasEntries(String path) async {
  final dir = Directory(path);
  if (!await dir.exists()) return false;
  return dir.list().isEmpty.then((empty) => !empty);
}

Future<void> _copyDirectoryContents(Directory from, Directory to) async {
  await to.create(recursive: true);
  await for (final entity in from.list()) {
    final name = entity.uri.pathSegments.where((s) => s.isNotEmpty).last;
    if (entity is Directory) {
      await _copyDirectoryContents(entity, Directory('${to.path}${Platform.pathSeparator}$name'));
    } else if (entity is File) {
      await entity.copy('${to.path}${Platform.pathSeparator}$name');
    }
  }
}

/// Copies every file and subfolder from [fromPath] into [toPath] (creating
/// destination folders as needed, overwriting any same-named file already
/// there), then deletes [fromPath] entirely -- used to relocate a whole
/// Games/Deck Library folder when the user points the setting at a new
/// location and chooses to bring their existing files along.
Future<void> moveDirectoryContents({required String fromPath, required String toPath}) async {
  await _copyDirectoryContents(Directory(fromPath), Directory(toPath));
  await Directory(fromPath).delete(recursive: true);
}
