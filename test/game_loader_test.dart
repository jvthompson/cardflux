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

  test('loadFromFolder finds the gamedef.json file in a directory, ignoring stray files', () async {
    final tempDir = await Directory.systemTemp.createTemp('flutter_deck_test_games_');
    addTearDown(() => tempDir.delete(recursive: true));

    final gameFile = File('${tempDir.path}/gamedef.json');
    await gameFile.writeAsString(jsonEncode({
      'id': 'my_game',
      'name': 'My Custom Game',
      'cards': [
        {'id': 'c1', 'cardTitle': 'One', 'colorHex': '#000000'},
      ],
    }));
    // A non-JSON file, and a stray .json file that isn't named gamedef.json,
    // should both be ignored, not error and not loaded as a second game.
    await File('${tempDir.path}/notes.txt').writeAsString('not a game');
    await File('${tempDir.path}/My Deck.json').writeAsString(jsonEncode({
      'id': 'other_game',
      'name': 'Other',
      'cards': [
        {'id': 'x1', 'cardTitle': 'X', 'colorHex': '#000000'},
      ],
    }));

    final games = await GameLoader().loadFromFolder(tempDir.path);
    expect(games, hasLength(1));
    expect(games.single.id, 'my_game');
    expect(games.single.cards.single.cardTitle, 'One');
  });

  test('loadFromFolder resolves a card imagePath to an absolute path alongside the JSON', () async {
    final tempDir = await Directory.systemTemp.createTemp('flutter_deck_test_games_');
    addTearDown(() => tempDir.delete(recursive: true));

    final gameFile = File('${tempDir.path}/gamedef.json');
    await gameFile.writeAsString(jsonEncode({
      'id': 'my_game',
      'name': 'My Custom Game',
      'cards': [
        {'id': 'c1', 'cardTitle': 'One', 'imagePath': 'one.jpg'},
      ],
    }));

    final games = await GameLoader().loadFromFolder(tempDir.path);
    final resolved = games.single.cards.single.imagePath;
    expect(resolved, '${tempDir.path}${Platform.pathSeparator}one.jpg');
  });

  test('loadFromFolder preserves zones through image-path resolution', () async {
    final tempDir = await Directory.systemTemp.createTemp('flutter_deck_test_games_');
    addTearDown(() => tempDir.delete(recursive: true));

    final gameFile = File('${tempDir.path}/gamedef.json');
    await gameFile.writeAsString(jsonEncode({
      'id': 'my_game',
      'name': 'My Custom Game',
      'cards': [
        {'id': 'c1', 'cardTitle': 'One', 'colorHex': '#000000'},
      ],
      'zones': [
        {'id': 'draw_deck', 'name': 'Draw Deck', 'dealsBuiltDeck': true},
        {'id': 'discard_pile', 'name': 'Discard Pile'},
      ],
    }));

    final games = await GameLoader().loadFromFolder(tempDir.path);
    expect(games.single.zones, hasLength(2));
    expect(games.single.needsDeckBuilding, isTrue);
  });

  test('loadFromFolder preserves tagGroups and per-card types', () async {
    final tempDir = await Directory.systemTemp.createTemp('flutter_deck_test_games_');
    addTearDown(() => tempDir.delete(recursive: true));

    final gameFile = File('${tempDir.path}/gamedef.json');
    await gameFile.writeAsString(jsonEncode({
      'id': 'my_game',
      'name': 'My Custom Game',
      'tagGroups': [
        {
          'id': 'kinds',
          'name': 'Kind',
          'tags': ['Character', 'Item'],
        },
      ],
      'cards': [
        {'id': 'c1', 'cardTitle': 'One', 'imagePath': 'one.jpg', 'types': ['Character']},
      ],
    }));

    final games = await GameLoader().loadFromFolder(tempDir.path);
    final game = games.single;
    expect(game.tagGroups, hasLength(1));
    expect(game.tagGroups.single.id, 'kinds');
    expect(game.tagGroups.single.name, 'Kind');
    expect(game.tagGroups.single.tags, ['Character', 'Item']);
    expect(game.cards.single.types, ['Character']);
    // imagePath resolution (the reason this class exists) should still work
    // alongside the new fields.
    expect(game.cards.single.imagePath, '${tempDir.path}${Platform.pathSeparator}one.jpg');
  });

  test('loadFromFolder returns empty list for a missing folder', () async {
    final games = await GameLoader().loadFromFolder('C:/definitely/not/a/real/path/xyz');
    expect(games, isEmpty);
  });

  test('loadFromFolder parses a multi-set gamedef.json, tagging each card with its set id', () async {
    final tempDir = await Directory.systemTemp.createTemp('flutter_deck_test_games_');
    addTearDown(() => tempDir.delete(recursive: true));

    final gameFile = File('${tempDir.path}/gamedef.json');
    await gameFile.writeAsString(jsonEncode({
      'id': 'g1',
      'name': 'G',
      'sets': [
        {
          'id': 'set_a',
          'name': 'Set A',
          'cards': [
            {'id': 'c1', 'cardTitle': 'One'},
          ],
        },
        {
          'id': 'set_b',
          'name': 'Set B',
          'cards': [
            {'id': 'c2', 'cardTitle': 'Two'},
          ],
        },
      ],
    }));

    final games = await GameLoader().loadFromFolder(tempDir.path);
    final game = games.single;
    expect(game.sets.map((s) => s.id), ['set_a', 'set_b']);
    expect(game.sets.map((s) => s.name), ['Set A', 'Set B']);
    expect(game.cards, hasLength(2));
    expect(game.cards[0].setId, 'set_a');
    expect(game.cards[1].setId, 'set_b');
  });

  test('loadFromFolder leaves sets empty and setId null for the flat cards schema', () async {
    final tempDir = await Directory.systemTemp.createTemp('flutter_deck_test_games_');
    addTearDown(() => tempDir.delete(recursive: true));

    final gameFile = File('${tempDir.path}/gamedef.json');
    await gameFile.writeAsString(jsonEncode({
      'id': 'g1',
      'name': 'G',
      'cards': [
        {'id': 'c1', 'cardTitle': 'One'},
      ],
    }));

    final games = await GameLoader().loadFromFolder(tempDir.path);
    final game = games.single;
    expect(game.sets, isEmpty);
    expect(game.cards.single.setId, isNull);
  });

  test('loadFromFolder resolves a set card\'s imagePath inside its own set subfolder', () async {
    final tempDir = await Directory.systemTemp.createTemp('flutter_deck_test_games_');
    addTearDown(() => tempDir.delete(recursive: true));

    final gameFile = File('${tempDir.path}/gamedef.json');
    await gameFile.writeAsString(jsonEncode({
      'id': 'g1',
      'name': 'G',
      'sets': [
        {
          'id': 'core_set',
          'name': 'Core Set',
          'cards': [
            {'id': 'c1', 'cardTitle': 'One', 'imagePath': 'one.jpg'},
          ],
        },
      ],
    }));

    final games = await GameLoader().loadFromFolder(tempDir.path);
    final card = games.single.cards.single;
    expect(card.setId, 'core_set');
    expect(card.imagePath, '${tempDir.path}${Platform.pathSeparator}core_set${Platform.pathSeparator}one.jpg');
  });
}
