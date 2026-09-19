import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../data/game_definition_file_ops.dart' show imageFileTypes;
import '../data/player_avatar_file_ops.dart';
import '../data/player_profile_settings.dart';
import '../main.dart';
import '../models/color_palette.dart';
import 'deck_editor_game_select_screen.dart';
import 'game_definition_editor_entry_screen.dart';
import 'join_screen.dart';
import 'player_count_screen.dart';
import 'practice_player_count_screen.dart';
import 'widgets/avatar_widget.dart';
import 'widgets/color_swatch_row.dart';

/// Result of [_promptEditPlayerSettings] -- what the user chose to save, or
/// null if they cancelled. [avatarChanged] distinguishes "avatar untouched"
/// from "avatar explicitly changed" (picked a new one, or removed it, which
/// is [newAvatarSourcePath] == null while [avatarChanged] is true), since
/// the dialog itself performs no disk/prefs writes -- `HomeScreen` applies
/// this result after the fact so Cancel has nothing to undo.
typedef PlayerProfileEditResult = ({String name, int color, bool avatarChanged, String? newAvatarSourcePath});

/// Modal editor for the local player's name, color, and avatar image --
/// moved out of the Home screen's body into its own dialog so those fields
/// have real Cancel semantics (today's inline fields autosave on every
/// keystroke/tap with no way to back out). Follows the same
/// `showDialog`+`StatefulBuilder` shape as
/// `_promptForGameId` (game_definition_editor_entry_screen.dart) and
/// `TableScreen`'s `_promptSetColors`.
Future<PlayerProfileEditResult?> _promptEditPlayerSettings(
  BuildContext context, {
  required String initialName,
  required int initialColor,
  required String? initialAvatarPath,
}) async {
  final nameController = TextEditingController(text: initialName);
  final result = await showDialog<PlayerProfileEditResult>(
    context: context,
    builder: (context) {
      int color = initialColor;
      String? displayAvatarPath = initialAvatarPath;
      bool avatarChanged = false;
      String? newAvatarSourcePath;
      return StatefulBuilder(
        builder: (context, setState) {
          Future<void> pickImage() async {
            final file = await openFile(acceptedTypeGroups: imageFileTypes);
            if (file == null || !context.mounted) return;
            setState(() {
              displayAvatarPath = file.path;
              avatarChanged = true;
              newAvatarSourcePath = file.path;
            });
          }

          return AlertDialog(
            title: const Text('Edit Player Settings'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: pickImage,
                    child: AvatarWidget(color: color, imagePath: displayAvatarPath),
                  ),
                  if (displayAvatarPath != null)
                    TextButton.icon(
                      onPressed: () => setState(() {
                        displayAvatarPath = null;
                        avatarChanged = true;
                        newAvatarSourcePath = null;
                      }),
                      icon: const Icon(Icons.delete_outline),
                      label: const Text('Remove Image'),
                    ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: 'Your name', border: OutlineInputBorder()),
                  ),
                  const SizedBox(height: 16),
                  const Align(alignment: Alignment.centerLeft, child: Text('Your color')),
                  const SizedBox(height: 8),
                  ColorSwatchRow(selected: color, onSelected: (c) => setState(() => color = c)),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
              FilledButton(
                onPressed: () => Navigator.of(context).pop((
                  name: nameController.text.trim(),
                  color: color,
                  avatarChanged: avatarChanged,
                  newAvatarSourcePath: newAvatarSourcePath,
                )),
                child: const Text('Save'),
              ),
            ],
          );
        },
      );
    },
  );
  nameController.dispose();
  return result;
}

