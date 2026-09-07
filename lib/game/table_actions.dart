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
