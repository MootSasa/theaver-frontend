import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../theme/theme_provider.dart';
import 'account_manager.dart';
import 'auth_service.dart';
import 'contacts_service.dart';
import 'database/app_database.dart';
import 'draft_service.dart';
import 'liquid_glass_provider.dart';
import 'notification_service.dart';
import 'notification_settings_provider.dart';
import 'power_saving_provider.dart';
import 'privacy_settings_provider.dart';
import 'profile_instant_cache.dart';
import 'settings_service.dart';
import 'theav_theme_service.dart';

/// Atomically coordinates post-authentication session setup across account storage,
/// SQLite user scoping, onboarding appearance inheritance, and runtime providers.
class SessionBootstrapCoordinator {
  SessionBootstrapCoordinator._();

  /// Shared onboarding completion preference key synced with [SplashScreen] and [FirstStartWizardScreen].
  static const String onboardingCompletedPrefKey =
      'onboarding_wizard_completed_v1';

  /// Optional test hook capturing exact activation order (`setActiveUser:<id>`,
  /// `ensureSavedChatExists:<id>`, etc.).
  @visibleForTesting
  static List<String>? debugCallOrderLog;

  /// Optional test override replacing actual database operations while preserving
  /// strict call ordering for widget/unit tests.
  @visibleForTesting
  static Future<void> Function(String userId)? debugEnsureSavedChatOverride;

  /// Optional test flag to skip background network/push side effects during headless tests.
  @visibleForTesting
  static bool skipBackgroundNetworkSyncInTests = false;

  /// Completes authentication state for [userId], adopting device onboarding appearance
  /// before binding user-scoped services, activating the user database before creating
  /// Saved Messages, and reloading all dependent providers.
  static Future<void> bootstrapAuthenticatedSession({
    required String token,
    required String userId,
    Map<String, dynamic>? userMap,
    String? fallbackUsername,
    String? fallbackEmail,
    String? fallbackPhone,
    String? fallbackFirstName,
    String? fallbackLastName,
    String? fallbackDisplayName,
    String? fallbackAvatarUrl,
    BuildContext? context,
  }) async {
    if (userId.isEmpty) return;

    ThemeProvider? themeProvider;
    LiquidGlassProvider? liquidGlass;
    PrivacySettingsProvider? privacy;
    NotificationSettingsProvider? notif;
    final BuildContext? capturedContext =
        (context != null && context.mounted) ? context : null;
    if (capturedContext != null) {
      try {
        themeProvider = capturedContext.read<ThemeProvider>();
      } catch (_) {}
      try {
        liquidGlass = capturedContext.read<LiquidGlassProvider>();
      } catch (_) {}
      try {
        privacy = capturedContext.read<PrivacySettingsProvider>();
      } catch (_) {}
      try {
        notif = capturedContext.read<NotificationSettingsProvider>();
      } catch (_) {}
    }

    // 1. Adopt pre-login onboarding appearance before switching active user state.
    await SettingsService().adoptDeviceOnboardingAppearanceIfUnset(userId);
    await TheavThemeService().adoptDeviceOnboardingAppearanceIfUnset(userId);
    await ThemeProvider.adoptDeviceOnboardingAppearanceIfUnset(userId);

    // 2. Persist account credentials & full profile into AccountManager.
    final accountManager = AccountManager();
    await accountManager.init();
    final username = userMap?['username']?.toString() ?? fallbackUsername;
    final firstName =
        userMap?['first_name']?.toString() ??
        userMap?['name']?.toString() ??
        fallbackFirstName;
    final lastName =
        userMap?['last_name']?.toString() ??
        userMap?['surname']?.toString() ??
        fallbackLastName;
    final displayName =
        userMap?['display_name']?.toString() ?? fallbackDisplayName;
    final avatarUrl = userMap?['avatar_url']?.toString() ?? fallbackAvatarUrl;
    final email = userMap?['email']?.toString() ?? fallbackEmail;
    final emailVerified = userMap?['email_verified'] == true;
    final phone = userMap?['phone']?.toString() ?? fallbackPhone;

    final existingIdx = accountManager.accounts.indexWhere(
      (a) => a.userId == userId,
    );
    if (existingIdx == -1) {
      await accountManager.addAccount(
        Account(
          userId: userId,
          token: token,
          username: username,
          displayName: displayName,
          avatarUrl: avatarUrl,
          lastLogin: DateTime.now(),
          name: firstName,
          surname: lastName,
          email: email,
          emailVerified: emailVerified,
          phone: phone,
        ),
      );
    } else {
      await accountManager.updateAccountToken(userId, token);
      await accountManager.updateAccountProfile(
        userId,
        username: username,
        displayName: displayName,
        avatarUrl: avatarUrl,
        name: firstName,
        surname: lastName,
        email: email,
        emailVerified: emailVerified ? true : null,
        phone: phone,
      );
    }

    await accountManager.setCurrentAccount(userId);
    try {
      await accountManager.registerDeviceSession(userId);
    } catch (_) {}

    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('auth_token', token);
    await prefs.setString('user_id', userId);
    await prefs.setBool(onboardingCompletedPrefKey, true);

    // 3. Activate SQLite DB for [userId] STRICTLY BEFORE creating Saved Messages.
    AppDatabase.setActiveUser(userId);
    debugCallOrderLog?.add('setActiveUser:$userId');

    if (debugEnsureSavedChatOverride != null) {
      await debugEnsureSavedChatOverride!(userId);
      debugCallOrderLog?.add('ensureSavedChatExists:$userId');
    } else {
      await AppDatabase(userId).ensureSavedChatExists(userId);
      debugCallOrderLog?.add('ensureSavedChatExists:$userId');
    }

    // 4. Reload user-scoped settings, themes, drafts, contacts & providers.
    await SettingsService().reloadForUser(userId);
    await TheavThemeService().switchUser(userId);
    try {
      await DraftService().switchAccount(userId);
    } catch (_) {}
    try {
      await ContactsService.switchAccount(userId);
    } catch (_) {}
    try {
      await PowerSavingProvider.instance.reloadForUser();
    } catch (_) {}

    if (themeProvider != null) {
      try {
        await themeProvider.reloadForUser(userId);
      } catch (_) {}
    }
    if (liquidGlass != null) {
      try {
        liquidGlass.init();
      } catch (_) {}
    }
    if (privacy != null) {
      try {
        await privacy.reloadForUser();
      } catch (_) {}
    }
    if (notif != null) {
      try {
        await notif.reloadForUser();
      } catch (_) {}
    }

    if (!skipBackgroundNetworkSyncInTests) {
      final savedLang = prefs.getString('selected_language');
      if (savedLang != null && savedLang.isNotEmpty) {
        unawaited(AuthService.syncSessionLocale(savedLang));
      }
      unawaited(NotificationService().registerCurrentToken());
      if (capturedContext != null && capturedContext.mounted) {
        unawaited(
          ProfileInstantCache.instance.warmupSelf(context: capturedContext),
        );
      } else {
        unawaited(ProfileInstantCache.instance.warmupSelf());
      }
    }
  }
}
