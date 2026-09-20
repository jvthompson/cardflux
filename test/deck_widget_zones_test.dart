import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_deck/game/deck_widget_zones.dart';

void main() {
  group('buildDeckWidgetZoneId / parseDeckWidgetZoneId', () {
    test('round-trips widgetInstanceId and realZoneId', () {
      final id = buildDeckWidgetZoneId(widgetInstanceId: 'w1', realZoneId: 'main_deck');
      expect(isDeckWidgetZoneId(id), isTrue);
      final parsed = parseDeckWidgetZoneId(id);
      expect(parsed, isNotNull);
      expect(parsed!.widgetInstanceId, 'w1');
      expect(parsed.realZoneId, 'main_deck');
    });

    test('a real zone id is not recognized as a synthetic one', () {
      expect(isDeckWidgetZoneId('main_deck'), isFalse);
      expect(parseDeckWidgetZoneId('main_deck'), isNull);
    });

    test('a real zone id containing a colon still parses correctly', () {
      final id = buildDeckWidgetZoneId(widgetInstanceId: 'w1', realZoneId: 'weird:zone:id');
      final parsed = parseDeckWidgetZoneId(id);
      expect(parsed, isNotNull);
      expect(parsed!.widgetInstanceId, 'w1');
      expect(parsed.realZoneId, 'weird:zone:id');
    });

    test('malformed strings return null', () {
      expect(parseDeckWidgetZoneId(''), isNull);
      expect(parseDeckWidgetZoneId('deckWidget:'), isNull);
      expect(parseDeckWidgetZoneId('deckWidget:onlyOnePart'), isNull);
      expect(parseDeckWidgetZoneId('deckWidget::main_deck'), isNull);
      expect(parseDeckWidgetZoneId('deckWidget:w1:'), isNull);
    });
  });
}
