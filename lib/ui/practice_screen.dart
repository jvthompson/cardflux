import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../data/game_loader.dart';
import '../game/game_session.dart';
import '../game/table_controller.dart';
import '../models/card_definition.dart';
import 'table_screen.dart';

const String _localPlayerId = 'local';

/// Loads the standard deck and drops the player into a single-player
/// sandbox (M2) -- no networking involved. Builds the [GameSession] exactly
/// once (in [initState]) so an unrelated parent rebuild can't silently
/// discard in-progress game state.
class PracticeScreen extends StatefulWidget {
  const PracticeScreen({super.key});

  @override
  State<PracticeScreen> createState() => _PracticeScreenState();
}

class _PracticeScreenState extends State<PracticeScreen> {
  GameSession? _session;
  Map<String, CardDefinition> _definitionsById = {};

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    final game = await GameLoader().loadStandardDeck();
    if (!mounted) return;
    setState(() {
      _session = GameSession.localSandbox(game: game, localPlayerId: _localPlayerId);
      _definitionsById = {for (final c in game.cards) c.id: c};
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    if (session == null) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return ChangeNotifierProvider.value(
      value: session,
      child: TableScreen(
        definitionsById: _definitionsById,
        controller: HostTableController(session),
        isMirrored: false,
      ),
    );
  }
}
