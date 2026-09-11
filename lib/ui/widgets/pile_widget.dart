import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/card_definition.dart';
import 'card_back_widget.dart';
import 'card_face_widget.dart';
import 'draggable_card.dart' show rotationAnimationDuration;

/// Extra room (beyond the card's own [cardWidth]/[cardHeight]) [PileWidget]
/// reserves on each axis so its count badge and shuffle button can overflow
/// slightly past the card's edges. Callers positioning a [PileWidget] by its
/// center (see table_screen.dart) must offset by half of `cardWidth +
/// pileWidgetExtra`/`cardHeight + pileWidgetExtra`, not half of the bare
/// card dimensions, or the whole widget renders off-center.
const double pileWidgetExtra = 24;

/// A stack of 2+ cards rendered with a count badge, showing either the real
/// face of the top card (if it's face-up -- e.g. cards played face-up and
/// stacked into a discard-like pile) or a back (face-down, same as
/// [topFaceUp] being false, or [topDefinition] missing -- an opponent's
/// hidden card, mirroring [DraggableCard]'s own fallback). Tap draws the top
/// card into the local hand -- the same shortcut a deck zone used to offer
/// before dragging replaced it there (see `ZoneStackWidget`); a table pile
/// keeps both, since tap-to-hand is still the common case while dragging
/// lets the top card be placed anywhere (the table, or back onto another
/// deck to return it) via [onDragEnd], the same drop-handling every other
/// draggable card already goes through. The shuffle button (hidden entirely
/// when [onShuffle] is null -- e.g. a zone whose `ZoneDefinition.shuffleable`
/// is false, like a discard pile) randomizes stacking order and flips every
/// card face-down, and plays a brief decaying wiggle (M6) so the tap reads
/// as having done something even when the pile was already showing a back.
class PileWidget extends StatefulWidget {
  const PileWidget({
    super.key,
    required this.count,
    required this.topInstanceId,
    required this.topFaceUp,
    required this.topDefinition,
    required this.onDraw,
    required this.onDragEnd,
    required this.onShuffle,
    this.isMirrored = false,
    this.interactable = true,
    this.isBeingSearched = false,
    this.applyOrientation = false,
    this.topRotationTurns = 0,
    this.topBorderColor,
    this.onHover,
    this.cardBackImagePath,
    this.feedbackOverride,
    this.onDragStarted,
  });

  final int count;
  final String topInstanceId;
  final bool topFaceUp;
  final CardDefinition? topDefinition;
  final VoidCallback onDraw;
  final void Function(Offset globalTopLeft) onDragEnd;
  final VoidCallback? onShuffle;
  final bool isMirrored;

  /// Gates draw-tap, drag, and shuffle entirely -- see `DraggableCard`'s own
  /// copy of this concept (used to block acting on a pile owned by the other
  /// player). Hover still fires either way.
  final bool interactable;

  /// Shows a large eyeball badge over this pile -- true whenever some
  /// player (any player, not just the local one -- see `TableScreen`'s
  /// `ActiveSearch` lookup) currently has a Search window open on it.
  /// Purely decorative: dismissing a search only ever happens from that
  /// window's own close control, never by tapping this badge.
  final bool isBeingSearched;

  /// Folds `topDefinition.orientation` into the rotation -- see
  /// `DraggableCard`'s own copy of this concept. Only ever true for a
  /// free-table pile.
  final bool applyOrientation;

  /// The top card's `CardInstance.rotationTurns` -- see `DraggableCard`'s own
  /// copy of this concept.
  final int topRotationTurns;

  /// Non-null when the top card is owned by the other player -- see
  /// `DraggableCard.opponentBorderColor`.
  final Color? topBorderColor;

  /// Notified when the mouse enters/exits this pile -- same purpose as
  /// `DraggableCard.onHover` (Space-hold preview, and D/Q/E targeting),
  /// reported against [topInstanceId] since that's the card actually shown.
  final ValueChanged<bool>? onHover;
  final String? cardBackImagePath;

  /// Replaces the default single-card drag feedback -- see
  /// `DraggableCard.feedbackOverride`'s own copy of this concept.
  final Widget? feedbackOverride;

  /// Notified when a drag on this pile's top card actually starts -- see
  /// `DraggableCard.onDragStarted`'s own copy of this concept.
  final VoidCallback? onDragStarted;

  @override
  State<PileWidget> createState() => _PileWidgetState();
}

class _PileWidgetState extends State<PileWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shuffleController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  /// Keeps the Shuffle button out of focus traversal entirely, so it can
  /// never be left holding keyboard focus after a click -- otherwise
  /// Flutter's default Space/Enter-activates-focused-button behavior would
  /// re-trigger a real shuffle from an unrelated later keypress (e.g. Space
  /// held to preview a card).
  final FocusNode _shuffleFocusNode = FocusNode(
    canRequestFocus: false,
    skipTraversal: true,
  );

  VoidCallback? get _effectiveOnShuffle =>
      widget.interactable ? widget.onShuffle : null;

  void _handleShuffle() {
    _effectiveOnShuffle?.call();
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
    final bordered = widget.topBorderColor == null
        ? content
        : Container(
            foregroundDecoration: BoxDecoration(
              border: Border.all(color: widget.topBorderColor!, width: 2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: content,
          );
    final orientation = widget.applyOrientation
        ? (widget.topDefinition?.orientation ?? CardOrientation.portrait)
        : CardOrientation.portrait;
    final turns =
        (widget.isMirrored ? 0.5 : 0.0) +
        orientationTurns(orientation) +
        widget.topRotationTurns / 4;
    return AnimatedRotation(
      turns: turns,
      duration: rotationAnimationDuration,
      curve: Curves.easeOut,
      child: bordered,
    );
  }

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => widget.onHover?.call(true),
      onExit: (_) => widget.onHover?.call(false),
      child: SizedBox(
        width: cardWidth + pileWidgetExtra,
        height: cardHeight + pileWidgetExtra,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.center,
          children: [
            if (!widget.interactable)
              AnimatedBuilder(
                animation: _shuffleController,
                builder: (context, child) {
                  final t = _shuffleController.value;
                  final angle = math.sin(t * math.pi * 6) * 0.15 * (1 - t);
                  return Transform.rotate(angle: angle, child: child);
                },
                child: _topFace(),
              )
            else
              GestureDetector(
                // Claims a zero-movement click for onDraw before Draggable's own
                // recognizer can resolve it as a zero-distance drag -- mirrors
                // how DraggableCard/ZoneStackWidget avoid the same footgun.
                onTap: widget.onDraw,
                child: Draggable<String>(
                  data: widget.topInstanceId,
                  feedback:
                      widget.feedbackOverride ??
                      Material(
                        type: MaterialType.transparency,
                        child: _topFace(),
                      ),
                  childWhenDragging: Opacity(opacity: 0.3, child: _topFace()),
                  onDragStarted: widget.onDragStarted,
                  onDragEnd: (details) => widget.onDragEnd(details.offset),
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
            if (_effectiveOnShuffle != null)
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
      ),
    );
  }
}

/// A large eyeball badge marking a zone/pile as currently being searched --
/// roughly twice the size of the Shuffle button's own circular badge (see
/// [PileWidget]'s Shuffle `Positioned`/`Material`/`CircleBorder` recipe,
/// which this mirrors). Shared by [PileWidget] and `ZoneStackWidget`.
class SearchBadge extends StatelessWidget {
  const SearchBadge({super.key});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.black54,
      shape: const CircleBorder(),
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        child: const Icon(Icons.visibility, color: Colors.white, size: 32),
      ),
    );
  }
}
