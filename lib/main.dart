import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app_theme.dart';
import 'data/theme_mode_settings.dart';
import 'services/discord/discord_presence_service.dart';
import 'services/discord/discord_social_service.dart';
import 'ui/discord_join_prompt_dialog.dart';
import 'ui/home_screen.dart';
import 'ui/navigation.dart';
import 'ui/widgets/app_title_bar.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(DiscordPresenceService.instance.initialize());
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(null, () async {
    // setAsFrameless() changes the window's style flags, which can make
    // Windows drop a maximized state back to its restored bounds (the
    // native runner's fixed 1280x720 creation size, windows/runner/main.cpp)
    // -- so it must run BEFORE maximize(), leaving maximize() as the last
    // window-affecting call before show().
    await windowManager.setAsFrameless();
    await windowManager.maximize();
    await windowManager.show();
  });
  runApp(const MainApp());
}

/// Drives the app-wide light/dark [ThemeMode], persisted via
/// [ThemeModeSettings] -- read once at startup, then live-updated whenever
/// the home screen's toggle flips it (see [HomeScreen]'s AppBar action).
/// [TableScreen] pins itself to [AppTheme.light] regardless of this, so
/// gameplay is never affected.
class ThemeModeController extends ChangeNotifier {
  ThemeModeController() {
    _settings.getDarkMode().then((value) {
      _isDarkMode = value;
      notifyListeners();
    });
  }

  final _settings = ThemeModeSettings();
  bool _isDarkMode = false;

  bool get isDarkMode => _isDarkMode;

  void setDarkMode(bool enabled) {
    _isDarkMode = enabled;
    notifyListeners();
    _settings.setDarkMode(enabled);
  }
}

class MainApp extends StatefulWidget {
  const MainApp({super.key});

  @override
  State<MainApp> createState() => _MainAppState();
}

class _MainAppState extends State<MainApp> with WindowListener {
  StreamSubscription<String>? _joinSecretSub;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    windowManager.addListener(this);
    // Fires whenever a friend accepts a Discord game invite (or clicks
    // Join on the host's Rich Presence) -- can happen at any time,
    // including right at cold start, so this listener lives here rather
    // than in any particular screen.
    _joinSecretSub = DiscordSocialService.instance.joinSecretReceived.listen((secret) {
      final context = navigatorKey.currentContext;
      if (context == null) return;
      // navigatorKey.currentContext is fetched fresh above, not carried
      // across an awaited gap -- the standard safe pattern for reaching a
      // BuildContext from outside the widget tree (see navigatorKey's doc).
      // ignore: use_build_context_synchronously
      showDiscordJoinPrompt(context, secret);
    });
  }

  @override
  void dispose() {
    _joinSecretSub?.cancel();
    // Best-effort only: normal window close goes through
    // windowManager.close() (app_title_bar.dart), which doesn't route
    // through this widget's dispose. Discord clears presence on its own
    // once the process disconnects, so this isn't required for correctness.
    DiscordPresenceService.instance.dispose();
    windowManager.removeListener(this);
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _isChromeHidden = true;
  bool _isTogglingChrome = false;

  /// Lets [AppTitleBar] (built inside [MaterialApp]'s `builder`, whose
  /// `context` is an ANCESTOR of the Navigator since `child` there already
  /// *is* the built Navigator) call `.pop()` without a descendant context
  /// to find it through `Navigator.of(context)`.
  final navigatorKey = GlobalKey<NavigatorState>();

  /// What [AppTitleBar] renders -- provided app-wide (alongside
  /// [ThemeModeController]) and kept in sync with the current route by
  /// [_chromeObserver]. Not recreated per [build] so the observer registered
  /// on [MaterialApp] stays the same instance across rebuilds.
  final _chromeController = ChromeController();
  late final _chromeObserver = ChromeRouteObserver(_chromeController);

  // main() maximizes the window before the first frame, so this starts in
  // sync with that; onWindowMaximize/onWindowUnmaximize below keep it in
  // sync after that, including when HomeScreen's maximize button changes it.
  bool _isMaximized = true;

  @override
  void onWindowMaximize() => setState(() => _isMaximized = true);

  @override
  void onWindowUnmaximize() => setState(() => _isMaximized = false);

  bool _handleKeyEvent(KeyEvent event) {
    if (event.logicalKey == LogicalKeyboardKey.f11 && event is KeyDownEvent) {
      _toggleChrome();
      return true;
    }
    return false;
  }

  // Toggles window chrome (title bar/borders) rather than true OS
  // fullscreen: window_manager's fullscreen implementation resizes the
  // window, which can deadlock the Windows engine's platform thread on
  // exit. Staying maximized and only toggling the frameless state never
  // resizes the window, avoiding that hang.
  Future<void> _toggleChrome() async {
    if (_isTogglingChrome) return;
    _isTogglingChrome = true;
    try {
      if (_isChromeHidden) {
        await windowManager.setTitleBarStyle(TitleBarStyle.normal);
      } else {
        await windowManager.setAsFrameless();
      }
      _isChromeHidden = !_isChromeHidden;
    } finally {
      _isTogglingChrome = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeModeController()),
        ChangeNotifierProvider.value(value: _chromeController),
      ],
      child: Consumer<ThemeModeController>(
        builder: (context, controller, _) => MaterialApp(
          navigatorKey: navigatorKey,
          navigatorObservers: [_chromeObserver],
          title: 'Cardflux',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: controller.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: const HomeScreen(),
          // The window is frameless (see main()), so the OS gives us no
          // edge-drag resize handles of its own. DragToResizeArea adds
          // invisible hit regions along the edges that call
          // windowManager.startResizing() -- only useful once the window
          // isn't maximized/filling the screen. AppTitleBar sits above the
          // Navigator's routed content, so it appears identically on every
          // screen (see its own doc comment) -- child already shrinks to
          // fit whatever height Expanded leaves it, no per-screen changes
          // needed.
          builder: (context, child) => DragToResizeArea(
            enableResizeEdges: _isMaximized ? const [] : null,
            // AppTitleBar sits outside the Navigator's own subtree (it's a
            // sibling of `child`, which already *is* the built Navigator),
            // so it has no ancestor Overlay of its own -- its IconButtons'
            // tooltips need one to render (Tooltip uses Overlay.of(context)
            // internally). This Overlay supplies that, wrapping both the
            // bar and the routed content underneath it.
            child: Overlay(
              initialEntries: [
                OverlayEntry(
                  builder: (context) => Column(
                    children: [
                      AppTitleBar(isMaximized: _isMaximized, navigatorKey: navigatorKey),
                      Expanded(child: child!),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
