import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/active_search.dart';
import '../models/board_widget_instance.dart';
import '../models/card_definition.dart';
import '../models/card_instance.dart';
import '../models/deck_config.dart';
import '../models/game_definition.dart';
import '../models/player.dart';
import '../models/standard_deck.dart';
import '../models/table_state.dart';
import '../models/zone_definition.dart';
import 'shared_zone_layout.dart';
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
    this.isLocalPractice = false,
  }) : _state = initialState;

  /// The game this session is playing -- needed by [HostGameEngine] to
  /// resolve a zone request (`{zoneId}`, no owner in the payload) down to
  /// whether that zone is shared or belongs to the requesting player, via
  /// [GameDefinition.zones].
  final GameDefinition game;
  final String localPlayerId;

  /// True only for a local multi-seat practice session (see
  /// [GameSession.localPractice]) -- lets one real person "hot-seat" between
  /// several simulated players via [setActiveSeat] instead of always acting
  /// as [localPlayerId]. False (the default) for every host/client session,
  /// where [actingPlayerId] is simply [localPlayerId] and can't be changed.
  final bool isLocalPractice;
  String? _activeSeatId;

  final TableActions _actions = const TableActions();
  TableState _state;

  TableState get state => _state;

  /// The player id [HostTableController] acts/deals as right now --
  /// [localPlayerId] normally, or whichever seat [setActiveSeat] last picked
  /// in a local practice session. Every ownership/zone/search/arrow check
  /// should key off this, not [localPlayerId] directly, so hot-seat
  /// switching actually changes what's interactable; table *layout*
  /// (rotation, mirroring, avatar photo source) should keep using
  /// [localPlayerId] instead, since that must stay anchored to one seat
  /// regardless of which seat is currently active.
  String get actingPlayerId => _activeSeatId ?? localPlayerId;

  /// Switches which seat this local practice session is currently acting
  /// as -- a no-op outside a [isLocalPractice] session. See [actingPlayerId].
  void setActiveSeat(String playerId) {
    if (!isLocalPractice) return;
    _activeSeatId = playerId;
    notifyListeners();
  }

  /// Builds a fresh local multi-seat practice session via [dealFromZones]:
  /// [players] (1-4 of them) are all simulated by the one real person at
  /// this device, who starts out acting as `players.first` and can switch
  /// via [setActiveSeat] -- see [actingPlayerId]. [deckConfigsByPlayerId]
  /// works exactly like the networked host path: a zone marked
  /// [ZoneDefinition.dealsBuiltDeck] with no matching entry falls back to
  /// one of every card in [game].
  factory GameSession.localPractice({
    required GameDefinition game,
    required List<PlayerInfo> players,
    Map<String, Map<String, DeckConfig>>? deckConfigsByPlayerId,
  }) {
    return GameSession.dealFromZones(
      game: game,
      players: players,
      localPlayerId: players.first.id,
      deckConfigsByPlayerId: deckConfigsByPlayerId,
      isLocalPractice: true,
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
  /// canonical position: centered on the table, arranged side by side in a
  /// row with any other shared zone that also uses the automatic layout,
  /// unless it sets a nonzero [ZoneDefinition.offsetX]/[ZoneDefinition.offsetY],
  /// in which case it's placed at that pixel offset from center instead (and
  /// excluded from the row the remaining zones form) -- see
  /// [_sharedZonePosition]. Its contents come from
  /// [ZoneDefinition.standardDeck] (one of each generated standard playing
  /// card) if set, else [sharedDeckConfigsByZoneId]'s entry for this zone (a
  /// deck resolved from [ZoneDefinition.deckName] by the caller, since that
  /// requires disk I/O this synchronous factory can't do itself) if present,
  /// else its own [ZoneDefinition.entries] (empty meaning one of every card
  /// in [game], same convention the old `FixedDeckDefinition` used -- unless
  /// [ZoneDefinition.isDiscardPile] is set, in which case empty always means
  /// "start empty" instead, exactly like an owned discard pile, since a
  /// discard pile should never auto-populate with the full deck just for
  /// being shared). Entries referencing an unknown [DeckEntry.definitionId]
  /// are skipped throughout.
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
    Map<String, DeckConfig>? sharedDeckConfigsByZoneId,
    bool isLocalPractice = false,
  }) {
    // Generated here (rather than trusting every caller to have already
    // merged them into `game.cards`, which `GameLoader` does for the real
    // app) so a standard-deck zone deals correctly regardless of caller --
    // see `ZoneDefinition.standardDeck`.
    final standardDeckCards = game.zones.any((z) => z.shared && z.standardDeck)
        ? buildStandardDeckCards()
        : const <CardDefinition>[];
    final validIds = {
      for (final c in game.cards) c.id,
      for (final c in standardDeckCards) c.id,
    };
    final definitionsById = {
      for (final c in game.cards) c.id: c,
      for (final c in standardDeckCards) c.id: c,
    };
    final fullDeckEntries = [
      for (final c in game.cards) DeckEntry(definitionId: c.id, quantity: 1),
    ];
    final standardDeckEntries = [
      for (final c in standardDeckCards) DeckEntry(definitionId: c.id, quantity: 1),
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
      required bool autoShuffle,
    }) {
      // Expanded to one definitionId per copy before assigning zIndex, so
      // shuffling this flat list (rather than the still-quantity-grouped
      // `entries`) randomizes actual card order, not just which entry's
      // whole stack of copies goes first.
      final definitionIds = [
        for (final entry in entries)
          if (validIds.contains(entry.definitionId))
            for (var q = 0; q < entry.quantity; q++) entry.definitionId,
      ];
      if (autoShuffle) definitionIds.shuffle();
      for (final definitionId in definitionIds) {
        cards.add(
          CardInstance(
            instanceId: _uuid.v4(),
            definitionId: definitionId,
            x: x,
            y: y,
            zIndex: i,
            faceUp: faceUp,
            zone: CardZone.zone,
            zoneId: zoneId,
            ownerId: ownerId,
            unownable: definitionsById[definitionId]?.unownable ?? false,
          ),
        );
        i++;
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
          autoShuffle: zone.autoShuffle,
        );
      }
    }

    final sharedZones = game.zones.where((z) => z.shared).toList();
    final positionsByZoneId = sharedZonePositions(game.zones);
    for (final zone in sharedZones) {
      final List<DeckEntry> entries;
      if (zone.standardDeck) {
        entries = standardDeckEntries;
      } else {
        final loadedDeck = sharedDeckConfigsByZoneId?[zone.id];
        entries = loadedDeck != null
            ? loadedDeck.entries
            : (zone.entries.isNotEmpty || zone.isDiscardPile
                  ? zone.entries
                  : fullDeckEntries);
      }
      final (px, py) = positionsByZoneId[zone.id]!;
      deal(
        entries,
        zoneId: zone.id,
        ownerId: null,
        x: px,
        y: py,
        faceUp: zone.faceUp,
        autoShuffle: zone.autoShuffle,
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
      isLocalPractice: isLocalPractice,
    );
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

  /// Reassigns [instanceId]'s ownership to [newOwnerId] (null releases it
  /// back to unowned) -- see `TableActions.giveCard`.
  void giveCard(String instanceId, String? newOwnerId) {
    _state = _actions.giveCard(
      _state,
      instanceId: instanceId,
      newOwnerId: newOwnerId,
    );
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

  /// Draws the top [count] cards of the free-table pile rooted at
  /// [pileInstanceId] into [ownerId]'s hand, defaulting to this session's
  /// own local player -- the host overrides this to the requesting client's
  /// id when applying a networked draw request on their behalf. For a zone
  /// (draw deck, discard pile, etc.) see [drawFromZone] instead.
  void drawCard(String pileInstanceId, {String? ownerId, int count = 1}) {
    _state = _actions.drawCard(
      _state,
      pileInstanceId: pileInstanceId,
      ownerId: ownerId ?? localPlayerId,
      count: count,
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

  /// Draws the top [count] cards of the zone [zoneId] (owned by
  /// [zoneOwnerId], null for a shared zone) into [toOwnerId]'s hand,
  /// defaulting to this session's own local player.
  void drawFromZone(
    String zoneId, {
    required String? zoneOwnerId,
    String? toOwnerId,
    int count = 1,
  }) {
    _state = _actions.drawFromZone(
      _state,
      zoneId: zoneId,
      zoneOwnerId: zoneOwnerId,
      toOwnerId: toOwnerId ?? localPlayerId,
      count: count,
    );
    notifyListeners();
  }

  /// Returns [instanceId] to the zone [zoneId] (owned by [zoneOwnerId], null
  /// for a shared zone), detached from wherever it was, showing its face
  /// according to that zone's own [ZoneDefinition.faceUp]. If [zoneId] is
  /// shared, its reserved [sharedZonePositions] slot is passed through as a
  /// fallback anchor, so landing the first card there (see
  /// `TableActions.returnToZone`) snaps it into that slot instead of
  /// wherever it was dropped from.
  void returnToZone(
    String instanceId,
    String zoneId, {
    required String? zoneOwnerId,
    bool toBottom = false,
  }) {
    final zone = _zoneDefinition(zoneId);
    _state = _actions.returnToZone(
      _state,
      instanceId: instanceId,
      zoneId: zoneId,
      zoneOwnerId: zoneOwnerId,
      faceUp: zone.faceUp,
      toBottom: toBottom,
      emptySharedPosition: zone.shared
          ? sharedZonePositions(game.zones)[zoneId]
          : null,
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

  // --- Search --------------------------------------------------------

  /// Opens a Search window on the zone [zoneId] (owned by [zoneOwnerId],
  /// null for a shared zone), attributed to [searcherId] -- defaulting to
  /// this session's own local player, overridden by `HostGameEngine` when
  /// applying a networked request on a client's behalf.
  void startSearchZone(
    String zoneId, {
    required String? zoneOwnerId,
    String? searcherId,
  }) {
    _state = _actions.startSearch(
      _state,
      searcherId: searcherId ?? localPlayerId,
      targetType: SearchTargetType.zone,
      targetId: zoneId,
      targetOwnerId: zoneOwnerId,
    );
    notifyListeners();
  }

  /// Opens a Search window on the free-table pile rooted at
  /// [pileRootInstanceId], attributed to [searcherId] -- see
  /// [startSearchZone]'s doc for the defaulting convention.
  void startSearchPile(String pileRootInstanceId, {String? searcherId}) {
    _state = _actions.startSearch(
      _state,
      searcherId: searcherId ?? localPlayerId,
      targetType: SearchTargetType.pile,
      targetId: pileRootInstanceId,
    );
    notifyListeners();
  }

  /// Closes [searcherId]'s Search window, defaulting to this session's own
  /// local player.
  void stopSearch({String? searcherId}) {
    _state = _actions.stopSearch(
      _state,
      searcherId: searcherId ?? localPlayerId,
    );
    notifyListeners();
  }

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

  /// Updates every non-host player's [PlayerInfo.connected] flag from
  /// [connectedNonHostIds] (`HostServer.roster`, minus the host) -- a
  /// disconnected seat's cards/zones are left exactly where they are; this
  /// only drives the cosmetic "disconnected" indicator on that player's
  /// panel header (see `TableScreen`). The host itself is always connected.
  void syncConnectedPlayerIds(Set<String> connectedNonHostIds) {
    final updated = [
      for (final p in _state.players)
        p.copyWith(connected: p.role == PlayerRole.host || connectedNonHostIds.contains(p.id)),
    ];
    _state = _state.copyWith(players: updated, revision: _state.revision + 1);
    notifyListeners();
  }
}
