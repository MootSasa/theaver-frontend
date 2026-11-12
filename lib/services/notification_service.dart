import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:dio/dio.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart'
    show Color, Widget, WidgetsBindingObserver, AppLifecycleState, WidgetsBinding;
import 'package:flutter/services.dart' show MethodChannel;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:local_notifier/local_notifier.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import '../config/app_config.dart';
import '../screens/chat/channel_screen.dart';
import '../screens/chat/group_chat_screen.dart';
import '../screens/chat/private_chat_screen.dart';
import '../screens/settings/widgets/update_dialog.dart';
import '../utils/image_utils.dart';
import '../utils/swipe_back_route.dart';
import 'account_manager.dart';
import 'auth_service.dart';
import 'deep_link_service.dart';
import 'desktop_tray_service.dart';
import 'notification_service_hms.dart';
import 'notification_settings_provider.dart';
import 'notifications/background_handlers.dart';
import 'notifications/call_notifications.dart';
import 'notifications/message_notification_presenter.dart';
import 'notifications/notification_channels.dart';
import 'notifications/notification_decider.dart';
import 'notifications/notification_dedup_store.dart';
import 'notifications/notification_payload.dart';
import 'push_service_detector.dart';
import 'settings_service.dart';
import 'tiling_layout_controller.dart';
import 'update_service.dart';
import 'web_notification_helper.dart';
import 'websocket_service.dart';

export 'notifications/background_handlers.dart'
    show firebaseMessagingBackgroundHandler, hmsMessagingBackgroundHandler;
export 'notifications/notification_images.dart'
    show downloadOrGetCachedImage, downloadOrGetCachedAvatar;

/// Result of the system notification sound picker.
class ChatSoundPick {
  const ChatSoundPick({required this.uri, required this.title});

  /// null = system default sound, '' = silent, otherwise a content URI.
  final String? uri;
  final String title;
}

/// Central notification facade.
///
/// Every notification is an OS system notification (no custom in-app banners):
///
/// * **Foreground**: the app renders notifications itself from WebSocket events
///   (and from FCM/HMS foreground messages as a fallback, de-duplicated by
///   message ID). The server does not push to foreground devices
///   (`client_state`, see backend `api/websocket_client_state.go`).
/// * **Background / killed**: the server sends FCM/HMS/APNs notification messages
///   that the OS renders with the same `tag chat_<id>` as foreground notifications.
/// * **Desktop / Web**: no push service — the WebSocket is always the source.
class NotificationService with WidgetsBindingObserver {
  NotificationService._internal();
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;

  static const MethodChannel _native = MethodChannel('app.theaver.messenger/push_detector');

  /// Native chat-notification renderer (Android) / notification config (iOS).
  /// On Android every chat notification — WebSocket or FCM/HMS push — is drawn by
  /// the same native code: chat avatar, history, "Ответить"/"Прочитано".
  static const MethodChannel _nativeNotifications =
      MethodChannel('app.theaver.messenger/native_notifications');

  static bool get _isAndroid => !kIsWeb && Platform.isAndroid;

  FirebaseMessaging? _firebaseMessaging;
  final FlutterLocalNotificationsPlugin _localNotifications = FlutterLocalNotificationsPlugin();
  late final MessageNotificationPresenter _presenter = MessageNotificationPresenter(_localNotifications);
  HMSPushService? _hmsPushService;
  final PushServiceDetector _detector = PushServiceDetector();
  final NotificationDedupStore _dedup = NotificationDedupStore();

  NotificationSettingsProvider? _settingsProvider;
  String? _pushToken;
  bool _initialized = false;
  bool _pushAvailable = false;
  bool _localNotificationsReady = false;

  int _unreadCount = 0;
  int get unreadCount => _unreadCount;
  String? get pushToken => _pushToken;
  bool get isInitialized => _initialized;
  PushServiceType get pushServiceType => _detector.serviceType;

  /// True when FCM/HMS is initialized and a token is registered, i.e. the server
  /// can reach this device while it is backgrounded.
  bool get isPushAvailable => _pushAvailable;

