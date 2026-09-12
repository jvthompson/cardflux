import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_deck/game/seat_utils.dart';
import 'package:flutter_deck/models/player.dart';

const _p1 = PlayerInfo(id: 'p1', name: 'P1', role: PlayerRole.host, color: 0xFFD32F2F);
const _p2 = PlayerInfo(id: 'p2', name: 'P2', role: PlayerRole.client, color: 0xFF1976D2);
const _p3 = PlayerInfo(id: 'p3', name: 'P3', role: PlayerRole.client, color: 0xFF388E3C);
const _p4 = PlayerInfo(id: 'p4', name: 'P4', role: PlayerRole.client, color: 0xFF7B1FA2);

void main() {
  group('computeHandRowLayout -- 4 players', () {
    final players = [_p1, _p2, _p3, _p4];

    test('near-group viewers (seats 0-1) both see the identical arrangement', () {
      for (final viewer in [_p1, _p2]) {
        final layout = computeHandRowLayout(players, viewer.id);
        expect(layout.bottomRow.map((p) => p.id), ['p1', 'p2']);
        expect(layout.topRow.map((p) => p.id), ['p3', 'p4']);
      }
    });

    test('far-group viewers (seats 2-3) both see the identical 180-rotated arrangement', () {
      for (final viewer in [_p3, _p4]) {
        final layout = computeHandRowLayout(players, viewer.id);
        expect(layout.bottomRow.map((p) => p.id), ['p4', 'p3']);
        expect(layout.topRow.map((p) => p.id), ['p2', 'p1']);
      }
    });

    test('local player always appears in bottomRow, never in topRow', () {
      for (final viewer in players) {
        final layout = computeHandRowLayout(players, viewer.id);
        expect(layout.bottomRow.any((p) => p.id == viewer.id), isTrue);
        expect(layout.topRow.any((p) => p.id == viewer.id), isFalse);
      }
    });
  });

  group('computeHandRowLayout -- 3 players', () {
    final players = [_p1, _p2, _p3];

    test('seat 0 (near) is alone at the bottom, full width, with the other two split on top', () {
      final fromSeat0 = computeHandRowLayout(players, 'p1');
      expect(fromSeat0.bottomRow.map((p) => p.id), ['p1']);
      expect(fromSeat0.topRow.map((p) => p.id), ['p2', 'p3']);
    });

    test('both far-seated players (seats 1-2) see the identical arrangement -- sharing the '
        'bottom together, not each seeing themselves solo', () {
      for (final viewer in [_p2, _p3]) {
        final layout = computeHandRowLayout(players, viewer.id);
        expect(layout.bottomRow.map((p) => p.id), ['p3', 'p2']);
        expect(layout.topRow.map((p) => p.id), ['p1']);
      }
    });

    test('local player always appears in bottomRow, never in topRow', () {
      for (final viewer in players) {
        final layout = computeHandRowLayout(players, viewer.id);
        expect(layout.bottomRow.any((p) => p.id == viewer.id), isTrue);
        expect(layout.topRow.any((p) => p.id == viewer.id), isFalse);
      }
    });
  });

  group('computeHandRowLayout -- 2 players', () {
    final players = [_p1, _p2];

    test('each player sees themselves at the bottom, the other at the top', () {
      final fromP1 = computeHandRowLayout(players, 'p1');
      expect(fromP1.bottomRow.single.id, 'p1');
      expect(fromP1.topRow.single.id, 'p2');

      final fromP2 = computeHandRowLayout(players, 'p2');
      expect(fromP2.bottomRow.single.id, 'p2');
      expect(fromP2.topRow.single.id, 'p1');
    });
  });
}
