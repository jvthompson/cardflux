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
    this.fixedDeckNames = const {},
  });

  final String gameId;
  final List<PlayerInfo> players;
  final List<CardInstance> cards;
  final int revision;

  /// Root instanceId -> name, for decks dealt by `GameSession.dealFixedDecks`
  /// (see `GameDeckMode.fixedDeck`) -- displayed as a hover tooltip over that
  /// stack on the table. Set once at deal time and never touched again (not
  /// exposed as a [copyWith] parameter), so it survives shuffles for free --
  /// `shufflePile` never changes a stack's root/identity, only draw order.
  final Map<String, String> fixedDeckNames;

  TableState copyWith({List<CardInstance>? cards, int? revision}) {
    return TableState(
      gameId: gameId,
      players: players,
      cards: cards ?? this.cards,
      revision: revision ?? this.revision,
      fixedDeckNames: fixedDeckNames,
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
      fixedDeckNames: (json['fixedDeckNames'] as Map?)?.cast<String, String>() ?? const {},
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'gameId': gameId,
      'players': players.map((p) => p.toJson()).toList(),
      'cards': cards.map((c) => c.toJson()).toList(),
      'revision': revision,
      if (fixedDeckNames.isNotEmpty) 'fixedDeckNames': fixedDeckNames,
    };
  }
}
