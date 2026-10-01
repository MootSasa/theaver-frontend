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
import '../../services/privacy_settings_provider.dart';
import '../../services/settings_service.dart';
import '../../widgets/settings/settings_group.dart';
import '../../widgets/common/adaptive_switch.dart';
import 'passcode_screen.dart';
import 'blocked_users_screen.dart';
import 'devices_screen.dart';

/// Screen "Security" — 2FA, App Lock, Blocked Users, Active Sessions, and Account Auto-Deletion TTL
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
      context.read<PrivacySettingsProvider>().loadAccountTTL();
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(l10n.translate('security_title'))),
      body: Consumer<PrivacySettingsProvider>(
        builder: (context, provider, _) {
          final tfa = provider.twoFactor;
          final lock = provider.appLock;

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
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
                    subtitle: Text(tfa.enabled
                        ? l10n.translate('security_2fa_enabled')
                        : l10n.translate('security_2fa_disabled')),
                    trailing: AdaptiveSwitch(
                      value: tfa.enabled,
                      onChanged: (v) async {
                        HapticFeedback.lightImpact();
                        if (v) {
                          _show2FADialog(context);
                        } else {
                          await provider.disable2FA();
                        }
                      },
                    ),
                  ),
                  if (tfa.enabled)
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
                      subtitle: Text(tfa.recoveryEmail.isEmpty
                          ? l10n.translate('security_not_set')
                          : tfa.recoveryEmail),
                      trailing: NavArrowRight(
                        width: 18,
                        height: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      onTap: () =>
                          _showRecoveryEmailDialog(context, tfa.recoveryEmail),
                    ),
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
                        color: lock.hasPin
                            ? theme.colorScheme.primaryContainer.withOpacity(0.6)
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: SmartphoneDevice(
                        width: 22,
                        height: 22,
                        color: lock.hasPin
                            ? theme.colorScheme.primary
                            : Colors.grey,
                      ),
                    ),
                    title: Text(l10n.translate('security_pin_code')),
                    subtitle: Text(lock.hasPin
                        ? l10n.translate('security_pin_set')
                        : l10n.translate('security_pin_not_set')),
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
                  ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: lock.biometricsEnabled
                            ? theme.colorScheme.primaryContainer.withOpacity(0.6)
                            : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Fingerprint(
                        width: 22,
                        height: 22,
                        color: lock.biometricsEnabled
                            ? theme.colorScheme.primary
                            : Colors.grey,
                      ),
                    ),
                    title: Text(l10n.translate('security_biometrics')),
                    trailing: AdaptiveSwitch(
                      value: lock.biometricsEnabled,
                      onChanged: (v) {
                        HapticFeedback.lightImpact();
                        provider.saveAppLock(AppLockSettings(
                          hasPin: lock.hasPin,
                          biometricsEnabled: v,
                          autoLockTimeout: lock.autoLockTimeout,
                        ));
                      },
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
                      child: Timer(
                        width: 22,
                        height: 22,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    title: Text(l10n.translate('security_auto_lock')),
                    subtitle: Text(_autoLockLabel(l10n, lock.autoLockTimeout)),
                    trailing: NavArrowRight(
                      width: 18,
                      height: 18,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    onTap: () => _showAutoLockPicker(context, lock),
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
                        SnackBar(
                          content: Text(l10n.translate('settings_saved')),
                        ),
                      );
                    }
                  },
                );
              }).toList(),
            ],
          ),
        ),
      ),
    );
  }

  void _show2FADialog(BuildContext context) {
    final l10n = context.l10n;
    final provider = context.read<PrivacySettingsProvider>();
    final passwordController = TextEditingController();
    final emailController = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('security_2fa_setup_title')),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(
            controller: passwordController,
            obscureText: true,
            decoration: InputDecoration(labelText: l10n.translate('security_password_label')),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: emailController,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(labelText: l10n.translate('security_recovery_email_label')),
          ),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.translate('common_cancel'))),
          TextButton(
            onPressed: () async {
              await provider.enable2FA(passwordController.text, emailController.text);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(l10n.translate('common_save')),
          ),
        ],
      ),
    );
  }

  void _showRecoveryEmailDialog(BuildContext context, String currentEmail) {
    final l10n = context.l10n;
    final provider = context.read<PrivacySettingsProvider>();
    final controller = TextEditingController(text: currentEmail);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.translate('security_recovery_email')),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.emailAddress,
          decoration: InputDecoration(labelText: l10n.translate('security_recovery_email_label')),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: Text(l10n.translate('common_cancel'))),
          TextButton(
            onPressed: () async {
              await provider.enable2FA('', controller.text);
              if (ctx.mounted) Navigator.pop(ctx);
            },
            child: Text(l10n.translate('common_save')),
          ),
        ],
      ),
    );
  }

  void _showAutoLockPicker(BuildContext context, AppLockSettings lock) {
    final l10n = context.l10n;
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
            final isSelected = lock.autoLockTimeout == opt;
            return ListTile(
              title: Text(_autoLockLabel(l10n, opt)),
              trailing: isSelected
                  ? Check(width: 20, height: 20, color: Theme.of(context).primaryColor)
                  : null,
              onTap: () {
                HapticFeedback.lightImpact();
                context.read<PrivacySettingsProvider>().saveAppLock(AppLockSettings(
                  hasPin: lock.hasPin,
                  biometricsEnabled: lock.biometricsEnabled,
                  autoLockTimeout: opt,
                ));
                Navigator.pop(ctx);
              },
            );
          }).toList(),
        ),
      ),
    );
  }
}
