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

  /// Moves a card to a free table position, detaching it from any stack.
  TableState moveCard(TableState state, {required String instanceId, required double x, required double y}) {
    final nextZ = _nextZIndex(state);
    final cards = state.cards.map((c) {
      if (c.instanceId != instanceId) return c;
      return c.copyWith(x: x, y: y, zone: CardZone.table, stackParentId: null, zIndex: nextZ);
    }).toList();
    return state.copyWith(cards: cards, revision: state.revision + 1);
  }

  /// Repositions every card in the stack rooted at [rootInstanceId] to
  /// [x]/[y] as a unit -- unlike [moveCard], nothing is detached: zone,
  /// stackParentId, and zIndex ordering all stay exactly as they were, only
  /// the shared position changes. Used to drag an entire pile around
  /// (Alt+drag on a [PileWidget]) rather than pulling just its top card out.
  TableState moveStack(TableState state, {required String rootInstanceId, required double x, required double y}) {
    final stackIds = _stacks.stackOf(state.cards, rootInstanceId).map((c) => c.instanceId).toSet();
    if (stackIds.isEmpty) return state;
    final cards = state.cards.map((c) {
      if (!stackIds.contains(c.instanceId)) return c;
      return c.copyWith(x: x, y: y);
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
      return c.copyWith(zone: CardZone.hand, ownerId: ownerId, faceUp: true, stackParentId: null, zIndex: nextZ);
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

  /// Toggles a card's face-up/down state in place.
  TableState flipCard(TableState state, {required String instanceId}) {
    final cards = state.cards.map((c) {
      if (c.instanceId != instanceId) return c;
      return c.copyWith(faceUp: !c.faceUp);
    }).toList();
    return state.copyWith(cards: cards, revision: state.revision + 1);
  }

  /// Stacks [instanceId] on top of [ontoInstanceId], snapping its position
  /// and zone to match, and placing it above every existing card in the
  /// stack.
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
        zIndex: nextZ,
      );
    }).toList();
    return state.copyWith(cards: cards, revision: state.revision + 1);
  }

  /// Moves the topmost card of the stack rooted at [pileInstanceId] into
  /// [ownerId]'s hand, face-up, detached from the pile.
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
        zIndex: nextZ,
      );
    }).toList();
    return state.copyWith(cards: cards, revision: state.revision + 1);
  }

  /// Returns [instanceId] to the deck rooted at [deckRootInstanceId] --
  /// face-down, detached from wherever it was (hand, table, another stack).
  /// [deckRootInstanceId] is null for a currently-empty deck, in which case
  /// [instanceId] becomes its new root, owned by [ownerId] (e.g. the local
  /// player claiming their own emptied-out personal deck) and keeps its own
  /// current `x`/`y` (nothing to snap to yet).
  ///
  /// A deck that already has a root keeps that root's own existing ownerId
  /// (null for a shared/unowned deck, like a fixed-deck game's table pile or
  /// Practice Mode's original pile; a specific player for a personal deck) --
  /// [ownerId] is ignored in that case, so returning a card to *any* deck
  /// (yours or a shared one) always lands it back with the deck's own
  /// identity rather than the acting player's. The returned card also snaps
  /// to the root's `x`/`y` (mirroring [stackCard]), not wherever it happened
  /// to be dragged from -- a free-table deck (unlike a personal deck's own
  /// fixed-position zone widget) renders at its topmost card's canonical
  /// position, so without this a return-to-top would visibly relocate the
  /// whole pile to the returned card's old spot.
  ///
  /// New cards always attach directly to the root (a flat star, same shape
  /// [GameSession.dealPlayerDecks]/[GameSession.dealFixedDecks] already
  /// deal) rather than chaining onto whatever the current top/bottom happens
  /// to be -- simpler, and equivalent for [StackUtils.stackOf]/
  /// [StackUtils.rootIdOf] purposes. By default the card becomes the new top
  /// (drawn next, via the global max-zIndex convention every other "put on
  /// top" action already uses); [toBottom] instead gives it a zIndex below
  /// every other card currently in the deck, so it's drawn last (the root
  /// itself is still always drawn truly last, per [drawCard]'s own anchor
  /// rule).
  TableState returnToDeck(
    TableState state, {
    required String instanceId,
    required String? deckRootInstanceId,
    required String ownerId,
    bool toBottom = false,
  }) {
    if (instanceId == deckRootInstanceId) return state;
    final stack = deckRootInstanceId == null ? const <CardInstance>[] : _stacks.stackOf(state.cards, deckRootInstanceId);
    final newZ = toBottom && stack.isNotEmpty
        ? stack.map((c) => c.zIndex).reduce((a, b) => a < b ? a : b) - 1
        : _nextZIndex(state);
    final root = deckRootInstanceId == null ? null : _findById(state, deckRootInstanceId);
    final resolvedOwnerId = deckRootInstanceId == null ? ownerId : root?.ownerId;

    final cards = state.cards.map((c) {
      if (c.instanceId != instanceId) return c;
      return c.copyWith(
        x: root?.x ?? c.x,
        y: root?.y ?? c.y,
        zone: CardZone.drawPile,
        ownerId: resolvedOwnerId,
        faceUp: false,
        stackParentId: deckRootInstanceId,
        zIndex: newZ,
      );
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
