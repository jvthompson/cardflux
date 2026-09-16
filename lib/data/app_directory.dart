import 'dart:io';

/// The folder the running executable lives in (e.g. `C:\Cardflux` for an
/// install at `C:\Cardflux\Cardflux.exe`) -- the base every Games/Deck
/// Library setting defaults to until the user explicitly chooses a folder of
/// their own (see `GamesDirectorySettings`/`DecksDirectorySettings`).
String get appDirectoryPath => File(Platform.resolvedExecutable).parent.path;
