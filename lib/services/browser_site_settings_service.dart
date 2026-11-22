import 'dart:convert';

import 'package:flutter/foundation.dart' show ChangeNotifier, visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/safari_url_safety.dart';
import 'account_manager.dart';
import 'browser_data_service.dart';

/// Global cookie acceptance policy for Theaver's in-app WebView browser.
enum BrowserCookiePolicy {
  allowAll,
  blockThirdParty,
  blockAll,
}

/// Persistent site permission decision stored per domain host.
enum SitePermissionDecision {
  ask,
  allow,
  deny,
}

/// Persistent settings for a specific domain host (`asciiHost`).
class BrowserSitePreference {
  final String asciiHost;
  final String displayHost;
  final bool? desktopMode;
  final SitePermissionDecision cameraPolicy;
  final SitePermissionDecision microphonePolicy;
  final bool muteJsDialogs;

  const BrowserSitePreference({
    required this.asciiHost,
    required this.displayHost,
    this.desktopMode,
    this.cameraPolicy = SitePermissionDecision.ask,
    this.microphonePolicy = SitePermissionDecision.ask,
    this.muteJsDialogs = false,
  });

  bool get isDefault =>
      desktopMode == null &&
      cameraPolicy == SitePermissionDecision.ask &&
      microphonePolicy == SitePermissionDecision.ask &&
      !muteJsDialogs;

  BrowserSitePreference copyWith({
    bool? desktopMode,
    bool clearDesktopMode = false,
    SitePermissionDecision? cameraPolicy,
    SitePermissionDecision? microphonePolicy,
    bool? muteJsDialogs,
  }) {
    return BrowserSitePreference(
      asciiHost: asciiHost,
      displayHost: displayHost,
      desktopMode: clearDesktopMode ? null : (desktopMode ?? this.desktopMode),
      cameraPolicy: cameraPolicy ?? this.cameraPolicy,
      microphonePolicy: microphonePolicy ?? this.microphonePolicy,
      muteJsDialogs: muteJsDialogs ?? this.muteJsDialogs,
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'asciiHost': asciiHost,
        'displayHost': displayHost,
        if (desktopMode != null) 'desktopMode': desktopMode,
        'cameraPolicy': cameraPolicy.name,
        'microphonePolicy': microphonePolicy.name,
        'muteJsDialogs': muteJsDialogs,
      };

  factory BrowserSitePreference.fromJson(Map<String, dynamic> json) {
    SitePermissionDecision parseDecision(dynamic raw) {
      return SitePermissionDecision.values.firstWhere(
        (d) => d.name == raw?.toString(),
        orElse: () => SitePermissionDecision.ask,
      );
    }

    final host = json['asciiHost']?.toString().toLowerCase() ?? '';
    return BrowserSitePreference(
      asciiHost: host,
      displayHost: (json['displayHost']?.toString().isNotEmpty ?? false)
          ? json['displayHost'].toString()
          : host,
      desktopMode: json['desktopMode'] is bool ? json['desktopMode'] as bool : null,
      cameraPolicy: parseDecision(json['cameraPolicy']),
      microphonePolicy: parseDecision(json['microphonePolicy']),
      muteJsDialogs: json['muteJsDialogs'] == true,
    );
  }
}

/// Manages per-account persistent browser preferences (cookie policy, autofill
/// toggles, and per-host Desktop mode / Camera & Microphone / JS dialog mute).
class BrowserSiteSettingsService extends ChangeNotifier {
  BrowserSiteSettingsService._internal();
  static final BrowserSiteSettingsService instance =
      BrowserSiteSettingsService._internal();

  static const String _prefsPrefix = 'browser_site_settings_v1_u_';

  @visibleForTesting
  String? debugUserIdOverride;

  String? _loadedUid;
  BrowserCookiePolicy _cookiePolicy = BrowserCookiePolicy.allowAll;
  bool _savePasswordsEnabled = true;
  bool _contactAutofillEnabled = true;
  bool _osAutofillEnabled = true;
  Map<String, BrowserSitePreference> _sitePreferences =
      <String, BrowserSitePreference>{};

  BrowserCookiePolicy get cookiePolicy => _cookiePolicy;
  bool get savePasswordsEnabled => _savePasswordsEnabled;
  bool get contactAutofillEnabled => _contactAutofillEnabled;
  bool get osAutofillEnabled => _osAutofillEnabled;
  Map<String, BrowserSitePreference> get sitePreferences =>
      Map<String, BrowserSitePreference>.unmodifiable(_sitePreferences);

