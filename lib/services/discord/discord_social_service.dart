import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';

import '../../data/discord_auth_settings.dart';
import 'discord_rpc_bindings.dart'
    show DiscordClient, DiscordClientResult, DiscordRpcBindings, DiscordString, allocateDiscordString, freeDiscordString;
import 'discord_social_bindings.dart';

/// A Discord friend eligible to be invited to join a hosted game (already
/// filtered to real friends -- see [DiscordSocialService.fetchInvitableFriends]).
///
/// [status] is included rather than pre-filtered: Discord deliberately
/// reports an Invisible user's status as `Discord_StatusType_Offline` to
/// everyone else (that's the entire point of Invisible), so there is no way
/// to tell "really offline" apart from "invisible but actually online" from
/// this API alone -- hiding "offline" friends would silently hide real,
/// reachable ones. Show [status] to the user instead and let them decide.
class DiscordFriend {
  const DiscordFriend({
    required this.userId,
    required this.username,
    required this.displayName,
    required this.status,
    this.avatarUrl,
  });

  final int userId;
  final String username;
  final String displayName;
  final int status;
  final String? avatarUrl;
}

/// Party/join metadata to attach to the host's Rich Presence Activity so a
/// Discord invite (or a friend clicking "Ask to Join" on the host's
/// profile) carries enough info to auto-connect. See
/// `DiscordPresenceService.setPlaying`.
class DiscordPartyInfo {
  const DiscordPartyInfo({
    required this.partyId,
    required this.currentSize,
    required this.maxSize,
    required this.joinSecret,
  });

  final String partyId;
  final int currentSize;
  final int maxSize;

  /// Opaque string we fully control -- Cardflux encodes it as `'ip:port'`.
  /// Handed back verbatim by Discord once a friend accepts/joins.
  final String joinSecret;
}

/// Handles the Discord OAuth login, friends list, and invite-send/receive
/// plumbing for the "invite a friend to join my game" feature. Reuses the
/// single native `Discord_Client` that [DiscordPresenceService] already
/// owns (via [attachClient]) rather than creating a second one -- one
/// native identity, one `RunCallbacks()` pump for the whole app.
///
/// A singleton, like `DiscordPresenceService`/`SoundService`. Every public
/// method is defensive (never throws past its own boundary, resolves to a
/// failure value instead) since this is a decorative feature layered on
/// top of gameplay that must never crash the app or block hosting a game.
class DiscordSocialService {
  DiscordSocialService._();
  static final DiscordSocialService instance = DiscordSocialService._();

  static const int _applicationId = 1551391208423555102;
  static const _readyTimeout = Duration(seconds: 15);

  Pointer<DiscordClient>? _client;
  DiscordSocialBindings? _bindings;

  NativeCallable<DiscordStatusChangedCallbackNative>? _statusCallable;
  NativeCallable<DiscordActivityJoinCallbackNative>? _joinCallable;

  final _statusController = StreamController<int>.broadcast();
  final _joinSecretController = StreamController<String>.broadcast();

  int _lastStatus = -1;

  /// Called once by `DiscordPresenceService.initialize()` right after it
  /// creates the shared client, before this service is used for anything.
  void attachClient(Pointer<DiscordClient> client, DynamicLibrary lib) {
    _client = client;
    _bindings = DiscordSocialBindings(lib);
  }

  bool get isReady => _lastStatus == discordClientStatusReady;
  Stream<int> get statusStream => _statusController.stream;

  /// Fires with the join secret whenever a friend accepts our invite (or
  /// otherwise joins) from inside their own real Discord client -- the
  /// "click Join in Discord" path. A broadcast stream since it can fire at
  /// any time, including before any UI is listening.
  Stream<String> get joinSecretReceived => _joinSecretController.stream;

