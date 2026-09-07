/// A template describing one kind of card available in a [GameDefinition]'s
/// card pool. Not a card actually on the table — see [CardInstance] for that.
class CardDefinition {
  const CardDefinition({
    required this.id,
    required this.label,
    required this.colorHex,
    this.suit,
    this.rank,
    this.imagePath,
    this.extraFields = const {},
  });

  final String id;
  final String label;
  final String colorHex;
  final String? suit;
  final String? rank;
  final String? imagePath;
  final Map<String, String> extraFields;

  factory CardDefinition.fromJson(Map<String, dynamic> json) {
    return CardDefinition(
      id: json['id'] as String,
      label: json['label'] as String,
      colorHex: json['colorHex'] as String,
      suit: json['suit'] as String?,
      rank: json['rank'] as String?,
      imagePath: json['imagePath'] as String?,
      extraFields: (json['extraFields'] as Map?)?.cast<String, String>() ?? const {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'colorHex': colorHex,
      if (suit != null) 'suit': suit,
      if (rank != null) 'rank': rank,
      if (imagePath != null) 'imagePath': imagePath,
      if (extraFields.isNotEmpty) 'extraFields': extraFields,
    };
  }
}
