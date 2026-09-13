import '../models/zone_definition.dart';
import 'geometry_utils.dart';

/// Canonical [0,1] position for every shared zone in [zones] (non-shared
/// zones are ignored), keyed by zone id. A zone with a nonzero
/// `ZoneDefinition.offsetX`/`offsetY` is placed that many pixels from the
/// table's exact center (`(0.5, 0.5)`, converted via [kWorldSize]) and
/// excluded from the automatic layout entirely; every other zone is spread
/// horizontally through dead center, in a row, so 1 zone lands dead center
/// and N zones form an evenly-spaced row centered on it -- as if the offset
/// zones didn't exist.
///
/// Pure function of [zones] alone (no dealt state), so every caller that
/// needs a shared zone's reserved table position -- `GameSession.dealFromZones`
/// (the initial deal), `GameSession.returnToZone` (anchoring the first card
/// landed in a previously-empty shared zone to the same slot), and
/// `TableScreen` (an empty shared zone's placeholder) -- always agrees,
/// without that position ever needing to be stored in `TableState` itself.
Map<String, (double, double)> sharedZonePositions(
  List<ZoneDefinition> zones,
) {
  const centerX = 0.5;
  const centerY = 0.5;
  // 0.05 of the table width (128px on the current 2560px-wide table) --
  // close enough that adjacent piles (each ~94px wide, cardWidth +
  // pileWidgetExtra) read as a snug row with a small gap, not spread out.
  const spacing = 0.05;
  final positions = <String, (double, double)>{};
  final autoZones = <ZoneDefinition>[];
  for (final zone in zones) {
    if (!zone.shared) continue;
    if (zone.offsetX != 0 || zone.offsetY != 0) {
      positions[zone.id] = (
        centerX + zone.offsetX / kWorldSize.width,
        centerY + zone.offsetY / kWorldSize.height,
      );
    } else {
      autoZones.add(zone);
    }
  }
  for (var i = 0; i < autoZones.length; i++) {
    final x = autoZones.length <= 1
        ? centerX
        : centerX + (i - (autoZones.length - 1) / 2) * spacing;
    positions[autoZones[i].id] = (x, centerY);
  }
  return positions;
}
