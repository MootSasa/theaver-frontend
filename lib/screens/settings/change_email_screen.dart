import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:iconoir_flutter/regular/mail.dart';
import 'package:iconoir_flutter/regular/check.dart';
import 'package:iconoir_flutter/regular/lock.dart';

import '../../l10n/app_localizations.dart';
import '../../services/account_manager.dart';
import '../../services/auth_service.dart';
import '../../services/privacy_settings_provider.dart';
import '../../services/settings_service.dart';
import '../../widgets/settings/settings_floating_header.dart';
import '../../widgets/settings/settings_group.dart';

/// Screen for viewing, verifying, and changing the account email via OTP.
class ChangeEmailScreen extends StatefulWidget {
  const ChangeEmailScreen({super.key});

  @override
  State<ChangeEmailScreen> createState() => _ChangeEmailScreenState();
}

class _ChangeEmailScreenState extends State<ChangeEmailScreen> {
  final _verifyCodeCtrl = TextEditingController();
  final _newEmailCtrl = TextEditingController();
  final _currentPasswordCtrl = TextEditingController();
  final _twoFactorCtrl = TextEditingController();
  final _changeCodeCtrl = TextEditingController();

  bool _verifyCodeSent = false;
  bool _changeCodeSent = false;
  bool _requires2FA = false;
  bool _isSendingVerify = false;
  bool _isConfirmingVerify = false;
  bool _isSendingChange = false;
  bool _isConfirmingChange = false;

  int _verifyCooldown = 0;
  int _changeCooldown = 0;
  Timer? _verifyTimer;
  Timer? _changeTimer;

