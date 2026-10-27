import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/auth_service.dart';
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
  const LoginScreen({Key? key}) : super(key: key);

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

  @override
  void initState() {
    super.initState();
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
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
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
      );

      if (!mounted) return;

      if (result['success'] == true) {
        // Update WebSocket with new user ID
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
        _errorMessage = context.l10n.translate('auth_unexpected_error');
      });
    }
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
