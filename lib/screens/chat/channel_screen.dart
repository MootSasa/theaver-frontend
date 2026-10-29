import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import '../../models/theav_theme.dart';
import '../../services/chat_service.dart';
import '../../services/auth_service.dart';
import '../../services/websocket_service.dart';
import '../../services/unread_count_provider.dart';
import '../../services/database/app_database.dart';
import '../../services/sync_service.dart';
import '../../services/chat_realtime_manager.dart';
import '../../services/notification_service.dart';
import '../../services/profile_instant_cache.dart';
import '../../services/profile_theme_provider.dart';
import 'package:drift/drift.dart' show Value;
import '../../utils/image_utils.dart';
import '../../utils/emoji_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/chat/liquid_glass_input_field.dart';
import '../../widgets/chat/floating_glass_app_bar.dart';
import '../../widgets/chat/chat_scaffold.dart';
import '../../widgets/chat/chat_input_bar.dart';
import '../../widgets/chat/chat_messages_list_view.dart';
import '../../widgets/chat/chat_scroll_navigator.dart';
import '../../widgets/chat/emoji_sticker_panel.dart';
import '../../widgets/message/message_bubble.dart';
import '../../widgets/message/text_message_widget.dart';
import '../../widgets/message/message_status_widget.dart';
import '../../widgets/chat/message_reply_info.dart';
import '../../widgets/chat/swipe_to_reply_wrapper.dart';
import '../../widgets/chat/unread_separator.dart';
import '../../utils/swipe_back_route.dart';
import 'private_chat_screen.dart';
import 'group_chat_screen.dart';
import '../../utils/entity_parser.dart';
import '../../l10n/app_localizations.dart';
import '../../utils/date_time_utils.dart';
import '../../config/app_config.dart';
import '../../services/media_playback_coordinator.dart';
import '../../services/media_cache_manager.dart';
import '../../services/file_service.dart';
import '../../services/video_note_recorder_service.dart';
import '../../services/video_note_playback_service.dart';
import '../../services/voice_note_recorder_service.dart';
import '../../services/voice_playback_service.dart';
import '../../widgets/chat/media_note_player_header.dart';
import '../../widgets/chat/round_video_recording_overlay.dart';
import '../../widgets/chat/voice_recording_overlay.dart';
import '../../widgets/message/video_message_widget.dart';
import '../../widgets/message/voice_message_widget.dart';
import '../../widgets/message/poll_message_widget.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/draft_service.dart';
import '../../services/chat_actions_helper.dart';
import '../../services/glass_toast_service.dart';
import '../../services/message_context_menu_service.dart';
import '../settings/profile_screen.dart';
import '../../services/tiling_layout_controller.dart';
import '../../widgets/tiling/tile_viewport_scope.dart';



class ChannelScreen extends StatefulWidget {
  final String channelId;
  final String? channelName;
  final String? channelAvatar;
  final String? highlightMessageId;

  const ChannelScreen({
    Key? key,
    required this.channelId,
    this.channelName,
    this.channelAvatar,
    this.highlightMessageId,
  }) : super(key: key);

  @override
  State<ChannelScreen> createState() => _ChannelScreenState();
}