  /// Flag set by MainScreen when navigation from a notification tap is safe.
  bool isMainScreenReady = false;

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);
  static bool get _isMobile => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  /// Windows/Linux use local_notifier; Android/iOS/macOS use flutter_local_notifications.
  static bool get _usesLocalNotifier => !kIsWeb && (Platform.isWindows || Platform.isLinux);

  // ======================= Active chat / lifecycle =======================

  /// Chats currently open in visible tiles/routes (notifications suppressed while focused).
  final Set<String> _activeChatIds = <String>{};

  String? get currentActiveChatId => _activeChatIds.isNotEmpty ? _activeChatIds.last : null;
  set currentActiveChatId(String? value) => setActiveChat(value);

  bool _isAppInForeground = true;
  bool get isAppInForeground => _isAppInForeground;

  /// Whether a chat is open on screen. Only meaningful while the app/window is
  /// in the foreground — a chat left open in a minimized window is not "seen".
  bool isChatActive(String chatId) {
    if (chatId.isEmpty || !_isAppInForeground) return false;
    return _activeChatIds.contains(chatId) ||
        TilingLayoutController.instance.isChatOpenInAnyTile(chatId);
  }

  void addActiveChat(String chatId) {
    if (chatId.isEmpty) return;
    _activeChatIds
      ..remove(chatId)
      ..add(chatId);
    cancelChatNotifications(chatId);
    _syncClientState();
  }

  void removeActiveChat(String chatId) {
    if (chatId.isEmpty) return;
    _activeChatIds.remove(chatId);
    _syncClientState();
  }

  /// Sets the chat currently open on this device (legacy single-chat API).
  void setActiveChat(String? chatId, {String? previousChatId}) {
    if (chatId != null && chatId.isNotEmpty) {
      addActiveChat(chatId);
    } else if (previousChatId != null && previousChatId.isNotEmpty) {
      removeActiveChat(previousChatId);
    } else if (!TilingLayoutController.instance.isWorkspaceMounted) {
      _activeChatIds.clear();
      _syncClientState();
    } else {
      final openIds = TilingLayoutController.instance.chatTiles.map((t) => t.chatId).toSet();
      _activeChatIds.retainAll(openIds);
      _syncClientState();
    }
  }

  /// App/window/tab went to background (also called by DesktopTrayService and the web helper).
  void onAppPause() {
    if (!_isAppInForeground) return;
    _isAppInForeground = false;
    _syncClientState();
  }

  /// App/window/tab returned to foreground.
  void onAppResume() {
    if (_isAppInForeground) return;
    _isAppInForeground = true;
    _syncClientState();
    for (final id in _activeChatIds) {
      cancelChatNotifications(id);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // `inactive` (notification shade, app switcher, incoming system dialog) is
    // NOT background: the user is still in the app.
    if (state == AppLifecycleState.resumed) {
      onAppResume();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      if (!_isDesktop) onAppPause();
    }
  }

  void _syncClientState() {
    WebSocketService().sendClientState(
      isForeground: _isAppInForeground,
      activeChatId: _isAppInForeground ? currentActiveChatId : null,
      pushAvailable: _pushAvailable,
    );
    if (_isAndroid) {
      final active = <String>{
        ..._activeChatIds,
        if (TilingLayoutController.instance.isWorkspaceMounted)
          ...TilingLayoutController.instance.chatTiles.map((t) => t.chatId),
      }.where((id) => id.isNotEmpty).toList();
      _nativeNotifications.invokeMethod('setState', <String, dynamic>{
        'foreground': _isAppInForeground,
        'foreground_enabled': foregroundNotificationsEnabled,
        'active_chat_ids': _isAppInForeground ? active : <String>[],
      }).catchError((_) {});
    }
  }

  /// Passes API URLs and the auth token to native code so notification actions
  /// ("Ответить"/"Прочитано") work without Flutter running.
  Future<void> configureNativeNotifications() async {
    if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) return;
    try {
      await _nativeNotifications.invokeMethod('configure', <String, dynamic>{
        'base_url': AppConfig.baseUrl,
        'storage_url': AppConfig.storageUrl,
        'token': await AuthService.getToken() ?? '',
        'user_id': await AuthService.getUserId() ?? '',
      });
    } catch (e) {
      debugPrint('NotificationService: native configure failed: $e');
    }
  }

  Future<void> _initNativeNotificationBridge() async {
    if (!_isAndroid) return;
    _nativeNotifications.setMethodCallHandler((call) async {
      if (call.method == 'onNotificationTap') {
        final payload = (call.arguments as Map?)?['payload']?.toString();
        if (payload != null && payload.isNotEmpty) {
          _navigateFromNotificationData(normalizePushPayload(payload));
        }
        return true;
      }
      return null;
    });
    try {
      final initial = await _nativeNotifications.invokeMethod<String>('getInitialTap');
      if (initial != null && initial.isNotEmpty) {
        _navigateFromNotificationData(normalizePushPayload(initial));
      }
    } catch (_) {}
  }

  // ======================= Pending navigation / calls =======================

  Map<String, dynamic>? _pendingNotificationData;
  Map<String, dynamic>? get pendingNotificationData => _pendingNotificationData;
  bool get hasPendingNotification => _pendingNotificationData != null;

  void Function(String action, Map<String, dynamic> callData)? _callActionHandler;
  Map<String, dynamic>? _pendingCallAction;

  void registerCallActionHandler(
    void Function(String action, Map<String, dynamic> callData) handler,
  ) {
    _callActionHandler = handler;
    final pending = _pendingCallAction;
    if (pending != null) {
      _pendingCallAction = null;
      Future.microtask(() => handler(
            pending['action']?.toString() ?? 'open_call',
            Map<String, dynamic>.from(pending['data'] as Map),
          ));
    }
  }

  void _dispatchCallAction(String action, Map<String, dynamic> callData) {
    final handler = _callActionHandler;
    if (handler != null) {
      handler(action, callData);
    } else {
      _pendingCallAction = <String, dynamic>{'action': action, 'data': callData};
    }
  }

  void consumePendingNotification() {
    final pendingCall = _pendingCallAction;
    if (pendingCall != null && _callActionHandler != null) {
      _pendingCallAction = null;
      _callActionHandler!(
        pendingCall['action']?.toString() ?? 'open_call',
        Map<String, dynamic>.from(pendingCall['data'] as Map),
      );
    }
    final data = _pendingNotificationData;
    if (data != null) {
      _pendingNotificationData = null;
      _navigateFromNotificationData(data);
    }
  }

  // ======================= Initialization =======================

  StreamSubscription? _wsSubscription;

  /// Initializes notifications. Each step is isolated: a failing push provider
  /// (e.g. FCM `SERVICE_NOT_AVAILABLE`, missing iOS Firebase config) must never
  /// disable local/WebSocket notifications.
  Future<void> init(NotificationSettingsProvider settingsProvider) async {
    if (_initialized) return;
    _initialized = true;
    _settingsProvider = settingsProvider;
    WidgetsBinding.instance.addObserver(this);

    await _step('push detection', _detector.detect);
    debugPrint('NotificationService: push service = ${_detector.serviceType}');

    if (kIsWeb) {
      WebNotificationHelper.init(onTabHidden: onAppPause, onTabVisible: onAppResume);
    } else {
      if (_isDesktop) await _step('desktop tray', () => DesktopTrayService().init());
      if (_usesLocalNotifier) {
        await _step('local_notifier', () => localNotifier.setup(
              appName: 'Theaver',
              shortcutPolicy: ShortcutPolicy.requireCreate,
            ));
      } else {
        await _step('local notifications', _initLocalNotifications);
      }
    }

    // WebSocket notifications work regardless of the push provider outcome.
    _subscribeWebSocketMessages();
    await _step('native notifications', () async {
      await configureNativeNotifications();
      await _initNativeNotificationBridge();
    });

    if (_isMobile) {
      switch (_detector.serviceType) {
        case PushServiceType.gms:
          await _step('FCM', _initFCM);
          break;
        case PushServiceType.hms:
          await _step('HMS', _initHMS);
          break;
        case PushServiceType.none:
          debugPrint('NotificationService: no push service, WebSocket notifications only');
          break;
      }
    }
    _syncClientState();
    debugPrint('NotificationService: initialized (push=${_detector.serviceType}, available=$_pushAvailable)');
  }

  Future<void> _step(String name, Future<void> Function() body) async {
    try {
      await body();
    } catch (e, st) {
      debugPrint('NotificationService: $name init failed: $e\n$st');
    }
  }

  Future<void> _initLocalNotifications() async {
    final darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
      notificationCategories: MessageNotificationPresenter.darwinCategories(),
    );
    await _localNotifications.initialize(
      InitializationSettings(
        android: const AndroidInitializationSettings('@drawable/ic_notification'),
        iOS: darwin,
        macOS: darwin,
      ),
      onDidReceiveNotificationResponse: _onLocalNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: notificationActionBackgroundHandler,
    );
    _localNotificationsReady = true;

    if (!kIsWeb && Platform.isAndroid) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await NotificationChannels.ensureBaseChannels(_localNotifications);
    } else if (!kIsWeb && Platform.isIOS) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } else if (!kIsWeb && Platform.isMacOS) {
      await _localNotifications
          .resolvePlatformSpecificImplementation<MacOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    }

    final launch = await _localNotifications.getNotificationAppLaunchDetails();
    if (launch?.didNotificationLaunchApp == true && launch?.notificationResponse != null) {
      _onLocalNotificationResponse(launch!.notificationResponse!);
    }
  }

  // ======================= Push providers =======================

  Future<void> _initFCM() async {
    _firebaseMessaging = FirebaseMessaging.instance;

    // Handlers first: they must work even if permission/token calls fail.
    FirebaseMessaging.onMessage.listen((m) => _handlePushData(m.data));
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _navigateFromNotificationData(m.data));
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    _firebaseMessaging!.onTokenRefresh.listen((token) {
      _pushToken = token;
      _registerPushTokenOnServer(token, 'fcm');
    });

    if (!kIsWeb && Platform.isIOS) {
      // In foreground the app renders notifications itself (WebSocket); a push
      // that still arrives (state race) is handled in onMessage + de-duplicated.
      await _firebaseMessaging!.setForegroundNotificationPresentationOptions(
        alert: false,
        badge: true,
        sound: false,
      );
    }

    await _step('FCM permission', () async {
      final settings = await _firebaseMessaging!.requestPermission(alert: true, badge: true, sound: true);
      debugPrint('NotificationService: FCM permission = ${settings.authorizationStatus}');
    });

    await _step('FCM initial message', () async {
      final initial = await _firebaseMessaging!.getInitialMessage();
      if (initial != null) _navigateFromNotificationData(initial.data);
    });

    final token = await _firebaseMessaging!.getToken();
    if (token != null && token.isNotEmpty) {
      _pushToken = token;
      _pushAvailable = true;
      await _registerPushTokenOnServer(token, 'fcm');
    }
  }

  Future<void> _initHMS() async {
    _hmsPushService = HMSPushService();
    _hmsPushService!.onMessageReceived.listen(_handlePushData);
    _hmsPushService!.onMessageOpenedApp.listen(_navigateFromNotificationData);
    _hmsPushService!.onTokenRefresh.listen((token) {
      _pushToken = token;
      _pushAvailable = token.isNotEmpty;
      _registerPushTokenOnServer(token, 'hms');
      _syncClientState();
    });
    await _hmsPushService!.registerBackgroundMessageHandler(hmsMessagingBackgroundHandler);
    await _hmsPushService!.requestPermission();

    await _step('HMS initial notification', () async {
      final initial = await _hmsPushService!.getInitialNotification();
      if (initial != null && initial.isNotEmpty) _navigateFromNotificationData(initial);
    });

    final token = await _hmsPushService!.getToken();
    if (token != null && token.isNotEmpty) {
      _pushToken = token;
      _pushAvailable = true;
      await _registerPushTokenOnServer(token, 'hms');
    }
  }

  // ======================= Token registration =======================

  Future<void> _registerPushTokenOnServer(String token, String type) async {
    try {
      final authToken = await AuthService.getToken();
      if (authToken == null || authToken.isEmpty) {
        debugPrint('NotificationService: $type token will be registered after login');
        return;
      }
      final prefs = await SharedPreferences.getInstance();
      final deviceId = AccountManager().currentDeviceId ??
          prefs.getString('current_device_id') ??
          prefs.getString('device_id') ??
          'unknown';
      final payload = <String, dynamic>{
        'token': token,
        'push_token': token,
        'fcm_token': token,
        'service_type': type,
        'type': type,
        'device_id': deviceId,
        // Android renders chat pushes natively (data messages): avatar, history,
        // reply/read actions — the same look as foreground notifications.
        if (_isAndroid) 'push_render': 'native',
      };
      final options = Options(headers: <String, String>{
        'Authorization': 'Bearer $authToken',
        'Content-Type': 'application/json',
      });
      try {
        await Dio().put('${AppConfig.baseUrl}/api/sessions/push-token', data: payload, options: options);
      } catch (_) {
        await Dio().post('${AppConfig.baseUrl}/api/notifications/push-token', data: payload, options: options);
      }
      debugPrint('NotificationService: $type push token registered');
    } catch (e) {
      debugPrint('NotificationService: failed to register $type token: $e');
    }
  }

  Future<void> registerCurrentToken() async {
    if (_pushToken == null || _pushToken!.isEmpty) {
      try {
        if (_detector.serviceType == PushServiceType.hms) {
          _pushToken = await _hmsPushService?.getToken();
        } else if (_detector.serviceType == PushServiceType.gms) {
          _pushToken = await _firebaseMessaging?.getToken();
        }
      } catch (e) {
        debugPrint('NotificationService: token refresh failed: $e');
      }
    }
    final token = _pushToken;
    if (token != null && token.isNotEmpty) {
      _pushAvailable = true;
      await _registerPushTokenOnServer(token, _detector.serviceType == PushServiceType.hms ? 'hms' : 'fcm');
    }
    await configureNativeNotifications();
    _syncClientState();
  }

  Future<void> unregisterPushToken() async {
    if (!kIsWeb && (Platform.isAndroid || Platform.isIOS)) {
      // Logged out: native notification actions must not use the old token.
      _nativeNotifications.invokeMethod('configure', <String, dynamic>{
        'base_url': AppConfig.baseUrl,
        'storage_url': AppConfig.storageUrl,
        'token': '',
        'user_id': '',
      }).catchError((_) {});
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      final deviceId = AccountManager().currentDeviceId ??
          prefs.getString('current_device_id') ??
          prefs.getString('device_id') ??
          'unknown';
      final authToken = await AuthService.getToken();
      final options = Options(headers: <String, String>{
        if (authToken != null) 'Authorization': 'Bearer $authToken',
        'Content-Type': 'application/json',
      });
      try {
        await Dio().delete('${AppConfig.baseUrl}/api/sessions/push-token',
            data: {'device_id': deviceId}, options: options);
      } catch (_) {
        await Dio().delete('${AppConfig.baseUrl}/api/notifications/push-token',
            data: {'device_id': deviceId}, options: options);
      }
    } catch (e) {
      debugPrint('NotificationService: failed to unregister token: $e');
    }
  }

  // ======================= Incoming events =======================

  void _subscribeWebSocketMessages() {
    _wsSubscription?.cancel();
    _wsSubscription = WebSocketService().eventStream.listen((event) async {
      try {
        switch (event.type) {
          case WebSocketEventType.messageRead:
            final cid = event.data['chat_id']?.toString();
            if (cid != null && cid.isNotEmpty) cancelChatNotifications(cid);
            return;
          case WebSocketEventType.unreadCountUpdated:
            final cid = event.data['chat_id']?.toString();
            if (cid != null && cid.isNotEmpty && event.data['unread_count'] == 0) {
              cancelChatNotifications(cid);
            }
            return;
          case WebSocketEventType.newMessage:
            final data = Map<String, dynamic>.from(event.data);
            final m = ChatMessageNotification.fromWebSocket(data);
            if (m == null || m.messageType == 'call') return;
            await _onChatMessage(m, NotificationSource.websocket);
            return;
          default:
            return;
        }
      } catch (e, st) {
        debugPrint('NotificationService: WebSocket event handling failed: $e\n$st');
      }
    });
  }

  /// FCM/HMS message delivered to the running app.
  Future<void> _handlePushData(Map<String, dynamic> rawData) async {
    final data = normalizePushPayload(rawData);
    final type = data['type']?.toString() ?? '';
    debugPrint('NotificationService: push "$type" in foreground');
    switch (type) {
      case 'new_message':
        if ((data['message_type'] ?? '').toString() == 'call') return;
        final m = ChatMessageNotification.fromPush(data);
        if (m != null) await _onChatMessage(m, NotificationSource.push);
        break;
      case 'read_status_updated':
        final cid = data['chat_id']?.toString();
        if (cid != null && cid.isNotEmpty) cancelChatNotifications(cid);
        break;
      case 'incoming_call':
        _handleIncomingCallPush(data);
        break;
      case 'call_ended':
        cancelIncomingCallNotification(
          callId: data['call_id']?.toString(),
          chatId: data['chat_id']?.toString(),
        );
        break;
      case 'app_update':
        _handleAppUpdatePush();
        break;
    }
  }

  Future<void> _onChatMessage(ChatMessageNotification m, NotificationSource source) async {
    final currentUserId = await AuthService.getUserId();
    final isOwn = m.senderId.isNotEmpty && currentUserId != null && m.senderId == currentUserId;

    final ctx = NotificationContext(
      source: source,
      chatId: m.chatId,
      isOwnMessage: isOwn,
      isChatOpen: isChatActive(m.chatId),
      isAppInForeground: _isAppInForeground,
      isAllowedBySettings: _settingsProvider?.shouldShowNotification(m.chatId, isMention: m.isMention) ?? true,
      foregroundNotificationsEnabled: foregroundNotificationsEnabled,
      pushAvailable: _pushAvailable,
      isDuplicate: false,
      isDesktopOrWeb: kIsWeb || _isDesktop,
    );
    var decision = decideNotification(ctx);
    if (decision == NotificationDecision.show) {
      final key = NotificationDedupStore.keyFor(
          kind: 'msg', chatId: m.chatId, messageId: m.messageId, fallbackText: m.text);
      if (await _dedup.checkAndMark(key)) decision = NotificationDecision.skipDuplicate;
    }
    if (decision != NotificationDecision.show) {
      debugPrint('NotificationService: chat ${m.chatId} msg ${m.messageId} -> $decision');
      return;
    }
    await _presentChatMessage(m);
  }

  Future<void> _presentChatMessage(ChatMessageNotification m) async {
    final effective = _settingsProvider?.getEffectiveSettings(m.chatId);
    final showPreview = effective?.previewEnabled ?? true;
    final soundEnabled = effective?.soundEnabled ?? true;

    if (kIsWeb) {
      final title = m.chatName;
      final body = showPreview
          ? (m.isGroup && m.senderName.isNotEmpty ? '${m.senderName}: ${m.text}' : m.text)
          : 'Новое сообщение';
      WebNotificationHelper.showBrowserNotification(
        title: title,
        body: body,
        iconUrl: getValidAvatarUrl(m.avatarUrl),
        tag: 'chat_${m.chatId}',
        onTap: () => _navigateFromNotificationData(m.toTapPayload()),
      );
      return;
    }

    if (_usesLocalNotifier) {
      await _showDesktopMessage(m, showPreview: showPreview, soundEnabled: soundEnabled);
      return;
    }

    if (_isAndroid) {
      try {
        await _nativeNotifications.invokeMethod('showChatNotification', <String, dynamic>{
          'type': 'new_message',
          'chat_id': m.chatId,
          'chat_name': m.chatName,
          'chat_type': m.isChannel ? 'channel' : (m.isGroup ? 'group' : 'private'),
          'is_group': '${m.isGroup}',
          'is_channel': '${m.isChannel}',
          'is_mention': '${m.isMention}',
          'sender_id': m.senderId,
          'sender_name': showPreview ? m.senderName : '',
          'message_text': showPreview ? m.text : 'Новое сообщение',
          if (m.messageId != null) 'id': m.messageId,
          if (m.avatarUrl != null) 'avatar_url': m.avatarUrl,
          if (m.senderAvatarUrl != null) 'sender_avatar_url': m.senderAvatarUrl,
          if (!soundEnabled) 'sound': 'none',
        });
      } catch (e) {
        debugPrint('NotificationService: native chat notification failed: $e');
      }
      return;
    }

    if (!_localNotificationsReady) return;
    await _presenter.present(
      m,
      options: MessagePresentationOptions(
        showPreview: showPreview,
        soundEnabled: soundEnabled,
        vibrationEnabled: effective?.vibration != VibrationPattern.none,
        vibrationPattern: _vibrationPattern(effective?.vibration),
      ),
    );
  }

  // ======================= Desktop (Windows / Linux) =======================

  final Map<String, List<LocalNotification>> _desktopNotifications = <String, List<LocalNotification>>{};

  Future<void> _showDesktopMessage(
    ChatMessageNotification m, {
    required bool showPreview,
    required bool soundEnabled,
  }) async {
    try {
      // One toast per chat: replace the previous one.
      final previous = _desktopNotifications.remove(m.chatId);
      for (final n in previous ?? const <LocalNotification>[]) {
        try {
          await n.close();
        } catch (_) {}
      }
      final body = showPreview
          ? (m.isGroup && m.senderName.isNotEmpty ? '${m.senderName}: ${m.text}' : m.text)
          : 'Новое сообщение';
      final notification = LocalNotification(
        identifier: 'msg_${m.chatId}_${DateTime.now().microsecondsSinceEpoch}',
        title: showPreview ? m.chatName : 'Theaver',
        body: body,
        silent: !soundEnabled,
      );
      (_desktopNotifications[m.chatId] ??= <LocalNotification>[]).add(notification);
      notification.onClose = (_) => _desktopNotifications[m.chatId]?.remove(notification);
      notification.onClick = () async {
        _desktopNotifications[m.chatId]?.remove(notification);
        try {
          await notification.close();
        } catch (_) {}
        await DesktopTrayService().showAndFocusWindow();
        _navigateFromNotificationData(m.toTapPayload());
      };
      await notification.show();
    } catch (e) {
      debugPrint('NotificationService: desktop toast failed: $e');
    }
  }

  // ======================= Calls =======================

  final Map<String, DateTime> _shownIncomingCallIds = <String, DateTime>{};

  void _handleIncomingCallPush(Map<String, dynamic> data) {
    showCallNotification(
      callId: data['call_id']?.toString() ?? '',
      chatId: data['chat_id']?.toString() ?? '',
      callerId: data['caller_id']?.toString() ?? '',
      callerName: payloadString(data, const ['caller_name', 'chat_name'], 'Входящий звонок'),
      callerAvatar: payloadString(data, const ['caller_avatar', 'avatar_url']),
      isVideo: payloadBool(data['is_video']) || data['call_type'] == 'video',
      isGroup: data['chat_type'] == 'group' || payloadBool(data['is_group']),
      chatTitle: payloadString(data, const ['chat_title', 'chat_name']),
    );
    _dispatchCallAction('incoming_push', data);
  }

  /// Shows the system incoming-call notification on every platform, in
  /// foreground and background (there is no custom in-app call banner).
  Future<void> showCallNotification({
    required String callId,
    required String callerName,
    String chatId = '',
    String callerId = '',
    String? callerAvatar,
    bool isVideo = false,
    bool isGroup = false,
    String? chatTitle,
  }) async {
    final now = DateTime.now();
    _shownIncomingCallIds.removeWhere((_, ts) => now.difference(ts).inSeconds > 45);
    final dedupKey = callId.isNotEmpty ? callId : chatId;
    if (dedupKey.isNotEmpty) {
      if (_shownIncomingCallIds.containsKey(dedupKey)) return;
      _shownIncomingCallIds[dedupKey] = now;
      if (!kIsWeb && callId.isNotEmpty && !await CallNotifications.markCallShown(callId)) return;
    }

    final displayCaller = callerName.isNotEmpty
        ? callerName
        : (chatTitle != null && chatTitle.isNotEmpty ? chatTitle : 'Входящий звонок');
    final title = CallNotifications.titleFor(isVideo: isVideo, isGroup: isGroup);
    final body = '$displayCaller звонит вам';
    final payload = <String, dynamic>{
      'type': 'incoming_call',
      'call_id': callId,
      'chat_id': chatId,
      'caller_id': callerId,
      'caller_name': displayCaller,
      if (callerAvatar != null) 'caller_avatar': callerAvatar,
      'is_video': isVideo,
      'is_group': isGroup,
      if (chatTitle != null) 'chat_title': chatTitle,
    };

    if (kIsWeb) {
      WebNotificationHelper.showBrowserNotification(
        title: title,
        body: body,
        iconUrl: getValidAvatarUrl(callerAvatar),
        tag: 'incoming_call_$dedupKey',
        requireInteraction: true,
        onTap: () => _dispatchCallAction('open_call', payload),
      );
      return;
    }

    if (_usesLocalNotifier) {
      await _showDesktopCall(title: title, body: body, callId: callId, payload: payload);
      return;
    }

    if (!_localNotificationsReady) return;
    await CallNotifications.showIncoming(
      _localNotifications,
      payload: payload,
      callerName: displayCaller,
      callerAvatar: callerAvatar,
      isVideo: isVideo,
      isGroup: isGroup,
    );
    if (Platform.isMacOS) {
      try {
        if (!await windowManager.isVisible()) {
          await DesktopTrayService().showAndFocusWindow();
        }
      } catch (_) {}
    }
  }

  Future<void> _showDesktopCall({
    required String title,
    required String body,
    required String callId,
    required Map<String, dynamic> payload,
  }) async {
    try {
      for (final prev in _desktopNotifications.remove('calls') ?? const <LocalNotification>[]) {
        try {
          await prev.close();
        } catch (_) {}
      }
      final notification = LocalNotification(
        identifier: 'call_${callId.isNotEmpty ? callId : DateTime.now().millisecondsSinceEpoch}',
        title: title,
        body: body,
        silent: false,
        actions: <LocalNotificationAction>[
          LocalNotificationAction(text: 'Принять'),
          LocalNotificationAction(text: 'Отклонить'),
        ],
      );
      (_desktopNotifications['calls'] ??= <LocalNotification>[]).add(notification);
      notification.onClose = (_) => _desktopNotifications['calls']?.remove(notification);
      notification.onClick = () async {
        _desktopNotifications['calls']?.remove(notification);
        await DesktopTrayService().showAndFocusWindow();
        _dispatchCallAction('open_call', payload);
      };
      notification.onClickAction = (index) async {
        _desktopNotifications['calls']?.remove(notification);
        if (index == 0) {
          await DesktopTrayService().showAndFocusWindow();
          _dispatchCallAction('accept_call', payload);
        } else {
          _dispatchCallAction('decline_call', payload);
        }
      };
      await notification.show();
    } catch (e) {
      debugPrint('NotificationService: desktop call toast failed: $e');
    }
  }

  Future<void> showMissedCallNotification({
    required String callId,
    required String chatId,
    required String callerName,
    bool isVideo = false,
    bool isGroup = false,
  }) async {
    await cancelIncomingCallNotification(callId: callId, chatId: chatId);
    final displayCaller = callerName.isNotEmpty ? callerName : 'Собеседник';
    final title = isVideo ? 'Пропущенный видеозвонок' : 'Пропущенный звонок';
    final payload = <String, dynamic>{
      'type': 'missed_call',
      'call_id': callId,
      'chat_id': chatId,
      'caller_name': displayCaller,
      'chat_name': displayCaller,
      'is_video': isVideo,
      'is_group': isGroup,
    };

    if (kIsWeb) {
      WebNotificationHelper.showBrowserNotification(
        title: title,
        body: displayCaller,
        tag: 'missed_call_${callId.isNotEmpty ? callId : chatId}',
        onTap: () => _navigateFromNotificationData({...payload, 'type': 'new_message'}),
      );
      return;
    }
    if (_usesLocalNotifier) {
      try {
        final notification = LocalNotification(
          identifier: 'missed_call_${callId.isNotEmpty ? callId : chatId}',
          title: title,
          body: displayCaller,
          silent: true,
        );
        notification.onClick = () async {
          await DesktopTrayService().showAndFocusWindow();
          await _navigateFromNotificationData({...payload, 'type': 'new_message'});
        };
        await notification.show();
      } catch (_) {}
      return;
    }
    if (!_localNotificationsReady) return;
    await CallNotifications.showMissed(
      _localNotifications,
      payload: payload,
      callerName: displayCaller,
      callKey: callId.isNotEmpty ? callId : chatId,
      isVideo: isVideo,
    );
  }

  Future<void> cancelIncomingCallNotification({String? callId, String? chatId}) async {
    if (callId != null && callId.isNotEmpty) _shownIncomingCallIds.remove(callId);
    if (chatId != null && chatId.isNotEmpty) _shownIncomingCallIds.remove(chatId);
    if (kIsWeb) return;
    if (_usesLocalNotifier) {
      for (final n in _desktopNotifications.remove('calls') ?? const <LocalNotification>[]) {
        try {
          await n.close();
        } catch (_) {}
      }
      await CallNotifications.clearCallShown(callId);
      return;
    }
    await CallNotifications.cancelIncoming(_localNotifications, callId: callId, chatId: chatId);
  }

  Future<void> startCallForegroundService({
    required String title,
    bool isVideo = false,
    bool isScreenShare = false,
  }) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _native.invokeMethod('startCallForegroundService', {
        'title': title,
        'is_video': isVideo,
        'is_screen_share': isScreenShare,
      });
    } catch (e) {
      debugPrint('NotificationService: startCallForegroundService error: $e');
    }
  }

  Future<void> promoteCallToMediaProjection() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _native.invokeMethod('promoteCallToMediaProjection');
    } catch (e) {
      debugPrint('NotificationService: promoteCallToMediaProjection error: $e');
    }
  }

  Future<void> stopCallForegroundService() async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      await _native.invokeMethod('stopCallForegroundService');
    } catch (e) {
      debugPrint('NotificationService: stopCallForegroundService error: $e');
    }
  }

  // ======================= App updates =======================

  static const int _kAppUpdateNotificationId = 88888;

  Future<void> _handleAppUpdatePush() async {
    try {
      final update = await AppUpdateService.instance.checkForUpdate(silent: true);
      if (update.hasUpdate) {
        await showAppUpdateNotification(update);
        await AppUpdateService.instance.markDeviceNotified(update.latestBuild);
      }
    } catch (e) {
      debugPrint('NotificationService: app update push error: $e');
    }
  }

  /// System notification about a new Theaver version.
  Future<void> showAppUpdateNotification(AppUpdateInfo update) async {
    if (!update.hasUpdate) return;
    final title = update.forceUpdate
        ? 'Требуется обновление Theaver v${update.latestVersion}'
        : 'Доступно обновление Theaver v${update.latestVersion}';
    final cleanNotes = update.releaseNotes.trim().replaceAll(RegExp(r'\s+'), ' ');
    final sizeInfo = update.formattedSize.isNotEmpty ? ' (${update.formattedSize})' : '';
    final body = cleanNotes.isNotEmpty
        ? 'Сборка #${update.latestBuild}$sizeInfo: ${cleanNotes.length > 140 ? '${cleanNotes.substring(0, 140)}…' : cleanNotes}'
        : 'Доступна новая сборка #${update.latestBuild}$sizeInfo. Нажмите, чтобы установить обновление.';
    final payload = <String, dynamic>{...update.toJson(), 'type': 'app_update'};

    if (kIsWeb) {
      WebNotificationHelper.showBrowserNotification(
        title: title,
        body: body,
        tag: 'app_update_${update.latestBuild}',
        onTap: () => _navigateFromNotificationData(payload),
      );
      return;
    }
    if (_usesLocalNotifier) {
      try {
        for (final prev in _desktopNotifications.remove('app_updates') ?? const <LocalNotification>[]) {
          try {
            await prev.close();
          } catch (_) {}
        }
        final notification = LocalNotification(
          identifier: 'app_update_${update.latestBuild}',
          title: title,
          body: body,
        );
        (_desktopNotifications['app_updates'] ??= <LocalNotification>[]).add(notification);
        notification.onClick = () async {
          await DesktopTrayService().showAndFocusWindow();
          await _navigateFromNotificationData(payload);
        };
        await notification.show();
      } catch (e) {
        debugPrint('NotificationService: desktop update toast failed: $e');
      }
      return;
    }
    if (!_localNotificationsReady) return;
    try {
      await _localNotifications.show(
        _kAppUpdateNotificationId,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            NotificationChannels.appUpdates,
            NotificationChannels.label(NotificationChannels.appUpdates),
            channelDescription: NotificationChannels.description(NotificationChannels.appUpdates),
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
            icon: '@drawable/ic_notification',
            color: const Color(0xFF5B7FFF),
            autoCancel: true,
            onlyAlertOnce: true,
            styleInformation: BigTextStyleInformation(
              body,
              contentTitle: title,
              summaryText: 'Theaver v${update.latestVersion}',
            ),
          ),
          iOS: const DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentSound: true),
          macOS: const DarwinNotificationDetails(presentAlert: true, presentBanner: true, presentSound: true),
        ),
        payload: jsonEncode(payload),
      );
    } catch (e) {
      debugPrint('NotificationService: update notification failed: $e');
    }
  }

  // ======================= Cancellation =======================

  void updateUnreadCount(int count) {
    _unreadCount = count;
  }

  /// Removes all notifications of a chat (local, FCM-rendered and HMS-rendered).
  Future<void> cancelChatNotifications(String chatId, {String? chatTitle}) async {
    if (kIsWeb || chatId.isEmpty) return;
    if (_usesLocalNotifier) {
      for (final n in _desktopNotifications.remove(chatId) ?? const <LocalNotification>[]) {
        try {
          await n.close();
        } catch (_) {}
      }
      return;
    }
    await _presenter.cancelChat(chatId);
    if (Platform.isAndroid) {
      try {
        await _nativeNotifications.invokeMethod('cancelChat', <String, dynamic>{'chat_id': chatId});
      } catch (_) {}
      try {
        await _native.invokeMethod('cancelChatNotifications', {'chat_id': chatId});
      } catch (_) {}
      if (_detector.serviceType == PushServiceType.hms) {
        try {
          await (_hmsPushService ?? HMSPushService()).cancelChatNotifications(chatId);
        } catch (_) {}
      }
    }
  }

  Future<void> cancelAllNotifications() async {
    if (kIsWeb) return;
    for (final list in _desktopNotifications.values) {
      for (final n in list) {
        try {
          await n.close();
        } catch (_) {}
      }
    }
    _desktopNotifications.clear();
    if (_usesLocalNotifier) return;
    await _presenter.cancelAll();
    if (Platform.isAndroid) {
      try {
        await _nativeNotifications.invokeMethod('cancelAll');
      } catch (_) {}
      try {
        await _native.invokeMethod('cancelAllNotifications');
      } catch (_) {}
      if (_detector.serviceType == PushServiceType.hms) {
        try {
          await (_hmsPushService ?? HMSPushService()).cancelAllNotifications();
        } catch (_) {}
      }
    }
  }

  // ======================= Settings =======================

  /// "Показывать уведомления, когда приложение открыто".
  bool get foregroundNotificationsEnabled =>
      _settingsProvider?.globalSettings.foregroundNotifications ?? true;

  bool shouldShowNotification(String chatId, {bool isMention = false}) {
    if (isChatActive(chatId)) return false;
    return _settingsProvider?.shouldShowNotification(chatId, isMention: isMention) ?? true;
  }

  static Int64List? _vibrationPattern(VibrationPattern? p) => switch (p) {
        VibrationPattern.short => Int64List.fromList(<int>[0, 100]),
        VibrationPattern.long => Int64List.fromList(<int>[0, 400]),
        VibrationPattern.doubleShort => Int64List.fromList(<int>[0, 100, 100, 100]),
        VibrationPattern.tripleShort => Int64List.fromList(<int>[0, 100, 100, 100, 100, 100]),
        _ => null,
      };

  // ======================= Per-chat channels (Android) =======================

  /// Whether per-chat notification channels / the system sound picker are supported.
  bool get supportsChatChannels => !kIsWeb && Platform.isAndroid;

  /// Opens the system notification sound picker (Android). Returns null when
  /// cancelled/unsupported; otherwise a [ChatSoundPick] where `uri == null`
  /// means "system default" and `uri == ''` means "silent".
  Future<ChatSoundPick?> pickChatSound({String? currentUri}) async {
    if (!supportsChatChannels) return null;
    try {
      final result = await _native.invokeMethod<Map<dynamic, dynamic>>(
        'pickNotificationSound',
        <String, dynamic>{'current_uri': currentUri},
      );
      if (result == null || result['cancelled'] == true) return null;
      return ChatSoundPick(uri: result['uri'] as String?, title: result['title']?.toString() ?? '');
    } catch (e) {
      debugPrint('NotificationService: sound picker failed: $e');
      return null;
    }
  }

  /// Device-local sound URI of a chat channel (null = default, '' = silent).
  Future<String?> chatSoundUri(String chatId) => NotificationChannels.customSoundFor(chatId);

  /// Creates/updates the per-chat Android channel (Telegram-style) and tells the
  /// server which channel to reference in pushes for this chat on this device.
  ///
  /// Pass [useCustomChannel] = false to drop the custom channel and fall back to
  /// the base channel of the chat type.
  Future<void> applyChatChannelSettings({
    required String chatId,
    required String chatTitle,
    required bool isGroup,
    required bool useCustomChannel,
    String? soundUri,
    VibrationPattern? vibration,
  }) async {
    if (!supportsChatChannels || chatId.isEmpty) return;
    String? channelId;
    try {
      if (useCustomChannel) {
        channelId = await NotificationChannels.upsertChatChannel(
          _localNotifications,
          chatId: chatId,
          chatTitle: chatTitle,
          isGroup: isGroup,
          soundUri: soundUri,
          vibrationEnabled: vibration != VibrationPattern.none,
          vibrationPattern: _vibrationPattern(vibration),
        );
      } else {
        await NotificationChannels.removeChatChannel(_localNotifications, chatId);
      }
    } catch (e) {
      debugPrint('NotificationService: chat channel update failed: $e');
      return;
    }
    await _syncChatChannelWithServer(chatId, channelId);
  }

  /// Opens the system settings page of the chat's channel (or of the app).
  Future<void> openChatChannelSettings(String chatId) async {
    if (!supportsChatChannels) return;
    final channelId = await NotificationChannels.customChannelFor(chatId);
    try {
      await _native.invokeMethod('openChannelSettings', <String, dynamic>{'channel_id': channelId});
    } catch (_) {}
  }

  Future<void> _syncChatChannelWithServer(String chatId, String? channelId) async {
    try {
      final authToken = await AuthService.getToken();
      if (authToken == null || authToken.isEmpty) return;
      final prefs = await SharedPreferences.getInstance();
      final deviceId = AccountManager().currentDeviceId ??
          prefs.getString('current_device_id') ??
          prefs.getString('device_id') ??
          '';
      if (deviceId.isEmpty) return;
      final options = Options(headers: <String, String>{
        'Authorization': 'Bearer $authToken',
        'Content-Type': 'application/json',
      });
      final url = '${AppConfig.baseUrl}/api/notifications/channels';
      final body = <String, dynamic>{'chat_id': chatId, 'device_id': deviceId};
      if (channelId != null) {
        await Dio().put(url, data: {...body, 'channel_id': channelId}, options: options);
      } else {
        await Dio().delete(url, data: body, options: options);
      }
    } catch (e) {
      debugPrint('NotificationService: channel sync failed: $e');
    }
  }

  // ======================= Taps & actions =======================

  void _onLocalNotificationResponse(NotificationResponse response) {
    final actionId = response.actionId;
    if (actionId == MessageNotificationPresenter.actionReply ||
        actionId == MessageNotificationPresenter.actionMarkRead) {
      // iOS/macOS deliver text/plain actions here while the app is running.
      handleMessageNotificationAction(response);
      return;
    }
    final payload = response.payload;
    if (payload == null || payload.isEmpty || payload == 'test') return;

    if (payload.startsWith('call_')) {
      final callId = payload.substring(5);
      cancelIncomingCallNotification(callId: callId);
      _dispatchCallAction(actionId ?? 'open_call', <String, dynamic>{'type': 'incoming_call', 'call_id': callId});
      return;
    }

    final data = normalizePushPayload(payload);
    if (data['type'] == 'incoming_call') {
      cancelIncomingCallNotification(callId: data['call_id']?.toString(), chatId: data['chat_id']?.toString());
      _dispatchCallAction(actionId ?? 'open_call', data);
      return;
    }
    if (data['type'] == 'missed_call' || actionId == 'callback_missed_call') {
      if (actionId == 'callback_missed_call') {
        _dispatchCallAction('callback_missed_call', data);
      }
      _navigateFromNotificationData(<String, dynamic>{...data, 'type': 'new_message'});
      return;
    }
    _navigateFromNotificationData(data);
  }

  Future<void> _navigateFromNotificationData(Map<String, dynamic> rawData) async {
    final data = normalizePushPayload(rawData);

    if (data['type'] == 'incoming_call') {
      cancelIncomingCallNotification(callId: data['call_id']?.toString(), chatId: data['chat_id']?.toString());
      _dispatchCallAction(data['action']?.toString() ?? 'open_call', data);
      return;
    }

    if (_isDesktop) {
      try {
        await DesktopTrayService().showAndFocusWindow();
      } catch (_) {}
    }

    if (data['type'] == 'app_update') {
      await _openAppUpdate(data);
      return;
    }

    final chatId = data['chat_id']?.toString();
    if (chatId == null || chatId.isEmpty || chatId == '0') return;

    if (!isMainScreenReady) {
      _pendingNotificationData = data;
      return;
    }

    var token = await AuthService.getToken();
    for (var i = 0; token == null && i < 5; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 150));
      token = await AuthService.getToken();
    }
    if (token == null) return;

    final navState = DeepLinkService().navigatorKey.currentState;
    if (navState == null) {
      _pendingNotificationData = data;
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (_pendingNotificationData != null && isMainScreenReady) consumePendingNotification();
      });
      return;
    }

    cancelChatNotifications(chatId);

    final chatName = payloadString(data, const ['chat_name', 'sender_name']);
    final avatarUrl = payloadString(data, const ['avatar_url', 'avatar']);
    final messageId = payloadString(data, const ['id', 'message_id']);
    final isGroup = payloadBool(data['is_group']);
    final isChannel = payloadBool(data['is_channel']) || data['chat_type'] == 'channel';

    if (TilingLayoutController.instance.isWorkspaceMounted) {
      try {
        navState.popUntil((route) => route.isFirst);
      } catch (_) {}
      TilingLayoutController.instance.openChatInActiveTile(
        chatId: chatId,
        chatType: isChannel ? 'channel' : (isGroup ? 'group' : 'private'),
        chatName: chatName,
        avatarUrl: avatarUrl.isEmpty ? null : avatarUrl,
        initialMessageId: messageId.isEmpty ? null : messageId,
      );
      return;
    }

    if (isChatActive(chatId)) return;
    try {
      navState.popUntil((route) => route.isFirst);
    } catch (_) {}

    final Widget screen;
    if (isChannel) {
      screen = ChannelScreen(
        channelId: chatId,
        channelName: chatName.isNotEmpty ? chatName : null,
        channelAvatar: avatarUrl.isEmpty ? null : avatarUrl,
        highlightMessageId: messageId.isEmpty ? null : messageId,
      );
    } else if (isGroup) {
      screen = GroupChatScreen(
        chatId: chatId,
        groupName: chatName.isNotEmpty ? chatName : null,
        groupAvatar: avatarUrl.isEmpty ? null : avatarUrl,
        initialMessageId: messageId.isEmpty ? null : messageId,
      );
    } else {
      screen = PrivateChatScreen(
        chatId: chatId,
        otherUserName: chatName.isNotEmpty ? chatName : null,
        otherUserAvatar: avatarUrl.isEmpty ? null : avatarUrl,
        initialMessageId: messageId.isEmpty ? null : messageId,
      );
    }
    navState.push(SwipeBackPageRoute(builder: (_) => screen));
  }

  Future<void> _openAppUpdate(Map<String, dynamic> data) async {
    if (!isMainScreenReady) {
      _pendingNotificationData = data;
      return;
    }
    final context = DeepLinkService().navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      _pendingNotificationData = data;
      Future<void>.delayed(const Duration(milliseconds: 300), () {
        if (_pendingNotificationData != null && isMainScreenReady) consumePendingNotification();
      });
      return;
    }
    final AppUpdateInfo update;
    if (data['download_url']?.toString().isNotEmpty == true &&
        data['latest_version']?.toString().isNotEmpty == true) {
      update = AppUpdateInfo.fromJson(data);
    } else {
      update = await AppUpdateService.instance.checkForUpdate(silent: false);
    }
    if (update.hasUpdate && context.mounted) {
      UpdateDialog.show(context, update, isManual: true);
    }
  }

  // ======================= Diagnostics =======================

  /// Shows a local system notification and asks the server to send a real push
  /// (POST /api/notifications/test) to verify the push channel end-to-end.
  Future<Map<String, dynamic>> sendTestNotification() async {
    final test = ChatMessageNotification(
      chatId: '0',
      chatName: 'Theaver',
      senderName: 'Тест',
      text: 'Тестовое уведомление доставлено успешно!',
      messageId: 'test_${DateTime.now().millisecondsSinceEpoch}',
    );
    await _presentChatMessage(test);

    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': true, 'message': 'Локальное уведомление показано (вход не выполнен)'};
      }
      final response = await Dio().post(
        '${AppConfig.baseUrl}/api/notifications/test',
        options: Options(headers: <String, String>{
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/json',
        }),
      );
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data;
        final success = data['success'] == true;
        final msg = data['message'] ?? (success ? 'Push отправлен сервером' : 'Ошибка отправки');
        final deviceCount = data['device_count'] ?? 0;
        return {
          'success': success,
          'message': '$msg (устройств: $deviceCount, push: ${_detector.serviceType.name}, '
              'токен ${_pushAvailable ? 'зарегистрирован' : 'отсутствует'})',
          'device_count': deviceCount,
        };
      }
      return {'success': false, 'message': 'Сервер ответил со статусом ${response.statusCode}'};
    } catch (e) {
      return {'success': true, 'message': 'Локальное уведомление показано. Ответ сервера: $e'};
    }
  }

  void dispose() {
    _wsSubscription?.cancel();
  }
}
