import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/theav_theme.dart';
import '../services/account_manager.dart';
import '../services/theav_theme_service.dart';
import 'app_theme.dart';

class ThemeProvider extends ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.system;
  bool _scheduleEnabled = false;
  TimeOfDay _darkStart = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _darkEnd = const TimeOfDay(hour: 7, minute: 0);
  double _messageFontSize = 16.0;
  Timer? _scheduleTimer;

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

  String _userKey(String? uid, String suffix) =>
      uid != null && uid.isNotEmpty ? 'user_${uid}_$suffix' : suffix;

  String _themeModeKey(String? uid) => _userKey(uid, 'theme_mode');

  /// Evaluates whether [now] falls inside the scheduled dark window `[start, end)`.
  static bool isTimeInDarkSchedule(
    DateTime now,
    TimeOfDay start,
    TimeOfDay end,
  ) {
    final nowMins = now.hour * 60 + now.minute;
    final startMins = start.hour * 60 + start.minute;
    final endMins = end.hour * 60 + end.minute;
    if (startMins == endMins) return false;
    if (startMins < endMins) {
      return nowMins >= startMins && nowMins < endMins;
    }
    // Overnight window, e.g. 22:00 -> 07:00
    return nowMins >= startMins || nowMins < endMins;
  }

  Future<void> _switchUserThemeMode(String? userId) async {
    _currentUserId = userId;
    final prefs = await SharedPreferences.getInstance();
    final userKey = _themeModeKey(userId);

    int? themeIndex = prefs.getInt(userKey);
    // Legacy migration: if user-scoped key is missing and legacy 'theme_mode' exists, migrate once
    if (themeIndex == null &&
        userId != null &&
        userId.isNotEmpty &&
        prefs.containsKey('theme_mode')) {
      themeIndex = prefs.getInt('theme_mode');
      if (themeIndex != null) {
        await prefs.setInt(userKey, themeIndex);
      }
    }

    if (themeIndex != null &&
        themeIndex >= 0 &&
        themeIndex < ThemeMode.values.length) {
      _themeMode = ThemeMode.values[themeIndex];
    } else {
      _themeMode = ThemeMode.system;
    }

    _scheduleEnabled =
        prefs.getBool(_userKey(userId, 'theme_schedule_enabled')) ?? false;
    final startMins =
        prefs.getInt(_userKey(userId, 'theme_dark_start')) ?? (22 * 60);
    final endMins =
        prefs.getInt(_userKey(userId, 'theme_dark_end')) ?? (7 * 60);
    _darkStart = TimeOfDay(
      hour: (startMins ~/ 60) % 24,
      minute: startMins % 60,
    );
    _darkEnd = TimeOfDay(
      hour: (endMins ~/ 60) % 24,
      minute: endMins % 60,
    );

    final fontSize = prefs.getDouble(_userKey(userId, 'message_font_size'));
    _messageFontSize = (fontSize ?? 16.0).clamp(12.0, 24.0);

    _syncScheduleTimer();
    if (_scheduleEnabled) {
      _applyScheduledMode(notify: false);
    }
    notifyListeners();
  }

  void _syncScheduleTimer() {
    _scheduleTimer?.cancel();
    _scheduleTimer = null;
    if (_scheduleEnabled) {
      _scheduleTimer = Timer.periodic(
        const Duration(seconds: 60),
        (_) => _applyScheduledMode(notify: true),
      );
    }
  }

  void _applyScheduledMode({required bool notify}) {
    if (!_scheduleEnabled) return;
    final target = isTimeInDarkSchedule(DateTime.now(), _darkStart, _darkEnd)
        ? ThemeMode.dark
        : ThemeMode.light;
    if (_themeMode != target) {
      _themeMode = target;
      if (notify) {
        notifyListeners();
      }
    }
  }

  ThemeMode get themeMode => _themeMode;
  bool get scheduleEnabled => _scheduleEnabled;
  TimeOfDay get darkStart => _darkStart;
  TimeOfDay get darkEnd => _darkEnd;
  double get messageFontSize => _messageFontSize;
  TheavThemeService get service => _service;

  TheavTheme get activeLightTheme => _service.activeLightTheme;
  TheavTheme get activeDarkTheme => _service.activeDarkTheme;

  TheavTheme get activeTheme =>
      _themeMode == ThemeMode.dark ? activeDarkTheme : activeLightTheme;

  ThemeData get lightThemeData => AppTheme.fromTheavTheme(
        activeLightTheme,
        messageFontSize: _messageFontSize,
      );

  ThemeData get darkThemeData => AppTheme.fromTheavTheme(
        activeDarkTheme,
        messageFontSize: _messageFontSize,
      );

  Future<void> setThemeMode(ThemeMode mode) async {
    _themeMode = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_themeModeKey(_currentUserId), mode.index);
    if (_scheduleEnabled) {
      _scheduleEnabled = false;
      _syncScheduleTimer();
      await prefs.setBool(
        _userKey(_currentUserId, 'theme_schedule_enabled'),
        false,
      );
    }
    notifyListeners();
  }

  Future<void> setScheduleEnabled(bool enabled) async {
    _scheduleEnabled = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(
      _userKey(_currentUserId, 'theme_schedule_enabled'),
      enabled,
    );
    _syncScheduleTimer();
    if (enabled) {
      _applyScheduledMode(notify: false);
    }
    notifyListeners();
  }

  Future<void> setDarkSchedule({TimeOfDay? start, TimeOfDay? end}) async {
    if (start != null) _darkStart = start;
    if (end != null) _darkEnd = end;
    final prefs = await SharedPreferences.getInstance();
    if (start != null) {
      await prefs.setInt(
        _userKey(_currentUserId, 'theme_dark_start'),
        start.hour * 60 + start.minute,
      );
    }
    if (end != null) {
      await prefs.setInt(
        _userKey(_currentUserId, 'theme_dark_end'),
        end.hour * 60 + end.minute,
      );
    }
    if (_scheduleEnabled) {
      _applyScheduledMode(notify: false);
    }
    notifyListeners();
  }

  Future<void> setMessageFontSize(double size) async {
    final clamped = size.clamp(12.0, 24.0);
    _messageFontSize = clamped;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_userKey(_currentUserId, 'message_font_size'), clamped);
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
    _scheduleTimer?.cancel();
    AccountManager().removeListener(_onAccountManagerChanged);
    _service.removeListener(_onServiceChanged);
    super.dispose();
  }
}
