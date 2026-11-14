import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:iconoir_flutter/regular/lock.dart';
import 'package:iconoir_flutter/regular/fingerprint.dart';
import 'package:iconoir_flutter/regular/timer.dart';
import 'package:iconoir_flutter/regular/user_xmark.dart';
import 'package:iconoir_flutter/regular/laptop.dart';
import 'package:iconoir_flutter/regular/smartphone_device.dart';
import 'package:iconoir_flutter/regular/trash.dart';
import 'package:iconoir_flutter/regular/mail.dart';
import 'package:iconoir_flutter/regular/check.dart';
import 'package:iconoir_flutter/regular/nav_arrow_right.dart';

import '../../l10n/app_localizations.dart';
import '../../services/account_manager.dart';
import '../../services/app_lock_service.dart';
import '../../services/privacy_settings_provider.dart';
import '../../services/settings_service.dart';
import '../../widgets/settings/settings_floating_header.dart';
import '../../widgets/settings/settings_group.dart';
import '../../widgets/common/adaptive_switch.dart';
import 'blocked_users_screen.dart';
import 'change_email_screen.dart';
import 'devices_screen.dart';
import 'passcode_screen.dart';

/// Screen "Security" — Email, 2FA & Recovery Codes, App Lock, Blocked Users,
/// Active Sessions, and Account Auto-Deletion TTL.
class SecurityScreen extends StatefulWidget {
  const SecurityScreen({super.key});

  @override
  State<SecurityScreen> createState() => _SecurityScreenState();
}

