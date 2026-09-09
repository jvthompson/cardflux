/// One named grouping of card tags within a [GameDefinition] (e.g. "Card
/// Type", "Mana Color") -- each gets its own filter button wherever cards
/// are filtered, and its own chip section on the card detail form. [id] is a
/// stable identity independent of the user-editable [name], the same
/// pattern as `GameSet`/`ZoneDefinition`, since group filter-selection state
/// and reorderable-list keys both need to survive a rename.
class TagGroup {
  const TagGroup({required this.id, required this.name, this.tags = const []});

  final String id;
  final String name;
  final List<String> tags;

  factory TagGroup.fromJson(Map<String, dynamic> json) => TagGroup(
        id: json['id'] as String,
        name: json['name'] as String,
        tags: (json['tags'] as List?)?.cast<String>().toList() ?? const [],
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'tags': tags};

  TagGroup copyWith({String? name, List<String>? tags}) =>
      TagGroup(id: id, name: name ?? this.name, tags: tags ?? this.tags);
}
