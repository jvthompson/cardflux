import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_deck/networking/net_message.dart';

void main() {
  group('NetMessage', () {
    for (final type in NetMessageType.values) {
      test('round-trips through JSON for $type', () {
        final msg = NetMessage(type: type, payload: {'a': 1, 'b': 'two'});
        final roundTripped = NetMessage.fromJson(msg.toJson());
        expect(roundTripped.type, type);
        expect(roundTripped.payload, {'a': 1, 'b': 'two'});
      });
    }

    test('defaults to an empty payload', () {
      const msg = NetMessage(type: NetMessageType.ping);
      expect(msg.payload, isEmpty);
    });
  });

  group('encodeLine/decodeMessages', () {
    test('encodes as one JSON object per line', () {
      const msg = NetMessage(type: NetMessageType.hello, payload: {'name': 'Alice'});
      final line = encodeLine(msg);
      expect(line.endsWith('\n'), isTrue);
      expect(jsonDecode(line.trim()), {'type': 'hello', 'payload': {'name': 'Alice'}});
    });

    test('decodes multiple messages sent across separate chunks, including a split mid-line', () async {
      const msgA = NetMessage(type: NetMessageType.hello, payload: {'name': 'Alice'});
      const msgB = NetMessage(type: NetMessageType.ping);
      final fullLineA = encodeLine(msgA);
      final splitPoint = fullLineA.length ~/ 2;

      // Uint8List, not List<int>, matching Socket's actual element type --
      // this is what previously slipped a runtime-only StreamTransformer
      // type error past this test (see decodeMessages' .cast<List<int>>()).
      final controller = StreamController<Uint8List>();
      final received = <NetMessage>[];
      final done = Completer<void>();
      final sub = decodeMessages(controller.stream).listen(received.add, onDone: done.complete);

      controller.add(utf8.encode(fullLineA.substring(0, splitPoint)));
      controller.add(utf8.encode(fullLineA.substring(splitPoint)));
      controller.add(utf8.encode(encodeLine(msgB)));
      await controller.close();
      await done.future.timeout(const Duration(seconds: 5));
      await sub.cancel();

      expect(received, hasLength(2));
      expect(received[0].type, NetMessageType.hello);
      expect(received[0].payload['name'], 'Alice');
      expect(received[1].type, NetMessageType.ping);
    });

    test('ignores blank lines', () async {
      // Uint8List, not List<int>, matching Socket's actual element type --
      // this is what previously slipped a runtime-only StreamTransformer
      // type error past this test (see decodeMessages' .cast<List<int>>()).
      final controller = StreamController<Uint8List>();
      final received = <NetMessage>[];
      final done = Completer<void>();
      final sub = decodeMessages(controller.stream).listen(received.add, onDone: done.complete);

      controller.add(utf8.encode('\n${encodeLine(const NetMessage(type: NetMessageType.pong))}\n'));
      await controller.close();
      await done.future.timeout(const Duration(seconds: 5));
      await sub.cancel();

      expect(received, hasLength(1));
      expect(received.single.type, NetMessageType.pong);
    });
  });
}
