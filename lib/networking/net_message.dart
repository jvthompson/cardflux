import 'dart:convert';

/// Default TCP port a host binds to and a joiner's IP-entry screen
/// pre-fills, so a LAN game normally needs no port to be communicated
/// out-of-band -- just the host's IP address.
const int defaultGamePort = 51234;

/// How often each side of a connection sends an unprompted [NetMessageType.ping]
/// to the other -- keeps the line active and lets [heartbeatTimeout] detect a
/// silently-dead peer (as opposed to a clean process exit, which the socket's
/// own `onDone`/`onError` already reports immediately).
const Duration heartbeatInterval = Duration(seconds: 4);

/// How long without receiving *any* message (gameplay traffic or a ping)
/// before a connection is considered dead and forcibly dropped.
const Duration heartbeatTimeout = Duration(seconds: 12);

enum NetMessageType {
  hello,
  welcome,
  gameData,
  fullState,
  requestDeckChosen,
  requestReady,
  lobbyRosterUpdate,
  lobbyReadyUpdate,
  requestMove,
  requestMoveStack,
  requestMoveGroup,
  requestRotateStack,
  requestFlip,
  requestStack,
  requestMoveToHand,
  requestReorderHand,
  requestDraw,
  requestShuffle,
  requestDrawFromZone,
  requestReturnToZone,
  requestShuffleZone,
  requestStartSearchZone,
  requestStartSearchPile,
  requestStopSearch,
  requestCreateWidget,
  requestCreateArrow,
  requestMoveWidget,
  requestSetWidgetValue,
  requestDeleteWidget,
  requestSetWidgetColors,
  requestDuplicateWidget,
  requestAttachWidgetToCard,
  ping,
  pong,
  disconnect;

  static NetMessageType fromName(String name) =>
      NetMessageType.values.byName(name);
}

/// One protocol message. Framed on the wire as one JSON object per line
/// (see [encodeLine]/[decodeMessages]) over a plain TCP socket.
class NetMessage {
  const NetMessage({required this.type, this.payload = const {}});

  final NetMessageType type;
  final Map<String, dynamic> payload;

  factory NetMessage.fromJson(Map<String, dynamic> json) {
    return NetMessage(
      type: NetMessageType.fromName(json['type'] as String),
      payload: (json['payload'] as Map?)?.cast<String, dynamic>() ?? const {},
    );
  }

  Map<String, dynamic> toJson() => {'type': type.name, 'payload': payload};
}

/// A [NetMessage] paired with the id of whichever connected client actually
/// sent it -- [HostServer.incoming] emits this instead of a bare [NetMessage]
/// so [HostGameEngine]/`HostLoadDeckScreen` can tell N clients' requests
/// apart, instead of assuming (as when this app supported only one client)
/// that every incoming message came from "the" one opponent.
class IncomingMessage {
  const IncomingMessage({required this.senderId, required this.message});

  final String senderId;
  final NetMessage message;
}

/// Encodes [msg] as one line of newline-delimited JSON, ready to write
/// straight to a [Socket].
String encodeLine(NetMessage msg) => '${jsonEncode(msg.toJson())}\n';

/// Decodes a raw byte stream (e.g. a [Socket]) into [NetMessage]s, one per
/// line. Handles partial-packet reassembly via [LineSplitter]; blank lines
/// (e.g. a trailing newline) are ignored.
Stream<NetMessage> decodeMessages(Stream<List<int>> byteStream) {
  // A raw Socket is a Stream<Uint8List>, whose reified type argument makes
  // utf8.decoder's transform() fail at runtime unless first cast down to
  // the plain List<int> this function declares.
  return byteStream
      .cast<List<int>>()
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .where((line) => line.trim().isNotEmpty)
      .map(
        (line) => NetMessage.fromJson(jsonDecode(line) as Map<String, dynamic>),
      );
}
