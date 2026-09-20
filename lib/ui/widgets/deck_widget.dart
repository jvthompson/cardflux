import 'package:flutter/material.dart';

import '../../models/board_widget_instance.dart';
import 'card_face_widget.dart' show cardWidth, cardHeight;
import 'pile_widget.dart' show pileWidgetExtra;

const double _deckWidgetHeaderHeight = 24;
const double _deckWidgetFooterHeight = 36;
const double _deckWidgetSpacing = 8;
const double _deckWidgetPadding = 8;

/// The footprint of a [DeckWidget] with [subZoneCount] deck-building
/// sub-zones -- unlike every other [BoardWidgetKind], this one's size isn't
/// a per-kind constant (see `TableScreen._widgetSize`'s per-kind switch),
/// since it depends on how many `GameDefinition.deckBuildingZones` the
/// loaded game declares. Floors at 1 so a widget spawned for a game that's
/// since lost its deck-building zones still renders a sane, non-empty box.
(double, double) deckWidgetSize(int subZoneCount) {
  final n = subZoneCount < 1 ? 1 : subZoneCount;
  final zoneWidth = cardWidth + pileWidgetExtra;
  final zoneHeight = cardHeight + pileWidgetExtra;
  final width = n * zoneWidth + (n - 1) * _deckWidgetSpacing + _deckWidgetPadding * 2;
  final height =
      _deckWidgetHeaderHeight + _deckWidgetSpacing + zoneHeight + _deckWidgetSpacing + _deckWidgetFooterHeight + _deckWidgetPadding * 2;
  return (width, height);
}

/// A table-side deck-building station (see [BoardWidgetKind.deckBuilder]):
/// one labeled sub-zone per `GameDefinition.deckBuildingZones` entry
/// ([zoneFaces], pre-built by `TableScreen` since it alone has access to
/// `GameSession`/the zone-drag-and-search machinery), plus a Save button.
/// Owned by whoever spawned it -- [isOwner] switches between the fully
/// interactive owner view (draggable header to reposition the whole widget,
/// a working Save button) and a read-only view for everyone else (plain
/// header text, no Save button, no gestures at all -- [zoneFaces] itself is
/// expected to already be built read-only in that case, e.g. via
/// `OpponentZoneStackWidget`).
class DeckWidget extends StatelessWidget {
  const DeckWidget({
    super.key,
    required this.instance,
    required this.isOwner,
    required this.ownerLabel,
    required this.zoneFaces,
    this.onMoveDragEnd,
    this.onSave,
    this.onSecondaryTapUp,
    this.interactable = true,
  });

  final BoardWidgetInstance instance;
  final bool isOwner;
  final String ownerLabel;
  final List<Widget> zoneFaces;

  /// Repositions the whole widget -- only ever wired up for the owner.
  final void Function(Offset globalPosition)? onMoveDragEnd;

  /// Opens the save-deck flow -- only ever wired up for the owner.
  final VoidCallback? onSave;

  final void Function(Offset globalPosition)? onSecondaryTapUp;

  /// See `CounterWidget.interactable`.
  final bool interactable;

  Widget _headerText() => Text(
        ownerLabel,
        style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
        overflow: TextOverflow.ellipsis,
      );

  Widget _header() {
    final content = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.drag_indicator, size: 14, color: Colors.white70),
        const SizedBox(width: 4),
        Flexible(child: _headerText()),
      ],
    );
    if (!isOwner || !interactable) return content;
    return Draggable<String>(
      data: instance.instanceId,
      feedback: Material(type: MaterialType.transparency, child: content),
      childWhenDragging: Opacity(opacity: 0.3, child: content),
      onDragEnd: (details) => onMoveDragEnd?.call(details.offset),
      child: content,
    );
  }

  @override
  Widget build(BuildContext context) {
    final body = Container(
      padding: const EdgeInsets.all(_deckWidgetPadding),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white24),
      ),
      // IntrinsicWidth bounds the Save button's `width: double.infinity`
      // below to this Column's own natural (header/zone-row) width, rather
      // than the ambient table Stack's -- otherwise, sitting in a Stack
      // with no width constraint of its own, that button would balloon to
      // fill the entire table and drag the rest of this box along with it,
      // rendering the button far outside where the widget visually appears.
      child: IntrinsicWidth(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: _deckWidgetHeaderHeight, child: _header()),
            const SizedBox(height: _deckWidgetSpacing),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < zoneFaces.length; i++) ...[
                  if (i > 0) const SizedBox(width: _deckWidgetSpacing),
                  zoneFaces[i],
                ],
              ],
            ),
            if (isOwner && onSave != null) ...[
              const SizedBox(height: _deckWidgetSpacing),
              SizedBox(
                width: double.infinity,
                height: _deckWidgetFooterHeight,
                child: ElevatedButton(
                  onPressed: interactable ? onSave : null,
                  child: const Text('Save Deck'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
    if (!interactable || onSecondaryTapUp == null) return body;
    return GestureDetector(
      onSecondaryTapUp: (details) => onSecondaryTapUp!(details.globalPosition),
      child: body,
    );
  }
}
