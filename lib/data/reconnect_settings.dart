import 'package:shared_preferences/shared_preferences.dart';

/// Persists the most recent host address a `JoinScreen` connection was
/// assigned a player id for, so a later "Join Game" attempt to that same
/// address can offer that id back as a `rejoinPlayerId` -- letting a
/// disconnected player rejoin an in-progress game in their own seat instead
/// of joining as a stranger. Mirrors `PlayerProfileSettings` exactly, under
/// its own keys.
///
/// Only ever remembers the single most recent `(host, id)` pair -- fine for
/// "the game I was just in," and harmless when it's stale (a host that no
/// longer recognizes the id, or isn't running at all, just falls back to
/// minting a fresh one, same as any other new join).
class ReconnectSettings {
  static const _hostKeyKey = 'reconnect_host_key';
  static const _playerIdKey = 'reconnect_player_id';

  /// [hostKey] is expected to be `'$host:$port'`, matching whatever
  /// `JoinScreen` is about to connect to.
  Future<String?> getPlayerIdFor(String hostKey) async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getString(_hostKeyKey) != hostKey) return null;
    return prefs.getString(_playerIdKey);
  }

  Future<void> save({required String hostKey, required String playerId}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_hostKeyKey, hostKey);
    await prefs.setString(_playerIdKey, playerId);
  }
}
