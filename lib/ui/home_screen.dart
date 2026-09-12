import 'package:flutter/material.dart';

import '../data/player_profile_settings.dart';
import '../models/color_palette.dart';
import 'deck_editor_game_select_screen.dart';
import 'game_definition_editor_entry_screen.dart';
import 'join_screen.dart';
import 'player_count_screen.dart';
import 'practice_screen.dart';
import 'widgets/color_swatch_row.dart';

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

class _HomeScreenState extends State<HomeScreen> {
  final _nameController = TextEditingController(text: 'Player');
  int _playerColor = boardWidgetColorPalette.first;
  final _profileSettings = PlayerProfileSettings();

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  Future<void> _loadProfile() async {
    final name = await _profileSettings.getName();
    final color = await _profileSettings.getColor();
    if (!mounted) return;
    setState(() {
      if (name != null && name.isNotEmpty) _nameController.text = name;
      if (color != null) _playerColor = color;
    });
  }

  @override
  void dispose() {
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
      appBar: AppBar(title: const Text('Card Table')),
      body: Center(
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
                TextField(
                  controller: _nameController,
                  decoration: const InputDecoration(labelText: 'Your name', border: OutlineInputBorder()),
                  onChanged: (value) => _profileSettings.setName(value.trim()),
                ),
                const SizedBox(height: 16),
                const Align(alignment: Alignment.centerLeft, child: Text('Your color')),
                const SizedBox(height: 8),
                ColorSwatchRow(
                  selected: _playerColor,
                  onSelected: (c) {
                    setState(() => _playerColor = c);
                    _profileSettings.setColor(c);
                  },
                ),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => PlayerCountScreen(localPlayerName: _playerName, localPlayerColor: _playerColor),
                  )),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Host Game'),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => JoinScreen(localPlayerName: _playerName, localPlayerColor: _playerColor),
                  )),
                  child: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 12),
                    child: Text('Join Game'),
                  ),
                ),
                const SizedBox(height: 24),
                TextButton(
                  onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => const PracticeScreen(),
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
    );
  }
}
