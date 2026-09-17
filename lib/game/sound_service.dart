import 'package:audioplayers/audioplayers.dart';

/// Every gameplay sound effect this app can play, named after its file
/// under `assets/audio/` (also declared there in pubspec.yaml) -- keep this
/// list in sync with that folder.
enum SoundEffect {
  draw('draw.wav'),
  playCard('playcard.wav'),
  shuffle('shuffle.wav'),
  tap('tap.wav'),
  untap('untap.wav'),
  error('error.wav');

  const SoundEffect(this.assetFileName);
  final String assetFileName;
}

/// Plays short gameplay sound effects (see [SoundEffect]) from
/// `assets/audio/`. A singleton -- one `AudioPool` per effect, lazily
/// created on first use and cached so its samples are only ever decoded
/// once, and pooled ([_poolPlayers] players deep) so the same effect (or two
/// different ones fired close together, e.g. several cards drawn back to
/// back) can overlap instead of cutting each other off.
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  static const int _poolPlayers = 4;

  final Map<SoundEffect, Future<AudioPool>> _pools = {};

  Future<AudioPool> _poolFor(SoundEffect effect) {
    return _pools.putIfAbsent(
      effect,
      () => AudioPool.create(
        source: AssetSource('audio/${effect.assetFileName}'),
        maxPlayers: _poolPlayers,
      ),
    );
  }

  /// Fires [effect] -- fire-and-forget, safe to call from any gameplay
  /// action handler. Never throws: a missing or corrupt asset is swallowed
  /// rather than crashing the game over a decorative sound.
  Future<void> play(SoundEffect effect) async {
    try {
      final pool = await _poolFor(effect);
      await pool.start();
    } catch (_) {
      // Sound is decorative -- never let a bad/missing asset break gameplay.
    }
  }
}
