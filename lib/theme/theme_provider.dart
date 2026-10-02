import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/theav_theme.dart';
import '../services/theav_theme_service.dart';
import 'app_theme.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  final TheavThemeService _service = TheavThemeService();

  ThemeProvider() {
    _loadThemeMode();
    _service.addListener(_onServiceChanged);
    _service.init();
  }

  void _onServiceChanged() {
    notifyListeners();
  }

  ThemeMode get themeMode => _themeMode;
  TheavThemeService get service => _service;

  TheavTheme get activeLightTheme => _service.activeLightTheme;
  TheavTheme get activeDarkTheme => _service.activeDarkTheme;

  TheavTheme get activeTheme =>
      _themeMode == ThemeMode.dark ? activeDarkTheme : activeLightTheme;

  ThemeData get lightThemeData => AppTheme.fromTheavTheme(activeLightTheme);
  ThemeData get darkThemeData => AppTheme.fromTheavTheme(activeDarkTheme);

  Future<void> _loadThemeMode() async {
    final prefs = await SharedPreferences.getInstance();
    final int? themeIndex = prefs.getInt('theme_mode');
    if (themeIndex != null && themeIndex >= 0 && themeIndex < ThemeMode.values.length) {
      _themeMode = ThemeMode.values[themeIndex];
    } else {
      _themeMode = ThemeMode.system;
    }
    notifyListeners();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('theme_mode', mode.index);
    notifyListeners();
  }

  Future<void> setActiveTheme(TheavTheme theme) async {
    await _service.setActiveTheme(theme);
    notifyListeners();
  }

  // Convenience methods for UI
  Future<void> setToSystem() => setThemeMode(ThemeMode.system);
  Future<void> setToLight() => setThemeMode(ThemeMode.light);
  Future<void> setToDark() => setThemeMode(ThemeMode.dark);

  @override
  void dispose() {
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }
}
