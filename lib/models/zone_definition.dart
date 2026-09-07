import 'deck_config.dart';

/// One zone a game defines beyond the always-present, per-player hand
/// (never declared in JSON -- see `TableScreen`) -- either a personal stack
/// owned by each player (e.g. a draw deck, a discard pile) or a single
/// shared stack everyone can see and use (e.g. a fixed 52-card deck). What a
/// zone is *for* is just its [name]; every zone supports the same generic
/// draw/return/shuffle actions regardless of role.
class ZoneDefinition {
  const ZoneDefinition({
    required this.id,
    required this.name,
    this.shared = false,
    this.dealsBuiltDeck = false,
    this.entries = const [],
    this.faceUp = false,
    this.shuffleable = true,
    this.visibleToAll = false,
    this.isDiscardPile = false,
  });

  /// Stable identity referenced by `CardInstance.zoneId` -- never shown to
  /// players (see [name] for that).
  final String id;

  /// Shown as a hover tooltip over this zone's pile.
  final String name;

  /// False (the default): one private instance per player, laid out in
  /// their own corner next to their hand. True: one public instance shared
  /// by everyone, positioned on the open table like any other table pile.
  final bool shared;

  /// Only meaningful when [shared] is false: this zone receives the local
  /// player's own chosen deck (from the Load Deck screen) at deal time,
  /// instead of starting from [entries]. Exactly one owned zone per game
  /// should set this -- a game needs no other flag to mark itself
  /// deck-building, see `GameDefinition.needsDeckBuilding`.
  final bool dealsBuiltDeck;

  /// Static starting contents, dealt once at game start. Ignored when
  /// [dealsBuiltDeck] is true. Empty means "start empty" for an owned zone
  /// (e.g. a discard pile) or "one of every card in the game" for a shared
  /// zone (e.g. Standard 52's Deck) -- the same convention the old
  /// `FixedDeckDefinition` used.
  final List<DeckEntry> entries;

  /// Whether a card entering this zone (dealt at game start, or returned to
  /// it later) shows its real face -- false (the default) for a face-down
  /// deck, true for a zone meant to be visibly inspectable, like a discard
  /// pile.
  final bool faceUp;

  /// Whether this zone's shuffle button is shown at all -- true (the
  /// default) for a deck-like zone, false for one where shuffling wouldn't
  /// make sense, like a discard pile (its card order matters -- it's a
  /// history, not a randomized pool).
  final bool shuffleable;

  /// Only meaningful for an owned (non-[shared]) zone: whether every other
  /// player can see this zone's real cards too -- false (the default,
  /// assumed whenever absent from JSON) for a private zone like a draw
  /// deck, true for a zone meant to be visible to everyone despite
  /// belonging to one player, like a discard pile. Still not interactable
  /// by anyone but its owner -- the opponent's view is read-only, exactly
  /// like their hand count is today, just showing real faces instead of
  /// backs. A [shared] zone is already visible to everyone regardless of
  /// this flag.
  final bool visibleToAll;

  /// Whether this is "the" discard pile for its owner -- pressing D while
  /// hovering your own table card sends it here (see `TableScreen`). False
  /// (the default, assumed whenever absent from JSON) for every other zone;
  /// at most one owned zone per game should set this.
  final bool isDiscardPile;

  factory ZoneDefinition.fromJson(Map<String, dynamic> json) {
    return ZoneDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      shared: json['shared'] as bool? ?? false,
      dealsBuiltDeck: json['dealsBuiltDeck'] as bool? ?? false,
      entries: (json['entries'] as List?)
              ?.map((e) => DeckEntry.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          const [],
      faceUp: json['faceUp'] as bool? ?? false,
      shuffleable: json['shuffleable'] as bool? ?? true,
      visibleToAll: json['visibleToAll'] as bool? ?? false,
      isDiscardPile: json['isDiscardPile'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (shared) 'shared': shared,
      if (dealsBuiltDeck) 'dealsBuiltDeck': dealsBuiltDeck,
      if (entries.isNotEmpty) 'entries': entries.map((e) => e.toJson()).toList(),
      if (faceUp) 'faceUp': faceUp,
      if (!shuffleable) 'shuffleable': shuffleable,
      if (visibleToAll) 'visibleToAll': visibleToAll,
      if (isDiscardPile) 'isDiscardPile': isDiscardPile,
    };
  }
}
