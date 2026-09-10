import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/board_widget_instance.dart';
import '../models/card_instance.dart';
import '../models/deck_config.dart';
import '../models/game_definition.dart';
import '../models/player.dart';
import '../models/table_state.dart';
import '../models/zone_definition.dart';
import 'table_actions.dart';

const _uuid = Uuid();

/// Wraps the current [TableState] for consumption via `provider`. Used
/// identically by the host (authoritative) and by a client (fed by incoming
/// `fullState` messages via [applyRemoteState] instead of local action
/// calls -- see TableController for how the two differ in practice).
class GameSession extends ChangeNotifier {
  GameSession({
    required this.game,
    required this.localPlayerId,
    required TableState initialState,
  }) : _state = initialState;

  /// The game this session is playing -- needed by [HostGameEngine] to
  /// resolve a zone request (`{zoneId}`, no owner in the payload) down to
  /// whether that zone is shared or belongs to the requesting player, via
  /// [GameDefinition.zones].
  final GameDefinition game;
  final String localPlayerId;
  final TableActions _actions = const TableActions();
  TableState _state;

  TableState get state => _state;

  /// Builds a fresh single-player sandbox session (M2) via [dealFromZones],
  /// with no per-player deck choice available -- any zone marked
  /// [ZoneDefinition.dealsBuiltDeck] falls back to one of every card in
  /// [game] instead of a real Load Deck selection.
  factory GameSession.localSandbox({
    required GameDefinition game,
    required String localPlayerId,
  }) {
    return GameSession.dealFromZones(
      game: game,
      players: [
        PlayerInfo(id: localPlayerId, name: 'You', role: PlayerRole.host),
      ],
      localPlayerId: localPlayerId,
    );
  }

  /// Deals every [player]'s zones from [game]'s [GameDefinition.zones]:
  /// for each player, each owned zone (`!shared`) gets either that player's
  /// entry in [deckConfigsByPlayerId] (if the zone is marked
  /// [ZoneDefinition.dealsBuiltDeck] -- looked up by *both* player id and
  /// zone id, since a game can have more than one such zone, e.g. METW's
  /// Draw Deck and Location Deck; falls back to one of every card in [game]
  /// if no config was supplied for that zone, e.g. Practice Mode) or its own
  /// static [ZoneDefinition.entries] (typically empty, e.g. a discard pile
  /// starting empty). Each shared zone is dealt once, unowned, at its own
  /// canonical position (clustered around the host's middle-right, mirrored
  /// automatically for the client -- see [_sharedZonePosition|), from its
  /// own [ZoneDefinition.entries] (empty meaning one of every card, same
  /// convention the old `FixedDeckDefinition` used). Entries referencing an
  /// unknown [DeckEntry.definitionId] are skipped throughout.
  ///
  /// Zone cards don't need a stack-root identity the way a free-table pile
  /// does (see `StackUtils`) -- a zone is found by `zone`/`zoneId`/`ownerId`
  /// directly, not by walking a `stackParentId` chain, so [stackParentId] is
  /// simply left null for every card dealt here.
  factory GameSession.dealFromZones({
    required GameDefinition game,
    required List<PlayerInfo> players,
    required String localPlayerId,
    Map<String, Map<String, DeckConfig>>? deckConfigsByPlayerId,
  }) {
    final validIds = {for (final c in game.cards) c.id};
    final fullDeckEntries = [
      for (final c in game.cards) DeckEntry(definitionId: c.id, quantity: 1),
    ];
    final cards = <CardInstance>[];
    var i = 0;

    void deal(
      Iterable<DeckEntry> entries, {
      required String zoneId,
      required String? ownerId,
      required double x,
      required double y,
      required bool faceUp,
    }) {
      for (final entry in entries) {
        if (!validIds.contains(entry.definitionId)) continue;
        for (var q = 0; q < entry.quantity; q++) {
          cards.add(
            CardInstance(
              instanceId: _uuid.v4(),
              definitionId: entry.definitionId,
              x: x,
              y: y,
              zIndex: i,
              faceUp: faceUp,
              zone: CardZone.zone,
              zoneId: zoneId,
              ownerId: ownerId,
            ),
          );
          i++;
        }
      }
    }

    for (final player in players) {
      for (final zone in game.zones.where((z) => !z.shared)) {
        final entries = zone.dealsBuiltDeck
            ? (deckConfigsByPlayerId?[player.id]?[zone.id]?.entries ??
                  fullDeckEntries)
            : zone.entries;
        deal(
          entries,
          zoneId: zone.id,
          ownerId: player.id,
          x: 0.5,
          y: 0.5,
          faceUp: zone.faceUp,
        );
      }
    }

    final sharedZones = game.zones.where((z) => z.shared).toList();
    for (var d = 0; d < sharedZones.length; d++) {
      final zone = sharedZones[d];
      final entries = zone.entries.isNotEmpty ? zone.entries : fullDeckEntries;
      final (px, py) = _sharedZonePosition(d, sharedZones.length);
      deal(
        entries,
        zoneId: zone.id,
        ownerId: null,
        x: px,
        y: py,
        faceUp: zone.faceUp,
      );
    }

    final state = TableState(
      gameId: game.id,
      players: players,
      cards: cards,
      revision: 0,
    );
    return GameSession(
      game: game,
      localPlayerId: localPlayerId,
      initialState: state,
    );
  }

