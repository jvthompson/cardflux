import '../models/card_instance.dart';
import '../models/player.dart';
import '../models/table_state.dart';

/// Result of [matchPlayersByName]: every saved player this session's current
/// roster could unambiguously identify by name, plus the leftovers on each
/// side still needing a human to resolve (via a seat-match confirmation
/// screen) before a load can proceed.
class PlayerMatchResult {
  const PlayerMatchResult({
    required this.matchedSavedIdToCurrentId,
    required this.unmatchedSavedPlayers,
    required this.unmatchedCurrentPlayers,
  });

  /// Saved [PlayerInfo.id] -> current [PlayerInfo.id], one entry per
  /// unambiguous name match.
  final Map<String, String> matchedSavedIdToCurrentId;

  /// Saved players (in their original saved order) with no unambiguous
  /// current-side match -- either their name doesn't appear in
  /// [currentPlayers] at all, or it's ambiguous (the same name appears more
  /// than once on either side).
  final List<PlayerInfo> unmatchedSavedPlayers;

  /// Current players not claimed by an unmatched auto-match -- the pool a
  /// seat-match screen should offer for each of [unmatchedSavedPlayers].
  final List<PlayerInfo> unmatchedCurrentPlayers;
}

/// Matches each of [savedPlayers] to one of [currentPlayers] by exact,
/// case-sensitive name -- a saved player only auto-matches when its name is
/// unique within *both* lists (a duplicate name on either side is left for
/// manual resolution rather than guessed at). Callers combine
/// [PlayerMatchResult.matchedSavedIdToCurrentId] with a human-confirmed
/// mapping for [PlayerMatchResult.unmatchedSavedPlayers] to build the total
/// id map [buildLoadedTableState] needs.
PlayerMatchResult matchPlayersByName({
  required List<PlayerInfo> savedPlayers,
  required List<PlayerInfo> currentPlayers,
}) {
  final savedByName = <String, List<PlayerInfo>>{};
  for (final p in savedPlayers) {
    savedByName.putIfAbsent(p.name, () => []).add(p);
  }
  final currentByName = <String, List<PlayerInfo>>{};
  for (final p in currentPlayers) {
    currentByName.putIfAbsent(p.name, () => []).add(p);
  }

  final matched = <String, String>{};
  final claimedCurrentIds = <String>{};
  for (final saved in savedPlayers) {
    final savedGroup = savedByName[saved.name]!;
    final currentGroup = currentByName[saved.name];
    if (savedGroup.length == 1 && currentGroup != null && currentGroup.length == 1) {
      matched[saved.id] = currentGroup.single.id;
      claimedCurrentIds.add(currentGroup.single.id);
    }
  }

  return PlayerMatchResult(
    matchedSavedIdToCurrentId: matched,
    unmatchedSavedPlayers: [for (final p in savedPlayers) if (!matched.containsKey(p.id)) p],
    unmatchedCurrentPlayers: [for (final p in currentPlayers) if (!claimedCurrentIds.contains(p.id)) p],
  );
}

/// [buildLoadedTableState]'s return value: the rebuilt state, plus how many
/// saved cards had to be dropped because their [CardInstance.definitionId]
/// no longer exists in the game being loaded into (edited since the save) --
/// callers should confirm with the user before committing to a load that
/// drops anything.
class LoadedTableStateResult {
  const LoadedTableStateResult({required this.state, required this.droppedCardCount});

  final TableState state;
  final int droppedCardCount;
}

/// Rebuilds [saved] into a fresh, loadable [TableState] for the current
/// session: [saved.players] is walked in its own (saved) order and each seat
/// is filled with the real current [PlayerInfo] `savedIdToCurrentId` says
/// fills it -- so a returning player lands back in their original seat/table
/// position regardless of this session's own join order, which is exactly
/// why table position must be restored from the save rather than kept as
/// today's roster order. Every `ownerId`/`creatorId` reference in
/// [saved.cards]/[saved.widgets] is rewritten through the same map (falling
/// back to unowned if a referenced saved id is somehow missing from the map,
/// rather than throwing -- defensive, shouldn't happen given a total map).
/// A card whose [CardInstance.definitionId] isn't in [validDefinitionIds] is
/// dropped (see [LoadedTableStateResult.droppedCardCount]); any surviving
/// card's `stackParentId`, or any widget's `attachedCardId`, that pointed at
/// a dropped card is cleared rather than left dangling. [TableState.searches]
/// is always empty; `revision`/`gameId` pass through unchanged.
LoadedTableStateResult buildLoadedTableState({
  required TableState saved,
  required List<PlayerInfo> currentPlayers,
  required Map<String, String> savedIdToCurrentId,
  required Set<String> validDefinitionIds,
}) {
  final currentById = {for (final p in currentPlayers) p.id: p};
  final players = <PlayerInfo>[];
  for (final savedPlayer in saved.players) {
    final currentId = savedIdToCurrentId[savedPlayer.id];
    final current = currentId == null ? null : currentById[currentId];
    if (current != null) players.add(current);
  }

  String? remapOwner(String? savedOwnerId) {
    if (savedOwnerId == null) return null;
    return savedIdToCurrentId[savedOwnerId];
  }

  final keptCards = <CardInstance>[];
  var droppedCardCount = 0;
  for (final card in saved.cards) {
    if (!validDefinitionIds.contains(card.definitionId)) {
      droppedCardCount++;
      continue;
    }
    keptCards.add(card.copyWith(ownerId: remapOwner(card.ownerId)));
  }
  final keptCardIds = {for (final c in keptCards) c.instanceId};
  final cards = [
    for (final c in keptCards)
      if (c.stackParentId != null && !keptCardIds.contains(c.stackParentId)) c.copyWith(stackParentId: null) else c,
  ];

  final widgets = [
    for (final w in saved.widgets)
      w.copyWith(
        ownerId: remapOwner(w.ownerId),
        creatorId: remapOwner(w.creatorId),
        attachedCardId: w.attachedCardId != null && !keptCardIds.contains(w.attachedCardId) ? null : w.attachedCardId,
      ),
  ];

  return LoadedTableStateResult(
    state: TableState(
      gameId: saved.gameId,
      players: players,
      cards: cards,
      revision: saved.revision,
      widgets: widgets,
    ),
    droppedCardCount: droppedCardCount,
  );
}
