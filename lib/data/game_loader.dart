import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart' show rootBundle;

import '../models/card_definition.dart';
import '../models/game_definition.dart';
import '../models/standard_deck.dart';
import 'image_path_resolver.dart';

const String standardDeckAssetPath = 'assets/games/standard_52/standard_52.json';

/// Loads [GameDefinition]s from either the bundled default deck or a
/// user-chosen games directory (see `GamesDirectorySettings`) containing one
/// subfolder per game.
class GameLoader {
  Future<GameDefinition> loadStandardDeck() async {
    final raw = await rootBundle.loadString(standardDeckAssetPath);
    final parsed = GameDefinition.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    return _withStandardDeckCards(parsed);
  }

  /// Scans [rootPath] (the user-chosen games directory, see
  /// `GamesDirectorySettings`) for every game folder inside it, so games
  /// dropped in after the app was built show up with no rebuild. Each game
  /// lives in its own subfolder (its JSON alongside any images it uses), so
  /// this lists immediate subfolders and runs [loadFromFolder] on each --
  /// reusing its scan/parse/image-path-resolution logic unchanged.
  Future<List<GameDefinition>> loadGamesFromDirectory(String rootPath) async {
    final dir = Directory(rootPath);
    if (!await dir.exists()) return const [];

    final games = <GameDefinition>[];
    await for (final entity in dir.list()) {
      if (entity is Directory) games.addAll(await loadFromFolder(entity.path));
    }
    return games;
  }

  /// Scans [folderPath] for a file named exactly `gamedef.json`
  /// (case-insensitive), parsing it as one [GameDefinition]. Any other file
  /// in the folder (a stray deck save, notes, etc.) is ignored. Each card's
  /// [CardDefinition.imagePath] and the game's own
  /// [GameDefinition.cardBackImagePath] (both authored as bare filenames
  /// alongside the game's JSON) are rewritten to an absolute path so
  /// renderers can load them directly without needing to know which folder a
  /// game came from -- a card belonging to a set (see [GameSet]) has its
  /// image resolved inside that set's own subfolder (named after
  /// [CardDefinition.setId]), since set art is kept one folder deeper than
  /// the game's own JSON.
  Future<List<GameDefinition>> loadFromFolder(String folderPath) async {
    final dir = Directory(folderPath);
    if (!await dir.exists()) return const [];

    final games = <GameDefinition>[];
    await for (final entity in dir.list()) {
      if (entity is! File || entity.uri.pathSegments.last.toLowerCase() != 'gamedef.json') continue;
      try {
        final raw = await entity.readAsString();
        final parsed = GameDefinition.fromJson(jsonDecode(raw) as Map<String, dynamic>);
        games.add(_withStandardDeckCards(_resolveGameImagePaths(parsed, folderPath)));
      } catch (_) {
        // Skip files that aren't valid game definitions.
      }
    }
    return games;
  }

  /// Appends [buildStandardDeckCards]'s cards into [game.cards] whenever any
  /// zone has [ZoneDefinition.standardDeck] set, so they resolve normally
  /// everywhere a [CardDefinition] is looked up (rendering, dealing's
  /// `validIds`, etc.) exactly like an author-defined card -- skips any id
  /// already present so this stays a no-op on a game with no such zone, and
  /// idempotent if ever called twice on the same [GameDefinition].
  GameDefinition _withStandardDeckCards(GameDefinition game) {
    if (!game.zones.any((z) => z.standardDeck)) return game;
    final existingIds = {for (final c in game.cards) c.id};
    final newCards = buildStandardDeckCards().where((c) => !existingIds.contains(c.id));
    return GameDefinition(
      id: game.id,
      name: game.name,
      cards: [...game.cards, ...newCards],
      sets: game.sets,
      cardBackImagePath: game.cardBackImagePath,
      zones: game.zones,
      tagGroups: game.tagGroups,
      folderPath: game.folderPath,
    );
  }

  GameDefinition _resolveGameImagePaths(GameDefinition game, String folderPath) {
    final cards = game.cards.map((c) {
      final imagePath = c.imagePath;
      if (imagePath == null) return c;
      return CardDefinition(
        id: c.id,
        cardTitle: c.cardTitle,
        colorHex: c.colorHex,
        suit: c.suit,
        rank: c.rank,
        imagePath: resolveBareImagePath(folderPath: folderPath, bareImagePath: imagePath, setId: c.setId),
        extraFields: c.extraFields,
        types: c.types,
        orientation: c.orientation,
        setId: c.setId,
        unownable: c.unownable,
      );
    }).toList();
    final cardBackImagePath = game.cardBackImagePath;
    return GameDefinition(
      id: game.id,
      name: game.name,
      cards: cards,
      sets: game.sets,
      cardBackImagePath: cardBackImagePath == null
          ? null
          : resolveBareImagePath(folderPath: folderPath, bareImagePath: cardBackImagePath),
      zones: game.zones,
      tagGroups: game.tagGroups,
      folderPath: folderPath,
    );
  }
}
