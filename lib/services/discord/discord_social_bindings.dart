import 'dart:convert';
import 'dart:ffi';

import 'discord_rpc_bindings.dart' show DiscordActivity, DiscordClient, DiscordClientResult, DiscordString;

/// Hand-written `dart:ffi` bindings for the OAuth/relationships/invite
/// subset of Discord Social SDK 1.10.19337's C API (`cdiscord.h`) needed to
/// invite a Discord friend to join a hosted Cardflux game. Kept separate
/// from `discord_rpc_bindings.dart` (which stays scoped to the small,
/// no-login Rich Presence path) since this file's OAuth/relationship
/// surface is much larger and involves a real user-facing login.
///
/// Verified directly against `C:\Dev\SDK\discord_social_sdk\include\cdiscord.h`
/// line by line -- in particular, which functions take a `Discord_String` BY
/// VALUE (a plain struct parameter) vs BY POINTER (`Discord_String*`), since
/// the header is not consistent about this per-function.

/// Every SDK handle struct is `{ void* opaque; }` -- the caller allocates it
/// and passes its address; the matching `_Init`/`Create*` function fills in
/// `opaque` internally. Same pattern as `DiscordClient`/`DiscordActivity` in
/// `discord_rpc_bindings.dart`.
final class DiscordAuthorizationArgs extends Struct {
  external Pointer<Void> opaque;
}

final class DiscordAuthorizationCodeVerifier extends Struct {
  external Pointer<Void> opaque;
}

final class DiscordAuthorizationCodeChallenge extends Struct {
  external Pointer<Void> opaque;
}

final class DiscordActivityParty extends Struct {
  external Pointer<Void> opaque;
}

final class DiscordActivitySecrets extends Struct {
  external Pointer<Void> opaque;
}

final class DiscordRelationshipHandle extends Struct {
  external Pointer<Void> opaque;
}

final class DiscordUserHandle extends Struct {
  external Pointer<Void> opaque;
}

/// `Discord_RelationshipHandleSpan`/`Discord_UserHandleSpan` are literal
/// `{ptr, size}` array views (same shape as `DiscordString`), NOT opaque
/// handles -- the SDK allocates `.ptr`, we read `.size` entries out of it.
final class DiscordRelationshipHandleSpan extends Struct {
  external Pointer<DiscordRelationshipHandle> ptr;
  @Size()
  external int size;
}

final class DiscordUserHandleSpan extends Struct {
  external Pointer<DiscordUserHandle> ptr;
  @Size()
  external int size;
}

/// `Discord_Client_Status` (cdiscord.h ~line 305) -- only the value this
/// app actually branches on is named; others are logged as their raw int.
const int discordClientStatusReady = 3;

/// `Discord_StatusType` (cdiscord.h ~line 280).
const int discordStatusTypeOffline = 1;

/// `Discord_RelationshipType` (cdiscord.h ~line 250).
const int discordRelationshipTypeFriend = 1;

/// `Discord_ActivityPartyPrivacy` (cdiscord.h ~line 54) -- MVP always
/// invites explicitly, never publicly, so only this value is used.
const int discordActivityPartyPrivacyPrivate = 0;

/// `Discord_UserHandle_AvatarType` (cdiscord.h ~line 272).
const int discordUserHandleAvatarTypePng = 2;

/// `Discord_AuthorizationTokenType` (cdiscord.h ~line 323).
const int discordAuthorizationTokenTypeBearer = 1;

/// `Discord_ActivityGamePlatforms` (cdiscord.h ~line 78) -- a bitflag enum.
/// Required on the Activity for Discord to consider the game "detected"/
/// launchable at all on a given platform; without this the Join button
/// shows as disabled with a "game not detected" message, even with a valid
/// party/join secret set (learned the hard way -- verified against
/// Discord's own "Managing Game Invites" guide, which sets this
/// explicitly and calls it out as one of three required Rich Presence
/// fields alongside party and secrets).
const int discordActivityGamePlatformsDesktop = 1;

