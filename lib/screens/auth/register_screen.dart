import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:url_launcher/url_launcher.dart';

import '../../l10n/app_localizations.dart';
import '../../models/avatar_editor_models.dart';
import '../../services/auth_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/tiling_layout_controller.dart';
import '../../services/websocket_service.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../../widgets/auth/country_phone_input.dart';
import '../../widgets/auth/theav_auth_primitives.dart';
import '../../widgets/avatar_editor/theav_avatar_picker_sheet.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/settings/settings_floating_header.dart';
import '../../widgets/tiling/tiling_workspace_scaffold.dart';

/// 3-Step Registration Wizard rebuilt natively on Theaver's design system:
/// - Step 0: Email + E.164 phone ([CountryPhoneInput]), silent PoW, Stalwart OTP,
///   and optional Reverse-SMS (skipping already-verified OAuth channels).
/// - Step 1: `@username` with live availability + mandatory `>= 8` char password.
/// - Step 2: Avatar ([TheavAvatarPickerSheet] or OAuth avatar), required first name, optional last name.
class RegisterScreen extends StatefulWidget {
  final OAuthRegistrationPrefill? oauthPrefill;
  final String? initialCountryCode;
  @visibleForTesting
  final AuthProvidersConfig? debugProvidersOverride;

  const RegisterScreen({
    super.key,
    this.oauthPrefill,
    this.initialCountryCode,
    this.debugProvidersOverride,
  });

