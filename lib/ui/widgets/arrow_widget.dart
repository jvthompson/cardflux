import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Fallback color for an arrow whose creator can't be resolved to a player
/// (shouldn't normally happen -- `HostGameEngine` always stamps a real
/// `creatorId` -- kept only as a safe default). Every real arrow is instead
/// colored after the player who drew it (see `TableScreen`'s
/// `arrowColorFor`).
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

/// A line + triangular arrowhead from [from] to [to] (both must already be in
/// the table Stack's own local *screen* pixel space -- i.e. run through
/// `TableScreen._toScreenPixel`, not the raw, offset-free world-pixel space
/// `_globalToTableLocal` returns), drawn by holding TAB and dragging on the
/// table, colored after whichever player drew it (see `arrowColorFor`).
///
/// Purely decorative and never interactive -- an arrow auto-expires on its
/// own (see `GameSession.createArrow`'s doc comment) rather than being
/// dismissed by a click, so this never claims any pointer event; it's always
/// wrapped in an [IgnorePointer] and never blocks a click/drag meant for
/// whatever's underneath it.
///
/// Always returns exactly one [Positioned] as its build result, with the
/// [IgnorePointer] nested *inside* it -- `Positioned` only applies when it's
/// a direct child of a `Stack`, so every caller must use this widget
/// directly as a `Stack` child with nothing wrapped around the *outside* of
/// it, or the position silently stops applying and -- because it also
/// introduces a non-`Positioned` child into a `Stack` that otherwise has
/// none -- corrupts that `Stack`'s own size calculation for every other
/// child in it too.
class ArrowWidget extends StatelessWidget {
  const ArrowWidget({
    super.key,
    required this.from,
    required this.to,
    this.color = arrowColor,
  });

  final Offset from;
  final Offset to;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final left = math.min(from.dx, to.dx) - arrowHeadLength;
    final top = math.min(from.dy, to.dy) - arrowHeadLength;
    final size = Size(
      (from.dx - to.dx).abs() + arrowHeadLength * 2,
      (from.dy - to.dy).abs() + arrowHeadLength * 2,
    );
    return Positioned(
      left: left,
      top: top,
      width: size.width,
      height: size.height,
      child: IgnorePointer(
        child: CustomPaint(
          painter: _ArrowPainter(
            from: from - Offset(left, top),
            to: to - Offset(left, top),
            color: color,
          ),
        ),
      ),
    );
  }
}

class _ArrowPainter extends CustomPainter {
  _ArrowPainter({required this.from, required this.to, required this.color});

  final Offset from;
  final Offset to;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if ((to - from).distance < arrowMinLength) return;
    final linePaint = Paint()
      ..color = color
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
      ..color = color
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
      oldDelegate.from != from ||
      oldDelegate.to != to ||
      oldDelegate.color != color;
}