/// Decodes a `Discord_String` the SDK has written into [out] (e.g. via a
/// `_returnValue` out-parameter) to a Dart String. Deliberately does not
/// free the native buffer afterward: ownership/free semantics for these
/// SDK-populated out-strings aren't documented anywhere in the header, and
/// a wrong guess there is a crash (double free / freeing SDK-internal
/// memory) while a missed free is only a small leak -- for how
/// infrequently these are called (once per friend per list refresh, a
/// handful of times during OAuth), the leak is the safer tradeoff.
String readDiscordString(Pointer<DiscordString> out) => decodeDiscordStringValue(out.ref);

/// Same decoding as [readDiscordString], for a `Discord_String` received BY
/// VALUE (as several callback parameters are -- see e.g.
/// [DiscordActivityJoinCallbackNative]) rather than via an out-pointer.
String decodeDiscordStringValue(DiscordString s) {
  if (s.size == 0) return '';
  return utf8.decode(s.ptr.asTypedList(s.size), allowMalformed: true);
}

// ===== OAuth: scopes, PKCE, authorize, token exchange, connect =====

typedef _GetScopesNative = Void Function(Pointer<DiscordString>);
typedef DiscordGetScopesDart = void Function(Pointer<DiscordString>);

typedef _CreateCodeVerifierNative = Void Function(Pointer<DiscordClient>, Pointer<DiscordAuthorizationCodeVerifier>);
typedef DiscordCreateCodeVerifierDart = void Function(Pointer<DiscordClient>, Pointer<DiscordAuthorizationCodeVerifier>);

typedef _CodeVerifierVerifierNative = Void Function(Pointer<DiscordAuthorizationCodeVerifier>, Pointer<DiscordString>);
typedef DiscordCodeVerifierVerifierDart = void Function(Pointer<DiscordAuthorizationCodeVerifier>, Pointer<DiscordString>);

typedef _CodeVerifierChallengeNative =
    Void Function(Pointer<DiscordAuthorizationCodeVerifier>, Pointer<DiscordAuthorizationCodeChallenge>);
typedef DiscordCodeVerifierChallengeDart =
    void Function(Pointer<DiscordAuthorizationCodeVerifier>, Pointer<DiscordAuthorizationCodeChallenge>);

typedef _DropOpaqueNative<T extends NativeType> = Void Function(Pointer<T>);
typedef DiscordDropOpaqueDart<T extends NativeType> = void Function(Pointer<T>);

typedef _AuthArgsInitNative = Void Function(Pointer<DiscordAuthorizationArgs>);
typedef DiscordAuthArgsInitDart = void Function(Pointer<DiscordAuthorizationArgs>);

typedef _AuthArgsSetClientIdNative = Void Function(Pointer<DiscordAuthorizationArgs>, Uint64);
typedef DiscordAuthArgsSetClientIdDart = void Function(Pointer<DiscordAuthorizationArgs>, int);

typedef _AuthArgsSetScopesNative = Void Function(Pointer<DiscordAuthorizationArgs>, DiscordString);
typedef DiscordAuthArgsSetScopesDart = void Function(Pointer<DiscordAuthorizationArgs>, DiscordString);

typedef _AuthArgsSetCodeChallengeNative =
    Void Function(Pointer<DiscordAuthorizationArgs>, Pointer<DiscordAuthorizationCodeChallenge>);
typedef DiscordAuthArgsSetCodeChallengeDart =
    void Function(Pointer<DiscordAuthorizationArgs>, Pointer<DiscordAuthorizationCodeChallenge>);

/// `Discord_Client_AuthorizationCallback` -- `code`/`redirectUri` are passed
/// BY VALUE (plain `Discord_String`, not `Discord_String*`).
typedef DiscordAuthorizationCallbackNative =
    Void Function(Pointer<DiscordClientResult>, DiscordString code, DiscordString redirectUri, Pointer<Void>);
