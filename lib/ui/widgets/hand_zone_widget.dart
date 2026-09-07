import 'package:flutter/material.dart';

import '../../models/card_definition.dart';
import '../../models/card_instance.dart';
import 'card_face_widget.dart';
import 'draggable_card.dart';

/// The local player's private hand — always rendered face-up, laid out in a
/// horizontal row along the bottom of the table screen. [cards] must already
/// be in the desired left-to-right display order (see `TableScreen`, which
/// sorts by zIndex -- the same field [reorderHand]-style actions renumber to
/// change that order).
class HandZoneWidget extends StatelessWidget {
  const HandZoneWidget({
    super.key,
    required this.cards,
    required this.definitionsById,
    required this.onTapFlip,
    required this.onDragEnd,
    this.onHoverCard,
    this.cardBackImagePath,
    this.cardKeyFor,
  });

  final List<CardInstance> cards;
  final Map<String, CardDefinition> definitionsById;
  final void Function(String instanceId) onTapFlip;
  final void Function(String instanceId, Offset globalPosition) onDragEnd;
  final void Function(String? instanceId)? onHoverCard;
  final String? cardBackImagePath;

  /// Supplies a stable [GlobalKey] per card instance so [TableScreen] can
  /// query each rendered card's real on-screen position later (used to
  /// figure out which two cards a dropped card landed between, for
  /// drag-to-reorder) -- without this, `RenderBox` lookups would have
  /// nothing to attach to.
  final GlobalKey Function(String instanceId)? cardKeyFor;

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
                  key: cardKeyFor?.call(card.instanceId),
                  instance: card,
                  definition: definitionsById[card.definitionId],
                  onTapFlip: () => onTapFlip(card.instanceId),
                  onDragEnd: (offset) => onDragEnd(card.instanceId, offset),
                  onHover: onHoverCard == null ? null : (hovering) => onHoverCard!(hovering ? card.instanceId : null),
                  cardBackImagePath: cardBackImagePath,
                );
              },
            ),
    );
  }
}
