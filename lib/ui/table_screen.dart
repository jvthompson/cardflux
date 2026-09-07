import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../game/game_session.dart';
import '../game/geometry_utils.dart';
import '../game/stack_utils.dart';
import '../game/table_controller.dart';
import '../models/card_definition.dart';
import '../models/card_instance.dart';
import 'widgets/card_back_widget.dart';
import 'widgets/card_face_widget.dart';
import 'widgets/draggable_card.dart';
import 'widgets/hand_zone_widget.dart';
import 'widgets/opponent_hand_zone_widget.dart';
import 'widgets/pile_widget.dart';

const StackUtils _stackUtils = StackUtils();

/// Overlap radius (in logical pixels) within which dropping a card onto
/// another counts as stacking rather than a bare move.
const double _stackHitRadius = cardWidth * 0.6;

/// The main gameplay surface: a free-form table where cards can be dragged
/// anywhere, flipped, and stacked into piles, plus the local player's hand.
/// Every action goes through [controller] -- the host applies it directly,
/// a client sends it to the host and waits for the next state broadcast.
///
/// [isMirrored] renders the shared table area's *positions* (not the hand
/// zones, which always keep their own fixed top/bottom layout) as if viewed
/// from the opposite seat -- both axes flipped -- so a card dragged near one
/// player's own hand appears near the *other* player's, matching a physical
/// table where the two seats face each other. The host is always the
/// canonical/unmirrored seat; the client is always mirrored. Each card's
/// *rotation* is separate from this and is decided per-card in [build] by
/// who last held it (`CardInstance.ownerId`), not by seat -- so a card
/// always faces upright for whichever player played it, on both screens.
///
/// Holding Alt while hovering any card shows a full-size preview of exactly
/// what's currently visible for that card (its real face if face-up, a back
/// otherwise -- never an x-ray of hidden information), positioned in the
/// center of whichever half of the screen the cursor *isn't* on so it's
/// always fully visible and never covers the card being inspected.
class TableScreen extends StatefulWidget {
  const TableScreen({super.key, required this.definitionsById, required this.controller, required this.isMirrored});

  final Map<String, CardDefinition> definitionsById;
  final TableController controller;
  final bool isMirrored;

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  final GlobalKey _tableKey = GlobalKey();
  final GlobalKey _handZoneKey = GlobalKey();

  /// The table Stack's own measured size, refreshed every build via the
  /// LayoutBuilder in [build] -- needed to convert canonical [0,1] fractions
  /// to this screen's pixels *during* the same build that lays the Stack
  /// out, before `_tableBox` (which needs a completed layout) is available.
  Size _tableSize = Size.zero;

  /// Instance id of the card currently under the mouse, or null. Looked up
  /// fresh against the latest [TableState.cards] on every build (rather than
  /// caching the [CardInstance] itself) so the Alt-preview never shows stale
  /// data if the hovered card changes underneath the cursor (e.g. flipped,
  /// or moved by the other player) without the mouse actually leaving it.
  String? _hoveredInstanceId;

