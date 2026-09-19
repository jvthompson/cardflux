import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/active_search.dart';
import '../models/board_widget_instance.dart';
import '../models/card_definition.dart';
import '../models/card_instance.dart';
import '../models/deck_config.dart';
import '../models/game_definition.dart';
import '../models/log_entry.dart';
import '../models/player.dart';
import '../models/standard_deck.dart';
import '../models/table_state.dart';
import '../models/zone_definition.dart';
import 'drag_preview.dart';
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
    DateTime? clockStart,
  }) : _state = initialState,
       _clockStart = clockStart ?? DateTime.now();

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

  /// When this session's in-game clock reads `00:00:00` -- `DateTime.now()`
  /// for a fresh deal, or resumed from a loaded save's last log entry (see
  /// `HostGameScreen`/`PracticeGameScreen`'s `clockStart:` argument) so
  /// elapsed time keeps counting up seamlessly across a save/load instead of
  /// jumping back to zero.
  final DateTime _clockStart;

  /// Card-name lookups for log text -- mirrors what every UI screen already
  /// builds from `game.cards` (which `GameLoader`/[dealFromZones] already
  /// merge any standard-deck cards into).
  late final Map<String, CardDefinition> _definitionsById = {
    for (final c in game.cards) c.id: c,
  };

  TableState get state => _state;

  /// Other players' in-progress, uncommitted card drags / TAB-drawn arrows,
  /// keyed by the dragging player's id -- deliberately **not** part of
  /// [TableState], never bumps [revision], never touches [notifyListeners]
  /// or [applyRemoteState]. `TableScreen` reacts to these via narrow
  /// `ValueListenableBuilder`s (the same pattern its own local `_arrowDrag`
  /// preview already uses) so ~20Hz preview traffic never triggers a
  /// `Consumer<GameSession>` rebuild of the entire table. `HostGameEngine`
  /// writes here for both a relayed client preview and the host's own drag;
  /// `ClientGameScreen` writes here for whatever the host relays to it --
  /// same shape either way, so `TableScreen`'s rendering code is written
  /// once for both roles.
  final ValueNotifier<Map<String, CardDragPreview>> cardDragPreviews =
      ValueNotifier({});
  final ValueNotifier<Map<String, ArrowDragPreview>> arrowDragPreviews =
      ValueNotifier({});

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
  /// works exactly like the networked host path: a wholly-missing map falls
  /// back to one of every card in [game] for every
  /// [ZoneDefinition.dealsBuiltDeck] zone.
  factory GameSession.localPractice({
    required GameDefinition game,
    required List<PlayerInfo> players,
    Map<String, DeckConfig>? deckConfigsByPlayerId,
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
  /// chosen deck in [deckConfigsByPlayerId] (if the zone is marked
  /// [ZoneDefinition.dealsBuiltDeck] -- that deck's subdeck named
  /// [ZoneDefinition.deckType] supplies this zone's entries, since a game can
  /// have more than one such zone sharing one deck file, e.g. METW's Draw
  /// Deck and Location Deck; a wholly-missing [deckConfigsByPlayerId] falls
  /// back to one of every card in [game], e.g. Practice Mode with no Load
  /// Deck step -- a chosen deck simply missing that subdeck deals empty
  /// instead, since required-subdeck completeness is validated before a deck
  /// is ever chosen) or its own static [ZoneDefinition.entries] (typically
  /// empty, e.g. a discard pile
  /// starting empty). Each shared zone is dealt once, unowned, into a docked
  /// side panel (see [ZoneDefinition.side]) rather than any canonical table
  /// position -- [x]/[y] are just the same `0.5, 0.5` placeholder owned-zone
  /// cards get, since a zone card's coordinates are never read for display.
  /// Its contents come from
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
    Map<String, DeckConfig>? deckConfigsByPlayerId,
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
      for (final zone in game.zones.where(
        (z) => !z.shared && z.kind == ZoneKind.card,
      )) {
        final entries = zone.dealsBuiltDeck
            ? (deckConfigsByPlayerId == null
                  ? fullDeckEntries
                  : (deckConfigsByPlayerId[player.id]?.entriesFor(zone.deckType) ?? const []))
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

    // One BoardWidgetInstance per (player, widget zone) -- e.g. one Simple
    // Counter per player for a "Life Total"-style zone -- seeded from the
    // zone's own starting value/colors. Never shared (see ZoneKind's doc),
    // so this only ever needs the owned-zone list, unlike the card dealing
    // above which also handles a separate shared-zone loop below.
    final widgets = <BoardWidgetInstance>[];
    var widgetZIndex = 0;
    for (final player in players) {
      for (final zone in game.zones.where(
        (z) => !z.shared && z.kind == ZoneKind.widget,
      )) {
        widgets.add(
          BoardWidgetInstance(
            instanceId: _uuid.v4(),
            kind: switch (zone.widgetKind) {
              ZoneWidgetKind.counter => BoardWidgetKind.simpleCounter,
            },
            x: 0.5,
            y: 0.5,
            zIndex: widgetZIndex,
            value: zone.counterStartingValue,
            backgroundColor: zone.counterStartingColor,
            textColor: zone.counterStartingTextColor,
            ownerId: player.id,
            zoneId: zone.id,
          ),
        );
        widgetZIndex++;
      }
    }

    final sharedZones = game.zones.where((z) => z.shared).toList();
    for (final zone in sharedZones) {
      final List<DeckEntry> entries;
      if (zone.standardDeck) {
        entries = standardDeckEntries;
      } else {
        final loadedDeck = sharedDeckConfigsByZoneId?[zone.id];
        entries = loadedDeck != null
            ? loadedDeck.entriesFor('main_deck')
            : (zone.entries.isNotEmpty || zone.isDiscardPile
                  ? zone.entries
                  : fullDeckEntries);
      }
      deal(
        entries,
        zoneId: zone.id,
        ownerId: null,
        x: 0.5,
        y: 0.5,
        faceUp: zone.faceUp,
        autoShuffle: zone.autoShuffle,
      );
    }

    final state = TableState(
      gameId: game.id,
      players: players,
      cards: cards,
      widgets: widgets,
      revision: 0,
    );
    return GameSession(
      game: game,
      localPlayerId: localPlayerId,
      initialState: state,
      isLocalPractice: isLocalPractice,
    );
  }

  // --- Action log ------------------------------------------------------

  CardInstance? _findCard(String instanceId) {
    for (final c in _state.cards) {
      if (c.instanceId == instanceId) return c;
    }
    return null;
  }

  BoardWidgetInstance? _findWidget(String instanceId) {
    for (final w in _state.widgets) {
      if (w.instanceId == instanceId) return w;
    }
    return null;
  }

  String _playerName(String playerId) {
    for (final p in _state.players) {
      if (p.id == playerId) return p.name;
    }
    return playerId;
  }

  /// Mirrors `state_filter.dart`'s `filterForRecipient` privacy rule: a
  /// card's identity is fair to show in the log (to every player, not just
  /// the owner) exactly when a client would be allowed to see its real face
  /// over the network -- face-up, and either on the table, in a shared zone
  /// (`ownerId == null`), or in an owned zone marked
  /// [ZoneDefinition.visibleToAll]. A hand card is always private,
  /// regardless of face.
  bool _isPubliclyVisible(CardInstance card) {
    if (!card.faceUp) return false;
    switch (card.zone) {
      case CardZone.table:
        return true;
      case CardZone.hand:
        return false;
      case CardZone.zone:
        if (card.ownerId == null) return true;
        return _zoneDefinition(card.zoneId!).visibleToAll;
    }
  }

  /// The card's real name for a log line, or null (meaning the line should
  /// stay generic) unless it was publicly visible (see [_isPubliclyVisible])
  /// immediately before *or* immediately after the action -- so, e.g.,
  /// discarding a face-down hand card face-up into a visible discard pile
  /// still reveals it, and picking up an already-public table card into a
  /// hidden hand still credits the name once.
  String? _revealedCardName(CardInstance? oldCard, CardInstance? newCard) {
    final revealed =
        (oldCard != null && _isPubliclyVisible(oldCard)) ||
        (newCard != null && _isPubliclyVisible(newCard));
    if (!revealed) return null;
    final definitionId = (newCard ?? oldCard)?.definitionId;
    if (definitionId == null) return null;
    return _definitionsById[definitionId]?.cardTitle;
  }

  /// Appends one line to `_state.log`, timestamped against [_clockStart].
  /// Deliberately never bumps `revision` itself -- every call site already
  /// sits alongside a mutation (either `TableActions`' own `revision + 1`,
  /// or the caller's own explicit bump) that does, so this only ever adds
  /// to whichever `revision` is already current.
  void _log(String actingPlayerId, String action) {
    final elapsedMs = DateTime.now().difference(_clockStart).inMilliseconds;
    _state = _state.copyWith(
      log: [
        ..._state.log,
        LogEntry(elapsedMs: elapsedMs, message: '${_playerName(actingPlayerId)} $action'),
      ],
    );
  }

  /// Shared by every action that lands a card on the free table from
  /// somewhere else (`moveCard`, `moveGroup`'s primary, `stackCard`) --
  /// composes both the card-name-or-generic clause and the "from hand" /
  /// "from the zone's own name" origin clause.
  void _logPlayedToTable(String actingPlayerId, CardInstance oldCard, String instanceId) {
    final newCard = _findCard(instanceId);
    final name = _revealedCardName(oldCard, newCard);
    final cardText = name != null ? '"$name"' : 'a card';
    final origin = oldCard.zone == CardZone.hand
        ? 'hand'
        : 'the ${_zoneDefinition(oldCard.zoneId!).name}';
    _log(actingPlayerId, 'played $cardText to the table from $origin.');
  }

  void moveCard(String instanceId, double x, double y, {required String actingPlayerId}) {
    final oldCard = _findCard(instanceId);
    _state = _actions.moveCard(_state, instanceId: instanceId, x: x, y: y);
    if (oldCard != null && oldCard.zone != CardZone.table) {
      _logPlayedToTable(actingPlayerId, oldCard, instanceId);
    }
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
    double y, {
    required String actingPlayerId,
  }) {
    final oldPrimary = _findCard(primaryInstanceId);
    _state = _actions.moveGroup(
      _state,
      primaryInstanceId: primaryInstanceId,
      passengerRootInstanceIds: passengerRootInstanceIds,
      x: x,
      y: y,
    );
    if (oldPrimary != null && oldPrimary.zone != CardZone.table) {
      _logPlayedToTable(actingPlayerId, oldPrimary, primaryInstanceId);
    }
    notifyListeners();
  }

  void rotateStack(
    String rootInstanceId, {
    required bool clockwise,
    required String actingPlayerId,
  }) {
    _state = _actions.rotateStack(
      _state,
      rootInstanceId: rootInstanceId,
      clockwise: clockwise,
    );
    final card = _findCard(rootInstanceId);
    if (card != null) {
      final name = _isPubliclyVisible(card) ? _definitionsById[card.definitionId]?.cardTitle : null;
      _log(actingPlayerId, name != null ? 'rotated "$name".' : 'rotated a card.');
    }
    notifyListeners();
  }

  void bringToFront(String rootInstanceId) {
    _state = _actions.bringToFront(_state, rootInstanceId: rootInstanceId);
    notifyListeners();
  }

  /// Always names the real card, regardless of visibility -- a flip either
  /// reveals a card that was hidden or hides one that was just visible, so
  /// one of the two snapshots is always public anyway.
  void flipCard(String instanceId, {required String actingPlayerId}) {
    _state = _actions.flipCard(_state, instanceId: instanceId);
    final card = _findCard(instanceId);
    final direction = (card?.faceUp ?? false) ? 'face up' : 'face down';
    final name = card != null ? _definitionsById[card.definitionId]?.cardTitle : null;
    _log(actingPlayerId, name != null ? 'flipped "$name" $direction.' : 'flipped a card $direction.');
    notifyListeners();
  }

  /// Reassigns [instanceId]'s ownership to [newOwnerId] (null releases it
  /// back to unowned) -- see `TableActions.giveCard`.
  void giveCard(String instanceId, String? newOwnerId, {required String actingPlayerId}) {
    _state = _actions.giveCard(
      _state,
      instanceId: instanceId,
      newOwnerId: newOwnerId,
    );
    final card = _findCard(instanceId);
    final name = card != null && _isPubliclyVisible(card) ? _definitionsById[card.definitionId]?.cardTitle : null;
    final cardText = name != null ? '"$name"' : 'a card';
    _log(
      actingPlayerId,
      newOwnerId != null
          ? 'gave $cardText to ${_playerName(newOwnerId)}.'
          : 'released $cardText back to the table.',
    );
    notifyListeners();
  }

  void stackCard(String instanceId, String ontoInstanceId, {required String actingPlayerId}) {
    final oldCard = _findCard(instanceId);
    _state = _actions.stackCard(
      _state,
      instanceId: instanceId,
      ontoInstanceId: ontoInstanceId,
    );
    if (oldCard != null && oldCard.zone != CardZone.table) {
      _logPlayedToTable(actingPlayerId, oldCard, instanceId);
    }
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
    final actingPlayerId = ownerId ?? localPlayerId;
    final oldCard = _findCard(instanceId);
    _state = _actions.moveToHand(
      _state,
      instanceId: instanceId,
      ownerId: actingPlayerId,
    );
    final name = oldCard != null && _isPubliclyVisible(oldCard)
        ? _definitionsById[oldCard.definitionId]?.cardTitle
        : null;
    _log(
      actingPlayerId,
      name != null ? 'picked up "$name" into their hand.' : 'picked up a card into their hand.',
    );
    notifyListeners();
  }

  /// Draws the top [count] cards of the free-table pile rooted at
  /// [pileInstanceId] into [ownerId]'s hand, defaulting to this session's
  /// own local player -- the host overrides this to the requesting client's
  /// id when applying a networked draw request on their behalf. For a zone
  /// (draw deck, discard pile, etc.) see [drawFromZone] instead.
  void drawCard(String pileInstanceId, {String? ownerId, int count = 1}) {
    final actingPlayerId = ownerId ?? localPlayerId;
    _state = _actions.drawCard(
      _state,
      pileInstanceId: pileInstanceId,
      ownerId: actingPlayerId,
      count: count,
    );
    _log(actingPlayerId, count == 1 ? 'drew a card.' : 'drew $count cards.');
    notifyListeners();
  }

  void shufflePile(String pileRootInstanceId, {required String actingPlayerId}) {
    _state = _actions.shufflePile(
      _state,
      pileRootInstanceId: pileRootInstanceId,
    );
    _log(actingPlayerId, 'shuffled a pile of cards.');
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
    final actingPlayerId = toOwnerId ?? localPlayerId;
    final zoneName = _zoneDefinition(zoneId).name;
    _state = _actions.drawFromZone(
      _state,
      zoneId: zoneId,
      zoneOwnerId: zoneOwnerId,
      toOwnerId: actingPlayerId,
      count: count,
    );
    _log(
      actingPlayerId,
      count == 1 ? 'drew a card from the $zoneName.' : 'drew $count cards from the $zoneName.',
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
    required String actingPlayerId,
  }) {
    final zone = _zoneDefinition(zoneId);
    final oldCard = _findCard(instanceId);
    _state = _actions.returnToZone(
      _state,
      instanceId: instanceId,
      zoneId: zoneId,
      zoneOwnerId: zoneOwnerId,
      faceUp: zone.faceUp,
      toBottom: toBottom,
    );
    final newCard = _findCard(instanceId);
    final name = _revealedCardName(oldCard, newCard);
    final cardText = name != null ? '"$name"' : 'a card';
    _log(
      actingPlayerId,
      zone.isDiscardPile ? 'discarded $cardText.' : 'returned $cardText to the ${zone.name}.',
    );
    notifyListeners();
  }

  /// Shuffles the zone [zoneId] (owned by [zoneOwnerId], null for a shared
  /// zone) -- a no-op if that zone's own [ZoneDefinition.shuffleable] is
  /// false (e.g. a discard pile, whose order is a history rather than a
  /// randomized pool).
  void shuffleZone(String zoneId, {required String? zoneOwnerId, required String actingPlayerId}) {
    if (!_zoneDefinition(zoneId).shuffleable) return;
    final zoneName = _zoneDefinition(zoneId).name;
    _state = _actions.shuffleZone(
      _state,
      zoneId: zoneId,
      zoneOwnerId: zoneOwnerId,
    );
    _log(actingPlayerId, 'shuffled the $zoneName.');
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
    final actingPlayerId = searcherId ?? localPlayerId;
    final zoneName = _zoneDefinition(zoneId).name;
    _state = _actions.startSearch(
      _state,
      searcherId: actingPlayerId,
      targetType: SearchTargetType.zone,
      targetId: zoneId,
      targetOwnerId: zoneOwnerId,
    );
    _log(actingPlayerId, 'opened a search on the $zoneName.');
    notifyListeners();
  }

  /// Opens a Search window on the free-table pile rooted at
  /// [pileRootInstanceId], attributed to [searcherId] -- see
  /// [startSearchZone]'s doc for the defaulting convention.
  void startSearchPile(String pileRootInstanceId, {String? searcherId}) {
    final actingPlayerId = searcherId ?? localPlayerId;
    _state = _actions.startSearch(
      _state,
      searcherId: actingPlayerId,
      targetType: SearchTargetType.pile,
      targetId: pileRootInstanceId,
    );
    _log(actingPlayerId, 'opened a search on a pile of cards.');
    notifyListeners();
  }

  /// Closes [searcherId]'s Search window, defaulting to this session's own
  /// local player.
  void stopSearch({String? searcherId}) {
    final actingPlayerId = searcherId ?? localPlayerId;
    final hadSearch = _state.searches.any((s) => s.searcherId == actingPlayerId);
    _state = _actions.stopSearch(
      _state,
      searcherId: actingPlayerId,
    );
    if (hadSearch) _log(actingPlayerId, 'closed their search.');
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

  /// How long a drawn arrow stays on the table before removing itself --
  /// arrows have no manual dismiss (no right-click menu, no click-to-delete
  /// -- see `ArrowWidget`'s own doc), so this is the only way one ever goes
  /// away.
  static const Duration arrowLifetime = Duration(seconds: 5);

  /// This method (called from both `HostTableController.createArrow` for the
  /// host's own arrow and `HostGameEngine`'s `requestCreateArrow` handler for
  /// a client's) only ever runs on the host's own authoritative session --
  /// a client's `GameSession` never calls it directly (see
  /// `ClientTableController.createArrow`, which only sends a request and
  /// waits for the resulting `fullState`). So scheduling the expiry [Timer]
  /// here, rather than from the UI, naturally runs it exactly once per
  /// arrow, on the one session that can actually delete it -- every client
  /// (and the host's own table) just sees the widget disappear on the next
  /// `fullState` like any other host-driven change.
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
    Timer(arrowLifetime, () {
      if (_state.widgets.any((w) => w.instanceId == instanceId)) {
        deleteWidget(instanceId);
      }
    });
  }

  void moveWidget(String instanceId, double x, double y) {
    _state = _actions.moveWidget(_state, instanceId: instanceId, x: x, y: y);
    notifyListeners();
  }

  void setWidgetValue(String instanceId, int value, {required String actingPlayerId}) {
    final widget = _findWidget(instanceId);
    _state = _actions.setWidgetValue(
      _state,
      instanceId: instanceId,
      value: value,
    );
    if (widget != null && widget.kind == BoardWidgetKind.simpleCounter) {
      final clamped = value.clamp(boardWidgetCounterMin, boardWidgetCounterMax);
      final label = widget.zoneId != null ? _zoneDefinition(widget.zoneId!).name : 'a counter';
      _log(actingPlayerId, 'set $label to $clamped.');
    }
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
    double y, {
    required String actingPlayerId,
  }) {
    final widget = _findWidget(instanceId);
    final card = _findCard(cardId);
    _state = _actions.attachWidgetToCard(
      _state,
      instanceId: instanceId,
      cardId: cardId,
      x: x,
      y: y,
    );
    final kindLabel = switch (widget?.kind) {
      BoardWidgetKind.simpleCounter => 'a counter',
      BoardWidgetKind.token => 'a token',
      _ => 'a widget',
    };
    final name = card != null && _isPubliclyVisible(card) ? _definitionsById[card.definitionId]?.cardTitle : null;
    final cardText = name != null ? '"$name"' : 'a card';
    _log(actingPlayerId, 'attached $kindLabel to $cardText.');
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
    final updated = <PlayerInfo>[];
    for (final p in _state.players) {
      final nowConnected = p.role == PlayerRole.host || connectedNonHostIds.contains(p.id);
      if (nowConnected != p.connected) {
        _log(p.id, nowConnected ? 'connected.' : 'disconnected.');
      }
      updated.add(p.copyWith(connected: nowConnected));
    }
    _state = _state.copyWith(players: updated, revision: _state.revision + 1);
    notifyListeners();
  }
}
