import 'package:flutter/material.dart';

import '../../models/card_definition.dart';
import '../../models/card_instance.dart';
import 'card_back_widget.dart';
import 'card_face_widget.dart';

/// A single card rendered at its table position: draggable to reposition or
/// stack, tappable to flip. [definition] is null for a hidden opponent-hand
/// card (see state_filter.dart's sentinel) — in that case a back is always
/// shown regardless of [instance.faceUp].
class DraggableCard extends StatelessWidget {
  const DraggableCard({
    super.key,
    required this.instance,
    required this.definition,
    required this.onTapFlip,
    required this.onDragEnd,
  });

  final CardInstance instance;
  final CardDefinition? definition;
  final VoidCallback onTapFlip;
  final void Function(Offset globalPosition) onDragEnd;

  Widget _face() {
    if (instance.faceUp && definition != null) {
      return CardFaceWidget(definition: definition!);
    }
    return const CardBackWidget();
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
