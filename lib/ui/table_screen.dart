import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../game/game_session.dart';
import '../game/geometry_utils.dart';
import '../game/stack_utils.dart';
import '../game/table_controller.dart';
import '../models/card_definition.dart';
import '../models/card_instance.dart';
import '../models/game_definition.dart';
import '../models/zone_definition.dart';
import 'widgets/card_back_widget.dart';
import 'widgets/card_face_widget.dart';
import 'widgets/draggable_card.dart';
import 'widgets/hand_zone_widget.dart';
import 'widgets/opponent_hand_zone_widget.dart';
import 'widgets/opponent_zone_stack_widget.dart';
import 'widgets/pile_widget.dart';
import 'widgets/zone_stack_widget.dart';

const StackUtils _stackUtils = StackUtils();

/// Overlap radius (in logical pixels) within which dropping a card onto
/// another counts as stacking rather than a bare move.
const double _stackHitRadius = cardWidth * 0.6;

/// The main gameplay surface: a free-form table where cards can be dragged
/// anywhere, flipped, and stacked into piles, plus each player's hand and
/// [zones] (a draw deck, a discard pile, a shared deck, etc. -- see
/// `ZoneDefinition`). Every action goes through [controller] -- the host
/// applies it directly, a client sends it to the host and waits for the
/// next state broadcast.
///
/// [isMirrored] renders the shared table area's *positions* (not the hand/
/// zone rows, which always keep their own fixed top/bottom layout) as if
/// viewed from the opposite seat -- both axes flipped -- so a card dragged
/// near one player's own hand appears near the *other* player's, matching a
/// physical table where the two seats face each other. The host is always
/// the canonical/unmirrored seat; the client is always mirrored. Each
/// card's *rotation* is separate from this and is decided per-card in
/// [build] by who last held it (`CardInstance.ownerId`), not by seat -- so a
/// card always faces upright for whichever player played it, on both
/// screens.
///
/// Holding Space while hovering any card shows a full-size preview of
/// exactly what's currently visible for that card (its real face if
/// face-up, a back otherwise -- never an x-ray of hidden information),
/// positioned in the center of whichever half of the screen the cursor
/// *isn't* on so it's always fully visible and never covers the card being
/// inspected. Alt is reserved for movement modifiers instead: return a card
/// to the bottom of a deck/zone, drag a whole pile as a unit, or -- the one
/// case that isn't a drop onto a defined zone target -- stack a dropped card
/// onto another loose card/pile at all (see [_handleDragEnd]); without Alt,
/// dropping near another card just places it there instead of piling it.
class TableScreen extends StatefulWidget {
  const TableScreen({
    super.key,
    required this.definitionsById,
    required this.controller,
    required this.isMirrored,
    required this.zones,
    this.opponentCardBorderColor = defaultOpponentCardBorderColor,
    this.cardBackImagePath,
  });

  final Map<String, CardDefinition> definitionsById;
  final TableController controller;
  final bool isMirrored;

  /// This game's non-hand zones (see `ZoneDefinition`) -- owned ones render
  /// clustered next to each player's hand, shared ones render on the open
  /// table like any other pile.
  final List<ZoneDefinition> zones;

  /// `#RRGGBB` -- see `GameDefinition.opponentCardBorderColor`.
  final String opponentCardBorderColor;
  final String? cardBackImagePath;

  @override
  State<TableScreen> createState() => _TableScreenState();
}

/// A snapshot of a card discarded via D, flying (purely as a client-local
/// visual overlay -- see `_startDiscardFlight`) from where it sat on the
/// table to its owner's discard pile. `from`/`to` are in the inner table
/// `Stack`'s own local coordinate space (the same one `_toScreenPixel`
/// already produces), so the ghost can be positioned there directly.
class _FlyingDiscard {
  _FlyingDiscard({required this.instanceId, required this.from, required this.to, required this.faceUp, required this.definition});

  final String instanceId;
  final Offset from;
  final Offset to;
  final bool faceUp;
  final CardDefinition? definition;
}

class _TableScreenState extends State<TableScreen> with SingleTickerProviderStateMixin {
  final GlobalKey _tableKey = GlobalKey();
  final GlobalKey _handZoneKey = GlobalKey();

