import 'card_instance.dart';
import 'player.dart';

/// A full snapshot of a session: either the host's authoritative truth, or a
/// per-recipient filtered view of it (see networking/state_filter.dart).
class TableState {
  const TableState({
    required this.gameId,
    required this.players,
    required this.cards,
    required this.revision,
  });

  final String gameId;
  final List<PlayerInfo> players;
  final List<CardInstance> cards;
  final int revision;

  TableState copyWith({List<CardInstance>? cards, int? revision}) {
    return TableState(
      gameId: gameId,
      players: players,
      cards: cards ?? this.cards,
      revision: revision ?? this.revision,
    );
  }

  factory TableState.fromJson(Map<String, dynamic> json) {
    return TableState(
      gameId: json['gameId'] as String,
      players: (json['players'] as List)
          .map((e) => PlayerInfo.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      cards: (json['cards'] as List)
          .map((e) => CardInstance.fromJson((e as Map).cast<String, dynamic>()))
          .toList(),
      revision: json['revision'] as int,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'gameId': gameId,
      'players': players.map((p) => p.toJson()).toList(),
      'cards': cards.map((c) => c.toJson()).toList(),
      'revision': revision,
    };
  }
}
