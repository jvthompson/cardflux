import 'package:flutter/material.dart';

import 'card_back_widget.dart';
import 'card_face_widget.dart';

/// A stack of 2+ cards rendered as a single back-face with a count badge.
/// Tap draws the top card into the local hand; the shuffle button
/// randomizes stacking order.
class PileWidget extends StatelessWidget {
  const PileWidget({
    super.key,
    required this.count,
    required this.onDraw,
    required this.onShuffle,
  });

  final int count;
  final VoidCallback onDraw;
  final VoidCallback onShuffle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: cardWidth + 24,
      height: cardHeight + 24,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          GestureDetector(
            onTap: onDraw,
            child: const CardBackWidget(),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: CircleAvatar(
              radius: 12,
              backgroundColor: Colors.black87,
              child: Text('$count', style: const TextStyle(color: Colors.white, fontSize: 11)),
            ),
          ),
          Positioned(
            bottom: -8,
            child: Material(
              color: Colors.black54,
              shape: const CircleBorder(),
              child: IconButton(
                icon: const Icon(Icons.shuffle, color: Colors.white, size: 16),
                tooltip: 'Shuffle',
                onPressed: onShuffle,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints.tightFor(width: 28, height: 28),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
