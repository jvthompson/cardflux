import 'pack_setting.dart';

/// One named set of cards within a [GameDefinition] -- [id] matches a
/// subfolder in the game's directory holding that set's card art. Metadata
/// only: the actual cards live flattened in [GameDefinition.cards], each
/// tagged with the enclosing set's [id] via [CardDefinition.setId].
class GameSet {
  const GameSet({required this.id, required this.name, this.packSettings = const []});

  final String id;
  final String name;

  /// How a Pack Generator widget assembles a pack from this set -- see
  /// `selectPackCards`. Empty means "no configured breakdown": a pack is
  /// just [defaultPackCardCount] random cards from this set, tags ignored.
  final List<PackSetting> packSettings;

  factory GameSet.fromJson(Map<String, dynamic> json) {
    return GameSet(
      id: json['id'] as String,
      name: json['name'] as String,
      packSettings: (json['packSettings'] as List?)
              ?.map((e) => PackSetting.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (packSettings.isNotEmpty) 'packSettings': packSettings.map((p) => p.toJson()).toList(),
      };

  GameSet copyWith({String? name, List<PackSetting>? packSettings}) {
    return GameSet(id: id, name: name ?? this.name, packSettings: packSettings ?? this.packSettings);
  }
}
