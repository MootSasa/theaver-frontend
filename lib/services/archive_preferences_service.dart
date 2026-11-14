import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'account_manager.dart';

/// Persists per-account archive presentation preferences (e.g. hiding the
/// archive row above the main chat list so it opens on pull-down or from menu).
class ArchivePreferencesService extends ChangeNotifier {
  ArchivePreferencesService._internal();
  static final ArchivePreferencesService _instance =
      ArchivePreferencesService._internal();
  factory ArchivePreferencesService() => _instance;

  SharedPreferences? _prefs;
  String? _currentUserId;
  bool _hiddenAboveList = false;
  bool _initialized = false;

  /// Whether the Archive entry row is hidden above the main chat list.
  bool get isHiddenAboveList => _hiddenAboveList;

  /// Whether preferences have finished initial load for the active account.
  bool get isInitialized => _initialized;

  String _storageKey(String? userId) =>
      userId != null && userId.isNotEmpty
          ? 'user_${userId}_archive_hidden_above_list'
          : 'archive_hidden_above_list_default';

  /// Loads preferences for the current account and subscribes to account changes.
  Future<void> init() async {
    final accountManager = AccountManager();
    accountManager.removeListener(_onAccountChanged);
    accountManager.addListener(_onAccountChanged);

    _prefs ??= await SharedPreferences.getInstance();
    final uid = accountManager.currentAccount?.userId;
    await _loadForUser(uid);
    _initialized = true;
  }

  void _onAccountChanged() {
    final newUid = AccountManager().currentAccount?.userId;
    if (newUid != _currentUserId) {
      _loadForUser(newUid);
    }
  }

  Future<void> _loadForUser(String? userId) async {
    _currentUserId = userId;
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final nextValue = prefs.getBool(_storageKey(userId)) ?? false;
    final changed = nextValue != _hiddenAboveList || !_initialized;
    _hiddenAboveList = nextValue;
    if (changed) {
      notifyListeners();
    }
  }

  /// Sets whether the Archive row should be hidden above the main chat list.
  Future<void> setHiddenAboveList(bool hidden) async {
    final prefs = _prefs ??= await SharedPreferences.getInstance();
    final uid = _currentUserId ?? AccountManager().currentAccount?.userId;
    _currentUserId = uid;
    _initialized = true;
    final changed = _hiddenAboveList != hidden;
    _hiddenAboveList = hidden;
    await prefs.setBool(_storageKey(uid), hidden);
    if (changed) {
      notifyListeners();
    }
  }

  /// Toggles the hidden-above-list preference.
  Future<void> toggleHiddenAboveList() => setHiddenAboveList(!_hiddenAboveList);

  /// Resets in-memory state (useful in tests with mock SharedPreferences).
  @visibleForTesting
  Future<void> reloadForTest({String? userId}) async {
    _prefs = await SharedPreferences.getInstance();
    _initialized = false;
    await _loadForUser(userId ?? AccountManager().currentAccount?.userId);
    _initialized = true;
  }
}
