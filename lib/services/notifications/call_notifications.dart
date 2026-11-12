import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show Color;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'message_notification_presenter.dart';
import 'notification_channels.dart';
import 'notification_images.dart';

/// Incoming / missed call system notifications (Android, iOS, macOS).
/// Shared by the main isolate and the push background isolate.
class CallNotifications {
  CallNotifications._();

  static const int incomingCallId = 77703;
  static const int _missedCallIdBase = 77800;
  static const String _lastCallIdKey = 'last_incoming_call_id';
  static const String _lastCallTsKey = 'last_incoming_call_ts';
  static const MethodChannel _native = MethodChannel('app.theaver.messenger/push_detector');

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  /// Cross-isolate guard against showing the same call twice (push + WebSocket).
  /// Returns true if the call is new and was registered.
  static Future<bool> markCallShown(String callId) async {
    if (callId.isEmpty) return true;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.reload();
      final now = DateTime.now().millisecondsSinceEpoch;
      if (prefs.getString(_lastCallIdKey) == callId &&
          now - (prefs.getInt(_lastCallTsKey) ?? 0) < 45000) {
        return false;
      }
      await prefs.setString(_lastCallIdKey, callId);
      await prefs.setInt(_lastCallTsKey, now);
    } catch (_) {}
    return true;
  }

  static Future<void> clearCallShown(String? callId) async {
    if (callId == null || callId.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getString(_lastCallIdKey) == callId) {
        await prefs.remove(_lastCallIdKey);
        await prefs.remove(_lastCallTsKey);
      }
    } catch (_) {}
  }

  static String titleFor({required bool isVideo, required bool isGroup}) => isVideo
      ? (isGroup ? 'Групповой видеозвонок' : 'Входящий видеозвонок')
      : (isGroup ? 'Групповой звонок' : 'Входящий звонок');

  /// Shows the incoming call notification: full-screen intent on a locked
  /// screen, heads-up with "Принять"/"Отклонить" otherwise (also in foreground —
  /// there is no custom in-app call banner anymore).
  static Future<void> showIncoming(
    FlutterLocalNotificationsPlugin plugin, {
    required Map<String, dynamic> payload,
    required String callerName,
    String? callerAvatar,
    bool isVideo = false,
    bool isGroup = false,
  }) async {
    if (_isAndroid) {
      try {
        await _native.invokeMethod('wakeUpScreenForCall', {'enable': true});
      } catch (_) {}
    }

    FilePathAndroidBitmap? largeIcon;
    if (_isAndroid && callerAvatar != null && callerAvatar.isNotEmpty) {
      final path = await downloadOrGetCachedAvatar(callerAvatar);
      if (path != null) largeIcon = FilePathAndroidBitmap(path);
    }

    final title = titleFor(isVideo: isVideo, isGroup: isGroup);
    final body = '$callerName звонит вам';

    final android = AndroidNotificationDetails(
      NotificationChannels.incomingCalls,
      NotificationChannels.label(NotificationChannels.incomingCalls),
      channelDescription: NotificationChannels.description(NotificationChannels.incomingCalls),
      importance: Importance.max,
      priority: Priority.max,
      icon: '@drawable/ic_notification',
      color: const Color(0xFF2ECC71),
      largeIcon: largeIcon,
      autoCancel: false,
      ongoing: true,
      onlyAlertOnce: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.call,
      visibility: NotificationVisibility.public,
      timeoutAfter: 45000,
      playSound: true,
      enableVibration: true,
      vibrationPattern: Int64List.fromList(<int>[0, 500, 400, 500, 400, 500, 400, 500]),
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction(
          'accept_call',
          'Принять',
          showsUserInterface: true,
          cancelNotification: true,
          titleColor: Color(0xFF2ECC71),
        ),
        AndroidNotificationAction(
          'decline_call',
          'Отклонить',
          showsUserInterface: true,
          cancelNotification: true,
          titleColor: Color(0xFFE74C3C),
        ),
      ],
    );
    // Critical alerts require a special Apple entitlement; time-sensitive does not
    // (only the "Time Sensitive Notifications" capability).
    const darwin = DarwinNotificationDetails(
      presentAlert: true,
      presentBanner: true,
      presentList: true,
      presentBadge: false,
      presentSound: true,
      interruptionLevel: InterruptionLevel.timeSensitive,
      categoryIdentifier: MessageNotificationPresenter.darwinCallCategory,
    );
    try {
      await plugin.show(
        incomingCallId,
        title,
        body,
        NotificationDetails(android: android, iOS: darwin, macOS: darwin),
        payload: jsonEncode(payload),
      );
    } catch (e) {
      debugPrint('CallNotifications: incoming call notification failed: $e');
    }
  }

  static Future<void> cancelIncoming(
    FlutterLocalNotificationsPlugin plugin, {
    String? callId,
    String? chatId,
  }) async {
    await clearCallShown(callId);
    try {
      await plugin.cancel(incomingCallId);
    } catch (_) {}
    if (_isAndroid) {
      try {
        await _native.invokeMethod('cancelCallNotifications', {
          'call_id': callId ?? '',
          'chat_id': chatId ?? '',
        });
      } catch (_) {}
    }
  }

  static Future<void> showMissed(
    FlutterLocalNotificationsPlugin plugin, {
    required Map<String, dynamic> payload,
    required String callerName,
    required String callKey,
    bool isVideo = false,
  }) async {
    final title = isVideo ? 'Пропущенный видеозвонок' : 'Пропущенный звонок';
    final android = AndroidNotificationDetails(
      NotificationChannels.missedCalls,
      NotificationChannels.label(NotificationChannels.missedCalls),
      channelDescription: NotificationChannels.description(NotificationChannels.missedCalls),
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
      icon: '@drawable/ic_notification',
      color: const Color(0xFFE74C3C),
      autoCancel: true,
      onlyAlertOnce: true,
      category: AndroidNotificationCategory.missedCall,
      actions: const <AndroidNotificationAction>[
        AndroidNotificationAction(
          'callback_missed_call',
          'Перезвонить',
          showsUserInterface: true,
          cancelNotification: true,
          titleColor: Color(0xFF5B7FFF),
        ),
      ],
    );
    const darwin = DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentSound: false);
    try {
      await plugin.show(
        _missedCallIdBase + (callKey.hashCode.abs() % 1000),
        title,
        callerName,
        NotificationDetails(android: android, iOS: darwin, macOS: darwin),
        payload: jsonEncode(payload),
      );
    } catch (e) {
      debugPrint('CallNotifications: missed call notification failed: $e');
    }
  }
}
