import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform, File;
import 'package:flutter/material.dart' show Color, Widget;
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:window_manager/window_manager.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:dio/dio.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import 'account_manager.dart';
import 'auth_service.dart';
import 'websocket_service.dart';
import 'desktop_tray_service.dart';
import 'notification_settings_provider.dart';
import 'notification_service_hms.dart';
import 'push_service_detector.dart';
import 'settings_service.dart';
import 'deep_link_service.dart';
import '../config/app_config.dart';
import '../utils/image_utils.dart';
import '../screens/chat/private_chat_screen.dart';
import '../screens/chat/group_chat_screen.dart';
import '../screens/chat/channel_screen.dart';
import '../utils/swipe_back_route.dart';
import '../widgets/notifications/in_app_notification_banner.dart';

export '../widgets/notifications/in_app_notification_banner.dart' show InAppNotificationData;

/// Скачивает или достает из временного кэша изображение для отображения в уведомлениях
Future<String?> downloadOrGetCachedImage(String? url, {String prefix = 'notif_img'}) async {
  if (url == null || url.isEmpty) return null;
  try {
    // 1. Data URLs (Base64 avatar string from backend/database)
    if (url.startsWith('data:')) {
      final commaIndex = url.indexOf(',');
      if (commaIndex != -1) {
        final base64Str = url.substring(commaIndex + 1);
        final bytes = base64Decode(base64Str);
        final tempDir = await getTemporaryDirectory();
        final hash = url.hashCode.abs().toString();
        final cachedFile = File('${tempDir.path}/${prefix}_$hash.png');
        await cachedFile.writeAsBytes(bytes, flush: true);
        return cachedFile.path;
      }
      return null;
    }

    // 2. Local file paths or file:// URIs
    if (url.startsWith('file://')) {
      final f = File(Uri.parse(url).toFilePath());
      if (await f.exists()) return f.path;
    }
    final directFile = File(url);
    if (await directFile.exists()) return directFile.path;

    // 3. Resolve URL with getValidAvatarUrl (handles / relative paths and domain fixes)
    final validUrl = getValidAvatarUrl(url);
    if (validUrl == null) return null;

    if (!validUrl.startsWith('http://') && !validUrl.startsWith('https://')) {
      final f = File(validUrl);
      if (await f.exists()) return f.path;
      return null;
    }

    // 4. Try DefaultCacheManager first (instant local disk hit if CachedNetworkImage loaded it)
    try {
      final fileInfo = await DefaultCacheManager().getFileFromCache(validUrl);
      if (fileInfo != null && await fileInfo.file.exists() && (await fileInfo.file.length()) > 0) {
        return fileInfo.file.path;
      }
    } catch (_) {}

    // 5. Try temporary directory cache
    final tempDir = await getTemporaryDirectory();
    final hash = validUrl.hashCode.abs().toString();
    final cachedFile = File('${tempDir.path}/${prefix}_$hash.png');

    if (await cachedFile.exists() && (await cachedFile.length()) > 0) {
      return cachedFile.path;
    }

    // 6. Download via Dio
    final response = await Dio().get<List<int>>(
      validUrl,
      options: Options(
        responseType: ResponseType.bytes,
        sendTimeout: const Duration(milliseconds: 4000),
        receiveTimeout: const Duration(milliseconds: 4000),
      ),
    );
    if (response.statusCode == 200 && response.data != null && response.data!.isNotEmpty) {
      await cachedFile.writeAsBytes(response.data!, flush: true);
      return cachedFile.path;
    }
  } catch (e) {
    debugPrint('NotificationService: image download warning: $e');
  }
  return null;
}

/// Скачивает или достает из временного кэша аватарку для отображения в уведомлениях
Future<String?> downloadOrGetCachedAvatar(String? url) =>
    downloadOrGetCachedImage(url, prefix: 'notif_avatar');

/// Фоновый обработчик FCM сообщений (должен быть top-level функцией)
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // Если сообщение содержит notification-payload, Google Play Services уже показал его в шторке
  if (message.notification != null) {
    debugPrint('NotificationService: background notification already displayed by system tray');
    return;
  }

  await Firebase.initializeApp();
  final localNotifications = FlutterLocalNotificationsPlugin();
  const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');
  const iosSettings = DarwinInitializationSettings();
  await localNotifications.initialize(
    const InitializationSettings(android: androidSettings, iOS: iosSettings),
  );
  if (Platform.isAndroid) {
    final androidPlugin = localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      'private_chats',
      'Личные чаты',
      description: 'Уведомления о новых сообщениях в личных чатах',
      importance: Importance.high,
    ));
    await androidPlugin?.createNotificationChannel(const AndroidNotificationChannel(
      'group_chats',
      'Групповые чаты',
      description: 'Уведомления о новых сообщениях в группах',
      importance: Importance.high,
    ));
  }
  final data = message.data;
  if (data.containsKey('chat_id') && data.containsKey('chat_name')) {
    await _showBackgroundNotification(localNotifications, data);
  }
}

const _firebaseMessagingBackgroundHandler = firebaseMessagingBackgroundHandler;

