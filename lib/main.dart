import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'app_theme.dart';
import 'data/theme_mode_settings.dart';
import 'ui/home_screen.dart';

void main() {
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

class MainApp extends StatelessWidget {
  const MainApp({super.key});

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
        ),
      ),
    );
  }
}
