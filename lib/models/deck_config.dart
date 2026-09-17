import 'game_definition.dart';

/// How many copies of one [CardDefinition] (by id) a player is bringing to
/// the session.
class DeckEntry {
  const DeckEntry({required this.definitionId, required this.quantity});

  final String definitionId;
  final int quantity;

  factory DeckEntry.fromJson(Map<String, dynamic> json) {
    return DeckEntry(definitionId: json['definitionId'] as String, quantity: json['quantity'] as int);
  }

  Map<String, dynamic> toJson() => {'definitionId': definitionId, 'quantity': quantity};
}

/// One named pile within a [DeckConfig] -- [name] matches a
/// [ZoneDefinition.deckType], so a single deck file can supply more than one
/// of a game's owned zones (e.g. METW's `main_deck` and `location_deck`).
class SubDeck {
  const SubDeck({required this.name, required this.entries});

  final String name;
  final List<DeckEntry> entries;

  factory SubDeck.fromJson(Map<String, dynamic> json) {
    return SubDeck(
      name: json['name'] as String,
      entries: (json['entries'] as List)
          .map((e) => DeckEntry.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'entries': entries.map((e) => e.toJson()).toList()};
}

/// Thrown by [DeckConfig.fromJson] when parsing a pre-subdeck deck file (no
/// `subdecks` key at all) -- lets callers show a specific "this deck needs to
/// be rebuilt" message instead of a generic parse failure.
class LegacyDeckFormatException implements Exception {
  const LegacyDeckFormatException();

  @override
  String toString() => 'This deck was saved in an older format and needs to be rebuilt in the Deck Editor.';
}

/// The set of cards (and how many of each) a player selected from a
/// [GameDefinition] to bring into a session, split into one or more named
/// [SubDeck]s -- one per [ZoneDefinition.deckType] the game's owned,
/// deck-building zones declare (see [GameDefinition.deckTypes]).
class DeckConfig {
  const DeckConfig({required this.gameId, required this.subdecks});

  final String gameId;
  final List<SubDeck> subdecks;

  SubDeck? subdeck(String name) {
    for (final s in subdecks) {
      if (s.name == name) return s;
    }
    return null;
  }

  List<DeckEntry> entriesFor(String name) => subdeck(name)?.entries ?? const [];

  int cardCountFor(String name) => entriesFor(name).fold<int>(0, (a, e) => a + e.quantity);

  /// One copy of every card in [game], split into one [SubDeck] per distinct
  /// [GameDefinition.deckTypes] entry -- the default "use the whole pool"
  /// starting point for a game with deck-building zones. A game with none
  /// (e.g. Standard 52) gets a single `main_deck` subdeck instead.
  factory DeckConfig.full(GameDefinition game) {
    final entries = [for (final c in game.cards) DeckEntry(definitionId: c.id, quantity: 1)];
    final types = game.deckTypes;
    return DeckConfig(
      gameId: game.id,
      subdecks: types.isEmpty
          ? [SubDeck(name: 'main_deck', entries: entries)]
          : [for (final t in types) SubDeck(name: t, entries: entries)],
    );
  }

  factory DeckConfig.fromJson(Map<String, dynamic> json) {
    final rawSubdecks = json['subdecks'] as List?;
    if (rawSubdecks == null) throw const LegacyDeckFormatException();
    return DeckConfig(
      gameId: json['gameId'] as String,
      subdecks: rawSubdecks.map((e) => SubDeck.fromJson((e as Map).cast<String, dynamic>())).toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'gameId': gameId, 'subdecks': subdecks.map((s) => s.toJson()).toList()};
  }
}
