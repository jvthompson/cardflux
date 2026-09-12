import 'package:shared_preferences/shared_preferences.dart';

/// Persists the local player's chosen display name, color, and avatar image
/// path across app restarts. Mirrors `DecksDirectorySettings`/
/// `GamesDirectorySettings` exactly, under their own keys.
class PlayerProfileSettings {
  static const _nameKey = 'player_profile_name';
  static const _colorKey = 'player_profile_color';
  static const _avatarPathKey = 'player_profile_avatar_path';

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

  Future<String?> getAvatarPath() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_avatarPathKey);
  }

  /// Persists [path], or clears the stored value when [path] is null (used
  /// when the player removes their avatar).
  Future<void> setAvatarPath(String? path) async {
    final prefs = await SharedPreferences.getInstance();
    if (path == null) {
      await prefs.remove(_avatarPathKey);
    } else {
      await prefs.setString(_avatarPathKey, path);
    }
  }
}