typedef _AuthorizeNative = Void Function(
  Pointer<DiscordClient>,
  Pointer<DiscordAuthorizationArgs>,
  Pointer<NativeFunction<DiscordAuthorizationCallbackNative>>,
  Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
  Pointer<Void>,
);
typedef DiscordAuthorizeDart = void Function(
  Pointer<DiscordClient>,
  Pointer<DiscordAuthorizationArgs>,
  Pointer<NativeFunction<DiscordAuthorizationCallbackNative>>,
  Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
  Pointer<Void>,
);

/// `Discord_Client_TokenExchangeCallback` -- `accessToken`/`refreshToken`/
/// `scopes` all passed BY VALUE. Shared by `GetToken` and `RefreshToken`.
typedef DiscordTokenExchangeCallbackNative =
    Void Function(
      Pointer<DiscordClientResult>,
      DiscordString accessToken,
      DiscordString refreshToken,
      Int32 tokenType,
      Int32 expiresIn,
      DiscordString scopes,
      Pointer<Void>,
    );

typedef _GetTokenNative = Void Function(
  Pointer<DiscordClient>,
  Uint64,
  DiscordString code,
  DiscordString codeVerifier,
  DiscordString redirectUri,
  Pointer<NativeFunction<DiscordTokenExchangeCallbackNative>>,
  Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
  Pointer<Void>,
);
typedef DiscordGetTokenDart = void Function(
  Pointer<DiscordClient>,
  int,
  DiscordString code,
  DiscordString codeVerifier,
  DiscordString redirectUri,
  Pointer<NativeFunction<DiscordTokenExchangeCallbackNative>>,
  Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
  Pointer<Void>,
);

typedef _RefreshTokenNative = Void Function(
  Pointer<DiscordClient>,
  Uint64,
  DiscordString refreshToken,
  Pointer<NativeFunction<DiscordTokenExchangeCallbackNative>>,
  Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
  Pointer<Void>,
);
typedef DiscordRefreshTokenDart = void Function(
  Pointer<DiscordClient>,
  int,
  DiscordString refreshToken,
  Pointer<NativeFunction<DiscordTokenExchangeCallbackNative>>,
  Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
  Pointer<Void>,
);

/// `Discord_Client_UpdateTokenCallback`-equivalent -- the header names this
/// inline rather than via a shared typedef, but its shape is just
/// `(result*, userData)`.
typedef DiscordUpdateTokenCallbackNative = Void Function(Pointer<DiscordClientResult>, Pointer<Void>);

typedef _UpdateTokenNative = Void Function(
  Pointer<DiscordClient>,
  Int32,
  DiscordString token,
  Pointer<NativeFunction<DiscordUpdateTokenCallbackNative>>,
  Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
  Pointer<Void>,
);
typedef DiscordUpdateTokenDart = void Function(
  Pointer<DiscordClient>,
  int,
  DiscordString token,
  Pointer<NativeFunction<DiscordUpdateTokenCallbackNative>>,
  Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
  Pointer<Void>,
);

typedef _ConnectNative = Void Function(Pointer<DiscordClient>);
typedef DiscordConnectDart = void Function(Pointer<DiscordClient>);

typedef _GetStatusNative = Int32 Function(Pointer<DiscordClient>);
typedef DiscordGetStatusDart = int Function(Pointer<DiscordClient>);

/// `Discord_Client_OnStatusChanged` -- registered exactly once for the
/// app's whole lifetime (see `DiscordSocialService.registerLaunchAndJoinHandling`).
typedef DiscordStatusChangedCallbackNative = Void Function(Int32 status, Int32 error, Int32 errorDetail, Pointer<Void>);

typedef _SetStatusChangedCallbackNative = Void Function(
  Pointer<DiscordClient>,
  Pointer<NativeFunction<DiscordStatusChangedCallbackNative>>,
  Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
  Pointer<Void>,
);
typedef DiscordSetStatusChangedCallbackDart = void Function(
  Pointer<DiscordClient>,
  Pointer<NativeFunction<DiscordStatusChangedCallbackNative>>,
  Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
  Pointer<Void>,
);

