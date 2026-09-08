import 'dart:math';

import '../models/card_instance.dart';
import '../models/table_state.dart';
import 'stack_utils.dart';

/// Pure, network-free transformations of a [TableState]. Used directly by
/// the local sandbox (M2) and, once networking is wired in (M4), by
/// HostGameEngine to apply validated client requests. No rules are enforced
/// here — these functions only maintain structural consistency of the table.
class TableActions {
  const TableActions();

  static const StackUtils _stacks = StackUtils();

  int _nextZIndex(TableState state) {
    if (state.cards.isEmpty) return 0;
    return state.cards.map((c) => c.zIndex).reduce((a, b) => a > b ? a : b) + 1;
  }

  CardInstance? _findById(TableState state, String id) {
    for (final c in state.cards) {
      if (c.instanceId == id) return c;
    }
    return null;
  }

  /// Moves a card to a free table position, detaching it from any stack or
  /// zone (clearing [CardInstance.zoneId] -- leaving it stale would make the
  /// card linger in its old zone's grouping even though [CardZone.table]
  /// says it's no longer there).
  TableState moveCard(TableState state, {required String instanceId, required double x, required double y}) {
    final nextZ = _nextZIndex(state);
    final cards = state.cards.map((c) {
      if (c.instanceId != instanceId) return c;
      return c.copyWith(x: x, y: y, zone: CardZone.table, stackParentId: null, zoneId: null, zIndex: nextZ);
    }).toList();
    return state.copyWith(cards: cards, revision: state.revision + 1);
  }

  /// Repositions every card in the stack rooted at [rootInstanceId] to
  /// [x]/[y] as a unit -- unlike [moveCard], nothing is detached: zone,
  /// stackParentId, and each member's zIndex *relative to the rest of the
  /// stack* stay exactly as they were, only the shared position changes.
  /// Used to drag an entire pile around (Alt+drag on a [PileWidget]) rather
  /// than pulling just its top card out.
  ///
  /// The stack's current top card (per [StackUtils.topOf]) additionally gets
  /// bumped to the table's new running-max zIndex -- since cross-pile
  /// render order is driven by each pile's top card, this brings the whole
  /// pile to the front of every other free-table pile/card without
  /// disturbing the internal draw order this stack's own members keep among
  /// themselves.
  TableState moveStack(TableState state, {required String rootInstanceId, required double x, required double y}) {
    final stack = _stacks.stackOf(state.cards, rootInstanceId);
    if (stack.isEmpty) return state;
    final stackIds = stack.map((c) => c.instanceId).toSet();
    final currentTopId = _stacks.topOf(stack).instanceId;
    final nextZ = _nextZIndex(state);
    final cards = state.cards.map((c) {
      if (!stackIds.contains(c.instanceId)) return c;
      final zIndex = c.instanceId == currentTopId ? nextZ : c.zIndex;
      return c.copyWith(x: x, y: y, zIndex: zIndex);
    }).toList();
    return state.copyWith(cards: cards, revision: state.revision + 1);
  }

  /// Rotates every card in the stack rooted at [rootInstanceId] by one
  /// quarter-turn in the same direction -- a lone table card is already "a
  /// stack of one" under [StackUtils.stackOf], so this handles both a single
  /// card and a whole pile with the same call. Only `CardZone.table` cards
  /// are affected (defensive -- nothing outside `TableScreen`'s own
  /// table-only Q/E handling should ever reach this with anything else).
  ///
  /// Also bumps the stack's current top card to the table's new
  /// running-max zIndex -- see [moveStack]'s doc for why this is enough to
  /// bring the whole pile to the front without touching every member's
  /// zIndex.
  TableState rotateStack(TableState state, {required String rootInstanceId, required bool clockwise}) {
    final stack = _stacks.stackOf(state.cards, rootInstanceId);
    if (stack.isEmpty) return state;
    final stackIds = stack.map((c) => c.instanceId).toSet();
    final currentTopId = _stacks.topOf(stack).instanceId;
    final nextZ = _nextZIndex(state);
    final delta = clockwise ? 1 : -1;
    final cards = state.cards.map((c) {
      if (!stackIds.contains(c.instanceId) || c.zone != CardZone.table) return c;
      final zIndex = c.instanceId == currentTopId ? nextZ : c.zIndex;
      return c.copyWith(rotationTurns: ((c.rotationTurns + delta) % 4 + 4) % 4, zIndex: zIndex);
    }).toList();
    return state.copyWith(cards: cards, revision: state.revision + 1);
  }

