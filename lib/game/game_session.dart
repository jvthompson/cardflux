import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/card_instance.dart';
import '../models/deck_config.dart';
import '../models/game_definition.dart';
import '../models/player.dart';
import '../models/table_state.dart';
import 'table_actions.dart';

const _uuid = Uuid();

/// Wraps the current [TableState] for consumption via `provider`. Used
/// identically by the host (authoritative) and by a client (fed by incoming
/// `fullState` messages via [applyRemoteState] instead of local action
/// calls -- see TableController for how the two differ in practice).
class GameSession extends ChangeNotifier {
  GameSession({required this.localPlayerId, required TableState initialState}) : _state = initialState;

  final String localPlayerId;
  final TableActions _actions = const TableActions();
  TableState _state;

  TableState get state => _state;

  /// Builds a fresh single-player sandbox session (M2): every card from
  /// [game] dealt face-down into one shared draw pile at the table center --
  /// unless [game] is [GameDeckMode.fixedDeck], in which case its own
  /// pre-authored, named deck(s) are dealt via [dealFixedDecks] instead (so
  /// Practice Mode shows the same named-deck tooltip a real match would).
  factory GameSession.localSandbox({
    required GameDefinition game,
    required String localPlayerId,
    double pileX = 0.5,
    double pileY = 0.5,
  }) {
    if (game.deckMode == GameDeckMode.fixedDeck) {
      return GameSession.dealFixedDecks(
        game: game,
        players: [PlayerInfo(id: localPlayerId, name: 'You', role: PlayerRole.host)],
        localPlayerId: localPlayerId,
      );
    }
    return GameSession.dealDeck(
      game: game,
      deckConfig: DeckConfig.full(game),
      localPlayerId: localPlayerId,
      pileX: pileX,
      pileY: pileY,
    );
  }

  /// Builds a fresh session (M5) from a host's [DeckConfig] selection: the
  /// requested quantity of each chosen [game] card, dealt face-down into one
  /// shared draw pile at the table center. Entries referencing an unknown
  /// [DeckEntry.definitionId] are skipped.
  ///
  /// [pileX]/[pileY] are canonical [0,1] fractions of the table's play area,
  /// not pixels -- see `lib/game/geometry_utils.dart` for how a viewer
  /// converts these to their own screen's local pixels (and mirrors them,
  /// for whichever seat views the table from the opposite side).
  factory GameSession.dealDeck({
    required GameDefinition game,
    required DeckConfig deckConfig,
    required String localPlayerId,
    double pileX = 0.5,
    double pileY = 0.5,
  }) {
    final validIds = {for (final c in game.cards) c.id};
    final cards = <CardInstance>[];
    String? rootId;
    var i = 0;
    for (final entry in deckConfig.entries) {
      if (!validIds.contains(entry.definitionId)) continue;
      for (var q = 0; q < entry.quantity; q++) {
        final instanceId = _uuid.v4();
        cards.add(CardInstance(
          instanceId: instanceId,
          definitionId: entry.definitionId,
          x: pileX,
          y: pileY,
          zIndex: i,
          faceUp: false,
          zone: CardZone.drawPile,
          // All cards anchor directly to the first card, forming one pile.
          stackParentId: i == 0 ? null : rootId,
        ));
        rootId ??= instanceId;
        i++;
      }
    }
    final state = TableState(
      gameId: game.id,
      players: [PlayerInfo(id: localPlayerId, name: 'You', role: PlayerRole.host)],
      cards: cards,
      revision: 0,
    );
    return GameSession(localPlayerId: localPlayerId, initialState: state);
  }

  /// Builds a fresh networked session from two independent per-player
  /// [DeckConfig] selections (the Load Deck screen): each owner's cards are
  /// dealt face-down into their *own* [CardZone.drawPile] stack (a separate
  /// stackParentId chain per owner), unlike [dealDeck]'s single unowned
  /// shared pile. Canonical `x`/`y` are unused for these cards -- a personal
  /// deck renders via a fixed-position zone widget (see `DeckZoneWidget`),
  /// never the free-form table `Stack`. Entries referencing an unknown
  /// [DeckEntry.definitionId] are skipped, same as [dealDeck].
  factory GameSession.dealPlayerDecks({
    required GameDefinition game,
    required Map<String, DeckConfig> deckConfigsByPlayerId,
    required List<PlayerInfo> players,
    required String localPlayerId,
  }) {
    final validIds = {for (final c in game.cards) c.id};
    final cards = <CardInstance>[];
    var i = 0;
    for (final entry in deckConfigsByPlayerId.entries) {
      final ownerId = entry.key;
      String? rootId;
      for (final deckEntry in entry.value.entries) {
        if (!validIds.contains(deckEntry.definitionId)) continue;
        for (var q = 0; q < deckEntry.quantity; q++) {
          final instanceId = _uuid.v4();
          cards.add(CardInstance(
            instanceId: instanceId,
            definitionId: deckEntry.definitionId,
            x: 0.5,
            y: 0.5,
            zIndex: i,
            faceUp: false,
            zone: CardZone.drawPile,
            ownerId: ownerId,
            stackParentId: rootId,
          ));
          rootId ??= instanceId;
          i++;
        }
      }
    }
    final state = TableState(gameId: game.id, players: players, cards: cards, revision: 0);
    return GameSession(localPlayerId: localPlayerId, initialState: state);
  }

