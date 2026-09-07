import 'package:flutter/material.dart';

import '../../models/card_definition.dart';
import '../../models/card_instance.dart';
import 'card_face_widget.dart';
import 'draggable_card.dart';

/// The local player's private hand — always rendered face-up, laid out in a
/// horizontal row along the bottom of the table screen.
class HandZoneWidget extends StatelessWidget {
  const HandZoneWidget({
    super.key,
    required this.cards,
    required this.definitionsById,
    required this.onTapFlip,
    required this.onDragEnd,
    this.onHoverCard,
  });

  final List<CardInstance> cards;
  final Map<String, CardDefinition> definitionsById;
  final void Function(String instanceId) onTapFlip;
  final void Function(String instanceId, Offset globalPosition) onDragEnd;
  final void Function(String? instanceId)? onHoverCard;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: cardHeight + 16,
      color: Colors.black.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: cards.isEmpty
          ? const Center(child: Text('Your hand is empty', style: TextStyle(color: Colors.white70)))
          : ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: cards.length,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) {
                final card = cards[index];
                return DraggableCard(
                  instance: card,
                  definition: definitionsById[card.definitionId],
                  onTapFlip: () => onTapFlip(card.instanceId),
                  onDragEnd: (offset) => onDragEnd(card.instanceId, offset),
                  onHover: onHoverCard == null ? null : (hovering) => onHoverCard!(hovering ? card.instanceId : null),
                );
              },
            ),
    );
  }
}
