/// Which kind of board widget a [BoardWidgetInstance] is. The widget catalog
/// is hardcoded in app code (unlike `CardDefinition`/`ZoneDefinition`, which
/// are JSON-defined per game) -- a widget is a generic utility available in
/// every game, not game content.
enum BoardWidgetKind {
  simpleCounter,

  /// A small colored circle with no numeric state -- just a marker. Reuses
  /// [BoardWidgetInstance.backgroundColor] for its own color; [value]/
  /// [BoardWidgetInstance.textColor] are meaningless for this kind.
  token,

  /// A line with an arrowhead pointing from ([BoardWidgetInstance.x],
  /// [BoardWidgetInstance.y]) to ([BoardWidgetInstance.x2],
  /// [BoardWidgetInstance.y2]) -- drawn by holding TAB and dragging on the
  /// table (see `TableScreen`), dismissed only by its own
  /// [BoardWidgetInstance.creatorId] via double-tap. Unlike every other
  /// kind, this one needs a second point; [value]/colors/attach fields are
  /// all meaningless for it.
  arrow,

  /// A neutral, unowned table object showing a game's `packgen.png` image
  /// (or a text fallback) -- see `PackGeneratorWidget`. Right-clicking it
  /// lists the game's `GameSet`s; picking one deals a random pack into the
  /// clicking player's hand (see `GameSession.generatePack`). No numeric
  /// [value]/colors/attach-to-card concept applies, mirroring [token] --
  /// which set to draw from is chosen at click-time via the menu, not
  /// stored on the instance.
  packGenerator,

  /// A table-side deck-building station, owned by whoever spawns it (see
  /// [BoardWidgetInstance.ownerId]'s updated doc) -- one sub-zone per
  /// `GameDefinition.deckBuildingZones` entry, each a real, private,
  /// searchable zone scoped to this specific instance (see
  /// `lib/game/deck_widget_zones.dart`). A Save button on it writes a
  /// `DeckConfig` built from whatever's currently in those sub-zones to the
  /// deck library. See `DeckWidget`. No numeric [value]/colors/attach-to-card
  /// concept applies, mirroring [token].
  deckBuilder;

  static BoardWidgetKind fromName(String name) =>
      BoardWidgetKind.values.byName(name);
}

/// Inclusive bounds every mutator that sets a [BoardWidgetInstance.value]
/// clamps to -- shared here so `TableActions` and the UI's Set Value prompt
/// agree on the same range.
const int boardWidgetCounterMin = 0;
const int boardWidgetCounterMax = 99999;

/// Default [BoardWidgetInstance.backgroundColor]/[BoardWidgetInstance.textColor]
/// (ARGB, matching [Color.value]'s format) -- a plain `int` rather than a
/// `dart:ui`/Flutter `Color` so this model stays framework-free like every
/// other model in this app; the UI parses these back into `Color` itself.
const int defaultBoardWidgetBackgroundColor =
    0xFF455A64; // Colors.blueGrey.shade700
const int defaultBoardWidgetTextColor = 0xFFFFFFFF; // Colors.white

/// A general-purpose utility placed on the table -- not a card. Unlike
/// `CardInstance`, there's no `definitionId` to look up: [kind] alone
/// determines everything about how it renders and behaves, since the
/// catalog is small and hardcoded rather than JSON-defined.
class BoardWidgetInstance {
  BoardWidgetInstance({
    required this.instanceId,
    required this.kind,
    required this.x,
    required this.y,
    required this.zIndex,
    this.value = 0,
    this.backgroundColor = defaultBoardWidgetBackgroundColor,
    this.textColor = defaultBoardWidgetTextColor,
    this.attachedCardId,
    this.attachOffsetX = 0,
    this.attachOffsetY = 0,
    this.x2,
    this.y2,
    this.creatorId,
    this.ownerId,
    this.zoneId,
  });

  final String instanceId;
  final BoardWidgetKind kind;

  /// Canonical position as [0,1] fractions of the table's play area, same
  /// convention as `CardInstance.x`/`y` -- see `geometry_utils.dart`.
  final double x;
  final double y;
  final int zIndex;

  /// Kind-specific state -- for [BoardWidgetKind.simpleCounter], the current
  /// displayed value. Always kept within
  /// [boardWidgetCounterMin]-[boardWidgetCounterMax] by every mutator in
  /// `TableActions`; this class itself is just a plain data holder and
  /// doesn't enforce that range.
  final int value;

  /// User-customizable appearance, set via the widget's own "Set Colors"
  /// context menu action -- ARGB ints, same format `Color.value` uses.
  final int backgroundColor;
  final int textColor;

  /// The instanceId of a table `CardInstance` this widget is currently
  /// resting on, or null if it's freely positioned -- see
  /// `TableActions.attachWidgetToCard`. [attachOffsetX]/[attachOffsetY] (only
  /// meaningful while attached) are the fixed canonical-fraction offset from
  /// the card's own position to wherever this widget was actually dropped
  /// onto it -- attaching does NOT snap to the card's center. Every
  /// card-position action in `TableActions` (`moveCard`/`moveStack`/
  /// `moveGroup`/`stackCard`) re-applies `card position + offset` to this
  /// widget's x/y, so it travels with whatever card/pile it's sitting on,
  /// preserving exactly where on the card it was placed, like a token
  /// resting on a physical card. Cleared by `TableActions.moveWidget` --
  /// dragging the widget itself to a new spot always detaches it.
  final String? attachedCardId;
  final double attachOffsetX;
  final double attachOffsetY;

