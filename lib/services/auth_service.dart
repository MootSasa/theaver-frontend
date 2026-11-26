import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as path;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_config.dart';
import '../models/avatar_editor_models.dart';
import 'account_manager.dart';
import 'avatar_sync_service.dart';
import 'browser_cookie_jar_vault.dart';
import 'browser_data_service.dart';
import 'browser_site_settings_service.dart';
import 'browser_vault_auth_gate.dart';
import 'browser_vault_service.dart';
import 'cache_service.dart';
import 'contacts_service.dart';
import 'database/app_database.dart';
import 'deep_link_service.dart';
import 'draft_service.dart';
import 'websocket_service.dart';
import 'notification_service.dart';
import 'session_bootstrap_coordinator.dart';
import 'settings_service.dart';
import '../screens/auth/login_screen.dart';
import '../widgets/bot/mini_app_webview_sheet.dart';
import '../utils/image_utils.dart';
import '../utils/swipe_back_route.dart';
import '../l10n/app_localizations.dart';

String _solveProofOfWorkSync(String challenge) {
  final trimmed = challenge.trim();
  final parts = trimmed.split('.');
  final diff = (parts.length >= 2 ? (int.tryParse(parts[1]) ?? 18) : 18).clamp(
    1,
    28,
  );
  final prefix = '$trimmed:';
  var nonce = 0;
  while (true) {
    final digest = sha256.convert(utf8.encode('$prefix$nonce')).bytes;
    var leadingZeros = 0;
    for (final b in digest) {
      if (b == 0) {
        leadingZeros += 8;
      } else {
        var v = b;
        var lz = 0;
        if ((v & 0xF0) == 0) {
          lz += 4;
          v <<= 4;
        }
        if ((v & 0xC0) == 0) {
          lz += 2;
          v <<= 2;
        }
        if ((v & 0x80) == 0) {
          lz += 1;
        }
        leadingZeros += lz;
        break;
      }
    }
    if (leadingZeros >= diff) {
      return nonce.toString();
    }
    nonce++;
  }
}

/// Solves a server-issued PoW challenge inside a worker isolate on native platforms.
Future<String> computeRegistrationProofOfWork(String challenge) async {
  if (kIsWeb) {
    return _solveProofOfWorkSync(challenge);
  }
  return Isolate.run(() => _solveProofOfWorkSync(challenge));
}

/// Configured OAuth2/OIDC provider returned by `/api/auth/providers`.
class AuthProviderInfo {
  final String id;
  final String displayName;
  final bool recommendedForRegion;

  const AuthProviderInfo({
    required this.id,
    required this.displayName,
    this.recommendedForRegion = false,
  });

  factory AuthProviderInfo.fromJson(Map<String, dynamic> json) {
    return AuthProviderInfo(
      id: (json['id'] ?? '').toString().trim().toLowerCase(),
      displayName: (json['display_name'] ?? '').toString().trim(),
      recommendedForRegion: json['recommended_for_region'] == true,
    );
  }
}

/// Region, phone verification, PoW, and configured OAuth settings returned by `/api/auth/providers`.
class AuthProvidersConfig {
  final String countryCode;
  final String phoneDialCode;
  final String recommendedLanguage;
  final String phoneVerificationMode;
  final int powDifficultyBits;
  final List<AuthProviderInfo> providers;

  const AuthProvidersConfig({
    this.countryCode = 'RU',
    this.phoneDialCode = '7',
    this.recommendedLanguage = 'ru',
    this.phoneVerificationMode = 'disabled',
    this.powDifficultyBits = 18,
    this.providers = const [],
  });

  factory AuthProvidersConfig.fromJson(Map<String, dynamic> json) {
    final rawList = json['providers'];
    final parsedProviders = rawList is List
        ? rawList
              .whereType<Map>()
              .map(
                (item) =>
                    AuthProviderInfo.fromJson(Map<String, dynamic>.from(item)),
              )
              .where((p) => p.id.isNotEmpty)
              .toList()
        : const <AuthProviderInfo>[];

    return AuthProvidersConfig(
      countryCode: (json['country_code'] ?? 'RU').toString().trim().toUpperCase(),
      phoneDialCode: (json['phone_dial_code'] ?? '7').toString().trim(),
      recommendedLanguage:
          (json['recommended_language'] ?? 'ru').toString().trim().toLowerCase(),
      phoneVerificationMode:
          (json['phone_verification_mode'] ?? 'disabled').toString().trim(),
      powDifficultyBits: (json['pow_difficulty_bits'] as num?)?.toInt() ?? 18,
      providers: parsedProviders,
    );
  }
}

/// Prefill payload yielded when OAuth returns `needs_registration`.
class OAuthRegistrationPrefill {
  final String provider;
  final String providerName;
  final String oauthRegistrationToken;
  final String email;
  final bool emailVerified;
  final String phone;
  final bool phoneVerified;
  final String firstName;
  final String lastName;
  final String suggestedUsername;
  final String externalAvatarUrl;

  const OAuthRegistrationPrefill({
    required this.provider,
    this.providerName = '',
    required this.oauthRegistrationToken,
    this.email = '',
    this.emailVerified = false,
    this.phone = '',
    this.phoneVerified = false,
    this.firstName = '',
    this.lastName = '',
    this.suggestedUsername = '',
    this.externalAvatarUrl = '',
  });

  factory OAuthRegistrationPrefill.fromStatusPayload(Map<String, dynamic> json) {
    final prefill = json['prefill'] is Map
        ? Map<String, dynamic>.from(json['prefill'] as Map)
        : const <String, dynamic>{};
    return OAuthRegistrationPrefill(
      provider: (json['provider'] ?? '').toString().trim().toLowerCase(),
      providerName: (json['provider_name'] ?? '').toString().trim(),
      oauthRegistrationToken:
          (json['oauth_registration_token'] ?? '').toString().trim(),
      email: (prefill['email'] ?? '').toString().trim(),
      emailVerified: prefill['email_verified'] == true,
      phone: (prefill['phone'] ?? '').toString().trim(),
      phoneVerified: prefill['phone_verified'] == true,
      firstName: (prefill['first_name'] ?? '').toString().trim(),
      lastName: (prefill['last_name'] ?? '').toString().trim(),
      suggestedUsername: (prefill['suggested_username'] ?? '').toString().trim(),
      externalAvatarUrl:
          (prefill['external_avatar_url'] ?? '').toString().trim(),
    );
  }
}

/// AuthService handles authentication operations including login, logout,
/// and token management. Integrates with AccountManager for multi-account support.
class AuthService {
  // Base URL is now managed by AppConfig