  /// Moves an arbitrary table card directly into [ownerId]'s hand, face-up,
  /// detached from any stack -- used when a card is dropped onto the
  /// player's own hand zone rather than a table position. Unlike [drawCard],
  /// [instanceId] is the card itself, not a pile to resolve a top card from.
  TableState moveToHand(TableState state, {required String instanceId, required String ownerId}) {
    final nextZ = _nextZIndex(state);
    final cards = state.cards.map((c) {
      if (c.instanceId != instanceId) return c;
      return c.copyWith(
        zone: CardZone.hand,
        ownerId: ownerId,
        faceUp: true,
        stackParentId: null,
        zoneId: null,
        rotationTurns: 0,
        zIndex: nextZ,
      );
    }).toList();
    return state.copyWith(cards: cards, revision: state.revision + 1);
  }

  /// Reorders [instanceId] within [ownerId]'s hand to sit at [targetIndex]
  /// (0-based, in the hand's left-to-right display order -- itself the
  /// ascending-zIndex order of that player's hand cards). Renumbers every
  /// card currently in that hand to consecutive zIndex values reflecting the
  /// new order; no other card is touched. A no-op if [instanceId] isn't
  /// currently a hand card owned by [ownerId]. [targetIndex] is clamped to
  /// the hand's bounds (dropping past the last card just appends it there).
  TableState reorderHand(
    TableState state, {
    required String instanceId,
    required String ownerId,
    required int targetIndex,
  }) {
    final hand = state.cards.where((c) => c.zone == CardZone.hand && c.ownerId == ownerId).toList()
      ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
    final currentIndex = hand.indexWhere((c) => c.instanceId == instanceId);
    if (currentIndex == -1) return state;

    final moved = hand.removeAt(currentIndex);
    hand.insert(targetIndex.clamp(0, hand.length), moved);

    final baseZ = _nextZIndex(state);
    final newZByInstanceId = <String, int>{for (var i = 0; i < hand.length; i++) hand[i].instanceId: baseZ + i};
    final cards = state.cards.map((c) {
      final newZ = newZByInstanceId[c.instanceId];
      if (newZ == null) return c;
      return c.copyWith(zIndex: newZ);
    }).toList();
    return state.copyWith(cards: cards, revision: state.revision + 1);
  }

  /// Toggles a card's face-up/down state in place, and brings it to the
  /// front (see [moveStack]'s doc for why a top-card zIndex bump is enough
  /// to bring its whole pile forward).
  TableState flipCard(TableState state, {required String instanceId}) {
    final nextZ = _nextZIndex(state);
    final cards = state.cards.map((c) {
      if (c.instanceId != instanceId) return c;
      return c.copyWith(faceUp: !c.faceUp, zIndex: nextZ);
    }).toList();
    return state.copyWith(cards: cards, revision: state.revision + 1);
  }

  /// Stacks [instanceId] on top of [ontoInstanceId], snapping its position
  /// and zone to match, and placing it above every existing card in the
  /// stack. Only ever called with a free-table pile as the target (see
  /// table_screen.dart -- a zone target goes through [TableActions] via
  /// `returnToZone` instead), so [zoneId] is always cleared: any zone
  /// membership the dragged card had is left behind, not carried over.
  TableState stackCard(TableState state, {required String instanceId, required String ontoInstanceId}) {
    if (instanceId == ontoInstanceId) return state;
    final target = _findById(state, ontoInstanceId);
    if (target == null) return state;

    final nextZ = _nextZIndex(state);
    final cards = state.cards.map((c) {
      if (c.instanceId != instanceId) return c;
      return c.copyWith(
        x: target.x,
        y: target.y,
        zone: target.zone,
        stackParentId: ontoInstanceId,
        zoneId: null,
        zIndex: nextZ,
      );
    }).toList();
    return state.copyWith(cards: cards, revision: state.revision + 1);
  }

