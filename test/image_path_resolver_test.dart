import 'dart:io';

import 'package:flutter_deck/data/image_path_resolver.dart';
import 'package:flutter_deck/models/card_back_definition.dart';
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

  test("mergeLocalImagePaths uses local's cardBacks, not remote's", () {
    final remote = GameDefinition(
      id: 'g1',
      name: 'Game',
      cards: const [],
      cardBacks: const [CardBackDefinition(id: 'default', name: 'Default', imagePath: 'C:/host/back.jpg')],
    );
    final local = GameDefinition(
      id: 'g1',
      name: 'Game',
      cards: const [],
      cardBacks: const [CardBackDefinition(id: 'default', name: 'Default', imagePath: 'C:/client/back.jpg')],
    );
    final merged = mergeLocalImagePaths(remote: remote, local: local);
    expect(merged.cardBacks.single.imagePath, 'C:/client/back.jpg');
  });

  group('resolveCardBackImagePath', () {
    test('returns null/not-missing when cardBacks is empty and no unique mode', () {
      final resolved = resolveCardBackImagePath(cardBacks: const [], card: null);
      expect(resolved.path, isNull);
      expect(resolved.missing, isFalse);
    });

    test('defaults to the first entry when the card has no cardBackId', () {
      const card = CardDefinition(id: 'c1', cardTitle: 'Card One');
      const cardBacks = [
        CardBackDefinition(id: 'b1', name: 'Default', imagePath: 'default.png'),
        CardBackDefinition(id: 'b2', name: 'Alt', imagePath: 'alt.png'),
      ];
      final resolved = resolveCardBackImagePath(cardBacks: cardBacks, card: card);
      expect(resolved.path, 'default.png');
      expect(resolved.missing, isFalse);
    });

    test('resolves a named alternate by id', () {
      const card = CardDefinition(id: 'c1', cardTitle: 'Card One', cardBackId: 'b2');
      const cardBacks = [
        CardBackDefinition(id: 'b1', name: 'Default', imagePath: 'default.png'),
        CardBackDefinition(id: 'b2', name: 'Alt', imagePath: 'alt.png'),
      ];
      final resolved = resolveCardBackImagePath(cardBacks: cardBacks, card: card);
      expect(resolved.path, 'alt.png');
      expect(resolved.missing, isFalse);
    });

    test('resolves a named alternate\'s own orientation, independent of the card\'s front', () {
      const card = CardDefinition(
        id: 'c1',
        cardTitle: 'Card One',
        orientation: CardOrientation.portrait,
        cardBackId: 'b2',
      );
      const cardBacks = [
        CardBackDefinition(id: 'b1', name: 'Default', imagePath: 'default.png'),
        CardBackDefinition(id: 'b2', name: 'Alt', imagePath: 'alt.png', orientation: CardOrientation.left),
      ];
      final resolved = resolveCardBackImagePath(cardBacks: cardBacks, card: card);
      expect(resolved.orientation, CardOrientation.left);
    });

    test('orientation defaults to portrait when cardBacks is empty', () {
      final resolved = resolveCardBackImagePath(cardBacks: const [], card: null);
      expect(resolved.orientation, CardOrientation.portrait);
    });

    test('falls back to the default when cardBackId no longer exists', () {
      const card = CardDefinition(id: 'c1', cardTitle: 'Card One', cardBackId: 'deleted');
      const cardBacks = [CardBackDefinition(id: 'b1', name: 'Default', imagePath: 'default.png')];
      final resolved = resolveCardBackImagePath(cardBacks: cardBacks, card: card);
      expect(resolved.path, 'default.png');
      expect(resolved.missing, isFalse);
    });

    test('unique mode finds a matching _BACK file next to the card image', () async {
      final tempDir = await Directory.systemTemp.createTemp('flutter_deck_test_cardback_');
      addTearDown(() => tempDir.delete(recursive: true));
      final frontPath = '${tempDir.path}${Platform.pathSeparator}001_Krennic.png';
      final backPath = '${tempDir.path}${Platform.pathSeparator}001_Krennic_BACK.png';
      await File(backPath).writeAsBytes([1]);
      final card = CardDefinition(
        id: 'c1',
        cardTitle: 'Krennic',
        imagePath: frontPath,
        cardBackId: uniqueCardBackId,
      );
      final resolved = resolveCardBackImagePath(cardBacks: const [], card: card);
      expect(resolved.path, backPath);
      expect(resolved.missing, isFalse);
    });

    test('unique mode reports missing when no matching _BACK file exists', () {
      const card = CardDefinition(
        id: 'c1',
        cardTitle: 'Krennic',
        imagePath: 'C:/game/001_Krennic.png',
        cardBackId: uniqueCardBackId,
      );
      final resolved = resolveCardBackImagePath(cardBacks: const [], card: card);
      expect(resolved.path, isNull);
      expect(resolved.missing, isTrue);
    });

    test('unique mode reports missing when the card has no image of its own', () {
      const card = CardDefinition(id: 'c1', cardTitle: 'Krennic', cardBackId: uniqueCardBackId);
      final resolved = resolveCardBackImagePath(cardBacks: const [], card: card);
      expect(resolved.path, isNull);
      expect(resolved.missing, isTrue);
    });

    test('unique mode uses the card\'s own uniqueBackOrientation, even when missing', () {
      const missingCard = CardDefinition(
        id: 'c1',
        cardTitle: 'Krennic',
        imagePath: 'C:/game/001_Krennic.png',
        cardBackId: uniqueCardBackId,
        uniqueBackOrientation: CardOrientation.right,
      );
      final resolved = resolveCardBackImagePath(cardBacks: const [], card: missingCard);
      expect(resolved.missing, isTrue);
      expect(resolved.orientation, CardOrientation.right);
    });
  });

  group('resolvePackGeneratorImagePath', () {
    test('returns the path when packgen.png exists in the folder', () async {
      final tempDir = await Directory.systemTemp.createTemp('flutter_deck_test_packgen_');
      addTearDown(() => tempDir.delete(recursive: true));
      final packgenPath = '${tempDir.path}${Platform.pathSeparator}packgen.png';
      await File(packgenPath).writeAsBytes([1]);
      expect(resolvePackGeneratorImagePath(tempDir.path), packgenPath);
    });

    test('returns null when packgen.png does not exist', () async {
      final tempDir = await Directory.systemTemp.createTemp('flutter_deck_test_packgen_');
      addTearDown(() => tempDir.delete(recursive: true));
      expect(resolvePackGeneratorImagePath(tempDir.path), isNull);
    });

    test('returns null when folderPath is null', () {
      expect(resolvePackGeneratorImagePath(null), isNull);
    });
  });
}