  /// Registers the cold-start launch command and the persistent
  /// status/join callbacks. Called unconditionally at every app startup
  /// (NOT gated on the user ever opening Invite mode) -- both are cheap,
  /// local, and don't trigger a consent screen; the join callback must be
  /// live even for a user who never hosts/invites themselves, since they
  /// could be the one being invited.
  void registerLaunchAndJoinHandling() {
    final b = _bindings;
    final client = _client;
    if (b == null || client == null) return;
    try {
      final cmd = allocateDiscordString('');
      final registered = b.registerLaunchCommand(client, _applicationId, cmd.ref);
      freeDiscordString(cmd);
      debugPrint('DiscordSocialService: RegisterLaunchCommand -> $registered');
    } catch (e) {
      debugPrint('DiscordSocialService: RegisterLaunchCommand failed ($e)');
    }
    try {
      _statusCallable = NativeCallable<DiscordStatusChangedCallbackNative>.listener(_onStatusChanged);
      b.setStatusChangedCallback(client, _statusCallable!.nativeFunction, DiscordRpcBindings.noFreeFn, nullptr);
    } catch (e) {
      debugPrint('DiscordSocialService: SetStatusChangedCallback failed ($e)');
    }
    try {
      _joinCallable = NativeCallable<DiscordActivityJoinCallbackNative>.listener(_onActivityJoin);
      b.setActivityJoinCallback(client, _joinCallable!.nativeFunction, DiscordRpcBindings.noFreeFn, nullptr);
    } catch (e) {
      debugPrint('DiscordSocialService: SetActivityJoinCallback failed ($e)');
    }
  }

  void _onStatusChanged(int status, int error, int errorDetail, Pointer<Void> userData) {
    debugPrint('DiscordSocialService: status -> $status (error=$error, errorDetail=$errorDetail)');
    _lastStatus = status;
    _statusController.add(status);
  }

  void _onActivityJoin(DiscordString joinSecret, Pointer<Void> userData) {
    final secret = joinSecret.size == 0 ? '' : decodeDiscordStringValue(joinSecret);
    debugPrint('DiscordSocialService: activity join received ($secret)');
    if (secret.isNotEmpty) _joinSecretController.add(secret);
  }

  /// Checks a `Discord_ClientResult` and logs the SDK's own error text/code
  /// if it failed -- every one-shot completion callback below must check
  /// this before trusting the data it carries; a failed call still invokes
  /// its callback (per the null-callback-crashes lesson we've already
  /// learned the hard way), just with `Successful() == false` and the
  /// other output values left at their defaults (e.g. an empty access
  /// token), which would otherwise be silently treated as a real value.
  bool _checkResult(DiscordSocialBindings b, String label, Pointer<DiscordClientResult> result) {
    final ok = b.resultSuccessful(result);
    if (!ok) {
      final errOut = calloc<DiscordString>();
      final bodyOut = calloc<DiscordString>();
      b.resultError(result, errOut);
      b.resultResponseBody(result, bodyOut);
      final message = readDiscordString(errOut);
      final body = readDiscordString(bodyOut);
      calloc.free(errOut);
      calloc.free(bodyOut);
      debugPrint(
        'DiscordSocialService: $label failed (type=${b.resultType(result)}, code=${b.resultErrorCode(result)}, '
        'error="$message", body="$body")',
      );
    }
    return ok;
  }

  /// Lazy OAuth entry point -- only called when the host first opens
  /// Invite mode. Tries a persisted refresh token first (no consent
  /// screen); falls back to a full `Authorize` (real consent screen) if
  /// none exists or it's no longer valid. Never throws; resolves `false`
  /// on any failure so the UI can show a retry affordance.
  Future<bool> ensureAuthorizedAndConnected() async {
    final b = _bindings;
    final client = _client;
    if (b == null || client == null) return false;
    if (isReady) return true;
    try {
      final savedRefreshToken = await DiscordAuthSettings().getRefreshToken();
      debugPrint('DiscordSocialService: loaded saved refresh token (len=${savedRefreshToken?.length})');
      if (savedRefreshToken != null) {
        final refreshed = await _refreshToken(b, client, savedRefreshToken);
        if (refreshed) return await _connectAndAwaitReady(b, client);
        await DiscordAuthSettings().clear();
      }
      final authorized = await _authorizeFromScratch(b, client);
      if (!authorized) return false;
      return await _connectAndAwaitReady(b, client);
    } catch (e) {
      debugPrint('DiscordSocialService: ensureAuthorizedAndConnected failed ($e)');
      return false;
    }
  }

