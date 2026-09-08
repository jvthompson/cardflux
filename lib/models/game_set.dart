/// One named set of cards within a [GameDefinition] -- [id] matches a
/// subfolder in the game's directory holding that set's card art. Metadata
/// only: the actual cards live flattened in [GameDefinition.cards], each
/// tagged with the enclosing set's [id] via [CardDefinition.setId].
class GameSet {
  const GameSet({required this.id, required this.name});

  final String id;
  final String name;

  factory GameSet.fromJson(Map<String, dynamic> json) {
    return GameSet(id: json['id'] as String, name: json['name'] as String);
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name};
}
