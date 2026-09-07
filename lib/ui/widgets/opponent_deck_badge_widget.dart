import 'package:flutter/material.dart';

import 'card_back_widget.dart';
import 'card_face_widget.dart' show cardWidth, cardHeight;

/// The opponent's personal deck, shown read-only as a face-down back with a
/// count badge -- no draw/shuffle affordance, matching how the opponent's
/// hand is already shown as a plain count rather than interactive cards.
class OpponentDeckBadgeWidget extends StatelessWidget {
  const OpponentDeckBadgeWidget({super.key, required this.count, this.cardBackImagePath});

  final int count;
  final String? cardBackImagePath;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: cardWidth + 24,
      height: cardHeight + 24,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          CardBackWidget(imagePath: cardBackImagePath),
          Positioned(
            top: 0,
            right: 0,
            child: CircleAvatar(
              radius: 12,
              backgroundColor: Colors.black87,
              child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 11)),
            ),
          ),
        ],
      ),
    );
  }
}
