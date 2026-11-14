import 'dart:async';
import 'package:flutter/foundation.dart' show kIsWeb, defaultTargetPlatform, TargetPlatform;
import 'package:flutter/material.dart';
import 'package:pretty_qr_code/pretty_qr_code.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
import '../../services/notification_settings_provider.dart';
import '../../services/privacy_settings_provider.dart';
import '../../services/settings_service.dart';
import '../../services/tiling_layout_controller.dart';
import '../../services/websocket_service.dart';
import '../../services/geo_language_service.dart';
import '../../widgets/tiling/tiling_workspace_scaffold.dart';
import 'register_screen.dart';
import 'recovery_screen.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/swipe_back_route.dart';
import '../../config/app_config.dart';
import '../settings/service_menu_screen.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key, this.initialUsername}) : super(key: key);

  final String? initialUsername;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _obscurePassword = true;
  String? _errorMessage;
  String? _suggestedLanguageCode;

  // QR Login state (Web / Desktop)
  bool _qrMode = false;
  bool _qrLoading = false;
  bool _qrExpired = false;
  bool _qrAwaiting2faHandled = false;
  String? _qrToken;
  String? _qrSecret;
  String? _qrShortCode;
  String? _qrUrl;
  String? _qrError;
  Timer? _qrPollTimer;

  bool get _supportsQrLogin =>
      kIsWeb ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.linux;

  @override
  void initState() {
    super.initState();
    if (widget.initialUsername != null && widget.initialUsername!.isNotEmpty) {
      _emailController.text = widget.initialUsername!;
    }
    // Откладываем вызов до первого кадра, чтобы Provider был доступен
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _detectLanguage();
    });
  }

  Future<void> _detectLanguage() async {
    final detected = await GeoLanguageService.detectLanguage();
    if (detected == null || !mounted) return;

    // Ждём загрузки сохранённого языка из SharedPreferences
    await context.read<LocaleProvider>().ready;
    if (!mounted) return;

    final currentLangCode = context.read<LocaleProvider>().locale.languageCode;

    // Показываем кнопку только если язык отличается от текущего
    if (detected != currentLangCode) {
      setState(() {
        _suggestedLanguageCode = detected;
      });
    }
  }

  void _switchLanguage() {
    if (_suggestedLanguageCode == null) return;
    context.read<LocaleProvider>().setLocaleByCode(_suggestedLanguageCode!);
    setState(() {
      _suggestedLanguageCode = null;
    });
  }

  @override
  void dispose() {
    _qrPollTimer?.cancel();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _reloadUserScopedProviders(String? userId) async {
    await SettingsService().reloadForUser(userId);
    if (!mounted) return;
    try {
      await context.read<PrivacySettingsProvider>().reloadForUser();
    } catch (_) {}
    if (!mounted) return;
    try {
      await context.read<NotificationSettingsProvider>().reloadForUser();
    } catch (_) {}
  }

  Future<void> _navigateToWorkspace(String? userId) async {
    await _reloadUserScopedProviders(userId);
    await WebSocketService().updateUserId(userId);
    if (!mounted) return;
    TilingLayoutController.instance.closeAllChats();
    final localNav = Navigator.of(context);
    if (TilingLayoutController.instance.isWorkspaceMounted && localNav.canPop()) {
      localNav.popUntil((route) => route.isFirst);
    } else {
      Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
        SwipeBackPageRoute(builder: (_) => const TilingWorkspaceScaffold()),
        (route) => false,
      );
    }
  }

  Future<Map<String, dynamic>?> _promptTwoFactorDialog({
    bool hasRecoveryEmail = false,
    String? usernameOrEmail,
    String? accountPassword,
    bool allowEmailReset = true,
  }) async {
    final l10n = context.l10n;
    final codeCtrl = TextEditingController();
    final resetOtpCtrl = TextEditingController();
    bool useRecoveryCode = false;
    bool resetMode = false;
    bool resetOtpSent = false;
    bool busy = false;
    String? dialogError;
    String? maskedEmail;

    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          if (resetMode) {
            return AlertDialog(
              title: Text(l10n.translate('auth_2fa_reset_title')),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    maskedEmail != null && maskedEmail!.isNotEmpty
                        ? l10n
                            .translate('email_code_sent')
                            .replaceAll('{email}', maskedEmail!)
                        : l10n.translate('auth_2fa_reset_desc'),
                    style: Theme.of(ctx).textTheme.bodySmall,
                  ),
                  if (resetOtpSent) ...[
                    const SizedBox(height: 12),
                    TextField(
                      controller: resetOtpCtrl,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      decoration: InputDecoration(
                        labelText: l10n.translate('email_otp_label'),
                        counterText: '',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ],
                  if (dialogError != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      dialogError!,
                      style: const TextStyle(color: Colors.red, fontSize: 13),
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: busy
                      ? null
                      : () => setDialogState(() {
                            resetMode = false;
                            dialogError = null;
                          }),
                  child: Text(l10n.translate('common_back')),
                ),
                ElevatedButton(
                  onPressed: busy
                      ? null
                      : () async {
                          if (!resetOtpSent) {
                            setDialogState(() {
                              busy = true;
                              dialogError = null;
                            });
                            final res = await AuthService.send2FAResetCode(
                              usernameOrEmail: usernameOrEmail ?? '',
                              password: accountPassword ?? '',
                            );
                            if (!ctx.mounted) return;
                            if (res['success'] == true) {
                              setDialogState(() {
                                busy = false;
                                resetOtpSent = true;
                                maskedEmail = res['masked_email']?.toString();
                              });
                            } else {
                              setDialogState(() {
                                busy = false;
                                dialogError = res['message']?.toString() ??
                                    l10n.translate('common_error');
                              });
                            }
                          } else {
                            setDialogState(() {
                              busy = true;
                              dialogError = null;
                            });
                            final res = await AuthService.confirm2FAReset(
                              usernameOrEmail: usernameOrEmail ?? '',
                              password: accountPassword ?? '',
                              code: resetOtpCtrl.text.trim(),
                            );
                            if (!ctx.mounted) return;
                            if (res['success'] == true) {
                              Navigator.pop(ctx, {'resetDone': true});
                            } else {
                              setDialogState(() {
                                busy = false;
                                dialogError = res['message']?.toString() ??
                                    l10n.translate('email_error_invalid_code');
                              });
                            }
                          }
                        },
                  child: Text(
                    resetOtpSent
                        ? l10n.translate('confirm')
                        : l10n.translate('recovery_send_button'),
                  ),
                ),
              ],
            );
          }

          return AlertDialog(
            title: Text(l10n.translate('security_2fa')),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextField(
                  controller: codeCtrl,
                  obscureText: !useRecoveryCode,
                  autofocus: true,
                  decoration: InputDecoration(
                    labelText: useRecoveryCode
                        ? l10n.translate('auth_2fa_backup_code_label')
                        : l10n.translate('security_2fa_password_label'),
                    border: const OutlineInputBorder(),
                  ),
                  onSubmitted: (val) => Navigator.pop(ctx, {
                    'value': val,
                    'isRecoveryCode': useRecoveryCode,
                  }),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: () {
                    setDialogState(() {
                      useRecoveryCode = !useRecoveryCode;
                      codeCtrl.clear();
                    });
                  },
                  child: Text(
                    useRecoveryCode
                        ? l10n.translate('auth_2fa_use_password')
                        : l10n.translate('auth_2fa_use_backup_code'),
                  ),
                ),
                if (allowEmailReset && hasRecoveryEmail && usernameOrEmail != null)
                  TextButton(
                    onPressed: () {
                      setDialogState(() {
                        resetMode = true;
                        dialogError = null;
                      });
                    },
                    child: Text(l10n.translate('auth_2fa_forgot_password')),
                  ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, null),
                child: Text(l10n.translate('cancel')),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, {
                  'value': codeCtrl.text,
                  'isRecoveryCode': useRecoveryCode,
                }),
                child: Text(l10n.translate('confirm')),
              ),
            ],
          );
        },
      ),
    );
    codeCtrl.dispose();
    resetOtpCtrl.dispose();
    return result;
  }

  Future<void> _login({String? twoFactorPassword, String? recoveryCode}) async {
    if (!_formKey.currentState!.validate()) {
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await AuthService.login(
        usernameOrEmail: _emailController.text.trim(),
        password: _passwordController.text,
        twoFactorPassword: twoFactorPassword,
        recoveryCode: recoveryCode,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        await _navigateToWorkspace(result['userId'] as String?);
      } else if (result['requires_2fa'] == true &&
          twoFactorPassword == null &&
          recoveryCode == null) {
        setState(() {
          _isLoading = false;
        });
        final choice = await _promptTwoFactorDialog(
          hasRecoveryEmail: result['has_recovery_email'] == true,
          usernameOrEmail: _emailController.text.trim(),
          accountPassword: _passwordController.text,
        );
        if (!mounted || choice == null) return;
        if (choice['resetDone'] == true) {
          await _login();
          return;
        }
        final value = choice['value']?.toString().trim() ?? '';
        if (value.isNotEmpty) {
          if (choice['isRecoveryCode'] == true) {
            await _login(recoveryCode: value);
          } else {
            await _login(twoFactorPassword: value);
          }
        }
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = result['message'] as String?;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = context.l10n.translate('auth_unexpected_error');
      });
    }
  }

  Future<void> _startQrLogin() async {
    _qrPollTimer?.cancel();
    setState(() {
      _qrMode = true;
      _qrLoading = true;
      _qrExpired = false;
      _qrAwaiting2faHandled = false;
      _qrError = null;
      _qrToken = null;
      _qrSecret = null;
      _qrShortCode = null;
      _qrUrl = null;
    });

    final created = await AuthService.createQrLoginSession();
    if (!mounted || !_qrMode) return;
    if (created['success'] != true) {
      setState(() {
        _qrLoading = false;
        _qrError = created['message']?.toString() ??
            context.l10n.translate('common_error');
      });
      return;
    }

    setState(() {
      _qrLoading = false;
      _qrToken = created['token']?.toString();
      _qrSecret = created['qr_secret']?.toString();
      _qrShortCode = created['short_code']?.toString();
      _qrUrl = created['qr_url']?.toString();
    });

    _qrPollTimer = Timer.periodic(const Duration(seconds: 2), (_) async {
      await _pollQrStatus();
    });
  }

  Future<void> _pollQrStatus() async {
    final token = _qrToken;
    final secret = _qrSecret;
    if (!mounted || !_qrMode || token == null || secret == null) {
      _qrPollTimer?.cancel();
      return;
    }
    final statusRes = await AuthService.pollQrLoginStatus(
      token: token,
      qrSecret: secret,
    );
    if (!mounted || !_qrMode) return;

    final status = statusRes['status']?.toString() ?? '';
    if (status == 'expired') {
      _qrPollTimer?.cancel();
      setState(() => _qrExpired = true);
      return;
    }

    if (status == 'confirmed' && statusRes['auth_token'] != null) {
      _qrPollTimer?.cancel();
      final authToken = statusRes['auth_token'].toString();
      final userId = statusRes['user_id']?.toString() ?? '';
      final userMap = statusRes['user'] is Map
          ? Map<String, dynamic>.from(statusRes['user'] as Map)
          : null;
      await AuthService.completeExternalLoginSession(
        authToken: authToken,
        userId: userId,
        user: userMap,
      );
      if (mounted) {
        await _navigateToWorkspace(userId);
      }
      return;
    }

    if (status == 'awaiting_2fa' && !_qrAwaiting2faHandled) {
      _qrAwaiting2faHandled = true;
      _qrPollTimer?.cancel();
      final choice = await _promptTwoFactorDialog(allowEmailReset: false);
      if (!mounted) return;
      if (choice == null || (choice['value']?.toString().trim().isEmpty ?? true)) {
        setState(() {
          _qrAwaiting2faHandled = false;
        });
        _qrPollTimer = Timer.periodic(const Duration(seconds: 2), (_) => _pollQrStatus());
        return;
      }
      final val = choice['value'].toString().trim();
      final verifyRes = await AuthService.verifyQrLogin2FA(
        token: token,
        qrSecret: secret,
        twoFactorPassword: choice['isRecoveryCode'] == true ? null : val,
        recoveryCode: choice['isRecoveryCode'] == true ? val : null,
      );
      if (!mounted) return;
      if (verifyRes['success'] == true && verifyRes['auth_token'] != null) {
        final authToken = verifyRes['auth_token'].toString();
        final userId = verifyRes['user_id']?.toString() ?? '';
        final userMap = verifyRes['user'] is Map
            ? Map<String, dynamic>.from(verifyRes['user'] as Map)
            : null;
        await AuthService.completeExternalLoginSession(
          authToken: authToken,
          userId: userId,
          user: userMap,
        );
        if (mounted) {
          await _navigateToWorkspace(userId);
        }
      } else {
        setState(() {
          _qrAwaiting2faHandled = false;
          _qrError = verifyRes['message']?.toString() ??
              context.l10n.translate('email_error_invalid_2fa');
        });
      }
    }
  }

  void _stopQrLogin() {
    _qrPollTimer?.cancel();
    setState(() {
      _qrMode = false;
      _qrError = null;
    });
  }

  void _navigateToRecovery() {
    Navigator.push(
      context,
      SwipeBackPageRoute(builder: (_) => const RecoveryScreen()),
    );
  }

  void _navigateToRegister() {
    Navigator.push(
      context,
      SwipeBackPageRoute(builder: (_) => const RegisterScreen()),
    );
  }

  Future<void> _loginAsTestUser() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final result = await AuthService.loginAsTestUser();

      if (!mounted) return;

      if (result['success'] == true) {
        // Update WebSocket with test user ID
        final wsService = WebSocketService();
        await wsService.updateUserId(result['userId'] as String?);

        if (!mounted) return;
        TilingLayoutController.instance.closeAllChats();
        // Navigate to home screen and clear back stack
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          SwipeBackPageRoute(builder: (_) => const TilingWorkspaceScaffold()),
          (route) => false,
        );
      } else {
        setState(() {
          _isLoading = false;
          _errorMessage = result['message'] as String?;
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _isLoading = false;
        _errorMessage = 'Test login failed: $e';
      });
    }
  }

  Future<void> _handleGoogleSignIn() async {
    // TODO: Implement Google Sign-In
    // For now, show a placeholder message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.translate('auth_google_signin_not_implemented')),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  Future<void> _handleAppleSignIn() async {
    // TODO: Implement Apple Sign-In
    // For now, show a placeholder message
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(context.l10n.translate('auth_apple_signin_not_implemented')),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      if (_suggestedLanguageCode != null)
                        TextButton.icon(
                          onPressed: _switchLanguage,
                          icon: const Icon(Icons.language, size: 18),
                          label: Text(_suggestedLanguageCode!.toUpperCase()),
                        )
                      else
                        const SizedBox.shrink(),
                      IconButton(
                        icon: const Icon(Icons.dns_outlined),
                        tooltip: 'Настройка сервера (${AppConfig.baseUrl})',
                        onPressed: () async {
                          await Navigator.push(
                            context,
                            SwipeBackPageRoute(
                              builder: (_) => const ServiceMenuScreen(),
                            ),
                          );
                          if (mounted) setState(() {});
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Logo or App Name
                  Text(
                    l10n.translate('app_title'),
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  const SizedBox(height: 4),
                  InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () async {
                      await Navigator.push(
                        context,
                        SwipeBackPageRoute(
                          builder: (_) => const ServiceMenuScreen(),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.link, size: 14, color: Colors.grey[600]),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              AppConfig.baseUrl,
                              style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 32),
                  // Email/Username Field
                  TextFormField(
                    controller: _emailController,
                    decoration: InputDecoration(
                      labelText: l10n.translate('auth_email_or_username'),
                      prefixIcon: const Icon(Icons.email_outlined),
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                      ),
                      enabledBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                        borderSide: BorderSide(color: Color(0xFF0088CC), width: 2),
                      ),
                    ),
                    keyboardType: TextInputType.emailAddress,
                    textInputAction: TextInputAction.next,
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return l10n.translate('validation_enter_email');
                      }
                      return null;
                    },
                  ),
                  const SizedBox(height: 16),
                  // Password Field
                  TextFormField(
                    controller: _passwordController,
                    decoration: InputDecoration(
                      labelText: l10n.translate('auth_password'),
                      prefixIcon: const Icon(Icons.lock_outline),
                      suffixIcon: IconButton(
                        icon: Icon(
                          _obscurePassword
                              ? Icons.visibility_off
                              : Icons.visibility,
                        ),
                        onPressed: () {
                          setState(() {
                            _obscurePassword = !_obscurePassword;
                          });
                        },
                      ),
                      border: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                      ),
                      enabledBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                      ),
                      focusedBorder: const OutlineInputBorder(
                        borderRadius: BorderRadius.all(Radius.circular(16)),
                        borderSide: BorderSide(color: Color(0xFF0088CC), width: 2),
                      ),
                    ),
                    obscureText: _obscurePassword,
                    textInputAction: TextInputAction.done,
                    onFieldSubmitted: (_) => _login(),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return l10n.translate('validation_enter_password');
                      }
                      if (value.length < 6) {
                        return l10n.translate('validation_password_length');
                      }
                      return null;
                    },
                  ),
                  if (_errorMessage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 16.0),
                      child: Text(
                        _errorMessage!,
                        style: const TextStyle(color: Colors.red, fontSize: 14),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  const SizedBox(height: 24),
                  // Login Button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton(
                      onPressed: _isLoading ? null : _login,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                      ),
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
                              l10n.translate('auth_login'),
                              style: const TextStyle(fontSize: 16),
                            ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // Test Login Button (offline mode)
                  SizedBox(
                    width: double.infinity,
                    height: 40,
                    child: OutlinedButton(
                      onPressed: _isLoading ? null : _loginAsTestUser,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.grey[600],
                        side: BorderSide(color: Colors.grey[400]!),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Test Login (admin / admin)',
                        style: TextStyle(fontSize: 14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Forgot Password?
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _isLoading ? null : _navigateToRecovery,
                      child: Text(l10n.translate('auth_forgot_password')),
                    ),
                  ),
                  if (_supportsQrLogin) ...[
                    const SizedBox(height: 8),
                    if (!_qrMode)
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _isLoading ? null : _startQrLogin,
                          icon: const Icon(Icons.qr_code_2),
                          label: Text(l10n.translate('auth_qr_sign_in')),
                        ),
                      )
                    else
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.surfaceContainerHighest.withOpacity(0.5),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: Theme.of(context).dividerColor.withOpacity(0.25),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              l10n.translate('auth_qr_title'),
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            const SizedBox(height: 12),
                            if (_qrLoading)
                              const Padding(
                                padding: EdgeInsets.all(32),
                                child: CircularProgressIndicator(),
                              )
                            else if (_qrError != null)
                              Column(
                                children: [
                                  Text(
                                    _qrError!,
                                    style: const TextStyle(color: Colors.red),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 8),
                                  TextButton(
                                    onPressed: _startQrLogin,
                                    child: Text(l10n.translate('devices_retry')),
                                  ),
                                ],
                              )
                            else if (_qrExpired)
                              Column(
                                children: [
                                  Text(l10n.translate('auth_qr_expired')),
                                  const SizedBox(height: 8),
                                  ElevatedButton(
                                    onPressed: _startQrLogin,
                                    child: Text(l10n.translate('auth_qr_refresh')),
                                  ),
                                ],
                              )
                            else if (_qrUrl != null) ...[
                              Container(
                                width: 184,
                                height: 184,
                                padding: const EdgeInsets.all(12),
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  borderRadius: BorderRadius.circular(16),
                                ),
                                child: PrettyQrView.data(
                                  data: _qrUrl!,
                                  decoration: const PrettyQrDecoration(
                                    shape: PrettyQrSmoothSymbol(
                                      color: Colors.black,
                                    ),
                                  ),
                                ),
                              ),
                              if (_qrShortCode != null && _qrShortCode!.isNotEmpty) ...[
                                const SizedBox(height: 12),
                                SelectableText(
                                  '${l10n.translate('auth_qr_code_label')}: $_qrShortCode',
                                  style: const TextStyle(
                                    fontFamily: 'monospace',
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.5,
                                  ),
                                ),
                              ],
                              const SizedBox(height: 8),
                              Text(
                                l10n.translate('auth_qr_instructions'),
                                style: Theme.of(context).textTheme.bodySmall,
                                textAlign: TextAlign.center,
                              ),
                            ],
                            const SizedBox(height: 12),
                            TextButton(
                              onPressed: _stopQrLogin,
                              child: Text(l10n.translate('auth_qr_back_password')),
                            ),
                          ],
                        ),
                      ),
                  ],
                  const SizedBox(height: 24),
                  // Divider or Social Login (optional)
                  Row(
                    children: [
                      const Expanded(child: Divider()),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8.0),
                        child: Text(l10n.translate('auth_or_continue_with')),
                      ),
                      const Expanded(child: Divider()),
                    ],
                  ),
                  const SizedBox(height: 16),
                  // Social Login Buttons (optional)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Google
                      OutlinedButton.icon(
                        icon: const Icon(Icons.g_mobiledata, color: Colors.red),
                        label: const Text('Google'),
                        onPressed: _isLoading ? null : _handleGoogleSignIn,
                      ),
                      const SizedBox(width: 16),
                      // Apple
                      OutlinedButton.icon(
                        icon: const Icon(Icons.phone_iphone, color: Colors.black),
                        label: const Text('Apple'),
                        onPressed: _isLoading ? null : _handleAppleSignIn,
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Don't have an account? Sign up
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text("${l10n.translate('auth_no_account')} "),
                      TextButton(
                        onPressed: _isLoading ? null : _navigateToRegister,
                        child: Text(l10n.translate('auth_sign_up')),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),
                  // Language switch button based on IP geolocation
                  if (_suggestedLanguageCode != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: OutlinedButton(
                          onPressed: _switchLanguage,
                          style: OutlinedButton.styleFrom(
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                            side: const BorderSide(color: Colors.blue),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.language, color: Colors.blue, size: 20),
                              const SizedBox(width: 8),
                              Text(
                                GeoLanguageService.getSwitchButtonText(_suggestedLanguageCode!) ?? _suggestedLanguageCode!,
                                style: const TextStyle(color: Colors.blue, fontSize: 15),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
