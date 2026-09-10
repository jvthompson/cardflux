import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_deck/game/geometry_utils.dart';

void main() {
  group('worldCenteringOffset', () {
    test('viewport bigger than the world on both axes centers it with positive offset', () {
      final offset = worldCenteringOffset(
        world: const Size(1600, 900),
        viewport: const Size(2000, 1200),
      );
      expect(offset.dx, closeTo(200, 1e-9)); // (2000 - 1600) / 2
      expect(offset.dy, closeTo(150, 1e-9)); // (1200 - 900) / 2
    });

    test('viewport smaller than the world on both axes gives a negative (overflowing) offset', () {
      final offset = worldCenteringOffset(
        world: const Size(1600, 900),
        viewport: const Size(800, 500),
      );
      expect(offset.dx, closeTo(-400, 1e-9)); // (800 - 1600) / 2
      expect(offset.dy, closeTo(-200, 1e-9)); // (500 - 900) / 2
    });

    test('viewport matching the world exactly has zero offset', () {
      final offset = worldCenteringOffset(
        world: const Size(1600, 900),
        viewport: const Size(1600, 900),
      );
      expect(offset, Offset.zero);
    });

    test(
      'bigger on one axis and smaller on the other mixes signs independently',
      () {
        final offset = worldCenteringOffset(
          world: const Size(1600, 900),
          viewport: const Size(2000, 500),
        );
        expect(
          offset.dx,
          closeTo(200, 1e-9),
        ); // bigger viewport width -> positive
        expect(
          offset.dy,
          closeTo(-200, 1e-9),
        ); // smaller viewport height -> negative
      },
    );
  });

  group('clampCardCenterY', () {
    test('leaves an in-bounds center unchanged', () {
      final y = clampCardCenterY(
        proposedCenterY: 200,
        tableHeight: 400,
        cardHeight: 100,
        margin: 10,
      );
      expect(y, 200);
    });

    // tablePanMarginFraction (0.5) widens the old hand-zone-only bounds by
    // half the table height on each side, so a camera-pan-revealed position
    // that would have clamped to the hand-zone edge before now passes
    // through unchanged -- it's only clipped from view (by the ClipRect
    // around the pannable Stack), not forced back into the old band.
    test('a center within the panned margin above the table is no longer clamped to the hand-zone edge', () {
      final y = clampCardCenterY(
        proposedCenterY: -20,
        tableHeight: 400,
        cardHeight: 100,
        margin: 10,
      );
      expect(y, -20);
    });

    test('a center within the panned margin below the table is no longer clamped to the hand-zone edge', () {
      final y = clampCardCenterY(
        proposedCenterY: 450,
        tableHeight: 400,
        cardHeight: 100,
        margin: 10,
      );
      expect(y, 450);
    });

    test('still clamps a center beyond even the widened margin', () {
      // tableMargin = 400 * 0.5 = 200; lowerBound = 10 + 50 - 200 = -140.
      final y = clampCardCenterY(
        proposedCenterY: -500,
        tableHeight: 400,
        cardHeight: 100,
        margin: 10,
      );
      expect(y, -140);
    });

    test('falls back to vertical center when tableHeight is too small to fit both margins', () {
      final y = clampCardCenterY(
        proposedCenterY: 999,
        tableHeight: 10,
        cardHeight: 100,
        margin: 10,
      );
      expect(y, 5); // tableHeight / 2; lowerBound > upperBound even with the widened margin
    });
  });

  group('canonicalToLocalPixel', () {
    test('passes through unchanged when unmirrored', () {
      final (px, py) = canonicalToLocalPixel(
        fx: 0.25,
        fy: 0.75,
        tableWidth: 800,
        tableHeight: 400,
        isMirrored: false,
      );
      expect(px, 200);
      expect(py, 300);
    });

    test('flips both axes when mirrored', () {
      final (px, py) = canonicalToLocalPixel(
        fx: 0.25,
        fy: 0.75,
        tableWidth: 800,
        tableHeight: 400,
        isMirrored: true,
      );
      expect(px, 600); // (1 - 0.25) * 800
      expect(py, 100); // (1 - 0.75) * 400
    });

    test('the table center is mirror-invariant', () {
      final unmirrored = canonicalToLocalPixel(
        fx: 0.5,
        fy: 0.5,
        tableWidth: 800,
        tableHeight: 400,
        isMirrored: false,
      );
      final mirrored = canonicalToLocalPixel(
        fx: 0.5,
        fy: 0.5,
        tableWidth: 800,
        tableHeight: 400,
        isMirrored: true,
      );
      expect(mirrored, unmirrored);
    });
  });

  group('localPixelToCanonical', () {
    test('passes through unchanged when unmirrored', () {
      final (fx, fy) = localPixelToCanonical(
        pixelX: 200,
        pixelY: 300,
        tableWidth: 800,
        tableHeight: 400,
        isMirrored: false,
      );
      expect(fx, 0.25);
      expect(fy, 0.75);
    });

    test('flips both axes when mirrored', () {
      final (fx, fy) = localPixelToCanonical(
        pixelX: 200,
        pixelY: 300,
        tableWidth: 800,
        tableHeight: 400,
        isMirrored: true,
      );
      expect(fx, 0.75); // 1 - 0.25
      expect(fy, 0.25); // 1 - 0.75
    });

    test('preserves pixel input within the tablePanMarginFraction margin instead of clamping to [0,1]', () {
      // tablePanMarginFraction is 0.5, so up to half a table-width beyond
      // each edge is preserved -- this is what lets a card be placed into
      // the area a panned camera reveals, not just wherever a camera-free
      // [0,1] table already showed.
      final left = localPixelToCanonical(
        pixelX: -200,
        pixelY: 0,
        tableWidth: 800,
        tableHeight: 400,
        isMirrored: false,
      );
      expect(left.$1, closeTo(-0.25, 1e-9));
      final right = localPixelToCanonical(
        pixelX: 900,
        pixelY: 0,
        tableWidth: 800,
        tableHeight: 400,
        isMirrored: false,
      );
      expect(right.$1, closeTo(1.125, 1e-9));
    });

    test(
      'still clamps pixel input beyond the tablePanMarginFraction margin',
      () {
        final farLeft = localPixelToCanonical(
          pixelX: -1000,
          pixelY: 0,
          tableWidth: 800,
          tableHeight: 400,
          isMirrored: false,
        );
        expect(farLeft.$1, -0.5); // -tablePanMarginFraction
        final farRight = localPixelToCanonical(
          pixelX: 2000,
          pixelY: 0,
          tableWidth: 800,
          tableHeight: 400,
          isMirrored: false,
        );
        expect(farRight.$1, 1.5); // 1 + tablePanMarginFraction
      },
    );
  });

  group('canonicalToLocalPixel / localPixelToCanonical round-trip', () {
    test('recovers the original fraction when unmirrored', () {
      final (px, py) = canonicalToLocalPixel(
        fx: 0.3,
        fy: 0.6,
        tableWidth: 800,
        tableHeight: 400,
        isMirrored: false,
      );
      final (fx, fy) = localPixelToCanonical(
        pixelX: px,
        pixelY: py,
        tableWidth: 800,
        tableHeight: 400,
        isMirrored: false,
      );
      expect(fx, closeTo(0.3, 1e-9));
      expect(fy, closeTo(0.6, 1e-9));
    });

    test('recovers the original fraction when mirrored', () {
      final (px, py) = canonicalToLocalPixel(
        fx: 0.3,
        fy: 0.6,
        tableWidth: 800,
        tableHeight: 400,
        isMirrored: true,
      );
      final (fx, fy) = localPixelToCanonical(
        pixelX: px,
        pixelY: py,
        tableWidth: 800,
        tableHeight: 400,
        isMirrored: true,
      );
      expect(fx, closeTo(0.3, 1e-9));
      expect(fy, closeTo(0.6, 1e-9));
    });
  });
}
