import 'dart:convert';
import 'dart:io';

import 'package:flutter_deck/data/game_definition_file_ops.dart';
import 'package:flutter_deck/models/card_definition.dart';
import 'package:flutter_deck/models/game_definition.dart';
import 'package:flutter_deck/models/game_set.dart';
import 'package:flutter_test/flutter_test.dart';

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

    test('buildCardsFromImageFolder makes one sorted CardDefinition per image, ignoring stray files', () async {
      final sourceDir = await tempDir.createTemp('cards_source_');
      await File('${sourceDir.path}${Platform.pathSeparator}Zeta.jpg').writeAsBytes([1]);
      await File('${sourceDir.path}${Platform.pathSeparator}Alpha.png').writeAsBytes([2]);
      await File('${sourceDir.path}${Platform.pathSeparator}readme.txt').writeAsString('nope');

      final cards = await fileOps.buildCardsFromImageFolder(sourceFolderPath: sourceDir.path, setId: 'core_set');

      expect(cards, hasLength(2));
      expect(cards[0].id, 'Alpha');
      expect(cards[0].cardTitle, 'Alpha');
      expect(cards[0].imagePath, 'Alpha.png');
      expect(cards[0].setId, 'core_set');
      expect(cards[1].id, 'Zeta');
      expect(cards[1].imagePath, 'Zeta.jpg');
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
        cardBackImagePath: 'cardback.jpg',
      );

      await fileOps.writeGameDefinition(folderPath: folderPath, game: game);

      final written = File('$folderPath${Platform.pathSeparator}gamedef.json');
      expect(await written.exists(), isTrue);
      final decoded = jsonDecode(await written.readAsString()) as Map<String, dynamic>;
      expect(decoded['cardBackImagePath'], 'cardback.jpg');
      final sets = decoded['sets'] as List;
      final cards = (sets.single as Map)['cards'] as List;
      expect((cards.single as Map)['imagePath'], 'a.jpg');

      // Round-trip through GameDefinition.fromJson confirms it's still the
      // bare, unresolved shape GameLoader expects to find on disk.
      final roundTripped = GameDefinition.fromJson(decoded);
      expect(roundTripped.cards.single.imagePath, 'a.jpg');
      expect(roundTripped.cardBackImagePath, 'cardback.jpg');
    });
  });
}
