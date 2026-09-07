import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'card_back_widget.dart';
import 'card_face_widget.dart';

/// Extra room (beyond the card's own [cardWidth]/[cardHeight]) [PileWidget]
/// reserves on each axis so its count badge and shuffle button can overflow
/// slightly past the card's edges. Callers positioning a [PileWidget] by its
/// center (see table_screen.dart) must offset by half of `cardWidth +
/// pileWidgetExtra`/`cardHeight + pileWidgetExtra`, not half of the bare
/// card dimensions, or the whole widget renders off-center.
const double pileWidgetExtra = 24;

/// A stack of 2+ cards rendered as a single back-face with a count badge.
/// Tap draws the top card into the local hand; the shuffle button
/// randomizes stacking order and plays a brief decaying wiggle (M6) so the
/// tap reads as having done something, since a face-down pile otherwise
/// looks identical before and after a shuffle.
class PileWidget extends StatefulWidget {
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
  State<PileWidget> createState() => _PileWidgetState();
}

class _PileWidgetState extends State<PileWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _shuffleController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  void _handleShuffle() {
    widget.onShuffle();
    _shuffleController.forward(from: 0);
  }

  @override
  void dispose() {
    _shuffleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: cardWidth + pileWidgetExtra,
      height: cardHeight + pileWidgetExtra,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          GestureDetector(
            onTap: widget.onDraw,
            child: AnimatedBuilder(
              animation: _shuffleController,
              builder: (context, child) {
                final t = _shuffleController.value;
                // A few oscillations that decay to zero by the end.
                final angle = math.sin(t * math.pi * 6) * 0.15 * (1 - t);
                return Transform.rotate(angle: angle, child: child);
              },
              child: const CardBackWidget(),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: CircleAvatar(
              radius: 12,
              backgroundColor: Colors.black87,
              child: Text('${widget.count}', style: const TextStyle(color: Colors.white, fontSize: 11)),
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
                onPressed: _handleShuffle,
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
