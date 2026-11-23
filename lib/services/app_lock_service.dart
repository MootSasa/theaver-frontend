import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart'
    show ChangeNotifier, Uint8List, kDebugMode, kIsWeb;
import 'package:flutter/services.dart' show MissingPluginException;
import 'package:flutter/widgets.dart' show AppLifecycleState, WidgetsBinding;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'settings_service.dart';

/// Local, hardware-backed App Lock service storing salted PBKDF2-HMAC-SHA256
/// PIN digests on the device and tracking lifecycle transitions & lockouts.
class AppLockService extends ChangeNotifier {
  AppLockService._internal({
    FlutterSecureStorage? secureStorage,
    LocalAuthentication? localAuth,
    bool forcePrefsFallbackForTesting = false,
  })  : _secureStorage = secureStorage ?? const FlutterSecureStorage(),
        _localAuth = localAuth ?? LocalAuthentication(),
        _usePrefsFallback = forcePrefsFallbackForTesting;

  static final AppLockService instance = AppLockService._internal();

  /// Test-only constructor allowing isolated SharedPreferences-backed runs.
  factory AppLockService.forTesting() =>
      AppLockService._internal(forcePrefsFallbackForTesting: true);

  static const int pbkdf2Iterations = 20000;
  static const int _saltBytesLength = 16;
  static const int _derivedKeyLength = 32;
  static const List<int> _backoffSeconds = [15, 30, 60, 300];

  static const String _keySalt = 'theaver_app_lock_salt';
  static const String _keyHash = 'theaver_app_lock_hash';
  static const String _keyPinLength = 'theaver_app_lock_pin_len';
  static const String _keyBiometrics = 'theaver_app_lock_biometrics';
  static const String _keyAutoLock = 'theaver_app_lock_timeout';
  static const String _keyFailed = 'theaver_app_lock_failed';
  static const String _keyLockoutUntil = 'theaver_app_lock_until_ms';

  final FlutterSecureStorage _secureStorage;
  final LocalAuthentication _localAuth;
  bool _usePrefsFallback;

  bool _initialized = false;
  bool _hasPin = false;
  bool _isLocked = false;
  bool _isPrivacyShieldActive = false;
  bool _biometricsEnabled = false;
  String _autoLockTimeout = '5min';
  int _pinLength = 4;
  int _failedAttempts = 0;
  int _lockoutUntilMs = 0;
  int? _backgroundedAtMs;
  bool _isAuthenticatingBiometrics = false;

  String? _saltB64;
  String? _hashB64;

  bool get isInitialized => _initialized;
  bool get hasPin => _hasPin;
  bool get isLocked => _isLocked;
  bool get isPrivacyShieldActive =>
      _hasPin && _isPrivacyShieldActive && !_isAuthenticatingBiometrics;
  bool get biometricsEnabled => _hasPin && _biometricsEnabled && !kIsWeb;
  String get autoLockTimeout => _autoLockTimeout;
  int get pinLength => _pinLength;
  int get failedAttempts => _failedAttempts;

  Duration get lockoutRemaining {
    if (_lockoutUntilMs <= 0) return Duration.zero;
    final remainingMs =
        _lockoutUntilMs - DateTime.now().millisecondsSinceEpoch;
    if (remainingMs <= 0) return Duration.zero;
    return Duration(milliseconds: remainingMs);
  }

  bool get isLockedOut => lockoutRemaining > Duration.zero;

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

