import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:permission_handler/permission_handler.dart';

/// Drop-in replacement for `file_selector`'s [getDirectoryPath] that also
/// clears Android's "All files access" special permission first -- without
/// it, Android's scoped storage silently denies plain `dart:io`
/// File/Directory access to a folder the user picks outside the app's own
/// sandbox, even though the OS folder picker itself succeeds (every game
/// library, deck library, and game-definition-editor folder feature reads
/// and writes via `dart:io`, same as desktop). A no-op on every other
/// platform, which has no such restriction.
///
/// Returns null if the user cancels the picker, or if they don't grant the
/// permission -- callers already treat a null [getDirectoryPath] result as
/// "user cancelled", so no separate error path is needed here.
Future<String?> pickDirectoryPath() async {
  if (Platform.isAndroid) {
    var status = await Permission.manageExternalStorage.status;
    if (!status.isGranted) {
      status = await Permission.manageExternalStorage.request();
      if (!status.isGranted) return null;
    }
  }
  return getDirectoryPath();
}
