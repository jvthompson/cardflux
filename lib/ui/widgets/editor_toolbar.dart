import 'package:flutter/material.dart';

/// A slim, in-body toolbar row for a screen whose own actions (Open/Save/
/// New, etc. -- and, via [bottom], a `TabBar`) don't fit the global window
/// title bar (see `AppTitleBar`/main.dart), which only ever carries a plain
/// back button/title on the left and window controls on the right. Sits
/// directly under that global bar, styled with this app's normal
/// (light/dark-following) surface color, unlike the global bar's own fixed
/// dark one -- this is ordinary in-app chrome, not window chrome.
class EditorToolbar extends StatelessWidget {
  const EditorToolbar({super.key, required this.title, this.actions = const [], this.bottom});

  final String title;
  final List<Widget> actions;

  /// An optional row immediately below the title/actions row -- e.g. a
  /// `TabBar` (see `GameDefinitionEditorScreen`).
  final Widget? bottom;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surface,
      elevation: 1,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: kToolbarHeight,
            child: Row(
              children: [
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                ...actions,
                const SizedBox(width: 8),
              ],
            ),
          ),
          ?bottom,
        ],
      ),
    );
  }
}
