enum PlayerRole {
  host,
  client;

  static PlayerRole fromName(String name) => PlayerRole.values.byName(name);
}

class PlayerInfo {
  const PlayerInfo({required this.id, required this.name, required this.role});

  final String id;
  final String name;
  final PlayerRole role;

  factory PlayerInfo.fromJson(Map<String, dynamic> json) {
    return PlayerInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      role: PlayerRole.fromName(json['role'] as String),
    );
  }

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'role': role.name};
}
