import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import 'browser_data_service.dart';
import 'browser_storage_bridge.dart';
import 'browser_vault_service.dart';

/// Isolates live WebView cookie jars across multiple Theaver accounts
/// (`u_<userId>`) and transient Private Browsing («Частный доступ») tabs.
class BrowserCookieJarVault {
  BrowserCookieJarVault._internal({
    BrowserStorageBridge? bridge,
    BrowserVaultService? vaultService,
  })  : _bridge = bridge ?? BrowserStorageBridge.instance,
        _vaultService = vaultService ?? BrowserVaultService.instance;

  static final BrowserCookieJarVault instance =
      BrowserCookieJarVault._internal();

  /// Test-only isolated instance with injected dependencies.
  @visibleForTesting
  factory BrowserCookieJarVault.forTesting({
    required BrowserStorageBridge bridge,
    required BrowserVaultService vaultService,
  }) {
    return BrowserCookieJarVault._internal(
      bridge: bridge,
      vaultService: vaultService,
    );
  }

  static const String _jarPrefsPrefix = 'browser_cookie_jar_v1_u_';

  final BrowserStorageBridge _bridge;
  final BrowserVaultService _vaultService;

  final Set<String> _activeIncognitoSessionIds = <String>{};
  final Set<String> _incognitoVisitedOrigins = <String>{};
  List<BrowserCookieRecord>? _preIncognitoNormalSnapshot;

  bool get isIncognitoActive => _activeIncognitoSessionIds.isNotEmpty;
  int get activeIncognitoCount => _activeIncognitoSessionIds.length;
  List<String> get incognitoVisitedOrigins =>
      List<String>.unmodifiable(_incognitoVisitedOrigins);

  /// Exports and AES-256-GCM encrypts the outgoing account's live WebView
  /// cookies before clearing live WebView storage for an account switch.
  Future<void> snapshotAndClearForOutgoingAccount(String? fromUserId) async {
    // Never leak private-tab cookies into the user's saved account jar.
    if (isIncognitoActive) {
      await _discardIncognitoWithoutRestoring();
    }

    final uid = fromUserId?.trim() ?? '';
    if (uid.isNotEmpty) {
      final knownOrigins = BrowserDataService.instance.knownOriginsForAccount(uid);
      final cookies = await _bridge.exportAllCookies(knownOrigins: knownOrigins);
      try {
        final prefs = await SharedPreferences.getInstance();
        if (cookies.isEmpty) {
          await prefs.remove('$_jarPrefsPrefix$uid');
        } else {
          final keyBytes = await _vaultService.getOrCreateAccountMasterKey(uid);
          final plain = jsonEncode(cookies.map((c) => c.toJson()).toList());
          final encrypted = _vaultService.encryptWithMasterKey(keyBytes, plain);
          await prefs.setString('$_jarPrefsPrefix$uid', encrypted);
        }
      } catch (_) {}
    }

    await _bridge.clearAllWebData();
  }

  /// Clears any leftover live WebView state and restores [toUserId]'s encrypted
  /// cookie jar (including `HttpOnly` session cookies) when switching accounts.
  Future<void> restoreForIncomingAccount(String? toUserId) async {
    await _bridge.clearAllWebData();
    final uid = toUserId?.trim() ?? '';
    if (uid.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final payload = prefs.getString('$_jarPrefsPrefix$uid');
      if (payload == null || payload.isEmpty) return;

      final keyBytes = await _vaultService.getOrCreateAccountMasterKey(uid);
      final plain = _vaultService.decryptWithMasterKey(keyBytes, payload);
      final decoded = jsonDecode(plain);
      if (decoded is! List) return;

      final now = DateTime.now();
      final records = decoded
          .whereType<Map>()
          .map(BrowserCookieRecord.fromJson)
          .where((c) => c.hostKey.isNotEmpty && c.name.isNotEmpty && !c.isExpiredAt(now))
          .toList();
      if (records.isNotEmpty) {
        await _bridge.importCookies(records);
        await _bridge.flushCookies();
      }
    } catch (_) {}
  }

  /// Permanently deletes the stored cookie jar snapshot for [userId], and wipes
  /// live WebView storage when [isCurrentAccount] is true.
  Future<void> wipeAccountCookies(
    String userId, {
    bool isCurrentAccount = false,
  }) async {
    final uid = userId.trim();
    if (uid.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove('$_jarPrefsPrefix$uid');
      } catch (_) {}
    }
    if (isCurrentAccount) {
      _activeIncognitoSessionIds.clear();
      _incognitoVisitedOrigins.clear();
      _preIncognitoNormalSnapshot = null;
      await _bridge.clearAllWebData();
    }
  }

  /// Stashes the active normal browsing cookie jar (only on opening the first
  /// private tab) and starts with an empty cookie jar so private tabs cannot
  /// see existing signed-in normal sessions.
  Future<void> onIncognitoSessionOpened(String sessionId) async {
    final firstPrivateTab = _activeIncognitoSessionIds.isEmpty;
    _activeIncognitoSessionIds.add(sessionId);
    if (!firstPrivateTab) return;

    await _bridge.flushCookies();
    _preIncognitoNormalSnapshot = await _bridge.exportAllCookies(
      knownOrigins: BrowserDataService.instance.knownOrigins,
    );
    await _bridge.clearAllWebData();
  }

  /// Records a private-tab origin purely in ephemeral memory so all traces
  /// are wiped when the last private tab closes.
  void onIncognitoUrlVisited(String url) {
    final origin = BrowserVaultService.normalizeOrigin(url);
    if (origin != null) {
      _incognitoVisitedOrigins.add(origin);
    }
  }

  Future<void> _discardIncognitoWithoutRestoring() async {
    final origins = List<String>.from(_incognitoVisitedOrigins);
    _activeIncognitoSessionIds.clear();
    _incognitoVisitedOrigins.clear();
    for (final origin in origins) {
      await _bridge.clearSiteData(origin);
    }
    await _bridge.clearAllWebData();
    _preIncognitoNormalSnapshot = null;
  }

  /// Closes a private tab; when the last active private tab closes, wipes all
  /// incognito cookies/site storage and restores the normal cookie snapshot.
  Future<void> onIncognitoSessionClosed(String sessionId) async {
    final removed = _activeIncognitoSessionIds.remove(sessionId);
    if (!removed || _activeIncognitoSessionIds.isNotEmpty) {
      return;
    }

    final originsToWipe = List<String>.from(_incognitoVisitedOrigins);
    _incognitoVisitedOrigins.clear();

    for (final origin in originsToWipe) {
      await _bridge.clearSiteData(origin);
    }
    await _bridge.clearAllWebData();

    final normalCookies = _preIncognitoNormalSnapshot;
    _preIncognitoNormalSnapshot = null;
    if (normalCookies != null && normalCookies.isNotEmpty) {
      await _bridge.importCookies(normalCookies);
      await _bridge.flushCookies();
    }
  }

  @visibleForTesting
  void resetForTesting() {
    _activeIncognitoSessionIds.clear();
    _incognitoVisitedOrigins.clear();
    _preIncognitoNormalSnapshot = null;
  }
}
