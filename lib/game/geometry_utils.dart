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

/// Converts a card's canonical [0,1] fraction position into a viewer's local
/// pixel position within the table's Stack. [isMirrored] flips both axes for
/// the seat viewing the table from the opposite side (see
/// table_screen.dart's `TableScreen.isMirrored`) -- the host's own view is
/// never mirrored; the client's is.
(double, double) canonicalToLocalPixel({
  required double fx,
  required double fy,
  required double tableWidth,
  required double tableHeight,
  required bool isMirrored,
}) {
  final ux = isMirrored ? 1 - fx : fx;
  final uy = isMirrored ? 1 - fy : fy;
  return (ux * tableWidth, uy * tableHeight);
}

/// Inverse of [canonicalToLocalPixel] -- converts a local pixel position
/// (e.g. from a drag-end gesture) back into the canonical [0,1] fraction
/// space stored on `CardInstance`, clamped to stay within the table.
(double, double) localPixelToCanonical({
  required double pixelX,
  required double pixelY,
  required double tableWidth,
  required double tableHeight,
  required bool isMirrored,
}) {
  final fx = (pixelX / tableWidth).clamp(0.0, 1.0);
  final fy = (pixelY / tableHeight).clamp(0.0, 1.0);
  return (isMirrored ? 1 - fx : fx, isMirrored ? 1 - fy : fy);
}
