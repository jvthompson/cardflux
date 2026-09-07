import 'dart:math' show pi;

import 'package:flutter/material.dart';

import '../../models/card_definition.dart';
import '../../models/card_instance.dart';
import 'card_back_widget.dart';
import 'card_face_widget.dart';

/// A single card rendered at its table position: draggable to reposition or
/// stack, tappable to flip. [definition] is null for a hidden opponent-hand
/// card (see state_filter.dart's sentinel) — in that case a back is always
/// shown regardless of [instance.faceUp].
///
/// [isMirrored] rotates the rendered face/back 180° -- used for shared table
/// cards on a mirrored seat's view (see table_screen.dart's
/// `TableScreen.isMirrored`); defaults to false since a player's own hand
/// (rendered via `HandZoneWidget`) is never mirrored regardless of seat.
class DraggableCard extends StatelessWidget {
  const DraggableCard({
    super.key,
    required this.instance,
    required this.definition,
    required this.onTapFlip,
    required this.onDragEnd,
    this.isMirrored = false,
  });

  final CardInstance instance;
  final CardDefinition? definition;
  final VoidCallback onTapFlip;
  final void Function(Offset globalPosition) onDragEnd;
  final bool isMirrored;

  Widget _face() {
    final content = instance.faceUp && definition != null ? CardFaceWidget(definition: definition!) : const CardBackWidget();
    return isMirrored ? Transform.rotate(angle: pi, child: content) : content;
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTapFlip,
      child: Draggable<String>(
        data: instance.instanceId,
        feedback: Material(type: MaterialType.transparency, child: _face()),
        childWhenDragging: Opacity(opacity: 0.3, child: _face()),
        onDragEnd: (details) => onDragEnd(details.offset),
        child: _face(),
      ),
    );
  }
}
