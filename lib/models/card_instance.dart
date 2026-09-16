/// Where a [CardInstance] currently lives on the table.
enum CardZone {
  table,
  hand,

  /// Sitting in some `ZoneDefinition` -- see [CardInstance.zoneId] for
  /// which one, and [CardInstance.ownerId] for whether it's a shared
  /// (null) or a specific player's own instance of it. Covers what used to
  /// be a single hardcoded "draw pile" -- a zone can be a draw deck, a
  /// discard pile, or anything else a game's JSON names it.
  zone;

  static CardZone fromName(String name) => CardZone.values.byName(name);
}

/// Sentinel [CardInstance.definitionId] used when filtering an opponent's
/// private hand card for network transmission — see state_filter.dart.
const String hiddenDefinitionId = '__hidden__';

/// An actual card placed on the table for the current session. References a
/// [CardDefinition] by id; carries all per-instance state (position,
/// face/down, ownership, stacking).
class CardInstance {
  CardInstance({
    required this.instanceId,
    required this.definitionId,
    required this.x,
    required this.y,
    required this.zIndex,
    required this.faceUp,
    required this.zone,
    this.ownerId,
    this.stackParentId,
    this.zoneId,
    this.rotationTurns = 0,
    this.unownable = false,
  });

  final String instanceId;
  final String definitionId;

  /// Canonical position as [0,1] fractions of the table's play area (0,0 =
  /// top-left, 1,1 = bottom-right), not pixels -- resolution-independent so
  /// host and client windows of any size agree on where a card sits. See
  /// `lib/game/geometry_utils.dart` for how a viewer converts these to their
  /// own screen's pixels, mirroring both axes for whichever seat views the
  /// table from the opposite side.
  final double x;
  final double y;
  final int zIndex;
  final bool faceUp;
  final CardZone zone;
  final String? ownerId;

  /// Only meaningful for a `CardZone.table` card stacked into a pile (see
  /// `StackUtils`) -- unrelated to [zoneId]/[CardZone.zone], which
  /// identifies zone membership directly rather than via a stack chain.
  final String? stackParentId;

  /// Only set when [zone] is [CardZone.zone] -- which `ZoneDefinition.id`
  /// this card belongs to.
  final String? zoneId;

  /// Quarter-turns applied on top of the ownership-driven 180° mirror flip
  /// -- see `DraggableCard`/`PileWidget`'s `AnimatedRotation`. Deliberately
  /// left unbounded rather than wrapped into 0-3 (see `rotateStack`): the
  /// resulting angle is equivalent mod 4, but AnimatedRotation needs the
  /// raw running count to keep spinning the same direction on every Q/E
  /// press instead of snapping back through zero. A table-only concept:
  /// every transition off the table (`moveToHand`, `drawCard`,
  /// `drawFromZone`, `returnToZone`) resets this to 0 so a card never shows
  /// up sideways in a hand or a deck.
  final int rotationTurns;

  /// Copied once from `CardDefinition.unownable` at deal time (see
  /// `GameSession.dealFromZones`) and never changed afterward -- when true,
  /// `TableActions.moveCard`/`moveGroup`/`stackCard`/`giveCard` force
  /// [ownerId] back to null every time this card lands on the free table,
  /// regardless of who last held it in their hand. Has no effect while the
  /// card is actually in a hand or an owned zone, which still need a real
  /// [ownerId] to know whose instance it is.
  final bool unownable;

  CardInstance copyWith({
    String? definitionId,
    double? x,
    double? y,
    int? zIndex,
    bool? faceUp,
    CardZone? zone,
    Object? ownerId = _unset,
    Object? stackParentId = _unset,
    Object? zoneId = _unset,
    int? rotationTurns,
    bool? unownable,
  }) {
    return CardInstance(
      instanceId: instanceId,
      definitionId: definitionId ?? this.definitionId,
      x: x ?? this.x,
      y: y ?? this.y,
      zIndex: zIndex ?? this.zIndex,
      faceUp: faceUp ?? this.faceUp,
      zone: zone ?? this.zone,
      ownerId: identical(ownerId, _unset) ? this.ownerId : ownerId as String?,
      stackParentId: identical(stackParentId, _unset)
          ? this.stackParentId
          : stackParentId as String?,
      zoneId: identical(zoneId, _unset) ? this.zoneId : zoneId as String?,
      rotationTurns: rotationTurns ?? this.rotationTurns,
      unownable: unownable ?? this.unownable,
    );
  }

  factory CardInstance.fromJson(Map<String, dynamic> json) {
    return CardInstance(
      instanceId: json['instanceId'] as String,
      definitionId: json['definitionId'] as String,
      x: (json['x'] as num).toDouble(),
      y: (json['y'] as num).toDouble(),
      zIndex: json['zIndex'] as int,
      faceUp: json['faceUp'] as bool,
      zone: CardZone.fromName(json['zone'] as String),
      ownerId: json['ownerId'] as String?,
      stackParentId: json['stackParentId'] as String?,
      zoneId: json['zoneId'] as String?,
      rotationTurns: json['rotationTurns'] as int? ?? 0,
      unownable: json['unownable'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'instanceId': instanceId,
      'definitionId': definitionId,
      'x': x,
      'y': y,
      'zIndex': zIndex,
      'faceUp': faceUp,
      'zone': zone.name,
      if (ownerId != null) 'ownerId': ownerId,
      if (stackParentId != null) 'stackParentId': stackParentId,
      if (zoneId != null) 'zoneId': zoneId,
      if (rotationTurns != 0) 'rotationTurns': rotationTurns,
      if (unownable) 'unownable': unownable,
    };
  }
}

/// Sentinel marker distinguishing "not passed" from "explicitly set to null"
/// for nullable [CardInstance.copyWith] parameters.
const Object _unset = Object();
