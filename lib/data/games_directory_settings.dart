import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user-chosen folder that [GamePicker] scans for games, so it
/// survives across app restarts without asking again. Kept as its own tiny
/// class (rather than inlined into `GameLoader`) since it wraps a different
/// concern -- durable settings, not game parsing.
class GamesDirectorySettings {
  static const _key = 'games_directory_path';

  Future<String?> getPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_key);
  }

  Future<void> setPath(String path) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_key, path);
  }
}
