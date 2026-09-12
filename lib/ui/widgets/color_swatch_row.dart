import 'package:flutter/material.dart';

import '../../models/color_palette.dart';

/// One row of tappable swatches from [boardWidgetColorPalette] -- the
/// currently [selected] one gets a highlighted ring. Used for board-widget
/// (Counter/Token) color prompts in `TableScreen`, and for the player-color
/// picker on `HomeScreen`.
class ColorSwatchRow extends StatelessWidget {
  const ColorSwatchRow({super.key, required this.selected, required this.onSelected});

  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in boardWidgetColorPalette)
          GestureDetector(
            onTap: () => onSelected(c),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(
                  color: c == selected ? Colors.blueAccent : Theme.of(context).colorScheme.outline,
                  width: c == selected ? 3 : 1,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
