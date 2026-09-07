import 'dart:io';

import 'package:flutter/material.dart';

import 'card_face_widget.dart' show cardWidth, cardHeight;

/// The back of a card — used for face-down cards and for any card sitting
/// in another player's private hand zone. If [imagePath] is set, renders the
/// game's real card-back art (falling back to the code-drawn pattern below
/// if the file can't be loaded); otherwise the pattern is used directly.
class CardBackWidget extends StatelessWidget {
  const CardBackWidget({super.key, this.imagePath});

  final String? imagePath;

  Widget _codeDrawnBack() {
    return Container(
      width: cardWidth,
      height: cardHeight,
      decoration: BoxDecoration(
        color: const Color(0xFF1565C0),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black26),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(1, 1))],
      ),
      padding: const EdgeInsets.all(6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: Colors.white24, width: 2),
          borderRadius: BorderRadius.circular(3),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: CustomPaint(size: Size.infinite, painter: _CardBackPatternPainter()),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final path = imagePath;
    if (path == null) return _codeDrawnBack();
    return Container(
      width: cardWidth,
      height: cardHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(1, 1))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: Colors.black26)),
          child: Image.file(
            File(path),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _codeDrawnBack(),
          ),
        ),
      ),
    );
  }
}

class _CardBackPatternPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.12)
      ..strokeWidth = 1;
    const spacing = 8.0;
    // Diagonal cross-hatch covering the full card back.
    for (double x = -size.height; x < size.width; x += spacing) {
      canvas.drawLine(Offset(x, 0), Offset(x + size.height, size.height), linePaint);
      canvas.drawLine(Offset(x + size.height, 0), Offset(x, size.height), linePaint);
    }

    final emblemPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final center = size.center(Offset.zero);
    final r = size.shortestSide * 0.22;
    final diamond = Path()
      ..moveTo(center.dx, center.dy - r)
      ..lineTo(center.dx + r, center.dy)
      ..lineTo(center.dx, center.dy + r)
      ..lineTo(center.dx - r, center.dy)
      ..close();
    canvas.drawPath(diamond, emblemPaint);
  }

  @override
  bool shouldRepaint(covariant _CardBackPatternPainter oldDelegate) => false;
}
