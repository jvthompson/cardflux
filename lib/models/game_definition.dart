import 'card_definition.dart';
import 'game_set.dart';
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
    this.cardTypes = const [],
    this.sets = const [],
  });

  final String id;
  final String name;
  final List<CardDefinition> cards;

  /// This game's declared card-type taxonomy (e.g. "Character", "Item"),
  /// display/toggle order matching JSON order -- see [CardDefinition.types].
  /// Empty means this game doesn't use types at all, in which case the Deck
  /// Editor shows no filter chips.
  final List<String> cardTypes;

  /// This game's declared sets (e.g. METW's "Core Set", Lorcana's numbered
  /// chapters) -- see [GameSet]. Empty means this game's JSON used the flat
  /// top-level `cards` schema with no set concept, in which case the Deck
  /// Editor shows no Set filter chips and every [CardDefinition.setId] here
  /// is null.
  final List<GameSet> sets;

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

  /// Every owned zone marked [ZoneDefinition.dealsBuiltDeck] -- each one
  /// needs its own separate deck file loaded per player (e.g. METW's Draw
  /// Deck and Location Deck), not just one deck for the whole game. Empty
  /// for a game with no such zone (e.g. Standard 52).
  List<ZoneDefinition> get deckBuildingZones => zones.where((z) => !z.shared && z.dealsBuiltDeck).toList();

  /// Whether starting this game requires each player to pick their own
  /// deck(s) on the Load Deck screen first -- true iff [deckBuildingZones]
  /// is non-empty. A game with no such zone (e.g. Standard 52, whose only
  /// zone is a shared deck) deals automatically with no per-player choice.
  bool get needsDeckBuilding => deckBuildingZones.isNotEmpty;

  factory GameDefinition.fromJson(Map<String, dynamic> json) {
    final rawSets = json['sets'] as List?;
    final List<GameSet> sets;
    final List<CardDefinition> cards;
    if (rawSets != null) {
      sets = rawSets.map((e) => GameSet.fromJson((e as Map).cast<String, dynamic>())).toList();
      cards = [
        for (final rawSet in rawSets.cast<Map>().map((e) => e.cast<String, dynamic>()))
          for (final rawCard in (rawSet['cards'] as List).cast<Map>().map((e) => e.cast<String, dynamic>()))
            _cardWithSetId(CardDefinition.fromJson(rawCard), rawSet['id'] as String),
      ];
    } else {
      sets = const [];
      cards = (json['cards'] as List)
          .map((e) => CardDefinition.fromJson((e as Map).cast<String, dynamic>()))
          .toList();
    }
    return GameDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      cards: cards,
      sets: sets,
      cardBackImagePath: json['cardBackImagePath'] as String?,
      zones: (json['zones'] as List?)
              ?.map((e) => ZoneDefinition.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          const [],
      opponentCardBorderColor: json['opponentCardBorderColor'] as String? ?? defaultOpponentCardBorderColor,
      cardTypes: (json['cardTypes'] as List?)?.cast<String>().toList() ?? const [],
    );
  }

  /// Reconstructs [card] with [setId] stamped on -- used while parsing the
  /// nested `sets` schema, where a card's set membership comes from its
  /// position in the JSON rather than an inline field.
  static CardDefinition _cardWithSetId(CardDefinition card, String setId) {
    return CardDefinition(
      id: card.id,
      cardTitle: card.cardTitle,
      colorHex: card.colorHex,
      suit: card.suit,
      rank: card.rank,
      imagePath: card.imagePath,
      extraFields: card.extraFields,
      types: card.types,
      orientation: card.orientation,
      setId: setId,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (sets.isNotEmpty)
        'sets': [
          for (final s in sets)
            {
              'id': s.id,
              'name': s.name,
              'cards': cards
                  .where((c) => c.setId == s.id)
                  .map((c) => c.toJson()..remove('setId'))
                  .toList(),
            },
        ]
      else
        'cards': cards.map((c) => c.toJson()).toList(),
      if (cardBackImagePath != null) 'cardBackImagePath': cardBackImagePath,
      if (zones.isNotEmpty) 'zones': zones.map((z) => z.toJson()).toList(),
      if (opponentCardBorderColor != defaultOpponentCardBorderColor) 'opponentCardBorderColor': opponentCardBorderColor,
      if (cardTypes.isNotEmpty) 'cardTypes': cardTypes,
    };
  }
}
