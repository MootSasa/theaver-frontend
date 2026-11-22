import 'dart:collection';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';

/// Serializable representation of a native WebView HTTP cookie including
/// `HttpOnly`, `Secure`, and `SameSite` attributes.
class BrowserCookieRecord {
  final String hostKey;
  final String name;
  final String value;
  final String path;
  final int expiresEpochMs;
  final bool isSecure;
  final bool isHttpOnly;
  final int sameSite;

  const BrowserCookieRecord({
    required this.hostKey,
    required this.name,
    required this.value,
    this.path = '/',
    this.expiresEpochMs = 0,
    this.isSecure = false,
    this.isHttpOnly = false,
    this.sameSite = -1,
  });

  bool isExpiredAt(DateTime now) {
    if (expiresEpochMs <= 0) return false;
    return expiresEpochMs <= now.millisecondsSinceEpoch;
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'hostKey': hostKey,
        'name': name,
        'value': value,
        'path': path,
        'expiresEpochMs': expiresEpochMs,
        'isSecure': isSecure,
        'isHttpOnly': isHttpOnly,
        'sameSite': sameSite,
      };

  factory BrowserCookieRecord.fromJson(Map<dynamic, dynamic> raw) {
    return BrowserCookieRecord(
      hostKey: raw['hostKey']?.toString() ?? '',
      name: raw['name']?.toString() ?? '',
      value: raw['value']?.toString() ?? '',
      path: (raw['path']?.toString().isNotEmpty ?? false)
          ? raw['path'].toString()
          : '/',
      expiresEpochMs: (raw['expiresEpochMs'] as num?)?.toInt() ?? 0,
      isSecure: raw['isSecure'] == true,
      isHttpOnly: raw['isHttpOnly'] == true,
      sameSite: (raw['sameSite'] as num?)?.toInt() ?? -1,
    );
  }
}

/// Platform abstraction for WebView cookie-jar persistence, storage cleanup,
/// and per-WebView OS Autofill / third-party cookie policy enforcement.
abstract interface class BrowserStorageBackend {
  Future<void> flushCookies();

  Future<void> configureWebViewPolicies({
    String? url,
    required bool acceptThirdPartyCookies,
    required bool enableOsAutofill,
    required bool isIncognito,
    required bool blockAllCookies,
  });

  Future<List<BrowserCookieRecord>> exportAllCookies({
    List<String> knownOrigins = const [],
  });

  Future<void> importCookies(List<BrowserCookieRecord> cookies);

  Future<void> clearSiteData(String originUrl);

  Future<void> clearAllWebData();
}

/// Production backend delegating to the native `app.theaver.messenger/browser_storage`
/// channel on Android & iOS.
class MethodChannelBrowserStorageBackend implements BrowserStorageBackend {
  static const MethodChannel _channel =
      MethodChannel('app.theaver.messenger/browser_storage');

  const MethodChannelBrowserStorageBackend();

  @override
  Future<void> flushCookies() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<bool>('flushCookies');
    } on MissingPluginException {
      // Desktop / test runtimes without native WebView storage plugin.
    } on PlatformException {
      // Ignore transient channel unavailability.
    } catch (_) {}
  }

  @override
  Future<void> configureWebViewPolicies({
    String? url,
    required bool acceptThirdPartyCookies,
    required bool enableOsAutofill,
    required bool isIncognito,
    required bool blockAllCookies,
  }) async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<bool>(
        'configureWebViewPolicies',
        <String, dynamic>{
          if (url != null) 'url': url,
          'acceptThirdPartyCookies': acceptThirdPartyCookies,
          'enableOsAutofill': enableOsAutofill,
          'isIncognito': isIncognito,
          'blockAllCookies': blockAllCookies,
        },
      );
    } on MissingPluginException {
      // No-op in headless/unit-test environments.
    } on PlatformException {
      // Ignore transient WebView initialization timing errors.
    } catch (_) {}
  }

  @override
  Future<List<BrowserCookieRecord>> exportAllCookies({
    List<String> knownOrigins = const [],
  }) async {
    if (kIsWeb) return const [];
    try {
      final raw = await _channel.invokeMethod<List<dynamic>>(
        'exportAllCookies',
        <String, dynamic>{'knownOrigins': knownOrigins},
      );
      if (raw == null || raw.isEmpty) return const [];
      return raw
          .whereType<Map>()
          .map(BrowserCookieRecord.fromJson)
          .where((c) => c.hostKey.isNotEmpty && c.name.isNotEmpty)
          .toList();
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<void> importCookies(List<BrowserCookieRecord> cookies) async {
    if (kIsWeb || cookies.isEmpty) return;
    try {
      await _channel.invokeMethod<bool>(
        'importCookies',
        <String, dynamic>{
          'cookies': cookies.map((c) => c.toJson()).toList(),
        },
      );
    } on MissingPluginException {
      // No-op on unsupported test hosts.
    } on PlatformException {
      // Ignore invalid cookie rejection on malformed entries.
    } catch (_) {}
  }

  @override
  Future<void> clearSiteData(String originUrl) async {
    if (kIsWeb || originUrl.trim().isEmpty) return;
    try {
      await _channel.invokeMethod<bool>(
        'clearSiteData',
        <String, dynamic>{'originUrl': originUrl.trim()},
      );
    } on MissingPluginException {
      // No-op on unsupported test hosts.
    } on PlatformException {
      // Ignore channel error.
    } catch (_) {}
  }

  @override
  Future<void> clearAllWebData() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<bool>('clearAllWebData');
    } on MissingPluginException {
      // No-op on unsupported test hosts.
    } on PlatformException {
      // Ignore channel error.
    } catch (_) {}
  }
}

