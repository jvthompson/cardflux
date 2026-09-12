import 'package:shared_preferences/shared_preferences.dart';

/// Persists the local player's chosen display name and color across app
/// restarts. Mirrors `DecksDirectorySettings`/`GamesDirectorySettings`
/// exactly, under their own keys.
class PlayerProfileSettings {
  static const _nameKey = 'player_profile_name';
  static const _colorKey = 'player_profile_color';

  Future<String?> getName() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_nameKey);
  }

  Future<void> setName(String name) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_nameKey, name);
  }

  Future<int?> getColor() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_colorKey);
  }

  Future<void> setColor(int color) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_colorKey, color);
  }
}
