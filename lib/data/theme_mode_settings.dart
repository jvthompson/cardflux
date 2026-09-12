import 'package:shared_preferences/shared_preferences.dart';

/// Persists the user's dark-mode preference across app restarts. Mirrors
/// `PlayerProfileSettings`/`DecksDirectorySettings`/`GamesDirectorySettings`
/// exactly, under its own key.
class ThemeModeSettings {
  static const _key = 'dark_mode_enabled';

  Future<bool> getDarkMode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }

  Future<void> setDarkMode(bool enabled) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, enabled);
  }
}
