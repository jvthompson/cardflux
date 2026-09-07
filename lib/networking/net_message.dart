import 'dart:convert';

/// Default TCP port a host binds to and a joiner's IP-entry screen
/// pre-fills, so a LAN game normally needs no port to be communicated
/// out-of-band -- just the host's IP address.
const int defaultGamePort = 51234;

enum NetMessageType {
  hello,
  welcome,
  fullState,
  requestMove,
  requestFlip,
  requestStack,
  requestDraw,
  requestShuffle,
  ping,
  pong,
  disconnect;

  static NetMessageType fromName(String name) => NetMessageType.values.byName(name);
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
      .map((line) => NetMessage.fromJson(jsonDecode(line) as Map<String, dynamic>));
}
