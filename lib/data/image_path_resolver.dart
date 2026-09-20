import 'dart:io';

import '../models/card_back_definition.dart';
import '../models/card_definition.dart';
import '../models/game_definition.dart';

/// Joins a bare, as-authored image filename (as stored in
/// `CardDefinition.imagePath`/each `CardBackDefinition.imagePath`) into an
/// absolute path alongside a game's `gamedef.json` -- a card belonging to a
/// set (see `GameSet`) has its art one folder deeper, inside a subfolder
/// named after [setId]. Shared by `GameLoader._resolveGameImagePaths` (real
/// loading, for rendering on the table) and the Game Definition Editor
/// (display-only resolution that never mutates the bare path actually
/// stored in the model) so the two can never drift apart.
String resolveBareImagePath({
  required String folderPath,
  required String bareImagePath,
  String? setId,
}) {
  final base = setId == null
      ? folderPath
      : '$folderPath${Platform.pathSeparator}$setId';
  return '$base${Platform.pathSeparator}$bareImagePath';
}

/// [resolveBareImagePath], or null if [bareImagePath] itself is null --
/// convenience for call sites juggling an optional image path.
String? resolvedImagePathForDisplay(
  String folderPath, {
  required String? bareImagePath,
  String? setId,
}) {
  if (bareImagePath == null) return null;
  return resolveBareImagePath(
    folderPath: folderPath,
    bareImagePath: bareImagePath,
    setId: setId,
  );
}

/// [imagePath] (already resolved to an absolute path) with [cardBackFileSuffix]
/// inserted before its extension -- e.g. `.../001_Krennic.png` ->
/// `.../001_Krennic_BACK.png`. Used only by [resolveCardBackImagePath]'s
/// "Unique" lookup.
String _uniqueCardBackPathFor(String imagePath) {
  final lastDot = imagePath.lastIndexOf('.');
  if (lastDot <= 0) return '$imagePath$cardBackFileSuffix';
  return '${imagePath.substring(0, lastDot)}$cardBackFileSuffix${imagePath.substring(lastDot)}';
}

/// The card-back image to render for [card] (its own `cardBackId` choice,
/// resolved against [cardBacks] -- see `GameDefinition.cardBacks`), whether
/// it's specifically "Unique" mode with no matching art on disk, and which
/// way that back should be rotated on the table.
///
/// `card?.cardBackId == uniqueCardBackId` derives the expected filename from
/// [card]'s own (already-resolved, absolute) `imagePath` via
/// [_uniqueCardBackPathFor] and checks it actually exists -- found returns
/// that path with `missing: false`; not found (or [card] has no image of its
/// own to derive from) returns `missing: true`, the caller's cue to show an
/// error placeholder instead of a code-drawn back. Either way, `orientation`
/// is [card]'s own `uniqueBackOrientation` -- even a missing-art placeholder
/// still needs to sit at the card's correct physical rotation.
///
/// Otherwise, looks up `card?.cardBackId` in [cardBacks] -- `null` or an id
/// no longer present there both fall back to `cardBacks.first` (the default;
/// null if [cardBacks] is empty). `missing` is always false on this path: a
/// resolved entry with no `imagePath` of its own is a normal "use the
/// code-drawn look" state, not an error. `orientation` is the resolved
/// `CardBackDefinition.orientation` (portrait if [cardBacks] is empty) --
/// that art is shared by every card using this back, so it isn't per-card.
({String? path, bool missing, CardOrientation orientation}) resolveCardBackImagePath({
  required List<CardBackDefinition> cardBacks,
  required CardDefinition? card,
}) {
  final cardBackId = card?.cardBackId;
  if (cardBackId == uniqueCardBackId) {
    final orientation = card?.uniqueBackOrientation ?? CardOrientation.portrait;
    final imagePath = card?.imagePath;
    if (imagePath == null) return (path: null, missing: true, orientation: orientation);
    final candidate = _uniqueCardBackPathFor(imagePath);
    return File(candidate).existsSync()
        ? (path: candidate, missing: false, orientation: orientation)
        : (path: null, missing: true, orientation: orientation);
  }
  CardBackDefinition? selected;
  if (cardBackId != null) {
    for (final back in cardBacks) {
      if (back.id == cardBackId) {
        selected = back;
        break;
      }
    }
  }
  selected ??= cardBacks.isEmpty ? null : cardBacks.first;
  return (path: selected?.imagePath, missing: false, orientation: selected?.orientation ?? CardOrientation.portrait);
}

