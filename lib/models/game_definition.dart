import 'card_definition.dart';
import 'deck_config.dart';

/// Whether a game's decks are player-built ([deckBuilding], the default --
/// see the Load Deck screen) or pre-authored by the game itself
/// ([fixedDeck] -- see [GameDefinition.fixedDecks]), dealt automatically
/// with no per-player choice.
enum GameDeckMode {
  deckBuilding,
  fixedDeck;

  static GameDeckMode fromName(String name) => GameDeckMode.values.byName(name);
}

/// A loaded "game": a named pool of card definitions players can build decks
/// from. Sourced either from a bundled asset (the default standard 52-card
/// deck) or a JSON file in a user-chosen folder on disk (custom games).
class GameDefinition {
  const GameDefinition({
    required this.id,
    required this.name,
    required this.cards,
    this.cardBackImagePath,
    this.deckMode = GameDeckMode.deckBuilding,
    this.fixedDecks = const [],
  });

  final String id;
  final String name;
  final List<CardDefinition> cards;

  /// Optional real art for this game's card back, shared by every card in
  /// it (unlike [CardDefinition.imagePath], which is per-card front art).
  /// Falls back to a code-drawn back (see `CardBackWidget`) when null.
  final String? cardBackImagePath;

  final GameDeckMode deckMode;

  /// The named decks a [deckMode] of [GameDeckMode.fixedDeck] deals
  /// automatically -- empty (and unused) for a [GameDeckMode.deckBuilding]
  /// game.
  final List<FixedDeckDefinition> fixedDecks;

  factory GameDefinition.fromJson(Map<String, dynamic> json) {
    return GameDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      cards: (json['cards'] as List)
          .map((e) => CardDefinition.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      cardBackImagePath: json['cardBackImagePath'] as String?,
      deckMode: json['deckMode'] == null ? GameDeckMode.deckBuilding : GameDeckMode.fromName(json['deckMode'] as String),
      fixedDecks: (json['fixedDecks'] as List?)
              ?.map((e) => FixedDeckDefinition.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'cards': cards.map((c) => c.toJson()).toList(),
      if (cardBackImagePath != null) 'cardBackImagePath': cardBackImagePath,
      if (deckMode != GameDeckMode.deckBuilding) 'deckMode': deckMode.name,
      if (fixedDecks.isNotEmpty) 'fixedDecks': fixedDecks.map((d) => d.toJson()).toList(),
    };
  }
}
