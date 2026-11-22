import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';

import '../utils/safari_url_safety.dart';
import '../widgets/browser/browser_vault_pin_sheet.dart';
import 'app_lock_service.dart';
import 'glass_toast_service.dart';

/// Biometric / PIN security gate protecting saved browser credentials during
/// website autofill and settings vault access.
///
/// Supports a short-lived (`20 s`) unlock grant scoped strictly to a single
/// normalized `origin` (`scheme://host[:port]`) for two-step login flows,
/// invalidated immediately when the app goes to background or changes origin.
class BrowserVaultAuthGate with WidgetsBindingObserver {
  BrowserVaultAuthGate._internal({
    AppLockService? appLockService,
    LocalAuthentication? localAuth,
  })  : _appLock = appLockService ?? AppLockService.instance,
        _localAuth = localAuth ?? LocalAuthentication() {
    try {
      WidgetsBinding.instance.addObserver(this);
    } catch (_) {
      // Headless pure-Dart test isolates may not initialize WidgetsBinding yet.
    }
  }

  static final BrowserVaultAuthGate instance = BrowserVaultAuthGate._internal();

  /// Test-only isolated instance with injected [AppLockService] / [LocalAuthentication].
  @visibleForTesting
  factory BrowserVaultAuthGate.forTesting({
    AppLockService? appLockService,
    LocalAuthentication? localAuth,
  }) =>
      BrowserVaultAuthGate._internal(
        appLockService: appLockService,
        localAuth: localAuth,
      );

  static const Duration sameOriginGrantDuration = Duration(seconds: 20);

  AppLockService _appLock;
  LocalAuthentication _localAuth;
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

  /// Authenticates the user before decrypting/autofilling saved passwords.
  ///
  /// When [originScope] is non-null, a successful authentication unlocks the
  /// vault for that exact `scheme://host[:port]` for 20 seconds so two-step
  /// login pages (username screen -> password screen) do not prompt twice.
  Future<bool> authenticate(
    BuildContext context, {
    required String reason,
    String? originScope,
  }) async {
    _ensureObserverAttached();
    final String? normalizedOrigin = normalizeOriginScope(originScope);
    if (normalizedOrigin != null && hasActiveGrantFor(normalizedOrigin)) {
      return true;
    }
    if (originScope != null && normalizedOrigin != _grantedOrigin) {
      invalidateGrant();
    }

    if (debugAuthOverride != null) {
      final ok = await debugAuthOverride!(context, reason, normalizedOrigin);
      if (ok) {
        _recordGrant(normalizedOrigin);
      }
      return ok;
    }

    if (!_appLock.isInitialized) {
      await _appLock.init(lockOnInitIfConfigured: false);
    }

    if (_appLock.hasPin) {
      if (!kIsWeb && _appLock.biometricsEnabled) {
        try {
          final bioOk = await _localAuth.authenticate(
            localizedReason: reason,
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
        reason: reason,
        appLockService: _appLock,
      );
      if (pinOk) {
        _recordGrant(normalizedOrigin);
        return true;
      }
      return false;
    }

    if (!kIsWeb) {
      try {
        final bool supported = await _localAuth.isDeviceSupported();
        if (supported) {
          final bool osOk = await _localAuth.authenticate(
            localizedReason: reason,
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

    if (context.mounted) {
      GlassToastService().show(
        context,
        'Задайте PIN-код блокировки в настройках или системный пароль экрана',
        icon: Icons.lock_outline_rounded,
      );
    }
    return false;
  }

  @visibleForTesting
  void resetForTesting() {
    invalidateGrant();
    debugAuthOverride = null;
    debugClockOverride = null;
  }
}