  /// Canonical [0,1] position for the [index]th of [count] shared zones,
  /// clustered around the host's middle-right (`x` fixed, `y` spread evenly
  /// around center for `count` > 1) so multiple shared zones don't overlap.
  static (double, double) _sharedZonePosition(int index, int count) {
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
    _state = _actions.moveStack(
      _state,
      rootInstanceId: rootInstanceId,
      x: x,
      y: y,
    );
    notifyListeners();
  }

  void moveGroup(
    String primaryInstanceId,
    List<String> passengerRootInstanceIds,
    double x,
    double y,
  ) {
    _state = _actions.moveGroup(
      _state,
      primaryInstanceId: primaryInstanceId,
      passengerRootInstanceIds: passengerRootInstanceIds,
      x: x,
      y: y,
    );
    notifyListeners();
  }

  void rotateStack(String rootInstanceId, {required bool clockwise}) {
    _state = _actions.rotateStack(
      _state,
      rootInstanceId: rootInstanceId,
      clockwise: clockwise,
    );
    notifyListeners();
  }

  void flipCard(String instanceId) {
    _state = _actions.flipCard(_state, instanceId: instanceId);
    notifyListeners();
  }

  void stackCard(String instanceId, String ontoInstanceId) {
    _state = _actions.stackCard(
      _state,
      instanceId: instanceId,
      ontoInstanceId: ontoInstanceId,
    );
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
    _state = _actions.moveToHand(
      _state,
      instanceId: instanceId,
      ownerId: ownerId ?? localPlayerId,
    );
    notifyListeners();
  }

  /// Draws the top card of the free-table pile rooted at [pileInstanceId]
  /// into [ownerId]'s hand, defaulting to this session's own local player --
  /// the host overrides this to the requesting client's id when applying a
  /// networked draw request on their behalf. For a zone (draw deck, discard
  /// pile, etc.) see [drawFromZone] instead.
  void drawCard(String pileInstanceId, {String? ownerId}) {
    _state = _actions.drawCard(
      _state,
      pileInstanceId: pileInstanceId,
      ownerId: ownerId ?? localPlayerId,
    );
    notifyListeners();
  }

  void shufflePile(String pileRootInstanceId) {
    _state = _actions.shufflePile(
      _state,
      pileRootInstanceId: pileRootInstanceId,
    );
    notifyListeners();
  }

