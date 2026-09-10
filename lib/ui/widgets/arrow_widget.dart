import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Fixed visual style for every arrow -- a single color/weight for v1, no
/// per-arrow customization (no right-click menu, unlike Counter/Token).
const Color arrowColor = Colors.redAccent;
const double arrowStrokeWidth = 3;
const double arrowHeadLength = 14;
const double arrowHeadAngle = math.pi / 7; // ~25.7 degrees each side

/// Below this length, [_ArrowPainter] paints nothing at all rather than a
/// degenerate line -- a zero/near-zero-length stroke with a round cap (plus
/// an arrowhead angle computed from `atan2(0, 0)`) is exactly what the live
/// preview draws for its very first frame, the instant a drag starts before
/// the cursor has moved. That degenerate paint call is the confirmed trigger
/// for a rendering glitch that blanked the whole table for the duration of
/// the drag (see TableScreen's TAB-drag preview) -- skipping it here is a
/// couple of imperceptible pixels of dead zone, not a visible behavior
/// change for a real drag.
const double arrowMinLength = 2;

/// A line + triangular arrowhead from [from] to [to] (both already in the
/// table Stack's own local pixel space -- see `TableScreen._toScreenPixel`/
/// `_globalToTableLocal`), drawn by holding TAB and dragging on the table.
/// When [onDoubleTap] is non-null, a bounding-box region around the line is
/// double-tappable to dismiss it -- null for the live drag preview (see
/// `TableScreen`) and for a committed arrow the local player didn't create,
/// since only its creator may dismiss it.
///
/// Hit-testing uses the line's straight bounding rectangle rather than
/// precise distance-to-segment math -- adequate for a short annotation
/// arrow, not meant to be pixel-perfect.
///
/// Always returns exactly one [Positioned] as its build result, with
/// everything else (including [ignorePointer]'s `IgnorePointer`) nested
/// *inside* it -- `Positioned` only applies when it's a direct child of a
/// `Stack`, so every caller must use this widget directly as a `Stack` child
/// with nothing wrapped around the *outside* of it (no `IgnorePointer`, no
/// other render-object widget), or the position silently stops applying and
/// -- because it also introduces a non-`Positioned` child into a `Stack`
/// that otherwise has none -- corrupts that `Stack`'s own size calculation
/// for every other child in it too. [ignorePointer] exists precisely so
/// callers never need to wrap this widget from the outside for that.
class ArrowWidget extends StatelessWidget {
  const ArrowWidget({
    super.key,
    required this.from,
    required this.to,
    this.onDoubleTap,
    this.ignorePointer = false,
  });

  final Offset from;
  final Offset to;
  final VoidCallback? onDoubleTap;

  /// True for the local live-drag preview (see `TableScreen`), so it never
  /// intercepts the in-progress pan gesture or a committed arrow's hit
  /// region underneath it.
  final bool ignorePointer;

  @override
  Widget build(BuildContext context) {
    final left = math.min(from.dx, to.dx) - arrowHeadLength;
    final top = math.min(from.dy, to.dy) - arrowHeadLength;
    final size = Size(
      (from.dx - to.dx).abs() + arrowHeadLength * 2,
      (from.dy - to.dy).abs() + arrowHeadLength * 2,
    );
    Widget content = GestureDetector(
      // Translucent, not opaque -- this widget's hit region is its whole
      // straight bounding box (see the class doc), which commonly overlaps
      // cards nowhere near the actual line. Translucent still lets a
      // double-tap on this box dismiss the arrow, but lets a single
      // click/drag pass through to whatever's underneath instead of being
      // swallowed here.
      behavior: HitTestBehavior.translucent,
      onDoubleTap: onDoubleTap,
      child: CustomPaint(
        painter: _ArrowPainter(
          from: from - Offset(left, top),
          to: to - Offset(left, top),
        ),
      ),
    );
    if (ignorePointer) content = IgnorePointer(child: content);
    return Positioned(
      left: left,
      top: top,
      width: size.width,
      height: size.height,
      child: content,
    );
  }
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter({required this.from, required this.to});

  final Offset from;
  final Offset to;

  @override
  void paint(Canvas canvas, Size size) {
    if ((to - from).distance < arrowMinLength) return;
    final linePaint = Paint()
      ..color = arrowColor
      ..strokeWidth = arrowStrokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(from, to, linePaint);

    final angle = math.atan2(to.dy - from.dy, to.dx - from.dx);
    final p1 =
        to -
        Offset(
              math.cos(angle - arrowHeadAngle),
              math.sin(angle - arrowHeadAngle),
            ) *
            arrowHeadLength;
    final p2 =
        to -
        Offset(
              math.cos(angle + arrowHeadAngle),
              math.sin(angle + arrowHeadAngle),
            ) *
            arrowHeadLength;
    final headPaint = Paint()
      ..color = arrowColor
      ..style = PaintingStyle.fill;
    canvas.drawPath(
      Path()
        ..moveTo(to.dx, to.dy)
        ..lineTo(p1.dx, p1.dy)
        ..lineTo(p2.dx, p2.dy)
        ..close(),
      headPaint,
    );
  }

  @override
  bool shouldRepaint(_ArrowPainter oldDelegate) =>
      oldDelegate.from != from || oldDelegate.to != to;
}
