import 'dart:convert';
import 'dart:math';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show Uint8List, kDebugMode, kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

import '../l10n/app_localizations.dart';
import '../utils/safari_url_safety.dart';
import '../widgets/browser/browser_vault_pin_sheet.dart';
import 'account_manager.dart';
import 'app_lock_service.dart';
import 'browser_site_settings_service.dart';

class _VaultPinRecord {
  final String saltB64;
  final String hashB64;
  final int pinLength;
  final int failedAttempts;
  final int lockoutUntilMs;

  const _VaultPinRecord({
    required this.saltB64,
    required this.hashB64,
    required this.pinLength,
    required this.failedAttempts,
    required this.lockoutUntilMs,
  });

  Map<String, dynamic> toJson() => <String, dynamic>{
        'saltB64': saltB64,
        'hashB64': hashB64,
        'pinLength': pinLength,
        'failedAttempts': failedAttempts,
        'lockoutUntilMs': lockoutUntilMs,
      };

  static _VaultPinRecord? tryFromJsonString(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final saltB64 = decoded['saltB64']?.toString() ?? '';
      final hashB64 = decoded['hashB64']?.toString() ?? '';
      if (saltB64.isEmpty || hashB64.isEmpty) return null;
      final rawPinLen = int.tryParse(decoded['pinLength']?.toString() ?? '') ?? 4;
      final pinLength = rawPinLen.clamp(4, 8);
      final failedAttempts =
          int.tryParse(decoded['failedAttempts']?.toString() ?? '') ?? 0;
      final lockoutUntilMs =
          int.tryParse(decoded['lockoutUntilMs']?.toString() ?? '') ?? 0;
      return _VaultPinRecord(
        saltB64: saltB64,
        hashB64: hashB64,
        pinLength: pinLength,
        failedAttempts: failedAttempts < 0 ? 0 : failedAttempts,
        lockoutUntilMs: lockoutUntilMs < 0 ? 0 : lockoutUntilMs,
      );
    } catch (_) {
      return null;
    }
  }

  _VaultPinRecord copyWith({
    int? failedAttempts,
    int? lockoutUntilMs,
  }) {
    return _VaultPinRecord(
      saltB64: saltB64,
      hashB64: hashB64,
      pinLength: pinLength,
      failedAttempts: failedAttempts ?? this.failedAttempts,
      lockoutUntilMs: lockoutUntilMs ?? this.lockoutUntilMs,
    );
  }
}

/// Biometric / PIN security gate protecting saved browser credentials, payment
/// cards, and sensitive vault access during autofill and settings management.
///
/// Supports a short-lived (`20 s`) unlock grant scoped strictly to a single
/// normalized `origin` (`scheme://host[:port]`) for two-step login flows,
/// invalidated immediately when the app goes to background or changes origin.
class BrowserVaultAuthGate with WidgetsBindingObserver {
  BrowserVaultAuthGate._internal({
    AppLockService? appLockService,
    LocalAuthentication? localAuth,
    FlutterSecureStorage? secureStorage,
  })  : _appLock = appLockService ?? AppLockService.instance,
        _localAuth = localAuth ?? LocalAuthentication(),
        _secureStorage = secureStorage ?? const FlutterSecureStorage() {
    try {
      WidgetsBinding.instance.addObserver(this);
      _observerAttached = true;
    } catch (_) {
      // Headless pure-Dart test isolates may not initialize WidgetsBinding yet.
    }
  }

  static final BrowserVaultAuthGate instance = BrowserVaultAuthGate._internal();

  /// Test-only isolated instance with injected dependencies.
  @visibleForTesting
  factory BrowserVaultAuthGate.forTesting({
    AppLockService? appLockService,
    LocalAuthentication? localAuth,
    FlutterSecureStorage? secureStorage,
    Map<String, String>? pinStore,
    String? userId,
  }) =>
      BrowserVaultAuthGate._internal(
        appLockService: appLockService,
        localAuth: localAuth,
        secureStorage: secureStorage,
      )
        ..debugPinStoreOverride = pinStore
        ..debugUserIdOverride = userId;

