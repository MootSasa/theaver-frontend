import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../screens/auth/login_screen.dart';
import '../utils/swipe_back_route.dart';
import 'account_manager.dart';
import 'auth_service.dart';
import 'browser_cookie_jar_vault.dart';
import 'browser_data_service.dart';
import 'browser_site_settings_service.dart';
import 'browser_vault_auth_gate.dart';
import 'browser_vault_service.dart';
import 'contacts_service.dart';
import 'database/app_database.dart';
import 'deep_link_service.dart';
import 'draft_service.dart';
import 'liquid_glass_provider.dart';
import 'notification_service.dart';
import 'notification_settings_provider.dart';
import 'power_saving_provider.dart';
import 'privacy_settings_provider.dart';
import 'settings_service.dart';
import 'tiling_layout_controller.dart';
import 'unread_count_provider.dart';
import '../widgets/bot/mini_app_webview_sheet.dart';

enum AccountSwitchStatus {
  alreadyActive,
  switched,
  switchedOffline,
  sessionExpired,
  failed,
}

class AccountSwitchResult {
  final AccountSwitchStatus status;
  final String? message;

  const AccountSwitchResult({
    required this.status,
    this.message,
  });

  bool get isSuccess =>
      status == AccountSwitchStatus.switched ||
      status == AccountSwitchStatus.switchedOffline ||
      status == AccountSwitchStatus.alreadyActive;
}

/// Coordinates safe multi-account switching without mutating active account
/// or database state before token validation succeeds.
class AccountSwitchOrchestrator {
  AccountSwitchOrchestrator._internal();
  static final AccountSwitchOrchestrator _instance =
      AccountSwitchOrchestrator._internal();
  factory AccountSwitchOrchestrator() => _instance;

  final AccountManager _accountManager = AccountManager();

  /// Validates the target account token before mutating active account or DB
  /// state, then reloads user-scoped services and providers.
  Future<AccountSwitchResult> switchToAccount(
    BuildContext context,
    Account account,
  ) async {
    if (_accountManager.currentAccount?.userId == account.userId) {
      return const AccountSwitchResult(
        status: AccountSwitchStatus.alreadyActive,
      );
    }

    LiquidGlassProvider? liquidGlass;
    UnreadCountProvider? unread;
    NotificationSettingsProvider? notif;
    PrivacySettingsProvider? privacy;
    try {
      liquidGlass = context.read<LiquidGlassProvider>();
    } catch (_) {}
    try {
      unread = context.read<UnreadCountProvider>();
    } catch (_) {}
    try {
      notif = context.read<NotificationSettingsProvider>();
    } catch (_) {}
    try {
      privacy = context.read<PrivacySettingsProvider>();
    } catch (_) {}

    try {
      final verification = await AuthService.verifyToken(account.token);
      final status = verification['status'] as String? ?? 'offline';
      if (status == 'expired') {
        return const AccountSwitchResult(
          status: AccountSwitchStatus.sessionExpired,
        );
      }

      if (verification['user'] is Map<String, dynamic>) {
        final u = verification['user'] as Map<String, dynamic>;
        final birthdayStr = u['birthday'] as String?;
        final parsedBirthday =
            birthdayStr != null ? DateTime.tryParse(birthdayStr) : null;
        await _accountManager.updateAccountProfile(
          account.userId,
          username: u['username'] as String?,
          displayName: u['display_name'] as String?,
          avatarUrl: u['avatar_url'] as String?,
          name: u['name'] as String?,
          surname: u['surname'] as String?,
          email: u['email'] as String?,
          emailVerified: u['email_verified'] as bool?,
          phone: u['phone'] as String?,
          bio: u['bio'] as String?,
          birthday: parsedBirthday,
          clearBirthday: u.containsKey('birthday') && parsedBirthday == null,
        );
      }

      final prevUserId = _accountManager.currentAccount?.userId;

      TilingLayoutController.instance.closeAllChats();
      MiniAppSessionController.instance.closeAllMinimized();
      BrowserVaultAuthGate.instance.invalidateGrant();
      await BrowserCookieJarVault.instance
          .snapshotAndClearForOutgoingAccount(prevUserId);

      await _accountManager.setCurrentAccount(account.userId);
      AppDatabase.setActiveUser(account.userId);
      await DraftService().switchAccount(account.userId);
      await ContactsService.switchAccount(account.userId);
      unawaited(
        ContactsService.getContacts(forceRefresh: true, includeOverrides: true),
      );
      await SettingsService().reloadForUser(account.userId);
      await PowerSavingProvider.instance.reloadForUser();
      await _accountManager.registerDeviceSession(account.userId);
      await BrowserCookieJarVault.instance
          .restoreForIncomingAccount(account.userId);
      unawaited(BrowserDataService.instance.ensureLoaded(forceReload: true));
      unawaited(BrowserVaultService.instance.ensureLoaded(forceReload: true));
      unawaited(
        BrowserSiteSettingsService.instance.ensureLoaded(forceReload: true),
      );

      liquidGlass?.init();
      unread?.clearForAccountSwitch();
      if (notif != null) {
        unawaited(notif.reloadForUser());
      }
      if (privacy != null) {
        unawaited(privacy.reloadForUser());
      }

      unawaited(NotificationService().registerCurrentToken());
      unawaited(
        _accountManager.trySyncPendingProfile(userId: account.userId),
      );

      return AccountSwitchResult(
        status: status == 'valid'
            ? AccountSwitchStatus.switched
            : AccountSwitchStatus.switchedOffline,
      );
    } catch (e) {
      return AccountSwitchResult(
        status: AccountSwitchStatus.failed,
        message: e.toString(),
      );
    }
  }

  /// Removes [account], switching seamlessly to another saved account when
  /// removing the active one, or navigating to [LoginScreen] if none remain.
  Future<void> removeAccountAndRecover(
    BuildContext context,
    Account account,
  ) async {
    final isCurrent = account.userId == _accountManager.currentAccount?.userId;
    if (!isCurrent) {
      await _accountManager.removeAccount(account.userId);
      await BrowserVaultService.instance.wipeAccountVault(account.userId);
      await BrowserSiteSettingsService.instance.wipeAccount(account.userId);
      await BrowserDataService.instance.wipeAccountData(account.userId);
      await BrowserCookieJarVault.instance.wipeAccountCookies(
        account.userId,
        isCurrentAccount: false,
      );
      try {
        await ContactsService.clearCache(clearDisk: true, userId: account.userId);
      } catch (_) {}
      try {
        await AppDatabase.removeUserDatabase(account.userId);
      } catch (_) {}
      return;
    }

    TilingLayoutController.instance.closeAllChats();
    final remaining = _accountManager.accounts
        .where((a) => a.userId != account.userId)
        .toList();

    await AuthService.logout();

    for (final candidate in remaining) {
      if (!context.mounted) return;
      final res = await switchToAccount(context, candidate);
      if (res.isSuccess) {
        return;
      }
    }

    if (!context.mounted) return;
    final nav = DeepLinkService().navigatorKey.currentState ??
        Navigator.of(context, rootNavigator: true);
    nav.pushAndRemoveUntil(
      SwipeBackPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }
}
