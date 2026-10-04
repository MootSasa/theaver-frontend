import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/theav_theme.dart';
import '../services/account_manager.dart';
import '../services/theav_theme_service.dart';
import 'app_theme.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  final TheavThemeService _service = TheavThemeService();
  String? _currentUserId;

  ThemeProvider() {
    _service.addListener(_onServiceChanged);
    _service.init();

    final accountManager = AccountManager();
    accountManager.removeListener(_onAccountManagerChanged);
    accountManager.addListener(_onAccountManagerChanged);

    final currentUid = accountManager.currentAccount?.userId;
    _switchUserThemeMode(currentUid);
  }

  void _onServiceChanged() {
    notifyListeners();
  }

  void _onAccountManagerChanged() {
    final newUid = AccountManager().currentAccount?.userId;
    if (newUid != _currentUserId) {
      _switchUserThemeMode(newUid);
    }
  }

  String _themeModeKey(String? uid) =>
      uid != null && uid.isNotEmpty ? 'user_${uid}_theme_mode' : 'theme_mode';

  Future<void> _switchUserThemeMode(String? userId) async {
    _currentUserId = userId;
    final prefs = await SharedPreferences.getInstance();
    final userKey = _themeModeKey(userId);

    int? themeIndex = prefs.getInt(userKey);
    // Legacy migration: if user-scoped key is missing and legacy 'theme_mode' exists, migrate once
    if (themeIndex == null && userId != null && userId.isNotEmpty && prefs.containsKey('theme_mode')) {
      themeIndex = prefs.getInt('theme_mode');
      if (themeIndex != null) {
        await prefs.setInt(userKey, themeIndex);
      }
    }

    if (themeIndex != null && themeIndex >= 0 && themeIndex < ThemeMode.values.length) {
      _themeMode = ThemeMode.values[themeIndex];
    } else {
      _themeMode = ThemeMode.system;
    }
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

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey(_currentUserId), mode.index);
    notifyListeners();
  }

  Future<void> setActiveTheme(TheavTheme theme) async {
    await _service.setActiveTheme(theme);
    if (theme.isDark && _themeMode != ThemeMode.dark) {
      await setThemeMode(ThemeMode.dark);
    } else if (!theme.isDark && _themeMode != ThemeMode.light) {
      await setThemeMode(ThemeMode.light);
    } else {
      notifyListeners();
    }
  }

  // Convenience methods for UI
  Future<void> setToSystem() => setThemeMode(ThemeMode.system);
  Future<void> setToLight() => setThemeMode(ThemeMode.light);
  Future<void> setToDark() => setThemeMode(ThemeMode.dark);

  @override
  void dispose() {
    AccountManager().removeListener(_onAccountManagerChanged);
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }
}