  String get _activeUid {
    if (debugUserIdOverride != null && debugUserIdOverride!.trim().isNotEmpty) {
      return debugUserIdOverride!.trim();
    }
    try {
      final uid = AccountManager().currentAccount?.userId;
      if (uid != null && uid.trim().isNotEmpty) return uid.trim();
    } catch (_) {}
    return 'guest';
  }

  static String normalizeHostKey(String rawUrlOrHost) {
    final clean = rawUrlOrHost.trim();
    if (clean.isEmpty) return '';
    if (clean.contains('://')) {
      final safety = SafariUrlSafetyAnalyzer.analyzeUrl(clean);
      if (safety.asciiHost.isNotEmpty) {
        return safety.asciiHost.toLowerCase();
      }
      return BrowserDataService.extractHost(clean).toLowerCase();
    }
    return clean.toLowerCase().replaceFirst(RegExp(r'^www\.'), '');
  }

  static String _displayHostFor(String rawUrlOrHost, String fallbackHost) {
    if (rawUrlOrHost.contains('://')) {
      final safety = SafariUrlSafetyAnalyzer.analyzeUrl(rawUrlOrHost);
      if (safety.displayHost.isNotEmpty) return safety.displayHost;
    }
    final decoded = SafariUrlSafetyAnalyzer.decodePunycodeHost(fallbackHost);
    return decoded.replaceFirst(RegExp(r'^www\.'), '');
  }

  Future<void> ensureLoaded({bool forceReload = false}) async {
    final uid = _activeUid;
    if (!forceReload && _loadedUid == uid) return;
    _loadedUid = uid;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefsPrefix$uid');
      if (raw == null || raw.isEmpty) {
        _cookiePolicy = BrowserCookiePolicy.allowAll;
        _savePasswordsEnabled = true;
        _contactAutofillEnabled = true;
        _osAutofillEnabled = true;
        _sitePreferences = <String, BrowserSitePreference>{};
      } else {
        final decoded = jsonDecode(raw);
        if (decoded is Map) {
          _cookiePolicy = BrowserCookiePolicy.values.firstWhere(
            (p) => p.name == decoded['cookiePolicy']?.toString(),
            orElse: () => BrowserCookiePolicy.allowAll,
          );
          _savePasswordsEnabled = decoded['savePasswordsEnabled'] != false;
          _contactAutofillEnabled = decoded['contactAutofillEnabled'] != false;
          _osAutofillEnabled = decoded['osAutofillEnabled'] != false;

          final sites = <String, BrowserSitePreference>{};
          final rawSites = decoded['sites'];
          if (rawSites is Map) {
            for (final entry in rawSites.entries) {
              if (entry.value is Map) {
                final pref = BrowserSitePreference.fromJson(
                  Map<String, dynamic>.from(entry.value as Map),
                );
                if (pref.asciiHost.isNotEmpty && !pref.isDefault) {
                  sites[pref.asciiHost] = pref;
                }
              }
            }
          }
          _sitePreferences = sites;
        }
      }
      notifyListeners();
    } catch (_) {}
  }

