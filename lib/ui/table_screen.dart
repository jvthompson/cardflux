import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../app_theme.dart';
import '../game/game_session.dart';
import '../game/geometry_utils.dart';
import '../game/seat_utils.dart';
import '../game/shared_zone_layout.dart';
import '../game/stack_utils.dart';
import '../game/table_controller.dart';
import '../models/active_search.dart';
import '../models/board_widget_instance.dart';
import '../models/card_definition.dart';
import '../models/card_instance.dart';
import '../models/player.dart';
import '../models/table_state.dart';
import '../models/zone_definition.dart';
import 'widgets/arrow_widget.dart';
import 'widgets/avatar_widget.dart';
import 'widgets/card_back_widget.dart';
import 'widgets/card_face_widget.dart';
import 'widgets/color_swatch_row.dart';
import 'widgets/counter_widget.dart';
import 'widgets/draggable_card.dart';
import 'widgets/hand_zone_widget.dart';
import 'widgets/opponent_hand_zone_widget.dart';
import 'widgets/opponent_zone_stack_widget.dart';
import 'widgets/pile_widget.dart';
import 'widgets/token_widget.dart';
import 'widgets/zone_search_overlay.dart';
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
    this.cardBackImagePath,
    this.localPlayerAvatarPath,
    this.avatarBytesByPlayerId = const {},
    this.gameFolderPath,
  });

  final Map<String, CardDefinition> definitionsById;
  final TableController controller;
  final bool isMirrored;

  /// This game's non-hand zones (see `ZoneDefinition`) -- owned ones render
  /// clustered next to each player's hand, shared ones render on the open
  /// table like any other pile.
  final List<ZoneDefinition> zones;

  final String? cardBackImagePath;

  /// This machine's own local folder for the game being played (see
  /// `GameDefinition.folderPath`) -- null for the bundled standard-52 deck,
  /// or if this is a client that hasn't yet resolved a local copy of the
  /// host's game. Used only to look for a `_playmats` subfolder to pick a
  /// random background image from (see [_TableScreenState._buildCenterMarker]);
  /// gameplay itself never depends on it.
  final String? gameFolderPath;

  /// The local player's own avatar, read from their local
  /// `PlayerProfileSettings`/`PlayerAvatarFileOps` file -- never round-
  /// tripped over the network to itself, unlike [avatarBytesByPlayerId].
  final String? localPlayerAvatarPath;

  /// Every OTHER known player's avatar bytes, keyed by player id --
  /// received over the network (see `HostServer`/`GameClient`'s `hello`/
  /// `lobbyRosterUpdate` avatar payload) and passed down by
  /// `HostGameScreen`/`ClientGameScreen`. The local player's own avatar is
  /// always rendered from [localPlayerAvatarPath] instead.
  final Map<String, Uint8List> avatarBytesByPlayerId;

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

  /// True when [_hoveredInstanceId] came from a Search window tile -- forces
  /// [_buildHoverPreview] to show the real face regardless of
  /// `CardInstance.faceUp`, since searching a deck already reveals every
  /// card's real face to the searcher (see `ZoneSearchOverlay`'s own grid);
  /// the Space-hold preview shouldn't fall back to showing a back just
  /// because the card is face-down at rest in the pile.
  bool _hoveredForceFaceUp = false;

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

  /// Toggled by F1 -- while true, [ownerBorderColor]-driven card borders are
  /// hidden table-wide (they can get visually busy with 3-4 players' colors
  /// all showing at once). Session-local only, resets to visible on the next
  /// table screen build -- not a persisted preference.
  bool _bordersHidden = false;

  /// Toggled by F2 -- while true (the default), every zone/hand background
  /// and each player's avatar+name header background use a darkened shade
  /// of that player's own color (see `_playerTintColor`) instead of the flat
  /// black tint every background used before this existed. Session-local
  /// only, resets to the color-tinted default on the next table screen
  /// build -- not a persisted preference, mirroring [_bordersHidden].
  bool _colorTintEnabled = true;

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
    if (_pressedMovementKeys.contains(LogicalKeyboardKey.keyA)) dx += 1;
    if (_pressedMovementKeys.contains(LogicalKeyboardKey.keyD)) dx -= 1;
    if (_pressedMovementKeys.contains(LogicalKeyboardKey.keyW)) dy += 1;
    if (_pressedMovementKeys.contains(LogicalKeyboardKey.keyS)) dy -= 1;
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

  /// Fixed size (in [kWorldSize]'s real, unscaled pixels) of the darker-green
  /// landmark rectangle centered on the table -- 1600x900 so it fills most of
  /// a 1920x1080 viewport's visible playspace, giving every player a shared
  /// reference for "the general center of the table" regardless of their own
  /// window size or camera pan.
  static const Size _centerMarkerSize = Size(1600, 900);
  static const double _centerMarkerRadius = 32;

  /// A static rectangle centered on [kWorldSize] itself, not on any card or
  /// canonical [0,1] position -- deliberately bypasses
  /// [canonicalToLocalPixel]/[_toWorldPixel] (which exist for *card*
  /// placement) and instead offsets straight from world-pixel space, since
  /// this marker has no canonical fraction of its own and simply needs to
  /// track the same camera pan/centering every card does.
  ///
  /// [_playmatImagePath], when set, is drawn faded (50% opacity, so it never
  /// competes with cards placed over it) and clipped to the same rounded
  /// rect as the border -- the border itself is a separate, fully-opaque
  /// layer on top so it stays a crisp, reliable landmark regardless of how
  /// busy or light/dark the chosen art is.
  Widget _buildCenterMarker() {
    final left = (kWorldSize.width - _centerMarkerSize.width) / 2;
    final top = (kWorldSize.height - _centerMarkerSize.height) / 2;
    final origin = Offset(left, top) + _worldOffset + _clampedCameraOffset;
    final imagePath = _playmatImagePath;
    return Positioned(
      left: origin.dx,
      top: origin.dy,
      width: _centerMarkerSize.width,
      height: _centerMarkerSize.height,
      child: IgnorePointer(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (imagePath != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(_centerMarkerRadius),
                child: Opacity(
                  opacity: 0.5,
                  child: Image.file(File(imagePath), fit: BoxFit.cover),
                ),
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                border: Border.all(color: const Color(0xFF063D2A), width: 4),
                borderRadius: BorderRadius.circular(_centerMarkerRadius),
              ),
            ),
          ],
        ),
      ),
    );
  }

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
    _maybeLoadPlaymat();
  }

  @override
  void didUpdateWidget(covariant TableScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.gameFolderPath != widget.gameFolderPath) _maybeLoadPlaymat();
  }

  /// Every playmat image found in [widget.gameFolderPath]'s `_playmats`
  /// subfolder, shuffled once when the folder is first scanned (see
  /// [_maybeLoadPlaymat]) -- [_playmatIndex] then just walks this fixed
  /// order as F12 is pressed (see [_cyclePlaymat]), rather than re-rolling
  /// randomly each time, so cycling forward eventually visits every image
  /// exactly once before wrapping back around. Purely local/visual --
  /// deliberately never synced over the network (unlike table state), so
  /// each player is free to cycle their own playmat independently.
  List<String> _playmatImages = const [];

  /// Index into [_playmatImages], or -1 for "no playmat" (just the plain
  /// bordered rectangle) -- the initial state even once images are found, so
  /// the table starts bare and F12 has to be pressed to bring the first
  /// image in. [_cyclePlaymat] walks 0, 1, ..., length-1, -1, 0, ... so "no
  /// playmat" is one stop in the cycle, not just a fallback for the empty
  /// case.
  int _playmatIndex = -1;
  String? _playmatScannedFolderPath;

  /// The playmat currently shown by [_buildCenterMarker] -- null (falling
  /// back to a plain bordered rectangle) if [widget.gameFolderPath] has no
  /// `_playmats` subfolder, none with any image in it, or [_playmatIndex] is
  /// currently on the "no playmat" stop of the cycle.
  String? get _playmatImagePath =>
      _playmatIndex < 0 ? null : _playmatImages[_playmatIndex];

  static const _playmatExtensions = {'.png', '.jpg', '.jpeg', '.webp'};

  static String _extensionOf(String path) {
    final dot = path.lastIndexOf('.');
    return dot == -1 ? '' : path.substring(dot).toLowerCase();
  }

  Future<void> _maybeLoadPlaymat() async {
    final folderPath = widget.gameFolderPath;
    if (folderPath == null || folderPath == _playmatScannedFolderPath) return;
    _playmatScannedFolderPath = folderPath;
    final playmatsDir = Directory(
      '$folderPath${Platform.pathSeparator}_playmats',
    );
    List<FileSystemEntity> entries;
    try {
      entries = await playmatsDir.list().toList();
    } catch (_) {
      return;
    }
    final images = [
      for (final e in entries)
        if (e is File && _playmatExtensions.contains(_extensionOf(e.path)))
          e.path,
    ];
    if (images.isEmpty || !mounted) return;
    images.shuffle();
    setState(() => _playmatImages = images);
  }

  /// Advances [_playmatIndex] to the next stop in the cycle: image 0, 1, ...,
  /// length-1, then -1 ("no playmat") before wrapping back to image 0 -- a
  /// no-op with no images at all, since there's nothing to cycle to.
  void _cyclePlaymat() {
    if (_playmatImages.isEmpty) return;
    setState(() {
      _playmatIndex = _playmatIndex + 1 >= _playmatImages.length
          ? -1
          : _playmatIndex + 1;
    });
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

  /// 1-9 (both the top-row digits and the numpad) while hovering a
  /// deck/pile draws that many cards -- see [_drawNFromHovered].
  static final _drawCountKeys = {
    LogicalKeyboardKey.digit1: 1,
    LogicalKeyboardKey.digit2: 2,
    LogicalKeyboardKey.digit3: 3,
    LogicalKeyboardKey.digit4: 4,
    LogicalKeyboardKey.digit5: 5,
    LogicalKeyboardKey.digit6: 6,
    LogicalKeyboardKey.digit7: 7,
    LogicalKeyboardKey.digit8: 8,
    LogicalKeyboardKey.digit9: 9,
    LogicalKeyboardKey.numpad1: 1,
    LogicalKeyboardKey.numpad2: 2,
    LogicalKeyboardKey.numpad3: 3,
    LogicalKeyboardKey.numpad4: 4,
    LogicalKeyboardKey.numpad5: 5,
    LogicalKeyboardKey.numpad6: 6,
    LogicalKeyboardKey.numpad7: 7,
    LogicalKeyboardKey.numpad8: 8,
    LogicalKeyboardKey.numpad9: 9,
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
      } else if (event.logicalKey == LogicalKeyboardKey.keyX) {
        _discardHovered();
      } else if (event.logicalKey == LogicalKeyboardKey.keyF) {
        _flipHovered();
      } else if (event.logicalKey == LogicalKeyboardKey.home) {
        setState(() => _cameraOffset = Offset.zero);
      } else if (event.logicalKey == LogicalKeyboardKey.f1) {
        setState(() => _bordersHidden = !_bordersHidden);
      } else if (event.logicalKey == LogicalKeyboardKey.f2) {
        setState(() => _colorTintEnabled = !_colorTintEnabled);
      } else if (event.logicalKey == LogicalKeyboardKey.f12) {
        _cyclePlaymat();
      } else {
        final drawCount = _drawCountKeys[event.logicalKey];
        if (drawCount != null) _drawNFromHovered(drawCount);
      }
    }
    return false;
  }

  /// The hovered card, if it exists, sits on the table, and belongs to the
  /// local player -- the shared precondition for both Q/E and X (discard).
  /// Reads the session directly (outside `build()`, this is a raw keyboard callback,
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

  /// What pressing a 1-9 draw-count key while hovering would draw from, if
  /// anything -- a free-table pile (own card only, resolved to its stack
  /// root like [_rotateHovered] does), this zone's own instance of an owned
  /// zone, or any shared zone (any card count) -- but never a hand card or
  /// another player's owned zone. Same non-caching, re-scan-by-id idiom as
  /// [_ownedHoveredTableCard]/[_hoveredFlippableCard].
  ({String? pileRootId, String? zoneId, String? zoneOwnerId})?
  _hoveredDrawTarget() {
    final id = _hoveredInstanceId;
    if (id == null) return null;
    final session = context.read<GameSession>();
    for (final c in session.state.cards) {
      if (c.instanceId != id) continue;
      switch (c.zone) {
        case CardZone.table:
          if (c.ownerId != session.localPlayerId) return null;
          final rootId = _stackUtils.rootIdOf(session.state.cards, c);
          return (pileRootId: rootId, zoneId: null, zoneOwnerId: null);
        case CardZone.zone:
          if (c.ownerId != null && c.ownerId != session.localPlayerId) {
            return null;
          }
          return (pileRootId: null, zoneId: c.zoneId, zoneOwnerId: c.ownerId);
        case CardZone.hand:
          return null;
      }
    }
    return null;
  }

  /// Draws [n] cards (see [TableController.drawCard]/[drawFromZone]'s
  /// clamp-to-available behavior) from whatever [_hoveredDrawTarget]
  /// resolves to -- a no-op if nothing's hovered.
  void _drawNFromHovered(int n) {
    final target = _hoveredDrawTarget();
    if (target == null) return;
    final pileRootId = target.pileRootId;
    if (pileRootId != null) {
      widget.controller.drawCard(pileRootId, count: n);
    } else {
      widget.controller.drawFromZone(target.zoneId!, count: n);
    }
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
          onDoubleTapSide: (_) {},
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

  void _setHoveredId(String? id, {bool forceFaceUp = false}) {
    if (_hoveredInstanceId != id || _hoveredForceFaceUp != forceFaceUp) {
      setState(() {
        _hoveredInstanceId = id;
        _hoveredForceFaceUp = forceFaceUp;
      });
    }
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

  /// Finds the id of the nearest empty shared zone (see
  /// [emptySharedZonePositions]) within [_stackHitRadius] of [center], if
  /// any -- the empty-zone counterpart to [_findStackTarget], which only
  /// matches a shared zone that already has a card in it (an empty zone has
  /// no `CardInstance` to match against). Consulted only after
  /// [_findStackTarget] returns null, so a drop that's simultaneously near a
  /// real card/pile and an empty zone still prefers the real card.
  String? _findEmptySharedZoneTarget({
    required Map<String, (double, double)> emptySharedZonePositions,
    required Offset center,
  }) {
    String? best;
    double bestDist = double.infinity;
    for (final entry in emptySharedZonePositions.entries) {
      final (fx, fy) = entry.value;
      final dist = (_toWorldPixel(fx, fy) - center).distance;
      if (dist < _stackHitRadius && dist < bestDist) {
        best = entry.key;
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
    Map<String, (double, double)> emptySharedZonePositions,
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
      // No real card/pile nearby -- check for an empty shared zone's
      // reserved placeholder before giving up and just moving the card.
      // TableActions.returnToZone already anchors the first card landed in
      // a previously-empty shared zone to that zone's own reserved
      // position, so this snaps into place exactly like a drop onto a
      // shared zone that already has cards does above.
      final emptyZoneId = _findEmptySharedZoneTarget(
        emptySharedZonePositions: emptySharedZonePositions,
        center: rawCenter,
      );
      if (emptyZoneId != null) {
        widget.controller.returnToZone(
          instanceId,
          emptyZoneId,
          toBottom: altHeld,
        );
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
  /// Right-clicking a zone/pile the local player is allowed to search --
  /// a single-item menu (room for more later, matching the style of every
  /// other context menu here) that opens a Search window via [onSearch].
  Future<void> _showSearchMenu(
    Offset globalPosition,
    VoidCallback onSearch,
  ) async {
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        globalPosition.dx,
        globalPosition.dy,
        globalPosition.dx,
        globalPosition.dy,
      ),
      items: const [PopupMenuItem(value: 'search', child: Text('Search...'))],
    );
    if (action == 'search') onSearch();
  }

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
                ColorSwatchRow(
                  selected: background,
                  onSelected: (c) => setState(() => background = c),
                ),
                const SizedBox(height: 16),
                const Text('Text'),
                const SizedBox(height: 8),
                ColorSwatchRow(
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
            child: ColorSwatchRow(
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

  /// The local player's own Search window, if [session] has an
  /// [ActiveSearch] recorded for them in [state.searches] -- null otherwise
  /// (every other client only ever sees the eyeball badge, wired at each
  /// zone/pile's own render site). Lives as a `Stack` sibling of the board
  /// itself (see call site), not a pushed route, so its `Draggable` cards
  /// can still be released onto the table/hand through the same
  /// `_handleDragEnd` every other drag uses.
  Widget? _buildSearchOverlay(
    TableState state,
    GameSession session,
    Size screenSize,
    List<CardInstance> tableTops,
    Map<String, (double, double)> emptySharedZonePositions,
    List<CardInstance> pickupCandidates,
    List<CardInstance> localHand,
  ) {
    ActiveSearch? mySearch;
    for (final s in state.searches) {
      if (s.searcherId == session.localPlayerId) {
        mySearch = s;
        break;
      }
    }
    final search = mySearch;
    if (search == null) return null;

    final List<CardInstance> cards;
    String title;
    if (search.targetType == SearchTargetType.zone) {
      cards = state.cards
          .where(
            (c) =>
                c.zone == CardZone.zone &&
                c.zoneId == search.targetId &&
                c.ownerId == search.targetOwnerId,
          )
          .toList();
      title = 'Zone';
      for (final z in widget.zones) {
        if (z.id == search.targetId) {
          title = z.name;
          break;
        }
      }
    } else {
      cards = _stackUtils.stackOf(state.cards, search.targetId);
      title = 'Pile';
    }
    // Topmost card (highest zIndex, see StackUtils.topOf) listed first.
    cards.sort((a, b) => b.zIndex.compareTo(a.zIndex));

    return ZoneSearchOverlay(
      title: title,
      cards: cards,
      definitionsById: widget.definitionsById,
      screenSize: screenSize,
      onClose: () => widget.controller.stopSearch(),
      onCardDragEnd: (instanceId, offset) => _handleDragEnd(
        tableTops,
        emptySharedZonePositions,
        pickupCandidates,
        instanceId,
        offset,
        localHand,
      ),
      onCardHover: (instanceId, hovering) =>
          _setHoveredId(hovering ? instanceId : null, forceFaceUp: true),
    );
  }

  /// A large, always-upright rendering of exactly what [instance] currently
  /// shows (real face if face-up, a back otherwise) positioned in the center
  /// of whichever half of [screenSize] the cursor isn't in, clamped to stay
  /// fully on screen regardless of card image aspect ratio or window size.
  /// [forceFaceUp] overrides a face-down [instance] to show its real face
  /// anyway -- set when the hover came from a Search window tile (see
  /// [_hoveredForceFaceUp]'s doc).
  Widget _buildHoverPreview(
    CardInstance instance,
    CardDefinition? definition,
    Size screenSize,
    bool forceFaceUp,
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

    final content = (instance.faceUp || forceFaceUp) && definition != null
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
    Map<String, (double, double)> emptySharedZonePositions,
    List<CardInstance> pickupCandidates,
    List<CardInstance> localHand,
    bool isBeingSearched,
    Color? borderColor,
    Color backgroundColor,
  ) {
    final top = cards.isEmpty ? null : _stackUtils.topOf(cards);
    return GestureDetector(
      onSecondaryTapUp: (details) => _showSearchMenu(
        details.globalPosition,
        () => widget.controller.startSearchZone(zone.id),
      ),
      child: ColoredBox(
        key: _zoneKey(zone.id),
        color: backgroundColor,
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
                    emptySharedZonePositions,
                    pickupCandidates,
                    top.instanceId,
                    offset,
                    localHand,
                  ),
            onShuffle: cards.isEmpty || !zone.shuffleable
                ? null
                : () => widget.controller.shuffleZone(zone.id),
            isBeingSearched: isBeingSearched,
            cardBackImagePath: widget.cardBackImagePath,
            borderColor: borderColor,
            onHover: top == null
                ? null
                : (hovering) => _setHoveredId(hovering ? top.instanceId : null),
          ),
        ),
      ),
    );
  }

  /// The other player's instance of an owned [zone], read-only. [cards] is
  /// whatever this client's own filtered state carries for it -- real cards
  /// only for a `ZoneDefinition.visibleToAll` zone (see state_filter.dart),
  /// otherwise already-redacted stand-ins with no real face to show.
  Widget _buildOpponentZoneWidget(
    ZoneDefinition zone,
    List<CardInstance> cards,
    bool isBeingSearched,
    Color? borderColor,
    Color backgroundColor,
  ) {
    final top = cards.isEmpty ? null : _stackUtils.topOf(cards);
    return ColoredBox(
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: OpponentZoneStackWidget(
          zoneName: zone.name,
          count: cards.length,
          topFaceUp: top?.faceUp ?? false,
          topDefinition: top == null
              ? null
              : widget.definitionsById[top.definitionId],
          isBeingSearched: isBeingSearched,
          cardBackImagePath: widget.cardBackImagePath,
          borderColor: borderColor,
        ),
      ),
    );
  }

  /// Builds one player's raw hand+owned-zones content, in either its
  /// interactive form ([player] is the local player) or read-only form
  /// (anyone else) -- shared by both the bottom and top rows so there's one
  /// definition of "how a player's panel looks," not a separate hardcoded
  /// local/opponent pair. Returned unwrapped (no `Expanded`, no rotation) so
  /// the caller ([_buildPlayerRow]) can apply both in the right order --
  /// wrapping an already-`Expanded` widget in a `RotatedBox` is invalid,
  /// since `Expanded` must be a direct child of the `Row`/`Column` itself.
  ({Widget hand, List<Widget> zones}) _panelContent({
    required PlayerInfo player,
    required GameSession session,
    required List<ZoneDefinition> ownedZones,
    required List<CardInstance> tableTops,
    required Map<String, (double, double)> emptySharedZonePositions,
    required List<CardInstance> pickupCandidates,
    required List<CardInstance> localHand,
    required Map<String, int> handCountByPlayerId,
    required Map<String, List<CardInstance>> localZoneCardsById,
    required Map<String, Map<String, List<CardInstance>>> zoneCardsByPlayerIdThenZoneId,
    required bool Function(String zoneId, String? ownerId) isZoneSearched,
    required Color? Function(String? ownerId) ownerBorderColor,
    required Color Function(String? ownerId) zoneBackgroundColor,
  }) {
    final isLocal = player.id == session.localPlayerId;
    final borderColor = ownerBorderColor(player.id);
    final backgroundColor = zoneBackgroundColor(player.id);
    final handWidget = isLocal
        ? HandZoneWidget(
            key: _handZoneKey,
            cards: localHand,
            definitionsById: widget.definitionsById,
            onDragEnd: (id, offset) => _handleDragEnd(
              tableTops,
              emptySharedZonePositions,
              pickupCandidates,
              id,
              offset,
              localHand,
            ),
            onHoverCard: _setHoveredId,
            cardBackImagePath: widget.cardBackImagePath,
            cardKeyFor: _handCardKey,
            borderColor: borderColor,
            backgroundColor: backgroundColor,
          )
        : OpponentHandZoneWidget(
            count: handCountByPlayerId[player.id] ?? 0,
            cardBackImagePath: widget.cardBackImagePath,
            borderColor: borderColor,
            backgroundColor: backgroundColor,
          );
    final zoneWidgets = [
      for (final zone in ownedZones)
        isLocal
            ? _buildLocalZoneWidget(
                zone,
                localZoneCardsById[zone.id]!,
                tableTops,
                emptySharedZonePositions,
                pickupCandidates,
                localHand,
                isZoneSearched(zone.id, player.id),
                borderColor,
                backgroundColor,
              )
            : _buildOpponentZoneWidget(
                zone,
                zoneCardsByPlayerIdThenZoneId[player.id]?[zone.id] ?? const [],
                isZoneSearched(zone.id, player.id),
                borderColor,
                backgroundColor,
              ),
    ];
    return (hand: handWidget, zones: zoneWidgets);
  }

  /// A darkened, semi-transparent tint of [rawColor] (a `PlayerInfo.color`
  /// ARGB int) -- used for every zone/hand background (via
  /// `zoneBackgroundColor` in [build]), table-wide whenever
  /// [_colorTintEnabled] is true. Lightness is pulled down and
  /// alpha kept well below opaque so the felt-green table still faintly
  /// shows through, matching the flat black tint's own translucent feel
  /// rather than reading as a solid block.
  Color _playerTintColor(int rawColor) {
    final hsl = HSLColor.fromColor(Color(rawColor));
    final darker = hsl.withLightness((hsl.lightness - 0.30).clamp(0.0, 1.0));
    return darker.toColor().withValues(alpha: 0.55);
  }

  /// A player's avatar + name, sized and styled to sit in their panel's
  /// outer corner as if it were one more zone -- same `ColoredBox`+`Padding`
  /// shape, same [cardWidth]/[cardHeight] + [pileWidgetExtra] footprint, and
  /// the same [backgroundColor] as their actual zones (see
  /// `zoneBackgroundColor` in [build]) so it reads as a continuous strip
  /// with no visible seam, not a separate floating element -- square corners
  /// (no radius) come for free from not adding any `BorderRadius` here, same
  /// as the zone widgets. Never rotated even for a rotated top-row occupant
  /// -- a name reads better upright regardless of seat side. The local
  /// player's own avatar renders from their local file
  /// ([TableScreen.localPlayerAvatarPath]); every other player's avatar
  /// renders from bytes received over the network (see
  /// [TableScreen.avatarBytesByPlayerId]). Dimmed when
  /// [PlayerInfo.connected] is false, matching the zones' own disconnected
  /// styling.
  Widget _avatarCorner(PlayerInfo player, {required bool isLocal, required Color backgroundColor}) {
    return ColoredBox(
      color: backgroundColor,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        child: SizedBox(
          width: cardWidth + pileWidgetExtra,
          height: cardHeight + pileWidgetExtra,
          child: Opacity(
            opacity: player.connected ? 1 : 0.5,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min,
              children: [
                AvatarWidget(
                  color: player.color,
                  imagePath: isLocal ? widget.localPlayerAvatarPath : null,
                  imageBytes: isLocal ? null : widget.avatarBytesByPlayerId[player.id],
                  size: cardWidth,
                ),
                const SizedBox(height: 4),
                Text(
                  player.connected ? player.name : '${player.name} (disconnected)',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70, fontSize: 10),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// One full row (bottom or top) of 1-2 player panels, separated by a
  /// small gutter when there are two, so they don't visually run together.
  /// A non-local occupant of the *top* row has their hand/zone content
  /// rendered upside-down (matching the original single-opponent visual
  /// convention) whenever there are more than 2 total players -- a 2-player
  /// game's single top occupant is never rotated here, keeping that layout
  /// pixel-identical to before 3-4 player support existed.
  Widget _buildPlayerRow({
    required List<PlayerInfo> rowPlayers,
    required bool isTopRow,
    required int totalPlayerCount,
    required bool crossAxisStart,
    required GameSession session,
    required List<ZoneDefinition> ownedZones,
    required List<CardInstance> tableTops,
    required Map<String, (double, double)> emptySharedZonePositions,
    required List<CardInstance> pickupCandidates,
    required List<CardInstance> localHand,
    required Map<String, int> handCountByPlayerId,
    required Map<String, List<CardInstance>> localZoneCardsById,
    required Map<String, Map<String, List<CardInstance>>> zoneCardsByPlayerIdThenZoneId,
    required bool Function(String zoneId, String? ownerId) isZoneSearched,
    required Color? Function(String? ownerId) ownerBorderColor,
    required Color Function(String? ownerId) zoneBackgroundColor,
  }) {
    if (rowPlayers.isEmpty) return const SizedBox.shrink();
    final panels = <Widget>[
      for (final (i, player) in rowPlayers.indexed)
        Expanded(
          child: Column(
            // Explicit min -- this Column sits under an effectively
            // unbounded height constraint (a non-flex child of a Row that
            // is itself a non-flex sibling of this screen's Expanded middle
            // table), so the default MainAxisSize.max would try to consume
            // all of it instead of sizing to exactly (header + content row)
            // -- undefined-behavior territory that surfaced as the two
            // side-by-side bottom panels ending up different heights.
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Builder(
                builder: (context) {
                  final content = _panelContent(
                    player: player,
                    session: session,
                    ownedZones: ownedZones,
                    tableTops: tableTops,
                    emptySharedZonePositions: emptySharedZonePositions,
                    pickupCandidates: pickupCandidates,
                    localHand: localHand,
                    handCountByPlayerId: handCountByPlayerId,
                    localZoneCardsById: localZoneCardsById,
                    zoneCardsByPlayerIdThenZoneId: zoneCardsByPlayerIdThenZoneId,
                    isZoneSearched: isZoneSearched,
                    ownerBorderColor: ownerBorderColor,
                    zoneBackgroundColor: zoneBackgroundColor,
                  );
                  // A non-local occupant of the top row renders upside-down
                  // once there are more than 2 total players (see this
                  // method's own doc) -- rotate the raw hand/zone content
                  // here, before Expanded wraps the hand, since Expanded may
                  // only be a direct Row/Column child.
                  final rotate = isTopRow && totalPlayerCount > 2 && player.id != session.localPlayerId;
                  Widget maybeRotate(Widget w) => rotate ? RotatedBox(quarterTurns: 2, child: w) : w;
                  final handChild = Expanded(child: maybeRotate(content.hand));
                  final zoneChildren = [for (final z in content.zones) maybeRotate(z)];
                  // Reversed for the "left" side of a paired 3-4p row (see
                  // the comment below), AND for a top row's sole occupant
                  // whenever they're not already being rotated (true 2-player
                  // games, always; a 3-4 player game only if the host seated
                  // themselves alone in the top row) -- without rotation to
                  // mirror the panel automatically, this is the only way an
                  // unrotated top occupant's hand/zones/avatar end up
                  // visually mirrored against the bottom row instead of
                  // just repeating its exact left-to-right order.
                  final reversePileOrder = (rowPlayers.length == 2 && i == 0) || (isTopRow && rowPlayers.length == 1 && !rotate);
                  // On the "left" side of a pair, the hand still sits
                  // closest to center (rightmost in this panel), but the
                  // zones themselves must also reverse so the *first*-
                  // defined zone (in gamedef.json) ends up adjacent to the
                  // hand and later ones fan out away from center -- the
                  // same visual rule the "right" side already gets for
                  // free by just appending zones after the hand in their
                  // natural order.
                  final orderedZoneChildren = reversePileOrder ? zoneChildren.reversed.toList() : zoneChildren;
                  // The avatar always sits in the panel's outer corner --
                  // past the last zone, on whichever end that turns out to
                  // be -- never rotated itself (a name reads better upright
                  // regardless of seat side), unlike the hand/zones above.
                  final avatarChild = _avatarCorner(
                    player,
                    isLocal: player.id == session.localPlayerId,
                    backgroundColor: zoneBackgroundColor(player.id),
                  );
                  final rowChildren = reversePileOrder
                      ? [avatarChild, ...orderedZoneChildren, handChild]
                      : [handChild, ...orderedZoneChildren, avatarChild];
                  return Row(
                    crossAxisAlignment: crossAxisStart ? CrossAxisAlignment.start : CrossAxisAlignment.end,
                    children: rowChildren,
                  );
                },
              ),
            ],
          ),
        ),
    ];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (i, panel) in panels.indexed) ...[
          if (i > 0) const SizedBox(width: 12),
          panel,
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    // Pinned to the light theme regardless of the app-wide dark-mode toggle
    // (see ThemeModeController in main.dart) -- gameplay always keeps its
    // current felt-green look.
    return Theme(data: AppTheme.light, child: _buildTable(context));
  }

  Widget _buildTable(BuildContext context) {
    // This screen's controls are entirely mouse/drag- and raw-hotkey-driven
    // (see _handleKeyEvent) -- Space/Enter activating whatever button
    // happens to still hold keyboard focus (Flutter's default Shortcuts
    // behavior) was never part of that scheme and only causes surprises
    // (e.g. a stray Space after clicking Shuffle re-triggering it).
    return Shortcuts(
      shortcuts: const <ShortcutActivator, Intent>{
        SingleActivator(LogicalKeyboardKey.space): DoNothingIntent(),
        SingleActivator(LogicalKeyboardKey.enter): DoNothingIntent(),
      },
      child: Scaffold(
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
              // Per-player, not merged -- with 3-4 players, lumping every
              // non-local player's cards into one "opponent" bucket would
              // show a combined pile instead of each of theirs separately.
              final handCountByPlayerId = {
                for (final p in state.players)
                  p.id: state.cards
                      .where((c) => c.zone == CardZone.hand && c.ownerId == p.id)
                      .length,
              };

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
              final zoneCardsByPlayerIdThenZoneId = {
                for (final p in state.players)
                  if (p.id != session.localPlayerId)
                    p.id: {
                      for (final z in ownedZones)
                        z.id: state.cards
                            .where(
                              (c) =>
                                  c.zone == CardZone.zone &&
                                  c.zoneId == z.id &&
                                  c.ownerId == p.id,
                            )
                            .toList(),
                    },
              };
              final sharedZoneCardsById = {
                for (final z in sharedZones)
                  z.id: state.cards
                      .where((c) => c.zone == CardZone.zone && c.zoneId == z.id)
                      .toList(),
              };
              // Every shared zone's reserved canonical position, regardless
              // of whether it currently has any cards -- a card's own x/y is
              // only meaningful once it has one (see the render loop below,
              // which uses this map instead for a zone with none).
              final sharedZonePositionsById = sharedZonePositions(
                widget.zones,
              );
              // The subset of sharedZonePositionsById with no cards
              // currently in them -- _handleDragEnd's only other candidate
              // target once _findStackTarget (which only sees zones that
              // already have >=1 card, via tableTops below) comes up empty.
              final emptySharedZonePositions = {
                for (final z in sharedZones)
                  if (sharedZoneCardsById[z.id]!.isEmpty)
                    z.id: sharedZonePositionsById[z.id]!,
              };

              // Whether some player currently has a Search window open on
              // zone [zoneId] (owned by [ownerId], null for shared) / the
              // free-table pile rooted at [rootInstanceId] -- drives the
              // eyeball badge, synced to every client via `state.searches`
              // regardless of who opened it.
              bool isZoneSearched(String zoneId, String? ownerId) =>
                  state.searches.any(
                    (s) =>
                        s.targetType == SearchTargetType.zone &&
                        s.targetId == zoneId &&
                        s.targetOwnerId == ownerId,
                  );
              bool isPileSearched(String rootInstanceId) => state.searches.any(
                (s) =>
                    s.targetType == SearchTargetType.pile &&
                    s.targetId == rootInstanceId,
              );

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
              // Every owned card's border is its owner's own chosen color --
              // including the local player's own cards, so every seat (not
              // just "the opponent") is visually distinguishable at a glance.
              Color? ownerBorderColor(String? ownerId) {
                if (ownerId == null || _bordersHidden) return null;
                for (final p in state.players) {
                  if (p.id == ownerId) return Color(p.color);
                }
                return null;
              }

              // Every owned zone/hand background, and each player's
              // avatar+name header background, use this -- one function so
              // F2's table-wide toggle (see _colorTintEnabled's doc) can
              // never go half-applied between the two kinds of background.
              Color zoneBackgroundColor(String? ownerId) {
                if (!_colorTintEnabled || ownerId == null) {
                  return Colors.black.withValues(alpha: 0.15);
                }
                for (final p in state.players) {
                  if (p.id == ownerId) return _playerTintColor(p.color);
                }
                return Colors.black.withValues(alpha: 0.15);
              }

              // Whether a card owned by [ownerId] should render rotated 180°
              // for the local viewer -- true iff the owner sits on the
              // opposite side of the table (a different isFarMirrorSeat
              // group), not merely "owned by someone else." Two same-side
              // players (e.g. P1/P4 sharing the near side) must see each
              // other's cards upright, exactly as they'd see their own --
              // distinct from `ownedByOpponent` below, which gates
              // interactability/menus and is correctly about strict
              // ownership, not table side.
              bool cardFacesAwayFromMe(String? ownerId) {
                if (ownerId == null) return false;
                final n = state.players.length;
                final ownerSeat = state.players.indexWhere((p) => p.id == ownerId);
                final mySeat = state.players.indexWhere((p) => p.id == session.localPlayerId);
                if (ownerSeat < 0 || mySeat < 0) return ownerId != session.localPlayerId;
                return isFarMirrorSeat(ownerSeat, n) != isFarMirrorSeat(mySeat, n);
              }

              final handRowLayout = computeHandRowLayout(state.players, session.localPlayerId);

              return LayoutBuilder(
                builder: (context, outerConstraints) {
                  final screenSize = outerConstraints.biggest;
                  final searchOverlay = _buildSearchOverlay(
                    state,
                    session,
                    screenSize,
                    tableTops,
                    emptySharedZonePositions,
                    pickupCandidates,
                    localHand,
                  );
                  return MouseRegion(
                    onHover: (event) => _lastMousePos = event.position,
                    child: Stack(
                      children: [
                        Column(
                          children: [
                            _buildPlayerRow(
                              rowPlayers: handRowLayout.topRow,
                              isTopRow: true,
                              totalPlayerCount: state.players.length,
                              crossAxisStart: true,
                              session: session,
                              ownedZones: ownedZones,
                              tableTops: tableTops,
                              emptySharedZonePositions: emptySharedZonePositions,
                              pickupCandidates: pickupCandidates,
                              localHand: localHand,
                              handCountByPlayerId: handCountByPlayerId,
                              localZoneCardsById: localZoneCardsById,
                              zoneCardsByPlayerIdThenZoneId: zoneCardsByPlayerIdThenZoneId,
                              isZoneSearched: isZoneSearched,
                              ownerBorderColor: ownerBorderColor,
                              zoneBackgroundColor: zoneBackgroundColor,
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
                                            if (_arrowDrag.value == null)
                                              return;
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
                                          // Purely a visual landmark marking the table's fixed
                                          // center -- painted first (and IgnorePointer-wrapped)
                                          // so it always sits beneath every card/zone/widget and
                                          // never intercepts a click or drag meant for them.
                                          _buildCenterMarker(),
                                          for (final group in sortedPileEntries)
                                            Builder(
                                              key: ValueKey(group.key),
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
                                                    _activeDragGroupIds !=
                                                        null &&
                                                    _activeDragGroupIds!
                                                        .contains(
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
                                                      opacity:
                                                          isGhostedPassenger
                                                          ? 0.3
                                                          : 1.0,
                                                      child: GestureDetector(
                                                        onSecondaryTapUp:
                                                            ownedByOpponent
                                                            ? null
                                                            : (
                                                                details,
                                                              ) => _showSearchMenu(
                                                                details
                                                                    .globalPosition,
                                                                () => widget
                                                                    .controller
                                                                    .startSearchPile(
                                                                      group.key,
                                                                    ),
                                                              ),
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
                                                              .drawCard(
                                                                group.key,
                                                              ),
                                                          onDragStarted: () =>
                                                              _startGroupDrag(
                                                                pickupGroup,
                                                              ),
                                                          feedbackOverride:
                                                              pickupGroup
                                                                      .length >
                                                                  1
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
                                                                emptySharedZonePositions,
                                                                pickupCandidates,
                                                                top.instanceId,
                                                                offset,
                                                                localHand,
                                                              );
                                                            }
                                                          },
                                                          onShuffle: () =>
                                                              widget.controller
                                                                  .shufflePile(
                                                                    group.key,
                                                                  ),
                                                          isMirrored:
                                                              cardFacesAwayFromMe(
                                                                top.ownerId,
                                                              ),
                                                          interactable:
                                                              !ownedByOpponent &&
                                                              !_tabPressed,
                                                          applyOrientation:
                                                              true,
                                                          topBorderColor:
                                                              ownerBorderColor(
                                                                top.ownerId,
                                                              ),
                                                          onHover: (hovering) =>
                                                              _setHoveredId(
                                                                hovering
                                                                    ? top.instanceId
                                                                    : null,
                                                              ),
                                                          cardBackImagePath: widget
                                                              .cardBackImagePath,
                                                          isBeingSearched:
                                                              isPileSearched(
                                                                group.key,
                                                              ),
                                                        ),
                                                      ),
                                                    ),
                                                  );
                                                }
                                                if (_flyingDiscard
                                                        ?.instanceId ==
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
                                                      isMirrored:
                                                          cardFacesAwayFromMe(
                                                            top.ownerId,
                                                          ),
                                                      interactable:
                                                          !ownedByOpponent &&
                                                          !_tabPressed,
                                                      applyOrientation: true,
                                                      opponentBorderColor:
                                                          ownerBorderColor(
                                                            top.ownerId,
                                                          ),
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
                                                          emptySharedZonePositions,
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
                                                    _activeDragGroupIds !=
                                                        null &&
                                                    w.attachedCardId != null &&
                                                    _activeDragGroupIds!
                                                        .contains(
                                                          w.attachedCardId,
                                                        );
                                                return Positioned(
                                                  left:
                                                      pos.dx - widgetWidth / 2,
                                                  top:
                                                      pos.dy - widgetHeight / 2,
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
                                                          onDoubleTapSide:
                                                              (
                                                                isRightSide,
                                                              ) => widget
                                                                  .controller
                                                                  .setWidgetValue(
                                                                    w.instanceId,
                                                                    w.value +
                                                                        (isRightSide
                                                                            ? 1
                                                                            : -1),
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
                                            _buildFlyingDiscard(
                                              _flyingDiscard!,
                                            ),
                                          for (final zone in sharedZones)
                                            if (sharedZoneCardsById[zone.id]!
                                                .isNotEmpty)
                                              Builder(
                                                key: ValueKey(zone.id),
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
                                                        child: GestureDetector(
                                                          onSecondaryTapUp:
                                                              (
                                                                details,
                                                              ) => _showSearchMenu(
                                                                details
                                                                    .globalPosition,
                                                                () => widget
                                                                    .controller
                                                                    .startSearchZone(
                                                                      zone.id,
                                                                    ),
                                                              ),
                                                          child: PileWidget(
                                                            count: cards.length,
                                                            topInstanceId:
                                                                top.instanceId,
                                                            topFaceUp:
                                                                top.faceUp,
                                                            topDefinition:
                                                                widget
                                                                    .definitionsById[top
                                                                    .definitionId],
                                                            onDraw: () => widget
                                                                .controller
                                                                .drawFromZone(
                                                                  zone.id,
                                                                ),
                                                            onHover: (hovering) =>
                                                                _setHoveredId(
                                                                  hovering
                                                                      ? top.instanceId
                                                                      : null,
                                                                ),
                                                            onDragEnd: (offset) =>
                                                                _handleDragEnd(
                                                                  tableTops,
                                                                  emptySharedZonePositions,
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
                                                            cardBackImagePath:
                                                                widget
                                                                    .cardBackImagePath,
                                                            isBeingSearched:
                                                                isZoneSearched(
                                                                  zone.id,
                                                                  null,
                                                                ),
                                                          ),
                                                        ),
                                                      ),
                                                    );
                                                  }
                                                  return Positioned(
                                                    left:
                                                        pos.dx - cardWidth / 2,
                                                    top:
                                                        pos.dy - cardHeight / 2,
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
                                                              emptySharedZonePositions,
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
                                              )
                                            else
                                              Builder(
                                                key: ValueKey(zone.id),
                                                builder: (context) {
                                                  final (fx, fy) =
                                                      sharedZonePositionsById[zone
                                                          .id]!;
                                                  final pos = _toScreenPixel(
                                                    fx,
                                                    fy,
                                                  );
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
                                                      child: GestureDetector(
                                                        onSecondaryTapUp:
                                                            (
                                                              details,
                                                            ) => _showSearchMenu(
                                                              details
                                                                  .globalPosition,
                                                              () => widget
                                                                  .controller
                                                                  .startSearchZone(
                                                                    zone.id,
                                                                  ),
                                                            ),
                                                        child: EmptyZoneBox(
                                                          isBeingSearched:
                                                              isZoneSearched(
                                                                zone.id,
                                                                null,
                                                              ),
                                                        ),
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
                            _buildPlayerRow(
                              rowPlayers: handRowLayout.bottomRow,
                              isTopRow: false,
                              totalPlayerCount: state.players.length,
                              crossAxisStart: false,
                              session: session,
                              ownedZones: ownedZones,
                              tableTops: tableTops,
                              emptySharedZonePositions: emptySharedZonePositions,
                              pickupCandidates: pickupCandidates,
                              localHand: localHand,
                              handCountByPlayerId: handCountByPlayerId,
                              localZoneCardsById: localZoneCardsById,
                              zoneCardsByPlayerIdThenZoneId: zoneCardsByPlayerIdThenZoneId,
                              isZoneSearched: isZoneSearched,
                              ownerBorderColor: ownerBorderColor,
                              zoneBackgroundColor: zoneBackgroundColor,
                            ),
                          ],
                        ),
                        ?searchOverlay,
                        // Painted after (on top of) the search window itself,
                        // so holding Space over a searched card's tile still
                        // shows its preview instead of it being hidden behind
                        // the window.
                        if (showPreview)
                          _buildHoverPreview(
                            hoveredInstance!,
                            hoveredDefinition,
                            screenSize,
                            _hoveredForceFaceUp,
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        ),
      ),
    );
  }
}
