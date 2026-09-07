import 'card_definition.dart';

/// A loaded "game": a named pool of card definitions players can build decks
/// from. Sourced either from a bundled asset (the default standard 52-card
/// deck) or a JSON file in a user-chosen folder on disk (custom games).
class GameDefinition {
  const GameDefinition({required this.id, required this.name, required this.cards});

  final String id;
  final String name;
  final List<CardDefinition> cards;

  factory GameDefinition.fromJson(Map<String, dynamic> json) {
    return GameDefinition(
      id: json['id'] as String,
      name: json['name'] as String,
      cards: (json['cards'] as List)
          .map((e) => CardDefinition.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
    );
  }

  Map<String, dynamic> toJson() {
    return {'id': id, 'name': name, 'cards': cards.map((c) => c.toJson()).toList()};
  }
}
