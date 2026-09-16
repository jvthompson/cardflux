import 'package:flutter/material.dart';

import '../../data/image_path_resolver.dart';
import '../../models/card_back_definition.dart';
import '../../models/card_definition.dart';
import '../../models/card_instance.dart';
import 'card_back_widget.dart';
import 'card_face_widget.dart';

/// How long a rotation (from [CardInstance.rotationTurns] changing, or the
/// mirror-flip in [isMirrored]) takes to visually settle -- quick and sharp
/// on purpose, so a Q/E table rotation reads as an instant, obvious snap
/// rather than a slow spin.
const Duration rotationAnimationDuration = Duration(milliseconds: 150);

/// A single card rendered at its table position: draggable to reposition or
/// stack. Flipping is done by hovering it and pressing F (see
/// `TableScreen._flipHovered`), not by clicking it. [definition] is null for
/// a hidden opponent-hand card (see state_filter.dart's sentinel) — in that
/// case a back is always shown regardless of [instance.faceUp].
///
/// [isMirrored] rotates the rendered face/back 180° -- used for shared table
/// cards on a mirrored seat's view (see table_screen.dart's
/// `TableScreen.isMirrored`); defaults to false since a player's own hand
/// (rendered via `HandZoneWidget`) is never mirrored regardless of seat. This
/// folds into the same [AnimatedRotation] as [CardInstance.rotationTurns]
/// (the table-only Q/E rotation), so both animate the same way.
///
/// [onHover], if given, is notified when the mouse enters/exits this card --
/// used by [TableScreen] to drive the Space-hold full-size preview, and to
/// know which table card D/Q/E should act on.
///
/// [interactable] gates drag entirely (used to block acting on a card owned
/// by the other player) -- hover still fires either way, so the opponent
/// border, Space-preview, and F-flip-eligibility keep working on a card you
/// can't otherwise touch (F itself separately checks ownership again in
/// `TableScreen._hoveredFlippableCard`).
///
/// [applyOrientation], when true, folds [CardDefinition.orientation] into the
/// same rotation -- only ever set for a loose card on the free table; hand
/// and zone rendering leave it false so a landscape card always shows plain
/// portrait there.
class DraggableCard extends StatelessWidget {
  const DraggableCard({
    super.key,
    required this.instance,
    required this.definition,
    required this.onDragEnd,
    this.isMirrored = false,
    this.interactable = true,
    this.applyOrientation = false,
    this.opponentBorderColor,
    this.onHover,
    this.cardBacks = const [],
    this.feedbackOverride,
    this.onDragStarted,
    this.onDragUpdate,
  });

  final CardInstance instance;
  final CardDefinition? definition;
  final void Function(Offset globalPosition) onDragEnd;
  final bool isMirrored;
  final bool interactable;
  final bool applyOrientation;

  /// Replaces the default single-card drag feedback (this card's own face)
  /// with a caller-supplied widget -- used to show the whole pickup group
  /// (see `TableScreen._pickupGroup`) following the cursor together, instead
  /// of just the card actually grabbed. Null keeps the default.
  final Widget? feedbackOverride;

  /// Notified the instant a drag gesture on this card actually starts (not
  /// just a tap) -- used to record which other cards are being carried along
  /// as passengers, so they can be ghosted in place for the duration of the
  /// drag, matching this card's own automatic [childWhenDragging] dimming.
  final VoidCallback? onDragStarted;

  /// Notified with the pointer's current global position on every drag
  /// update -- used to broadcast a throttled live-drag preview to other
  /// players (see `TableScreen`'s `_handleCardDragPreviewUpdate`). Null is
  /// the default and wires nothing extra into the underlying [Draggable].
  final void Function(Offset globalPosition)? onDragUpdate;

  /// Non-null when this card is owned by the other player -- painted as a
  /// thin border *inside* the same rotated subtree as the card's face/back
  /// (see [_face]) so it turns together with Q/E rotation or the mirror
  /// flip, instead of staying axis-aligned.
  final Color? opponentBorderColor;
  final ValueChanged<bool>? onHover;
  final List<CardBackDefinition> cardBacks;

  Widget _face() {
    final showingBack = !(instance.faceUp && definition != null);
    final content = showingBack
        ? CardBackWidget(cardBacks: cardBacks, card: definition)
        : CardFaceWidget(definition: definition!);
    final bordered = opponentBorderColor == null
        ? content
        : Container(
            foregroundDecoration: BoxDecoration(
              border: Border.all(color: opponentBorderColor!, width: 2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: content,
          );
    final orientation = !applyOrientation
        ? CardOrientation.portrait
        : showingBack
            ? resolveCardBackImagePath(cardBacks: cardBacks, card: definition).orientation
            : (definition?.orientation ?? CardOrientation.portrait);
    final turns =
        (isMirrored ? 0.5 : 0.0) +
        orientationTurns(orientation) +
        instance.rotationTurns / 4;
    return AnimatedRotation(
      turns: turns,
      duration: rotationAnimationDuration,
      curve: Curves.easeOut,
      child: bordered,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!interactable) {
      return MouseRegion(
        onEnter: (_) => onHover?.call(true),
        onExit: (_) => onHover?.call(false),
        child: _face(),
      );
    }
    return MouseRegion(
      onEnter: (_) => onHover?.call(true),
      onExit: (_) => onHover?.call(false),
      child: Draggable<String>(
        data: instance.instanceId,
        feedback:
            feedbackOverride ??
            Material(type: MaterialType.transparency, child: _face()),
        childWhenDragging: Opacity(opacity: 0.3, child: _face()),
        onDragStarted: onDragStarted,
        onDragUpdate: onDragUpdate == null
            ? null
            : (details) => onDragUpdate!(details.globalPosition),
        onDragEnd: (details) => onDragEnd(details.offset),
        child: _face(),
      ),
    );
  }
}