// ===== Relationships (friends list) =====

typedef _GetRelationshipsNative = Void Function(Pointer<DiscordClient>, Pointer<DiscordRelationshipHandleSpan>);
typedef DiscordGetRelationshipsDart = void Function(Pointer<DiscordClient>, Pointer<DiscordRelationshipHandleSpan>);

typedef _RelationshipTypeNative = Int32 Function(Pointer<DiscordRelationshipHandle>);
typedef DiscordRelationshipTypeDart = int Function(Pointer<DiscordRelationshipHandle>);

typedef _RelationshipUserNative = Bool Function(Pointer<DiscordRelationshipHandle>, Pointer<DiscordUserHandle>);
typedef DiscordRelationshipUserDart = bool Function(Pointer<DiscordRelationshipHandle>, Pointer<DiscordUserHandle>);

typedef _UserIdNative = Uint64 Function(Pointer<DiscordUserHandle>);
typedef DiscordUserIdDart = int Function(Pointer<DiscordUserHandle>);

typedef _UserStringGetterNative = Void Function(Pointer<DiscordUserHandle>, Pointer<DiscordString>);
typedef DiscordUserStringGetterDart = void Function(Pointer<DiscordUserHandle>, Pointer<DiscordString>);

typedef _UserStatusNative = Int32 Function(Pointer<DiscordUserHandle>);
typedef DiscordUserStatusDart = int Function(Pointer<DiscordUserHandle>);

typedef _UserAvatarUrlNative = Void Function(Pointer<DiscordUserHandle>, Int32, Int32, Pointer<DiscordString>);
typedef DiscordUserAvatarUrlDart = void Function(Pointer<DiscordUserHandle>, int, int, Pointer<DiscordString>);

// ===== Activity party/secrets (extends the existing Rich Presence Activity) =====

typedef _PartyInitNative = Void Function(Pointer<DiscordActivityParty>);
typedef DiscordPartyInitDart = void Function(Pointer<DiscordActivityParty>);

typedef _PartySetIdNative = Void Function(Pointer<DiscordActivityParty>, DiscordString);
typedef DiscordPartySetIdDart = void Function(Pointer<DiscordActivityParty>, DiscordString);

typedef _PartySetSizeNative = Void Function(Pointer<DiscordActivityParty>, Int32);
typedef DiscordPartySetSizeDart = void Function(Pointer<DiscordActivityParty>, int);

typedef _SecretsInitNative = Void Function(Pointer<DiscordActivitySecrets>);
typedef DiscordSecretsInitDart = void Function(Pointer<DiscordActivitySecrets>);

typedef _SecretsSetJoinNative = Void Function(Pointer<DiscordActivitySecrets>, DiscordString);
typedef DiscordSecretsSetJoinDart = void Function(Pointer<DiscordActivitySecrets>, DiscordString);

typedef _ActivitySetPartyNative = Void Function(Pointer<DiscordActivity>, Pointer<DiscordActivityParty>);
typedef DiscordActivitySetPartyDart = void Function(Pointer<DiscordActivity>, Pointer<DiscordActivityParty>);

typedef _ActivitySetSecretsNative = Void Function(Pointer<DiscordActivity>, Pointer<DiscordActivitySecrets>);
typedef DiscordActivitySetSecretsDart = void Function(Pointer<DiscordActivity>, Pointer<DiscordActivitySecrets>);

typedef _ActivitySetSupportedPlatformsNative = Void Function(Pointer<DiscordActivity>, Int32);
typedef DiscordActivitySetSupportedPlatformsDart = void Function(Pointer<DiscordActivity>, int);

// ===== Invite send + cold-start launch registration + join callback =====