  Future<bool> _connectAndAwaitReady(DiscordSocialBindings b, Pointer<DiscordClient> client) async {
    if (isReady) return true;
    final readyFuture = statusStream.firstWhere((s) => s == discordClientStatusReady).timeout(_readyTimeout);
    b.connect(client);
    try {
      await readyFuture;
      return true;
    } catch (e) {
      debugPrint('DiscordSocialService: never reached Ready ($e)');
      return false;
    }
  }

  Future<bool> _refreshToken(DiscordSocialBindings b, Pointer<DiscordClient> client, String refreshToken) async {
    final completer = Completer<_TokenResult?>();
    late final NativeCallable<DiscordTokenExchangeCallbackNative> callable;
    void handler(
      Pointer<DiscordClientResult> result,
      DiscordString accessToken,
      DiscordString refreshTokenOut,
      int tokenType,
      int expiresIn,
      DiscordString scopes,
      Pointer<Void> userData,
    ) {
      if (!completer.isCompleted) {
        completer.complete(
          !_checkResult(b, 'RefreshToken', result)
              ? null
              : _TokenResult(accessToken: decodeDiscordStringValue(accessToken), refreshToken: decodeDiscordStringValue(refreshTokenOut)),
        );
      }
      callable.close();
    }

    callable = NativeCallable<DiscordTokenExchangeCallbackNative>.listener(handler);
    final refreshStr = allocateDiscordString(refreshToken);
    try {
      b.refreshToken(client, _applicationId, refreshStr.ref, callable.nativeFunction, DiscordRpcBindings.noFreeFn, nullptr);
    } finally {
      freeDiscordString(refreshStr);
    }
    final token = await completer.future.timeout(const Duration(seconds: 10), onTimeout: () => null);
    if (token == null) return false;
    debugPrint('DiscordSocialService: RefreshToken succeeded, saving new refresh token (len=${token.refreshToken.length})');
    await DiscordAuthSettings().saveRefreshToken(token.refreshToken);
    return _updateToken(b, client, token.accessToken);
  }

  Future<bool> _authorizeFromScratch(DiscordSocialBindings b, Pointer<DiscordClient> client) async {
    final verifier = calloc<DiscordAuthorizationCodeVerifier>();
    final challenge = calloc<DiscordAuthorizationCodeChallenge>();
    final args = calloc<DiscordAuthorizationArgs>();
    try {
      b.createAuthorizationCodeVerifier(client, verifier);
      b.codeVerifierChallenge(verifier, challenge);
      final verifierOut = calloc<DiscordString>();
      b.codeVerifierVerifier(verifier, verifierOut);
      final codeVerifierValue = readDiscordString(verifierOut);
      calloc.free(verifierOut);

      final presenceScopesOut = calloc<DiscordString>();
      final commsScopesOut = calloc<DiscordString>();
      b.getDefaultPresenceScopes(presenceScopesOut);
      b.getDefaultCommunicationScopes(commsScopesOut);
      final scopes = '${readDiscordString(presenceScopesOut)} ${readDiscordString(commsScopesOut)}'.trim();
      calloc.free(presenceScopesOut);
      calloc.free(commsScopesOut);

      b.authArgsInit(args);
      b.authArgsSetClientId(args, _applicationId);
      final scopesStr = allocateDiscordString(scopes);
      b.authArgsSetScopes(args, scopesStr.ref);
      freeDiscordString(scopesStr);
      b.authArgsSetCodeChallenge(args, challenge);

      final authResult = await _authorize(b, client, args);
      if (authResult == null) return false;

      final tokenResult = await _getToken(
        b,
        client,
        code: authResult.code,
        codeVerifier: codeVerifierValue,
        redirectUri: authResult.redirectUri,
      );
      if (tokenResult == null) return false;
      debugPrint('DiscordSocialService: GetToken succeeded, saving refresh token (len=${tokenResult.refreshToken.length})');
      await DiscordAuthSettings().saveRefreshToken(tokenResult.refreshToken);
      return await _updateToken(b, client, tokenResult.accessToken);
    } finally {
      b.authArgsDrop(args);
      calloc.free(args);
      b.codeChallengeDrop(challenge);
      calloc.free(challenge);
      b.codeVerifierDrop(verifier);
      calloc.free(verifier);
    }
  }

