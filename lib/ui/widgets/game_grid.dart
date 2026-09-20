import 'dart:io';

import 'package:flutter/material.dart';

import '../../data/image_path_resolver.dart';

/// One tile's worth of display data for [GameGridView] -- deliberately
/// decoupled from `GameDefinition`/`LibraryGameEntry` so the same grid UI
/// serves both `GamePicker` (picking a `GameDefinition` to play) and
/// `GameDefinitionEditorEntryScreen` (picking a game folder to edit), whose
/// underlying models differ.
class GameGridEntry {
  const GameGridEntry({
    required this.name,
    required this.cardCount,
    required this.folderPath,
    required this.onTap,
  });

  final String name;
  final int cardCount;

  /// This game's on-disk folder (containing `gamedef.json`), used to look up
  /// its `gamelogo` art -- null for the bundled Standard 52 deck, which has
  /// no real folder and always falls back to [GameGridView._fallbackLogo].
  final String? folderPath;

  final VoidCallback onTap;
}

/// Renders [entries] as a grid of card-shaped tiles, each showing that
/// game's `gamelogo` artwork (see [resolveGameLogoImagePath]) with its name
/// and card count below -- tiles are always exactly [_tileWidth] wide (never
/// scaled), up to [_maxColumns] across, scrolling vertically when it
/// overflows its bounds. Shared by `GamePicker` and
/// `GameDefinitionEditorEntryScreen` so both game-selection surfaces look
/// and behave identically.
class GameGridView extends StatelessWidget {
  const GameGridView({super.key, required this.entries});

  final List<GameGridEntry> entries;

  static const double _tileWidth = 400;
  static const int _maxColumns = 5;
  static const double _tileSpacing = 16;
  // Extra height (beyond the square logo area) for a tile's padding, the
  // up-to-2-line name, and the card-count line below it -- tuned to fit
  // without overflow at the default text scale.
  static const double _tileTextBlockHeight = 96;

  Widget _fallbackLogo(BuildContext context) {
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(Icons.style, size: 48, color: Theme.of(context).colorScheme.onSurfaceVariant),
    );
  }

  Widget _buildTile(BuildContext context, GameGridEntry entry) {
    final logoPath = resolveGameLogoImagePath(entry.folderPath);
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: entry.onTap,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
          boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 3, offset: Offset(1, 1))],
        ),
        child: Column(
          children: [
            Expanded(
              child: AspectRatio(
                aspectRatio: 1,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: logoPath == null
                      ? _fallbackLogo(context)
                      : Image.file(
                          File(logoPath),
                          fit: BoxFit.contain,
                          errorBuilder: (context, error, stackTrace) => _fallbackLogo(context),
                        ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              entry.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 2),
            Text(
              '${entry.cardCount} card(s)',
              style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = ((constraints.maxWidth + _tileSpacing) / (_tileWidth + _tileSpacing))
            .floor()
            .clamp(1, _maxColumns);
        final gridWidth = columns * _tileWidth + (columns - 1) * _tileSpacing;
        return Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            width: gridWidth,
            child: GridView.builder(
              padding: const EdgeInsets.symmetric(vertical: 4),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                crossAxisSpacing: _tileSpacing,
                mainAxisSpacing: _tileSpacing,
                mainAxisExtent: _tileWidth + _tileTextBlockHeight,
              ),
              itemCount: entries.length,
              itemBuilder: (context, index) => _buildTile(context, entries[index]),
            ),
          ),
        );
      },
    );
  }
}
