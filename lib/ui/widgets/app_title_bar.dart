import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import '../../main.dart';
import '../navigation.dart';

/// Fixed background for [AppTitleBar] -- deliberately independent of
/// [ThemeModeController]'s light/dark toggle (this is window chrome, not
/// themed app content), mirroring how `TableScreen` pins itself to
/// `AppTheme.light` regardless of that same toggle.
const Color _titleBarColor = Color(0xFF1B2430);
const Color _titleBarForeground = Colors.white70;

/// The single title bar present at the very top of the window on every
/// screen (wired in via `MainApp`'s `MaterialApp.builder`, above the
/// Navigator's routed content -- see main.dart) -- replaces what used to be
/// a separate `AppBar` per screen. Left: a back button (only while
/// [ChromeController.showBackButton] is true) and the current screen's
/// title. Middle: empty draggable space (moves the window -- this app is
/// frameless, see main.dart). Right: dark-mode toggle, maximize/restore,
/// close.
class AppTitleBar extends StatelessWidget {
  const AppTitleBar({super.key, required this.isMaximized, required this.navigatorKey});

  final bool isMaximized;
  final GlobalKey<NavigatorState> navigatorKey;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _titleBarColor,
      child: SizedBox(
        height: kToolbarHeight,
        child: Consumer<ChromeController>(
          builder: (context, chrome, _) => Row(
            children: [
              if (chrome.showBackButton)
                IconButton(
                  icon: const Icon(Icons.arrow_back, color: _titleBarForeground),
                  tooltip: 'Back',
                  onPressed: chrome.onBack ?? () => navigatorKey.currentState?.pop(),
                ),
              Padding(
                padding: EdgeInsets.only(left: chrome.showBackButton ? 0 : 16),
                child: Text(
                  chrome.title,
                  style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w500),
                ),
              ),
              const Expanded(child: DragToMoveArea(child: SizedBox.expand())),
              Consumer<ThemeModeController>(
                builder: (context, controller, _) => IconButton(
                  icon: Icon(
                    controller.isDarkMode ? Icons.light_mode : Icons.dark_mode,
                    color: _titleBarForeground,
                  ),
                  tooltip: controller.isDarkMode ? 'Switch to light mode' : 'Switch to dark mode',
                  onPressed: () => controller.setDarkMode(!controller.isDarkMode),
                ),
              ),
              IconButton(
                icon: Icon(
                  isMaximized ? Icons.filter_none : Icons.crop_square,
                  color: _titleBarForeground,
                ),
                tooltip: isMaximized ? 'Restore' : 'Maximize',
                onPressed: () => isMaximized ? windowManager.unmaximize() : windowManager.maximize(),
              ),
              IconButton(
                icon: const Icon(Icons.close, color: _titleBarForeground),
                tooltip: 'Close Cardflux',
                onPressed: () => windowManager.close(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
