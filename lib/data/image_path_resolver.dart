import 'dart:io';

import '../models/game_definition.dart';

/// Joins a bare, as-authored image filename (as stored in
/// `CardDefinition.imagePath`/`GameDefinition.cardBackImagePath`) into an
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

/// Keeps [remote]'s card/zone/rule data (the session's source of truth --
/// matters if the host is running a customized/homebrew variant) but
/// substitutes each card's `imagePath`, and `cardBackImagePath`, with
/// [local]'s own values, matched by `CardDefinition.id`. A card present in
/// [remote] but missing from [local] gets `imagePath` cleared to null, which
/// `CardFaceWidget`/`CardBackWidget` already render as a code-drawn
/// placeholder rather than a broken image -- used so a client can render a
/// host-sent [GameDefinition] using this machine's own locally-resolved
/// image paths instead of the host's, which only work here by coincidence
/// (see `GameLoader._resolveGameImagePaths`).
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
    cardBackImagePath: local.cardBackImagePath,
    zones: remote.zones,
    tagGroups: remote.tagGroups,
    sets: remote.sets,
    folderPath: local.folderPath,
  );
}
