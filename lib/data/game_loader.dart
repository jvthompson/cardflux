import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import '../models/card_definition.dart';
import '../models/game_definition.dart';

const String standardDeckAssetPath = 'assets/games/standard_52.json';

/// Loads [GameDefinition]s from either the bundled default game or a
/// user-chosen folder of custom game JSON files.
class GameLoader {
  Future<GameDefinition> loadStandardDeck() async {
    final raw = await rootBundle.loadString(standardDeckAssetPath);
    return GameDefinition.fromJson(jsonDecode(raw) as Map<String, dynamic>);
  }

  /// Scans [folderPath] for `*.json` files, parsing each as one
  /// [GameDefinition]. Files that fail to parse are skipped. Each card's
  /// [CardDefinition.imagePath] (authored as a bare filename alongside the
  /// game's JSON) is rewritten to an absolute path so renderers can load it
  /// directly without needing to know which folder a game came from.
  Future<List<GameDefinition>> loadFromFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return const [];

    final games = <GameDefinition>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) continue;
      try {
        final raw = await entity.readAsString();
        final parsed = GameDefinition.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        games.add(_resolveImagePaths(parsed, folderPath));
      } catch (_) {
        // Skip files that aren't valid game definitions.
      }
    }
    return games;
  }

  GameDefinition _resolveImagePaths(GameDefinition game, String folderPath) {
    final cards = game.cards.map((c) {
      final imagePath = c.imagePath;
      if (imagePath == null) return c;
      return CardDefinition(
        id: c.id,
        cardTitle: c.cardTitle,
        colorHex: c.colorHex,
        suit: c.suit,
        rank: c.rank,
        imagePath: '$folderPath${Platform.pathSeparator}$imagePath',
        extraFields: c.extraFields,
      );
    }).toList();
    return GameDefinition(id: game.id, name: game.name, cards: cards);
  }
}
