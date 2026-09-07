import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../game/game_session.dart';
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
class TableScreen extends StatefulWidget {
  const TableScreen({super.key, required this.definitionsById, required this.controller});

  final Map<String, CardDefinition> definitionsById;
  final TableController controller;

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  final GlobalKey _tableKey = GlobalKey();

  Offset _globalToTableLocal(Offset global) {
    final box = _tableKey.currentContext!.findRenderObject() as RenderBox;
    return box.globalToLocal(global);
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
      final dist = (Offset(c.x, c.y) - center).distance;
      if (dist < _stackHitRadius && dist < bestDist) {
        best = c;
        bestDist = dist;
      }
    }
    return best;
  }

  void _handleDragEnd(List<CardInstance> tableTops, String instanceId, Offset globalTopLeft) {
    final local = _globalToTableLocal(globalTopLeft);
    final center = Offset(local.dx + cardWidth / 2, local.dy + cardHeight / 2);
    final target = _findStackTarget(tableTops: tableTops, excludingInstanceId: instanceId, center: center);
    if (target != null) {
      widget.controller.stackCard(instanceId, target.instanceId);
    } else {
      widget.controller.moveCard(instanceId, center.dx, center.dy);
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
                  child: Stack(
                    key: _tableKey,
                    clipBehavior: Clip.none,
                    children: [
                      for (final group in groups.entries)
                        Builder(builder: (context) {
                          final cards = group.value;
                          final top = _stackUtils.topOf(cards);
                          if (cards.length > 1) {
                            return Positioned(
                              left: top.x - cardWidth / 2,
                              top: top.y - cardHeight / 2,
                              child: PileWidget(
                                count: cards.length,
                                onDraw: () => widget.controller.drawCard(group.key),
                                onShuffle: () => widget.controller.shufflePile(group.key),
                              ),
                            );
                          }
                          return Positioned(
                            left: top.x - cardWidth / 2,
                            top: top.y - cardHeight / 2,
                            child: DraggableCard(
                              instance: top,
                              definition: widget.definitionsById[top.definitionId],
                              onTapFlip: () => widget.controller.flipCard(top.instanceId),
                              onDragEnd: (offset) => _handleDragEnd(tops, top.instanceId, offset),
                            ),
                          );
                        }),
                    ],
                  ),
                ),
                HandZoneWidget(
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
