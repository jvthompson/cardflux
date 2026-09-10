import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../game/game_session.dart';
import '../game/geometry_utils.dart';
import '../game/stack_utils.dart';
import '../game/table_controller.dart';
import '../models/board_widget_instance.dart';
import '../models/card_definition.dart';
import '../models/card_instance.dart';
import '../models/game_definition.dart';
import '../models/zone_definition.dart';
import 'widgets/arrow_widget.dart';
import 'widgets/card_back_widget.dart';
import 'widgets/card_face_widget.dart';
import 'widgets/counter_widget.dart';
import 'widgets/draggable_card.dart';
import 'widgets/hand_zone_widget.dart';
import 'widgets/opponent_hand_zone_widget.dart';
import 'widgets/opponent_zone_stack_widget.dart';
import 'widgets/pile_widget.dart';
import 'widgets/token_widget.dart';
import 'widgets/zone_stack_widget.dart';

const StackUtils _stackUtils = StackUtils();

/// Mints ids for widgets created interactively (see [_TableScreenState._showBoardContextMenu])
/// -- unlike a card, which only ever gets an id at deal time in `GameSession`,
/// a widget's id has to be picked by whichever side (host or client) is
/// creating it, before any round trip, so its own creator has a stable id to
/// reference immediately.
const Uuid _uuid = Uuid();

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
  _FlyingDiscard({
    required this.instanceId,
    required this.from,
    required this.to,
    required this.faceUp,
    required this.definition,
  });

  final String instanceId;
  final Offset from;
  final Offset to;
  final bool faceUp;
  final CardDefinition? definition;
}

