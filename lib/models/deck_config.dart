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

/// The set of cards (and how many of each) a player selected from a
/// [GameDefinition] to bring into a session.
class DeckConfig {
  const DeckConfig({required this.gameId, required this.entries});

  final String gameId;
  final List<DeckEntry> entries;

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
