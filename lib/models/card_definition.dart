/// A card's default table rotation relative to plain upright portrait --
/// some cards (e.g. METW's Region cards) are physically landscape, printed
/// sideways on an otherwise portrait-shaped card image. [right] is 90°
/// clockwise from portrait, [left] is 90° counter-clockwise. Only affects a
/// card's own loose on-table look (see `DraggableCard`/`PileWidget`'s
/// `applyOrientation`) -- a hand card or anything sitting in a zone always
/// renders plain portrait regardless of this.
enum CardOrientation { portrait, left, right }

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

  /// This card's types (e.g. "Character", "Item") -- matched against
  /// [GameDefinition.cardTypes] to drive the Deck Editor's filter chips. A
  /// card with no types is never hidden by any filter. Not validated against
  /// the game's declared taxonomy -- an unrecognized type just never matches
  /// a chip.
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
}
