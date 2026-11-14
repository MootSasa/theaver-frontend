import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';

/// 3-step account password recovery screen using Email OTP and optional 2FA / recovery code.
class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final _emailCtrl = TextEditingController();
  final _codeCtrl = TextEditingController();
  final _newPwdCtrl = TextEditingController();
  final _confirmPwdCtrl = TextEditingController();
  final _twoFactorCtrl = TextEditingController();

  int _step = 1; // 1 = email, 2 = OTP + new password, 3 = 2FA verification
  bool _useRecoveryCode = false;
  bool _obscureNew = true;
  bool _isLoading = false;
  String? _errorMessage;
  int _cooldown = 0;
  Timer? _cooldownTimer;

  @override
  void initState() {
    super.initState();
    if (widget.initialEmail != null && widget.initialEmail!.isNotEmpty) {
      _emailCtrl.text = widget.initialEmail!;
    }
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _emailCtrl.dispose();
    _codeCtrl.dispose();
    _newPwdCtrl.dispose();
    _confirmPwdCtrl.dispose();
    _twoFactorCtrl.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    setState(() => _cooldown = seconds > 0 ? seconds : 60);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      if (_cooldown <= 1) {
        t.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  String _mapError(AppLocalizations l10n, Map<String, dynamic> res) {
    final err = res['error']?.toString() ?? '';
    switch (err) {
      case 'email_not_configured':
        return l10n.translate('email_error_not_configured');
      case 'cooldown':
        final s = (res['cooldown_seconds'] as num?)?.toInt() ?? 60;
        return l10n.translate('email_error_cooldown').replaceAll('{seconds}', '$s');
      case 'invalid_code':
      case 'code_expired':
        return l10n.translate('email_error_invalid_code');
      case 'too_many_attempts':
        return l10n.translate('email_error_too_many_attempts');
      case 'invalid_2fa_password':
        return l10n.translate('email_error_invalid_2fa');
      case 'password_too_short':
        return l10n.translate('validation_password_length');
      default:
        return res['message']?.toString().isNotEmpty == true
            ? res['message'].toString()
            : l10n.translate('common_error');
    }
  }

  Future<void> _sendCode() async {
    final l10n = context.l10n;
    final email = _emailCtrl.text.trim();
    if (!email.contains('@')) {
      setState(() => _errorMessage = l10n.translate('email_error_invalid_format'));
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });
    final res = await AuthService.sendPasswordResetCode(email: email);
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['success'] == true) {
      _startCooldown((res['cooldown_seconds'] as num?)?.toInt() ?? 60);
      setState(() => _step = 2);
    } else {
      if (res['error'] == 'cooldown') {
        _startCooldown((res['cooldown_seconds'] as num?)?.toInt() ?? 60);
        setState(() => _step = 2);
      }
      setState(() => _errorMessage = _mapError(l10n, res));
    }
  }

  Future<void> _submitReset() async {
    final l10n = context.l10n;
    final email = _emailCtrl.text.trim();
    final code = _codeCtrl.text.trim();
    final newPwd = _newPwdCtrl.text;
    final confirmPwd = _confirmPwdCtrl.text;

    if (code.length < 4) {
      setState(() => _errorMessage = l10n.translate('email_enter_code_hint'));
      return;
    }
    if (newPwd.length < 6) {
      setState(() => _errorMessage = l10n.translate('validation_password_length'));
      return;
    }
    if (newPwd != confirmPwd) {
      setState(() => _errorMessage = l10n.translate('security_2fa_passwords_mismatch'));
      return;
    }
    if (_step == 3 && _twoFactorCtrl.text.trim().isEmpty) {
      setState(() => _errorMessage = l10n.translate('recovery_enter_2fa_hint'));
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final twoFactorInput = _twoFactorCtrl.text.trim();
    final res = await AuthService.resetPasswordWithCode(
      email: email,
      code: code,
      newPassword: newPwd,
      twoFactorPassword: (_step == 3 && !_useRecoveryCode) ? twoFactorInput : null,
      recoveryCode: (_step == 3 && _useRecoveryCode) ? twoFactorInput : null,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['success'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('recovery_password_updated'))),
      );
      Navigator.pop(context);
      return;
    }

    if (res['requires_2fa'] == true && _step < 3) {
      setState(() {
        _step = 3;
        _errorMessage = null;
      });
      return;
    }

    setState(() => _errorMessage = _mapError(l10n, res));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('recovery_title')),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.lock_reset, size: 72, color: Colors.blue),
              const SizedBox(height: 16),
              Text(
                l10n.translate('recovery_subtitle'),
                style: theme.textTheme.bodyMedium?.copyWith(color: Colors.grey[600]),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),

              TextField(
                controller: _emailCtrl,
                enabled: _step == 1 && !_isLoading,
                keyboardType: TextInputType.emailAddress,
                decoration: InputDecoration(
                  labelText: l10n.translate('auth_email'),
                  prefixIcon: const Icon(Icons.email_outlined),
                  border: const OutlineInputBorder(
                    borderRadius: BorderRadius.all(Radius.circular(14)),
                  ),
                ),
              ),

              if (_step >= 2) ...[
                const SizedBox(height: 16),
                TextField(
                  controller: _codeCtrl,
                  enabled: _step == 2 && !_isLoading,
                  keyboardType: TextInputType.number,
                  maxLength: 6,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    labelText: l10n.translate('email_otp_label'),
                    counterText: '',
                    prefixIcon: const Icon(Icons.pin_outlined),
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _newPwdCtrl,
                  enabled: _step == 2 && !_isLoading,
                  obscureText: _obscureNew,
                  decoration: InputDecoration(
                    labelText: l10n.translate('recovery_new_password'),
                    prefixIcon: const Icon(Icons.lock_outline),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureNew ? Icons.visibility_off : Icons.visibility),
                      onPressed: () => setState(() => _obscureNew = !_obscureNew),
                    ),
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _confirmPwdCtrl,
                  enabled: _step == 2 && !_isLoading,
                  obscureText: _obscureNew,
                  decoration: InputDecoration(
                    labelText: l10n.translate('security_2fa_confirm_password_label'),
                    prefixIcon: const Icon(Icons.lock_outline),
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                  ),
                ),
              ],

              if (_step == 3) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primaryContainer.withOpacity(0.35),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    l10n.translate('recovery_2fa_step_hint'),
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: _twoFactorCtrl,
                  enabled: !_isLoading,
                  obscureText: !_useRecoveryCode,
                  decoration: InputDecoration(
                    labelText: _useRecoveryCode
                        ? l10n.translate('auth_2fa_backup_code_label')
                        : l10n.translate('security_2fa_password_label'),
                    prefixIcon: const Icon(Icons.shield_outlined),
                    border: const OutlineInputBorder(
                      borderRadius: BorderRadius.all(Radius.circular(14)),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _isLoading
                        ? null
                        : () {
                            setState(() {
                              _useRecoveryCode = !_useRecoveryCode;
                              _twoFactorCtrl.clear();
                            });
                          },
                    child: Text(
                      _useRecoveryCode
                          ? l10n.translate('auth_2fa_use_password')
                          : l10n.translate('auth_2fa_use_backup_code'),
                    ),
                  ),
                ),
              ],

              if (_errorMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  _errorMessage!,
                  style: const TextStyle(color: Colors.red, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ],

              const SizedBox(height: 20),
              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _isLoading
                      ? null
                      : (_step == 1 ? _sendCode : _submitReset),
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  child: _isLoading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                          ),
                        )
                      : Text(
                          _step == 1
                              ? l10n.translate('recovery_send_button')
                              : l10n.translate('recovery_reset_button'),
                        ),
                ),
              ),

              if (_step == 2) ...[
                const SizedBox(height: 10),
                TextButton(
                  onPressed: (_isLoading || _cooldown > 0) ? null : _sendCode,
                  child: Text(
                    _cooldown > 0
                        ? l10n
                            .translate('email_resend_in')
                            .replaceAll('{seconds}', '$_cooldown')
                        : l10n.translate('email_resend_code'),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
