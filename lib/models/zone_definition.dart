import 'board_widget_instance.dart';
import 'deck_config.dart';

/// Which screen edge a [ZoneDefinition.shared] zone is docked to -- a fixed
/// panel outside the pannable table, exactly like the per-player hand/zone
/// rows are docked to the top and bottom. Only meaningful when `shared` is
/// true; [left] is the default.
enum SharedZoneSide { left, right }

/// Whether a [ZoneDefinition] holds cards (today's only option, and every
/// zone with no `kind` in its JSON) or a single board widget instead -- see
/// [ZoneDefinition.widgetKind]. Every card-related field on [ZoneDefinition]
/// (`shared`, `dealsBuiltDeck`, `entries`, `faceUp`, `shuffleable`,
/// `visibleToAll`, `isDiscardPile`, `autoShuffle`, `standardDeck`,
/// `deckName`, `side`) is meaningless for a [widget] zone.
enum ZoneKind { card, widget }

/// Which board widget a [ZoneKind.widget] zone docks -- deliberately a
/// separate, smaller catalog than `BoardWidgetKind` (which also has `token`/
/// `arrow`, neither sensible permanently docked in a player's panel), so the
/// Zone Editor's own "Widget Type" list only ever offers options that make
/// sense here, and can grow independently later.
enum ZoneWidgetKind { counter }

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
    this.autoShuffle = false,
    this.standardDeck = false,
    this.deckName,
    this.side = SharedZoneSide.left,
    this.kind = ZoneKind.card,
    this.widgetKind = ZoneWidgetKind.counter,
    this.counterStartingValue = 0,
    this.counterStartingColor = defaultBoardWidgetBackgroundColor,
    this.counterStartingTextColor = defaultBoardWidgetTextColor,
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
  /// instead of starting from [entries]. A game can set this on more than
  /// one owned zone (e.g. METW's Draw Deck and Location Deck) -- each gets
  /// its own separately loaded deck file, see `GameDefinition.deckBuildingZones`.
  final bool dealsBuiltDeck;

  /// Static starting contents, dealt once at game start. Ignored when
  /// [dealsBuiltDeck] is true (an owned zone), or [standardDeck]/[deckName]
  /// resolves to something (a shared zone). Empty means "start empty" for
  /// an owned zone, or for any zone -- owned or shared -- with
  /// [isDiscardPile] set (a discard pile should never auto-populate); for
  /// every other shared zone, empty means "one of every card in the game"
  /// instead (e.g. Standard 52's Deck) -- the same convention the old
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

  /// Whether this zone's contents are dealt in randomized order at game
  /// start instead of the order [entries] (or a loaded deck, for a
  /// [dealsBuiltDeck] zone) lists them in -- false (the default) leaves the
  /// dealt order exactly as authored/loaded. Unlike the in-game Shuffle
  /// button, this only affects the initial deal order; it doesn't force
  /// cards face-down (that's still governed by [faceUp]).
  final bool autoShuffle;

  /// Only meaningful when [shared] is true: generate one of each traditional
  /// playing card (via `buildStandardDeckCards`) as this zone's starting
  /// contents instead of [entries]/[deckName] -- lets any game plug in a
  /// standard 52-card deck with no deck file and no need to author those 52
  /// cards itself. Takes precedence over [deckName] when both are set.
  final bool standardDeck;

  /// Only meaningful when [shared] is true and [standardDeck] is false: the
  /// filename (minus `.json`) of a deck in the Deck Library's folder for
  /// this game (see `DeckLibraryLoader`) to load as this zone's starting
  /// contents instead of [entries]. Resolved once by the host at game start
  /// -- if no such deck is found, falls back to [entries] like normal.
  final String? deckName;

  /// Only meaningful when [shared] is true: which screen edge this zone is
  /// docked to. [SharedZoneSide.left] is the default.
  final SharedZoneSide side;

  /// Whether this zone holds cards (the default) or a single docked board
  /// widget -- see [ZoneKind]'s doc for which other fields this makes
  /// meaningless.
  final ZoneKind kind;

  /// Only meaningful when [kind] is [ZoneKind.widget]: which widget this
  /// zone docks. [ZoneWidgetKind.counter] is the only value today, and the
  /// default.
  final ZoneWidgetKind widgetKind;

  /// Only meaningful when [kind] is [ZoneKind.widget] and [widgetKind] is
  /// [ZoneWidgetKind.counter]: this counter's value/colors at deal time, one
  /// independent instance per player (a widget zone is never [shared]). See
  /// `BoardWidgetInstance.value`/`backgroundColor`/`textColor` for the
  /// runtime fields these seed.
  final int counterStartingValue;
  final int counterStartingColor;
  final int counterStartingTextColor;

  factory ZoneDefinition.fromJson(Map<String, dynamic> json) {
    return ZoneDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      shared: json['shared'] as bool? ?? false,
      dealsBuiltDeck: json['dealsBuiltDeck'] as bool? ?? false,
      entries:
          (json['entries'] as List?)
              ?.map(
                (e) => DeckEntry.fromJson((e as Map).cast<String, dynamic>()),
              )
              .toList() ??
          const [],
      faceUp: json['faceUp'] as bool? ?? false,
      shuffleable: json['shuffleable'] as bool? ?? true,
      visibleToAll: json['visibleToAll'] as bool? ?? false,
      isDiscardPile: json['isDiscardPile'] as bool? ?? false,
      autoShuffle: json['autoShuffle'] as bool? ?? false,
      standardDeck: json['standardDeck'] as bool? ?? false,
      deckName: json['deckName'] as String?,
      side: SharedZoneSide.values.byName(json['side'] as String? ?? 'left'),
      kind: ZoneKind.values.byName(json['kind'] as String? ?? 'card'),
      widgetKind: ZoneWidgetKind.values.byName(
        json['widgetKind'] as String? ?? 'counter',
      ),
      counterStartingValue: json['counterStartingValue'] as int? ?? 0,
      counterStartingColor:
          json['counterStartingColor'] as int? ??
          defaultBoardWidgetBackgroundColor,
      counterStartingTextColor:
          json['counterStartingTextColor'] as int? ??
          defaultBoardWidgetTextColor,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      if (shared) 'shared': shared,
      if (dealsBuiltDeck) 'dealsBuiltDeck': dealsBuiltDeck,
      if (entries.isNotEmpty)
        'entries': entries.map((e) => e.toJson()).toList(),
      if (faceUp) 'faceUp': faceUp,
      if (!shuffleable) 'shuffleable': shuffleable,
      if (visibleToAll) 'visibleToAll': visibleToAll,
      if (isDiscardPile) 'isDiscardPile': isDiscardPile,
      if (autoShuffle) 'autoShuffle': autoShuffle,
      if (standardDeck) 'standardDeck': standardDeck,
      if (deckName != null) 'deckName': deckName,
      if (side != SharedZoneSide.left) 'side': side.name,
      if (kind != ZoneKind.card) 'kind': kind.name,
      if (widgetKind != ZoneWidgetKind.counter) 'widgetKind': widgetKind.name,
      if (counterStartingValue != 0)
        'counterStartingValue': counterStartingValue,
      if (counterStartingColor != defaultBoardWidgetBackgroundColor)
        'counterStartingColor': counterStartingColor,
      if (counterStartingTextColor != defaultBoardWidgetTextColor)
        'counterStartingTextColor': counterStartingTextColor,
    };
  }

  /// Returns a copy with the given fields replaced; every field here except
  /// [deckName] is non-nullable, so a plain `field ?? this.field` is
  /// sufficient -- unlike `CardDefinition.copyWith`, no sentinel is needed to
  /// represent "clear this field." [deckName] is cleared with
  /// [clearDeckName] instead, since `null` here means "keep the current
  /// value," not "clear it."
  ZoneDefinition copyWith({
    String? id,
    String? name,
    bool? shared,
    bool? dealsBuiltDeck,
    List<DeckEntry>? entries,
    bool? faceUp,
    bool? shuffleable,
    bool? visibleToAll,
    bool? isDiscardPile,
    bool? autoShuffle,
    bool? standardDeck,
    String? deckName,
    bool clearDeckName = false,
    SharedZoneSide? side,
    ZoneKind? kind,
    ZoneWidgetKind? widgetKind,
    int? counterStartingValue,
    int? counterStartingColor,
    int? counterStartingTextColor,
  }) {
    return ZoneDefinition(
      id: id ?? this.id,
      name: name ?? this.name,
      shared: shared ?? this.shared,
      dealsBuiltDeck: dealsBuiltDeck ?? this.dealsBuiltDeck,
      entries: entries ?? this.entries,
      faceUp: faceUp ?? this.faceUp,
      shuffleable: shuffleable ?? this.shuffleable,
      visibleToAll: visibleToAll ?? this.visibleToAll,
      isDiscardPile: isDiscardPile ?? this.isDiscardPile,
      autoShuffle: autoShuffle ?? this.autoShuffle,
      standardDeck: standardDeck ?? this.standardDeck,
      deckName: clearDeckName ? null : (deckName ?? this.deckName),
      side: side ?? this.side,
      kind: kind ?? this.kind,
      widgetKind: widgetKind ?? this.widgetKind,
      counterStartingValue: counterStartingValue ?? this.counterStartingValue,
      counterStartingColor: counterStartingColor ?? this.counterStartingColor,
      counterStartingTextColor:
          counterStartingTextColor ?? this.counterStartingTextColor,
    );
  }
}
