import 'package:flutter/material.dart';

import 'card_back_widget.dart';
import 'card_face_widget.dart';
import 'hand_zone_widget.dart' show handBandPadding;
import 'pile_widget.dart' show pileWidgetExtra;

/// The opponent's hand, shown only as a count of face-down backs -- the
/// filtered [TableState] a client receives never carries the real identity
/// of another player's hand cards (see state_filter.dart), so this widget
/// has nothing more to render even if it wanted to.
class OpponentHandZoneWidget extends StatelessWidget {
  const OpponentHandZoneWidget({
    super.key,
    required this.count,
    this.cardBackImagePath,
    this.borderColor,
    this.backgroundColor = const Color(0x26000000),
  });

  final int count;
  final String? cardBackImagePath;

  /// This hand's owner's chosen color -- painted as a border on every back,
  /// same as any other owned card (see `TableScreen._ownerBorderColor`).
  final Color? borderColor;

  /// This zone's background band color -- either the flat black tint every
  /// zone/hand used before the F2 toggle existed, or a darkened shade of
  /// this hand's owner's color (see `TableScreen._playerTintColor`/
  /// `zoneBackgroundColor`), depending on that table-wide toggle's current
  /// state.
  final Color backgroundColor;

  Widget _back() {
    final content = CardBackWidget(imagePath: cardBackImagePath);
    if (borderColor == null) return content;
    return Container(
      foregroundDecoration: BoxDecoration(
        border: Border.all(color: borderColor!, width: 2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      // Matches HandZoneWidget's own total band height exactly (see
      // handBandPadding's doc for why the +handBandPadding.vertical is
      // needed on top of cardHeight + pileWidgetExtra) -- both hand widgets
      // must stay in lockstep with each other, and both with every zone
      // panel's own band height, or the row they all sit in looks uneven.
      height: cardHeight + pileWidgetExtra + handBandPadding.vertical,
      color: backgroundColor,
      padding: handBandPadding,
      child: count == 0
          ? const Center(child: Text("Opponent's hand is empty", style: TextStyle(color: Colors.white70)))
          : LayoutBuilder(
              builder: (context, constraints) {
                final naturalWidth = count * cardWidth + (count - 1) * handCardSpacing;
                final Widget row;
                if (naturalWidth <= constraints.maxWidth) {
                  row = ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: count,
                    separatorBuilder: (_, _) => const SizedBox(width: handCardSpacing),
                    itemBuilder: (context, index) => _back(),
                  );
                } else {
                  // Overflow -- fan the backs out the same way HandZoneWidget
                  // does: last card flush with the right edge, rest evenly
                  // spaced between, rightmost painted on top via Stack order.
                  final step = count == 1 ? 0.0 : ((constraints.maxWidth - cardWidth) / (count - 1)).clamp(0.0, double.infinity);
                  row = Stack(
                    children: [
                      for (var index = 0; index < count; index++)
                        Positioned(left: index * step, top: 0, child: _back()),
                    ],
                  );
                }
                // See HandZoneWidget's identical fix for why `row` must be
                // pinned to exactly cardHeight here -- otherwise the bare
                // ListView branch's tight cross-axis constraint stretches
                // every back taller than its real size once this Container
                // grew to match a zone panel's total height.
                return Center(child: SizedBox(height: cardHeight, child: row));
              },
            ),
    );
  }
}
