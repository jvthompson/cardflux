import 'dart:io';

import 'package:flutter/material.dart';

import '../../models/board_widget_instance.dart';
import 'counter_widget.dart' show counterWidgetWidth, counterWidgetHeight;

/// A neutral table object showing this game's `packgen.png` (looked up at
/// `<GameDefinition.folderPath>/packgen.png` -- see
/// `resolvePackGeneratorImagePath`, resolved once per build by the caller,
/// `TableScreen`) or plain "Pack Generator" text if that file doesn't
/// exist. Same footprint as `CounterWidget` ([counterWidgetWidth]/
/// [counterWidgetHeight]). Right-click lists the game's Sets (see
/// `TableScreen._showPackGeneratorMenu`); picking one deals a random pack
/// into the *clicking* player's hand. Deliberately ownerless/unowned, like
/// `CounterWidget` and `TokenWidget`.
class PackGeneratorWidget extends StatelessWidget {
  const PackGeneratorWidget({
    super.key,
    required this.instance,
    required this.imagePath,
    required this.onSecondaryTapUp,
    this.onDragEnd,
    this.interactable = true,
    this.draggable = true,
  });

  final BoardWidgetInstance instance;

  /// Absolute path to this game's `packgen.png`, or null if it doesn't
  /// exist -- resolved by the caller, since this widget has no access to
  /// `GameSession.game.folderPath` itself.
  final String? imagePath;

  final void Function(Offset globalPosition) onSecondaryTapUp;
  final void Function(Offset globalPosition)? onDragEnd;

  /// See `CounterWidget.interactable`.
  final bool interactable;

  /// See `CounterWidget.draggable`.
  final bool draggable;

  Widget _textFace() {
    return Text(
      'Pack Generator',
      textAlign: TextAlign.center,
      style: TextStyle(color: Color(instance.textColor), fontSize: 11, fontWeight: FontWeight.bold),
    );
  }

  Widget _face() {
    final path = imagePath;
    return Container(
      width: counterWidgetWidth,
      height: counterWidgetHeight,
      decoration: BoxDecoration(
        color: Color(instance.backgroundColor),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      alignment: Alignment.center,
      padding: path == null ? const EdgeInsets.all(4) : EdgeInsets.zero,
      child: path == null
          ? _textFace()
          : ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Image.file(
                File(path),
                width: counterWidgetWidth,
                height: counterWidgetHeight,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => _textFace(),
              ),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!interactable) return _face();
    return GestureDetector(
      onSecondaryTapUp: (details) => onSecondaryTapUp(details.globalPosition),
      child: draggable
          ? Draggable<String>(
              data: instance.instanceId,
              feedback: Material(type: MaterialType.transparency, child: _face()),
              childWhenDragging: Opacity(opacity: 0.3, child: _face()),
              onDragEnd: (details) => onDragEnd?.call(details.offset),
              child: _face(),
            )
          : _face(),
    );
  }
}