/// Bare filename every game's optional Pack Generator table-widget image is
/// expected to be named, if present -- sits alongside `gamedef.json`, never
/// per-set (see [resolveCardBackImagePath]'s identical existence-check
/// pattern for another optional per-game asset).
const String packGeneratorImageFileName = 'packgen.png';

/// Absolute path to [folderPath]'s `packgen.png`, or null if that file
/// doesn't exist -- the "does this optional per-game asset exist" check
/// `PackGeneratorWidget` needs before deciding whether to render the image
/// or fall back to text. Null [folderPath] (e.g. the bundled standard-52
/// game, which has no real on-disk folder) always returns null.
String? resolvePackGeneratorImagePath(String? folderPath) {
  if (folderPath == null) return null;
  final candidate = '$folderPath${Platform.pathSeparator}$packGeneratorImageFileName';
  return File(candidate).existsSync() ? candidate : null;
}

/// Filename stem (no extension) every game's optional grid-tile logo is
/// expected to use, sitting alongside `gamedef.json` -- checked against each
/// of [_gameLogoExtensions] in turn since the author may save it as any
/// typical image format (same "optional per-game asset" pattern as
/// [packGeneratorImageFileName]).
const String gameLogoFileNameStem = 'gamelogo';

const List<String> _gameLogoExtensions = ['png', 'jpg', 'jpeg', 'webp', 'gif', 'bmp'];

/// Absolute path to [folderPath]'s `gamelogo.<ext>` (first matching
/// extension in [_gameLogoExtensions] wins), or null if none exists -- same
/// "does this optional per-game asset exist" pattern as
/// [resolvePackGeneratorImagePath]. Null [folderPath] (the bundled
/// standard-52 game, which has no real on-disk folder) always returns null.
String? resolveGameLogoImagePath(String? folderPath) {
  if (folderPath == null) return null;
  for (final ext in _gameLogoExtensions) {
    final candidate = '$folderPath${Platform.pathSeparator}$gameLogoFileNameStem.$ext';
    if (File(candidate).existsSync()) return candidate;
  }
  return null;
}

/// Keeps [remote]'s card/zone/rule data (the session's source of truth --
/// matters if the host is running a customized/homebrew variant) but
/// substitutes each card's `imagePath`, and every declared card back's own
/// `imagePath`, with [local]'s own values, matched by `CardDefinition.id`/
/// `CardBackDefinition.id` respectively. A card present in [remote] but
/// missing from [local] gets `imagePath` cleared to null, which
/// `CardFaceWidget`/`CardBackWidget` already render as a code-drawn
/// placeholder rather than a broken image -- used so a client can render a
/// host-sent [GameDefinition] using this machine's own locally-resolved
/// image paths instead of the host's, which only work here by coincidence
/// (see `GameLoader._resolveGameImagePaths`). Each `CardDefinition.cardBackId`
/// is left untouched -- it's authored content (like `setId`/`types`), not a
/// locally-resolved path, so it always comes from [remote].
GameDefinition mergeLocalImagePaths({
  required GameDefinition remote,
  required GameDefinition local,
}) {
  final localImageById = {for (final c in local.cards) c.id: c.imagePath};
  return GameDefinition(
    id: remote.id,
    name: remote.name,
    cards: [
      for (final c in remote.cards) c.copyWith(imagePath: localImageById[c.id]),
    ],
    cardBacks: local.cardBacks,
    zones: remote.zones,
    tagGroups: remote.tagGroups,
    sets: remote.sets,
    folderPath: local.folderPath,
  );
}
