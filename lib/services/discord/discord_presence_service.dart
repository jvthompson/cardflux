import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'discord_rpc_bindings.dart';

/// Publishes Discord Rich Presence for Cardflux via the Discord Social SDK
/// (`windows/discord/discord_partner_sdk.dll`), loaded and driven through
/// hand-written `dart:ffi` bindings in [DiscordRpcBindings].
///
/// A singleton, like [SoundService] -- nothing in the UI reacts to presence
/// state, it's a fire-and-forget side effect, so it isn't `ChangeNotifier`/
/// Provider-registered. Every public method is a no-op if [initialize]
/// hasn't succeeded (wrong platform, DLL missing, Discord not installed,
/// etc.) -- this is a decorative feature and must never crash or block the
/// game over Discord being unavailable.
class DiscordPresenceService {
  DiscordPresenceService._();
  static final DiscordPresenceService instance = DiscordPresenceService._();

  /// Cardflux's application in the Discord Developer Portal.
  static const int _applicationId = 1551391208423555102;

  static const _pumpInterval = Duration(milliseconds: 100);

  DiscordRpcBindings? _bindings;
  Pointer<DiscordClient>? _client;
  Timer? _pumpTimer;
  bool _enabled = false;

  String? _lastDetails;
  String? _lastState;

  /// Loads the SDK and starts publishing presence. Safe to call once at app
  /// startup; never throws.
  Future<void> initialize() async {
    if (!Platform.isWindows) return;
    try {
      final lib = DynamicLibrary.open('discord_partner_sdk.dll');
      final bindings = DiscordRpcBindings(lib);
      final client = calloc<DiscordClient>();
      bindings.clientInit(client);
      bindings.clientSetApplicationId(client, _applicationId);
      _bindings = bindings;
      _client = client;
      _enabled = true;
      _pumpTimer = Timer.periodic(_pumpInterval, (_) => _pump());
      setIdle();
    } catch (e) {
      debugPrint('DiscordPresenceService: init failed, disabling ($e)');
      _enabled = false;
    }
  }

  void _pump() {
    try {
      _bindings?.runCallbacks();
    } catch (e) {
      debugPrint('DiscordPresenceService: RunCallbacks failed ($e)');
    }
  }

  /// Publishes "Playing `<gameName>`" / "`<playerCount>`[/`<maxPlayers>`]
  /// players". No-ops (skips the native call entirely) if neither line has
  /// changed since the last call, so listeners can call this on every
  /// unrelated table change without spamming the SDK.
  void setPlaying({required String gameName, required int playerCount, int? maxPlayers}) {
    final details = 'Playing $gameName';
    final state = maxPlayers != null ? '$playerCount/$maxPlayers players' : '$playerCount players';
    _publish(details: details, state: state);
  }

  /// Publishes a generic "In the menus" status for when no game is active.
  void setIdle() {
    _publish(details: 'In the menus', state: null);
  }

  void _publish({required String details, String? state}) {
    if (!_enabled) return;
    if (details == _lastDetails && state == _lastState) return;
    final bindings = _bindings;
    final client = _client;
    if (bindings == null || client == null) return;
    try {
      final activity = calloc<DiscordActivity>();
      bindings.activityInit(activity);
      bindings.activitySetType(activity, discordActivityTypesPlaying);
      final detailsStr = allocateDiscordString(details);
      bindings.activitySetDetails(activity, detailsStr);
      freeDiscordString(detailsStr);
      Pointer<DiscordString>? stateStr;
      if (state != null) {
        stateStr = allocateDiscordString(state);
        bindings.activitySetState(activity, stateStr);
      }
      // The completion callback must be a real function pointer, not
      // nullptr -- Discord_Client_UpdateRichPresence doesn't null-check it
      // before invoking it once the update completes (on a later
      // Discord_RunCallbacks() tick), so a null callback crashes the
      // process. See DiscordRpcBindings.noCallback's doc.
      bindings.clientUpdateRichPresence(
        client,
        activity,
        DiscordRpcBindings.noCallback,
        DiscordRpcBindings.noFreeFn,
        nullptr,
      );
      if (stateStr != null) freeDiscordString(stateStr);
      bindings.activityDrop(activity);
      calloc.free(activity);
      _lastDetails = details;
      _lastState = state;
    } catch (e) {
      debugPrint('DiscordPresenceService: failed to publish presence ($e)');
    }
  }

  /// Clears presence and tears down the client. Best-effort cleanup -- see
  /// `main.dart`'s `MainApp.dispose` doc for why this isn't guaranteed to
  /// run before the process exits, and why that's fine (Discord clears
  /// presence on its own once the process disconnects).
  void dispose() {
    if (!_enabled) return;
    _pumpTimer?.cancel();
    _pumpTimer = null;
    final bindings = _bindings;
    final client = _client;
    try {
      if (bindings != null && client != null) {
        bindings.clientClearRichPresence(client);
        bindings.clientDrop(client);
      }
    } catch (e) {
      debugPrint('DiscordPresenceService: dispose failed ($e)');
    } finally {
      if (client != null) calloc.free(client);
      _client = null;
      _bindings = null;
      _enabled = false;
    }
  }
}