  /// Draws the top card of the zone [zoneId] (owned by [zoneOwnerId], null
  /// for a shared zone) into [toOwnerId]'s hand, defaulting to this
  /// session's own local player.
  void drawFromZone(
    String zoneId, {
    required String? zoneOwnerId,
    String? toOwnerId,
  }) {
    _state = _actions.drawFromZone(
      _state,
      zoneId: zoneId,
      zoneOwnerId: zoneOwnerId,
      toOwnerId: toOwnerId ?? localPlayerId,
    );
    notifyListeners();
  }

  /// Returns [instanceId] to the zone [zoneId] (owned by [zoneOwnerId], null
  /// for a shared zone), detached from wherever it was, showing its face
  /// according to that zone's own [ZoneDefinition.faceUp].
  void returnToZone(
    String instanceId,
    String zoneId, {
    required String? zoneOwnerId,
    bool toBottom = false,
  }) {
    _state = _actions.returnToZone(
      _state,
      instanceId: instanceId,
      zoneId: zoneId,
      zoneOwnerId: zoneOwnerId,
      faceUp: _zoneDefinition(zoneId).faceUp,
      toBottom: toBottom,
    );
    notifyListeners();
  }

  /// Shuffles the zone [zoneId] (owned by [zoneOwnerId], null for a shared
  /// zone) -- a no-op if that zone's own [ZoneDefinition.shuffleable] is
  /// false (e.g. a discard pile, whose order is a history rather than a
  /// randomized pool).
  void shuffleZone(String zoneId, {required String? zoneOwnerId}) {
    if (!_zoneDefinition(zoneId).shuffleable) return;
    _state = _actions.shuffleZone(
      _state,
      zoneId: zoneId,
      zoneOwnerId: zoneOwnerId,
    );
    notifyListeners();
  }

  ZoneDefinition _zoneDefinition(String zoneId) =>
      game.zones.firstWhere((z) => z.id == zoneId);

  // --- Board widgets -----------------------------------------------

  void createWidget(
    String instanceId,
    BoardWidgetKind kind,
    double x,
    double y,
  ) {
    _state = _actions.createWidget(
      _state,
      instanceId: instanceId,
      kind: kind,
      x: x,
      y: y,
    );
    notifyListeners();
  }

  void createArrow(
    String instanceId,
    double x,
    double y,
    double x2,
    double y2, {
    required String creatorId,
  }) {
    _state = _actions.createArrow(
      _state,
      instanceId: instanceId,
      x: x,
      y: y,
      x2: x2,
      y2: y2,
      creatorId: creatorId,
    );
    notifyListeners();
  }

  void moveWidget(String instanceId, double x, double y) {
    _state = _actions.moveWidget(_state, instanceId: instanceId, x: x, y: y);
    notifyListeners();
  }

  void setWidgetValue(String instanceId, int value) {
    _state = _actions.setWidgetValue(
      _state,
      instanceId: instanceId,
      value: value,
    );
    notifyListeners();
  }

  void deleteWidget(String instanceId) {
    _state = _actions.deleteWidget(_state, instanceId: instanceId);
    notifyListeners();
  }

  void setWidgetColors(String instanceId, int backgroundColor, int textColor) {
    _state = _actions.setWidgetColors(
      _state,
      instanceId: instanceId,
      backgroundColor: backgroundColor,
      textColor: textColor,
    );
    notifyListeners();
  }

  void duplicateWidget(
    String sourceInstanceId,
    String newInstanceId,
    double x,
    double y,
  ) {
    _state = _actions.duplicateWidget(
      _state,
      sourceInstanceId: sourceInstanceId,
      newInstanceId: newInstanceId,
      x: x,
      y: y,
    );
    notifyListeners();
  }

  void attachWidgetToCard(
    String instanceId,
    String cardId,
    double x,
    double y,
  ) {
    _state = _actions.attachWidgetToCard(
      _state,
      instanceId: instanceId,
      cardId: cardId,
      x: x,
      y: y,
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
