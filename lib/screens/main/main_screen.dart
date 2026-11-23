import '../../utils/image_utils.dart';
import 'package:flutter/foundation.dart';
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
import '../../screens/chat/create_chat_screen.dart';
import '../../screens/contacts/contacts_screen.dart';
import '../../screens/settings/settings_screen.dart';
import '../../screens/settings/profile_screen.dart';
import '../../screens/chat/private_chat_screen.dart';
import '../../screens/chat/group_chat_screen.dart';
import '../../screens/chat/channel_screen.dart';
import '../../screens/chat/forum_topics_screen.dart';
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
import '../../services/peer_customization_cache.dart';
import '../../services/profile_instant_cache.dart';
import '../../services/chat_instant_cache.dart';
import '../../services/profile_theme_provider.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/unread_count_provider.dart';
import '../../screens/auth/login_screen.dart';
import '../../l10n/app_localizations.dart';
import '../../models/theav_theme.dart';
import '../../widgets/chat/classic_bottom_bar.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import '../../widgets/settings/settings_group.dart';
import '../../services/sync_service.dart';
import '../../services/database/app_database.dart';
import '../../utils/swipe_back_route.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/blur_utils.dart';
import '../../services/update_service.dart';
import '../settings/widgets/update_dialog.dart';
import '../../widgets/chat/media_note_player_header.dart';
import '../../widgets/call/call_device_transfer_banner.dart';
import '../../widgets/notifications/notification_permission_dialog.dart';
import '../../widgets/notifications/huawei_autostart_prompt.dart';
import '../../services/notification_service.dart';
import '../../services/notification_settings_provider.dart';
import '../../services/settings_service.dart';
import '../../services/proximity_audio_service.dart';
import '../../services/archive_preferences_service.dart';
import '../chat/archived_chats_screen.dart';
import '../../models/chat_folder.dart';
import '../../services/chat_folder_service.dart';
import '../../services/chat_swipe_service.dart';
import '../../services/voice_playback_service.dart';
import '../../services/video_note_playback_service.dart';
import '../../services/tiling_layout_controller.dart';
import '../../widgets/chat/chat_batch_dialogs.dart';
import '../../widgets/chat/chat_list_tile_item.dart';
import '../../widgets/chat/chat_selection_header.dart';
import '../../widgets/common/peer_badges_widget.dart';
import '../../widgets/tiling/tile_viewport_scope.dart';
import '../../models/community_models.dart';
import '../../services/community_service.dart';
import '../community/community_screen.dart';
import '../community/create_community_screen.dart';

class MainScreen extends StatefulWidget {
  const MainScreen({Key? key}) : super(key: key);

