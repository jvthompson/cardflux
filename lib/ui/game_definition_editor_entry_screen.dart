import 'dart:convert';
import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/directory_picker.dart';
import '../data/game_definition_file_ops.dart';
import '../data/games_directory_settings.dart';
import '../models/game_definition.dart';
import 'game_definition_editor_screen.dart';
import 'widgets/move_library_prompt.dart';

const List<XTypeGroup> _gameDefFileTypes = [
  XTypeGroup(label: 'Game Definition', extensions: ['json']),
];

/// A folder path (containing, or about to contain, `gamedef.json`) plus the
/// [GameDefinition] to start editing there. Loaded WITHOUT resolving image
/// paths -- unlike `GameLoader`/`GamePicker`, which rewrite bare filenames
/// to absolute paths for rendering. The editor needs the original bare
/// filenames so saving writes them back out unchanged.
class NewOrOpenGameResult {
  const NewOrOpenGameResult({required this.folderPath, required this.game});

  final String folderPath;
  final GameDefinition game;
}

/// One game found while scanning the games-library folder for the
/// one-click open list below -- loaded the same unresolved-image-path way
/// as [NewOrOpenGameResult], via [_loadGameDefFile].
class LibraryGameEntry {
  const LibraryGameEntry({required this.folderPath, required this.game});

  final String folderPath;
  final GameDefinition game;
}

Future<NewOrOpenGameResult> _loadGameDefFile(String jsonPath, String folderPath) async {
  final raw = await File(jsonPath).readAsString();
  return NewOrOpenGameResult(
    folderPath: folderPath,
    game: GameDefinition.fromJson(jsonDecode(raw) as Map<String, dynamic>),
  );
}

/// Validates a user-typed game id as a filesystem folder name. Whether
/// `<root>/<id>` already exists is checked separately (async) by the caller.
String? _validateGameId(String id) {
  if (id.isEmpty) return 'Enter a game ID.';
  if (id == '.' || id == '..') return 'Invalid ID.';
  const reserved = r'/\:*?"<>|';
  if (id.split('').any(reserved.contains)) {
    return 'ID cannot contain: / \\ : * ? " < > |';
  }
  return null;
}

/// Returns the games-library root to create/open definitions under (see
/// [GamesDirectorySettings], the same folder `GamePicker` scans elsewhere) --
/// always resolvable, since an unset preference falls back to a default
/// folder alongside the app itself, so no prompt is ever needed here.
Future<String> _resolveLibraryRoot() => GamesDirectorySettings().getPath();

/// Modal id prompt for creating a new game folder under [libraryRoot].
/// Validates synchronously via [_validateGameId] on every submit attempt,
/// then asynchronously checks `<libraryRoot>/<id>` doesn't already exist.
Future<String?> _promptForGameId(BuildContext context, String libraryRoot) async {
  final controller = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) {
      String? error;
      bool checking = false;
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> submit() async {
            final id = controller.text.trim();
            final syncError = _validateGameId(id);
            if (syncError != null) {
              setState(() => error = syncError);
              return;
            }
            setState(() {
              checking = true;
              error = null;
            });
            final exists = await Directory('$libraryRoot${Platform.pathSeparator}$id').exists();
            if (exists) {
              setState(() {
                checking = false;
                error = 'A game with this ID already exists.';
              });
              return;
            }
            if (context.mounted) Navigator.of(context).pop(id);
          }

          return AlertDialog(
            title: const Text('New Game Definition'),
            content: TextField(
              controller: controller,
              autofocus: true,
              enabled: !checking,
              decoration: InputDecoration(labelText: 'Game ID', errorText: error),
              onSubmitted: (_) => submit(),
            ),
            actions: [
              TextButton(
                onPressed: checking ? null : () => Navigator.of(context).pop(),
                child: const Text('Cancel'),
              ),
              FilledButton(onPressed: checking ? null : submit, child: const Text('Create')),
            ],
          );
        },
      );
    },
  );
  controller.dispose();
  return result;
}

/// Scans [root] non-recursively for subfolders containing a `gamedef.json`,
/// loading each via [_loadGameDefFile] (never `GameLoader`/`GamePicker` --
/// those resolve bare image filenames to absolute paths, which this editor
/// must never receive, see [NewOrOpenGameResult]). Unparsable files are
/// skipped rather than failing the whole scan. Sorted by game name.
Future<List<LibraryGameEntry>> _scanGameLibrary(String root) async {
  final dir = Directory(root);
  if (!await dir.exists()) return const [];
  final entries = <LibraryGameEntry>[];
  await for (final entity in dir.list()) {
    if (entity is! Directory) continue;
    final gameDefPath = await GameDefinitionFileOps().findGameDefFile(entity.path);
    if (gameDefPath == null) continue;
    try {
      final result = await _loadGameDefFile(gameDefPath, entity.path);
      entries.add(LibraryGameEntry(folderPath: result.folderPath, game: result.game));
    } catch (_) {
      // Skip unparsable gamedef.json.
    }
  }
  entries.sort((a, b) => a.game.name.toLowerCase().compareTo(b.game.name.toLowerCase()));
  return entries;
}