class _SecurityScreenState extends State<SecurityScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final provider = context.read<PrivacySettingsProvider>();
      provider.load2FA();
      provider.loadBlockedUsers();
      provider.loadAccountTTL();
      provider.loadAppLock();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final acc = AccountManager().currentAccount;
    final cachedEmail = SettingsService().userProfile?.email ?? '';
    final email = (acc?.email?.isNotEmpty == true ? acc!.email! : cachedEmail);
    final emailVerified = acc?.emailVerified ?? false;

    return SettingsFloatingScaffold(
      title: l10n.translate('security_title'),
      body: Consumer2<PrivacySettingsProvider, AppLockService>(
        builder: (context, provider, appLock, _) {
          final tfa = provider.twoFactor;
          final hasPin = appLock.hasPin;
          final biometricsEnabled = appLock.biometricsEnabled;
          final autoLockTimeout = appLock.autoLockTimeout;

          return ListView(
            padding: EdgeInsets.only(
              top: SettingsFloatingHeader.topClearanceOf(context) + 8,
              bottom: 24,
            ),
            children: [
              // Account Email
              SettingsGroup(
                title: l10n.translate('email_current_section'),
                children: [
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: (emailVerified ? Colors.green : Colors.orange)
                            .withOpacity(0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Mail(
                        width: 22,
                        height: 22,
                        color: emailVerified ? Colors.green : Colors.orange,
                      ),
                    ),
                    title: Text(l10n.translate('email_screen_title')),
                    subtitle: Text(
                      email.isEmpty
                          ? l10n.translate('security_not_set')
                          : '$email • ${emailVerified ? l10n.translate('email_status_verified') : l10n.translate('email_status_unverified')}',
                    ),
                    trailing: NavArrowRight(
                      width: 18,
                      height: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onTap: () async {
                      HapticFeedback.lightImpact();
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const ChangeEmailScreen(),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
                  ),
                ],
              ),

              // Two-Factor Authentication
              SettingsGroup(
                title: l10n.translate('security_2fa_section'),
                children: [
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: tfa.enabled
                            ? Colors.green.withOpacity(0.15)
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Lock(
                        width: 22,
                        height: 22,
                        color: tfa.enabled ? Colors.green : Colors.grey,
                      ),
                    ),
                    title: Text(l10n.translate('security_2fa')),
                    subtitle: Text(
                      tfa.enabled
                          ? l10n.translate('security_2fa_enabled')
                          : l10n.translate('security_2fa_disabled'),
                    ),
                    trailing: AdaptiveSwitch(
                      value: tfa.enabled,
                      onChanged: (v) async {
                        HapticFeedback.lightImpact();
                        if (v) {
                          _show2FADialog(
                            context,
                            isChanging: false,
                            initialRecoveryEmail: tfa.recoveryEmail.isNotEmpty
                                ? tfa.recoveryEmail
                                : email,
                          );
                        } else {
                          _showDisable2FADialog(context);
                        }
                      },
                    ),
                  ),
                  if (tfa.enabled) ...[
                    ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Lock(
                          width: 22,
                          height: 22,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      title: Text(l10n.translate('security_2fa_change_password')),
                      trailing: NavArrowRight(
                        width: 18,
                        height: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      onTap: () => _show2FADialog(
                        context,
                        isChanging: true,
                        initialRecoveryEmail: tfa.recoveryEmail,
                      ),
                    ),
                    ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Mail(
                          width: 22,
                          height: 22,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      title: Text(l10n.translate('security_recovery_email')),
                      subtitle: Text(
                        tfa.recoveryEmail.isEmpty
                            ? l10n.translate('security_not_set')
                            : tfa.recoveryEmail,
                      ),
                      trailing: NavArrowRight(
                        width: 18,
                        height: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      onTap: () => _showRecoveryEmailDialog(context, tfa.recoveryEmail),
                    ),
                    ListTile(
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          Icons.vpn_key_outlined,
                          size: 20,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                      title: Text(l10n.translate('security_2fa_regenerate_codes')),
                      subtitle: Text(l10n.translate('security_2fa_regenerate_desc')),
                      trailing: NavArrowRight(
                        width: 18,
                        height: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      onTap: () => _showRegenerateCodesDialog(context),
                    ),
                  ],
                ],
              ),

              // App Lock
              SettingsGroup(
                title: l10n.translate('security_app_lock_section'),
                children: [
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: hasPin
                            ? theme.colorScheme.primaryContainer.withOpacity(0.6)
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: SmartphoneDevice(
                        width: 22,
                        height: 22,
                        color: hasPin ? theme.colorScheme.primary : Colors.grey,
                      ),
                    ),
                    title: Text(l10n.translate('security_pin_code')),
                    subtitle: Text(
                      hasPin
                          ? l10n.translate('security_pin_set')
                          : l10n.translate('security_pin_not_set'),
                    ),
                    trailing: NavArrowRight(
                      width: 18,
                      height: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const PasscodeScreen(),
                        ),
                      );
                    },
                  ),
                  if (!kIsWeb)
                    ListTile(
                      enabled: hasPin,
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: (hasPin && biometricsEnabled)
                              ? theme.colorScheme.primaryContainer.withOpacity(0.6)
                              : theme.colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Fingerprint(
                          width: 22,
                          height: 22,
                          color: (hasPin && biometricsEnabled)
                              ? theme.colorScheme.primary
                              : Colors.grey,
                        ),
                      ),
                      title: Text(l10n.translate('security_biometrics')),
                      trailing: AdaptiveSwitch(
                        value: hasPin && biometricsEnabled,
                        onChanged: hasPin
                            ? (v) async {
                                HapticFeedback.lightImpact();
                                await appLock.setBiometricsEnabled(v);
                                await provider.saveAppLock(AppLockSettings(
                                  hasPin: hasPin,
                                  biometricsEnabled: v,
                                  autoLockTimeout: autoLockTimeout,
                                ));
                              }
                            : null,
                      ),
                    ),
                  ListTile(
                    enabled: hasPin,
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Timer(
                        width: 22,
                        height: 22,
                        color: hasPin
                            ? theme.colorScheme.onSurfaceVariant
                            : Colors.grey,
                      ),
                    ),
                    title: Text(l10n.translate('security_auto_lock')),
                    subtitle: Text(
                      hasPin
                          ? _autoLockLabel(l10n, autoLockTimeout)
                          : l10n.translate('security_pin_required_hint'),
                    ),
                    trailing: NavArrowRight(
                      width: 18,
                      height: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onTap: hasPin ? () => _showAutoLockPicker(context) : null,
                  ),
                ],
              ),

              // Blocked Users
              SettingsGroup(
                title: l10n.translate('security_blocked_section'),
                children: [
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: const UserXmark(
                        width: 22,
                        height: 22,
                        color: Colors.red,
                      ),
                    ),
                    title: Text(l10n.translate('security_blocked_users')),
                    subtitle: Text('${provider.blockedUsers.length}'),
                    trailing: NavArrowRight(
                      width: 18,
                      height: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const BlockedUsersScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),

              // Active Sessions Link
              SettingsGroup(
                title: l10n.translate('security_sessions_section'),
                children: [
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withOpacity(0.5),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Laptop(
                        width: 22,
                        height: 22,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    title: Text(l10n.translate('security_active_sessions')),
                    trailing: NavArrowRight(
                      width: 18,
                      height: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onTap: () {
                      HapticFeedback.lightImpact();
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const DevicesScreen(),
                        ),
                      );
                    },
                  ),
                ],
              ),

              // Account Auto-Deletion Section
              SettingsGroup(
                title: l10n.translate('security_account_ttl_section'),
                children: [
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: Colors.red.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: const Trash(
                        width: 22,
                        height: 22,
                        color: Colors.red,
                      ),
                    ),
                    title: Text(l10n.translate('security_account_ttl_title')),
                    subtitle: Text(_formatAccountTTL(l10n, provider.accountTTLMonths)),
                    trailing: NavArrowRight(
                      width: 18,
                      height: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onTap: () => _showAccountTTLPicker(context, provider),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    child: Text(
                      l10n.translate('security_account_ttl_desc'),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  String _autoLockLabel(AppLocalizations l10n, String timeout) => switch (timeout) {
        'immediately' => l10n.translate('security_auto_lock_immediately'),
        '1min' => l10n.translate('security_auto_lock_1min'),
        '5min' => l10n.translate('security_auto_lock_5min'),
        '15min' => l10n.translate('security_auto_lock_15min'),
        '1hour' => l10n.translate('security_auto_lock_1hour'),
        _ => timeout,
      };

  String _formatAccountTTL(AppLocalizations l10n, int months) {
    switch (months) {
      case 1:
        return l10n.translate('security_account_ttl_1_month');
      case 3:
        return l10n.translate('security_account_ttl_3_months');
      case 6:
        return l10n.translate('security_account_ttl_6_months');
      case 12:
        return l10n.translate('security_account_ttl_1_year');
      case 24:
        return l10n.translate('security_account_ttl_2_years');
      default:
        return '$months ${l10n.translate('security_months')}';
    }
  }

  void _showAccountTTLPicker(BuildContext context, PrivacySettingsProvider provider) {
    final l10n = context.l10n;
    HapticFeedback.lightImpact();

    final options = [
      {'months': 1, 'label': l10n.translate('security_account_ttl_1_month')},
      {'months': 3, 'label': l10n.translate('security_account_ttl_3_months')},
      {'months': 6, 'label': l10n.translate('security_account_ttl_6_months')},
      {'months': 12, 'label': l10n.translate('security_account_ttl_1_year')},
      {'months': 24, 'label': l10n.translate('security_account_ttl_2_years')},
    ];

    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                child: Text(
                  l10n.translate('security_account_ttl_title'),
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
              ),
              const Divider(),
              ...options.map((opt) {
                final months = opt['months'] as int;
                final label = opt['label'] as String;
                final isSelected = provider.accountTTLMonths == months;

                return ListTile(
                  title: Text(label),
                  trailing: isSelected
                      ? Check(
                          width: 20,
                          height: 20,
                          color: Theme.of(context).primaryColor,
                        )
                      : null,
                  onTap: () async {
                    Navigator.pop(ctx);
                    HapticFeedback.lightImpact();
                    final success = await provider.saveAccountTTL(months);
                    if (context.mounted && success) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(l10n.translate('settings_saved'))),
                      );
                    }
                  },
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  void _show2FADialog(
    BuildContext context, {
    required bool isChanging,
    String initialRecoveryEmail = '',
  }) {
    final l10n = context.l10n;
    final provider = context.read<PrivacySettingsProvider>();
    final currentCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final confirmCtrl = TextEditingController();
    final emailCtrl = TextEditingController(text: initialRecoveryEmail);
    String? errorText;
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(
            isChanging
                ? l10n.translate('security_2fa_change_password')
                : l10n.translate('security_2fa_setup_title'),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: currentCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: isChanging
                        ? l10n.translate('security_2fa_current_password_label')
                        : l10n.translate('security_current_account_password_label'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: passwordCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.translate('security_2fa_new_password_label'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: confirmCtrl,
                  obscureText: true,
                  decoration: InputDecoration(
                    labelText: l10n.translate('security_2fa_confirm_password_label'),
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  decoration: InputDecoration(
                    labelText: l10n.translate('security_recovery_email_label'),
                  ),
                ),
                if (errorText != null) ...[
                  const SizedBox(height: 10),
                  Text(
                    errorText!,
                    style: const TextStyle(color: Colors.red, fontSize: 13),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: Text(l10n.translate('common_cancel')),
            ),
            TextButton(
              onPressed: saving
                  ? null
                  : () async {
                      final cur = currentCtrl.text.trim();
                      final np = passwordCtrl.text.trim();
                      final cp = confirmCtrl.text.trim();
                      if (cur.isEmpty) {
                        setDialogState(() {
                          errorText = l10n.translate('email_enter_current_password');
                        });
                        return;
                      }
                      if (np.length < 6) {
                        setDialogState(() {
                          errorText = l10n.translate('validation_password_length');
                        });
                        return;
                      }
                      if (np != cp) {
                        setDialogState(() {
                          errorText = l10n.translate('security_2fa_passwords_mismatch');
                        });
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        errorText = null;
                      });
                      final res = await provider.enable2FA(
                        np,
                        emailCtrl.text.trim(),
                        currentPassword: isChanging ? null : cur,
                        current2faPassword: isChanging ? cur : null,
                      );
                      if (!ctx.mounted) return;
                      if (res['success'] == true) {
                        Navigator.pop(ctx);
                        final codes = (res['recovery_codes'] as List?)
                                ?.map((e) => e.toString())
                                .toList() ??
                            <String>[];
                        if (codes.isNotEmpty && context.mounted) {
                          _showRecoveryCodesDialog(context, codes);
                        }
                      } else {
                        setDialogState(() {
                          saving = false;
                          errorText = res['error'] == 'invalid_current_password'
                              ? l10n.translate('email_error_invalid_password')
                              : l10n.translate('common_error');
                        });
                      }
                    },
              child: saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.translate('common_save')),
            ),
          ],
        ),
      ),
    );
  }

  void _showDisable2FADialog(BuildContext context) {
    final l10n = context.l10n;
    final provider = context.read<PrivacySettingsProvider>();
    final passwordCtrl = TextEditingController();
    String? errorText;
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.translate('security_2fa_disable_title')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(l10n.translate('security_2fa_disable_prompt')),
              const SizedBox(height: 12),
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l10n.translate('security_password_label'),
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 10),
                Text(
                  errorText!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: Text(l10n.translate('common_cancel')),
            ),
            TextButton(
              onPressed: saving
                  ? null
                  : () async {
                      final pwd = passwordCtrl.text;
                      if (pwd.isEmpty) {
                        setDialogState(() {
                          errorText = l10n.translate('validation_enter_password');
                        });
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        errorText = null;
                      });
                      final res = await provider.disable2FA(password: pwd);
                      if (!ctx.mounted) return;
                      if (res['success'] == true) {
                        Navigator.pop(ctx);
                      } else {
                        setDialogState(() {
                          saving = false;
                          errorText = l10n.translate('email_error_invalid_password');
                        });
                      }
                    },
              child: Text(
                l10n.translate('security_2fa_disable_confirm'),
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRecoveryEmailDialog(BuildContext context, String currentEmail) {
    final l10n = context.l10n;
    final provider = context.read<PrivacySettingsProvider>();
    final emailCtrl = TextEditingController(text: currentEmail);
    final twoFaPwdCtrl = TextEditingController();
    String? errorText;
    bool saving = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.translate('security_recovery_email')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: emailCtrl,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: l10n.translate('security_recovery_email_label'),
                ),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: twoFaPwdCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l10n.translate('security_2fa_current_password_label'),
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 10),
                Text(
                  errorText!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(ctx),
              child: Text(l10n.translate('common_cancel')),
            ),
            TextButton(
              onPressed: saving
                  ? null
                  : () async {
                      final pwd = twoFaPwdCtrl.text.trim();
                      if (pwd.length < 6) {
                        setDialogState(() {
                          errorText = l10n.translate('validation_password_length');
                        });
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        errorText = null;
                      });
                      final res = await provider.enable2FA(
                        pwd,
                        emailCtrl.text.trim(),
                        current2faPassword: pwd,
                      );
                      if (!ctx.mounted) return;
                      if (res['success'] == true) {
                        Navigator.pop(ctx);
                        final codes = (res['recovery_codes'] as List?)
                                ?.map((e) => e.toString())
                                .toList() ??
                            <String>[];
                        if (codes.isNotEmpty && context.mounted) {
                          _showRecoveryCodesDialog(context, codes);
                        }
                      } else {
                        setDialogState(() {
                          saving = false;
                          errorText = l10n.translate('email_error_invalid_2fa');
                        });
                      }
                    },
              child: Text(l10n.translate('common_save')),
            ),
          ],
        ),
      ),
    );
  }

  void _showRegenerateCodesDialog(BuildContext context) {
    final l10n = context.l10n;
    final provider = context.read<PrivacySettingsProvider>();
    final passwordCtrl = TextEditingController();
    String? errorText;
    bool loading = false;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: Text(l10n.translate('security_2fa_regenerate_codes')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: passwordCtrl,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: l10n.translate('security_2fa_current_password_label'),
                ),
              ),
              if (errorText != null) ...[
                const SizedBox(height: 10),
                Text(
                  errorText!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: loading ? null : () => Navigator.pop(ctx),
              child: Text(l10n.translate('common_cancel')),
            ),
            TextButton(
              onPressed: loading
                  ? null
                  : () async {
                      final pwd = passwordCtrl.text;
                      if (pwd.isEmpty) {
                        setDialogState(() {
                          errorText = l10n.translate('validation_enter_password');
                        });
                        return;
                      }
                      setDialogState(() {
                        loading = true;
                        errorText = null;
                      });
                      final res = await provider.regenerateRecoveryCodes(pwd);
                      if (!ctx.mounted) return;
                      if (res['success'] == true) {
                        Navigator.pop(ctx);
                        final codes = (res['recovery_codes'] as List?)
                                ?.map((e) => e.toString())
                                .toList() ??
                            <String>[];
                        if (context.mounted) {
                          _showRecoveryCodesDialog(context, codes);
                        }
                      } else {
                        setDialogState(() {
                          loading = false;
                          errorText = l10n.translate('email_error_invalid_2fa');
                        });
                      }
                    },
              child: Text(l10n.translate('common_confirm')),
            ),
          ],
        ),
      ),
    );
  }

  void _showRecoveryCodesDialog(BuildContext context, List<String> codes) {
    final l10n = context.l10n;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('security_2fa_codes_title')),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                l10n.translate('security_2fa_codes_warning'),
                style: TextStyle(color: Colors.orange[800], fontSize: 13),
              ),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  children: codes
                      .map(
                        (c) => SelectableText(
                          c,
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w600,
                            fontSize: 14,
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton.icon(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: codes.join('\n')));
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(l10n.translate('security_2fa_codes_copied'))),
              );
            },
            icon: const Icon(Icons.copy_all, size: 18),
            label: Text(l10n.translate('common_copy')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(l10n.translate('common_done')),
          ),
        ],
      ),
    );
  }

  void _showAutoLockPicker(BuildContext context) {
    final l10n = context.l10n;
    final provider = context.read<PrivacySettingsProvider>();
    final appLock = AppLockService.instance;
    final options = ['immediately', '1min', '5min', '15min', '1hour'];
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: options.map((opt) {
            final isSelected = appLock.autoLockTimeout == opt;
            return ListTile(
              title: Text(_autoLockLabel(l10n, opt)),
              trailing: isSelected
                  ? Check(width: 20, height: 20, color: Theme.of(context).primaryColor)
                  : null,
              onTap: () async {
                HapticFeedback.lightImpact();
                await appLock.setAutoLockTimeout(opt);
                await provider.saveAppLock(AppLockSettings(
                  hasPin: appLock.hasPin,
                  biometricsEnabled: appLock.biometricsEnabled,
                  autoLockTimeout: opt,
                ));
                if (ctx.mounted) Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}
