import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/account_manager.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../../utils/swipe_back_route.dart';
import '../../widgets/auth/theav_auth_primitives.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/tiling/tiling_workspace_scaffold.dart';
import 'first_start_wizard_screen.dart';
import 'login_screen.dart';

/// Splash screen that routes cleanly without a harsh white flash:
/// - Saved active account -> [TilingWorkspaceScaffold]
/// - Fresh device before onboarding -> [FirstStartWizardScreen]
/// - Signed-out / post-wizard -> [LoginScreen]
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuthAndNavigate();
    });
  }

  Future<void> _checkAuthAndNavigate() async {
    if (_hasNavigated || !mounted) return;
    final accountManager = AccountManager();
    if (accountManager.hasSavedAccount) {
      _navigateToMain();
      _updateActivityInBackground();
      return;
    }

    bool onboardingDone = false;
    try {
      final prefs = await SharedPreferences.getInstance();
      onboardingDone = prefs.getBool(kOnboardingWizardCompletedPrefKey) ?? false;
    } catch (_) {}

    if (!mounted || _hasNavigated) return;
    if (!onboardingDone && accountManager.accounts.isEmpty) {
      _navigateToWizard();
    } else {
      _navigateToLogin();
    }
  }

  void _navigateToMain() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    Navigator.of(context).pushAndRemoveUntil(
      SwipeBackPageRoute(builder: (_) => const TilingWorkspaceScaffold()),
      (route) => false,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().consumePendingNotification();
    });
  }

  void _navigateToWizard() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    Navigator.of(context).pushAndRemoveUntil(
      SwipeBackPageRoute(builder: (_) => const FirstStartWizardScreen()),
      (route) => false,
    );
  }

  void _navigateToLogin() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;

    Navigator.of(context).pushAndRemoveUntil(
      SwipeBackPageRoute(builder: (_) => const LoginScreen()),
      (route) => false,
    );
  }

  Future<void> _updateActivityInBackground() async {
    try {
      final accountManager = AccountManager();
      await accountManager.updateCurrentDeviceActivity();
      final result = await AuthService.getCurrentUser();
      if (result['success'] == true) {
        await NotificationService().registerCurrentToken();
      }
    } catch (e) {
      debugPrint('SplashScreen background update error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const TheavAuthWallpaperBackground(),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: palette.surface.withValues(alpha: 0.72),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: palette.onSurface.withValues(alpha: 0.08),
                      width: 0.75,
                    ),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Image.asset(
                      'assets/icons/app_icon.png',
                      width: 80,
                      height: 80,
                      filterQuality: FilterQuality.high,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.2,
                    valueColor: AlwaysStoppedAnimation<Color>(palette.primary),
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
