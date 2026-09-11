import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/card_definition.dart';
import '../../models/card_instance.dart';
import 'card_back_widget.dart';
import 'card_face_widget.dart';

/// The Search window opened over a zone/pile the local player is searching
/// (see `TableScreen`'s `ActiveSearch` lookup) -- a floating panel, not a
/// pushed route, so it stays in the same `Overlay` subtree as the board and
/// its `Draggable` cards can still be released onto the table/hand through
/// `TableScreen._handleDragEnd`'s existing `GlobalKey`-based hit-testing.
///
/// [cards] must already be sorted topmost-card-first (see
/// `TableScreen`'s zIndex-descending sort) -- this widget just lays them out
/// in a grid, it doesn't sort them itself.
class ZoneSearchOverlay extends StatelessWidget {
  const ZoneSearchOverlay({
    super.key,
    required this.title,
    required this.cards,
    required this.definitionsById,
    required this.screenSize,
    required this.onClose,
    required this.onCardDragEnd,
    required this.onCardHover,
  });

  final String title;
  final List<CardInstance> cards;
  final Map<String, CardDefinition> definitionsById;
  final Size screenSize;
  final VoidCallback onClose;
  final void Function(String instanceId, Offset globalTopLeft) onCardDragEnd;

  /// Reports mouse enter/exit over a tile -- wired by `TableScreen` into its
  /// existing `_setHoveredId`, so holding Space over a searched card shows
  /// the same large preview every other card already gets.
  final void Function(String instanceId, bool hovering) onCardHover;

  @override
  Widget build(BuildContext context) {
    final width = math.min(1280.0, screenSize.width - 40);
    final height = math.min(720.0, screenSize.height - 40);

    return Stack(
      children: [
        // A light scrim, not opaque -- the board stays visible (and,
        // functionally, still reachable for a drop release) around the
        // window's edges. Tapping it closes the window, same as the X
        // button.
        Positioned.fill(
          child: GestureDetector(
            onTap: onClose,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.25)),
          ),
        ),
        Center(
          child: SizedBox(
            width: width,
            height: height,
            child: Material(
              color: const Color(0xFF262626),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        Text(
                          '${cards.length} card${cards.length == 1 ? '' : 's'}',
                          style: const TextStyle(color: Colors.white70),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          tooltip: 'Close',
                          onPressed: onClose,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white24),
                  Expanded(
                    child: cards.isEmpty
                        ? const Center(
                            child: Text(
                              'Nothing here to search.',
                              style: TextStyle(color: Colors.white54),
                            ),
                          )
                        : GridView.builder(
                            padding: const EdgeInsets.all(12),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                                  maxCrossAxisExtent: cardWidth + 24,
                                  mainAxisExtent: cardHeight + 28,
                                  crossAxisSpacing: 12,
                                  mainAxisSpacing: 12,
                                ),
                            itemCount: cards.length,
                            itemBuilder: (context, index) {
                              final card = cards[index];
                              return _SearchTile(
                                card: card,
                                definition: definitionsById[card.definitionId],
                                onDragEnd: (offset) =>
                                    onCardDragEnd(card.instanceId, offset),
                                onHover: (hovering) =>
                                    onCardHover(card.instanceId, hovering),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _SearchTile extends StatelessWidget {
  const _SearchTile({
    required this.card,
    required this.definition,
    required this.onDragEnd,
    required this.onHover,
  });

  final CardInstance card;
  final CardDefinition? definition;
  final ValueChanged<Offset> onDragEnd;
  final ValueChanged<bool> onHover;

  @override
  Widget build(BuildContext context) {
    // Always the real face, regardless of `card.faceUp` -- this is the
    // owner privately inspecting their own zone/pile (or a shared one,
    // already visible to everyone), never an opponent's hidden card.
    final face = definition == null
        ? const CardBackWidget()
        : CardFaceWidget(definition: definition!);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        MouseRegion(
          onEnter: (_) => onHover(true),
          onExit: (_) => onHover(false),
          child: Draggable<String>(
            data: card.instanceId,
            feedback: Material(type: MaterialType.transparency, child: face),
            childWhenDragging: Opacity(opacity: 0.3, child: face),
            onDragEnd: (details) => onDragEnd(details.offset),
            child: face,
          ),
        ),
        const SizedBox(height: 4),
        SizedBox(
          width: cardWidth,
          child: Text(
            definition?.cardTitle ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11, color: Colors.white),
          ),
        ),
      ],
    );
  }
}