/// Entry screen: choose a display name, then host a game, join one by IP,
/// or practice offline in the single-player sandbox (M2). [message], when
/// set, is shown as a one-time banner -- used to explain why we're back here
/// (e.g. the opponent disconnected mid-game, see host_game_screen.dart /
/// client_game_screen.dart).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, this.message});

  final String? message;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WindowListener {
  final _nameController = TextEditingController(text: 'Player');
  int _playerColor = boardWidgetColorPalette.first;
  String? _avatarPath;
  final _profileSettings = PlayerProfileSettings();
  final _avatarFileOps = PlayerAvatarFileOps();
  String? _buildNumber;
  bool _isMaximized = true;

  @override
  void initState() {
    super.initState();
    _loadProfile();
    _loadBuildNumber();
    windowManager.addListener(this);
    windowManager.isMaximized().then((value) {
      if (mounted) setState(() => _isMaximized = value);
    });
  }

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  Future<void> _loadBuildNumber() async {
    final info = await PackageInfo.fromPlatform();
    if (!mounted) return;
    setState(() => _buildNumber = info.buildNumber);
  }

  Future<void> _loadProfile() async {
    final name = await _profileSettings.getName();
    final color = await _profileSettings.getColor();
    final avatarPath = await _profileSettings.getAvatarPath();
    if (!mounted) return;
    setState(() {
      if (name != null && name.isNotEmpty) _nameController.text = name;
      if (color != null) _playerColor = color;
      _avatarPath = avatarPath;
    });
  }

  /// Opens [_promptEditPlayerSettings] and, on a non-cancelled result,
  /// applies and persists it -- the dialog itself never touches disk/prefs
  /// (see [PlayerProfileEditResult]'s doc comment), so all the actual
  /// `PlayerProfileSettings`/`PlayerAvatarFileOps` writes happen here,
  /// matching how this screen already owns every profile write today.
  Future<void> _openEditPlayerSettingsDialog() async {
    final result = await _promptEditPlayerSettings(
      context,
      initialName: _playerName,
      initialColor: _playerColor,
      initialAvatarPath: _avatarPath,
    );
    if (result == null || !mounted) return;
    setState(() {
      _nameController.text = result.name;
      _playerColor = result.color;
    });
    _profileSettings.setName(result.name);
    _profileSettings.setColor(result.color);
    if (result.avatarChanged) {
      if (result.newAvatarSourcePath != null) {
        final saved = await _avatarFileOps.saveAvatar(result.newAvatarSourcePath!);
        if (!mounted) return;
        setState(() => _avatarPath = saved);
        _profileSettings.setAvatarPath(saved);
      } else {
        await _avatarFileOps.deleteAvatar();
        if (!mounted) return;
        setState(() => _avatarPath = null);
        _profileSettings.setAvatarPath(null);
      }
    }
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    _nameController.dispose();
    super.dispose();
  }

  String get _playerName {
    final trimmed = _nameController.text.trim();
    return trimmed.isEmpty ? 'Player' : trimmed;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cardflux'),
        // The window is frameless (see main.dart) with no native title bar,
        // so give the app bar itself drag-to-move (and double-tap-to-maximize)
        // behavior. It sits behind the title/actions in the AppBar's stack,
        // so it only catches drags on the bar's empty space.
        flexibleSpace: const DragToMoveArea(child: SizedBox.expand()),
        actions: [
          Consumer<ThemeModeController>(
            builder: (context, controller, _) => IconButton(
              icon: Icon(controller.isDarkMode ? Icons.light_mode : Icons.dark_mode),
              tooltip: controller.isDarkMode ? 'Switch to light mode' : 'Switch to dark mode',
              onPressed: () => controller.setDarkMode(!controller.isDarkMode),
            ),
          ),
          // The window is frameless with no native maximize/restore control.
          IconButton(
            icon: Icon(_isMaximized ? Icons.filter_none : Icons.crop_square),
            tooltip: _isMaximized ? 'Restore' : 'Maximize',
            onPressed: () =>
                _isMaximized ? windowManager.unmaximize() : windowManager.maximize(),
          ),
          // The app runs with no native window chrome, so there's otherwise
          // no way to quit it.
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close Cardflux',
            onPressed: () => windowManager.close(),
          ),
        ],
      ),
      body: Stack(
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 360),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.message != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.orange.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.orange),
                        ),
                        child: Text(widget.message!, style: const TextStyle(color: Colors.orange)),
                      ),
                      const SizedBox(height: 24),
                    ],
                    InkWell(
                      onTap: _openEditPlayerSettingsDialog,
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.all(8),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            AvatarWidget(color: _playerColor, imagePath: _avatarPath),
                            const SizedBox(height: 12),
                            Text(_playerName, style: Theme.of(context).textTheme.titleLarge),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    FilledButton(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PlayerCountScreen(
                          localPlayerName: _playerName,
                          localPlayerColor: _playerColor,
                          localAvatarPath: _avatarPath,
                        ),
                      )),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Host Game'),
                      ),
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => JoinScreen(
                          localPlayerName: _playerName,
                          localPlayerColor: _playerColor,
                          localAvatarPath: _avatarPath,
                        ),
                      )),
                      child: const Padding(
                        padding: EdgeInsets.symmetric(vertical: 12),
                        child: Text('Join Game'),
                      ),
                    ),
                    const SizedBox(height: 24),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => PracticePlayerCountScreen(
                          localPlayerName: _playerName,
                          localPlayerColor: _playerColor,
                          localAvatarPath: _avatarPath,
                        ),
                      )),
                      child: const Text('Practice Offline'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const DeckEditorGameSelectScreen(),
                      )),
                      child: const Text('Deck Editor'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const GameDefinitionEditorEntryScreen(),
                      )),
                      child: const Text('Game Definition Editor'),
                    ),
                  ],
                ),
              ),
            ),
          ),
          if (_buildNumber != null)
            Positioned(
              left: 8,
              bottom: 8,
              child: Text(
                'Build $_buildNumber',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).disabledColor,
                    ),
              ),
            ),
        ],
      ),
    );
  }
}
