import 'package:flutter/material.dart';

import 'card_back_widget.dart';
import 'card_face_widget.dart';

/// The opponent's hand, shown only as a count of face-down backs -- the
/// filtered [TableState] a client receives never carries the real identity
/// of another player's hand cards (see state_filter.dart), so this widget
/// has nothing more to render even if it wanted to.
class OpponentHandZoneWidget extends StatelessWidget {
  const OpponentHandZoneWidget({super.key, required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: cardHeight + 16,
      color: Colors.black.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      child: count == 0
          ? const Center(child: Text("Opponent's hand is empty", style: TextStyle(color: Colors.white70)))
          : ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: count,
              separatorBuilder: (_, _) => const SizedBox(width: 6),
              itemBuilder: (context, index) => const CardBackWidget(),
            ),
    );
  }
}
