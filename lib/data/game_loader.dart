import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

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
  /// [GameDefinition]. Files that fail to parse are skipped.
  Future<List<GameDefinition>> loadFromFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return const [];

    final games = <GameDefinition>[];
    await for (final entity in dir.list()) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.json')) continue;
      try {
        final raw = await entity.readAsString();
        games.add(GameDefinition.fromJson(jsonDecode(raw) as Map<String, dynamic>));
      } catch (_) {
        // Skip files that aren't valid game definitions.
      }
    }
    return games;
  }
}
