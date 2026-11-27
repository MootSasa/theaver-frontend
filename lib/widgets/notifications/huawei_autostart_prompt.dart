import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/notification_service.dart';
import '../../services/push_service_detector.dart';

/// Huawei/Honor (HMS): chat pushes are data messages rendered by the app; Huawei
/// delivers them to a killed app only when "App launch" (auto-launch) is allowed.
/// Shows a one-time explanation with a button to the right settings screen.
class HuaweiAutoStartPrompt {
  HuaweiAutoStartPrompt._();

  static const String _prefKey = 'hms_autostart_prompt_shown_v1';
  static const MethodChannel _channel = MethodChannel('app.theaver.messenger/native_notifications');

  /// Whether the device uses HMS push (the prompt / settings row is relevant).
  static bool get isRelevant =>
      !kIsWeb && Platform.isAndroid && NotificationService().pushServiceType == PushServiceType.hms;

  /// Opens the Huawei "App launch" screen (falls back to app details).
  static Future<void> openSettings() async {
    try {
      await _channel.invokeMethod('openAutoStartSettings');
    } catch (e) {
      debugPrint('HuaweiAutoStartPrompt: open settings failed: $e');
    }
  }

  static Future<void> maybeShow(BuildContext context) async {
    if (!isRelevant) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_prefKey) ?? false) return;
      if (!context.mounted) return;
      await prefs.setBool(_prefKey, true);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Уведомления на Huawei'),
          content: const Text(
            'Чтобы получать сообщения и звонки, когда Theaver закрыт, разрешите '
            'автозапуск:\n\n'
            '«Запуск приложений» → Theaver → выключите «Управлять автоматически» и '
            'включите «Автозапуск», «Косвенный запуск» и «Работа в фоне».',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Позже'),
            ),
            FilledButton(
              onPressed: () {
                Navigator.of(ctx).pop();
                openSettings();
              },
              child: const Text('Открыть настройки'),
            ),
          ],
        ),
      );
    } catch (e) {
      debugPrint('HuaweiAutoStartPrompt error: $e');
    }
  }
}
