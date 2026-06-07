import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'theme_colors.dart';

export 'theme_colors.dart';

enum AppTheme { appleLight, appleDark, dynamic, system }

class ThemeProvider extends ChangeNotifier {
  AppTheme _current = AppTheme.system;
  Brightness _platformBrightness = Brightness.dark;

  AppTheme get currentTheme => _current;

  /// Resolved brightness — when [system] or [dynamic], reads the device's actual brightness.
  Brightness get brightness {
    if (_current == AppTheme.system || _current == AppTheme.dynamic) {
      return _platformBrightness;
    }
    return _current == AppTheme.appleLight ? Brightness.light : Brightness.dark;
  }

  bool get isLight => brightness == Brightness.light;
  bool get isDark => brightness == Brightness.dark;

  /// Resolved colors — when [system], picks dark/light based on device brightness.
  ThemeColors get colors => _resolveColors();
  ThemeData get themeData => buildThemeData(colors);

  ThemeProvider() {
    _platformBrightness =
        ui.PlatformDispatcher.instance.platformBrightness;
    _load();
  }

  /// Called by [WidgetsBindingObserver.didChangePlatformBrightness] in main.dart.
  void updatePlatformBrightness(Brightness b) {
    if (b != _platformBrightness) {
      _platformBrightness = b;
      if (_current == AppTheme.system || _current == AppTheme.dynamic) {
        notifyListeners();
      }
    }
  }

  Future<void> _load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final idx = prefs.getInt('appThemeIndex') ?? 1;
      if (idx >= 0 && idx < AppTheme.values.length) {
        _current = AppTheme.values[idx];
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> setTheme(AppTheme theme) async {
    _current = theme;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt('appThemeIndex', theme.index);
    } catch (_) {}
  }

  /// Resolve the actual theme enum when system mode is selected.
  ThemeColors _resolveColors() {
    if (_current == AppTheme.dynamic) {
      // Generate harmonious colors from the dynamic seed
      return ThemeColors.fromSeed(
        seed: _seedColor,
        brightness: _platformBrightness,
      );
    }
    final actual = _current == AppTheme.system
        ? (_platformBrightness == Brightness.light
            ? AppTheme.appleLight
            : AppTheme.appleDark)
        : _current;
    return _colorsFor(actual);
  }

  /// Seed color used by the [dynamic] theme.
  /// Switches between the dark and light theme's primary accents so the
  /// generated palette feels familiar in each mode.
  Color get _seedColor =>
      _platformBrightness == Brightness.light
          ? const Color(0xFF2C3E6B) // deep navy — academic feel
          : const Color(0xFF1E88E5); // electric blue — CSTIAN dynamic

  static ThemeColors _colorsFor(AppTheme theme) {
    switch (theme) {
      case AppTheme.appleLight:
        return ThemeColors.appleLight;
      case AppTheme.appleDark:
        return ThemeColors.appleDark;
      case AppTheme.dynamic:
        // Should not reach here (resolved before calling), but fallback to dark
        return ThemeColors.appleDark;
      case AppTheme.system:
        // Should not reach here (resolved before calling), but fallback to dark
        return ThemeColors.appleDark;
    }
  }

  /// Get the ThemeProvider from context (no listening — use context.colors instead).
  static ThemeProvider of(BuildContext context) {
    return Provider.of<ThemeProvider>(context, listen: false);
  }
}

// ── Convenience extension ───────────────────────────────────────────────────
extension ThemeColorsExt on BuildContext {
  /// Watch-based colors — use in [build] methods to react to theme changes.
  /// This ensures screens like Notes, Routines, etc. automatically switch
  /// between light and dark themes when the user toggles themes.
  ThemeColors get colors => watch<ThemeProvider>().colors;

  /// Read-based colors — use in event handlers, callbacks, and async methods
  /// where [watch] would throw a Provider assertion error.
  ThemeColors get colorsOf => read<ThemeProvider>().colors;
}

