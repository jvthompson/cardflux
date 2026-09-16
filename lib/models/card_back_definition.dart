import 'card_definition.dart' show CardOrientation;

/// Sentinel [CardDefinition.cardBackId] value selecting the "Unique" mode --
/// looked up as `<cardImageBaseName>$cardBackFileSuffix.<ext>` next to the
/// card's own art (see `resolveCardBackImagePath`) rather than referring to
/// an entry in [GameDefinition.cardBacks]. Never a real
/// [CardBackDefinition.id] (those are `Uuid.v4()`-generated), so no
/// collision is possible.
const String uniqueCardBackId = '__unique__';

/// The filename suffix (before the extension) marking an image as a card's
/// unique back art rather than a front -- e.g. `001_Krennic_BACK.png` is the
/// back for `001_Krennic.png`. Used both by `resolveCardBackImagePath`'s
/// "Unique" lookup and by `GameDefinitionFileOps.buildCardsFromImageFolder`,
/// which skips any image ending in this suffix when bulk-importing a set's
/// cards, so a card's own back art never gets turned into a phantom extra
/// card.
const String cardBackFileSuffix = '_BACK';

/// Sentinel default for [CardBackDefinition.copyWith]'s nullable [imagePath]
/// parameter, so "omitted" (keep current value) is distinguishable from an
/// explicitly passed `null` (clear the field) -- same trick as
/// `CardDefinition`'s own `_unset`.
const Object _unset = Object();

/// One named card-back art option a game declares, managed on the Game
/// Definition Editor's Game Settings tab. [GameDefinition.cardBacks]' first
/// entry is that game's default -- used by any card whose
/// [CardDefinition.cardBackId] is null -- the rest are alternates a card can
/// opt into by [id]. [id] is a stable identity independent of the
/// user-editable [name], the same pattern as `GameSet`/`TagGroup`, since a
/// card's `cardBackId` reference and this list's own reorderable-list keys
/// both need to survive a rename.
class CardBackDefinition {
  const CardBackDefinition({
    required this.id,
    required this.name,
    this.imagePath,
    this.orientation = CardOrientation.portrait,
  });

  final String id;
  final String name;

  /// Bare filename alongside the game's `gamedef.json` before a game is
  /// loaded for play, resolved to an absolute path afterward -- same
  /// treatment as `CardDefinition.imagePath`.
  final String? imagePath;

  /// This back's own table rotation -- see `CardDefinition.orientation`'s
  /// identical doc. Independent of any card's own front orientation, since
  /// this art is shared by every card that picks this back.
  final CardOrientation orientation;

  factory CardBackDefinition.fromJson(Map<String, dynamic> json) => CardBackDefinition(
        id: json['id'] as String,
        name: json['name'] as String,
        imagePath: json['imagePath'] as String?,
        orientation: CardOrientation.values.byName(json['orientation'] as String? ?? 'portrait'),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (imagePath != null) 'imagePath': imagePath,
        if (orientation != CardOrientation.portrait) 'orientation': orientation.name,
      };

  CardBackDefinition copyWith({String? name, Object? imagePath = _unset, CardOrientation? orientation}) {
    return CardBackDefinition(
      id: id,
      name: name ?? this.name,
      imagePath: identical(imagePath, _unset) ? this.imagePath : imagePath as String?,
      orientation: orientation ?? this.orientation,
    );
  }
}
