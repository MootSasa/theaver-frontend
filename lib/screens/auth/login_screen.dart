import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../services/auth_service.dart';
import '../../services/deep_link_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/tiling_layout_controller.dart';
import '../../services/websocket_service.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../../widgets/auth/theav_auth_primitives.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/settings/settings_floating_header.dart';
import '../../widgets/tiling/tiling_workspace_scaffold.dart';
import '../settings/service_menu_screen.dart';
import 'recovery_screen.dart';
import 'register_screen.dart';

/// Adaptive login screen built exclusively on Theaver's native design system:
/// - `@username`, `email`, or phone login + QR login & grant-code claim
/// - 5-tap secret trigger on brand emblem to open [ServiceMenuScreen]
/// - Regional configured-only OAuth2/OIDC (Yandex ID, VK ID, Google, Apple)
class LoginScreen extends StatefulWidget {
  final String? initialUsername;
  final String? initialCountryCode;
  @visibleForTesting
  final AuthProvidersConfig? debugProvidersOverride;

  const LoginScreen({
    super.key,
    this.initialUsername,
    this.initialCountryCode,
    this.debugProvidersOverride,
  });

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

enum _MobileAuthTab { password, qr }

class _LoginScreenState extends State<LoginScreen> {
  final _identifierCtrl = TextEditingController();
  final _passwordCtrl = TextEditingController();
  final _qrClaimCodeCtrl = TextEditingController();

  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  _MobileAuthTab _mobileTab = _MobileAuthTab.password;
  bool _wasWideLayout = false;

  // Providers & custom server state
  AuthProvidersConfig? _providersConfig;
  String? _customServerUrl;
  final List<DateTime> _logoTapTimes = [];

  // QR Login state
  bool _qrLoading = false;
  bool _qrExpired = false;
  bool _qrAwaiting2faHandled = false;
  bool _qrClaiming = false;
  String? _qrToken;
  String? _qrSecret;
  String? _qrShortCode;
  String? _qrUrl;
  String? _qrError;
  String? _qrClaimError;
  Timer? _qrPollTimer;

  // Active OAuth broker session state
  Timer? _oauthPollTimer;
  StreamSubscription<OAuthCallbackEvent>? _oauthSub;
  String? _activeOAuthSessionId;
  String? _activeOAuthPollSecret;
  bool _handlingOAuthOutcome = false;
  BuildContext? _oauthWaitingSheetContext;

  @override
  void initState() {
    super.initState();
    if (widget.initialUsername != null && widget.initialUsername!.isNotEmpty) {
      _identifierCtrl.text = widget.initialUsername!;
    }
    _identifierCtrl.addListener(_onIdentifierChanged);
    _loadCustomServerState();
    _loadProvidersConfig();
    _oauthSub = DeepLinkService().oauthCallbacks.listen(_handleOAuthDeepLink);
  }

  @override
  void dispose() {
    _qrPollTimer?.cancel();
    _oauthPollTimer?.cancel();
    _oauthSub?.cancel();
    _identifierCtrl.removeListener(_onIdentifierChanged);
    _identifierCtrl.dispose();
    _passwordCtrl.dispose();
    _qrClaimCodeCtrl.dispose();
    super.dispose();
  }

