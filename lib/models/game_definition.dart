import 'card_back_definition.dart';
import 'card_definition.dart';
import 'game_set.dart';
import 'tag_group.dart';
import 'zone_definition.dart';

/// A loaded "game": a named pool of card definitions players can build decks
/// from. Sourced either from a bundled asset (the default standard 52-card
/// deck) or a JSON file in a user-chosen folder on disk (custom games).
class GameDefinition {
  const GameDefinition({
    required this.id,
    required this.name,
    required this.cards,
    this.cardBacks = const [],
    this.zones = const [],
    this.tagGroups = const [],
    this.sets = const [],
    this.folderPath,
  });

  final String id;
  final String name;
  final List<CardDefinition> cards;

  /// This machine's own on-disk folder for this game (e.g.
  /// `game_library/lorcana`), set by `GameLoader` when loading from a games
  /// directory -- null for the bundled standard-52 asset (which lives in the
  /// app bundle, not a real folder a player could drop extra content into).
  /// Purely local, like `CardDefinition.imagePath`/each [CardBackDefinition]'s
  /// own `imagePath`: never round-tripped through [fromJson]/[toJson], since a
  /// path on the host's disk means nothing on a client's -- see
  /// `mergeLocalImagePaths`, which re-populates it from the client's own
  /// local copy of the game instead of trusting whatever the host sent.
  final String? folderPath;

  /// This game's declared tag taxonomy, grouped into independently-named
  /// [TagGroup]s (e.g. "Card Type", "Mana Color") -- see
  /// [CardDefinition.types], which stores a card's tags as one flat list
  /// regardless of which group each tag belongs to. Empty means this game
  /// doesn't use tags at all, in which case the Deck Editor shows no filter
  /// buttons.
  final List<TagGroup> tagGroups;

  /// This game's declared sets (e.g. METW's "Core Set", Lorcana's numbered
  /// chapters) -- see [GameSet]. Empty means this game's JSON used the flat
  /// top-level `cards` schema with no set concept, in which case the Deck
  /// Editor shows no Set filter chips and every [CardDefinition.setId] here
  /// is null.
  final List<GameSet> sets;

  /// This game's declared card backs -- see [CardBackDefinition]. The first
  /// entry is the default, used by any card whose [CardDefinition.cardBackId]
  /// is null; the rest are named alternates a card can opt into by id. Empty
  /// means no real art is configured at all -- see `CardBackWidget`, which
  /// falls back to a code-drawn back in that case.
  final List<CardBackDefinition> cardBacks;

  /// This game's non-hand zones (draw deck, discard pile, a shared deck,
  /// etc.) -- see [ZoneDefinition]. The hand zone is automatic and never
  /// listed here.
  final List<ZoneDefinition> zones;

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
    // Migrates a pre-multiple-card-backs file: no `cardBacks` key, just the
    // old single `cardBackImagePath` string -- becomes that one default
    // entry, so an existing gamedef.json keeps working unchanged until it's
    // next saved from the Editor (which always writes the new `cardBacks`
    // shape and never this legacy key again).
    final rawCardBacks = json['cardBacks'] as List?;
    final legacyCardBackImagePath = json['cardBackImagePath'] as String?;
    return GameDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      cards: cards,
      sets: sets,
      cardBacks: rawCardBacks != null
          ? rawCardBacks.map((e) => CardBackDefinition.fromJson((e as Map).cast<String, dynamic>())).toList()
          : (legacyCardBackImagePath == null
              ? const []
              : [CardBackDefinition(id: 'default', name: 'Default', imagePath: legacyCardBackImagePath)]),
      zones: (json['zones'] as List?)
              ?.map((e) => ZoneDefinition.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          const [],
      tagGroups: (json['tagGroups'] as List?)
              ?.map((e) => TagGroup.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          const [],
    );
  }

  /// Reconstructs [card] with [setId] stamped on -- used while parsing the
  /// nested `sets` schema, where a card's set membership comes from its
  /// position in the JSON rather than an inline field.
  static CardDefinition _cardWithSetId(CardDefinition card, String setId) => card.copyWith(setId: setId);

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
      if (cardBacks.isNotEmpty) 'cardBacks': cardBacks.map((b) => b.toJson()).toList(),
      if (zones.isNotEmpty) 'zones': zones.map((z) => z.toJson()).toList(),
      if (tagGroups.isNotEmpty) 'tagGroups': tagGroups.map((g) => g.toJson()).toList(),
    };
  }
}
