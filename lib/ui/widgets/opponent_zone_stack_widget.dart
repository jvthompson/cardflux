import 'package:flutter/material.dart';

import '../../models/card_definition.dart';
import 'card_back_widget.dart';
import 'card_face_widget.dart';
import 'pile_widget.dart' show SearchBadge, pileWidgetExtra;

/// The opponent's instance of a zone, shown read-only with a count badge --
/// no draw/shuffle affordance, matching how the opponent's hand is already
/// shown as a plain count rather than interactive cards. Shows the real face
/// of the top card when [topFaceUp] and [topDefinition] are both non-null --
/// only possible for a `ZoneDefinition.visibleToAll` zone (a discard pile,
/// say); the filtered state a client receives for any other owned zone
/// always redacts both (see state_filter.dart), so this falls back to a
/// back exactly like before that flag existed. When [count] is 0, shows the
/// same empty outlined placeholder as `ZoneStackWidget` -- no back, no count
/// badge -- rather than a misleading card back with nothing behind it.
class OpponentZoneStackWidget extends StatelessWidget {
  const OpponentZoneStackWidget({
    super.key,
    required this.zoneName,
    required this.count,
    this.topFaceUp = false,
    this.topDefinition,
    this.isBeingSearched = false,
    this.cardBackImagePath,
  });

  final String zoneName;
  final int count;
  final bool topFaceUp;
  final CardDefinition? topDefinition;

  /// See `PileWidget.isBeingSearched`'s identical doc.
  final bool isBeingSearched;
  final String? cardBackImagePath;

  @override
  Widget build(BuildContext context) {
    return Tooltip(message: zoneName, child: _buildContent());
  }

  Widget _buildContent() {
    if (count == 0) {
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
            if (isBeingSearched)
              const Positioned(top: -12, child: SearchBadge()),
          ],
        ),
      );
    }
    final content = topFaceUp && topDefinition != null
        ? CardFaceWidget(definition: topDefinition!)
        : CardBackWidget(imagePath: cardBackImagePath);
    return SizedBox(
      width: cardWidth + pileWidgetExtra,
      height: cardHeight + pileWidgetExtra,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          content,
          Positioned(
            top: 0,
            right: 0,
            child: CircleAvatar(
              radius: 12,
              backgroundColor: Colors.black87,
              child: Text(
                '$count',
                style: const TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
          if (isBeingSearched) const Positioned(top: -12, child: SearchBadge()),
        ],
      ),
    );
  }
}
