import 'dart:ui';

/// The table's actual, real, fixed pixel dimensions -- identical for every
/// player regardless of their own window size. Canonical [0,1] positions
/// are always scaled against this fixed size, never the live viewport (see
/// `TableScreen._toScreenPixel`), so two players with different window
/// sizes see the *same physical table at the same physical scale* -- a
/// smaller window just shows less of it at once (see
/// [worldCenteringOffset] and `TableScreen`'s WASD camera pan), rather than
/// a zoomed-in or zoomed-out view of the same content. Sized at QHD
/// (2560x1440) so the table stays bigger than a typical maximized window
/// while still comfortably fitting ~36x14 70x100px cards edge-to-edge, with
/// room to spread out and reason to pan, without leaving so much blank
/// margin that panning feels like wandering an empty room.
const Size kWorldSize = Size(2560, 1440);

/// Where the fixed-size [world] sits by default within a [viewport] that
/// may be a different size -- centers it (symmetric overflow/letterboxing
/// on whichever axis differs). No scaling: the world always renders at
/// real, 1:1 pixels, identically for every player regardless of window
/// size -- only how much of it fits in view differs.
Offset worldCenteringOffset({required Size world, required Size viewport}) {
  return Offset(
    (viewport.width - world.width) / 2,
    (viewport.height - world.height) / 2,
  );
}

/// How far a player's camera may pan beyond the table's canonical [0,1]
/// area, and how far a card may be placed into that revealed margin --
/// expressed as a fraction of the table's own width/height, on every side.
/// Purely a client-side viewing/placement allowance: the host never
/// validates or clamps a card's x/y (see `TableActions`' class doc), so
/// widening what a client is willing to store here has no effect on other
/// clients beyond needing their own camera panned to see it.
const double tablePanMarginFraction = 0.5;

/// Clamps a proposed card center-Y so the whole card stays at least [margin]
/// logical pixels clear of both hand-zone bands flanking the table's own
/// Stack: the opponent's zone above and the local player's zone below.
/// Operates purely in the table Stack's own local coordinate space --
/// callers are responsible for translating to/from global/screen
/// coordinates (see table_screen.dart's `_handleDragEnd`).
///
/// The valid range extends [tablePanMarginFraction] of [tableHeight] beyond
/// each edge (matching [localPixelToCanonical]'s widened clamp) rather than
/// stopping exactly at the hand-zone bands -- a card dropped that far out is
/// only visible once the local camera has panned that way; nothing can
/// bleed into the fixed hand rows regardless, since those are cropped by a
/// `ClipRect` around the pannable Stack, not by this clamp.
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
  final tableMargin = tableHeight * tablePanMarginFraction;
  final lowerBound = margin + halfCard - tableMargin;
  final upperBound = tableHeight - margin - halfCard + tableMargin;
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
/// (e.g. from a drag-end gesture) back into the canonical fraction space
/// stored on `CardInstance`, clamped to [tablePanMarginFraction] beyond
/// [0,1] on every side (rather than exactly [0,1]) so a card can be placed
/// into the margin a panned camera can reveal, not just within whatever is
/// visible at the default (unpanned) framing.
(double, double) localPixelToCanonical({
  required double pixelX,
  required double pixelY,
  required double tableWidth,
  required double tableHeight,
  required bool isMirrored,
}) {
  final fx = (pixelX / tableWidth).clamp(
    -tablePanMarginFraction,
    1 + tablePanMarginFraction,
  );
  final fy = (pixelY / tableHeight).clamp(
    -tablePanMarginFraction,
    1 + tablePanMarginFraction,
  );
  return (isMirrored ? 1 - fx : fx, isMirrored ? 1 - fy : fy);
}