Future<void> _showBackgroundNotification(
  FlutterLocalNotificationsPlugin localNotifications,
  Map<String, dynamic> data,
) async {
  final chatId = data['chat_id']?.toString() ?? '';
  final chatName = data['chat_name']?.toString() ?? 'Theaver';
  final senderName = data['sender_name']?.toString() ?? '';
  final messageId = data['id']?.toString() ?? data['message_id']?.toString();
  final messageText = (data['message_text']?.toString().isNotEmpty == true)
      ? data['message_text']!.toString()
      : (data['content']?.toString() ?? 'Новое сообщение');
  final isGroup = data['is_group'] == 'true' || data['is_group'] == true;
  final body = (senderName.isNotEmpty && isGroup)
      ? '$senderName: $messageText'
      : messageText;
  final channelId = isGroup ? 'group_chats' : 'private_chats';
  final channelLabel = isGroup ? 'Групповые чаты' : 'Личные чаты';

  final avatarUrl = data['avatar_url']?.toString() ?? data['avatar']?.toString();
  FilePathAndroidBitmap? largeIconBitmap;
  if (avatarUrl != null && avatarUrl.isNotEmpty) {
    final cachedPath = await downloadOrGetCachedAvatar(avatarUrl);
    if (cachedPath != null) {
      largeIconBitmap = FilePathAndroidBitmap(cachedPath);
    }
  }

  final mediaUrl = data['media_url']?.toString() ?? data['image']?.toString() ?? data['file_url']?.toString();
  FilePathAndroidBitmap? bigPictureBitmap;
  String? cachedMediaPath;
  if (mediaUrl != null && mediaUrl.isNotEmpty) {
    cachedMediaPath = await downloadOrGetCachedImage(mediaUrl, prefix: 'notif_media');
    if (cachedMediaPath != null) {
      bigPictureBitmap = FilePathAndroidBitmap(cachedMediaPath);
    }
  }

  final StyleInformation styleInformation = bigPictureBitmap != null
      ? BigPictureStyleInformation(
          bigPictureBitmap,
          largeIcon: largeIconBitmap,
          contentTitle: chatName,
          summaryText: body,
          hideExpandedLargeIcon: false,
        )
      : BigTextStyleInformation(
          body,
          contentTitle: chatName,
        );

  final androidDetails = AndroidNotificationDetails(
    channelId,
    channelLabel,
    channelDescription: isGroup
        ? 'Уведомления о новых сообщениях в группах'
        : 'Уведомления о новых сообщениях в личных чатах',
    importance: Importance.high,
    priority: Priority.high,
    icon: '@drawable/ic_notification',
    color: const Color(0xFF5B7FFF),
    largeIcon: largeIconBitmap,
    groupKey: 'com.theaver.messenger.MESSAGES',
    autoCancel: true,
    onlyAlertOnce: false,
    styleInformation: styleInformation,
  );
  final iosDetails = DarwinNotificationDetails(
    attachments: cachedMediaPath != null
        ? [DarwinNotificationAttachment(cachedMediaPath)]
        : null,
  );
  final details = NotificationDetails(android: androidDetails, iOS: iosDetails);
  final rawNotifId = (messageId != null && messageId.isNotEmpty)
      ? (int.tryParse(messageId) ?? (chatId.hashCode ^ messageId.hashCode))
      : (DateTime.now().millisecondsSinceEpoch.remainder(100000) ^ chatId.hashCode);
  final notifId = rawNotifId.abs() % 2147483647;

  // Persist notification ID for cancellation on read
  if (chatId.isNotEmpty) {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'chat_notif_ids_$chatId';
      final existing = prefs.getStringList(key) ?? [];
      if (!existing.contains('$notifId')) {
        existing.add('$notifId');
        await prefs.setStringList(key, existing);
      }
    } catch (_) {}
  }

  final payloadData = jsonEncode({
    'chat_id': chatId,
    'chat_name': chatName,
    'sender_name': senderName,
    'is_group': isGroup,
    'avatar_url': avatarUrl,
    'media_url': mediaUrl,
    'id': messageId,
    'type': 'new_message',
  });

  await localNotifications.show(
    notifId,
    chatName,
    body,
    details,
    payload: payloadData,
  );
}

/// Центральный сервис управления уведомлениями.
///
/// Поддерживает дуальный push: FCM (Google) + HMS Push Kit (Huawei).
/// Автоматически определяет доступный сервис через PushServiceDetector.
class NotificationService {
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  FirebaseMessaging? _firebaseMessaging;
  final FlutterLocalNotificationsPlugin _localNotifications =
      FlutterLocalNotificationsPlugin();
  HMSPushService? _hmsPushService;
  final PushServiceDetector _detector = PushServiceDetector();

  NotificationSettingsProvider? _settingsProvider;
  String? _pushToken;
  bool _initialized = false;

  InAppNotificationData? _currentBanner;
  final StreamController<InAppNotificationData?> _bannerController =
      StreamController<InAppNotificationData?>.broadcast();

  Stream<InAppNotificationData?> get bannerStream => _bannerController.stream;
  InAppNotificationData? get currentBanner => _currentBanner;
  int _unreadCount = 0;
  int get unreadCount => _unreadCount;
  String? get pushToken => _pushToken;
  bool get isInitialized => _initialized;
  PushServiceType get pushServiceType => _detector.serviceType;

  /// Флаг готовности MainScreen для безопасной навигации при тапе на уведомление
  bool isMainScreenReady = false;

  /// ID чата, открытого прямо сейчас на экране пользователя (для подавления уведомлений)
  String? currentActiveChatId;
  String? _lastActiveChatId;
  final Map<String, List<int>> _chatNotificationIds = {};
  final Map<String, List<LocalNotification>> _desktopNotifications = {};

  Map<String, dynamic>? _pendingNotificationData;
  Map<String, dynamic>? get pendingNotificationData => _pendingNotificationData;
  bool get hasPendingNotification => _pendingNotificationData != null;

  void consumePendingNotification() {
    if (_pendingNotificationData != null) {
      final data = _pendingNotificationData!;
      _pendingNotificationData = null;
      _navigateFromNotificationData(data);
    }
  }

  /// Устанавливает текущий открытый чат на этом устройстве,
  /// синхронизирует его с бэкендом через WebSocket для подавления push-уведомлений,
  /// и удаляет уже висящие уведомления для этого чата из шторки.
  void setActiveChat(String? chatId) {
    currentActiveChatId = (chatId != null && chatId.isNotEmpty) ? chatId : null;
    _lastActiveChatId = null;

    if (currentActiveChatId != null) {
      cancelChatNotifications(currentActiveChatId!);
    }
    WebSocketService().sendActiveChat(currentActiveChatId);
  }

  bool _isAppInForeground = true;
  bool get isAppInForeground => _isAppInForeground;

  /// Вызывается при сворачивании приложения в фон:
  /// пользователь больше не смотрит в экран чата, поэтому сервер должен слать push-уведомления.
  void onAppPause() {
    _isAppInForeground = false;
    _lastActiveChatId = currentActiveChatId;
    currentActiveChatId = null;
    WebSocketService().sendActiveChat(null);
  }

  /// Вызывается при возврате приложения на передний план:
  /// если пользователь оставался на экране чата, восстанавливаем активный статус и очищаем уведомления.
  void onAppResume() {
    _isAppInForeground = true;
    if (_lastActiveChatId != null) {
      currentActiveChatId = _lastActiveChatId;
      _lastActiveChatId = null;
      WebSocketService().sendActiveChat(currentActiveChatId);
      if (currentActiveChatId != null) {
        cancelChatNotifications(currentActiveChatId!);
      }
    }
  }

  /// Кэш недавно показанных уведомлений для защиты от дублирования (гонка WebSocket и Push)
  final Map<String, DateTime> _recentlyShownNotifications = {};