  @override
  State<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends State<RegisterScreen> {
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  final _usernameCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _confirmPasswordCtrl = TextEditingController();
  final _firstNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();

  int _step = 0;
  bool _stepForward = true;
  bool _isLoading = false;
  String? _errorMessage;

  late String _countryIso = _initialIso();
  String _currentE164Phone = '';

  // Step 0 verification state
  bool _awaitingCodes = false;
  bool _requiresEmailCode = false;
  bool _requiresReverseSms = false;
  bool _smsVerified = false;
  String _emailOtpCode = '';
  int _otpShakeCounter = 0;
  int _cooldown = 0;
  Timer? _cooldownTimer;
  Timer? _smsPollTimer;
  String? _phoneVerificationId;
  String? _smsTargetNumber;
  String? _smsBody;
  String? _smsUri;
  String? _registrationTicket;

  // Step 1 username & password state
  bool _checkingUsername = false;
  bool? _usernameAvailable;
  String? _usernameStatusReason;
  List<String> _usernameSuggestions = const [];
  Timer? _usernameDebounce;
  bool _obscurePassword = true;

  // Step 2 avatar & names state
  AvatarPickResult? _pickedAvatar;

  String _initialIso() {
    final w = widget.initialCountryCode?.trim().toUpperCase() ?? '';
    return w.length == 2 ? w : 'RU';
  }

  @override
  void initState() {
    super.initState();
    final prefill = widget.oauthPrefill;
    if (prefill != null) {
      if (prefill.email.isNotEmpty) {
        _emailCtrl.text = prefill.email;
      }
      if (prefill.phone.isNotEmpty) {
        final detected = detectCountryFromE164(
          prefill.phone,
          preferredIso: _countryIso,
        );
        if (detected != null) {
          _countryIso = detected.iso;
        }
        _phoneCtrl.text = prefill.phone;
        _currentE164Phone = prefill.phone;
      }
      if (prefill.suggestedUsername.isNotEmpty) {
        _usernameCtrl.text = prefill.suggestedUsername;
      }
      if (prefill.firstName.isNotEmpty) {
        _firstNameCtrl.text = prefill.firstName;
      }
      if (prefill.lastName.isNotEmpty) {
        _lastNameCtrl.text = prefill.lastName;
      }
    }
    _emailCtrl.addListener(_onEmailEdited);
    _usernameCtrl.addListener(_onUsernameEdited);
    _loadRegionDefaultIfNeeded();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    _smsPollTimer?.cancel();
    _usernameDebounce?.cancel();
    _emailCtrl.removeListener(_onEmailEdited);
    _usernameCtrl.removeListener(_onUsernameEdited);
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    _usernameCtrl.dispose();
    _passwordCtrl.dispose();
    _confirmPasswordCtrl.dispose();
    _firstNameCtrl.dispose();
    _lastNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadRegionDefaultIfNeeded() async {
    if (widget.initialCountryCode != null &&
        widget.initialCountryCode!.length == 2) {
      return;
    }
    if (widget.oauthPrefill?.phone.isNotEmpty ?? false) return;
    final cfg = widget.debugProvidersOverride ??
        await AuthService.fetchAuthProviders();
    if (!mounted) return;
    if (cfg.countryCode.length == 2 &&
        kTheavCountryDialCatalog.any((c) => c.iso == cfg.countryCode)) {
      setState(() => _countryIso = cfg.countryCode);
    }
  }

  void _onEmailEdited() {
    if (!mounted) return;
    setState(() {
      _registrationTicket = null;
      _awaitingCodes = false;
    });
  }

  bool get _isEmailVerifiedByOAuth {
    final p = widget.oauthPrefill;
    if (p == null || !p.emailVerified || p.email.isEmpty) return false;
    return _emailCtrl.text.trim().toLowerCase() == p.email.toLowerCase();
  }

  bool get _isPhoneVerifiedByOAuth {
    final p = widget.oauthPrefill;
    if (p == null || !p.phoneVerified || p.phone.isEmpty) return false;
    return _resolvedE164Phone == p.phone;
  }

  String get _resolvedE164Phone {
    if (_currentE164Phone.isNotEmpty) return _currentE164Phone;
    return normalizeToE164(_phoneCtrl.text, defaultIso: _countryIso) ?? '';
  }

  String _oauthProviderTitle() {
    final p = widget.oauthPrefill;
    if (p == null) return '';
    if (p.providerName.isNotEmpty) return p.providerName;
    switch (p.provider) {
      case 'yandex':
        return 'Yandex ID';
      case 'vk':
        return 'VK ID';
      case 'huawei':
        return 'Huawei ID';
      case 'google':
        return 'Google';
      case 'apple':
        return 'Apple';
      default:
        return p.provider.toUpperCase();
    }
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

  // ============ Step 0: Start & Verify Contacts ============

  Future<void> _startStep0Verification() async {
    final l10n = context.l10n;
    final email = _emailCtrl.text.trim();
    final e164Phone =
        normalizeToE164(_phoneCtrl.text, defaultIso: _countryIso) ?? '';

    if (email.isEmpty || !email.contains('@') || !email.contains('.')) {
      setState(() => _errorMessage = l10n.translate('validation_valid_email'));
      return;
    }
    if (e164Phone.isEmpty) {
      setState(() => _errorMessage = l10n.translate('validation_valid_phone'));
      return;
    }

    _currentE164Phone = e164Phone;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final useOAuthToken = widget.oauthPrefill?.oauthRegistrationToken;

    final res = await AuthService.startRegistrationVerification(
      email: email,
      phone: e164Phone,
      countryCode: _countryIso,
      oauthRegistrationToken: useOAuthToken,
      locale: l10n.locale.languageCode,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['success'] != true) {
      setState(() {
        _errorMessage = _mapBackendError(l10n, res['error'], res['message']);
      });
      return;
    }

    final instantTicket = res['registration_ticket']?.toString() ?? '';
    final needsEmail = res['requires_email_code'] == true;
    final needsSms = res['requires_reverse_sms'] == true;

    if (instantTicket.isNotEmpty && !needsEmail && !needsSms) {
      _registrationTicket = instantTicket;
      _goToStep(1);
      return;
    }

    final cd = (res['cooldown_seconds'] as num?)?.toInt() ?? 60;
    if (needsEmail && cd > 0) {
      _startCooldown(cd);
    }

    setState(() {
      _awaitingCodes = true;
      _requiresEmailCode = needsEmail;
      _requiresReverseSms = needsSms;
      _smsVerified = res['phone_verified'] == true;
      _phoneVerificationId = res['phone_verification_id']?.toString();
      _smsTargetNumber = res['sms_target_number']?.toString();
      _smsBody = res['sms_body']?.toString();
      _smsUri = res['sms_uri']?.toString();
    });

    if (needsSms && (_phoneVerificationId?.isNotEmpty ?? false)) {
      _startReverseSmsPolling();
    }
  }

  void _startReverseSmsPolling() {
    _smsPollTimer?.cancel();
    final vid = _phoneVerificationId;
    if (vid == null || vid.isEmpty) return;
    _smsPollTimer = Timer.periodic(const Duration(milliseconds: 2500), (_) async {
      final res = await AuthService.pollPhoneVerificationStatus(vid);
      if (!mounted) return;
      if (res['status'] == 'verified') {
        _smsPollTimer?.cancel();
        HapticUtils.selection();
        setState(() => _smsVerified = true);
      }
    });
  }

  Future<void> _confirmStep0Codes() async {
    final l10n = context.l10n;
    if (_requiresEmailCode && _emailOtpCode.trim().length < 6) {
      setState(() {
        _otpShakeCounter++;
        _errorMessage = l10n.translate('email_error_invalid_code');
      });
      return;
    }
    if (_requiresReverseSms && !_smsVerified) {
      setState(() {
        _errorMessage = l10n.trOr(
          'register_sms_pending',
          'Send the verification SMS and wait for confirmation.',
        );
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await AuthService.verifyRegistrationContacts(
      email: _emailCtrl.text.trim(),
      phone: _resolvedE164Phone,
      countryCode: _countryIso,
      emailCode: _requiresEmailCode ? _emailOtpCode.trim() : null,
      phoneVerificationId: _requiresReverseSms ? _phoneVerificationId : null,
      oauthRegistrationToken: widget.oauthPrefill?.oauthRegistrationToken,
    );

    if (!mounted) return;
    setState(() => _isLoading = false);

    if (res['success'] == true &&
        (res['registration_ticket']?.toString().isNotEmpty ?? false)) {
      _smsPollTimer?.cancel();
      _registrationTicket = res['registration_ticket'].toString();
      _goToStep(1);
      return;
    }

    if (res['error'] == 'invalid_code') {
      _otpShakeCounter++;
    }
    setState(() {
      _errorMessage = _mapBackendError(l10n, res['error'], res['message']);
    });
  }

  // ============ Step 1: Username & Password ============

  void _onUsernameEdited() {
    _usernameDebounce?.cancel();
    final clean = _usernameCtrl.text.trim().replaceFirst(RegExp(r'^@+'), '');
    if (clean.length < 3) {
      if (mounted) {
        setState(() {
          _checkingUsername = false;
          _usernameAvailable = null;
          _usernameStatusReason = null;
          _usernameSuggestions = const [];
        });
      }
      return;
    }
    setState(() => _checkingUsername = true);
    _usernameDebounce = Timer(const Duration(milliseconds: 350), () async {
      final res = await AuthService.checkUsernameAvailability(clean);
      if (!mounted) return;
      final latest =
          _usernameCtrl.text.trim().replaceFirst(RegExp(r'^@+'), '');
      if (latest != clean) return;
      setState(() {
        _checkingUsername = false;
        _usernameAvailable = res['available'] == true;
        _usernameStatusReason = res['reason']?.toString();
        final sug = res['suggestions'];
        _usernameSuggestions =
            sug is List ? sug.map((e) => e.toString()).toList() : const [];
      });
    });
  }

  Future<void> _submitStep1() async {
    final l10n = context.l10n;
    final cleanUser =
        _usernameCtrl.text.trim().replaceFirst(RegExp(r'^@+'), '');
    final pwd = _passwordCtrl.text;
    final confirm = _confirmPasswordCtrl.text;

    if (!RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{2,31}$').hasMatch(cleanUser)) {
      setState(() {
        _errorMessage = l10n.trOr(
          'register_username_format_error',
          'Username must start with a letter and be 3-32 characters (A-Z, 0-9, _).',
        );
      });
      return;
    }
    if (_usernameAvailable == false) {
      setState(() {
        _errorMessage = l10n.trOr(
          'register_username_taken',
          'This username is unavailable. Pick another one or tap a suggestion.',
        );
      });
      return;
    }
    if (pwd.length < 8) {
      setState(() {
        _errorMessage = l10n.trOr(
          'register_password_min_length',
          'Password must be at least 8 characters',
        );
      });
      return;
    }
    if (pwd != confirm) {
      setState(() {
        _errorMessage = l10n.translate('security_2fa_passwords_mismatch');
      });
      return;
    }

    _goToStep(2);
  }

  // ============ Step 2: Avatar & Name ============

  Future<void> _pickAvatar() async {
    HapticUtils.tap();
    final subject = _firstNameCtrl.text.trim().isNotEmpty
        ? _firstNameCtrl.text.trim()
        : _usernameCtrl.text.trim();
    final pick = await TheavAvatarPickerSheet.open(
      context: context,
      maskShape: AvatarShapeMask.circle,
      ctaMode: AvatarEditorCtaMode.done,
      subjectName: subject.isNotEmpty ? subject : 'Theaver',
      canDeleteCurrent: _pickedAvatar != null,
    );
    if (!mounted || pick == null) return;
    setState(() {
      _pickedAvatar = pick.deletedCurrent ? null : pick;
    });
  }

  Future<void> _completeRegistration() async {
    final l10n = context.l10n;
    final firstName = _firstNameCtrl.text.trim();
    final lastName = _lastNameCtrl.text.trim();
    final username =
        _usernameCtrl.text.trim().replaceFirst(RegExp(r'^@+'), '');

    if (firstName.isEmpty) {
      setState(() {
        _errorMessage = l10n.trOr(
          'register_first_name_required',
          'First name is required',
        );
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final res = await AuthService.register(
      username: username,
      email: _emailCtrl.text.trim(),
      password: _passwordCtrl.text,
      firstName: firstName,
      lastName: lastName.isNotEmpty ? lastName : null,
      phone: _resolvedE164Phone,
      countryCode: _countryIso,
      registrationTicket: _registrationTicket,
      oauthRegistrationToken: widget.oauthPrefill?.oauthRegistrationToken,
      locale: l10n.locale.languageCode,
      context: context,
    );

    if (!mounted) return;

    if (res['success'] != true) {
      setState(() {
        _isLoading = false;
        _errorMessage = _mapBackendError(l10n, res['error'], res['message']);
      });
      return;
    }

    final userId = res['userId']?.toString() ?? '';
    if (_pickedAvatar != null) {
      await AuthService.uploadAvatarFromPick(_pickedAvatar!, userId: userId);
    }

    if (userId.isNotEmpty) {
      await WebSocketService().updateUserId(userId);
    }

    if (!mounted) return;
    setState(() => _isLoading = false);

    TilingLayoutController.instance.closeAllChats();
    final nav = Navigator.of(context);
    if (TilingLayoutController.instance.isWorkspaceMounted && nav.canPop()) {
      nav.popUntil((route) => route.isFirst);
    } else {
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        SwipeBackPageRoute(builder: (_) => const TilingWorkspaceScaffold()),
        (route) => false,
      );
    }
  }

  void _goToStep(int next) {
    HapticUtils.tap();
    setState(() {
      _stepForward = next >= _step;
      _step = next.clamp(0, 2);
      _errorMessage = null;
    });
  }

  String _mapBackendError(AppLocalizations l10n, Object? code, Object? fallback) {
    switch (code?.toString()) {
      case 'invalid_phone':
        return l10n.translate('validation_valid_phone');
      case 'invalid_email':
        return l10n.translate('validation_valid_email');
      case 'disposable_email_not_allowed':
        return l10n.trOr(
          'register_error_disposable_email',
          'Temporary or disposable email providers are not allowed.',
        );
      case 'email_domain_unreachable':
        return l10n.trOr(
          'register_error_email_domain',
          'This email domain cannot receive verification messages.',
        );
      case 'email_taken':
        return l10n.trOr(
          'register_error_email_taken',
          'An account with this email already exists.',
        );
      case 'phone_taken':
        return l10n.trOr(
          'register_error_phone_taken',
          'This phone number is already registered.',
        );
      case 'invalid_code':
        return l10n.translate('email_error_invalid_code');
      case 'code_expired':
        return l10n.translate('email_error_code_expired');
      case 'rate_limited':
      case 'cooldown_active':
        return l10n.translate('email_error_rate_limited');
      default:
        return (fallback?.toString().isNotEmpty ?? false)
            ? fallback.toString()
            : l10n.translate('auth_registration_failed');
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.theav;
    final topClearance = SettingsFloatingHeader.topClearanceOf(context);

    final String title;
    switch (_step) {
      case 0:
        title = l10n.trOr('register_step_contacts_title', 'Contacts');
        break;
      case 1:
        title = l10n.trOr('register_step_security_title', 'Username');
        break;
      default:
        title = l10n.trOr('register_step_profile_title', 'Profile');
        break;
    }

    return PopScope(
      canPop: _step == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _step > 0) {
          _goToStep(_step - 1);
        }
      },
      child: Stack(
        fit: StackFit.expand,
        children: [
          const TheavAuthWallpaperBackground(),
          SettingsFloatingScaffold(
            backgroundColor: Colors.transparent,
            title: title,
            onBack: () {
              if (_step > 0) {
                _goToStep(_step - 1);
              } else {
                Navigator.of(context).pop();
              }
            },
            actions: [
              SettingsHeaderAction(
                tooltip: '${_step + 1} / 3',
                child: Text(
                  '${_step + 1}/3',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                    color: palette.primary,
                  ),
                ),
                onTap: null,
              ),
            ],
            body: SafeArea(
              top: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 540),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.fromLTRB(0, topClearance + 10, 0, 28),
                    child: TheavStepViewport(
                      stepIndex: _step,
                      forward: _stepForward,
                      child: _step == 0
                          ? _buildStep0Contacts(palette, l10n)
                          : (_step == 1
                              ? _buildStep1Credentials(palette, l10n)
                              : _buildStep2Profile(palette, l10n)),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStep0Contacts(TheavPalette palette, AppLocalizations l10n) {
    final providerTitle = _oauthProviderTitle();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                l10n.trOr('register_step0_heading', 'Create your account'),
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                  color: palette.onSurface,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                widget.oauthPrefill != null
                    ? l10n
                        .trOr(
                          'register_oauth_prefill_subtitle',
                          'Connected with {provider}. Review your contacts before choosing a username.',
                        )
                        .replaceAll('{provider}', providerTitle)
                    : l10n.trOr(
                        'register_step0_subtitle',
                        'We use your email and phone number for account recovery and sign-in.',
                      ),
                style: TextStyle(fontSize: 14, color: palette.subtext),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        TheavInsetGroup(
          header: l10n.trOr('register_contacts_group', 'Contact details'),
          children: [
            TheavInlineTextField(
              controller: _emailCtrl,
              enabled: !_isLoading,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              placeholder: l10n.translate('auth_email'),
              prefix: iconoir.Mail(
                width: 19,
                height: 19,
                color: palette.subtext,
              ),
              suffix: _isEmailVerifiedByOAuth
                  ? _VerifiedChip(label: providerTitle)
                  : null,
            ),
            CountryPhoneInput(
              controller: _phoneCtrl,
              countryIso: _countryIso,
              enabled: !_isLoading,
              verified: _isPhoneVerifiedByOAuth || _smsVerified,
              verifiedProviderLabel: _isPhoneVerifiedByOAuth
                  ? providerTitle
                  : (_smsVerified ? 'SMS' : null),
              onCountryChanged: (entry) {
                setState(() {
                  _countryIso = entry.iso;
                  _registrationTicket = null;
                });
              },
              onE164Changed: (e164) {
                setState(() {
                  _currentE164Phone = e164;
                  _registrationTicket = null;
                });
              },
            ),
          ],
        ),
        if (_awaitingCodes) ...[
          const SizedBox(height: 10),
          if (_requiresEmailCode) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                l10n
                    .trOr(
                      'register_enter_email_code',
                      'Enter the 6-digit code sent to {email}',
                    )
                    .replaceAll('{email}', _emailCtrl.text.trim()),
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: palette.onSurface,
                ),
              ),
            ),
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TheavOtpPinRow(
                value: _emailOtpCode,
                errorShakeCounter: _otpShakeCounter,
                enabled: !_isLoading,
                onChanged: (v) => _emailOtpCode = v,
              ),
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TheavSpringButton(
                variant: TheavSpringButtonVariant.glass,
                enabled: !_isLoading && _cooldown == 0,
                height: 44,
                label: _cooldown > 0
                    ? l10n
                        .translate('email_resend_cooldown')
                        .replaceAll('{seconds}', '$_cooldown')
                    : l10n.translate('email_resend_button'),
                onPressed:
                    (_isLoading || _cooldown > 0) ? null : _startStep0Verification,
              ),
            ),
          ],
          if (_requiresReverseSms) ...[
            const SizedBox(height: 12),
            TheavInsetGroup(
              header: l10n.trOr('register_reverse_sms_title', 'Phone verification'),
              footer: l10n.trOr(
                'register_reverse_sms_hint',
                'Send the code below from your SIM card to verify your phone number automatically.',
              ),
              children: [
                TheavListRow(
                  leading: iconoir.MessageText(
                    width: 20,
                    height: 20,
                    color: _smsVerified ? const Color(0xFF28A745) : palette.primary,
                  ),
                  title: _smsBody ?? '',
                  subtitle: _smsTargetNumber ?? '',
                  trailing: _smsVerified
                      ? const _VerifiedChip(label: 'OK')
                      : GestureDetector(
                          onTap: () {
                            if (_smsBody != null) {
                              Clipboard.setData(ClipboardData(text: _smsBody!));
                              HapticUtils.selection();
                              GlassToastService().show(
                                context,
                                l10n.trOr('copied_to_clipboard', 'Copied'),
                                icon: Icons.copy_outlined,
                              );
                            }
                          },
                          child: iconoir.Copy(
                            width: 19,
                            height: 19,
                            color: palette.primary,
                          ),
                        ),
                  onTap: (_smsUri != null && !_smsVerified)
                      ? () => launchUrl(Uri.parse(_smsUri!))
                      : null,
                ),
              ],
            ),
          ],
        ],
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          TheavAuthErrorBanner(message: _errorMessage!),
        ],
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TheavSpringButton(
            isLoading: _isLoading,
            label: _awaitingCodes
                ? l10n.trOr('register_verify_continue', 'Verify and Continue')
                : l10n.trOr('onboarding_continue', 'Continue'),
            trailing: iconoir.NavArrowRight(
              width: 18,
              height: 18,
              color: palette.onPrimary,
            ),
            onPressed:
                _awaitingCodes ? _confirmStep0Codes : _startStep0Verification,
          ),
        ),
      ],
    );
  }

  Widget _buildStep1Credentials(TheavPalette palette, AppLocalizations l10n) {
    final pwd = _passwordCtrl.text;
    final cleanUsername =
        _usernameCtrl.text.trim().replaceFirst(RegExp(r'^@+'), '');

    Widget? usernameTrailing;
    if (_checkingUsername) {
      usernameTrailing = SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          valueColor: AlwaysStoppedAnimation<Color>(palette.primary),
        ),
      );
    } else if (_usernameAvailable == true && cleanUsername.length >= 3) {
      usernameTrailing = const iconoir.CheckCircle(
        width: 18,
        height: 18,
        color: Color(0xFF28A745),
      );
    } else if (_usernameAvailable == false && cleanUsername.length >= 3) {
      usernameTrailing = iconoir.XmarkCircle(
        width: 18,
        height: 18,
        color: palette.error,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            l10n.trOr(
              'register_step1_heading',
              'Pick a unique @username and password',
            ),
            style: TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.4,
              color: palette.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 12),
        TheavInsetGroup(
          header: l10n.translate('auth_username'),
          footer: (_usernameAvailable == false && _usernameStatusReason != null)
              ? l10n.trOr(
                  'register_username_unavailable_hint',
                  'This username is unavailable or reserved. Choose another below.',
                )
              : null,
          children: [
            TheavInlineTextField(
              controller: _usernameCtrl,
              enabled: !_isLoading,
              placeholder: 'username',
              textInputAction: TextInputAction.next,
              prefix: iconoir.AtSign(
                width: 19,
                height: 19,
                color: palette.primary,
              ),
              suffix: usernameTrailing,
            ),
          ],
        ),
        if (_usernameSuggestions.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final suggestion in _usernameSuggestions)
                  GestureDetector(
                    onTap: () {
                      HapticUtils.selection();
                      _usernameCtrl.text = suggestion;
                      _usernameCtrl.selection = TextSelection.collapsed(
                        offset: suggestion.length,
                      );
                    },
                    child: TheavFloatingSurface(
                      borderRadius: 14.0,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 7,
                      ),
                      child: Text(
                        '@$suggestion',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: palette.primary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 8),
        TheavInsetGroup(
          header: l10n.translate('auth_password'),
          footer: l10n.trOr(
            'register_password_footer',
            'Minimum 8 characters. Used together with OAuth for backup sign-in.',
          ),
          children: [
            TheavInlineTextField(
              controller: _passwordCtrl,
              enabled: !_isLoading,
              obscureText: _obscurePassword,
              placeholder: l10n.translate('auth_password'),
              textInputAction: TextInputAction.next,
              prefix: iconoir.Lock(
                width: 19,
                height: 19,
                color: palette.subtext,
              ),
              suffix: GestureDetector(
                onTap: () => setState(
                  () => _obscurePassword = !_obscurePassword,
                ),
                child: _obscurePassword
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
              onChanged: (_) => setState(() {}),
            ),
            TheavInlineTextField(
              controller: _confirmPasswordCtrl,
              enabled: !_isLoading,
              obscureText: _obscurePassword,
              placeholder: l10n.translate('security_2fa_confirm_password_label'),
              textInputAction: TextInputAction.done,
              prefix: iconoir.Lock(
                width: 19,
                height: 19,
                color: palette.subtext,
              ),
              onSubmitted: (_) => _submitStep1(),
            ),
          ],
        ),
        if (pwd.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: _PasswordStrengthBar(password: pwd),
          ),
        ],
        if (_errorMessage != null) ...[
          const SizedBox(height: 6),
          TheavAuthErrorBanner(message: _errorMessage!),
        ],
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TheavSpringButton(
            label: l10n.trOr('onboarding_continue', 'Continue'),
            trailing: iconoir.NavArrowRight(
              width: 18,
              height: 18,
              color: palette.onPrimary,
            ),
            onPressed: _submitStep1,
          ),
        ),
      ],
    );
  }

