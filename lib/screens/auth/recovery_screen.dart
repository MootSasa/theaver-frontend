import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/glass_toast_service.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/auth/theav_auth_primitives.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/settings/settings_floating_header.dart';

/// Password recovery screen rebuilt onto Theaver's native design system:
/// - Step 1: Enter verified account email
/// - Step 2: Enter 6-digit OTP via [TheavOtpPinRow] and new password
/// - Step 3: Optional 2FA cloud password or recovery code confirmation
class RecoveryScreen extends StatefulWidget {
  const RecoveryScreen({super.key, this.initialEmail});

  final String? initialEmail;

  @override
  State<RecoveryScreen> createState() => _RecoveryScreenState();
}

class _RecoveryScreenState extends State<RecoveryScreen> {
  final _emailCtrl = TextEditingController();
  final _newPwdCtrl = TextEditingController();
  final _confirmPwdCtrl = TextEditingController();
  final _twoFactorCtrl = TextEditingController();

  int _step = 1;
  bool _stepForward = true;
  bool _isLoading = false;
  bool _obscureNew = true;
  bool _useRecoveryCode = false;
  String _otpCode = '';
  int _otpShakeCounter = 0;
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
    _newPwdCtrl.dispose();
    _confirmPwdCtrl.dispose();
    _twoFactorCtrl.dispose();
    super.dispose();
  }

  void _startCooldown(int seconds) {
    _cooldownTimer?.cancel();
    if (seconds <= 0) return;
    setState(() => _cooldown = seconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldown <= 1) {
        timer.cancel();
        setState(() => _cooldown = 0);
      } else {
        setState(() => _cooldown--);
      }
    });
  }

  Future<void> _sendCode() async {
    final l10n = context.l10n;
    final email = _emailCtrl.text.trim();
    if (email.isEmpty || !email.contains('@')) {
      setState(() => _errorMessage = l10n.translate('recovery_invalid_email'));
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await AuthService.sendPasswordResetCode(
      email: email,
      locale: l10n.locale.languageCode,
    );
    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['success'] == true) {
      final cd = (res['cooldown_seconds'] as num?)?.toInt() ?? 60;
      _startCooldown(cd > 0 ? cd : 60);
      setState(() {
        _stepForward = true;
        _step = 2;
      });
      GlassToastService().show(
        context,
        l10n.translate('email_code_sent_short').replaceAll('{email}', email),
        icon: Icons.mark_email_read_outlined,
      );
      return;
    }

    final cd = (res['cooldown_seconds'] as num?)?.toInt() ?? 0;
    if (cd > 0) _startCooldown(cd);
    setState(() {
      _errorMessage = _mapError(l10n, res['error'], res['message']);
    });
  }

  Future<void> _submitReset() async {
    final l10n = context.l10n;
    final code = _otpCode.trim();
    final newPwd = _newPwdCtrl.text;
    final confirmPwd = _confirmPwdCtrl.text;

    if (code.length < 6) {
      setState(() {
        _otpShakeCounter++;
        _errorMessage = l10n.translate('email_error_invalid_code');
      });
      return;
    }
    if (newPwd.length < 8) {
      setState(() {
        _errorMessage = l10n.trOr(
          'register_password_min_length',
          'Password must be at least 8 characters',
        );
      });
      return;
    }
    if (newPwd != confirmPwd) {
      setState(() {
        _errorMessage = l10n.translate('security_2fa_passwords_mismatch');
      });
      return;
    }

    if (_step == 3 && _twoFactorCtrl.text.trim().isEmpty) {
      setState(() {
        _errorMessage = l10n.translate('auth_2fa_enter_password_prompt');
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await AuthService.resetPasswordWithCode(
      email: _emailCtrl.text.trim(),
      code: code,
      newPassword: newPwd,
      twoFactorPassword: _step == 3 && !_useRecoveryCode
          ? _twoFactorCtrl.text
          : null,
      recoveryCode: _step == 3 && _useRecoveryCode
          ? _twoFactorCtrl.text.trim()
          : null,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['success'] == true) {
      GlassToastService().show(
        context,
        l10n.translate('recovery_password_updated'),
        icon: Icons.check_circle_outline,
      );
      Navigator.of(context).pop();
      return;
    }

    if (res['requires_2fa'] == true && _step != 3) {
      setState(() {
        _stepForward = true;
        _step = 3;
        _errorMessage = null;
      });
      return;
    }

    if (res['error'] == 'invalid_code') {
      _otpShakeCounter++;
    }
    setState(() {
      _errorMessage = _mapError(l10n, res['error'], res['message']);
    });
  }

  String _mapError(AppLocalizations l10n, Object? code, Object? fallback) {
    switch (code?.toString()) {
      case 'invalid_code':
        return l10n.translate('email_error_invalid_code');
      case 'code_expired':
        return l10n.translate('email_error_code_expired');
      case 'too_many_attempts':
        return l10n.translate('email_error_too_many_attempts');
      case 'cooldown_active':
      case 'rate_limited':
        return l10n.translate('email_error_rate_limited');
      case 'invalid_2fa_password':
        return l10n.translate('email_error_invalid_2fa');
      case 'weak_password':
        return l10n.trOr(
          'register_password_min_length',
          'Password must be at least 8 characters',
        );
      default:
        return (fallback?.toString().isNotEmpty ?? false)
            ? fallback.toString()
            : l10n.translate('error_occurred');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.theav;
    final topClearance = SettingsFloatingHeader.topClearanceOf(context);

    return PopScope(
      canPop: _step == 1,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 1) {
          setState(() {
            _stepForward = false;
            _step = _step == 3 ? 2 : 1;
            _errorMessage = null;
          });
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          const TheavAuthWallpaperBackground(),
          SettingsFloatingScaffold(
            backgroundColor: Colors.transparent,
            title: l10n.translate('auth_recovery'),
            onBack: () {
              if (_step > 1) {
                setState(() {
                  _stepForward = false;
                  _step = _step == 3 ? 2 : 1;
                  _errorMessage = null;
                });
              } else {
                Navigator.of(context).pop();
              }
            },
            actions: [
              SettingsHeaderAction(
                tooltip: '$_step / 3',
                child: Text(
                  '$_step/3',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: palette.primary,
                  ),
                ),
                onTap: null,
              ),
            ],
            body: Stack(
              fit: StackFit.expand,
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 520),
                    child: SingleChildScrollView(
                      padding: EdgeInsets.fromLTRB(
                        0,
                        topClearance + 14,
                        0,
                        112 + MediaQuery.paddingOf(context).bottom,
                      ),
                      child: TheavStepViewport(
                        stepIndex: _step,
                        forward: _stepForward,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            child: Column(
                              children: [
                                Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    color: palette.primary.withValues(alpha: 0.14),
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: iconoir.Lock(
                                    width: 28,
                                    height: 28,
                                    color: palette.primary,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  _step == 1
                                      ? l10n.translate('recovery_title')
                                      : (_step == 2
                                          ? l10n.translate('email_enter_code')
                                          : l10n.translate(
                                              'recovery_2fa_step_title',
                                            )),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    color: palette.onSurface,
                                    letterSpacing: -0.3,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  _step == 1
                                      ? l10n.translate('recovery_description')
                                      : (_step == 2
                                          ? l10n.translate(
                                              'recovery_step2_description',
                                            )
                                          : l10n.translate(
                                              'recovery_2fa_step_hint',
                                            )),
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 14,
                                    height: 1.35,
                                    color: palette.subtext,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 18),
                          TheavInsetGroup(
                            children: [
                              TheavInlineTextField(
                                controller: _emailCtrl,
                                enabled: _step == 1 && !_isLoading,
                                placeholder: l10n.translate('auth_email'),
                                keyboardType: TextInputType.emailAddress,
                                textInputAction: _step == 1
                                    ? TextInputAction.done
                                    : TextInputAction.next,
                                prefix: iconoir.Mail(
                                  width: 19,
                                  height: 19,
                                  color: palette.subtext,
                                ),
                                onSubmitted: _step == 1 ? (_) => _sendCode() : null,
                              ),
                            ],
                          ),
                          if (_step >= 2) ...[
                            const SizedBox(height: 10),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: TheavOtpPinRow(
                                value: _otpCode,
                                errorShakeCounter: _otpShakeCounter,
                                enabled: _step == 2 && !_isLoading,
                                onChanged: (val) => _otpCode = val,
                              ),
                            ),
                            const SizedBox(height: 12),
                            TheavInsetGroup(
                              children: [
                                TheavInlineTextField(
                                  controller: _newPwdCtrl,
                                  enabled: _step == 2 && !_isLoading,
                                  obscureText: _obscureNew,
                                  placeholder: l10n.translate(
                                    'recovery_new_password_label',
                                  ),
                                  textInputAction: TextInputAction.next,
                                  prefix: iconoir.Lock(
                                    width: 19,
                                    height: 19,
                                    color: palette.subtext,
                                  ),
                                  suffix: GestureDetector(
                                    onTap: () => setState(
                                      () => _obscureNew = !_obscureNew,
                                    ),
                                    child: _obscureNew
                                        ? iconoir.Eye(
                                            width: 19,
                                            height: 19,
                                            color: palette.subtext,
                                          )
                                        : iconoir.EyeClosed(
                                            width: 19,
                                            height: 19,
                                            color: palette.subtext,
                                          ),
                                  ),
                                ),
                                TheavInlineTextField(
                                  controller: _confirmPwdCtrl,
                                  enabled: _step == 2 && !_isLoading,
                                  obscureText: _obscureNew,
                                  placeholder: l10n.translate(
                                    'security_2fa_confirm_password_label',
                                  ),
                                  textInputAction: TextInputAction.done,
                                  prefix: iconoir.Lock(
                                    width: 19,
                                    height: 19,
                                    color: palette.subtext,
                                  ),
                                  onSubmitted: (_) => _submitReset(),
                                ),
                              ],
                            ),
                          ],
                          if (_step == 3) ...[
                            const SizedBox(height: 10),
                            TheavInsetGroup(
                              children: [
                                TheavInlineTextField(
                                  controller: _twoFactorCtrl,
                                  enabled: !_isLoading,
                                  obscureText: !_useRecoveryCode,
                                  placeholder: _useRecoveryCode
                                      ? l10n.translate(
                                          'auth_2fa_backup_code_label',
                                        )
                                      : l10n.translate(
                                          'security_2fa_password_label',
                                        ),
                                  prefix: iconoir.Shield(
                                    width: 19,
                                    height: 19,
                                    color: palette.subtext,
                                  ),
                                  onSubmitted: (_) => _submitReset(),
                                ),
                                TheavListRow(
                                  title: _useRecoveryCode
                                      ? l10n.translate('auth_2fa_use_password')
                                      : l10n.translate('auth_2fa_use_backup_code'),
                                  showChevron: true,
                                  onTap: _isLoading
                                      ? null
                                      : () {
                                          HapticUtils.selection();
                                          setState(() {
                                            _useRecoveryCode = !_useRecoveryCode;
                                            _twoFactorCtrl.clear();
                                          });
                                        },
                                ),
                              ],
                            ),
                          ],
                          if (_errorMessage != null)
                            TheavAuthErrorBanner(message: _errorMessage!),
                          if (_step == 2) ...[
                            const SizedBox(height: 12),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: TheavSpringButton(
                                variant: TheavSpringButtonVariant.glass,
                                enabled: !_isLoading && _cooldown == 0,
                                label: _cooldown > 0
                                    ? l10n
                                        .translate('email_resend_cooldown')
                                        .replaceAll('{seconds}', '$_cooldown')
                                    : l10n.translate('email_resend_button'),
                                onPressed: (_isLoading || _cooldown > 0)
                                    ? null
                                    : _sendCode,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
                ),
                TheavFloatingBottomBar(
                  maxWidth: 520,
                  child: TheavSpringButton(
                    label: _step == 1
                        ? l10n.translate('recovery_send_button')
                        : l10n.translate('recovery_reset_button'),
                    isLoading: _isLoading,
                    onPressed: _step == 1 ? _sendCode : _submitReset,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