  Future<_AuthorizeResult?> _authorize(
    DiscordSocialBindings b,
    Pointer<DiscordClient> client,
    Pointer<DiscordAuthorizationArgs> args,
  ) async {
    final completer = Completer<_AuthorizeResult?>();
    late final NativeCallable<DiscordAuthorizationCallbackNative> callable;
    void handler(Pointer<DiscordClientResult> result, DiscordString code, DiscordString redirectUri, Pointer<Void> userData) {
      if (!completer.isCompleted) {
        completer.complete(
          !_checkResult(b, 'Authorize', result)
              ? null
              : _AuthorizeResult(code: decodeDiscordStringValue(code), redirectUri: decodeDiscordStringValue(redirectUri)),
        );
      }
      callable.close();
    }

    callable = NativeCallable<DiscordAuthorizationCallbackNative>.listener(handler);
    b.authorize(client, args, callable.nativeFunction, DiscordRpcBindings.noFreeFn, nullptr);
    return completer.future.timeout(
      const Duration(minutes: 5), // user needs time to interact with the consent screen
      onTimeout: () {
        debugPrint('DiscordSocialService: Authorize timed out waiting for user consent');
        return null;
      },
    );
  }

  Future<_TokenResult?> _getToken(
    DiscordSocialBindings b,
    Pointer<DiscordClient> client, {
    required String code,
    required String codeVerifier,
    required String redirectUri,
  }) async {
    final completer = Completer<_TokenResult?>();
    late final NativeCallable<DiscordTokenExchangeCallbackNative> callable;
    void handler(
      Pointer<DiscordClientResult> result,
      DiscordString accessToken,
      DiscordString refreshToken,
      int tokenType,
      int expiresIn,
      DiscordString scopes,
      Pointer<Void> userData,
    ) {
      if (!completer.isCompleted) {
        completer.complete(
          !_checkResult(b, 'GetToken', result)
              ? null
              : _TokenResult(accessToken: decodeDiscordStringValue(accessToken), refreshToken: decodeDiscordStringValue(refreshToken)),
        );
      }
      callable.close();
    }

    callable = NativeCallable<DiscordTokenExchangeCallbackNative>.listener(handler);
    final codeStr = allocateDiscordString(code);
    final verifierStr = allocateDiscordString(codeVerifier);
    final redirectStr = allocateDiscordString(redirectUri);
    try {
      b.getToken(
        client,
        _applicationId,
        codeStr.ref,
        verifierStr.ref,
        redirectStr.ref,
        callable.nativeFunction,
        DiscordRpcBindings.noFreeFn,
        nullptr,
      );
    } finally {
      freeDiscordString(codeStr);
      freeDiscordString(verifierStr);
      freeDiscordString(redirectStr);
    }
    return completer.future.timeout(const Duration(seconds: 15), onTimeout: () => null);
  }

  Future<bool> _updateToken(DiscordSocialBindings b, Pointer<DiscordClient> client, String accessToken) async {
    final completer = Completer<bool>();
    late final NativeCallable<DiscordUpdateTokenCallbackNative> callable;
    void handler(Pointer<DiscordClientResult> result, Pointer<Void> userData) {
      if (!completer.isCompleted) completer.complete(_checkResult(b, 'UpdateToken', result));
      callable.close();
    }

    callable = NativeCallable<DiscordUpdateTokenCallbackNative>.listener(handler);
    final tokenStr = allocateDiscordString(accessToken);
    try {
      b.updateToken(
        client,
        discordAuthorizationTokenTypeBearer,
        tokenStr.ref,
        callable.nativeFunction,
        DiscordRpcBindings.noFreeFn,
        nullptr,
      );
    } finally {
      freeDiscordString(tokenStr);
    }
    return completer.future.timeout(const Duration(seconds: 10), onTimeout: () => false);
  }