  Future<void> _save(String uid) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encodedSites = <String, dynamic>{};
      for (final entry in _sitePreferences.entries) {
        if (!entry.value.isDefault) {
          encodedSites[entry.key] = entry.value.toJson();
        }
      }
      await prefs.setString(
        '$_prefsPrefix$uid',
        jsonEncode(<String, dynamic>{
          'cookiePolicy': _cookiePolicy.name,
          'savePasswordsEnabled': _savePasswordsEnabled,
          'contactAutofillEnabled': _contactAutofillEnabled,
          'osAutofillEnabled': _osAutofillEnabled,
          'sites': encodedSites,
        }),
      );
    } catch (_) {}
  }

  BrowserSitePreference? preferenceForUrl(String url) {
    final key = normalizeHostKey(url);
    if (key.isEmpty) return null;
    return _sitePreferences[key];
  }

  BrowserSitePreference? preferenceForHost(String hostKey) {
    final key = normalizeHostKey(hostKey);
    if (key.isEmpty) return null;
    return _sitePreferences[key];
  }

  Future<void> setCookiePolicy(BrowserCookiePolicy policy) async {
    await ensureLoaded();
    if (_cookiePolicy == policy) return;
    _cookiePolicy = policy;
    notifyListeners();
    await _save(_activeUid);
  }

  Future<void> setSavePasswordsEnabled(bool enabled) async {
    await ensureLoaded();
    if (_savePasswordsEnabled == enabled) return;
    _savePasswordsEnabled = enabled;
    notifyListeners();
    await _save(_activeUid);
  }

  Future<void> setContactAutofillEnabled(bool enabled) async {
    await ensureLoaded();
    if (_contactAutofillEnabled == enabled) return;
    _contactAutofillEnabled = enabled;
    notifyListeners();
    await _save(_activeUid);
  }

  Future<void> setOsAutofillEnabled(bool enabled) async {
    await ensureLoaded();
    if (_osAutofillEnabled == enabled) return;
    _osAutofillEnabled = enabled;
    notifyListeners();
    await _save(_activeUid);
  }

  BrowserSitePreference _getOrInit(String rawUrlOrHost) {
    final key = normalizeHostKey(rawUrlOrHost);
    return _sitePreferences[key] ??
        BrowserSitePreference(
          asciiHost: key,
          displayHost: _displayHostFor(rawUrlOrHost, key),
        );
  }

  void _storeOrPrune(BrowserSitePreference next) {
    if (next.asciiHost.isEmpty) return;
    if (next.isDefault) {
      _sitePreferences.remove(next.asciiHost);
    } else {
      _sitePreferences[next.asciiHost] = next;
    }
  }

  Future<void> setDesktopModeForUrl(String rawUrl, bool? desktopMode) async {
    await ensureLoaded();
    final key = normalizeHostKey(rawUrl);
    if (key.isEmpty) return;
    final existing = _getOrInit(rawUrl);
    final next = desktopMode == null
        ? existing.copyWith(clearDesktopMode: true)
        : existing.copyWith(desktopMode: desktopMode);
    _storeOrPrune(next);
    notifyListeners();
    await _save(_activeUid);
  }

  Future<void> setPermissionForHost(
    String rawUrlOrHost, {
    SitePermissionDecision? camera,
    SitePermissionDecision? microphone,
  }) async {
    await ensureLoaded();
    final key = normalizeHostKey(rawUrlOrHost);
    if (key.isEmpty) return;
    final existing = _getOrInit(rawUrlOrHost);
    final next = existing.copyWith(
      cameraPolicy: camera,
      microphonePolicy: microphone,
    );
    _storeOrPrune(next);
    notifyListeners();
    await _save(_activeUid);
  }

  Future<void> setMuteJsDialogsForHost(
    String rawUrlOrHost,
    bool muted,
  ) async {
    await ensureLoaded();
    final key = normalizeHostKey(rawUrlOrHost);
    if (key.isEmpty) return;
    final existing = _getOrInit(rawUrlOrHost);
    final next = existing.copyWith(muteJsDialogs: muted);
    _storeOrPrune(next);
    notifyListeners();
    await _save(_activeUid);
  }

  Future<void> resetHost(String rawUrlOrHost) async {
    await ensureLoaded();
    final key = normalizeHostKey(rawUrlOrHost);
    if (_sitePreferences.remove(key) != null) {
      notifyListeners();
      await _save(_activeUid);
    }
  }

  Future<void> clearAllSitePreferences() async {
    await ensureLoaded();
    if (_sitePreferences.isEmpty) return;
    _sitePreferences.clear();
    notifyListeners();
    await _save(_activeUid);
  }

  Future<void> wipeAccount(String userId) async {
    final uid = userId.trim();
    if (uid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_prefsPrefix$uid');
    } catch (_) {}
    if (_loadedUid == uid || _activeUid == uid) {
      _cookiePolicy = BrowserCookiePolicy.allowAll;
      _savePasswordsEnabled = true;
      _contactAutofillEnabled = true;
      _osAutofillEnabled = true;
      _sitePreferences = <String, BrowserSitePreference>{};
      _loadedUid = null;
      notifyListeners();
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _loadedUid = null;
    _cookiePolicy = BrowserCookiePolicy.allowAll;
    _savePasswordsEnabled = true;
    _contactAutofillEnabled = true;
    _osAutofillEnabled = true;
    _sitePreferences = <String, BrowserSitePreference>{};
    debugUserIdOverride = null;
  }
}