  Widget _buildStep2Profile(TheavPalette palette, AppLocalizations l10n) {
    final externalAvatar = widget.oauthPrefill?.externalAvatarUrl ?? '';

    Widget avatarContent;
    if (_pickedAvatar != null) {
      if (_pickedAvatar!.bytes != null) {
        avatarContent = Image.memory(
          _pickedAvatar!.bytes!,
          fit: BoxFit.cover,
        );
      } else if (_pickedAvatar!.file != null) {
        avatarContent = Image.file(
          _pickedAvatar!.file!,
          fit: BoxFit.cover,
        );
      } else {
        avatarContent = _avatarPlaceholder(palette);
      }
    } else if (externalAvatar.isNotEmpty) {
      avatarContent = Image.network(
        externalAvatar,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _avatarPlaceholder(palette),
      );
    } else {
      avatarContent = _avatarPlaceholder(palette);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: GestureDetector(
            onTap: _isLoading ? null : _pickAvatar,
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: palette.surface,
                    border: Border.all(
                      color: palette.primary.withValues(alpha: 0.35),
                      width: 1.5,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: palette.primary.withValues(alpha: 0.16),
                        blurRadius: 16,
                        offset: const Offset(0, 6),
                      ),
                    ],
                  ),
                  child: ClipOval(child: avatarContent),
                ),
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: palette.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: palette.surface, width: 2),
                  ),
                  alignment: Alignment.center,
                  child: iconoir.Camera(
                    width: 15,
                    height: 15,
                    color: palette.onPrimary,
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 10),
        Center(
          child: Text(
            l10n.trOr('register_avatar_optional', 'Profile photo (optional)'),
            style: TextStyle(fontSize: 13, color: palette.subtext),
          ),
        ),
        const SizedBox(height: 14),
        TheavInsetGroup(
          header: l10n.trOr('register_your_name_header', 'Your name'),
          children: [
            TheavInlineTextField(
              controller: _firstNameCtrl,
              enabled: !_isLoading,
              placeholder: l10n.trOr('register_first_name_label', 'First name'),
              textInputAction: TextInputAction.next,
              prefix: iconoir.User(
                width: 19,
                height: 19,
                color: palette.subtext,
              ),
            ),
            TheavInlineTextField(
              controller: _lastNameCtrl,
              enabled: !_isLoading,
              placeholder: l10n.trOr(
                'register_last_name_label',
                'Last name (optional)',
              ),
              textInputAction: TextInputAction.done,
              prefix: iconoir.UserBadgeCheck(
                width: 19,
                height: 19,
                color: palette.subtext,
              ),
              onSubmitted: (_) => _completeRegistration(),
            ),
          ],
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          TheavAuthErrorBanner(message: _errorMessage!),
        ],
        const SizedBox(height: 18),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TheavSpringButton(
            isLoading: _isLoading,
            label: l10n.trOr('register_complete_button', 'Complete registration'),
            onPressed: _completeRegistration,
          ),
        ),
      ],
    );
  }

  Widget _avatarPlaceholder(TheavPalette palette) {
    return Container(
      color: palette.primary.withValues(alpha: 0.10),
      alignment: Alignment.center,
      child: iconoir.Camera(
        width: 32,
        height: 32,
        color: palette.primary,
      ),
    );
  }
}

