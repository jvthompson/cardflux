import '../models/card_instance.dart';
import '../models/table_state.dart';

/// Builds the [TableState] snapshot the host sends to [recipientPlayerId]:
/// any card sitting in another player's private hand, or an owned zone not
/// in [visibleZoneIds] (a draw deck, a discard pile, or anything else a
/// game names one -- see `ZoneDefinition.visibleToAll`), has its real
/// identity replaced with a sentinel and is forced face-down, so the true
/// card never leaves the host for a recipient it doesn't belong to -- even a
/// modified client build can't recover it from the wire payload. A zone in
/// [visibleZoneIds] is still not interactable by anyone but its owner --
/// only what the recipient's client is allowed to *render* changes here;
/// `HostGameEngine` never accepts a client's action on a zone it doesn't own.
TableState filterForRecipient(TableState trueState, String recipientPlayerId, {required Set<String> visibleZoneIds}) {
  final filteredCards = trueState.cards.map((card) {
    final isPrivateZoneCard = card.zone == CardZone.zone && !visibleZoneIds.contains(card.zoneId);
    final isOpponentPrivateCard =
        card.ownerId != null && card.ownerId != recipientPlayerId && (card.zone == CardZone.hand || isPrivateZoneCard);
    if (!isOpponentPrivateCard) return card;
    return card.copyWith(faceUp: false, definitionId: hiddenDefinitionId);
  }).toList();
  return trueState.copyWith(cards: filteredCards);
}
