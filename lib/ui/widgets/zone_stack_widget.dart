import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/card_definition.dart';
import 'card_back_widget.dart';
import 'card_face_widget.dart';
import 'pile_widget.dart' show SearchBadge, pileWidgetExtra;

/// The local player's own instance of a `ZoneDefinition` (owned or shared) --
/// a fixed zone next to the hand zone (unlike table piles, never positioned
/// by canonical [0,1] fractions). Shows the real face of its top card when
/// face-up (e.g. a discard pile), a back otherwise -- mirrors `PileWidget`'s
/// own face-up-top-card handling. The top card is a drag handle -- there is
/// no tap-to-draw; dragging it onto the hand zone or table is handled
/// entirely by [TableScreen]'s existing drag-drop plumbing (the same code
/// path any other card drag already uses), via [onDragEnd]. The shuffle
/// button remains a tap, unrelated to drawing -- hidden entirely when
/// [onShuffle] is null (a zone whose `ZoneDefinition.shuffleable` is false,
/// like a discard pile). Always tooltipped with [zoneName], the whole
/// reason a zone is worth naming in a game's JSON.
class ZoneStackWidget extends StatefulWidget {
  const ZoneStackWidget({
    super.key,
    required this.zoneName,
    required this.count,
    required this.topInstanceId,
    required this.topFaceUp,
    required this.topDefinition,
    required this.onDragEnd,
    required this.onShuffle,
    this.isBeingSearched = false,
    this.cardBackImagePath,
    this.borderColor,
  });

  final String zoneName;
  final int count;
  final String? topInstanceId;
  final bool topFaceUp;
  final CardDefinition? topDefinition;
  final void Function(Offset globalTopLeft)? onDragEnd;
  final VoidCallback? onShuffle;

  /// See `PileWidget.isBeingSearched`'s identical doc.
  final bool isBeingSearched;
  final String? cardBackImagePath;

  /// This zone's owner's chosen color -- painted as a border on the top
  /// card, same as any other owned card (see `TableScreen._ownerBorderColor`).
  final Color? borderColor;

  @override
  State<ZoneStackWidget> createState() => _ZoneStackWidgetState();
}

class _ZoneStackWidgetState extends State<ZoneStackWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shuffleController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  /// See `PileWidget`'s identical field -- keeps this Shuffle button out of
  /// focus traversal so a stray Space/Enter after a click can't re-trigger it.
  final FocusNode _shuffleFocusNode = FocusNode(
    canRequestFocus: false,
    skipTraversal: true,
  );

  void _handleShuffle() {
    widget.onShuffle?.call();
    _shuffleController.forward(from: 0);
  }

  @override
  void dispose() {
    _shuffleController.dispose();
    _shuffleFocusNode.dispose();
    super.dispose();
  }

  Widget _topFace() {
    final content = widget.topFaceUp && widget.topDefinition != null
        ? CardFaceWidget(definition: widget.topDefinition!)
        : CardBackWidget(imagePath: widget.cardBackImagePath);
    if (widget.borderColor == null) return content;
    return Container(
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: widget.borderColor!, width: 2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(message: widget.zoneName, child: _buildContent());
  }

  Widget _buildContent() {
    if (widget.count == 0 || widget.topInstanceId == null) {
      return SizedBox(
        width: cardWidth + pileWidgetExtra,
        height: cardHeight + pileWidgetExtra,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            Center(
              child: Container(
                width: cardWidth,
                height: cardHeight,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(color: Colors.white24, width: 1.5),
                ),
              ),
            ),
            if (widget.isBeingSearched)
              const Positioned(top: -12, child: SearchBadge()),
          ],
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
              feedback: Material(
                type: MaterialType.transparency,
                child: _topFace(),
              ),
              childWhenDragging: Opacity(opacity: 0.3, child: _topFace()),
              onDragEnd: (details) => widget.onDragEnd?.call(details.offset),
              child: AnimatedBuilder(
                animation: _shuffleController,
                builder: (context, child) {
                  final t = _shuffleController.value;
                  // A few oscillations that decay to zero by the end.
                  final angle = math.sin(t * math.pi * 6) * 0.15 * (1 - t);
                  return Transform.rotate(angle: angle, child: child);
                },
                child: _topFace(),
              ),
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: CircleAvatar(
              radius: 12,
              backgroundColor: Colors.black87,
              child: Text(
                '${widget.count}',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
          if (widget.onShuffle != null)
            Positioned(
              bottom: -8,
              child: Material(
                color: Colors.black54,
                shape: const CircleBorder(),
                child: IconButton(
                  icon: const Icon(
                    Icons.shuffle,
                    color: Colors.white,
                    size: 16,
                  ),
                  tooltip: 'Shuffle',
                  onPressed: _handleShuffle,
                  focusNode: _shuffleFocusNode,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints.tightFor(
                    width: 28,
                    height: 28,
                  ),
                ),
              ),
            ),
          if (widget.isBeingSearched)
            const Positioned(top: -12, child: SearchBadge()),
        ],
      ),
    );
  }
}
