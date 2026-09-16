import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_directory.dart';

/// Persists the user-chosen folder that [GamePicker] scans for games, so it
/// survives across app restarts without asking again. Kept as its own tiny
/// class (rather than inlined into `GameLoader`) since it wraps a different
/// concern -- durable settings, not game parsing.
class GamesDirectorySettings {
  static const _key = 'games_directory_path';

  /// The configured Games Library folder: the user's explicit choice if one
  /// has been saved via [setPath], else `<application folder>/game_library`
  /// -- so a fresh install has a working library with no setup needed. That
  /// default is computed fresh each call (via [appDirectoryPath], never
  /// persisted as the saved preference itself) so it keeps tracking the
  /// app's own location until the user picks a folder of their own.
  Future<String> getPath() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    return saved ?? '$appDirectoryPath${Platform.pathSeparator}game_library';
  }

  Future<void> setPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, path);
  }
}
