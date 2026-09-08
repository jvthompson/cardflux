/// Which kind of board widget a [BoardWidgetInstance] is. The widget catalog
/// is hardcoded in app code (unlike `CardDefinition`/`ZoneDefinition`, which
/// are JSON-defined per game) -- a widget is a generic utility available in
/// every game, not game content.
enum BoardWidgetKind {
  simpleCounter,

  /// A small colored circle with no numeric state -- just a marker. Reuses
  /// [BoardWidgetInstance.backgroundColor] for its own color; [value]/
  /// [BoardWidgetInstance.textColor] are meaningless for this kind.
  token;

  static BoardWidgetKind fromName(String name) => BoardWidgetKind.values.byName(name);
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
const int defaultBoardWidgetBackgroundColor = 0xFF455A64; // Colors.blueGrey.shade700
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
      attachedCardId: identical(attachedCardId, _unset) ? this.attachedCardId : attachedCardId as String?,
      attachOffsetX: attachOffsetX ?? this.attachOffsetX,
      attachOffsetY: attachOffsetY ?? this.attachOffsetY,
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
      backgroundColor: json['backgroundColor'] as int? ?? defaultBoardWidgetBackgroundColor,
      textColor: json['textColor'] as int? ?? defaultBoardWidgetTextColor,
      attachedCardId: json['attachedCardId'] as String?,
      attachOffsetX: (json['attachOffsetX'] as num?)?.toDouble() ?? 0,
      attachOffsetY: (json['attachOffsetY'] as num?)?.toDouble() ?? 0,
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
      if (backgroundColor != defaultBoardWidgetBackgroundColor) 'backgroundColor': backgroundColor,
      if (textColor != defaultBoardWidgetTextColor) 'textColor': textColor,
      if (attachedCardId != null) 'attachedCardId': attachedCardId,
      if (attachOffsetX != 0) 'attachOffsetX': attachOffsetX,
      if (attachOffsetY != 0) 'attachOffsetY': attachOffsetY,
    };
  }
}

/// Sentinel marker distinguishing "not passed" from "explicitly set to null"
/// for [BoardWidgetInstance.copyWith]'s [BoardWidgetInstance.attachedCardId]
/// parameter -- mirrors the same pattern in `card_instance.dart`.
const Object _unset = Object();