  /// One stable [GlobalKey] per *local* owned zone id, so a drop can be
  /// tested against that zone's real on-screen rect (see
  /// [_localZoneIdAt]) -- only the local player's own zones are ever a drop
  /// target this way, mirroring the old single `_deckZoneKey`.
  final Map<String, GlobalKey> _zoneKeys = {};

  GlobalKey _zoneKey(String zoneId) => _zoneKeys.putIfAbsent(zoneId, GlobalKey.new);

  /// One stable [GlobalKey] per hand card instance, so a drop can later
  /// query each card's real on-screen position (via [_computeHandDropIndex])
  /// to figure out which two cards it landed between -- reused across builds
  /// (keyed by instanceId, not list index) so Flutter doesn't lose a card
  /// widget's identity when the hand's order changes. Never pruned: stale
  /// entries for cards no longer in hand are harmless (a card game's hand
  /// size is small) and pruning risks dropping a key still in use mid-drag.
  final Map<String, GlobalKey> _handCardKeys = {};

  GlobalKey _handCardKey(String instanceId) => _handCardKeys.putIfAbsent(instanceId, GlobalKey.new);

  /// The table Stack's own measured size, refreshed every build via the
  /// LayoutBuilder in [build] -- needed to convert canonical [0,1] fractions
  /// to this screen's pixels *during* the same build that lays the Stack
  /// out, before `_tableBox` (which needs a completed layout) is available.
  Size _tableSize = Size.zero;

  /// Instance id of the card currently under the mouse, or null. Looked up
  /// fresh against the latest [TableState.cards] on every build (rather than
  /// caching the [CardInstance] itself) so the Space-preview never shows
  /// stale data if the hovered card changes underneath the cursor (e.g.
  /// flipped, or moved by the other player) without the mouse actually
  /// leaving it.
  String? _hoveredInstanceId;

  /// Latest raw mouse position (window-global coordinates), updated on every
  /// hover event without triggering a rebuild -- only read at the moment a
  /// rebuild already has to happen (hover target or Space state changing) to
  /// decide which half of the screen the preview belongs in.
  Offset _lastMousePos = Offset.zero;

  /// Whether Space is currently held -- unlike the modifier keys (Alt/Shift/
  /// Ctrl), `HardwareKeyboard` has no built-in convenience getter for a
  /// plain key like Space, so this is tracked explicitly in
  /// [_handleKeyEvent].
  bool _spacePressed = false;

  /// The card currently animating from the table into a discard pile, if
  /// any -- see [_startDiscardFlight]. Only one flight is tracked at a time;
  /// a second D press while one is still in progress simply replaces it.
  _FlyingDiscard? _flyingDiscard;