  /// Second endpoint, only meaningful for [BoardWidgetKind.arrow] -- the
  /// arrow points from ([x],[y]) to ([x2],[y2]), both in the same canonical
  /// [0,1]-fraction space. Null for every other kind.
  final double? x2;
  final double? y2;

  /// The id of the player who created this widget -- today only ever set
  /// for [BoardWidgetKind.arrow] (see `TableScreen`'s TAB-drag), null for
  /// every other kind, which stay deliberately ownerless (see
  /// `table_controller.dart`'s doc comment). Used to gate who may
  /// double-tap-dismiss an arrow (see `HostGameEngine`).
  final String? creatorId;

  /// [ownerId]/[zoneId] together describe one of three states:
  ///  1. Both null: a free-floating, unowned widget ([BoardWidgetKind.simpleCounter],
  ///     [BoardWidgetKind.token], [BoardWidgetKind.packGenerator]) -- fair
  ///     game for any player to move/act on/delete, unchanged since before
  ///     ownership existed.
  ///  2. [zoneId] non-null (always paired with a non-null [ownerId]): a
  ///     widget dealt from a [ZoneKind.widget] `ZoneDefinition` (see
  ///     `GameSession.dealFromZones`), permanently docked in that owning
  ///     player's panel slot. Never rendered on the free table, and can
  ///     never be moved/attached/duplicated/deleted -- see `TableScreen`'s
  ///     zone-widget panel rendering and `HostGameEngine`'s rejection of
  ///     those requests for such a widget.
  ///  3. [ownerId] non-null, [zoneId] null: a free-floating widget that's
  ///     still owned ([BoardWidgetKind.deckBuilder]) -- rendered on the open
  ///     table like state 1, but movable/actionable/deletable only by its
  ///     owner (see `HostGameEngine`'s `_isMovableWidget`/
  ///     `_isAllowedToActOnWidget`/`_isAllowedToDeleteWidget`).
  final String? ownerId;
  final String? zoneId;

  BoardWidgetInstance copyWith({
    double? x,
    double? y,
    int? zIndex,
    int? value,
    int? backgroundColor,
    int? textColor,
    Object? attachedCardId = _unset,
    double? attachOffsetX,
    double? attachOffsetY,
    Object? x2 = _unset,
    Object? y2 = _unset,
    Object? creatorId = _unset,
    Object? ownerId = _unset,
    Object? zoneId = _unset,
  }) {
    return BoardWidgetInstance(
      instanceId: instanceId,
      kind: kind,
      x: x ?? this.x,
      y: y ?? this.y,
      zIndex: zIndex ?? this.zIndex,
      value: value ?? this.value,
      backgroundColor: backgroundColor ?? this.backgroundColor,
      textColor: textColor ?? this.textColor,
      attachedCardId: identical(attachedCardId, _unset)
          ? this.attachedCardId
          : attachedCardId as String?,
      attachOffsetX: attachOffsetX ?? this.attachOffsetX,
      attachOffsetY: attachOffsetY ?? this.attachOffsetY,
      x2: identical(x2, _unset) ? this.x2 : x2 as double?,
      y2: identical(y2, _unset) ? this.y2 : y2 as double?,
      creatorId: identical(creatorId, _unset)
          ? this.creatorId
          : creatorId as String?,
      ownerId: identical(ownerId, _unset) ? this.ownerId : ownerId as String?,
      zoneId: identical(zoneId, _unset) ? this.zoneId : zoneId as String?,
    );
  }

  factory BoardWidgetInstance.fromJson(Map<String, dynamic> json) {
    return BoardWidgetInstance(
      instanceId: json['instanceId'] as String,
      kind: BoardWidgetKind.fromName(json['kind'] as String),
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      zIndex: json['zIndex'] as int,
      value: json['value'] as int? ?? 0,
      backgroundColor:
          json['backgroundColor'] as int? ?? defaultBoardWidgetBackgroundColor,
      textColor: json['textColor'] as int? ?? defaultBoardWidgetTextColor,
      attachedCardId: json['attachedCardId'] as String?,
      attachOffsetX: (json['attachOffsetX'] as num?)?.toDouble() ?? 0,
      attachOffsetY: (json['attachOffsetY'] as num?)?.toDouble() ?? 0,
      x2: (json['x2'] as num?)?.toDouble(),
      y2: (json['y2'] as num?)?.toDouble(),
      creatorId: json['creatorId'] as String?,
      ownerId: json['ownerId'] as String?,
      zoneId: json['zoneId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'instanceId': instanceId,
      'kind': kind.name,
      'x': x,
      'y': y,
      'zIndex': zIndex,
      if (value != 0) 'value': value,
      if (backgroundColor != defaultBoardWidgetBackgroundColor)
        'backgroundColor': backgroundColor,
      if (textColor != defaultBoardWidgetTextColor) 'textColor': textColor,
      if (attachedCardId != null) 'attachedCardId': attachedCardId,
      if (attachOffsetX != 0) 'attachOffsetX': attachOffsetX,
      if (attachOffsetY != 0) 'attachOffsetY': attachOffsetY,
      if (x2 != null) 'x2': x2,
      if (y2 != null) 'y2': y2,
      if (creatorId != null) 'creatorId': creatorId,
      if (ownerId != null) 'ownerId': ownerId,
      if (zoneId != null) 'zoneId': zoneId,
    };
  }
}

/// Sentinel marker distinguishing "not passed" from "explicitly set to null"
/// for [BoardWidgetInstance.copyWith]'s [BoardWidgetInstance.attachedCardId]
/// parameter -- mirrors the same pattern in `card_instance.dart`.
const Object _unset = Object();