  static const Duration sameOriginGrantDuration = Duration(seconds: 20);
  static const String _vaultPinKeyPrefix = 'browser_vault_pin_v1_u_';
  static const int _pbkdf2Iterations = 20000;
  static const int _saltBytesLength = 16;
  static const int _derivedKeyLength = 32;
  static const List<int> _vaultPinBackoffSeconds = <int>[30, 60, 120, 300];

  AppLockService _appLock;
  LocalAuthentication _localAuth;
  final FlutterSecureStorage _secureStorage;
  final Random _secureRandom = Random.secure();
  final Map<String, String> _inMemoryPinStore = <String, String>{};
  final Map<String, _VaultPinRecord> _pinStateCache =
      <String, _VaultPinRecord>{};
  bool _observerAttached = false;

  String? _grantedOrigin;
  DateTime? _grantExpiresAt;

  @visibleForTesting
  Future<bool> Function(
    BuildContext context,
    String reason,
    String? originScope,
  )? debugAuthOverride;

  @visibleForTesting
  Map<String, String>? debugPinStoreOverride;

  @visibleForTesting
  String? debugUserIdOverride;

  @visibleForTesting
  AppLockService get debugAppLock => _appLock;

  @visibleForTesting
  set debugAppLock(AppLockService value) => _appLock = value;

  @visibleForTesting
  LocalAuthentication get debugLocalAuth => _localAuth;

  @visibleForTesting
  set debugLocalAuth(LocalAuthentication value) => _localAuth = value;

  @visibleForTesting
  DateTime Function()? debugClockOverride;

  DateTime _now() => debugClockOverride?.call() ?? DateTime.now();

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

  String _resolveUid(String? userId) {
    final clean = userId?.trim();
    if (clean != null && clean.isNotEmpty) return clean;
    return _activeUid;
  }

  String _pinKeyFor(String uid) => '$_vaultPinKeyPrefix$uid';

  Duration get vaultPinLockoutRemaining {
    final record = _pinStateCache[_activeUid];
    if (record == null || record.lockoutUntilMs <= 0) return Duration.zero;
    final remainingMs = record.lockoutUntilMs - _now().millisecondsSinceEpoch;
    if (remainingMs <= 0) return Duration.zero;
    return Duration(milliseconds: remainingMs);
  }

  bool get isVaultPinLockedOut => vaultPinLockoutRemaining > Duration.zero;

  int get vaultPinLength => _pinStateCache[_activeUid]?.pinLength ?? 4;

  static bool get _isFlutterTestBinding {
    if (!kDebugMode) return false;
    try {
      final name = WidgetsBinding.instance.runtimeType.toString();
      return name.contains('TestWidgetsFlutterBinding') ||
          name.contains('AutomatedTestWidgetsFlutterBinding');
    } catch (_) {
      return false;
    }
  }

  Future<String?> _readPinRaw(String uid) async {
    final key = _pinKeyFor(uid);
    final override = debugPinStoreOverride;
    if (override != null) return override[key];
    if (_isFlutterTestBinding) {
      return _inMemoryPinStore[key];
    }
    try {
      return await _secureStorage.read(key: key);
    } on MissingPluginException {
      return _inMemoryPinStore[key];
    } on UnimplementedError {
      return _inMemoryPinStore[key];
    }
  }

  Future<void> _writePinRaw(String uid, String value) async {
    final key = _pinKeyFor(uid);
    final override = debugPinStoreOverride;
    if (override != null) {
      override[key] = value;
      return;
    }
    if (_isFlutterTestBinding) {
      _inMemoryPinStore[key] = value;
      return;
    }
    try {
      await _secureStorage.write(key: key, value: value);
    } on MissingPluginException {
      _inMemoryPinStore[key] = value;
    } on UnimplementedError {
      _inMemoryPinStore[key] = value;
    }
  }

  Future<void> _deletePinRaw(String uid) async {
    final key = _pinKeyFor(uid);
    final override = debugPinStoreOverride;
    if (override != null) {
      override.remove(key);
      return;
    }
    if (_isFlutterTestBinding) {
      _inMemoryPinStore.remove(key);
      return;
    }
    try {
      await _secureStorage.delete(key: key);
    } on MissingPluginException {
      _inMemoryPinStore.remove(key);
    } on UnimplementedError {
      _inMemoryPinStore.remove(key);
    }
  }

