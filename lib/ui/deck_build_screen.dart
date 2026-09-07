import 'package:flutter/material.dart';

import '../models/card_definition.dart';
import '../models/deck_config.dart';
import '../models/game_definition.dart';
import '../networking/host_server.dart';
import 'host_game_screen.dart';

/// Host-only screen (M5): choose how many copies of each [game] card to
/// bring into the session, defaulting to one of everything (the full deck).
/// Confirming builds a [DeckConfig] and starts the real networked match.
class DeckBuildScreen extends StatefulWidget {
  const DeckBuildScreen({
    super.key,
    required this.hostServer,
    required this.hostPlayerId,
    required this.game,
  });

  final HostServer hostServer;
  final String hostPlayerId;
  final GameDefinition game;

  @override
  State<DeckBuildScreen> createState() => _DeckBuildScreenState();
}

class _DeckBuildScreenState extends State<DeckBuildScreen> {
  late final Map<String, int> _quantities = {for (final c in widget.game.cards) c.id: 1};

  int get _totalCards => _quantities.values.fold(0, (a, b) => a + b);

  void _setQuantity(String id, int quantity) {
    setState(() => _quantities[id] = quantity.clamp(0, 99));
  }

  void _selectAll() => setState(() {
        for (final c in widget.game.cards) {
          _quantities[c.id] = 1;
        }
      });

  void _clearAll() => setState(() {
        for (final c in widget.game.cards) {
          _quantities[c.id] = 0;
        }
      });

  void _startGame() {
    final deckConfig = DeckConfig(
      gameId: widget.game.id,
      entries: [
        for (final entry in _quantities.entries)
          if (entry.value > 0) DeckEntry(definitionId: entry.key, quantity: entry.value),
      ],
    );
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => HostGameScreen(
        hostServer: widget.hostServer,
        hostPlayerId: widget.hostPlayerId,
        game: widget.game,
        deckConfig: deckConfig,
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Build Deck -- ${widget.game.name}')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                TextButton(onPressed: _selectAll, child: const Text('Full Deck')),
                TextButton(onPressed: _clearAll, child: const Text('Clear All')),
                const Spacer(),
                Text('$_totalCards card(s) selected'),
              ],
            ),
          ),
          const Divider(height: 1),
          Expanded(
            child: ListView.builder(
              itemCount: widget.game.cards.length,
              itemBuilder: (context, index) {
                final card = widget.game.cards[index];
                return _DeckEntryRow(
                  card: card,
                  quantity: _quantities[card.id] ?? 0,
                  onChanged: (q) => _setQuantity(card.id, q),
                );
              },
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(16),
            child: FilledButton(
              onPressed: _totalCards > 0 ? _startGame : null,
              child: const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Text('Start Game'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _DeckEntryRow extends StatelessWidget {
  const _DeckEntryRow({required this.card, required this.quantity, required this.onChanged});

  final CardDefinition card;
  final int quantity;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final color = Color(int.parse((card.colorHex ?? '#9E9E9E').replaceFirst('#', '0xFF')));
    return ListTile(
      leading: CircleAvatar(backgroundColor: color, child: Text(card.cardTitle, style: const TextStyle(color: Colors.white, fontSize: 12))),
      title: Text(card.cardTitle),
      subtitle: card.suit != null ? Text(card.suit!) : null,
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.remove_circle_outline),
            onPressed: quantity > 0 ? () => onChanged(quantity - 1) : null,
          ),
          SizedBox(width: 24, child: Text('$quantity', textAlign: TextAlign.center)),
          IconButton(
            icon: const Icon(Icons.add_circle_outline),
            onPressed: () => onChanged(quantity + 1),
          ),
        ],
      ),
    );
  }
}