  /// Builds a fresh session from a [GameDeckMode.fixedDeck] game's own
  /// pre-authored [GameDefinition.fixedDecks] -- no player ever builds or
  /// chooses these (contrast [dealPlayerDecks]). Each deck is dealt
  /// face-down into its own unowned, shared stack (same [CardZone.drawPile]
  /// convention as [dealDeck]'s single shared pile -- draw/shuffle already
  /// work for anyone on an unowned pile, no new guards needed) at its own
  /// canonical position via [_fixedDeckPosition], clustered around the
  /// host's middle-right (mirrors to the client's middle-left automatically,
  /// same as any other canonical table position). A deck with empty
  /// [FixedDeckDefinition.entries] gets one of every card in [game]; entries
  /// referencing an unknown [DeckEntry.definitionId] are skipped, same as
  /// [dealDeck]/[dealPlayerDecks].
  factory GameSession.dealFixedDecks({
    required GameDefinition game,
    required List<PlayerInfo> players,
    required String localPlayerId,
  }) {
    final validIds = {for (final c in game.cards) c.id};
    final cards = <CardInstance>[];
    final fixedDeckNames = <String, String>{};
    var i = 0;
    for (var d = 0; d < game.fixedDecks.length; d++) {
      final deck = game.fixedDecks[d];
      final entries = deck.entries.isNotEmpty
          ? deck.entries
          : [for (final c in game.cards) DeckEntry(definitionId: c.id, quantity: 1)];
      final (px, py) = _fixedDeckPosition(d, game.fixedDecks.length);
      String? rootId;
      for (final entry in entries) {
        if (!validIds.contains(entry.definitionId)) continue;
        for (var q = 0; q < entry.quantity; q++) {
          final instanceId = _uuid.v4();
          cards.add(CardInstance(
            instanceId: instanceId,
            definitionId: entry.definitionId,
            x: px,
            y: py,
            zIndex: i,
            faceUp: false,
            zone: CardZone.drawPile,
            stackParentId: rootId,
          ));
          rootId ??= instanceId;
          i++;
        }
      }
      if (rootId != null) fixedDeckNames[rootId] = deck.name;
    }
    final state = TableState(
      gameId: game.id,
      players: players,
      cards: cards,
      revision: 0,
      fixedDeckNames: fixedDeckNames,
    );
    return GameSession(localPlayerId: localPlayerId, initialState: state);
  }

  /// Canonical [0,1] position for the [index]th of [count] fixed decks,
  /// clustered around the host's middle-right (`x` fixed, `y` spread evenly
  /// around center for `count` > 1) so multiple named decks don't overlap.
  static (double, double) _fixedDeckPosition(int index, int count) {
    const x = 0.8;
    const centerY = 0.5;
    const spacing = 0.15;
    if (count <= 1) return (x, centerY);
    return (x, centerY + (index - (count - 1) / 2) * spacing);
  }

  void moveCard(String instanceId, double x, double y) {
    _state = _actions.moveCard(_state, instanceId: instanceId, x: x, y: y);
    notifyListeners();
  }

  void moveStack(String rootInstanceId, double x, double y) {
    _state = _actions.moveStack(_state, rootInstanceId: rootInstanceId, x: x, y: y);
    notifyListeners();
  }

  void flipCard(String instanceId) {
    _state = _actions.flipCard(_state, instanceId: instanceId);
    notifyListeners();
  }

  void stackCard(String instanceId, String ontoInstanceId) {
    _state = _actions.stackCard(_state, instanceId: instanceId, ontoInstanceId: ontoInstanceId);
    notifyListeners();
  }

  /// Reorders within [ownerId]'s hand, defaulting to this session's own
  /// local player -- see [drawCard]'s doc for why the host overrides this
  /// when applying a networked request on the client's behalf.
  void reorderHand(String instanceId, int targetIndex, {String? ownerId}) {
    _state = _actions.reorderHand(
      _state,
      instanceId: instanceId,
      ownerId: ownerId ?? localPlayerId,
      targetIndex: targetIndex,
    );
    notifyListeners();
  }

  /// Moves into [ownerId]'s hand, defaulting to this session's own local
  /// player -- see [drawCard]'s doc for why the host overrides this.
  void moveToHand(String instanceId, {String? ownerId}) {
    _state = _actions.moveToHand(_state, instanceId: instanceId, ownerId: ownerId ?? localPlayerId);
    notifyListeners();
  }

  /// Draws into [ownerId]'s hand, defaulting to this session's own local
  /// player -- the host overrides this to the requesting client's id when
  /// applying a networked draw request on their behalf.
  void drawCard(String pileInstanceId, {String? ownerId}) {
    _state = _actions.drawCard(_state, pileInstanceId: pileInstanceId, ownerId: ownerId ?? localPlayerId);
    notifyListeners();
  }

  void shufflePile(String pileRootInstanceId) {
    _state = _actions.shufflePile(_state, pileRootInstanceId: pileRootInstanceId);
    notifyListeners();
  }

  /// Returns into [ownerId]'s personal deck, defaulting to this session's
  /// own local player -- see [drawCard]'s doc for why the host overrides
  /// this when applying a networked request on the client's behalf.
  void returnToDeck(String instanceId, String? deckRootInstanceId, {String? ownerId, bool toBottom = false}) {
    _state = _actions.returnToDeck(
      _state,
      instanceId: instanceId,
      deckRootInstanceId: deckRootInstanceId,
      ownerId: ownerId ?? localPlayerId,
      toBottom: toBottom,
    );
    notifyListeners();
  }

  /// Replaces the entire state wholesale — used once networking lands (M4)
  /// to apply an incoming `fullState` snapshot from the host.
  void applyRemoteState(TableState newState) {
    if (newState.revision <= _state.revision) return;
    _state = newState;
    notifyListeners();
  }
}
