/// What kind of thing an [ActiveSearch] targets -- see [ActiveSearch.targetId]
/// for how that id is interpreted for each case.
enum SearchTargetType {
  /// A `ZoneDefinition` (owned or shared) -- [ActiveSearch.targetId] is the
  /// zone's `ZoneDefinition.id`.
  zone,

  /// A free-table pile (a `stackParentId` chain, unrelated to any
  /// `ZoneDefinition`) -- [ActiveSearch.targetId] is the pile's root
  /// `CardInstance.instanceId` (see `StackUtils`).
  pile;

  static SearchTargetType fromName(String name) =>
      SearchTargetType.values.byName(name);
}

/// Records that [searcherId] currently has a Search window open on some
/// zone or pile -- broadcast as part of [TableState] like any other table
/// fact, so every client renders the same "being searched" eyeball badge on
/// that zone/pile, and the searcher's own client knows to show the window.
/// At most one entry exists per [searcherId] at a time (see
/// `TableActions.startSearch`).
class ActiveSearch {
  const ActiveSearch({
    required this.searcherId,
    required this.targetType,
    required this.targetId,
    this.targetOwnerId,
  });

  final String searcherId;
  final SearchTargetType targetType;
  final String targetId;

  /// Only meaningful for [SearchTargetType.zone]: null for a shared zone,
  /// otherwise the id of the player whose own instance of that zone is being
  /// searched. Always null for [SearchTargetType.pile] -- a free-table
  /// pile's ownership is implicit in its cards, not a stored fact here.
  final String? targetOwnerId;

  factory ActiveSearch.fromJson(Map<String, dynamic> json) {
    return ActiveSearch(
      searcherId: json['searcherId'] as String,
      targetType: SearchTargetType.fromName(json['targetType'] as String),
      targetId: json['targetId'] as String,
      targetOwnerId: json['targetOwnerId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'searcherId': searcherId,
      'targetType': targetType.name,
      'targetId': targetId,
      if (targetOwnerId != null) 'targetOwnerId': targetOwnerId,
    };
  }
}
