import 'dart:io';

import 'package:flutter_deck/data/image_path_resolver.dart';
import 'package:flutter_deck/models/card_definition.dart';
import 'package:flutter_deck/models/game_definition.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolveBareImagePath joins folder and bare filename for a card with no set', () {
    final resolved = resolveBareImagePath(
      folderPath: 'C:/games/metw',
      bareImagePath: 'one.jpg',
    );
    expect(resolved, 'C:/games/metw${Platform.pathSeparator}one.jpg');
  });

  test('resolveBareImagePath joins folder, setId, and bare filename for a set card', () {
    final resolved = resolveBareImagePath(
      folderPath: 'C:/games/metw',
      bareImagePath: 'one.jpg',
      setId: 'core_set',
    );
    expect(
      resolved,
      'C:/games/metw${Platform.pathSeparator}core_set${Platform.pathSeparator}one.jpg',
    );
  });

  test(
    'resolvedImagePathForDisplay returns null when bareImagePath is null',
    () {
      expect(
        resolvedImagePathForDisplay('C:/games/metw', bareImagePath: null),
        isNull,
      );
    },
  );

  test('resolvedImagePathForDisplay matches resolveBareImagePath when bareImagePath is set', () {
    expect(
      resolvedImagePathForDisplay(
        'C:/games/metw',
        bareImagePath: 'one.jpg',
        setId: 'core_set',
      ),
      'C:/games/metw${Platform.pathSeparator}core_set${Platform.pathSeparator}one.jpg',
    );
  });

  test(
    'mergeLocalImagePaths substitutes local imagePath matched by card id',
    () {
      final remote = GameDefinition(
        id: 'g1',
        name: 'Game',
        cards: [
          CardDefinition(
            id: 'c1',
            cardTitle: 'Card One',
            imagePath: 'C:/host/c1.jpg',
          ),
        ],
      );
      final local = GameDefinition(
        id: 'g1',
        name: 'Game',
        cards: [
          CardDefinition(
            id: 'c1',
            cardTitle: 'Card One',
            imagePath: 'C:/client/c1.jpg',
          ),
        ],
      );
      final merged = mergeLocalImagePaths(remote: remote, local: local);
      expect(merged.cards.single.imagePath, 'C:/client/c1.jpg');
      expect(merged.cards.single.cardTitle, 'Card One');
    },
  );

  test(
    'mergeLocalImagePaths clears imagePath for a card missing from local',
    () {
      final remote = GameDefinition(
        id: 'g1',
        name: 'Game',
        cards: [
          CardDefinition(
            id: 'c1',
            cardTitle: 'Card One',
            imagePath: 'C:/host/c1.jpg',
          ),
        ],
      );
      final local = GameDefinition(id: 'g1', name: 'Game', cards: const []);
      final merged = mergeLocalImagePaths(remote: remote, local: local);
      expect(merged.cards.single.imagePath, isNull);
    },
  );

  test("mergeLocalImagePaths uses local's cardBackImagePath, not remote's", () {
    final remote = GameDefinition(
      id: 'g1',
      name: 'Game',
      cards: const [],
      cardBackImagePath: 'C:/host/back.jpg',
    );
    final local = GameDefinition(
      id: 'g1',
      name: 'Game',
      cards: const [],
      cardBackImagePath: 'C:/client/back.jpg',
    );
    final merged = mergeLocalImagePaths(remote: remote, local: local);
    expect(merged.cardBackImagePath, 'C:/client/back.jpg');
  });
}
