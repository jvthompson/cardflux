import 'dart:io';

import 'package:path_provider/path_provider.dart';

import 'avatar_image_utils.dart';
import 'game_definition_file_ops.dart' show basenameOf;

/// Manages the local player's single avatar image file on disk, stored
/// under a deterministic name (`avatar.png`) inside the app's own support
/// directory -- unlike `GameDefinitionFileOps`, which copies art into a
/// user-chosen game folder, there's no "project folder" for a
/// SharedPreferences-backed profile setting (see `PlayerProfileSettings`),
/// so this resolves its own persistent location via `path_provider`.
/// Re-picking always fully replaces the prior file rather than accumulating
/// orphans, since [avatarDirectory] is exclusively reserved for this single
/// file.
class PlayerAvatarFileOps {
  static const _baseName = 'avatar';

  /// The `<appSupportDir>/avatar/` directory this class owns entirely.
  /// A separate method (rather than inlined into every call site) so tests
  /// can override it with a temp directory instead of a real platform path.
  Future<Directory> avatarDirectory() async {
    final supportDir = await getApplicationSupportDirectory();
    return Directory('${supportDir.path}${Platform.pathSeparator}avatar');
  }

  /// Downscales the picked image at [sourcePath] (see [resizeAvatarBytes])
  /// and writes it into [avatarDirectory] as `avatar.png`, first deleting
  /// any previously stored avatar file so re-picking never leaves an
  /// orphaned file behind. The file is always re-encoded to PNG regardless
  /// of the source format, both to keep it small (it's later read back
  /// as-is for network transmission to other players -- see `HostServer`/
  /// `GameClient`) and to keep the on-disk naming deterministic. Returns the
  /// absolute destination path -- what the caller should persist via
  /// `PlayerProfileSettings.setAvatarPath`.
  Future<String> saveAvatar(String sourcePath) async {
    final dir = await avatarDirectory();
    await dir.create(recursive: true);
    await _clearExisting(dir);
    final resized = await resizeAvatarBytes(await File(sourcePath).readAsBytes());
    final destPath = '${dir.path}${Platform.pathSeparator}$_baseName.png';
    await File(destPath).writeAsBytes(resized);
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
}
