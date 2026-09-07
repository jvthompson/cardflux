import 'card_definition.dart';
import 'zone_definition.dart';

/// Default for [GameDefinition.opponentCardBorderColor] when a game's JSON
/// doesn't specify one -- plain red.
const String defaultOpponentCardBorderColor = '#FF0000';

/// A loaded "game": a named pool of card definitions players can build decks
/// from. Sourced either from a bundled asset (the default standard 52-card
/// deck) or a JSON file in a user-chosen folder on disk (custom games).
class GameDefinition {
  const GameDefinition({
    required this.id,
    required this.name,
    required this.cards,
    this.cardBackImagePath,
    this.zones = const [],
    this.opponentCardBorderColor = defaultOpponentCardBorderColor,
  });

  final String id;
  final String name;
  final List<CardDefinition> cards;

  /// Optional real art for this game's card back, shared by every card in
  /// it (unlike [CardDefinition.imagePath], which is per-card front art).
  /// Falls back to a code-drawn back (see `CardBackWidget`) when null.
  final String? cardBackImagePath;

  /// This game's non-hand zones (draw deck, discard pile, a shared deck,
  /// etc.) -- see [ZoneDefinition]. The hand zone is automatic and never
  /// listed here.
  final List<ZoneDefinition> zones;

  /// `#RRGGBB` color for the thin border `TableScreen` draws around any
  /// free-table card owned by someone other than the local player, so an
  /// opponent's played card is easy to pick out at a glance. Defaults to
  /// red; a game's JSON can override it.
  final String opponentCardBorderColor;

  /// Whether starting this game requires each player to pick their own deck
  /// on the Load Deck screen first -- true iff some owned zone is marked
  /// [ZoneDefinition.dealsBuiltDeck]. A game with no such zone (e.g.
  /// Standard 52, whose only zone is a shared deck) deals automatically
  /// with no per-player choice.
  bool get needsDeckBuilding => zones.any((z) => !z.shared && z.dealsBuiltDeck);

  factory GameDefinition.fromJson(Map<String, dynamic> json) {
    return GameDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      cards: (json['cards'] as List)
          .map((e) => CardDefinition.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      cardBackImagePath: json['cardBackImagePath'] as String?,
      zones: (json['zones'] as List?)
              ?.map((e) => ZoneDefinition.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          const [],
      opponentCardBorderColor: json['opponentCardBorderColor'] as String? ?? defaultOpponentCardBorderColor,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'cards': cards.map((c) => c.toJson()).toList(),
      if (cardBackImagePath != null) 'cardBackImagePath': cardBackImagePath,
      if (zones.isNotEmpty) 'zones': zones.map((z) => z.toJson()).toList(),
      if (opponentCardBorderColor != defaultOpponentCardBorderColor) 'opponentCardBorderColor': opponentCardBorderColor,
    };
  }
}
