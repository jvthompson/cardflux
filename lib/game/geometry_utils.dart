/// Clamps a proposed card center-Y so the whole card stays at least [margin]
/// logical pixels clear of both hand-zone bands flanking the table's own
/// Stack: the opponent's zone above (table-local y <= 0) and the local
/// player's zone below (table-local y >= [tableHeight]). Operates purely in
/// the table Stack's own local coordinate space -- callers are responsible
/// for translating to/from global/screen coordinates (see
/// table_screen.dart's `_handleDragEnd`).
///
/// If [tableHeight] is too small to fit a card of [cardHeight] plus [margin]
/// on both sides (e.g. an aggressively resized/tiny window), the valid range
/// inverts; in that degenerate case this returns the vertical center of the
/// available table height instead of throwing, since `num.clamp` requires
/// its lower bound <= its upper bound.
double clampCardCenterY({
  required double proposedCenterY,
  required double tableHeight,
  required double cardHeight,
  double margin = 10,
}) {
  final halfCard = cardHeight / 2;
  final lowerBound = margin + halfCard;
  final upperBound = tableHeight - margin - halfCard;
  if (lowerBound > upperBound) return tableHeight / 2;
  return proposedCenterY.clamp(lowerBound, upperBound);
}