typedef _RegisterLaunchCommandNative = Bool Function(Pointer<DiscordClient>, Uint64, DiscordString);
typedef DiscordRegisterLaunchCommandDart = bool Function(Pointer<DiscordClient>, int, DiscordString);

typedef DiscordSendActivityInviteCallbackNative = Void Function(Pointer<DiscordClientResult>, Pointer<Void>);

typedef _SendActivityInviteNative = Void Function(
  Pointer<DiscordClient>,
  Uint64,
  DiscordString content,
  Pointer<NativeFunction<DiscordSendActivityInviteCallbackNative>>,
  Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
  Pointer<Void>,
);
typedef DiscordSendActivityInviteDart = void Function(
  Pointer<DiscordClient>,
  int,
  DiscordString content,
  Pointer<NativeFunction<DiscordSendActivityInviteCallbackNative>>,
  Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
  Pointer<Void>,
);

/// `Discord_Client_ActivityJoinCallback` -- fires with the exact string we
/// set via `Discord_ActivitySecrets_SetJoin` when a friend accepts our
/// invite (or otherwise "Join"s us) from inside their own real Discord
/// client. `joinSecret` is passed BY VALUE. Registered exactly once for the
/// app's whole lifetime, unconditionally at startup.
typedef DiscordActivityJoinCallbackNative = Void Function(DiscordString joinSecret, Pointer<Void>);

typedef _SetActivityJoinCallbackNative = Void Function(
  Pointer<DiscordClient>,
  Pointer<NativeFunction<DiscordActivityJoinCallbackNative>>,
  Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
  Pointer<Void>,
);
typedef DiscordSetActivityJoinCallbackDart = void Function(
  Pointer<DiscordClient>,
  Pointer<NativeFunction<DiscordActivityJoinCallbackNative>>,
  Pointer<NativeFunction<Void Function(Pointer<Void>)>>,
  Pointer<Void>,
);

typedef _ResultSuccessfulNative = Bool Function(Pointer<DiscordClientResult>);
typedef DiscordResultSuccessfulDart = bool Function(Pointer<DiscordClientResult>);

typedef _ResultErrorNative = Void Function(Pointer<DiscordClientResult>, Pointer<DiscordString>);
typedef DiscordResultErrorDart = void Function(Pointer<DiscordClientResult>, Pointer<DiscordString>);

typedef _ResultErrorCodeNative = Int32 Function(Pointer<DiscordClientResult>);
typedef DiscordResultErrorCodeDart = int Function(Pointer<DiscordClientResult>);

typedef _ResultTypeNative = Int32 Function(Pointer<DiscordClientResult>);
typedef DiscordResultTypeDart = int Function(Pointer<DiscordClientResult>);

typedef _ResultResponseBodyNative = Void Function(Pointer<DiscordClientResult>, Pointer<DiscordString>);
typedef DiscordResultResponseBodyDart = void Function(Pointer<DiscordClientResult>, Pointer<DiscordString>);

