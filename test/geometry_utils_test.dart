import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_deck/game/geometry_utils.dart';

void main() {
  group('clampCardCenterY', () {
    test('leaves an in-bounds center unchanged', () {
      final y = clampCardCenterY(proposedCenterY: 200, tableHeight: 400, cardHeight: 100, margin: 10);
      expect(y, 200);
    });

    test('clamps a center that overlaps the opponent hand zone above', () {
      final y = clampCardCenterY(proposedCenterY: -20, tableHeight: 400, cardHeight: 100, margin: 10);
      expect(y, 60); // margin + cardHeight / 2
    });

    test('clamps a center that overlaps the local hand zone below', () {
      final y = clampCardCenterY(proposedCenterY: 450, tableHeight: 400, cardHeight: 100, margin: 10);
      expect(y, 340); // tableHeight - margin - cardHeight / 2
    });

    test('falls back to vertical center when tableHeight is too small to fit both margins', () {
      final y = clampCardCenterY(proposedCenterY: 999, tableHeight: 100, cardHeight: 100, margin: 10);
      expect(y, 50); // tableHeight / 2; lowerBound (60) > upperBound (40)
    });
  });
}