  bool _isDuplicateNotification(String chatId, String messageText, {String? messageId}) {
    final now = DateTime.now();
    _recentlyShownNotifications.removeWhere((_, time) => now.difference(time).inSeconds > 10);
    final key = (messageId != null && messageId.isNotEmpty)
        ? '$chatId:$messageId'
        : '$chatId:$messageText';
    if (_recentlyShownNotifications.containsKey(key)) {
      return true;
    }
    _recentlyShownNotifications[key] = now;
    return false;
  }

  StreamSubscription? _wsSubscription;

  /// Полная инициализация: детектирование + Firebase/HMS + Local Notifications + Desktop
  Future<void> init(NotificationSettingsProvider settingsProvider) async {
    if (_initialized) return;
    _settingsProvider = settingsProvider;

    try {
      // 1. Детектирование push-сервиса
      await _detector.detect();
      debugPrint('NotificationService: detected push service = ${_detector.serviceType}');

      // 2. Инициализация для конкретной платформы
      if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
        await _initDesktopNotifications();
      } else {
        // Локальные уведомления на Android / iOS
        await _initLocalNotifications();
        await _createNotificationChannels();

        // Инициализация push-сервиса в зависимости от детекта
        switch (_detector.serviceType) {
          case PushServiceType.gms:
            await _initFCM();
            break;
          case PushServiceType.hms:
            await _initHMS();
            break;
          case PushServiceType.none:
            debugPrint('NotificationService: no push service, local notifications only');
            break;
        }
      }

      // 3. Подписка на входящие WebSocket сообщения
      _subscribeWebSocketMessages();

      _initialized = true;
      debugPrint('NotificationService: fully initialized (${_detector.serviceType})');
    } catch (e) {
      debugPrint('NotificationService: initialization error: $e');
      _initialized = true;
    }
  }

  Future<void> _initDesktopNotifications() async {
    try {
      await DesktopTrayService().init();
      await localNotifier.setup(
        appName: 'Theaver',
        shortcutPolicy: ShortcutPolicy.requireCreate,
      );
      debugPrint('NotificationService: desktop local_notifier initialized');
    } catch (e) {
      debugPrint('NotificationService: desktop notification init error: $e');
    }
  }

  void _subscribeWebSocketMessages() {
    _wsSubscription?.cancel();
    _wsSubscription = WebSocketService().eventStream.listen((event) async {
      if (event.type == WebSocketEventType.messageRead) {
        final cid = event.data['chat_id']?.toString();
        if (cid != null && cid.isNotEmpty) {
          cancelChatNotifications(cid);
        }
        return;
      } else if (event.type == WebSocketEventType.unreadCountUpdated) {
        final cid = event.data['chat_id']?.toString();
        final count = event.data['unread_count'] as int?;
        if (cid != null && cid.isNotEmpty && count == 0) {
          cancelChatNotifications(cid);
        }
        return;
      }

      if (event.type == WebSocketEventType.newMessage) {
        final data = event.data;
        final msg = (data['message'] is Map)
            ? Map<String, dynamic>.from(data['message'] as Map)
            : <String, dynamic>{};

        final chatId = data['chat_id']?.toString() ?? msg['chat_id']?.toString() ?? '';
        final senderId = msg['sender_id']?.toString() ?? data['sender_id']?.toString() ?? '';
        final currentUserId = await AuthService.getUserId();
        if (senderId.isNotEmpty && currentUserId != null && senderId == currentUserId) {
          return;
        }

        if (chatId.isEmpty) return;
        if (!shouldShowNotification(chatId)) return;

        final senderName = msg['sender_name']?.toString() ?? data['sender_name']?.toString() ?? '';
        final chatName = (data['chat_name']?.toString().isNotEmpty == true)
            ? data['chat_name']!.toString()
            : (senderName.isNotEmpty ? senderName : 'Theaver');

        String messageText = msg['content']?.toString() ?? data['message_text']?.toString() ?? data['content']?.toString() ?? '';
        if (messageText.isEmpty) {
          final msgType = msg['message_type']?.toString() ?? '';
          switch (msgType) {
            case 'voice':
              messageText = '🎤 Голосовое сообщение';
              break;
            case 'video_note':
              messageText = '📹 Видеосообщение';
              break;
            case 'image':
              messageText = '📷 Фотография';
              break;
            case 'video':
              messageText = '🎥 Видео';
              break;
            case 'file':
              messageText = '📎 Файл';
              break;
            default:
              messageText = 'Новое сообщение';
          }
        }
        final isGroup = data['is_group'] == true || data['is_group'] == 'true' || msg['is_group'] == true;
        final messageId = msg['id']?.toString() ?? data['id']?.toString() ?? data['message_id']?.toString();
        final avatarUrl = data['avatar_url']?.toString() ?? msg['sender_avatar_url']?.toString();
        String? mediaUrl = msg['media_url']?.toString() ?? msg['file_url']?.toString() ?? data['media_url']?.toString() ?? data['file_url']?.toString();
        if (mediaUrl == null || mediaUrl.isEmpty) {
          final mediaPayload = msg['media_payload'] ?? data['media_payload'];
          if (mediaPayload is Map) {
            mediaUrl = mediaPayload['thumb_url']?.toString() ?? mediaPayload['thumbnail_url']?.toString() ?? mediaPayload['photo']?.toString();
          }
        }

        if (_isDuplicateNotification(chatId, messageText, messageId: messageId)) return;

        if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
          bool isFocused = false;
          try {
            isFocused = await windowManager.isFocused();
          } catch (_) {}

          final isCurrentChatActive = currentActiveChatId != null && currentActiveChatId == chatId;
          // Показываем системный тост, если окно не в фокусе, свернуто или открыт другой чат
          if (!isFocused || !isCurrentChatActive) {
            await showMessageNotification(
              chatId: chatId,
              chatName: chatName,
              senderName: senderName,
              messageText: messageText,
              avatarUrl: avatarUrl,
              mediaUrl: mediaUrl,
              isGroup: isGroup,
              messageId: messageId,
            );
          }
          if (isFocused) {
            showInAppBanner(
              chatId: chatId,
              chatName: chatName,
              senderName: senderName,
              messageText: messageText,
              avatarUrl: avatarUrl,
              isGroup: isGroup,
            );
          }
        } else {
          // Мобильные платформы (Android / iOS):
          showInAppBanner(
            chatId: chatId,
            chatName: chatName,
            senderName: senderName,
            messageText: messageText,
            avatarUrl: avatarUrl,
            isGroup: isGroup,
          );
          // В фоне показываем локальное уведомление ТОЛЬКО если push-сервисы не активны (например, нет Google/Huawei)
          if (!_isAppInForeground && (_pushToken == null || _pushToken!.isEmpty)) {
            await showMessageNotification(
              chatId: chatId,
              chatName: chatName,
              senderName: senderName,
              messageText: messageText,
              avatarUrl: avatarUrl,
              mediaUrl: mediaUrl,
              isGroup: isGroup,
              messageId: messageId,
            );
          }
        }
      }
    });
  }

  // ============ FCM Initialization ============

  Future<void> _initFCM() async {
    _firebaseMessaging = FirebaseMessaging.instance;

    // Запрос разрешений
    final settings = await _firebaseMessaging!.requestPermission(
      alert: true, badge: true, sound: true,
    );
    debugPrint('NotificationService: FCM permission = ${settings.authorizationStatus}');

    // Получение токена
    _pushToken = await _firebaseMessaging!.getToken();
    debugPrint('NotificationService: FCM token=${_pushToken?.substring(0, 20)}...');

    if (_pushToken != null) {
      await _registerPushTokenOnServer(_pushToken!, 'fcm');
    }

    // Слушатель обновления токена
    _firebaseMessaging!.onTokenRefresh.listen((token) {
      _pushToken = token;
      _registerPushTokenOnServer(token, 'fcm');
    });

    // Обработчики
    FirebaseMessaging.onMessage.listen(_onForegroundMessage);
    FirebaseMessaging.onMessageOpenedApp.listen(_onMessageOpenedApp);
    _checkInitialMessage();
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
  }

  // ============ HMS Push Initialization ============

  Future<void> _initHMS() async {
    _hmsPushService = HMSPushService();

    // Запрос разрешений
    await _hmsPushService!.requestPermission();

    // Получение токена
    _pushToken = await _hmsPushService!.getToken();
    final logToken = _pushToken != null
        ? (_pushToken!.length > 20 ? '${_pushToken!.substring(0, 20)}...' : _pushToken!)
        : 'null';
    debugPrint('NotificationService: HMS push token=$logToken');

    if (_pushToken != null && _pushToken!.isNotEmpty) {
      await _registerPushTokenOnServer(_pushToken!, 'hms');
    }

    // Слушатель обновления токена
    _hmsPushService!.onTokenRefresh.listen((token) {
      _pushToken = token;
      _registerPushTokenOnServer(token, 'hms');
    });

    // Обработчики
    _hmsPushService!.onMessageReceived.listen(_onHMSForegroundMessage);
    _hmsPushService!.onMessageOpenedApp.listen(_onHMSMessageOpenedApp);

    // Проверяем начальное уведомление при холодном старте
    await _checkHMSInitialMessage();
  }

  Future<void> _checkHMSInitialMessage() async {
    try {
      final initialData = await _hmsPushService?.getInitialNotification();
      if (initialData != null && initialData.isNotEmpty) {
        debugPrint('NotificationService: HMS initial notification detected: $initialData');
        _pendingNotificationData = initialData;
        _navigateFromNotificationData(initialData);
      }
    } catch (e) {
      debugPrint('NotificationService: _checkHMSInitialMessage error: $e');
    }
  }

  // ============ Local Notifications ============

  Future<void> _initLocalNotifications() async {
    const androidSettings = AndroidInitializationSettings('@drawable/ic_notification');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _localNotifications.initialize(
      const InitializationSettings(android: androidSettings, iOS: iosSettings),
      onDidReceiveNotificationResponse: _onLocalNotificationTap,
    );

    if (Platform.isAndroid) {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
    }

    try {
      final launchDetails = await _localNotifications.getNotificationAppLaunchDetails();
      if (launchDetails?.didNotificationLaunchApp == true) {
        final payload = launchDetails?.notificationResponse?.payload;
        if (payload != null && payload.isNotEmpty && !payload.startsWith('call_')) {
          try {
            final decoded = jsonDecode(payload);
            if (decoded is Map<String, dynamic>) {
              _pendingNotificationData = decoded;
            } else {
              _pendingNotificationData = {'chat_id': payload, 'type': 'new_message'};
            }
          } catch (_) {
            _pendingNotificationData = {'chat_id': payload, 'type': 'new_message'};
          }
        }
      }
    } catch (e) {
      debugPrint('NotificationService: launchDetails error: $e');
    }
  }

  Future<void> _createNotificationChannels() async {
    if (!Platform.isAndroid) return;
    final androidPlugin = _localNotifications
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    if (androidPlugin == null) return;

    await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
      'private_chats', 'Личные чаты',
      description: 'Уведомления о новых сообщениях в личных чатах',
      importance: Importance.high,
    ));
    await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
      'group_chats', 'Групповые чаты',
      description: 'Уведомления о новых сообщениях в группах',
      importance: Importance.high,
    ));
    await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
      'channels', 'Каналы',
      description: 'Уведомления о новых постах в каналах',
      importance: Importance.defaultImportance,
    ));
    await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
      'calls', 'Звонки',
      description: 'Уведомления о входящих звонках',
      importance: Importance.max,
    ));
    await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
      'mentions', 'Упоминания',
      description: 'Уведомления об @упоминаниях',
      importance: Importance.high,
    ));
    await androidPlugin.createNotificationChannel(const AndroidNotificationChannel(
      'silent', 'Беззвучные',
      description: 'Тихие уведомления — только бейдж',
      importance: Importance.low,
    ));
  }

  // ============ Token Registration ============

  Future<void> _registerPushTokenOnServer(String token, String type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = AccountManager().currentDeviceId ??
          prefs.getString('current_device_id') ??
          prefs.getString('device_id') ??
          'unknown';
      final authToken = await AuthService.getToken();

      final payload = {
        'token': token,
        'push_token': token,
        'fcm_token': token,
        'service_type': type,
        'type': type,
        'device_id': deviceId,
      };

      final options = Options(
        headers: {
          if (authToken != null) 'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
      );

      try {
        await Dio().put(
          '${AppConfig.baseUrl}/api/sessions/push-token',
          data: payload,
          options: options,
        );
      } catch (_) {
        await Dio().post(
          '${AppConfig.baseUrl}/api/notifications/push-token',
          data: payload,
          options: options,
        );
      }
      debugPrint('NotificationService: $type push token registered on server');
    } catch (e) {
      debugPrint('NotificationService: failed to register $type token: $e');
    }
  }

  Future<void> registerCurrentToken() async {
    if (_pushToken != null && _pushToken!.isNotEmpty) {
      final type = _detector.serviceType == PushServiceType.hms ? 'hms' : 'fcm';
      await _registerPushTokenOnServer(_pushToken!, type);
    }
  }

  Future<void> unregisterPushToken() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = AccountManager().currentDeviceId ??
          prefs.getString('current_device_id') ??
          prefs.getString('device_id') ??
          'unknown';
      final authToken = await AuthService.getToken();

      final options = Options(
        headers: {
          if (authToken != null) 'Authorization': 'Bearer $authToken',
          'Content-Type': 'application/json',
        },
      );

      try {
        await Dio().delete(
          '${AppConfig.baseUrl}/api/sessions/push-token',
          data: {'device_id': deviceId},
          options: options,
        );
      } catch (_) {
        await Dio().delete(
          '${AppConfig.baseUrl}/api/notifications/push-token',
          data: {'device_id': deviceId},
          options: options,
        );
      }
      debugPrint('NotificationService: push token unregistered');
    } catch (e) {
      debugPrint('NotificationService: failed to unregister token: $e');
    }
  }

  // ============ FCM Handlers ============

  void _onForegroundMessage(RemoteMessage message) {
    final data = message.data;
    debugPrint('NotificationService: FCM foreground: $data');
    _handlePushData(data);
  }

  void _onMessageOpenedApp(RemoteMessage message) {
    _navigateFromNotificationData(message.data);
  }

  Future<void> _checkInitialMessage() async {
    final initialMessage = await _firebaseMessaging?.getInitialMessage();
    if (initialMessage != null) {
      _pendingNotificationData = initialMessage.data;
      _navigateFromNotificationData(initialMessage.data);
    }
  }

  // ============ HMS Handlers ============

  void _onHMSForegroundMessage(Map<String, dynamic> data) {
    debugPrint('NotificationService: HMS foreground: $data');
    _handlePushData(data);
  }

  void _onHMSMessageOpenedApp(Map<String, dynamic> data) {
    _navigateFromNotificationData(data);
  }

  // ============ Common Push Data Handler ============

  void _handlePushData(Map<String, dynamic> data) {
    final type = data['type'] ?? '';
    switch (type) {
      case 'sync_required':
        if (data.containsKey('chat_id') && data.containsKey('chat_name')) {
          showInAppBanner(
            chatId: data['chat_id']!,
            chatName: data['chat_name']!,
            senderName: data['sender_name'] ?? '',
            messageText: data['message_text'] ?? '',
            isGroup: data['is_group'] == 'true',
          );
        }
        break;
      case 'new_message':
        if (data.containsKey('chat_id')) {
          final chatId = data['chat_id']!.toString();
          final senderName = data['sender_name']?.toString() ?? '';
          final chatName = (data['chat_name']?.toString().isNotEmpty == true)
              ? data['chat_name']!.toString()
              : (senderName.isNotEmpty ? senderName : 'Theaver');
          final messageText = (data['message_text']?.toString().isNotEmpty == true)
              ? data['message_text']!.toString()
              : (data['content']?.toString() ?? 'Новое сообщение');
          final isGroup = data['is_group'] == 'true' || data['is_group'] == true;
          final messageId = data['id']?.toString() ?? data['message_id']?.toString();

          if (shouldShowNotification(chatId) && !_isDuplicateNotification(chatId, messageText, messageId: messageId)) {
            if (_isAppInForeground) {
              showInAppBanner(
                chatId: chatId,
                chatName: chatName,
                senderName: senderName,
                messageText: messageText,
                isGroup: isGroup,
              );
            }
          }
        }
        break;
      case 'read_status_updated':
        final cid = data['chat_id']?.toString();
        debugPrint('NotificationService: read status updated for chat $cid');
        if (cid != null && cid.isNotEmpty) {
          cancelChatNotifications(cid);
        }
        break;
      case 'incoming_call':
        _handleIncomingCall(data);
        break;
    }
  }

  void _handleIncomingCall(Map<String, dynamic> data) {
    showCallNotification(
      callId: data['call_id'] ?? '',
      callerName: data['caller_name'] ?? '',
      isVideo: data['is_video'] == 'true',
    );
  }

  Future<void> _navigateFromNotificationData(Map<String, dynamic> rawData) async {
    final Map<String, dynamic> data = Map<String, dynamic>.from(rawData);

    // Defensive unpacking if chat_id is missing at top level
    if (!data.containsKey('chat_id') || data['chat_id'] == null) {
      if (data['remoteMessage'] is Map) {
        final rm = Map<String, dynamic>.from(data['remoteMessage']);
        if (rm['dataOfMap'] != null) {
          if (rm['dataOfMap'] is Map) {
            data.addAll(Map<String, dynamic>.from(rm['dataOfMap']));
          } else if (rm['dataOfMap'] is String && (rm['dataOfMap'] as String).isNotEmpty) {
            try {
              final decoded = json.decode(rm['dataOfMap'] as String);
              if (decoded is Map) data.addAll(Map<String, dynamic>.from(decoded));
            } catch (_) {}
          }
        }
        if (rm['data'] != null) {
          if (rm['data'] is Map) {
            data.addAll(Map<String, dynamic>.from(rm['data']));
          } else if (rm['data'] is String && (rm['data'] as String).isNotEmpty) {
            try {
              final decoded = json.decode(rm['data'] as String);
              if (decoded is Map) data.addAll(Map<String, dynamic>.from(decoded));
            } catch (_) {}
          }
        }
      }
      if (data['extras'] is Map) {
        final extras = Map<String, dynamic>.from(data['extras']);
        if (extras.containsKey('chat_id')) {
          data.addAll(extras);
        } else if (extras['data'] != null) {
          if (extras['data'] is Map) {
            data.addAll(Map<String, dynamic>.from(extras['data']));
          } else if (extras['data'] is String && (extras['data'] as String).isNotEmpty) {
            try {
              final decoded = json.decode(extras['data'] as String);
              if (decoded is Map) data.addAll(Map<String, dynamic>.from(decoded));
            } catch (_) {}
          }
        }
      }
      if (data['data'] is String && (data['data'] as String).isNotEmpty) {
        try {
          final decoded = json.decode(data['data'] as String);
          if (decoded is Map) data.addAll(Map<String, dynamic>.from(decoded));
        } catch (_) {}
      }
    }

    final chatId = data['chat_id']?.toString();
    if (chatId == null || chatId.isEmpty) {
      return;
    }
    debugPrint('NotificationService: navigating to chat $chatId');

    // On Desktop, bring window to front
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        await DesktopTrayService().showAndFocusWindow();
      } catch (e) {
        debugPrint('NotificationService: showAndFocusWindow error: $e');
      }
    }

    // Dismiss in-app banner if showing
    dismissBanner();

    // If MainScreen is not ready yet (e.g. cold start splash or auth loading),
    // save to _pendingNotificationData so MainScreen can consume it when mounted.
    if (!isMainScreenReady) {
      debugPrint('NotificationService: MainScreen not ready yet, queuing pending navigation for chat $chatId');
      _pendingNotificationData = data;
      return;
    }

    // Check if user is logged in
    var token = await AuthService.getToken();
    if (token == null) {
      for (var i = 0; i < 5; i++) {
        await Future.delayed(const Duration(milliseconds: 150));
        token = await AuthService.getToken();
        if (token != null) break;
      }
    }
    if (token == null) {
      debugPrint('NotificationService: user not logged in, ignoring navigation');
      return;
    }

    final navState = DeepLinkService().navigatorKey.currentState;
    if (navState == null) {
      debugPrint('NotificationService: navigatorState is null, queueing pending navigation');
      _pendingNotificationData = data;
      Future.delayed(const Duration(milliseconds: 300), () {
        if (_pendingNotificationData != null && isMainScreenReady) {
          consumePendingNotification();
        }
      });
      return;
    }

    // Dismiss active notifications for this chat immediately upon navigation
    cancelChatNotifications(chatId);

    // If already in this chat, don't push again
    if (currentActiveChatId == chatId) {
      debugPrint('NotificationService: chat $chatId is already active');
      return;
    }

    // Pop any open sub-screens (like other chats or profiles) back to MainScreen
    try {
      navState.popUntil((route) => route.isFirst);
    } catch (_) {}

    final chatName = data['chat_name']?.toString() ?? data['sender_name']?.toString() ?? '';
    final avatarUrl = data['avatar_url']?.toString() ?? data['avatar']?.toString();
    final messageId = data['id']?.toString() ?? data['message_id']?.toString();
    final isGroup = data['is_group'] == true || data['is_group'] == 'true';
    final isChannel = data['is_channel'] == true || data['is_channel'] == 'true' || data['chat_type'] == 'channel';

    Widget screen;
    if (isChannel) {
      screen = ChannelScreen(
        channelId: chatId,
        channelName: chatName.isNotEmpty ? chatName : null,
        channelAvatar: avatarUrl,
        highlightMessageId: messageId,
      );
    } else if (isGroup) {
      screen = GroupChatScreen(
        chatId: chatId,
        groupName: chatName.isNotEmpty ? chatName : null,
        groupAvatar: avatarUrl,
        initialMessageId: messageId,
      );
    } else {
      screen = PrivateChatScreen(
        chatId: chatId,
        otherUserName: chatName.isNotEmpty ? chatName : null,
        otherUserAvatar: avatarUrl,
        initialMessageId: messageId,
      );
    }

    navState.push(
      SwipeBackPageRoute(builder: (_) => screen),
    );
  }

  // ============ Local Notifications ============

  Future<void> showMessageNotification({
    required String chatId,
    required String chatName,
    required String senderName,
    required String messageText,
    String? avatarPath,
    String? avatarUrl,
    String? mediaUrl,
    bool isGroup = false,
    String? messageId,
  }) async {
    if (!shouldShowNotification(chatId)) return;

    final effective = _settingsProvider?.getEffectiveSettings(chatId);
    final showPreview = effective?.previewEnabled ?? true;
    final displayChatName = chatName.isNotEmpty ? chatName : (senderName.isNotEmpty ? senderName : 'Theaver');
    final displayText = messageText.isNotEmpty ? messageText : 'Новое сообщение';
    final title = showPreview ? (isGroup ? '$displayChatName ($senderName)' : displayChatName) : 'Theaver';
    final body = showPreview
        ? (isGroup ? (senderName.isNotEmpty ? '$senderName: $displayText' : displayText) : displayText)
        : 'Новое сообщение';

    // Desktop (Windows, Linux, macOS)
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        final notification = LocalNotification(
          identifier: 'msg_${chatId}_${messageId ?? DateTime.now().millisecondsSinceEpoch}_${DateTime.now().microsecondsSinceEpoch}',
          title: title,
          body: body,
          silent: !(effective?.soundEnabled ?? true),
        );
        (_desktopNotifications[chatId] ??= []).add(notification);
        notification.onClose = (_) {
          _desktopNotifications[chatId]?.remove(notification);
        };
        notification.onClick = () async {
          _desktopNotifications[chatId]?.remove(notification);
          try {
            await notification.close();
          } catch (_) {}
          await DesktopTrayService().showAndFocusWindow();
          _navigateFromNotificationData({
            'chat_id': chatId,
            'chat_name': chatName,
            'sender_name': senderName,
            'is_group': isGroup,
            'avatar_url': avatarUrl,
            'media_url': mediaUrl,
            'id': messageId,
            'type': 'new_message',
          });
        };
        await notification.show();
      } catch (e) {
        debugPrint('NotificationService: desktop local_notifier show error: $e');
      }
      return;
    }

    // Android / iOS
    final effectiveAvatar = avatarUrl ?? avatarPath;
    FilePathAndroidBitmap? largeIconBitmap;
    if (effectiveAvatar != null && effectiveAvatar.isNotEmpty) {
      final cachedPath = await downloadOrGetCachedAvatar(effectiveAvatar);
      if (cachedPath != null) {
        largeIconBitmap = FilePathAndroidBitmap(cachedPath);
      }
    }

    FilePathAndroidBitmap? bigPictureBitmap;
    String? cachedMediaPath;
    if (mediaUrl != null && mediaUrl.isNotEmpty) {
      cachedMediaPath = await downloadOrGetCachedImage(mediaUrl, prefix: 'notif_media');
      if (cachedMediaPath != null) {
        bigPictureBitmap = FilePathAndroidBitmap(cachedMediaPath);
      }
    }

    final StyleInformation styleInformation = bigPictureBitmap != null
        ? BigPictureStyleInformation(
            bigPictureBitmap,
            largeIcon: largeIconBitmap,
            contentTitle: title,
            summaryText: isGroup ? chatName : null,
            hideExpandedLargeIcon: false,
          )
        : BigTextStyleInformation(
            body,
            contentTitle: title,
            summaryText: isGroup ? chatName : null,
          );

    final channelId = _getChannelId(chatId, isGroup, effective);
    final androidDetails = AndroidNotificationDetails(
      channelId, _channelLabel(channelId),
      channelDescription: _channelDescription(channelId),
      importance: _getImportance(effective),
      priority: _getPriority(effective),
      icon: '@drawable/ic_notification',
      color: const Color(0xFF5B7FFF),
      largeIcon: largeIconBitmap,
      enableVibration: effective?.vibration != VibrationPattern.none,
      vibrationPattern: _getVibrationPattern(effective?.vibration),
      playSound: effective?.soundEnabled ?? true,
      groupKey: 'com.theaver.messenger.MESSAGES',
      setAsGroupSummary: false,
      autoCancel: true,
      onlyAlertOnce: false,
      styleInformation: styleInformation,
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true, presentBadge: true, presentSound: true, presentBanner: true,
      attachments: cachedMediaPath != null
          ? [DarwinNotificationAttachment(cachedMediaPath)]
          : null,
    );

    final details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    final rawNotifId = (messageId != null && messageId.isNotEmpty)
        ? (int.tryParse(messageId) ?? (chatId.hashCode ^ messageId.hashCode))
        : (DateTime.now().millisecondsSinceEpoch.remainder(100000) ^ chatId.hashCode);
    final notifId = rawNotifId.abs() % 2147483647;
    (_chatNotificationIds[chatId] ??= []).add(notifId);

    // Persist notification ID for cancellation on read across isolates
    if (chatId.isNotEmpty) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final key = 'chat_notif_ids_$chatId';
        final existing = prefs.getStringList(key) ?? [];
        if (!existing.contains('$notifId')) {
          existing.add('$notifId');
          await prefs.setStringList(key, existing);
        }
      } catch (_) {}
    }

    final payloadData = jsonEncode({
      'chat_id': chatId,
      'chat_name': chatName,
      'sender_name': senderName,
      'is_group': isGroup,
      'avatar_url': avatarUrl,
      'media_url': mediaUrl,
      'id': messageId,
      'type': 'new_message',
    });

    await _localNotifications.show(notifId, title, body, details, payload: payloadData);
  }

  Future<void> showCallNotification({
    required String callId,
    required String callerName,
    bool isVideo = false,
  }) async {
    const androidDetails = AndroidNotificationDetails(
      'calls', 'Звонки',
      channelDescription: 'Уведомления о входящих звонках',
      importance: Importance.max, priority: Priority.max,
      autoCancel: false, ongoing: true,
      fullScreenIntent: true,
      category: AndroidNotificationCategory.call,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true, presentBadge: true, presentSound: true,
      interruptionLevel: InterruptionLevel.critical,
    );
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    await _localNotifications.show(
      callId.hashCode, isVideo ? 'Видеозвонок' : 'Звонок', callerName, details,
      payload: 'call_$callId',
    );
  }

  void updateUnreadCount(int count) {
    _unreadCount = count;
    if (Platform.isAndroid && count > 0) {
      _showBadgeSummary(count);
    } else if (Platform.isAndroid && count == 0) {
      _localNotifications.cancel(-1);
    }
  }

  Future<void> _showBadgeSummary(int count) async {
    const androidDetails = AndroidNotificationDetails(
      'silent', 'Беззвучные',
      channelDescription: 'Счётчик непрочитанных',
      importance: Importance.low, priority: Priority.low,
      playSound: false, enableVibration: false,
      setAsGroupSummary: true, groupKey: 'theaver_summary', autoCancel: false,
    );
    const details = NotificationDetails(android: androidDetails);
    await _localNotifications.show(-1, 'Theaver', '$count непрочитанных', details);
  }

  Future<void> cancelChatNotifications(String chatId) async {
    // 1. Desktop local_notifier
    final desktopNotifications = _desktopNotifications.remove(chatId);
    if (desktopNotifications != null) {
      for (final n in desktopNotifications) {
        try {
          await n.close();
        } catch (_) {}
      }
    }

    // 2. Mobile local_notifications from memory
    final ids = _chatNotificationIds.remove(chatId);
    if (ids != null) {
      for (final id in ids) {
        await _localNotifications.cancel(id);
      }
    }

    // 3. Stored notification IDs across isolates
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'chat_notif_ids_$chatId';
      final storedIds = prefs.getStringList(key);
      if (storedIds != null) {
        final parsedIds = <int>[];
        for (final idStr in storedIds) {
          final id = int.tryParse(idStr);
          if (id != null) {
            parsedIds.add(id);
            await _localNotifications.cancel(id);
          }
        }
        if (parsedIds.isNotEmpty && Platform.isAndroid) {
          try {
            await (_hmsPushService ?? HMSPushService()).cancelNotificationsWithIds(parsedIds);
          } catch (_) {}
        }
        await prefs.remove(key);
      }
    } catch (_) {}

    // 4. Cancel active notifications via Huawei Push SDK (for HMS Core notifications)
    if (Platform.isAndroid) {
      try {
        await (_hmsPushService ?? HMSPushService()).cancelChatNotifications(chatId);
      } catch (_) {}
    }

    // Cancel by chat Tag (used in FCM and HMS push notifications)
    try {
      await _localNotifications.cancel(0, tag: 'chat_$chatId');
    } catch (_) {}

    final parsed = int.tryParse(chatId);
    if (parsed != null) {
      await _localNotifications.cancel(parsed);
      try {
        await _localNotifications.cancel(parsed, tag: 'chat_$chatId');
      } catch (_) {}
    }
    await _localNotifications.cancel(chatId.hashCode);
    try {
      await _localNotifications.cancel(chatId.hashCode, tag: 'chat_$chatId');
    } catch (_) {}
  }

  Future<void> cancelAllNotifications() async {
    for (final list in _desktopNotifications.values) {
      for (final n in list) {
        try {
          await n.close();
        } catch (_) {}
      }
    }
    _desktopNotifications.clear();
    _chatNotificationIds.clear();
    await _localNotifications.cancelAll();
    if (Platform.isAndroid) {
      try {
        await (_hmsPushService ?? HMSPushService()).cancelAllNotifications();
      } catch (_) {}
    }
  }

  // ============ Logic ============

  bool shouldShowNotification(String chatId, {bool isMention = false}) {
    if (chatId.isNotEmpty && currentActiveChatId == chatId) {
      return false;
    }
    if (_settingsProvider == null) return true;
    return _settingsProvider!.shouldShowNotification(chatId, isMention: isMention);
  }

  void showInAppBanner({
    required String chatId,
    required String chatName,
    required String senderName,
    required String messageText,
    String? avatarUrl,
    bool isGroup = false,
  }) {
    if (!shouldShowNotification(chatId)) return;
    final data = InAppNotificationData(
      chatId: chatId,
      chatName: chatName,
      senderName: senderName,
      messageText: messageText,
      avatarUrl: avatarUrl,
      isGroup: isGroup,
      timestamp: DateTime.now(),
    );
    _currentBanner = data;
    _bannerController.add(data);

    final context = DeepLinkService().navigatorKey.currentContext;
    if (context != null && context.mounted) {
      InAppNotificationBanner.showTopBanner(
        context,
        data: data,
        onTap: () {
          _navigateFromNotificationData({
            'chat_id': chatId,
            'chat_name': chatName,
            'sender_name': senderName,
            'avatar_url': avatarUrl,
            'is_group': isGroup,
            'type': 'new_message',
          });
        },
      );
    }
  }

  void dismissBanner() {
    _currentBanner = null;
    _bannerController.add(null);
    InAppNotificationBanner.dismissTopBanner();
  }

  // ============ Local Notification Tap ============

  void _onLocalNotificationTap(NotificationResponse response) {
    final payload = response.payload;
    if (payload == null || payload.isEmpty) return;
    if (payload.startsWith('call_')) {
      debugPrint('NotificationService: call notification tapped');
    } else {
      Map<String, dynamic> data;
      try {
        final decoded = jsonDecode(payload);
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        } else {
          data = {'chat_id': payload, 'type': 'new_message'};
        }
      } catch (_) {
        data = {'chat_id': payload, 'type': 'new_message'};
      }
      _navigateFromNotificationData(data);
    }
  }

  // ============ Helpers ============

  String _getChannelId(String chatId, bool isGroup, EffectiveChatSettings? effective) {
    if (effective?.isMuted == true) return 'silent';
    if (effective?.mentionsOnly == true) return 'mentions';
    if (isGroup) return 'group_chats';
    return 'private_chats';
  }

  String _channelLabel(String id) => {
    'private_chats': 'Личные чаты', 'group_chats': 'Групповые чаты',
    'channels': 'Каналы', 'calls': 'Звонки', 'mentions': 'Упоминания',
    'silent': 'Беззвучные',
  }[id] ?? 'Уведомления';

  String _channelDescription(String id) => {
    'private_chats': 'Уведомления о новых сообщениях в личных чатах',
    'group_chats': 'Уведомления о новых сообщениях в группах',
    'channels': 'Уведомления о новых постах в каналах',
    'calls': 'Уведомления о входящих звонках',
    'mentions': 'Уведомления об @упоминаниях',
    'silent': 'Тихие уведомления — только бейдж',
  }[id] ?? 'Уведомления Theaver';

  Importance _getImportance(EffectiveChatSettings? e) =>
      e?.isMuted == true ? Importance.low : Importance.high;
  Priority _getPriority(EffectiveChatSettings? e) =>
      e?.isMuted == true ? Priority.low : Priority.high;

  Int64List? _getVibrationPattern(VibrationPattern? p) => switch (p) {
    VibrationPattern.none => null,
    VibrationPattern.short => Int64List.fromList([0, 100]),
    VibrationPattern.long => Int64List.fromList([0, 400]),
    VibrationPattern.doubleShort => Int64List.fromList([0, 100, 100, 100]),
    VibrationPattern.tripleShort => Int64List.fromList([0, 100, 100, 100, 100, 100]),
    _ => null,
  };

  /// Отправляет тестовое уведомление:
  /// 1. Немедленно показывает локальное уведомление в системной шторке
  /// 2. Отображает in-app баннер в приложении
  /// 3. Вызывает серверный эндпоинт POST /api/notifications/test для проверки реального push-канала
  Future<Map<String, dynamic>> sendTestNotification() async {
    // 1. Показываем локальное уведомление в системе
    if (Platform.isWindows || Platform.isLinux || Platform.isMacOS) {
      try {
        final notification = LocalNotification(
          identifier: 'test_${DateTime.now().millisecondsSinceEpoch}',
          title: 'Theaver',
          body: 'Тестовое уведомление доставлено успешно!',
        );
        notification.onClick = () async {
          await DesktopTrayService().showAndFocusWindow();
        };
        await notification.show();
        debugPrint('NotificationService: desktop test notification shown successfully');
      } catch (e) {
        debugPrint('NotificationService: desktop test notification error: $e');
      }
    } else {
      try {
        const androidDetails = AndroidNotificationDetails(
          'private_chats',
          'Личные чаты',
          channelDescription: 'Уведомления о новых сообщениях в личных чатах',
          importance: Importance.high,
          priority: Priority.high,
          icon: '@drawable/ic_notification',
          color: Color(0xFF5B7FFF),
          playSound: true,
          enableVibration: true,
        );
        const iosDetails = DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
          presentBanner: true,
        );
        const details = NotificationDetails(android: androidDetails, iOS: iosDetails);
        await _localNotifications.show(
          99999,
          'Theaver',
          'Тестовое уведомление доставлено успешно!',
          details,
          payload: 'test',
        );
      } catch (e) {
        debugPrint('NotificationService: local test notification error: $e');
      }
    }

    // 2. In-app баннер
    showInAppBanner(
      chatId: '0',
      chatName: 'Theaver',
      senderName: 'Тест',
      messageText: 'Локальное уведомление создано!',
      isGroup: false,
    );

    // 3. Отправляем запрос на сервер
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {
          'success': true,
          'message': 'Локальное уведомление показано (на сервере вход не выполнен)',
        };
      }

      final response = await Dio().post(
        '${AppConfig.baseUrl}/api/notifications/test',
        options: Options(
          headers: {
            'Authorization': 'Bearer $token',
            'Content-Type': 'application/json',
          },
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final success = data['success'] == true;
        final msg = data['message'] ?? (success ? 'Push отправлен сервером' : 'Ошибка отправки');
        final deviceCount = data['device_count'] ?? 0;
        return {
          'success': success,
          'message': '$msg (устройств: $deviceCount)',
          'device_count': deviceCount,
        };
      }
      return {
        'success': false,
        'message': 'Сервер ответил со статусом ${response.statusCode}',
      };
    } catch (e) {
      debugPrint('NotificationService: server test notification error: $e');
      return {
        'success': true,
        'message': 'Локальное уведомление показано. Ответ сервера: $e',
      };
    }
  }

  void dispose() { _bannerController.close(); }
}