/// Resolves every symbol once at construction time -- same pattern as
/// `DiscordRpcBindings`.
class DiscordSocialBindings {
  DiscordSocialBindings(DynamicLibrary lib)
    : getDefaultPresenceScopes = lib.lookupFunction<_GetScopesNative, DiscordGetScopesDart>(
        'Discord_Client_GetDefaultPresenceScopes',
      ),
      getDefaultCommunicationScopes = lib.lookupFunction<_GetScopesNative, DiscordGetScopesDart>(
        'Discord_Client_GetDefaultCommunicationScopes',
      ),
      createAuthorizationCodeVerifier = lib
          .lookupFunction<_CreateCodeVerifierNative, DiscordCreateCodeVerifierDart>(
            'Discord_Client_CreateAuthorizationCodeVerifier',
          ),
      codeVerifierVerifier = lib.lookupFunction<_CodeVerifierVerifierNative, DiscordCodeVerifierVerifierDart>(
        'Discord_AuthorizationCodeVerifier_Verifier',
      ),
      codeVerifierChallenge = lib.lookupFunction<_CodeVerifierChallengeNative, DiscordCodeVerifierChallengeDart>(
        'Discord_AuthorizationCodeVerifier_Challenge',
      ),
      codeVerifierDrop = lib
          .lookupFunction<
            _DropOpaqueNative<DiscordAuthorizationCodeVerifier>,
            DiscordDropOpaqueDart<DiscordAuthorizationCodeVerifier>
          >('Discord_AuthorizationCodeVerifier_Drop'),
      codeChallengeDrop = lib
          .lookupFunction<
            _DropOpaqueNative<DiscordAuthorizationCodeChallenge>,
            DiscordDropOpaqueDart<DiscordAuthorizationCodeChallenge>
          >('Discord_AuthorizationCodeChallenge_Drop'),
      authArgsInit = lib.lookupFunction<_AuthArgsInitNative, DiscordAuthArgsInitDart>('Discord_AuthorizationArgs_Init'),
      authArgsDrop = lib
          .lookupFunction<_DropOpaqueNative<DiscordAuthorizationArgs>, DiscordDropOpaqueDart<DiscordAuthorizationArgs>>(
            'Discord_AuthorizationArgs_Drop',
          ),
      authArgsSetClientId = lib.lookupFunction<_AuthArgsSetClientIdNative, DiscordAuthArgsSetClientIdDart>(
        'Discord_AuthorizationArgs_SetClientId',
      ),
      authArgsSetScopes = lib.lookupFunction<_AuthArgsSetScopesNative, DiscordAuthArgsSetScopesDart>(
        'Discord_AuthorizationArgs_SetScopes',
      ),
      authArgsSetCodeChallenge = lib
          .lookupFunction<_AuthArgsSetCodeChallengeNative, DiscordAuthArgsSetCodeChallengeDart>(
            'Discord_AuthorizationArgs_SetCodeChallenge',
          ),
      authorize = lib.lookupFunction<_AuthorizeNative, DiscordAuthorizeDart>('Discord_Client_Authorize'),
      getToken = lib.lookupFunction<_GetTokenNative, DiscordGetTokenDart>('Discord_Client_GetToken'),
      refreshToken = lib.lookupFunction<_RefreshTokenNative, DiscordRefreshTokenDart>('Discord_Client_RefreshToken'),
      updateToken = lib.lookupFunction<_UpdateTokenNative, DiscordUpdateTokenDart>('Discord_Client_UpdateToken'),
      connect = lib.lookupFunction<_ConnectNative, DiscordConnectDart>('Discord_Client_Connect'),
      getStatus = lib.lookupFunction<_GetStatusNative, DiscordGetStatusDart>('Discord_Client_GetStatus'),
      setStatusChangedCallback = lib
          .lookupFunction<_SetStatusChangedCallbackNative, DiscordSetStatusChangedCallbackDart>(
            'Discord_Client_SetStatusChangedCallback',
          ),
      getRelationships = lib.lookupFunction<_GetRelationshipsNative, DiscordGetRelationshipsDart>(
        'Discord_Client_GetRelationships',
      ),
      relationshipDiscordType = lib.lookupFunction<_RelationshipTypeNative, DiscordRelationshipTypeDart>(
        'Discord_RelationshipHandle_DiscordRelationshipType',
      ),
      relationshipUser = lib.lookupFunction<_RelationshipUserNative, DiscordRelationshipUserDart>(
        'Discord_RelationshipHandle_User',
      ),
      relationshipDrop = lib
          .lookupFunction<
            _DropOpaqueNative<DiscordRelationshipHandle>,
            DiscordDropOpaqueDart<DiscordRelationshipHandle>
          >('Discord_RelationshipHandle_Drop'),
      userId = lib.lookupFunction<_UserIdNative, DiscordUserIdDart>('Discord_UserHandle_Id'),
      userUsername = lib.lookupFunction<_UserStringGetterNative, DiscordUserStringGetterDart>(
        'Discord_UserHandle_Username',
      ),
      userDisplayName = lib.lookupFunction<_UserStringGetterNative, DiscordUserStringGetterDart>(
        'Discord_UserHandle_DisplayName',
      ),
      userStatus = lib.lookupFunction<_UserStatusNative, DiscordUserStatusDart>('Discord_UserHandle_Status'),
      userAvatarUrl = lib.lookupFunction<_UserAvatarUrlNative, DiscordUserAvatarUrlDart>('Discord_UserHandle_AvatarUrl'),
      userDrop = lib.lookupFunction<_DropOpaqueNative<DiscordUserHandle>, DiscordDropOpaqueDart<DiscordUserHandle>>(
        'Discord_UserHandle_Drop',
      ),
      partyInit = lib.lookupFunction<_PartyInitNative, DiscordPartyInitDart>('Discord_ActivityParty_Init'),
      partyDrop = lib
          .lookupFunction<_DropOpaqueNative<DiscordActivityParty>, DiscordDropOpaqueDart<DiscordActivityParty>>(
            'Discord_ActivityParty_Drop',
          ),
      partySetId = lib.lookupFunction<_PartySetIdNative, DiscordPartySetIdDart>('Discord_ActivityParty_SetId'),
      partySetCurrentSize = lib.lookupFunction<_PartySetSizeNative, DiscordPartySetSizeDart>(
        'Discord_ActivityParty_SetCurrentSize',
      ),
      partySetMaxSize = lib.lookupFunction<_PartySetSizeNative, DiscordPartySetSizeDart>(
        'Discord_ActivityParty_SetMaxSize',
      ),
      partySetPrivacy = lib.lookupFunction<_PartySetSizeNative, DiscordPartySetSizeDart>(
        'Discord_ActivityParty_SetPrivacy',
      ),
      secretsInit = lib.lookupFunction<_SecretsInitNative, DiscordSecretsInitDart>('Discord_ActivitySecrets_Init'),
      secretsDrop = lib
          .lookupFunction<_DropOpaqueNative<DiscordActivitySecrets>, DiscordDropOpaqueDart<DiscordActivitySecrets>>(
            'Discord_ActivitySecrets_Drop',
          ),
      secretsSetJoin = lib.lookupFunction<_SecretsSetJoinNative, DiscordSecretsSetJoinDart>(
        'Discord_ActivitySecrets_SetJoin',
      ),
      activitySetParty = lib.lookupFunction<_ActivitySetPartyNative, DiscordActivitySetPartyDart>(
        'Discord_Activity_SetParty',
      ),
      activitySetSecrets = lib.lookupFunction<_ActivitySetSecretsNative, DiscordActivitySetSecretsDart>(
        'Discord_Activity_SetSecrets',
      ),
      activitySetSupportedPlatforms = lib
          .lookupFunction<_ActivitySetSupportedPlatformsNative, DiscordActivitySetSupportedPlatformsDart>(
            'Discord_Activity_SetSupportedPlatforms',
          ),
      registerLaunchCommand = lib.lookupFunction<_RegisterLaunchCommandNative, DiscordRegisterLaunchCommandDart>(
        'Discord_Client_RegisterLaunchCommand',
      ),
      sendActivityInvite = lib.lookupFunction<_SendActivityInviteNative, DiscordSendActivityInviteDart>(
        'Discord_Client_SendActivityInvite',
      ),
      setActivityJoinCallback = lib
          .lookupFunction<_SetActivityJoinCallbackNative, DiscordSetActivityJoinCallbackDart>(
            'Discord_Client_SetActivityJoinCallback',
          ),
      resultSuccessful = lib.lookupFunction<_ResultSuccessfulNative, DiscordResultSuccessfulDart>(
        'Discord_ClientResult_Successful',
      ),
      resultError = lib.lookupFunction<_ResultErrorNative, DiscordResultErrorDart>('Discord_ClientResult_Error'),
      resultErrorCode = lib.lookupFunction<_ResultErrorCodeNative, DiscordResultErrorCodeDart>(
        'Discord_ClientResult_ErrorCode',
      ),
      resultType = lib.lookupFunction<_ResultTypeNative, DiscordResultTypeDart>('Discord_ClientResult_Type'),
      resultResponseBody = lib.lookupFunction<_ResultResponseBodyNative, DiscordResultResponseBodyDart>(
        'Discord_ClientResult_ResponseBody',
      );