class _TableScreenState extends State<TableScreen>
    with TickerProviderStateMixin {
  final GlobalKey _tableKey = GlobalKey();
  final GlobalKey _handZoneKey = GlobalKey();

  /// One stable [GlobalKey] per *local* owned zone id, so a drop can be
  /// tested against that zone's real on-screen rect (see
  /// [_localZoneIdAt]) -- only the local player's own zones are ever a drop
  /// target this way, mirroring the old single `_deckZoneKey`.
  final Map<String, GlobalKey> _zoneKeys = {};

  GlobalKey _zoneKey(String zoneId) =>
      _zoneKeys.putIfAbsent(zoneId, GlobalKey.new);

  /// One stable [GlobalKey] per hand card instance, so a drop can later
  /// query each card's real on-screen position (via [_computeHandDropIndex])
  /// to figure out which two cards it landed between -- reused across builds
  /// (keyed by instanceId, not list index) so Flutter doesn't lose a card
  /// widget's identity when the hand's order changes. Never pruned: stale
  /// entries for cards no longer in hand are harmless (a card game's hand
  /// size is small) and pruning risks dropping a key still in use mid-drag.
  final Map<String, GlobalKey> _handCardKeys = {};

  GlobalKey _handCardKey(String instanceId) =>
      _handCardKeys.putIfAbsent(instanceId, GlobalKey.new);

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

  /// Whether TAB is currently held -- while true, every card/pile/counter/
  /// token drag (and incidentally tap-to-flip/tap-to-draw) is suppressed
  /// table-wide (see the `interactable: !_tabPressed` call sites in
  /// [build]), so a left-click-drag anywhere on the table draws an arrow
  /// instead of moving whatever's underneath the cursor. Same simple-boolean
  /// pattern as [_spacePressed].
  bool _tabPressed = false;

  /// The arrow drag currently in progress, if any -- both points in the
  /// table Stack's own local coordinate space (same convention as
  /// `_toScreenPixel`/`_globalToTableLocal`), updated live by `onPanUpdate`
  /// and consumed by `onPanEnd` (via [_commitArrowDrag]) to commit a real
  /// networked arrow. Purely local UI state, mirroring [_flyingDiscard]/
  /// [_hoveredInstanceId] -- never touches `TableState`/the network until
  /// commit.
  ///
  /// A [ValueNotifier], not a plain field driven by `setState`, on purpose:
  /// `onPanUpdate` fires on every pointer-move event during the drag, and
  /// this `State`'s `build()` constructs the entire table (every card, pile,
  /// zone, and widget) -- calling `setState` that often was rebuilding the
  /// whole multi-thousand-line tree per pixel of mouse movement, causing
  /// severe jank (dropped/incomplete frames visible as the table briefly
  /// going blank) and letting the final `onPanEnd` race ahead of a
  /// still-queued `onPanUpdate`, which is what produced an inaccurate
  /// endpoint. Only the small `ValueListenableBuilder` around the live
  /// preview (see [build]) listens to this, so a pointer move now only
  /// rebuilds that one tiny widget -- exactly how `Draggable`'s own built-in
  /// feedback (used by every card/pile drag already) avoids the same
  /// problem, via its own lightweight overlay mechanism instead of the
  /// ancestor `State`.
  final ValueNotifier<({Offset start, Offset current})?> _arrowDrag =
      ValueNotifier(null);

  /// The card currently animating from the table into a discard pile, if
  /// any -- see [_startDiscardFlight]. Only one flight is tracked at a time;
  /// a second D press while one is still in progress simply replaces it.
  _FlyingDiscard? _flyingDiscard;

  /// Drives [_flyingDiscard]'s position -- short and sharp on purpose, so a
  /// discard reads as an obvious, immediate action rather than a slow drift.
  late final AnimationController _discardFlightController =
      AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 220),
      )..addStatusListener((status) {
        if (status == AnimationStatus.completed && mounted)
          setState(() => _flyingDiscard = null);
      });

  /// The instance id of whichever free-table card is actually being dragged,
  /// while a pickup group (see [_pickupGroup]) larger than one is in
  /// progress -- null the rest of the time, including for an ordinary
  /// single-card drag (which needs none of this; `Draggable`'s own
  /// `childWhenDragging` already handles that case).
  String? _activeDragPrimaryId;

  /// Every card id in the pickup group currently being dragged (including
  /// the primary), while such a drag is in progress -- used to ghost each
  /// passenger in place, matching how the primary already dims itself via
  /// `childWhenDragging`. Null the rest of the time.
  Set<String>? _activeDragGroupIds;

  /// How far this player's own camera has panned the table view, in local
  /// pixels -- purely client-side (never read by `TableController` or
  /// `GameSession`), so each side of a host/client game can look at a
  /// different part of the shared table independently. Applied as a single
  /// `Transform.translate` around the pannable Stack in [build] -- see its
  /// doc comment there for why that means every existing hit-test/render
  /// call site needs no offset math of its own.
  Offset _cameraOffset = Offset.zero;

  /// Which of the WASD movement keys are currently held down -- unlike
  /// Q/E/D/Space, camera movement is continuous while held, not a one-shot
  /// trigger, so this (rather than a single boolean) drives [_cameraTicker]
  /// every frame for as long as any of them remain pressed.
  final Set<LogicalKeyboardKey> _pressedMovementKeys = {};

  /// Timestamp of the previous [_onCameraTick] call, to compute per-frame
  /// delta time -- null when the ticker isn't currently running (i.e.
  /// [_pressedMovementKeys] is empty), so the first tick after a key is
  /// pressed doesn't apply a huge delta measured from whenever the ticker
  /// last stopped.
  Duration? _lastCameraTick;

  static const double _cameraPanSpeed = 600; // logical pixels/second

  late final Ticker _cameraTicker = createTicker(_onCameraTick);

  void _onCameraTick(Duration elapsed) {
    final lastTick = _lastCameraTick;
    _lastCameraTick = elapsed;
    if (lastTick == null) return; // first frame after starting -- no delta yet
    final dt =
        (elapsed - lastTick).inMicroseconds / Duration.microsecondsPerSecond;
    var dx = 0.0, dy = 0.0;
    if (_pressedMovementKeys.contains(LogicalKeyboardKey.keyA)) dx -= 1;
    if (_pressedMovementKeys.contains(LogicalKeyboardKey.keyD)) dx += 1;
    if (_pressedMovementKeys.contains(LogicalKeyboardKey.keyW)) dy -= 1;
    if (_pressedMovementKeys.contains(LogicalKeyboardKey.keyS)) dy += 1;
    if (dx == 0 && dy == 0) return;
    final maxX = _maxPanX;
    final maxY = _maxPanY;
    setState(() {
      _cameraOffset = Offset(
        (_cameraOffset.dx + dx * _cameraPanSpeed * dt).clamp(-maxX, maxX),
        (_cameraOffset.dy + dy * _cameraPanSpeed * dt).clamp(-maxY, maxY),
      );
    });
  }

  /// How far the camera may pan on each axis, so the local player can reach
  /// every part of the fixed-size world (including the
  /// [tablePanMarginFraction] margin beyond its own edges) with the
  /// *current* viewport size -- unlike a fixed fraction of the world alone,
  /// this shrinks toward zero once the viewport is already as big as (or
  /// bigger than) the margin-inclusive world, since nothing would be left
  /// to pan to see. Recomputed from [_tableSize] every time it's needed --
  /// not cached -- so a window resize is reflected immediately, including
  /// pulling an already-panned camera back in if the new viewport makes the
  /// old offset invalid (see [_clampedCameraOffset]).
  double get _maxPanX => math.max(
    0,
    (kWorldSize.width * (1 + 2 * tablePanMarginFraction) - _tableSize.width) /
        2,
  );
  double get _maxPanY => math.max(
    0,
    (kWorldSize.height * (1 + 2 * tablePanMarginFraction) - _tableSize.height) /
        2,
  );

  /// [_cameraOffset] re-clamped against the *current* viewport size, so a
  /// window resize that shrinks the allowed pan range (e.g. maximizing a
  /// window that was previously panned to its old, smaller-viewport limit)
  /// never leaves rendering/hit-testing using an out-of-range offset --
  /// every read of the camera offset for rendering or hit-testing goes
  /// through this, not the raw field.
  Offset get _clampedCameraOffset => Offset(
    _cameraOffset.dx.clamp(-_maxPanX, _maxPanX),
    _cameraOffset.dy.clamp(-_maxPanY, _maxPanY),
  );

  void _setMovementKeyPressed(LogicalKeyboardKey key, bool pressed) {
    final wasEmpty = _pressedMovementKeys.isEmpty;
    if (pressed) {
      _pressedMovementKeys.add(key);
    } else {
      _pressedMovementKeys.remove(key);
    }
    if (wasEmpty && _pressedMovementKeys.isNotEmpty) {
      _lastCameraTick = null;
      _cameraTicker.start();
    } else if (!wasEmpty && _pressedMovementKeys.isEmpty) {
      _cameraTicker.stop();
    }
  }

  RenderBox get _tableBox =>
      _tableKey.currentContext!.findRenderObject() as RenderBox;

  /// The camera pan (WASD, see [_cameraOffset]) is applied directly here and
  /// in [_toScreenPixel] as plain arithmetic, rather than via an ancestor
  /// `Transform` widget wrapping the pannable Stack. Two earlier attempts
  /// used a `Transform.translate` (optionally with a `SizedBox` enlarging
  /// the Stack itself so panned-in margin content stayed hit-testable): both
  /// caused card interaction to only work within a fixed, pan-independent
  /// top-left region of the screen, matching what a subtly wrong manual
  /// Transform-hit-test inversion would produce -- and prior to that, the
  /// simple `Transform` alone reproduced the exact "content outside the
  /// default viewport paints but is never clickable" bug (`Clip.none` only
  /// ever affects painting, never hit-testing, which Flutter gates on a
  /// render object's own reported size first regardless). Baking the offset
  /// into these two functions directly sidesteps that whole class of
  /// Transform/RenderStack hit-test interaction entirely: every card's
  /// `Positioned` box is given its *true, current on-screen* position, so
  /// `RenderStack`'s own `_size.contains()` gate (still sized to just
  /// `_tableSize`, the default viewport, completely unchanged) always agrees
  /// with reality -- anything actually visible on screen is, by
  /// construction, within that size; anything panned out of view isn't, and
  /// correctly can't be interacted with until panned back into view.
  ///
  /// `_cameraOffset` and every canonical<->pixel conversion below operate in
  /// `kWorldSize`'s fixed, real pixels -- rendered 1:1, **never scaled**,
  /// so two players with different window sizes see the identical table at
  /// the identical physical scale (cards close together on one screen are
  /// never spread apart, or overlapping, on another's). [_worldOffset]
  /// (pure centering, no scale factor) is the only place `_tableSize`
  /// enters this math, positioning the fixed-size world within whatever
  /// viewport the local player happens to have.
  Offset get _worldOffset =>
      worldCenteringOffset(world: kWorldSize, viewport: _tableSize);

  Offset _globalToTableLocal(Offset global) =>
      _tableBox.globalToLocal(global) - _worldOffset - _clampedCameraOffset;

  Offset _toScreenPixel(double fx, double fy) =>
      _toWorldPixel(fx, fy) + _worldOffset + _clampedCameraOffset;

  /// Canonical fraction -> world-pixel, in the same "canonical 0 = pixel 0"
  /// convention [_globalToTableLocal] returns -- i.e. [_toScreenPixel]
  /// without the centering/camera offset added for actually painting it on
  /// screen. [_findStackTarget] needs this, not [_toScreenPixel]: comparing
  /// its candidates' *screen* positions against a `center` that came from
  /// [_globalToTableLocal] (world-pixel space) silently canceled out back
  /// when the world and viewport were the same size (offset was always
  /// zero), but produced a many-hundred-pixel mismatch once the world
  /// became genuinely bigger than the viewport -- every candidate looked
  /// impossibly far away, so a token/card drop could never find a stack to
  /// attach/join, even landing squarely on top of one.
  Offset _toWorldPixel(double fx, double fy) {
    final (px, py) = canonicalToLocalPixel(
      fx: fx,
      fy: fy,
      tableWidth: kWorldSize.width,
      tableHeight: kWorldSize.height,
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
    _cameraTicker.dispose();
    _arrowDrag.dispose();
    super.dispose();
  }

  static final _movementKeys = {
    LogicalKeyboardKey.keyW,
    LogicalKeyboardKey.keyA,
    LogicalKeyboardKey.keyS,
    LogicalKeyboardKey.keyD,
  };

  bool _handleKeyEvent(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.space) {
      final pressed = event is! KeyUpEvent;
      if (pressed != _spacePressed) setState(() => _spacePressed = pressed);
      return false;
    }
    if (_movementKeys.contains(event.logicalKey) && event is! KeyRepeatEvent) {
      _setMovementKeyPressed(event.logicalKey, event is! KeyUpEvent);
      return false;
    }
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      final pressed = event is! KeyUpEvent;
      if (pressed != _tabPressed) {
        if (!pressed) {
          // Releasing TAB mid-drag (e.g. Alt-tabbing away) abandons the
          // preview rather than committing a partial arrow. Not part of the
          // setState below -- ValueNotifier assignment never needs one.
          _arrowDrag.value = null;
        }
        setState(() => _tabPressed = pressed);
      }
      return false;
    }
    // KeyRepeatEvent (an OS repeat while held) is deliberately not handled
    // here -- only a fresh KeyDownEvent should rotate/discard/reset-camera,
    // so holding Q/E doesn't spam the action.
    if (event is KeyDownEvent) {
      if (event.logicalKey == LogicalKeyboardKey.keyQ) {
        _rotateHovered(clockwise: false);
      } else if (event.logicalKey == LogicalKeyboardKey.keyE) {
        _rotateHovered(clockwise: true);
      } else if (event.logicalKey == LogicalKeyboardKey.backspace) {
        _discardHovered();
      } else if (event.logicalKey == LogicalKeyboardKey.keyF) {
        _flipHovered();
      } else if (event.logicalKey == LogicalKeyboardKey.home) {
        setState(() => _cameraOffset = Offset.zero);
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
      if (c.zone != CardZone.table || c.ownerId != session.localPlayerId)
        return null;
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

  bool _isSharedZone(String zoneId) =>
      widget.zones.any((z) => z.id == zoneId && z.shared);

  /// The hovered card, if flipping it is currently allowed -- matches
  /// exactly what used to be reachable by clicking a card before flipping
  /// moved to hover+F: a free-table card, a hand card, or a shared zone's
  /// top card, and never one owned by the other player. An owned zone's own
  /// card (e.g. your draw deck) stays unreachable here, same as it was
  /// never clickable-to-flip before -- only its drag-to-move/drag-to-hand
  /// affordance exists for those.
  CardInstance? _hoveredFlippableCard() {
    final id = _hoveredInstanceId;
    if (id == null) return null;
    final session = context.read<GameSession>();
    for (final c in session.state.cards) {
      if (c.instanceId != id) continue;
      if (c.ownerId != null && c.ownerId != session.localPlayerId) return null;
      switch (c.zone) {
        case CardZone.table:
        case CardZone.hand:
          return c;
        case CardZone.zone:
          return _isSharedZone(c.zoneId!) ? c : null;
      }
    }
    return null;
  }

  void _flipHovered() {
    final card = _hoveredFlippableCard();
    if (card == null) return;
    widget.controller.flipCard(card.instanceId);
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

  /// Commits the in-progress TAB-drag preview (see [_arrowDrag]) as a real
  /// networked arrow, then clears the local preview state. A no-op (just
  /// clears state) if the two points are (near-)identical -- a plain
  /// click-without-drag while TAB is held shouldn't create a zero-length
  /// arrow.
  void _commitArrowDrag() {
    final drag = _arrowDrag.value;
    _arrowDrag.value = null;
    if (drag == null) return;
    final (start, end) = (drag.start, drag.current);
    if ((end - start).distance < 4) return;
    final (fx, fy) = localPixelToCanonical(
      pixelX: start.dx,
      pixelY: start.dy,
      tableWidth: kWorldSize.width,
      tableHeight: kWorldSize.height,
      isMirrored: widget.isMirrored,
    );
    final (fx2, fy2) = localPixelToCanonical(
      pixelX: end.dx,
      pixelY: end.dy,
      tableWidth: kWorldSize.width,
      tableHeight: kWorldSize.height,
      isMirrored: widget.isMirrored,
    );
    widget.controller.createArrow(_uuid.v4(), fx, fy, fx2, fy2);
  }

  /// Kicks off the purely decorative discard-flight ghost (see
  /// [_FlyingDiscard]) from [card]'s current table position to the local
  /// [discardZoneId] widget's on-screen rect, then fires the real
  /// `returnToZone` action in parallel -- by the time the short flight
  /// finishes, the real state has essentially always already caught up (see
  /// the class doc), so clearing the ghost reveals it seamlessly.
  void _startDiscardFlight(CardInstance card, String discardZoneId) {
    final zoneBox =
        _zoneKey(discardZoneId).currentContext?.findRenderObject()
            as RenderBox?;
    if (zoneBox == null) {
      widget.controller.returnToZone(
        card.instanceId,
        discardZoneId,
        toBottom: false,
      );
      return;
    }
    final fromLocal =
        _toScreenPixel(card.x, card.y) -
        const Offset(cardWidth / 2, cardHeight / 2);
    final zoneGlobalCenter =
        zoneBox.localToGlobal(Offset.zero) +
        Offset(zoneBox.size.width / 2, zoneBox.size.height / 2);
    final toLocal =
        _tableBox.globalToLocal(zoneGlobalCenter) -
        const Offset(cardWidth / 2, cardHeight / 2);
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
    widget.controller.returnToZone(
      card.instanceId,
      discardZoneId,
      toBottom: false,
    );
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

  /// Records [group] (see [_pickupGroup]) as the active drag, so its
  /// passengers can be ghosted in place -- a no-op (no ghosting) for a
  /// lone-card group, which needs nothing beyond `Draggable`'s own
  /// automatic dimming of the card actually being dragged.
  void _startGroupDrag(List<CardInstance> group) {
    if (group.length <= 1) return;
    setState(() {
      _activeDragPrimaryId = group.first.instanceId;
      _activeDragGroupIds = {for (final c in group) c.instanceId};
    });
  }

  void _endGroupDrag() {
    if (_activeDragGroupIds == null) return;
    setState(() {
      _activeDragPrimaryId = null;
      _activeDragGroupIds = null;
    });
  }

  /// A static (non-animated -- built once when the drag starts) snapshot of
  /// exactly what's currently visible for [c] (its real face if face-up, a
  /// back otherwise -- same privacy rule as everywhere else), with no
  /// rotation applied -- a deliberate simplification for this decorative
  /// drag feedback, matching [_buildFlyingDiscard]'s own.
  Widget _ghostFace(CardInstance c) {
    final definition = widget.definitionsById[c.definitionId];
    return IgnorePointer(
      child: c.faceUp && definition != null
          ? CardFaceWidget(definition: definition)
          : CardBackWidget(imagePath: widget.cardBackImagePath),
    );
  }

  /// Same idea as [_ghostFace], for a board widget riding along attached to
  /// a card that's part of the group being dragged (see
  /// [_buildGroupFeedback]) -- a static, non-interactive snapshot. Arrows
  /// are never attached to a card (see `BoardWidgetInstance.attachedCardId`'s
  /// doc comment), so that arm is unreachable in practice; it exists only to
  /// satisfy exhaustiveness.
  Widget _ghostWidgetFace(BoardWidgetInstance w) {
    return IgnorePointer(
      child: switch (w.kind) {
        BoardWidgetKind.simpleCounter => CounterWidget(
          instance: w,
          onDragEnd: (_) {},
          onSecondaryTapUp: (_) {},
          interactable: false,
        ),
        BoardWidgetKind.token => TokenWidget(
          instance: w,
          onDragEnd: (_) {},
          onSecondaryTapUp: (_) {},
          interactable: false,
        ),
        BoardWidgetKind.arrow => const SizedBox.shrink(),
      },
    );
  }

  /// [w]'s own footprint, matching the size lookup in the main widget render
  /// loop -- needed so [_buildGroupFeedback] can convert its center position
  /// into the correct top-left within that box, since a board widget's size
  /// generally differs from a card's.
  (double, double) _widgetSize(BoardWidgetKind kind) => switch (kind) {
    BoardWidgetKind.simpleCounter => (counterWidgetWidth, counterWidgetHeight),
    BoardWidgetKind.token => (tokenWidgetSize, tokenWidgetSize),
    BoardWidgetKind.arrow => (0.0, 0.0),
  };

  /// Drag feedback for a pickup group larger than one card: every member
  /// rendered at its position relative to [primary] (the card actually being
  /// dragged), so the whole group appears to follow the cursor together,
  /// preserving the same visual offsets they have on the table. The primary
  /// itself is positioned at local (0,0) sized exactly `cardWidth` x
  /// `cardHeight` -- matching the default single-card feedback's own box --
  /// so `Draggable`'s default anchor strategy (which measures the drag's
  /// start offset against the plain card widget, not this composite one)
  /// still keeps the exact grabbed point under the cursor.
  Widget _buildGroupFeedback(List<CardInstance> group, CardInstance primary) {
    final primaryPos = _toScreenPixel(primary.x, primary.y);
    final groupIds = {for (final c in group) c.instanceId};
    final attachedWidgets = context.read<GameSession>().state.widgets.where(
      (w) => groupIds.contains(w.attachedCardId),
    );
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: cardWidth,
        height: cardHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            for (final c in group)
              Positioned(
                left: _toScreenPixel(c.x, c.y).dx - primaryPos.dx,
                top: _toScreenPixel(c.x, c.y).dy - primaryPos.dy,
                child: _ghostFace(c),
              ),
            // Any board widget (e.g. a Token) riding along attached to a
            // group member -- see BoardWidgetInstance.attachedCardId --
            // follows the same relative-offset math as the cards above,
            // adjusted for its own footprint since a widget's size generally
            // isn't cardWidth x cardHeight (see _widgetSize).
            for (final w in attachedWidgets)
              Builder(
                builder: (context) {
                  final (widgetWidth, widgetHeight) = _widgetSize(w.kind);
                  final pos = _toScreenPixel(w.x, w.y);
                  return Positioned(
                    left:
                        pos.dx - primaryPos.dx + (cardWidth - widgetWidth) / 2,
                    top:
                        pos.dy -
                        primaryPos.dy +
                        (cardHeight - widgetHeight) / 2,
                    child: _ghostWidgetFace(w),
                  );
                },
              ),
          ],
        ),
      ),
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
  int _computeHandDropIndex(
    List<CardInstance> otherHandCards,
    Offset globalPoint,
  ) {
    for (var i = 0; i < otherHandCards.length; i++) {
      final box =
          _handCardKeys[otherHandCards[i].instanceId]?.currentContext
                  ?.findRenderObject()
              as RenderBox?;
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
      // same mirror-aware transform [center] itself came from (world-pixel,
      // via _globalToTableLocal -- NOT _toScreenPixel's on-screen space; see
      // _toWorldPixel's doc comment for why mixing the two silently broke
      // once the world stopped being the same size as the viewport).
      final dist = (_toWorldPixel(c.x, c.y) - center).distance;
      if (dist < _stackHitRadius && dist < bestDist) {
        best = c;
        bestDist = dist;
      }
    }
    return best;
  }

  /// Every card in [candidates] overlapping [dragged]'s on-screen rect with a
  /// strictly higher zIndex, transitively -- i.e. everything currently
  /// resting on top of [dragged] as you'd pick it up off the table.
  /// [dragged] itself is always included, first. [candidates] is expected to
  /// already exclude shared-zone piles and any card owned by the other
  /// player (see [pickupCandidates] at the call site) -- this method doesn't
  /// re-check either.
  List<CardInstance> _pickupGroup(
    List<CardInstance> candidates,
    CardInstance dragged,
  ) {
    final posById = {
      for (final c in candidates) c.instanceId: _toScreenPixel(c.x, c.y),
    };
    bool overlaps(CardInstance a, CardInstance b) {
      final pa = posById[a.instanceId]!;
      final pb = posById[b.instanceId]!;
      return (pa.dx - pb.dx).abs() < cardWidth &&
          (pa.dy - pb.dy).abs() < cardHeight;
    }

    final result = [dragged];
    final visited = {dragged.instanceId};
    final frontier = [dragged];
    while (frontier.isNotEmpty) {
      final current = frontier.removeLast();
      for (final other in candidates) {
        if (visited.contains(other.instanceId)) continue;
        if (other.zIndex > current.zIndex && overlaps(current, other)) {
          visited.add(other.instanceId);
          result.add(other);
          frontier.add(other);
        }
      }
    }
    return result;
  }

  void _handleDragEnd(
    List<CardInstance> tableTops,
    List<CardInstance> pickupCandidates,
    String instanceId,
    Offset globalTopLeft,
    List<CardInstance> localHand,
  ) {
    CardInstance? dragged;
    for (final c in pickupCandidates) {
      if (c.instanceId == instanceId) {
        dragged = c;
        break;
      }
    }
    if (dragged != null) {
      final group = _pickupGroup(pickupCandidates, dragged);
      if (group.length > 1) {
        // Picking up more than one card is always a plain positional move of
        // the whole group -- the hand/zone/stack special-case targets below
        // only apply to a lone card with nothing above it.
        final local = _globalToTableLocal(globalTopLeft);
        final rawCenter = Offset(
          local.dx + cardWidth / 2,
          local.dy + cardHeight / 2,
        );
        final clampedY = clampCardCenterY(
          proposedCenterY: rawCenter.dy,
          tableHeight: kWorldSize.height,
          cardHeight: cardHeight,
        );
        final (fx, fy) = localPixelToCanonical(
          pixelX: rawCenter.dx,
          pixelY: clampedY,
          tableWidth: kWorldSize.width,
          tableHeight: kWorldSize.height,
          isMirrored: widget.isMirrored,
        );
        final allCards = context.read<GameSession>().state.cards;
        final passengerRootIds = [
          for (final c in group)
            if (c.instanceId != instanceId) _stackUtils.rootIdOf(allCards, c),
        ];
        widget.controller.moveGroup(instanceId, passengerRootIds, fx, fy);
        return;
      }
    }

    final globalCenter =
        globalTopLeft + const Offset(cardWidth / 2, cardHeight / 2);
    if (_isOverLocalHandZone(globalCenter)) {
      final otherHandCards = localHand
          .where((c) => c.instanceId != instanceId)
          .toList();
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
      widget.controller.returnToZone(
        instanceId,
        droppedZoneId,
        toBottom: HardwareKeyboard.instance.isAltPressed,
      );
      return;
    }

    final local = _globalToTableLocal(globalTopLeft);
    final rawCenter = Offset(
      local.dx + cardWidth / 2,
      local.dy + cardHeight / 2,
    );
    final target = _findStackTarget(
      tableTops: tableTops,
      excludingInstanceId: instanceId,
      center: rawCenter,
    );
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
        widget.controller.returnToZone(
          instanceId,
          target.zoneId!,
          toBottom: altHeld,
        );
      } else {
        widget.controller.stackCard(instanceId, target.instanceId);
      }
    } else {
      // Keep the whole card clear of both hand zones -- otherwise a drop
      // released over a hand zone band lands behind it, unselectable.
      final clampedY = clampCardCenterY(
        proposedCenterY: rawCenter.dy,
        tableHeight: kWorldSize.height,
        cardHeight: cardHeight,
      );
      final (fx, fy) = localPixelToCanonical(
        pixelX: rawCenter.dx,
        pixelY: clampedY,
        tableWidth: kWorldSize.width,
        tableHeight: kWorldSize.height,
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
  void _handlePileDragEnd(
    String rootId,
    List<CardInstance> pileCards,
    Offset globalTopLeft,
  ) {
    final globalCenter =
        globalTopLeft + const Offset(cardWidth / 2, cardHeight / 2);
    if (_isOverLocalHandZone(globalCenter)) {
      final ordered = pileCards.toList()
        ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
      for (final c in ordered) {
        widget.controller.moveToHand(c.instanceId);
      }
      return;
    }

    final local = _globalToTableLocal(globalTopLeft);
    final rawCenter = Offset(
      local.dx + cardWidth / 2,
      local.dy + cardHeight / 2,
    );
    final clampedY = clampCardCenterY(
      proposedCenterY: rawCenter.dy,
      tableHeight: kWorldSize.height,
      cardHeight: cardHeight,
    );
    final (fx, fy) = localPixelToCanonical(
      pixelX: rawCenter.dx,
      pixelY: clampedY,
      tableWidth: kWorldSize.width,
      tableHeight: kWorldSize.height,
      isMirrored: widget.isMirrored,
    );
    widget.controller.moveStack(rootId, fx, fy);
  }

  /// Shared position math for a board widget drag release -- converts a
  /// drag's raw global top-left into the canonical center position a widget
  /// of [widgetWidth]/[widgetHeight] should land at, clamped clear of the
  /// hand-zone bands via [clampCardCenterY] just like a card drop.
  (double, double) _widgetDropPosition(
    Offset globalTopLeft,
    double widgetWidth,
    double widgetHeight,
  ) {
    final local = _globalToTableLocal(globalTopLeft);
    final rawCenter = Offset(
      local.dx + widgetWidth / 2,
      local.dy + widgetHeight / 2,
    );
    final clampedY = clampCardCenterY(
      proposedCenterY: rawCenter.dy,
      tableHeight: kWorldSize.height,
      cardHeight: widgetHeight,
    );
    return localPixelToCanonical(
      pixelX: rawCenter.dx,
      pixelY: clampedY,
      tableWidth: kWorldSize.width,
      tableHeight: kWorldSize.height,
      isMirrored: widget.isMirrored,
    );
  }

  /// Repositions a placed board widget after a drag release -- structurally
  /// like [_handleDragEnd]'s plain-move branch, minus every card-specific
  /// concern (hand/zone drop targets, stacking) a widget has none of.
  void _handleWidgetDragEnd(
    String instanceId,
    Offset globalTopLeft, {
    required double widgetWidth,
    required double widgetHeight,
  }) {
    final (fx, fy) = _widgetDropPosition(
      globalTopLeft,
      widgetWidth,
      widgetHeight,
    );
    widget.controller.moveWidget(instanceId, fx, fy);
  }

  /// A plain (non-Ctrl) drag release on a [TokenWidget]: if the drop lands
  /// on a card (within [_stackHitRadius], same hit-test [_findStackTarget]
  /// uses for card-onto-card stacking), the token attaches to it instead of
  /// just moving there -- left exactly where it was dropped (not snapped to
  /// the card's center), then carried along at that same offset by
  /// `TableActions`'s attached-widget sync on every future move of that
  /// card/pile. See `TableActions.attachWidgetToCard`. Dropping on empty
  /// space instead falls back to a plain [_handleWidgetDragEnd], which
  /// detaches any previous attachment.
  void _handleTokenDragEnd(
    String instanceId,
    Offset globalTopLeft, {
    required List<CardInstance> tableTops,
  }) {
    final local = _globalToTableLocal(globalTopLeft);
    final rawCenter = Offset(
      local.dx + tokenWidgetSize / 2,
      local.dy + tokenWidgetSize / 2,
    );
    final target = _findStackTarget(
      tableTops: tableTops,
      excludingInstanceId: instanceId,
      center: rawCenter,
    );
    if (target != null) {
      final (fx, fy) = _widgetDropPosition(
        globalTopLeft,
        tokenWidgetSize,
        tokenWidgetSize,
      );
      widget.controller.attachWidgetToCard(
        instanceId,
        target.instanceId,
        fx,
        fy,
      );
    } else {
      _handleWidgetDragEnd(
        instanceId,
        globalTopLeft,
        widgetWidth: tokenWidgetSize,
        widgetHeight: tokenWidgetSize,
      );
    }
  }

  /// Ctrl+drag on a [TokenWidget]: creates a copy at the drop position
  /// (mirroring `TableActions.duplicateWidget`, leaving [instanceId] exactly
  /// where it was), and -- if the drop lands on a card -- attaches that new
  /// copy to it too, exactly like [_handleTokenDragEnd]'s plain-drag
  /// attachment. Without this, a Ctrl-duplicate released directly onto a
  /// card would create a free-floating clone right where a plain drag would
  /// have attached, which reads as broken since the two gestures otherwise
  /// behave identically except for leaving the original in place.
  void _duplicateTokenAt(
    String instanceId,
    Offset globalTopLeft, {
    required List<CardInstance> tableTops,
  }) {
    final local = _globalToTableLocal(globalTopLeft);
    final rawCenter = Offset(
      local.dx + tokenWidgetSize / 2,
      local.dy + tokenWidgetSize / 2,
    );
    final target = _findStackTarget(
      tableTops: tableTops,
      excludingInstanceId: instanceId,
      center: rawCenter,
    );
    final (fx, fy) = _widgetDropPosition(
      globalTopLeft,
      tokenWidgetSize,
      tokenWidgetSize,
    );
    final newInstanceId = _uuid.v4();
    widget.controller.duplicateWidget(instanceId, newInstanceId, fx, fy);
    if (target != null) {
      widget.controller.attachWidgetToCard(
        newInstanceId,
        target.instanceId,
        fx,
        fy,
      );
    }
  }

  /// Right-clicking empty table space: a first menu picking a category (just
  /// "Widgets" today), then a second listing that category's widget types
  /// (just "Simple Counter" today) -- two plain sequential [showMenu] calls
  /// rather than a nested-submenu widget, since a catalog of one item in one
  /// category doesn't warrant building a generic plugin system; a second
  /// category or widget type is just one more [PopupMenuItem] in the
  /// relevant list. The same click position anchors both menus and becomes
  /// the new widget's canonical position.
  Future<void> _showBoardContextMenu(Offset globalPosition) async {
    final category = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: const [PopupMenuItem(value: 'widgets', child: Text('Widgets'))],
    );
    if (category != 'widgets' || !mounted) return;

    final kind = await showMenu<BoardWidgetKind>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: const [
        PopupMenuItem(
          value: BoardWidgetKind.simpleCounter,
          child: Text('Simple Counter'),
        ),
        PopupMenuItem(value: BoardWidgetKind.token, child: Text('Token')),
      ],
    );
    if (kind == null || !mounted) return;

    final local = _globalToTableLocal(globalPosition);
    final (fx, fy) = localPixelToCanonical(
      pixelX: local.dx,
      pixelY: local.dy,
      tableWidth: kWorldSize.width,
      tableHeight: kWorldSize.height,
      isMirrored: widget.isMirrored,
    );
    widget.controller.createWidget(_uuid.v4(), kind, fx, fy);
  }

  /// Right-clicking a placed [CounterWidget]: Increment/Decrement send the
  /// current value +/- 1 as a new absolute value (the host-side clamp in
  /// `TableActions.setWidgetValue` handles both ends of the range), Set
  /// Value opens [_promptSetValue], Set Colors opens [_promptSetColors],
  /// Delete removes it outright.
  Future<void> _showCounterMenu(
    Offset globalPosition,
    BoardWidgetInstance instance,
  ) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: const [
        PopupMenuItem(value: 'increment', child: Text('Increment')),
        PopupMenuItem(value: 'decrement', child: Text('Decrement')),
        PopupMenuItem(value: 'setValue', child: Text('Set Value')),
        PopupMenuItem(value: 'setColors', child: Text('Set Colors')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'increment':
        widget.controller.setWidgetValue(
          instance.instanceId,
          instance.value + 1,
        );
      case 'decrement':
        widget.controller.setWidgetValue(
          instance.instanceId,
          instance.value - 1,
        );
      case 'setValue':
        await _promptSetValue(instance);
      case 'setColors':
        await _promptSetColors(instance);
      case 'delete':
        widget.controller.deleteWidget(instance.instanceId);
    }
  }

  /// A modal numeric prompt for Set Value -- the one deliberate exception to
  /// this app having no other [showDialog] anywhere, since a blocking
  /// numeric prompt has no other natural fit here. Non-numeric input shows
  /// an inline error and keeps the dialog open rather than silently
  /// substituting a fallback (unlike the `?? default` idiom used for the
  /// join screen's port field) -- a valid but out-of-range number is instead
  /// clamped and accepted, matching the spec's "validated, clamped to
  /// 0-99999".
  Future<void> _promptSetValue(BoardWidgetInstance instance) async {
    final textController = TextEditingController(text: '${instance.value}');
    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        String? error;
        return StatefulBuilder(
          builder: (context, setState) => AlertDialog(
            title: const Text('Set Value'),
            content: TextField(
              controller: textController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Value (0-$boardWidgetCounterMax)',
                errorText: error,
              ),
              onSubmitted: (_) {
                final parsed = int.tryParse(textController.text.trim());
                if (parsed == null) {
                  setState(() => error = 'Enter a whole number');
                  return;
                }
                Navigator.of(context).pop(
                  parsed.clamp(boardWidgetCounterMin, boardWidgetCounterMax),
                );
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () {
                  final parsed = int.tryParse(textController.text.trim());
                  if (parsed == null) {
                    setState(() => error = 'Enter a whole number');
                    return;
                  }
                  Navigator.of(context).pop(
                    parsed.clamp(boardWidgetCounterMin, boardWidgetCounterMax),
                  );
                },
                child: const Text('Set'),
              ),
            ],
          ),
        );
      },
    );
    textController.dispose();
    if (result != null && mounted)
      widget.controller.setWidgetValue(instance.instanceId, result);
  }

  /// A modal prompt to set a widget's background/text color from a small
  /// fixed palette ([boardWidgetColorPalette]) -- there's no color-picker
  /// dependency in this app, and a preset swatch grid is simpler than
  /// building/adding one for a cosmetic setting.
  Future<void> _promptSetColors(BoardWidgetInstance instance) async {
    int background = instance.backgroundColor;
    int text = instance.textColor;
    final result = await showDialog<(int, int)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Set Colors'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Background'),
                const SizedBox(height: 8),
                _colorSwatchRow(
                  selected: background,
                  onSelected: (c) => setState(() => background = c),
                ),
                const SizedBox(height: 16),
                const Text('Text'),
                const SizedBox(height: 8),
                _colorSwatchRow(
                  selected: text,
                  onSelected: (c) => setState(() => text = c),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop((background, text)),
              child: const Text('Set'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) {
      widget.controller.setWidgetColors(
        instance.instanceId,
        result.$1,
        result.$2,
      );
    }
  }

  /// Right-clicking a placed [TokenWidget]: Set Color opens
  /// [_promptSetTokenColor], Delete removes it outright. A token has no
  /// numeric state, so unlike [_showCounterMenu] there's no Increment/
  /// Decrement/Set Value.
  Future<void> _showTokenMenu(
    Offset globalPosition,
    BoardWidgetInstance instance,
  ) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: const [
        PopupMenuItem(value: 'setColor', child: Text('Set Color')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    if (!mounted) return;
    switch (action) {
      case 'setColor':
        await _promptSetTokenColor(instance);
      case 'delete':
        widget.controller.deleteWidget(instance.instanceId);
    }
  }

  /// Like [_promptSetColors] but for a single color -- a token has no text
  /// to color, just its own fill. [BoardWidgetInstance.textColor] is left
  /// untouched (meaningless for a token, but preserved rather than
  /// overwritten in case a future kind change ever wants it back).
  Future<void> _promptSetTokenColor(BoardWidgetInstance instance) async {
    int color = instance.backgroundColor;
    final result = await showDialog<int>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setState) => AlertDialog(
          title: const Text('Set Color'),
          content: SingleChildScrollView(
            child: _colorSwatchRow(
              selected: color,
              onSelected: (c) => setState(() => color = c),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(color),
              child: const Text('Set'),
            ),
          ],
        ),
      ),
    );
    if (result != null && mounted) {
      widget.controller.setWidgetColors(
        instance.instanceId,
        result,
        instance.textColor,
      );
    }
  }

  /// One row of tappable swatches from [boardWidgetColorPalette] -- the
  /// currently [selected] one gets a highlighted ring.
  Widget _colorSwatchRow({
    required int selected,
    required ValueChanged<int> onSelected,
  }) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final c in boardWidgetColorPalette)
          GestureDetector(
            onTap: () => onSelected(c),
            child: Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: Color(c),
                shape: BoxShape.circle,
                border: Border.all(
                  color: c == selected ? Colors.blueAccent : Colors.black26,
                  width: c == selected ? 3 : 1,
                ),
              ),
            ),
          ),
      ],
    );
  }

  /// A large, always-upright rendering of exactly what [instance] currently
  /// shows (real face if face-up, a back otherwise) positioned in the center
  /// of whichever half of [screenSize] the cursor isn't in, clamped to stay
  /// fully on screen regardless of card image aspect ratio or window size.
  Widget _buildHoverPreview(
    CardInstance instance,
    CardDefinition? definition,
    Size screenSize,
  ) {
    // Only a table card's own orientation is honored here (matching
    // DraggableCard/PileWidget's applyOrientation) -- a hand/zone card is
    // never actually rendered rotated on screen, so its preview shouldn't be
    // either.
    final orientation = instance.zone == CardZone.table
        ? (definition?.orientation ?? CardOrientation.portrait)
        : CardOrientation.portrait;
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
    final targetCenterX = onLeftHalf
        ? screenSize.width * 0.75
        : screenSize.width * 0.25;
    final left = (targetCenterX - previewWidth / 2).clamp(
      0.0,
      screenSize.width - previewWidth,
    );
    final top = (screenSize.height / 2 - previewHeight / 2).clamp(
      0.0,
      screenSize.height - previewHeight,
    );

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
              child: SizedBox(
                width: cardWidth,
                height: cardHeight,
                child: content,
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The local player's own instance of an owned [zone], wrapped in the
  /// standard translucent box every zone gets, keyed for [_localZoneIdAt] so
  /// a drop can land here.
  Widget _buildLocalZoneWidget(
    ZoneDefinition zone,
    List<CardInstance> cards,
    List<CardInstance> tableTops,
    List<CardInstance> pickupCandidates,
    List<CardInstance> localHand,
  ) {
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
          topDefinition: top == null
              ? null
              : widget.definitionsById[top.definitionId],
          onDragEnd: top == null
              ? null
              : (offset) => _handleDragEnd(
                  tableTops,
                  pickupCandidates,
                  top.instanceId,
                  offset,
                  localHand,
                ),
          onShuffle: cards.isEmpty || !zone.shuffleable
              ? null
              : () => widget.controller.shuffleZone(zone.id),
          cardBackImagePath: widget.cardBackImagePath,
        ),
      ),
    );
  }

  /// The opponent's instance of an owned [zone], read-only. [cards] is
  /// whatever this client's own filtered state carries for it -- real cards
  /// only for a `ZoneDefinition.visibleToAll` zone (see state_filter.dart),
  /// otherwise already-redacted stand-ins with no real face to show.
  Widget _buildOpponentZoneWidget(
    ZoneDefinition zone,
    List<CardInstance> cards,
  ) {
    final top = cards.isEmpty ? null : _stackUtils.topOf(cards);
    return ColoredBox(
      color: Colors.black.withValues(alpha: 0.15),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: OpponentZoneStackWidget(
          zoneName: zone.name,
          count: cards.length,
          topFaceUp: top?.faceUp ?? false,
          topDefinition: top == null
              ? null
              : widget.definitionsById[top.definitionId],
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
            final localHand =
                state.cards
                    .where(
                      (c) =>
                          c.zone == CardZone.hand &&
                          c.ownerId == session.localPlayerId,
                    )
                    .toList()
                  ..sort((a, b) => a.zIndex.compareTo(b.zIndex));
            final opponentHandCount = state.cards
                .where(
                  (c) =>
                      c.zone == CardZone.hand &&
                      c.ownerId != session.localPlayerId,
                )
                .length;

            final localZoneCardsById = {
              for (final z in ownedZones)
                z.id: state.cards
                    .where(
                      (c) =>
                          c.zone == CardZone.zone &&
                          c.zoneId == z.id &&
                          c.ownerId == session.localPlayerId,
                    )
                    .toList(),
            };
            final opponentZoneCardsById = {
              for (final z in ownedZones)
                z.id: state.cards
                    .where(
                      (c) =>
                          c.zone == CardZone.zone &&
                          c.zoneId == z.id &&
                          c.ownerId != null &&
                          c.ownerId != session.localPlayerId,
                    )
                    .toList(),
            };
            final sharedZoneCardsById = {
              for (final z in sharedZones)
                z.id: state.cards
                    .where((c) => c.zone == CardZone.zone && c.zoneId == z.id)
                    .toList(),
            };

            // Free-table piles -- ad-hoc stacks built by dragging cards
            // together, unrelated to any zone (a pile is not a zone).
            final tableCardsOnly = state.cards
                .where((c) => c.zone == CardZone.table)
                .toList();
            final pileGroups = _stackUtils.groupByStack(tableCardsOnly);
            // Sorted so a higher-zIndex pile/card (the one most recently
            // moved, flipped, rotated, or stacked -- see TableActions) is
            // built later in this Stack's children and therefore actually
            // paints on top of an overlapping lower one; Map iteration order
            // alone (the old behavior) had no relationship to zIndex at all.
            final sortedPileEntries = pileGroups.entries.toList()
              ..sort(
                (a, b) => _stackUtils
                    .topOf(a.value)
                    .zIndex
                    .compareTo(_stackUtils.topOf(b.value).zIndex),
              );

            final freeTableTops = [
              for (final g in pileGroups.values) _stackUtils.topOf(g),
            ];
            final tableTops = <CardInstance>[
              ...freeTableTops,
              for (final z in sharedZones)
                if (sharedZoneCardsById[z.id]!.isNotEmpty)
                  _stackUtils.topOf(sharedZoneCardsById[z.id]!),
            ];
            // Candidates for a drag's pickup group (see _pickupGroup) --
            // free-table piles only (dragging a card never rips the top card
            // off a shared zone pile just because it's visually nearby), and
            // never a card owned by the other player (so you can't
            // indirectly drag an opponent's card by pulling your own card
            // out from under it).
            final pickupCandidates = freeTableTops
                .where(
                  (c) =>
                      c.ownerId == null || c.ownerId == session.localPlayerId,
                )
                .toList();

            CardInstance? hoveredInstance;
            if (_hoveredInstanceId != null) {
              for (final c in state.cards) {
                if (c.instanceId == _hoveredInstanceId) {
                  hoveredInstance = c;
                  break;
                }
              }
            }
            final hoveredDefinition = hoveredInstance == null
                ? null
                : widget.definitionsById[hoveredInstance.definitionId];
            final showPreview = hoveredInstance != null && _spacePressed;
            final opponentBorderColor = parseHexColor(
              widget.opponentCardBorderColor,
            );

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
                              for (final zone in ownedZones)
                                _buildOpponentZoneWidget(
                                  zone,
                                  opponentZoneCardsById[zone.id]!,
                                ),
                            ],
                          ),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                _tableSize = constraints.biggest;
                                return GestureDetector(
                                  behavior: HitTestBehavior.opaque,
                                  onSecondaryTapUp: (details) =>
                                      _showBoardContextMenu(
                                        details.globalPosition,
                                      ),
                                  // TAB-held drag draws an arrow (see _tabPressed/_commitArrowDrag) --
                                  // every interactive card/pile/counter/token call site below passes
                                  // `interactable: !_tabPressed` while TAB is held, so this ancestor
                                  // pan gesture wins uncontested instead of fighting a descendant
                                  // Draggable's own recognizer.
                                  //
                                  // All three callbacks are wired unconditionally whenever TAB is
                                  // held (never additionally gated on whether a drag has actually
                                  // started) so the PanGestureRecognizer is fully wired from the very
                                  // first build -- gating on drag-in-progress state meant onUpdate/
                                  // onEnd stayed null until a rebuild landed, leaving a window where a
                                  // fast drag's move/end events could reach the recognizer before they
                                  // were reassigned. None of these call setState -- see _arrowDrag's
                                  // doc comment for why a per-pixel setState on this State (whose
                                  // build() constructs the entire table) was the real cause of both
                                  // the wrong-endpoint and the table-blanking bugs.
                                  onPanStart: !_tabPressed
                                      ? null
                                      : (details) {
                                          final p = _globalToTableLocal(
                                            details.globalPosition,
                                          );
                                          _arrowDrag.value = (
                                            start: p,
                                            current: p,
                                          );
                                        },
                                  onPanUpdate: !_tabPressed
                                      ? null
                                      : (details) {
                                          final drag = _arrowDrag.value;
                                          if (drag == null) return;
                                          _arrowDrag.value = (
                                            start: drag.start,
                                            current: _globalToTableLocal(
                                              details.globalPosition,
                                            ),
                                          );
                                        },
                                  onPanEnd: !_tabPressed
                                      ? null
                                      : (details) {
                                          if (_arrowDrag.value == null) return;
                                          _commitArrowDrag();
                                        },
                                  // The camera pan (WASD, see _cameraOffset) is plain arithmetic baked
                                  // into _toScreenPixel/_globalToTableLocal directly (see their doc
                                  // comments for why an ancestor Transform was tried and abandoned) --
                                  // every card's Positioned box already reflects its true current
                                  // on-screen position, so this Stack needs no special sizing beyond
                                  // the default viewport. ClipRect (sized to this same, unchanged
                                  // LayoutBuilder box) keeps panned content from ever bleeding into the
                                  // fixed hand/zone rows above and below.
                                  child: ClipRect(
                                    child: Stack(
                                      key: _tableKey,
                                      clipBehavior: Clip.none,
                                      children: [
                                        for (final group in sortedPileEntries)
                                          Builder(
                                            builder: (context) {
                                              final cards = group.value;
                                              final top = _stackUtils.topOf(
                                                cards,
                                              );
                                              final pos = _toScreenPixel(
                                                top.x,
                                                top.y,
                                              );
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
                                              final ownedByOpponent =
                                                  top.ownerId != null &&
                                                  top.ownerId !=
                                                      session.localPlayerId;
                                              // _pickupGroup requires dragged to be a member of candidates (see its
                                              // doc comment), which pickupCandidates deliberately violates for an
                                              // opponent-owned top card -- skip it here since an opponent pile is
                                              // never interactable/draggable anyway, so pickupGroup would never be
                                              // consulted for it.
                                              final pickupGroup =
                                                  ownedByOpponent
                                                  ? <CardInstance>[top]
                                                  : _pickupGroup(
                                                      pickupCandidates,
                                                      top,
                                                    );
                                              final isGhostedPassenger =
                                                  _activeDragGroupIds != null &&
                                                  _activeDragGroupIds!.contains(
                                                    top.instanceId,
                                                  ) &&
                                                  top.instanceId !=
                                                      _activeDragPrimaryId;
                                              if (cards.length > 1) {
                                                // PileWidget's own box is larger than a bare
                                                // card (room for its badge/shuffle button to
                                                // overflow) -- center on that actual size, or
                                                // the pile renders shifted off its true
                                                // canonical position (see pileWidgetExtra).
                                                return Positioned(
                                                  left:
                                                      pos.dx -
                                                      (cardWidth +
                                                              pileWidgetExtra) /
                                                          2,
                                                  top:
                                                      pos.dy -
                                                      (cardHeight +
                                                              pileWidgetExtra) /
                                                          2,
                                                  child: Opacity(
                                                    opacity: isGhostedPassenger
                                                        ? 0.3
                                                        : 1.0,
                                                    child: PileWidget(
                                                      count: cards.length,
                                                      topInstanceId:
                                                          top.instanceId,
                                                      topFaceUp: top.faceUp,
                                                      topDefinition:
                                                          widget
                                                              .definitionsById[top
                                                              .definitionId],
                                                      topRotationTurns:
                                                          top.rotationTurns,
                                                      onDraw: () => widget
                                                          .controller
                                                          .drawCard(group.key),
                                                      onDragStarted: () =>
                                                          _startGroupDrag(
                                                            pickupGroup,
                                                          ),
                                                      feedbackOverride:
                                                          pickupGroup.length > 1
                                                          ? _buildGroupFeedback(
                                                              pickupGroup,
                                                              top,
                                                            )
                                                          : null,
                                                      onDragEnd: (offset) {
                                                        _endGroupDrag();
                                                        if (HardwareKeyboard
                                                            .instance
                                                            .isAltPressed) {
                                                          _handlePileDragEnd(
                                                            group.key,
                                                            cards,
                                                            offset,
                                                          );
                                                        } else {
                                                          _handleDragEnd(
                                                            tableTops,
                                                            pickupCandidates,
                                                            top.instanceId,
                                                            offset,
                                                            localHand,
                                                          );
                                                        }
                                                      },
                                                      onShuffle: () => widget
                                                          .controller
                                                          .shufflePile(
                                                            group.key,
                                                          ),
                                                      isMirrored:
                                                          ownedByOpponent,
                                                      interactable:
                                                          !ownedByOpponent &&
                                                          !_tabPressed,
                                                      applyOrientation: true,
                                                      topBorderColor:
                                                          ownedByOpponent
                                                          ? opponentBorderColor
                                                          : null,
                                                      onHover: (hovering) =>
                                                          _setHoveredId(
                                                            hovering
                                                                ? top.instanceId
                                                                : null,
                                                          ),
                                                      cardBackImagePath: widget
                                                          .cardBackImagePath,
                                                    ),
                                                  ),
                                                );
                                              }
                                              if (_flyingDiscard?.instanceId ==
                                                  top.instanceId) {
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
                                                child: Opacity(
                                                  opacity: isGhostedPassenger
                                                      ? 0.3
                                                      : 1.0,
                                                  child: DraggableCard(
                                                    instance: top,
                                                    definition:
                                                        widget
                                                            .definitionsById[top
                                                            .definitionId],
                                                    isMirrored: ownedByOpponent,
                                                    interactable:
                                                        !ownedByOpponent &&
                                                        !_tabPressed,
                                                    applyOrientation: true,
                                                    opponentBorderColor:
                                                        ownedByOpponent
                                                        ? opponentBorderColor
                                                        : null,
                                                    onDragStarted: () =>
                                                        _startGroupDrag(
                                                          pickupGroup,
                                                        ),
                                                    feedbackOverride:
                                                        pickupGroup.length > 1
                                                        ? _buildGroupFeedback(
                                                            pickupGroup,
                                                            top,
                                                          )
                                                        : null,
                                                    onDragEnd: (offset) {
                                                      _endGroupDrag();
                                                      _handleDragEnd(
                                                        tableTops,
                                                        pickupCandidates,
                                                        top.instanceId,
                                                        offset,
                                                        localHand,
                                                      );
                                                    },
                                                    onHover: (hovering) =>
                                                        _setHoveredId(
                                                          hovering
                                                              ? top.instanceId
                                                              : null,
                                                        ),
                                                    cardBackImagePath: widget
                                                        .cardBackImagePath,
                                                  ),
                                                ),
                                              );
                                            },
                                          ),
                                        // Board widgets (e.g. a Simple Counter) always render above every
                                        // card -- cards and widgets don't share a unified z-order, since
                                        // they're never expected to visually interleave the way two cards
                                        // stack together.
                                        for (final w in state.widgets.where(
                                          (w) =>
                                              w.kind != BoardWidgetKind.arrow,
                                        ))
                                          Builder(
                                            builder: (context) {
                                              final pos = _toScreenPixel(
                                                w.x,
                                                w.y,
                                              );
                                              final (
                                                widgetWidth,
                                                widgetHeight,
                                              ) = _widgetSize(
                                                w.kind,
                                              );
                                              // Dimmed in place while a copy follows the cursor via
                                              // _buildGroupFeedback -- same idea as isGhostedPassenger
                                              // for a card, keyed off the card it's attached to
                                              // (rather than its own instanceId) being part of the
                                              // active drag group.
                                              final isGhostedAttachedWidget =
                                                  _activeDragGroupIds != null &&
                                                  w.attachedCardId != null &&
                                                  _activeDragGroupIds!.contains(
                                                    w.attachedCardId,
                                                  );
                                              return Positioned(
                                                left: pos.dx - widgetWidth / 2,
                                                top: pos.dy - widgetHeight / 2,
                                                child: Opacity(
                                                  opacity:
                                                      isGhostedAttachedWidget
                                                      ? 0.3
                                                      : 1.0,
                                                  child: switch (w.kind) {
                                                    BoardWidgetKind
                                                        .simpleCounter =>
                                                      CounterWidget(
                                                        instance: w,
                                                        onDragEnd: (offset) =>
                                                            _handleWidgetDragEnd(
                                                              w.instanceId,
                                                              offset,
                                                              widgetWidth:
                                                                  widgetWidth,
                                                              widgetHeight:
                                                                  widgetHeight,
                                                            ),
                                                        onSecondaryTapUp:
                                                            (globalPos) =>
                                                                _showCounterMenu(
                                                                  globalPos,
                                                                  w,
                                                                ),
                                                        interactable:
                                                            !_tabPressed,
                                                      ),
                                                    // Ctrl+drag duplicates instead of moving -- see
                                                    // _duplicateTokenAt; a plain drag either attaches to
                                                    // whatever card it lands on (see _handleTokenDragEnd) or
                                                    // just moves normally.
                                                    BoardWidgetKind.token =>
                                                      TokenWidget(
                                                        instance: w,
                                                        onDragEnd: (offset) {
                                                          if (HardwareKeyboard
                                                              .instance
                                                              .isControlPressed) {
                                                            _duplicateTokenAt(
                                                              w.instanceId,
                                                              offset,
                                                              tableTops:
                                                                  tableTops,
                                                            );
                                                          } else {
                                                            _handleTokenDragEnd(
                                                              w.instanceId,
                                                              offset,
                                                              tableTops:
                                                                  tableTops,
                                                            );
                                                          }
                                                        },
                                                        onSecondaryTapUp:
                                                            (globalPos) =>
                                                                _showTokenMenu(
                                                                  globalPos,
                                                                  w,
                                                                ),
                                                        interactable:
                                                            !_tabPressed,
                                                      ),
                                                    // Unreachable -- this loop's iterable already
                                                    // excludes arrows (see the `.where` above); only here
                                                    // to satisfy exhaustiveness.
                                                    BoardWidgetKind.arrow =>
                                                      const SizedBox.shrink(),
                                                  },
                                                ),
                                              );
                                            },
                                          ),
                                        // Arrows (see _commitArrowDrag) render as a line between two
                                        // points instead of a single centered box, so they get their own
                                        // loop rather than a third arm on the switches above.
                                        for (final w in state.widgets.where(
                                          (w) =>
                                              w.kind == BoardWidgetKind.arrow,
                                        ))
                                          Builder(
                                            builder: (context) {
                                              final from = _toScreenPixel(
                                                w.x,
                                                w.y,
                                              );
                                              final to = _toScreenPixel(
                                                w.x2!,
                                                w.y2!,
                                              );
                                              final dismissible =
                                                  w.creatorId == null ||
                                                  w.creatorId ==
                                                      session.localPlayerId;
                                              return ArrowWidget(
                                                from: from,
                                                to: to,
                                                onDoubleTap: dismissible
                                                    ? () => widget.controller
                                                          .deleteWidget(
                                                            w.instanceId,
                                                          )
                                                    : null,
                                              );
                                            },
                                          ),
                                        // The live TAB-drag preview -- purely local UI state (see
                                        // _arrowDrag), never a real networked arrow until
                                        // _commitArrowDrag runs. A ValueListenableBuilder scoped to
                                        // just this one widget, not a setState on the whole State, so a
                                        // pointer move during the drag only ever rebuilds this small
                                        // subtree -- see _arrowDrag's doc comment.
                                        //
                                        // Must always resolve to exactly one Positioned Stack child
                                        // (see ArrowWidget's own doc comment) -- the "nothing to show"
                                        // branch uses a degenerate zero-size Positioned rather than a
                                        // bare SizedBox, and ArrowWidget's own ignorePointer flag is
                                        // used instead of wrapping it in an external IgnorePointer, so
                                        // this slot never introduces a non-Positioned child into a
                                        // Stack that otherwise has none.
                                        ValueListenableBuilder(
                                          valueListenable: _arrowDrag,
                                          builder: (context, drag, _) {
                                            if (drag == null) {
                                              return const Positioned(
                                                left: 0,
                                                top: 0,
                                                width: 0,
                                                height: 0,
                                                child: SizedBox.shrink(),
                                              );
                                            }
                                            return ArrowWidget(
                                              from: drag.start,
                                              to: drag.current,
                                              ignorePointer: true,
                                            );
                                          },
                                        ),
                                        if (_flyingDiscard != null)
                                          _buildFlyingDiscard(_flyingDiscard!),
                                        for (final zone in sharedZones)
                                          if (sharedZoneCardsById[zone.id]!
                                              .isNotEmpty)
                                            Builder(
                                              builder: (context) {
                                                final cards =
                                                    sharedZoneCardsById[zone
                                                        .id]!;
                                                final top = _stackUtils.topOf(
                                                  cards,
                                                );
                                                final pos = _toScreenPixel(
                                                  top.x,
                                                  top.y,
                                                );
                                                if (cards.length > 1) {
                                                  return Positioned(
                                                    left:
                                                        pos.dx -
                                                        (cardWidth +
                                                                pileWidgetExtra) /
                                                            2,
                                                    top:
                                                        pos.dy -
                                                        (cardHeight +
                                                                pileWidgetExtra) /
                                                            2,
                                                    child: Tooltip(
                                                      message: zone.name,
                                                      child: PileWidget(
                                                        count: cards.length,
                                                        topInstanceId:
                                                            top.instanceId,
                                                        topFaceUp: top.faceUp,
                                                        topDefinition:
                                                            widget
                                                                .definitionsById[top
                                                                .definitionId],
                                                        onDraw: () => widget
                                                            .controller
                                                            .drawFromZone(
                                                              zone.id,
                                                            ),
                                                        onDragEnd: (offset) =>
                                                            _handleDragEnd(
                                                              tableTops,
                                                              pickupCandidates,
                                                              top.instanceId,
                                                              offset,
                                                              localHand,
                                                            ),
                                                        onShuffle:
                                                            zone.shuffleable
                                                            ? () => widget
                                                                  .controller
                                                                  .shuffleZone(
                                                                    zone.id,
                                                                  )
                                                            : null,
                                                        cardBackImagePath: widget
                                                            .cardBackImagePath,
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
                                                      definition:
                                                          widget
                                                              .definitionsById[top
                                                              .definitionId],
                                                      onDragEnd: (offset) =>
                                                          _handleDragEnd(
                                                            tableTops,
                                                            pickupCandidates,
                                                            top.instanceId,
                                                            offset,
                                                            localHand,
                                                          ),
                                                      onHover: (hovering) =>
                                                          _setHoveredId(
                                                            hovering
                                                                ? top.instanceId
                                                                : null,
                                                          ),
                                                      cardBackImagePath: widget
                                                          .cardBackImagePath,
                                                    ),
                                                  ),
                                                );
                                              },
                                            ),
                                      ],
                                    ),
                                  ),
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
                                  onDragEnd: (id, offset) => _handleDragEnd(
                                    tableTops,
                                    pickupCandidates,
                                    id,
                                    offset,
                                    localHand,
                                  ),
                                  onHoverCard: _setHoveredId,
                                  cardBackImagePath: widget.cardBackImagePath,
                                  cardKeyFor: _handCardKey,
                                ),
                              ),
                              for (final zone in ownedZones)
                                _buildLocalZoneWidget(
                                  zone,
                                  localZoneCardsById[zone.id]!,
                                  tableTops,
                                  pickupCandidates,
                                  localHand,
                                ),
                            ],
                          ),
                        ],
                      ),
                      if (showPreview)
                        _buildHoverPreview(
                          hoveredInstance!,
                          hoveredDefinition,
                          screenSize,
                        ),
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
