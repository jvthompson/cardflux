/// A card (or grouped stack) another player is currently dragging, before
/// they've released it -- purely cosmetic, never persisted, and never
/// derived from [TableState]/[GameSession.revision] (see `GameSession`'s
/// `cardDragPreviews` doc comment for why). [instanceIds] is the dragged
/// primary followed by any passenger root ids riding along (see
/// `TableScreen._buildGroupFeedback`); [fx]/[fy] is the primary's live
/// target position, in the same canonical `[0,1]` fraction space
/// `CardInstance.x`/`y` already use. Card identity is deliberately absent
/// here -- a receiver renders using its own already-privacy-filtered local
/// `CardInstance` for each id (see `state_filter.dart`), so a card hidden
/// from a given viewer stays hidden throughout the drag for free.
class CardDragPreview {
  const CardDragPreview({
    required this.playerId,
    required this.instanceIds,
    required this.fx,
    required this.fy,
  });

  final String playerId;
  final List<String> instanceIds;
  final double fx;
  final double fy;
}

/// An in-progress TAB-drag arrow another player is currently drawing, before
/// they've released it -- see [CardDragPreview]'s doc for why this is a
/// separate, non-persisted channel. Both endpoints are canonical `[0,1]`
/// fractions, matching `BoardWidgetInstance`'s own arrow fields.
class ArrowDragPreview {
  const ArrowDragPreview({
    required this.playerId,
    required this.fx,
    required this.fy,
    required this.fx2,
    required this.fy2,
  });

  final String playerId;
  final double fx;
  final double fy;
  final double fx2;
  final double fy2;
}

/// What a locally-initiated drag/arrow preview is published through so it
/// reaches other players -- implemented by `HostGameEngine`, which both
/// relays a client's preview to every other client and (since the host has
/// no socket to itself) is also where the host's own `HostTableController`
/// publishes its own drags directly.
abstract class DragPreviewSink {
  void publishCardDragPreview({
    required String playerId,
    required List<String> instanceIds,
    required double fx,
    required double fy,
  });
  void clearCardDragPreview(String playerId);

  void publishArrowDragPreview({
    required String playerId,
    required double fx,
    required double fy,
    required double fx2,
    required double fy2,
  });
  void clearArrowDragPreview(String playerId);
}