/// Lets the user create a brand-new game definition: resolves (or prompts
/// for) the games-library folder, prompts for a game id via
/// [_promptForGameId], then writes a stub `gamedef.json` under
/// `<root>/<id>/`. Also called directly from [GameDefinitionEditorScreen]'s
/// own toolbar, so both entry points share this one creation flow.
Future<NewOrOpenGameResult?> pickNewGameDefinitionFolder(BuildContext context) async {
  final root = await _resolveLibraryRoot();
  if (!context.mounted) return null;

  final id = await _promptForGameId(context, root);
  if (id == null || !context.mounted) return null;

  final folderPath = '$root${Platform.pathSeparator}$id';
  final game = GameDefinition(id: id, name: id, cards: const []);
  await GameDefinitionFileOps().writeGameDefinition(folderPath: folderPath, game: game);
  return NewOrOpenGameResult(folderPath: folderPath, game: game);
}

/// Lets the user open an existing game definition JSON file directly.
/// `file_selector` can only filter by extension, not the exact filename
/// `gamedef.json` -- the same limitation `DeckEditorScreen._openDeck` has
/// for deck files -- so a bad/unrelated `.json` is caught by the try/catch
/// below instead.
Future<NewOrOpenGameResult?> pickExistingGameDefinitionFile(BuildContext context) async {
  final file = await openFile(acceptedTypeGroups: _gameDefFileTypes);
  if (file == null || !context.mounted) return null;
  try {
    return await _loadGameDefFile(file.path, File(file.path).parent.path);
  } catch (_) {
    if (!context.mounted) return null;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('That file is not a valid game definition.')),
    );
    return null;
  }
}

/// Entry point for the Game Definition Editor: one-click open any game
/// already in the games-library folder, create a brand-new game definition
/// by id, or fall back to opening a `gamedef.json` saved elsewhere -- then
/// proceed into [GameDefinitionEditorScreen].
class GameDefinitionEditorEntryScreen extends StatefulWidget {
  const GameDefinitionEditorEntryScreen({super.key});

  @override
  State<GameDefinitionEditorEntryScreen> createState() => _GameDefinitionEditorEntryScreenState();
}

class _GameDefinitionEditorEntryScreenState extends State<GameDefinitionEditorEntryScreen> {
  String? _libraryRoot;
  List<LibraryGameEntry>? _libraryGames;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final root = await GamesDirectorySettings().getPath();
    if (!mounted) return;
    setState(() => _libraryRoot = root);
    await _refreshLibrary();
  }

  Future<void> _refreshLibrary() async {
    final root = _libraryRoot;
    if (root == null) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    List<LibraryGameEntry> entries = const [];
    String? error;
    try {
      entries = await _scanGameLibrary(root);
      if (entries.isEmpty) error = 'No games found in this folder.';
    } catch (e) {
      error = 'Could not read that folder: $e';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _libraryGames = entries;
      _error = error;
    });
  }

  Future<void> _changeLibraryRoot() async {
    final chosen = await pickDirectoryPath();
    if (chosen == null || !mounted) return;
    final oldRoot = _libraryRoot;
    if (oldRoot != null) {
      await maybeMoveLibraryFolder(context, oldRoot: oldRoot, newRoot: chosen, whatLabel: 'game');
      if (!mounted) return;
    }
    await GamesDirectorySettings().setPath(chosen);
    if (!mounted) return;
    setState(() => _libraryRoot = chosen);
    await _refreshLibrary();
  }

  Future<void> _newGame(BuildContext context) async {
    final result = await pickNewGameDefinitionFolder(context);
    if (result == null || !context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GameDefinitionEditorScreen(folderPath: result.folderPath, initialGame: result.game),
    ));
    if (!mounted) return;
    final root = await GamesDirectorySettings().getPath();
    if (!mounted) return;
    setState(() => _libraryRoot = root);
    await _refreshLibrary();
  }

  Future<void> _openGame(BuildContext context) async {
    final result = await pickExistingGameDefinitionFile(context);
    if (result == null || !context.mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GameDefinitionEditorScreen(folderPath: result.folderPath, initialGame: result.game),
    ));
    await _refreshLibrary();
  }

  Future<void> _openLibraryEntry(BuildContext context, LibraryGameEntry entry) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => GameDefinitionEditorScreen(folderPath: entry.folderPath, initialGame: entry.game),
    ));
    await _refreshLibrary();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Game Definition Editor')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 480),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_libraryRoot == null)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            _libraryRoot!,
                            style: TextStyle(color: Theme.of(context).colorScheme.primary, fontSize: 12),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          tooltip: 'Refresh',
                          icon: const Icon(Icons.refresh),
                          onPressed: _busy ? null : _refreshLibrary,
                        ),
                        IconButton(
                          tooltip: 'Change Folder...',
                          icon: const Icon(Icons.folder_open),
                          onPressed: _busy ? null : _changeLibraryRoot,
                        ),
                      ],
                    ),
                  const SizedBox(height: 12),
                  if (_busy)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 16),
                      child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  else if (_error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant)),
                    )
                  else if (_libraryGames != null)
                    for (final entry in _libraryGames!)
                      Card(
                        child: ListTile(
                          title: Text(entry.game.name),
                          subtitle: Text('${entry.game.cards.length} card(s)'),
                          onTap: () => _openLibraryEntry(context, entry),
                        ),
                      ),
                  const SizedBox(height: 8),
                  FilledButton(
                    onPressed: () => _newGame(context),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('New Game Definition...'),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Divider(),
                  const SizedBox(height: 8),
                  OutlinedButton(
                    onPressed: () => _openGame(context),
                    child: const Padding(
                      padding: EdgeInsets.symmetric(vertical: 12),
                      child: Text('Open Existing...'),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