  /// Fetches the caller's real Discord friends list (every real friend,
  /// regardless of status -- see [DiscordFriend]'s doc for why "offline"
  /// isn't filtered out here).
  Future<List<DiscordFriend>> fetchInvitableFriends() async {
    final b = _bindings;
    final client = _client;
    if (b == null || client == null || !isReady) return const [];
    final span = calloc<DiscordRelationshipHandleSpan>();
    try {
      b.getRelationships(client, span);
      final friends = <DiscordFriend>[];
      for (var i = 0; i < span.ref.size; i++) {
        final rel = span.ref.ptr + i;
        if (b.relationshipDiscordType(rel) != discordRelationshipTypeFriend) continue;
        final user = calloc<DiscordUserHandle>();
        try {
          if (!b.relationshipUser(rel, user)) continue;
          final status = b.userStatus(user);

          final usernameOut = calloc<DiscordString>();
          final displayOut = calloc<DiscordString>();
          final avatarOut = calloc<DiscordString>();
          try {
            b.userUsername(user, usernameOut);
            b.userDisplayName(user, displayOut);
            b.userAvatarUrl(user, discordUserHandleAvatarTypePng, discordUserHandleAvatarTypePng, avatarOut);
            final username = readDiscordString(usernameOut);
            final displayName = readDiscordString(displayOut);
            final avatarUrl = readDiscordString(avatarOut);
            friends.add(
              DiscordFriend(
                userId: b.userId(user),
                username: username,
                displayName: displayName.isEmpty ? username : displayName,
                status: status,
                avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
              ),
            );
          } finally {
            calloc.free(usernameOut);
            calloc.free(displayOut);
            calloc.free(avatarOut);
          }
        } finally {
          b.userDrop(user);
          calloc.free(user);
        }
      }
      return friends;
    } catch (e) {
      debugPrint('DiscordSocialService: fetchInvitableFriends failed ($e)');
      return const [];
    } finally {
      // NOTE: not freeing span.ref.ptr (the SDK-allocated relationship
      // array itself) -- same documented-nowhere ownership ambiguity as
      // individual Discord_String buffers (see readDiscordString's doc);
      // this is called at most once per Invite-mode session, so the leak
      // is negligible against the crash risk of guessing wrong.
      calloc.free(span);
    }
  }

  /// Sends a targeted Discord activity invite to [friendUserId], carrying
  /// [joinSecret] (delivered back verbatim via [joinSecretReceived] if
  /// they accept). Resolves `true` once Discord acknowledges the send --
  /// this does NOT mean the friend has seen or acted on it yet.
  Future<bool> sendGameInvite({required int friendUserId, required String joinSecret}) async {
    final b = _bindings;
    final client = _client;
    if (b == null || client == null || !isReady) return false;
    final completer = Completer<bool>();
    late final NativeCallable<DiscordSendActivityInviteCallbackNative> callable;
    void handler(Pointer<DiscordClientResult> result, Pointer<Void> userData) {
      if (!completer.isCompleted) completer.complete(_checkResult(b, 'SendActivityInvite', result));
      callable.close();
    }

    callable = NativeCallable<DiscordSendActivityInviteCallbackNative>.listener(handler);
    final contentStr = allocateDiscordString('Join my Cardflux game!');
    try {
      b.sendActivityInvite(
        client,
        friendUserId,
        contentStr.ref,
        callable.nativeFunction,
        DiscordRpcBindings.noFreeFn,
        nullptr,
      );
    } catch (e) {
      debugPrint('DiscordSocialService: sendGameInvite failed ($e)');
      callable.close();
      return false;
    } finally {
      freeDiscordString(contentStr);
    }
    return completer.future.timeout(const Duration(seconds: 10), onTimeout: () => false);
  }

  void dispose() {
    _statusCallable?.close();
    _statusCallable = null;
    _joinCallable?.close();
    _joinCallable = null;
    _client = null;
    _bindings = null;
  }
}

class _AuthorizeResult {
  const _AuthorizeResult({required this.code, required this.redirectUri});
  final String code;
  final String redirectUri;
}

class _TokenResult {
  const _TokenResult({required this.accessToken, required this.refreshToken});
  final String accessToken;
  final String refreshToken;
}
