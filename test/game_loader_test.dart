import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_deck/data/game_loader.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('loadStandardDeck loads all 52 cards', () async {
    final game = await GameLoader().loadStandardDeck();
    expect(game.id, 'standard_52');
    expect(game.cards, hasLength(52));

    final suits = game.cards.map((c) => c.suit).toSet();
    expect(suits, {'hearts', 'diamonds', 'clubs', 'spades'});

    final ids = game.cards.map((c) => c.id).toSet();
    expect(ids, hasLength(52), reason: 'all card ids should be unique');
  });

  test('loadFromFolder parses every json file in a directory', () async {
    final tempDir = await Directory.systemTemp.createTemp('flutter_deck_test_games_');
    addTearDown(() => tempDir.delete(recursive: true));

    final gameFile = File('${tempDir.path}/my_game.json');
    await gameFile.writeAsString(jsonEncode({
      'id': 'my_game',
      'name': 'My Custom Game',
      'cards': [
        {'id': 'c1', 'cardTitle': 'One', 'colorHex': '#000000'},
      ],
    }));
    // A non-JSON file in the same folder should be ignored, not error.
    await File('${tempDir.path}/notes.txt').writeAsString('not a game');

    final games = await GameLoader().loadFromFolder(tempDir.path);
    expect(games, hasLength(1));
    expect(games.single.id, 'my_game');
    expect(games.single.cards.single.cardTitle, 'One');
  });

  test('loadFromFolder returns empty list for a missing folder', () async {
    final games = await GameLoader().loadFromFolder('C:/definitely/not/a/real/path/xyz');
    expect(games, isEmpty);
  });
}
