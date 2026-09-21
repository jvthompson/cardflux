import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Hand-written `dart:ffi` bindings for the small subset of Discord Social
/// SDK 1.10.19337's C API (`cdiscord.h`) needed for text-only Rich Presence.
/// Verified directly against the header at
/// `C:\Dev\SDK\discord_social_sdk\include\cdiscord.h` -- not just its doc
/// comments -- so the struct layouts and parameter order below are exact.

/// Every SDK "handle" struct in cdiscord.h is just `{ void* opaque; }` --
/// the caller allocates it (8 bytes on x64) and passes its address; the
/// matching `_Init` function fills in `opaque` internally. No size-query or
/// factory function exists or is needed.
final class DiscordClient extends Struct {
  external Pointer<Void> opaque;
}

final class DiscordActivity extends Struct {
  external Pointer<Void> opaque;
}

final class DiscordClientResult extends Struct {
  external Pointer<Void> opaque;
}

/// `cdiscord.h`'s string type is a `{ptr, size}` byte slice, NOT a
/// null-terminated C string.
final class DiscordString extends Struct {
  external Pointer<Uint8> ptr;
  @Size()
  external int size;
}

/// `Discord_ActivityTypes_Playing = 0` (cdiscord.h line ~61).
const int discordActivityTypesPlaying = 0;

typedef _DiscordClientInitNative = Void Function(Pointer<DiscordClient>);
typedef DiscordClientInitDart = void Function(Pointer<DiscordClient>);

typedef _DiscordClientDropNative = Void Function(Pointer<DiscordClient>);
typedef DiscordClientDropDart = void Function(Pointer<DiscordClient>);

typedef _DiscordClientSetApplicationIdNative = Void Function(Pointer<DiscordClient>, Uint64);
typedef DiscordClientSetApplicationIdDart = void Function(Pointer<DiscordClient>, int);

typedef _DiscordRunCallbacksNative = Void Function();
typedef DiscordRunCallbacksDart = void Function();

typedef _DiscordActivityInitNative = Void Function(Pointer<DiscordActivity>);
typedef DiscordActivityInitDart = void Function(Pointer<DiscordActivity>);

typedef _DiscordActivityDropNative = Void Function(Pointer<DiscordActivity>);
typedef DiscordActivityDropDart = void Function(Pointer<DiscordActivity>);

typedef _DiscordActivitySetTypeNative = Void Function(Pointer<DiscordActivity>, Int32);
typedef DiscordActivitySetTypeDart = void Function(Pointer<DiscordActivity>, int);

typedef _DiscordActivitySetStateNative = Void Function(Pointer<DiscordActivity>, Pointer<DiscordString>);
typedef DiscordActivitySetStateDart = void Function(Pointer<DiscordActivity>, Pointer<DiscordString>);

typedef _DiscordActivitySetDetailsNative = Void Function(Pointer<DiscordActivity>, Pointer<DiscordString>);
typedef DiscordActivitySetDetailsDart = void Function(Pointer<DiscordActivity>, Pointer<DiscordString>);

/// `Discord_Client_UpdateRichPresenceCallback` is `void(*)(Discord_ClientResult*, void*)`.
typedef DiscordUpdateRichPresenceCallback = Pointer<NativeFunction<Void Function(Pointer<DiscordClientResult>, Pointer<Void>)>>;
typedef DiscordFreeFn = Pointer<NativeFunction<Void Function(Pointer<Void>)>>;

// Discord_Client_UpdateRichPresence does NOT null-check `cb` before invoking
// it once the update completes (observed during implementation: passing
// `nullptr` crashes with an access violation at address 0 on a LATER
// Discord_RunCallbacks() tick, when the SDK gets around to calling it). We
// don't care about the result for v1, but we must still hand it a real
// function pointer -- a persistent, app-lifetime no-op via NativeCallable.
void _noOpUpdateRichPresenceCallback(Pointer<DiscordClientResult> result, Pointer<Void> userData) {}
void _noOpFreeFn(Pointer<Void> ptr) {}

final NativeCallable<Void Function(Pointer<DiscordClientResult>, Pointer<Void>)> _updateRichPresenceCallable =
    NativeCallable.listener(_noOpUpdateRichPresenceCallback);
final NativeCallable<Void Function(Pointer<Void>)> _freeFnCallable = NativeCallable.listener(_noOpFreeFn);

