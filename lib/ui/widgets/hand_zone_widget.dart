import 'package:flutter/material.dart';

import '../../models/card_definition.dart';
import '../../models/card_instance.dart';
import 'card_face_widget.dart';
import 'draggable_card.dart';
import 'pile_widget.dart' show pileWidgetExtra;

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
    required this.onDragEnd,
    this.onHoverCard,
    this.cardBackImagePath,
    this.cardKeyFor,
  });

  final List<CardInstance> cards;
  final Map<String, CardDefinition> definitionsById;
  final void Function(String instanceId, Offset globalPosition) onDragEnd;
  final void Function(String? instanceId)? onHoverCard;
  final String? cardBackImagePath;

  /// Supplies a stable [GlobalKey] per card instance so [TableScreen] can
  /// query each rendered card's real on-screen position later (used to
  /// figure out which two cards a dropped card landed between, for
  /// drag-to-reorder) -- without this, `RenderBox` lookups would have
  /// nothing to attach to.
  final GlobalKey Function(String instanceId)? cardKeyFor;

  Widget _cardAt(int index) {
    final card = cards[index];
    return DraggableCard(
      key: cardKeyFor?.call(card.instanceId),
      instance: card,
      definition: definitionsById[card.definitionId],
      onDragEnd: (offset) => onDragEnd(card.instanceId, offset),
      onHover: onHoverCard == null
          ? null
          : (hovering) => onHoverCard!(hovering ? card.instanceId : null),
      cardBackImagePath: cardBackImagePath,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // Matches ZoneStackWidget's own height exactly (cardHeight +
      // pileWidgetExtra) so the hand zone and the deck zone(s) beside it in
      // the same Row line up instead of the hand's background band being a
      // visibly different height.
      height: cardHeight + pileWidgetExtra,
      color: Colors.black.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: cards.isEmpty
          ? const Center(
              child: Text(
                'Your hand is empty',
                style: TextStyle(color: Colors.white70),
              ),
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final naturalWidth =
                    cards.length * cardWidth +
                    (cards.length - 1) * handCardSpacing;
                if (naturalWidth <= constraints.maxWidth) {
                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: cards.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: handCardSpacing),
                    itemBuilder: (context, index) => _cardAt(index),
                  );
                }
                // Overflow -- fan the cards out with just enough overlap that
                // the last card still lands flush with the zone's right edge
                // (its normal, non-overlapping position) and the rest are
                // evenly spaced between the first and last. Stack paint order
                // is last-child-on-top, and cards are already left-to-right
                // by zIndex, so this also gives the desired "rightmost cards
                // sit above leftward ones" stacking for free.
                final step = cards.length == 1
                    ? 0.0
                    : ((constraints.maxWidth - cardWidth) / (cards.length - 1))
                          .clamp(0.0, double.infinity);
                return Stack(
                  children: [
                    for (var index = 0; index < cards.length; index++)
                      Positioned(
                        left: index * step,
                        top: 0,
                        child: _cardAt(index),
                      ),
                  ],
                );
              },
            ),
    );
  }
}