  Future<String?> _readKey(String key) async {
    if (!_usePrefsFallback && !_isFlutterTestBinding) {
      try {
        return await _secureStorage.read(key: key);
      } on MissingPluginException {
        _usePrefsFallback = true;
      } on UnimplementedError {
        _usePrefsFallback = true;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString('seclock_$key');
  }

  Future<void> _writeKey(String key, String value) async {
    if (!_usePrefsFallback && !_isFlutterTestBinding) {
      try {
        await _secureStorage.write(key: key, value: value);
        return;
      } on MissingPluginException {
        _usePrefsFallback = true;
      } on UnimplementedError {
        _usePrefsFallback = true;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('seclock_$key', value);
  }

  Future<void> _deleteKey(String key) async {
    if (!_usePrefsFallback && !_isFlutterTestBinding) {
      try {
        await _secureStorage.delete(key: key);
        return;
      } on MissingPluginException {
        _usePrefsFallback = true;
      } on UnimplementedError {
        _usePrefsFallback = true;
      }
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('seclock_$key');
  }

  /// Loads persisted PIN metadata and engages cold-start lock if enabled.
  Future<void> init({bool lockOnInitIfConfigured = true}) async {
    _saltB64 = await _readKey(_keySalt);
    _hashB64 = await _readKey(_keyHash);
    final pinLenStr = await _readKey(_keyPinLength);
    final bioStr = await _readKey(_keyBiometrics);
    final timeoutStr = await _readKey(_keyAutoLock);
    final failedStr = await _readKey(_keyFailed);
    final lockoutStr = await _readKey(_keyLockoutUntil);

    _hasPin = (_saltB64 != null &&
        _saltB64!.isNotEmpty &&
        _hashB64 != null &&
        _hashB64!.isNotEmpty);
    _pinLength = int.tryParse(pinLenStr ?? '') ?? 4;
    if (_pinLength != 4 && _pinLength != 6) {
      _pinLength = 4;
    }
    _biometricsEnabled = _hasPin && !kIsWeb && bioStr == 'true';
    _autoLockTimeout =
        (timeoutStr != null && _isValidTimeout(timeoutStr)) ? timeoutStr : '5min';
    _failedAttempts = int.tryParse(failedStr ?? '') ?? 0;
    _lockoutUntilMs = int.tryParse(lockoutStr ?? '') ?? 0;
    if (!_hasPin) {
      _isLocked = false;
    } else if (lockOnInitIfConfigured) {
      _isLocked = true;
    }
    _initialized = true;
    notifyListeners();
  }

  static bool _isValidTimeout(String val) =>
      val == 'immediately' ||
      val == '1min' ||
      val == '5min' ||
      val == '15min' ||
      val == '1hour';

  static Duration _timeoutDuration(String timeout) => switch (timeout) {
        'immediately' => Duration.zero,
        '1min' => const Duration(minutes: 1),
        '5min' => const Duration(minutes: 5),
        '15min' => const Duration(minutes: 15),
        '1hour' => const Duration(hours: 1),
        _ => const Duration(minutes: 5),
      };

  /// Tracks app lifecycle states to toggle privacy shield and auto-lock timeout.
  void onAppLifecycleChanged(AppLifecycleState state) {
    if (!_hasPin || _isAuthenticatingBiometrics) return;

    switch (state) {
      case AppLifecycleState.inactive:
        if (!_isPrivacyShieldActive) {
          _isPrivacyShieldActive = true;
          notifyListeners();
        }
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        _isPrivacyShieldActive = true;
        _backgroundedAtMs ??= DateTime.now().millisecondsSinceEpoch;
        notifyListeners();
        break;
      case AppLifecycleState.resumed:
        _isPrivacyShieldActive = false;
        final bgAt = _backgroundedAtMs;
        _backgroundedAtMs = null;
        if (!_isLocked && bgAt != null) {
          final elapsedMs = DateTime.now().millisecondsSinceEpoch - bgAt;
          if (elapsedMs >= _timeoutDuration(_autoLockTimeout).inMilliseconds) {
            _isLocked = true;
          }
        }
        notifyListeners();
        break;
      case AppLifecycleState.detached:
        break;
    }
  }

  /// Derives a PBKDF2-HMAC-SHA256 digest (RFC 2898) for the given PIN and salt.
  static Uint8List derivePbkdf2Sha256(
    String pin,
    List<int> salt, {
    int iterations = pbkdf2Iterations,
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

  bool _matchesStoredPin(String candidatePin) {
    if (!_hasPin || _saltB64 == null || _hashB64 == null) return false;
    final salt = base64Decode(_saltB64!);
    final expected = base64Decode(_hashB64!);
    final derived = derivePbkdf2Sha256(candidatePin, salt);
    return _constantTimeEquals(derived, expected);
  }

  Future<void> _recordFailure() async {
    _failedAttempts += 1;
    await _writeKey(_keyFailed, '$_failedAttempts');
    if (_failedAttempts >= 5) {
      final idx = (_failedAttempts - 5).clamp(0, _backoffSeconds.length - 1);
      final penaltySec = _backoffSeconds[idx];
      _lockoutUntilMs =
          DateTime.now().millisecondsSinceEpoch + penaltySec * 1000;
      await _writeKey(_keyLockoutUntil, '$_lockoutUntilMs');
    }
    notifyListeners();
  }

  Future<void> _resetFailures() async {
    _failedAttempts = 0;
    _lockoutUntilMs = 0;
    await _deleteKey(_keyFailed);
    await _deleteKey(_keyLockoutUntil);
  }

  /// Verifies the PIN against the stored PBKDF2 digest and unlocks if valid.
  Future<bool> verifyPin(String pin, {bool unlockOnSuccess = true}) async {
    if (!_hasPin) return false;
    if (isLockedOut) return false;

    if (_matchesStoredPin(pin)) {
      await _resetFailures();
      if (unlockOnSuccess) {
        _isLocked = false;
        _isPrivacyShieldActive = false;
        _backgroundedAtMs = null;
      }
      notifyListeners();
      return true;
    }

    await _recordFailure();
    return false;
  }

  /// Sets a new 4- or 6-digit PIN. Requires [currentPin] when replacing an existing PIN.
  Future<bool> setPin(String newPin, {String? currentPin}) async {
    if (newPin.length != 4 && newPin.length != 6) return false;
    if (!RegExp(r'^\d+$').hasMatch(newPin)) return false;

    if (_hasPin) {
      if (isLockedOut || currentPin == null || !_matchesStoredPin(currentPin)) {
        if (_hasPin && !isLockedOut) {
          await _recordFailure();
        }
        return false;
      }
      await _resetFailures();
    }

    final rng = Random.secure();
    final salt = List<int>.generate(_saltBytesLength, (_) => rng.nextInt(256));
    final digest = derivePbkdf2Sha256(newPin, salt);
    final saltB64 = base64Encode(salt);
    final hashB64 = base64Encode(digest);

    await _writeKey(_keySalt, saltB64);
    await _writeKey(_keyHash, hashB64);
    await _writeKey(_keyPinLength, '${newPin.length}');

    _saltB64 = saltB64;
    _hashB64 = hashB64;
    _pinLength = newPin.length;
    _hasPin = true;
    _isLocked = false;
    _isPrivacyShieldActive = false;
    _backgroundedAtMs = null;
    notifyListeners();
    return true;
  }

  /// Disables the local App Lock PIN after verifying [currentPin] and resets biometrics.
  Future<bool> disablePin(String currentPin) async {
    if (!_hasPin) return true;
    if (isLockedOut || !_matchesStoredPin(currentPin)) {
      if (!isLockedOut) await _recordFailure();
      return false;
    }

    await _deleteKey(_keySalt);
    await _deleteKey(_keyHash);
    await _deleteKey(_keyPinLength);
    await _deleteKey(_keyBiometrics);
    await _resetFailures();

    _saltB64 = null;
    _hashB64 = null;
    _hasPin = false;
    _isLocked = false;
    _isPrivacyShieldActive = false;
    _biometricsEnabled = false;
    _backgroundedAtMs = null;
    notifyListeners();
    return true;
  }

  Future<void> setBiometricsEnabled(bool enabled) async {
    if (!_hasPin || kIsWeb) {
      _biometricsEnabled = false;
      await _writeKey(_keyBiometrics, 'false');
      notifyListeners();
      return;
    }
    _biometricsEnabled = enabled;
    await _writeKey(_keyBiometrics, enabled ? 'true' : 'false');
    notifyListeners();
  }

  Future<void> setAutoLockTimeout(String timeout) async {
    if (!_isValidTimeout(timeout)) return;
    _autoLockTimeout = timeout;
    await _writeKey(_keyAutoLock, timeout);
    notifyListeners();
  }

  void lockNow() {
    if (!_hasPin) return;
    _isLocked = true;
    _backgroundedAtMs = null;
    notifyListeners();
  }

  Future<bool> canCheckBiometrics() async {
    if (kIsWeb) return false;
    try {
      final supported = await _localAuth.isDeviceSupported();
      final canCheck = await _localAuth.canCheckBiometrics;
      if (!supported && !canCheck) return false;
      final available = await _localAuth.getAvailableBiometrics();
      return available.isNotEmpty || supported;
    } catch (_) {
      return false;
    }
  }

  Future<bool> authenticateWithBiometrics(String localizedReason) async {
    if (kIsWeb || !_hasPin || !_biometricsEnabled) return false;
    if (_isAuthenticatingBiometrics) return false;
    _isAuthenticatingBiometrics = true;
    try {
      final authenticated = await _localAuth.authenticate(
        localizedReason: localizedReason,
        options: const AuthenticationOptions(
          biometricOnly: true,
          stickyAuth: true,
        ),
      );
      if (authenticated) {
        await _resetFailures();
        _isLocked = false;
        _isPrivacyShieldActive = false;
        _backgroundedAtMs = null;
        notifyListeners();
      }
      return authenticated;
    } catch (_) {
      return false;
    } finally {
      _isAuthenticatingBiometrics = false;
    }
  }

  AppLockSettings toAppLockSettings() => AppLockSettings(
        hasPin: _hasPin,
        biometricsEnabled: biometricsEnabled,
        autoLockTimeout: _autoLockTimeout,
      );
}
