const String _prefix = 'deckWidget:';

/// The synthetic `CardInstance.zoneId` a `DeckWidget` instance's sub-zone for
/// [realZoneId] (one of `GameDefinition.deckBuildingZones`) uses -- never a
/// member of `GameDefinition.zones` itself, so it can never collide with a
/// player's real, live gameplay zone of the same id, and (see
/// `state_filter.dart`'s `visibleZoneIds`) can never become visible to
/// anyone but the widget's own owner. See [parseDeckWidgetZoneId] for the
/// inverse.
String buildDeckWidgetZoneId({required String widgetInstanceId, required String realZoneId}) =>
    '$_prefix$widgetInstanceId:$realZoneId';

/// True if [zoneId] was built by [buildDeckWidgetZoneId] (as opposed to an
/// ordinary `GameDefinition.zones` id).
bool isDeckWidgetZoneId(String zoneId) => zoneId.startsWith(_prefix);

/// The parsed halves of a synthetic id built by [buildDeckWidgetZoneId].
class DeckWidgetZoneId {
  const DeckWidgetZoneId({required this.widgetInstanceId, required this.realZoneId});

  final String widgetInstanceId;
  final String realZoneId;
}

/// Parses [zoneId] as a `DeckWidget` synthetic sub-zone id, or null if it
/// isn't one (an ordinary `GameDefinition.zones` id, or malformed) --
/// callers should always fall back to treating it as an ordinary zone id in
/// that case. Splits on the *first* `:` after the prefix only: a widget
/// instance id is always a uuid (never contains `:`), so this stays correct
/// even if a game author's own [realZoneId] happens to contain one.
DeckWidgetZoneId? parseDeckWidgetZoneId(String zoneId) {
  if (!zoneId.startsWith(_prefix)) return null;
  final rest = zoneId.substring(_prefix.length);
  final sep = rest.indexOf(':');
  if (sep <= 0) return null;
  final realZoneId = rest.substring(sep + 1);
  if (realZoneId.isEmpty) return null;
  return DeckWidgetZoneId(widgetInstanceId: rest.substring(0, sep), realZoneId: realZoneId);
}