/// Deterministic in-memory [BrowserStorageBackend] for unit and widget tests.
class InMemoryBrowserStorageBackend implements BrowserStorageBackend {
  final LinkedHashMap<String, BrowserCookieRecord> _cookies =
      LinkedHashMap<String, BrowserCookieRecord>();
  int flushCount = 0;
  int clearAllCount = 0;
  final List<String> clearedSites = <String>[];
  Map<String, dynamic>? lastConfiguredPolicy;

  List<BrowserCookieRecord> get currentCookies =>
      List<BrowserCookieRecord>.unmodifiable(_cookies.values);

  String _keyFor(BrowserCookieRecord c) =>
      '${c.hostKey.toLowerCase()}|${c.path}|${c.name}';

  void seedCookie(BrowserCookieRecord cookie) {
    _cookies[_keyFor(cookie)] = cookie;
  }

  @override
  Future<void> flushCookies() async {
    flushCount += 1;
  }

  @override
  Future<void> configureWebViewPolicies({
    String? url,
    required bool acceptThirdPartyCookies,
    required bool enableOsAutofill,
    required bool isIncognito,
    required bool blockAllCookies,
  }) async {
    lastConfiguredPolicy = <String, dynamic>{
      'url': url,
      'acceptThirdPartyCookies': acceptThirdPartyCookies,
      'enableOsAutofill': enableOsAutofill,
      'isIncognito': isIncognito,
      'blockAllCookies': blockAllCookies,
    };
  }

  @override
  Future<List<BrowserCookieRecord>> exportAllCookies({
    List<String> knownOrigins = const [],
  }) async {
    final now = DateTime.now();
    return _cookies.values
        .where((c) => !c.isExpiredAt(now))
        .toList(growable: false);
  }

  @override
  Future<void> importCookies(List<BrowserCookieRecord> cookies) async {
    final now = DateTime.now();
    for (final c in cookies) {
      if (c.isExpiredAt(now)) continue;
      _cookies[_keyFor(c)] = c;
    }
  }

  @override
  Future<void> clearSiteData(String originUrl) async {
    clearedSites.add(originUrl);
    final uri = Uri.tryParse(originUrl.trim());
    final host = uri?.host.toLowerCase().replaceFirst(RegExp(r'^\.'), '') ??
        originUrl.trim().toLowerCase();
    if (host.isEmpty) return;
    _cookies.removeWhere((_, c) {
      final hk = c.hostKey.toLowerCase();
      final hkNoDot = hk.replaceFirst(RegExp(r'^\.'), '');
      return hkNoDot == host ||
          hkNoDot.endsWith('.$host') ||
          (hk.startsWith('.') && host.endsWith(hk));
    });
  }

  @override
  Future<void> clearAllWebData() async {
    clearAllCount += 1;
    _cookies.clear();
  }
}

/// Singleton entrypoint to native WebView cookie/storage operations.
class BrowserStorageBridge {
  BrowserStorageBridge._internal();
  static final BrowserStorageBridge instance = BrowserStorageBridge._internal();

  static const BrowserStorageBackend _defaultBackend =
      MethodChannelBrowserStorageBackend();

  @visibleForTesting
  BrowserStorageBackend? debugBackendOverride;

  BrowserStorageBackend get _backend => debugBackendOverride ?? _defaultBackend;

  Future<void> flushCookies() => _backend.flushCookies();

  Future<void> configureWebViewPolicies({
    String? url,
    required bool acceptThirdPartyCookies,
    required bool enableOsAutofill,
    required bool isIncognito,
    required bool blockAllCookies,
  }) =>
      _backend.configureWebViewPolicies(
        url: url,
        acceptThirdPartyCookies: acceptThirdPartyCookies,
        enableOsAutofill: enableOsAutofill,
        isIncognito: isIncognito,
        blockAllCookies: blockAllCookies,
      );

  Future<List<BrowserCookieRecord>> exportAllCookies({
    List<String> knownOrigins = const [],
  }) =>
      _backend.exportAllCookies(knownOrigins: knownOrigins);

  Future<void> importCookies(List<BrowserCookieRecord> cookies) =>
      _backend.importCookies(cookies);

  Future<void> clearSiteData(String originUrl) =>
      _backend.clearSiteData(originUrl);

  Future<void> clearAllWebData() => _backend.clearAllWebData();
}
