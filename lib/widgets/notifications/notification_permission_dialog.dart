import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/notification_service.dart';
import '../../utils/haptic_utils.dart';

/// Диалог запроса разрешений на уведомления при первом входе.
class NotificationPermissionDialog {
  static const String _prefKey = 'has_prompted_notification_permission';

  /// Проверяет статус разрешений и показывает диалог, если они ещё не запрошены.
  static Future<void> checkAndPrompt(BuildContext context) async {
    // Уведомления через системные диалоги запрашиваются на мобильных платформах (Android / iOS)
    if (kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      final alreadyPrompted = prefs.getBool(_prefKey) ?? false;
      if (alreadyPrompted) return;

      final status = await Permission.notification.status;
      if (status.isGranted) {
        await prefs.setBool(_prefKey, true);
        return;
      }

      if (!context.mounted) return;

      // Показываем bottom sheet с объяснением необходимости уведомлений
      await showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.transparent,
        builder: (ctx) => _PermissionBottomSheet(prefs: prefs),
      );
    } catch (e) {
      debugPrint('NotificationPermissionDialog error: $e');
    }
  }
}

class _PermissionBottomSheet extends StatelessWidget {
  final SharedPreferences prefs;

  const _PermissionBottomSheet({required this.prefs});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E2633) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),

            // Icon
            Container(
              width: 68,
              height: 68,
              decoration: BoxDecoration(
                color: const Color(0xFF0088CC).withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: const Center(
                child: Icon(
                  Icons.notifications_active_rounded,
                  size: 36,
                  color: Color(0xFF0088CC),
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Text(
              'Включите уведомления',
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),

            // Description
            Text(
              'Разрешите Theaver присылать уведомления, чтобы не пропускать личные сообщения от друзей, ответы в группах и входящие звонки.',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark ? Colors.white70 : Colors.black54,
                height: 1.4,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Action Buttons
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF0088CC),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 0,
                ),
                onPressed: () async {
                  HapticUtils.selection();
                  Navigator.of(context).pop();
                  await prefs.setBool(NotificationPermissionDialog._prefKey, true);

                  final result = await Permission.notification.request();
                  if (result.isGranted) {
                    await NotificationService().registerCurrentToken();
                  } else if (result.isPermanentlyDenied) {
                    // Пользователь ранее заблокировал, предлагаем открыть настройки
                    openAppSettings();
                  }
                },
                child: const Text(
                  'Включить уведомления',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            SizedBox(
              width: double.infinity,
              height: 44,
              child: TextButton(
                style: TextButton.styleFrom(
                  foregroundColor: isDark ? Colors.white60 : Colors.black45,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () async {
                  HapticUtils.selection();
                  Navigator.of(context).pop();
                  await prefs.setBool(NotificationPermissionDialog._prefKey, true);
                },
                child: const Text(
                  'Позже',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
