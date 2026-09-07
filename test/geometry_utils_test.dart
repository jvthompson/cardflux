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

  group('canonicalToLocalPixel', () {
    test('passes through unchanged when unmirrored', () {
      final (px, py) = canonicalToLocalPixel(fx: 0.25, fy: 0.75, tableWidth: 800, tableHeight: 400, isMirrored: false);
      expect(px, 200);
      expect(py, 300);
    });

    test('flips both axes when mirrored', () {
      final (px, py) = canonicalToLocalPixel(fx: 0.25, fy: 0.75, tableWidth: 800, tableHeight: 400, isMirrored: true);
      expect(px, 600); // (1 - 0.25) * 800
      expect(py, 100); // (1 - 0.75) * 400
    });

    test('the table center is mirror-invariant', () {
      final unmirrored = canonicalToLocalPixel(fx: 0.5, fy: 0.5, tableWidth: 800, tableHeight: 400, isMirrored: false);
      final mirrored = canonicalToLocalPixel(fx: 0.5, fy: 0.5, tableWidth: 800, tableHeight: 400, isMirrored: true);
      expect(mirrored, unmirrored);
    });
  });

  group('localPixelToCanonical', () {
    test('passes through unchanged when unmirrored', () {
      final (fx, fy) = localPixelToCanonical(pixelX: 200, pixelY: 300, tableWidth: 800, tableHeight: 400, isMirrored: false);
      expect(fx, 0.25);
      expect(fy, 0.75);
    });

    test('flips both axes when mirrored', () {
      final (fx, fy) = localPixelToCanonical(pixelX: 200, pixelY: 300, tableWidth: 800, tableHeight: 400, isMirrored: true);
      expect(fx, 0.75); // 1 - 0.25
      expect(fy, 0.25); // 1 - 0.75
    });

    test('clamps out-of-range pixel input to [0,1] before mirroring', () {
      final below = localPixelToCanonical(pixelX: -50, pixelY: 0, tableWidth: 800, tableHeight: 400, isMirrored: false);
      expect(below.$1, 0);
      final above = localPixelToCanonical(pixelX: 900, pixelY: 0, tableWidth: 800, tableHeight: 400, isMirrored: false);
      expect(above.$1, 1);
    });
  });

  group('canonicalToLocalPixel / localPixelToCanonical round-trip', () {
    test('recovers the original fraction when unmirrored', () {
      final (px, py) = canonicalToLocalPixel(fx: 0.3, fy: 0.6, tableWidth: 800, tableHeight: 400, isMirrored: false);
      final (fx, fy) = localPixelToCanonical(pixelX: px, pixelY: py, tableWidth: 800, tableHeight: 400, isMirrored: false);
      expect(fx, closeTo(0.3, 1e-9));
      expect(fy, closeTo(0.6, 1e-9));
    });

    test('recovers the original fraction when mirrored', () {
      final (px, py) = canonicalToLocalPixel(fx: 0.3, fy: 0.6, tableWidth: 800, tableHeight: 400, isMirrored: true);
      final (fx, fy) = localPixelToCanonical(pixelX: px, pixelY: py, tableWidth: 800, tableHeight: 400, isMirrored: true);
      expect(fx, closeTo(0.3, 1e-9));
      expect(fy, closeTo(0.6, 1e-9));
    });
  });
}
