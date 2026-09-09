import 'dart:io';

import 'package:flutter_deck/data/image_path_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolveBareImagePath joins folder and bare filename for a card with no set', () {
    final resolved = resolveBareImagePath(folderPath: 'C:/games/metw', bareImagePath: 'one.jpg');
    expect(resolved, 'C:/games/metw${Platform.pathSeparator}one.jpg');
  });

  test('resolveBareImagePath joins folder, setId, and bare filename for a set card', () {
    final resolved = resolveBareImagePath(folderPath: 'C:/games/metw', bareImagePath: 'one.jpg', setId: 'core_set');
    expect(resolved, 'C:/games/metw${Platform.pathSeparator}core_set${Platform.pathSeparator}one.jpg');
  });

  test('resolvedImagePathForDisplay returns null when bareImagePath is null', () {
    expect(resolvedImagePathForDisplay('C:/games/metw', bareImagePath: null), isNull);
  });

  test('resolvedImagePathForDisplay matches resolveBareImagePath when bareImagePath is set', () {
    expect(
      resolvedImagePathForDisplay('C:/games/metw', bareImagePath: 'one.jpg', setId: 'core_set'),
      'C:/games/metw${Platform.pathSeparator}core_set${Platform.pathSeparator}one.jpg',
    );
  });
}