  /// Latest raw mouse position (window-global coordinates), updated on every
  /// hover event without triggering a rebuild -- only read at the moment a
  /// rebuild already has to happen (hover target or Alt state changing) to
  /// decide which half of the screen the preview belongs in.
  Offset _lastMousePos = Offset.zero;

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
    super.dispose();
  }

  /// Only Alt down/up actually needs to change anything on screen; rebuild
  /// on those and read `HardwareKeyboard.instance.isAltPressed` fresh in
  /// [build] rather than tracking a separate bool, so there's no risk of it
  /// desyncing from the real modifier state.
  bool _handleKeyEvent(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.altLeft || event.logicalKey == LogicalKeyboardKey.altRight) {
      setState(() {});
    }
    return false;
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

  /// Finds the nearest other top-of-stack card within [_stackHitRadius] of
  /// [center], if any — used to decide whether a drop should stack instead
  /// of just moving.
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

  void _handleDragEnd(List<CardInstance> tableTops, String instanceId, Offset globalTopLeft) {
    final globalCenter = globalTopLeft + const Offset(cardWidth / 2, cardHeight / 2);
    if (_isOverLocalHandZone(globalCenter)) {
      widget.controller.moveToHand(instanceId);
      return;
    }

    final local = _globalToTableLocal(globalTopLeft);
    final rawCenter = Offset(local.dx + cardWidth / 2, local.dy + cardHeight / 2);
    final target = _findStackTarget(tableTops: tableTops, excludingInstanceId: instanceId, center: rawCenter);
    if (target != null) {
      widget.controller.stackCard(instanceId, target.instanceId);
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

  /// A large, always-upright rendering of exactly what [instance] currently
  /// shows (real face if face-up, a back otherwise) positioned in the center
  /// of whichever half of [screenSize] the cursor isn't in, clamped to stay
  /// fully on screen regardless of card image aspect ratio or window size.
  Widget _buildHoverPreview(CardInstance instance, CardDefinition? definition, Size screenSize) {
    double previewHeight = screenSize.height * 0.7;
    double previewWidth = previewHeight * (cardWidth / cardHeight);
    final maxWidth = screenSize.width * 0.42;
    if (previewWidth > maxWidth) {
      previewWidth = maxWidth;
      previewHeight = previewWidth * (cardHeight / cardWidth);
    }

    final onLeftHalf = _lastMousePos.dx < screenSize.width / 2;
    final targetCenterX = onLeftHalf ? screenSize.width * 0.75 : screenSize.width * 0.25;
    final left = (targetCenterX - previewWidth / 2).clamp(0.0, screenSize.width - previewWidth);
    final top = (screenSize.height / 2 - previewHeight / 2).clamp(0.0, screenSize.height - previewHeight);

    final content = instance.faceUp && definition != null ? CardFaceWidget(definition: definition) : const CardBackWidget();

    return Positioned(
      left: left,
      top: top,
      child: IgnorePointer(
        child: SizedBox(
          width: previewWidth,
          height: previewHeight,
          child: FittedBox(
            fit: BoxFit.contain,
            child: SizedBox(width: cardWidth, height: cardHeight, child: content),
          ),
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
            final localHand = state.cards
                .where((c) => c.zone == CardZone.hand && c.ownerId == session.localPlayerId)
                .toList();
            final opponentHandCount = state.cards
                .where((c) => c.zone == CardZone.hand && c.ownerId != session.localPlayerId)
                .length;
            final tableCards = state.cards.where((c) => c.zone != CardZone.hand).toList();
            final groups = _stackUtils.groupByStack(tableCards);
            final tops = groups.values.map(_stackUtils.topOf).toList();

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
            final showPreview = hoveredInstance != null && HardwareKeyboard.instance.isAltPressed;

            return LayoutBuilder(
              builder: (context, outerConstraints) {
                final screenSize = outerConstraints.biggest;
                return MouseRegion(
                  onHover: (event) => _lastMousePos = event.position,
                  child: Stack(
                    children: [
                      Column(
                        children: [
                          OpponentHandZoneWidget(count: opponentHandCount),
                          Expanded(
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                _tableSize = constraints.biggest;
                                return Stack(
                                  key: _tableKey,
                                  clipBehavior: Clip.none,
                                  children: [
                                    for (final group in groups.entries)
                                      Builder(builder: (context) {
                                        final cards = group.value;
                                        final top = _stackUtils.topOf(cards);
                                        final pos = _toScreenPixel(top.x, top.y);
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
                                              onDraw: () => widget.controller.drawCard(group.key),
                                              onShuffle: () => widget.controller.shufflePile(group.key),
                                            ),
                                          );
                                        }
                                        return Positioned(
                                          left: pos.dx - cardWidth / 2,
                                          top: pos.dy - cardHeight / 2,
                                          child: DraggableCard(
                                            instance: top,
                                            definition: widget.definitionsById[top.definitionId],
                                            // A card faces whichever player last held it
                                            // (moveCard/stackCard never clear ownerId),
                                            // not whichever seat is viewing it -- so it
                                            // stays upright for its own player on both
                                            // screens and only appears rotated to the
                                            // other player. A never-held card (still in
                                            // the shared pile) has no owner and stays
                                            // neutral/unrotated for everyone.
                                            isMirrored: top.ownerId != null && top.ownerId != session.localPlayerId,
                                            onTapFlip: () => widget.controller.flipCard(top.instanceId),
                                            onDragEnd: (offset) => _handleDragEnd(tops, top.instanceId, offset),
                                            onHover: (hovering) => _setHoveredId(hovering ? top.instanceId : null),
                                          ),
                                        );
                                      }),
                                  ],
                                );
                              },
                            ),
                          ),
                          HandZoneWidget(
                            key: _handZoneKey,
                            cards: localHand,
                            definitionsById: widget.definitionsById,
                            onTapFlip: (id) => widget.controller.flipCard(id),
                            onDragEnd: (id, offset) => _handleDragEnd(tops, id, offset),
                            onHoverCard: _setHoveredId,
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
