import 'dart:io';

import 'package:flutter_deck/data/save_game_file_ops.dart';
import 'package:flutter_deck/models/card_instance.dart';
import 'package:flutter_deck/models/player.dart';
import 'package:flutter_deck/models/saved_game.dart';
import 'package:flutter_deck/models/table_state.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SaveGameFileOps', () {
    late Directory tempDir;
    late SaveGameFileOps fileOps;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('flutter_deck_test_savegame_');
      fileOps = SaveGameFileOps();
    });

    tearDown(() async {
      await tempDir.delete(recursive: true);
    });

    SavedGame sampleSave({int playerCount = 2}) {
      return SavedGame(
        savedAt: DateTime.utc(2026, 1, 1),
        state: TableState(
          gameId: 'g1',
          players: [
            for (var i = 0; i < playerCount; i++)
              PlayerInfo(id: 'p$i', name: 'Player $i', role: PlayerRole.host, color: 0xFFD32F2F),
          ],
          cards: const [],
          revision: 0,
        ),
      );
    }

    test('listSaveGames returns const [] when the savegames folder does not exist', () async {
      expect(await fileOps.listSaveGames(tempDir.path), isEmpty);
    });

    test('writeSaveGame then listSaveGames round-trips displayName/savedAt/playerCount', () async {
      await fileOps.writeSaveGame(gameFolderPath: tempDir.path, name: 'my-save', save: sampleSave(playerCount: 3));

      final entries = await fileOps.listSaveGames(tempDir.path);
      expect(entries, hasLength(1));
      expect(entries.single.displayName, 'my-save');
      expect(entries.single.playerCount, 3);
      expect(entries.single.savedAt, DateTime.utc(2026, 1, 1));
    });

    test('saveExists reflects whether the named file is there', () async {
      expect(await fileOps.saveExists(tempDir.path, 'my-save'), isFalse);
      await fileOps.writeSaveGame(gameFolderPath: tempDir.path, name: 'my-save', save: sampleSave());
      expect(await fileOps.saveExists(tempDir.path, 'my-save'), isTrue);
    });

    test('readSaveGame reads back a full CardInstance correctly', () async {
      final save = SavedGame(
        savedAt: DateTime.utc(2026, 1, 1),
        state: TableState(
          gameId: 'g1',
          players: const [PlayerInfo(id: 'p1', name: 'Alice', role: PlayerRole.host, color: 0xFFD32F2F)],
          cards: [
            CardInstance(
              instanceId: 'i1',
              definitionId: 'card_a',
              x: 0.5,
              y: 0.5,
              zIndex: 0,
              faceUp: true,
              zone: CardZone.hand,
              ownerId: 'p1',
            ),
          ],
          revision: 5,
        ),
      );
      await fileOps.writeSaveGame(gameFolderPath: tempDir.path, name: 'full', save: save);
      final entries = await fileOps.listSaveGames(tempDir.path);
      final read = await fileOps.readSaveGame(entries.single.filePath);
      expect(read.state.cards.single.ownerId, 'p1');
      expect(read.state.revision, 5);
    });

    test('listSaveGames silently skips a corrupt/foreign JSON file', () async {
      final savesDir = Directory('${tempDir.path}${Platform.pathSeparator}savegames');
      await savesDir.create(recursive: true);
      await File('${savesDir.path}${Platform.pathSeparator}corrupt.json').writeAsString('not valid json{{{');
      await File('${savesDir.path}${Platform.pathSeparator}foreign.json').writeAsString('{"unrelated": true}');
      await fileOps.writeSaveGame(gameFolderPath: tempDir.path, name: 'good', save: sampleSave());

      final entries = await fileOps.listSaveGames(tempDir.path);
      expect(entries.map((e) => e.displayName), ['good']);
    });

    test('listSaveGames returns newest-first', () async {
      await fileOps.writeSaveGame(
        gameFolderPath: tempDir.path,
        name: 'older',
        save: SavedGame(
          savedAt: DateTime.utc(2026, 1, 1),
          state: const TableState(gameId: 'g1', players: [], cards: [], revision: 0),
        ),
      );
      await fileOps.writeSaveGame(
        gameFolderPath: tempDir.path,
        name: 'newer',
        save: SavedGame(
          savedAt: DateTime.utc(2026, 6, 1),
          state: const TableState(gameId: 'g1', players: [], cards: [], revision: 0),
        ),
      );

      final entries = await fileOps.listSaveGames(tempDir.path);
      expect(entries.map((e) => e.displayName), ['newer', 'older']);
    });
  });
}
