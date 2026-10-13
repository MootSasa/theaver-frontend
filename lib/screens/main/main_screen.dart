import '../../utils/image_utils.dart';
import '../../utils/emoji_utils.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:math' as math;

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
import '../../services/draft_service.dart';
import '../../services/websocket_service.dart';
import '../../services/local_storage_service.dart';
import '../../services/account_manager.dart';
import '../../services/deep_link_service.dart';
import '../../services/cache_service.dart';
import '../../services/profile_theme_provider.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/unread_count_provider.dart';
import '../../screens/auth/login_screen.dart';
import '../../l10n/app_localizations.dart';
import '../../widgets/user/avatar_with_status.dart';
import '../../models/theav_theme.dart';
import '../../widgets/chat/classic_bottom_bar.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import '../../widgets/settings/settings_group.dart';
import '../../services/sync_service.dart';
import '../../services/database/app_database.dart';
import 'package:drift/drift.dart' show Value;
import '../../utils/swipe_back_route.dart';
import '../../utils/date_time_utils.dart';
import '../../services/update_service.dart';
import '../settings/widgets/update_dialog.dart';
import '../../widgets/chat/round_video_thumbnail.dart';
import '../../widgets/chat/media_note_player_header.dart';
import '../../widgets/notifications/notification_permission_dialog.dart';
import '../../services/notification_service.dart';
import '../../models/chat_folder.dart';
import '../../services/chat_folder_service.dart';
import '../../services/chat_swipe_service.dart';
import '../../services/voice_playback_service.dart';
import '../../services/video_note_playback_service.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  int _currentIndex = 1; // 0: Settings, 1: Chats, 2: Search
  int _activeFilter = 0; // Index of the active folder in _folderService.folders
  final ChatFolderService _folderService = ChatFolderService();

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  // PageController для свайпа между Настройками и Чатами
  final PageController _pageController = PageController(initialPage: 1);

  // Search functionality
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';

  // Chats list
  List<Chat> _chats = [];
  bool _isLoadingChats = true;
  StreamSubscription<List<DbChat>>? _chatsStreamSubscription;

  void _initChatsStream() {
    _chatsStreamSubscription?.cancel();
    _chatsStreamSubscription = AppDatabase().watchChats().listen((dbChats) {
      if (!mounted) return;
      setState(() {
        _chats = dbChats.map(_dbChatToChat).toList();
        if (_isLoadingChats && _chats.isNotEmpty) {
          _isLoadingChats = false;
        }
      });
      DraftService().populateFromChats(_chats);
    });
  }

  // Multi-select mode
  bool _isSelectMode = false;
  Set<String> _selectedChatIds = {};

  // Top glass bar & morph context menu
  bool _isTopMenuOpen = false;
  final LayerLink _topMenuLayerLink = LayerLink();
  final OverlayPortalController _topMenuOverlayController = OverlayPortalController();

  // Central folder morph menu
  bool _isFolderMenuOpen = false;
  final LayerLink _folderMenuLayerLink = LayerLink();
  final OverlayPortalController _folderMenuOverlayController = OverlayPortalController();

  // Animation controllers for Material mode top bar morphing
  late final AnimationController _classicTopMenuController;
  late final AnimationController _classicFolderMenuController;
  late final CurvedAnimation _classicTopMenuAnimation;
  late final CurvedAnimation _classicFolderMenuAnimation;
  int _topMenuTabIndex = 1;

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
    _classicTopMenuController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _classicTopMenuAnimation = CurvedAnimation(
      parent: _classicTopMenuController,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    _classicFolderMenuController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _classicFolderMenuAnimation = CurvedAnimation(
      parent: _classicFolderMenuController,
      curve: Curves.easeInOutCubic,
      reverseCurve: Curves.easeInOutCubic,
    );
    WidgetsBinding.instance.addObserver(this);
    _folderMenuOverlayController.show();
    _topMenuOverlayController.show();
    _searchController.addListener(_onSearchChanged);
    DraftService().draftsNotifier.addListener(_onDraftsChanged);
    _accountManager.addListener(_onAccountChanged);
    _folderService.addListener(_onServiceUpdate);
    ChatSwipeService().addListener(_onServiceUpdate);
    VoicePlaybackService().addListener(_onServiceUpdate);
    VideoNotePlaybackService().addListener(_onServiceUpdate);

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

  /// Последовательная инициализация: Drift → стрим чатов → чаты с сервера → WebSocket
  Future<void> _initApp() async {
    // 1. Инициализация Drift (обязательно до _loadChats!)
    await _initOfflineFirst();

    // 2. Реактивная подписка на стрим чатов из SQLite
    _initChatsStream();

    // 3. Загрузка чатов (фоновый запрос к серверу)
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
      if (!mounted) return;
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
      // Ignore empty private chats without messages or drafts that are not pinned
      if (newChat.chatType == 'private' &&
          (newChat.lastMessage == null || newChat.lastMessage!.isEmpty) &&
          (newChat.draft == null || newChat.draft!.text.isEmpty) &&
          !newChat.isPinned) {
        return;
      }

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
          }
          _sortChats();
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
      if (chatIndex != -1) {
        setState(() {
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

          final msgType = messageData?['message_type'] as String? ?? 'text';
          final isRound =
              messageData?['is_round'] == true || msgType == 'round';
          final fileUrl = messageData?['file_url'] as String?;
          final groupedId = messageData?['grouped_id'] as String?;
          final content = messageData?['content'] as String? ?? '';

          final updatedChat = Chat(
            id: chat.id,
            chatType: chat.chatType,
            name: chat.name,
            avatarUrl: chat.avatarUrl,
            lastMessage: content,
            lastMessageTime:
                messageData?['created_at'] as String? ?? chat.lastMessageTime,
            lastMessageType: msgType,
            lastMessageIsRound: isRound,
            lastMessageFileUrl: fileUrl,
            lastMessageGroupedId: groupedId,
            updatedAt: messageData?['created_at'] as String? ?? chat.updatedAt,
            unreadCount: newUnreadCount,
            isOnline: chat.isOnline,
            lastSeen: chat.lastSeen,
            isPinned: chat.isPinned,
            otherUserId: chat.otherUserId,
            draft: chat.draft,
          );

          // Update the chat in place
          _chats[chatIndex] = updatedChat;
          // Re-sort: pinned/saved chats stay in their fixed positions,
          // unpinned chats sort by updated_at
          _sortChats();
        });
        // Save to local storage
        _localStorage.saveChats(_chats);

        // Сохранить в Drift
        final db = AppDatabase();
        try {
          db.saveChat(_chatToCompanion(updatedChat));
        } catch (_) {}
      } else {
        // Chat was not in the list yet, reload chats seamlessly
        _loadChats(silent: true);
      }
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

  void _onMessageDeleted(WebSocketEvent event) async {
    debugPrint('Message deleted received in MainScreen: ${event.data}');
    final chatId = event.data['chat_id']?.toString();
    final messageId =
        (event.data['message_id'] ?? event.data['messageId'])?.toString();
    if (chatId != null) {
      if (messageId != null) {
        try {
          await AppDatabase().deleteMessage(messageId);
        } catch (_) {}
      }
      if (mounted) {
        await _refreshChatLastMessage(chatId);
      }
    }
  }

  Future<void> _refreshChatLastMessage(String chatId) async {
    try {
      final db = AppDatabase();
      await db.refreshChatLastMessageFromDb(chatId);
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
    await db.ensureInitialized();

    // Фоновая загрузка с сервера (бесшовное обновление локальной БД)
    try {
      final result = await ChatService.getChats();

      if (mounted) {
        if (result['success'] == true && result['chats'] is List<Chat>) {
          final serverChats = result['chats'] as List<Chat>;
          DraftService().populateFromChats(serverChats);

          // Сохранить в Drift — это автоматически обновит _chats через reactive stream!
          try {
            final chatModels = serverChats.map(_chatToCompanion).toList();
            await db.saveChats(chatModels);
          } catch (e) {
            debugPrint('MainScreen: Error saving to Drift: $e');
          }

          // Обновить провайдер
          try {
            context.read<UnreadCountProvider>().loadFromChats(serverChats);
          } catch (_) {}
        } else {
          debugPrint('Failed to load chats: ${result['message']}');
          if (result['message'] == 'Not authenticated') {
            _localStorage.clearUserData();
          }
        }
      }
    } catch (e) {
      debugPrint('MainScreen: Error loading from server: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoadingChats = false);
      }
    }

    // Всегда проверять существование Избранного локально (даже оффлайн)
    await _ensureSavedChatExists();
  }

  /// Ensure "Saved Messages" / "Favorites" chat exists
  Future<void> _ensureSavedChatExists() async {
    try {
      final userId = await AuthService.getUserId();
      final db = AppDatabase();
      if (userId != null) {
        await db.ensureSavedChatExists(userId);
      }

      // Secondary sync: Request saved chat from server
      debugPrint('Requesting saved chat from server for sync...');
      final result = await ChatService.getOrCreateSavedChat();

      if (result['success'] == true && result['chat'] != null) {
        final savedChat = result['chat'] as Chat;
        if (userId != null) {
          await db.migrateSavedChatId('saved_$userId', savedChat.id);
        }
        await db.saveChat(_chatToCompanion(savedChat));
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
      lastMessageType: model.lastMessageType,
      lastMessageIsRound: model.lastMessageIsRound,
      lastMessageFileUrl: model.lastMessageFileUrl,
      lastMessageGroupedId: model.lastMessageGroupedId,
      otherUserId: model.otherUserId,
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
      lastMessageType: Value(chat.lastMessageType),
      lastMessageIsRound: Value(chat.lastMessageIsRound),
      lastMessageFileUrl: Value(chat.lastMessageFileUrl),
      lastMessageGroupedId: Value(chat.lastMessageGroupedId),
      otherUserId: Value(chat.otherUserId),
      updatedAt: Value(chat.updatedAt),
      unreadCount: Value(chat.unreadCount),
      isOnline: Value(chat.isOnline),
      lastSeen: Value(chat.lastSeen),
      isPinned: Value(chat.isPinned),
    );
  }

  @override
  void dispose() {
    _classicTopMenuAnimation.dispose();
    _classicFolderMenuAnimation.dispose();
    _classicTopMenuController.dispose();
    _classicFolderMenuController.dispose();
    NotificationService().isMainScreenReady = false;
    WidgetsBinding.instance.removeObserver(this);
    DraftService().draftsNotifier.removeListener(_onDraftsChanged);
    _accountManager.removeListener(_onAccountChanged);
    _folderService.removeListener(_onServiceUpdate);
    ChatSwipeService().removeListener(_onServiceUpdate);
    VoicePlaybackService().removeListener(_onServiceUpdate);
    VideoNotePlaybackService().removeListener(_onServiceUpdate);
    _searchController.dispose();
    _searchFocusNode.dispose();
    _pageController.dispose();
    _wsSubscription?.cancel();
    _connectionCheckTimer?.cancel();
    _chatsStreamSubscription?.cancel();
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

  void _onAccountChanged() {
    if (!mounted) return;
    debugPrint('[MainScreen] Active account changed! Refreshing state and WS...');
    setState(() {
      _chats = [];
      _isLoadingChats = true;
    });
    _initChatsStream();
    // Disconnect old WebSocket, reconnect with new account token, reload chats
    _wsService.disconnect();
    _initWebSocket();
    _loadChats();
    try {
      SyncService().syncFromServer();
    } catch (_) {}
  }

  void _onDraftsChanged() {
    if (mounted) setState(() {});
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
  // ignore: unused_element
  int _getTotalUnreadCount() {
    try {
      return context.read<UnreadCountProvider>().totalUnread;
    } catch (_) {
      return _chats.fold(0, (sum, chat) => sum + chat.unreadCount);
    }
  }

  void _onTabTapped(int index) {
    if (_isTopMenuOpen) {
      _closeTopMenu();
    }
    if (_isFolderMenuOpen) {
      _closeFolderMenu();
    }
    if (_currentIndex == index) return;
    // Закрываем клавиатуру при уходе с поиска
    if (_currentIndex == 2 && index != 2) {
      _searchFocusNode.unfocus();
    }
    setState(() {
      _currentIndex = index;
      if (index == 2) {
        _searchController.clear();
        _searchQuery = '';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _searchFocusNode.requestFocus();
        });
      }
    });
    _pageController.animateToPage(
      index,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
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
              leading: iconoir.UserPlus(
                color: Theme.of(context).colorScheme.primary,
                width: 24,
                height: 24,
              ),
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
              leading: iconoir.Group(
                color: Theme.of(context).colorScheme.primary,
                width: 24,
                height: 24,
              ),
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
              leading: iconoir.Megaphone(
                color: Theme.of(context).colorScheme.primary,
                width: 24,
                height: 24,
              ),
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

  // ── Top Glass Bar & Morph Menu Logic ──────────────────────────────

  void _openTopMenu() {
    if (_isTopMenuOpen) return;
    if (_isFolderMenuOpen) {
      _closeFolderMenu();
    }
    _topMenuTabIndex = _currentIndex;
    HapticUtils.tap();
    _classicTopMenuController.forward();
    _topMenuOverlayController.show();
    setState(() {
      _isTopMenuOpen = true;
    });
  }

  void _closeTopMenu() {
    if (!_isTopMenuOpen) return;
    _classicTopMenuController.reverse();
    setState(() {
      _isTopMenuOpen = false;
    });
  }

  void _toggleTopMenu() {
    if (_isTopMenuOpen) {
      _closeTopMenu();
    } else {
      _openTopMenu();
    }
  }

  void _openFolderMenu() {
    if (_currentIndex != 1) return;
    if (_isFolderMenuOpen) return;
    if (_isTopMenuOpen) {
      _closeTopMenu();
    }
    HapticUtils.tap();
    _classicFolderMenuController.forward();
    _folderMenuOverlayController.show();
    setState(() {
      _isFolderMenuOpen = true;
    });
  }

  void _closeFolderMenu() {
    if (!_isFolderMenuOpen) return;
    _classicFolderMenuController.reverse();
    setState(() {
      _isFolderMenuOpen = false;
    });
  }

  void _toggleFolderMenu() {
    if (_isFolderMenuOpen) {
      _closeFolderMenu();
    } else {
      _openFolderMenu();
    }
  }

  double _calculateTitleWidth(BuildContext context) {
    final tp = TextPainter(
      text: TextSpan(
        text: _currentTitleText,
        style: const TextStyle(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
        ),
      ),
      textDirection: Directionality.of(context),
    )..layout();
    return tp.width;
  }

  String get _currentTitleText {
    final l10n = context.l10n;
    switch (_currentIndex) {
      case 0:
        return l10n.translate('settings_title');
      case 2:
        return l10n.translate('common_search');
      case 1:
      default:
        if (!_isWsConnected) return 'соединение';
        final folders = _folderService.folders;
        if (_activeFilter >= 0 && _activeFilter < folders.length) {
          final f = folders[_activeFilter];
          if (f.id == 'all') {
            return l10n.translate('app_title').isNotEmpty
                ? l10n.translate('app_title')
                : 'Theaver';
          }
          return f.name;
        }
        return l10n.translate('app_title').isNotEmpty
            ? l10n.translate('app_title')
            : 'Theaver';
    }
  }

  String get _currentTitleKey {
    switch (_currentIndex) {
      case 0:
        return 'settings';
      case 2:
        return 'search';
      case 1:
      default:
        return _isWsConnected ? 'chats_filter_$_activeFilter' : 'connecting';
    }
  }

  bool get _isTitleConnected {
    if (_currentIndex == 1) {
      return _isWsConnected;
    }
    return true;
  }

  List<_MorphMenuItemData> _getMenuItems(int index) {
    final l10n = context.l10n;
    switch (index) {
      case 0: // Settings
        return [
          _MorphMenuItemData(
            id: 'profile',
            label: l10n.translate('settings_profile'),
            iconBuilder: (color, size) => iconoir.User(color: color, width: size, height: size),
          ),
          _MorphMenuItemData(
            id: 'clear_data',
            label: l10n.translate('clear_data_title'),
            iconBuilder: (color, size) => iconoir.Trash(color: color, width: size, height: size),
            color: Colors.orange,
          ),
          _MorphMenuItemData(
            id: 'logout',
            label: l10n.translate('menu_logout'),
            iconBuilder: (color, size) => iconoir.LogOut(color: color, width: size, height: size),
            color: Colors.red,
          ),
        ];
      case 2: // Search
        return [
          _MorphMenuItemData(
            id: 'clear_search',
            label: 'Очистить поиск',
            iconBuilder: (color, size) => iconoir.Trash(color: color, width: size, height: size),
          ),
          _MorphMenuItemData(
            id: 'profile',
            label: l10n.translate('settings_profile'),
            iconBuilder: (color, size) => iconoir.User(color: color, width: size, height: size),
          ),
        ];
      case 1: // Chats
      default:
        return [
          _MorphMenuItemData(
            id: 'select_chats',
            label: 'Выбрать чаты',
            iconBuilder: (color, size) => iconoir.ListSelect(color: color, width: size, height: size),
          ),
          _MorphMenuItemData(
            id: 'new_chat',
            label: l10n.translate('chat_new_private'),
            iconBuilder: (color, size) => iconoir.UserPlus(color: color, width: size, height: size),
          ),
          _MorphMenuItemData(
            id: 'new_group',
            label: l10n.translate('chat_new_group'),
            iconBuilder: (color, size) => iconoir.Group(color: color, width: size, height: size),
          ),
          _MorphMenuItemData(
            id: 'new_channel',
            label: l10n.translate('chat_new_channel'),
            iconBuilder: (color, size) => iconoir.Megaphone(color: color, width: size, height: size),
          ),
          _MorphMenuItemData(
            id: 'profile',
            label: l10n.translate('settings_profile'),
            iconBuilder: (color, size) => iconoir.User(color: color, width: size, height: size),
          ),
        ];
    }
  }

  double _getMenuHeight(int index) {
    final count = _getMenuItems(index).length;
    return count * 44.0 + 12.0;
  }

  void _handleMenuAction(String actionId) {
    _closeTopMenu();

    switch (actionId) {
      case 'select_chats':
        setState(() {
          _isSelectMode = true;
          _selectedChatIds = {};
        });
        break;
      case 'new_chat':
        Navigator.push(
          context,
          SwipeBackPageRoute(builder: (_) => const CreatePrivateChatScreen()),
        );
        break;
      case 'new_group':
        Navigator.push(
          context,
          SwipeBackPageRoute(builder: (_) => const CreateGroupScreen()),
        );
        break;
      case 'new_channel':
        Navigator.push(
          context,
          SwipeBackPageRoute(builder: (_) => const CreateChannelScreen()),
        );
        break;
      case 'profile':
        Navigator.push(
          context,
          SwipeBackPageRoute(builder: (_) => const ProfileScreen()),
        );
        break;
      case 'clear_data':
        _showClearDataDialog();
        break;
      case 'logout':
        _showLogoutDialog();
        break;
      case 'clear_search':
        _searchController.clear();
        setState(() {
          _searchQuery = '';
          _users = [];
          _groups = [];
          _channels = [];
          _messages = [];
        });
        break;
    }
  }

  void _showLogoutDialog() {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('menu_logout')),
        content: Text(l10n.translate('accounts_logout_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.translate('common_cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.of(context).pop();
              final nav = DeepLinkService().navigatorKey.currentState ??
                  Navigator.of(context, rootNavigator: true);
              nav.pushAndRemoveUntil(
                SwipeBackPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
              await AuthService.logout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(l10n.translate('menu_logout')),
          ),
        ],
      ),
    );
  }

  void _showClearDataDialog() {
    final l10n = context.l10n;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.translate('clear_data_title')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.translate('clear_data_message')),
            const SizedBox(height: 12),
            Text(
              l10n.translate('clear_data_warning'),
              style: const TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(l10n.translate('common_cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              final nav = DeepLinkService().navigatorKey.currentState ??
                  Navigator.of(context, rootNavigator: true);
              Navigator.of(context).pop();
              nav.pushAndRemoveUntil(
                SwipeBackPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
              try {
                WebSocketService().disconnect();
                await AuthService.logout();
                await AppDatabase().clearAllData();
                await CacheService().clearCache();
                await _accountManager.clearAll();
                final prefs = await SharedPreferences.getInstance();
                await prefs.clear();
              } catch (_) {}
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
            ),
            child: Text(l10n.translate('clear_data_button')),
          ),
        ],
      ),
    );
  }

  Widget _buildTopGlassBar(
    BuildContext context,
    LiquidGlassProvider glassProvider,
  ) {
    const double ctrlSize = 44.0;
    const double menuWidth = 200.0;
    const double folderMenuWidth = 220.0;
    const double barRadius = ctrlSize / 2; // 22.0 — stadium capsule ratio

    final pillStyle = glassProvider.createStyle(
      context: context,
      cornerRadius: barRadius,
      refractionIndex: 1.1,
      refractionWidth: 24.0,
    );

    final morphStyle = pillStyle;
    const morphMotion = LiquidGlassMorphMotion.fluid;

    final double closedPillWidth =
        math.max(130.0, _calculateTitleWidth(context) + 48.0);

    return SizedBox(
      width: double.infinity,
      height: ctrlSize + 4,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Centered title pill / morph folder dropdown menu
          Positioned(
            top: 2,
            left: 0,
            right: 0,
            child: Align(
              alignment: Alignment.topCenter,
              child: OverlayPortal(
                controller: _folderMenuOverlayController,
                overlayChildBuilder: (context) {
                  return Stack(
                    children: [
                      Positioned.fill(
                        child: IgnorePointer(
                          ignoring: !_isFolderMenuOpen,
                          child: GestureDetector(
                            onTap: _closeFolderMenu,
                            behavior: HitTestBehavior.opaque,
                          ),
                        ),
                      ),
                      CompositedTransformFollower(
                        link: _folderMenuLayerLink,
                        showWhenUnlinked: false,
                        targetAnchor: Alignment.topCenter,
                        followerAnchor: Alignment.topCenter,
                        child: LiquidGlassMorph(
                          key: const ValueKey<String>('main_folder_menu_morph'),
                          alignment: Alignment.topCenter,
                          motion: morphMotion,
                          smoothness: 28,
                          style: pillStyle,
                          child: _isFolderMenuOpen
                              ? _FolderMorphMenu(
                                  key: const ValueKey<String>('folder_menu'),
                                  width: folderMenuWidth,
                                  activeFilter: _activeFilter,
                                  folders: _folderService.folders,
                                  unreadCounts: List.generate(
                                    _folderService.folders.length,
                                    (index) => _getUnreadCountForFilter(index),
                                  ),
                                  onSelectFolder: (index) {
                                    HapticUtils.selection();
                                    setState(() => _activeFilter = index);
                                    _closeFolderMenu();
                                  },
                                )
                              : _TitlePillContent(
                                  key: const ValueKey<String>('title_pill'),
                                  title: _currentTitleText,
                                  titleKey: _currentTitleKey,
                                  isConnected: _isTitleConnected,
                                  onTap: _currentIndex == 1 ? _toggleFolderMenu : null,
                                ),
                        ),
                      ),
                    ],
                  );
                },
                child: CompositedTransformTarget(
                  link: _folderMenuLayerLink,
                  child: SizedBox(
                    width: closedPillWidth,
                    height: ctrlSize,
                  ),
                ),
              ),
            ),
          ),

          // Persistent three dots button and morph context menu
          Positioned(
            top: 2,
            right: 16,
            child: OverlayPortal(
              controller: _topMenuOverlayController,
              overlayChildBuilder: (context) {
                return Stack(
                  children: [
                    Positioned.fill(
                      child: IgnorePointer(
                        ignoring: !_isTopMenuOpen,
                        child: GestureDetector(
                          onTap: _closeTopMenu,
                          behavior: HitTestBehavior.opaque,
                        ),
                      ),
                    ),
                    CompositedTransformFollower(
                      link: _topMenuLayerLink,
                      showWhenUnlinked: false,
                      targetAnchor: Alignment.topRight,
                      followerAnchor: Alignment.topRight,
                      child: LiquidGlassMorph(
                        key: const ValueKey<String>('main_top_menu_morph'),
                        alignment: Alignment.topRight,
                        motion: morphMotion,
                        smoothness: 28,
                        style: morphStyle,
                        child: _isTopMenuOpen
                            ? _TopMorphMenu(
                                key: const ValueKey<String>('menu'),
                                width: menuWidth,
                                items: _getMenuItems(_currentIndex),
                                onItemTap: _handleMenuAction,
                              )
                            : _ThreeDotsGlyph(
                                key: const ValueKey<String>('glyph'),
                                size: ctrlSize,
                                onTap: _toggleTopMenu,
                              ),
                      ),
                    ),
                  ],
                );
              },
              child: CompositedTransformTarget(
                link: _topMenuLayerLink,
                child: const SizedBox(
                  width: ctrlSize,
                  height: ctrlSize,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectModeBar(BuildContext context) {
    final primaryColor = Theme.of(context).colorScheme.primary;
    return Container(
      height: 44,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: primaryColor,
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: primaryColor.withValues(alpha: 0.35),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            icon: const iconoir.Xmark(color: Colors.white, width: 20, height: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _exitSelectMode,
          ),
          const SizedBox(width: 8),
          Text(
            'Выбрано: ${_selectedChatIds.length}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const Spacer(),
          IconButton(
            icon: const iconoir.ListSelect(color: Colors.white, width: 20, height: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            tooltip: 'Выбрать все',
            onPressed: _selectAllChats,
          ),
          IconButton(
            icon: const iconoir.MoreVert(color: Colors.white, width: 20, height: 20),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: _showSelectedChatsMenu,
          ),
        ],
      ),
    );
  }

  Widget _buildClassicTopBar(BuildContext context) {
    final theme = Theme.of(context);
    final themeExt = theme.extension<TheavThemeExtension>();
    final p = themeExt?.palette;
    final isDark = theme.brightness == Brightness.dark;

    final barBackgroundColor = p?.surface ??
        (isDark ? const Color(0xFF2C2C2E) : Colors.white);
    final borderColor = p?.divider ??
        (isDark
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.06));
    final double baseShadowAlpha = isDark ? 0.35 : 0.08;

    const double ctrlSize = 44.0;
    const double menuWidth = 200.0;
    final int menuTabIndex =
        _classicTopMenuController.value > 0 ? _topMenuTabIndex : _currentIndex;
    final double menuHeight = _getMenuHeight(menuTabIndex);
    const double folderMenuWidth = 220.0;
    final double folderMenuHeight =
        math.max(44.0, _folderService.folders.length * 44.0 + 12.0);

    final double closedPillWidth =
        math.max(130.0, _calculateTitleWidth(context) + 48.0);

    return AnimatedBuilder(
      animation: Listenable.merge([
        _classicTopMenuAnimation,
        _classicFolderMenuAnimation,
      ]),
      builder: (context, _) {
        final double topProgress = _classicTopMenuAnimation.value;
        final double folderProgress = _classicFolderMenuAnimation.value;

        final double currentTopWidth =
            ctrlSize + (menuWidth - ctrlSize) * topProgress;
        final double currentTopHeight =
            ctrlSize + (menuHeight - ctrlSize) * topProgress;

        final double currentFolderWidth =
            closedPillWidth + (folderMenuWidth - closedPillWidth) * folderProgress;
        final double currentFolderHeight =
            ctrlSize + (folderMenuHeight - ctrlSize) * folderProgress;

        final double currentBarHeight = math.max(
          ctrlSize + 4,
          math.max(currentTopHeight, currentFolderHeight) + 8,
        );

        final folderPillWidget = Positioned(
          top: 2,
          left: 0,
          right: 0,
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              width: currentFolderWidth,
              height: currentFolderHeight,
              decoration: BoxDecoration(
                color: barBackgroundColor,
                borderRadius: BorderRadius.circular(22.0),
                border: Border.all(color: borderColor, width: 0.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: (baseShadowAlpha *
                              (0.6 + 0.4 * folderProgress))
                          .clamp(0.0, 1.0),
                    ),
                    blurRadius: 10 + 6 * folderProgress,
                    offset: Offset(0, 3 + 3 * folderProgress),
                  ),
                ],
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                clipBehavior: Clip.hardEdge,
                children: [
                  // Folder menu items
                  if (folderProgress > 0.01)
                    Positioned(
                      top: 0,
                      left: (currentFolderWidth - folderMenuWidth) / 2,
                      width: folderMenuWidth,
                      height: folderMenuHeight,
                      child: Opacity(
                        opacity: ((folderProgress - 0.15) / 0.85)
                            .clamp(0.0, 1.0),
                        child: Transform.translate(
                          offset:
                              Offset(0, -10.0 * (1.0 - folderProgress)),
                          child: IgnorePointer(
                            ignoring: folderProgress < 0.9,
                            child: _FolderMorphMenu(
                              key: const ValueKey<String>('folder_menu'),
                              width: folderMenuWidth,
                              activeFilter: _activeFilter,
                              folders: _folderService.folders,
                              unreadCounts: List.generate(
                                _folderService.folders.length,
                                (index) => _getUnreadCountForFilter(index),
                              ),
                              onSelectFolder: (index) {
                                HapticUtils.selection();
                                setState(() => _activeFilter = index);
                                _closeFolderMenu();
                              },
                            ),
                          ),
                        ),
                      ),
                    ),

                  // Title pill content ("Theaver")
                  if (folderProgress < 0.99)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: ctrlSize,
                      child: Opacity(
                        opacity: (1.0 - (folderProgress / 0.35))
                            .clamp(0.0, 1.0),
                        child: Transform.scale(
                          scale: 1.0 - 0.15 * folderProgress,
                          child: IgnorePointer(
                            ignoring: folderProgress > 0.1,
                            child: _TitlePillContent(
                              key: const ValueKey<String>('title_pill'),
                              title: _currentTitleText,
                              titleKey: _currentTitleKey,
                              isConnected: _isTitleConnected,
                              onTap: _currentIndex == 1
                                  ? _toggleFolderMenu
                                  : null,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );

        final threeDotsWidget = Positioned(
          top: 2,
          right: 16,
          child: Container(
            width: currentTopWidth,
            height: currentTopHeight,
            decoration: BoxDecoration(
              color: barBackgroundColor,
              borderRadius: BorderRadius.circular(22.0),
              border: Border.all(color: borderColor, width: 0.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(
                    alpha:
                        (baseShadowAlpha * (0.6 + 0.4 * topProgress))
                            .clamp(0.0, 1.0),
                  ),
                  blurRadius: 10 + 6 * topProgress,
                  offset: Offset(0, 3 + 3 * topProgress),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              clipBehavior: Clip.hardEdge,
              children: [
                // Menu items
                if (topProgress > 0.01)
                  Positioned(
                    top: 0,
                    right: 0,
                    width: menuWidth,
                    height: menuHeight,
                    child: Opacity(
                      opacity: ((topProgress - 0.15) / 0.85)
                          .clamp(0.0, 1.0),
                      child: Transform.translate(
                        offset:
                            Offset(0, -10.0 * (1.0 - topProgress)),
                        child: IgnorePointer(
                          ignoring: topProgress < 0.9,
                          child: _TopMorphMenu(
                            key: const ValueKey<String>('menu'),
                            width: menuWidth,
                            items: _getMenuItems(menuTabIndex),
                            onItemTap: _handleMenuAction,
                          ),
                        ),
                      ),
                    ),
                  ),

                // Three dots glyph
                if (topProgress < 0.99)
                  Positioned(
                    top: 0,
                    right: 0,
                    width: ctrlSize,
                    height: ctrlSize,
                    child: Opacity(
                      opacity: (1.0 - (topProgress / 0.35))
                          .clamp(0.0, 1.0),
                      child: Transform.scale(
                        scale: 1.0 - 0.2 * topProgress,
                        child: IgnorePointer(
                          ignoring: topProgress > 0.1,
                          child: _ThreeDotsGlyph(
                            key: const ValueKey<String>('glyph'),
                            size: ctrlSize,
                            onTap: _toggleTopMenu,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );

        return SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: SizedBox(
              width: double.infinity,
              height: currentBarHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: folderProgress > 0
                    ? [threeDotsWidget, folderPillWidget]
                    : [folderPillWidget, threeDotsWidget],
              ),
            ),
          ),
        );
      },
    );
  }

  /// Calculate number of chats with unread messages for a specific filter index
  int _getUnreadCountForFilter(int filterIndex) {
    final folders = _folderService.folders;
    if (filterIndex >= 0 && filterIndex < folders.length) {
      final folder = folders[filterIndex];
      return _chats.where((chat) => folder.matchesChat(chat) && chat.unreadCount > 0).length;
    }
    return 0;
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

    // Filter chats based on active folder rules
    final folders = _folderService.folders;
    final activeFolder = (_activeFilter >= 0 && _activeFilter < folders.length)
        ? folders[_activeFilter]
        : (folders.isNotEmpty ? folders.first : ChatFolder.defaults.first);

    List<Chat> filteredChats = _chats.where((chat) => activeFolder.matchesChat(chat)).toList();

    if (filteredChats.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            iconoir.ChatBubble(
              width: 80,
              height: 80,
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

    return AnimatedPadding(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      padding: EdgeInsets.only(
        top: topPadding,
        bottom: 100,
      ),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(
          parent: BouncingScrollPhysics(),
        ),
        padding: EdgeInsets.zero,
        itemCount: filteredChats.length,
        itemBuilder: (context, index) {
          final chat = filteredChats[index];
          return _buildChatListItem(chat);
        },
      ),
    );
  }

  Widget _buildChatListItem(Chat chat) {
    Widget iconWidget;
    switch (chat.chatType) {
      case 'private':
        iconWidget = const iconoir.User(color: Colors.white, width: 22, height: 22);
        break;
      case 'group':
        iconWidget = const iconoir.Group(color: Colors.white, width: 22, height: 22);
        break;
      case 'channel':
        iconWidget = const iconoir.Megaphone(color: Colors.white, width: 22, height: 22);
        break;
      case 'saved':
        iconWidget = const iconoir.Bookmark(color: Colors.white, width: 22, height: 22);
        break;
      case 'system':
        iconWidget = const iconoir.ShieldCheck(color: Colors.white, width: 22, height: 22);
        break;
      default:
        iconWidget = const iconoir.ChatBubble(color: Colors.white, width: 22, height: 22);
    }

    final hasUnread = chat.unreadCount > 0;
    final isPrivateChat = chat.chatType == 'private';
    final isSelected = _selectedChatIds.contains(chat.id);

    final avatarWidget = isPrivateChat
        ? AvatarWithStatus(
            avatarUrl: chat.avatarUrl,
            name: chat.name,
            radius: 22,
            isOnline: _isSelectMode ? false : chat.isOnline,
          )
        : CircleAvatar(
            backgroundColor: Theme.of(context).colorScheme.primary,
            backgroundImage:
                chat.avatarUrl != null && chat.avatarUrl!.isNotEmpty
                    ? avatarImageProvider(chat.avatarUrl)
                    : null,
            child: chat.avatarUrl == null || chat.avatarUrl!.isEmpty
                ? iconWidget
                : null,
          );

    final Widget leadingWidget = Stack(
      clipBehavior: Clip.none,
      children: [
        avatarWidget,
        if (_isSelectMode && isSelected)
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              width: 18,
              height: 18,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).scaffoldBackgroundColor,
                  width: 2,
                ),
              ),
              child: const Center(
                child: iconoir.Check(
                  color: Colors.white,
                  width: 11,
                  height: 11,
                  strokeWidth: 2.5,
                ),
              ),
            ),
          ),
      ],
    );

    final Widget? trailingWidget = _isSelectMode
        ? null
        : Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
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
              const SizedBox(height: 4),
              if (hasUnread)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).extension<TheavThemeExtension>()?.palette.unreadBadge ??
                        Theme.of(context).colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: Text(
                    chat.unreadCount > 99 ? '99+' : chat.unreadCount.toString(),
                    style: TextStyle(
                      color: Theme.of(context).extension<TheavThemeExtension>()?.palette.unreadBadgeText ??
                          Theme.of(context).colorScheme.onPrimary,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                )
              else
                const SizedBox(height: 18),
            ],
          );

    final chatTile = Container(
      color:
          isSelected ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08) : null,
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
                child: iconoir.Pin(
                  width: 14,
                  height: 14,
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
                    iconoir.CheckCircle(width: 16, height: 16, color: Theme.of(context).colorScheme.primary),
                  ],
                ],
              ),
            ),
          ],
        ),
        subtitle: _buildChatSubtitle(chat, hasUnread),
        trailing: trailingWidget,
      ),
    );

    if (_isSelectMode) {
      return chatTile;
    }

    return Dismissible(
      key: ValueKey('chat_swipe_${chat.id}'),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        final action = ChatSwipeService().action;
        HapticUtils.selection();
        switch (action) {
          case ChatSwipeAction.read:
            await _toggleReadChat(chat);
            break;
          case ChatSwipeAction.pin:
            await _togglePinChat(chat);
            break;
          case ChatSwipeAction.delete:
            if (chat.chatType != 'saved') {
              await _batchDeleteChats([chat]);
            }
            break;
          case ChatSwipeAction.archive:
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Архивация чатов скоро будет доступна')),
              );
            }
            break;
          case ChatSwipeAction.mute:
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Отключение уведомлений скоро будет доступно')),
              );
            }
            break;
        }
        return false;
      },
      background: const SizedBox.shrink(),
      secondaryBackground: _buildChatSwipeBackground(),
      child: chatTile,
    );
  }

  Future<void> _toggleReadChat(Chat chat) async {
    final db = AppDatabase();
    if (chat.unreadCount > 0) {
      await db.batchMarkAsRead([chat.id]);
      try {
        context.read<UnreadCountProvider>().setCount(chat.id, 0);
      } catch (_) {}
      await ChatService.markMessagesAsRead(chatId: chat.id);
    } else {
      await db.updateUnreadCount(chat.id, 1);
      try {
        context.read<UnreadCountProvider>().setCount(chat.id, 1);
      } catch (_) {}
    }
  }

  Future<void> _togglePinChat(Chat chat) async {
    if (chat.chatType == 'saved') return;
    final newPinned = !chat.isPinned;
    await AppDatabase().batchSetPinned([chat.id], newPinned);
    if (newPinned) {
      await ChatService.pinChat(chatId: chat.id);
    } else {
      await ChatService.unpinChat(chatId: chat.id);
    }
  }

  Widget _buildChatSwipeBackground() {
    final action = ChatSwipeService().action;
    Widget icon;
    switch (action) {
      case ChatSwipeAction.pin:
        icon = const iconoir.Pin(color: Colors.white, width: 22, height: 22);
        break;
      case ChatSwipeAction.read:
        icon = const iconoir.ChatBubble(color: Colors.white, width: 22, height: 22);
        break;
      case ChatSwipeAction.archive:
        icon = const iconoir.Archive(color: Colors.white, width: 22, height: 22);
        break;
      case ChatSwipeAction.mute:
        icon = const iconoir.BellOff(color: Colors.white, width: 22, height: 22);
        break;
      case ChatSwipeAction.delete:
        icon = const iconoir.Trash(color: Colors.white, width: 22, height: 22);
        break;
    }

    return Container(
      color: action.color,
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            action.label,
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
          const SizedBox(width: 8),
          icon,
        ],
      ),
    );
  }

  Widget? _buildChatSubtitle(Chat chat, bool hasUnread) {
    final draft = DraftService().getDraft(chat.id) ?? chat.draft;
    if (draft != null && draft.isNotEmpty) {
      final draftPrefix = AppLocalizations.of(context)?.translate('chat_draft_prefix') ?? 'Черновик';
      final draftText = draft.text.trim().isNotEmpty ? draft.text : '...';
      return RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          children: [
            TextSpan(
              text: '$draftPrefix: ',
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            ...EmojiUtils.buildEmojiTextSpan(
              draftText,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                fontSize: 14,
              ),
            ).children ??
                [
                  TextSpan(
                    text: draftText,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
                      fontSize: 14,
                    ),
                  ),
                ],
          ],
        ),
      );
    }

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

    final themeExt = Theme.of(context).extension<TheavThemeExtension>();
    final subtitleColor = hasUnread
        ? (themeExt?.palette.chatSubtitleUnread ?? Theme.of(context).colorScheme.onSurface)
        : (themeExt?.palette.chatSubtitle ??
            Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6));

    return Text(
      displaySubtitle,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: subtitleColor,
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
    final folders = _folderService.folders;
    final activeFolder = (_activeFilter >= 0 && _activeFilter < folders.length)
        ? folders[_activeFilter]
        : (folders.isNotEmpty ? folders.first : ChatFolder.defaults.first);

    setState(() {
      _selectedChatIds = _chats
          .where((chat) => activeFolder.matchesChat(chat))
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
                leading: allPinned
                    ? iconoir.PinSlash(color: Theme.of(context).colorScheme.primary, width: 22, height: 22)
                    : iconoir.Pin(color: Theme.of(context).colorScheme.primary, width: 22, height: 22),
                title: Text(allPinned ? 'Открепить чаты' : 'Закрепить чаты'),
                onTap: () {
                  Navigator.pop(context);
                  _batchTogglePin(selectedChats);
                },
              ),
            // Mark as read
            if (anyUnread)
              ListTile(
                leading: iconoir.DoubleCheck(color: Theme.of(context).colorScheme.primary, width: 22, height: 22),
                title: const Text('Отметить как прочитанные'),
                onTap: () {
                  Navigator.pop(context);
                  _batchMarkAsRead(selectedChats);
                },
              ),
            // Delete (not for saved chat)
            if (deletableChats.isNotEmpty)
              ListTile(
                leading: const iconoir.Trash(color: Colors.red, width: 22, height: 22),
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

    final db = AppDatabase();

    // Оптимистичное обновление SQLite — стрим мгновенно обновит UI
    if (toPin.isNotEmpty) {
      await db.batchSetPinned(toPin.map((c) => c.id).toList(), true);
    }
    if (toUnpin.isNotEmpty) {
      await db.batchSetPinned(toUnpin.map((c) => c.id).toList(), false);
    }
    _exitSelectMode();

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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Обновлено $successCount чатов')),
      );
    }
  }

  /// Batch mark selected chats as read
  Future<void> _batchMarkAsRead(List<Chat> chats) async {
    final db = AppDatabase();
    final ids = chats.map((c) => c.id).toList();

    // Оптимистичное обновление SQLite и провайдера — стрим мгновенно обновит UI
    await db.batchMarkAsRead(ids);
    for (final id in ids) {
      try {
        context.read<UnreadCountProvider>().setCount(id, 0);
      } catch (_) {}
    }
    _exitSelectMode();

    int successCount = 0;
    for (final chat in chats) {
      if (chat.unreadCount > 0) {
        final result = await ChatService.markMessagesAsRead(chatId: chat.id);
        if (result['success'] == true) {
          successCount++;
        }
      }
    }

    if (mounted) {
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
      final db = AppDatabase();
      final ids = chats.map((c) => c.id).toList();

      // Оптимистичное удаление из SQLite — стрим мгновенно обновит UI
      await db.batchDeleteChats(ids);
      _exitSelectMode();

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
    try {
      context.read<UnreadCountProvider>().setOpenChat(chat.id);
    } catch (_) {}
    NotificationService().setActiveChat(chat.id);

    final VoidCallback onReturn = () {
      try {
        context.read<UnreadCountProvider>().setOpenChat(null);
      } catch (_) {}
      NotificationService().setActiveChat(null);
      if (mounted) _refreshChatLastMessage(chat.id);
    };

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
        ).then((_) => onReturn());
        break;
      case 'saved':
        // Open saved chat as a special chat with yourself
        Navigator.push(
          context,
          SwipeBackPageRoute(
            builder: (_) => PrivateChatScreen(
              chatId: chat.id,
              otherUserName: context.l10n.translate('chat_saved_messages').isNotEmpty
                  ? context.l10n.translate('chat_saved_messages')
                  : 'Избранное',
              otherUserAvatar: null,
            ),
          ),
        ).then((_) => onReturn());
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
        ).then((_) => onReturn());
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
        ).then((_) => onReturn());
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
        ).then((_) => onReturn());
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
      if (a.chatType == 'saved' && b.chatType == 'saved') return 0;
      if (a.chatType == 'saved') return -1;
      if (b.chatType == 'saved') return 1;

      // Pinned chats next
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }

      // Then by parsed updated_at to ensure accurate chronological ordering
      final dtA = DateTimeUtils.parseUtcDateTime(a.updatedAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final dtB = DateTimeUtils.parseUtcDateTime(b.updatedAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return dtB.compareTo(dtA);
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
        canPop: _currentIndex == 1 &&
            !_isTopMenuOpen &&
            !_isFolderMenuOpen &&
            !_isSelectMode,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_isTopMenuOpen) {
            _closeTopMenu();
            return;
          }
          if (_isFolderMenuOpen) {
            _closeFolderMenu();
            return;
          }
          if (_isSelectMode) {
            _exitSelectMode();
            return;
          }
          if (_currentIndex != 1) {
            _onTabTapped(1);
          }
        },
        child: Consumer<LiquidGlassProvider>(
          builder: (context, glassProvider, _) {
            // PageView: страница 0 = Настройки, страница 1 = Чаты, страница 2 = Поиск
            // Свайп влево → Настройки, свайп вправо → Чаты
            final Widget pageView = PageView(
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (page) {
                    if (_isTopMenuOpen) {
                      _closeTopMenu();
                    }
                    if (_isFolderMenuOpen) {
                      _closeFolderMenu();
                    }
                    // Закрываем клавиатуру при уходе с поиска
                    if (_currentIndex == 2 && page != 2) {
                      _searchFocusNode.unfocus();
                    }
                    if (_currentIndex != page) {
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
                    }
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
                        child: Builder(
                          builder: (context) {
                            final statusBarHeight =
                                MediaQuery.of(context).padding.top;
                            final topBarHeight = statusBarHeight + 52.0;
                            final playerOffset = (VoicePlaybackService().hasActiveAudio ||
                                    VideoNotePlaybackService().hasActiveVideo)
                                ? 56.0
                                : 0.0;
                            return _buildChatList(
                              topPadding: topBarHeight + 8.0 + playerOffset,
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
                              // Отступ под стационарный верхний бар
                              const SizedBox(height: 52),
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
                                    prefixIcon: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: iconoir.Search(
                                        width: 20,
                                        height: 20,
                                        color: Theme.of(context).iconTheme.color ?? Colors.grey,
                                      ),
                                    ),
                                    suffixIcon: IconButton(
                                      icon: const iconoir.Xmark(width: 20, height: 20),
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
                ); // closes PageView

            final isDark = Theme.of(context).brightness == Brightness.dark;
            final statusBarHeight = MediaQuery.of(context).padding.top;
            final topBarHeight = statusBarHeight + 52.0;

            if (glassProvider.enabled) {
              final double screen = MediaQuery.sizeOf(context).width;
              final double keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
              final double safeBottom = MediaQuery.paddingOf(context).bottom;

              const double barHeight = 60.0;
              const double edgePadding = 16.0;
              const double spacing = 10.0;
              const double actionSize = 60.0;
              const double bottomMargin = 12.0;
              const double maxGroupWidth = 560.0;

              final double totalRequiredWidth = screen - edgePadding * 2;
              final double leftMargin;
              final double actionMargin;
              final double barWidth;

              if (totalRequiredWidth <= maxGroupWidth) {
                leftMargin = edgePadding;
                actionMargin = edgePadding;
                barWidth = totalRequiredWidth - actionSize - spacing;
              } else {
                final double groupLeft = (screen - maxGroupWidth) / 2;
                leftMargin = groupLeft;
                actionMargin = groupLeft;
                barWidth = maxGroupWidth - actionSize - spacing;
              }

              final barStyle = glassProvider.createStyle(
                context: context,
                cornerRadius: barHeight / 2,
                refractionIndex: 1.1,
                refractionWidth: 24.0,
              );

              final actionStyle = barStyle;

              final double effectiveBottomMargin = keyboardHeight > 0
                  ? (bottomMargin + keyboardHeight - safeBottom)
                  : bottomMargin;

              return LiquidGlassScaffold(
                pixelRatio: 1.0,
                useSync: true,
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                appBar: _isSelectMode
                    ? _buildSelectModeBar(context)
                    : _buildTopGlassBar(context, glassProvider),
                appBarTopMargin: 8.0,
                lenses: [
                  if (_isTopMenuOpen || _isFolderMenuOpen)
                    GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (_isTopMenuOpen) _closeTopMenu();
                        if (_isFolderMenuOpen) _closeFolderMenu();
                      },
                    ),
                ],
                body: Scaffold(
                  backgroundColor: Colors.transparent,
                  resizeToAvoidBottomInset: true,
                  body: Stack(
                    children: [
                      pageView,
                      Positioned(
                        top: topBarHeight + 4.0,
                        left: 0,
                        right: 0,
                        child: const MediaNotePlayerHeader(),
                      ),
                    ],
                  ),
                ),
                bottomNavigationBarActionMargin: actionMargin,
                floatingActionButtonMargin: actionMargin,
                bottomNavigationBar: LiquidGlassTabBar(
                  items: [
                    _buildTabBarItem(
                      iconBuilder: (i) => iconoir.Settings(
                        color: i.color,
                        width: i.size,
                        height: i.size,
                      ),
                    ),
                    _buildTabBarItem(
                      iconBuilder: (i) {
                        final icon = iconoir.ChatBubble(
                          color: i.color,
                          width: i.size,
                          height: i.size,
                        );
                        final totalUnread =
                            context.watch<UnreadCountProvider>().totalUnread;
                        if (totalUnread <= 0) return icon;
                        return Stack(
                          clipBehavior: Clip.none,
                          alignment: Alignment.center,
                          children: [
                            icon,
                            Positioned(
                              top: -4,
                              right: -10,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 5, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                constraints: const BoxConstraints(
                                    minWidth: 16, minHeight: 16),
                                child: Text(
                                  totalUnread > 99 ? '99+' : '$totalUnread',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight: FontWeight.bold,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                    _buildTabBarItem(
                      iconBuilder: (i) => iconoir.Search(
                        color: i.color,
                        width: i.size,
                        height: i.size,
                      ),
                    ),
                  ],
                  selectedIndex: _currentIndex,
                  onChanged: (index) {
                    HapticUtils.selection();
                    _onTabTapped(index);
                  },
                  width: barWidth,
                  height: barHeight,
                  alignment: Alignment.bottomLeft,
                  margin: EdgeInsets.only(
                    left: leftMargin,
                    bottom: effectiveBottomMargin,
                  ),
                  itemPadding: 3,
                  style: barStyle,
                  itemStyle: LiquidGlassTabItemStyle(
                    selectedColor: Theme.of(context).colorScheme.primary,
                    unselectedColor: isDark
                        ? const Color(0xFF8E8E93)
                        : const Color(0xFF636366),
                    iconSize: 26,
                    labelFontSize: 10,
                    iconLabelGap: 0,
                    underGlassIconSize: 30,
                    underGlassLabelFontSize: 10,
                    selectedFontWeight: FontWeight.w700,
                    unselectedFontWeight: FontWeight.w600,
                  ),
                  pillStyle: LiquidGlassTabPillStyle(
                    mode: LiquidGlassPillMode.both,
                    show: true,
                    animated: true,
                    growHeight: 7,
                    rest: LiquidGlassStyle(
                      shape: _glassShape(28),
                      color: isDark
                          ? const Color(0x38FFFFFF)
                          : const Color(0x2EAEAEB2),
                    ),
                  ),
                ),
                bottomNavigationBarAction: LiquidGlassButton(
                  width: actionSize,
                  height: actionSize,
                  padding: EdgeInsets.zero,
                  touch: const LiquidGlassTouch(
                    flex: LiquidGlassFlex(
                      stretch: 8,
                      squeeze: 0.65,
                      lean: 0.35,
                      grip: 0.55,
                      holdScale: 0.035,
                      tapScale: 0.025,
                    ),
                  ),
                  foregroundColor:
                      isDark ? Colors.white : const Color(0xFF121215),
                  style: actionStyle,
                  onPressed: () {
                    HapticUtils.tap();
                    _showCreateMenu();
                  },
                  child: iconoir.Plus(
                    color: isDark ? Colors.white : const Color(0xFF121215),
                    width: 28,
                    height: 28,
                  ),
                ),
              );
            }

            // Классический режим — сплошная заливка бара поверх контента
            return Scaffold(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              resizeToAvoidBottomInset: true,
              body: Stack(
                children: [
                  Positioned.fill(child: pageView),
                  if (_isTopMenuOpen || _isFolderMenuOpen)
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          if (_isTopMenuOpen) _closeTopMenu();
                          if (_isFolderMenuOpen) _closeFolderMenu();
                        },
                      ),
                    ),
                  Positioned(
                    top: topBarHeight + 4.0,
                    left: 0,
                    right: 0,
                    child: const MediaNotePlayerHeader(),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _isSelectMode
                        ? SafeArea(child: _buildSelectModeBar(context))
                        : _buildClassicTopBar(context),
                  ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: SafeArea(
                      top: false,
                      child: ClassicBottomBar(
                        selectedIndex: _currentIndex,
                        unreadCount:
                            context.watch<UnreadCountProvider>().totalUnread,
                        onTabSelected: (index) {
                          _onTabTapped(index);
                        },
                        onAddTap: _showCreateMenu,
                        bottomPadding: 12,
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ), // closes PopScope
    ); // closes AnnotatedRegion
  }

  LiquidGlassShape _glassShape(double cornerRadius) =>
      LiquidGlassShape.continuousRoundedRectangle(
        cornerRadius: cornerRadius,
        clipQuality: LiquidGlassClipQuality.exact,
      );

  LiquidGlassTabBarItem _buildTabBarItem({
    required Widget Function(LiquidGlassGlyph i) iconBuilder,
  }) {
    return LiquidGlassTabBarItem(
      iconBuilder: (context, i) => iconBuilder(i),
    );
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
            iconoir.Search(width: 80, height: 80, color: Colors.grey[400]),
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
      padding: const EdgeInsets.only(bottom: 100),
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
                        leading: const iconoir.Group(width: 40, height: 40),
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
                        leading: const iconoir.Megaphone(width: 40, height: 40),
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
                        leading: const iconoir.Message(width: 24, height: 24),
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
            ).then((_) {
              if (mounted) _refreshChatLastMessage(chat.id);
            });
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
          ).then((_) {
            if (mounted) _refreshChatLastMessage(result.id);
          });
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
          ).then((_) {
            if (mounted) _refreshChatLastMessage(result.id);
          });
        }
        break;
      case 'message':
        if (result is SearchResultMessage) {
          final targetChatId = result.channelId.isNotEmpty
              ? result.channelId
              : result.groupId;
          final dbChat = await AppDatabase().getChat(targetChatId);
          final chatType = dbChat?.chatType ??
              (result.channelId.isNotEmpty ? 'channel' : 'group');

          if (!mounted) return;
          if (chatType == 'private') {
            Navigator.push(
              context,
              SwipeBackPageRoute(
                builder: (_) => PrivateChatScreen(
                  chatId: targetChatId,
                  otherUserName: dbChat?.name ?? '',
                  highlightMessageId: result.id,
                ),
              ),
            );
          } else if (chatType == 'group') {
            Navigator.push(
              context,
              SwipeBackPageRoute(
                builder: (_) => GroupChatScreen(
                  chatId: targetChatId,
                  groupName: dbChat?.name ?? '',
                  highlightMessageId: result.id,
                ),
              ),
            );
          } else {
            Navigator.push(
              context,
              SwipeBackPageRoute(
                builder: (_) => ChannelScreen(
                  channelId: targetChatId,
                  channelName: dbChat?.name,
                  channelAvatar: dbChat?.avatarUrl,
                  highlightMessageId: result.id,
                ),
              ),
            );
          }
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

class _MorphMenuItemData {
  final String id;
  final String label;
  final Widget Function(Color color, double size) iconBuilder;
  final Color? color;

  const _MorphMenuItemData({
    required this.id,
    required this.label,
    required this.iconBuilder,
    this.color,
  });
}

class _ThreeDotsGlyph extends StatelessWidget {
  final double size;
  final VoidCallback onTap;

  const _ThreeDotsGlyph({
    super.key,
    required this.size,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        width: size,
        height: size,
        child: Center(
          child: iconoir.MoreVert(
            width: 22.0,
            height: 22.0,
            color: isDark ? Colors.white : const Color(0xFF1C1C1E),
          ),
        ),
      ),
    );
  }
}

class _TopMorphMenu extends StatelessWidget {
  final double width;
  final List<_MorphMenuItemData> items;
  final ValueChanged<String> onItemTap;

  const _TopMorphMenu({
    super.key,
    required this.width,
    required this.items,
    required this.onItemTap,
  });

  @override
  Widget build(BuildContext context) {
    final double totalHeight = items.length * 44.0 + 12.0;
    return SizedBox(
      width: width,
      height: totalHeight,
      child: OverflowBox(
        minWidth: width,
        maxWidth: width,
        minHeight: 0,
        maxHeight: totalHeight,
        alignment: Alignment.topCenter,
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < items.length; i++)
                    _MorphMenuRow(
                      key: ValueKey(items[i].id),
                      item: items[i],
                      onTap: () => onItemTap(items[i].id),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MorphMenuRow extends StatelessWidget {
  final _MorphMenuItemData item;
  final VoidCallback onTap;

  const _MorphMenuRow({
    super.key,
    required this.item,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final itemColor = item.color ?? defaultColor;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 44.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0),
          child: Row(
              children: [
                item.iconBuilder(itemColor, 20.0),
                const SizedBox(width: 10.0),
                Expanded(
                  child: Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15.0,
                      fontWeight: FontWeight.w500,
                      color: itemColor,
                      letterSpacing: -0.2,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
  }
}

class _TitlePillContent extends StatelessWidget {
  final String title;
  final String titleKey;
  final bool isConnected;
  final VoidCallback? onTap;

  const _TitlePillContent({
    super.key,
    required this.title,
    required this.titleKey,
    required this.isConnected,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isConnected
        ? (isDark ? Colors.white : const Color(0xFF1C1C1E))
        : Colors.grey;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 44.0,
        padding: const EdgeInsets.symmetric(horizontal: 20.0),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              transitionBuilder: (child, animation) {
                final inAnimation = Tween<Offset>(
                  begin: const Offset(0.0, -1.0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                ));
                final outAnimation = Tween<Offset>(
                  begin: const Offset(0.0, 1.0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeInCubic,
                ));
                final isIncoming = child.key == ValueKey<String>(titleKey);
                return ClipRect(
                  child: SlideTransition(
                    position: isIncoming ? inAnimation : outAnimation,
                    child: FadeTransition(
                      opacity: animation,
                      child: child,
                    ),
                  ),
                );
              },
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  alignment: Alignment.center,
                  clipBehavior: Clip.none,
                  children: [
                    ...previousChildren.map(
                      (w) => Positioned.fill(
                        child: Center(
                          child: OverflowBox(
                            minWidth: 0,
                            maxWidth: double.infinity,
                            minHeight: 0,
                            maxHeight: double.infinity,
                            child: w,
                          ),
                        ),
                      ),
                    ),
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              child: Text(
                title,
                key: ValueKey<String>(titleKey),
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  color: textColor,
                  letterSpacing: -0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FolderMorphMenu extends StatelessWidget {
  final double width;
  final int activeFilter;
  final List<ChatFolder> folders;
  final List<int> unreadCounts;
  final ValueChanged<int> onSelectFolder;

  const _FolderMorphMenu({
    super.key,
    required this.width,
    required this.activeFilter,
    required this.folders,
    required this.unreadCounts,
    required this.onSelectFolder,
  });

  Widget _buildFolderIcon(String iconName, Color color, double size) {
    switch (iconName) {
      case 'chat':
        return iconoir.ChatBubble(color: color, width: size, height: size);
      case 'user':
        return iconoir.User(color: color, width: size, height: size);
      case 'group':
        return iconoir.Group(color: color, width: size, height: size);
      case 'megaphone':
        return iconoir.Megaphone(color: color, width: size, height: size);
      case 'folder':
      default:
        return iconoir.Folder(color: color, width: size, height: size);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final folderItems = <_FolderMenuItemData>[];
    for (int i = 0; i < folders.length; i++) {
      final f = folders[i];
      String label = f.name;
      if (f.id == 'all') {
        final tr = l10n.translate('filter_all');
        if (tr.isNotEmpty) label = tr;
      } else if (f.id == 'personal') {
        final tr = l10n.translate('filter_personal');
        if (tr.isNotEmpty) label = tr;
      } else if (f.id == 'groups') {
        final tr = l10n.translate('filter_groups');
        if (tr.isNotEmpty) label = tr;
      } else if (f.id == 'channels') {
        final tr = l10n.translate('filter_channels');
        if (tr.isNotEmpty) label = tr;
      }
      folderItems.add(
        _FolderMenuItemData(
          index: i,
          label: label,
          iconBuilder: (color, size) => _buildFolderIcon(f.iconName, color, size),
        ),
      );
    }

    final double totalHeight = math.max(44.0, folders.length * 44.0 + 12.0);
    return SizedBox(
      width: width,
      height: totalHeight,
      child: OverflowBox(
        minWidth: width,
        maxWidth: width,
        minHeight: 0,
        maxHeight: totalHeight,
        alignment: Alignment.topCenter,
        child: Material(
          color: Colors.transparent,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6.0),
            child: SingleChildScrollView(
              physics: const NeverScrollableScrollPhysics(),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (int i = 0; i < folderItems.length; i++)
                    _FolderMenuRow(
                      key: ValueKey('folder_${folders[i].id}_${folderItems[i].index}'),
                      item: folderItems[i],
                      isSelected: activeFilter == folderItems[i].index,
                      unreadCount: folderItems[i].index < unreadCounts.length
                          ? unreadCounts[folderItems[i].index]
                          : 0,
                      onTap: () => onSelectFolder(folderItems[i].index),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _FolderMenuItemData {
  final int index;
  final String label;
  final Widget Function(Color color, double size) iconBuilder;

  const _FolderMenuItemData({
    required this.index,
    required this.label,
    required this.iconBuilder,
  });
}

class _FolderMenuRow extends StatelessWidget {
  final _FolderMenuItemData item;
  final bool isSelected;
  final int unreadCount;
  final VoidCallback onTap;

  const _FolderMenuRow({
    super.key,
    required this.item,
    required this.isSelected,
    required this.unreadCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final defaultColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final accentColor = Theme.of(context).colorScheme.primary;
    final itemColor = isSelected ? accentColor : defaultColor;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 44.0,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14.0),
          child: Row(
            children: [
              item.iconBuilder(itemColor, 20.0),
              const SizedBox(width: 10.0),
              Expanded(
                child: Text(
                  item.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15.0,
                    fontWeight:
                        isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: itemColor,
                    letterSpacing: -0.2,
                  ),
                ),
              ),
              if (unreadCount > 0) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? accentColor
                        : (isDark
                            ? Colors.white.withValues(alpha: 0.16)
                            : Colors.black.withValues(alpha: 0.08)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(minWidth: 18),
                  child: Text(
                    '$unreadCount',
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : (isDark ? Colors.white : const Color(0xFF1C1C1E)),
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(width: 8.0),
              ],
              if (isSelected)
                iconoir.Check(width: 18.0, height: 18.0, color: accentColor)
              else
                const SizedBox(width: 18.0),
            ],
          ),
        ),
      ),
    );
  }
}



