import 'package:flutter/material.dart';

import '../../models/board_widget_instance.dart';

/// This tile's fixed on-screen footprint -- unlike a card, a counter has no
/// per-instance size/orientation variation to account for.
const double counterWidgetWidth = 80;
const double counterWidgetHeight = 80;

/// Preset swatches offered by every board widget's color prompt (see
/// `TableScreen._colorSwatchRow`, used by both `_promptSetColors` for a
/// Simple Counter and `_promptSetTokenColor` for a Token) -- a small fixed
/// palette rather than a full color picker, since this app has no
/// color-picker dependency and a board widget's color is a cosmetic touch,
/// not something that needs an arbitrary RGB value.
const List<int> boardWidgetColorPalette = [
  0xFF455A64, // blueGrey (default background)
  0xFFFFFFFF, // white (default text)
  0xFF000000, // black
  0xFFD32F2F, // red
  0xFFF57C00, // orange
  0xFFFBC02D, // yellow
  0xFF388E3C, // green
  0xFF1976D2, // blue
  0xFF7B1FA2, // purple
  0xFF5D4037, // brown
  0xFF9E9E9E, // grey
  0xFFEC407A, // pink
];

/// A Simple Counter placed on the table: an integer readout, draggable to
/// reposition like a card, right-click for its own context menu (see
/// `TableScreen._showCounterMenu` for Increment/Decrement/Set Value/Set
/// Colors/Delete). No face/back concept applies here the way it does for
/// `DraggableCard`.
class CounterWidget extends StatelessWidget {
  const CounterWidget({
    super.key,
    required this.instance,
    required this.onDragEnd,
    required this.onSecondaryTapUp,
    required this.onDoubleTapSide,
    this.interactable = true,
  });

  final BoardWidgetInstance instance;
  final void Function(Offset globalPosition) onDragEnd;
  final void Function(Offset globalPosition) onSecondaryTapUp;

  /// Double-tapping/double-clicking the face: `isRightSide` is true for a
  /// tap on the right half (increment), false for the left half (decrement).
  final void Function(bool isRightSide) onDoubleTapSide;

  /// False while TAB is held table-wide (see `TableScreen`), so a
  /// click-drag over this widget draws an arrow instead of moving it --
  /// mirrors `DraggableCard.interactable`.
  final bool interactable;

  Widget _face() {
    return Container(
      width: counterWidgetWidth,
      height: counterWidgetHeight,
      decoration: BoxDecoration(
        color: Color(instance.backgroundColor),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      alignment: Alignment.center,
      child: Text(
        '${instance.value}',
        style: TextStyle(
          color: Color(instance.textColor),
          fontSize: 22,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!interactable) return _face();
    return GestureDetector(
      onSecondaryTapUp: (details) => onSecondaryTapUp(details.globalPosition),
      onDoubleTapDown: (details) =>
          onDoubleTapSide(details.localPosition.dx >= counterWidgetWidth / 2),
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
