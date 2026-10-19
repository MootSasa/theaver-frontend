import 'package:flutter/foundation.dart';

class WebNotificationHelper {
  static void init({
    required VoidCallback onTabHidden,
    required VoidCallback onTabVisible,
  }) {}

  static Future<bool> requestPermission() async => false;

  static bool get isTabFocused => true;

  static void showBrowserNotification({
    required String title,
    required String body,
    String? iconUrl,
    String? tag,
    VoidCallback? onTap,
  }) {}

  static void playNotificationSound() {}
}
