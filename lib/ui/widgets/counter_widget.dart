import 'package:flutter/material.dart';

import '../../models/board_widget_instance.dart';

export '../../models/color_palette.dart' show boardWidgetColorPalette;

/// This tile's fixed on-screen footprint -- unlike a card, a counter has no
/// per-instance size/orientation variation to account for.
const double counterWidgetWidth = 80;
const double counterWidgetHeight = 80;

/// A Simple Counter placed on the table: an integer readout, draggable to
/// reposition like a card, right-click for its own context menu (see
/// `TableScreen._showCounterMenu` for Increment/Decrement/Set Value/Set
/// Colors/Delete). No face/back concept applies here the way it does for
/// `DraggableCard`.
class CounterWidget extends StatelessWidget {
  const CounterWidget({
    super.key,
    required this.instance,
    required this.onSecondaryTapUp,
    required this.onDoubleTapSide,
    this.onDragEnd,
    this.interactable = true,
    this.draggable = true,
  });

  final BoardWidgetInstance instance;
  final void Function(Offset globalPosition)? onDragEnd;
  final void Function(Offset globalPosition) onSecondaryTapUp;

  /// Double-tapping/double-clicking the face: `isRightSide` is true for a
  /// tap on the right half (increment), false for the left half (decrement).
  final void Function(bool isRightSide) onDoubleTapSide;

  /// False while TAB is held table-wide (see `TableScreen`), so a
  /// click-drag over this widget draws an arrow instead of moving it --
  /// mirrors `DraggableCard.interactable`. Also false for a fully read-only
  /// render (an opponent's zone-docked counter) -- suppresses every gesture,
  /// not just dragging.
  final bool interactable;

  /// False for a counter permanently docked in a `ZoneDefinition.kind ==
  /// ZoneKind.widget` player-panel slot (see `TableScreen`'s
  /// `_buildLocalWidgetZoneWidget`) -- it stays fully interactable
  /// ([onSecondaryTapUp]/[onDoubleTapSide] still work) but is never wrapped
  /// in a [Draggable], so it can never be dragged out of its slot. True (the
  /// default) preserves today's free-table behavior for every existing call
  /// site. [onDragEnd] is meaningless (and may be omitted) when false.
  final bool draggable;

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
      child: draggable
          ? Draggable<String>(
              data: instance.instanceId,
              feedback: Material(
                type: MaterialType.transparency,
                child: _face(),
              ),
              childWhenDragging: Opacity(opacity: 0.3, child: _face()),
              onDragEnd: (details) => onDragEnd?.call(details.offset),
              child: _face(),
            )
          : _face(),
    );
  }
}
