import 'package:flutter/material.dart';

import '../../models/card_definition.dart';

const double cardWidth = 70;
const double cardHeight = 100;

Color _parseHexColor(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  return Color(int.parse('FF$cleaned', radix: 16));
}

/// The front face of a card, code-drawn from its [CardDefinition] — no image
/// assets required.
class CardFaceWidget extends StatelessWidget {
  const CardFaceWidget({super.key, required this.definition});

  final CardDefinition definition;

  @override
  Widget build(BuildContext context) {
    final color = _parseHexColor(definition.colorHex);
    return Container(
      width: cardWidth,
      height: cardHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black26),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(1, 1))],
      ),
      padding: const EdgeInsets.all(4),
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            child: Text(
              definition.label,
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
            ),
          ),
          Center(
            child: Text(
              definition.label,
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 22),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Transform.rotate(
              angle: 3.14159,
              child: Text(
                definition.label,
                style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
