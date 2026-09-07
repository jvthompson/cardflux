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
import 'widgets/deck_zone_widget.dart';
import 'widgets/draggable_card.dart';
import 'widgets/hand_zone_widget.dart';
import 'widgets/opponent_deck_badge_widget.dart';
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
  const TableScreen({
    super.key,
    required this.definitionsById,
    required this.controller,
    required this.isMirrored,
    required this.hasPersonalDecks,
    this.cardBackImagePath,
  });

  final Map<String, CardDefinition> definitionsById;
  final TableController controller;
  final bool isMirrored;

  /// Whether each player has their own personal deck zone (a
  /// [GameDeckMode.deckBuilding] game) -- false for a [GameDeckMode.fixedDeck]
  /// game, whose deck(s) are shared, unowned table piles instead, so neither
  /// player's deck zone/badge is rendered at all.
  final bool hasPersonalDecks;
  final String? cardBackImagePath;

  @override
  State<TableScreen> createState() => _TableScreenState();
}

class _TableScreenState extends State<TableScreen> {
  final GlobalKey _tableKey = GlobalKey();
  final GlobalKey _handZoneKey = GlobalKey();
  final GlobalKey _deckZoneKey = GlobalKey();

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

  /// True if [globalPoint] falls within the local player's own deck zone --
  /// used so a card dropped there goes back into the personal deck instead
  /// of onto the table.
  bool _isOverLocalDeckZone(Offset globalPoint) {
    final box = _deckZoneKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return false;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    return rect.contains(globalPoint);
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
  /// [center], if any -- keyed by that stack's root instanceId (needed to
  /// call [TableController.returnToDeck] when the target turns out to be a
  /// deck, not just any pile) -- used to decide whether a drop should stack
  /// or return-to-deck instead of just moving.
  MapEntry<String, CardInstance>? _findStackTarget({
    required Map<String, CardInstance> topsByRootId,
    required String excludingInstanceId,
    required Offset center,
  }) {
    MapEntry<String, CardInstance>? best;
    double bestDist = double.infinity;
    for (final entry in topsByRootId.entries) {
      if (entry.value.instanceId == excludingInstanceId) continue;
      // Candidates are stored as canonical fractions -- convert through the
      // same mirror-aware transform as rendering so distances are measured
      // in this screen's actual pixel space regardless of seat.
      final dist = (_toScreenPixel(entry.value.x, entry.value.y) - center).distance;
      if (dist < _stackHitRadius && dist < bestDist) {
        best = entry;
        bestDist = dist;
      }
    }
    return best;
  }

  void _handleDragEnd(
    Map<String, CardInstance> topsByRootId,
    String instanceId,
    Offset globalTopLeft,
    String? localDeckRootId,
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
    if (_isOverLocalDeckZone(globalCenter)) {
      widget.controller.returnToDeck(
        instanceId,
        localDeckRootId,
        toBottom: HardwareKeyboard.instance.isAltPressed,
      );
      return;
    }

    final local = _globalToTableLocal(globalTopLeft);
    final rawCenter = Offset(local.dx + cardWidth / 2, local.dy + cardHeight / 2);
    final target = _findStackTarget(topsByRootId: topsByRootId, excludingInstanceId: instanceId, center: rawCenter);
    if (target != null) {
      if (target.value.zone == CardZone.drawPile) {
        // Dropped onto an unowned deck pile on the free table (a
        // fixed-deck game's named deck, or Practice Mode's original shared
        // pile) -- return the card to it instead of just stacking, exactly
        // like dropping onto the local player's own personal deck zone
        // (top by default, bottom if Alt is held). TableActions.returnToDeck
        // takes the resulting ownerId from the deck's own current owner
        // (null here), not the acting player, so it stays shared.
        widget.controller.returnToDeck(
          instanceId,
          target.key,
          toBottom: HardwareKeyboard.instance.isAltPressed,
        );
      } else {
        widget.controller.stackCard(instanceId, target.value.instanceId);
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
  /// rather than broken apart.
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
            final localDeckCards = state.cards
                .where((c) => c.zone == CardZone.drawPile && c.ownerId == session.localPlayerId)
                .toList();
            final opponentDeckCount = state.cards
                .where((c) => c.zone == CardZone.drawPile && c.ownerId != null && c.ownerId != session.localPlayerId)
                .length;
            // Owned drawPile cards (personal decks) render via the fixed
            // DeckZoneWidget/OpponentDeckBadgeWidget below, not the free-form
            // table Stack; an unowned drawPile (Practice Mode's shared pile)
            // still renders there exactly as before.
            final tableCards = state.cards
                .where((c) => c.zone != CardZone.hand && !(c.zone == CardZone.drawPile && c.ownerId != null))
                .toList();
            final groups = _stackUtils.groupByStack(tableCards);
            // Keyed by each stack's root instanceId, not just a plain list --
            // _handleDragEnd needs the root id (not the possibly-different
            // top-of-zIndex card) to call TableController.returnToDeck when a
            // drop target turns out to be a deck.
            final topsByRootId = {for (final e in groups.entries) e.key: _stackUtils.topOf(e.value)};
            final localDeckGroups = _stackUtils.groupByStack(localDeckCards);
            final localDeckRootId = localDeckGroups.keys.isEmpty ? null : localDeckGroups.keys.first;
            final localDeckTop = localDeckCards.isEmpty ? null : _stackUtils.topOf(localDeckCards);

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
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: OpponentHandZoneWidget(
                                  count: opponentHandCount,
                                  cardBackImagePath: widget.cardBackImagePath,
                                ),
                              ),
                              if (widget.hasPersonalDecks)
                                ColoredBox(
                                  color: Colors.black.withValues(alpha: 0.15),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    child: OpponentDeckBadgeWidget(
                                      count: opponentDeckCount,
                                      cardBackImagePath: widget.cardBackImagePath,
                                    ),
                                  ),
                                ),
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
                                    for (final group in groups.entries)
                                      Builder(builder: (context) {
                                        final cards = group.value;
                                        final top = _stackUtils.topOf(cards);
                                        final pos = _toScreenPixel(top.x, top.y);
                                        // Set once at deal time by
                                        // GameSession.dealFixedDecks and never
                                        // touched again -- stays correct across
                                        // shuffles since a stack's root identity
                                        // (the map's key) never changes, only
                                        // its cards' zIndex does.
                                        final fixedDeckName = state.fixedDeckNames[group.key];
                                        if (cards.length > 1) {
                                          // PileWidget's own box is larger than a bare
                                          // card (room for its badge/shuffle button to
                                          // overflow) -- center on that actual size, or
                                          // the pile renders shifted off its true
                                          // canonical position (see pileWidgetExtra).
                                          Widget pile = PileWidget(
                                            count: cards.length,
                                            topInstanceId: top.instanceId,
                                            topFaceUp: top.faceUp,
                                            topDefinition: widget.definitionsById[top.definitionId],
                                            onDraw: () => widget.controller.drawCard(group.key),
                                            onDragEnd: (offset) => HardwareKeyboard.instance.isAltPressed
                                                ? _handlePileDragEnd(group.key, cards, offset)
                                                : _handleDragEnd(
                                                    topsByRootId,
                                                    top.instanceId,
                                                    offset,
                                                    localDeckRootId,
                                                    localHand,
                                                  ),
                                            onShuffle: () => widget.controller.shufflePile(group.key),
                                            // Same rotation rule as the bare-card
                                            // branch below -- a card faces whichever
                                            // player last held it, not whichever seat
                                            // is viewing it.
                                            isMirrored: top.ownerId != null && top.ownerId != session.localPlayerId,
                                            cardBackImagePath: widget.cardBackImagePath,
                                          );
                                          if (fixedDeckName != null) {
                                            pile = Tooltip(message: fixedDeckName, child: pile);
                                          }
                                          return Positioned(
                                            left: pos.dx - (cardWidth + pileWidgetExtra) / 2,
                                            top: pos.dy - (cardHeight + pileWidgetExtra) / 2,
                                            child: pile,
                                          );
                                        }
                                        Widget card = DraggableCard(
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
                                          onDragEnd: (offset) => _handleDragEnd(
                                            topsByRootId,
                                            top.instanceId,
                                            offset,
                                            localDeckRootId,
                                            localHand,
                                          ),
                                          onHover: (hovering) => _setHoveredId(hovering ? top.instanceId : null),
                                          cardBackImagePath: widget.cardBackImagePath,
                                        );
                                        if (fixedDeckName != null) {
                                          card = Tooltip(message: fixedDeckName, child: card);
                                        }
                                        return Positioned(
                                          left: pos.dx - cardWidth / 2,
                                          top: pos.dy - cardHeight / 2,
                                          child: card,
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
                                  onDragEnd: (id, offset) =>
                                      _handleDragEnd(topsByRootId, id, offset, localDeckRootId, localHand),
                                  onHoverCard: _setHoveredId,
                                  cardBackImagePath: widget.cardBackImagePath,
                                  cardKeyFor: _handCardKey,
                                ),
                              ),
                              if (widget.hasPersonalDecks)
                                ColoredBox(
                                  key: _deckZoneKey,
                                  color: Colors.black.withValues(alpha: 0.15),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                                    child: DeckZoneWidget(
                                      count: localDeckCards.length,
                                      topInstanceId: localDeckTop?.instanceId,
                                      onDragEnd: localDeckTop == null
                                          ? null
                                          : (offset) => _handleDragEnd(
                                                topsByRootId,
                                                localDeckTop.instanceId,
                                                offset,
                                                localDeckRootId,
                                                localHand,
                                              ),
                                      onShuffle: localDeckRootId == null
                                          ? null
                                          : () => widget.controller.shufflePile(localDeckRootId),
                                      cardBackImagePath: widget.cardBackImagePath,
                                    ),
                                  ),
                                ),
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
