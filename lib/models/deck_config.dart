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

/// One pre-authored, named deck a `GameDeckMode.fixedDeck` game deals
/// automatically -- never built or chosen by a player (contrast
/// [DeckConfig], which a player builds/loads). Empty [entries] means "one of
/// every card in the game" (resolved at deal time), so a simple single-deck
/// game like Standard 52 doesn't need to spell out every card.
class FixedDeckDefinition {
  const FixedDeckDefinition({required this.name, this.entries = const []});

  final String name;
  final List<DeckEntry> entries;

  factory FixedDeckDefinition.fromJson(Map<String, dynamic> json) {
    return FixedDeckDefinition(
      name: json['name'] as String,
      entries: (json['entries'] as List?)
              ?.map((e) => DeckEntry.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      if (entries.isNotEmpty) 'entries': entries.map((e) => e.toJson()).toList(),
    };
  }
}

/// The set of cards (and how many of each) a player selected from a
/// [GameDefinition] to bring into a session.
class DeckConfig {
  const DeckConfig({required this.gameId, required this.entries});

  final String gameId;
  final List<DeckEntry> entries;

  /// One copy of every card in [game] -- the default "use the whole deck"
  /// starting point offered on [DeckBuildScreen].
  factory DeckConfig.full(GameDefinition game) {
    return DeckConfig(
      gameId: game.id,
      entries: [for (final c in game.cards) DeckEntry(definitionId: c.id, quantity: 1)],
    );
  }

  factory DeckConfig.fromJson(Map<String, dynamic> json) {
    return DeckConfig(
      gameId: json['gameId'] as String,
      entries: (json['entries'] as List)
          .map((e) => DeckEntry.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'gameId': gameId, 'entries': entries.map((e) => e.toJson()).toList()};
  }
}
