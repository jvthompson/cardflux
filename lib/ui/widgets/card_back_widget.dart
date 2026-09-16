import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/image_path_resolver.dart';
import '../../models/card_back_definition.dart';
import '../../models/card_definition.dart';
import 'card_face_widget.dart' show cardWidth, cardHeight;

/// The back of a card — used for face-down cards and for any card sitting
/// in another player's private hand zone. Resolves which art to show itself,
/// via [resolveCardBackImagePath], from [card]'s own card-back choice against
/// [cardBacks] (see `GameDefinition.cardBacks`) -- [card] is null wherever
/// the card's identity is unknown to this viewer (a privacy-filtered
/// opponent hand/pile), which always renders this game's default back.
/// Renders the resolved real art if there is any (falling back to the
/// code-drawn pattern below if the file can't be loaded), the code-drawn
/// pattern directly if none is configured, or a red error placeholder if
/// [card] specifically selected "Unique" and no matching art exists on disk.
class CardBackWidget extends StatelessWidget {
  const CardBackWidget({super.key, this.cardBacks = const [], this.card});

  final List<CardBackDefinition> cardBacks;
  final CardDefinition? card;

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

  /// Shown instead of [_codeDrawnBack] specifically when [card] selected
  /// "Unique" and no `_BACK` image was found -- red, so it reads as an error
  /// (a missing asset to go fix) rather than "no back art configured."
  Widget _missingBack() {
    return Container(
      width: cardWidth,
      height: cardHeight,
      decoration: BoxDecoration(
        color: const Color(0xFFB71C1C),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black26),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(1, 1))],
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.warning_amber_rounded, color: Colors.white, size: 32),
    );
  }

  @override
  Widget build(BuildContext context) {
    final resolved = resolveCardBackImagePath(cardBacks: cardBacks, card: card);
    if (resolved.missing) return _missingBack();
    final path = resolved.path;
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
