import 'package:flutter/material.dart';

import '../../models/log_entry.dart';

/// The L-triggered in-game action log overlay -- matches `GameMenuOverlay`'s
/// exact visual shape (a translucent scrim plus a centered dark panel), but
/// wider/taller to fit a scrollable list. See
/// `TableScreen._handleKeyEvent` for how L toggles this and suppresses every
/// other keyboard shortcut while it's open.
class ActionLogOverlay extends StatefulWidget {
  const ActionLogOverlay({
    super.key,
    required this.entries,
    required this.onClose,
    required this.onSaveLog,
  });

  final List<LogEntry> entries;
  final VoidCallback onClose;

  /// Null (hidden Save Log button) when this player has no local game
  /// folder to export into -- see `TableScreen._saveLog`.
  final VoidCallback? onSaveLog;

  @override
  State<ActionLogOverlay> createState() => _ActionLogOverlayState();
}

class _ActionLogOverlayState extends State<ActionLogOverlay> {
  final ScrollController _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            onTap: widget.onClose,
            child: ColoredBox(color: Colors.black.withValues(alpha: 0.25)),
          ),
        ),
        Center(
          child: SizedBox(
            width: 480,
            height: 560,
            child: Material(
              color: const Color(0xFF262626),
              borderRadius: BorderRadius.circular(12),
              clipBehavior: Clip.antiAlias,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Game Log',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          tooltip: 'Close',
                          onPressed: widget.onClose,
                        ),
                      ],
                    ),
                  ),
                  const Divider(height: 1, color: Colors.white24),
                  Expanded(
                    child: widget.entries.isEmpty
                        ? const Center(
                            child: Text(
                              'No actions yet.',
                              style: TextStyle(color: Colors.white54),
                            ),
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                            itemCount: widget.entries.length,
                            itemBuilder: (context, i) {
                              final entry = widget.entries[i];
                              return Padding(
                                padding: const EdgeInsets.symmetric(vertical: 2),
                                child: Text.rich(
                                  TextSpan(
                                    children: [
                                      TextSpan(
                                        text: '[${formatElapsedTime(entry.elapsedMs)}] ',
                                        style: const TextStyle(
                                          color: Colors.white38,
                                          fontFeatures: [FontFeature.tabularFigures()],
                                        ),
                                      ),
                                      TextSpan(
                                        text: entry.message,
                                        style: const TextStyle(color: Colors.white),
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                  if (widget.onSaveLog != null) ...[
                    const Divider(height: 1, color: Colors.white24),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: OutlinedButton.icon(
                        icon: const Icon(Icons.save_alt),
                        label: const Text('Save Log'),
                        onPressed: widget.onSaveLog,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