  static Uint8List _derivePbkdf2Sha256(
    String pin,
    List<int> salt, {
    int iterations = _pbkdf2Iterations,
    int keyLength = _derivedKeyLength,
  }) {
    final passwordBytes = utf8.encode(pin);
    final hmac = Hmac(sha256, passwordBytes);
    const blockLen = 32;
    final numBlocks = (keyLength + blockLen - 1) ~/ blockLen;
    final out = Uint8List(numBlocks * blockLen);

    for (var blockIndex = 1; blockIndex <= numBlocks; blockIndex++) {
      final initialInput = Uint8List(salt.length + 4)
        ..setRange(0, salt.length, salt)
        ..[salt.length] = (blockIndex >> 24) & 0xff
        ..[salt.length + 1] = (blockIndex >> 16) & 0xff
        ..[salt.length + 2] = (blockIndex >> 8) & 0xff
        ..[salt.length + 3] = blockIndex & 0xff;

      var u = Uint8List.fromList(hmac.convert(initialInput).bytes);
      final t = Uint8List.fromList(u);

      for (var iter = 1; iter < iterations; iter++) {
        u = Uint8List.fromList(hmac.convert(u).bytes);
        for (var j = 0; j < blockLen; j++) {
          t[j] ^= u[j];
        }
      }
      out.setRange((blockIndex - 1) * blockLen, blockIndex * blockLen, t);
    }

    return Uint8List.sublistView(out, 0, keyLength);
  }

  static bool _constantTimeEquals(List<int> a, List<int> b) {
    if (a.length != b.length) return false;
    var diff = 0;
    for (var i = 0; i < a.length; i++) {
      diff |= a[i] ^ b[i];
    }
    return diff == 0;
  }

  Future<_VaultPinRecord?> _loadPinRecord(String uid) async {
    final raw = await _readPinRaw(uid);
    final record = _VaultPinRecord.tryFromJsonString(raw);
    if (record == null) {
      _pinStateCache.remove(uid);
      return null;
    }
    _pinStateCache[uid] = record;
    return record;
  }

  Future<void> _savePinRecord(String uid, _VaultPinRecord record) async {
    _pinStateCache[uid] = record;
    await _writePinRaw(uid, jsonEncode(record.toJson()));
  }

  Future<bool> hasVaultPin({String? userId}) async {
    final uid = _resolveUid(userId);
    final record = await _loadPinRecord(uid);
    return record != null;
  }

  Future<void> setVaultPin(String pin, {String? userId}) async {
    final clean = pin.trim();
    if (!RegExp(r'^\d{4,8}$').hasMatch(clean)) {
      throw ArgumentError('Vault PIN must be 4 to 8 digits');
    }
    final uid = _resolveUid(userId);
    final salt = List<int>.generate(
      _saltBytesLength,
      (_) => _secureRandom.nextInt(256),
    );
    final digest = _derivePbkdf2Sha256(clean, salt);
    final record = _VaultPinRecord(
      saltB64: base64Encode(salt),
      hashB64: base64Encode(digest),
      pinLength: clean.length,
      failedAttempts: 0,
      lockoutUntilMs: 0,
    );
    await _savePinRecord(uid, record);
  }

  Future<bool> verifyVaultPin(String pin, {String? userId}) async {
    final uid = _resolveUid(userId);
    final record = await _loadPinRecord(uid);
    if (record == null) return false;

    final nowMs = _now().millisecondsSinceEpoch;
    if (record.lockoutUntilMs > nowMs) {
      return false;
    }

    try {
      final salt = base64Decode(record.saltB64);
      final expected = base64Decode(record.hashB64);
      final derived = _derivePbkdf2Sha256(pin.trim(), salt);
      if (_constantTimeEquals(derived, expected)) {
        if (record.failedAttempts != 0 || record.lockoutUntilMs != 0) {
          await _savePinRecord(
            uid,
            record.copyWith(failedAttempts: 0, lockoutUntilMs: 0),
          );
        }
        return true;
      }
    } catch (_) {}

    final nextFailed = record.failedAttempts + 1;
    int nextLockoutUntilMs = 0;
    if (nextFailed >= 5) {
      final idx =
          (nextFailed - 5).clamp(0, _vaultPinBackoffSeconds.length - 1);
      final penaltySec = _vaultPinBackoffSeconds[idx];
      nextLockoutUntilMs = nowMs + penaltySec * 1000;
    }
    await _savePinRecord(
      uid,
      record.copyWith(
        failedAttempts: nextFailed,
        lockoutUntilMs: nextLockoutUntilMs,
      ),
    );
    return false;
  }

