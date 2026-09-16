import 'dart:convert';
import 'dart:io';

import 'package:flutter_deck/data/game_definition_file_ops.dart';
import 'package:flutter_deck/models/card_back_definition.dart';
import 'package:flutter_deck/models/card_definition.dart';
import 'package:flutter_deck/models/game_definition.dart';
import 'package:flutter_deck/models/game_set.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

List<int> _pngBytes({required int width, required int height}) {
  return img.encodePng(img.Image(width: width, height: height));
}

void main() {
  group('basenameOf / deriveIdFromFolderPath', () {
    test('extracts the final path segment', () {
      expect(basenameOf('C:/games/metw'), 'metw');
      expect(deriveIdFromFolderPath('C:/games/metw'), 'metw');
    });

    test('trims a trailing separator', () {
      expect(basenameOf('C:/games/metw/'), 'metw');
      expect(basenameOf(r'C:\games\metw\'), 'metw');
    });

    test('tolerates mixed separators', () {
      expect(basenameOf(r'C:/games\metw'), 'metw');
    });
  });

  group('stripExtension', () {
    test('removes the last extension only', () {
      expect(stripExtension('AChanceMeeting.jpg'), 'AChanceMeeting');
      expect(stripExtension('my.card.png'), 'my.card');
    });

    test('leaves a filename with no extension unchanged', () {
      expect(stripExtension('noext'), 'noext');
    });
  });

  group('isImageFile', () {
    test('true for known image extensions, case-insensitive', () {
      expect(isImageFile('a.jpg'), isTrue);
      expect(isImageFile('a.JPEG'), isTrue);
      expect(isImageFile('a.png'), isTrue);
      expect(isImageFile('a.WEBP'), isTrue);
    });

    test('false for non-image extensions or no extension', () {
      expect(isImageFile('a.txt'), isFalse);
      expect(isImageFile('gamedef.json'), isFalse);
      expect(isImageFile('noext'), isFalse);
    });
  });

  group('GameDefinitionFileOps', () {
    late Directory tempDir;
    late GameDefinitionFileOps fileOps;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('flutter_deck_test_fileops_');
      fileOps = GameDefinitionFileOps();
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('isSamePath is true for the same file, false for different files', () {
      final a = '${tempDir.path}${Platform.pathSeparator}one.jpg';
      final b = '${tempDir.path}${Platform.pathSeparator}two.jpg';
      expect(isSamePath(a, a), isTrue);
      expect(isSamePath(a, b), isFalse);
    });

    test('findGameDefFile finds gamedef.json case-insensitively, null when absent', () async {
      expect(await fileOps.findGameDefFile(tempDir.path), isNull);
      final gameDefFile = File('${tempDir.path}${Platform.pathSeparator}GameDef.json');
      await gameDefFile.writeAsString('{}');
      expect(await fileOps.findGameDefFile(tempDir.path), gameDefFile.path);
    });

    test('copyIntoFolder copies a file into a newly-created destination folder', () async {
      final source = File('${tempDir.path}${Platform.pathSeparator}source.jpg');
      await source.writeAsBytes([1, 2, 3]);
      final destFolder = '${tempDir.path}${Platform.pathSeparator}dest';

      await fileOps.copyIntoFolder(sourcePath: source.path, destFolderPath: destFolder, fileName: 'source.jpg');

      final destFile = File('$destFolder${Platform.pathSeparator}source.jpg');
      expect(await destFile.exists(), isTrue);
      expect(await destFile.readAsBytes(), [1, 2, 3]);
    });

    test('copyIntoFolder is a no-op when source already is the destination', () async {
      final source = File('${tempDir.path}${Platform.pathSeparator}source.jpg');
      await source.writeAsBytes([1, 2, 3]);

      await fileOps.copyIntoFolder(sourcePath: source.path, destFolderPath: tempDir.path, fileName: 'source.jpg');

      expect(await source.readAsBytes(), [1, 2, 3]);
    });

    test('copyPickedImage copies the file and returns its bare filename', () async {
      final sourceDir = await tempDir.createTemp('source_');
      final source = File('${sourceDir.path}${Platform.pathSeparator}art.png');
      await source.writeAsBytes([9]);
      final destFolder = '${tempDir.path}${Platform.pathSeparator}dest';

      final fileName = await fileOps.copyPickedImage(sourcePath: source.path, destFolderPath: destFolder);

      expect(fileName, 'art.png');
      expect(await File('$destFolder${Platform.pathSeparator}art.png').exists(), isTrue);
    });

    test('copySetImages copies only image files, ignoring stray non-images', () async {
      final sourceDir = await tempDir.createTemp('set_source_');
      await File('${sourceDir.path}${Platform.pathSeparator}a.jpg').writeAsBytes([1]);
      await File('${sourceDir.path}${Platform.pathSeparator}b.png').writeAsBytes([2]);
      await File('${sourceDir.path}${Platform.pathSeparator}notes.txt').writeAsString('nope');
      final destFolder = '${tempDir.path}${Platform.pathSeparator}core_set';

      await fileOps.copySetImages(sourceFolderPath: sourceDir.path, destFolderPath: destFolder);

      final destFiles = await Directory(destFolder).list().map((e) => e.uri.pathSegments.last).toList();
      expect(destFiles.toSet(), {'a.jpg', 'b.png'});
    });

    test('copySetImages is a no-op when source and dest are the same folder', () async {
      final setFolder = await tempDir.createTemp('same_');
      await File('${setFolder.path}${Platform.pathSeparator}a.jpg').writeAsBytes([1]);

      await fileOps.copySetImages(sourceFolderPath: setFolder.path, destFolderPath: setFolder.path);

      final files = await setFolder.list().toList();
      expect(files, hasLength(1));
    });

    test('copySetImages rotates a landscape image to portrait', () async {
      final sourceDir = await tempDir.createTemp('set_source_');
      final source = File('${sourceDir.path}${Platform.pathSeparator}wide.png');
      await source.writeAsBytes(_pngBytes(width: 100, height: 60));
      final destFolder = '${tempDir.path}${Platform.pathSeparator}core_set';

      await fileOps.copySetImages(sourceFolderPath: sourceDir.path, destFolderPath: destFolder);

      final decoded = img.decodeImage(await File('$destFolder${Platform.pathSeparator}wide.png').readAsBytes());
      expect(decoded!.width, 60);
      expect(decoded.height, 100);
    });

    test('copySetImages leaves an already-portrait image untouched', () async {
      final sourceDir = await tempDir.createTemp('set_source_');
      final source = File('${sourceDir.path}${Platform.pathSeparator}tall.png');
      await source.writeAsBytes(_pngBytes(width: 60, height: 100));
      final destFolder = '${tempDir.path}${Platform.pathSeparator}core_set';

      await fileOps.copySetImages(sourceFolderPath: sourceDir.path, destFolderPath: destFolder);

      final decoded = img.decodeImage(await File('$destFolder${Platform.pathSeparator}tall.png').readAsBytes());
      expect(decoded!.width, 60);
      expect(decoded.height, 100);
    });

    test('copyPickedImage only rotates a landscape image when correctCardOrientation is true', () async {
      final sourceDir = await tempDir.createTemp('source_');
      final source = File('${sourceDir.path}${Platform.pathSeparator}wide.png');
      await source.writeAsBytes(_pngBytes(width: 100, height: 60));
      final destFolder = '${tempDir.path}${Platform.pathSeparator}dest';

      await fileOps.copyPickedImage(sourcePath: source.path, destFolderPath: destFolder);

      final untouched = img.decodeImage(await File('$destFolder${Platform.pathSeparator}wide.png').readAsBytes());
      expect(untouched!.width, 100, reason: 'no rotation by default -- used by the card-back pickers');
      expect(untouched.height, 60);

      final destFolder2 = '${tempDir.path}${Platform.pathSeparator}dest2';
      await fileOps.copyPickedImage(
        sourcePath: source.path,
        destFolderPath: destFolder2,
        correctCardOrientation: true,
      );
      final rotated = img.decodeImage(await File('$destFolder2${Platform.pathSeparator}wide.png').readAsBytes());
      expect(rotated!.width, 60);
      expect(rotated.height, 100);
    });

    test('buildCardsFromImageFolder makes one sorted CardDefinition per image, ignoring stray files', () async {
      final sourceDir = await tempDir.createTemp('cards_source_');
      await File('${sourceDir.path}${Platform.pathSeparator}Zeta.jpg').writeAsBytes([1]);
      await File('${sourceDir.path}${Platform.pathSeparator}Alpha.png').writeAsBytes([2]);
      await File('${sourceDir.path}${Platform.pathSeparator}readme.txt').writeAsString('nope');

      final cards = await fileOps.buildCardsFromImageFolder(
        sourceFolderPath: sourceDir.path,
        setId: 'core_set',
        existingCardIds: const [],
      );

      expect(cards, hasLength(2));
      expect(cards[0].id, 'Alpha');
      expect(cards[0].cardTitle, 'Alpha');
      expect(cards[0].imagePath, 'Alpha.png');
      expect(cards[0].setId, 'core_set');
      expect(cards[1].id, 'Zeta');
      expect(cards[1].imagePath, 'Zeta.jpg');
    });

    test('buildCardsFromImageFolder appends _001 when a filename collides with an existing card id', () async {
      final sourceDir = await tempDir.createTemp('cards_source_');
      await File('${sourceDir.path}${Platform.pathSeparator}Goblin.png').writeAsBytes([1]);

      final cards = await fileOps.buildCardsFromImageFolder(
        sourceFolderPath: sourceDir.path,
        setId: 'core_set',
        existingCardIds: const ['Goblin'],
      );

      expect(cards, hasLength(1));
      expect(cards[0].id, 'Goblin_001');
      expect(cards[0].cardTitle, 'Goblin');
    });

    test('buildCardsFromImageFolder dedupes ids colliding within the same import batch', () async {
      final sourceDir = await tempDir.createTemp('cards_source_');
      await File('${sourceDir.path}${Platform.pathSeparator}Goblin.jpg').writeAsBytes([1]);
      await File('${sourceDir.path}${Platform.pathSeparator}Goblin.png').writeAsBytes([2]);

      final cards = await fileOps.buildCardsFromImageFolder(
        sourceFolderPath: sourceDir.path,
        setId: 'core_set',
        existingCardIds: const [],
      );

      expect(cards, hasLength(2));
      expect(cards.map((c) => c.id).toSet(), {'Goblin', 'Goblin_001'});
      expect(cards.every((c) => c.cardTitle == 'Goblin'), isTrue);
    });

    test('buildCardsFromImageFolder skips images whose name ends in the card-back suffix', () async {
      final sourceDir = await tempDir.createTemp('cards_source_');
      await File('${sourceDir.path}${Platform.pathSeparator}001_Krennic.png').writeAsBytes([1]);
      await File('${sourceDir.path}${Platform.pathSeparator}001_Krennic_BACK.png').writeAsBytes([2]);

      final cards = await fileOps.buildCardsFromImageFolder(
        sourceFolderPath: sourceDir.path,
        setId: 'core_set',
        existingCardIds: const [],
      );

      expect(cards, hasLength(1));
      expect(cards.single.id, '001_Krennic');
    });

    test('writeGameDefinition writes gamedef.json with bare filenames, not absolute paths', () async {
      final folderPath = '${tempDir.path}${Platform.pathSeparator}mygame';
      const game = GameDefinition(
        id: 'mygame',
        name: 'My Game',
        sets: [GameSet(id: 'core_set', name: 'Core Set')],
        cards: [
          CardDefinition(id: 'a', cardTitle: 'A', imagePath: 'a.jpg', setId: 'core_set'),
        ],
        cardBacks: [CardBackDefinition(id: 'default', name: 'Default', imagePath: 'cardback.jpg')],
      );

      await fileOps.writeGameDefinition(folderPath: folderPath, game: game);

      final written = File('$folderPath${Platform.pathSeparator}gamedef.json');
      expect(await written.exists(), isTrue);
      final decoded = jsonDecode(await written.readAsString()) as Map<String, dynamic>;
      final decodedCardBacks = decoded['cardBacks'] as List;
      expect((decodedCardBacks.single as Map)['imagePath'], 'cardback.jpg');
      final sets = decoded['sets'] as List;
      final cards = (sets.single as Map)['cards'] as List;
      expect((cards.single as Map)['imagePath'], 'a.jpg');

      // Round-trip through GameDefinition.fromJson confirms it's still the
      // bare, unresolved shape GameLoader expects to find on disk.
      final roundTripped = GameDefinition.fromJson(decoded);
      expect(roundTripped.cards.single.imagePath, 'a.jpg');
      expect(roundTripped.cardBacks.single.imagePath, 'cardback.jpg');
    });
  });
}
