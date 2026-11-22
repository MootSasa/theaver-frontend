import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';

import 'browser_data_service.dart';
import 'browser_storage_bridge.dart';
import 'browser_vault_service.dart';

/// Isolates live WebView cookie jars across multiple Theaver accounts
/// (`u_<userId>`).
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

  /// Exports and AES-256-GCM encrypts the outgoing account's live WebView
  /// cookies before clearing live WebView storage for an account switch.
  Future<void> snapshotAndClearForOutgoingAccount(String? fromUserId) async {
    final uid = fromUserId?.trim() ?? '';
    if (uid.isNotEmpty) {
      await BrowserDataService.instance.ensureLoaded(scopeOverride: uid);
      final knownOrigins = BrowserDataService.instance.knownOriginsForAccount(uid);
      final cookies = await _bridge.exportAllCookies(knownOrigins: knownOrigins);
      try {
        final prefs = await SharedPreferences.getInstance();
        if (cookies.isEmpty) {
          if (knownOrigins.isNotEmpty) {
            await prefs.remove('$_jarPrefsPrefix$uid');
          }
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

  /// Explicitly deletes the stored encrypted cookie jar snapshot for [userId].
  Future<void> clearAccountJar(String userId) async {
    final uid = userId.trim();
    if (uid.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('$_jarPrefsPrefix$uid');
    } catch (_) {}
  }

  /// Permanently deletes the stored cookie jar snapshot for [userId], and wipes
  /// live WebView storage when [isCurrentAccount] is true.
  Future<void> wipeAccountCookies(
    String userId, {
    bool isCurrentAccount = false,
  }) async {
    await clearAccountJar(userId);
    if (isCurrentAccount) {
      await _bridge.clearAllWebData();
    }
  }

  @visibleForTesting
  void resetForTesting() {}
}
