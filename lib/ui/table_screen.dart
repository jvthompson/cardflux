import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/game_session.dart';
import '../game/geometry_utils.dart';
import '../game/stack_utils.dart';
import '../game/table_controller.dart';
import '../models/card_definition.dart';
import '../models/card_instance.dart';
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

            return Column(
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
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
