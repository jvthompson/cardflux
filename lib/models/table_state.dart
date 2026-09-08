import 'board_widget_instance.dart';
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
    this.widgets = const [],
  });

  final String gameId;
  final List<PlayerInfo> players;
  final List<CardInstance> cards;
  final int revision;

  /// Board widgets (e.g. a Simple Counter) placed on the table -- unlike
  /// [cards], never owned by a player and never hidden, so unlike `cards`,
  /// nothing here needs `state_filter.dart` redaction.
  final List<BoardWidgetInstance> widgets;

  TableState copyWith({List<CardInstance>? cards, int? revision, List<BoardWidgetInstance>? widgets}) {
    return TableState(
      gameId: gameId,
      players: players,
      cards: cards ?? this.cards,
      revision: revision ?? this.revision,
      widgets: widgets ?? this.widgets,
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
      widgets: (json['widgets'] as List?)
              ?.map((e) => BoardWidgetInstance.fromJson((e as Map).cast<String, dynamic>()))
              .toList() ??
          const [],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'gameId': gameId,
      'players': players.map((p) => p.toJson()).toList(),
      'cards': cards.map((c) => c.toJson()).toList(),
      'revision': revision,
      if (widgets.isNotEmpty) 'widgets': widgets.map((w) => w.toJson()).toList(),
    };
  }
}
