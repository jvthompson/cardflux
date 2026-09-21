import 'package:shared_preferences/shared_preferences.dart';

/// Persists the Discord OAuth refresh token obtained the first time the
/// user authorizes Cardflux for the Discord friend-invite feature, so later
/// app launches can silently reconnect (`Discord_Client_RefreshToken`)
/// instead of showing the consent screen again. Mirrors `ReconnectSettings`
/// exactly, under its own keys.
class DiscordAuthSettings {
  static const _refreshTokenKey = 'discord_refresh_token';

  Future<String?> getRefreshToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_refreshTokenKey);
  }

  Future<void> saveRefreshToken(String token) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_refreshTokenKey, token);
  }

  /// Called if a persisted refresh token comes back permanently invalid
  /// (revoked/expired past refresh), forcing a fresh consent screen next
  /// time instead of retrying the same dead token forever.
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_refreshTokenKey);
  }
}
