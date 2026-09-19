import 'package:flutter/material.dart';

import '../data/game_definition_file_ops.dart';
import '../models/card_back_definition.dart';
import '../models/card_definition.dart';
import '../models/game_definition.dart';
import '../models/game_set.dart';
import '../models/tag_group.dart';
import '../models/zone_definition.dart';
import 'game_definition_editor_entry_screen.dart';
import 'widgets/card_view_tab.dart';
import 'widgets/game_settings_tab.dart';
import 'widgets/sets_tab.dart';
import 'widgets/zones_tab.dart';

/// The main Game Definition Editor: a 4-tab editor (Game Settings / Zones /
/// Sets / Card View) over one working [GameDefinition], backed by
/// [folderPath] (the folder containing, or that will contain,
/// `gamedef.json`). [initialGame] must have been loaded WITHOUT resolving
/// image paths -- see `pickNewGameDefinitionFolder`/
/// `pickExistingGameDefinitionFile` for why this screen must never be fed a
/// `GameLoader`/`GamePicker`-resolved `GameDefinition`.
///
/// No dirty-tracking/unsaved-changes prompt in v1 -- matches
/// `DeckEditorScreen`, which has none either. `GameDefinition.id` is carried
/// through unedited, fixed to whatever the folder/loaded file gave it (see
/// the entry screen).
class GameDefinitionEditorScreen extends StatefulWidget {
  const GameDefinitionEditorScreen({super.key, required this.folderPath, required this.initialGame});

  final String folderPath;
  final GameDefinition initialGame;

  @override
  State<GameDefinitionEditorScreen> createState() => _GameDefinitionEditorScreenState();
}

class _GameDefinitionEditorScreenState extends State<GameDefinitionEditorScreen> {
  final GameDefinitionFileOps _fileOps = GameDefinitionFileOps();

  late String _folderPath = widget.folderPath;
  late String _id = widget.initialGame.id;
  late String _name = widget.initialGame.name;
  late List<CardBackDefinition> _cardBacks = widget.initialGame.cardBacks.toList();
  late List<TagGroup> _tagGroups = widget.initialGame.tagGroups.toList();
  late List<ZoneDefinition> _zones = widget.initialGame.zones.toList();
  late List<GameSet> _sets = widget.initialGame.sets.toList();
  late List<CardDefinition> _cards = widget.initialGame.cards.toList();
  bool _busy = false;

  GameDefinition get _currentGame => GameDefinition(
        id: _id,
        name: _name,
        cards: _cards,
        tagGroups: _tagGroups,
        sets: _sets,
        cardBacks: _cardBacks,
        zones: _zones,
      );

  Future<void> _save() async {
    setState(() => _busy = true);
    try {
      await _fileOps.writeGameDefinition(folderPath: _folderPath, game: _currentGame);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Saved to $_folderPath')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not save: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _newGameDefinition() async {
    final result = await pickNewGameDefinitionFolder(context);
    if (result == null || !mounted) return;
    _loadResult(result);
  }

  Future<void> _openGameDefinition() async {
    final result = await pickExistingGameDefinitionFile(context);
    if (result == null || !mounted) return;
    _loadResult(result);
  }

  void _loadResult(NewOrOpenGameResult result) {
    setState(() {
      _folderPath = result.folderPath;
      _id = result.game.id;
      _name = result.game.name;
      _cardBacks = result.game.cardBacks.toList();
      _tagGroups = result.game.tagGroups.toList();
      _zones = result.game.zones.toList();
      _sets = result.game.sets.toList();
      _cards = result.game.cards.toList();
    });
  }

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(_name.isEmpty ? 'Game Definition Editor' : _name),
          bottom: const TabBar(tabs: [
            Tab(text: 'Game Settings'),
            Tab(text: 'Zones'),
            Tab(text: 'Sets'),
            Tab(text: 'Card View'),
          ]),
          actions: [
            IconButton(
              icon: const Icon(Icons.note_add_outlined),
              tooltip: 'New Game Definition...',
              onPressed: _busy ? null : _newGameDefinition,
            ),
            IconButton(
              icon: const Icon(Icons.folder_open),
              tooltip: 'Open Existing...',
              onPressed: _busy ? null : _openGameDefinition,
            ),
            IconButton(icon: const Icon(Icons.save), tooltip: 'Save', onPressed: _busy ? null : _save),
          ],
        ),
        body: TabBarView(
          children: [
            GameSettingsTab(
              folderPath: _folderPath,
              name: _name,
              cardBacks: _cardBacks,
              tagGroups: _tagGroups,
              cards: _cards,
              sets: _sets,
              fileOps: _fileOps,
              onNameChanged: (v) => setState(() => _name = v),
              onCardBacksChanged: (v) => setState(() => _cardBacks = v),
              onTagGroupsChanged: (v) => setState(() => _tagGroups = v),
              onCardsChanged: (v) => setState(() => _cards = v),
            ),
            ZonesTab(
              zones: _zones,
              cards: _cards,
              onZonesChanged: (v) => setState(() => _zones = v),
            ),
            SetsTab(
              folderPath: _folderPath,
              sets: _sets,
              cards: _cards,
              tagGroups: _tagGroups,
              fileOps: _fileOps,
              onSetsChanged: (v) => setState(() => _sets = v),
              onCardsChanged: (v) => setState(() => _cards = v),
            ),
            CardViewTab(
              folderPath: _folderPath,
              cards: _cards,
              sets: _sets,
              tagGroups: _tagGroups,
              cardBacks: _cardBacks,
              fileOps: _fileOps,
              onCardsChanged: (v) => setState(() => _cards = v),
            ),
          ],
        ),
      ),
    );
  }
}