  /// Drives [_flyingDiscard]'s position -- short and sharp on purpose, so a
  /// discard reads as an obvious, immediate action rather than a slow drift.
  late final AnimationController _discardFlightController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) setState(() => _flyingDiscard = null);
    });

  RenderBox get _tableBox => _tableKey.currentContext!.findRenderObject() as RenderBox;

  Offset _globalToTableLocal(Offset global) => _tableBox.globalToLocal(global);

  Offset _toScreenPixel(double fx, double fy) {
    final (px, py) = canonicalToLocalPixel(
      fx: fx,
      fy: fy,
      tableWidth: _tableSize.width,
      tableHeight: _tableSize.height,
      isMirrored: widget.isMirrored,
    );
    return Offset(px, py);
  }

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    _discardFlightController.dispose();
    super.dispose();
  }

  bool _handleKeyEvent(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.space) {
      final pressed = event is! KeyUpEvent;
      if (pressed != _spacePressed) setState(() => _spacePressed = pressed);
      return false;
    }
    // KeyRepeatEvent (an OS repeat while held) is deliberately not handled
    // here -- only a fresh KeyDownEvent should rotate/discard, so holding Q/E
    // doesn't spam the action.
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.keyQ) {
        _rotateHovered(clockwise: false);
      } else if (event.logicalKey == LogicalKeyboardKey.keyE) {
        _rotateHovered(clockwise: true);
      } else if (event.logicalKey == LogicalKeyboardKey.keyD) {
        _discardHovered();
      }
    }
    return false;
  }

  /// The hovered card, if it exists, sits on the table, and belongs to the
  /// local player -- the shared precondition for both Q/E and D. Reads the
  /// session directly (outside `build()`, this is a raw keyboard callback,
  /// not part of the widget tree) rather than caching state, so it's never
  /// stale by even one action.
  CardInstance? _ownedHoveredTableCard() {
    final id = _hoveredInstanceId;
    if (id == null) return null;
    final session = context.read<GameSession>();
    for (final c in session.state.cards) {
      if (c.instanceId != id) continue;
      if (c.zone != CardZone.table || c.ownerId != session.localPlayerId) return null;
      return c;
    }
    return null;
  }

  void _rotateHovered({required bool clockwise}) {
    final card = _ownedHoveredTableCard();
    if (card == null) return;
    final state = context.read<GameSession>().state;
    final rootId = _stackUtils.rootIdOf(state.cards, card);
    widget.controller.rotateStack(rootId, clockwise: clockwise);
  }

  void _discardHovered() {
    final card = _ownedHoveredTableCard();
    if (card == null) return;
    final discardZoneId = _localDiscardZoneId;
    if (discardZoneId == null) return;
    _startDiscardFlight(card, discardZoneId);
    setState(() => _hoveredInstanceId = null);
  }

  /// `null` if [zones] defines no owned zone marked
  /// `ZoneDefinition.isDiscardPile` -- in which case D simply does nothing.
  String? get _localDiscardZoneId {
    for (final z in widget.zones) {
      if (!z.shared && z.isDiscardPile) return z.id;
    }
    return null;
  }

  /// Kicks off the purely decorative discard-flight ghost (see
  /// [_FlyingDiscard]) from [card]'s current table position to the local
  /// [discardZoneId] widget's on-screen rect, then fires the real
  /// `returnToZone` action in parallel -- by the time the short flight
  /// finishes, the real state has essentially always already caught up (see
  /// the class doc), so clearing the ghost reveals it seamlessly.
  void _startDiscardFlight(CardInstance card, String discardZoneId) {
    final zoneBox = _zoneKey(discardZoneId).currentContext?.findRenderObject() as RenderBox?;
    if (zoneBox == null) {
      widget.controller.returnToZone(card.instanceId, discardZoneId, toBottom: false);
      return;
    }
    final fromLocal = _toScreenPixel(card.x, card.y) - const Offset(cardWidth / 2, cardHeight / 2);
    final zoneGlobalCenter = zoneBox.localToGlobal(Offset.zero) + Offset(zoneBox.size.width / 2, zoneBox.size.height / 2);
    final toLocal = _tableBox.globalToLocal(zoneGlobalCenter) - const Offset(cardWidth / 2, cardHeight / 2);
    setState(() {
      _flyingDiscard = _FlyingDiscard(
        instanceId: card.instanceId,
        from: fromLocal,
        to: toLocal,
        faceUp: card.faceUp,
        definition: widget.definitionsById[card.definitionId],
      );
    });
    _discardFlightController.forward(from: 0);
    widget.controller.returnToZone(card.instanceId, discardZoneId, toBottom: false);
  }

  /// The flying ghost itself -- a static snapshot of the card's face/back as
  /// it looked the instant D was pressed, `IgnorePointer`-wrapped (purely
  /// decorative), lerping from/to with an eased curve.
  Widget _buildFlyingDiscard(_FlyingDiscard flight) {
    return AnimatedBuilder(
      animation: _discardFlightController,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_discardFlightController.value);
        final pos = Offset.lerp(flight.from, flight.to, t)!;
        return Positioned(
          left: pos.dx,
          top: pos.dy,
          child: IgnorePointer(
            child: flight.faceUp && flight.definition != null
                ? CardFaceWidget(definition: flight.definition!)
                : CardBackWidget(imagePath: widget.cardBackImagePath),
          ),
        );
      },
    );
  }

  void _setHoveredId(String? id) {
    if (_hoveredInstanceId != id) setState(() => _hoveredInstanceId = id);
  }

  /// True if [globalPoint] falls within the local player's own hand zone --
  /// used so a card dropped back onto that zone goes into the hand instead
  /// of onto the table (regardless of where it started the drag from).
  bool _isOverLocalHandZone(Offset globalPoint) {
    final box = _handZoneKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return false;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    return rect.contains(globalPoint);
  }

  /// The id of whichever local owned zone [globalPoint] falls within, if
  /// any -- used so a card dropped there returns to that zone instead of
  /// landing on the table.
  String? _localZoneIdAt(Offset globalPoint) {
    for (final entry in _zoneKeys.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(globalPoint)) return entry.key;
    }
    return null;
  }

  /// Figures out which position [globalPoint] falls at within [otherHandCards]
  /// (the local hand *excluding* the card being dropped, already in display
  /// order) -- the index of the first card whose real on-screen center sits
  /// to the right of the drop point, or the hand's length if it's past every
  /// card. That's directly usable as `reorderHand`'s targetIndex: dropping
  /// left of the first card's center returns 0 (front, shifting the whole
  /// hand right); between two cards returns the index of the one on the
  /// right (inserting before it); past the last card appends at the end.
  int _computeHandDropIndex(List<CardInstance> otherHandCards, Offset globalPoint) {
    for (var i = 0; i < otherHandCards.length; i++) {
      final box = _handCardKeys[otherHandCards[i].instanceId]?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null) continue;
      final centerX = (box.localToGlobal(Offset.zero) & box.size).center.dx;
      if (globalPoint.dx < centerX) return i;
    }
    return otherHandCards.length;
  }

  /// Finds the nearest other top-of-stack card within [_stackHitRadius] of
  /// [center], if any -- used to decide whether a drop should stack onto a
  /// free-table pile or return into a shared zone instead of just moving.
  CardInstance? _findStackTarget({
    required List<CardInstance> tableTops,
    required String excludingInstanceId,
    required Offset center,
  }) {
    CardInstance? best;
    double bestDist = double.infinity;
    for (final c in tableTops) {
      if (c.instanceId == excludingInstanceId) continue;
      // Candidates are stored as canonical fractions -- convert through the
      // same mirror-aware transform as rendering so distances are measured
      // in this screen's actual pixel space regardless of seat.
      final dist = (_toScreenPixel(c.x, c.y) - center).distance;
      if (dist < _stackHitRadius && dist < bestDist) {
        best = c;
        bestDist = dist;
      }
    }
    return best;
  }

  void _handleDragEnd(
    List<CardInstance> tableTops,
    String instanceId,
    Offset globalTopLeft,
    List<CardInstance> localHand,
  ) {
    final globalCenter = globalTopLeft + const Offset(cardWidth / 2, cardHeight / 2);
    if (_isOverLocalHandZone(globalCenter)) {
      final otherHandCards = localHand.where((c) => c.instanceId != instanceId).toList();
      if (otherHandCards.length != localHand.length) {
        // Already a hand card -- a genuine reorder, not an arrival from
        // elsewhere. Figure out which two (real, on-screen) cards it landed
        // between and slot it in there instead of just appending.
        final targetIndex = _computeHandDropIndex(otherHandCards, globalCenter);
        widget.controller.reorderHand(instanceId, targetIndex);
      } else {
        widget.controller.moveToHand(instanceId);
      }
      return;
    }
    final droppedZoneId = _localZoneIdAt(globalCenter);
    if (droppedZoneId != null) {
      widget.controller.returnToZone(instanceId, droppedZoneId, toBottom: HardwareKeyboard.instance.isAltPressed);
      return;
    }

    final local = _globalToTableLocal(globalTopLeft);
    final rawCenter = Offset(local.dx + cardWidth / 2, local.dy + cardHeight / 2);
    final target = _findStackTarget(tableTops: tableTops, excludingInstanceId: instanceId, center: rawCenter);
    final altHeld = HardwareKeyboard.instance.isAltPressed;
    // A shared zone is a defined drop target regardless of Alt (which only
    // picks top vs. bottom there); stacking onto a loose card/pile is an
    // incidental proximity match, so it additionally requires Alt -- without
    // it, a drop that merely lands near another card just moves there
    // instead of piling onto it.
    if (target != null && (target.zone == CardZone.zone || altHeld)) {
      if (target.zone == CardZone.zone) {
        // Dropped onto a shared zone pile on the free table -- return the
        // card to it instead of just stacking, exactly like dropping onto
        // one of the local player's own owned zones (top by default,
        // bottom if Alt is held). TableActions.returnToZone takes the
        // resulting ownerId from the zone itself (null here), not the
        // acting player, so it stays shared.
        widget.controller.returnToZone(instanceId, target.zoneId!, toBottom: altHeld);
      } else {
        widget.controller.stackCard(instanceId, target.instanceId);
      }
    } else {
      // Keep the whole card clear of both hand zones -- otherwise a drop
      // released over a hand zone band lands behind it, unselectable.
      final clampedY = clampCardCenterY(
        proposedCenterY: rawCenter.dy,
        tableHeight: _tableSize.height,
        cardHeight: cardHeight,
      );
      final (fx, fy) = localPixelToCanonical(
        pixelX: rawCenter.dx,
        pixelY: clampedY,
        tableWidth: _tableSize.width,
        tableHeight: _tableSize.height,
        isMirrored: widget.isMirrored,
      );
      widget.controller.moveCard(instanceId, fx, fy);
    }
  }

  /// Handles an Alt+drag release on an entire [PileWidget] (as opposed to a
  /// plain drag, which pulls just its top card out via [_handleDragEnd]) --
  /// dropped onto the local hand zone, every card in [pileCards] is dealt
  /// into the hand individually (so each gets its own left-to-right slot,
  /// same as any other arrival there); dropped anywhere else on the table,
  /// the whole pile is repositioned as a unit via [TableController.moveStack]
  /// rather than broken apart. Only ever wired up for genuine free-table
  /// piles (`stackParentId`-chained) -- a zone has no such chain to move as
  /// a unit, so this is never used for one.
  void _handlePileDragEnd(String rootId, List<CardInstance> pileCards, Offset globalTopLeft) {
    final globalCenter = globalTopLeft + const Offset(cardWidth / 2, cardHeight / 2);
    if (_isOverLocalHandZone(globalCenter)) {
      final ordered = pileCards.toList()..sort((a, b) => a.zIndex.compareTo(b.zIndex));
      for (final c in ordered) {
        widget.controller.moveToHand(c.instanceId);
      }
      return;
    }

    final local = _globalToTableLocal(globalTopLeft);
    final rawCenter = Offset(local.dx + cardWidth / 2, local.dy + cardHeight / 2);
    final clampedY = clampCardCenterY(
      proposedCenterY: rawCenter.dy,
      tableHeight: _tableSize.height,
      cardHeight: cardHeight,
    );
    final (fx, fy) = localPixelToCanonical(
      pixelX: rawCenter.dx,
      pixelY: clampedY,
      tableWidth: _tableSize.width,
      tableHeight: _tableSize.height,
      isMirrored: widget.isMirrored,
    );
    widget.controller.moveStack(rootId, fx, fy);
  }

  /// A large, always-upright rendering of exactly what [instance] currently
  /// shows (real face if face-up, a back otherwise) positioned in the center
  /// of whichever half of [screenSize] the cursor isn't in, clamped to stay
  /// fully on screen regardless of card image aspect ratio or window size.
  Widget _buildHoverPreview(CardInstance instance, CardDefinition? definition, Size screenSize) {
    // Only a table card's own orientation is honored here (matching
    // DraggableCard/PileWidget's applyOrientation) -- a hand/zone card is
    // never actually rendered rotated on screen, so its preview shouldn't be
    // either.
    final orientation =
        instance.zone == CardZone.table ? (definition?.orientation ?? CardOrientation.portrait) : CardOrientation.portrait;
    final rotated = orientation != CardOrientation.portrait;
    final boxWidth = rotated ? cardHeight : cardWidth;
    final boxHeight = rotated ? cardWidth : cardHeight;

    double previewHeight = screenSize.height * 0.7;
    double previewWidth = previewHeight * (boxWidth / boxHeight);
    final maxWidth = screenSize.width * 0.42;
    if (previewWidth > maxWidth) {
      previewWidth = maxWidth;
      previewHeight = previewWidth * (boxHeight / boxWidth);
    }

    final onLeftHalf = _lastMousePos.dx < screenSize.width / 2;
    final targetCenterX = onLeftHalf ? screenSize.width * 0.75 : screenSize.width * 0.25;
    final left = (targetCenterX - previewWidth / 2).clamp(0.0, screenSize.width - previewWidth);
    final top = (screenSize.height / 2 - previewHeight / 2).clamp(0.0, screenSize.height - previewHeight);

    final content = instance.faceUp && definition != null
        ? CardFaceWidget(definition: definition)
        : CardBackWidget(imagePath: widget.cardBackImagePath);

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: SizedBox(
          width: previewWidth,
          height: previewHeight,
          child: FittedBox(
            fit: BoxFit.contain,
            child: RotatedBox(
              quarterTurns: orientationQuarterTurns(orientation),
              child: SizedBox(width: cardWidth, height: cardHeight, child: content),
            ),
          ),
        ),
      ),
    );
  }

  /// The local player's own instance of an owned [zone], wrapped in the
  /// standard translucent box every zone gets, keyed for [_localZoneIdAt] so
  /// a drop can land here.
  Widget _buildLocalZoneWidget(ZoneDefinition zone, List<CardInstance> cards, List<CardInstance> tableTops, List<CardInstance> localHand) {
    final top = cards.isEmpty ? null : _stackUtils.topOf(cards);
    return ColoredBox(
      key: _zoneKey(zone.id),
      color: Colors.black.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: ZoneStackWidget(
          zoneName: zone.name,
          count: cards.length,
          topInstanceId: top?.instanceId,
          topFaceUp: top?.faceUp ?? false,
          topDefinition: top == null ? null : widget.definitionsById[top.definitionId],
          onDragEnd: top == null
              ? null
              : (offset) => _handleDragEnd(tableTops, top.instanceId, offset, localHand),
          onShuffle: cards.isEmpty || !zone.shuffleable ? null : () => widget.controller.shuffleZone(zone.id),
          cardBackImagePath: widget.cardBackImagePath,
        ),
      ),
    );
  }

  /// The opponent's instance of an owned [zone], read-only. [cards] is
  /// whatever this client's own filtered state carries for it -- real cards
  /// only for a `ZoneDefinition.visibleToAll` zone (see state_filter.dart),
  /// otherwise already-redacted stand-ins with no real face to show.
  Widget _buildOpponentZoneWidget(ZoneDefinition zone, List<CardInstance> cards) {
    final top = cards.isEmpty ? null : _stackUtils.topOf(cards);
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: OpponentZoneStackWidget(
          zoneName: zone.name,
          count: cards.length,
          topFaceUp: top?.faceUp ?? false,
          topDefinition: top == null ? null : widget.definitionsById[top.definitionId],
          cardBackImagePath: widget.cardBackImagePath,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B6E4F),
      body: SafeArea(
        child: Consumer<GameSession>(
          builder: (context, session, _) {
            final state = session.state;
            final ownedZones = widget.zones.where((z) => !z.shared).toList();
            final sharedZones = widget.zones.where((z) => z.shared).toList();

            // Sorted by zIndex -- the field `reorderHand` renumbers to
            // control left-to-right display/drop order, exactly like a
            // table pile's zIndex already controls its draw order.
            final localHand = state.cards
                .where((c) => c.zone == CardZone.hand && c.ownerId == session.localPlayerId)
                .toList()
              ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
            final opponentHandCount = state.cards
                .where((c) => c.zone == CardZone.hand && c.ownerId != session.localPlayerId)
                .length;

            final localZoneCardsById = {
              for (final z in ownedZones)
                z.id: state.cards
                    .where((c) => c.zone == CardZone.zone && c.zoneId == z.id && c.ownerId == session.localPlayerId)
                    .toList(),
            };
            final opponentZoneCardsById = {
              for (final z in ownedZones)
                z.id: state.cards
                    .where((c) =>
                        c.zone == CardZone.zone && c.zoneId == z.id && c.ownerId != null && c.ownerId != session.localPlayerId)
                    .toList(),
            };
            final sharedZoneCardsById = {
              for (final z in sharedZones)
                z.id: state.cards.where((c) => c.zone == CardZone.zone && c.zoneId == z.id).toList(),
            };

            // Free-table piles -- ad-hoc stacks built by dragging cards
            // together, unrelated to any zone (a pile is not a zone).
            final tableCardsOnly = state.cards.where((c) => c.zone == CardZone.table).toList();
            final pileGroups = _stackUtils.groupByStack(tableCardsOnly);
            // Sorted so a higher-zIndex pile/card (the one most recently
            // moved, flipped, rotated, or stacked -- see TableActions) is
            // built later in this Stack's children and therefore actually
            // paints on top of an overlapping lower one; Map iteration order
            // alone (the old behavior) had no relationship to zIndex at all.
            final sortedPileEntries = pileGroups.entries.toList()
              ..sort((a, b) => _stackUtils.topOf(a.value).zIndex.compareTo(_stackUtils.topOf(b.value).zIndex));

            final tableTops = <CardInstance>[
              for (final g in pileGroups.values) _stackUtils.topOf(g),
              for (final z in sharedZones)
                if (sharedZoneCardsById[z.id]!.isNotEmpty) _stackUtils.topOf(sharedZoneCardsById[z.id]!),
            ];

            CardInstance? hoveredInstance;
            if (_hoveredInstanceId != null) {
              for (final c in state.cards) {
                if (c.instanceId == _hoveredInstanceId) {
                  hoveredInstance = c;
                  break;
                }
              }
            }
            final hoveredDefinition = hoveredInstance == null ? null : widget.definitionsById[hoveredInstance.definitionId];
            final showPreview = hoveredInstance != null && _spacePressed;
            final opponentBorderColor = parseHexColor(widget.opponentCardBorderColor);

            return LayoutBuilder(
              builder: (context, outerConstraints) {
                final screenSize = outerConstraints.biggest;
                return MouseRegion(
                  onHover: (event) => _lastMousePos = event.position,
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: OpponentHandZoneWidget(
                                  count: opponentHandCount,
                                  cardBackImagePath: widget.cardBackImagePath,
                                ),
                              ),
                              for (final zone in ownedZones) _buildOpponentZoneWidget(zone, opponentZoneCardsById[zone.id]!),
                            ],
                          ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                _tableSize = constraints.biggest;
                                return Stack(
                                  key: _tableKey,
                                  clipBehavior: Clip.none,
                                  children: [
                                    for (final group in sortedPileEntries)
                                      Builder(builder: (context) {
                                        final cards = group.value;
                                        final top = _stackUtils.topOf(cards);
                                        final pos = _toScreenPixel(top.x, top.y);
                                        // A card faces whichever player last held it
                                        // (moveCard/stackCard never clear ownerId), not
                                        // whichever seat is viewing it -- so it stays
                                        // upright for its own player on both screens and
                                        // only appears rotated to the other player. A
                                        // never-held card (still in the shared pile) has
                                        // no owner and stays neutral/unrotated for
                                        // everyone. The same ownership check also decides
                                        // the opponent-card border and whether the local
                                        // player may interact with it at all.
                                        final ownedByOpponent = top.ownerId != null && top.ownerId != session.localPlayerId;
                                        if (cards.length > 1) {
                                          // PileWidget's own box is larger than a bare
                                          // card (room for its badge/shuffle button to
                                          // overflow) -- center on that actual size, or
                                          // the pile renders shifted off its true
                                          // canonical position (see pileWidgetExtra).
                                          return Positioned(
                                            left: pos.dx - (cardWidth + pileWidgetExtra) / 2,
                                            top: pos.dy - (cardHeight + pileWidgetExtra) / 2,
                                            child: PileWidget(
                                              count: cards.length,
                                              topInstanceId: top.instanceId,
                                              topFaceUp: top.faceUp,
                                              topDefinition: widget.definitionsById[top.definitionId],
                                              topRotationTurns: top.rotationTurns,
                                              onDraw: () => widget.controller.drawCard(group.key),
                                              onDragEnd: (offset) => HardwareKeyboard.instance.isAltPressed
                                                  ? _handlePileDragEnd(group.key, cards, offset)
                                                  : _handleDragEnd(tableTops, top.instanceId, offset, localHand),
                                              onShuffle: () => widget.controller.shufflePile(group.key),
                                              isMirrored: ownedByOpponent,
                                              interactable: !ownedByOpponent,
                                              applyOrientation: true,
                                              topBorderColor: ownedByOpponent ? opponentBorderColor : null,
                                              onHover: (hovering) => _setHoveredId(hovering ? top.instanceId : null),
                                              cardBackImagePath: widget.cardBackImagePath,
                                            ),
                                          );
                                        }
                                        if (_flyingDiscard?.instanceId == top.instanceId) {
                                          // Hidden for the duration of the discard flight
                                          // (see _startDiscardFlight) -- the ghost overlay
                                          // stands in for it, so it doesn't flicker back
                                          // into view if the real state update (host-
                                          // authoritative, network-round-tripped for a
                                          // client) takes longer than the short animation.
                                          return const SizedBox.shrink();
                                        }
                                        return Positioned(
                                          left: pos.dx - cardWidth / 2,
                                          top: pos.dy - cardHeight / 2,
                                          child: DraggableCard(
                                            instance: top,
                                            definition: widget.definitionsById[top.definitionId],
                                            isMirrored: ownedByOpponent,
                                            interactable: !ownedByOpponent,
                                            applyOrientation: true,
                                            opponentBorderColor: ownedByOpponent ? opponentBorderColor : null,
                                            onTapFlip: () => widget.controller.flipCard(top.instanceId),
                                            onDragEnd: (offset) => _handleDragEnd(tableTops, top.instanceId, offset, localHand),
                                            onHover: (hovering) => _setHoveredId(hovering ? top.instanceId : null),
                                            cardBackImagePath: widget.cardBackImagePath,
                                          ),
                                        );
                                      }),
                                    if (_flyingDiscard != null) _buildFlyingDiscard(_flyingDiscard!),
                                    for (final zone in sharedZones)
                                      if (sharedZoneCardsById[zone.id]!.isNotEmpty)
                                        Builder(builder: (context) {
                                          final cards = sharedZoneCardsById[zone.id]!;
                                          final top = _stackUtils.topOf(cards);
                                          final pos = _toScreenPixel(top.x, top.y);
                                          if (cards.length > 1) {
                                            return Positioned(
                                              left: pos.dx - (cardWidth + pileWidgetExtra) / 2,
                                              top: pos.dy - (cardHeight + pileWidgetExtra) / 2,
                                              child: Tooltip(
                                                message: zone.name,
                                                child: PileWidget(
                                                  count: cards.length,
                                                  topInstanceId: top.instanceId,
                                                  topFaceUp: top.faceUp,
                                                  topDefinition: widget.definitionsById[top.definitionId],
                                                  onDraw: () => widget.controller.drawFromZone(zone.id),
                                                  onDragEnd: (offset) =>
                                                      _handleDragEnd(tableTops, top.instanceId, offset, localHand),
                                                  onShuffle:
                                                      zone.shuffleable ? () => widget.controller.shuffleZone(zone.id) : null,
                                                  cardBackImagePath: widget.cardBackImagePath,
                                                ),
                                              ),
                                            );
                                          }
                                          return Positioned(
                                            left: pos.dx - cardWidth / 2,
                                            top: pos.dy - cardHeight / 2,
                                            child: Tooltip(
                                              message: zone.name,
                                              child: DraggableCard(
                                                instance: top,
                                                definition: widget.definitionsById[top.definitionId],
                                                onTapFlip: () => widget.controller.flipCard(top.instanceId),
                                                onDragEnd: (offset) =>
                                                    _handleDragEnd(tableTops, top.instanceId, offset, localHand),
                                                onHover: (hovering) => _setHoveredId(hovering ? top.instanceId : null),
                                                cardBackImagePath: widget.cardBackImagePath,
                                              ),
                                            ),
                                          );
                                        }),
                                  ],
                                );
                              },
                            ),
                          ),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Expanded(
                                child: HandZoneWidget(
                                  key: _handZoneKey,
                                  cards: localHand,
                                  definitionsById: widget.definitionsById,
                                  onTapFlip: (id) => widget.controller.flipCard(id),
                                  onDragEnd: (id, offset) => _handleDragEnd(tableTops, id, offset, localHand),
                                  onHoverCard: _setHoveredId,
                                  cardBackImagePath: widget.cardBackImagePath,
                                  cardKeyFor: _handCardKey,
                                ),
                              ),
                              for (final zone in ownedZones)
                                _buildLocalZoneWidget(zone, localZoneCardsById[zone.id]!, tableTops, localHand),
                            ],
                          ),
                        ],
                      ),
                      if (showPreview) _buildHoverPreview(hoveredInstance!, hoveredDefinition, screenSize),
                    ],
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
