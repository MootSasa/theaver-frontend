import 'dart:convert';

import 'package:flutter/foundation.dart'
    show ChangeNotifier, kIsWeb, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../utils/safari_url_safety.dart';
import 'account_manager.dart';
import 'browser_storage_bridge.dart';

class BrowserBookmark {
  final String url;
  final String title;
  final DateTime createdAt;

  const BrowserBookmark({
    required this.url,
    required this.title,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'createdAt': createdAt.toIso8601String(),
      };

  factory BrowserBookmark.fromJson(Map<String, dynamic> json) {
    return BrowserBookmark(
      url: json['url']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      createdAt: DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

class BrowserHistoryEntry {
  final String url;
  final String title;
  final DateTime visitedAt;

  const BrowserHistoryEntry({
    required this.url,
    required this.title,
    required this.visitedAt,
  });

  Map<String, dynamic> toJson() => {
        'url': url,
        'title': title,
        'visitedAt': visitedAt.toIso8601String(),
      };

  factory BrowserHistoryEntry.fromJson(Map<String, dynamic> json) {
    return BrowserHistoryEntry(
      url: json['url']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      visitedAt: DateTime.tryParse(json['visitedAt']?.toString() ?? '') ??
          DateTime.now(),
    );
  }
}

/// Manages local per-account bookmarks, browsing history, and cookie/cache
/// cleanup for Theaver's in-app WebView browser.
class BrowserDataService extends ChangeNotifier {
  BrowserDataService._internal();
  static final BrowserDataService instance = BrowserDataService._internal();

  static const String _bookmarksBaseKey = 'in_app_browser_bookmarks';
  static const String _historyBaseKey = 'in_app_browser_history';
  static const String _knownOriginsBaseKey = 'in_app_browser_known_origins';
  static const int _maxHistoryItems = 200;
  static const int _maxKnownOrigins = 500;

  @visibleForTesting
  String? debugUserIdOverride;

  List<BrowserBookmark> _bookmarks = [];
  List<BrowserHistoryEntry> _history = [];
  List<String> _knownOrigins = [];
  String? _loadedScope;

  List<BrowserBookmark> get bookmarks => List.unmodifiable(_bookmarks);
  List<BrowserHistoryEntry> get history => List.unmodifiable(_history);
  List<String> get knownOrigins => List.unmodifiable(_knownOrigins);

  List<String> knownOriginsForAccount(String userId) {
    final targetScope = _scopeForUserId(userId);
    if (_loadedScope == targetScope) {
      return List.unmodifiable(_knownOrigins);
    }
    return const [];
  }

  static String extractHost(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri != null && uri.host.isNotEmpty) {
      return uri.host.replaceFirst(RegExp(r'^www\.'), '');
    }
    return rawUrl.trim();
  }

  static String? _normalizeOrigin(String rawUrl) {
    final uri = Uri.tryParse(rawUrl.trim());
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    final safety = SafariUrlSafetyAnalyzer.analyzeUrl(rawUrl);
    final host = safety.asciiHost.isNotEmpty
        ? safety.asciiHost.toLowerCase()
        : uri.host.trim().toLowerCase();
    if (host.isEmpty) return null;
    final portSuffix = (uri.hasPort &&
            !((scheme == 'https' && uri.port == 443) ||
                (scheme == 'http' && uri.port == 80)))
        ? ':${uri.port}'
        : '';
    return '$scheme://$host$portSuffix';
  }

  String _scopeForUserId(String? uid) {
    final clean = uid?.trim() ?? '';
    return clean.isNotEmpty ? 'u_${clean}_' : '';
  }

  String _currentScope() {
    if (debugUserIdOverride != null && debugUserIdOverride!.trim().isNotEmpty) {
      return _scopeForUserId(debugUserIdOverride);
    }
    try {
      final uid = AccountManager().currentAccount?.userId;
      if (uid != null && uid.isNotEmpty) return _scopeForUserId(uid);
    } catch (_) {}
    return '';
  }

  Future<void> ensureLoaded({bool forceReload = false}) async {
    final scope = _currentScope();
    if (!forceReload && _loadedScope == scope) return;
    _loadedScope = scope;
    try {
      final prefs = await SharedPreferences.getInstance();
      final rawBm = prefs.getString('$scope$_bookmarksBaseKey');
      if (rawBm != null && rawBm.isNotEmpty) {
        final list = jsonDecode(rawBm);
        if (list is List) {
          _bookmarks = list
              .whereType<Map>()
              .map(
                (e) => BrowserBookmark.fromJson(Map<String, dynamic>.from(e)),
              )
              .where((b) => b.url.isNotEmpty)
              .toList();
        }
      } else {
        _bookmarks = [];
      }

      final rawHist = prefs.getString('$scope$_historyBaseKey');
      if (rawHist != null && rawHist.isNotEmpty) {
        final list = jsonDecode(rawHist);
        if (list is List) {
          _history = list
              .whereType<Map>()
              .map(
                (e) =>
                    BrowserHistoryEntry.fromJson(Map<String, dynamic>.from(e)),
              )
              .where((h) => h.url.isNotEmpty)
              .toList();
        }
      } else {
        _history = [];
      }

      final rawOrigins = prefs.getStringList('$scope$_knownOriginsBaseKey');
      _knownOrigins = rawOrigins != null
          ? rawOrigins.where((e) => e.trim().isNotEmpty).toList()
          : <String>[];

      notifyListeners();
    } catch (_) {}
  }

  Future<void> _saveBookmarks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scope = _currentScope();
      await prefs.setString(
        '$scope$_bookmarksBaseKey',
        jsonEncode(_bookmarks.map((b) => b.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scope = _currentScope();
      await prefs.setString(
        '$scope$_historyBaseKey',
        jsonEncode(_history.map((h) => h.toJson()).toList()),
      );
    } catch (_) {}
  }

  Future<void> _saveKnownOrigins() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final scope = _currentScope();
      await prefs.setStringList('$scope$_knownOriginsBaseKey', _knownOrigins);
    } catch (_) {}
  }

  bool isBookmarked(String url) {
    final target = url.trim();
    return _bookmarks.any((b) => b.url == target);
  }

  Future<bool> toggleBookmark(String url, String title) async {
    await ensureLoaded();
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return false;
    final cleanTitle =
        title.trim().isNotEmpty ? title.trim() : extractHost(cleanUrl);
    final idx = _bookmarks.indexWhere((b) => b.url == cleanUrl);
    bool added;
    if (idx >= 0) {
      _bookmarks.removeAt(idx);
      added = false;
    } else {
      _bookmarks.insert(
        0,
        BrowserBookmark(
          url: cleanUrl,
          title: cleanTitle,
          createdAt: DateTime.now(),
        ),
      );
      added = true;
    }
    notifyListeners();
    await _saveBookmarks();
    return added;
  }

  Future<void> removeBookmark(String url) async {
    await ensureLoaded();
    _bookmarks.removeWhere((b) => b.url == url.trim());
    notifyListeners();
    await _saveBookmarks();
  }

  Future<void> recordVisit(String url, String title) async {
    await ensureLoaded();
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty ||
        (!cleanUrl.startsWith('http://') && !cleanUrl.startsWith('https://'))) {
      return;
    }
    final cleanTitle =
        title.trim().isNotEmpty ? title.trim() : extractHost(cleanUrl);
    if (_history.isNotEmpty && _history.first.url == cleanUrl) {
      _history[0] = BrowserHistoryEntry(
        url: cleanUrl,
        title: cleanTitle,
        visitedAt: DateTime.now(),
      );
    } else {
      _history.removeWhere((h) => h.url == cleanUrl);
      _history.insert(
        0,
        BrowserHistoryEntry(
          url: cleanUrl,
          title: cleanTitle,
          visitedAt: DateTime.now(),
        ),
      );
      if (_history.length > _maxHistoryItems) {
        _history = _history.sublist(0, _maxHistoryItems);
      }
    }

    final origin = _normalizeOrigin(cleanUrl);
    bool originsChanged = false;
    if (origin != null) {
      _knownOrigins.remove(origin);
      _knownOrigins.insert(0, origin);
      if (_knownOrigins.length > _maxKnownOrigins) {
        _knownOrigins = _knownOrigins.sublist(0, _maxKnownOrigins);
      }
      originsChanged = true;
    }

    notifyListeners();
    await _saveHistory();
    if (originsChanged) {
      await _saveKnownOrigins();
    }
  }

  Future<void> deleteHistoryAt(int index) async {
    await ensureLoaded();
    if (index < 0 || index >= _history.length) return;
    _history.removeAt(index);
    notifyListeners();
    await _saveHistory();
  }

  /// Removes a specific [entry] regardless of filtered list indices.
  Future<void> removeHistoryEntry(BrowserHistoryEntry entry) async {
    await ensureLoaded();
    final int idx = _history.indexWhere(
      (h) =>
          identical(h, entry) ||
          (h.url == entry.url && h.visitedAt == entry.visitedAt),
    );
    if (idx < 0) return;
    _history.removeAt(idx);
    notifyListeners();
    await _saveHistory();
  }

  /// Clears cookies (including `HttpOnly`), `WebStorage`, and origin records
  /// for the site matching [urlOrOrigin].
  Future<void> clearSiteData(String urlOrOrigin) async {
    await ensureLoaded();
    final raw = urlOrOrigin.trim();
    if (raw.isEmpty) return;
    final String normalizedTarget = _normalizeOrigin(raw) ??
        (raw.contains('://') ? raw : 'https://$raw');
    await BrowserStorageBridge.instance.clearSiteData(normalizedTarget);

    final targetHost = (Uri.tryParse(normalizedTarget)?.host ?? raw)
        .toLowerCase()
        .replaceFirst(RegExp(r'^www\.'), '');
    final prevLen = _knownOrigins.length;
    if (targetHost.isNotEmpty) {
      _knownOrigins.removeWhere((origin) {
        final h = (Uri.tryParse(origin)?.host ?? '')
            .toLowerCase()
            .replaceFirst(RegExp(r'^www\.'), '');
        return h == targetHost || h.endsWith('.$targetHost');
      });
    }
    if (_knownOrigins.length != prevLen) {
      await _saveKnownOrigins();
    }
    notifyListeners();
  }

  Future<void> clearHistoryAndCookies({
    bool clearHistory = true,
    bool clearCookiesAndSiteData = true,
  }) async {
    await ensureLoaded();
    if (clearHistory) {
      _history = [];
    }
    if (clearCookiesAndSiteData) {
      _knownOrigins = [];
    }
    notifyListeners();
    if (clearHistory) {
      await _saveHistory();
    }
    if (clearCookiesAndSiteData) {
      await _saveKnownOrigins();
      await BrowserStorageBridge.instance.clearAllWebData();
      if (!kIsWeb && WebViewPlatform.instance != null) {
        try {
          await WebViewCookieManager().clearCookies();
        } catch (_) {}
      }
    }
  }

  /// Permanently removes all bookmarks, history, and known origins stored for [userId].
  Future<void> wipeAccountData(String userId) async {
    final scope = _scopeForUserId(userId);
    if (scope.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$scope$_bookmarksBaseKey');
      await prefs.remove('$scope$_historyBaseKey');
      await prefs.remove('$scope$_knownOriginsBaseKey');
    } catch (_) {}
    if (_loadedScope == scope || _currentScope() == scope) {
      _bookmarks = [];
      _history = [];
      _knownOrigins = [];
      _loadedScope = null;
      notifyListeners();
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _bookmarks = [];
    _history = [];
    _knownOrigins = [];
    _loadedScope = null;
    debugUserIdOverride = null;
  }
}
