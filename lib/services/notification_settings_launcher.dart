import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

/// Открывает системные настройки уведомлений приложения.
///
/// - Android: нативный метод `openAppNotificationSettings` в канале
///   `app.theaver.messenger/push_detector`.
/// - iOS / macOS: экран настроек приложения через `permission_handler`.
/// - Остальные платформы (включая Web): no-op.
class NotificationSettingsLauncher {
  NotificationSettingsLauncher._();

  static const MethodChannel _channel =
      MethodChannel('app.theaver.messenger/push_detector');

  /// Открывает системный экран настроек уведомлений для Theaver.
  static Future<void> openAppNotificationSettings() async {
    if (kIsWeb) return;
    try {
      switch (defaultTargetPlatform) {
        case TargetPlatform.android:
          await _channel.invokeMethod('openAppNotificationSettings');
          break;
        case TargetPlatform.iOS:
        case TargetPlatform.macOS:
          await ph.openAppSettings();
          break;
        default:
          break;
      }
    } catch (e) {
      debugPrint('NotificationSettingsLauncher: failed to open settings: $e');
    }
  }
}
