import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter/widgets.dart' show WidgetsFlutterBinding;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:huawei_push/huawei_push.dart' as hms;
import 'package:uuid/uuid.dart';

import '../../config/app_config.dart';
import '../account_manager.dart';
import 'call_notifications.dart';
import 'message_notification_presenter.dart';
import 'notification_channels.dart';
import 'notification_dedup_store.dart';
import 'notification_payload.dart';

/// Initializes flutter_local_notifications in a background isolate.
Future<FlutterLocalNotificationsPlugin> initBackgroundNotificationsPlugin() async {
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(
    InitializationSettings(
      android: const AndroidInitializationSettings('@drawable/ic_notification'),
      iOS: DarwinInitializationSettings(
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
        notificationCategories: MessageNotificationPresenter.darwinCategories(),
      ),
    ),
  );
  await NotificationChannels.ensureBaseChannels(plugin);
  return plugin;
}

/// FCM background handler (must be a top-level function).
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  if (kIsWeb) return;
  final data = Map<String, dynamic>.from(message.data);
  final msgType = data['type']?.toString() ?? '';

  // Chat messages with a notification block are rendered by the OS itself.
  if (message.notification != null && msgType != 'incoming_call' && msgType != 'call_ended') {
    return;
  }

  WidgetsFlutterBinding.ensureInitialized();
  try {
    await Firebase.initializeApp();
  } catch (_) {}
  await processBackgroundPushData(data);
}

/// HMS background handler for data messages (calls, sync). Chat messages are
/// notification messages rendered by the Huawei notification center.
@pragma('vm:entry-point')
void hmsMessagingBackgroundHandler(hms.RemoteMessage message) async {
  if (kIsWeb) return;
  WidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic> data = <String, dynamic>{};
  if (message.dataOfMap != null && message.dataOfMap!.isNotEmpty) {
    data = Map<String, dynamic>.from(message.dataOfMap!);
  } else if (message.data != null && message.data!.isNotEmpty) {
    data = normalizePushPayload(message.data);
  }
  if (data.isEmpty) return;
  await processBackgroundPushData(data);
}

/// Handles data-only pushes while the app UI is not running.
Future<void> processBackgroundPushData(Map<String, dynamic> data) async {
  final msgType = data['type']?.toString() ?? '';
  final plugin = await initBackgroundNotificationsPlugin();

  switch (msgType) {
    case 'call_ended':
      await CallNotifications.cancelIncoming(
        plugin,
        callId: data['call_id']?.toString(),
        chatId: data['chat_id']?.toString(),
      );
      return;
    case 'incoming_call':
      final callId = data['call_id']?.toString() ?? '';
      if (!await CallNotifications.markCallShown(callId)) return;
      final callerName = payloadString(data, const ['caller_name', 'chat_name'], 'Входящий звонок');
      final isVideo = payloadBool(data['is_video']) || data['call_type'] == 'video';
      final isGroup = data['chat_type'] == 'group' || payloadBool(data['is_group']);
      await CallNotifications.showIncoming(
        plugin,
        payload: <String, dynamic>{
          ...data,
          'type': 'incoming_call',
          'call_id': callId,
          'caller_name': callerName,
          'is_video': isVideo,
        },
        callerName: callerName,
        callerAvatar: payloadString(data, const ['caller_avatar', 'avatar_url']),
        isVideo: isVideo,
        isGroup: isGroup,
      );
      return;
    case 'read_status_updated':
      final chatId = data['chat_id']?.toString() ?? '';
      if (chatId.isEmpty) return;
      await MessageNotificationPresenter(plugin).cancelChat(chatId);
      if (Platform.isAndroid) {
        try {
          await const MethodChannel('app.theaver.messenger/push_detector')
              .invokeMethod('cancelChatNotifications', {'chat_id': chatId});
        } catch (_) {}
      }
      return;
    case 'new_message':
      // Legacy data-only chat push (no notification block): render it ourselves.
      final m = ChatMessageNotification.fromPush(data);
      if (m == null) return;
      final key = NotificationDedupStore.keyFor(
          kind: 'msg', chatId: m.chatId, messageId: m.messageId, fallbackText: m.text);
      if (await NotificationDedupStore().checkAndMark(key)) return;
      await MessageNotificationPresenter(plugin).present(m);
      return;
    default:
      return;
  }
}

/// Handles notification actions that do not open the UI ("Ответить", "Прочитано").
/// flutter_local_notifications runs this in a dedicated background isolate even
/// while the app is alive, so it must be self-contained.
@pragma('vm:entry-point')
Future<void> notificationActionBackgroundHandler(NotificationResponse response) async {
  WidgetsFlutterBinding.ensureInitialized();
  await handleMessageNotificationAction(response);
}

/// Returns true if the response was a message action and was handled.
Future<bool> handleMessageNotificationAction(NotificationResponse response) async {
  final actionId = response.actionId;
  if (actionId != MessageNotificationPresenter.actionReply &&
      actionId != MessageNotificationPresenter.actionMarkRead) {
    return false;
  }
  final payload = normalizePushPayload(response.payload);
  final chatId = payload['chat_id']?.toString() ?? '';
  if (chatId.isEmpty) return true;

  final plugin = await initBackgroundNotificationsPlugin();
  final presenter = MessageNotificationPresenter(plugin);
  final token = await _authToken();
  if (token == null) {
    debugPrint('NotificationActions: not logged in, ignoring $actionId');
    return true;
  }

  if (actionId == MessageNotificationPresenter.actionReply) {
    final text = (response.input ?? '').trim();
    if (text.isEmpty) return true;
    final ok = await _post(
      '${AppConfig.baseUrl}/api/chats/$chatId/messages',
      token,
      <String, dynamic>{
        'content': text,
        'message_type': 'text',
        'local_id': const Uuid().v4(),
      },
    );
    if (ok) {
      // Sending a message marks the chat as read on the server as well.
      await _post('${AppConfig.baseUrl}/api/chats/$chatId/messages/read', token, null);
      await presenter.appendOwnReply(tapPayload: payload, text: text);
    } else {
      await presenter.appendOwnReply(tapPayload: payload, text: '⚠️ Не отправлено: $text');
    }
    return true;
  }

  // mark_read
  await _post('${AppConfig.baseUrl}/api/chats/$chatId/messages/read', token, null);
  await presenter.cancelChat(chatId);
  return true;
}

Future<String?> _authToken() async {
  try {
    final manager = AccountManager();
    if (manager.currentAccount == null) {
      await manager.init();
    }
    final token = manager.currentAccount?.token;
    return (token == null || token.isEmpty) ? null : token;
  } catch (e) {
    debugPrint('NotificationActions: token load failed: $e');
    return null;
  }
}

Future<bool> _post(String url, String token, Map<String, dynamic>? body) async {
  try {
    final response = await http
        .post(
          Uri.parse(url),
          headers: <String, String>{
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $token',
          },
          body: body != null ? jsonEncode(body) : null,
        )
        .timeout(const Duration(seconds: 15));
    return response.statusCode >= 200 && response.statusCode < 300;
  } catch (e) {
    debugPrint('NotificationActions: POST $url failed: $e');
    return false;
  }
}
