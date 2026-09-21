import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import 'discord_rpc_bindings.dart';
import 'discord_social_bindings.dart';
import 'discord_social_service.dart';

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
  DiscordSocialBindings? _socialBindings;
  Pointer<DiscordClient>? _client;
  Timer? _pumpTimer;
  StreamSubscription<int>? _socialStatusSub;
  bool _enabled = false;

  // What the SDK was last told (used to skip redundant native calls).
  String? _lastDetails;
  String? _lastState;
  String? _lastPartyKey;

  // What we currently intend to show -- kept separate from the "last
  // published" cache above so a forced republish (see _onSocialStatusChanged)
  // can replay it even though, from our own bookkeeping, nothing changed.
  String? _currentDetails;
  String? _currentState;
  DiscordPartyInfo? _currentParty;

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
      _socialBindings = DiscordSocialBindings(lib);
      _client = client;
      _enabled = true;
      _pumpTimer = Timer.periodic(_pumpInterval, (_) => _pump());
      DiscordSocialService.instance.attachClient(client, lib);
      DiscordSocialService.instance.registerLaunchAndJoinHandling();
      // Per Discord's own SDK docs: Rich Presence set via this lightweight
      // pre-Connect path is CLEARED once Client::Connect() actually
      // succeeds (confirmed by observation: opening Invite mode -- which
      // triggers OAuth Connect() -- silently wiped an already-hosting
      // game's presence, breaking SendActivityInvite along with it since
      // there was no Activity left to invite into). Republish whenever the
      // social client reaches Ready, bypassing our own "nothing changed"
      // dedup cache since the SDK's state changed out from under us, not
      // through a call of ours.
      _socialStatusSub = DiscordSocialService.instance.statusStream.listen((status) {
        if (status == discordClientStatusReady) _republishAfterConnect();
      });
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
  /// players". No-ops (skips the native call entirely) if nothing (details,
  /// state, or [party]) has changed since the last call, so listeners can
  /// call this on every unrelated table change without spamming the SDK.
  ///
  /// [party] is only meaningful while hosting -- it attaches the
  /// party/join-secret info a Discord invite (or "Ask to Join" on the
  /// host's profile) needs to actually connect a friend. Leave it null for
  /// clients/practice sessions, which have nothing to invite anyone into.
  void setPlaying({
    required String gameName,
    required int playerCount,
    int? maxPlayers,
    DiscordPartyInfo? party,
  }) {
    final details = 'Playing $gameName';
    final state = maxPlayers != null ? '$playerCount/$maxPlayers players' : '$playerCount players';
    _publish(details: details, state: state, party: party);
  }

  /// Publishes a generic "In the menus" status for when no game is active.
  void setIdle() {
    _publish(details: 'In the menus', state: null, party: null);
  }

  void _republishAfterConnect() {
    if (!_enabled || _currentDetails == null) return;
    _lastDetails = null;
    _lastState = null;
    _lastPartyKey = null;
    _publish(details: _currentDetails!, state: _currentState, party: _currentParty);
  }

  void _publish({required String details, String? state, required DiscordPartyInfo? party}) {
    if (!_enabled) return;
    _currentDetails = details;
    _currentState = state;
    _currentParty = party;
    final partyKey = party == null ? null : '${party.partyId}:${party.currentSize}:${party.maxSize}:${party.joinSecret}';
    if (details == _lastDetails && state == _lastState && partyKey == _lastPartyKey) return;
    final bindings = _bindings;
    final social = _socialBindings;
    final client = _client;
    if (bindings == null || client == null) return;
    Pointer<DiscordActivityParty>? partyPtr;
    Pointer<DiscordActivitySecrets>? secretsPtr;
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
      if (party != null && social != null) {
        partyPtr = calloc<DiscordActivityParty>();
        social.partyInit(partyPtr);
        final idStr = allocateDiscordString(party.partyId);
        social.partySetId(partyPtr, idStr.ref);
        freeDiscordString(idStr);
        social.partySetCurrentSize(partyPtr, party.currentSize);
        social.partySetMaxSize(partyPtr, party.maxSize);
        social.partySetPrivacy(partyPtr, discordActivityPartyPrivacyPrivate);
        social.activitySetParty(activity, partyPtr);

        secretsPtr = calloc<DiscordActivitySecrets>();
        social.secretsInit(secretsPtr);
        final joinStr = allocateDiscordString(party.joinSecret);
        social.secretsSetJoin(secretsPtr, joinStr.ref);
        freeDiscordString(joinStr);
        social.activitySetSecrets(activity, secretsPtr);
        social.activitySetSupportedPlatforms(activity, discordActivityGamePlatformsDesktop);
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
      _lastPartyKey = partyKey;
    } catch (e) {
      debugPrint('DiscordPresenceService: failed to publish presence ($e)');
    } finally {
      if (partyPtr != null) {
        social?.partyDrop(partyPtr);
        calloc.free(partyPtr);
      }
      if (secretsPtr != null) {
        social?.secretsDrop(secretsPtr);
        calloc.free(secretsPtr);
      }
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
    _socialStatusSub?.cancel();
    _socialStatusSub = null;
    final bindings = _bindings;
    final client = _client;
    DiscordSocialService.instance.dispose();
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
      _socialBindings = null;
      _enabled = false;
    }
  }
}
