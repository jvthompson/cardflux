import 'dart:io';

import 'package:flutter_deck/data/game_log_file_ops.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GameLogFileOps', () {
    late Directory tempDir;
    late GameLogFileOps fileOps;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('flutter_deck_test_gamelog_');
      fileOps = GameLogFileOps();
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    test('writeLog creates the gamelogs folder and writes the file', () async {
      await fileOps.writeLog(
        gameFolderPath: tempDir.path,
        fileName: 'gamelog_2026-01-01_120000.txt',
        contents: '[00:00:05] Host drew a card.',
      );

      final file = File('${tempDir.path}${Platform.pathSeparator}gamelogs${Platform.pathSeparator}gamelog_2026-01-01_120000.txt');
      expect(await file.exists(), isTrue);
      expect(await file.readAsString(), '[00:00:05] Host drew a card.');
    });

    test('writeLog does not clobber a differently-named file already there', () async {
      await fileOps.writeLog(gameFolderPath: tempDir.path, fileName: 'a.txt', contents: 'first');
      await fileOps.writeLog(gameFolderPath: tempDir.path, fileName: 'b.txt', contents: 'second');

      final logsDir = Directory('${tempDir.path}${Platform.pathSeparator}gamelogs');
      final names = (await logsDir.list().toList()).map((e) => e.uri.pathSegments.last).toSet();
      expect(names, {'a.txt', 'b.txt'});
    });
  });
}
