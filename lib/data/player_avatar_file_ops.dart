import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'game_definition_file_ops.dart' show basenameOf, isSamePath;

/// Manages the local player's single avatar image file on disk, stored
/// under a deterministic name (`avatar.<ext>`) inside the app's own support
/// directory -- unlike `GameDefinitionFileOps`, which copies art into a
/// user-chosen game folder, there's no "project folder" for a
/// SharedPreferences-backed profile setting (see `PlayerProfileSettings`),
/// so this resolves its own persistent location via `path_provider`.
/// Re-picking (even with a different file extension) always fully replaces
/// the prior file rather than accumulating orphans, since [avatarDirectory]
/// is exclusively reserved for this single file.
class PlayerAvatarFileOps {
  static const _baseName = 'avatar';

  /// The `<appSupportDir>/avatar/` directory this class owns entirely.
  /// A separate method (rather than inlined into every call site) so tests
  /// can override it with a temp directory instead of a real platform path.
  Future<Directory> avatarDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    return Directory('${supportDir.path}${Platform.pathSeparator}avatar');
  }

  /// Copies the picked image at [sourcePath] into [avatarDirectory] as
  /// `avatar.<ext>`, first deleting any previously stored avatar file
  /// (whatever its extension) so re-picking never leaves an orphaned file
  /// behind. Returns the absolute destination path -- what the caller
  /// should persist via `PlayerProfileSettings.setAvatarPath`.
  Future<String> saveAvatar(String sourcePath) async {
    final dir = await avatarDirectory();
    await dir.create(recursive: true);
    await _clearExisting(dir);
    final destPath = '${dir.path}${Platform.pathSeparator}$_baseName${_extensionOf(sourcePath)}';
    if (!isSamePath(sourcePath, destPath)) {
      await File(sourcePath).copy(destPath);
    }
    return destPath;
  }

  /// Deletes the stored avatar file, if any. Safe to call when nothing is
  /// stored (used when the user taps "Remove Image").
  Future<void> deleteAvatar() async {
    final dir = await avatarDirectory();
    await _clearExisting(dir);
  }

  Future<void> _clearExisting(Directory dir) async {
    if (!await dir.exists()) return;
    await for (final entity in dir.list()) {
      if (entity is File && basenameOf(entity.path).startsWith('$_baseName.')) {
        await entity.delete();
      }
    }
  }

  String _extensionOf(String path) {
    final name = basenameOf(path);
    final lastDot = name.lastIndexOf('.');
    return lastDot == -1 ? '' : name.substring(lastDot).toLowerCase();
  }
}
