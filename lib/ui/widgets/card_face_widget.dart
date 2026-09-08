import 'dart:io';
import 'dart:math' show pi;

import 'package:flutter/material.dart';

import '../../models/card_definition.dart';

const double cardWidth = 70;
const double cardHeight = 100;

/// The gap between adjacent cards in a hand row when they all fit without
/// overlapping. Shared by [HandZoneWidget] and [OpponentHandZoneWidget].
const double handCardSpacing = 6;

const Map<String, String> _suitGlyphs = {
  'hearts': '♥',
  'diamonds': '♦',
  'clubs': '♣',
  'spades': '♠',
};

/// The corner/center glyph for [suit], or null for a custom game with no
/// suit concept (its cards fall back to just the rank label everywhere).
String? _suitGlyphFor(String? suit) => suit == null ? null : _suitGlyphs[suit.toLowerCase()];

/// Fallback color for a custom game that doesn't assign a [CardDefinition.colorHex]
/// (e.g. one with no natural single-color-per-card scheme).
const String _defaultColorHex = '#9E9E9E';

/// Parses a `#RRGGBB` string (the `colorHex`-style format used throughout
/// this app's JSON, e.g. [CardDefinition.colorHex]) into a [Color].
Color parseHexColor(String hex) {
  final cleaned = hex.replaceFirst('#', '');
  return Color(int.parse('FF$cleaned', radix: 16));
}

/// The `AnimatedRotation`/`Transform.rotate` turns contributed by
/// [CardOrientation] alone -- see its own doc for what `right`/`left` mean.
/// Shared by `DraggableCard`, `PileWidget`, and the Deck Editor's pool grid
/// so the mapping only lives in one place.
double orientationTurns(CardOrientation orientation) => switch (orientation) {
      CardOrientation.portrait => 0,
      CardOrientation.right => 0.25,
      CardOrientation.left => -0.25,
    };

/// The `RotatedBox.quarterTurns` equivalent of [orientationTurns] -- for
/// preview-style rendering (Deck Editor hover, Space-hold on the table) that
/// scales a rotated card to fill an available box via `FittedBox`.
/// `RotatedBox`, unlike `Transform.rotate`/`AnimatedRotation`, actually swaps
/// the child's effective width/height for a 90°/270° turn, so `FittedBox`
/// scales a landscape card to fill the space instead of shrinking it inside
/// a portrait-shaped box.
int orientationQuarterTurns(CardOrientation orientation) => switch (orientation) {
      CardOrientation.portrait => 0,
      CardOrientation.right => 1,
      CardOrientation.left => 3,
    };

/// The front face of a card. If [CardDefinition.imagePath] is set, renders
/// the real scanned/art image (falling back to the code-drawn face below if
/// the file can't be loaded); otherwise code-draws it from the definition's
/// label/suit/rank -- no image required. Suited cards (standard deck) get a
/// corner rank + suit glyph and a large center suit glyph, matching a real
/// playing card; suitless custom cards fall back to a plain rank label.
class CardFaceWidget extends StatelessWidget {
  const CardFaceWidget({super.key, required this.definition});

  final CardDefinition definition;

  Widget _corner(Color color, String? glyph) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          definition.cardTitle,
          style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 15, height: 1),
        ),
        if (glyph != null) Text(glyph, style: TextStyle(color: color, fontSize: 13, height: 1.1)),
      ],
    );
  }

  Widget _codeDrawnFace() {
    final color = parseHexColor(definition.colorHex ?? _defaultColorHex);
    final glyph = _suitGlyphFor(definition.suit);
    return Container(
      width: cardWidth,
      height: cardHeight,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: Colors.black26),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(1, 1))],
      ),
      padding: const EdgeInsets.all(4),
      child: Stack(
        children: [
          Positioned(top: 0, left: 0, child: _corner(color, glyph)),
          Center(
            child: Text(
              glyph ?? definition.cardTitle,
              style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: glyph != null ? 34 : 22),
            ),
          ),
          Positioned(
            bottom: 0,
            right: 0,
            child: Transform.rotate(angle: pi, child: _corner(color, glyph)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final imagePath = definition.imagePath;
    if (imagePath == null) return _codeDrawnFace();
    return Container(
      width: cardWidth,
      height: cardHeight,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(6),
        boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(1, 1))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border.all(color: Colors.black26)),
          child: Image.file(
            File(imagePath),
            fit: BoxFit.cover,
            errorBuilder: (context, error, stackTrace) => _codeDrawnFace(),
          ),
        ),
      ),
    );
  }
}
