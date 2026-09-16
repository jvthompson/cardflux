import 'package:flutter/material.dart';

import '../../models/card_back_definition.dart';
import '../../models/card_definition.dart';
import '../../models/card_instance.dart';
import 'card_face_widget.dart';
import 'draggable_card.dart';
import 'pile_widget.dart' show pileWidgetExtra;

/// Padding inside both hand-zone widgets' own band (this one and
/// [OpponentHandZoneWidget]), on every side. An owned/shared zone panel gets
/// this same 8px wrapped *around* it by its caller instead (see
/// `TableScreen._buildLocalZoneWidget`/`_buildSharedZoneWidget`/
/// `_buildOpponentZoneWidget`'s `Padding`), which *adds* to that panel's own
/// height; a hand widget applies it to itself internally via `Container`'s
/// own `padding`, which does not, so each hand widget's fixed `height` must
/// add [EdgeInsets.vertical] back explicitly to end up the same total band
/// height as a zone panel instead of coming out 16 logical pixels short.
const EdgeInsets handBandPadding = EdgeInsets.symmetric(
  horizontal: 8,
  vertical: 8,
);

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
    this.cardBacks = const [],
    this.cardKeyFor,
    this.borderColor,
    this.backgroundColor = const Color(0x26000000),
    this.onDragUpdate,
  });

  final List<CardInstance> cards;
  final Map<String, CardDefinition> definitionsById;
  final void Function(String instanceId, Offset globalPosition) onDragEnd;
  final void Function(String? instanceId)? onHoverCard;

  /// Notified with a dragged hand card's instance id and the pointer's
  /// current global position on every drag update -- see
  /// `DraggableCard.onDragUpdate`'s own copy of this concept.
  final void Function(String instanceId, Offset globalPosition)? onDragUpdate;
  final List<CardBackDefinition> cardBacks;

  /// This hand's owner's chosen color -- painted as a border on every card
  /// in it, same as any other owned card (see `TableScreen._ownerBorderColor`).
  final Color? borderColor;

  /// This zone's background band color -- either the flat black tint every
  /// zone/hand used before the F2 toggle existed, or a darkened shade of
  /// this hand's owner's color (see `TableScreen._playerTintColor`/
  /// `zoneBackgroundColor`), depending on that table-wide toggle's current
  /// state.
  final Color backgroundColor;

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
      onDragUpdate: onDragUpdate == null
          ? null
          : (globalPos) => onDragUpdate!(card.instanceId, globalPos),
      onHover: onHoverCard == null
          ? null
          : (hovering) => onHoverCard!(hovering ? card.instanceId : null),
      cardBacks: cardBacks,
      opponentBorderColor: borderColor,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // Matches a zone panel's own total band height (cardHeight +
      // pileWidgetExtra, plus the same 8px padding a zone panel's caller
      // wraps around it -- see handBandPadding's own doc) so the hand zone
      // and the deck zone(s) beside it in the same Row line up instead of
      // the hand's background band being visibly shorter.
      height: cardHeight + pileWidgetExtra + handBandPadding.vertical,
      color: backgroundColor,
      padding: handBandPadding,
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
                final Widget row;
                if (naturalWidth <= constraints.maxWidth) {
                  row = ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: cards.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(width: handCardSpacing),
                    itemBuilder: (context, index) => _cardAt(index),
                  );
                } else {
                  // Overflow -- fan the cards out with just enough overlap
                  // that the last card still lands flush with the zone's
                  // right edge (its normal, non-overlapping position) and the
                  // rest are evenly spaced between the first and last. Stack
                  // paint order is last-child-on-top, and cards are already
                  // left-to-right by zIndex, so this also gives the desired
                  // "rightmost cards sit above leftward ones" stacking for
                  // free.
                  final step = cards.length == 1
                      ? 0.0
                      : ((constraints.maxWidth - cardWidth) /
                                (cards.length - 1))
                            .clamp(0.0, double.infinity);
                  row = Stack(
                    children: [
                      for (var index = 0; index < cards.length; index++)
                        Positioned(
                          left: index * step,
                          top: 0,
                          child: _cardAt(index),
                        ),
                    ],
                  );
                }
                // Both branches above hand a horizontal-scrollable/Stack
                // ancestor a bounded height to size against -- a bare
                // ListView in particular imposes a *tight* cross-axis
                // constraint on every item, matching whatever height it's
                // given, which force-stretched each card taller than its own
                // real cardHeight once this Container's own height grew to
                // match a zone panel's (see handBandPadding's doc). Fixing
                // `row` itself to exactly cardHeight -- with the extra room
                // becoming blank margin via Center, same as how a zone
                // panel's own extra pileWidgetExtra room is just centered
                // blank space around its (naturally-sized) card -- keeps
                // every card its true, undistorted size regardless of how
                // tall this Container ends up.
                return Center(child: SizedBox(height: cardHeight, child: row));
              },
            ),
    );
  }
}