  final DiscordGetScopesDart getDefaultPresenceScopes;
  final DiscordGetScopesDart getDefaultCommunicationScopes;
  final DiscordCreateCodeVerifierDart createAuthorizationCodeVerifier;
  final DiscordCodeVerifierVerifierDart codeVerifierVerifier;
  final DiscordCodeVerifierChallengeDart codeVerifierChallenge;
  final DiscordDropOpaqueDart<DiscordAuthorizationCodeVerifier> codeVerifierDrop;
  final DiscordDropOpaqueDart<DiscordAuthorizationCodeChallenge> codeChallengeDrop;
  final DiscordAuthArgsInitDart authArgsInit;
  final DiscordDropOpaqueDart<DiscordAuthorizationArgs> authArgsDrop;
  final DiscordAuthArgsSetClientIdDart authArgsSetClientId;
  final DiscordAuthArgsSetScopesDart authArgsSetScopes;
  final DiscordAuthArgsSetCodeChallengeDart authArgsSetCodeChallenge;
  final DiscordAuthorizeDart authorize;
  final DiscordGetTokenDart getToken;
  final DiscordRefreshTokenDart refreshToken;
  final DiscordUpdateTokenDart updateToken;
  final DiscordConnectDart connect;
  final DiscordGetStatusDart getStatus;
  final DiscordSetStatusChangedCallbackDart setStatusChangedCallback;
  final DiscordGetRelationshipsDart getRelationships;
  final DiscordRelationshipTypeDart relationshipDiscordType;
  final DiscordRelationshipUserDart relationshipUser;
  final DiscordDropOpaqueDart<DiscordRelationshipHandle> relationshipDrop;
  final DiscordUserIdDart userId;
  final DiscordUserStringGetterDart userUsername;
  final DiscordUserStringGetterDart userDisplayName;
  final DiscordUserStatusDart userStatus;
  final DiscordUserAvatarUrlDart userAvatarUrl;
  final DiscordDropOpaqueDart<DiscordUserHandle> userDrop;
  final DiscordPartyInitDart partyInit;
  final DiscordDropOpaqueDart<DiscordActivityParty> partyDrop;
  final DiscordPartySetIdDart partySetId;
  final DiscordPartySetSizeDart partySetCurrentSize;
  final DiscordPartySetSizeDart partySetMaxSize;
  final DiscordPartySetSizeDart partySetPrivacy;
  final DiscordSecretsInitDart secretsInit;
  final DiscordDropOpaqueDart<DiscordActivitySecrets> secretsDrop;
  final DiscordSecretsSetJoinDart secretsSetJoin;
  final DiscordActivitySetPartyDart activitySetParty;
  final DiscordActivitySetSecretsDart activitySetSecrets;
  final DiscordActivitySetSupportedPlatformsDart activitySetSupportedPlatforms;
  final DiscordRegisterLaunchCommandDart registerLaunchCommand;
  final DiscordSendActivityInviteDart sendActivityInvite;
  final DiscordSetActivityJoinCallbackDart setActivityJoinCallback;
  final DiscordResultSuccessfulDart resultSuccessful;
  final DiscordResultErrorDart resultError;
  final DiscordResultErrorCodeDart resultErrorCode;
  final DiscordResultTypeDart resultType;
  final DiscordResultResponseBodyDart resultResponseBody;
}
