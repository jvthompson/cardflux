import 'dart:io';

/// Joins a bare, as-authored image filename (as stored in
/// `CardDefinition.imagePath`/`GameDefinition.cardBackImagePath`) into an
/// absolute path alongside a game's `gamedef.json` -- a card belonging to a
/// set (see `GameSet`) has its art one folder deeper, inside a subfolder
/// named after [setId]. Shared by `GameLoader._resolveGameImagePaths` (real
/// loading, for rendering on the table) and the Game Definition Editor
/// (display-only resolution that never mutates the bare path actually
/// stored in the model) so the two can never drift apart.
String resolveBareImagePath({required String folderPath, required String bareImagePath, String? setId}) {
  final base = setId == null ? folderPath : '$folderPath${Platform.pathSeparator}$setId';
  return '$base${Platform.pathSeparator}$bareImagePath';
}

/// [resolveBareImagePath], or null if [bareImagePath] itself is null --
/// convenience for call sites juggling an optional image path.
String? resolvedImagePathForDisplay(String folderPath, {required String? bareImagePath, String? setId}) {
  if (bareImagePath == null) return null;
  return resolveBareImagePath(folderPath: folderPath, bareImagePath: bareImagePath, setId: setId);
}
