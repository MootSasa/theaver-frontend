import '../../utils/image_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'dart:async';

import '../../utils/haptic_utils.dart';
import '../../screens/chat/create_private_chat_screen.dart';
import '../../screens/chat/create_group_screen.dart';
import '../../screens/chat/create_channel_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../screens/settings/profile_screen.dart';
import '../../screens/chat/private_chat_screen.dart';
import '../../screens/chat/group_chat_screen.dart';
import '../../screens/chat/channel_screen.dart';
import '../../screens/chat/system_notifications_screen.dart';
import '../../services/search_service.dart';
import '../../services/auth_service.dart';
import '../../services/chat_service.dart';
import '../../services/websocket_service.dart';
import '../../services/local_storage_service.dart';
import '../../services/account_manager.dart';
import '../../services/profile_theme_provider.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/unread_count_provider.dart';
import '../../screens/auth/login_screen.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/user/avatar_with_status.dart';
import '../../widgets/chat/liquid_glass_filter_chips.dart';
import '../../widgets/chat/liquid_glass_bottom_bar.dart';
import '../../widgets/chat/liquid_glass_app_bar.dart';
import '../../widgets/chat/classic_bottom_bar.dart';
import '../../widgets/settings/settings_group.dart';
import '../../services/sync_service.dart';
import '../../services/database/app_database.dart';
import 'package:drift/drift.dart' show Value;
import '../../utils/swipe_back_route.dart';
import '../../utils/date_time_utils.dart';
import '../../services/update_service.dart';
import '../settings/widgets/update_dialog.dart';
import '../../widgets/chat/round_video_thumbnail.dart';
import '../../widgets/notifications/notification_permission_dialog.dart';
import '../../services/notification_service.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> with WidgetsBindingObserver {
  int _currentIndex = 1; // 0: Settings, 1: Chats, 2: Search
  int _activeFilter = 0; // 0: Все, 1: Личные, 2: Группы, 3: Каналы

  // PageController для свайпа между Настройками и Чатами
  final PageController _pageController = PageController(initialPage: 1);

  // Search functionality
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  // Chats list
  List<Chat> _chats = [];
  bool _isLoadingChats = true;

  // Multi-select mode
  bool _isSelectMode = false;
  Set<String> _selectedChatIds = {};

  // Search results
  List<SearchResultUser> _users = [];
  List<SearchResultGroup> _groups = [];
  List<SearchResultChannel> _channels = [];
  List<SearchResultMessage> _messages = [];

  // Loading states
  bool _isLoading = false;

  // Account manager
  final AccountManager _accountManager = AccountManager();

  // WebSocket
  final WebSocketService _wsService = WebSocketService();
  StreamSubscription<WebSocketEvent>? _wsSubscription;
  bool _isWsConnected = false;
  Timer? _connectionCheckTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _searchController.addListener(_onSearchChanged);

    // Инициализация: сначала Drift, потом загрузка чатов и WebSocket
    _initApp();

    // Listen to UnreadCountProvider changes to sync _chats list
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final provider = context.read<UnreadCountProvider>();
        provider.addListener(_onUnreadCountProviderChanged);
      } catch (_) {}
      NotificationService().isMainScreenReady = true;
      NotificationService().consumePendingNotification();
    });
  }

  /// Последовательная инициализация: Drift → чаты → WebSocket
  Future<void> _initApp() async {
    // 1. Инициализация Drift (обязательно до _loadChats!)
    await _initOfflineFirst();

    // 2. Загрузка чатов (теперь Drift уже инициализирован)
    _loadChats();

    // 3. WebSocket (параллельно, не блокирует UI)
    _initWebSocket();
    _startConnectionCheck();

    // 4. Проверка обновлений в фоне
    _checkForUpdates();

    // 5. Запрос разрешения на уведомления при первом входе
    _checkNotificationPermission();
  }

  Future<void> _checkNotificationPermission() async {
    // Небольшая задержка, чтобы дать экрану полностью отрендериться
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    await NotificationPermissionDialog.checkAndPrompt(context);
  }

  Future<void> _checkForUpdates() async {
    try {
      final isAutoCheck = await AppUpdateService.instance.isAutoCheckEnabled();
      if (!isAutoCheck) return;

      // Небольшая задержка, чтобы не забивать сеть в момент первичной отрисовки UI
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;

      final update = await AppUpdateService.instance.checkForUpdate(silent: true);
      if (!mounted) return;

      if (update.hasUpdate) {
        UpdateDialog.show(context, update, isManual: false);
      }
    } catch (e) {
      debugPrint('MainScreen: Background update check error: $e');
    }
  }

  Future<void> _initOfflineFirst() async {
    try {
      final syncService = SyncService();
      await syncService.initialize();
      debugPrint('MainScreen: SyncService initialized');
    } catch (e) {
      debugPrint('MainScreen: SyncService init error: $e');
      // Continue without offline support
    }
  }

  void _startConnectionCheck() {
    // Check connection status every 5 seconds
    _connectionCheckTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      final isConnected = _wsService.isConnected;
      if (isConnected != _isWsConnected) {
        setState(() {
          _isWsConnected = isConnected;
        });
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Reload chats when returning to this screen (e.g., after account switch)
    // This ensures chats are refreshed when navigating back
    if (_chats.isEmpty && !_isLoadingChats) {
      _loadChats();
    }
  }

  Future<void> _initWebSocket() async {
    // Subscribe to WebSocket events BEFORE connecting,
    // so we don't miss the 'connected' event from the broadcast stream.
    _wsSubscription = _wsService.eventStream.listen(_handleWebSocketEvent);

    // Subscribe to specific events
    _wsService.subscribe(WebSocketEventType.newChat, _onNewChat);
    _wsService.subscribe(WebSocketEventType.newMessage, _onNewMessage);
    _wsService.subscribe(WebSocketEventType.chatUpdate, _onChatUpdate);
    _wsService.subscribe(WebSocketEventType.connected, _onWsConnected);
    _wsService.subscribe(WebSocketEventType.messageRead, _onMessageRead);
    _wsService.subscribe(
        WebSocketEventType.unreadCountUpdated, _onUnreadCountUpdated);
    _wsService.subscribe(WebSocketEventType.userStatus, _onUserStatus);
    _wsService.subscribe(WebSocketEventType.messageDeleted, _onMessageDeleted);
    _wsService.subscribe(WebSocketEventType.userAvatarUpdated, _onUserAvatarUpdated);
    _wsService.subscribe(WebSocketEventType.userAppearanceUpdated, _onUserAppearanceUpdated);

    // Now connect — the 'connected' event will be caught by our listeners
    await _wsService.connect();

    // If already connected after connect(), sync state immediately
    // (in case the broadcast event was still missed)
    if (_wsService.isConnected && mounted) {
      setState(() => _isWsConnected = true);
    }
  }

  void _handleWebSocketEvent(WebSocketEvent event) {
    // Update connection status
    if (event.type == WebSocketEventType.connected) {
      setState(() => _isWsConnected = true);
    }
    // Note: WebSocket disconnection is handled by the WebSocketService
    // which sets _isConnected to false internally. We check _wsService.isConnected
    // periodically or on state changes.
  }

  void _onWsConnected(WebSocketEvent event) {
    debugPrint('WebSocket connected: ${event.data}');
    if (mounted) {
      setState(() => _isWsConnected = true);
      _loadChats();

      // Delta Sync при переподключении (мульти-девайс)
      try {
        SyncService().syncFromServer();
      } catch (_) {}
    }
  }

  void _onNewChat(WebSocketEvent event) {
    debugPrint('New chat received: ${event.data}');
    // The event data contains the chat info directly (chat_id, name, chat_type, etc.)
    // or wrapped in a 'chat' field
    Map<String, dynamic>? chatData;
    if (event.data.containsKey('chat')) {
      chatData = event.data['chat'] as Map<String, dynamic>?;
    } else if (event.data.containsKey('chat_id')) {
      // Use the event data directly as chat data
      chatData = event.data;
    }

    if (chatData != null) {
      final newChat = Chat.fromJson(chatData);
      if (mounted) {
        setState(() {
          // Check if chat already exists
          final existingIndex = _chats.indexWhere((c) => c.id == newChat.id);
          if (existingIndex == -1) {
            // Add new chat at the beginning of the list
            _chats.insert(0, newChat);
          } else {
            // Update existing chat
            _chats[existingIndex] = newChat;
            // Move to top
            _chats.removeAt(existingIndex);
            _chats.insert(0, newChat);
          }
        });
        // Save to local storage
        _localStorage.saveChats(_chats);
      }
    } else {
      // Fallback: reload if no chat data provided
      _loadChats();
    }
  }

  void _onNewMessage(WebSocketEvent event) {
    debugPrint('New message received: ${event.data}');
    final chatId = event.data['chat_id']?.toString();
    final messageData = event.data['message'] as Map<String, dynamic>?;
    final senderId = messageData?['sender_id']?.toString();

    if (chatId != null && mounted) {
      // NOTE: UnreadCountProvider already increments via its own _onNewMessage
      // subscriber (initialized in initialize()). Do NOT call provider.increment()
      // here — that would cause double-counting.

      final chatIndex = _chats.indexWhere((c) => c.id == chatId);
      setState(() {
        // Find the chat and update it
        if (chatIndex != -1) {
          final chat = _chats[chatIndex];

          // Get unread count from provider (authoritative, already incremented)
          int newUnreadCount = chat.unreadCount;
          try {
            newUnreadCount =
                context.read<UnreadCountProvider>().getCount(chatId);
          } catch (_) {
            // Fallback: increment manually if provider not available
            final currentUserId = _wsService.currentUserId;
            final isFromMe = senderId != null && senderId == currentUserId;
            newUnreadCount = isFromMe ? chat.unreadCount : chat.unreadCount + 1;
          }

          final msgType = messageData?['message_type'] as String?;
          final isRound = messageData?['is_round'] == true || msgType == 'round';
          final fileUrl = messageData?['file_url'] as String?;
          final updatedChat = chat.copyWith(
            lastMessage: messageData?['content'] as String? ?? chat.lastMessage,
            lastMessageTime:
                messageData?['created_at'] as String? ?? chat.lastMessageTime,
            lastMessageType: msgType ?? chat.lastMessageType,
            lastMessageIsRound: isRound || chat.lastMessageIsRound,
            lastMessageFileUrl: fileUrl ?? chat.lastMessageFileUrl,
            updatedAt: messageData?['created_at'] as String? ?? chat.updatedAt,
            unreadCount: newUnreadCount,
          );
          // Update the chat in place
          _chats[chatIndex] = updatedChat;
          // Re-sort: pinned/saved chats stay in their fixed positions,
          // unpinned chats sort by updated_at
          _sortChats();
        }
      });
      // Save to local storage
      _localStorage.saveChats(_chats);

      // Сохранить в Drift
      final db = AppDatabase();
      try {
        if (chatIndex != -1) {
          db.saveChat(_chatToCompanion(_chats[chatIndex]));
        }
      } catch (_) {}
    }
  }

  void _onChatUpdate(WebSocketEvent event) {
    debugPrint('Chat update received: ${event.data}');
    final chatData = event.data['chat'] as Map<String, dynamic>?;
    final chatId = event.data['chat_id']?.toString();

    if (chatId != null && mounted) {
      setState(() {
        final chatIndex = _chats.indexWhere((c) => c.id == chatId);
        if (chatIndex != -1) {
          if (chatData != null) {
            // Update with new data
            final updatedChat = Chat.fromJson(chatData);
            _chats[chatIndex] = updatedChat;
          }
          // Re-sort instead of blindly moving to top,
          // so pinned chats keep their fixed positions
          _sortChats();
        }
      });
      // Save to local storage
      _localStorage.saveChats(_chats);
    }
  }

  void _onMessageRead(WebSocketEvent event) {
    // This event is sent to the SENDER of messages to notify that their messages were read.
    // It should NOT be used to update unread_count on the chat list.
    // Unread count is updated via the unreadCountUpdated event instead.
    // We only use this to update the isRead status of our sent messages in chat screens.
    debugPrint(
        'Message read event received (sender notification): ${event.data}');
  }

  /// Handle unread count updates from the server — the authoritative source for unread counts
  void _onUnreadCountUpdated(WebSocketEvent event) {
    debugPrint('Unread count updated: ${event.data}');
    final chatId = event.data['chat_id']?.toString();
    final unreadCount = event.data['unread_count'] as int? ?? 0;

    if (chatId != null && mounted) {
      try {
        context.read<UnreadCountProvider>().setCount(chatId, unreadCount);
      } catch (_) {}

      _syncChatUnreadCount(chatId, unreadCount);
    }
  }

  /// Handle real-time presence changes for mutual contacts in chat list
  void _onUserStatus(WebSocketEvent event) {
    final userId = event.data['user_id']?.toString();
    final isOnline = event.data['is_online'] == true;
    final lastSeen = event.data['last_seen'] != null
        ? DateTimeUtils.parseUtcDateTime(event.data['last_seen'])
            ?.toIso8601String()
        : null;

    if (userId != null && mounted) {
      setState(() {
        for (int i = 0; i < _chats.length; i++) {
          if (_chats[i].chatType == 'private' &&
              _chats[i].otherUserId == userId) {
            _chats[i] = _chats[i].copyWith(
              isOnline: isOnline,
              lastSeen: lastSeen ??
                  (isOnline ? null : DateTime.now().toIso8601String()),
            );
          }
        }
      });
    }
  }

  /// Handle real-time avatar updates for current user or contacts
  void _onUserAvatarUpdated(WebSocketEvent event) {
    final userId = event.data['user_id']?.toString();
    final avatarUrl = event.data['avatar_url']?.toString();
    if (userId == null) return;

    debugPrint('[MainScreen] user_avatar_updated for user $userId: $avatarUrl');

    // Evict cached images from memory for immediate visual update
    PaintingBinding.instance.imageCache.clear();
    PaintingBinding.instance.imageCache.clearLiveImages();

    final currentAccount = _accountManager.currentAccount;
    final isMe = currentAccount != null && currentAccount.userId == userId;

    if (isMe) {
      _accountManager.updateAccountProfile(
        userId,
        avatarUrl: avatarUrl,
      );
    }

    if (mounted) {
      setState(() {
        for (int i = 0; i < _chats.length; i++) {
          if (_chats[i].chatType == 'private' && _chats[i].otherUserId == userId) {
            _chats[i] = _chats[i].copyWith(avatarUrl: avatarUrl);
          } else if (isMe && _chats[i].chatType == 'saved') {
            _chats[i] = _chats[i].copyWith(avatarUrl: avatarUrl);
          }
        }
      });
      _localStorage.saveChats(_chats);
    }

    try {
      AppDatabase().updateUserAvatarInChats(userId, avatarUrl);
    } catch (_) {}
  }

  /// Handle real-time appearance settings changes (sync across devices)
  void _onUserAppearanceUpdated(WebSocketEvent event) {
    final userId = event.data['user_id']?.toString();
    final currentAccount = _accountManager.currentAccount;
    if (currentAccount != null && currentAccount.userId == userId && mounted) {
      context.read<ProfileThemeProvider>().init();
    }
  }

  void _onMessageDeleted(WebSocketEvent event) {
    debugPrint('Message deleted received in MainScreen: ${event.data}');
    final chatId = event.data['chat_id']?.toString();
    final messageId =
        (event.data['message_id'] ?? event.data['messageId'])?.toString();
    if (chatId != null) {
      if (messageId != null) {
        try {
          AppDatabase().deleteMessage(messageId);
        } catch (_) {}
      }
      if (mounted) {
        _refreshChatLastMessage(chatId);
      }
    }
  }

  Future<void> _refreshChatLastMessage(String chatId) async {
    try {
      final db = AppDatabase();
      final lastMsg = await db.getLastMessageForChat(chatId);
      if (!mounted) return;
      final chatIndex = _chats.indexWhere((c) => c.id == chatId);
      if (chatIndex != -1) {
        setState(() {
          final chat = _chats[chatIndex];
          _chats[chatIndex] = chat.copyWith(
            lastMessage: (lastMsg != null && lastMsg.content.isNotEmpty)
                ? lastMsg.content
                : chat.lastMessage,
            lastMessageTime: (lastMsg != null && lastMsg.createdAt.isNotEmpty)
                ? lastMsg.createdAt
                : chat.lastMessageTime,
            lastMessageType: lastMsg?.messageType ?? chat.lastMessageType,
            lastMessageIsRound: lastMsg?.isRound ?? chat.lastMessageIsRound,
            lastMessageFileUrl: lastMsg?.fileUrl ?? chat.lastMessageFileUrl,
            updatedAt: (lastMsg != null && lastMsg.createdAt.isNotEmpty)
                ? lastMsg.createdAt
                : chat.updatedAt,
          );
        });
        _localStorage.saveChats(_chats);
      }
    } catch (e) {
      debugPrint('Error refreshing last message for chat $chatId: $e');
    }
  }

  /// Sync unread count from UnreadCountProvider to _chats list.
  /// Called when the provider changes (e.g. user reads messages in a chat).
  void _onUnreadCountProviderChanged() {
    if (!mounted) return;
    try {
      final provider = context.read<UnreadCountProvider>();
      bool changed = false;
      for (int i = 0; i < _chats.length; i++) {
        final providerCount = provider.getCount(_chats[i].id);
        if (_chats[i].unreadCount != providerCount) {
          _chats[i] = _chats[i].copyWith(unreadCount: providerCount);
          changed = true;
        }
      }
      if (changed) {
        setState(() {});
        _localStorage.saveChats(_chats);
      }
    } catch (_) {}
  }

  /// Update a single chat's unread count in _chats and persist
  void _syncChatUnreadCount(String chatId, int unreadCount) {
    setState(() {
      final chatIndex = _chats.indexWhere((c) => c.id == chatId);
      if (chatIndex != -1) {
        _chats[chatIndex] =
            _chats[chatIndex].copyWith(unreadCount: unreadCount);
      }
    });

    // Сохранить в Drift
    final db = AppDatabase();
    try {
      db.updateUnreadCount(chatId, unreadCount);
    } catch (_) {}

    _localStorage.saveChats(_chats);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // При возврате из фона: восстановить статус активного чата,
      // переподключить WS если не подключён, затем обновить чаты
      NotificationService().onAppResume();
      if (!_isWsConnected) {
        _wsService.tryReconnect();
        _loadChats();
      }
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      // При уходе в фон: снять подавление push-уведомлений для этого устройства
      NotificationService().onAppPause();
    }
  }

  // Local storage service
  final LocalStorageService _localStorage = LocalStorageService();

  Future<void> _loadChats({bool silent = false}) async {
    final bool isInitialLoad = _chats.isEmpty;
    if (isInitialLoad && !silent) {
      setState(() => _isLoadingChats = true);
    }

    final db = AppDatabase();
    bool loadedFromLocal = false;

    // 1. При холодном старте (когда _chats ещё пуст) мгновенно загрузить из локального кэша
    if (isInitialLoad) {
      try {
        final localChats = await db.getChats();
        if (localChats.isNotEmpty && mounted) {
          setState(() {
            _chats = localChats.map(_dbChatToChat).toList();
            _isLoadingChats = false;
          });
          _sortChats();
          loadedFromLocal = true;
          debugPrint('MainScreen: Loaded ${localChats.length} chats from Drift');
        }
      } catch (e) {
        debugPrint('MainScreen: Error loading from Drift: $e');
      }

      // 2. Fallback: SharedPreferences если Drift пуст
      if (!loadedFromLocal) {
        try {
          final prefsChats = await _localStorage.loadChats();
          if (prefsChats.isNotEmpty && mounted) {
            setState(() {
              _chats = prefsChats;
              _isLoadingChats = false;
            });
            _sortChats();
            loadedFromLocal = true;
            debugPrint('MainScreen: Loaded ${prefsChats.length} chats from SharedPreferences');
          }
        } catch (e) {
          debugPrint('MainScreen: Error loading from SharedPreferences: $e');
        }
      }
    }

    // 3. Фоновая загрузка с сервера (бесшовное обновление)
    try {
      final result = await ChatService.getChats();

      if (mounted) {
        setState(() {
          _isLoadingChats = false;
          if (result['success'] == true) {
            _chats = result['chats'] as List<Chat>;
            _sortChats();

            // Сохранить в Drift для offline-доступа
            try {
              final chatModels = _chats.map(_chatToCompanion).toList();
              db.saveChats(chatModels);
            } catch (e) {
              debugPrint('MainScreen: Error saving to Drift: $e');
            }

            // Сохранить в SharedPreferences как fallback
            _localStorage.saveChats(_chats);

            // Обновить провайдер
            try {
              context.read<UnreadCountProvider>().loadFromChats(_chats);
            } catch (_) {}
          } else {
            debugPrint('Failed to load chats: ${result['message']}');
            if (result['message'] == 'Not authenticated') {
              _chats = [];
              _localStorage.clearUserData();
            }
          }
        });
      }
    } catch (e) {
      debugPrint('MainScreen: Error loading from server: $e');
      // Сервер недоступен — оставляем текущие данные
      if (mounted) {
        setState(() => _isLoadingChats = false);
        if (_chats.isEmpty && !loadedFromLocal) {
          try {
            final prefsChats = await _localStorage.loadChats();
            if (prefsChats.isNotEmpty) {
              setState(() {
                _chats = prefsChats;
              });
              _sortChats();
              debugPrint('MainScreen: Fallback — loaded ${prefsChats.length} chats from SharedPreferences');
            }
          } catch (_) {}
        }
      }
    }

    // Всегда проверять существование Избранного локально (даже оффлайн)
    await _ensureSavedChatExists();
  }

  /// Ensure "Saved Messages" / "Favorites" chat exists
  Future<void> _ensureSavedChatExists() async {
    try {
      final userId = await AuthService.getUserId();
      if (userId != null) {
        final db = AppDatabase();
        await db.ensureSavedChatExists(userId);
      }

      // Check if saved chat already exists in local list
      final hasSavedChat = _chats.any((c) => c.chatType == 'saved');
      debugPrint('hasSavedChat: $hasSavedChat, chats count: ${_chats.length}');

      if (!hasSavedChat) {
        // If not in _chats but might be in DB (just created or already there), reload from DB
        try {
          final dbChats = await AppDatabase().getChats();
          if (dbChats.isNotEmpty && mounted) {
            setState(() {
              _chats = dbChats.map(_dbChatToChat).toList();
            });
            _sortChats();
          }
        } catch (_) {}
      }

      // Secondary sync: Request saved chat from server
      debugPrint('Requesting saved chat from server for sync...');
      final result = await ChatService.getOrCreateSavedChat();
      debugPrint('Saved chat result: $result');

      if (result['success'] == true && result['chat'] != null) {
        final savedChat = result['chat'] as Chat;
        debugPrint(
            'Got saved chat: ${savedChat.id}, name: ${savedChat.name}');

        if (userId != null) {
          await AppDatabase().migrateSavedChatId('saved_$userId', savedChat.id);
        }

        // Add to list if not already present
        if (!_chats.any((c) => c.id == savedChat.id)) {
          if (mounted) {
            setState(() {
              _chats.insert(0, savedChat);
              _sortChats();
              _localStorage.saveChats(_chats);
            });
          }
          debugPrint('Added saved chat to list');
        }
      } else {
        debugPrint('Failed to get saved chat: ${result['message']}');
      }
    } catch (e) {
      debugPrint('Error ensuring saved chat exists: $e');
    }
  }

  /// Конвертация DbChat (Drift) → Chat (для UI)
  Chat _dbChatToChat(DbChat model) {
    return Chat(
      id: model.chatId,
      chatType: model.chatType,
      name: model.name,
      avatarUrl: model.avatarUrl,
      lastMessage: model.lastMessage,
      lastMessageTime: model.lastMessageTime,
      updatedAt: model.updatedAt,
      unreadCount: model.unreadCount,
      isOnline: model.isOnline,
      lastSeen: model.lastSeen,
      isPinned: model.isPinned,
    );
  }

  /// Конвертация Chat (UI) → ChatsCompanion (Drift)
  ChatsCompanion _chatToCompanion(Chat chat) {
    return ChatsCompanion(
      chatId: Value(chat.id),
      chatType: Value(chat.chatType),
      name: Value(chat.name),
      avatarUrl: Value(chat.avatarUrl),
      lastMessage: Value(chat.lastMessage),
      lastMessageTime: Value(chat.lastMessageTime),
      updatedAt: Value(chat.updatedAt),
      unreadCount: Value(chat.unreadCount),
      isOnline: Value(chat.isOnline),
      lastSeen: Value(chat.lastSeen),
      isPinned: Value(chat.isPinned),
    );
  }

  @override
  void dispose() {
    NotificationService().isMainScreenReady = false;
    WidgetsBinding.instance.removeObserver(this);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _pageController.dispose();
    _wsSubscription?.cancel();
    _connectionCheckTimer?.cancel();
    // Don't disconnect WebSocket on dispose - it's a singleton and should stay connected
    // for the entire app lifecycle. Only unsubscribe OUR callbacks (not UnreadCountProvider's!).
    // Using unsubscribe() instead of unsubscribeAll() to avoid wiping other subscribers.
    _wsService.unsubscribe(WebSocketEventType.newChat, _onNewChat);
    _wsService.unsubscribe(WebSocketEventType.newMessage, _onNewMessage);
    _wsService.unsubscribe(WebSocketEventType.chatUpdate, _onChatUpdate);
    _wsService.unsubscribe(WebSocketEventType.connected, _onWsConnected);
    _wsService.unsubscribe(WebSocketEventType.messageRead, _onMessageRead);
    _wsService.unsubscribe(WebSocketEventType.unreadCountUpdated, _onUnreadCountUpdated);
    _wsService.unsubscribe(WebSocketEventType.userStatus, _onUserStatus);
    _wsService.unsubscribe(WebSocketEventType.messageDeleted, _onMessageDeleted);
    _wsService.unsubscribe(WebSocketEventType.userAvatarUpdated, _onUserAvatarUpdated);
    _wsService.unsubscribe(WebSocketEventType.userAppearanceUpdated, _onUserAppearanceUpdated);
    // Remove UnreadCountProvider listener
    try {
      context.read<UnreadCountProvider>().removeListener(_onUnreadCountProviderChanged);
    } catch (_) {}
    super.dispose();
  }

  void _onSearchChanged() {
    final newQuery = _searchController.text;
    if (newQuery != _searchQuery) {
      setState(() {
        _searchQuery = newQuery;
      });
      _performSearch();
    }
  }

  Future<void> _performSearch() async {
    if (_searchQuery.isEmpty) {
      setState(() {
        _users = [];
        _groups = [];
        _channels = [];
        _messages = [];
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final users = await SearchService.searchUsers(query: _searchQuery);
      final groups = await SearchService.searchGroups(query: _searchQuery);
      final channels = await SearchService.searchChannels(query: _searchQuery);
      final messages = await SearchService.searchMessages(query: _searchQuery);

      if (mounted) {
        setState(() {
          _users = users;
          _groups = groups;
          _channels = channels;
          _messages = messages;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Метод для получения общего количества непрочитанных
  int _getTotalUnreadCount() {
    try {
      return context.read<UnreadCountProvider>().totalUnread;
    } catch (_) {
      return _chats.fold(0, (sum, chat) => sum + chat.unreadCount);
    }
  }

  void _onTabTapped(int index) {
    // Закрываем клавиатуру при уходе с поиска
    if (_currentIndex == 2 && index != 2) {
      _searchFocusNode.unfocus();
    }
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _showCreateMenu() {
    final l10n = context.l10n;

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_add, color: Color(0xFF0088CC)),
              title: Text(l10n.translate('chat_new_private')),
              subtitle: Text(l10n.translate('chat_new_private_desc')),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  SwipeBackPageRoute(
                      builder: (_) => const CreatePrivateChatScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.group_add, color: Color(0xFF0088CC)),
              title: Text(l10n.translate('chat_new_group')),
              subtitle: Text(l10n.translate('chat_new_group_desc')),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  SwipeBackPageRoute(builder: (_) => const CreateGroupScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.campaign, color: Color(0xFF0088CC)),
              title: Text(l10n.translate('chat_new_channel')),
              subtitle: Text(l10n.translate('chat_new_channel_desc')),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  SwipeBackPageRoute(
                      builder: (_) => const CreateChannelScreen()),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  void _showProfileMenu() {
    final l10n = context.l10n;
    final totalUnread = _getTotalUnreadCount();

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person, color: Color(0xFF0088CC)),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.translate('menu_profile')),
                  if (totalUnread > 0)
                    Text(
                      '$totalUnread ${l10n.translate('menu_unread')}',
                      style: const TextStyle(
                          fontSize: 12, color: Color(0xFF0088CC)),
                    ),
                ],
              ),
              onTap: () async {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  SwipeBackPageRoute(
                    builder: (_) => const ProfileScreen(),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.settings, color: Color(0xFF0088CC)),
              title: Text(l10n.translate('menu_settings')),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  SwipeBackPageRoute(builder: (_) => const SettingsScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: Colors.red),
              title: Text(l10n.translate('menu_logout')),
              onTap: () async {
                Navigator.pop(context);
                await AuthService.logout();
                if (!mounted) return;
                // ignore: use_build_context_synchronously
                Navigator.of(context).pushAndRemoveUntil(
                  SwipeBackPageRoute(builder: (_) => const LoginScreen()),
                  (route) => false,
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  /// Calculate number of chats with unread messages for a specific filter index
  int _getUnreadCountForFilter(int filterIndex) {
    return _chats.where((chat) {
      // First filter by chat type
      bool matchesFilter = true;
      switch (filterIndex) {
        // "Личные" filter includes both 'private' and 'saved' chats,
        // since "Избранное" belongs to the personal chats category
        case 1:
          matchesFilter =
              chat.chatType == 'private' || chat.chatType == 'saved';
          break;
        case 2:
          matchesFilter = chat.chatType == 'group';
          break;
        case 3:
          matchesFilter = chat.chatType == 'channel';
          break;
        default:
          matchesFilter = true;
      }
      // Then check if chat has unread messages
      return matchesFilter && chat.unreadCount > 0;
    }).length;
  }

  Widget _buildChatList({double topPadding = 8}) {
    final l10n = context.l10n;

    if (_isLoadingChats) {
      // Use topPadding so the indicator is visible below the glass AppBar
      return Padding(
        padding: EdgeInsets.only(top: topPadding),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    // Filter chats based on active filter
    List<Chat> filteredChats = _chats.where((chat) {
      // Always include saved chat
      if (chat.chatType == 'saved') return true;
      switch (_activeFilter) {
        case 1:
          return chat.chatType == 'private';
        case 2:
          return chat.chatType == 'group';
        case 3:
          return chat.chatType == 'channel';
        default:
          return true;
      }
    }).toList();

    if (filteredChats.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.chat_bubble_outline,
              size: 80,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              l10n.translate('chat_no_chats'),
              style: TextStyle(
                fontSize: 24,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.translate('chat_start_new'),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.only(top: topPadding, bottom: 120),
      itemCount: filteredChats.length,
      itemBuilder: (context, index) {
        final chat = filteredChats[index];
        return _buildChatListItem(chat);
      },
    );
  }

  Widget _buildChatListItem(Chat chat) {
    IconData icon;
    switch (chat.chatType) {
      case 'private':
        icon = Icons.person;
        break;
      case 'group':
        icon = Icons.group;
        break;
      case 'channel':
        icon = Icons.campaign;
        break;
      case 'saved':
        icon = Icons.bookmark;
        break;
      case 'system':
        icon = Icons.shield_outlined;
        break;
      default:
        icon = Icons.chat;
    }

    final hasUnread = chat.unreadCount > 0;
    final isPrivateChat = chat.chatType == 'private';
    final isSelected = _selectedChatIds.contains(chat.id);

    Widget leadingWidget;
    if (_isSelectMode) {
      // In select mode: show checkbox instead of avatar
      leadingWidget = Checkbox(
        value: isSelected,
        onChanged: (_) => _toggleChatSelection(chat.id),
        activeColor: const Color(0xFF0088CC),
      );
    } else {
      leadingWidget = Stack(
        children: [
          if (isPrivateChat)
            AvatarWithStatus(
              avatarUrl: chat.avatarUrl,
              name: chat.name,
              radius: 22,
              isOnline: chat.isOnline,
            )
          else
            CircleAvatar(
              backgroundColor: const Color(0xFF0088CC),
              backgroundImage:
                  chat.avatarUrl != null && chat.avatarUrl!.isNotEmpty
                      ? avatarImageProvider(chat.avatarUrl)
                      : null,
              child: chat.avatarUrl == null || chat.avatarUrl!.isEmpty
                  ? Icon(icon, color: Colors.white)
                  : null,
            ),
          if (hasUnread)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                ),
                constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                child: Text(
                  chat.unreadCount > 99 ? '99+' : chat.unreadCount.toString(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      );
    }

    return Container(
      color:
          isSelected ? const Color(0xFF0088CC).withValues(alpha: 0.08) : null,
      child: ListTile(
        onLongPress: () {
          HapticUtils.impact();
          if (_isSelectMode) {
            // Long press on a selected chat in select mode shows the batch menu
            if (isSelected) {
              _showSelectedChatsMenu();
            } else {
              _toggleChatSelection(chat.id);
            }
          } else {
            // Enter select mode and select this chat
            _enterSelectMode(chat.id);
          }
        },
        onTap: () {
          if (_isSelectMode) {
            HapticUtils.selection();
            _toggleChatSelection(chat.id);
          } else {
            HapticUtils.tap();
            _openChat(chat);
          }
        },
        leading: leadingWidget,
        title: Row(
          children: [
            if (chat.isPinned || chat.chatType == 'saved')
              Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Icon(
                  Icons.push_pin,
                  size: 14,
                  color: hasUnread
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey[500],
                ),
              ),
            Expanded(
              child: Row(
                children: [
                  Flexible(
                    child: Text(
                      chat.name,
                      style: TextStyle(
                        fontWeight: hasUnread ? FontWeight.w600 : FontWeight.w500,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (chat.chatType == 'system') ...[
                    const SizedBox(width: 4),
                    const Icon(Icons.verified, size: 16, color: Color(0xFF0088CC)),
                  ],
                ],
              ),
            ),
          ],
        ),
        subtitle: _buildChatSubtitle(chat, hasUnread),
        trailing: _isSelectMode
            ? (isSelected
                ? const Icon(Icons.check_circle, color: Color(0xFF0088CC))
                : Icon(Icons.radio_button_unchecked, color: Colors.grey[400]))
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (chat.lastMessageTime != null)
                    Text(
                      _formatChatTime(chat.lastMessageTime!),
                      style: TextStyle(
                        fontSize: 12,
                        color: hasUnread
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[500],
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Widget? _buildChatSubtitle(Chat chat, bool hasUnread) {
    if (chat.isLastMessageRoundVideo) {
      final primary = Theme.of(context).colorScheme.primary;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RoundVideoThumbnail(
            videoUrl: chat.lastMessageFileUrl,
            size: 18,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              AppLocalizations.of(context)?.translate('chat_video_note') ??
                  'Video message',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: primary,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ],
      );
    }

    String? displaySubtitle = chat.lastMessage;
    if (displaySubtitle == null || displaySubtitle.trim().isEmpty) {
      final loc = AppLocalizations.of(context);
      if (chat.lastMessageGroupedId != null &&
          chat.lastMessageGroupedId!.isNotEmpty) {
        displaySubtitle = loc?.translate('chat_album') ?? 'Album';
      } else {
        final msgType = chat.lastMessageType?.toLowerCase();
        if (msgType == 'photo' || msgType == 'image') {
          displaySubtitle = loc?.translate('chat_photo') ?? 'Photo';
        } else if (msgType == 'video') {
          displaySubtitle = loc?.translate('chat_video') ?? 'Video';
        } else if (msgType == 'album') {
          displaySubtitle = loc?.translate('chat_album') ?? 'Album';
        } else if (msgType == 'voice' || msgType == 'audio') {
          displaySubtitle =
              loc?.translate('chat_voice_message') ?? 'Voice message';
        } else if (msgType == 'file') {
          displaySubtitle = loc?.translate('chat_file') ?? 'File';
        }
      }
    }

    if (displaySubtitle == null || displaySubtitle.trim().isEmpty) {
      return null;
    }

    return Text(
      displaySubtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: hasUnread ? Colors.grey[800] : Colors.grey[600],
        fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
      ),
    );
  }

  /// Enter multi-select mode with the given chat pre-selected
  void _enterSelectMode(String chatId) {
    setState(() {
      _isSelectMode = true;
      _selectedChatIds = {chatId};
    });
  }

  /// Exit multi-select mode
  void _exitSelectMode() {
    setState(() {
      _isSelectMode = false;
      _selectedChatIds = {};
    });
  }

  /// Select all chats (respecting current filter)
  void _selectAllChats() {
    setState(() {
      _selectedChatIds = _chats
          .where((chat) {
            // Apply same filter logic as _buildChatList
            if (chat.chatType == 'saved') return true;
            switch (_activeFilter) {
              case 1:
                return chat.chatType == 'private';
              case 2:
                return chat.chatType == 'group';
              case 3:
                return chat.chatType == 'channel';
              default:
                return true;
            }
          })
          .map((c) => c.id)
          .toSet();
    });
  }

  /// Toggle selection of a single chat
  void _toggleChatSelection(String chatId) {
    setState(() {
      if (_selectedChatIds.contains(chatId)) {
        _selectedChatIds.remove(chatId);
        // If no chats selected, exit select mode
        if (_selectedChatIds.isEmpty) {
          _isSelectMode = false;
        }
      } else {
        _selectedChatIds.add(chatId);
      }
    });
  }

  /// Show context menu for selected chats (pin/unpin, mark read, delete)
  void _showSelectedChatsMenu() {
    if (_selectedChatIds.isEmpty) return;

    final selectedChats =
        _chats.where((c) => _selectedChatIds.contains(c.id)).toList();
    final count = selectedChats.length;
    final allPinned =
        selectedChats.every((c) => c.isPinned || c.chatType == 'saved');
    final anyUnread = selectedChats.any((c) => c.unreadCount > 0);
    final hasSavedChat = selectedChats.any((c) => c.chatType == 'saved');
    final deletableChats =
        selectedChats.where((c) => c.chatType != 'saved').toList();

    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Выбрано чатов: $count',
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            const Divider(height: 1),
            // Pin/Unpin
            if (!hasSavedChat || selectedChats.length > 1)
              ListTile(
                leading: Icon(
                  allPinned ? Icons.push_pin : Icons.push_pin_outlined,
                  color: const Color(0xFF0088CC),
                ),
                title: Text(allPinned ? 'Открепить чаты' : 'Закрепить чаты'),
                onTap: () {
                  Navigator.pop(context);
                  _batchTogglePin(selectedChats);
                },
              ),
            // Mark as read
            if (anyUnread)
              ListTile(
                leading: const Icon(Icons.done_all, color: Color(0xFF0088CC)),
                title: const Text('Отметить как прочитанные'),
                onTap: () {
                  Navigator.pop(context);
                  _batchMarkAsRead(selectedChats);
                },
              ),
            // Delete (not for saved chat)
            if (deletableChats.isNotEmpty)
              ListTile(
                leading: const Icon(Icons.delete, color: Colors.red),
                title: Text(
                  'Удалить чаты${hasSavedChat ? ' (кроме Избранного)' : ''}',
                  style: const TextStyle(color: Colors.red),
                ),
                onTap: () {
                  Navigator.pop(context);
                  _batchDeleteChats(deletableChats);
                },
              ),
          ],
        ),
      ),
    );
  }

  /// Batch toggle pin status for selected chats
  Future<void> _batchTogglePin(List<Chat> chats) async {
    final toPin = <Chat>[];
    final toUnpin = <Chat>[];

    for (final chat in chats) {
      if (chat.chatType == 'saved') continue; // Skip saved chat
      if (chat.isPinned) {
        toUnpin.add(chat);
      } else {
        toPin.add(chat);
      }
    }

    int successCount = 0;
    for (final chat in toPin) {
      final result = await ChatService.pinChat(chatId: chat.id);
      if (result['success'] == true) successCount++;
    }
    for (final chat in toUnpin) {
      final result = await ChatService.unpinChat(chatId: chat.id);
      if (result['success'] == true) successCount++;
    }

    if (mounted) {
      setState(() {
        for (final chat in [...toPin, ...toUnpin]) {
          final index = _chats.indexWhere((c) => c.id == chat.id);
          if (index != -1) {
            _chats[index] = chat.copyWith(isPinned: !chat.isPinned);
          }
        }
        _sortChats();
      });
      _exitSelectMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Обновлено $successCount чатов')),
      );
    }
  }

  /// Batch mark selected chats as read
  Future<void> _batchMarkAsRead(List<Chat> chats) async {
    int successCount = 0;
    for (final chat in chats) {
      if (chat.unreadCount > 0) {
        final result = await ChatService.markMessagesAsRead(chatId: chat.id);
        if (result['success'] == true) {
          successCount++;
          if (mounted) {
            setState(() {
              final index = _chats.indexWhere((c) => c.id == chat.id);
              if (index != -1) {
                _chats[index] = chat.copyWith(unreadCount: 0);
              }
            });
          }
        }
      }
    }
    if (mounted) {
      _exitSelectMode();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Отмечено как прочитанное: $successCount чатов')),
      );
    }
  }

  /// Batch delete selected chats
  Future<void> _batchDeleteChats(List<Chat> chats) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Удалить чаты?'),
        content: Text(
            'Выбранные чаты (${chats.length}) будут удалены из вашего списка.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      // Call API to delete/leave each chat
      int deleted = 0;
      int failed = 0;
      for (final chat in chats) {
        final result = await ChatService.deleteChat(chat.id);
        if (result['success'] == true) {
          deleted++;
        } else {
          failed++;
        }
      }

      if (!mounted) return;
      setState(() {
        for (final chat in chats) {
          _chats.removeWhere((c) => c.id == chat.id);
        }
      });
      _exitSelectMode();
      // ignore: use_build_context_synchronously
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(
          failed > 0
              ? 'Удалено: $deleted, ошибка: $failed'
              : 'Удалено чатов: $deleted',
        )),
      );
    }
  }

  void _openChat(Chat chat) {
    // Track currently open chat to avoid incrementing unread for it
    

    switch (chat.chatType) {
      case 'private':
        Navigator.push(
          context,
          SwipeBackPageRoute(
            builder: (_) => PrivateChatScreen(
              chatId: chat.id,
              otherUserName: chat.name,
              otherUserAvatar: chat.avatarUrl,
              otherUserOnline: chat.isOnline,
              otherUserLastSeen:
                  DateTimeUtils.parseUtcDateTime(chat.lastSeen),
              otherUserId: chat.otherUserId,
            ),
          ),
        ).then((_) {
          if (mounted) _refreshChatLastMessage(chat.id);
        });
        break;
      case 'saved':
        // Open saved chat as a special chat with yourself
        Navigator.push(
          context,
          SwipeBackPageRoute(
            builder: (_) => PrivateChatScreen(
              chatId: chat.id,
              otherUserName: 'Избранное',
              otherUserAvatar: null,
            ),
          ),
        ).then((_) {
          if (mounted) _refreshChatLastMessage(chat.id);
        });
        break;
      case 'system':
        Navigator.push(
          context,
          SwipeBackPageRoute(
            builder: (_) => SystemNotificationsScreen(
              chatId: chat.id,
              chatName: chat.name.isNotEmpty
                  ? chat.name
                  : context.l10n.translate('system_notifications_title'),
            ),
          ),
        ).then((_) {
          if (mounted) _refreshChatLastMessage(chat.id);
        });
        break;
      case 'group':
        Navigator.push(
          context,
          SwipeBackPageRoute(
            builder: (_) => GroupChatScreen(
              chatId: chat.id,
              groupName: chat.name,
              groupAvatar: chat.avatarUrl,
            ),
          ),
        ).then((_) {
          if (mounted) _refreshChatLastMessage(chat.id);
        });
        break;
      case 'channel':
        Navigator.push(
          context,
          SwipeBackPageRoute(
            builder: (_) => ChannelScreen(
              channelId: chat.id,
              channelName: chat.name,
              channelAvatar: chat.avatarUrl,
            ),
          ),
        ).then((_) {
          if (mounted) _refreshChatLastMessage(chat.id);
        });
        break;
    }
  }

  String _formatChatTime(String timestamp) {
    try {
      final localDateTime = DateTimeUtils.parseUtcDateTime(timestamp);
      if (localDateTime == null) return '';
      final now = DateTime.now();

      if (DateTimeUtils.isToday(localDateTime, now: now)) {
        return '${localDateTime.hour.toString().padLeft(2, '0')}:${localDateTime.minute.toString().padLeft(2, '0')}';
      } else if (DateTimeUtils.isYesterday(localDateTime, now: now)) {
        return context.l10n.translate('date_yesterday');
      } else {
        final days = DateTimeUtils.startOfDay(now)
            .difference(DateTimeUtils.startOfDay(localDateTime))
            .inDays;
        if (days < 7 && days > 0) {
          return DateTimeUtils.formatWeekday(localDateTime.weekday, context);
        } else {
          return '${localDateTime.day}.${localDateTime.month}';
        }
      }
    } catch (e) {
      return '';
    }
  }

  /// Sort chats: saved first, then pinned (stable), then by updated_at
  void _sortChats() {
    _chats.sort((a, b) {
      // Saved chat always first
      if (a.chatType == 'saved') return -1;
      if (b.chatType == 'saved') return 1;

      // Pinned chats next
      if (a.isPinned && !b.isPinned) return -1;
      if (!a.isPinned && b.isPinned) return 1;

      // Then by updated_at
      return b.updatedAt.compareTo(a.updatedAt);
    });
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Прозрачный статус-бар для бесшовного glass-эффекта
    // PopScope: системный жест «назад» на экране Настроек/Поиска
    // возвращает на главный экран (Чаты), а не закрывает приложение
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
        statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      ),
      child: PopScope(
        canPop: _currentIndex == 1,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _currentIndex != 1) {
            _onTabTapped(1);
          }
        },
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          // Stack: PageView занимает весь экран, нижний бар плавает поверх
          // чтобы glass-эффект преломлял контент под баром
          body: Stack(
            children: [
              // PageView: страница 0 = Настройки, страница 1 = Чаты/Поиск
              // Свайп влево → Настройки, свайп вправо → Чаты
              Positioned.fill(
                child: PageView(
                  controller: _pageController,
                  physics: const BouncingScrollPhysics(),
                  onPageChanged: (page) {
                    // Закрываем клавиатуру при уходе с поиска (свайпом)
                    if (_currentIndex == 2 && page != 2) {
                      _searchFocusNode.unfocus();
                    }
                    setState(() {
                      _currentIndex = page;
                      if (page == 2) {
                        // Поиск — очищаем поле при переходе
                        _searchController.clear();
                        _searchQuery = '';
                        // Клавиатура появляется после завершения перехода
                        WidgetsBinding.instance.addPostFrameCallback((_) {
                          if (mounted) _searchFocusNode.requestFocus();
                        });
                      }
                    });
                  },
                  children: [
                    // Страница 0: Настройки (встроенная)
                    const RepaintBoundary(
                      child: _KeepAlivePage(
                        child: SettingsScreen(isEmbedded: true),
                      ),
                    ),

                    // Страница 1: Чаты
                    RepaintBoundary(
                      child: _KeepAlivePage(
                        child: Consumer<LiquidGlassProvider>(
                          builder: (context, glassProvider, _) {
                            final glassEnabled = glassProvider.enabled;
                            final filters = [
                              l10n.translate('filter_all'),
                              l10n.translate('filter_personal'),
                              l10n.translate('filter_groups'),
                              l10n.translate('filter_channels'),
                            ];
                            final unreadCounts = [
                              _getUnreadCountForFilter(0),
                              _getUnreadCountForFilter(1),
                              _getUnreadCountForFilter(2),
                              _getUnreadCountForFilter(3),
                            ];
                            // === Glass-режим ===
                            // Плавающий glass AppBar + фильтры поверх списка чатов
                            if (glassEnabled) {
                              final statusBarHeight =
                                  MediaQuery.of(context).padding.top;
                              final topBarHeight =
                                  statusBarHeight + kToolbarHeight;
                              const filterAreaHeight = 48.0;
                              // Отступ внутри ListView чтобы первые чаты
                              // были видны ниже стеклянных элементов
                              final chatList = _buildChatList(
                                topPadding: topBarHeight + filterAreaHeight,
                              );

                              return Stack(
                                children: [
                                  // Список чатов заполняет весь экран —
                                  // стеклянные AppBar и фильтры преломляют контент
                                  Positioned.fill(
                                    child: chatList,
                                  ),
                                  // Glass AppBar с заголовком "Miptgram"
                                  Positioned(
                                    top: 0,
                                    left: 0,
                                    right: 0,
                                    child: LiquidGlassAppBar(
                                      title: Text(
                                        _isWsConnected
                                            ? l10n.translate('app_title')
                                            : 'соединение',
                                        style: TextStyle(
                                          fontSize: 28,
                                          fontWeight: FontWeight.bold,
                                          color: _isWsConnected
                                              ? Theme.of(context)
                                                  .colorScheme
                                                  .onSurface
                                              : Colors.grey,
                                        ),
                                      ),
                                      actions: [
                                        Padding(
                                          padding: const EdgeInsets.only(right: 8),
                                          child: Container(
                                            width: 10,
                                            height: 10,
                                            decoration: BoxDecoration(
                                              color: _isWsConnected
                                                  ? Colors.green
                                                  : Colors.grey,
                                              shape: BoxShape.circle,
                                            ),
                                          ),
                                        ),
                                      ],
                                      leading: const SizedBox.shrink(),
                                      centerTitle: true,
                                      isLite: glassProvider.isLite,
                                    ),
                                  ),
                                  // Фильтры плавают ниже AppBar
                                  Positioned(
                                    top: topBarHeight,
                                    left: 0,
                                    right: 0,
                                    child: LiquidGlassFilterChips(
                                      enabled: true,
                                      isLite: glassProvider.isLite,
                                      filters: filters,
                                      activeFilter: _activeFilter,
                                      onFilterSelected: (i) =>
                                          setState(() => _activeFilter = i),
                                      unreadCounts: unreadCounts,
                                    ),
                                  ),
                                  // Режим выбора — поверх всего
                                  if (_isSelectMode)
                                    Positioned(
                                      top: 0,
                                      left: 0,
                                      right: 0,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 8),
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF0088CC),
                                          boxShadow: [
                                            BoxShadow(
                                              color: const Color(0xFF0088CC)
                                                  .withValues(alpha: 0.3),
                                              blurRadius: 8,
                                              offset: const Offset(0, 2),
                                            ),
                                          ],
                                        ),
                                        child: SafeArea(
                                          bottom: false,
                                          child: Row(
                                            children: [
                                              IconButton(
                                                icon: const Icon(Icons.close,
                                                    color: Colors.white),
                                                onPressed: _exitSelectMode,
                                              ),
                                              const SizedBox(width: 8),
                                              Text(
                                                'Выбрано: ${_selectedChatIds.length}',
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 18,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                              const Spacer(),
                                              IconButton(
                                                icon: const Icon(
                                                    Icons.select_all,
                                                    color: Colors.white),
                                                tooltip: 'Выбрать все',
                                                onPressed: _selectAllChats,
                                              ),
                                              IconButton(
                                                icon: const Icon(
                                                    Icons.more_vert,
                                                    color: Colors.white),
                                                onPressed:
                                                    _showSelectedChatsMenu,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              );
                            }

                            // === Classic-режим ===
                            return SafeArea(
                              child: Column(
                                children: [
                                  // Top bar
                                  if (_isSelectMode)
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFF0088CC),
                                        boxShadow: [
                                          BoxShadow(
                                            color: const Color(0xFF0088CC)
                                                .withValues(alpha: 0.3),
                                            blurRadius: 8,
                                            offset: const Offset(0, 2),
                                          ),
                                        ],
                                      ),
                                      child: Row(
                                        children: [
                                          IconButton(
                                            icon: const Icon(Icons.close,
                                                color: Colors.white),
                                            onPressed: _exitSelectMode,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'Выбрано: ${_selectedChatIds.length}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 18,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                          const Spacer(),
                                          IconButton(
                                            icon: const Icon(Icons.select_all,
                                                color: Colors.white),
                                            tooltip: 'Выбрать все',
                                            onPressed: _selectAllChats,
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.more_vert,
                                                color: Colors.white),
                                            onPressed: _showSelectedChatsMenu,
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 12, vertical: 8),
                                      child: Center(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              _isWsConnected
                                                  ? l10n.translate('app_title')
                                                  : 'соединение',
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: _isWsConnected
                                                    ? Theme.of(context)
                                                        .colorScheme
                                                        .onSurface
                                                    : Colors.grey,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Container(
                                              width: 10,
                                              height: 10,
                                              decoration: BoxDecoration(
                                                color: _isWsConnected
                                                    ? Colors.green
                                                    : Colors.grey,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  // Filter chips + Chat list
                                  LiquidGlassFilterChips(
                                    enabled: false,
                                    filters: filters,
                                    activeFilter: _activeFilter,
                                    onFilterSelected: (i) =>
                                        setState(() => _activeFilter = i),
                                    unreadCounts: unreadCounts,
                                  ),
                                  Expanded(child: _buildChatList()),
                                ],
                              ),
                            );
                          },
                        ),
                      ), // closes _KeepAlivePage
                    ), // closes RepaintBoundary

                    // Страница 2: Поиск
                    RepaintBoundary(
                      child: _KeepAlivePage(
                        child: SafeArea(
                          child: Column(
                            children: [
                              // Заголовок поиска — по центру
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                child: Center(
                                  child: Text(
                                    l10n.translate('common_search'),
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                              // Поле поиска
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                child: TextField(
                                  controller: _searchController,
                                  autofocus: false,
                                  focusNode: _searchFocusNode,
                                  decoration: InputDecoration(
                                    hintText: l10n.translate('common_search'),
                                    prefixIcon: const Icon(Icons.search),
                                    suffixIcon: IconButton(
                                      icon: const Icon(Icons.close, size: 20),
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() {
                                          _searchQuery = '';
                                          _users = [];
                                          _groups = [];
                                          _channels = [];
                                          _messages = [];
                                        });
                                      },
                                    ),
                                    border: OutlineInputBorder(
                                      borderRadius: BorderRadius.circular(12),
                                      borderSide: BorderSide.none,
                                    ),
                                    filled: true,
                                  ),
                                ),
                              ),
                              // Результаты поиска
                              Expanded(
                                child: _buildSearchResults(),
                              ),
                            ],
                          ),
                        ), // closes SafeArea
                      ), // closes _KeepAlivePage
                    ),
                  ], // closes PageView children
                ), // closes PageView
              ), // closes Positioned.fill

              // Нижний бар плавает поверх контента — glass преломляет содержимое
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Consumer<LiquidGlassProvider>(
                  builder: (context, glassProvider, _) {
                    if (glassProvider.enabled) {
                      // Glass-режим: плавающий бар с кнопкой "+"
                      return LiquidGlassBottomBar(
                        selectedIndex: _currentIndex,
                        onTabSelected: (index) {
                          _onTabTapped(index);
                        },
                        onAddTap: _showCreateMenu,
                        isLite: glassProvider.isLite,
                      );
                    }

                    // Классический режим — тот же визуал, но сплошная заливка
                    return ClassicBottomBar(
                      selectedIndex: _currentIndex,
                      onTabSelected: (index) {
                        _onTabTapped(index);
                      },
                      onAddTap: _showCreateMenu,
                    );
                  },
                ),
              ),
            ], // closes Stack children
          ), // closes Stack
        ), // closes Scaffold
      ), // closes PopScope
    ); // closes AnnotatedRegion
  }

  Widget _buildSearchResults() {
    final l10n = context.l10n;

    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_users.isEmpty &&
        _groups.isEmpty &&
        _channels.isEmpty &&
        _messages.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search, size: 80, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              l10n.translate('common_nothing_found'),
              style: TextStyle(
                fontSize: 20,
                color: Colors.grey[600],
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.translate('common_try_different_query'),
              style: TextStyle(
                fontSize: 14,
                color: Colors.grey[500],
              ),
            ),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        if (_users.isNotEmpty)
          _buildSearchSection(
              l10n.translate('search_users'),
              _users
                  .map((u) => ListTile(
                        leading: CircleAvatar(
                          child: Text(u.name.isNotEmpty
                              ? u.name[0].toUpperCase()
                              : '?'),
                        ),
                        title: Text(u.name),
                        subtitle: Text('@${u.username}'),
                        onTap: () => _onSearchResultTap(u, 'user'),
                      ))
                  .toList()),
        if (_groups.isNotEmpty)
          _buildSearchSection(
              l10n.translate('search_groups'),
              _groups
                  .map((g) => ListTile(
                        leading: const Icon(Icons.group, size: 40),
                        title: Text(g.name),
                        subtitle: Text(g.description.isNotEmpty
                            ? g.description
                            : l10n.translate('search_no_description')),
                        onTap: () => _onSearchResultTap(g, 'group'),
                      ))
                  .toList()),
        if (_channels.isNotEmpty)
          _buildSearchSection(
              l10n.translate('search_channels'),
              _channels
                  .map((c) => ListTile(
                        leading: const Icon(Icons.forum, size: 40),
                        title: Text(c.name),
                        subtitle: Text(c.description.isNotEmpty
                            ? c.description
                            : l10n.translate('search_no_description')),
                        onTap: () => _onSearchResultTap(c, 'channel'),
                      ))
                  .toList()),
        if (_messages.isNotEmpty)
          _buildSearchSection(
              l10n.translate('search_messages'),
              _messages
                  .map((m) => ListTile(
                        leading: const Icon(Icons.message),
                        title: Text(m.content,
                            maxLines: 2, overflow: TextOverflow.ellipsis),
                        subtitle: Text(
                            '${l10n.translate('search_from_user').replaceAll('{user}', m.userId)} • ${_formatDate(m.createdAt)}'),
                        onTap: () => _onSearchResultTap(m, 'message'),
                      ))
                  .toList()),
      ],
    );
  }

  Widget _buildSearchSection(String title, List<Widget> items) {
    return SettingsGroup(
      title: title,
      children: items,
    );
  }

  String _formatDate(DateTime date) {
    final l10n = context.l10n;
    final localDate = date.toLocal();
    final now = DateTime.now();

    if (DateTimeUtils.isToday(localDate, now: now)) {
      return '${l10n.translate('date_today')} ${localDate.hour.toString().padLeft(2, '0')}:${localDate.minute.toString().padLeft(2, '0')}';
    } else if (DateTimeUtils.isYesterday(localDate, now: now)) {
      return l10n.translate('date_yesterday');
    } else {
      final daysDiff = DateTimeUtils.startOfDay(now)
          .difference(DateTimeUtils.startOfDay(localDate))
          .inDays;
      if (daysDiff < 7 && daysDiff > 0) {
        return l10n
            .translate('date_days_ago')
            .replaceAll('{days}', daysDiff.toString());
      } else {
        return '${localDate.day}.${localDate.month.toString().padLeft(2, '0')}.${localDate.year}';
      }
    }
  }

  void _onSearchResultTap(dynamic result, String type) async {
    switch (type) {
      case 'user':
        if (result is SearchResultUser) {
          // Create or get existing private chat
          final chatResult = await ChatService.createChat(
            chatType: 'private',
            participantIds: [result.id],
          );
          if (chatResult['success'] == true && mounted) {
            final chat = chatResult['chat'] as Chat;
            
            Navigator.push(
              context,
              SwipeBackPageRoute(
                builder: (_) => PrivateChatScreen(
                  chatId: chat.id,
                  otherUserName: result.name,
                  otherUserAvatar: result.avatarUrl,
                  otherUserId: result.id,
                ),
              ),
            ).then((_) {});
          } else if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                  content:
                      Text(chatResult['message'] ?? 'Failed to create chat')),
            );
          }
        }
        break;
      case 'group':
        if (result is SearchResultGroup) {
          
          Navigator.push(
            context,
            SwipeBackPageRoute(
              builder: (_) => GroupChatScreen(
                chatId: result.id,
                groupName: result.name,
                groupAvatar: null,
              ),
            ),
          ).then((_) {});
        }
        break;
      case 'channel':
        if (result is SearchResultChannel) {
          
          Navigator.push(
            context,
            SwipeBackPageRoute(
              builder: (_) => ChannelScreen(
                channelId: result.id,
                channelName: result.name,
                channelAvatar: null,
              ),
            ),
          ).then((_) {});
        }
        break;
      case 'message':
        if (result is SearchResultMessage) {
          // Navigate to the channel where the message is located
          // The message will be highlighted/scrolled to via the messageId parameter
          
          Navigator.push(
            context,
            SwipeBackPageRoute(
              builder: (_) => ChannelScreen(
                channelId: result.channelId,
                channelName: null,
                channelAvatar: null,
                highlightMessageId: result.id,
              ),
            ),
          ).then((_) {});
        }
        break;
      default:
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unknown type: $type')),
        );
    }
  }
}

/// Обёртка для страниц PageView, предотвращающая пересоздание
/// при переключении вкладок. AutomaticKeepAliveClientMixin
/// сохраняет состояние виджета даже когда он не виден.
class _KeepAlivePage extends StatefulWidget {
  final Widget child;
  const _KeepAlivePage({required this.child});

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
