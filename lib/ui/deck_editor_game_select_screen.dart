import 'package:flutter/material.dart';

import 'deck_editor_screen.dart';
import 'navigation.dart';
import 'widgets/game_picker.dart';

/// Entry point for the standalone Deck Editor: pick the bundled standard
/// deck or a custom game folder (same [GamePicker] used by the host flow's
/// `GameSelectScreen`), then proceed into [DeckEditorScreen] -- no
/// networking involved, unlike the host flow.
class DeckEditorGameSelectScreen extends StatelessWidget {
  const DeckEditorGameSelectScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: GamePicker(
          onGameChosen: (game) => pushScreen(
            context,
            title: 'Deck Editor',
            builder: (_) => DeckEditorScreen(game: game),
          ),
        ),
      ),
    );
  }
}