  /// Registers a new user and activates their session via [SessionBootstrapCoordinator].
  static Future<Map<String, dynamic>> register({
    required String username,
    required String email,
    required String password,
    String displayName = '',
    String? firstName,
    String? lastName,
    String? phone,
    String? countryCode,
    String? registrationTicket,
    String? oauthRegistrationToken,
    String? locale,
    BuildContext? context,
  }) async {
    try {
      final accountManager = AccountManager();
      final deviceInfo = await accountManager.getCurrentDeviceInfo();
      final deviceId =
          accountManager.currentDeviceId ??
          'device_${DateTime.now().millisecondsSinceEpoch}';

      final trimmedFirst = (firstName ?? '').trim();
      final trimmedLast = (lastName ?? '').trim();
      final trimmedDisplay = displayName.trim();
      final resolvedFirst = trimmedFirst.isNotEmpty
          ? trimmedFirst
          : trimmedDisplay;
      final resolvedDisplay = trimmedDisplay.isNotEmpty
          ? trimmedDisplay
          : [resolvedFirst, trimmedLast]
                .where((part) => part.isNotEmpty)
                .join(' ')
                .trim();

      final bodyMap = <String, dynamic>{
        'username': username.trim(),
        'email': email.trim(),
        'password': password,
        'display_name': resolvedDisplay,
        if (resolvedFirst.isNotEmpty) 'first_name': resolvedFirst,
        if (trimmedLast.isNotEmpty) 'last_name': trimmedLast,
        if (phone != null && phone.trim().isNotEmpty) 'phone': phone.trim(),
        if (countryCode != null && countryCode.trim().isNotEmpty)
          'country_code': countryCode.trim().toUpperCase(),
        if (registrationTicket != null && registrationTicket.trim().isNotEmpty)
          'registration_ticket': registrationTicket.trim(),
        if (oauthRegistrationToken != null &&
            oauthRegistrationToken.trim().isNotEmpty)
          'oauth_registration_token': oauthRegistrationToken.trim(),
        'locale': await _currentLocaleCode(locale),
        'device_id': deviceId,
        'device_name': deviceInfo.deviceName,
        'device_type': deviceInfo.deviceType.name,
        'os_name': deviceInfo.os,
        'os_version': deviceInfo.osVersion,
        'app_version': AppConfig.currentVersion,
      };

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/auth/register'),
        headers: await _buildDeviceHeaders(overrideDeviceId: deviceId),
        body: jsonEncode(bodyMap),
      );

      final data = _tryDecodeMap(response.body);
      if ((response.statusCode == 200 || response.statusCode == 201) &&
          data['success'] == true) {
        final authToken = data['auth_token']?.toString() ?? '';
        final userId = data['user_id']?.toString() ?? '';
        final userMap = data['user'] is Map
            ? Map<String, dynamic>.from(data['user'] as Map)
            : null;
        await SessionBootstrapCoordinator.bootstrapAuthenticatedSession(
          token: authToken,
          userId: userId,
          userMap: userMap,
          fallbackUsername: username.trim(),
          fallbackEmail: email.trim(),
          fallbackPhone: phone?.trim(),
          fallbackFirstName: resolvedFirst,
          fallbackLastName: trimmedLast,
          fallbackDisplayName: resolvedDisplay,
          context: (context != null && context.mounted) ? context : null,
        );
        return {
          'success': true,
          'authToken': authToken,
          'userId': userId,
          'user': userMap,
          'message': data['message'] ?? 'Registration successful',
        };
      }
      return {
        'success': false,
        'error': data['error']?.toString(),
        'message': _getErrorMessage(
          response.statusCode,
          data['message']?.toString(),
        ),
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  /// Logs in a user with `@username`, email, or E.164/local phone identifier and password.
  static Future<Map<String, dynamic>> login({
    String? usernameOrEmail,
    String? identifier,
    required String password,
    String? countryCode,
    String? twoFactorPassword,
    String? recoveryCode,
    BuildContext? context,
  }) async {
    try {
      final resolvedIdentifier = (identifier ?? usernameOrEmail ?? '').trim();
      final accountManager = AccountManager();
      final deviceInfo = await accountManager.getCurrentDeviceInfo();
      final deviceId =
          accountManager.currentDeviceId ??
          'device_${DateTime.now().millisecondsSinceEpoch}';

      final bodyMap = <String, dynamic>{
        'identifier': resolvedIdentifier,
        'username_or_email': resolvedIdentifier,
        'password': password,
        if (countryCode != null && countryCode.trim().isNotEmpty)
          'country_code': countryCode.trim().toUpperCase(),
        'device_id': deviceId,
        'device_name': deviceInfo.deviceName,
        'device_type': deviceInfo.deviceType.name,
        'os_name': deviceInfo.os,
        'os_version': deviceInfo.osVersion,
        'app_version': AppConfig.currentVersion,
      };
      if (twoFactorPassword != null && twoFactorPassword.isNotEmpty) {
        bodyMap['two_factor_password'] = twoFactorPassword;
      }
      if (recoveryCode != null && recoveryCode.isNotEmpty) {
        bodyMap['recovery_code'] = recoveryCode;
      }

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/auth/login'),
        headers: await _buildDeviceHeaders(overrideDeviceId: deviceId),
        body: jsonEncode(bodyMap),
      );

      final Map<String, dynamic> data = _tryDecodeMap(response.body);
      if (response.statusCode == 200) {
        if (data['success'] == true) {
          final authToken = data['auth_token']?.toString() ?? '';
          final userId = data['user_id']?.toString() ?? '';
          final userMap = data['user'] is Map
              ? Map<String, dynamic>.from(data['user'] as Map)
              : null;
          await SessionBootstrapCoordinator.bootstrapAuthenticatedSession(
            token: authToken,
            userId: userId,
            userMap: userMap,
            context: (context != null && context.mounted) ? context : null,
          );
          return {
            'success': true,
            'authToken': authToken,
            'userId': userId,
            'message': data['message'] ?? 'Login successful',
            'user': userMap ?? data['user'],
          };
        } else {
          return {
            'success': false,
            'requires_2fa': data['requires_2fa'] == true,
            'temp_2fa_token': data['temp_2fa_token'],
            'has_recovery_email': data['has_recovery_email'] == true,
            'error': data['error'],
            'message': data['message'] ?? 'Login failed',
          };
        }
      } else {
        return {
          'success': false,
          'requires_2fa': data['requires_2fa'] == true,
          'temp_2fa_token': data['temp_2fa_token'],
          'has_recovery_email': data['has_recovery_email'] == true,
          'error': data['error'],
          'message': data['requires_2fa'] == true
              ? (data['message'] ?? 'Two-factor authentication password required')
              : _getErrorMessage(
                  response.statusCode,
                  data['message']?.toString(),
                ),
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  /// Logs out the current user by invalidating the session and cleaning local data.
  static Future<void> logout() async {
    try {
      MiniAppSessionController.instance.closeAllMinimized();

      // 1. Disconnect WebSocket immediately
      try {
        WebSocketService().disconnect();
      } catch (_) {}

      // Grab token & current account info before wiping
      final token = await getToken();
      final accountManager = AccountManager();
      final currentUserId = accountManager.currentAccount?.userId;

      BrowserVaultAuthGate.instance.invalidateGrant();
      if (currentUserId != null && currentUserId.isNotEmpty) {
        await BrowserVaultService.instance.wipeAccountVault(currentUserId);
        await BrowserSiteSettingsService.instance.wipeAccount(currentUserId);
        await BrowserDataService.instance.wipeAccountData(currentUserId);
      }
      await BrowserCookieJarVault.instance.wipeAccountCookies(
        currentUserId ?? '',
        isCurrentAccount: true,
      );

      // 2. Clear current account & contact cache immediately
      try {
        await ContactsService.clearCache(clearDisk: true);
      } catch (e) {
        debugPrint('Logout: error clearing ContactsService cache: $e');
      }
      if (currentUserId != null) {
        await accountManager.removeAccount(currentUserId);
      } else {
        await accountManager.clearCurrentAccount();
      }

      // 3. Clear local SQLite database, user-scoped permanent files, and media cache
      if (currentUserId != null) {
        await CacheService().clearUserPermanentData(currentUserId);
      }
      await DraftService().clearAllLocalDrafts(userId: currentUserId);
      try {
        if (accountManager.accounts.isEmpty) {
          await AppDatabase.deleteAllDatabases();
          await CacheService().clearCache();
          await CacheService().clearAllPermanentUserDirs();
        } else if (currentUserId != null) {
          await AppDatabase.removeUserDatabase(currentUserId);
        } else {
          await AppDatabase().clearAllData();
        }
      } catch (e) {
        debugPrint('Logout: error clearing local storage: $e');
      }

      // 4. Remote network cleanup in background with short timeout so it never blocks UI
      if (token != null) {
        NotificationService()
            .unregisterPushToken()
            .timeout(const Duration(seconds: 2))
            .catchError((e) {
          debugPrint('Logout: error unregistering push token: $e');
        });

        http.post(
          Uri.parse('${AppConfig.baseUrl}/api/auth/logout'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        ).timeout(const Duration(seconds: 2)).catchError((e) {
          debugPrint('Logout: error notifying server: $e');
          return http.Response('', 500);
        });
      }
    } catch (e) {
      debugPrint('Logout error: $e');
    }
  }

  /// Refreshes the JWT token for the current active account.
  /// Calls POST /api/auth/refresh and updates local storage.
  /// Returns true if successful, false otherwise.
  static Future<bool> refreshToken() async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) return false;

      final accountManager = AccountManager();
      final currentUserId = accountManager.currentAccount?.userId;
      final deviceId = accountManager.currentDeviceId ?? '';

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/auth/refresh'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
          if (deviceId.isNotEmpty) 'X-Device-ID': deviceId,
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true && data['auth_token'] != null) {
          final newToken = data['auth_token'] as String;
          if (currentUserId != null) {
            await accountManager.updateAccountToken(currentUserId, newToken);
          }
          final prefs = await SharedPreferences.getInstance();
          await prefs.setString('auth_token', newToken);
          debugPrint('AuthService: Token refreshed successfully (TTL: ${data['ttl_days']} days)');
          return true;
        }
      } else if (response.statusCode == 401) {
        debugPrint('AuthService: Refresh token rejected with 401 (session expired)');
        await handleRemoteSessionTerminated(reason: 'session_expired');
        return false;
      }
    } catch (e) {
      debugPrint('AuthService: Error refreshing token: $e');
    }
    return false;
  }

  static bool _isTerminating = false;

  /// Handles remote or expired termination of the current session
  static Future<void> handleRemoteSessionTerminated({String? reason}) async {
    if (_isTerminating) return;
    _isTerminating = true;

    try {
      debugPrint('AuthService: Session terminated. Reason: $reason');
      MiniAppSessionController.instance.closeAllMinimized();

      // 1. Disconnect WebSocket
      try {
        WebSocketService().disconnect();
      } catch (_) {}

      // 2. Clear local SQLite database and media cache
      try {
        await AppDatabase().clearAllData();
      } catch (e) {
        debugPrint('Error clearing AppDatabase on session termination: $e');
      }
      try {
        await CacheService().clearCache();
      } catch (e) {
        debugPrint('Error clearing CacheService on session termination: $e');
      }

      // 3. Clear current account credentials & contact cache locally
      try {
        await ContactsService.clearCache(clearDisk: true);
      } catch (e) {
        debugPrint('Error clearing ContactsService on session termination: $e');
      }
      final accountManager = AccountManager();
      final terminatedAccount = accountManager.currentAccount;
      final currentUserId = terminatedAccount?.userId;
      if (currentUserId != null) {
        await accountManager.removeAccount(currentUserId);
      }

      // 4. Navigation to LoginScreen & notification
      final nav = DeepLinkService().navigatorKey.currentState;
      final context = DeepLinkService().navigatorKey.currentContext;

      final isExpired = reason == 'session_expired' || (reason?.contains('expired') ?? false);

      if (nav != null) {
        nav.pushAndRemoveUntil(
          SwipeBackPageRoute(builder: (_) => const LoginScreen()),
          (route) => false,
        );
      }

      if (context != null && context.mounted) {
        final message = isExpired
            ? context.l10n.translate('session_expired')
            : context.l10n.translate('session_terminated_remotely');
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.white),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    message,
                    style: const TextStyle(fontWeight: FontWeight.w500, color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.red[700],
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    } catch (e) {
      debugPrint('Error in handleRemoteSessionTerminated: $e');
    } finally {
      _isTerminating = false;
    }
  }

  /// Logout from a specific device session.
  static Future<bool> logoutDevice(String deviceId) async {
    final res = await logoutDeviceWithResult(deviceId);
    return res['success'] == true;
  }

  /// Logout from a specific device session with structured status/error details.
  static Future<Map<String, dynamic>> logoutDeviceWithResult(
    String deviceId, {
    String? sessionId,
  }) async {
    try {
      final token = await getToken();
      if (token == null) return {'success': false, 'error': 'unauthorized'};

      final headers = await _buildDeviceHeaders(token: token);
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/auth/logout-device'),
        headers: headers,
        body: jsonEncode({
          if (deviceId.isNotEmpty) 'device_id': deviceId,
          if (sessionId != null && sessionId.isNotEmpty) 'session_id': sessionId,
        }),
      );

      final data = _tryDecodeMap(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        await AccountManager().removeDeviceSession(
          deviceId.isNotEmpty ? deviceId : (sessionId ?? ''),
        );
        return {'success': true};
      }
      return {
        'success': false,
        'statusCode': response.statusCode,
        'error': data['error'],
        'message': data['message']?.toString() ?? 'Failed to terminate session',
      };
    } catch (e) {
      debugPrint('Logout device error: $e');
      return {'success': false, 'error': 'network_error', 'message': e.toString()};
    }
  }

  /// Terminate all other sessions except the current device
  static Future<bool> terminateOtherSessions(String currentDeviceId) async {
    final res = await terminateOtherSessionsWithResult(currentDeviceId);
    return res['success'] == true;
  }

  /// Terminate all other sessions with structured quarantine/error details.
  static Future<Map<String, dynamic>> terminateOtherSessionsWithResult(
    String currentDeviceId,
  ) async {
    try {
      final token = await getToken();
      if (token == null) return {'success': false, 'error': 'unauthorized'};

      final headers = await _buildDeviceHeaders(
        token: token,
        overrideDeviceId: currentDeviceId.isNotEmpty ? currentDeviceId : null,
      );
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/auth/terminate-others'),
        headers: headers,
        body: jsonEncode({'current_device_id': currentDeviceId}),
      );

      final data = _tryDecodeMap(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true};
      }
      return {
        'success': false,
        'statusCode': response.statusCode,
        'error': data['error'],
        'message': data['message']?.toString() ?? 'Failed to terminate sessions',
      };
    } catch (e) {
      debugPrint('Terminate others error: $e');
      return {'success': false, 'error': 'network_error', 'message': e.toString()};
    }
  }

  /// Get sessions auto-termination TTL (in days).
  static Future<int> getSessionsTTL() async {
    try {
      final token = await getToken();
      if (token == null) return 180;

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/auth/sessions/ttl'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return data['ttl_days'] as int? ?? 180;
      }
    } catch (e) {
      debugPrint('getSessionsTTL error: $e');
    }
    return 180;
  }

  /// Update sessions auto-termination TTL (in days).
  static Future<bool> setSessionsTTL(int ttlDays) async {
    try {
      final token = await getToken();
      if (token == null) return false;

      final response = await http.put(
        Uri.parse('${AppConfig.baseUrl}/api/auth/sessions/ttl'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'ttl_days': ttlDays}),
      );

      if (response.statusCode == 200) {
        try {
          final data = jsonDecode(response.body);
          if (data['auth_token'] != null && (data['auth_token'] as String).isNotEmpty) {
            final newToken = data['auth_token'] as String;
            final accountManager = AccountManager();
            final currentUserId = accountManager.currentAccount?.userId;
            if (currentUserId != null) {
              await accountManager.updateAccountToken(currentUserId, newToken);
            }
            final prefs = await SharedPreferences.getInstance();
            await prefs.setString('auth_token', newToken);
            debugPrint('AuthService: Saved updated token after TTL change to $ttlDays days');
          }
        } catch (_) {}
        return true;
      }
      return false;
    } catch (e) {
      debugPrint('setSessionsTTL error: $e');
      return false;
    }
  }

  /// Initiates password recovery for a given email.
  static Future<Map<String, dynamic>> recoverPassword({
    required String email,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/auth/recover'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'email': email}),
      );

      final data = jsonDecode(response.body);
      return {
        'success': data['success'] == true,
        'message': data['message'] ?? 'Recovery email sent if account exists',
      };
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  /// Gets the stored auth token from AccountManager.
  static Future<String?> getToken() async {
    final accountManager = AccountManager();
    return accountManager.currentAccount?.token;
  }

  /// Gets the stored user ID from AccountManager.
  static Future<String?> getUserId() async {
    final accountManager = AccountManager();
    return accountManager.currentAccount?.userId;
  }

  /// Checks if the user is logged in.
  static Future<bool> isLoggedIn() async {
    final accountManager = AccountManager();
    return accountManager.hasSavedAccount;
  }

  /// Gets the current user's profile data from the server.
  /// Returns a map containing user data on success.
  static Future<Map<String, dynamic>> getCurrentUser() async {
    try {
      final token = await getToken();
      if (token == null) {
        return {
          'success': false,
          'message': 'Not authenticated',
        };
      }

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/user/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          // Update account profile
          final accountManager = AccountManager();
          final currentAcc = accountManager.currentAccount;
          if (currentAcc != null) {
            final userJson = data['user'] as Map<String, dynamic>?;
            final birthdayStr = userJson?['birthday'] as String?;
            final parsedBirthday = birthdayStr != null ? DateTime.tryParse(birthdayStr) : null;
            await accountManager.updateAccountProfile(
              currentAcc.userId,
              username: userJson?['username'],
              displayName: userJson?['display_name'],
              avatarUrl: userJson?['avatar_url'],
              name: userJson?['name'],
              surname: userJson?['surname'],
              email: userJson?['email'],
              emailVerified: userJson?['email_verified'] as bool?,
              phone: userJson?['phone'],
              bio: userJson?['bio'],
              birthday: parsedBirthday,
              clearBirthday: userJson != null &&
                  userJson.containsKey('birthday') &&
                  parsedBirthday == null,
            );
          }
          return {
            'success': true,
            'user': data['user'],
          };
        } else {
          return {
            'success': false,
            'message': data['message'] ?? 'Failed to get user data',
          };
        }
      } else {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': _getErrorMessage(response.statusCode, data['message']),
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  /// Gets another user's public profile by user ID.
  /// Returns a map containing user data on success.
  /// Only public fields are returned (no email or phone).
  static Future<Map<String, dynamic>> getUserProfile(String userId) async {
    try {
      final token = await getToken();
      if (token == null) {
        return {
          'success': false,
          'message': 'Not authenticated',
        };
      }

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/user/profile/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          return {
            'success': true,
            'user': data['user'],
          };
        } else {
          return {
            'success': false,
            'message': data['message'] ?? 'Failed to get user profile',
          };
        }
      } else {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': _getErrorMessage(response.statusCode, data['message']),
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  /// Gets all active sessions for the current user.
  static Future<Map<String, dynamic>> getActiveSessions() async {
    try {
      final token = await getToken();
      if (token == null) {
        return {
          'success': false,
          'message': 'Not authenticated',
        };
      }

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/auth/sessions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        return {
          'success': true,
          'sessions': data['sessions'] ?? [],
        };
      } else {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': _getErrorMessage(response.statusCode, data['message']),
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  // Private helpers

  /// Validates an arbitrary auth token without changing the active account.
  /// Returns {'status': 'valid'|'expired'|'offline', 'user': ...}.
  static Future<Map<String, dynamic>> verifyToken(String token) async {
    if (token.isEmpty) {
      return {'status': 'expired'};
    }
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/user/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      ).timeout(const Duration(seconds: 6));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body) as Map<String, dynamic>;
        if (data['success'] == true) {
          return {'status': 'valid', 'user': data['user']};
        }
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        return {'status': 'expired'};
      }
      return {'status': 'offline'};
    } catch (_) {
      return {'status': 'offline'};
    }
  }

  /// Upload avatar image to server.
    /// Returns a map containing the avatar URL on success.
    /// Uses MinIO storage for avatar upload.
    static Future<Map<String, dynamic>> uploadAvatar(
      String filePath, {
      Uint8List? bytes,
      String? fileName,
      String? avatarCrop,
    }) async {
      try {
        debugPrint('[uploadAvatar] Step 1: Getting token...');
        final token = await getToken();
        if (token == null) {
          debugPrint('[uploadAvatar] Step 1-fail: token is null');
          return {
            'success': false,
            'message': 'Not authenticated',
          };
        }
        debugPrint('[uploadAvatar] Step 1-ok: token obtained (length=${token.length})');

        final cleanFilePath = stripAvatarCropFragment(filePath) ?? filePath;
        final resolvedFileName = (fileName != null && fileName.trim().isNotEmpty)
            ? path.basename(fileName.trim())
            : (cleanFilePath.isNotEmpty ? path.basename(cleanFilePath) : 'avatar.jpg');

        // Use the new MinIO-based avatar upload endpoint
        debugPrint('[uploadAvatar] Step 3: Creating MultipartRequest to ${AppConfig.baseUrl}/api/files/upload-avatar');
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('${AppConfig.baseUrl}/api/files/upload-avatar'),
        );

        request.headers['Authorization'] = 'Bearer $token';
        final cleanCrop = avatarCrop?.trim() ??
            AvatarCropSpec.split(filePath).crop?.toCompactParam();
        if (cleanCrop != null && cleanCrop.isNotEmpty) {
          request.fields['avatar_crop'] = cleanCrop;
        }
        if (bytes != null) {
          debugPrint('[uploadAvatar] Step 4: Adding MultipartFile fromBytes (${bytes.length} bytes)...');
          request.files.add(
            http.MultipartFile.fromBytes(
              'avatar',
              bytes,
              filename: resolvedFileName,
            ),
          );
        } else {
          debugPrint('[uploadAvatar] Step 2: Checking file exists at $cleanFilePath');
          final file = File(cleanFilePath);
          if (!await file.exists()) {
            debugPrint('[uploadAvatar] Step 2-fail: file not found');
            return {
              'success': false,
              'message': 'File not found',
            };
          }
          final fileSize = await file.length();
          debugPrint('[uploadAvatar] Step 2-ok: file exists, size=$fileSize bytes');

          debugPrint('[uploadAvatar] Step 4: Adding MultipartFile fromPath...');
          request.files.add(
            await http.MultipartFile.fromPath(
              'avatar',
              cleanFilePath,
              filename: resolvedFileName,
            ),
          );
        }
        debugPrint('[uploadAvatar] Step 4-ok: MultipartFile added');
  
        debugPrint('[uploadAvatar] Step 5: Sending request (timeout=60s)...');
        final streamedResponse = await request.send().timeout(
          const Duration(seconds: 60),
          onTimeout: () {
            debugPrint('[uploadAvatar] Step 5-timeout: request timed out');
            throw Exception('Upload timed out after 60 seconds');
          },
        );
        debugPrint('[uploadAvatar] Step 5-ok: Streamed response received, statusCode=${streamedResponse.statusCode}');
  
        debugPrint('[uploadAvatar] Step 6: Reading response from stream (timeout=30s)...');
        final response = await http.Response.fromStream(streamedResponse)
            .timeout(const Duration(seconds: 30), onTimeout: () {
          debugPrint('[uploadAvatar] Step 6-timeout: reading stream timed out');
          throw Exception('Reading response timed out after 30 seconds');
        });
        debugPrint('[uploadAvatar] Step 6-ok: Response body length=${response.body.length}, statusCode=${response.statusCode}');
  
        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          debugPrint('[uploadAvatar] Response data: $data');
          if (data['success'] == true) {
            // Update account avatar URL
            final accountManager = AccountManager();
            if (accountManager.currentAccount != null) {
              await accountManager.updateAccountProfile(
                accountManager.currentAccount!.userId,
                avatarUrl: data['avatar_url'],
              );
            }
            return {
              'success': true,
              'avatar_url': data['avatar_url'],
              'avatar_id': data['avatar_id'],  // Pass through avatar_id from backend
              'message': data['message'] ?? 'Avatar uploaded successfully',
            };
          } else {
            return {
              'success': false,
              'message': data['message'] ?? 'Failed to upload avatar',
            };
          }
        } else {
          final data = jsonDecode(response.body);
          return {
            'success': false,
            'message': _getErrorMessage(response.statusCode, data['message']),
          };
        }
      } catch (e) {
        return {
          'success': false,
          'message': 'Network error: ${e.toString()}',
        };
      }
    }

    /// Upload wallpaper image to server.
    /// Returns a map containing the wallpaper URL on success.
    static Future<Map<String, dynamic>> uploadWallpaper(String filePath) async {
      try {
        final token = await getToken();
        if (token == null) {
          return {
            'success': false,
            'message': 'Not authenticated',
          };
        }

        final file = File(filePath);
        if (!await file.exists()) {
          return {
            'success': false,
            'message': 'File not found',
          };
        }

        final fileName = path.basename(filePath);
        final request = http.MultipartRequest(
          'POST',
          Uri.parse('${AppConfig.baseUrl}/api/user/wallpaper'),
        );

        request.headers['Authorization'] = 'Bearer $token';
        request.files.add(
          await http.MultipartFile.fromPath(
            'wallpaper',
            filePath,
            filename: fileName,
          ),
        );

        final streamedResponse = await request.send().timeout(
          const Duration(seconds: 60),
        );

        final response = await http.Response.fromStream(streamedResponse)
            .timeout(const Duration(seconds: 30));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            return {
              'success': true,
              'wallpaper_url': data['wallpaper_url'],
              'message': data['message'] ?? 'Wallpaper uploaded successfully',
            };
          } else {
            return {
              'success': false,
              'message': data['message'] ?? 'Failed to upload wallpaper',
            };
          }
        } else {
          final data = jsonDecode(response.body);
          return {
            'success': false,
            'message': _getErrorMessage(response.statusCode, data['message']),
          };
        }
      } catch (e) {
        return {
          'success': false,
          'message': 'Network error: ${e.toString()}',
        };
      }
    }

    /// Delete custom wallpaper from server.
    static Future<Map<String, dynamic>> deleteWallpaper() async {
      try {
        final token = await getToken();
        if (token == null) {
          return {'success': false, 'message': 'Not authenticated'};
        }

        final response = await http.delete(
          Uri.parse('${AppConfig.baseUrl}/api/user/wallpaper'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );

        final data = jsonDecode(response.body);
        if (response.statusCode == 200 && data['success'] == true) {
          return {'success': true, 'message': 'Wallpaper deleted'};
        } else {
          return {'success': false, 'message': data['message'] ?? 'Failed to delete wallpaper'};
        }
      } catch (e) {
        return {'success': false, 'message': 'Network error: ${e.toString()}'};
      }
    }

    /// Get current user appearance settings including wallpaper_url.
    static Future<Map<String, dynamic>> getAppearance() async {
      try {
        final token = await getToken();
        if (token == null) {
          return {'success': false, 'message': 'Not authenticated'};
        }

        final response = await http.get(
          Uri.parse('${AppConfig.baseUrl}/api/user/appearance'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
        );

        final data = jsonDecode(response.body);
        if (response.statusCode == 200 && data['success'] == true) {
          return {'success': true, 'appearance': data['appearance']};
        }
        return {'success': false, 'message': data['message'] ?? 'Failed to get appearance'};
      } catch (e) {
        return {'success': false, 'message': 'Network error: ${e.toString()}'};
      }
    }
  
    /// Updates the user profile with new data.
  /// Returns a map containing success status and message.
  static Future<Map<String, dynamic>> updateProfile({
    required String name,
    required String surname,
    required String username,
    required String email,
    required String phone,
    String? avatarUrl,
    String? bio,
    DateTime? birthday,
    bool requiresServerValidation = false,
  }) async {
    final accountManager = AccountManager();
    final currentAcc = accountManager.currentAccount;
    final birthdayIso = birthday?.toIso8601String().split('T').first;

    // Проверяем, изменились ли никнейм или телефон относительно текущего сохраненного профиля
    final isUsernameChanged = currentAcc != null &&
        username.trim() != (currentAcc.username ?? '').trim();
    final isPhoneChanged = currentAcc != null &&
        phone.trim() != (currentAcc.phone ?? '').trim();

    final isUniqueFieldChanged =
        requiresServerValidation || isUsernameChanged || isPhoneChanged;

    // Если изменяются УНИКАЛЬНЫЕ поля (никнейм/телефон), ТРЕБУЕТСЯ прямое подтверждение сервера!
    if (isUniqueFieldChanged) {
      try {
        final token = await getToken();
        if (token == null) {
          return {
            'success': false,
            'requiresServer': true,
            'message': 'Not authenticated on server',
          };
        }

        final response = await http.put(
          Uri.parse('${AppConfig.baseUrl}/api/user/profile'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: jsonEncode({
            'name': name,
            'surname': surname,
            'username': username,
            'email': email,
            'phone': phone,
            if (avatarUrl != null) 'avatar_url': avatarUrl,
            if (bio != null) 'bio': bio,
            if (birthdayIso != null) 'birthday': birthdayIso,
            if (birthday == null) 'clear_birthday': true,
          }),
        ).timeout(const Duration(seconds: 5));

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            // Сервер подтвердил свободу уникальных полей и успешно обновил профиль
            if (currentAcc != null) {
              await accountManager.updateAccountProfile(
                currentAcc.userId,
                username: username,
                displayName: '$name $surname',
                avatarUrl: avatarUrl,
                name: name,
                surname: surname,
                email: email,
                phone: phone,
                bio: bio,
                birthday: birthday,
                clearBirthday: birthday == null,
                clearBio: bio != null && bio.isEmpty,
              );
            }
            await accountManager.clearPendingProfileSync();
            return {
              'success': true,
              'synced': true,
              'message': data['message'] ?? 'Profile updated successfully',
              'user': data['user'],
            };
          } else {
            return {
              'success': false,
              'message': data['message'] ?? 'Failed to update profile',
            };
          }
        } else {
          final data = jsonDecode(response.body);
          return {
            'success': false,
            'message': _getErrorMessage(response.statusCode, data['message']),
          };
        }
      } catch (e) {
        // Запрос не удался/офлайн: изменение никнейма или телефона ЗАПРЕЩЕНО без подтверждения сервера!
        return {
          'success': false,
          'requiresServer': true,
          'message':
              'Server connection required to verify username/phone availability',
        };
      }
    }

    // Если изменялись только обычные поля (Имя, Фамилия, Био и т.д.):
    // 1. Гарантированно сохраняем локально и применяем изменения сразу
    if (currentAcc != null) {
      await accountManager.updateAccountProfile(
        currentAcc.userId,
        username: username,
        displayName: '$name $surname',
        avatarUrl: avatarUrl,
        name: name,
        surname: surname,
        email: email,
        phone: phone,
        bio: bio,
        birthday: birthday,
        clearBirthday: birthday == null,
        clearBio: bio != null && bio.isEmpty,
      );
    }

    try {
      final token = await getToken();
      if (token == null) {
        await accountManager.savePendingProfileSync({
          'name': name,
          'surname': surname,
          'username': username,
          'email': email,
          'phone': phone,
          if (bio != null) 'bio': bio,
          if (birthdayIso != null) 'birthday': birthdayIso,
          if (birthday == null) 'clear_birthday': true,
        });
        return {
          'success': true,
          'synced': false,
          'message': 'Not authenticated on server',
        };
      }

      final response = await http.put(
        Uri.parse('${AppConfig.baseUrl}/api/user/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'name': name,
          'surname': surname,
          'username': username,
          'email': email,
          'phone': phone,
          if (avatarUrl != null) 'avatar_url': avatarUrl,
          if (bio != null) 'bio': bio,
          if (birthdayIso != null) 'birthday': birthdayIso,
          if (birthday == null) 'clear_birthday': true,
        }),
      ).timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          await accountManager.clearPendingProfileSync();
          return {
            'success': true,
            'synced': true,
            'message': data['message'] ?? 'Profile updated successfully',
            'user': data['user'],
          };
        }
      }

      await accountManager.savePendingProfileSync({
        'name': name,
        'surname': surname,
        'username': username,
        'email': email,
        'phone': phone,
        if (bio != null) 'bio': bio,
        if (birthdayIso != null) 'birthday': birthdayIso,
      });

      return {
        'success': true,
        'synced': false,
        'message': 'Server error. Profile saved locally.',
      };
    } catch (e) {
      await accountManager.savePendingProfileSync({
        'name': name,
        'surname': surname,
        'username': username,
        'email': email,
        'phone': phone,
        if (bio != null) 'bio': bio,
        if (birthdayIso != null) 'birthday': birthdayIso,
      });

      return {
        'success': true,
        'synced': false,
        'message': 'Network offline. Saved locally.',
      };
    }
  }

  /// Deletes the user's primary avatar by removing the newest one.
  /// Uses the new DELETE /api/user/avatars/:avatarId endpoint.
  /// Returns a map containing success status and message.
  static Future<Map<String, dynamic>> deleteAvatar({int? avatarId}) async {
    try {
      final token = await getToken();
      if (token == null) {
        return {
          'success': false,
          'message': 'Not authenticated',
        };
      }

      if (avatarId != null) {
        // Delete specific avatar by ID
        final response = await http.delete(
          Uri.parse('${AppConfig.baseUrl}/api/user/avatars/$avatarId'),
          headers: {
            'Authorization': 'Bearer $token',
          },
        );

        if (response.statusCode == 200) {
          final data = jsonDecode(response.body);
          if (data['success'] == true) {
            // Refresh profile to get updated avatar_url
            final accountManager = AccountManager();
            if (accountManager.currentAccount != null) {
              await accountManager.updateAccountProfile(
                accountManager.currentAccount!.userId,
                avatarUrl: '',
              );
            }
            return {
              'success': true,
              'message': data['message'] ?? 'Avatar deleted successfully',
            };
          } else {
            return {
              'success': false,
              'message': data['message'] ?? 'Failed to delete avatar',
            };
          }
        } else {
          final data = jsonDecode(response.body);
          return {
            'success': false,
            'message': _getErrorMessage(response.statusCode, data['message']),
          };
        }
      }

      // Fallback: old method — clear avatar_url via profile update
      final response = await http.put(
        Uri.parse('${AppConfig.baseUrl}/api/user/profile'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'avatar_url': '',
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        if (data['success'] == true) {
          // Update account profile to remove avatar
          final accountManager = AccountManager();
          if (accountManager.currentAccount != null) {
            await accountManager.updateAccountProfile(
              accountManager.currentAccount!.userId,
              avatarUrl: '',
            );
          }
          return {
            'success': true,
            'message': data['message'] ?? 'Avatar deleted successfully',
          };
        } else {
          return {
            'success': false,
            'message': data['message'] ?? 'Failed to delete avatar',
          };
        }
      } else {
        final data = jsonDecode(response.body);
        return {
          'success': false,
          'message': _getErrorMessage(response.statusCode, data['message']),
        };
      }
    } catch (e) {
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
      };
    }
  }

  static Map<String, dynamic> _tryDecodeMap(String body) {
    try {
      if (body.trim().isEmpty) return {};
      final decoded = jsonDecode(body);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {}
    return {};
  }

  /// Strips non-ASCII / control characters so `package:http` never throws
  /// `FormatException` when OS or host device names contain smart quotes or UTF-8.
  static String _sanitizeHeaderValue(String? value, {String fallback = ''}) {
    if (value == null || value.isEmpty) return fallback;
    final cleaned = value
        .replaceAll('\u2019', "'")
        .replaceAll('\u2018', "'")
        .replaceAll('\u201C', '"')
        .replaceAll('\u201D', '"')
        .replaceAll('\r', ' ')
        .replaceAll('\n', ' ')
        .replaceAll(RegExp(r'[^\x20-\x7E]'), '')
        .trim();
    return cleaned.isEmpty ? fallback : cleaned;
  }

  static Future<Map<String, String>> _buildDeviceHeaders({
    String? token,
    String? overrideDeviceId,
    Map<String, String>? extra,
  }) async {
    final accountManager = AccountManager();
    final deviceInfo = await accountManager.getCurrentDeviceInfo();
    final deviceId = overrideDeviceId ??
        accountManager.currentDeviceId ??
        'device_${DateTime.now().millisecondsSinceEpoch}';
    final locale = await _currentLocaleCode();
    return {
      'Content-Type': 'application/json',
      if (token != null && token.isNotEmpty) 'Authorization': 'Bearer $token',
      'X-Device-ID': _sanitizeHeaderValue(deviceId, fallback: 'device_unknown'),
      'X-Device-Name': _sanitizeHeaderValue(
        deviceInfo.deviceName,
        fallback: 'Theaver Device',
      ),
      'X-Device-Type': _sanitizeHeaderValue(
        deviceInfo.deviceType.name,
        fallback: 'unknown',
      ),
      'X-OS-Name': _sanitizeHeaderValue(deviceInfo.os, fallback: 'Unknown'),
      'X-OS-Version': _sanitizeHeaderValue(deviceInfo.osVersion, fallback: '0'),
      'X-App-Version': _sanitizeHeaderValue(
        AppConfig.currentVersion,
        fallback: '1.0.0',
      ),
      'X-App-Locale': _sanitizeHeaderValue(locale, fallback: 'en'),
      if (extra != null) ...extra,
    };
  }

  static Future<Map<String, String>> _buildDeviceBodyFields({String? locale}) async {
    final deviceInfo = await AccountManager().getCurrentDeviceInfo();
    return {
      'device_name': deviceInfo.deviceName,
      'device_type': deviceInfo.deviceType.name,
      'os_name': deviceInfo.os,
      'os_version': deviceInfo.osVersion,
      'app_version': AppConfig.currentVersion,
      'locale': await _currentLocaleCode(locale),
    };
  }

  static Future<String> _currentLocaleCode([String? explicit]) async {
    if (explicit != null && explicit.isNotEmpty) return explicit;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('selected_language');
      if (saved != null && saved.trim().isNotEmpty) {
        return saved.trim();
      }
      return LocaleProvider.resolveSystemLanguageCode();
    } catch (_) {
      return LocaleProvider.resolveSystemLanguageCode();
    }
  }

  // ============ Email OTP Verification & Change ============

  static Future<Map<String, dynamic>> sendEmailVerifyCode({String? locale}) async {
    try {
      final token = await getToken();
      if (token == null) return {'success': false, 'error': 'unauthorized'};
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/user/email/verify/send-code'),
        headers: await _buildDeviceHeaders(token: token),
        body: jsonEncode({'locale': await _currentLocaleCode(locale)}),
      );
      final data = _tryDecodeMap(response.body);
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'cooldown_seconds': data['cooldown_seconds'] ?? data['retry_after'] ?? 0,
        'error': data['error'],
        'message': data['message']?.toString(),
      };
    } catch (e) {
      return {'success': false, 'error': 'network_error', 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> confirmEmailVerify(String code) async {
    try {
      final token = await getToken();
      if (token == null) return {'success': false, 'error': 'unauthorized'};
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/user/email/verify/confirm'),
        headers: await _buildDeviceHeaders(token: token),
        body: jsonEncode({'code': code.trim()}),
      );
      final data = _tryDecodeMap(response.body);
      final ok = response.statusCode == 200 && data['success'] == true;
      if (ok) {
        final newEmail = data['email']?.toString();
        final accountManager = AccountManager();
        final cur = accountManager.currentAccount;
        if (cur != null) {
          await accountManager.updateAccountProfile(
            cur.userId,
            email: newEmail,
            emailVerified: true,
          );
        }
        final cached = SettingsService().userProfile;
        if (cached != null && newEmail != null && newEmail.isNotEmpty) {
          await SettingsService().saveUserProfile(cached.copyWith(email: newEmail));
        }
      }
      return {
        'success': ok,
        'email': data['email']?.toString(),
        'email_verified': data['email_verified'] == true,
        'error': data['error'],
        'message': data['message']?.toString(),
      };
    } catch (e) {
      return {'success': false, 'error': 'network_error', 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> requestEmailChange({
    required String newEmail,
    required String currentPassword,
    String? twoFactorPassword,
    String? locale,
  }) async {
    try {
      final token = await getToken();
      if (token == null) return {'success': false, 'error': 'unauthorized'};
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/user/email/change/request'),
        headers: await _buildDeviceHeaders(token: token),
        body: jsonEncode({
          'new_email': newEmail.trim(),
          'current_password': currentPassword,
          if (twoFactorPassword != null && twoFactorPassword.isNotEmpty)
            'two_factor_password': twoFactorPassword,
          'locale': await _currentLocaleCode(locale),
        }),
      );
      final data = _tryDecodeMap(response.body);
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'cooldown_seconds': data['cooldown_seconds'] ?? data['retry_after'] ?? 0,
        'requires_2fa': data['requires_2fa'] == true,
        'error': data['error'],
        'message': data['message']?.toString(),
      };
    } catch (e) {
      return {'success': false, 'error': 'network_error', 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> confirmEmailChange({
    required String newEmail,
    required String code,
  }) async {
    try {
      final token = await getToken();
      if (token == null) return {'success': false, 'error': 'unauthorized'};
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/user/email/change/confirm'),
        headers: await _buildDeviceHeaders(token: token),
        body: jsonEncode({
          'new_email': newEmail.trim(),
          'code': code.trim(),
        }),
      );
      final data = _tryDecodeMap(response.body);
      final ok = response.statusCode == 200 && data['success'] == true;
      if (ok) {
        final resolvedEmail = data['email']?.toString() ?? newEmail.trim();
        final accountManager = AccountManager();
        final cur = accountManager.currentAccount;
        if (cur != null) {
          await accountManager.updateAccountProfile(
            cur.userId,
            email: resolvedEmail,
            emailVerified: true,
          );
        }
        final cached = SettingsService().userProfile;
        if (cached != null) {
          await SettingsService()
              .saveUserProfile(cached.copyWith(email: resolvedEmail));
        }
      }
      return {
        'success': ok,
        'email': data['email']?.toString() ?? newEmail.trim(),
        'email_verified': data['email_verified'] == true,
        'error': data['error'],
        'message': data['message']?.toString(),
      };
    } catch (e) {
      return {'success': false, 'error': 'network_error', 'message': e.toString()};
    }
  }

  // ============ Password & 2FA OTP Reset ============

  static Future<Map<String, dynamic>> sendPasswordResetCode({
    required String email,
    String? locale,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/auth/password/send-code'),
        headers: await _buildDeviceHeaders(),
        body: jsonEncode({
          'email': email.trim(),
          'locale': await _currentLocaleCode(locale),
        }),
      );
      final data = _tryDecodeMap(response.body);
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'cooldown_seconds': data['cooldown_seconds'] ?? data['retry_after'] ?? 0,
        'error': data['error'],
        'message': data['message']?.toString(),
      };
    } catch (e) {
      return {'success': false, 'error': 'network_error', 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> resetPasswordWithCode({
    required String email,
    required String code,
    required String newPassword,
    String? twoFactorPassword,
    String? recoveryCode,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/auth/password/reset'),
        headers: await _buildDeviceHeaders(),
        body: jsonEncode({
          'email': email.trim(),
          'code': code.trim(),
          'new_password': newPassword,
          if (twoFactorPassword != null && twoFactorPassword.isNotEmpty)
            'two_factor_password': twoFactorPassword,
          if (recoveryCode != null && recoveryCode.isNotEmpty)
            'recovery_code': recoveryCode.trim(),
        }),
      );
      final data = _tryDecodeMap(response.body);
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'requires_2fa': data['requires_2fa'] == true,
        'error': data['error'],
        'message': data['message']?.toString(),
      };
    } catch (e) {
      return {'success': false, 'error': 'network_error', 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> send2FAResetCode({
    required String usernameOrEmail,
    required String password,
    String? locale,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/auth/2fa/reset/send-code'),
        headers: await _buildDeviceHeaders(),
        body: jsonEncode({
          'username_or_email': usernameOrEmail.trim(),
          'password': password,
          'locale': await _currentLocaleCode(locale),
        }),
      );
      final data = _tryDecodeMap(response.body);
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'masked_email': data['masked_email']?.toString(),
        'cooldown_seconds': data['cooldown_seconds'] ?? data['retry_after'] ?? 0,
        'error': data['error'],
        'message': data['message']?.toString(),
      };
    } catch (e) {
      return {'success': false, 'error': 'network_error', 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> confirm2FAReset({
    required String usernameOrEmail,
    required String password,
    required String code,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/auth/2fa/reset/confirm'),
        headers: await _buildDeviceHeaders(),
        body: jsonEncode({
          'username_or_email': usernameOrEmail.trim(),
          'password': password,
          'code': code.trim(),
        }),
      );
      final data = _tryDecodeMap(response.body);
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'error': data['error'],
        'message': data['message']?.toString(),
      };
    } catch (e) {
      return {'success': false, 'error': 'network_error', 'message': e.toString()};
    }
  }

  // ============ QR Auth & External Session Completion ============

  static Future<Map<String, dynamic>> createQrLoginSession({String? locale}) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/auth/qr/create'),
        headers: await _buildDeviceHeaders(),
        body: jsonEncode(await _buildDeviceBodyFields(locale: locale)),
      );
      final data = _tryDecodeMap(response.body);
      final token = data['token']?.toString();
      final rawUrl = data['qr_url']?.toString();
      final qrUrl = (rawUrl != null && rawUrl.isNotEmpty)
          ? rawUrl
          : (token != null && token.isNotEmpty
              ? 'theaver://qr-login?token=${Uri.encodeQueryComponent(token)}'
              : null);
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'token': token,
        'short_code': data['short_code']?.toString(),
        'qr_secret': data['qr_secret']?.toString(),
        'qr_url': qrUrl,
        'expires_at': data['expires_at']?.toString(),
        'error': data['error'],
        'message': data['message']?.toString(),
      };
    } catch (e) {
      return {'success': false, 'error': 'network_error', 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> createQrGrantSession({String? locale}) async {
    try {
      final authToken = await getToken();
      if (authToken == null) return {'success': false, 'error': 'unauthorized'};
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/auth/qr/grant'),
        headers: await _buildDeviceHeaders(token: authToken),
        body: jsonEncode({'locale': await _currentLocaleCode(locale)}),
      );
      final data = _tryDecodeMap(response.body);
      final token = data['token']?.toString();
      final rawUrl = data['qr_url']?.toString();
      final qrUrl = (rawUrl != null && rawUrl.isNotEmpty)
          ? rawUrl
          : (token != null && token.isNotEmpty
              ? 'theaver://qr-login?mode=grant&token=${Uri.encodeQueryComponent(token)}'
              : null);
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'mode': data['mode']?.toString() ?? 'grant',
        'token': token,
        'short_code': data['short_code']?.toString(),
        'qr_secret': data['qr_secret']?.toString(),
        'qr_url': qrUrl,
        'expires_at': data['expires_at']?.toString(),
        'error': data['error'],
        'message': data['message']?.toString(),
      };
    } catch (e) {
      return {'success': false, 'error': 'network_error', 'message': e.toString()};
    }
  }

  static String _normalizeShortCodeArg(String raw) {
    final t = raw.trim();
    return (t.contains('://') || t.contains('token=')) ? t : t.toUpperCase();
  }

  static Future<Map<String, dynamic>> claimQrGrantSession({
    String? token,
    String? shortCode,
    String? twoFactorPassword,
    String? recoveryCode,
    String? locale,
  }) async {
    try {
      final body = <String, dynamic>{
        ...await _buildDeviceBodyFields(locale: locale),
        if (token != null && token.trim().isNotEmpty) 'token': token.trim(),
        if (shortCode != null && shortCode.trim().isNotEmpty)
          'short_code': _normalizeShortCodeArg(shortCode),
        if (twoFactorPassword != null && twoFactorPassword.isNotEmpty)
          'two_factor_password': twoFactorPassword,
        if (recoveryCode != null && recoveryCode.trim().isNotEmpty)
          'recovery_code': recoveryCode.trim(),
      };
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/auth/qr/claim'),
        headers: await _buildDeviceHeaders(),
        body: jsonEncode(body),
      );
      final data = _tryDecodeMap(response.body);
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'status': data['status']?.toString(),
        'auth_token': data['auth_token']?.toString(),
        'device_id': data['device_id']?.toString(),
        'user_id': data['user_id']?.toString(),
        'user': data['user'] is Map ? Map<String, dynamic>.from(data['user'] as Map) : null,
        'requires_2fa': data['requires_2fa'] == true,
        'error': data['error'],
        'message': data['message']?.toString(),
      };
    } catch (e) {
      return {'success': false, 'error': 'network_error', 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> pollQrLoginStatus({
    required String token,
    required String qrSecret,
  }) async {
    try {
      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/auth/qr/status/${Uri.encodeComponent(token)}'),
        headers: await _buildDeviceHeaders(extra: {'X-QR-Secret': qrSecret}),
      );
      final data = _tryDecodeMap(response.body);
      return {
        'statusCode': response.statusCode,
        'status': data['status']?.toString() ?? 'expired',
        'auth_token': data['auth_token']?.toString(),
        'token': data['token']?.toString(),
        'device_id': data['device_id']?.toString(),
        'device_name': data['device_name']?.toString(),
        'device_type': data['device_type']?.toString(),
        'user_id': data['user_id']?.toString(),
        'user': data['user'] is Map ? Map<String, dynamic>.from(data['user'] as Map) : null,
        'error': data['error'],
        'message': data['message']?.toString(),
      };
    } catch (e) {
      return {'status': 'error', 'error': 'network_error', 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> verifyQrLogin2FA({
    required String token,
    required String qrSecret,
    String? twoFactorPassword,
    String? recoveryCode,
  }) async {
    try {
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/auth/qr/verify-2fa'),
        headers: await _buildDeviceHeaders(extra: {'X-QR-Secret': qrSecret}),
        body: jsonEncode({
          'token': token,
          if (twoFactorPassword != null && twoFactorPassword.isNotEmpty)
            'two_factor_password': twoFactorPassword,
          if (recoveryCode != null && recoveryCode.isNotEmpty)
            'recovery_code': recoveryCode.trim(),
        }),
      );
      final data = _tryDecodeMap(response.body);
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'status': data['status']?.toString(),
        'auth_token': data['auth_token']?.toString(),
        'device_id': data['device_id']?.toString(),
        'user_id': data['user_id']?.toString(),
        'user': data['user'] is Map ? Map<String, dynamic>.from(data['user'] as Map) : null,
        'error': data['error'],
        'message': data['message']?.toString(),
      };
    } catch (e) {
      return {'success': false, 'error': 'network_error', 'message': e.toString()};
    }
  }

  static Future<Map<String, dynamic>> confirmQrLogin({
    String? token,
    String? shortCode,
  }) async {
    try {
      final authToken = await getToken();
      if (authToken == null) return {'success': false, 'error': 'unauthorized'};
      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/auth/qr/confirm'),
        headers: await _buildDeviceHeaders(token: authToken),
        body: jsonEncode({
          if (token != null && token.isNotEmpty) 'token': token.trim(),
          if (shortCode != null && shortCode.isNotEmpty)
            'short_code': _normalizeShortCodeArg(shortCode),
        }),
      );
      final data = _tryDecodeMap(response.body);
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'status': data['status']?.toString(),
        'device_name': data['device_name']?.toString(),
        'error': data['error'],
        'message': data['message']?.toString(),
      };
    } catch (e) {
      return {'success': false, 'error': 'network_error', 'message': e.toString()};
    }
  }

  // ============ Onboarding, Anti-Abuse Verification & OAuth2/OIDC ============

  static Future<AuthProvidersConfig> fetchAuthProviders({String? locale}) async {
    try {
      final loc = await _currentLocaleCode(locale);
      final uri = Uri.parse('${AppConfig.baseUrl}/api/auth/providers').replace(
        queryParameters: {'locale': loc},
      );
      final response = await http
          .get(uri, headers: await _buildDeviceHeaders())
          .timeout(const Duration(seconds: 8));
      final data = _tryDecodeMap(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return AuthProvidersConfig.fromJson(data);
      }
    } catch (e) {
      debugPrint('AuthService.fetchAuthProviders error: $e');
    }
    return AuthProvidersConfig(
      countryCode: 'RU',
      phoneDialCode: '7',
      recommendedLanguage: LocaleProvider.resolveSystemLanguageCode(),
    );
  }

  static Future<Map<String, dynamic>> fetchAuthChallenge({
    String purpose = 'register',
  }) async {
    try {
      final uri = Uri.parse('${AppConfig.baseUrl}/api/auth/challenge').replace(
        queryParameters: {'purpose': purpose},
      );
      final response = await http
          .get(uri, headers: await _buildDeviceHeaders())
          .timeout(const Duration(seconds: 10));
      final data = _tryDecodeMap(response.body);
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'challenge': data['challenge']?.toString(),
        'difficulty_bits': (data['difficulty_bits'] as num?)?.toInt() ?? 18,
        'expires_in_seconds':
            (data['expires_in_seconds'] as num?)?.toInt() ?? 300,
        'error': data['error']?.toString(),
        'message': data['message']?.toString(),
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'network_error',
        'message': e.toString(),
      };
    }
  }

  static Future<Map<String, dynamic>> checkUsernameAvailability(
    String username,
  ) async {
    try {
      final clean = username.trim().replaceFirst(RegExp(r'^@+'), '');
      final uri =
          Uri.parse('${AppConfig.baseUrl}/api/auth/check-username').replace(
        queryParameters: {'username': clean},
      );
      final response = await http
          .get(uri, headers: await _buildDeviceHeaders())
          .timeout(const Duration(seconds: 8));
      final data = _tryDecodeMap(response.body);
      final rawSuggestions = data['suggestions'];
      final suggestions = rawSuggestions is List
          ? rawSuggestions.map((e) => e.toString()).toList()
          : const <String>[];
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'available': data['available'] == true,
        'reason': data['reason']?.toString(),
        'username': data['username']?.toString() ?? clean,
        'suggestions': suggestions,
        'error': data['error']?.toString(),
        'message': data['message']?.toString(),
      };
    } catch (e) {
      return {
        'success': false,
        'available': false,
        'suggestions': const <String>[],
        'error': 'network_error',
        'message': e.toString(),
      };
    }
  }

  static Future<Map<String, dynamic>> startRegistrationVerification({
    required String email,
    required String phone,
    String? countryCode,
    String? powChallenge,
    String? powNonce,
    String? oauthRegistrationToken,
    String? locale,
  }) async {
    try {
      var resolvedChallenge = powChallenge?.trim();
      var resolvedNonce = powNonce?.trim();
      final hasOAuth =
          oauthRegistrationToken != null &&
          oauthRegistrationToken.trim().isNotEmpty;

      if (!hasOAuth &&
          (resolvedChallenge == null ||
              resolvedChallenge.isEmpty ||
              resolvedNonce == null ||
              resolvedNonce.isEmpty)) {
        final challengeRes = await fetchAuthChallenge(purpose: 'register');
        if (challengeRes['success'] != true ||
            challengeRes['challenge'] == null) {
          return {
            'success': false,
            'error': challengeRes['error'] ?? 'challenge_unavailable',
            'message':
                challengeRes['message'] ?? 'Security challenge unavailable',
          };
        }
        resolvedChallenge = challengeRes['challenge'].toString();
        resolvedNonce =
            await computeRegistrationProofOfWork(resolvedChallenge);
      }

      final accountManager = AccountManager();
      final deviceId =
          accountManager.currentDeviceId ??
          'device_${DateTime.now().millisecondsSinceEpoch}';

      final response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/api/auth/register/start'),
            headers: await _buildDeviceHeaders(overrideDeviceId: deviceId),
            body: jsonEncode({
              'email': email.trim(),
              'phone': phone.trim(),
              if (countryCode != null && countryCode.trim().isNotEmpty)
                'country_code': countryCode.trim().toUpperCase(),
              if (resolvedChallenge != null && resolvedChallenge.isNotEmpty)
                'pow_challenge': resolvedChallenge,
              if (resolvedNonce != null && resolvedNonce.isNotEmpty)
                'pow_nonce': resolvedNonce,
              if (hasOAuth)
                'oauth_registration_token': oauthRegistrationToken.trim(),
              'locale': await _currentLocaleCode(locale),
              'device_id': deviceId,
            }),
          )
          .timeout(const Duration(seconds: 20));
      final data = _tryDecodeMap(response.body);
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'email': data['email']?.toString() ?? email.trim(),
        'phone': data['phone']?.toString() ?? phone.trim(),
        'requires_email_code': data['requires_email_code'] == true,
        'requires_reverse_sms': data['requires_reverse_sms'] == true,
        'email_verified': data['email_verified'] == true,
        'phone_verified': data['phone_verified'] == true,
        'phone_verified_via': data['phone_verified_via']?.toString(),
        'cooldown_seconds':
            (data['cooldown_seconds'] ?? data['retry_after'] ?? 0) is num
                ? ((data['cooldown_seconds'] ?? data['retry_after'] ?? 0)
                        as num)
                    .toInt()
                : 0,
        'phone_verification_id': data['phone_verification_id']?.toString(),
        'sms_target_number': data['sms_target_number']?.toString(),
        'sms_body': data['sms_body']?.toString(),
        'sms_uri': data['sms_uri']?.toString(),
        'registration_ticket': data['registration_ticket']?.toString(),
        'error': data['error']?.toString(),
        'message': data['message']?.toString(),
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'network_error',
        'message': e.toString(),
      };
    }
  }

  static Future<Map<String, dynamic>> verifyRegistrationContacts({
    required String email,
    required String phone,
    String? countryCode,
    String? emailCode,
    String? phoneVerificationId,
    String? oauthRegistrationToken,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/api/auth/register/verify'),
            headers: await _buildDeviceHeaders(),
            body: jsonEncode({
              'email': email.trim(),
              'phone': phone.trim(),
              if (countryCode != null && countryCode.trim().isNotEmpty)
                'country_code': countryCode.trim().toUpperCase(),
              if (emailCode != null && emailCode.trim().isNotEmpty)
                'email_code': emailCode.trim(),
              if (phoneVerificationId != null &&
                  phoneVerificationId.trim().isNotEmpty)
                'phone_verification_id': phoneVerificationId.trim(),
              if (oauthRegistrationToken != null &&
                  oauthRegistrationToken.trim().isNotEmpty)
                'oauth_registration_token': oauthRegistrationToken.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      final data = _tryDecodeMap(response.body);
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'registration_ticket': data['registration_ticket']?.toString(),
        'email': data['email']?.toString(),
        'email_verified': data['email_verified'] == true,
        'phone': data['phone']?.toString(),
        'phone_verified': data['phone_verified'] == true,
        'phone_verified_via': data['phone_verified_via']?.toString(),
        'error': data['error']?.toString(),
        'message': data['message']?.toString(),
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'network_error',
        'message': e.toString(),
      };
    }
  }

  static Future<Map<String, dynamic>> pollPhoneVerificationStatus(
    String verificationId,
  ) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${AppConfig.baseUrl}/api/auth/phone-verify/${Uri.encodeComponent(verificationId)}/status',
            ),
            headers: await _buildDeviceHeaders(),
          )
          .timeout(const Duration(seconds: 8));
      final data = _tryDecodeMap(response.body);
      return {
        'success': response.statusCode == 200,
        'status': data['status']?.toString() ?? 'pending',
        'phone': data['phone']?.toString(),
        'error': data['error']?.toString(),
        'message': data['message']?.toString(),
      };
    } catch (e) {
      return {
        'success': false,
        'status': 'pending',
        'error': 'network_error',
        'message': e.toString(),
      };
    }
  }

  static Future<Map<String, dynamic>> startOAuthSession(
    String provider, {
    String? locale,
  }) async {
    try {
      final body = await _buildDeviceBodyFields(locale: locale);
      final response = await http
          .post(
            Uri.parse(
              '${AppConfig.baseUrl}/api/auth/oauth/${Uri.encodeComponent(provider)}/start',
            ),
            headers: await _buildDeviceHeaders(),
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 12));
      final data = _tryDecodeMap(response.body);
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'session_id': data['session_id']?.toString(),
        'poll_secret': data['poll_secret']?.toString(),
        'authorize_url': data['authorize_url']?.toString(),
        'expires_in_seconds':
            (data['expires_in_seconds'] as num?)?.toInt() ?? 600,
        'error': data['error']?.toString(),
        'message': data['message']?.toString(),
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'network_error',
        'message': e.toString(),
      };
    }
  }

  static Future<Map<String, dynamic>> pollOAuthSessionStatus({
    required String sessionId,
    required String pollSecret,
  }) async {
    try {
      final response = await http
          .get(
            Uri.parse(
              '${AppConfig.baseUrl}/api/auth/oauth/session/${Uri.encodeComponent(sessionId)}/status',
            ),
            headers: await _buildDeviceHeaders(
              extra: {'X-OAuth-Poll-Secret': pollSecret},
            ),
          )
          .timeout(const Duration(seconds: 10));
      final data = _tryDecodeMap(response.body);
      final status = data['status']?.toString() ?? 'pending';
      OAuthRegistrationPrefill? prefill;
      if (status == 'needs_registration') {
        prefill = OAuthRegistrationPrefill.fromStatusPayload(data);
      }
      return {
        'success': response.statusCode == 200 && data['success'] == true,
        'status': status,
        'auth_token': data['auth_token']?.toString(),
        'device_id': data['device_id']?.toString(),
        'user_id': data['user_id']?.toString(),
        'user': data['user'] is Map
            ? Map<String, dynamic>.from(data['user'] as Map)
            : null,
        'provider': data['provider']?.toString(),
        'provider_name': data['provider_name']?.toString(),
        'masked_email': data['masked_email']?.toString(),
        'requires_2fa': data['requires_2fa'] == true,
        'has_recovery_email': data['has_recovery_email'] == true,
        'prefill': prefill,
        'error': data['error']?.toString(),
        'message': data['message']?.toString(),
      };
    } catch (e) {
      return {
        'success': false,
        'status': 'error',
        'error': 'network_error',
        'message': e.toString(),
      };
    }
  }

  static Future<Map<String, dynamic>> verifyOAuth2FA({
    required String sessionId,
    required String pollSecret,
    String? twoFactorPassword,
    String? recoveryCode,
    BuildContext? context,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse(
              '${AppConfig.baseUrl}/api/auth/oauth/session/${Uri.encodeComponent(sessionId)}/verify-2fa',
            ),
            headers: await _buildDeviceHeaders(
              extra: {'X-OAuth-Poll-Secret': pollSecret},
            ),
            body: jsonEncode({
              if (twoFactorPassword != null && twoFactorPassword.isNotEmpty)
                'two_factor_password': twoFactorPassword,
              if (recoveryCode != null && recoveryCode.trim().isNotEmpty)
                'recovery_code': recoveryCode.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      final data = _tryDecodeMap(response.body);
      final ok = response.statusCode == 200 && data['success'] == true;
      final authToken = data['auth_token']?.toString() ?? '';
      final userId = data['user_id']?.toString() ?? '';
      final userMap = data['user'] is Map
          ? Map<String, dynamic>.from(data['user'] as Map)
          : null;
      if (ok && authToken.isNotEmpty && userId.isNotEmpty) {
        await completeExternalLoginSession(
          authToken: authToken,
          userId: userId,
          user: userMap,
          context: (context != null && context.mounted) ? context : null,
        );
      }
      return {
        'success': ok,
        'status': data['status']?.toString(),
        'auth_token': authToken,
        'user_id': userId,
        'user': userMap,
        'requires_2fa': data['requires_2fa'] == true,
        'error': data['error']?.toString(),
        'message': data['message']?.toString(),
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'network_error',
        'message': e.toString(),
      };
    }
  }

  static Future<Map<String, dynamic>> confirmOAuthPasswordLink({
    required String sessionId,
    required String pollSecret,
    required String password,
    String? twoFactorPassword,
    String? recoveryCode,
    BuildContext? context,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${AppConfig.baseUrl}/api/auth/oauth/confirm-link'),
            headers: await _buildDeviceHeaders(
              extra: {'X-OAuth-Poll-Secret': pollSecret},
            ),
            body: jsonEncode({
              'session_id': sessionId,
              'password': password,
              if (twoFactorPassword != null && twoFactorPassword.isNotEmpty)
                'two_factor_password': twoFactorPassword,
              if (recoveryCode != null && recoveryCode.trim().isNotEmpty)
                'recovery_code': recoveryCode.trim(),
            }),
          )
          .timeout(const Duration(seconds: 15));
      final data = _tryDecodeMap(response.body);
      final ok = response.statusCode == 200 && data['success'] == true;
      final authToken = data['auth_token']?.toString() ?? '';
      final userId = data['user_id']?.toString() ?? '';
      final userMap = data['user'] is Map
          ? Map<String, dynamic>.from(data['user'] as Map)
          : null;
      if (ok && authToken.isNotEmpty && userId.isNotEmpty) {
        await completeExternalLoginSession(
          authToken: authToken,
          userId: userId,
          user: userMap,
          context: (context != null && context.mounted) ? context : null,
        );
      }
      return {
        'success': ok,
        'status': data['status']?.toString(),
        'auth_token': authToken,
        'user_id': userId,
        'user': userMap,
        'requires_2fa': data['requires_2fa'] == true,
        'error': data['error']?.toString(),
        'message': data['message']?.toString(),
      };
    } catch (e) {
      return {
        'success': false,
        'error': 'network_error',
        'message': e.toString(),
      };
    }
  }

  /// Uploads an avatar chosen through [TheavAvatarPickerSheet] across Web & native.
  static Future<Map<String, dynamic>> uploadAvatarFromPick(
    AvatarPickResult pick, {
    String? userId,
  }) async {
    final cropParam = pick.miniCrop?.toCompactParam();
    final res = await uploadAvatar(
      pick.file?.path ?? '',
      bytes: kIsWeb ? pick.bytes : null,
      fileName: pick.fileName,
      avatarCrop: cropParam,
    );
    if (!kIsWeb &&
        res['success'] == true &&
        pick.file != null &&
        userId != null &&
        userId.isNotEmpty) {
      try {
        await AvatarSyncService().setLocalAvatar(
          userId,
          pick.file!.path,
          avatarCrop: cropParam,
        );
      } catch (_) {}
    }
    return res;
  }

  static Future<void> completeExternalLoginSession({
    required String authToken,
    required String userId,
    Map<String, dynamic>? user,
    BuildContext? context,
  }) async {
    await SessionBootstrapCoordinator.bootstrapAuthenticatedSession(
      token: authToken,
      userId: userId,
      userMap: user,
      context: (context != null && context.mounted) ? context : null,
    );
  }

  /// Sync current app locale to active backend device session (for localized server emails/pushes).
  static Future<void> syncSessionLocale(String locale) async {
    try {
      final token = await getToken();
      if (token == null || token.isEmpty) return;
      await http.put(
        Uri.parse('${AppConfig.baseUrl}/api/sessions/locale'),
        headers: await _buildDeviceHeaders(token: token),
        body: jsonEncode({'locale': locale}),
      );
    } catch (e) {
      debugPrint('AuthService: syncSessionLocale error: $e');
    }
  }

  static String _getErrorMessage(int statusCode, String? serverMessage) {
    switch (statusCode) {
      case 400:
        return serverMessage ?? 'Invalid request';
      case 401:
        return 'Invalid credentials';
      case 403:
        return 'Account is locked or disabled';
      case 404:
        return 'User not found';
      case 500:
        return 'Server error. Please try again later.';
      default:
        return 'An error occurred. Please try again.';
    }
  }
}
