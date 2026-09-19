import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:window_manager/window_manager.dart';

import 'app_theme.dart';
import 'data/theme_mode_settings.dart';
import 'ui/home_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();
  await windowManager.waitUntilReadyToShow(null, () async {
    await windowManager.maximize();
    await windowManager.setAsFrameless();
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
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKeyEvent);
    windowManager.addListener(this);
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    HardwareKeyboard.instance.removeHandler(_handleKeyEvent);
    super.dispose();
  }

  bool _isChromeHidden = true;
  bool _isTogglingChrome = false;

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
    return ChangeNotifierProvider(
      create: (_) => ThemeModeController(),
      child: Consumer<ThemeModeController>(
        builder: (context, controller, _) => MaterialApp(
          title: 'Cardflux',
          theme: AppTheme.light,
          darkTheme: AppTheme.dark,
          themeMode: controller.isDarkMode ? ThemeMode.dark : ThemeMode.light,
          home: const HomeScreen(),
          // The window is frameless (see main()), so the OS gives us no
          // edge-drag resize handles of its own. DragToResizeArea adds
          // invisible hit regions along the edges that call
          // windowManager.startResizing() -- only useful once the window
          // isn't maximized/filling the screen.
          builder: (context, child) => DragToResizeArea(
            enableResizeEdges: _isMaximized ? const [] : null,
            child: child!,
          ),
        ),
      ),
    );
  }
}