  /// Moves [primaryInstanceId] to `x`/`y` exactly like [moveCard] (fully
  /// detaching it from any stack/zone), and translates every stack rooted at
  /// [passengerRootInstanceIds] by the same delta the primary moved by --
  /// preserving each passenger's position *relative to the primary* and its
  /// own internal structure (a passenger that's itself a multi-card official
  /// pile moves as a whole, unchanged internally). Used for dragging a loose
  /// table card together with whatever other cards are visually overlapping
  /// and stacked above it -- unlike [moveStack], passengers are NOT snapped
  /// to one shared position, since they may only be loosely overlapping, not
  /// a collapsed pile.
  ///
  /// Only the primary and each passenger stack's own current top (per
  /// [StackUtils.topOf]) get a fresh, ascending zIndex (in
  /// [passengerRootInstanceIds] order) -- same minimal-touch approach
  /// [moveStack] uses -- so the whole group renders above every other table
  /// pile while preserving both the group's own front-to-back order and each
  /// passenger pile's internal order.
  TableState moveGroup(
    TableState state, {
    required String primaryInstanceId,
    required List<String> passengerRootInstanceIds,
    required double x,
    required double y,
  }) {
    final primary = _findById(state, primaryInstanceId);
    if (primary == null) return state;
    final dx = x - primary.x;
    final dy = y - primary.y;
    var nextZ = _nextZIndex(state);
    final primaryNewZ = nextZ++;
    final passengerTopNewZ = <String, int>{};
    final passengerIds = <String>{};
    for (final rootId in passengerRootInstanceIds) {
      final stack = _stacks.stackOf(state.cards, rootId);
      if (stack.isEmpty) continue;
      passengerIds.addAll(stack.map((c) => c.instanceId));
      passengerTopNewZ[_stacks.topOf(stack).instanceId] = nextZ++;
    }
    final cards = state.cards.map((c) {
      if (c.instanceId == primaryInstanceId) {
        return c.copyWith(x: x, y: y, zone: CardZone.table, stackParentId: null, zoneId: null, zIndex: primaryNewZ);
      }
      if (passengerIds.contains(c.instanceId)) {
        final bumped = passengerTopNewZ[c.instanceId];
        return c.copyWith(x: c.x + dx, y: c.y + dy, zIndex: bumped ?? c.zIndex);
      }
      return c;
    }).toList();
    return state.copyWith(cards: cards, revision: state.revision + 1);
  }

  /// Moves the topmost card of the free-table pile rooted at [pileInstanceId]
  /// into [ownerId]'s hand, face-up, detached from the pile. For a zone
  /// (draw deck, discard pile, etc.), see [drawFromZone] instead.
  ///
  /// [pileInstanceId] is the stack's root/anchor card — every other card in
  /// the pile identifies the pile via a stackParentId chain leading back to
  /// it. That anchor is only ever drawn once it's the last card left in the
  /// pile, so the pile's identity survives every draw before it.
  TableState drawCard(TableState state, {required String pileInstanceId, required String ownerId}) {
    final stack = _stacks.stackOf(state.cards, pileInstanceId);
    if (stack.isEmpty) return state;
    final candidates = stack.length > 1
        ? stack.where((c) => c.instanceId != pileInstanceId).toList()
        : stack;
    final top = _stacks.topOf(candidates);

    final nextZ = _nextZIndex(state);
    final cards = state.cards.map((c) {
      if (c.instanceId != top.instanceId) return c;
      return c.copyWith(
        zone: CardZone.hand,
        ownerId: ownerId,
        faceUp: true,
        stackParentId: null,
        rotationTurns: 0,
        zIndex: nextZ,
      );
    }).toList();
    return state.copyWith(cards: cards, revision: state.revision + 1);
  }

  /// Every card currently in the zone [zoneId] owned by [zoneOwnerId] (null
  /// for a shared zone) -- a static lookup by identity, not a
  /// `stackParentId`-chain walk, since a zone (unlike a free-table pile)
  /// doesn't need a stable "root card" to exist: it's found by `zone`/
  /// `zoneId`/`ownerId` alone, even when empty.
  List<CardInstance> _zoneCards(TableState state, {required String zoneId, required String? zoneOwnerId}) {
    return state.cards
        .where((c) => c.zone == CardZone.zone && c.zoneId == zoneId && c.ownerId == zoneOwnerId)
        .toList();
  }

  /// Moves the topmost card of the zone [zoneId] (owned by [zoneOwnerId],
  /// null for a shared zone) into [toOwnerId]'s hand, face-up. A no-op if
  /// the zone is currently empty.
  TableState drawFromZone(
    TableState state, {
    required String zoneId,
    required String? zoneOwnerId,
    required String toOwnerId,
  }) {
    final zoneCards = _zoneCards(state, zoneId: zoneId, zoneOwnerId: zoneOwnerId);
    if (zoneCards.isEmpty) return state;
    final top = _stacks.topOf(zoneCards);

    final nextZ = _nextZIndex(state);
    final cards = state.cards.map((c) {
      if (c.instanceId != top.instanceId) return c;
      return c.copyWith(
        zone: CardZone.hand,
        ownerId: toOwnerId,
        faceUp: true,
        zoneId: null,
        rotationTurns: 0,
        zIndex: nextZ,
      );
    }).toList();
    return state.copyWith(cards: cards, revision: state.revision + 1);
  }