class _VerifiedChip extends StatelessWidget {
  final String label;

  const _VerifiedChip({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF34C759).withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const iconoir.CheckCircle(
            width: 13,
            height: 13,
            color: Color(0xFF28A745),
          ),
          if (label.isNotEmpty) ...[
            const SizedBox(width: 4),
            Text(
              label,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF28A745),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PasswordStrengthBar extends StatelessWidget {
  final String password;

  const _PasswordStrengthBar({required this.password});

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    var score = 0;
    if (password.length >= 8) score++;
    if (password.length >= 12) score++;
    if (RegExp(r'[A-Z]').hasMatch(password) &&
        RegExp(r'[a-z]').hasMatch(password)) {
      score++;
    }
    if (RegExp(r'[0-9]').hasMatch(password) ||
        RegExp(r'[^A-Za-z0-9]').hasMatch(password)) {
      score++;
    }
    final fraction = (score / 4.0).clamp(0.15, 1.0);
    final Color barColor = score <= 1
        ? palette.error
        : (score == 2 ? const Color(0xFFFF9500) : const Color(0xFF34C759));

    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: LinearProgressIndicator(
        value: fraction,
        minHeight: 4,
        backgroundColor: palette.onSurface.withValues(alpha: 0.10),
        valueColor: AlwaysStoppedAnimation<Color>(barColor),
      ),
    );
  }
}