  Future<void> clearVaultPin({String? userId}) async {
    final uid = _resolveUid(userId);
    _pinStateCache.remove(uid);
    await _deletePinRaw(uid);
  }

  Future<void> clearVaultPinForAccount(String userId) async {
    final clean = userId.trim();
    if (clean.isEmpty) return;
    await clearVaultPin(userId: clean);
  }

  void _ensureObserverAttached() {
    if (_observerAttached) return;
    try {
      WidgetsBinding.instance.addObserver(this);
      _observerAttached = true;
    } catch (_) {}
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      invalidateGrant();
    }
  }

  /// Normalizes [rawUrlOrOrigin] to `scheme://asciiHost[:nonDefaultPort]`.
  static String? normalizeOriginScope(String? rawUrlOrOrigin) {
    final clean = rawUrlOrOrigin?.trim() ?? '';
    if (clean.isEmpty) return null;
    final uri = Uri.tryParse(clean);
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') return null;
    final analyzed = SafariUrlSafetyAnalyzer.analyzeUrl(clean);
    final host = analyzed.asciiHost.isNotEmpty
        ? analyzed.asciiHost.toLowerCase()
        : uri.host.trim().toLowerCase();
    if (host.isEmpty) return null;
    final String portSuffix;
    if (uri.hasPort &&
        !((scheme == 'https' && uri.port == 443) ||
            (scheme == 'http' && uri.port == 80))) {
      portSuffix = ':${uri.port}';
    } else {
      portSuffix = '';
    }
    return '$scheme://$host$portSuffix';
  }

  /// Immediately clears any cached two-step login unlock grant.
  void invalidateGrant() {
    _grantedOrigin = null;
    _grantExpiresAt = null;
  }

  /// Clears any active grant if navigating to a different normalized origin.
  void onOriginChanged(String? nextUrlOrOrigin) {
    if (_grantedOrigin == null) return;
    final nextOrigin = normalizeOriginScope(nextUrlOrOrigin);
    if (nextOrigin != _grantedOrigin) {
      invalidateGrant();
    }
  }

  bool hasActiveGrantFor(String? rawUrlOrOrigin) {
    final normalized = normalizeOriginScope(rawUrlOrOrigin);
    if (normalized == null || _grantedOrigin == null || _grantExpiresAt == null) {
      return false;
    }
    if (normalized != _grantedOrigin) return false;
    return _now().isBefore(_grantExpiresAt!);
  }

  void _recordGrant(String? normalizedOrigin) {
    if (normalizedOrigin == null) return;
    _grantedOrigin = normalizedOrigin;
    _grantExpiresAt = _now().add(sameOriginGrantDuration);
  }

  /// Authenticates the user before decrypting/autofilling saved passwords,
  /// payment cards, or opening sensitive vault sections.
  ///
  /// When [originScope] is non-null and [forceChallenge] is `false`, a
  /// successful authentication unlocks the vault for that exact
  /// `scheme://host[:port]` for 20 seconds so two-step login pages do not
  /// prompt twice.
  Future<bool> authenticate(
    BuildContext context, {
    required String reason,
    String? originScope,
    bool forceChallenge = false,
  }) async {
    _ensureObserverAttached();
    await BrowserSiteSettingsService.instance.ensureLoaded();
    if (!forceChallenge &&
        !BrowserSiteSettingsService.instance.requireAuthForVaultAccess) {
      return true;
    }

    final String? normalizedOrigin = normalizeOriginScope(originScope);
    if (!forceChallenge &&
        normalizedOrigin != null &&
        hasActiveGrantFor(normalizedOrigin)) {
      return true;
    }
    if (originScope != null && normalizedOrigin != _grantedOrigin) {
      invalidateGrant();
    }

    final String effectiveReason = reason.trim().isNotEmpty
        ? reason
        : AppLocalizations.trStatic(
            'browser_vault_auth_reason_default',
            'Подтвердите доступ к хранилищу браузера',
          );

    if (debugAuthOverride != null) {
      if (!context.mounted) return false;
      final ok = await debugAuthOverride!(
        context,
        effectiveReason,
        normalizedOrigin,
      );
      if (ok) {
        _recordGrant(normalizedOrigin);
      }
      return ok;
    }

    if (!_appLock.isInitialized) {
      await _appLock.init(lockOnInitIfConfigured: false);
    }

    // 1. App Lock PIN (+ optional biometrics).
    if (_appLock.hasPin) {
      if (!kIsWeb && _appLock.biometricsEnabled) {
        try {
          final bioOk = await _localAuth.authenticate(
            localizedReason: effectiveReason,
            options: const AuthenticationOptions(
              biometricOnly: true,
              stickyAuth: true,
            ),
          );
          if (bioOk) {
            _recordGrant(normalizedOrigin);
            return true;
          }
        } catch (_) {
          // Fall back cleanly to the in-app PIN verification modal sheet.
        }
      }

      if (!context.mounted) return false;
      final pinOk = await showBrowserVaultPinSheet(
        context,
        reason: effectiveReason,
        appLockService: _appLock,
        useVaultPin: false,
      );
      if (pinOk) {
        _recordGrant(normalizedOrigin);
        return true;
      }
      return false;
    }

    // 2. Per-account autonomous Vault PIN (+ optional OS biometrics).
    if (await hasVaultPin()) {
      if (!kIsWeb) {
        try {
          final bool canBio = await _localAuth.canCheckBiometrics;
          final bool supported = await _localAuth.isDeviceSupported();
          if (canBio && supported) {
            final bioOk = await _localAuth.authenticate(
              localizedReason: effectiveReason,
              options: const AuthenticationOptions(
                biometricOnly: true,
                stickyAuth: true,
              ),
            );
            if (bioOk) {
              _recordGrant(normalizedOrigin);
              return true;
            }
          }
        } catch (_) {
          // Fall back cleanly to the in-app Vault PIN modal sheet.
        }
      }

      if (!context.mounted) return false;
      final vaultPinOk = await showBrowserVaultPinSheet(
        context,
        reason: effectiveReason,
        authGate: this,
        useVaultPin: true,
      );
      if (vaultPinOk) {
        _recordGrant(normalizedOrigin);
        return true;
      }
      return false;
    }

    // 3. OS device authentication (device passcode/pattern/biometrics).
    if (!kIsWeb) {
      try {
        final bool supported = await _localAuth.isDeviceSupported();
        if (supported) {
          final bool osOk = await _localAuth.authenticate(
            localizedReason: effectiveReason,
            options: const AuthenticationOptions(
              biometricOnly: false,
              stickyAuth: true,
            ),
          );
          if (osOk) {
            _recordGrant(normalizedOrigin);
            return true;
          }
          return false;
        }
      } catch (_) {}
    }

    // 4. Unprotected fallback: offer creating a Vault PIN or disabling auth gate.
    if (!context.mounted) return false;
    final BrowserVaultUnprotectedAction action =
        await showBrowserVaultUnprotectedChoiceSheet(
      context,
      reason: effectiveReason,
      allowSkipAuth: !forceChallenge,
    );
    if (action == BrowserVaultUnprotectedAction.setVaultPin) {
      if (!context.mounted) return false;
      final bool created = await showBrowserVaultCreatePinSheet(
        context,
        authGate: this,
      );
      if (created) {
        _recordGrant(normalizedOrigin);
        return true;
      }
      return false;
    }
    if (!forceChallenge && action == BrowserVaultUnprotectedAction.continueWithoutPin) {
      await BrowserSiteSettingsService.instance
          .setRequireAuthForVaultAccess(false);
      return true;
    }
    return false;
  }

  @visibleForTesting
  void resetForTesting() {
    invalidateGrant();
    debugAuthOverride = null;
    debugClockOverride = null;
    debugPinStoreOverride = null;
    debugUserIdOverride = null;
    _inMemoryPinStore.clear();
    _pinStateCache.clear();
  }
}