class _ChannelScreenState extends State<ChannelScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  final List<Message> _messages = [];
  final MarkdownTextEditingController _messageController = MarkdownTextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();

  // Emoji panel & keyboard state
  bool _showEmojiPanel = false;
  bool _isKeyboardRising = false;
  bool _isKeyboardFalling = false;
  double _keyboardHeight = 270.0;
  double _lastBottomInset = 0.0;
  Timer? _transitionTimer;
  late AnimationController _emojiPanelController;
  late Animation<double> _emojiPanelAnimation;
  String? _lastActiveTileId;

  bool get _isDesktopPlatform =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  bool get _isMobilePlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  bool _isLoading = true;
  bool _isSyncing = false;
  Timer? _syncDebounceTimer;
  bool _hasMoreMessages = true;
  bool _isLoadingMore = false;
  bool _isProgrammaticJump = false;
  bool _isDetachedHistoryWindow = false;
  bool _hasMoreNewerMessages = false;
  bool _isLoadingNewer = false;
  List<Message> _detachedLatestBackup = [];
  bool _detachedBackupHasMoreOlder = true;
  bool _isSending = false;
  String? _currentUserId;
  String _channelName = '';
  String? _channelAvatar;
  int _subscriberCount = 0;
  bool _isAdmin = false;
  bool _isMuted = false;
  bool _showScrollDownFab = false;
  double _lastScrollOffset = 0;
  double _accumulatedScrollDown = 0;
  double _accumulatedScrollUp = 0;
  String? _highlightMessageId;
  bool _hasScrolledToHighlight = false;
  final GlobalKey _inputKey = GlobalKey();
  double _inputHeight = 90.0;
  final Map<String, GlobalKey> _messageKeys = {};
  final List<String> _jumpHistory = [];

  // Multi-message selection & desktop LMB drag state
  final Set<String> _selectedMessageIds = <String>{};
  bool get _isSelectionMode => _selectedMessageIds.isNotEmpty;
  int? _dragSelectStartIndex;
  bool _dragSelectTargetState = true;
  Set<String> _dragSelectBaselineIds = <String>{};
  bool _isLmbDraggingMessages = false;
  bool _isLmbDirectTextSelecting = false;
  Offset? _lmbDownGlobalPos;
  int? _lmbDownFeedIndex;
  Message? _lmbDownMessage;
  GlobalKey? _lmbDownKey;
  bool _lmbDownIsMe = false;
  bool _lmbDownInsideBubble = false;
  bool _lmbDownInsideText = false;

  // Touch & pointer tracking for keyboard/emoji dismissal (fast scroll + tap outside)
  Offset? _touchDownPos;
  Offset? _lastTouchPos;
  Duration? _lastTouchTime;
  double _touchVelocityY = 0.0;
  bool _dismissedOnCurrentTouch = false;
  bool _touchDownInsideBubble = false;

  // Reply / Quote state
  Message? _replyToMessage;
  bool _isQuote = false;
  String? _quoteText;
  int _quoteOffset = 0;
  int _quoteLength = 0;

  // Edit message state
  bool _isEditing = false;
  String? _editingMessageId;

  // File upload & voice/video note recording state
  final FileService _fileService = FileService();
  final ValueNotifier<double> _uploadProgressNotifier = ValueNotifier<double>(0.0);
  bool _isUploading = false;
  final VideoNoteRecorderService _videoRecorderService = VideoNoteRecorderService();
  final GlobalKey _videoOverlayKey = GlobalKey();
  bool _isVideoRecording = false;
  final VoiceNoteRecorderService _voiceRecorderService = VoiceNoteRecorderService();
  final GlobalKey _voiceOverlayKey = GlobalKey();
  bool _isVoiceRecording = false;
  bool _isVideoPointerDown = false;
  bool _isVoicePointerDown = false;

  // WebSocket & Realtime
  final WebSocketService _wsService = WebSocketService();
  ChatSubscription? _chatSubscription;
  UnreadCountProvider? _unreadCountProvider;
  String? _registeredTileId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _highlightMessageId = widget.highlightMessageId;
    ProfileInstantCache.instance.prefetchGroupOrChannel(widget.channelId);

    _emojiPanelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _emojiPanelAnimation = CurvedAnimation(
      parent: _emojiPanelController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _loadData();
    _loadCachedKeyboardHeight();
    _initWebSocket();
    _inputFocusNode.addListener(_onFocusChanged);
    _lastActiveTileId = TilingLayoutController.instance.activeTileId;
    TilingLayoutController.instance.addListener(_onTilingLayoutChanged);
    if (_isDesktopPlatform) {
      HardwareKeyboard.instance.addHandler(_handleGlobalDesktopKeyEvent);
    }

    // Restore draft if exists
    final draft = DraftService().getDraft(widget.channelId);
    if (draft != null && draft.isNotEmpty) {
      _messageController.text = draft.text;
      if (draft.quoteText != null && draft.quoteText!.isNotEmpty) {
        _isQuote = draft.isQuote;
        _quoteText = draft.quoteText;
      }
    }
    _messageController.addListener(_onInputTextChanged);

    // Connect continuous media playback with coordinator
    MediaPlaybackCoordinator.instance.registerChat(
      widget.channelId,
      ChatPlaybackCallbacks(
        onScrollToMessage: (id) => _scrollToMessage(id),
        onPlayNext: _playNextMediaNote,
        onBuildPlaylist: (id) => _buildPlaylistFrom(id),
      ),
    );
    NotificationService().addActiveChat(widget.channelId);

    _scrollController.addListener(() {
      if (!_scrollController.hasClients || _messages.isEmpty) return;

      // Пагинация: когда пользователь проскроллил вверх — загрузить ещё
      if (!_isProgrammaticJump && _hasMoreMessages && !_isLoadingMore) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        final currentScroll = _scrollController.offset;
        if (maxScroll > 0 && (currentScroll >= maxScroll * 0.75 || (maxScroll - currentScroll) < 600)) {
          _loadMoreMessages();
        }
      }

      // Пагинация вниз к настоящему при просмотре окна истории
      if (!_isProgrammaticJump &&
          _isDetachedHistoryWindow &&
          _hasMoreNewerMessages &&
          !_isLoadingNewer &&
          _scrollController.offset < 500) {
        _loadNewerMessages();
      }

      final offset = _scrollController.offset;
      final delta = offset - _lastScrollOffset;
      _lastScrollOffset = offset;

      if (delta < 0) {
        _accumulatedScrollDown -= delta;
        _accumulatedScrollUp = 0;
      } else if (delta > 0) {
        _accumulatedScrollUp += delta;
        _accumulatedScrollDown = 0;
      }

      final isScrollingDown = _scrollController.position.userScrollDirection == ScrollDirection.forward;
      
      // Clear jump history when near bottom
      if (!_isDetachedHistoryWindow && offset < 100 && _jumpHistory.isNotEmpty) {
        _jumpHistory.clear();
      }

      // Dynamic threshold: height of the newest message
      double threshold = 150.0;
      if (_messages.isNotEmpty) {
        final firstMsgId = _messages.first.id;
        final key = _messageKeys[firstMsgId];
        final renderBox = key?.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null && renderBox.hasSize) {
          threshold = renderBox.size.height;
        }
      }
      
      bool shouldShow = _showScrollDownFab;
      if (_isDetachedHistoryWindow || _jumpHistory.isNotEmpty) {
        shouldShow = true;
      } else if (offset <= threshold) {
        shouldShow = false;
      } else if (delta < 0 && _accumulatedScrollDown >= 80.0 && isScrollingDown) {
        shouldShow = true;
      } else if (delta > 0 && _accumulatedScrollUp >= 120.0) {
        shouldShow = false;
      }
      
      if (shouldShow != _showScrollDownFab) {
        setState(() {
          _showScrollDownFab = shouldShow;
          if (shouldShow) {
            _accumulatedScrollDown = 0;
          } else {
            _accumulatedScrollUp = 0;
          }
        });
      }
    });

    // Notify provider that this chat is open (so unread count is not incremented)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _unreadCountProvider = context.read<UnreadCountProvider>();
        _unreadCountProvider?.openChat(widget.channelId);
      } catch (_) {}
      NotificationService().cancelChatNotifications(widget.channelId, chatTitle: widget.channelName);
      if (_isDesktopPlatform && _isAdmin && _isMyTileActive()) {
        _inputFocusNode.requestFocus();
      }
    });
  }

  bool _isMyTileActive() {
    if (!mounted) return false;
    final tileId = _registeredTileId ?? TileViewportScope.maybeTileIdOf(context);
    if (tileId == null) return true;
    return TilingLayoutController.instance.activeTileId == tileId;
  }

  void _onTilingLayoutChanged() {
    if (!mounted || !_isDesktopPlatform || !_isAdmin) return;
    final currentActive = TilingLayoutController.instance.activeTileId;
    if (currentActive != _lastActiveTileId) {
      _lastActiveTileId = currentActive;
      final myTileId = _registeredTileId ?? TileViewportScope.maybeTileIdOf(context);
      if (myTileId != null && currentActive == myTileId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isAdmin && !_isSelectionMode) {
            _inputFocusNode.requestFocus();
          }
        });
      }
    }
  }

  bool _handleGlobalDesktopKeyEvent(KeyEvent event) {
    if (!mounted || !_isDesktopPlatform || !_isAdmin) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (_inputFocusNode.hasFocus) return false;
    if (!_isMyTileActive()) return false;
    if (_isSelectionMode) return false;
    if (MessageContextMenuService().isShowing) return false;
    if (ModalRoute.of(context)?.isCurrent == false) return false;

    final primaryFocus = FocusManager.instance.primaryFocus;
    if (primaryFocus != null && primaryFocus != _inputFocusNode) {
      final ctx = primaryFocus.context;
      if (ctx != null) {
        bool insideEditable = false;
        ctx.visitAncestorElements((el) {
          if (el.widget is EditableText) {
            insideEditable = true;
            return false;
          }
          return true;
        });
        if (insideEditable) return false;
      }
    }

    final isCtrl = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;

    if (isCtrl && !isAlt && event.logicalKey == LogicalKeyboardKey.keyV) {
      _inputFocusNode.requestFocus();
      Clipboard.getData(Clipboard.kTextPlain).then((data) {
        if (!mounted || data?.text == null || data!.text!.isEmpty) return;
        final text = _messageController.text;
        final sel = _messageController.selection;
        final start = sel.isValid ? sel.start : text.length;
        final end = sel.isValid ? sel.end : text.length;
        final newText = text.replaceRange(start, end, data.text!);
        _messageController.value = TextEditingValue(
          text: newText,
          selection: TextSelection.collapsed(offset: start + data.text!.length),
        );
      });
      return true;
    }

    if (isCtrl || isAlt) return false;

    final char = event.character;
    if (char != null &&
        char.isNotEmpty &&
        char.codeUnitAt(0) >= 32 &&
        char.codeUnitAt(0) != 127) {
      _inputFocusNode.requestFocus();
      final text = _messageController.text;
      final sel = _messageController.selection;
      final start = sel.isValid ? sel.start : text.length;
      final end = sel.isValid ? sel.end : text.length;
      final newText = text.replaceRange(start, end, char);
      _messageController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: start + char.length),
      );
      return true;
    }
    return false;
  }

  Future<void> _loadCachedKeyboardHeight() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getDouble('cached_keyboard_height');
    if (cached != null && cached > 150) {
      if (mounted) setState(() => _keyboardHeight = cached);
    }
  }

  Future<void> _saveKeyboardHeight(double height) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('cached_keyboard_height', height);
  }

  void _onFocusChanged() {
    if (_inputFocusNode.hasFocus && _showEmojiPanel && !_isMobilePlatform) {
      _closeEmojiPanel();
    } else if (!_inputFocusNode.hasFocus && !_showEmojiPanel && !_isEditing) {
      DraftService().flushDraft(widget.channelId);
    }
  }

  void _closeEmojiPanel() {
    if (!_showEmojiPanel) return;
    _transitionTimer?.cancel();
    _emojiPanelController.reverse().then((_) {
      if (mounted) {
        setState(() {
          _showEmojiPanel = false;
          _isKeyboardRising = false;
          _isKeyboardFalling = false;
        });
      }
    });
  }

  void _dismissKeyboardAndEmoji() {
    if (_showEmojiPanel) {
      _closeEmojiPanel();
    }
    if (_inputFocusNode.hasFocus) {
      _inputFocusNode.unfocus();
    } else {
      FocusScope.of(context).unfocus();
    }
  }

  void _focusInputField() {
    if (!_isAdmin) return;
    if (_showEmojiPanel) {
      _closeEmojiPanel();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inputFocusNode.requestFocus();
      if (_isMobilePlatform) {
        SystemChannels.textInput.invokeMethod('TextInput.show');
      }
    });
  }

  void _editLastOwnMessage() {
    if (!_isAdmin) return;
    for (final msg in _messages) {
      if ((msg.senderId == _currentUserId || _isAdmin) &&
          msg.messageType == 'text' &&
          !msg.isRound &&
          msg.content.trim().isNotEmpty) {
        setState(() {
          _cancelReply();
          _messageController.loadMessage(msg.content, msg.entities);
          _isEditing = true;
          _editingMessageId = msg.id;
        });
        _focusInputField();
        return;
      }
    }
  }

  void _onEmojiToggle() {
    _transitionTimer?.cancel();
    final kbOpen = MediaQuery.of(context).viewInsets.bottom > 0;

    if (!_showEmojiPanel) {
      if (kbOpen) {
        _emojiPanelController.value = 1.0;
        setState(() {
          _showEmojiPanel = true;
          _isKeyboardFalling = true;
          _isKeyboardRising = false;
        });
        if (_isMobilePlatform) {
          SystemChannels.textInput.invokeMethod('TextInput.hide');
          if (!_inputFocusNode.hasFocus) {
            _inputFocusNode.requestFocus();
          }
        } else {
          _inputFocusNode.unfocus();
        }
        _transitionTimer = Timer(const Duration(milliseconds: 600), () {
          if (mounted && _isKeyboardFalling) {
            setState(() => _isKeyboardFalling = false);
          }
        });
      } else {
        setState(() {
          _showEmojiPanel = true;
          _isKeyboardFalling = false;
          _isKeyboardRising = false;
        });
        if (_isMobilePlatform && !_inputFocusNode.hasFocus) {
          _inputFocusNode.requestFocus();
        }
        _emojiPanelController.forward(from: 0.0);
      }
    } else {
      if (!_isMobilePlatform) {
        _closeEmojiPanel();
        _inputFocusNode.requestFocus();
      } else {
        setState(() {
          _isKeyboardRising = true;
          _isKeyboardFalling = false;
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          if (!_inputFocusNode.hasFocus) {
            _inputFocusNode.requestFocus();
          }
          SystemChannels.textInput.invokeMethod('TextInput.show');
        });
        _transitionTimer = Timer(const Duration(milliseconds: 600), () {
          if (mounted && _isKeyboardRising) {
            _emojiPanelController.value = 0.0;
            setState(() {
              _showEmojiPanel = false;
              _isKeyboardRising = false;
            });
          }
        });
      }
    }
  }

  void _handleBackspace() {
    final text = _messageController.text;
    final selection = _messageController.selection;
    if (text.isEmpty) return;

    if (selection.isValid && !selection.isCollapsed) {
      final newText = text.replaceRange(selection.start, selection.end, '');
      _messageController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start),
      );
      return;
    }

    final cursorPos =
        (selection.isValid && selection.baseOffset >= 0) ? selection.baseOffset : text.length;
    if (cursorPos <= 0) return;

    final beforeCursor = text.substring(0, cursorPos);
    final afterCursor = text.substring(cursorPos);
    final chars = beforeCursor.characters;
    if (chars.isEmpty) return;

    final newBefore = chars.skipLast(1).toString();
    final newText = newBefore + afterCursor;
    _messageController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: newBefore.length),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    try {
      _unreadCountProvider = context.read<UnreadCountProvider>();
    } catch (_) {}
    final tileId = TileViewportScope.maybeTileIdOf(context);
    if (tileId != _registeredTileId) {
      if (_registeredTileId != null) {
        TilingLayoutController.instance.unregisterTileBackHandler(
          _registeredTileId!,
          _handleTileBack,
        );
      }
      _registeredTileId = tileId;
      if (tileId != null) {
        TilingLayoutController.instance.registerTileBackHandler(
          tileId,
          _handleTileBack,
        );
      }
    }
  }

  bool _handleTileBack() {
    if (!mounted) return false;
    if (MessageContextMenuService().isShowing) {
      MessageContextMenuService().dismiss();
      return true;
    }
    if (_isSelectionMode) {
      _clearSelection();
      return true;
    }
    if (_showEmojiPanel) {
      _closeEmojiPanel();
      return true;
    }
    if (_isEditing) {
      _cancelEditing();
      return true;
    }
    if (_replyToMessage != null) {
      _cancelReply();
      return true;
    }
    return false;
  }

  void _initWebSocket() {
    _chatSubscription = ChatRealtimeManager().bindChat(
      chatId: widget.channelId,
      onNewMessage: _onNewMessage,
      onMessageEdited: _onMessageEdited,
      onMessageDeleted: _onMessageDeleted,
      onReconnect: _triggerSilentSync,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    }
  }

  void _onAppResumed() {
    if (!_wsService.isConnected) {
      _wsService.connect();
    }
    _triggerSilentSync();
  }

  void _triggerSilentSync() {
    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        _syncLatestMessages();
      }
    });
  }

  /// Silently synchronizes latest channel messages without flashing a loading indicator.
  Future<void> _syncLatestMessages() async {
    if (_isSyncing || !mounted) return;
    _isSyncing = true;

    try {
      final result = await ChatService.getMessages(chatId: widget.channelId, limit: 50);
      if (result['success'] == true && mounted) {
        final serverMessages = result['messages'] as List<Message>;
        final db = AppDatabase();

        if (_isDetachedHistoryWindow) {
          final Map<String, Message> mergedBackup = {
            for (final m in _detachedLatestBackup) m.id: m,
            for (final m in serverMessages) m.id: m,
          };
          _detachedLatestBackup = mergedBackup.values.toList();
          _sortMessagesDescending(_detachedLatestBackup);
        } else {
          setState(() {
            final Map<String, Message> merged = {};
            for (final m in _messages) {
              merged[m.id] = m;
            }
            for (final m in serverMessages) {
              merged[m.id] = m;
            }

            _messages.clear();
            _messages.addAll(merged.values);
            _sortMessagesDescending(_messages);
          });
        }

        try {
          db.saveMessages(serverMessages.map((m) => _messageToCompanion(m)).toList());
        } catch (e) {
          debugPrint('Drift saveMessages in channel sync error: $e');
        }

        // Refresh channel info / subscriber count
        try {
          final chatResult = await ChatService.getChat(widget.channelId);
          if (chatResult['success'] == true && mounted) {
            final chat = chatResult['chat'] as ChatDetails;
            setState(() {
              _channelName = chat.name;
              _channelAvatar = chat.avatarUrl;
              _subscriberCount = chat.participants.length;
            });
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('ChannelScreen: _syncLatestMessages error: $e');
    } finally {
      _isSyncing = false;
    }
  }


  void _onMessageDeleted(WebSocketEvent event) {
    final messageId = event.data['message_id']?.toString();
    if (messageId == null) return;

    if (mounted) {
      setState(() {
        _messages.removeWhere((m) => m.id == messageId);
      });
    }

    try {
      AppDatabase().deleteMessage(messageId);
    } catch (_) {}
  }

  void _onMessageEdited(WebSocketEvent event) {
    final messageId = event.data['message_id']?.toString();
    final newContent = event.data['content']?.toString();
    if (messageId == null) return;

    Map<String, dynamic>? newMediaPayload;
    if (event.data['media_payload'] is Map) {
      newMediaPayload =
          Map<String, dynamic>.from(event.data['media_payload'] as Map);
    } else if (event.data['poll'] is Map) {
      newMediaPayload = Map<String, dynamic>.from(event.data['poll'] as Map);
    }

    final isPollEvent =
        event.data['message_type'] == 'poll' || newMediaPayload != null;
    if (newContent == null && newMediaPayload == null) return;

    String? effectiveContent = newContent;
    if (mounted) {
      setState(() {
        final index = _messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          final current = _messages[index];
          effectiveContent ??= current.content;
          final isPollMsg = current.messageType == 'poll' || isPollEvent;
          _messages[index] = current.copyWith(
            content: effectiveContent,
            mediaPayload: newMediaPayload ?? current.mediaPayload,
            isEdited: isPollMsg ? current.isEdited : true,
          );
        }
      });
    }

    try {
      AppDatabase().updateMessageContent(
        messageId,
        effectiveContent ?? '',
        null,
        newMediaPayload != null ? jsonEncode(newMediaPayload) : null,
        !isPollEvent,
      );
    } catch (_) {}
  }

  void _onNewMessage(WebSocketEvent event) {
    final messageData = event.data['message'] as Map<String, dynamic>?;
    if (messageData == null) return;

    final message = Message.fromJson(messageData);

    // Дедупликация / обновление: проверяем есть ли уже сообщение по serverId или localId
    final existingIndex = _messages.indexWhere((m) =>
        m.id == message.id ||
        (message.localId != null &&
            message.localId!.isNotEmpty &&
            m.localId == message.localId));

    if (existingIndex != -1) {
      // Сообщение уже в списке (отправлено с этого устройства). Обновляем id, статус и обогащенный replyInfo от сервера
      if (mounted) {
        setState(() {
          final existing = _messages[existingIndex];
          _messages[existingIndex] = message.copyWith(
            localId: existing.localId ?? message.localId,
            sendStatus: 1,
            replyInfo: message.replyInfo ?? existing.replyInfo,
            isQuote: message.isQuote || existing.isQuote,
            quoteText: message.quoteText ?? existing.quoteText,
            quoteOffset: message.quoteOffset != 0 ? message.quoteOffset : existing.quoteOffset,
            quoteLength: message.quoteLength != 0 ? message.quoteLength : existing.quoteLength,
          );
        });
      }
      return;
    }

    // Сохранить в Drift для оффлайн-доступа
    final db = AppDatabase();
    try {
      db.saveMessage(_messageToCompanion(message));
    } catch (_) {}

    if (mounted) {
      if (_isDetachedHistoryWindow) {
        if (!_detachedLatestBackup.any((m) => m.id == message.id)) {
          _detachedLatestBackup.insert(0, message);
        }
      } else {
        setState(() {
          _messages.insert(0, message);
        });
      }
      if (message.senderId != _currentUserId) {
        unawaited(_markMessagesAsRead());
      }
    }
  }

  Future<void> _markMessagesAsRead() async {
    final result = await ChatService.markMessagesAsRead(
      chatId: widget.channelId,
      chatTitle: widget.channelName,
    );
    final markedCount = result['marked_count'] as int? ?? 0;
    // Notify via WebSocket that messages were read
    _wsService.sendMessageRead(widget.channelId, markedCount: markedCount);
    if (result['success'] == true || markedCount > 0) {
      try {
        _unreadCountProvider?.clear(widget.channelId);
      } catch (_) {}
    }
  }

  Future<void> _loadData() async {
    // Get current user ID
    final userId = await AuthService.getUserId();
    setState(() {
      _currentUserId = userId;
    });

    // Load channel details
    final chatResult = await ChatService.getChat(widget.channelId);
    if (chatResult['success'] == true && mounted) {
      final chat = chatResult['chat'] as ChatDetails;
      setState(() {
        _channelName = chat.name;
        _channelAvatar = chat.avatarUrl;
        _subscriberCount = chat.participants.length;
        // Check if current user is admin or owner
        for (var p in chat.participants) {
          if (p.id == _currentUserId &&
              (p.role == 'owner' || p.role == 'admin')) {
            _isAdmin = true;
            break;
          }
        }
      });
      if (_isAdmin && _isDesktopPlatform) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isMyTileActive()) {
            _inputFocusNode.requestFocus();
          }
        });
      }
    }

    // Load messages
    await _loadMessages();

    // Mark messages as read when opening channel
    await _markMessagesAsRead();
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);

    // 1. Сначала загрузить из Drift (мгновенно, offline-first)
    final db = AppDatabase();
    List<DbMessage> localMessages = [];
    try {
      localMessages = await db.getMessages(widget.channelId, limit: 50);
    } catch (e) {
      debugPrint('Channel: Drift getMessages error: $e');
    }

    if (localMessages.isNotEmpty && mounted) {
      final fixedMessages = localMessages.map((m) {
        if (m.sendStatus == MessageSendStatus.sending.index) {
          if (m.serverId != null) {
            db.updateMessageSendStatus(
                m.localId, m.serverId!, MessageSendStatus.sent.index);
            return m.copyWith(sendStatus: MessageSendStatus.sent.index);
          } else {
            db.updateMessageStatus(m.localId, MessageSendStatus.failed.index);
            return m.copyWith(sendStatus: MessageSendStatus.failed.index);
          }
        }
        return m;
      }).toList();

      setState(() {
        _isLoading = false;
        _messages.clear();
        _messages.addAll(
            fixedMessages.map((m) => Message.fromDbMessage(m)).toList());
        _hasMoreMessages = localMessages.length >= 50;
      });

      if (_highlightMessageId != null && !_hasScrolledToHighlight) {
        _scrollToMessage(_highlightMessageId!);
        _hasScrolledToHighlight = true;
      }
    }

    // 2. Затем загрузить с сервера (обновление)
    try {
      final result =
          await ChatService.getMessages(chatId: widget.channelId, limit: 50);

      if (mounted) {
        setState(() {
          _isLoading = false;
          if (result['success'] == true) {
            final serverMessages = result['messages'] as List<Message>;
            _hasMoreMessages = result['has_more'] as bool? ?? (serverMessages.length >= 50);

            // Сохранить pending/failed сообщения из текущего списка (их нет на сервере)
            final pendingMessages = _messages
                .where(
                  (m) => m.sendStatus != 1 && m.localId != null,
                )
                .toList();

            final Map<String, Message> mergedById = {};
            final Map<String, Message> existingByLocalId = {};
            for (final m in _messages) {
              mergedById[m.id] = m;
              if (m.localId != null && m.localId!.isNotEmpty) {
                existingByLocalId[m.localId!] = m;
              }
            }
            for (final m in serverMessages) {
              final existing = mergedById[m.id] ??
                  (m.localId != null && m.localId!.isNotEmpty
                      ? existingByLocalId[m.localId!]
                      : null);
              if (existing != null) {
                mergedById[m.id] = m.copyWith(
                  localId: m.localId ?? existing.localId,
                  isQuote: m.isQuote || existing.isQuote,
                  quoteText: m.quoteText ?? existing.quoteText,
                  quoteOffset: m.quoteOffset != 0 ? m.quoteOffset : existing.quoteOffset,
                  quoteLength: m.quoteLength != 0 ? m.quoteLength : existing.quoteLength,
                );
              } else {
                mergedById[m.id] = m;
              }
            }
            final Set<String> serverLocalIds = mergedById.values
                .map((m) => m.localId)
                .whereType<String>()
                .where((id) => id.isNotEmpty)
                .toSet();
            for (final pending in pendingMessages) {
              final lId = pending.localId;
              if (!mergedById.containsKey(pending.id) &&
                  (lId == null || !serverLocalIds.contains(lId))) {
                mergedById[pending.id] = pending;
              }
            }

            _messages.clear();
            _messages.addAll(mergedById.values);

            // Сортировка по createdAt по убыванию
            _messages.sort((a, b) {
              try {
                final ta = DateTime.parse(a.createdAt);
                final tb = DateTime.parse(b.createdAt);
                final cmp = tb.compareTo(ta);
                if (cmp != 0) return cmp;
                return (int.tryParse(b.id) ?? 0).compareTo(int.tryParse(a.id) ?? 0);
              } catch (_) {
                return 0;
              }
            });

            // Сохранить в Drift для оффлайн-доступа
            try {
              db.saveMessages(
                  serverMessages.map((m) => _messageToCompanion(m)).toList());
            } catch (e) {
              debugPrint('Channel: Drift saveMessages error: $e');
            }
          }
        });

        if (_highlightMessageId != null && !_hasScrolledToHighlight) {
          _scrollToMessage(_highlightMessageId!);
          _hasScrolledToHighlight = true;
        } else if (localMessages.isEmpty) {
          _scrollToBottom();
        }
      }
    } catch (e) {
      debugPrint('Channel: Error loading from server: $e');
      // Сервер недоступен — оставляем локальные данные если есть
      if (mounted && localMessages.isEmpty) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Загрузить старые сообщения (пагинация)
  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages) return;

    setState(() => _isLoadingMore = true);

    final lastMessage = _messages.isNotEmpty ? _messages.last : null;
    final db = AppDatabase();

    // Найти самый старый числовой serverId и загрузить с сервера (во избежание дыр в локальном кэше)
    String? beforeServerId;
    for (int i = _messages.length - 1; i >= 0; i--) {
      if (int.tryParse(_messages[i].id) != null) {
        beforeServerId = _messages[i].id;
        break;
      }
    }

    final result = await ChatService.getMessages(
      chatId: widget.channelId,
      beforeMessageId: beforeServerId,
      beforeCreatedAt: lastMessage?.createdAt,
      limit: 50,
    );

    if (result['success'] == true && mounted) {
      final newMessages = result['messages'] as List<Message>;
      _hasMoreMessages = result['has_more'] as bool? ?? (newMessages.length >= 50);

      if (!_isDetachedHistoryWindow) {
        try {
          db.saveMessages(
              newMessages.map((m) => _messageToCompanion(m)).toList());
        } catch (e) {
          debugPrint('Channel: Drift saveMessages error: $e');
        }
      }

      setState(() {
        for (final m in newMessages) {
          if (!_messages.any((existing) => existing.id == m.id)) {
            _messages.add(m);
          }
        }
        _sortMessagesDescending(_messages);
        _isLoadingMore = false;
      });
      return;
    }

    // Оффлайн-фоллбэк: если сервер недоступен, подгрузить из Drift
    try {
      final localMessages = await db.getMessages(
        widget.channelId,
        beforeCreatedAt: lastMessage?.createdAt,
        limit: 50,
      );

      if (localMessages.isNotEmpty && mounted) {
        setState(() {
          for (final m
              in localMessages.map((m) => Message.fromDbMessage(m))) {
            if (!_messages.any((existing) =>
                existing.id == m.id ||
                (m.localId != null && existing.localId == m.localId))) {
              _messages.add(m);
            }
          }
          _sortMessagesDescending(_messages);
          _isLoadingMore = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('Channel: Drift loadMore error: $e');
    }

    if (mounted) {
      setState(() => _isLoadingMore = false);
    }
  }

  /// Конвертация Message → MessagesCompanion для Drift
  MessagesCompanion _messageToCompanion(Message msg) {
    final hasServerId = msg.sendStatus == 1 && msg.id.isNotEmpty;
    final effectiveChatId = msg.chatId.isNotEmpty ? msg.chatId : widget.channelId;
    return MessagesCompanion(
      serverId: hasServerId ? Value(msg.id) : const Value.absent(),
      localId: Value(msg.localId ?? msg.id),
      chatId: Value(effectiveChatId),
      senderId: Value(msg.senderId),
      content: Value(msg.content),
      messageType: Value(msg.messageType),
      fileUrl: Value(msg.fileUrl),
      fileName: Value(msg.fileName),
      replyToMessageId: Value(msg.replyToMessageId),
      isQuote: Value(msg.isQuote),
      quoteText: Value(msg.quoteText),
      quoteOffset: Value(msg.quoteOffset),
      quoteLength: Value(msg.quoteLength),
      replyToSenderId: Value(msg.replyInfo?.senderId),
      replyToSenderName: Value(msg.replyInfo?.senderName),
      replyToContent: Value(msg.replyInfo?.content),
      replyToMessageType: Value(msg.replyInfo?.messageType ?? 'text'),
      isRead: Value(msg.isRead),
      isEdited: Value(msg.isEdited),
      sendStatus: Value(msg.sendStatus),
      senderName: Value(msg.senderName),
      senderAvatarUrl: Value(msg.senderAvatarUrl),
      createdAt: Value(msg.createdAt),
      reactions: msg.reactions.isNotEmpty || msg.myReactions.isNotEmpty
          ? Value(jsonEncode({
              'reactions': msg.reactions,
              'my_reactions': msg.myReactions.toList(),
            }))
          : const Value.absent(),
      isRound: Value(msg.isRound),
      groupedId: Value(msg.groupedId),
      entities: msg.entities.isNotEmpty
          ? Value(jsonEncode(msg.entities.map((e) => e.toJson()).toList()))
          : const Value.absent(),
      linkPreviewOptions: msg.linkPreviewOptions != null
          ? Value(jsonEncode(msg.linkPreviewOptions!.toJson()))
          : const Value.absent(),
      mediaPayload: msg.mediaPayload != null && msg.mediaPayload!.isNotEmpty
          ? Value(jsonEncode(msg.mediaPayload))
          : const Value.absent(),
      invertMedia: Value(msg.invertMedia),
      isForward: Value(msg.isForward),
      forwardFromId: Value(msg.forwardFromId),
      forwardFromName: Value(msg.forwardFromName),
    );
  }

  void _sortMessagesDescending(List<Message> list) {
    final dateMap = <String, int>{};
    for (final m in list) {
      dateMap[m.id] =
          DateTimeUtils.parseUtcDateTime(m.createdAt)?.millisecondsSinceEpoch ??
              0;
    }
    list.sort((a, b) {
      final ta = dateMap[a.id] ?? 0;
      final tb = dateMap[b.id] ?? 0;
      final cmp = tb.compareTo(ta);
      if (cmp != 0) return cmp;
      return (int.tryParse(b.id) ?? 0).compareTo(int.tryParse(a.id) ?? 0);
    });
  }

  Future<void> _restoreLatestMessagesTail({bool scrollToBottom = false}) async {
    if (!_isDetachedHistoryWindow || !mounted) return;
    setState(() {
      if (_detachedLatestBackup.isNotEmpty) {
        _messages
          ..clear()
          ..addAll(_detachedLatestBackup);
        _hasMoreMessages = _detachedBackupHasMoreOlder;
      }
      _isDetachedHistoryWindow = false;
      _hasMoreNewerMessages = false;
      _detachedLatestBackup = [];
      _showScrollDownFab = false;
    });
    if (scrollToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.jumpTo(0);
      });
    }
  }

  Future<void> _fetchMessagesAround(String targetMessageId) async {
    try {
      if (_isDetachedHistoryWindow &&
          _detachedLatestBackup.any((m) => m.id == targetMessageId)) {
        await _restoreLatestMessagesTail();
        return;
      }

      final targetInt = int.tryParse(targetMessageId);
      int? oldestLoadedInt;
      for (int i = _messages.length - 1; i >= 0; i--) {
        final parsed = int.tryParse(_messages[i].id);
        if (parsed != null) {
          oldestLoadedInt = parsed;
          break;
        }
      }

      if (!_isDetachedHistoryWindow &&
          targetInt != null &&
          oldestLoadedInt != null &&
          targetInt < oldestLoadedInt &&
          (oldestLoadedInt - targetInt) <= 160) {
        final bridgeLimit = ((oldestLoadedInt - targetInt) + 30).clamp(60, 200);
        final bridgeRes = await ChatService.getMessages(
          chatId: widget.channelId,
          beforeMessageId: oldestLoadedInt.toString(),
          limit: bridgeLimit,
        );
        if (bridgeRes['success'] == true && mounted) {
          final bridged = bridgeRes['messages'] as List<Message>;
          if (bridged.any((m) => m.id == targetMessageId)) {
            _hasMoreMessages = bridgeRes['has_more'] as bool? ??
                (bridged.length >= bridgeLimit);
            try {
              AppDatabase().saveMessages(
                bridged.map((m) => _messageToCompanion(m)).toList(),
              );
            } catch (_) {}
            setState(() {
              for (final m in bridged) {
                if (!_messages.any((existing) => existing.id == m.id)) {
                  _messages.add(m);
                }
              }
              _sortMessagesDescending(_messages);
            });
            return;
          }
        }
      }

      final result = await ChatService.getMessages(
        chatId: widget.channelId,
        limit: 60,
        aroundMessageId: targetMessageId,
      );
      if (result['success'] == true && mounted) {
        final fetched = result['messages'] as List<Message>;
        if (fetched.isEmpty) return;

        final existingIds = <String>{for (final m in _messages) m.id};
        final bool overlapsCurrent =
            fetched.any((m) => existingIds.contains(m.id));

        setState(() {
          if (overlapsCurrent && !_isDetachedHistoryWindow) {
            for (final m in fetched) {
              if (!existingIds.contains(m.id)) {
                _messages.add(m);
              }
            }
            _sortMessagesDescending(_messages);
          } else {
            if (!_isDetachedHistoryWindow) {
              _detachedLatestBackup = List<Message>.from(_messages);
              _detachedBackupHasMoreOlder = _hasMoreMessages;
            }
            _isDetachedHistoryWindow = true;
            _hasMoreMessages =
                result['has_more'] as bool? ?? (fetched.length >= 30);
            _hasMoreNewerMessages =
                result['has_more_newer'] as bool? ?? true;
            _messages
              ..clear()
              ..addAll(fetched);
            _sortMessagesDescending(_messages);
            _showScrollDownFab = true;
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching channel messages around $targetMessageId: $e');
    }
  }

  Future<void> _loadNewerMessages() async {
    if (!_isDetachedHistoryWindow ||
        _isLoadingNewer ||
        !_hasMoreNewerMessages ||
        _messages.isEmpty) {
      return;
    }

    String? newestServerId;
    for (int i = 0; i < _messages.length; i++) {
      if (int.tryParse(_messages[i].id) != null) {
        newestServerId = _messages[i].id;
        break;
      }
    }
    if (newestServerId == null) return;

    setState(() => _isLoadingNewer = true);

    String? anchorMsgId;
    double? anchorScreenDy;
    for (int i = 0; i < _messages.length; i++) {
      final key = _messageKeys[_messages[i].id];
      final box = key?.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.attached && box.hasSize) {
        anchorMsgId = _messages[i].id;
        anchorScreenDy = box.localToGlobal(Offset.zero).dy;
        break;
      }
    }

    try {
      final result = await ChatService.getMessages(
        chatId: widget.channelId,
        afterMessageId: newestServerId,
        limit: 50,
      );
      if (result['success'] == true && mounted) {
        final newerMessages = result['messages'] as List<Message>;
        final hasMoreNewer = result['has_more_newer'] as bool? ?? false;

        final backupIds = <String>{
          for (final m in _detachedLatestBackup) m.id,
        };
        final bool reachedLatestBackup = !hasMoreNewer ||
            newerMessages.isEmpty ||
            newerMessages.any((m) => backupIds.contains(m.id));

        setState(() {
          final Map<String, Message> merged = {
            for (final m in _messages) m.id: m,
            for (final m in newerMessages) m.id: m,
          };
          if (reachedLatestBackup) {
            for (final m in _detachedLatestBackup) {
              merged[m.id] = m;
            }
            _isDetachedHistoryWindow = false;
            _hasMoreNewerMessages = false;
            _detachedLatestBackup = [];
          } else {
            _hasMoreNewerMessages = hasMoreNewer;
          }

          _messages
            ..clear()
            ..addAll(merged.values);
          _sortMessagesDescending(_messages);
          _isLoadingNewer = false;
        });

        if (anchorMsgId != null && anchorScreenDy != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_scrollController.hasClients) return;
            final key = _messageKeys[anchorMsgId];
            final box = key?.currentContext?.findRenderObject() as RenderBox?;
            if (box != null && box.attached && box.hasSize) {
              final newDy = box.localToGlobal(Offset.zero).dy;
              final delta = newDy - anchorScreenDy!;
              if (delta.abs() > 1.0) {
                final pos = _scrollController.position;
                final adjusted = (pos.pixels - delta)
                    .clamp(pos.minScrollExtent, pos.maxScrollExtent);
                _scrollController.jumpTo(adjusted);
              }
            }
          });
        }
      } else if (mounted) {
        setState(() => _isLoadingNewer = false);
      }
    } catch (e) {
      debugPrint('Error loading newer channel messages: $e');
      if (mounted) {
        setState(() => _isLoadingNewer = false);
      }
    }
  }

  /// Scroll to a specific message and highlight it using RenderObject-guided seek
  Future<void> _scrollToMessage(String messageId) async {
    if (!mounted) return;

    if (_isDetachedHistoryWindow &&
        !_messages.any((m) => m.id == messageId) &&
        _detachedLatestBackup.any((m) => m.id == messageId)) {
      await _restoreLatestMessagesTail();
    }

    int index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) {
      await _fetchMessagesAround(messageId);
      if (!mounted) return;
      index = _messages.indexWhere((m) => m.id == messageId);
      int loadRetries = 0;
      while (index == -1 && _hasMoreMessages && loadRetries < 3 && mounted) {
        await _loadMoreMessages();
        loadRetries++;
        index = _messages.indexWhere((m) => m.id == messageId);
      }
      if (index == -1) return;
    }

    _isProgrammaticJump = true;
    try {
      final reached = await ChatScrollNavigator.scrollToTarget(
        scrollController: _scrollController,
        targetIndex: index,
        itemCount: _messages.length,
        isMounted: () => mounted,
        keyForIndex: (i) => _messageKeys[_messages[i].id],
        resolveTargetKey: () => _messageKeys[messageId],
        alignment: 0.5,
      );
      if (reached && mounted) {
        _setHighlight(messageId);
      }
    } finally {
      _isProgrammaticJump = false;
    }
  }

  void _setHighlight(String messageId) {
    if (!mounted) return;
    setState(() {
      _highlightMessageId = messageId;
    });

    // Clear highlight after a delay
    Future.delayed(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _highlightMessageId = null;
        });
      }
    });
  }

  /// Handles tapping on a reply/forward header
  Future<void> _handleReplyTap(String messageId, String? originalChatId, {String? fromMessageId}) async {
    if (originalChatId == null || originalChatId == widget.channelId) {
      if (fromMessageId != null && (_jumpHistory.isEmpty || _jumpHistory.last != fromMessageId)) {
        _jumpHistory.add(fromMessageId);
        setState(() {
          _showScrollDownFab = true;
        });
      }
      await _scrollToMessage(messageId);
      return;
    }

    final result = await ChatService.getChat(originalChatId);
    if (result['success'] == true) {
      final chat = result['chat'] as ChatDetails;
      Widget targetScreen;
      if (chat.chatType == 'group') {
        targetScreen = GroupChatScreen(chatId: chat.id, initialMessageId: messageId);
      } else if (chat.chatType == 'channel') {
        targetScreen = ChannelScreen(channelId: chat.id, highlightMessageId: messageId);
      } else {
        targetScreen = PrivateChatScreen(
          chatId: chat.id,
          otherUserName: chat.name,
          otherUserAvatar: chat.avatarUrl,
          initialMessageId: messageId,
        );
      }

      if (mounted) {
        Navigator.push(
          context,
          SwipeBackPageRoute(builder: (_) => targetScreen),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'У вас нет доступа к этому сообщению'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
    }
  }

  Future<void> _sendMessage({
    String? cleanText,
    List<MessageEntity>? entities,
    LinkPreviewOptions? linkPreviewOptions,
    bool invertMedia = false,
  }) async {
    final String rawText = _messageController.text.trim();
    final String text = cleanText?.trim() ?? rawText;
    if (text.isEmpty || _isSending) return;

    final parsed = cleanText != null ? null : EntityParser.parseMarkdown(text);
    final String effectiveContent = cleanText ?? parsed!.cleanText;
    final List<MessageEntity>? effectiveEntities =
        entities ?? (parsed?.entities.isNotEmpty == true ? parsed!.entities : null);

    if (_isEditing && _editingMessageId != null) {
      final editingId = _editingMessageId!;
      setState(() {
        _isEditing = false;
        _editingMessageId = null;
        final index = _messages.indexWhere((m) => m.id == editingId);
        if (index != -1) {
          _messages[index] = _messages[index].copyWith(
            content: effectiveContent,
            isEdited: true,
            entities: effectiveEntities ?? const [],
          );
        }
      });
      _messageController.clear();
      try {
        await AppDatabase().updateMessageContent(
          editingId,
          effectiveContent,
          effectiveEntities != null && effectiveEntities.isNotEmpty
              ? jsonEncode(effectiveEntities.map((e) => e.toJson()).toList())
              : null,
        );
      } catch (_) {}
      await ChatService.editMessage(
        chatId: widget.channelId,
        messageId: editingId,
        content: effectiveContent,
        entities: effectiveEntities,
      );
      return;
    }

    final replyTo = _replyToMessage;
    final replyIsQuote = _isQuote;
    final replyQuoteText = _quoteText;
    final replyQuoteOffset = _quoteOffset;
    final replyQuoteLength = _quoteLength;

    _messageController.clear();
    DraftService().deleteDraft(widget.channelId);
    setState(() {
      _isSending = true;
      _replyToMessage = null;
      _isQuote = false;
      _quoteText = null;
      _quoteOffset = 0;
      _quoteLength = 0;
    });
    _scrollToBottom();

    final syncService = SyncService();
    String? pendingLocalId;
    DbMessage? pendingMsg;
    try {
      pendingMsg = await syncService.createPendingMessage(
        chatId: widget.channelId,
        senderId: _currentUserId ?? '',
        content: effectiveContent,
        messageType: 'text',
        replyToMessageId: replyTo?.id,
        isQuote: replyIsQuote,
        quoteText: replyQuoteText,
        quoteOffset: replyQuoteOffset,
        quoteLength: replyQuoteLength,
        replyToSenderId: replyTo?.senderId,
        replyToSenderName: replyTo?.senderName,
        replyToContent: replyTo?.content,
        replyToMessageType: replyTo?.messageType ?? 'text',
        entities: effectiveEntities,
        linkPreviewOptions: linkPreviewOptions,
        invertMedia: invertMedia,
      );
    } catch (e) {
      debugPrint('SyncService createPendingMessage error: $e');
    }

    if (pendingMsg != null) {
      pendingLocalId = pendingMsg.localId;
      final profileTheme = context.read<ProfileThemeProvider>();
      var message = Message.fromDbMessage(pendingMsg);
      if (replyTo != null) {
        final isReplyToMe = replyTo.senderId == _currentUserId;
        message = message.copyWith(
          replyInfo: ReplyInfo(
            messageId: replyTo.id,
            senderId: replyTo.senderId,
            senderName: replyTo.senderName,
            content: replyTo.content,
            messageType: replyTo.messageType,
            entities: replyTo.entities,
            nameColorPresetId: isReplyToMe
                ? profileTheme.currentNameColorPreset.id
                : (replyTo.senderNameColorId ?? 'name_red'),
            replyStripStyle: isReplyToMe
                ? profileTheme.currentStripStyle.name
                : (replyTo.senderReplyStripStyle ?? 'solid'),
          ),
        );
      }
      if (mounted) {
        setState(() {
          _messages.insert(0, message);
          _isSending = false;
        });
        _scrollToBottom();
      }

      try {
        final result = await ChatService.sendMessage(
          chatId: widget.channelId,
          content: effectiveContent,
          messageType: 'text',
          localId: pendingLocalId,
          replyToMessageId: replyTo?.id,
          isQuote: replyIsQuote,
          quoteText: replyQuoteText,
          quoteOffset: replyQuoteOffset,
          quoteLength: replyQuoteLength,
          entities: effectiveEntities,
          linkPreviewOptions: linkPreviewOptions,
          invertMedia: invertMedia,
        );

        if (result['success'] == true) {
          final sentMessage = result['message'];
          final serverId = sentMessage is Message ? sentMessage.id : null;
          if (serverId != null && serverId.isNotEmpty) {
            await syncService.confirmMessageSent(pendingLocalId, serverId);
            if (mounted) {
              setState(() {
                final idx =
                    _messages.indexWhere((m) => m.localId == pendingLocalId);
                if (idx != -1) {
                  if (sentMessage is Message) {
                    final existing = _messages[idx];
                    _messages[idx] = sentMessage.copyWith(
                      localId: pendingLocalId,
                      sendStatus: 1, // sent
                      replyInfo: sentMessage.replyInfo ?? existing.replyInfo,
                      isQuote: sentMessage.isQuote || existing.isQuote || replyIsQuote,
                      quoteText: sentMessage.quoteText ?? existing.quoteText ?? replyQuoteText,
                      quoteOffset: sentMessage.quoteOffset != 0
                          ? sentMessage.quoteOffset
                          : (existing.quoteOffset != 0 ? existing.quoteOffset : replyQuoteOffset),
                      quoteLength: sentMessage.quoteLength != 0
                          ? sentMessage.quoteLength
                          : (existing.quoteLength != 0 ? existing.quoteLength : replyQuoteLength),
                    );
                  } else {
                    _messages[idx] = _messages[idx].copyWith(
                      id: serverId,
                      sendStatus: 1, // sent
                    );
                  }
                }
              });
            }
          }
        } else {
          final errMsg = result['message']?.toString() ?? 'Failed to send message';
          debugPrint('ChatService.sendMessage in channel returned false: $errMsg');
          await syncService.markMessageFailed(pendingLocalId);
          if (mounted) {
            setState(() {
              final idx =
                  _messages.indexWhere((m) => m.localId == pendingLocalId);
              if (idx != -1) {
                _messages[idx] =
                    _messages[idx].copyWith(sendStatus: 2); // failed
              }
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(errMsg)),
            );
          }
        }
      } catch (e) {
        debugPrint('ChatService.sendMessage in channel exception: $e');
        await syncService.markMessageFailed(pendingLocalId);
        if (mounted) {
          setState(() {
            final idx =
                _messages.indexWhere((m) => m.localId == pendingLocalId);
            if (idx != -1) {
              _messages[idx] =
                  _messages[idx].copyWith(sendStatus: 2); // failed
            }
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Failed to send message: $e')),
          );
        }
      }
    } else {
      final result = await ChatService.sendMessage(
        chatId: widget.channelId,
        content: text,
      );

      if (mounted) {
        if (result['success'] == true) {
          final sentMsg = result['message'] as Message;
          setState(() {
            if (!_messages.any((m) => m.id == sentMsg.id)) {
              _messages.insert(0, sentMsg);
            }
            _isSending = false;
          });
          _scrollToBottom();
        } else {
          setState(() => _isSending = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(result['message'] ?? 'Failed to send message')),
          );
        }
      }
    }
  }

  /// Повторить отправку failed-сообщения
  Future<void> _retryMessage(Message message) async {
    if (message.localId == null) return;
    final syncService = SyncService();

    setState(() {
      final idx = _messages.indexWhere((m) => m.localId == message.localId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(sendStatus: 0);
      }
    });

    await syncService.retryFailedMessage(message.localId!);

    final db = AppDatabase();
    try {
      final updated = await db.getMessageByLocalId(message.localId!);
      if (updated != null && mounted) {
        setState(() {
          final idx =
              _messages.indexWhere((m) => m.localId == message.localId);
          if (idx != -1) {
            _messages[idx] = Message.fromDbMessage(updated);
          }
        });
      }
    } catch (e) {
      debugPrint('Retry getMessageByLocalId error: $e');
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.minScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onInputTextChanged() {
    DraftService().saveDraft(
      widget.channelId,
      text: _messageController.text,
      replyToMessageId: _replyToMessage?.id,
      quoteText: _quoteText,
      isQuote: _isQuote,
    );
  }

  void _startReply(Message message) {
    setState(() {
      if (_isEditing) {
        _isEditing = false;
        _editingMessageId = null;
        _messageController.clear();
      }
      _replyToMessage = message;
      _isQuote = false;
      _quoteText = null;
      _quoteOffset = 0;
      _quoteLength = 0;
    });
    DraftService().saveDraft(
      widget.channelId,
      text: _messageController.text,
      replyToMessageId: message.id,
      isQuote: false,
    );
    _focusInputField();
  }

  void _startQuote(Message message, String selectedText, int offset, int length) {
    setState(() {
      if (_isEditing) {
        _isEditing = false;
        _editingMessageId = null;
        _messageController.clear();
      }
      _replyToMessage = message;
      _isQuote = true;
      _quoteText = selectedText;
      _quoteOffset = offset;
      _quoteLength = length;
    });
    DraftService().saveDraft(
      widget.channelId,
      text: _messageController.text,
      replyToMessageId: message.id,
      quoteText: selectedText,
      isQuote: true,
    );
    _messageController.selection = TextSelection.collapsed(
      offset: _messageController.text.length,
    );
    _focusInputField();
  }

  void _cancelReply() {
    setState(() {
      _replyToMessage = null;
      _isQuote = false;
      _quoteText = null;
      _quoteOffset = 0;
      _quoteLength = 0;
    });
    DraftService().saveDraft(
      widget.channelId,
      text: _messageController.text,
    );
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _editingMessageId = null;
      _messageController.clear();
    });
  }

  String _formatTime(String timestamp) {
    return DateTimeUtils.formatTimeHHmm(timestamp);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _transitionTimer?.cancel();
    _syncDebounceTimer?.cancel();

    DraftService().flushDraft(widget.channelId);
    _messageController.removeListener(_onInputTextChanged);
    _emojiPanelController.dispose();
    _inputFocusNode.removeListener(_onFocusChanged);
    _inputFocusNode.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _chatSubscription?.cancel();

    TilingLayoutController.instance.removeListener(_onTilingLayoutChanged);
    if (_isDesktopPlatform) {
      HardwareKeyboard.instance.removeHandler(_handleGlobalDesktopKeyEvent);
    }

    if (_registeredTileId != null) {
      TilingLayoutController.instance.unregisterTileBackHandler(
        _registeredTileId!,
        _handleTileBack,
      );
    }

    if (_isVoiceRecording) {
      _voiceRecorderService.cancelRecording();
    }
    if (_isVideoRecording) {
      _videoRecorderService.cancelRecording();
    }
    _videoRecorderService.dispose();
    _voiceRecorderService.dispose();
    _uploadProgressNotifier.dispose();

    MediaPlaybackCoordinator.instance.unregisterChat(widget.channelId);

    _updateInputHeight();

    // Clear the open chat indicator in the provider
    try {
      _unreadCountProvider?.closeChat(widget.channelId);
    } catch (_) {}
    NotificationService().removeActiveChat(widget.channelId);

    super.dispose();
  }

  List<PlaybackTrack> _buildPlaylistFrom(String startMessageId) {
    final List<PlaybackTrack> playlist = [];
    final startIndex = _messages.indexWhere(
        (m) => m.id == startMessageId || m.localId == startMessageId);
    if (startIndex >= 0) {
      for (int i = startIndex - 1; i >= 0; i--) {
        final m = _messages[i];
        final rawUrl = m.fileUrl ?? '';
        final resolvedUrl = AppConfig.resolveMediaUrl(rawUrl) ?? rawUrl;
        if (resolvedUrl.isEmpty) continue;

        if (m.messageType == 'voice') {
          playlist.add(PlaybackTrack(
            messageId: m.id,
            chatId: widget.channelId,
            chatType: 'channel',
            mediaType: 'voice',
            mediaUrl: resolvedUrl,
            senderName: m.senderName,
            chatTitle: widget.channelName,
            duration: m.duration != null && m.duration! > 0 ? Duration(seconds: m.duration!) : null,
            waveform: m.waveform,
          ));
        } else if (m.isRound || (m.messageType == 'video' && m.isRound)) {
          playlist.add(PlaybackTrack(
            messageId: m.id,
            chatId: widget.channelId,
            chatType: 'channel',
            mediaType: 'video_note',
            mediaUrl: resolvedUrl,
            senderName: m.senderName,
            chatTitle: widget.channelName,
            duration: m.duration != null && m.duration! > 0 ? Duration(seconds: m.duration!) : null,
          ));
        }
      }
    }
    return playlist;
  }

  void _playNextMediaNote(String currentMessageId) {
    if (!mounted) return;
    final playlist = _buildPlaylistFrom(currentMessageId);
    if (playlist.isNotEmpty) {
      final nextTrack = playlist.removeAt(0);
      MediaPlaybackCoordinator.instance.startPlayback(
        track: nextTrack,
        remainingQueue: playlist,
      );
      return;
    }
    MediaPlaybackCoordinator.instance.stopAll();
  }

  void _updateInputHeight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_isAdmin) {
        if (_inputHeight != 0) setState(() => _inputHeight = 0);
        return;
      }
      final RenderBox? renderBox = _inputKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null) {
        final newHeight = renderBox.size.height;
        if (newHeight != _inputHeight && newHeight > 0) {
          setState(() {
            _inputHeight = newHeight;
          });
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    _updateInputHeight();
    final displayName = widget.channelName ?? (_channelName.isNotEmpty ? _channelName : 'Channel');
    final topPadding = ChatScaffold.getTopContentPadding(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    if (bottomInset > _keyboardHeight && !_showEmojiPanel) {
      _keyboardHeight = bottomInset;
      _saveKeyboardHeight(bottomInset);
    }

    if (_isKeyboardRising && bottomInset >= _keyboardHeight * 0.9) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isKeyboardRising) {
          setState(() {
            _isKeyboardRising = false;
            _showEmojiPanel = false;
          });
          _emojiPanelController.value = 0.0;
        }
      });
    }

    // If the user dismissed the system keyboard on mobile (e.g. Android Back/Down),
    // unfocus the input field so the blinking cursor does not stay stuck when both
    // keyboard and emoji panel are closed.
    if (_isMobilePlatform &&
        _lastBottomInset > 0 &&
        bottomInset == 0 &&
        !_showEmojiPanel &&
        !_isKeyboardFalling &&
        !_isKeyboardRising &&
        _inputFocusNode.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            MediaQuery.of(context).viewInsets.bottom == 0 &&
            !_showEmojiPanel &&
            _inputFocusNode.hasFocus) {
          _inputFocusNode.unfocus();
        }
      });
    }
    _lastBottomInset = bottomInset;

    final bool isKeyboardVisible = bottomInset > 0;

    final String subscriberText = context.l10n
        .translate('chat_status_subscribers_count')
        .replaceAll('{count}', _subscriberCount.toString());

    return ChatScaffold(
      canPop: !isKeyboardVisible && !_showEmojiPanel && !_isSelectionMode,
      onPopInvoked: (didPop, _) {
        if (!didPop) {
          if (_isSelectionMode) {
            _clearSelection();
          } else if (_showEmojiPanel) {
            _closeEmojiPanel();
          } else if (isKeyboardVisible) {
            FocusScope.of(context).unfocus();
          }
        }
      },
      appBar: FloatingGlassAppBar(
        name: displayName,
        avatarUrl: widget.channelAvatar ?? _channelAvatar,
        isOnline: false, // Channel doesn't have online status
        statusText: subscriberText,
        isChannel: true, // Calls hidden in channel
        isMuted: _isMuted,
        heroTag: displayName,
        isSelectionMode: _isSelectionMode,
        selectedCount: _selectedMessageIds.length,
        onCancelSelection: _clearSelection,
        onCopySelected: _copySelectedMessages,
        onForwardSelected: _forwardSelectedMessages,
        onDeleteSelected: _isAdmin ? _deleteSelectedMessages : null,
        profileScreenBuilder: (_) => ProfileScreen(
          entityType: ProfileEntityType.channel,
          chatId: widget.channelId,
          initialName: displayName,
          initialAvatarUrl: widget.channelAvatar ?? _channelAvatar,
          heroTag: displayName,
          onJumpToMessageId: (msgId) => _scrollToMessage(msgId),
        ),
        onBack: () => TilingLayoutController.popOrCloseChatTile(context),
        onTitleTap: () {
          Navigator.push(
            context,
            SwipeBackPageRoute(
              builder: (_) => ProfileScreen(
                entityType: ProfileEntityType.channel,
                chatId: widget.channelId,
                initialName: displayName,
                initialAvatarUrl: widget.channelAvatar ?? _channelAvatar,
                heroTag: displayName,
                onJumpToMessageId: (msgId) => _scrollToMessage(msgId),
              ),
            ),
          );
        },
        onViewProfile: () {
          Navigator.push(
            context,
            SwipeBackPageRoute(
              builder: (_) => ProfileScreen(
                entityType: ProfileEntityType.channel,
                chatId: widget.channelId,
                initialName: displayName,
                initialAvatarUrl: widget.channelAvatar ?? _channelAvatar,
                heroTag: displayName,
                onJumpToMessageId: (msgId) => _scrollToMessage(msgId),
              ),
            ),
          );
        },
        onSearch: () {
          ChatActionsHelper.openSearch(
            context: context,
            chatId: widget.channelId,
            chatName: displayName,
          );
        },
        onToggleMute: () {
          ChatActionsHelper.toggleMute(
            chatId: widget.channelId,
            currentMuted: _isMuted,
            onMuteChanged: (newMuted) => setState(() => _isMuted = newMuted),
          );
        },
        onClearHistory: () {
          ChatActionsHelper.showClearHistoryDialog(
            context: context,
            chatId: widget.channelId,
            onHistoryCleared: () {
              if (mounted) {
                setState(() {
                  _messages.clear();
                });
              }
            },
          );
        },
        onReport: () {
          // TODO: Report
        },
      ),
      floatingActionButton: ScrollDownFab(
        visible: _showScrollDownFab,
        unreadCount: 0,
        onPressed: () {
          if (_jumpHistory.isNotEmpty) {
            final lastId = _jumpHistory.removeLast();
            _scrollToMessage(lastId);
          } else if (_isDetachedHistoryWindow) {
            _restoreLatestMessagesTail(scrollToBottom: true);
          } else {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        },
      ),
      body: AnimatedBuilder(
        animation: _emojiPanelAnimation,
        builder: (context, child) {
          final emojiPanelHeight = _emojiPanelAnimation.value * _keyboardHeight;
          final effectiveBottom = (_isKeyboardFalling || _isKeyboardRising)
              ? _keyboardHeight
              : (bottomInset > emojiPanelHeight ? bottomInset : emojiPanelHeight);

          return Stack(
            children: [
              Listener(
                onPointerDown: _handleChatPointerDown,
                onPointerMove: _handleChatPointerMove,
                onPointerUp: _handleChatPointerUp,
                onPointerCancel: _handleChatPointerCancel,
                child: ChatMessagesListView(
                  isLoading: _isLoading,
                  isLoadingMore: _isLoadingMore,
                  itemCount: _messages.length,
                  scrollController: _scrollController,
                  topPadding: topPadding,
                  bottomPadding: _isAdmin ? _inputHeight + effectiveBottom + 8 : 16,
                  emptyTitle: 'No posts yet',
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    return _buildChannelMessage(message, index);
                  },
                ),
              ),
              Positioned(
                top: topPadding + 4.0,
                left: 0,
                right: 0,
                child: MediaNotePlayerHeader(
                  chatId: widget.channelId,
                  onScrollToActive: () {
                    final activeId = VoicePlaybackService().activeMessageId ??
                        VideoNotePlaybackService().activeMessageId;
                    if (activeId != null) {
                      _scrollToMessage(activeId);
                    }
                  },
                ),
              ),
              if (_isAdmin && (_emojiPanelAnimation.value > 0 || _showEmojiPanel))
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: (_isKeyboardFalling || _isKeyboardRising)
                      ? _keyboardHeight
                      : emojiPanelHeight,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      maxHeight: _keyboardHeight,
                      minHeight: _keyboardHeight,
                      child: EmojiStickerPanel(
                        controller: _messageController,
                        onBackspace: _handleBackspace,
                        onClose: _closeEmojiPanel,
                        height: _keyboardHeight,
                        isVisible: _showEmojiPanel,
                      ),
                    ),
                  ),
                ),
              if (_isAdmin)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: effectiveBottom,
                  child: Container(
                    key: _inputKey,
                    child: _buildMessageInput(),
                  ),
                ),
              if (_isVideoRecording)
                Positioned.fill(
                  child: RoundVideoRecordingOverlay(
                    key: _videoOverlayKey,
                    recorderService: _videoRecorderService,
                    onCancel: _onVideoRecordingCancelled,
                    onSend: _onVideoRecordingSend,
                    onTooShort: _onVideoRecordingTooShort,
                    replyToMessage: _replyToMessage,
                    isQuote: _isQuote,
                    quoteText: _quoteText,
                    onCancelReply: _cancelReply,
                  ),
                ),
              if (_isVoiceRecording)
                Positioned.fill(
                  child: VoiceRecordingOverlay(
                    key: _voiceOverlayKey,
                    recorderService: _voiceRecorderService,
                    onCancel: () => setState(() => _isVoiceRecording = false),
                    onSend: (res) async {
                      setState(() => _isVoiceRecording = false);
                      await _sendVoiceMessage(res);
                    },
                    onTooShort: () {
                      setState(() => _isVoiceRecording = false);
                      HapticFeedback.selectionClick();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            context.l10n.translate('chat_voice_too_short'),
                          ),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                    replyToMessage: _replyToMessage,
                    isQuote: _isQuote,
                    quoteText: _quoteText,
                    onCancelReply: _cancelReply,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildChannelMessage(Message message, int feedIndex) {
    final GlobalKey key;
    final hasLocalId = message.localId != null && message.localId!.isNotEmpty;
    if (hasLocalId && _messageKeys.containsKey(message.localId!)) {
      key = _messageKeys[message.localId!]!;
      _messageKeys[message.id] = key;
    } else {
      key = _messageKeys.putIfAbsent(message.id, () => GlobalKey());
      if (hasLocalId) {
        _messageKeys[message.localId!] = key;
      }
    }
    final isHighlighted = message.id == _highlightMessageId;
    final isSelected = _selectedMessageIds.contains(message.id);
    final bool useSelectedStyle = isSelected || isHighlighted;
    final TheavPalette? palette =
        Theme.of(context).extension<TheavThemeExtension>()?.palette;
    final Color rowHighlightColor = palette?.messageSelectionOverlay ??
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.16);
    final bool hasNoMedia = message.fileUrl == null || message.fileUrl!.trim().isEmpty;
    final int emojiCount = (message.messageType == 'text' &&
            hasNoMedia &&
            !message.hasReply &&
            message.entities.isEmpty)
        ? EmojiUtils.countEmojiOnly(message.content)
        : 0;
    final bool isBigEmoji = emojiCount > 0;
    final bool isMe = message.senderId == _currentUserId || _isAdmin;

    Widget postBody = isBigEmoji
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
              child: Align(
                alignment: Alignment.centerLeft, // Channels usually left-aligned
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    const double emojiFontSize = 64.0;
                    final String stableKey = message.localId ?? message.id;
                    final bool shouldAutoPlay = message.sendStatus == 0 ||
                        (DateTime.tryParse(message.createdAt)
                                ?.toLocal()
                                .isAfter(DateTime.now().subtract(
                                    const Duration(seconds: 3))) ??
                            false);

                    Widget metadataRow = Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.35),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          iconoir.Eye(
                            width: 10,
                            height: 10,
                            color: Colors.white.withValues(alpha: 0.8),
                          ),
                          const SizedBox(width: 4),
                          const Text(
                            '0',
                            style: TextStyle(color: Colors.white, fontSize: 10),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _formatTime(message.createdAt),
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ],
                      ),
                    );

                    return MetaData(
                      metaData: 'message_bubble_box',
                      behavior: HitTestBehavior.translucent,
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          if (emojiCount == 1)
                            LottieEmoji(
                              key: ValueKey('lottie_$stableKey'),
                              emoji: message.content,
                              width: emojiFontSize * 1.8,
                              height: emojiFontSize * 1.8,
                              isMe: false, // In channels usually left-aligned effects
                              autoPlay: shouldAutoPlay,
                              autoPlayId: stableKey,
                            )
                          else
                            Padding(
                              padding: const EdgeInsets.only(top: 4.0, bottom: 20.0, right: 16.0),
                              child: EmojiUtils.emojiOnlyText(
                                message.content,
                                fontSize: emojiCount <= 3 ? 44.0 : 32.0,
                              ),
                            ),
                          Positioned(
                            bottom: emojiCount == 1 ? 12 : 0,
                            right: emojiCount == 1 ? -16 : 0,
                            child: metadataRow,
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            )
          : MetaData(
              metaData: 'message_bubble_box',
              behavior: HitTestBehavior.translucent,
              child: Card(
                color: useSelectedStyle
                    ? (palette?.chatBubbleIncomingSelected ??
                        Theme.of(context).cardColor)
                    : null,
                margin: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header box: Forwarded info or Reply info
              if (message.hasReply)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4.0),
                  child: MessageReplyInfo(
                    replyInfo: message.replyInfo,
                    isQuote: message.isQuote,
                    quoteText: message.quoteText,
                    quoteOffset: message.quoteOffset,
                    quoteLength: message.quoteLength,
                    entitiesOverride: message.replyToMessageId != null
                        ? (_messages
                                .where((m) => m.id == message.replyToMessageId)
                                .map((m) => m.entities)
                                .firstOrNull ??
                            const [])
                        : const [],
                    isMe: false, // In channels, usually incoming style
                    onTap: () => _handleReplyTap(message.replyToMessageId!,
                        message.replyInfo?.chatId,
                        fromMessageId: message.id),
                  ),
                ),
              // Channel header
              Row(
                children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor: const Color(0xFF0088CC),
                    backgroundImage:
                        getValidAvatarUrl(message.senderAvatarUrl) != null
                            ? NetworkImage(
                                getValidAvatarUrl(message.senderAvatarUrl)!)
                            : null,
                    child: getValidAvatarUrl(message.senderAvatarUrl) == null
                        ? const iconoir.Megaphone(
                            color: Colors.white, width: 16, height: 16)
                        : null,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _channelName.isNotEmpty ? _channelName : 'Channel',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          _formatTime(message.createdAt),
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Message content
              if (message.messageType == 'voice' && message.fileUrl != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: VoiceMessageWidget(
                    key: ValueKey('voice_${message.id}'),
                    messageId: message.id,
                    audioUrl: AppConfig.resolveMediaUrl(message.fileUrl!) ?? message.fileUrl!,
                    duration: message.duration != null && message.duration! > 0
                        ? Duration(seconds: message.duration!)
                        : null,
                    waveform: message.waveform,
                    fileSize: message.mediaFileSize,
                    isMe: false,
                    isRead: true,
                    sendStatus: message.sendStatus,
                    timeText: _formatTime(message.createdAt),
                    senderName: _channelName,
                    onRetry: () => _retryMessage(message),
                    chatId: widget.channelId,
                    chatType: 'channel',
                    chatTitle: _channelName,
                  ),
                )
              else if (message.messageType == 'audio' && message.fileUrl != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: VoiceMessageWidget(
                    key: ValueKey('audio_${message.id}'),
                    messageId: message.id,
                    audioUrl: AppConfig.resolveMediaUrl(message.fileUrl!) ?? message.fileUrl!,
                    title: message.fileName ?? 'Audio',
                    duration: (message.duration ?? message.mediaDuration) != null &&
                            (message.duration ?? message.mediaDuration)! > 0
                        ? Duration(seconds: (message.duration ?? message.mediaDuration)!)
                        : null,
                    waveform: message.waveform,
                    fileSize: message.mediaFileSize,
                    isMe: false,
                    isRead: true,
                    sendStatus: message.sendStatus,
                    timeText: _formatTime(message.createdAt),
                    senderName: _channelName,
                    onRetry: () => _retryMessage(message),
                    chatId: widget.channelId,
                    chatType: 'channel',
                    chatTitle: _channelName,
                  ),
                )
              else if ((message.isRound || (message.messageType == 'video' && message.isRound)) && message.fileUrl != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: Center(
                    child: VideoMessageWidget(
                      key: ValueKey('vmsg_${message.id}'),
                      messageId: message.id,
                      videoUrl: AppConfig.resolveMediaUrl(message.fileUrl!) ?? message.fileUrl!,
                      duration: message.duration != null && message.duration! > 0
                          ? Duration(seconds: message.duration!)
                          : null,
                      thumbUrl: message.thumbUrl,
                      thumbBase64: message.thumbBase64,
                      fileSize: message.mediaFileSize,
                      isMe: false,
                      isRead: true,
                      sendStatus: message.sendStatus,
                      timeText: _formatTime(message.createdAt),
                      senderName: _channelName,
                      onRetry: () => _retryMessage(message),
                      chatId: widget.channelId,
                      chatType: 'channel',
                      chatTitle: _channelName,
                    ),
                  ),
                )
              else if (message.messageType != 'text' && message.fileUrl != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: Image.network(
                      AppConfig.resolveMediaUrl(message.fileUrl!) ?? message.fileUrl!,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const iconoir.Attachment(width: 20, height: 20),
                              const SizedBox(width: 8),
                              Text(message.fileName ?? 'File'),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ),
              LayoutBuilder(
                builder: (context, constraints) {
                  final bool isMediaNoteWithoutText =
                      message.messageType == 'voice' ||
                          message.isRound ||
                          message.messageType == 'round' ||
                          (message.messageType == 'audio' &&
                              (message.content.trim().isEmpty ||
                                  message.content.trim() == message.fileName));
                  final String displayContent =
                      isMediaNoteWithoutText ? '' : message.content;
                  final textStyle = Theme.of(context).textTheme.bodyMedium;
                  // Conservative estimate for metadata width (Views + Time + Icons + Padding)
                  const double metadataWidth = 85.0;
                  const double safetyMargin = 12.0;
                  final double maxContentWidth = constraints.maxWidth;

                  final TextPainter textPainter = TextPainter(
                    text: TextSpan(text: displayContent, style: textStyle),
                    textDirection: TextDirection.ltr,
                  )..layout(maxWidth: maxContentWidth);

                  final lineMetrics = textPainter.computeLineMetrics();
                  final double lastLineWidth =
                      lineMetrics.isNotEmpty ? lineMetrics.last.width : 0;

                  // Check if content ends with a block element (Code block, LaTeX, or Poll)
                  final bool endsWithBlock = message.messageType == 'poll' ||
                                             displayContent.trim().endsWith('```') ||
                                             displayContent.trim().endsWith('\$\$');

                  // Strict check for inline fitting
                  // But NEVER fit inline if it ends with a block element.
                  final bool fitsInline = !endsWithBlock && (lastLineWidth + metadataWidth + safetyMargin) < maxContentWidth;

                  Widget metadataRow = Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      iconoir.Eye(
                        width: 14,
                        height: 14,
                        color: Colors.grey[500]!,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '0', // Placeholder views
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatTime(message.createdAt),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500],
                        ),
                      ),
                      const SizedBox(width: 4),
                      if (message.senderId == _currentUserId) ...[
                        if (message.sendStatus == 0) // sending
                          const SizedBox(
                            width: 12,
                            height: 12,
                            child: CircularProgressIndicator(strokeWidth: 1.2),
                          )
                        else if (message.sendStatus == 2) // failed
                          GestureDetector(
                            onTap: () => _retryMessage(message),
                            child: const iconoir.WarningTriangle(
                              width: 14,
                              height: 14,
                              color: Colors.red,
                            ),
                          )
                        else
                          MessageStatusWidget(
                            isRead: message.isRead,
                            isOutgoing: true,
                          ),
                        const SizedBox(width: 4),
                      ],
                    ],
                  );

                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (!isMediaNoteWithoutText)
                        Stack(
                          clipBehavior: Clip.none,
                          children: [
                            if (message.messageType == 'poll')
                              PollMessageWidget(
                                chatId: message.chatId.isNotEmpty
                                    ? message.chatId
                                    : widget.channelId,
                                messageId: message.id,
                                questionFallback: message.content,
                                pollData: message.mediaPayload,
                                isMe: false,
                                isDark: Theme.of(context).brightness ==
                                    Brightness.dark,
                                textColor: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.white
                                    : Colors.black87,
                                subtextColor: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? Colors.grey[400]!
                                    : Colors.grey[600]!,
                                accentColor:
                                    Theme.of(context).colorScheme.primary,
                                currentUserId: _currentUserId ?? '',
                              )
                            else
                              MetaData(
                                metaData: 'message_selectable_content',
                                behavior: HitTestBehavior.translucent,
                                child: TextMessageWidget(
                                  text: displayContent,
                                  isMe: false,
                                ),
                              ),
                            if (fitsInline)
                              Opacity(
                                opacity: 0,
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // Replicate text width
                                    SizedBox(width: lastLineWidth),
                                    SizedBox(width: metadataWidth),
                                  ],
                                ),
                              ),
                            if (fitsInline)
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: metadataRow,
                              ),
                          ],
                        ),
                      if (isMediaNoteWithoutText || !fitsInline)
                        Align(
                          alignment: Alignment.bottomRight,
                          child: Padding(
                            padding: const EdgeInsets.only(top: 4.0),
                            child: metadataRow,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        ),
      ),
    );

    Widget messageWidget = AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeInOut,
      width: double.infinity,
      color: useSelectedStyle ? rowHighlightColor : Colors.transparent,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: _isSelectionMode
                ? Padding(
                    padding: const EdgeInsets.only(left: 12.0, right: 4.0),
                    child: MessageSelectionCheckbox(isSelected: isSelected),
                  )
                : const SizedBox.shrink(),
          ),
          Expanded(child: postBody),
        ],
      ),
    );

    // Wrap with SwipeToReplyWrapper for swipe-to-reply gesture
    messageWidget = SwipeToReplyWrapper(
      onReply: () => _startReply(message),
      enabled: _isAdmin && !_isSelectionMode,
      child: messageWidget,
    );

    final platform = Theme.of(context).platform;
    final bool isDesktop = platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS;

    messageWidget = Listener(
      onPointerDown: (event) => _handleMessagePointerDown(
        event: event,
        feedIndex: feedIndex,
        message: message,
        key: key,
        isMe: isMe,
      ),
      child: GestureDetector(
        onTap: () {
          if (_isSelectionMode) {
            if (_isLmbDraggingMessages) return;
            _toggleMessageSelection(message);
            return;
          }
          if (!isDesktop) {
            _showContextMenu(message, isMe, key, enableBlur: true);
          }
        },
        onLongPress: isDesktop
            ? null
            : () {
                _enterSelectionMode(message);
              },
        onSecondaryTapUp: (details) {
          final bool clickedOnBubble = MessageBubble.isGlobalPointInsideBubble(
            key.currentContext,
            details.globalPosition,
          );
          _showContextMenu(
            message,
            isMe,
            key,
            forceOpen: true,
            enableBlur: clickedOnBubble,
          );
        },
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          color: Colors.transparent,
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: messageWidget,
        ),
      ),
    );

    return ValueListenableBuilder<String?>(
      valueListenable: MessageContextMenuService().activeBlurMessageId,
      builder: (context, activeBlurId, child) {
        final isSeparatedForBlur = activeBlurId != null &&
            (activeBlurId == message.id ||
                (hasLocalId && activeBlurId == message.localId));
        return Visibility(
          visible: !isSeparatedForBlur,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: child!,
        );
      },
      child: messageWidget,
    );
  }

  void _confirmDeleteMessage(Message message) {
    final deletedIndex = _messages.indexWhere((m) => m.id == message.id);
    ChatActionsHelper.confirmAndDeleteMessage(
      context: context,
      chatId: widget.channelId,
      message: message,
      onOptimisticDelete: () {
        if (mounted) {
          setState(() {
            _messages.removeWhere((m) => m.id == message.id);
          });
        }
      },
      onRollback: () {
        if (mounted) {
          setState(() {
            if (deletedIndex >= 0 && deletedIndex <= _messages.length) {
              _messages.insert(deletedIndex, message);
            } else {
              _messages.add(message);
              _messages.sort((a, b) {
                try {
                  final ta = DateTime.parse(a.createdAt);
                  final tb = DateTime.parse(b.createdAt);
                  final cmp = tb.compareTo(ta);
                  if (cmp != 0) return cmp;
                  return (int.tryParse(b.id) ?? 0).compareTo(int.tryParse(a.id) ?? 0);
                } catch (_) {
                  return 0;
                }
              });
            }
          });
        }
      },
    );
  }

  void _showContextMenu(
    Message message,
    bool isMe,
    GlobalKey key, {
    bool forceOpen = false,
    bool enableBlur = true,
    Offset? initialDragStartGlobalPosition,
    Offset? initialDragCurrentGlobalPosition,
  }) {
    _dismissKeyboardAndEmoji();
    final bool isVideoNote = message.isRound || (message.messageType == 'video' && message.isRound);
    final bool isVoiceNote = message.messageType == 'voice';
    final bool isPoll = message.messageType == 'poll';

    MessageContextMenuService().show(
      context: context,
      message: message,
      messageKey: key,
      isMe: isMe,
      enableBlur: enableBlur,
      initialDragStartGlobalPosition: initialDragStartGlobalPosition,
      initialDragCurrentGlobalPosition: initialDragCurrentGlobalPosition,
      currentUserId: _currentUserId,
      canManagePoll: isMe || _isAdmin,
      onPollUpdated: (updatedPoll) {
        if (!mounted) return;
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == message.id);
          if (idx != -1) {
            _messages[idx] = _messages[idx].copyWith(mediaPayload: updatedPoll);
          }
        });
      },
      onReply: () => _startReply(message),
      onQuote: (!isVideoNote && !isVoiceNote && !isPoll) ? () => _startQuote(message, message.content, 0, message.content.length) : null,
      onQuotePartial: (!isVideoNote && !isVoiceNote && !isPoll)
          ? (selectedText, offset, length) =>
              _startQuote(message, selectedText, offset, length)
          : null,
      onSelect: () => _enterSelectionMode(message),
      onPin: () {},
      onEdit: (_isAdmin && !isVideoNote && !isVoiceNote && !isPoll)
          ? () {
              setState(() {
                _replyToMessage = null;
                _isQuote = false;
                _quoteText = null;
                _quoteOffset = 0;
                _quoteLength = 0;
                _isEditing = true;
                _editingMessageId = message.id;
                _messageController.loadMessage(message.content, message.entities);
                _messageController.selection = TextSelection.fromPosition(
                  TextPosition(offset: _messageController.text.length),
                );
              });
              _focusInputField();
            }
          : null,
      onDelete: (msg) => _confirmDeleteMessage(msg),
      onReaction: (msgId, emoji) {},
    );
  }

  void _enterSelectionMode(Message message) {
    _dismissKeyboardAndEmoji();
    HapticUtils.selection();
    setState(() {
      _selectedMessageIds.add(message.id);
    });
  }

  void _toggleMessageSelection(Message message) {
    HapticUtils.selection();
    setState(() {
      if (_selectedMessageIds.contains(message.id)) {
        _selectedMessageIds.remove(message.id);
      } else {
        _selectedMessageIds.add(message.id);
      }
    });
  }

  void _clearSelection() {
    if (_selectedMessageIds.isEmpty) return;
    setState(() {
      _selectedMessageIds.clear();
      _dragSelectStartIndex = null;
      _dragSelectBaselineIds.clear();
      _isLmbDraggingMessages = false;
    });
  }

  List<Message> _getOrderedSelectedMessages() {
    final selected = _messages
        .where((m) => _selectedMessageIds.contains(m.id))
        .toList();
    selected.sort((a, b) {
      final ta = DateTime.tryParse(a.createdAt);
      final tb = DateTime.tryParse(b.createdAt);
      if (ta != null && tb != null) {
        final cmp = ta.compareTo(tb);
        if (cmp != 0) return cmp;
      }
      return (int.tryParse(a.id) ?? 0).compareTo(int.tryParse(b.id) ?? 0);
    });
    return selected;
  }

  void _copySelectedMessages() {
    final selected = _getOrderedSelectedMessages();
    if (selected.isEmpty) return;
    final text = selected
        .map((m) => m.content.trim())
        .where((s) => s.isNotEmpty)
        .join('\n\n');
    if (text.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: text));
      GlassToastService().show(
        context,
        context.l10n.translate('copied_to_clipboard'),
        icon: Icons.check,
      );
    }
    _clearSelection();
  }

  void _forwardSelectedMessages() {
    if (_selectedMessageIds.isEmpty) return;
    GlassToastService().show(
      context,
      'Пересылка скоро появится',
      icon: Icons.forward,
    );
    _clearSelection();
  }

  void _deleteSelectedMessages() {
    final selected = _getOrderedSelectedMessages();
    if (selected.isEmpty) return;
    _clearSelection();
    for (final msg in selected) {
      _confirmDeleteMessage(msg);
    }
  }

  void _handleMessagePointerDown({
    required PointerDownEvent event,
    required int feedIndex,
    required Message message,
    required GlobalKey key,
    required bool isMe,
  }) {
    final insideBubble = MessageBubble.isGlobalPointInsideBubble(
      key.currentContext,
      event.position,
    );
    if (event.kind != PointerDeviceKind.mouse) {
      _touchDownInsideBubble = insideBubble;
      return;
    }
    if ((event.buttons & kPrimaryMouseButton) == 0) {
      return;
    }
    _lmbDownGlobalPos = event.position;
    _lmbDownFeedIndex = feedIndex;
    _lmbDownMessage = message;
    _lmbDownKey = key;
    _lmbDownIsMe = isMe;
    _lmbDownInsideBubble = insideBubble;
    _lmbDownInsideText = _lmbDownInsideBubble &&
        !_isSelectionMode &&
        message.content.trim().isNotEmpty &&
        message.messageType != 'voice' &&
        message.messageType != 'poll' &&
        !message.isRound &&
        MessageBubble.isGlobalPointInsideSelectableText(
          key.currentContext,
          event.position,
        );
    _isLmbDraggingMessages = false;
    _isLmbDirectTextSelecting = false;
  }

  void _handleChatPointerDown(PointerDownEvent event) {
    if (event.kind != PointerDeviceKind.mouse) {
      _touchDownPos = event.position;
      _lastTouchPos = event.position;
      _lastTouchTime = event.timeStamp;
      _touchVelocityY = 0.0;
      _dismissedOnCurrentTouch = false;
    } else {
      _touchDownInsideBubble = false;
    }
  }

  void _handleChatPointerMove(PointerMoveEvent event) {
    if (event.kind != PointerDeviceKind.mouse) {
      if (_isMobilePlatform &&
          !_dismissedOnCurrentTouch &&
          _lastTouchPos != null &&
          _lastTouchTime != null &&
          _touchDownPos != null) {
        final dtMicros = (event.timeStamp - _lastTouchTime!).inMicroseconds;
        final dy = (event.position.dy - _lastTouchPos!.dy).abs();
        final totalDy = (event.position.dy - _touchDownPos!.dy).abs();
        final totalDx = (event.position.dx - _touchDownPos!.dx).abs();
        if (dtMicros > 0) {
          final instantVy = (dy * 1000000.0) / dtMicros;
          _touchVelocityY = _touchVelocityY * 0.35 + instantVy * 0.65;
          // Fast vertical scroll on mobile dismisses keyboard & emoji panel
          if (_touchVelocityY > 1250.0 && totalDy > 42.0 && totalDy > totalDx * 1.8) {
            final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
            if (isKeyboardOpen || _showEmojiPanel || _inputFocusNode.hasFocus) {
              _dismissedOnCurrentTouch = true;
              _dismissKeyboardAndEmoji();
            }
          }
        }
      }
      _lastTouchPos = event.position;
      _lastTouchTime = event.timeStamp;
      return;
    }
    if ((event.buttons & kPrimaryMouseButton) == 0) {
      return;
    }
    final downPos = _lmbDownGlobalPos;
    if (downPos == null) return;

    final distance = (event.position - downPos).distance;
    if (distance < 5.0 &&
        !_isLmbDraggingMessages &&
        !_isLmbDirectTextSelecting) {
      return;
    }

    if (_isLmbDirectTextSelecting) {
      MessageContextMenuService().updateExternalDragSelection(event.position);
      return;
    }

    if (!_isLmbDraggingMessages &&
        !_isSelectionMode &&
        _lmbDownInsideText &&
        _lmbDownMessage != null &&
        _lmbDownKey != null) {
      _isLmbDirectTextSelecting = true;
      _showContextMenu(
        _lmbDownMessage!,
        _lmbDownIsMe,
        _lmbDownKey!,
        forceOpen: true,
        enableBlur: true,
        initialDragStartGlobalPosition: downPos,
        initialDragCurrentGlobalPosition: event.position,
      );
      return;
    }

    if (!_isLmbDraggingMessages) {
      if (!_isSelectionMode && _lmbDownInsideBubble) {
        return;
      }
      final startIdx = _lmbDownFeedIndex;
      final startMsg = _lmbDownMessage;
      if (startIdx == null || startMsg == null) return;
      _isLmbDraggingMessages = true;
      _dragSelectStartIndex = startIdx;
      _dragSelectBaselineIds = Set<String>.from(_selectedMessageIds);
      _dragSelectTargetState = !_dragSelectBaselineIds.contains(startMsg.id);
      _applyDragSelectionUpTo(startIdx);
    }

    final hoveredIdx = _findFeedIndexAtGlobalY(event.position.dy);
    if (hoveredIdx != null) {
      _applyDragSelectionUpTo(hoveredIdx);
    }
  }

  void _handleChatPointerUp(PointerUpEvent event) {
    if (event.kind != PointerDeviceKind.mouse) {
      final downPos = _touchDownPos;
      if (downPos != null &&
          !_dismissedOnCurrentTouch &&
          !_touchDownInsideBubble &&
          !_isSelectionMode) {
        final dist = (event.position - downPos).distance;
        if (dist < 12.0) {
          final isKeyboardOpen = MediaQuery.of(context).viewInsets.bottom > 0;
          if (isKeyboardOpen || _showEmojiPanel || _inputFocusNode.hasFocus) {
            _dismissKeyboardAndEmoji();
          }
        }
      }
      _touchDownPos = null;
      _lastTouchPos = null;
      _lastTouchTime = null;
      _touchVelocityY = 0.0;
      _touchDownInsideBubble = false;
      _dismissedOnCurrentTouch = false;
      return;
    }
    if (_isLmbDirectTextSelecting) {
      MessageContextMenuService().endExternalDragSelection();
    } else if (!_isLmbDraggingMessages &&
        !_isSelectionMode &&
        _showEmojiPanel &&
        _lmbDownGlobalPos != null &&
        (event.position - _lmbDownGlobalPos!).distance < 6.0) {
      _closeEmojiPanel();
    }
    _resetLmbDragState();
  }

  void _handleChatPointerCancel(PointerCancelEvent event) {
    _touchDownPos = null;
    _lastTouchPos = null;
    _lastTouchTime = null;
    _touchVelocityY = 0.0;
    _touchDownInsideBubble = false;
    _dismissedOnCurrentTouch = false;
    if (_isLmbDirectTextSelecting) {
      MessageContextMenuService().endExternalDragSelection();
    }
    _resetLmbDragState();
  }

  void _resetLmbDragState() {
    _lmbDownGlobalPos = null;
    _lmbDownFeedIndex = null;
    _lmbDownMessage = null;
    _lmbDownKey = null;
    _lmbDownInsideBubble = false;
    _lmbDownInsideText = false;
    _dragSelectStartIndex = null;
    _dragSelectBaselineIds.clear();
    _isLmbDirectTextSelecting = false;
    Future.microtask(() {
      _isLmbDraggingMessages = false;
    });
  }

  int? _findFeedIndexAtGlobalY(double globalY) {
    for (int i = 0; i < _messages.length; i++) {
      final msg = _messages[i];
      final key = _messageKeys[msg.id] ??
          (msg.localId != null ? _messageKeys[msg.localId!] : null);
      final ctx = key?.currentContext;
      if (ctx == null) continue;
      final box = ctx.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize || !box.attached) continue;
      final topLeft = box.localToGlobal(Offset.zero);
      final bottom = topLeft.dy + box.size.height;
      if (globalY >= topLeft.dy && globalY <= bottom) {
        return i;
      }
    }
    return null;
  }

  void _applyDragSelectionUpTo(int currentIndex) {
    final startIdx = _dragSelectStartIndex;
    if (startIdx == null) return;
    final int low = math.min(startIdx, currentIndex);
    final int high = math.max(startIdx, currentIndex);
    final nextIds = Set<String>.from(_dragSelectBaselineIds);
    for (int i = low; i <= high; i++) {
      if (i < 0 || i >= _messages.length) continue;
      final id = _messages[i].id;
      if (_dragSelectTargetState) {
        nextIds.add(id);
      } else {
        nextIds.remove(id);
      }
    }
    if (nextIds.length != _selectedMessageIds.length ||
        !nextIds.containsAll(_selectedMessageIds)) {
      HapticUtils.selection();
      setState(() {
        _selectedMessageIds
          ..clear()
          ..addAll(nextIds);
      });
    }
  }

  Widget _buildMessageInput() {
    return ChatInputBar(
      controller: _messageController,
      focusNode: _inputFocusNode,
      hintText: AppLocalizations.of(context)?.translate('channel_write_post') ??
          'Write a post...',
      isUploading: _isUploading,
      uploadProgressNotifier: _uploadProgressNotifier,
      replyToMessage: _replyToMessage,
      isQuote: _isQuote,
      quoteText: _quoteText,
      quoteOffset: _quoteOffset,
      quoteLength: _quoteLength,
      onCancelReply: _cancelReply,
      onTapReply: _replyToMessage != null ? () => _scrollToMessage(_replyToMessage!.id) : null,
      isEditing: _isEditing,
      onCancelEditing: _cancelEditing,
      onEditLastMessage: _editLastOwnMessage,
      isEmojiPanelOpen: _showEmojiPanel && !_isKeyboardRising,
      onTapInputWhenEmojiOpen: _onEmojiToggle,
      onEmoji: _onEmojiToggle,
      onSend: _sendMessage,
      onSendDetailed: (cleanText, entities, linkPreviewOptions, invertMedia) {
        _sendMessage(
          cleanText: cleanText,
          entities: entities,
          linkPreviewOptions: linkPreviewOptions,
          invertMedia: invertMedia,
        );
      },
      onStartVideoRecord: _onStartVideoRecord,
      onVideoRecordMove: _onVideoRecordMove,
      onVideoRecordEnd: _onVideoRecordEnd,
      onVideoRecordCancel: _onVideoRecordCancel,
      onStartVoiceRecord: _onStartVoiceRecord,
      onVoiceRecordMove: _onVoiceRecordMove,
      onVoiceRecordEnd: _onVoiceRecordEnd,
      onVoiceRecordCancel: _onVoiceRecordCancel,
      currentUserId: _currentUserId,
      isSending: _isSending,
    );
  }

  Future<void> _onStartVideoRecord() async {
    _isVideoPointerDown = true;
    _dismissKeyboardAndEmoji();
    final hasPerms = await _videoRecorderService.hasPermissions();
    if (!hasPerms) {
      _isVideoPointerDown = false;
      final permanentlyDenied =
          await _videoRecorderService.isPermanentlyDenied();
      if (permanentlyDenied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.translate('chat_video_note_permission_denied'),
              ),
              action: SnackBarAction(
                label: context.l10n.translate('settings_title'),
                onPressed: () => openAppSettings(),
              ),
            ),
          );
        }
        return;
      }

      final granted = await _videoRecorderService.requestPermissions();
      if (!granted) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.translate('chat_video_note_permission_denied'),
              ),
              action: SnackBarAction(
                label: context.l10n.translate('settings_title'),
                onPressed: () => openAppSettings(),
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
              context.l10n.translate('chat_video_note_hold_hint'),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    if (!_isVideoPointerDown) return;

    HapticFeedback.heavyImpact();
    setState(() => _isVideoRecording = true);
    final ok = await _videoRecorderService.startRecording();
    if (!_isVideoPointerDown && ok) {
      await _videoRecorderService.cancelRecording();
      if (mounted) {
        _onVideoRecordingTooShort();
      }
      return;
    }
    if (!ok && mounted) {
      setState(() => _isVideoRecording = false);
      final isPermDenied =
          _videoRecorderService.errorMessage == 'permission_denied';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isPermDenied
                ? context.l10n.translate('chat_video_note_permission_denied')
                : (_videoRecorderService.errorMessage ??
                    context.l10n
                        .translate('chat_video_note_permission_denied')),
          ),
          action: isPermDenied
              ? SnackBarAction(
                  label: context.l10n.translate('settings_title'),
                  onPressed: () => openAppSettings(),
                )
              : null,
        ),
      );
    }
  }

  void _onVideoRecordMove(Offset offset) {
    if (!_isVideoRecording) return;
    final state = _videoOverlayKey.currentState as dynamic;
    state?.updatePointerOffset(offset.dx, offset.dy);
  }

  void _onVideoRecordEnd() {
    _isVideoPointerDown = false;
    if (!_isVideoRecording) return;
    final state = _videoOverlayKey.currentState as dynamic;
    state?.handlePointerUp();
  }

  void _onVideoRecordCancel() {
    _isVideoPointerDown = false;
    if (!_isVideoRecording) return;
    final state = _videoOverlayKey.currentState as dynamic;
    if (state?.isLocked == true) return;
    _videoRecorderService.cancelRecording();
    setState(() => _isVideoRecording = false);
  }

  void _onVideoRecordingCancelled() {
    setState(() => _isVideoRecording = false);
  }

  void _onVideoRecordingTooShort() {
    setState(() => _isVideoRecording = false);
    HapticFeedback.selectionClick();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          context.l10n.translate('chat_video_note_too_short'),
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<void> _onVideoRecordingSend(File file) async {
    setState(() => _isVideoRecording = false);
    await _sendRoundVideoMessage(file);
  }

  Future<void> _onStartVoiceRecord() async {
    _isVoicePointerDown = true;
    _dismissKeyboardAndEmoji();
    final hasPerm = await _voiceRecorderService.hasPermission();
    if (!hasPerm) {
      _isVoicePointerDown = false;
      final isPermanentlyDenied =
          await _voiceRecorderService.isPermanentlyDenied();
      if (isPermanentlyDenied) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                context.l10n.translate('chat_voice_permission_denied'),
              ),
              action: SnackBarAction(
                label: context.l10n.translate('settings_title'),
                onPressed: () => openAppSettings(),
              ),
            ),
          );
        }
        return;
      }
      final granted = await _voiceRecorderService.requestPermissions();
      if (!granted) return;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.translate('chat_video_note_hold_hint'),
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    if (!_isVoicePointerDown) return;

    VoicePlaybackService().stopVoice();
    VideoNotePlaybackService().stopActivePlayback();

    final started = await _voiceRecorderService.startRecording();
    if (!_isVoicePointerDown) {
      if (started) {
        await _voiceRecorderService.cancelRecording();
      }
      if (mounted) {
        setState(() => _isVoiceRecording = false);
      }
      return;
    }
    if (started && mounted) {
      setState(() => _isVoiceRecording = true);
    }
  }

  void _onVoiceRecordMove(Offset offset) {
    if (!_isVoiceRecording) return;
    final state = _voiceOverlayKey.currentState as dynamic;
    state?.updatePointerOffset(offset.dx, offset.dy);
  }

  void _onVoiceRecordEnd() {
    _isVoicePointerDown = false;
    if (!_isVoiceRecording) return;
    final state = _voiceOverlayKey.currentState as dynamic;
    state?.handlePointerUp();
  }

  void _onVoiceRecordCancel() {
    _isVoicePointerDown = false;
    if (!_isVoiceRecording) return;
    final state = _voiceOverlayKey.currentState as dynamic;
    if (state?.isLocked == true) return;
    _voiceRecorderService.cancelRecording();
    setState(() => _isVoiceRecording = false);
  }

  Future<void> _sendVoiceMessage(VoiceRecordResult result) async {
    final file = result.file;
    final voiceLabel =
        AppLocalizations.of(context)?.translate('chat_voice_message') ??
            'Voice message';
    if (!kIsWeb && (!await file.exists() || await file.length() == 0)) {
      debugPrint('Voice file is empty or does not exist');
      return;
    }

    final replyTo = _replyToMessage;
    final replyIsQuote = _isQuote;
    final replyQuoteText = _quoteText;
    final replyQuoteOffset = _quoteOffset;
    final replyQuoteLength = _quoteLength;
    _cancelReply();

    final syncService = SyncService();
    String? pendingLocalId;
    DbMessage? pendingMsg;

    try {
      final fileName = kIsWeb
          ? 'voice_${DateTime.now().millisecondsSinceEpoch}.webm'
          : file.path.split(Platform.pathSeparator).last;
      try {
        pendingMsg = await syncService.createPendingMessage(
          chatId: widget.channelId,
          senderId: _currentUserId ?? '',
          content: voiceLabel,
          messageType: 'voice',
          fileUrl: file.path,
          fileName: fileName,
          replyToMessageId: replyTo?.id,
          isQuote: replyIsQuote,
          quoteText: replyQuoteText,
          quoteOffset: replyQuoteOffset,
          quoteLength: replyQuoteLength,
          replyToSenderId: replyTo?.senderId,
          replyToSenderName: replyTo?.senderName,
          replyToContent: replyTo?.content,
          replyToMessageType: replyTo?.messageType ?? 'text',
          waveform: result.waveform,
          duration: result.duration.inSeconds,
        );
      } catch (e) {
        debugPrint('SyncService createPendingMessage voice error in channel: $e');
      }

      if (pendingMsg != null) {
        pendingLocalId = pendingMsg.localId;
        final profileTheme = context.read<ProfileThemeProvider>();
        var message = Message.fromDbMessage(pendingMsg).copyWith(
          waveform: result.waveform,
          duration: result.duration.inSeconds,
        );
        if (replyTo != null) {
          final isReplyToMe = replyTo.senderId == _currentUserId;
          message = message.copyWith(
            replyInfo: ReplyInfo(
              messageId: replyTo.id,
              senderId: replyTo.senderId,
              senderName: replyTo.senderName,
              content: replyTo.content,
              messageType: replyTo.messageType,
              entities: replyTo.entities,
              nameColorPresetId: isReplyToMe
                  ? profileTheme.currentNameColorPreset.id
                  : (replyTo.senderNameColorId ?? 'name_red'),
              replyStripStyle: isReplyToMe
                  ? profileTheme.currentStripStyle.name
                  : (replyTo.senderReplyStripStyle ?? 'solid'),
            ),
          );
        }
        if (mounted) {
          setState(() {
            _messages.insert(0, message);
          });
          _scrollToBottom();
        }
      }

      setState(() => _isUploading = true);
      final uploadResult = await _fileService.uploadFile(
        file,
        onProgress: (progress) {
          if (mounted) _uploadProgressNotifier.value = progress;
        },
      );

      final effectiveDuration = uploadResult.duration > 0
          ? uploadResult.duration
          : result.duration.inSeconds;

      final sendResult = await ChatService.sendMessage(
        chatId: widget.channelId,
        content: voiceLabel,
        messageType: 'voice',
        localId: pendingLocalId,
        fileUrl: uploadResult.url,
        fileName: uploadResult.fileName,
        mediaPayload: uploadResult.toMediaPayload(),
        replyToMessageId: replyTo?.id,
        isQuote: replyIsQuote,
        quoteText: replyQuoteText,
        quoteOffset: replyQuoteOffset,
        quoteLength: replyQuoteLength,
        waveform: result.waveform,
        duration: effectiveDuration,
      );

      if (sendResult['success'] == true) {
        if (!kIsWeb) {
          await MediaCacheManager.instance
              .seedCacheFromFile(uploadResult.url, file);
        }
        final sentMessage = sendResult['message'];
        final serverId = sentMessage is Message ? sentMessage.id : null;
        if (serverId != null && serverId.isNotEmpty && pendingLocalId != null) {
          await syncService.confirmMessageSent(pendingLocalId, serverId,
              remoteFileUrl: uploadResult.url);
          if (mounted) {
            setState(() {
              final idx =
                  _messages.indexWhere((m) => m.localId == pendingLocalId);
              if (idx != -1) {
                if (sentMessage is Message) {
                  _messages[idx] = sentMessage.copyWith(
                    localId: pendingLocalId,
                    replyInfo: _messages[idx].replyInfo,
                    waveform: sentMessage.waveform ?? _messages[idx].waveform,
                    duration: sentMessage.duration ?? effectiveDuration,
                    fileUrl: uploadResult.url,
                  );
                } else {
                  _messages[idx] = _messages[idx].copyWith(
                    id: serverId,
                    sendStatus: 1,
                    duration: effectiveDuration,
                    fileUrl: uploadResult.url,
                  );
                }
              }
            });
          }
        }
      } else {
        if (pendingLocalId != null) {
          await syncService.markMessageFailed(pendingLocalId);
          if (mounted) {
            setState(() {
              final idx =
                  _messages.indexWhere((m) => m.localId == pendingLocalId);
              if (idx != -1) {
                _messages[idx] = _messages[idx].copyWith(sendStatus: 2);
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Voice message send error in channel: $e');
      if (pendingLocalId != null) {
        await syncService.markMessageFailed(pendingLocalId);
        if (mounted) {
          setState(() {
            final idx =
                _messages.indexWhere((m) => m.localId == pendingLocalId);
            if (idx != -1) {
              _messages[idx] = _messages[idx].copyWith(sendStatus: 2);
            }
          });
        }
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgressNotifier.value = 0.0;
        });
      }
    }
  }

  Future<void> _sendRoundVideoMessage(File file) async {
    final videoNoteLabel =
        AppLocalizations.of(context)?.translate('chat_video_note') ??
            'Video message';
    if (!kIsWeb && (!await file.exists() || await file.length() == 0)) {
      debugPrint('Video file is empty or does not exist');
      return;
    }

    final recordedDurationSec =
        math.max(1, _videoRecorderService.elapsed.inSeconds);
    final replyTo = _replyToMessage;
    final replyIsQuote = _isQuote;
    final replyQuoteText = _quoteText;
    final replyQuoteOffset = _quoteOffset;
    final replyQuoteLength = _quoteLength;
    _cancelReply();

    final syncService = SyncService();
    String? pendingLocalId;
    DbMessage? pendingMsg;

    try {
      final fileName = kIsWeb
          ? 'video_note_${DateTime.now().millisecondsSinceEpoch}.webm'
          : file.path.split(Platform.pathSeparator).last;
      try {
        pendingMsg = await syncService.createPendingMessage(
          chatId: widget.channelId,
          senderId: _currentUserId ?? '',
          content: videoNoteLabel,
          messageType: 'video',
          fileUrl: file.path,
          fileName: fileName,
          isRound: true,
          duration: recordedDurationSec,
          replyToMessageId: replyTo?.id,
          isQuote: replyIsQuote,
          quoteText: replyQuoteText,
          quoteOffset: replyQuoteOffset,
          quoteLength: replyQuoteLength,
          replyToSenderId: replyTo?.senderId,
          replyToSenderName: replyTo?.senderName,
          replyToContent: replyTo?.content,
          replyToMessageType: replyTo?.messageType ?? 'text',
        );
      } catch (e) {
        debugPrint('SyncService createPendingMessage video error in channel: $e');
      }

      if (pendingMsg != null) {
        pendingLocalId = pendingMsg.localId;
        final profileTheme = context.read<ProfileThemeProvider>();
        var message = Message.fromDbMessage(pendingMsg).copyWith(
          duration: recordedDurationSec,
        );
        if (replyTo != null) {
          final isReplyToMe = replyTo.senderId == _currentUserId;
          message = message.copyWith(
            replyInfo: ReplyInfo(
              messageId: replyTo.id,
              senderId: replyTo.senderId,
              senderName: replyTo.senderName,
              content: replyTo.content,
              messageType: replyTo.messageType,
              entities: replyTo.entities,
              nameColorPresetId: isReplyToMe
                  ? profileTheme.currentNameColorPreset.id
                  : (replyTo.senderNameColorId ?? 'name_red'),
              replyStripStyle: isReplyToMe
                  ? profileTheme.currentStripStyle.name
                  : (replyTo.senderReplyStripStyle ?? 'solid'),
            ),
          );
        }
        if (mounted) {
          setState(() {
            _messages.insert(0, message);
          });
          _scrollToBottom();
        }
      }

      setState(() => _isUploading = true);
      final uploadResult = await _fileService.uploadFileChunked(
        file,
        onProgress: (progress) {
          if (mounted) _uploadProgressNotifier.value = progress;
        },
      );

      final effectiveDuration = uploadResult.duration > 0
          ? uploadResult.duration
          : recordedDurationSec;

      final result = await ChatService.sendMessage(
        chatId: widget.channelId,
        content: videoNoteLabel,
        messageType: 'video',
        localId: pendingLocalId,
        fileUrl: uploadResult.url,
        fileName: uploadResult.fileName,
        mediaPayload: uploadResult.toMediaPayload(),
        isRound: true,
        duration: effectiveDuration,
        replyToMessageId: replyTo?.id,
        isQuote: replyIsQuote,
        quoteText: replyQuoteText,
        quoteOffset: replyQuoteOffset,
        quoteLength: replyQuoteLength,
      );

      if (result['success'] == true) {
        if (!kIsWeb) {
          await MediaCacheManager.instance
              .seedCacheFromFile(uploadResult.url, file);
        }
        final sentMessage = result['message'];
        final serverId = sentMessage is Message ? sentMessage.id : null;
        if (serverId != null && serverId.isNotEmpty && pendingLocalId != null) {
          await syncService.confirmMessageSent(pendingLocalId, serverId,
              remoteFileUrl: uploadResult.url);
          if (mounted) {
            setState(() {
              final idx =
                  _messages.indexWhere((m) => m.localId == pendingLocalId);
              if (idx != -1) {
                if (sentMessage is Message) {
                  _messages[idx] = sentMessage.copyWith(
                    localId: pendingLocalId,
                    replyInfo: _messages[idx].replyInfo,
                    sendStatus: 1,
                    isRound: true,
                    duration: sentMessage.duration ?? effectiveDuration,
                    fileUrl: uploadResult.url,
                  );
                } else {
                  _messages[idx] = _messages[idx].copyWith(
                    id: serverId,
                    sendStatus: 1,
                    isRound: true,
                    duration: effectiveDuration,
                    fileUrl: uploadResult.url,
                  );
                }
              }
            });
          }
        }
      } else {
        if (pendingLocalId != null) {
          await syncService.markMessageFailed(pendingLocalId);
          if (mounted) {
            setState(() {
              final idx =
                  _messages.indexWhere((m) => m.localId == pendingLocalId);
              if (idx != -1) {
                _messages[idx] = _messages[idx].copyWith(sendStatus: 2);
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error sending round video message in channel: $e');
      if (pendingLocalId != null) {
        await syncService.markMessageFailed(pendingLocalId);
        if (mounted) {
          setState(() {
            final idx =
                _messages.indexWhere((m) => m.localId == pendingLocalId);
            if (idx != -1) {
              _messages[idx] = _messages[idx].copyWith(sendStatus: 2);
            }
          });
        }
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n.translate('chat_upload_error'),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgressNotifier.value = 0.0;
        });
      }
    }
  }
}
