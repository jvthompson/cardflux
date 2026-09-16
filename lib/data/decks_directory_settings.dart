import 'dart:io';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_directory.dart';

/// Persists the user-chosen folder that [DeckLibraryScreen] scans for decks,
/// so it survives across app restarts without asking again. Mirrors
/// `GamesDirectorySettings` exactly, under its own key.
class DecksDirectorySettings {
  static const _key = 'decks_directory_path';

  /// The configured Deck Library folder: the user's explicit choice if one
  /// has been saved via [setPath], else `<application folder>/deck_library`
  /// -- so a fresh install has a working library with no setup needed. That
  /// default is computed fresh each call (via [appDirectoryPath], never
  /// persisted as the saved preference itself) so it keeps tracking the
  /// app's own location until the user picks a folder of their own.
  Future<String> getPath() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_key);
    return saved ?? '$appDirectoryPath${Platform.pathSeparator}deck_library';
  }

  Future<void> setPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, path);
  }
}
