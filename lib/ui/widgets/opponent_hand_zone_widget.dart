import 'package:flutter/material.dart';

import 'card_back_widget.dart';
import 'card_face_widget.dart';

/// The opponent's hand, shown only as a count of face-down backs -- the
/// filtered [TableState] a client receives never carries the real identity
/// of another player's hand cards (see state_filter.dart), so this widget
/// has nothing more to render even if it wanted to.
class OpponentHandZoneWidget extends StatelessWidget {
  const OpponentHandZoneWidget({super.key, required this.count, this.cardBackImagePath});

  final int count;
  final String? cardBackImagePath;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: cardHeight + 16,
      color: Colors.black.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: count == 0
          ? const Center(child: Text("Opponent's hand is empty", style: TextStyle(color: Colors.white70)))
          : LayoutBuilder(
              builder: (context, constraints) {
                final naturalWidth = count * cardWidth + (count - 1) * handCardSpacing;
                if (naturalWidth <= constraints.maxWidth) {
                  return ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: count,
                    separatorBuilder: (_, _) => const SizedBox(width: handCardSpacing),
                    itemBuilder: (context, index) => CardBackWidget(imagePath: cardBackImagePath),
                  );
                }
                // Overflow -- fan the backs out the same way HandZoneWidget
                // does: last card flush with the right edge, rest evenly
                // spaced between, rightmost painted on top via Stack order.
                final step = count == 1 ? 0.0 : ((constraints.maxWidth - cardWidth) / (count - 1)).clamp(0.0, double.infinity);
                return Stack(
                  children: [
                    for (var index = 0; index < count; index++)
                      Positioned(left: index * step, top: 0, child: CardBackWidget(imagePath: cardBackImagePath)),
                  ],
                );
              },
            ),
    );
  }
}
