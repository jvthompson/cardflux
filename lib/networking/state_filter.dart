import '../models/card_instance.dart';
import '../models/table_state.dart';

/// Builds the [TableState] snapshot the host sends to [recipientPlayerId]:
/// any card sitting in another player's private hand or personal deck has
/// its real identity replaced with a sentinel and is forced face-down, so
/// the true card never leaves the host for a recipient it doesn't belong to
/// -- even a modified client build can't recover it from the wire payload.
TableState filterForRecipient(TableState trueState, String recipientPlayerId) {
  final filteredCards = trueState.cards.map((card) {
    final isOpponentPrivateCard = card.ownerId != null &&
        card.ownerId != recipientPlayerId &&
        (card.zone == CardZone.hand || card.zone == CardZone.drawPile);
    if (!isOpponentPrivateCard) return card;
    return card.copyWith(faceUp: false, definitionId: hiddenDefinitionId);
  }).toList();
  return trueState.copyWith(cards: filteredCards);
}
