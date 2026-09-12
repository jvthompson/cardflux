import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user-chosen folder that [DeckLibraryScreen] scans for decks,
/// so it survives across app restarts without asking again. Mirrors
/// `GamesDirectorySettings` exactly, under its own key.
class DecksDirectorySettings {
  static const _key = 'decks_directory_path';

  Future<String?> getPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  Future<void> setPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, path);
  }
}