  @override
  State<MainScreen> createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen>
    with WidgetsBindingObserver, TickerProviderStateMixin {
  int _currentIndex = 1; // 0: Settings, 1: Chats, 2: Search
  final Set<int> _visitedPages = <int>{1};
  int _activeFilter = 0; // Index of the active folder in _folderService.folders
  final ChatFolderService _folderService = ChatFolderService();
  String _lastTilingSignature = '';
  Timer? _saveChatsDebounceTimer;

  void _scheduleSaveChats() {
    _saveChatsDebounceTimer?.cancel();
    _saveChatsDebounceTimer = Timer(const Duration(milliseconds: 650), () {
      if (mounted) {
        _localStorage.saveChats(_chats);
      }
    });
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _onTilingUpdate() {
    if (!mounted) return;
    final tiling = TilingLayoutController.instance;
    final isTwoCol =
        tiling.windowSize.width >= TilingLayoutController.kTwoColumnBreakpoint;
    // В однооконном мобильном режиме (< 640px) список чатов не подсвечивает активный тайл справа,
    // поэтому не вызываем лишний полный setState() всех строк чатов в момент старта анимации открытия чата.
    final sig = isTwoCol
        ? '${tiling.chatTiles.map((t) => t.chatId).join(",")}|${tiling.focusedChatTile?.chatId ?? ""}|1|${tiling.isWorkspaceMounted}'
        : 'single|${tiling.isWorkspaceMounted}';
    if (sig != _lastTilingSignature) {
      _lastTilingSignature = sig;
      setState(() {});
    }
  }

  // PageController для свайпа между Настройками и Чатами
  final PageController _pageController = PageController(initialPage: 1);
  final ScrollController _chatsScrollController = ScrollController();
  static const ValueKey<String> _pageViewKey = ValueKey<String>('main_page_view');
  bool? _lastGlassEnabled;

  // Search functionality
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  String _searchQuery = '';
  String _searchFilter = 'all'; // all, chats, users, groups, channels, messages
  Timer? _searchDebounce;
  UnifiedSearchResult _unifiedSearchResult = UnifiedSearchResult.empty;
  final Set<String> _joiningPeerIds = {};

  // Chats list & Communities
  List<Chat> _chats = [];
  List<Chat> _archivedChats = [];
  List<Community> _communities = [];
  bool _isLoadingChats = true;
  StreamSubscription<List<DbChat>>? _chatsStreamSubscription;
  StreamSubscription<List<DbChat>>? _archivedChatsStreamSubscription;
  String? _currentUserId;
  final Map<String, ({bool isOnline, String? lastSeen})> _liveUserPresence = {};
  final Map<String, ({String action, String? userName, Timer timer})>
      _chatTypingStates = {};
  final Map<String, List<MessageEntity>> _chatLastMessageEntities = {};

  Future<void> _loadCommunities() async {
    final list = await CommunityService.getCommunities();
    if (!mounted) return;
    final staleChannelIds = _chats
        .where((c) => CommunityService.isCommunityChannelId(c.id))
        .map((c) => c.id)
        .toList();
    if (staleChannelIds.isNotEmpty) {
      try {
        await AppDatabase(_currentUserId).batchDeleteChats(staleChannelIds);
      } catch (_) {}
    }
    if (!mounted) return;
    setState(() {
      _communities = list.where((c) => c.isMember).toList();
      _chats.removeWhere((c) => CommunityService.isCommunityChannelId(c.id));
    });
  }

  Chat _communityToChat(Community c) {
    final activeVoice = c.activeVoiceCount;
    final subtitle = activeVoice > 0
        ? '🔊 $activeVoice в голосовом • ${c.memberCount} участн.'
        : (c.description.isNotEmpty
            ? c.description
            : '${c.memberCount} участн. • Сообщество');
    return Chat(
      id: 'community_${c.id}',
      chatType: 'community',
      name: c.name,
      avatarUrl: c.avatarUrl,
      lastMessage: subtitle,
      lastMessageTime: c.createdAt.toIso8601String(),
      lastMessageType: 'text',
      updatedAt: c.createdAt.toIso8601String(),
      unreadCount: c.totalUnreadCount,
      otherUserId: c.id,
    );
  }

  List<Chat> get _chatsWithCommunities {
    final visibleChats = _chats
        .where((c) => !CommunityService.isCommunityChannelId(c.id))
        .toList();
    final existingIds = visibleChats.map((c) => c.id).toSet();
    final communityChats = _communities
        .where((c) => c.isMember)
        .map(_communityToChat)
        .where((cc) => !existingIds.contains(cc.id))
        .toList();
    return [...visibleChats, ...communityChats];
  }

  void _onCommunityCreated(Community createdCommunity) {
    if (!createdCommunity.isMember) return;
    CommunityService.cacheCommunity(createdCommunity);
    if (!mounted) return;
    setState(() {
      _communities = [
        createdCommunity,
        ..._communities.where((c) => c.id != createdCommunity.id),
      ];
      _chats.removeWhere((c) => CommunityService.isCommunityChannelId(c.id));
    });
  }

  Future<void> _showCreateCommunityDialog({bool initialJoinMode = false}) async {
    await Navigator.push(
      context,
      SwipeBackPageRoute(
        builder: (_) => CreateCommunityScreen(
          initialJoinMode: initialJoinMode,
          onCommunityCreated: _onCommunityCreated,
        ),
      ),
    );
    if (mounted) {
      _loadCommunities();
    }
  }

  void _initChatsStream() {
    _chatsStreamSubscription?.cancel();
    _archivedChatsStreamSubscription?.cancel();
    _currentUserId ??= _accountManager.currentAccount?.userId;
    final db = AppDatabase(_currentUserId);
    _archivedChatsStreamSubscription = db.watchArchivedChats().listen((dbArchived) {
      if (!mounted) return;
      final archived = dbArchived
          .where((c) =>
              c.chatType != 'community' &&
              c.chatType != 'community_channel' &&
              !CommunityService.isCommunityChannelId(c.chatId))
          .map(_dbChatToChat)
          .toList();
      setState(() => _archivedChats = archived);
      ChatInstantCache.instance.putChatSummaries(archived);
    });
    _chatsStreamSubscription = db.watchChats().listen((dbChats) async {
      if (!mounted) return;
      final mappedChats = <Chat>[];
      bool hasSaved = false;
      for (final dbChat in dbChats) {
        if (dbChat.chatType == 'community' ||
            dbChat.chatType == 'community_channel' ||
            CommunityService.isCommunityChannelId(dbChat.chatId)) {
          continue;
        }
        try {
          final lastMsg = await db.getLastMessageForChat(dbChat.chatId);
          if (lastMsg != null && lastMsg.content == dbChat.lastMessage) {
            final dbEntities = Message.fromDbMessage(lastMsg).entities;
            if (dbEntities.isNotEmpty ||
                lastMsg.createdAt == dbChat.lastMessageTime) {
              _chatLastMessageEntities[dbChat.chatId] = dbEntities;
            }
          }
        } catch (_) {}
        final chat = _dbChatToChat(dbChat);
        // Only keep one saved chat
        if (chat.chatType == 'saved') {
          if (hasSaved) continue;
          hasSaved = true;
        }
        // Exclude empty private chats with no message, no draft, not pinned
        if (chat.chatType == 'private' &&
            (chat.lastMessage == null || chat.lastMessage!.isEmpty) &&
            (chat.draft == null || chat.draft!.text.isEmpty) &&
            !chat.isPinned) {
          continue;
        }
        mappedChats.add(chat);
      }
      setState(() {
        _chats = mappedChats;
        if (_isLoadingChats && _chats.isNotEmpty) {
          _isLoadingChats = false;
        }
      });
      DraftService().populateFromChats(_chats);
      ChatInstantCache.instance.putChatSummaries(_chats);
      unawaited(
        ChatInstantCache.instance.prewarmFromDatabase(
          _currentUserId,
          chatIds: _chats.take(20).map((c) => c.id),
        ),
      );
    });
  }

  // Multi-select mode
  bool _isSelectMode = false;
  Set<String> _selectedChatIds = {};
  bool _isSelectionMenuOpen = false;
  final ValueNotifier<({double extent, bool armed})> _archivePullNotifier =
      ValueNotifier<({double extent, bool armed})>((extent: 0.0, armed: false));
  static const double _kArchivePullThreshold = 58.0;

  // Top glass bar & morph context menu
  bool _isTopMenuOpen = false;

  // Central folder morph menu
  bool _isFolderMenuOpen = false;

  // Bottom-right '+' create chat morph menu
  bool _isCreateMenuOpen = false;

  // Animation controllers for selection bottom bar hide & Material '+' menu
  late final AnimationController _selectModeController;
  late final AnimationController _classicCreateMenuController;
  late final CurvedAnimation _selectModeAnimation;
  late final CurvedAnimation _classicCreateMenuAnimation;

  // Loading states
  bool _isLoading = false;

  // Account manager
  final AccountManager _accountManager = AccountManager();

  // WebSocket
  final WebSocketService _wsService = WebSocketService();
  StreamSubscription<WebSocketEvent>? _wsSubscription;
  bool _isWsConnected = false;
  Timer? _connectionCheckTimer;
  Timer? _updateCheckTimer;
  DateTime? _lastUpdateCheckAt;

  @override
  void initState() {
    super.initState();
    _selectModeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _selectModeAnimation = CurvedAnimation(
      parent: _selectModeController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _classicCreateMenuController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 280),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _classicCreateMenuAnimation = CurvedAnimation(
      parent: _classicCreateMenuController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    WidgetsBinding.instance.addObserver(this);
    _searchController.addListener(_onSearchChanged);
    DraftService().draftsNotifier.addListener(_onDraftsChanged);
    _accountManager.addListener(_onAccountChanged);
    _folderService.addListener(_onServiceUpdate);
    ChatSwipeService().addListener(_onServiceUpdate);
    VoicePlaybackService().addListener(_onServiceUpdate);
    VideoNotePlaybackService().addListener(_onServiceUpdate);
    ArchivePreferencesService().addListener(_onServiceUpdate);
    TilingLayoutController.instance.addListener(_onTilingUpdate);
    TilingLayoutController.instance.registerTileBackHandler(
      TilingLayoutController.kLeftTileId,
      _handleLeftTileBack,
    );
    TilingLayoutController.instance.onMainScreenHandleBack =
        _handleMainScreenRootBack;
    TilingLayoutController.instance.onChatTileClosed = _onChatTileClosed;

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

  bool _handleLeftTileBack() {
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return false;
    if (_isTopMenuOpen) {
      _closeTopMenu();
      return true;
    }
    if (_isSelectionMenuOpen) {
      setState(() => _isSelectionMenuOpen = false);
      return true;
    }
    if (_isFolderMenuOpen) {
      _closeFolderMenu();
      return true;
    }
    if (_isCreateMenuOpen) {
      _closeCreateMenu();
      return true;
    }
    if (_isSelectMode) {
      _exitSelectMode();
      return true;
    }
    return false;
  }

  bool _handleMainScreenRootBack() {
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return false;
    if (_handleLeftTileBack()) return true;
    if (_currentIndex != 1) {
      _onTabTapped(1);
      return true;
    }
    return false;
  }

  void _onChatTileClosed(String chatId) {
    if (mounted) {
      _refreshChatLastMessage(chatId);
    }
  }

  /// Последовательная инициализация: Drift → стрим чатов → чаты с сервера → WebSocket
  Future<void> _initApp() async {
    _currentUserId = _accountManager.currentAccount?.userId;
    AppDatabase.setActiveUser(_currentUserId);
    unawaited(ArchivePreferencesService().init());

    // 1. Немедленно подписываемся на локальный стрим SQLite (UI мгновенно получает кэш)
    _initChatsStream();

    // 2. Инициализация Drift и фоновая синхронизация (не блокирует первичную загрузку чатов)
    unawaited(_initOfflineFirst());

    // 3. Загрузка чатов и сообществ (фоновый запрос к серверу)
    _loadChats();
    _loadCommunities();

    // 3. WebSocket (параллельно, не блокирует UI)
    _initWebSocket();
    _startConnectionCheck();
    ProximityAudioService.instance.registerListeners();

    // 4. Проверка обновлений в фоне + периодический таймер
    unawaited(AppUpdateService.instance.init());
    _checkForUpdates();
    _updateCheckTimer?.cancel();
    _updateCheckTimer = Timer.periodic(
      const Duration(hours: 4),
      (_) => _checkForUpdates(fromBackgroundTimer: true),
    );

    // 5. Запрос разрешения на уведомления при первом входе
    _checkNotificationPermission();
  }

  Future<void> _checkNotificationPermission() async {
    // Небольшая задержка, чтобы дать экрану полностью отрендериться
    await Future.delayed(const Duration(milliseconds: 1200));
    if (!mounted) return;
    await NotificationPermissionDialog.checkAndPrompt(context);
    if (!mounted) return;
    await HuaweiAutoStartPrompt.maybeShow(context);
  }

  Future<void> _checkForUpdates({bool fromBackgroundTimer = false}) async {
    if (kIsWeb) return;
    try {
      final isAutoCheck = await AppUpdateService.instance.isAutoCheckEnabled();
      if (!isAutoCheck) return;

      if (!fromBackgroundTimer) {
        // Небольшая задержка, чтобы не забивать сеть в момент первичной отричной отрисовки UI
        await Future.delayed(const Duration(seconds: 2));
      }
      if (!mounted) return;

      _lastUpdateCheckAt = DateTime.now();
      final update = await AppUpdateService.instance.checkForUpdate(silent: true);
      if (!mounted) return;

      if (update.hasUpdate) {
        final shouldNotify = await AppUpdateService.instance.shouldNotifyDevice(update);
        if (shouldNotify) {
          await NotificationService().showAppUpdateNotification(update);
          await AppUpdateService.instance.markDeviceNotified(update.latestBuild);
        }
        final shouldPrompt = await AppUpdateService.instance.shouldPromptInApp(update);
        if (!fromBackgroundTimer && shouldPrompt && mounted) {
          UpdateDialog.show(context, update, isManual: false);
        }
      }
    } catch (e) {
      debugPrint('MainScreen: Background update check error: $e');
    }
  }

  void _onAppUpdateAvailable(WebSocketEvent event) {
    if (kIsWeb) return;
    debugPrint('MainScreen: app_update_available WS event received: ${event.data}');
    if (!mounted) return;
    _checkForUpdates(fromBackgroundTimer: false);
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
      _loadCommunities();
    }
  }

  Future<void> _initWebSocket() async {
    _wsSubscription?.cancel();
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
    _wsService.subscribe(WebSocketEventType.appUpdateAvailable, _onAppUpdateAvailable);
    _wsService.subscribe(WebSocketEventType.chatArchiveUpdated, _onChatArchiveUpdated);
    _wsService.subscribe(WebSocketEventType.typing, _onChatTyping);

    // Now connect — the 'connected' event will be caught by our listeners
    await _wsService.connect();

    // If already connected after connect(), sync state immediately
    // (in case the broadcast event was still missed)
    if (_wsService.isConnected && mounted) {
      setState(() => _isWsConnected = true);
    }
  }

  void _onChatTyping(WebSocketEvent event) {
    final chatId = event.data['chat_id']?.toString();
    if (chatId == null || chatId.isEmpty) return;

    final typingUserId = event.data['user_id']?.toString();
    if (typingUserId != null && typingUserId == _currentUserId) return;

    final action = event.data['action']?.toString() ?? 'typing';
    final bool isTyping = event.data['is_typing'] != false && action != 'stop';

    if (!isTyping) {
      final existing = _chatTypingStates.remove(chatId);
      existing?.timer.cancel();
      if (mounted && existing != null) {
        setState(() {});
      }
      return;
    }

    final userName = event.data['user_name']?.toString();
    _chatTypingStates[chatId]?.timer.cancel();
    final timer = Timer(const Duration(seconds: 4), () {
      _chatTypingStates.remove(chatId);
      if (mounted) {
        setState(() {});
      }
    });
    _chatTypingStates[chatId] = (
      action: action,
      userName: userName,
      timer: timer,
    );
    if (mounted) {
      setState(() {});
    }
  }

  void _handleWebSocketEvent(WebSocketEvent event) {
    // Update connection status
    if (event.type == WebSocketEventType.connected) {
      setState(() => _isWsConnected = true);
    }
    final rawType = event.rawType.isNotEmpty
        ? event.rawType
        : (event.data['__raw_type'] ?? event.data['type'] ?? '').toString();
    if (rawType.startsWith('community.') && mounted) {
      _loadCommunities();
    }
  }

  void _onWsConnected(WebSocketEvent event) {
    debugPrint('WebSocket connected: ${event.data}');
    if (mounted) {
      setState(() => _isWsConnected = true);
      _loadChats();
      _loadCommunities();

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
      if (chatData['community_id'] != null ||
          event.data['community_id'] != null) {
        if (mounted) _loadCommunities();
        return;
      }
      final newChat = Chat.fromJson(chatData);
      if (newChat.isCommunityChannel) {
        if (mounted) _loadCommunities();
        return;
      }
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
    final communityId =
        event.data['community_id']?.toString() ??
        messageData?['community_id']?.toString();

    if ((communityId != null && communityId.isNotEmpty) ||
        (chatId != null && CommunityService.isCommunityChannelId(chatId))) {
      if (mounted) {
        _loadCommunities();
      }
      return;
    }

    if (chatId != null && mounted) {
      final existingTyping = _chatTypingStates.remove(chatId);
      existingTyping?.timer.cancel();
      // NOTE: UnreadCountProvider already increments via its own _onNewMessage
      // subscriber (initialized in initialize()). Do NOT call provider.increment()
      // here — that would cause double-counting.

      final chatIndex = _chats.indexWhere((c) => c.id == chatId);
      if (chatIndex != -1) {
        Message? parsedMsg;
        if (messageData != null) {
          try {
            parsedMsg = Message.fromJson(messageData);
          } catch (_) {}
        }
        if (parsedMsg != null &&
            (parsedMsg.threadRootMessageId == null ||
                parsedMsg.threadRootMessageId!.isEmpty)) {
          ChatInstantCache.instance.upsertMessage(chatId, parsedMsg);
        }
        final isThreadComment = parsedMsg?.threadRootMessageId != null &&
            parsedMsg!.threadRootMessageId!.isNotEmpty;

        Chat? updatedChat;
        if (!isThreadComment) {
          final msgEntities = parsedMsg?.entities ?? const <MessageEntity>[];
          final senderId = parsedMsg?.senderId ??
              messageData?['sender_id']?.toString();
          final senderName = parsedMsg?.senderName ??
              messageData?['sender_name']?.toString();

          setState(() {
            final chat = _chats[chatIndex];

            // Get unread count from provider (authoritative source)
            int newUnreadCount = chat.unreadCount;
            try {
              newUnreadCount =
                  context.read<UnreadCountProvider>().getCount(chatId);
            } catch (_) {}

            final msgType = messageData?['message_type'] as String? ?? 'text';
            final isRound =
                messageData?['is_round'] == true || msgType == 'round';
            final fileUrl = messageData?['file_url'] as String?;
            final groupedId = messageData?['grouped_id'] as String?;
            final content = messageData?['content'] as String? ?? '';
            _chatLastMessageEntities[chatId] = msgEntities;

            final newChat = chat.copyWith(
              lastMessage: content,
              lastMessageTime:
                  messageData?['created_at'] as String? ?? chat.lastMessageTime,
              lastMessageType: msgType,
              lastMessageIsRound: isRound,
              lastMessageFileUrl: fileUrl,
              lastMessageGroupedId: groupedId,
              lastMessageEntities: msgEntities,
              lastMessageSenderId: senderId,
              lastMessageSenderName: senderName,
              updatedAt: messageData?['created_at'] as String? ?? chat.updatedAt,
              unreadCount: newUnreadCount,
            );
            updatedChat = newChat;

            // Update the chat in place
            _chats[chatIndex] = newChat;
            // Re-sort: pinned/saved chats stay in their fixed positions,
            // unpinned chats sort by updated_at
            _sortChats();
          });
          if (updatedChat != null) {
            ChatInstantCache.instance.putChatSummaries([updatedChat!]);
          }
          // Save to local storage
          _localStorage.saveChats(_chats);
        }

        // Сохранить в Drift только поля последнего сообщения (чтобы не затереть unreadCount и isOnline)
        final db = AppDatabase(_currentUserId);
        if (updatedChat != null) {
          try {
            db.updateChatLastMessage(
              chatId: updatedChat!.id,
              content: updatedChat!.lastMessage ?? '',
              createdAt: updatedChat!.lastMessageTime ??
                  DateTime.now().toIso8601String(),
              messageType: updatedChat!.lastMessageType ?? 'text',
              isRound: updatedChat!.lastMessageIsRound,
              fileUrl: updatedChat!.lastMessageFileUrl,
              groupedId: updatedChat!.lastMessageGroupedId,
              senderId: updatedChat!.lastMessageSenderId,
              senderName: updatedChat!.lastMessageSenderName,
              incrementUnread: false,
            );
          } catch (_) {}
        }
        if (parsedMsg != null) {
          try {
            db.saveMessage(parsedMsg.toCompanion());
          } catch (_) {}
        }
      } else {
        // Chat was not in the list yet, reload chats seamlessly
        _loadChats(silent: true);
      }
    }
  }

  void _onChatArchiveUpdated(WebSocketEvent event) {
    final chatId =
        event.data['chat_id']?.toString() ?? event.data['id']?.toString();
    if (chatId == null || chatId.isEmpty) return;
    final isArchived =
        event.data['is_archived'] == true || event.data['is_archived'] == 1;
    unawaited(AppDatabase(_currentUserId).setChatArchived(chatId, isArchived));
  }

  void _onChatUpdate(WebSocketEvent event) {
    debugPrint('Chat update received: ${event.data}');
    final chatData = event.data['chat'] as Map<String, dynamic>?;
    final chatId = event.data['chat_id']?.toString();
    final communityId = event.data['community_id']?.toString() ??
        chatData?['community_id']?.toString();
    if ((communityId != null && communityId.isNotEmpty) ||
        (chatId != null && CommunityService.isCommunityChannelId(chatId))) {
      if (mounted) _loadCommunities();
      return;
    }

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
    final chatId = event.data['chat_id']?.toString();
    final rawOutboxHwm =
        event.data['last_read_outbox_message_id'] ?? event.data['max_id'];
    final outboxHwm = rawOutboxHwm is num
        ? rawOutboxHwm.toInt()
        : int.tryParse(rawOutboxHwm?.toString() ?? '');
    if (chatId != null && outboxHwm != null && outboxHwm > 0) {
      try {
        AppDatabase(_currentUserId).markOutboxMessagesReadUpTo(
          chatId,
          _currentUserId ?? '',
          outboxHwm,
          readAt: event.data['read_at']?.toString(),
        );
      } catch (_) {}
    }
  }

  /// Handle unread count updates from the server — the authoritative source for unread counts
  void _onUnreadCountUpdated(WebSocketEvent event) {
    debugPrint('Unread count updated: ${event.data}');
    final chatId = event.data['chat_id']?.toString();
    final unreadCount = event.data['unread_count'] as int? ?? 0;
    final rawInboxHwm = event.data['last_read_inbox_message_id'];
    final inboxHwm = rawInboxHwm is num
        ? rawInboxHwm.toInt()
        : int.tryParse(rawInboxHwm?.toString() ?? '');

    if (chatId != null && mounted) {
      try {
        context.read<UnreadCountProvider>().setCount(chatId, unreadCount);
      } catch (_) {}

      _syncChatUnreadCount(chatId, unreadCount, lastReadInboxMessageId: inboxHwm);
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
    final effectiveLastSeen =
        lastSeen ?? (isOnline ? null : DateTime.now().toIso8601String());

    if (userId != null) {
      _liveUserPresence[userId] = (
        isOnline: isOnline,
        lastSeen: effectiveLastSeen,
      );
      try {
        AppDatabase(_currentUserId).updateUserStatus(
          userId,
          isOnline: isOnline,
          lastSeen: effectiveLastSeen,
        );
      } catch (_) {}
    }

    if (userId != null && mounted) {
      setState(() {
        for (int i = 0; i < _chats.length; i++) {
          if (_chats[i].chatType == 'private' &&
              _chats[i].otherUserId == userId) {
            _chats[i] = _chats[i].copyWith(
              isOnline: isOnline,
              lastSeen: effectiveLastSeen,
            );
          }
        }
      });
      _localStorage.saveChats(_chats);
    }
  }

  /// Handle real-time avatar updates for current user or contacts
  void _onUserAvatarUpdated(WebSocketEvent event) {
    final userId = event.data['user_id']?.toString();
    final rawAvatarUrl = event.data['avatar_url']?.toString();
    if (userId == null) return;
    final avatarUrl = (rawAvatarUrl != null && rawAvatarUrl.isNotEmpty)
        ? (getValidAvatarUrl(rawAvatarUrl) ?? rawAvatarUrl)
        : rawAvatarUrl;

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

    ProfileInstantCache.instance.updateUserAvatar(userId, avatarUrl);

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
    if (userId != null && userId.isNotEmpty) {
      PeerCustomizationCache.instance.mergeFromJson(userId, event.data);
    }
    final currentAccount = _accountManager.currentAccount;
    if (currentAccount != null && currentAccount.userId == userId && mounted) {
      context.read<ProfileThemeProvider>().applyAppearanceUpdateMap(
            event.data,
            targetUserId: userId,
          );
    }
    if (userId != null && userId.isNotEmpty && mounted) {
      final updatedCust = PeerCustomizationCache.instance.getSync(userId);
      if (updatedCust != null) {
        final idx = _chats.indexWhere(
          (c) => c.chatType == 'private' && c.otherUserId == userId,
        );
        if (idx != -1) {
          setState(() {
            _chats[idx] = _chats[idx].copyWith(peerCustomization: updatedCust);
          });
        }
      }
    }
  }

  void _onMessageDeleted(WebSocketEvent event) async {
    debugPrint('Message deleted received in MainScreen: ${event.data}');
    final chatId = event.data['chat_id']?.toString();
    final messageId =
        (event.data['message_id'] ?? event.data['messageId'])?.toString();
    if (chatId != null) {
      if (messageId != null) {
        ChatInstantCache.instance.removeMessages(chatId, [messageId]);
        try {
          await AppDatabase().deleteMessage(messageId);
        } catch (_) {}
      }
      if (mounted) {
        await _refreshChatLastMessage(chatId, allowClear: true);
      }
    }
  }

  Future<void> _refreshChatLastMessage(String chatId, {bool allowClear = false}) async {
    try {
      final db = AppDatabase();
      final lastMsg = await db.getLastMessageForChat(chatId);
      if (lastMsg != null) {
        _chatLastMessageEntities[chatId] = Message.fromDbMessage(lastMsg).entities;
      } else if (allowClear) {
        _chatLastMessageEntities.remove(chatId);
      }
      await db.refreshChatLastMessageFromDb(chatId, allowClear: allowClear);
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
        _scheduleSaveChats();
      }
    } catch (_) {}
  }

  /// Update a single chat's unread count in _chats and persist
  void _syncChatUnreadCount(
    String chatId,
    int unreadCount, {
    int? lastReadInboxMessageId,
  }) {
    setState(() {
      final chatIndex = _chats.indexWhere((c) => c.id == chatId);
      if (chatIndex != -1) {
        _chats[chatIndex] = _chats[chatIndex].copyWith(
          unreadCount: unreadCount,
          lastReadInboxMessageId: lastReadInboxMessageId,
        );
      }
    });

    // Сохранить в Drift
    final db = AppDatabase();
    try {
      if (lastReadInboxMessageId != null && lastReadInboxMessageId > 0) {
        db.updateChatReadHwm(
          chatId,
          lastReadInboxMessageId: lastReadInboxMessageId,
          unreadCount: unreadCount,
        );
      } else {
        db.updateUnreadCount(chatId, unreadCount);
      }
    } catch (_) {}

    _scheduleSaveChats();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // При возврате из фона: переподключить WS если не подключён, затем обновить чаты.
      // Состояние foreground/background отслеживает сам NotificationService.
      if (!_isWsConnected) {
        _wsService.tryReconnect();
        _loadChats();
      }
      if (_lastUpdateCheckAt == null ||
          DateTime.now().difference(_lastUpdateCheckAt!) > const Duration(hours: 1)) {
        _checkForUpdates(fromBackgroundTimer: true);
      }
    }
  }

  // Local storage service
  final LocalStorageService _localStorage = LocalStorageService();

  Future<void> _loadChats({bool silent = false}) async {
    final bool isInitialLoad = _chats.isEmpty;
    if (isInitialLoad && !silent && !_isLoadingChats) {
      setState(() => _isLoadingChats = true);
    }

    _currentUserId ??= _accountManager.currentAccount?.userId;
    final db = AppDatabase(_currentUserId);
    await db.ensureInitialized();

    // Фоновая загрузка с сервера (бесшовное обновление локальной БД)
    try {
      final result = await ChatService.getChats();

      if (mounted) {
        if (result['success'] == true && result['chats'] is List<Chat>) {
          final serverChats = (result['chats'] as List<Chat>)
              .where((c) => !c.isCommunityChannel)
              .toList();
          DraftService().populateFromChats(serverChats);
          ChatInstantCache.instance.putChatSummaries(serverChats);

          for (final chat in serverChats) {
            _chatLastMessageEntities[chat.id] = chat.lastMessageEntities;
            if (chat.chatType == 'private' &&
                chat.otherUserId != null &&
                chat.otherUserId!.isNotEmpty) {
              _liveUserPresence[chat.otherUserId!] = (
                isOnline: chat.isOnline,
                lastSeen: chat.lastSeen,
              );
            }
          }

          // Обновить провайдер ДО сохранения в Drift, чтобы при срабатывании
          // реактивного стрима watchChats() провайдер уже имел актуальные значения
          try {
            context.read<UnreadCountProvider>().loadFromChats(serverChats);
          } catch (_) {}

          // Удалить из локальной БД устаревшие чаты (например, каналы сообществ),
          // которых больше нет в списке чатов сервера
          try {
            final serverIds = serverChats.map((c) => c.id).toSet();
            final staleIds = [..._chats, ..._archivedChats]
                .where(
                  (c) =>
                      c.chatType != 'saved' &&
                      !c.id.startsWith('saved_') &&
                      (c.isCommunityChannel ||
                          !serverIds.contains(c.id)),
                )
                .map((c) => c.id)
                .toList();
            if (staleIds.isNotEmpty) {
              await db.batchDeleteChats(staleIds);
            }
          } catch (_) {}

          // Сохранить в Drift — это автоматически обновит _chats через reactive stream!
          try {
            final chatModels = serverChats.map(_chatToCompanion).toList();
            await db.saveChats(chatModels);
          } catch (e) {
            debugPrint('MainScreen: Error saving to Drift: $e');
          }

          // Фоновый предзагруз сообщений для топ-10 активных чатов в Drift
          _prefetchRecentMessages(serverChats);
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

  /// Параллельная предзагрузка сообщений для всех чатов пользователя батчами,
  /// чтобы при открытии любого чата сообщения отображались мгновенно без lazy-задержки.
  void _prefetchRecentMessages(List<Chat> chats) {
    unawaited(() async {
      try {
        final db = AppDatabase(_currentUserId);
        const int batchSize = 8;
        for (int i = 0; i < chats.length; i += batchSize) {
          if (!mounted) break;
          final end = (i + batchSize < chats.length) ? i + batchSize : chats.length;
          final batch = chats.sublist(i, end);
          await Future.wait(
            batch.map((chat) async {
              if (!mounted) return;
              try {
                final res = await ChatService.getMessages(chatId: chat.id, limit: 50);
                if (res['success'] == true && res['messages'] is List<Message>) {
                  final msgs = res['messages'] as List<Message>;
                  if (msgs.isNotEmpty) {
                    ChatInstantCache.instance.putMessages(chat.id, msgs);
                    await db.saveMessages(
                      msgs.map((m) => m.toCompanion(fallbackChatId: chat.id)).toList(),
                    );
                    await db.refreshChatLastMessageFromDb(chat.id);
                  }
                }
              } catch (_) {}
            }),
          );
        }
      } catch (e) {
        debugPrint('MainScreen: _prefetchRecentMessages error: $e');
      }
    }());
  }

  /// Ensure "Saved Messages" / "Favorites" chat exists
  Future<void> _ensureSavedChatExists() async {
    try {
      final userId = await AuthService.getUserId();
      final db = AppDatabase(userId);
      if (userId != null) {
        await db.ensureSavedChatExists(userId);
      }

      // Secondary sync: Request saved chat from server
      debugPrint('Requesting saved chat from server for sync...');
      final result = await ChatService.getOrCreateSavedChat();

      if (result['success'] == true && result['chat'] != null) {
        final savedChat = result['chat'] as Chat;
        _chatLastMessageEntities[savedChat.id] = savedChat.lastMessageEntities;
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
    String name = model.name;
    if (name.trim().isEmpty || name.trim() == '?') {
      if (model.chatType == 'saved') {
        name = 'Избранное';
      } else if (model.chatType == 'private') {
        name = 'Пользователь';
      } else {
        name = 'Чат';
      }
    }
    String? avatarUrl = model.avatarUrl;
    if (model.chatType == 'saved' && (avatarUrl == null || avatarUrl.isEmpty)) {
      avatarUrl = _accountManager.currentAccount?.avatarUrl;
    }

    int effectiveUnreadCount = model.unreadCount;
    if (mounted) {
      try {
        final provider = context.read<UnreadCountProvider>();
        if (provider.hasAuthoritativeCount(model.chatId)) {
          effectiveUnreadCount = provider.getCount(model.chatId);
        }
      } catch (_) {}
    }

    bool effectiveIsOnline = model.isOnline;
    String? effectiveLastSeen = model.lastSeen;
    if (model.chatType == 'private' &&
        model.otherUserId != null &&
        _liveUserPresence.containsKey(model.otherUserId)) {
      final live = _liveUserPresence[model.otherUserId]!;
      effectiveIsOnline = live.isOnline;
      effectiveLastSeen = live.lastSeen ?? model.lastSeen;
    }

    return Chat.fromDbChat(
      model,
      lastMessageEntities: _chatLastMessageEntities[model.chatId] ?? const [],
      unreadCountOverride: effectiveUnreadCount,
      isOnlineOverride: effectiveIsOnline,
      lastSeenOverride: effectiveLastSeen,
    ).copyWith(
      name: name,
      avatarUrl: avatarUrl,
    );
  }

  /// Конвертация Chat (UI) → ChatsCompanion (Drift)
  ChatsCompanion _chatToCompanion(Chat chat) {
    String? avatarUrl = chat.avatarUrl;
    if (chat.chatType == 'saved' && (avatarUrl == null || avatarUrl.isEmpty)) {
      avatarUrl = _accountManager.currentAccount?.avatarUrl;
    }
    final normalized = avatarUrl != chat.avatarUrl
        ? chat.copyWith(avatarUrl: avatarUrl)
        : chat;
    return normalized.toCompanion();
  }

  @override
  void dispose() {
    _selectModeAnimation.dispose();
    _classicCreateMenuAnimation.dispose();
    _selectModeController.dispose();
    _classicCreateMenuController.dispose();
    _archivePullNotifier.dispose();
    NotificationService().isMainScreenReady = false;
    WidgetsBinding.instance.removeObserver(this);
    DraftService().draftsNotifier.removeListener(_onDraftsChanged);
    _accountManager.removeListener(_onAccountChanged);
    _folderService.removeListener(_onServiceUpdate);
    ChatSwipeService().removeListener(_onServiceUpdate);
    VoicePlaybackService().removeListener(_onServiceUpdate);
    VideoNotePlaybackService().removeListener(_onServiceUpdate);
    ArchivePreferencesService().removeListener(_onServiceUpdate);
    TilingLayoutController.instance.removeListener(_onTilingUpdate);
    TilingLayoutController.instance.unregisterTileBackHandler(
      TilingLayoutController.kLeftTileId,
      _handleLeftTileBack,
    );
    if (TilingLayoutController.instance.onMainScreenHandleBack ==
        _handleMainScreenRootBack) {
      TilingLayoutController.instance.onMainScreenHandleBack = null;
    }
    if (TilingLayoutController.instance.onChatTileClosed ==
        _onChatTileClosed) {
      TilingLayoutController.instance.onChatTileClosed = null;
    }
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _pageController.dispose();
    _chatsScrollController.dispose();
    _wsSubscription?.cancel();
    _connectionCheckTimer?.cancel();
    _updateCheckTimer?.cancel();
    _chatsStreamSubscription?.cancel();
    _archivedChatsStreamSubscription?.cancel();
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
    _wsService.unsubscribe(WebSocketEventType.appUpdateAvailable, _onAppUpdateAvailable);
    _wsService.unsubscribe(WebSocketEventType.chatArchiveUpdated, _onChatArchiveUpdated);
    _wsService.unsubscribe(WebSocketEventType.typing, _onChatTyping);
    if (_saveChatsDebounceTimer?.isActive ?? false) {
      _saveChatsDebounceTimer!.cancel();
      _localStorage.saveChats(_chats);
    }
    for (final state in _chatTypingStates.values) {
      state.timer.cancel();
    }
    _chatTypingStates.clear();
    // Remove UnreadCountProvider listener
    try {
      context.read<UnreadCountProvider>().removeListener(_onUnreadCountProviderChanged);
    } catch (_) {}
    super.dispose();
  }

  void _onAccountChanged() {
    if (!mounted) return;
    final newUserId = _accountManager.currentAccount?.userId;
    if (newUserId == _currentUserId) {
      // Profile, token, or settings updated for current account in background.
      // Do NOT clear chats or reconnect WebSocket!
      return;
    }
    debugPrint('[MainScreen] Active account changed: $_currentUserId -> $newUserId. Refreshing state and WS...');
    _currentUserId = newUserId;
    TilingLayoutController.instance.closeAllChats();
    try {
      VoicePlaybackService().stopVoice();
      VideoNotePlaybackService().stopActivePlayback();
    } catch (_) {}
    if (_isSelectMode) {
      _exitSelectMode();
    }
    _liveUserPresence.clear();
    _saveChatsDebounceTimer?.cancel();
    for (final state in _chatTypingStates.values) {
      state.timer.cancel();
    }
    _chatTypingStates.clear();
    AppDatabase.setActiveUser(newUserId);
    unawaited(ArchivePreferencesService().init());
    CommunityService.clearMemoryCache();
    ChatInstantCache.instance.clearMemory();

    setState(() {
      _activeFilter = 0;
      _chats = [];
      _communities = [];
      _isLoadingChats = true;
    });
    if (_currentIndex != 1) {
      _onTabTapped(1);
    }
    _initChatsStream();
    // Disconnect old WebSocket, reconnect with new account token, reload chats
    _wsService.disconnect();
    _initWebSocket();
    _loadChats();
    _loadCommunities();
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
      _searchDebounce?.cancel();
      final trimmed = _searchQuery.trim();
      if (trimmed.isEmpty) {
        setState(() {
          _unifiedSearchResult = UnifiedSearchResult.empty;
          _isLoading = false;
        });
        return;
      }
      _performLocalMainSearch(trimmed);
      _searchDebounce =
          Timer(const Duration(milliseconds: 280), _performSearch);
    }
  }

  Future<void> _performLocalMainSearch(String q) async {
    final localRes = await SearchService.searchLocal(query: q);
    if (mounted && _searchQuery.trim() == q) {
      setState(() {
        _unifiedSearchResult = localRes;
      });
    }
  }

  Future<void> _performSearch() async {
    final q = _searchQuery.trim();
    if (q.isEmpty) {
      setState(() {
        _unifiedSearchResult = UnifiedSearchResult.empty;
        _isLoading = false;
      });
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await SearchService.search(query: q);

      if (mounted && _searchQuery.trim() == q) {
        setState(() {
          _unifiedSearchResult = _unifiedSearchResult.mergeWithServer(result);
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
      return _chats.fold(
          0,
          (sum, chat) =>
              sum + (chat.unreadCount == -1 ? 1 : (chat.unreadCount > 0 ? chat.unreadCount : 0)));
    }
  }

  void _onTabTapped(int index) {
    if (_isTopMenuOpen) {
      _closeTopMenu();
    }
    if (_isFolderMenuOpen) {
      _closeFolderMenu();
    }
    if (_isCreateMenuOpen) {
      _closeCreateMenu();
    }
    if (_currentIndex == index) return;
    // Закрываем клавиатуру при уходе с поиска
    if (_currentIndex == 2 && index != 2) {
      _searchFocusNode.unfocus();
    }
    setState(() {
      _currentIndex = index;
      _visitedPages.add(index);
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

  void _onTabReselected(int index) {
    if (_isTopMenuOpen) {
      _closeTopMenu();
    }
    if (_isFolderMenuOpen) {
      _closeFolderMenu();
    }
    if (_isCreateMenuOpen) {
      _closeCreateMenu();
    }
    if (index == 1) {
      if (_chatsScrollController.hasClients &&
          _chatsScrollController.offset > 0) {
        _chatsScrollController.animateTo(
          0.0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
      return;
    }
    if (index == 2) {
      _searchFocusNode.requestFocus();
      return;
    }
    if (index == 0) {
      final primaryScroll = PrimaryScrollController.maybeOf(context);
      if (primaryScroll != null &&
          primaryScroll.hasClients &&
          primaryScroll.offset > 0) {
        primaryScroll.animateTo(
          0.0,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
        );
      }
    }
  }

  void _openCreateMenu() {
    if (_isCreateMenuOpen) return;
    if (_isTopMenuOpen) {
      _closeTopMenu();
    }
    if (_isFolderMenuOpen) {
      _closeFolderMenu();
    }
    HapticUtils.tap();
    _classicCreateMenuController.forward();
    setState(() {
      _isCreateMenuOpen = true;
    });
  }

  void _closeCreateMenu() {
    if (!_isCreateMenuOpen) return;
    _classicCreateMenuController.reverse();
    setState(() {
      _isCreateMenuOpen = false;
    });
  }

  void _toggleCreateMenu() {
    if (_isCreateMenuOpen) {
      _closeCreateMenu();
    } else {
      _openCreateMenu();
    }
  }

  void _handleCreateOptionSelected(CreateChatOptionType type) {
    _closeCreateMenu();
    switch (type) {
      case CreateChatOptionType.privateChat:
        Navigator.push(
          context,
          SwipeBackPageRoute(
            builder: (_) => CreatePrivateChatScreen(
              onCommunityCreated: _onCommunityCreated,
            ),
          ),
        );
        break;
      case CreateChatOptionType.groupChat:
        Navigator.push(
          context,
          SwipeBackPageRoute(builder: (_) => const CreateGroupScreen()),
        );
        break;
      case CreateChatOptionType.channel:
        Navigator.push(
          context,
          SwipeBackPageRoute(builder: (_) => const CreateChannelScreen()),
        );
        break;
      case CreateChatOptionType.community:
        _showCreateCommunityDialog(initialJoinMode: false);
        break;
      case CreateChatOptionType.joinByCode:
        _showCreateCommunityDialog(initialJoinMode: true);
        break;
      case CreateChatOptionType.contacts:
        Navigator.push(
          context,
          SwipeBackPageRoute(builder: (_) => const ContactsScreen()),
        );
        break;
    }
  }

  // ── Top Glass Bar & Morph Menu Logic ──────────────────────────────

  void _openTopMenu() {
    if (_isTopMenuOpen) return;
    if (_isFolderMenuOpen) {
      _closeFolderMenu();
    }
    if (_isCreateMenuOpen) {
      _closeCreateMenu();
    }
    HapticUtils.tap();
    setState(() {
      _isSelectionMenuOpen = false;
      _isTopMenuOpen = true;
    });
  }

  void _closeTopMenu() {
    if (!_isTopMenuOpen) return;
    setState(() {
      _isTopMenuOpen = false;
    });
  }

  void _openFolderMenu() {
    if (_currentIndex != 1) return;
    if (_isFolderMenuOpen) return;
    if (_isTopMenuOpen) {
      _closeTopMenu();
    }
    if (_isCreateMenuOpen) {
      _closeCreateMenu();
    }
    HapticUtils.tap();
    setState(() {
      _isSelectionMenuOpen = false;
      _isFolderMenuOpen = true;
    });
  }

  void _closeFolderMenu() {
    if (!_isFolderMenuOpen) return;
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

  List<SelectionMorphMenuItem> _getMenuItems(int index, [BuildContext? ctx]) {
    final targetCtx = ctx ?? context;
    final l10n = targetCtx.l10n;
    switch (index) {
      case 0: // Settings
        return [
          SelectionMorphMenuItem(
            id: 'profile',
            label: l10n.translate('settings_profile'),
            iconBuilder: (color, size) => iconoir.User(color: color, width: size, height: size),
          ),
          SelectionMorphMenuItem(
            id: 'clear_data',
            label: l10n.translate('clear_data_title'),
            iconBuilder: (color, size) => iconoir.Trash(color: color, width: size, height: size),
            color: Colors.orange,
          ),
          SelectionMorphMenuItem(
            id: 'logout',
            label: l10n.translate('menu_logout'),
            iconBuilder: (color, size) => iconoir.LogOut(color: color, width: size, height: size),
            color: Colors.red,
          ),
        ];
      case 2: // Search
        return [
          SelectionMorphMenuItem(
            id: 'clear_search',
            label: 'Очистить поиск',
            iconBuilder: (color, size) => iconoir.Trash(color: color, width: size, height: size),
          ),
          SelectionMorphMenuItem(
            id: 'profile',
            label: l10n.translate('settings_profile'),
            iconBuilder: (color, size) => iconoir.User(color: color, width: size, height: size),
          ),
        ];
      case 1: // Chats
      default:
        final showArchiveMenuItem =
            ArchivePreferencesService().isHiddenAboveList &&
                _archivedChats.isNotEmpty;
        return [
          SelectionMorphMenuItem(
            id: 'select_chats',
            label: l10n.translate('chat_select_chats'),
            iconBuilder: (color, size) => iconoir.ListSelect(color: color, width: size, height: size),
          ),
          if (showArchiveMenuItem)
            SelectionMorphMenuItem(
              id: 'open_archive',
              label: l10n.translate('archive_title'),
              iconBuilder: (color, size) => iconoir.Archive(color: color, width: size, height: size),
            ),
          SelectionMorphMenuItem(
            id: 'new_chat',
            label: l10n.translate('chat_new_private'),
            iconBuilder: (color, size) => iconoir.UserPlus(color: color, width: size, height: size),
          ),
          SelectionMorphMenuItem(
            id: 'new_group',
            label: l10n.translate('chat_new_group'),
            iconBuilder: (color, size) => iconoir.Group(color: color, width: size, height: size),
          ),
          SelectionMorphMenuItem(
            id: 'new_channel',
            label: l10n.translate('chat_new_channel'),
            iconBuilder: (color, size) => iconoir.Megaphone(color: color, width: size, height: size),
          ),
          SelectionMorphMenuItem(
            id: 'new_community',
            label: 'Новое сообщество',
            iconBuilder: (color, size) => Icon(Icons.hub_outlined, color: color, size: size),
          ),
          SelectionMorphMenuItem(
            id: 'join_by_code',
            label: 'Войти по коду',
            iconBuilder: (color, size) => Icon(Icons.tag_rounded, color: color, size: size),
          ),
          SelectionMorphMenuItem(
            id: 'profile',
            label: l10n.translate('settings_profile'),
            iconBuilder: (color, size) => iconoir.User(color: color, width: size, height: size),
          ),
        ];
    }
  }

  void _handleMenuAction(String actionId) {
    _closeTopMenu();

    switch (actionId) {
      case 'select_chats':
        _enterSelectMode();
        break;
      case 'open_archive':
        _openArchivedChatsScreen();
        break;
      case 'new_chat':
        Navigator.push(
          context,
          SwipeBackPageRoute(
            builder: (_) => CreatePrivateChatScreen(
              onCommunityCreated: _onCommunityCreated,
            ),
          ),
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
      case 'new_community':
        _showCreateCommunityDialog(initialJoinMode: false);
        break;
      case 'join_by_code':
        _showCreateCommunityDialog(initialJoinMode: true);
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
          _unifiedSearchResult = UnifiedSearchResult.empty;
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
              TilingLayoutController.instance.closeAllChats();
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
              TilingLayoutController.instance.closeAllChats();
              nav.pushAndRemoveUntil(
                SwipeBackPageRoute(builder: (_) => const LoginScreen()),
                (route) => false,
              );
              try {
                WebSocketService().disconnect();
                await AuthService.logout();
                await AppDatabase.deleteAllDatabases();
                await CacheService().clearCache();
                await CacheService().clearAllPermanentUserDirs();
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

  Widget _buildAdaptiveTopBar(BuildContext context) {
    final notifProvider = context.watch<NotificationSettingsProvider>();
    final folders = _folderService.folders;
    final activeFolder = (_activeFilter >= 0 && _activeFilter < folders.length)
        ? folders[_activeFilter]
        : (folders.isNotEmpty ? folders.first : ChatFolder.defaults.first);
    final folderChats = _chatsWithCommunities
        .where((chat) => activeFolder.matchesChat(chat))
        .toList();
    final selectedChats = folderChats
        .where((c) => _selectedChatIds.contains(c.id))
        .toList();
    final regularSelected = selectedChats
        .where((c) => c.chatType != 'saved' && c.chatType != 'community')
        .toList();
    final nonSavedSelected =
        selectedChats.where((c) => c.chatType != 'saved').toList();

    final allPinned = regularSelected.isNotEmpty &&
        regularSelected.every((c) => c.isPinned);
    final allMuted = regularSelected.isNotEmpty &&
        regularSelected.every(
          (c) => notifProvider.isChatMuted(c.id, chatType: c.chatType),
        );
    final anyUnread = regularSelected
        .any((c) => c.unreadCount > 0 || c.unreadCount == -1);
    final allSelected =
        folderChats.isNotEmpty && selectedChats.length == folderChats.length;
    final canSplit = TilingLayoutController.instance.windowSize.width >=
        TilingLayoutController.kTwoColumnBreakpoint;

    const double folderMenuWidth = 220.0;
    final double folderMenuHeight =
        math.max(44.0, folders.length * 44.0 + 12.0);

    final overflowItems = <SelectionMorphMenuItem>[
      if (selectedChats.length == 1 && canSplit)
        SelectionMorphMenuItem(
          id: 'open_adjacent',
          label: context.l10n.translate('selection_open_adjacent'),
          iconBuilder: (color, size) =>
              iconoir.ViewColumns2(color: color, width: size, height: size),
        ),
      if (regularSelected.isNotEmpty)
        SelectionMorphMenuItem(
          id: 'toggle_read',
          label: context.l10n.translate(
            anyUnread ? 'selection_mark_read' : 'selection_mark_unread',
          ),
          iconBuilder: (color, size) =>
              iconoir.DoubleCheck(color: color, width: size, height: size),
        ),
      if (selectedChats.isNotEmpty)
        SelectionMorphMenuItem(
          id: 'add_to_folder',
          label: context.l10n.translate('selection_add_to_folder'),
          iconBuilder: (color, size) =>
              iconoir.Folder(color: color, width: size, height: size),
        ),
      if (selectedChats.any((c) => c.chatType != 'community'))
        SelectionMorphMenuItem(
          id: 'clear_history',
          label: context.l10n.translate('selection_clear_history'),
          iconBuilder: (color, size) =>
              iconoir.Erase(color: color, width: size, height: size),
        ),
      if (folderChats.isNotEmpty)
        SelectionMorphMenuItem(
          id: 'select_all',
          label: context.l10n.translate(
            allSelected ? 'selection_deselect_all' : 'selection_select_all',
          ),
          iconBuilder: (color, size) =>
              iconoir.ListSelect(color: color, width: size, height: size),
        ),
    ];

    return ChatListAdaptiveTopBar(
      isSelectMode: _isSelectMode,
      selectedCount: selectedChats.length,
      onCancelSelection: _exitSelectMode,
      isSelectionOverflowOpen: _isSelectionMenuOpen,
      onSelectionOverflowOpenChanged: (open) {
        if (open) {
          if (_isTopMenuOpen) _closeTopMenu();
          if (_isFolderMenuOpen) _closeFolderMenu();
          if (_isCreateMenuOpen) _closeCreateMenu();
        }
        setState(() => _isSelectionMenuOpen = open);
      },
      selectionConfig: SelectionQuickActionsConfig(
        canPin: nonSavedSelected.isNotEmpty,
        isUnpin: allPinned,
        onPin: () => _batchTogglePin(nonSavedSelected),
        canMute: regularSelected.isNotEmpty,
        isUnmute: allMuted,
        onMute: () => _batchToggleMute(regularSelected),
        canArchive: regularSelected.isNotEmpty,
        isUnarchive: false,
        onArchive: () => _batchArchiveChats(regularSelected),
        canDelete: nonSavedSelected.isNotEmpty,
        onDelete: () => _batchDeleteChats(nonSavedSelected),
        overflowItems: overflowItems,
        onOverflowAction: (id) async {
          switch (id) {
            case 'open_adjacent':
              if (selectedChats.isNotEmpty) {
                final target = selectedChats.first;
                _exitSelectMode();
                _openChat(target, inAdjacentTile: true);
              }
              break;
            case 'toggle_read':
              await _batchToggleRead(regularSelected);
              break;
            case 'add_to_folder':
              final applied = await ChatBatchDialogs.showAddToFolderSheet(
                context,
                selectedChats,
              );
              if (applied && mounted) _exitSelectMode();
              break;
            case 'clear_history':
              await ChatBatchDialogs.executeClearHistory(
                context,
                selectedChats,
                currentUserId: _currentUserId,
                onBeforeExecute: _exitSelectMode,
              );
              break;
            case 'select_all':
              _selectAllOrDeselect(folderChats);
              break;
          }
        },
      ),
      normalTitle: _currentTitleText,
      normalTitleKey: _currentTitleKey,
      isTitleConnected: _isTitleConnected,
      onTitleTap: _currentIndex == 1 ? _toggleFolderMenu : null,
      openCenterMenu: _currentIndex == 1
          ? _FolderMorphMenu(
              key: const ValueKey<String>('folder_menu'),
              width: folderMenuWidth,
              activeFilter: _activeFilter,
              folders: folders,
              unreadCounts: List.generate(
                folders.length,
                (index) => _getUnreadCountForFilter(index),
              ),
              onSelectFolder: (index) {
                HapticUtils.selection();
                setState(() => _activeFilter = index);
                _closeFolderMenu();
              },
            )
          : null,
      openCenterMenuWidth: folderMenuWidth,
      openCenterMenuHeight: folderMenuHeight,
      isCenterMenuOpen: _currentIndex == 1 && _isFolderMenuOpen,
      onDismissCenterMenu: _closeFolderMenu,
      normalMenuItems: _getMenuItems(_currentIndex, context),
      isNormalMenuOpen: _isTopMenuOpen,
      onNormalMenuOpenChanged: (open) {
        if (open) {
          _openTopMenu();
        } else {
          _closeTopMenu();
        }
      },
      onNormalMenuAction: _handleMenuAction,
    );
  }

  /// Calculate number of chats with unread messages for a specific filter index
  int _getUnreadCountForFilter(int filterIndex) {
    final folders = _folderService.folders;
    if (filterIndex >= 0 && filterIndex < folders.length) {
      final folder = folders[filterIndex];
      return _chatsWithCommunities
          .where((chat) =>
              folder.matchesChat(chat) &&
              (chat.unreadCount > 0 || chat.unreadCount == -1))
          .length;
    }
    return 0;
  }

  void _openArchivedChatsScreen() {
    if (_isSelectMode) _exitSelectMode();
    Navigator.push(
      context,
      SwipeBackPageRoute(
        builder: (_) => const ArchivedChatsScreen(),
      ),
    );
  }

  Future<void> _hideArchiveAboveList() async {
    HapticUtils.impact();
    await ArchivePreferencesService().setHiddenAboveList(true);
    if (!mounted) return;
    final l10n = context.l10n;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(l10n.translate('archive_hidden_toast')),
        action: SnackBarAction(
          label: l10n.translate('common_undo'),
          onPressed: () {
            unawaited(ArchivePreferencesService().setHiddenAboveList(false));
          },
        ),
      ),
    );
  }

  Future<void> _markAllArchivedRead() async {
    final unread = _archivedChats
        .where((c) => c.unreadCount > 0 || c.unreadCount == -1)
        .toList();
    if (unread.isEmpty) return;

    final db = AppDatabase(_currentUserId);
    final ids = unread.map((c) => c.id).toList();
    UnreadCountProvider? unreadProvider;
    try {
      unreadProvider = context.read<UnreadCountProvider>();
    } catch (_) {}

    await db.batchMarkAsRead(ids);
    for (final id in ids) {
      unreadProvider?.setCount(id, 0);
    }
    for (final chat in unread) {
      if (chat.unreadCount > 0) {
        unawaited(ChatService.markMessagesAsRead(chatId: chat.id));
      }
    }
  }

  Future<void> _showArchiveRowContextMenu(
    BuildContext itemContext,
    Offset? globalPos,
  ) async {
    final overlay = Overlay.of(context, rootOverlay: true)
        .context
        .findRenderObject() as RenderBox?;
    if (overlay == null) return;

    Offset anchorPos;
    if (globalPos != null) {
      anchorPos = globalPos;
    } else {
      final box = itemContext.findRenderObject() as RenderBox?;
      if (box != null) {
        anchorPos = box.localToGlobal(box.size.center(Offset.zero));
      } else {
        anchorPos = overlay.size.center(Offset.zero);
      }
    }

    final hasUnread = _archivedChats
        .any((c) => c.unreadCount > 0 || c.unreadCount == -1);
    final l10n = context.l10n;
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final selected = await showMenu<String>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(anchorPos.dx, anchorPos.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      items: [
        PopupMenuItem<String>(
          value: 'hide',
          child: Row(
            children: [
              iconoir.EyeClosed(width: 18, height: 18, color: onSurface),
              const SizedBox(width: 10),
              Text(l10n.translate('archive_hide_above_list')),
            ],
          ),
        ),
        if (hasUnread)
          PopupMenuItem<String>(
            value: 'mark_all_read',
            child: Row(
              children: [
                iconoir.DoubleCheck(width: 18, height: 18, color: onSurface),
                const SizedBox(width: 10),
                Text(l10n.translate('archive_mark_all_read')),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'settings',
          child: Row(
            children: [
              iconoir.Settings(width: 18, height: 18, color: onSurface),
              const SizedBox(width: 10),
              Text(l10n.translate('archive_settings')),
            ],
          ),
        ),
      ],
    );

    if (!mounted || selected == null) return;
    switch (selected) {
      case 'hide':
        await _hideArchiveAboveList();
        break;
      case 'mark_all_read':
        await _markAllArchivedRead();
        break;
      case 'settings':
        await ChatBatchDialogs.showArchiveSettingsSheet(context);
        break;
    }
  }

  Widget _buildChatList(BuildContext context, {double topPadding = 8}) {
    final l10n = context.l10n;
    final double safeTopPadding = math.max(0.0, topPadding);

    if (_isLoadingChats && _chats.isEmpty && _communities.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: safeTopPadding),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    final folders = _folderService.folders;
    final activeFolder = (_activeFilter >= 0 && _activeFilter < folders.length)
        ? folders[_activeFilter]
        : (folders.isNotEmpty ? folders.first : ChatFolder.defaults.first);

    final allItems = _chatsWithCommunities;
    final List<Chat> filteredChats =
        allItems.where((chat) => activeFolder.matchesChat(chat)).toList();

    final bool hasArchivedInAll =
        activeFolder.id == 'all' && _archivedChats.isNotEmpty;
    final bool isArchiveHidden = ArchivePreferencesService().isHiddenAboveList;
    final bool showArchivedTile = hasArchivedInAll && !isArchiveHidden;
    final bool enablePullReveal =
        hasArchivedInAll && isArchiveHidden && !_isSelectMode;

    if (filteredChats.isEmpty && !showArchivedTile && !enablePullReveal) {
      if (_isLoadingChats && activeFolder.id != 'communities') {
        return Padding(
          padding: EdgeInsets.only(top: safeTopPadding),
          child: const Center(child: CircularProgressIndicator()),
        );
      }
      if (activeFolder.id == 'communities') {
        final primaryColor = Theme.of(context).colorScheme.primary;
        return Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: Icon(
                    Icons.hub_rounded,
                    size: 40,
                    color: primaryColor,
                  ),
                ),
                const SizedBox(height: 16),
                const Text(
                  'Сообщества Theaver',
                  style: TextStyle(
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Категории, текстовые и голосовые комнаты со стримингом экрана до 144 FPS, трибуны и гибкие роли.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: Colors.grey[500],
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton.icon(
                  onPressed: _showCreateCommunityDialog,
                  icon: const Icon(Icons.add_rounded),
                  label: const Text('Создать или войти по коду'),
                ),
              ],
            ),
          ),
        );
      }
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

    final Widget scrollList = ListView.builder(
      controller: _chatsScrollController,
      cacheExtent: 600.0,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.only(
        top: safeTopPadding,
        bottom: 100,
      ),
      itemCount: filteredChats.length + (showArchivedTile ? 1 : 0),
      itemBuilder: (itemContext, index) {
        if (showArchivedTile && index == 0) {
          return _buildArchivedChatsHeaderTile(itemContext);
        }
        final chat = filteredChats[showArchivedTile ? index - 1 : index];
        return _buildChatListItem(itemContext, chat);
      },
    );

    if (!enablePullReveal) {
      return scrollList;
    }

    final primaryColor = Theme.of(context).colorScheme.primary;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final current = _archivePullNotifier.value;
        if (notification is ScrollUpdateNotification) {
          if (notification.metrics.pixels < 0) {
            final pull = (-notification.metrics.pixels).clamp(0.0, 96.0);
            if (notification.dragDetails != null) {
              final armed = pull >= _kArchivePullThreshold;
              if (armed && !current.armed) {
                HapticUtils.impact();
              }
              if ((pull - current.extent).abs() > 0.5 ||
                  armed != current.armed) {
                _archivePullNotifier.value = (extent: pull, armed: armed);
              }
            } else {
              if (current.armed) {
                _archivePullNotifier.value = (extent: 0.0, armed: false);
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted) _openArchivedChatsScreen();
                });
              } else if (current.extent > 0) {
                _archivePullNotifier.value = (extent: pull, armed: false);
              }
            }
          } else if (current.extent > 0 || current.armed) {
            _archivePullNotifier.value = (extent: 0.0, armed: false);
          }
        } else if (notification is ScrollEndNotification) {
          if (current.armed) {
            _archivePullNotifier.value = (extent: 0.0, armed: false);
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) _openArchivedChatsScreen();
            });
          } else if (current.extent > 0) {
            _archivePullNotifier.value = (extent: 0.0, armed: false);
          }
        }
        return false;
      },
      child: Stack(
        children: [
          Positioned.fill(child: scrollList),
          ValueListenableBuilder<({double extent, bool armed})>(
            valueListenable: _archivePullNotifier,
            builder: (context, pullState, _) {
              if (pullState.extent <= 2.0) {
                return const SizedBox.shrink();
              }
              final double pullProgress =
                  (pullState.extent / _kArchivePullThreshold).clamp(0.0, 1.0);
              return Positioned(
                top: safeTopPadding + 4,
                left: 16,
                right: 16,
                child: IgnorePointer(
                  child: Opacity(
                    opacity: pullProgress,
                    child: Transform.translate(
                      offset: Offset(0, -10.0 * (1.0 - pullProgress)),
                      child: Center(
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          decoration: BoxDecoration(
                            color: pullState.armed
                                ? primaryColor.withValues(alpha: 0.18)
                                : (isDark
                                    ? const Color(0xFF2C2C2E)
                                    : Colors.white),
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.12),
                                blurRadius: 10,
                                offset: const Offset(0, 3),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedRotation(
                                turns: pullState.armed ? 0.5 : 0.0,
                                duration: const Duration(milliseconds: 160),
                                child: iconoir.NavArrowDown(
                                  width: 16,
                                  height: 16,
                                  color: pullState.armed
                                      ? primaryColor
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Text(
                                l10n.translate(
                                  pullState.armed
                                      ? 'archive_release_hint'
                                      : 'archive_pull_hint',
                                ),
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: pullState.armed
                                      ? primaryColor
                                      : theme.colorScheme.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildArchivedChatsHeaderTile(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final notifProvider = context.watch<NotificationSettingsProvider>();

    int unmutedUnread = 0;
    int totalUnread = 0;
    for (final c in _archivedChats) {
      final count =
          c.unreadCount > 0 ? c.unreadCount : (c.unreadCount == -1 ? 1 : 0);
      totalUnread += count;
      if (!notifProvider.isChatMuted(c.id, chatType: c.chatType)) {
        unmutedUnread += count;
      }
    }
    final bool hasUnmutedUnread = unmutedUnread > 0;

    final previewChats = _archivedChats.take(4).toList();
    final baseSubtitleStyle = TextStyle(
      fontSize: 13.5,
      color: Colors.grey[500],
    );
    final unreadSubtitleStyle = TextStyle(
      fontSize: 13.5,
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.88),
    );

    final List<TextSpan> previewSpans = [];
    for (int i = 0; i < previewChats.length; i++) {
      final chat = previewChats[i];
      final isChatUnread = chat.unreadCount > 0 || chat.unreadCount == -1;
      previewSpans.add(
        TextSpan(
          text: chat.name,
          style: isChatUnread ? unreadSubtitleStyle : baseSubtitleStyle,
        ),
      );
      if (i < previewChats.length - 1) {
        previewSpans.add(TextSpan(text: ', ', style: baseSubtitleStyle));
      }
    }

    final Widget tile = Builder(
      builder: (tileContext) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: _isSelectMode
            ? null
            : (details) =>
                _showArchiveRowContextMenu(tileContext, details.globalPosition),
        child: ListTile(
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
          leading: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: hasUnmutedUnread
                    ? [
                        primaryColor.withValues(alpha: 0.85),
                        primaryColor,
                      ]
                    : const [
                        Color(0xFF78909C),
                        Color(0xFF546E7A),
                      ],
              ),
            ),
            child: const Center(
              child: iconoir.Archive(
                color: Colors.white,
                width: 22,
                height: 22,
              ),
            ),
          ),
          title: Text(
            l10n.translate('archive_title'),
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
          subtitle: RichText(
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            text: TextSpan(children: previewSpans),
          ),
          trailing: totalUnread > 0
              ? Container(
                  height: 20,
                  constraints: const BoxConstraints(minWidth: 20),
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  decoration: BoxDecoration(
                    color: hasUnmutedUnread
                        ? primaryColor
                        : (isDark
                            ? Colors.white24
                            : Colors.grey.withValues(alpha: 0.45)),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Center(
                    widthFactor: 1.0,
                    heightFactor: 1.0,
                    child: Text(
                      totalUnread > 99 ? '99+' : '$totalUnread',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                      ),
                    ),
                  ),
                )
              : null,
          onTap: _isSelectMode ? null : _openArchivedChatsScreen,
          onLongPress: _isSelectMode
              ? null
              : () => _showArchiveRowContextMenu(tileContext, null),
        ),
      ),
    );

    return Dismissible(
      key: const ValueKey('archive_header_dismiss'),
      direction:
          _isSelectMode ? DismissDirection.none : DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        color: Colors.blueGrey.withValues(alpha: 0.25),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.translate('archive_hide_above_list'),
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(width: 8),
            iconoir.EyeClosed(
              width: 18,
              height: 18,
              color: theme.colorScheme.onSurface,
            ),
          ],
        ),
      ),
      confirmDismiss: (_) async {
        await _hideArchiveAboveList();
        return false;
      },
      child: tile,
    );
  }

  Widget _buildChatListItem(BuildContext context, Chat chat) {
    final tiling = TilingLayoutController.instance;
    final notifProvider = context.watch<NotificationSettingsProvider>();
    final isMuted = notifProvider.isChatMuted(
      chat.id,
      chatType: chat.chatType,
    );
    final isSelected = _selectedChatIds.contains(chat.id);
    final typing = _chatTypingStates[chat.id];
    final fallbackSavedAvatar = _accountManager.currentAccount?.avatarUrl ??
        _accountManager.currentAccount?.localAvatarPath;

    return ChatListTileItem(
      key: ValueKey<String>('main_chat_row_${chat.id}'),
      chat: chat,
      isSelectMode: _isSelectMode,
      isSelected: isSelected,
      isMuted: isMuted,
      currentUserId: _currentUserId,
      fallbackSavedAvatarUrl: fallbackSavedAvatar,
      typingInfo: typing != null
          ? (action: typing.action, userName: typing.userName)
          : null,
      fallbackEntities: _chatLastMessageEntities[chat.id] ?? const [],
      isOpenInTile: tiling.windowSize.width >=
              TilingLayoutController.kTwoColumnBreakpoint &&
          tiling.isChatOpen(chat.id),
      isFocusedInTile: tiling.windowSize.width >=
              TilingLayoutController.kTwoColumnBreakpoint &&
          tiling.focusedChatTile?.chatId == chat.id,
      onTap: () {
        if (_isSelectMode) {
          HapticUtils.selection();
          _toggleChatSelection(chat.id);
        } else {
          HapticUtils.tap();
          _openChat(chat);
        }
      },
      onLongPress: () {
        HapticUtils.impact();
        if (_isSelectMode) {
          _toggleChatSelection(chat.id);
        } else {
          _enterSelectMode(chat.id);
        }
      },
      onSecondaryTapUp: (details) {
        _showChatContextMenu(context, chat, details.globalPosition);
      },
      onCreateDragPayload: (initialRect, globalPos) =>
          ChatBatchDialogs.createDragPayload(
        context,
        chat,
        initialRect,
        globalPos,
      ),
      onSwipeAction: (action) async {
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
            await _toggleArchiveChat(chat);
            break;
          case ChatSwipeAction.mute:
            await _toggleMuteChat(chat);
            break;
        }
      },
    );
  }

  Future<void> _showChatContextMenu(
    BuildContext itemContext,
    Chat chat,
    Offset globalPos,
  ) async {
    final overlay =
        Overlay.of(context, rootOverlay: true).context.findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final canSplit = TilingLayoutController.instance.windowSize.width >=
        TilingLayoutController.kTwoColumnBreakpoint;
    final hasUnread = chat.unreadCount > 0 || chat.unreadCount == -1;
    final l10n = context.l10n;
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final isMuted = context
        .read<NotificationSettingsProvider>()
        .isChatMuted(chat.id, chatType: chat.chatType);

    final selected = await showMenu<String>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPos.dx, globalPos.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      items: [
        if (canSplit)
          PopupMenuItem<String>(
            value: 'open_adjacent',
            child: Row(
              children: [
                iconoir.ViewColumns2(
                  width: 18,
                  height: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text(l10n.translate('selection_open_adjacent')),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'open',
          child: Row(
            children: [
              iconoir.ChatBubble(
                width: 18,
                height: 18,
                color: onSurface,
              ),
              const SizedBox(width: 10),
              Text(l10n.translate('chat_open_chat')),
            ],
          ),
        ),
        if (chat.chatType != 'saved')
          PopupMenuItem<String>(
            value: 'pin',
            child: Row(
              children: [
                chat.isPinned
                    ? iconoir.PinSlash(width: 18, height: 18, color: onSurface)
                    : iconoir.Pin(width: 18, height: 18, color: onSurface),
                const SizedBox(width: 10),
                Text(
                  l10n.translate(
                    chat.isPinned ? 'selection_unpin' : 'selection_pin',
                  ),
                ),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'read',
          child: Row(
            children: [
              iconoir.DoubleCheck(width: 18, height: 18, color: onSurface),
              const SizedBox(width: 10),
              Text(
                l10n.translate(
                  hasUnread ? 'selection_mark_read' : 'selection_mark_unread',
                ),
              ),
            ],
          ),
        ),
        if (chat.chatType != 'saved' && chat.chatType != 'community')
          PopupMenuItem<String>(
            value: 'archive',
            child: Row(
              children: [
                iconoir.Archive(width: 18, height: 18, color: onSurface),
                const SizedBox(width: 10),
                Text(
                  l10n.translate(
                    chat.isArchived
                        ? 'selection_unarchive'
                        : 'selection_archive',
                  ),
                ),
              ],
            ),
          ),
        if (chat.chatType != 'saved' && chat.chatType != 'community')
          PopupMenuItem<String>(
            value: 'mute',
            child: Row(
              children: [
                isMuted
                    ? iconoir.Bell(width: 18, height: 18, color: onSurface)
                    : iconoir.BellOff(width: 18, height: 18, color: onSurface),
                const SizedBox(width: 10),
                Text(
                  l10n.translate(
                    isMuted ? 'selection_unmute' : 'selection_mute',
                  ),
                ),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'add_to_folder',
          child: Row(
            children: [
              iconoir.Folder(width: 18, height: 18, color: onSurface),
              const SizedBox(width: 10),
              Text(l10n.translate('selection_add_to_folder')),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'select',
          child: Row(
            children: [
              iconoir.CheckCircle(width: 18, height: 18, color: onSurface),
              const SizedBox(width: 10),
              Text(l10n.translate('chat_select_chats')),
            ],
          ),
        ),
        if (chat.chatType != 'community')
          PopupMenuItem<String>(
            value: 'clear_history',
            child: Row(
              children: [
                iconoir.Erase(width: 18, height: 18, color: onSurface),
                const SizedBox(width: 10),
                Text(l10n.translate('selection_clear_history')),
              ],
            ),
          ),
        if (chat.chatType != 'saved')
          PopupMenuItem<String>(
            value: 'delete',
            child: Row(
              children: [
                const iconoir.Trash(width: 18, height: 18, color: Colors.red),
                const SizedBox(width: 10),
                Text(
                  l10n.translate('selection_delete'),
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ),
          ),
      ],
    );

    if (!mounted || selected == null) return;
    switch (selected) {
      case 'open_adjacent':
        _openChat(chat, inAdjacentTile: true);
        break;
      case 'open':
        _openChat(chat);
        break;
      case 'pin':
        await _togglePinChat(chat);
        break;
      case 'read':
        await _toggleReadChat(chat);
        break;
      case 'archive':
        await _toggleArchiveChat(chat);
        break;
      case 'mute':
        await _toggleMuteChat(chat);
        break;
      case 'add_to_folder':
        await ChatBatchDialogs.showAddToFolderSheet(context, [chat]);
        break;
      case 'select':
        _enterSelectMode(chat.id);
        break;
      case 'clear_history':
        await ChatBatchDialogs.executeClearHistory(
          context,
          [chat],
          currentUserId: _currentUserId,
        );
        break;
      case 'delete':
        await _batchDeleteChats([chat]);
        break;
    }
  }

  Future<void> _toggleReadChat(Chat chat) async {
    UnreadCountProvider? unreadProvider;
    try {
      unreadProvider = context.read<UnreadCountProvider>();
    } catch (_) {}
    final db = AppDatabase(_currentUserId);
    if (chat.unreadCount > 0 || chat.unreadCount == -1) {
      await db.batchMarkAsRead([chat.id]);
      unreadProvider?.setCount(chat.id, 0);
      if (chat.unreadCount == -1) {
        await ChatService.unmarkChatUnread(chat.id);
      } else {
        await ChatService.markMessagesAsRead(chatId: chat.id);
      }
    } else {
      await db.updateUnreadCount(chat.id, -1);
      unreadProvider?.setCount(chat.id, -1);
      unawaited(ChatService.markChatUnread(chat.id));
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

  Future<void> _toggleArchiveChat(Chat chat) async {
    if (chat.chatType == 'saved' || chat.chatType == 'community') return;
    final targetArchived = !chat.isArchived;
    final db = AppDatabase(_currentUserId);
    await db.setChatArchived(chat.id, targetArchived);

    final res = targetArchived
        ? await ChatService.archiveChat(chatId: chat.id)
        : await ChatService.unarchiveChat(chatId: chat.id);

    if (res['success'] != true) {
      await db.setChatArchived(chat.id, !targetArchived);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res['message']?.toString() ?? 'Не удалось обновить архив',
            ),
          ),
        );
      }
      return;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            targetArchived
                ? '${chat.name} перемещён в архив'
                : '${chat.name} возвращён из архива',
          ),
          action: SnackBarAction(
            label: 'Отменить',
            onPressed: () {
              unawaited(
                _toggleArchiveChat(chat.copyWith(isArchived: targetArchived)),
              );
            },
          ),
        ),
      );
    }
  }

  Future<void> _toggleMuteChat(Chat chat) async {
    if (chat.chatType == 'saved' || chat.chatType == 'community') return;
    final notifProvider = context.read<NotificationSettingsProvider>();
    final currentlyMuted =
        notifProvider.isChatMuted(chat.id, chatType: chat.chatType);
    await notifProvider.setMuteState(
      chat.id,
      currentlyMuted ? MuteState.notMuted : MuteState.muted,
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            currentlyMuted
                ? 'Уведомления для «${chat.name}» включены'
                : 'Уведомления для «${chat.name}» отключены',
          ),
        ),
      );
    }
  }

  /// Enter multi-select mode (optionally pre-selecting [chatId])
  void _enterSelectMode([String? chatId]) {
    if (_isTopMenuOpen) _closeTopMenu();
    if (_isFolderMenuOpen) _closeFolderMenu();
    if (_isCreateMenuOpen) _closeCreateMenu();
    _selectModeController.forward();
    setState(() {
      _isSelectMode = true;
      _isSelectionMenuOpen = false;
      _selectedChatIds = chatId != null ? {chatId} : {};
    });
  }

  /// Exit multi-select mode
  void _exitSelectMode() {
    _selectModeController.reverse();
    setState(() {
      _isSelectMode = false;
      _isSelectionMenuOpen = false;
      _selectedChatIds = {};
    });
  }

  /// Select all visible folder chats, or clear selection if all are selected
  void _selectAllOrDeselect(List<Chat> folderChats) {
    final allSelected = folderChats.isNotEmpty &&
        folderChats.every((c) => _selectedChatIds.contains(c.id));
    setState(() {
      if (allSelected) {
        _selectedChatIds = {};
      } else {
        _selectedChatIds = folderChats.map((c) => c.id).toSet();
      }
    });
  }

  /// Toggle selection of a single chat
  void _toggleChatSelection(String chatId) {
    final shouldExit = _selectedChatIds.contains(chatId) &&
        _selectedChatIds.length == 1;
    if (shouldExit) {
      _exitSelectMode();
      return;
    }
    setState(() {
      if (_selectedChatIds.contains(chatId)) {
        _selectedChatIds.remove(chatId);
      } else {
        _selectedChatIds.add(chatId);
      }
    });
  }

  /// Batch toggle pin status for selected chats
  Future<void> _batchTogglePin(List<Chat> chats) async {
    final pinnable = chats
        .where((c) => c.chatType != 'saved' && c.chatType != 'community')
        .toList();
    if (pinnable.isEmpty) return;

    final allPinned = pinnable.every((c) => c.isPinned);
    final newPinned = !allPinned;
    final db = AppDatabase(_currentUserId);
    final messenger = ScaffoldMessenger.maybeOf(context);

    await db.batchSetPinned(pinnable.map((c) => c.id).toList(), newPinned);
    _exitSelectMode();

    int successCount = 0;
    for (final chat in pinnable) {
      final result = newPinned
          ? await ChatService.pinChat(chatId: chat.id)
          : await ChatService.unpinChat(chatId: chat.id);
      if (result['success'] == true) successCount++;
    }

    if (mounted) {
      messenger?.showSnackBar(
        SnackBar(content: Text('Обновлено $successCount чатов')),
      );
    }
  }

  /// Batch toggle mute state for selected chats
  Future<void> _batchToggleMute(List<Chat> chats) async {
    final muteable = chats
        .where((c) => c.chatType != 'saved' && c.chatType != 'community')
        .toList();
    if (muteable.isEmpty) return;

    final notifProvider = context.read<NotificationSettingsProvider>();
    final allMuted = muteable.every(
      (c) => notifProvider.isChatMuted(c.id, chatType: c.chatType),
    );
    final targetState = allMuted ? MuteState.notMuted : MuteState.muted;

    for (final chat in muteable) {
      await notifProvider.setMuteState(chat.id, targetState);
    }
    if (mounted) {
      _exitSelectMode();
    }
  }

  /// Batch move selected chats to archive with Undo snackbar
  Future<void> _batchArchiveChats(List<Chat> chats) async {
    final targets = chats
        .where((c) => c.chatType != 'saved' && c.chatType != 'community')
        .toList();
    if (targets.isEmpty) return;

    final messenger = ScaffoldMessenger.maybeOf(context);
    final l10n = context.l10n;
    final toastText = l10n
        .translate('archive_moved_toast')
        .replaceAll('{count}', '${targets.length}');
    final undoLabel = l10n.translate('common_undo');

    final db = AppDatabase(_currentUserId);
    final ids = targets.map((c) => c.id).toList();
    await db.batchSetArchived(ids, true);
    _exitSelectMode();

    final failedIds = <String>[];
    for (final chat in targets) {
      final res = await ChatService.archiveChat(chatId: chat.id);
      if (res['success'] != true) {
        failedIds.add(chat.id);
      }
    }

    if (failedIds.isNotEmpty) {
      await db.batchSetArchived(failedIds, false);
    }

    final succeededIds =
        ids.where((id) => !failedIds.contains(id)).toList();
    if (succeededIds.isEmpty) return;

    messenger?.showSnackBar(
      SnackBar(
        content: Text(toastText),
        action: SnackBarAction(
          label: undoLabel,
          onPressed: () {
            unawaited(() async {
              await db.batchSetArchived(succeededIds, false);
              for (final id in succeededIds) {
                await ChatService.unarchiveChat(chatId: id);
              }
            }());
          },
        ),
      ),
    );
  }

  /// Batch toggle read / unread status for selected chats
  Future<void> _batchToggleRead(List<Chat> chats) async {
    final regular =
        chats.where((c) => c.chatType != 'community').toList();
    if (regular.isEmpty) return;

    final anyUnread =
        regular.any((c) => c.unreadCount > 0 || c.unreadCount == -1);
    if (anyUnread) {
      await _batchMarkAsRead(regular);
      return;
    }

    UnreadCountProvider? unreadProvider;
    try {
      unreadProvider = context.read<UnreadCountProvider>();
    } catch (_) {}

    final db = AppDatabase(_currentUserId);
    final ids = regular.map((c) => c.id).toList();
    await db.batchMarkAsUnread(ids);
    for (final id in ids) {
      unreadProvider?.setCount(id, -1);
      unawaited(ChatService.markChatUnread(id));
    }
    _exitSelectMode();
  }

  /// Batch mark selected chats as read
  Future<void> _batchMarkAsRead(List<Chat> chats) async {
    UnreadCountProvider? unreadProvider;
    try {
      unreadProvider = context.read<UnreadCountProvider>();
    } catch (_) {}

    final db = AppDatabase(_currentUserId);
    final ids = chats.map((c) => c.id).toList();

    // Оптимистичное обновление SQLite и провайдера — стрим мгновенно обновит UI
    await db.batchMarkAsRead(ids);
    for (final id in ids) {
      unreadProvider?.setCount(id, 0);
    }
    _exitSelectMode();

    int successCount = 0;
    for (final chat in chats) {
      if (chat.unreadCount > 0) {
        final result = await ChatService.markMessagesAsRead(chatId: chat.id);
        if (result['success'] == true) {
          successCount++;
        }
      } else if (chat.unreadCount == -1) {
        final result = await ChatService.unmarkChatUnread(chat.id);
        if (result['success'] == true) {
          successCount++;
        } else {
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

  /// Batch delete or leave selected chats with tailored confirmation dialog
  Future<void> _batchDeleteChats(List<Chat> chats) async {
    final deletable = chats.where((c) => c.chatType != 'saved').toList();
    if (deletable.isEmpty) return;

    final delRes = await ChatBatchDialogs.confirmDeleteChatsWithOptions(
      context,
      deletable,
    );

    if (delRes.confirmed && mounted) {
      final db = AppDatabase(_currentUserId);
      final ids = deletable.map((c) => c.id).toList();

      // Оптимистичное удаление из SQLite — стрим мгновенно обновит UI
      await db.batchDeleteChats(ids);
      _exitSelectMode();

      int deleted = 0;
      int failed = 0;
      for (final chat in deletable) {
        final result = await ChatService.deleteChat(
          chat.id,
          revoke: chat.chatType == 'private' && delRes.revoke,
        );
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

  void _openChat(Chat chat, {bool inAdjacentTile = false}) {
    if (chat.unreadCount == -1) {
      final db = AppDatabase(_currentUserId);
      db.updateUnreadCount(chat.id, 0);
      try {
        context.read<UnreadCountProvider>().setCount(chat.id, 0);
      } catch (_) {}
      unawaited(ChatService.unmarkChatUnread(chat.id));
    }

    final effectiveSavedAvatar = chat.avatarUrl ??
        _accountManager.currentAccount?.avatarUrl ??
        _accountManager.currentAccount?.localAvatarPath;
    final translatedSaved = context.l10n.translate('chat_saved_messages');
    final displayName = chat.chatType == 'saved'
        ? (translatedSaved != 'chat_saved_messages'
            ? translatedSaved
            : 'Избранное')
        : (chat.chatType == 'system' && chat.name.isEmpty
            ? context.l10n.translate('system_notifications_title')
            : chat.name);
    final effectiveAvatar =
        chat.chatType == 'saved' ? effectiveSavedAvatar : chat.avatarUrl;

    if (chat.chatType == 'community') {
      final rawCommId = chat.otherUserId ??
          (chat.id.startsWith('community_')
              ? chat.id.substring('community_'.length)
              : chat.id);
      final comm = _communities.firstWhere(
        (c) => c.id == rawCommId,
        orElse: () =>
            CommunityService.getCachedCommunity(rawCommId) ??
            Community(
              id: rawCommId,
              name: chat.name,
              description: chat.lastMessage ?? '',
              avatarUrl: chat.avatarUrl,
              createdAt: DateTime.now(),
            ),
      );
      if (comm.isMember) {
        CommunityService.cacheCommunity(comm);
      }
      if (!TilingLayoutController.instance.isWorkspaceMounted) {
        Navigator.push(
          context,
          SwipeBackPageRoute(
            builder: (_) => CommunityScreen(
              community: comm,
              onCommunityJoined: _onCommunityCreated,
              onCommunityLeft: _loadCommunities,
            ),
          ),
        ).then((_) => _loadCommunities());
        return;
      }
    }

    if (TilingLayoutController.instance.isWorkspaceMounted) {
      if (inAdjacentTile) {
        TilingLayoutController.instance.openChatInAdjacentTile(
          chatId: chat.id,
          chatType: chat.chatType,
          chatName: displayName,
          avatarUrl: effectiveAvatar,
          otherUserId: chat.otherUserId,
          otherUserOnline: chat.isOnline,
          otherUserLastSeen: DateTimeUtils.parseUtcDateTime(chat.lastSeen),
        );
      } else {
        TilingLayoutController.instance.openChatInActiveTile(
          chatId: chat.id,
          chatType: chat.chatType,
          chatName: displayName,
          avatarUrl: effectiveAvatar,
          otherUserId: chat.otherUserId,
          otherUserOnline: chat.isOnline,
          otherUserLastSeen: DateTimeUtils.parseUtcDateTime(chat.lastSeen),
        );
      }
      return;
    }

    try {
      context.read<UnreadCountProvider>().openChat(chat.id);
    } catch (_) {}
    NotificationService().addActiveChat(chat.id);

    final VoidCallback onReturn = () {
      try {
        context.read<UnreadCountProvider>().closeChat(chat.id);
      } catch (_) {}
      NotificationService().removeActiveChat(chat.id);
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
              otherUserName: displayName,
              otherUserAvatar: effectiveSavedAvatar,
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
              chatName: displayName,
            ),
          ),
        ).then((_) => onReturn());
        break;
      case 'group':
        Navigator.push(
          context,
          SwipeBackPageRoute(
            builder: (_) => chat.isForum
                ? ForumTopicsScreen(
                    chatId: chat.id,
                    chatName: chat.name,
                    chatAvatar: chat.avatarUrl,
                  )
                : GroupChatScreen(
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

      // Then by precomputed updatedAtEpochMs to ensure accurate chronological ordering
      return b.updatedAtEpochMs.compareTo(a.updatedAtEpochMs);
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
            !_isSelectionMenuOpen &&
            !_isFolderMenuOpen &&
            !_isCreateMenuOpen &&
            !_isSelectMode,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          if (_isTopMenuOpen) {
            _closeTopMenu();
            return;
          }
          if (_isSelectionMenuOpen) {
            setState(() => _isSelectionMenuOpen = false);
            return;
          }
          if (_isFolderMenuOpen) {
            _closeFolderMenu();
            return;
          }
          if (_isCreateMenuOpen) {
            _closeCreateMenu();
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
            final unreadProvider = context.watch<UnreadCountProvider>();
            final notifProvider = context.watch<NotificationSettingsProvider>();
            final notifGlobal = notifProvider.globalSettings;
            final totalUnread = unreadProvider.getBadgeCount(
              badgeEnabled: notifGlobal.badgeEnabled,
              badgeMode: notifGlobal.badgeMode,
              includeMutedChats: notifGlobal.includeMutedChats,
              isMutedResolver: (chatId, chatType) =>
                  notifProvider.isChatMuted(chatId, chatType: chatType),
            );
            final primaryColor = Theme.of(context).colorScheme.primary;

            if (_lastGlassEnabled != glassProvider.enabled) {
              _lastGlassEnabled = glassProvider.enabled;
              final targetIndex = _currentIndex;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted && _pageController.hasClients) {
                  final currentPage = _pageController.page?.round();
                  if (currentPage != targetIndex) {
                    _pageController.jumpToPage(targetIndex);
                  }
                }
              });
            }

            // PageView: страница 0 = Настройки, страница 1 = Чаты, страница 2 = Поиск
            // Свайп влево → Настройки, свайп вправо → Чаты
            final Widget pageView = PageView(
                  key: _pageViewKey,
                  controller: _pageController,
                  physics: const NeverScrollableScrollPhysics(),
                  onPageChanged: (page) {
                    if (_isTopMenuOpen) {
                      _closeTopMenu();
                    }
                    if (_isFolderMenuOpen) {
                      _closeFolderMenu();
                    }
                    if (_isCreateMenuOpen) {
                      _closeCreateMenu();
                    }
                    // Закрываем клавиатуру при уходе с поиска
                    if (_currentIndex == 2 && page != 2) {
                      _searchFocusNode.unfocus();
                    }
                    if (_currentIndex != page) {
                      setState(() {
                        _currentIndex = page;
                        _visitedPages.add(page);
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
                    RepaintBoundary(
                      child: _visitedPages.contains(0)
                          ? const _KeepAlivePage(
                              child: SettingsScreen(isEmbedded: true),
                            )
                          : const SizedBox.shrink(),
                    ),

                    // Страница 1: Чаты
                    RepaintBoundary(
                      child: _KeepAlivePage(
                        child: Builder(
                          builder: (context) {
                            final statusBarHeight =
                                MediaQuery.of(context).padding.top;
                            final topBarHeight = statusBarHeight + 52.0;
                            final activePlayChatId = VoicePlaybackService().hasActiveAudio
                                ? VoicePlaybackService().activeChatId
                                : VideoNotePlaybackService().hasActiveVideo
                                    ? VideoNotePlaybackService().activeChatId
                                    : null;
                            final isPlayingInVisibleRightTile = activePlayChatId != null &&
                                TilingLayoutController.instance.isWorkspaceMounted &&
                                TilingLayoutController.instance.windowSize.width >=
                                    TilingLayoutController.kTwoColumnBreakpoint &&
                                TilingLayoutController.instance.isChatOpen(activePlayChatId);
                            final playerOffset =
                                (activePlayChatId != null && !isPlayingInVisibleRightTile)
                                    ? 56.0
                                    : 0.0;
                            final targetTopPadding =
                                topBarHeight + 8.0 + playerOffset;
                            return TweenAnimationBuilder<double>(
                              tween: Tween<double>(
                                begin: targetTopPadding,
                                end: targetTopPadding,
                              ),
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                              builder: (context, animatedTopPadding, _) {
                                return _buildChatList(
                                  context,
                                  topPadding: animatedTopPadding,
                                );
                              },
                            );
                          },
                        ),
                      ), // closes _KeepAlivePage
                    ), // closes RepaintBoundary

                    // Страница 2: Поиск
                    RepaintBoundary(
                      child: _visitedPages.contains(2)
                          ? _KeepAlivePage(
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
                                                _unifiedSearchResult =
                                                    UnifiedSearchResult.empty;
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
                                    _buildSearchFilterChips(context),
                                    // Результаты поиска
                                    Expanded(
                                      child: _buildSearchResults(),
                                    ),
                                  ],
                                ),
                              ), // closes SafeArea
                            )
                          : const SizedBox.shrink(), // closes _KeepAlivePage
                    ),
                  ], // closes PageView children
                ); // closes PageView

            final isDark = Theme.of(context).brightness == Brightness.dark;
            final statusBarHeight = MediaQuery.of(context).padding.top;
            final topBarHeight = statusBarHeight + 52.0;

            if (glassProvider.enabled) {
              final double screen = TileViewportScope.widthOf(context);
              final double keyboardHeight = MediaQuery.viewInsetsOf(context).bottom;
              final double safeBottom = MediaQuery.paddingOf(context).bottom;

              const double barHeight = 60.0;
              const double edgePadding = 16.0;
              const double spacing = 10.0;
              const double actionSize = 60.0;
              const double bottomMargin = 12.0;
              const double maxGroupWidth = 560.0;

              final double totalRequiredWidth =
                  math.max(0.0, screen - edgePadding * 2);
              final double leftMargin;
              final double actionMargin;
              final double barWidth;

              if (totalRequiredWidth <= maxGroupWidth) {
                leftMargin = edgePadding;
                actionMargin = edgePadding;
                barWidth =
                    math.max(120.0, totalRequiredWidth - actionSize - spacing);
              } else {
                final double groupLeft =
                    math.max(0.0, (screen - maxGroupWidth) / 2);
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

              final actionStyle = glassProvider.createStyle(
                context: context,
                cornerRadius: _isCreateMenuOpen ? 26.0 : (barHeight / 2),
                refractionIndex: 1.1,
                refractionWidth: 24.0,
              );

              final double effectiveBottomMargin = keyboardHeight > 0
                  ? (bottomMargin + keyboardHeight - safeBottom)
                  : bottomMargin;

              return AnimatedBuilder(
                animation: _selectModeAnimation,
                builder: (context, _) {
                  final double hideProgress =
                      _selectModeAnimation.value.clamp(0.0, 1.0);
                  final double visibleBottomFromWindow =
                      math.max(0.0, effectiveBottomMargin + safeBottom);
                  final double hideOffset =
                      (barHeight + visibleBottomFromWindow + 36.0) *
                          hideProgress;
                  final double actionOpacity =
                      (1.0 - hideProgress * 1.4).clamp(0.0, 1.0);

                  return LiquidGlassScaffold(
                    pixelRatio: 1.0,
                    useSync: true,
                    batch: false,
                    backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                    appBar: _buildAdaptiveTopBar(context),
                    appBarTopMargin: 8.0,
                    lenses: [
                      if (_isTopMenuOpen ||
                          _isFolderMenuOpen ||
                          _isCreateMenuOpen ||
                          _isSelectionMenuOpen)
                        GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            if (_isTopMenuOpen) _closeTopMenu();
                            if (_isFolderMenuOpen) _closeFolderMenu();
                            if (_isCreateMenuOpen) _closeCreateMenu();
                            if (_isSelectionMenuOpen) {
                              setState(() => _isSelectionMenuOpen = false);
                            }
                          },
                        ),
                    ],
                    body: Scaffold(
                      backgroundColor: Colors.transparent,
                      resizeToAvoidBottomInset: true,
                      body: Stack(
                        children: [
                          Positioned.fill(child: pageView),
                          Positioned(
                            top: topBarHeight + 4.0,
                            left: 0,
                            right: 0,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: const [
                                CallDeviceTransferBanner(),
                                MediaNotePlayerHeader(),
                              ],
                            ),
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
                                      color: primaryColor,
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
                        if (_isSelectMode) return;
                        _onTabTapped(index);
                      },
                      onReselected: (index) {
                        if (_isSelectMode) return;
                        HapticUtils.tap();
                        _onTabReselected(index);
                      },
                      width: barWidth,
                      height: barHeight,
                      alignment: Alignment.bottomLeft,
                      margin: EdgeInsets.only(
                        left: leftMargin,
                        bottom: effectiveBottomMargin - hideOffset,
                      ),
                      itemPadding: 3,
                      swell: const LiquidGlassTabBarSwell(scale: 0.024),
                      style: barStyle,
                      itemStyle: LiquidGlassTabItemStyle(
                        selectedColor: primaryColor,
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
                        behavior: const LiquidGlassTabPillBehavior(),
                        rest: LiquidGlassStyle(
                          shape: _glassShape(28),
                          color: isDark
                              ? const Color(0x38FFFFFF)
                              : const Color(0x2EAEAEB2),
                        ),
                      ),
                    ),
                    bottomNavigationBarAction: IgnorePointer(
                      ignoring: _isSelectMode || actionOpacity <= 0.01,
                      child: SizedBox(
                        width: CreateChatSelectorPanel.kPanelWidth,
                        height: CreateChatSelectorPanel.kPanelHeight,
                        child: LiquidGlassMorph(
                          key: const ValueKey<String>('main_create_menu_morph'),
                          alignment: Alignment.bottomRight,
                          opacity: actionOpacity.clamp(0.0, 1.0),
                          motion: LiquidGlassMorphMotion.fluid,
                          smoothness: 28,
                          style: actionStyle,
                          touch: !_isCreateMenuOpen
                              ? const LiquidGlassTouch.flexing(LiquidGlassFlex(
                                  stretch: 6,
                                  squeeze: 0.68,
                                  lean: 0.30,
                                  grip: 0.50,
                                ))
                              : null,
                          child: _isCreateMenuOpen
                              ? CreateChatSelectorPanel(
                                  key: const ValueKey<String>('create_chat_panel'),
                                  onClose: _closeCreateMenu,
                                  onSelectOption: _handleCreateOptionSelected,
                                )
                              : _PlusActionGlyph(
                                  key: const ValueKey<String>('plus_action_glyph'),
                                  size: actionSize,
                                  onTap: _toggleCreateMenu,
                                ),
                        ),
                      ),
                    ),
                  );
                },
              );
            }

            // Классический режим — матовый single-pass blur HUD поверх контента
            final Widget classicStack = Stack(
              children: [
                Positioned.fill(child: pageView),
                if (_isTopMenuOpen ||
                    _isFolderMenuOpen ||
                    _isCreateMenuOpen ||
                    _isSelectionMenuOpen)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        if (_isTopMenuOpen) _closeTopMenu();
                        if (_isFolderMenuOpen) _closeFolderMenu();
                        if (_isCreateMenuOpen) _closeCreateMenu();
                        if (_isSelectionMenuOpen) {
                          setState(() => _isSelectionMenuOpen = false);
                        }
                      },
                    ),
                  ),
                Positioned(
                  top: topBarHeight + 4.0,
                  left: 0,
                  right: 0,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: const [
                      CallDeviceTransferBanner(),
                      MediaNotePlayerHeader(),
                    ],
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: _buildAdaptiveTopBar(context),
                    ),
                  ),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: IgnorePointer(
                    ignoring: _isSelectMode,
                    child: AnimatedSlide(
                      offset: Offset(0, _isSelectMode ? 1.35 : 0.0),
                      duration: const Duration(milliseconds: 260),
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        opacity: _isSelectMode ? 0.0 : 1.0,
                        duration: const Duration(milliseconds: 200),
                        child: SafeArea(
                          top: false,
                          child: ClassicBottomBar(
                            selectedIndex: _currentIndex,
                            unreadCount: totalUnread,
                            onTabSelected: (index) {
                              _onTabTapped(index);
                            },
                            onAddTap: _toggleCreateMenu,
                            bottomPadding: 12,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 0,
                  bottom: 0,
                  child: _buildClassicCreateMenuOverlay(context),
                ),
              ],
            );

            return Scaffold(
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              resizeToAvoidBottomInset: true,
              body: BackdropGroup.of(context) == null
                  ? BackdropGroup(child: classicStack)
                  : classicStack,
            );
          },
        ),
      ), // closes PopScope
    ); // closes AnnotatedRegion
  }

  Widget _buildClassicCreateMenuOverlay(BuildContext context) {
    final theme = Theme.of(context);
    final themeExt = theme.extension<TheavThemeExtension>();
    final p = themeExt?.palette;
    final isDark = theme.brightness == Brightness.dark;
    final blurEnabled = BlurUtils.shouldBlurMaterialHud(context);

    final rawBg =
        p?.surface ?? (isDark ? const Color(0xFF2C2C2E) : Colors.white);
    final barBackgroundColor = BlurUtils.resolveMaterialHudColor(
      rawBg,
      isDark: isDark,
      blurEnabled: blurEnabled,
      darkAlpha: 0.84,
      lightAlpha: 0.88,
    );
    final borderColor = p?.divider ??
        (isDark
            ? Colors.white.withValues(alpha: 0.1)
            : Colors.black.withValues(alpha: 0.06));
    final double baseShadowAlpha = isDark ? 0.35 : 0.08;

    const double ctrlSize = 60.0;
    const double panelWidth = CreateChatSelectorPanel.kPanelWidth;
    const double panelHeight = CreateChatSelectorPanel.kPanelHeight;

    return AnimatedBuilder(
      animation: _classicCreateMenuAnimation,
      builder: (context, _) {
        final double progress = _classicCreateMenuAnimation.value;
        if (progress <= 0.001) {
          return const SizedBox.shrink();
        }

        final double currentWidth =
            ctrlSize + (panelWidth - ctrlSize) * progress;
        final double currentHeight =
            ctrlSize + (panelHeight - ctrlSize) * progress;
        final double currentRadius = 30.0 - 4.0 * progress;

        final Widget menuCard = Container(
          width: currentWidth,
          height: currentHeight,
          decoration: BoxDecoration(
            color: barBackgroundColor,
            borderRadius: BorderRadius.circular(currentRadius),
            border: Border.all(color: borderColor, width: 0.6),
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            clipBehavior: Clip.hardEdge,
            children: [
              if (progress > 0.01)
                Positioned(
                  bottom: 0,
                  right: 0,
                  width: panelWidth,
                  height: panelHeight,
                  child: Opacity(
                    opacity: ((progress - 0.15) / 0.85).clamp(0.0, 1.0),
                    child: Transform.translate(
                      offset: Offset(0, 10.0 * (1.0 - progress)),
                      child: IgnorePointer(
                        ignoring: progress < 0.85,
                        child: CreateChatSelectorPanel(
                          key: const ValueKey<String>(
                            'classic_create_chat_panel',
                          ),
                          onClose: _closeCreateMenu,
                          onSelectOption: _handleCreateOptionSelected,
                        ),
                      ),
                    ),
                  ),
                ),
              if (progress < 0.99)
                Positioned(
                  bottom: 0,
                  right: 0,
                  width: ctrlSize,
                  height: ctrlSize,
                  child: Opacity(
                    opacity: (1.0 - (progress / 0.35)).clamp(0.0, 1.0),
                    child: Transform.rotate(
                      angle: progress * math.pi / 4,
                      child: IgnorePointer(
                        ignoring: progress > 0.1,
                        child: _PlusActionGlyph(
                          size: ctrlSize,
                          onTap: _toggleCreateMenu,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );

        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.only(right: 16.0, bottom: 12.0),
            child: DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(currentRadius),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(
                      alpha: (baseShadowAlpha * (0.6 + 0.5 * progress))
                          .clamp(0.0, 1.0),
                    ),
                    blurRadius: 12 + 12 * progress,
                    offset: Offset(0, 4 + 4 * progress),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(currentRadius),
                child: blurEnabled
                    ? BackdropFilter.grouped(
                        filter: BlurUtils.createMaterialHudBlur(sigma: 12.0),
                        child: menuCard,
                      )
                    : menuCard,
              ),
            ),
          ),
        );
      },
    );
  }

  LiquidGlassShape _glassShape(double cornerRadius) =>
      LiquidGlassShape.continuousRoundedRectangle(
        cornerRadius: cornerRadius,
        clipQuality: LiquidGlassClipQuality.roundedRectangle,
      );

  LiquidGlassTabBarItem _buildTabBarItem({
    required Widget Function(LiquidGlassGlyph i) iconBuilder,
  }) {
    return LiquidGlassTabBarItem(
      iconBuilder: (context, i) => iconBuilder(i),
    );
  }



  Widget _buildSearchFilterChips(BuildContext context) {
    final filters = const <(String, String)>[
      ('all', 'Все'),
      ('chats', 'Чаты'),
      ('users', 'Люди и боты'),
      ('groups', 'Группы'),
      ('channels', 'Каналы'),
      ('communities', 'Сообщества'),
      ('messages', 'Сообщения'),
    ];
    final primary = Theme.of(context).colorScheme.primary;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        itemCount: filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final (key, label) = filters[index];
          final selected = _searchFilter == key;
          return GestureDetector(
            onTap: () => setState(() => _searchFilter = key),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
              decoration: BoxDecoration(
                color: selected
                    ? primary
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.08)
                        : Colors.black.withValues(alpha: 0.06)),
                borderRadius: BorderRadius.circular(16),
              ),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  color: selected
                      ? Colors.white
                      : Theme.of(context).colorScheme.onSurface,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  bool _matchesSearchPeerFilter(SearchPeer peer) {
    switch (_searchFilter) {
      case 'all':
        return true;
      case 'chats':
        return peer.isMember;
      case 'users':
        return peer.type == 'user';
      case 'groups':
        return peer.type == 'group';
      case 'channels':
        return peer.type == 'channel';
      case 'communities':
        return peer.type == 'community';
      case 'messages':
        return false;
      default:
        return true;
    }
  }

  Future<void> _joinPublicSearchPeer(SearchPeer peer) async {
    if (_joiningPeerIds.contains(peer.id)) return;
    setState(() => _joiningPeerIds.add(peer.id));
    try {
      if (peer.type == 'community') {
        final joined = await CommunityService.joinCommunity(peer.id);
        if (!mounted) return;
        if (joined != null) {
          _onCommunityCreated(joined);
          await _loadChats(silent: true);
          _onSearchPeerTap(peer.copyWith(isMember: true));
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Не удалось вступить в сообщество')),
          );
        }
        return;
      }
      final res = await ChatService.joinPublicChat(peer.id);
      if (!mounted) return;
      if (res['success'] == true) {
        await _loadChats(silent: true);
        _onSearchPeerTap(peer.copyWith(isMember: true));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res['message']?.toString() ?? 'Не удалось вступить')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _joiningPeerIds.remove(peer.id));
      }
    }
  }

  void _onSearchPeerTap(SearchPeer peer) {
    if (peer.type == 'user') {
      _onSearchResultTap(peer.toUser(), 'user');
    } else if (peer.type == 'group') {
      _onSearchResultTap(peer.toGroup(), 'group');
    } else if (peer.type == 'channel') {
      _onSearchResultTap(peer.toChannel(), 'channel');
    } else if (peer.type == 'community') {
      _onSearchResultTap(peer.toCommunity(), 'community');
    }
  }

  Widget _buildSearchResults() {
    final l10n = context.l10n;

    final myPeers =
        _unifiedSearchResult.myPeers.where(_matchesSearchPeerFilter).toList();
    final globalPeers = _unifiedSearchResult.globalPeers
        .where(_matchesSearchPeerFilter)
        .toList();
    final showMessages =
        _searchFilter == 'all' || _searchFilter == 'messages';
    final messages = showMessages
        ? _unifiedSearchResult.messages
        : <SearchResultMessage>[];

    if (myPeers.isEmpty && globalPeers.isEmpty && messages.isEmpty) {
      if (_isLoading) {
        return const Center(child: CircularProgressIndicator());
      }
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

    return Column(
      children: [
        if (_isLoading) const LinearProgressIndicator(minHeight: 2),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.only(bottom: 100),
            children: [
              if (myPeers.isNotEmpty)
                _buildSearchSection(
                  'МОИ ЧАТЫ',
                  myPeers
                      .map((p) =>
                          _buildSearchPeerTile(context, p, isGlobal: false))
                      .toList(),
                ),
              if (globalPeers.isNotEmpty)
                _buildSearchSection(
                  'ГЛОБАЛЬНЫЙ ПОИСК',
                  globalPeers
                      .map((p) =>
                          _buildSearchPeerTile(context, p, isGlobal: true))
                      .toList(),
                ),
              if (messages.isNotEmpty)
                _buildSearchSection(
                  l10n.translate('search_messages'),
                  messages
                      .map((m) => _buildSearchMessageTile(context, m))
                      .toList(),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSearchPeerTile(BuildContext context, SearchPeer peer,
      {required bool isGlobal}) {
    final validAvatar = getValidAvatarUrl(peer.avatarUrl);
    final canJoin = isGlobal &&
        !peer.isMember &&
        (peer.type == 'group' || peer.type == 'channel' || peer.type == 'community');
    final isJoining = _joiningPeerIds.contains(peer.id);

    final subtitleParts = <String>[];
    if (peer.username.isNotEmpty) {
      subtitleParts.add('@${peer.username}');
    }
    if (peer.type == 'user' && peer.isBot) {
      subtitleParts.add('бот');
    } else if (peer.type == 'community') {
      subtitleParts.add(
        peer.memberCount > 0
            ? 'Сообщество • ${peer.memberCount} участн.'
            : 'Сообщество',
      );
      if (peer.description.isNotEmpty) {
        subtitleParts.add(peer.description);
      }
    } else if (peer.memberCount > 0) {
      subtitleParts.add(
        peer.type == 'channel'
            ? '${peer.memberCount} подписчиков'
            : '${peer.memberCount} участников',
      );
    } else if (peer.description.isNotEmpty) {
      subtitleParts.add(peer.description);
    }

    return ListTile(
      leading: CircleAvatar(
        backgroundColor:
            Theme.of(context).colorScheme.primary.withValues(alpha: 0.16),
        backgroundImage:
            validAvatar != null ? avatarImageProvider(peer.avatarUrl) : null,
        child: validAvatar == null
            ? (peer.type == 'channel'
                ? iconoir.Megaphone(
                    width: 22,
                    height: 22,
                    color: Theme.of(context).colorScheme.primary,
                  )
                : peer.type == 'community'
                    ? Icon(
                        Icons.hub_rounded,
                        size: 22,
                        color: Theme.of(context).colorScheme.primary,
                      )
                    : peer.type == 'group'
                        ? iconoir.Group(
                            width: 22,
                            height: 22,
                            color: Theme.of(context).colorScheme.primary,
                          )
                        : Text(
                            peer.title.isNotEmpty
                                ? peer.title[0].toUpperCase()
                                : '?',
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.primary,
                              fontWeight: FontWeight.w600,
                            ),
                          ))
            : null,
      ),
      title: Row(
        children: [
          Flexible(
            child: Text(
              peer.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
          PeerBadgesRow(isBot: peer.isBot, isVerified: peer.isVerified),
        ],
      ),
      subtitle: subtitleParts.isNotEmpty
          ? Text(
              subtitleParts.join(' • '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            )
          : null,
      trailing: canJoin
          ? SizedBox(
              height: 30,
              child: FilledButton.tonal(
                onPressed: isJoining ? null : () => _joinPublicSearchPeer(peer),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  visualDensity: VisualDensity.compact,
                ),
                child: isJoining
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Text(
                        peer.type == 'channel' ? 'Подписаться' : 'Вступить',
                        style: const TextStyle(fontSize: 12),
                      ),
              ),
            )
          : null,
      onTap: () => _onSearchPeerTap(peer),
    );
  }

  Widget _buildSearchMessageTile(
      BuildContext context, SearchResultMessage m) {
    final l10n = context.l10n;
    final header = m.chatName.isNotEmpty
        ? m.chatName
        : (m.senderName.isNotEmpty
            ? m.senderName
            : l10n
                .translate('search_from_user')
                .replaceAll('{user}', m.userId));
    final senderPrefix = m.senderName.isNotEmpty && m.senderName != m.chatName
        ? '${m.senderName}: '
        : '';

    return ListTile(
      leading: const iconoir.Message(width: 24, height: 24),
      title: Row(
        children: [
          Expanded(
            child: Text(
              header,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatDate(m.createdAt),
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context)
                  .colorScheme
                  .onSurface
                  .withValues(alpha: 0.55),
            ),
          ),
        ],
      ),
      subtitle: Text(
        '$senderPrefix${m.content}',
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      onTap: () => _onSearchResultTap(m, 'message'),
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
            if (TilingLayoutController.instance.isWorkspaceMounted) {
              TilingLayoutController.instance.openChatInActiveTile(
                chatId: chat.id,
                chatType: 'private',
                chatName: result.name,
                avatarUrl: result.avatarUrl,
                otherUserId: result.id,
              );
              return;
            }
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
          if (TilingLayoutController.instance.isWorkspaceMounted) {
            TilingLayoutController.instance.openChatInActiveTile(
              chatId: result.id,
              chatType: 'group',
              chatName: result.name,
              avatarUrl: result.avatarUrl,
            );
            return;
          }
          Navigator.push(
            context,
            SwipeBackPageRoute(
              builder: (_) => GroupChatScreen(
                chatId: result.id,
                groupName: result.name,
                groupAvatar: result.avatarUrl,
              ),
            ),
          ).then((_) {
            if (mounted) _refreshChatLastMessage(result.id);
          });
        }
        break;
      case 'channel':
        if (result is SearchResultChannel) {
          if (TilingLayoutController.instance.isWorkspaceMounted) {
            TilingLayoutController.instance.openChatInActiveTile(
              chatId: result.id,
              chatType: 'channel',
              chatName: result.name,
              avatarUrl: result.avatarUrl,
            );
            return;
          }
          Navigator.push(
            context,
            SwipeBackPageRoute(
              builder: (_) => ChannelScreen(
                channelId: result.id,
                channelName: result.name,
                channelAvatar: result.avatarUrl,
              ),
            ),
          ).then((_) {
            if (mounted) _refreshChatLastMessage(result.id);
          });
        }
        break;
      case 'community':
        if (result is Community) {
          if (result.isMember) {
            _onCommunityCreated(result);
            _openChat(_communityToChat(result));
          } else {
            Navigator.push(
              context,
              SwipeBackPageRoute(
                builder: (_) => CommunityScreen(
                  community: result,
                  onCommunityJoined: _onCommunityCreated,
                  onCommunityLeft: _loadCommunities,
                ),
              ),
            ).then((_) => _loadCommunities());
          }
        }
        break;
      case 'message':
        if (result is SearchResultMessage) {
          final targetChatId = result.chatId.isNotEmpty
              ? result.chatId
              : (result.channelId.isNotEmpty
                  ? result.channelId
                  : result.groupId);
          final dbChat = await AppDatabase().getChat(targetChatId);
          final chatType = dbChat?.chatType ??
              (result.chatType.isNotEmpty
                  ? result.chatType
                  : (result.channelId.isNotEmpty ? 'channel' : 'group'));
          final effectiveChatName = dbChat?.name.isNotEmpty == true
              ? dbChat!.name
              : result.chatName;

          if (!mounted) return;
          if (TilingLayoutController.instance.isWorkspaceMounted) {
            TilingLayoutController.instance.openChatInActiveTile(
              chatId: targetChatId,
              chatType: chatType,
              chatName: effectiveChatName,
              avatarUrl: dbChat?.avatarUrl,
              otherUserId: dbChat?.otherUserId,
              otherUserOnline: dbChat?.isOnline ?? false,
              otherUserLastSeen:
                  DateTimeUtils.parseUtcDateTime(dbChat?.lastSeen),
              initialMessageId: result.id,
            );
            return;
          }
          if (chatType == 'private') {
            Navigator.push(
              context,
              SwipeBackPageRoute(
                builder: (_) => PrivateChatScreen(
                  chatId: targetChatId,
                  otherUserName: effectiveChatName,
                  initialMessageId: result.id,
                ),
              ),
            );
          } else if (chatType == 'group') {
            Navigator.push(
              context,
              SwipeBackPageRoute(
                builder: (_) => GroupChatScreen(
                  chatId: targetChatId,
                  groupName: effectiveChatName,
                  initialMessageId: result.id,
                ),
              ),
            );
          } else {
            Navigator.push(
              context,
              SwipeBackPageRoute(
                builder: (_) => ChannelScreen(
                  channelId: targetChatId,
                  channelName: effectiveChatName,
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
      case 'community':
        return Icon(Icons.hub_outlined, color: color, size: size);
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

class _PlusActionGlyph extends StatelessWidget {
  final double size;
  final VoidCallback onTap;

  const _PlusActionGlyph({
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
          child: iconoir.Plus(
            width: 28.0,
            height: 28.0,
            color: isDark ? Colors.white : const Color(0xFF121215),
          ),
        ),
      ),
    );
  }
}