  /// Returns [instanceId] to the zone [zoneId] (owned by [zoneOwnerId], null
  /// for a shared zone) -- detached from wherever it was (hand, table,
  /// another zone), landing with the zone's own ownership ([zoneOwnerId])
  /// rather than whichever player happened to drop it there, and showing
  /// its face according to [faceUp] (a zone's own `ZoneDefinition.faceUp` --
  /// false for a face-down deck, true for a discard pile-style zone meant to
  /// stay visible). Snaps to the `x`/`y` any other card already in that zone
  /// shares (an owned zone ignores this -- it always renders at a fixed
  /// screen position, never canonical coordinates -- but a shared zone
  /// renders on the open table at its topmost card's position, so without
  /// this a return-to-top would visibly relocate the whole pile to the
  /// returned card's old spot, same reasoning the old personal-deck
  /// return-to-top fix needed). By default the card becomes the new top
  /// (drawn next); [toBottom] instead gives it a zIndex below every other
  /// card in the zone, so it's drawn last.
  TableState returnToZone(
    TableState state, {
    required String instanceId,
    required String zoneId,
    required String? zoneOwnerId,
    required bool faceUp,
    bool toBottom = false,
  }) {
    final zoneCards = _zoneCards(state, zoneId: zoneId, zoneOwnerId: zoneOwnerId);
    if (zoneCards.any((c) => c.instanceId == instanceId)) return state;
    final newZ = toBottom && zoneCards.isNotEmpty
        ? zoneCards.map((c) => c.zIndex).reduce((a, b) => a < b ? a : b) - 1
        : _nextZIndex(state);
    final anchor = zoneCards.isEmpty ? null : zoneCards.first;

    final cards = state.cards.map((c) {
      if (c.instanceId != instanceId) return c;
      return c.copyWith(
        x: anchor?.x ?? c.x,
        y: anchor?.y ?? c.y,
        zone: CardZone.zone,
        zoneId: zoneId,
        ownerId: zoneOwnerId,
        faceUp: faceUp,
        stackParentId: null,
        rotationTurns: 0,
        zIndex: newZ,
      );
    }).toList();
    return state.copyWith(cards: cards, revision: state.revision + 1);
  }

  /// Randomizes the stacking order (zIndex) of every card in the zone
  /// [zoneId] (owned by [zoneOwnerId], null for a shared zone), and flips
  /// them all face-down.
  TableState shuffleZone(TableState state, {required String zoneId, required String? zoneOwnerId, int? seed}) {
    final zoneCards = _zoneCards(state, zoneId: zoneId, zoneOwnerId: zoneOwnerId);
    if (zoneCards.length < 2) return state;

    final ids = zoneCards.map((c) => c.instanceId).toList()..shuffle(seed != null ? Random(seed) : null);
    final baseZ = _nextZIndex(state);
    final newZByInstanceId = <String, int>{for (var i = 0; i < ids.length; i++) ids[i]: baseZ + i};

    final cards = state.cards.map((c) {
      final newZ = newZByInstanceId[c.instanceId];
      if (newZ == null) return c;
      return c.copyWith(zIndex: newZ, faceUp: false);
    }).toList();
    return state.copyWith(cards: cards, revision: state.revision + 1);
  }

  /// Randomizes the stacking order (zIndex) of every card in the stack
  /// rooted at [pileRootInstanceId], and flips them all face-down.
  TableState shufflePile(TableState state, {required String pileRootInstanceId, int? seed}) {
    final stack = _stacks.stackOf(state.cards, pileRootInstanceId);
    if (stack.length < 2) return state;

    final ids = stack.map((c) => c.instanceId).toList()..shuffle(seed != null ? Random(seed) : null);
    final baseZ = _nextZIndex(state);
    final newZByInstanceId = <String, int>{for (var i = 0; i < ids.length; i++) ids[i]: baseZ + i};

    final cards = state.cards.map((c) {
      final newZ = newZByInstanceId[c.instanceId];
      if (newZ == null) return c;
      return c.copyWith(zIndex: newZ, faceUp: false);
    }).toList();
    return state.copyWith(cards: cards, revision: state.revision + 1);
  }
}
