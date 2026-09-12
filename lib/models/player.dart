enum PlayerRole {
  host,
  client;

  static PlayerRole fromName(String name) => PlayerRole.values.byName(name);
}

class PlayerInfo {
  const PlayerInfo({
    required this.id,
    required this.name,
    required this.role,
    required this.color,
    this.connected = true,
  });

  final String id;
  final String name;
  final PlayerRole role;

  /// ARGB int, one of `boardWidgetColorPalette` -- shown next to this
  /// player's name and as the border color on every card they own (see
  /// `TableScreen`).
  final int color;

  /// Whether this player's connection is currently live -- always true for
  /// the host. A disconnected non-host player in a 3-4 player match keeps
  /// their seat (their cards stay on the table) while this flips to false,
  /// purely to dim their name/indicate they've left; see
  /// `GameSession.syncConnectedPlayerIds`.
  final bool connected;

  PlayerInfo copyWith({String? name, int? color, bool? connected}) {
    return PlayerInfo(
      id: id,
      name: name ?? this.name,
      role: role,
      color: color ?? this.color,
      connected: connected ?? this.connected,
    );
  }

  factory PlayerInfo.fromJson(Map<String, dynamic> json) {
    return PlayerInfo(
      id: json['id'] as String,
      name: json['name'] as String,
      role: PlayerRole.fromName(json['role'] as String),
      color: json['color'] as int,
      connected: json['connected'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() =>
      {'id': id, 'name': name, 'role': role.name, 'color': color, 'connected': connected};
}