  void _onIdentifierChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadCustomServerState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(AppConfig.prefCustomApiUrlKey) ??
          prefs.getString(AppConfig.prefCustomServerUrlKey);
      if (mounted) {
        setState(() {
          _customServerUrl =
              (raw != null && raw.trim().isNotEmpty) ? raw.trim() : null;
        });
      }
    } catch (_) {}
  }

  Future<void> _loadProvidersConfig() async {
    if (widget.debugProvidersOverride != null) {
      setState(() => _providersConfig = widget.debugProvidersOverride);
      return;
    }
    final cfg = await AuthService.fetchAuthProviders();
    if (!mounted) return;
    setState(() => _providersConfig = cfg);
  }

  void _handleBrandLogoTap() {
    final now = DateTime.now();
    _logoTapTimes.removeWhere(
      (ts) => now.difference(ts) > const Duration(milliseconds: 2500),
    );
    _logoTapTimes.add(now);
    if (_logoTapTimes.length >= 5) {
      _logoTapTimes.clear();
      HapticUtils.selection();
      Navigator.of(context)
          .push(SwipeBackPageRoute(builder: (_) => const ServiceMenuScreen()))
          .then((_) {
        if (mounted) {
          _loadCustomServerState();
          _loadProvidersConfig();
        }
      });
    }
  }

  Future<void> _resetCustomServer() async {
    HapticUtils.tap();
    await AppConfig.resetToDefaults();
    await _loadCustomServerState();
    await _loadProvidersConfig();
    if (!mounted) return;
    GlassToastService().show(
      context,
      context.l10n.trOr('auth_server_reset_done', 'Server reset to default'),
      icon: Icons.dns_outlined,
    );
  }

  String _resolvedCountryCode() {
    final w = widget.initialCountryCode?.trim().toUpperCase() ?? '';
    if (w.length == 2) return w;
    final p = _providersConfig?.countryCode.trim().toUpperCase() ?? '';
    if (p.length == 2) return p;
    return 'RU';
  }

  Widget _buildSmartIdentifierIcon(TheavPalette palette) {
    final text = _identifierCtrl.text.trim();
    if (text.startsWith('@')) {
      return iconoir.AtSign(width: 19, height: 19, color: palette.primary);
    }
    if (text.contains('@')) {
      return iconoir.Mail(width: 19, height: 19, color: palette.primary);
    }
    if (RegExp(r'^[+0-9]').hasMatch(text)) {
      return iconoir.Phone(width: 19, height: 19, color: palette.primary);
    }
    return iconoir.User(width: 19, height: 19, color: palette.subtext);
  }

  Future<void> _enterWorkspace(String userId) async {
    if (userId.isNotEmpty) {
      await WebSocketService().updateUserId(userId);
    }
    if (!mounted) return;
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

  Future<void> _submitPasswordLogin() async {
    final l10n = context.l10n;
    final identifier = _identifierCtrl.text.trim();
    final password = _passwordCtrl.text;

    if (identifier.isEmpty || password.isEmpty) {
      setState(() {
        _errorMessage = l10n.trOr(
          'auth_enter_credentials',
          'Enter username, email, or phone and password',
        );
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    var res = await AuthService.login(
      identifier: identifier,
      password: password,
      countryCode: _resolvedCountryCode(),
      context: context,
    );

    if (!mounted) return;

    if (res['requires_2fa'] == true) {
      setState(() => _isLoading = false);
      final choice = await _showTwoFactorSheet(
        allowEmailReset: true,
        hasRecoveryEmail: res['has_recovery_email'] == true,
        usernameOrEmail: identifier,
        passwordForReset: password,
      );
      if (!mounted || choice == null) return;
      if (choice['2fa_reset_done'] == true) {
        GlassToastService().show(
          context,
          l10n.translate('auth_2fa_reset_success'),
          icon: Icons.check_circle_outline,
        );
        return;
      }
      final val = choice['value']?.toString() ?? '';
      if (val.isEmpty) return;

      setState(() => _isLoading = true);
      res = await AuthService.login(
        identifier: identifier,
        password: password,
        countryCode: _resolvedCountryCode(),
        twoFactorPassword: choice['isRecoveryCode'] == true ? null : val,
        recoveryCode: choice['isRecoveryCode'] == true ? val : null,
        context: context,
      );
      if (!mounted) return;
    }

    setState(() => _isLoading = false);

    if (res['success'] == true) {
      await _enterWorkspace(res['userId']?.toString() ?? '');
      return;
    }

    setState(() {
      _errorMessage = res['error'] == 'invalid_2fa_password'
          ? l10n.translate('email_error_invalid_2fa')
          : (res['message']?.toString() ?? l10n.translate('auth_login_failed'));
    });
  }

  Future<Map<String, dynamic>?> _showTwoFactorSheet({
    bool allowEmailReset = false,
    bool hasRecoveryEmail = false,
    String? usernameOrEmail,
    String? passwordForReset,
  }) async {
    final l10n = context.l10n;
    final ctrl = TextEditingController();
    bool useRecoveryCode = false;

    final result = await showTheavModalSheet<Map<String, dynamic>>(
      context: context,
      title: l10n.translate('auth_2fa_title'),
      showCloseButton: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final palette = ctx.theav;
            final sheetL10n = ctx.l10n;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      useRecoveryCode
                          ? sheetL10n.translate('auth_2fa_enter_backup_code')
                          : sheetL10n.translate('auth_2fa_enter_password_prompt'),
                      style: TextStyle(fontSize: 14, color: palette.subtext),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TheavInsetGroup(
                    children: [
                      TheavInlineTextField(
                        controller: ctrl,
                        autofocus: true,
                        obscureText: !useRecoveryCode,
                        placeholder: useRecoveryCode
                            ? sheetL10n.translate('auth_2fa_backup_code_label')
                            : sheetL10n.translate('security_2fa_password_label'),
                        prefix: iconoir.Shield(
                          width: 19,
                          height: 19,
                          color: palette.subtext,
                        ),
                        onSubmitted: (v) {
                          if (v.trim().isNotEmpty) {
                            Navigator.of(sheetCtx).pop({
                              'value': v.trim(),
                              'isRecoveryCode': useRecoveryCode,
                            });
                          }
                        },
                      ),
                      TheavListRow(
                        title: useRecoveryCode
                            ? sheetL10n.translate('auth_2fa_use_password')
                            : sheetL10n.translate('auth_2fa_use_backup_code'),
                        showChevron: true,
                        onTap: () {
                          HapticUtils.selection();
                          setSheetState(() {
                            useRecoveryCode = !useRecoveryCode;
                            ctrl.clear();
                          });
                        },
                      ),
                      if (allowEmailReset &&
                          hasRecoveryEmail &&
                          usernameOrEmail != null &&
                          passwordForReset != null)
                        TheavListRow(
                          title: sheetL10n.translate('auth_2fa_forgot_button'),
                          isDestructive: true,
                          showChevron: true,
                          onTap: () async {
                            Navigator.of(sheetCtx).pop();
                            final resetDone = await _show2FAEmailResetSheet(
                              usernameOrEmail: usernameOrEmail,
                              password: passwordForReset,
                            );
                            if (resetDone == true && mounted) {
                              GlassToastService().show(
                                context,
                                l10n.translate('auth_2fa_reset_success'),
                                icon: Icons.check_circle_outline,
                              );
                            }
                          },
                        ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TheavSpringButton(
                      label: sheetL10n.translate('confirm'),
                      onPressed: () {
                        final val = ctrl.text.trim();
                        if (val.isEmpty) return;
                        Navigator.of(sheetCtx).pop({
                          'value': val,
                          'isRecoveryCode': useRecoveryCode,
                        });
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    ctrl.dispose();
    return result;
  }

  Future<bool?> _show2FAEmailResetSheet({
    required String usernameOrEmail,
    required String password,
  }) async {
    final l10n = context.l10n;
    bool sending = true;
    bool confirming = false;
    String otp = '';
    int shakeCount = 0;
    String? errorMsg;

    final sendRes = await AuthService.send2FAResetCode(
      usernameOrEmail: usernameOrEmail,
      password: password,
      locale: l10n.locale.languageCode,
    );
    sending = false;
    if (sendRes['success'] != true) {
      errorMsg =
          sendRes['message']?.toString() ?? l10n.translate('error_occurred');
    }

    if (!mounted) return null;
    return showTheavModalSheet<bool>(
      context: context,
      title: l10n.translate('auth_2fa_reset_title'),
      showCloseButton: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final palette = ctx.theav;
            final sheetL10n = ctx.l10n;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(0, 6, 0, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      sheetL10n.translate('auth_2fa_reset_description'),
                      style: TextStyle(fontSize: 14, color: palette.subtext),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TheavOtpPinRow(
                      value: otp,
                      errorShakeCounter: shakeCount,
                      enabled: !sending && !confirming,
                      onChanged: (v) => otp = v,
                    ),
                  ),
                  if (errorMsg != null) TheavAuthErrorBanner(message: errorMsg!),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TheavSpringButton(
                      isLoading: confirming,
                      label: sheetL10n.translate('auth_2fa_reset_confirm_button'),
                      onPressed: () async {
                        if (otp.trim().length < 6) {
                          setSheetState(() {
                            shakeCount++;
                            errorMsg = sheetL10n.translate(
                              'email_error_invalid_code',
                            );
                          });
                          return;
                        }
                        setSheetState(() {
                          confirming = true;
                          errorMsg = null;
                        });
                        final res = await AuthService.confirm2FAReset(
                          usernameOrEmail: usernameOrEmail,
                          password: password,
                          code: otp.trim(),
                        );
                        if (!ctx.mounted) return;
                        if (res['success'] == true) {
                          Navigator.of(sheetCtx).pop(true);
                        } else {
                          setSheetState(() {
                            confirming = false;
                            shakeCount++;
                            errorMsg = res['message']?.toString() ??
                                sheetL10n.translate('error_occurred');
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ============ QR Login ============

  Future<void> _startQrLogin() async {
    if (_qrLoading) return;
    _qrPollTimer?.cancel();
    setState(() {
      _qrLoading = true;
      _qrExpired = false;
      _qrAwaiting2faHandled = false;
      _qrError = null;
      _qrToken = null;
      _qrSecret = null;
      _qrShortCode = null;
      _qrUrl = null;
    });

    final created = await AuthService.createQrLoginSession(
      locale: context.l10n.locale.languageCode,
    );
    if (!mounted) return;

    if (created['success'] != true ||
        created['token'] == null ||
        created['qr_secret'] == null ||
        created['qr_url'] == null) {
      setState(() {
        _qrLoading = false;
        _qrError = created['message']?.toString() ??
            context.l10n.translate('qr_login_load_error');
      });
      return;
    }

    setState(() {
      _qrLoading = false;
      _qrToken = created['token'].toString();
      _qrSecret = created['qr_secret'].toString();
      _qrShortCode = created['short_code']?.toString();
      _qrUrl = created['qr_url'].toString();
    });

    _qrPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pollQrStatus(),
    );
  }

  Future<void> _pollQrStatus() async {
    if (!mounted || _qrToken == null || _qrSecret == null) return;
    final res = await AuthService.pollQrLoginStatus(
      token: _qrToken!,
      qrSecret: _qrSecret!,
    );
    if (!mounted) return;

    final status = res['status']?.toString() ?? 'expired';
    if (status == 'authorized' && res['auth_token'] != null) {
      _qrPollTimer?.cancel();
      final uid = res['user_id']?.toString() ?? '';
      await AuthService.completeExternalLoginSession(
        authToken: res['auth_token'].toString(),
        userId: uid,
        user: res['user'] is Map
            ? Map<String, dynamic>.from(res['user'] as Map)
            : null,
        context: context,
      );
      if (!mounted) return;
      await _enterWorkspace(uid);
      return;
    }

    if (status == 'awaiting_2fa' && !_qrAwaiting2faHandled) {
      _qrAwaiting2faHandled = true;
      _qrPollTimer?.cancel();
      final choice = await _showTwoFactorSheet();
      if (!mounted) return;
      if (choice == null || (choice['value']?.toString() ?? '').isEmpty) {
        _qrAwaiting2faHandled = false;
        _startQrLogin();
        return;
      }
      final val = choice['value'].toString();
      final verifyRes = await AuthService.verifyQrLogin2FA(
        token: _qrToken!,
        qrSecret: _qrSecret!,
        twoFactorPassword: choice['isRecoveryCode'] == true ? null : val,
        recoveryCode: choice['isRecoveryCode'] == true ? val : null,
      );
      if (!mounted) return;
      if (verifyRes['success'] == true && verifyRes['auth_token'] != null) {
        final uid = verifyRes['user_id']?.toString() ?? '';
        await AuthService.completeExternalLoginSession(
          authToken: verifyRes['auth_token'].toString(),
          userId: uid,
          user: verifyRes['user'] is Map
              ? Map<String, dynamic>.from(verifyRes['user'] as Map)
              : null,
          context: context,
        );
        if (!mounted) return;
        await _enterWorkspace(uid);
      } else {
        _qrAwaiting2faHandled = false;
        GlassToastService().showError(
          context,
          verifyRes['error'] == 'invalid_2fa_password'
              ? context.l10n.translate('email_error_invalid_2fa')
              : context.l10n.translate('qr_login_load_error'),
        );
        _startQrLogin();
      }
      return;
    }

    if (status == 'expired' || status == 'consumed') {
      _qrPollTimer?.cancel();
      setState(() => _qrExpired = true);
    }
  }

  void _stopQrLogin() {
    _qrPollTimer?.cancel();
    _qrPollTimer = null;
  }

  Future<void> _claimQrCode() async {
    final l10n = context.l10n;
    final raw = _qrClaimCodeCtrl.text.trim();
    if (raw.isEmpty) {
      setState(() => _qrClaimError = l10n.translate('qr_login_code_required'));
      return;
    }

    setState(() {
      _qrClaiming = true;
      _qrClaimError = null;
    });

    final isUri = raw.contains('://') || raw.contains('token=');
    var res = await AuthService.claimQrGrantSession(
      token: isUri ? raw : null,
      shortCode: isUri ? null : raw,
      locale: l10n.locale.languageCode,
    );
    if (!mounted) return;

    if (res['requires_2fa'] == true) {
      setState(() => _qrClaiming = false);
      final choice = await _showTwoFactorSheet();
      if (!mounted || choice == null) return;
      final val = choice['value']?.toString() ?? '';
      if (val.isEmpty) return;

      setState(() => _qrClaiming = true);
      res = await AuthService.claimQrGrantSession(
        token: isUri ? raw : null,
        shortCode: isUri ? null : raw,
        twoFactorPassword: choice['isRecoveryCode'] == true ? null : val,
        recoveryCode: choice['isRecoveryCode'] == true ? val : null,
        locale: l10n.locale.languageCode,
      );
      if (!mounted) return;
    }

    setState(() => _qrClaiming = false);

    if (res['success'] == true && res['auth_token'] != null) {
      final uid = res['user_id']?.toString() ?? '';
      await AuthService.completeExternalLoginSession(
        authToken: res['auth_token'].toString(),
        userId: uid,
        user: res['user'] is Map
            ? Map<String, dynamic>.from(res['user'] as Map)
            : null,
        context: context,
      );
      if (!mounted) return;
      await _enterWorkspace(uid);
      return;
    }

    setState(() {
      _qrClaimError = res['error'] == 'invalid_2fa_password'
          ? l10n.translate('email_error_invalid_2fa')
          : (res['message']?.toString() ??
              l10n.translate('qr_login_claim_failed'));
    });
  }

  // ============ Regional OAuth2 / OIDC ============

  Future<void> _startOAuthFlow(AuthProviderInfo provider) async {
    final l10n = context.l10n;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final startRes = await AuthService.startOAuthSession(
      provider.id,
      locale: l10n.locale.languageCode,
    );
    if (!mounted) return;

    if (startRes['success'] != true ||
        (startRes['authorize_url']?.toString().isEmpty ?? true) ||
        (startRes['session_id']?.toString().isEmpty ?? true) ||
        (startRes['poll_secret']?.toString().isEmpty ?? true)) {
      setState(() {
        _isLoading = false;
        _errorMessage = startRes['message']?.toString() ??
            l10n.trOr('oauth_start_failed', 'Unable to start sign-in');
      });
      return;
    }

    final sessionId = startRes['session_id'].toString();
    final pollSecret = startRes['poll_secret'].toString();
    final authorizeUrl = Uri.parse(startRes['authorize_url'].toString());

    _oauthPollTimer?.cancel();
    setState(() {
      _activeOAuthSessionId = sessionId;
      _activeOAuthPollSecret = pollSecret;
      _handlingOAuthOutcome = false;
      _isLoading = false;
    });

    try {
      await launchUrl(authorizeUrl, mode: LaunchMode.externalApplication);
    } catch (_) {}

    _oauthPollTimer = Timer.periodic(
      const Duration(seconds: 2),
      (_) => _pollOAuthSession(),
    );

    if (!mounted) return;
    await showTheavModalSheet<void>(
      context: context,
      title: provider.displayName,
      showCloseButton: true,
      builder: (sheetCtx) {
        _oauthWaitingSheetContext = sheetCtx;
        final palette = sheetCtx.theav;
        final sheetL10n = sheetCtx.l10n;
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  OAuthBrandGlyph(providerId: provider.id, size: 28),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text(
                      sheetL10n.trOr(
                        'oauth_waiting_browser',
                        'Complete sign-in in your browser and return to Theaver.',
                      ),
                      style: TextStyle(fontSize: 14.5, color: palette.onSurface),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 18),
              Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(palette.primary),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              TheavSpringButton(
                variant: TheavSpringButtonVariant.glass,
                label: sheetL10n.translate('cancel'),
                onPressed: () {
                  _cancelActiveOAuth();
                  Navigator.of(sheetCtx).pop();
                },
              ),
            ],
          ),
        );
      },
    ).whenComplete(() {
      _oauthWaitingSheetContext = null;
    });
    _oauthPollTimer?.cancel();
  }

  void _dismissOAuthWaitingSheet() {
    final sheetCtx = _oauthWaitingSheetContext;
    _oauthWaitingSheetContext = null;
    if (sheetCtx != null && sheetCtx.mounted) {
      Navigator.of(sheetCtx).pop();
    }
  }

  void _cancelActiveOAuth() {
    _oauthPollTimer?.cancel();
    _activeOAuthSessionId = null;
    _activeOAuthPollSecret = null;
    _handlingOAuthOutcome = false;
  }

  void _handleOAuthDeepLink(OAuthCallbackEvent event) {
    if (!mounted ||
        _activeOAuthSessionId == null ||
        event.sessionId != _activeOAuthSessionId) {
      return;
    }
    _pollOAuthSession();
  }

  Future<void> _pollOAuthSession() async {
    final sid = _activeOAuthSessionId;
    final secret = _activeOAuthPollSecret;
    if (!mounted || sid == null || secret == null || _handlingOAuthOutcome) {
      return;
    }

    final res = await AuthService.pollOAuthSessionStatus(
      sessionId: sid,
      pollSecret: secret,
    );
    if (!mounted || _handlingOAuthOutcome) return;

    final status = res['status']?.toString() ?? 'pending';
    if (status == 'pending') return;

    _handlingOAuthOutcome = true;
    _oauthPollTimer?.cancel();

    // Dismiss ONLY the tracked OAuth waiting modal if still mounted.
    _dismissOAuthWaitingSheet();
    if (!mounted) return;

    if (status == 'authenticated' && res['auth_token'] != null) {
      final uid = res['user_id']?.toString() ?? '';
      await AuthService.completeExternalLoginSession(
        authToken: res['auth_token'].toString(),
        userId: uid,
        user: res['user'] is Map
            ? Map<String, dynamic>.from(res['user'] as Map)
            : null,
        context: context,
      );
      _cancelActiveOAuth();
      if (!mounted) return;
      await _enterWorkspace(uid);
      return;
    }

    if (status == 'needs_registration' &&
        res['prefill'] is OAuthRegistrationPrefill) {
      final prefill = res['prefill'] as OAuthRegistrationPrefill;
      _cancelActiveOAuth();
      await Navigator.of(context).push(
        SwipeBackPageRoute(
          builder: (_) => RegisterScreen(
            oauthPrefill: prefill,
            initialCountryCode: _resolvedCountryCode(),
          ),
        ),
      );
      return;
    }

    if (status == 'needs_password_link') {
      final masked = res['masked_email']?.toString() ?? '';
      final provName = res['provider_name']?.toString() ?? '';
      await _handleOAuthPasswordLink(
        sessionId: sid,
        pollSecret: secret,
        providerName: provName,
        maskedEmail: masked,
      );
      _cancelActiveOAuth();
      return;
    }

    if (status == 'awaiting_2fa') {
      final choice = await _showTwoFactorSheet();
      if (mounted && choice != null) {
        final val = choice['value']?.toString() ?? '';
        if (val.isNotEmpty) {
          final vRes = await AuthService.verifyOAuth2FA(
            sessionId: sid,
            pollSecret: secret,
            twoFactorPassword: choice['isRecoveryCode'] == true ? null : val,
            recoveryCode: choice['isRecoveryCode'] == true ? val : null,
            context: context,
          );
          if (mounted && vRes['success'] == true) {
            _cancelActiveOAuth();
            await _enterWorkspace(vRes['user_id']?.toString() ?? '');
            return;
          }
        }
      }
      _cancelActiveOAuth();
      if (mounted) {
        setState(() {
          _errorMessage = context.l10n.translate('email_error_invalid_2fa');
        });
      }
      return;
    }

    _cancelActiveOAuth();
    setState(() {
      _errorMessage = res['message']?.toString() ??
          context.l10n.trOr('oauth_failed', 'External sign-in failed');
    });
  }

  Future<void> _handleOAuthPasswordLink({
    required String sessionId,
    required String pollSecret,
    required String providerName,
    required String maskedEmail,
  }) async {
    final l10n = context.l10n;
    final pwdCtrl = TextEditingController();
    bool submitting = false;
    String? errText;

    await showTheavModalSheet<void>(
      context: context,
      title: l10n.trOr('oauth_link_title', 'Link existing account'),
      showCloseButton: true,
      builder: (sheetCtx) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            final palette = ctx.theav;
            final sheetL10n = ctx.l10n;
            return SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Text(
                      sheetL10n
                          .trOr(
                            'oauth_link_description',
                            'Enter your current Theaver password once to link {provider} to {email}.',
                          )
                          .replaceAll('{provider}', providerName)
                          .replaceAll('{email}', maskedEmail),
                      style: TextStyle(fontSize: 14, color: palette.subtext),
                    ),
                  ),
                  const SizedBox(height: 10),
                  TheavInsetGroup(
                    children: [
                      TheavInlineTextField(
                        controller: pwdCtrl,
                        autofocus: true,
                        obscureText: true,
                        placeholder: sheetL10n.translate('auth_password'),
                        prefix: iconoir.Lock(
                          width: 19,
                          height: 19,
                          color: palette.subtext,
                        ),
                      ),
                    ],
                  ),
                  if (errText != null) TheavAuthErrorBanner(message: errText!),
                  const SizedBox(height: 12),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TheavSpringButton(
                      isLoading: submitting,
                      label: sheetL10n.translate('confirm'),
                      onPressed: () async {
                        if (pwdCtrl.text.isEmpty) return;
                        setSheetState(() {
                          submitting = true;
                          errText = null;
                        });
                        final res = await AuthService.confirmOAuthPasswordLink(
                          sessionId: sessionId,
                          pollSecret: pollSecret,
                          password: pwdCtrl.text,
                          context: context,
                        );
                        if (!ctx.mounted) return;
                        if (res['success'] == true) {
                          Navigator.of(sheetCtx).pop();
                          if (mounted) {
                            await _enterWorkspace(
                              res['user_id']?.toString() ?? '',
                            );
                          }
                        } else {
                          setSheetState(() {
                            submitting = false;
                            errText = res['message']?.toString() ??
                                sheetL10n.translate('error_occurred');
                          });
                        }
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    pwdCtrl.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final palette = context.theav;
    final langCode = context.watch<LocaleProvider>().locale.languageCode;
    final topClearance = SettingsFloatingHeader.topClearanceOf(context);
    final providers = _providersConfig?.providers ?? const <AuthProviderInfo>[];

    return Stack(
      fit: StackFit.expand,
      children: [
        const TheavAuthWallpaperBackground(),
        SettingsFloatingScaffold(
          backgroundColor: Colors.transparent,
          showBackButton: Navigator.of(context).canPop(),
          title: l10n.translate('auth_login'),
          actions: [
            SettingsHeaderAction(
              tooltip: l10n.trOr('onboarding_select_language', 'Language'),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    langCode.toUpperCase(),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: palette.primary,
                    ),
                  ),
                ],
              ),
              onTap: () => showLanguagePickerSheet(
                context,
                recommendedCode: _providersConfig?.recommendedLanguage,
              ),
            ),
          ],
          body: SafeArea(
            top: false,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final bool isWide = constraints.maxWidth >= 840;
                if (isWide && !_wasWideLayout) {
                  _wasWideLayout = true;
                  if (_qrToken == null && !_qrLoading && _qrError == null) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) _startQrLogin();
                    });
                  }
                } else if (!isWide && _wasWideLayout) {
                  _wasWideLayout = false;
                }

                return SingleChildScrollView(
                  padding: EdgeInsets.fromLTRB(
                    16,
                    topClearance + 14,
                    16,
                    28,
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: isWide ? 940 : 480,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildBrandHeader(palette, l10n),
                          if (_customServerUrl != null) ...[
                            const SizedBox(height: 10),
                            _buildCustomServerChip(palette, l10n),
                          ],
                          const SizedBox(height: 18),
                          if (!isWide) ...[
                            Center(
                              child: SizedBox(
                                width: 290,
                                child: TheavSegmentedControl<_MobileAuthTab>(
                                  selected: _mobileTab,
                                  expand: true,
                                  height: 38,
                                  onChanged: (next) {
                                    HapticUtils.selection();
                                    setState(() => _mobileTab = next);
                                    if (next == _MobileAuthTab.qr) {
                                      _startQrLogin();
                                    } else {
                                      _stopQrLogin();
                                    }
                                  },
                                  options: [
                                    TheavSegmentOption(
                                      value: _MobileAuthTab.password,
                                      label: l10n.trOr(
                                        'auth_tab_password',
                                        'Password',
                                      ),
                                    ),
                                    TheavSegmentOption(
                                      value: _MobileAuthTab.qr,
                                      label: l10n.trOr('auth_tab_qr', 'QR Code'),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 16),
                            if (_mobileTab == _MobileAuthTab.password)
                              _buildCredentialsColumn(palette, l10n, providers)
                            else
                              _buildQrColumn(palette, l10n),
                          ] else
                            Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  flex: 11,
                                  child: _buildCredentialsColumn(
                                    palette,
                                    l10n,
                                    providers,
                                  ),
                                ),
                                const SizedBox(width: 24),
                                Expanded(
                                  flex: 9,
                                  child: _buildQrColumn(palette, l10n),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBrandHeader(TheavPalette palette, AppLocalizations l10n) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          key: const ValueKey<String>('login_brand_emblem'),
          onTap: _handleBrandLogoTap,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: palette.surface.withValues(alpha: 0.72),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: palette.onSurface.withValues(alpha: 0.10),
                    width: 0.75,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: Image.asset(
                    'assets/icons/app_icon.png',
                    width: 68,
                    height: 68,
                    filterQuality: FilterQuality.high,
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Theaver',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.6,
                  color: palette.onSurface,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        Text(
          l10n.trOr('auth_login_subtitle', 'Sign in with username, email, or phone'),
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 14,
            color: palette.subtext,
          ),
        ),
      ],
    );
  }

  Widget _buildCustomServerChip(TheavPalette palette, AppLocalizations l10n) {
    final host = Uri.tryParse(_customServerUrl!)?.host ?? _customServerUrl!;
    return Center(
      child: TheavFloatingSurface(
        borderRadius: 18.0,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconoir.Server(width: 15, height: 15, color: palette.primary),
            const SizedBox(width: 6),
            Text(
              host,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: palette.onSurface,
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _resetCustomServer,
              child: Text(
                l10n.trOr('auth_server_reset', 'Reset'),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  color: palette.primary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCredentialsColumn(
    TheavPalette palette,
    AppLocalizations l10n,
    List<AuthProviderInfo> providers,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TheavInsetGroup(
          margin: EdgeInsets.zero,
          children: [
            TheavInlineTextField(
              controller: _identifierCtrl,
              enabled: !_isLoading,
              placeholder: l10n.trOr(
                'auth_identifier_hint',
                '@username, email or phone',
              ),
              textInputAction: TextInputAction.next,
              prefix: _buildSmartIdentifierIcon(palette),
            ),
            TheavInlineTextField(
              controller: _passwordCtrl,
              enabled: !_isLoading,
              obscureText: _obscurePassword,
              placeholder: l10n.translate('auth_password'),
              textInputAction: TextInputAction.done,
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
              onSubmitted: (_) => _submitPasswordLogin(),
            ),
          ],
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 8),
          TheavAuthErrorBanner(message: _errorMessage!),
        ],
        const SizedBox(height: 14),
        TheavSpringButton(
          label: l10n.translate('auth_login_button'),
          isLoading: _isLoading,
          onPressed: _submitPasswordLogin,
        ),
        if (providers.isNotEmpty) ...[
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Divider(
                  height: 1,
                  color: palette.onSurface.withValues(alpha: 0.14),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  l10n.trOr('oauth_continue_with', 'or continue with'),
                  style: TextStyle(fontSize: 12.5, color: palette.subtext),
                ),
              ),
              Expanded(
                child: Divider(
                  height: 1,
                  color: palette.onSurface.withValues(alpha: 0.14),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < providers.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            TheavSpringButton(
              variant: TheavSpringButtonVariant.glass,
              enabled: !_isLoading,
              leading: OAuthBrandGlyph(providerId: providers[i].id, size: 20),
              label: l10n
                  .trOr('oauth_sign_in_with_provider', 'Continue with {provider}')
                  .replaceAll('{provider}', providers[i].displayName),
              onPressed: () => _startOAuthFlow(providers[i]),
            ),
          ],
        ],
        const SizedBox(height: 16),
        TheavInsetGroup(
          margin: EdgeInsets.zero,
          children: [
            TheavListRow(
              leading: iconoir.UserPlus(
                width: 20,
                height: 20,
                color: palette.primary,
              ),
              title: l10n.translate('auth_create_account'),
              showChevron: true,
              onTap: _isLoading
                  ? null
                  : () {
                      Navigator.of(context).push(
                        SwipeBackPageRoute(
                          builder: (_) => RegisterScreen(
                            initialCountryCode: _resolvedCountryCode(),
                          ),
                        ),
                      );
                    },
            ),
            TheavListRow(
              leading: iconoir.Key(
                width: 20,
                height: 20,
                color: palette.subtext,
              ),
              title: l10n.translate('auth_forgot_password'),
              showChevron: true,
              onTap: _isLoading
                  ? null
                  : () {
                      final cur = _identifierCtrl.text.trim();
                      Navigator.of(context).push(
                        SwipeBackPageRoute(
                          builder: (_) => RecoveryScreen(
                            initialEmail: cur.contains('@') && !cur.startsWith('@')
                                ? cur
                                : null,
                          ),
                        ),
                      );
                    },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildQrColumn(TheavPalette palette, AppLocalizations l10n) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TheavInsetGroup(
          margin: EdgeInsets.zero,
          header: l10n.translate('qr_login_title'),
          footer: l10n.trOr(
            'qr_login_scan_instruction',
            'Open Theaver on another signed-in device: Settings -> Devices -> Link Device.',
          ),
          children: [
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_qrLoading)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 64),
                      child: SizedBox(
                        width: 28,
                        height: 28,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.4,
                          valueColor: AlwaysStoppedAnimation<Color>(
                            palette.primary,
                          ),
                        ),
                      ),
                    )
                  else if (_qrError != null)
                    Column(
                      children: [
                        TheavAuthErrorBanner(message: _qrError!),
                        const SizedBox(height: 10),
                        TheavSpringButton(
                          variant: TheavSpringButtonVariant.glass,
                          label: l10n.translate('qr_login_retry'),
                          onPressed: _startQrLogin,
                        ),
                      ],
                    )
                  else if (_qrUrl != null) ...[
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.08),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: SizedBox(
                        width: 176,
                        height: 176,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            PrettyQrView.data(
                              data: _qrUrl!,
                              errorCorrectLevel: QrErrorCorrectLevel.M,
                              decoration: const PrettyQrDecoration(
                                shape: PrettyQrSmoothSymbol(
                                  color: Color(0xFF1C1C1E),
                                ),
                              ),
                            ),
                            if (_qrExpired)
                              Container(
                                color: Colors.white.withValues(alpha: 0.92),
                                alignment: Alignment.center,
                                child: GestureDetector(
                                  onTap: _startQrLogin,
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      iconoir.Refresh(
                                        width: 28,
                                        height: 28,
                                        color: palette.primary,
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        l10n.translate('qr_login_refresh'),
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w700,
                                          color: palette.primary,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    if (_qrShortCode != null && _qrShortCode!.isNotEmpty) ...[
                      const SizedBox(height: 14),
                      GestureDetector(
                        onTap: () {
                          Clipboard.setData(ClipboardData(text: _qrShortCode!));
                          HapticUtils.selection();
                          GlassToastService().show(
                            context,
                            l10n.trOr('copied_to_clipboard', 'Copied'),
                            icon: Icons.copy_outlined,
                          );
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: palette.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            _qrShortCode!,
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 3,
                              color: palette.primary,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TheavInsetGroup(
          margin: EdgeInsets.zero,
          header: l10n.trOr('qr_login_enter_code_title', 'Or enter link code'),
          children: [
            TheavInlineTextField(
              controller: _qrClaimCodeCtrl,
              enabled: !_qrClaiming,
              placeholder: l10n.translate('qr_login_code_hint'),
              prefix: iconoir.QrCode(
                width: 19,
                height: 19,
                color: palette.subtext,
              ),
              onSubmitted: (_) => _claimQrCode(),
            ),
          ],
        ),
        if (_qrClaimError != null) ...[
          const SizedBox(height: 6),
          TheavAuthErrorBanner(message: _qrClaimError!),
        ],
        const SizedBox(height: 10),
        TheavSpringButton(
          variant: TheavSpringButtonVariant.glass,
          isLoading: _qrClaiming,
          label: l10n.translate('qr_login_claim_button'),
          onPressed: _claimQrCode,
        ),
      ],
    );
  }
}
