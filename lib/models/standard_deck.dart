import 'card_definition.dart';

/// Prefix on every generated card's id so it can never collide with a card a
/// game author defines themselves (see [buildStandardDeckCards]).
const String standardDeckIdPrefix = '__standard52_';

const _redHex = '#D32F2F';
const _blackHex = '#212121';
const _suits = [
  ('hearts', 'Hearts', _redHex),
  ('diamonds', 'Diamonds', _redHex),
  ('clubs', 'Clubs', _blackHex),
  ('spades', 'Spades', _blackHex),
];
const _ranks = ['A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K'];

/// Generates one of each traditional playing card -- 4 suits x 13 ranks,
/// text-rendered (no art) with the same suit color/tag scheme as the bundled
/// `assets/games/standard_52/standard_52.json` -- for a
/// `ZoneDefinition.standardDeck` shared zone. Every id is prefixed with
/// [standardDeckIdPrefix] so these can be safely merged into any game's own
/// `cards` list without ever colliding with an author-defined card id.
List<CardDefinition> buildStandardDeckCards() {
  return [
    for (final (suitId, suitName, colorHex) in _suits)
      for (final rank in _ranks)
        CardDefinition(
          id: '$standardDeckIdPrefix${suitId}_$rank',
          cardTitle: rank,
          colorHex: colorHex,
          suit: suitId,
          rank: rank,
          types: [suitName],
          unownable: true,
        ),
  ];
}
