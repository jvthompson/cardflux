import 'package:flutter/material.dart';

import '../../models/board_widget_instance.dart';

/// A token's fixed on-screen diameter -- small on purpose, a plain marker
/// rather than something meant to hold readable content the way a
/// `CounterWidget` does.
const double tokenWidgetSize = 15;

/// A small colored circle placed on the table -- just a marker, with no
/// numeric state. Draggable to reposition like any other board widget;
/// Ctrl+drag duplicates it instead of moving it (see
/// `TableScreen._handleTokenDragEnd`). Right-click for its own context menu
/// (see `TableScreen._showTokenMenu` for Set Color/Delete).
class TokenWidget extends StatelessWidget {
  const TokenWidget({
    super.key,
    required this.instance,
    required this.onDragEnd,
    required this.onSecondaryTapUp,
  });

  final BoardWidgetInstance instance;
  final void Function(Offset globalPosition) onDragEnd;
  final void Function(Offset globalPosition) onSecondaryTapUp;

  Widget _face() {
    return Container(
      width: tokenWidgetSize,
      height: tokenWidgetSize,
      decoration: BoxDecoration(
        color: Color(instance.backgroundColor),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black26),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onSecondaryTapUp: (details) => onSecondaryTapUp(details.globalPosition),
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
