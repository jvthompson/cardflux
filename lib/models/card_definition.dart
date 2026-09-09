/// A card's default table rotation relative to plain upright portrait --
/// some cards (e.g. METW's Region cards) are physically landscape, printed
/// sideways on an otherwise portrait-shaped card image. [right] is 90°
/// clockwise from portrait, [left] is 90° counter-clockwise. Only affects a
/// card's own loose on-table look (see `DraggableCard`/`PileWidget`'s
/// `applyOrientation`) -- a hand card or anything sitting in a zone always
/// renders plain portrait regardless of this.
enum CardOrientation { portrait, left, right }

/// Sentinel default for [CardDefinition.copyWith]'s nullable parameters, so
/// "omitted" (keep current value) is distinguishable from an explicitly
/// passed `null` (clear the field).
const Object _unset = Object();

/// A template describing one kind of card available in a [GameDefinition]'s
/// card pool. Not a card actually on the table — see [CardInstance] for that.
class CardDefinition {
  const CardDefinition({
    required this.id,
    required this.cardTitle,
    this.colorHex,
    this.suit,
    this.rank,
    this.imagePath,
    this.extraFields = const {},
    this.types = const [],
    this.orientation = CardOrientation.portrait,
    this.setId,
  });

  final String id;
  final String cardTitle;
  final String? colorHex;
  final String? suit;
  final String? rank;
  final String? imagePath;
  final Map<String, String> extraFields;

  /// This card's tags (e.g. "Character", "Item") -- one flat list regardless
  /// of which [GameDefinition.tagGroups] group each tag belongs to; matched
  /// against each group's tags to drive its own filter button. A card with
  /// no tags in a given group is never hidden by that group's filter. Not
  /// validated against the game's declared taxonomy -- an unrecognized tag
  /// just never matches a chip.
  final List<String> types;

  /// Which of [GameDefinition.sets] this card belongs to, stamped on by
  /// [GameDefinition.fromJson] when parsing the nested `sets` schema -- null
  /// for a game with no set concept (flat top-level `cards` schema). Drives
  /// the Deck Editor's Set filter chips the same way [types] drives Type.
  final String? setId;

  /// This card's default table rotation -- see [CardOrientation].
  final CardOrientation orientation;

  factory CardDefinition.fromJson(Map<String, dynamic> json) {
    return CardDefinition(
      id: json['id'] as String,
      cardTitle: json['cardTitle'] as String,
      colorHex: json['colorHex'] as String?,
      suit: json['suit'] as String?,
      rank: json['rank'] as String?,
      imagePath: json['imagePath'] as String?,
      extraFields: (json['extraFields'] as Map?)?.cast<String, String>() ?? const {},
      types: (json['types'] as List?)?.cast<String>().toList() ?? const [],
      orientation: CardOrientation.values.byName(json['orientation'] as String? ?? 'portrait'),
      setId: json['setId'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'cardTitle': cardTitle,
      if (colorHex != null) 'colorHex': colorHex,
      if (suit != null) 'suit': suit,
      if (rank != null) 'rank': rank,
      if (imagePath != null) 'imagePath': imagePath,
      if (extraFields.isNotEmpty) 'extraFields': extraFields,
      if (types.isNotEmpty) 'types': types,
      if (orientation != CardOrientation.portrait) 'orientation': orientation.name,
      if (setId != null) 'setId': setId,
    };
  }

  /// Returns a copy with the given fields replaced. For the nullable fields
  /// ([colorHex], [suit], [rank], [imagePath], [setId]), omitting a
  /// parameter keeps the current value; passing `null` explicitly clears it.
  CardDefinition copyWith({
    String? id,
    String? cardTitle,
    Object? colorHex = _unset,
    Object? suit = _unset,
    Object? rank = _unset,
    Object? imagePath = _unset,
    Map<String, String>? extraFields,
    List<String>? types,
    CardOrientation? orientation,
    Object? setId = _unset,
  }) {
    return CardDefinition(
      id: id ?? this.id,
      cardTitle: cardTitle ?? this.cardTitle,
      colorHex: identical(colorHex, _unset) ? this.colorHex : colorHex as String?,
      suit: identical(suit, _unset) ? this.suit : suit as String?,
      rank: identical(rank, _unset) ? this.rank : rank as String?,
      imagePath: identical(imagePath, _unset) ? this.imagePath : imagePath as String?,
      extraFields: extraFields ?? this.extraFields,
      types: types ?? this.types,
      orientation: orientation ?? this.orientation,
      setId: identical(setId, _unset) ? this.setId : setId as String?,
    );
  }
}
