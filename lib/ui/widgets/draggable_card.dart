import 'package:flutter/material.dart';

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
/// stack, tappable to flip. [definition] is null for a hidden opponent-hand
/// card (see state_filter.dart's sentinel) — in that case a back is always
/// shown regardless of [instance.faceUp].
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
/// [interactable] gates tap-to-flip and drag entirely (used to block acting
/// on a card owned by the other player) -- hover still fires either way, so
/// the opponent border and Space-preview keep working on a card you can't
/// otherwise touch.
class DraggableCard extends StatelessWidget {
  const DraggableCard({
    super.key,
    required this.instance,
    required this.definition,
    required this.onTapFlip,
    required this.onDragEnd,
    this.isMirrored = false,
    this.interactable = true,
    this.opponentBorderColor,
    this.onHover,
    this.cardBackImagePath,
  });

  final CardInstance instance;
  final CardDefinition? definition;
  final VoidCallback onTapFlip;
  final void Function(Offset globalPosition) onDragEnd;
  final bool isMirrored;
  final bool interactable;

  /// Non-null when this card is owned by the other player -- painted as a
  /// thin border *inside* the same rotated subtree as the card's face/back
  /// (see [_face]) so it turns together with Q/E rotation or the mirror
  /// flip, instead of staying axis-aligned.
  final Color? opponentBorderColor;
  final ValueChanged<bool>? onHover;
  final String? cardBackImagePath;

  Widget _face() {
    final content = instance.faceUp && definition != null
        ? CardFaceWidget(definition: definition!)
        : CardBackWidget(imagePath: cardBackImagePath);
    final bordered = opponentBorderColor == null
        ? content
        : Container(
            foregroundDecoration: BoxDecoration(
              border: Border.all(color: opponentBorderColor!, width: 2),
              borderRadius: BorderRadius.circular(6),
            ),
            child: content,
          );
    final turns = (isMirrored ? 0.5 : 0.0) + instance.rotationTurns / 4;
    return AnimatedRotation(turns: turns, duration: rotationAnimationDuration, curve: Curves.easeOut, child: bordered);
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
      child: GestureDetector(
        onTap: onTapFlip,
        child: Draggable<String>(
          data: instance.instanceId,
          feedback: Material(type: MaterialType.transparency, child: _face()),
          childWhenDragging: Opacity(opacity: 0.3, child: _face()),
          onDragEnd: (details) => onDragEnd(details.offset),
          child: _face(),
        ),
      ),
    );
  }
}
