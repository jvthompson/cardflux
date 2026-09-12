import 'package:flutter/material.dart';

/// Single source of truth for the app's light/dark ThemeData, so the
/// gameplay table (which always pins to [light], see TableScreen) and the
/// rest of the app (which switches via ThemeModeController) stay in sync.
class AppTheme {
  static final light = ThemeData(
    colorSchemeSeed: Colors.green,
    useMaterial3: true,
  );
  static final dark = ThemeData(
    colorSchemeSeed: Colors.green,
    useMaterial3: true,
    brightness: Brightness.dark,
  );
}
