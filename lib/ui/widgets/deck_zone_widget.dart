import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'card_back_widget.dart';
import 'card_face_widget.dart' show cardWidth, cardHeight;
import 'pile_widget.dart' show pileWidgetExtra;

/// The local player's personal loaded deck -- a fixed zone next to the hand
/// zone (unlike table piles, never positioned by canonical [0,1] fractions).
/// Always shows a card back (a deck's top card identity is never revealed by
/// this widget, regardless of the underlying [CardInstance.faceUp]). The top
/// card is a drag handle -- there is no tap-to-draw; dragging it onto the
/// hand zone or table is handled entirely by [TableScreen]'s existing
/// drag-drop plumbing (the same code path any other card drag already uses),
/// via [onDragEnd]. The shuffle button remains a tap, unrelated to drawing.
class DeckZoneWidget extends StatefulWidget {
  const DeckZoneWidget({
    super.key,
    required this.count,
    required this.topInstanceId,
    required this.onDragEnd,
    required this.onShuffle,
    this.cardBackImagePath,
  });

  final int count;
  final String? topInstanceId;
  final void Function(Offset globalTopLeft)? onDragEnd;
  final VoidCallback? onShuffle;
  final String? cardBackImagePath;

  @override
  State<DeckZoneWidget> createState() => _DeckZoneWidgetState();
}

class _DeckZoneWidgetState extends State<DeckZoneWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _shuffleController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  void _handleShuffle() {
    widget.onShuffle?.call();
    _shuffleController.forward(from: 0);
  }

  @override
  void dispose() {
    _shuffleController.dispose();
    super.dispose();
  }

  Widget _cardBack() => CardBackWidget(imagePath: widget.cardBackImagePath);

  @override
  Widget build(BuildContext context) {
    if (widget.count == 0 || widget.topInstanceId == null) {
      return SizedBox(
        width: cardWidth + pileWidgetExtra,
        height: cardHeight + pileWidgetExtra,
        child: Center(
          child: Container(
            width: cardWidth,
            height: cardHeight,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white24, width: 1.5),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: cardWidth + pileWidgetExtra,
      height: cardHeight + pileWidgetExtra,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Wrapped in a no-op tap GestureDetector so a plain click (zero
          // pointer movement) is claimed by the tap recognizer instead of
          // being resolved as a zero-distance drag-and-drop by Draggable's
          // own recognizer (which, left uncontested, treats *any* down-up
          // as a valid drag and fires onDragEnd) -- mirrors how
          // DraggableCard avoids the same footgun via its onTapFlip.
          GestureDetector(
            onTap: () {},
            child: Draggable<String>(
              data: widget.topInstanceId,
              feedback: Material(type: MaterialType.transparency, child: _cardBack()),
              childWhenDragging: Opacity(opacity: 0.3, child: _cardBack()),
              onDragEnd: (details) => widget.onDragEnd?.call(details.offset),
              child: AnimatedBuilder(
                animation: _shuffleController,
                builder: (context, child) {
                  final t = _shuffleController.value;
                  // A few oscillations that decay to zero by the end.
                  final angle = math.sin(t * math.pi * 6) * 0.15 * (1 - t);
                  return Transform.rotate(angle: angle, child: child);
                },
                child: _cardBack(),
              ),
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