typedef _DiscordClientUpdateRichPresenceNative = Void Function(
  Pointer<DiscordClient>,
  Pointer<DiscordActivity>,
  DiscordUpdateRichPresenceCallback,
  DiscordFreeFn,
  Pointer<Void>,
);
typedef DiscordClientUpdateRichPresenceDart = void Function(
  Pointer<DiscordClient>,
  Pointer<DiscordActivity>,
  DiscordUpdateRichPresenceCallback,
  DiscordFreeFn,
  Pointer<Void>,
);

typedef _DiscordClientClearRichPresenceNative = Void Function(Pointer<DiscordClient>);
typedef DiscordClientClearRichPresenceDart = void Function(Pointer<DiscordClient>);

/// Resolves every symbol once at construction time.
class DiscordRpcBindings {
  DiscordRpcBindings(DynamicLibrary lib)
    : clientInit = lib.lookupFunction<_DiscordClientInitNative, DiscordClientInitDart>('Discord_Client_Init'),
      clientDrop = lib.lookupFunction<_DiscordClientDropNative, DiscordClientDropDart>('Discord_Client_Drop'),
      clientSetApplicationId = lib
          .lookupFunction<_DiscordClientSetApplicationIdNative, DiscordClientSetApplicationIdDart>(
            'Discord_Client_SetApplicationId',
          ),
      runCallbacks = lib.lookupFunction<_DiscordRunCallbacksNative, DiscordRunCallbacksDart>('Discord_RunCallbacks'),
      activityInit = lib.lookupFunction<_DiscordActivityInitNative, DiscordActivityInitDart>('Discord_Activity_Init'),
      activityDrop = lib.lookupFunction<_DiscordActivityDropNative, DiscordActivityDropDart>('Discord_Activity_Drop'),
      activitySetType = lib.lookupFunction<_DiscordActivitySetTypeNative, DiscordActivitySetTypeDart>(
        'Discord_Activity_SetType',
      ),
      activitySetState = lib.lookupFunction<_DiscordActivitySetStateNative, DiscordActivitySetStateDart>(
        'Discord_Activity_SetState',
      ),
      activitySetDetails = lib.lookupFunction<_DiscordActivitySetDetailsNative, DiscordActivitySetDetailsDart>(
        'Discord_Activity_SetDetails',
      ),
      clientUpdateRichPresence = lib
          .lookupFunction<_DiscordClientUpdateRichPresenceNative, DiscordClientUpdateRichPresenceDart>(
            'Discord_Client_UpdateRichPresence',
          ),
      clientClearRichPresence = lib
          .lookupFunction<_DiscordClientClearRichPresenceNative, DiscordClientClearRichPresenceDart>(
            'Discord_Client_ClearRichPresence',
          );

  final DiscordClientInitDart clientInit;
  final DiscordClientDropDart clientDrop;
  final DiscordClientSetApplicationIdDart clientSetApplicationId;
  final DiscordRunCallbacksDart runCallbacks;
  final DiscordActivityInitDart activityInit;
  final DiscordActivityDropDart activityDrop;
  final DiscordActivitySetTypeDart activitySetType;
  final DiscordActivitySetStateDart activitySetState;
  final DiscordActivitySetDetailsDart activitySetDetails;
  final DiscordClientUpdateRichPresenceDart clientUpdateRichPresence;
  final DiscordClientClearRichPresenceDart clientClearRichPresence;

  /// Passed as `cb`/`cb__userDataFree` to [clientUpdateRichPresence] when the
  /// caller doesn't care about the result (fire-and-forget) -- real no-op
  /// function pointers, NOT null (see the comment above [_noOpFreeFn]).
  static DiscordUpdateRichPresenceCallback get noCallback => _updateRichPresenceCallable.nativeFunction;
  static DiscordFreeFn get noFreeFn => _freeFnCallable.nativeFunction;
}

/// Allocates a native [DiscordString] view over a UTF-8 encoding of [text].
/// Both the returned struct and its `.ref.ptr` buffer must be freed with
/// [freeDiscordString] once the SDK call that consumed it has returned.
Pointer<DiscordString> allocateDiscordString(String text) {
  final bytes = utf8.encode(text);
  final buffer = calloc<Uint8>(bytes.isEmpty ? 1 : bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    buffer[i] = bytes[i];
  }
  final str = calloc<DiscordString>();
  str.ref.ptr = buffer;
  str.ref.size = bytes.length;
  return str;
}

void freeDiscordString(Pointer<DiscordString> str) {
  calloc.free(str.ref.ptr);
  calloc.free(str);
}
