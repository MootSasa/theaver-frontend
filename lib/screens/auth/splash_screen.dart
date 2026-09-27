import 'package:flutter/material.dart';
import '../../services/account_manager.dart';
import '../../services/auth_service.dart';
import '../../services/notification_service.dart';
import '../main/main_screen.dart';
import 'login_screen.dart';
import '../../utils/swipe_back_route.dart';

/// Splash screen that checks authentication status on app launch.
/// Automatically navigates to MainScreen if user is logged in,
/// or to LoginScreen if no saved account found.
class SplashScreen extends StatefulWidget {
  const SplashScreen({Key? key}) : super(key: key);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  bool _hasNavigated = false;

  @override
  void initState() {
    super.initState();
    // Use addPostFrameCallback to ensure navigation happens after build
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAuthAndNavigate();
    });
  }

  Future<void> _checkAuthAndNavigate() async {
    if (_hasNavigated || !mounted) return;

    // Initialize AccountManager
    final accountManager = AccountManager();
    
    // Check if there's a saved account
    if (accountManager.hasSavedAccount) {
      _navigateToMain();
      
      // Update device activity in background
      _updateActivityInBackground();
    } else {
      _navigateToLogin();
    }
  }

  void _navigateToMain() {
    if (_hasNavigated || !mounted) return;
    _hasNavigated = true;
    
    Navigator.of(context).pushAndRemoveUntil(
      SwipeBackPageRoute(builder: (_) => const MainScreen()),
      (route) => false,
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationService().consumePendingNotification();
    });
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
      
      // Verify token in background
      final result = await AuthService.getCurrentUser();
      if (result['success'] != true) {
        debugPrint('Token verification failed: ${result['message']}');
      } else {
        // Register current push token on server for this active session
        NotificationService().registerCurrentToken();
      }
    } catch (e) {
      debugPrint('Background update error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    
    // Show a simple loading indicator while checking auth
    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App logo/icon
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFF0088CC),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.chat_bubble_rounded,
                size: 40,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 16),
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF0088CC)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