  String _currentEmail = '';
  bool _emailVerified = false;
  String? _statusMessage;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    _loadLocalEmailState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshProfile();
    });
  }

  @override
  void dispose() {
    _verifyTimer?.cancel();
    _changeTimer?.cancel();
    _verifyCodeCtrl.dispose();
    _newEmailCtrl.dispose();
    _currentPasswordCtrl.dispose();
    _twoFactorCtrl.dispose();
    _changeCodeCtrl.dispose();
    super.dispose();
  }

  void _loadLocalEmailState() {
    final acc = AccountManager().currentAccount;
    final profile = SettingsService().userProfile;
    _currentEmail = (acc?.email?.isNotEmpty == true ? acc!.email! : profile?.email) ?? '';
    _emailVerified = acc?.emailVerified ?? false;
    final tfaEnabled = context.read<PrivacySettingsProvider>().twoFactor.enabled;
    _requires2FA = _requires2FA || tfaEnabled;
  }

  Future<void> _refreshProfile() async {
    try {
      await context.read<PrivacySettingsProvider>().load2FA();
      final res = await AuthService.getCurrentUser();
      if (!mounted) return;
      if (res['success'] == true) {
        setState(_loadLocalEmailState);
      }
    } catch (_) {}
  }

  void _startVerifyCooldown(int seconds) {
    _verifyTimer?.cancel();
    setState(() => _verifyCooldown = seconds > 0 ? seconds : 60);
    _verifyTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_verifyCooldown <= 1) {
        t.cancel();
        setState(() => _verifyCooldown = 0);
      } else {
        setState(() => _verifyCooldown--);
      }
    });
  }

  void _startChangeCooldown(int seconds) {
    _changeTimer?.cancel();
    setState(() => _changeCooldown = seconds > 0 ? seconds : 60);
    _changeTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_changeCooldown <= 1) {
        t.cancel();
        setState(() => _changeCooldown = 0);
      } else {
        setState(() => _changeCooldown--);
      }
    });
  }

  void _setStatus(String msg, {bool isError = false}) {
    setState(() {
      _statusMessage = msg;
      _statusIsError = isError;
    });
  }

  String _mapBackendError(AppLocalizations l10n, Map<String, dynamic> res) {
    final err = res['error']?.toString() ?? '';
    switch (err) {
      case 'email_not_configured':
        return l10n.translate('email_error_not_configured');
      case 'email_taken':
        return l10n.translate('email_error_taken');
      case 'invalid_password':
        return l10n.translate('email_error_invalid_password');
      case 'invalid_2fa_password':
        return l10n.translate('email_error_invalid_2fa');
      case 'cooldown':
        final wait = (res['cooldown_seconds'] as num?)?.toInt() ?? 60;
        return l10n.translate('email_error_cooldown').replaceAll('{seconds}', '$wait');
      case 'invalid_code':
      case 'code_expired':
        return l10n.translate('email_error_invalid_code');
      case 'too_many_attempts':
        return l10n.translate('email_error_too_many_attempts');
      default:
        return res['message']?.toString().isNotEmpty == true
            ? res['message'].toString()
            : l10n.translate('common_error');
    }
  }

  Future<void> _sendVerifyCode() async {
    final l10n = context.l10n;
    setState(() {
      _isSendingVerify = true;
      _statusMessage = null;
    });
    final res = await AuthService.sendEmailVerifyCode();
    if (!mounted) return;
    setState(() => _isSendingVerify = false);
    if (res['success'] == true) {
      setState(() => _verifyCodeSent = true);
      _startVerifyCooldown((res['cooldown_seconds'] as num?)?.toInt() ?? 60);
      _setStatus(l10n.translate('email_code_sent').replaceAll('{email}', _currentEmail));
    } else {
      if (res['error'] == 'cooldown') {
        _startVerifyCooldown((res['cooldown_seconds'] as num?)?.toInt() ?? 60);
      }
      _setStatus(_mapBackendError(l10n, res), isError: true);
    }
  }

  Future<void> _confirmVerifyCode() async {
    final l10n = context.l10n;
    final code = _verifyCodeCtrl.text.trim();
    if (code.length < 4) {
      _setStatus(l10n.translate('email_enter_code_hint'), isError: true);
      return;
    }
    setState(() {
      _isConfirmingVerify = true;
      _statusMessage = null;
    });
    final res = await AuthService.confirmEmailVerify(code);
    if (!mounted) return;
    setState(() => _isConfirmingVerify = false);
    if (res['success'] == true) {
      setState(() {
        _emailVerified = true;
        _verifyCodeSent = false;
        _verifyCodeCtrl.clear();
        if (res['email'] != null && res['email'].toString().isNotEmpty) {
          _currentEmail = res['email'].toString();
        }
      });
      _setStatus(l10n.translate('email_verified_success'));
    } else {
      _setStatus(_mapBackendError(l10n, res), isError: true);
    }
  }

  Future<void> _requestEmailChange() async {
    final l10n = context.l10n;
    final newEmail = _newEmailCtrl.text.trim();
    final currentPassword = _currentPasswordCtrl.text;
    final twoFactor = _twoFactorCtrl.text;

    if (!newEmail.contains('@') || !newEmail.contains('.')) {
      _setStatus(l10n.translate('email_error_invalid_format'), isError: true);
      return;
    }
    if (currentPassword.isEmpty) {
      _setStatus(l10n.translate('email_enter_current_password'), isError: true);
      return;
    }

    setState(() {
      _isSendingChange = true;
      _statusMessage = null;
    });
    final res = await AuthService.requestEmailChange(
      newEmail: newEmail,
      currentPassword: currentPassword,
      twoFactorPassword: _requires2FA ? twoFactor : null,
    );
    if (!mounted) return;
    setState(() => _isSendingChange = false);
    if (res['success'] == true) {
      setState(() => _changeCodeSent = true);
      _startChangeCooldown((res['cooldown_seconds'] as num?)?.toInt() ?? 60);
      _setStatus(l10n.translate('email_code_sent').replaceAll('{email}', newEmail));
    } else {
      if (res['requires_2fa'] == true) {
        setState(() => _requires2FA = true);
      }
      if (res['error'] == 'cooldown') {
        _startChangeCooldown((res['cooldown_seconds'] as num?)?.toInt() ?? 60);
      }
      _setStatus(_mapBackendError(l10n, res), isError: true);
    }
  }

  Future<void> _confirmEmailChange() async {
    final l10n = context.l10n;
    final newEmail = _newEmailCtrl.text.trim();
    final code = _changeCodeCtrl.text.trim();
    if (code.length < 4) {
      _setStatus(l10n.translate('email_enter_code_hint'), isError: true);
      return;
    }
    setState(() {
      _isConfirmingChange = true;
      _statusMessage = null;
    });
    final res = await AuthService.confirmEmailChange(newEmail: newEmail, code: code);
    if (!mounted) return;
    setState(() => _isConfirmingChange = false);
    if (res['success'] == true) {
      setState(() {
        _currentEmail = res['email']?.toString() ?? newEmail;
        _emailVerified = true;
        _changeCodeSent = false;
        _verifyCodeSent = false;
        _newEmailCtrl.clear();
        _currentPasswordCtrl.clear();
        _twoFactorCtrl.clear();
        _changeCodeCtrl.clear();
      });
      _setStatus(l10n.translate('email_changed_success'));
    } else {
      _setStatus(_mapBackendError(l10n, res), isError: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final tfaEnabled = context.watch<PrivacySettingsProvider>().twoFactor.enabled;
    final show2FAField = _requires2FA || tfaEnabled;

    return SettingsFloatingScaffold(
      title: l10n.translate('email_screen_title'),
      body: ListView(
        padding: EdgeInsets.only(
          top: SettingsFloatingHeader.topClearanceOf(context) + 8,
          bottom: 32,
        ),
        children: [
          if (_statusMessage != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: (_statusIsError ? Colors.red : Colors.green).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: (_statusIsError ? Colors.red : Colors.green).withOpacity(0.35),
                  ),
                ),
                child: Text(
                  _statusMessage!,
                  style: TextStyle(
                    color: _statusIsError ? Colors.red[700] : Colors.green[700],
                    fontSize: 13,
                  ),
                ),
              ),
            ),

          SettingsGroup(
            title: l10n.translate('email_current_section'),
            children: [
              ListTile(
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: (_emailVerified ? Colors.green : Colors.orange).withOpacity(0.14),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  alignment: Alignment.center,
                  child: Mail(
                    width: 22,
                    height: 22,
                    color: _emailVerified ? Colors.green : Colors.orange,
                  ),
                ),
                title: Text(
                  _currentEmail.isEmpty
                      ? l10n.translate('security_not_set')
                      : _currentEmail,
                ),
                subtitle: Text(
                  _currentEmail.isEmpty
                      ? l10n.translate('email_add_hint')
                      : (_emailVerified
                          ? l10n.translate('email_status_verified')
                          : l10n.translate('email_status_unverified')),
                  style: TextStyle(
                    color: _emailVerified ? Colors.green : Colors.orange[800],
                  ),
                ),
                trailing: _emailVerified
                    ? const Check(width: 20, height: 20, color: Colors.green)
                    : null,
              ),
              if (_currentEmail.isNotEmpty && !_emailVerified)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (_verifyCodeSent) ...[
                        TextField(
                          controller: _verifyCodeCtrl,
                          keyboardType: TextInputType.number,
                          maxLength: 6,
                          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                          decoration: InputDecoration(
                            labelText: l10n.translate('email_otp_label'),
                            counterText: '',
                          ),
                        ),
                        const SizedBox(height: 12),
                        ElevatedButton(
                          onPressed: _isConfirmingVerify ? null : _confirmVerifyCode,
                          child: _isConfirmingVerify
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2),
                                )
                              : Text(l10n.translate('email_confirm_verify')),
                        ),
                        const SizedBox(height: 8),
                      ],
                      OutlinedButton(
                        onPressed: (_isSendingVerify || _verifyCooldown > 0)
                            ? null
                            : _sendVerifyCode,
                        child: Text(
                          _verifyCooldown > 0
                              ? l10n
                                  .translate('email_resend_in')
                                  .replaceAll('{seconds}', '$_verifyCooldown')
                              : l10n.translate('email_send_verify_code'),
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),

          SettingsGroup(
            title: l10n.translate('email_change_section'),
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    TextField(
                      controller: _newEmailCtrl,
                      keyboardType: TextInputType.emailAddress,
                      decoration: InputDecoration(
                        labelText: l10n.translate('email_new_label'),
                        prefixIcon: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Mail(width: 20, height: 20),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _currentPasswordCtrl,
                      obscureText: true,
                      decoration: InputDecoration(
                        labelText: l10n.translate('email_current_password_label'),
                        prefixIcon: const Padding(
                          padding: EdgeInsets.all(12),
                          child: Lock(width: 20, height: 20),
                        ),
                      ),
                    ),
                    if (show2FAField) ...[
                      const SizedBox(height: 12),
                      TextField(
                        controller: _twoFactorCtrl,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: l10n.translate('email_2fa_password_label'),
                          prefixIcon: const Padding(
                            padding: EdgeInsets.all(12),
                            child: Lock(width: 20, height: 20),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: (_isSendingChange || _changeCooldown > 0)
                          ? null
                          : _requestEmailChange,
                      child: _isSendingChange
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(
                              _changeCooldown > 0
                                  ? l10n
                                      .translate('email_resend_in')
                                      .replaceAll('{seconds}', '$_changeCooldown')
                                  : l10n.translate('email_send_change_code'),
                            ),
                    ),
                    if (_changeCodeSent) ...[
                      const SizedBox(height: 16),
                      const Divider(),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _changeCodeCtrl,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        decoration: InputDecoration(
                          labelText: l10n.translate('email_otp_label'),
                          counterText: '',
                        ),
                      ),
                      const SizedBox(height: 12),
                      FilledButton(
                        onPressed: _isConfirmingChange ? null : _confirmEmailChange,
                        child: _isConfirmingChange
                            ? const SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              )
                            : Text(l10n.translate('email_confirm_change')),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Text(
              l10n.translate('email_change_footer'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
