/// One row of a [GameSet]'s Pack Settings -- "[count] random cards tagged
/// [tag]" -- see `selectPackCards` (lib/game/pack_generator.dart) for how a
/// list of these turns into an actual pack.
class PackSetting {
  const PackSetting({required this.tag, required this.count});

  final String tag;
  final int count;

  factory PackSetting.fromJson(Map<String, dynamic> json) {
    return PackSetting(tag: json['tag'] as String, count: json['count'] as int);
  }

  Map<String, dynamic> toJson() => {'tag': tag, 'count': count};

  PackSetting copyWith({String? tag, int? count}) {
    return PackSetting(tag: tag ?? this.tag, count: count ?? this.count);
  }
}
