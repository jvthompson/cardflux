/// Where a [CardInstance] currently lives on the table.
enum CardZone {
  table,
  hand,
  drawPile,
  discardPile;

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
  final String? stackParentId;

  CardInstance copyWith({
    String? definitionId,
    double? x,
    double? y,
    int? zIndex,
    bool? faceUp,
    CardZone? zone,
    Object? ownerId = _unset,
    Object? stackParentId = _unset,
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
    };
  }
}

/// Sentinel marker distinguishing "not passed" from "explicitly set to null"
/// for nullable [CardInstance.copyWith] parameters.
const Object _unset = Object();
