import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import '../../services/glass_toast_service.dart';
import '../../utils/haptic_utils.dart';
import '../../services/chat_service.dart';
import '../../services/draft_service.dart';
import '../../services/chat_actions_helper.dart';
import '../../services/auth_service.dart';
import '../../services/websocket_service.dart';
import '../../services/file_service.dart';
import '../../services/video_note_recorder_service.dart';
import '../../widgets/chat/round_video_recording_overlay.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/unread_count_provider.dart';
import '../../services/database/app_database.dart';
import '../../services/sync_service.dart';
import '../../services/chat_realtime_manager.dart';
import '../../services/emoji_interaction_manager.dart';
import '../../services/notification_service.dart';
import '../../services/profile_instant_cache.dart';
import '../../services/profile_theme_provider.dart';
import '../../services/message_context_menu_service.dart';
import '../../l10n/app_localizations.dart';
import '../../config/app_config.dart';
import 'package:drift/drift.dart' show Value;
import '../../utils/image_utils.dart';
import '../../services/video_note_playback_service.dart';
import '../../services/media_playback_coordinator.dart';
import '../../services/media_cache_manager.dart';
import '../../services/voice_note_recorder_service.dart';
import '../../services/voice_playback_service.dart';
import '../../widgets/chat/voice_recording_overlay.dart';
import '../../widgets/chat/media_note_player_header.dart';
import '../../widgets/chat/liquid_glass_input_field.dart';
import '../../widgets/chat/floating_glass_app_bar.dart';
import '../../widgets/chat/chat_scaffold.dart';
import '../../widgets/chat/chat_input_bar.dart';
import '../../widgets/chat/chat_messages_list_view.dart';
import '../../widgets/chat/visible_message_detector.dart';
import '../../widgets/chat/swipe_to_reply_wrapper.dart';
import '../../widgets/chat/unread_separator.dart';
import '../../widgets/chat/chat_history_calendar.dart';
import '../../widgets/chat/chat_scroll_navigator.dart';
import '../../widgets/message/message_bubble.dart';
import '../../models/media_album.dart';
import '../../widgets/message/media_album_widget.dart';
import '../../widgets/message/fullscreen_photo_viewer.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:uuid/uuid.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:share_plus/share_plus.dart';
import '../../utils/swipe_back_route.dart';
import '../../utils/entity_parser.dart';
import 'private_chat_screen.dart';
import 'channel_screen.dart';
import '../../utils/date_time_utils.dart';
import 'group_info_screen.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/chat/attachment_picker_bottom_sheet.dart';
import '../../widgets/chat/emoji_sticker_panel.dart';
import 'media_send_screen.dart';
import 'poll_create_screen.dart';
import '../../services/tiling_layout_controller.dart';
import '../../services/proximity_audio_service.dart';
import '../../widgets/tiling/tile_viewport_scope.dart';

class GroupChatScreen extends StatefulWidget {
  static const String routeName = '/group_chat';

  final String chatId;
  final String? groupName;
  final String? groupAvatar;
  final String? initialMessageId;

  const GroupChatScreen({
    Key? key,
    required this.chatId,
    this.groupName,
    this.groupAvatar,
    this.initialMessageId,
  }) : super(key: key);

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  late TabController _tabController;
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
  bool _isMuted = false;
  bool _isSending = false;
  String? _currentUserId;
  String _groupName = '';
  String? _groupAvatar;
  List<ChatParticipant> _participants = [];
  final ValueNotifier<bool> _showScrollDownFabNotifier = ValueNotifier<bool>(false);
  double _lastScrollOffset = 0;
  double _accumulatedScrollDown = 0;
  double _accumulatedScrollUp = 0;
  String? _highlightMessageId;
  final Map<String, GlobalKey> _messageKeys = {};
  final GlobalKey _inputKey = GlobalKey();
  double _inputHeight = 90.0;
  Timer? _highlightTimer;
  final List<String> _jumpHistory = [];
  bool _isProgrammaticJump = false;
  bool _isDetachedHistoryWindow = false;
  bool _hasMoreNewerMessages = false;
  bool _isLoadingNewer = false;
  List<Message> _detachedLatestBackup = [];
  bool _detachedBackupHasMoreOlder = true;
  final Map<String, Map<String, int>> _messageReactions = {}; // msgId → {emoji → count}
  final Map<String, Set<String>> _myReactions = {}; // msgId → Set<emoji>
  final Set<String> _pendingMarkRead = {};
  Timer? _markReadTimer;
  bool _isMarkingRead = false;

  // WebSocket
  final WebSocketService _wsService = WebSocketService();
  ChatSubscription? _chatSubscription;
  bool _isTyping = false;
  String _typingAction = 'typing';
  Timer? _typingTimer;
  Timer? _recordingActionTimer;
  String? _typingUserName;
  String? _typingUserId;

  // Reply / Quote state
  Message? _replyToMessage;
  bool _isQuote = false;
  String? _quoteText;
  int _quoteOffset = 0;
  int _quoteLength = 0;

  // Edit message state
  bool _isEditing = false;
  String? _editingMessageId;

  // Video Note («Кружочки») state
  final FileService _fileService = FileService();
  final VideoNoteRecorderService _videoRecorderService = VideoNoteRecorderService();
  final GlobalKey _videoOverlayKey = GlobalKey();
  bool _isVideoRecording = false;

  // Voice Note («Голосовые сообщения») state
  final VoiceNoteRecorderService _voiceRecorderService = VoiceNoteRecorderService();
  final GlobalKey _voiceOverlayKey = GlobalKey();
  bool _isVoiceRecording = false;

  // Feed items (messages grouped into albums by grouped_id)
  List<FeedItem> _feedItems = [];
  int _unreadCount = 0;
  String? _firstUnreadMessageId;
  bool _showUnreadDivider = false;
  int _firstUnreadFeedIndex = -1;
  final GlobalKey _unreadSeparatorKey = GlobalKey();
  bool _hasScrolledToUnread = false;
  double _newestMessageHeight = 150.0;

  // Sticky date header & inline date separator keys
  final Map<DateTime, GlobalKey> _dateSeparatorKeys = {};
  final GlobalKey _stickyDateSlotKey = GlobalKey();
  final ValueNotifier<StickyDateState> _stickyDateStateNotifier =
      ValueNotifier<StickyDateState>(StickyDateState.empty);
  List<({DateTime day, DateTime sampleDt, int newestIdx, int oldestIdx})>
      _daySpans = [];
  bool _stickyDatePostFrameScheduled = false;

  static final Map<String, (DateTime, DateTime)> _dateCache = {};

  (DateTime, DateTime) _resolveDates(String createdAt) {
    var cached = _dateCache[createdAt];
    if (cached != null) return cached;
    final dt = DateTimeUtils.parseUtcDateTime(createdAt) ?? DateTime.now();
    final startOfDay = DateTimeUtils.startOfDay(dt);
    cached = (dt, startOfDay);
    if (_dateCache.length > 500) _dateCache.clear();
    _dateCache[createdAt] = cached;
    return cached;
  }

  String _formatDateLabel(DateTime dt) =>
      DateTimeUtils.formatDateSeparator(dt, context: context);

  void _updateFeedItems() {
    _feedItems = groupMessagesIntoFeedItems(_messages, isReversed: true);
    if (_showUnreadDivider && _firstUnreadMessageId != null) {
      _firstUnreadFeedIndex = _feedItems.indexWhere((item) =>
          item.id == _firstUnreadMessageId ||
          (item is FeedAlbumItem &&
              item.album.items.any((ai) => ai.id == _firstUnreadMessageId)));
    } else {
      _firstUnreadFeedIndex = -1;
    }

    final spans =
        <({DateTime day, DateTime sampleDt, int newestIdx, int oldestIdx})>[];
    for (int i = 0; i < _feedItems.length; i++) {
      final (dt, day) = _resolveDates(_feedItems[i].createdAt);
      _dateSeparatorKeys.putIfAbsent(day, () => GlobalKey());
      if (spans.isEmpty || spans.last.day != day) {
        spans.add((day: day, sampleDt: dt, newestIdx: i, oldestIdx: i));
      } else {
        final prev = spans.removeLast();
        spans.add((
          day: prev.day,
          sampleDt: prev.sampleDt,
          newestIdx: prev.newestIdx,
          oldestIdx: i,
        ));
      }
    }
    _daySpans = spans;

    _pruneMessageKeys();
    _scheduleStickyDateUpdate();
  }

  void _pruneMessageKeys() {
    if (_messageKeys.length > _messages.length * 2 + 200) {
      final activeIds = <String>{
        for (final m in _messages) m.id,
        for (final m in _messages)
          if (m.localId != null && m.localId!.isNotEmpty) m.localId!,
      };
      _messageKeys.removeWhere((id, _) => !activeIds.contains(id));
    }
  }

  // Attachments state
  final ImagePicker _imagePicker = ImagePicker();
  final List<File> _attachedFiles = [];
  final List<String> _attachedFileNames = [];
  bool _isUploading = false;
  final ValueNotifier<double> _uploadProgressNotifier = ValueNotifier<double>(0.0);
  double get _uploadProgress => _uploadProgressNotifier.value;

  bool _isVideoFile(String path) {
    final ext = path.toLowerCase();
    return ext.endsWith('.mp4') ||
        ext.endsWith('.mov') ||
        ext.endsWith('.avi') ||
        ext.endsWith('.mkv') ||
        ext.endsWith('.webm');
  }

  bool _isImageFile(String path) {
    final ext = path.toLowerCase();
    return ext.endsWith('.jpg') ||
        ext.endsWith('.jpeg') ||
        ext.endsWith('.png') ||
        ext.endsWith('.webp') ||
        ext.endsWith('.heic') ||
        ext.endsWith('.gif') ||
        ext.endsWith('.bmp');
  }

  bool _isMediaFile(String path) => _isImageFile(path) || _isVideoFile(path);

  void _removeAttachedFile(int index) {
    if (index >= 0 && index < _attachedFiles.length) {
      setState(() {
        _attachedFiles.removeAt(index);
        _attachedFileNames.removeAt(index);
      });
    }
  }

  void _clearAttachedFiles() {
    setState(() {
      _attachedFiles.clear();
      _attachedFileNames.clear();
      _isUploading = false;
    });
    _uploadProgressNotifier.value = 0.0;
  }

  void _cancelEditing() {
    _stopMyTyping();
    setState(() {
      _isEditing = false;
      _editingMessageId = null;
      _messageController.clear();
    });
  }

  UnreadCountProvider? _unreadCountProvider;
  String? _registeredTileId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    WidgetsBinding.instance.addObserver(this);
    ProfileInstantCache.instance.prefetchGroupOrChannel(widget.chatId);

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
    final draft = DraftService().getDraft(widget.chatId);
    if (draft != null && draft.isNotEmpty) {
      _messageController.text = draft.text;
      if (draft.quoteText != null && draft.quoteText!.isNotEmpty) {
        _isQuote = draft.isQuote;
        _quoteText = draft.quoteText;
      }
    }

    // Connect continuous media playback with coordinator
    MediaPlaybackCoordinator.instance.registerChat(
      widget.chatId,
      ChatPlaybackCallbacks(
        onScrollToMessage: (id) => _scrollToMessage(id),
        onPlayNext: _playNextMediaNote,
        onBuildPlaylist: (id) => _buildPlaylistFrom(id),
        onMessageListenedLocally: _onLocalMessageListened,
      ),
    );
    ProximityAudioService.instance.registerOpenChat(
      widget.chatId,
      onRaiseToListenFirstUnplayed: _onRaiseToListenFirstUnplayed,
    );
    NotificationService().addActiveChat(widget.chatId);

    _scrollController.addListener(() {
      if (!_scrollController.hasClients || _messages.isEmpty) return;

      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.offset;

      if (!_isProgrammaticJump) {
        // Пагинация вверх: загрузить старые сообщения
        if (_hasMoreMessages && !_isLoadingMore) {
          if (maxScroll > 0 &&
              (currentScroll >= maxScroll * 0.75 ||
                  (maxScroll - currentScroll) < 600)) {
            _loadMoreMessages();
          }
        }

        // Пагинация вниз в режиме «Окна истории»: загрузить более новые сообщения
        if (_isDetachedHistoryWindow &&
            _hasMoreNewerMessages &&
            !_isLoadingNewer &&
            currentScroll < 500) {
          _loadNewerMessages();
        }
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
      
      // Clear jump history only when near the real bottom of the chat
      if (!_isDetachedHistoryWindow && offset < 100 && _jumpHistory.isNotEmpty) {
        _jumpHistory.clear();
      }

      // Dynamic threshold: cached height of newest message
      if (!_isDetachedHistoryWindow && offset < 50 && _messages.isNotEmpty) {
        final firstMsgId = _messages.first.id;
        final key = _messageKeys[firstMsgId];
        final renderBox = key?.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null && renderBox.hasSize && renderBox.size.height > 20.0) {
          _newestMessageHeight = renderBox.size.height;
        }
        if (_unreadCount > 0) {
          _onMessageVisible(firstMsgId);
        }
      }
      final double threshold = _newestMessageHeight;
      
      final bool currentFabVisible = _showScrollDownFabNotifier.value;
      bool shouldShow = currentFabVisible;
      if (_isDetachedHistoryWindow || _jumpHistory.isNotEmpty) {
        shouldShow = true;
      } else if (offset <= threshold) {
        shouldShow = false;
      } else if (delta < 0 && _accumulatedScrollDown >= 80.0 && isScrollingDown) {
        shouldShow = true;
      } else if (delta > 0 && _accumulatedScrollUp >= 120.0) {
        shouldShow = false;
      }
      
      if (shouldShow != currentFabVisible) {
        _showScrollDownFabNotifier.value = shouldShow;
        if (shouldShow) {
          _accumulatedScrollDown = 0;
        } else {
          _accumulatedScrollUp = 0;
        }
      }

      _updateFloatingDateOnScroll();
      _scheduleStickyDateUpdate();
    });

    // Notify provider that this chat is open (so unread count is not incremented)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _unreadCountProvider = context.read<UnreadCountProvider>();
        _unreadCountProvider?.openChat(widget.chatId);
      } catch (_) {}
      NotificationService().cancelChatNotifications(widget.chatId, chatTitle: widget.groupName);
      if (_isDesktopPlatform && _isMyTileActive()) {
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
    if (!mounted || !_isDesktopPlatform) return;
    final currentActive = TilingLayoutController.instance.activeTileId;
    if (currentActive != _lastActiveTileId) {
      _lastActiveTileId = currentActive;
      final myTileId = _registeredTileId ?? TileViewportScope.maybeTileIdOf(context);
      if (myTileId != null && currentActive == myTileId) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_isSelectionMode && _tabController.index == 0) {
            _inputFocusNode.requestFocus();
          }
        });
      }
    }
  }

  bool _handleGlobalDesktopKeyEvent(KeyEvent event) {
    if (!mounted || !_isDesktopPlatform) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (_tabController.index != 0) return false;
    if (_inputFocusNode.hasFocus) return false;
    if (!_isMyTileActive()) return false;
    if (_isSelectionMode || _isVoiceRecording || _isVideoRecording) return false;
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

    // Handle Ctrl+V paste into input field
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
        _onInputTextChanged(newText);
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
      _onInputTextChanged(newText);
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
      DraftService().flushDraft(widget.chatId);
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
    if (_currentUserId == null) return;
    for (final msg in _messages) {
      if (msg.senderId == _currentUserId &&
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
      _onInputTextChanged(newText);
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
    _onInputTextChanged(newText);
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

  // Multi-message selection & desktop LMB drag state
  final Set<String> _selectedMessageIds = {};
  bool get _isSelectionMode => _selectedMessageIds.isNotEmpty;
  int? _dragSelectStartIndex;
  bool _dragSelectTargetState = true;
  Set<String> _dragSelectBaselineIds = {};
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
  Duration? _touchDownTime;
  Offset? _lastTouchPos;
  Duration? _lastTouchTime;
  double _touchVelocityY = 0.0;
  bool _dismissedOnCurrentTouch = false;
  bool _touchDownInsideBubble = false;

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
    if (_isVideoRecording) {
      _onVideoRecordingCancelled();
      return true;
    }
    if (_isVoiceRecording) {
      _voiceRecorderService.cancelRecording();
      setState(() => _isVoiceRecording = false);
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
      chatId: widget.chatId,
      onNewMessage: _onNewMessage,
      onMessageEdited: _onMessageEdited,
      onMessageDeleted: _onMessageDeleted,
      onReactionUpdated: _onMessageReactionUpdated,
      onMessageRead: _onMessageRead,
      onMessageListened: _onMessageListened,
      onTyping: _onTypingIndicator,
      onUserStatus: _onUserStatusUpdate,
      onUnreadCountUpdated: _onUnreadCountUpdated,
      onEmojiInteraction: _onEmojiInteraction,
      onUserAvatarUpdated: (event) {
        final userId = event.data['user_id']?.toString();
        final rawAvatarUrl = event.data['avatar_url']?.toString();
        if (userId == null || !mounted) return;
        final avatarUrl = (rawAvatarUrl != null && rawAvatarUrl.isNotEmpty)
            ? (getValidAvatarUrl(rawAvatarUrl) ?? rawAvatarUrl)
            : rawAvatarUrl;
        ProfileInstantCache.instance.updateUserAvatar(userId, avatarUrl);
        bool updatedAny = false;
        setState(() {
          for (int i = 0; i < _messages.length; i++) {
            if (_messages[i].senderId == userId) {
              _messages[i] = _messages[i].copyWith(senderAvatarUrl: avatarUrl);
              updatedAny = true;
            }
          }
        });
        if (updatedAny) {
          PaintingBinding.instance.imageCache.clear();
          PaintingBinding.instance.imageCache.clearLiveImages();
        }
      },
      onReconnect: _triggerSilentSync,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _onAppResumed();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _onAppPaused();
    }
  }

  void _onAppResumed() {
    if (!_wsService.isConnected) {
      _wsService.connect();
    }
    _triggerSilentSync();
  }

  void _onAppPaused() {
    _markReadTimer?.cancel();
    _flushMarkRead();
    _stopMyTyping();
    if (_isVideoRecording) {
      _onVideoRecordingCancelled();
    }
    if (_isVoiceRecording) {
      _voiceRecorderService.cancelRecording();
      setState(() => _isVoiceRecording = false);
    }
  }

  void _triggerSilentSync() {
    _syncDebounceTimer?.cancel();
    _syncDebounceTimer = Timer(const Duration(milliseconds: 400), () {
      if (mounted) {
        _syncLatestMessages();
      }
    });
  }

  /// Silently synchronizes latest messages from server without flashing a loading spinner
  /// or interrupting the user's scroll position.
  Future<void> _syncLatestMessages() async {
    if (_isSyncing || !mounted) return;
    _isSyncing = true;

    try {
      final result = await ChatService.getMessages(chatId: widget.chatId, limit: 50);
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
            final pendingMessages = _messages
                .where((m) => m.sendStatus != 1 && m.localId != null)
                .toList();

            final Map<String, Message> merged = {};
            for (final m in _messages) {
              merged[m.id] = m;
              if (m.localId != null && m.localId!.isNotEmpty) {
                merged[m.localId!] = m;
              }
            }
            for (final m in serverMessages) {
              merged[m.id] = m;
              if (m.localId != null && m.localId!.isNotEmpty) {
                merged[m.localId!] = m;
              }
            }
            for (final pending in pendingMessages) {
              final key = pending.localId ?? pending.id;
              if (!merged.containsKey(key)) {
                merged[key] = pending;
              }
            }

            _messages.clear();
            final Map<String, Message> dedupedById = {};
            for (final m in merged.values) {
              dedupedById[m.id] = m;
            }
            _messages.addAll(dedupedById.values);

            for (final m in _messages) {
              if (m.reactions.isNotEmpty) {
                _messageReactions[m.id] = Map.from(m.reactions);
              }
              if (m.myReactions.isNotEmpty) {
                _myReactions[m.id] = Set.from(m.myReactions);
              }
            }

            _sortMessagesDescending(_messages);
            _updateFeedItems();
          });
        }

        try {
          db.saveMessages(serverMessages.map((m) => _messageToCompanion(m)).toList());
        } catch (e) {
          debugPrint('Drift saveMessages in group sync error: $e');
        }

        try {
          final unreadInfo = await ChatService.getUnreadInfo(chatId: widget.chatId);
          if (unreadInfo['success'] == true && mounted) {
            final serverUnreadCount = unreadInfo['unread_count'] as int? ?? 0;
            setState(() {
              _unreadCount = serverUnreadCount;
            });
            try {
              context.read<UnreadCountProvider>().setCount(widget.chatId, serverUnreadCount);
            } catch (_) {}
          }
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('GroupChatScreen: _syncLatestMessages error: $e');
    } finally {
      _isSyncing = false;
    }
  }


  void _onMessageReactionUpdated(WebSocketEvent event) {
    final messageId = event.data['message_id']?.toString();
    if (messageId == null) return;

    final userId = event.data['user_id']?.toString();
    final emoji = event.data['emoji']?.toString();
    final action = event.data['action']?.toString(); // "added" or "removed"
    final bool? active =
        event.data['active'] is bool ? event.data['active'] as bool : null;
    final bool isAdded = action == 'added' || active == true;
    final bool isRemoved = action == 'removed' || active == false;

    final Map<String, int> reactionsMap = {};
    if (event.data['reactions'] is List) {
      for (final r in event.data['reactions']) {
        if (r is Map && r['emoji'] != null && r['count'] != null) {
          final cnt = (r['count'] as num).toInt();
          if (cnt > 0) {
            reactionsMap[r['emoji'].toString()] = cnt;
          }
        }
      }
    }

    if (mounted) {
      setState(() {
        _messageReactions[messageId] = reactionsMap;

        if (userId != null && userId == _currentUserId && emoji != null) {
          final mySet = _myReactions.putIfAbsent(messageId, () => <String>{});
          if (isAdded) {
            mySet.add(emoji);
          } else if (isRemoved) {
            mySet.remove(emoji);
          }
          if (mySet.isEmpty) {
            _myReactions.remove(messageId);
          }
        }

        final idx = _messages.indexWhere((m) => m.id == messageId);
        if (idx != -1) {
          _messages[idx] = _messages[idx].copyWith(
            reactions: reactionsMap,
            myReactions: _myReactions[messageId] ?? _messages[idx].myReactions,
          );
          _updateFeedItems();
        }
      });

      try {
        AppDatabase().updateMessageReactions(
          messageId,
          reactionsMap,
          _myReactions[messageId] ?? {},
        );
      } catch (e) {
        debugPrint('GroupChatScreen: error updating reactions in DB: $e');
      }
    }
  }

  void _onMessageDeleted(WebSocketEvent event) {
    final messageId = event.data['message_id']?.toString();
    if (messageId == null) return;

    if (mounted) {
      setState(() {
        _messages.removeWhere((m) => m.id == messageId);
        _updateFeedItems();
      });
    }

    try {
      AppDatabase().deleteMessage(messageId);
    } catch (e) {
      debugPrint('GroupChatScreen: error deleting message from DB: $e');
    }
  }

  void _onUserStatusUpdate(WebSocketEvent event) {
    final userId = event.data['user_id']?.toString();
    final isOnline = event.data['is_online'] == true;
    if (userId == null) return;

    if (mounted) {
      setState(() {
        final idx = _participants.indexWhere((p) => p.id == userId);
        if (idx != -1) {
          _participants[idx] = _participants[idx].copyWith(isOnline: isOnline);
        }
      });
    }
  }

  void _onMessageEdited(WebSocketEvent event) {
    final messageId = event.data['message_id']?.toString();
    final newContent = event.data['content']?.toString();
    if (messageId == null) return;

    List<MessageEntity>? newEntities;
    if (event.data['entities'] != null) {
      try {
        final list = event.data['entities'] as List;
        newEntities = list
            .map((e) => MessageEntity.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

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
            entities: newEntities ?? current.entities,
            mediaPayload: newMediaPayload ?? current.mediaPayload,
            isEdited: isPollMsg ? current.isEdited : true,
          );
          _updateFeedItems();
        }
      });
    }

    try {
      AppDatabase().updateMessageContent(
        messageId,
        effectiveContent ?? '',
        newEntities != null && newEntities.isNotEmpty
            ? jsonEncode(newEntities.map((e) => e.toJson()).toList())
            : null,
        newMediaPayload != null ? jsonEncode(newMediaPayload) : null,
        !isPollEvent,
      );
    } catch (_) {}
  }

  void _onUnreadCountUpdated(WebSocketEvent event) {
    final newUnreadCount = event.data['unread_count'] as int? ?? 0;
    if (mounted) {
      setState(() {
        _unreadCount = newUnreadCount;
        // Keep _showUnreadDivider and _firstUnreadMessageId during the active chat session
        // (Telegram behavior: banner stays until user sends a message or leaves chat).
        _updateFeedItems();
      });
      try {
        _unreadCountProvider?.setCount(widget.chatId, newUnreadCount);
      } catch (_) {}
    }
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
            groupedId: message.groupedId ?? existing.groupedId,
            isQuote: message.isQuote || existing.isQuote,
            quoteText: message.quoteText ?? existing.quoteText,
            quoteOffset: message.quoteOffset != 0 ? message.quoteOffset : existing.quoteOffset,
            quoteLength: message.quoteLength != 0 ? message.quoteLength : existing.quoteLength,
          );
          _updateFeedItems();
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
      final bool isFromOther = message.senderId != _currentUserId;
      final bool isNearBottom = !_isDetachedHistoryWindow &&
          (!_scrollController.hasClients || _scrollController.offset <= 150.0);

      setState(() {
        if (_typingUserId == message.senderId || _isTyping) {
          _typingTimer?.cancel();
          _isTyping = false;
          _typingUserId = null;
          _typingUserName = null;
        }
        if (_isDetachedHistoryWindow) {
          if (!_detachedLatestBackup.any((m) => m.id == message.id)) {
            _detachedLatestBackup.insert(0, message);
          }
          if (isFromOther) {
            _unreadCount++;
          }
        } else {
          _messages.insert(0, message);
          if (isFromOther && !isNearBottom) {
            _unreadCount++;
          }
          _updateFeedItems();
        }
      });
      if (isFromOther && isNearBottom) {
        _onMessageVisible(message.id);
      }
    }
  }

  void _onTypingIndicator(WebSocketEvent event) {
    final chatId = event.data['chat_id']?.toString();
    if (chatId != widget.chatId) return;

    final typingUserId = event.data['user_id']?.toString();
    if (typingUserId == _currentUserId) return;

    final action = event.data['action']?.toString() ?? 'typing';
    final bool isTyping = event.data['is_typing'] != false && action != 'stop';
    if (!isTyping) {
      if (mounted && _typingUserId == typingUserId) {
        _typingTimer?.cancel();
        setState(() {
          _isTyping = false;
          _typingAction = 'typing';
          _typingUserId = null;
          _typingUserName = null;
        });
      }
      return;
    }

    // Get typing user name from event or participants
    final eventUserName = event.data['user_name']?.toString();
    String name = eventUserName ?? '';
    if (name.isEmpty) {
      final typingUser = _participants.firstWhere(
        (p) => p.id == typingUserId,
        orElse: () => ChatParticipant(
            id: '', username: '', displayName: 'Someone', role: 'member'),
      );
      name = typingUser.displayName.isNotEmpty
          ? typingUser.displayName
          : typingUser.username;
    }

    if (mounted) {
      setState(() {
        _typingUserId = typingUserId;
        _typingUserName = name;
        _isTyping = true;
        _typingAction = action;
      });

      // Clear typing indicator after 4 seconds (Telegram-like smooth window)
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() {
            _isTyping = false;
            _typingAction = 'typing';
            _typingUserId = null;
            _typingUserName = null;
          });
        }
      });
    }
  }

  void _onEmojiInteraction(WebSocketEvent event) {
    final chatId = event.data['chat_id']?.toString();
    if (chatId != widget.chatId) return;

    final senderId = event.data['user_id']?.toString();
    if (senderId == _currentUserId) return;

    final action = event.data['action']?.toString() ?? 'tap';
    if (action != 'tap') return; // Group chats only trigger synchronized animations on direct tap

    final messageId = event.data['message_id']?.toString() ?? '';

    if (mounted) {
      // Play animation, haptics, and effect ONLY if this emoji is visible on screen
      EmojiInteractionManager.instance.trigger(messageId);
    }
  }

  Timer? _typingKeepAliveTimer;
  bool _amITyping = false;

  void _onInputTextChanged(String text) {
    if (!_isEditing) {
      DraftService().saveDraft(
        widget.chatId,
        text: text,
        replyToMessageId: _replyToMessage?.id,
        quoteText: _quoteText,
        isQuote: _isQuote,
      );
    }

    final bool hasText = text.trim().isNotEmpty;
    if (hasText) {
      if (!_amITyping) {
        _amITyping = true;
        _wsService.sendTypingIndicator(widget.chatId, isTyping: true);
      }
      _typingKeepAliveTimer ??= Timer.periodic(const Duration(milliseconds: 2000), (_) {
        if (_messageController.text.trim().isNotEmpty) {
          _wsService.sendTypingIndicator(widget.chatId, isTyping: true);
        } else {
          _stopMyTyping();
        }
      });
    } else {
      _stopMyTyping();
    }
  }

  void _stopMyTyping() {
    _typingKeepAliveTimer?.cancel();
    _typingKeepAliveTimer = null;
    if (_amITyping) {
      _amITyping = false;
      _wsService.sendTypingIndicator(widget.chatId, isTyping: false, action: 'stop');
    }
  }

  void _startRecordingActionBroadcast(String action) {
    _recordingActionTimer?.cancel();
    _wsService.sendTypingIndicator(widget.chatId, isTyping: true, action: action);
    _recordingActionTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted && (_isVoiceRecording || _isVideoRecording)) {
        _wsService.sendTypingIndicator(widget.chatId, isTyping: true, action: action);
      } else {
        _stopRecordingActionBroadcast();
      }
    });
  }

  void _stopRecordingActionBroadcast() {
    if (_recordingActionTimer != null) {
      _recordingActionTimer?.cancel();
      _recordingActionTimer = null;
      _wsService.sendTypingIndicator(widget.chatId, isTyping: false, action: 'stop');
    }
  }

  void _onMessageRead(WebSocketEvent event) {
    // Handle read status update
    final readerId = event.data['reader_id']?.toString();
    if (readerId == _currentUserId) return;

    final readAt = event.data['read_at']?.toString() ?? DateTime.now().toUtc().toIso8601String();
    final upToMessageId = event.data['up_to_message_id']?.toString();

    if (mounted) {
      setState(() {
        int upToIndex = 0;
        if (upToMessageId != null && upToMessageId.isNotEmpty) {
          final foundIndex = _messages.indexWhere((m) => m.id == upToMessageId);
          if (foundIndex >= 0) {
            upToIndex = foundIndex;
          }
        }
        // Messages list is newest-first (index 0 is newest)
        for (int i = upToIndex; i < _messages.length; i++) {
          if (_messages[i].senderId == _currentUserId) {
            _messages[i] = _messages[i].copyWith(
              isRead: true,
              readAt: _messages[i].readAt ?? readAt,
            );
          }
        }
        _updateFeedItems();
      });

      if (_currentUserId != null) {
        context
            .read<AppDatabase>()
            .markMessagesAsRead(widget.chatId, _currentUserId!, readAt: readAt);
      }
    }
  }

  void _onMessageListened(WebSocketEvent event) {
    final chatId = event.data['chat_id']?.toString();
    if (chatId != widget.chatId) return;

    final messageId = event.data['message_id']?.toString() ?? '';
    if (messageId.isEmpty) return;

    final listenedAt = event.data['listened_at']?.toString() ??
        DateTime.now().toUtc().toIso8601String();
    final readAt = event.data['read_at']?.toString() ?? listenedAt;

    if (mounted) {
      setState(() {
        final index = _messages.indexWhere((m) => m.id == messageId);
        if (index >= 0) {
          _messages[index] = _messages[index].copyWith(
            isRead: true,
            isListened: true,
            readAt: _messages[index].readAt ?? readAt,
            listenedAt: _messages[index].listenedAt ?? listenedAt,
          );
          _updateFeedItems();
        }
      });

      context.read<AppDatabase>().updateMessageReadAndListened(
            messageId,
            readAt: readAt,
            listenedAt: listenedAt,
            isListened: true,
          );
    }
  }

  void _onLocalMessageListened(String messageId, String listenedAt) {
    if (!mounted) return;
    setState(() {
      final index = _messages.indexWhere((m) => m.id == messageId);
      if (index >= 0) {
        _messages[index] = _messages[index].copyWith(
          isRead: true,
          isListened: true,
          readAt: _messages[index].readAt ?? listenedAt,
          listenedAt: _messages[index].listenedAt ?? listenedAt,
        );
        _updateFeedItems();
      }
    });
    context.read<AppDatabase>().updateMessageReadAndListened(
          messageId,
          readAt: listenedAt,
          listenedAt: listenedAt,
          isListened: true,
        );
  }

  Future<void> _markMessagesAsRead() async {
    final result = await ChatService.markMessagesAsRead(
      chatId: widget.chatId,
      chatTitle: widget.groupName,
    );
    final markedCount = result['marked_count'] as int? ?? 0;
    // Notify via WebSocket that messages were read
    _wsService.sendMessageRead(widget.chatId, markedCount: markedCount);
    if (result['success'] == true || markedCount > 0) {
      if (mounted) {
        setState(() {
          _unreadCount = 0;
        });
      }
      try {
        _unreadCountProvider?.clear(widget.chatId);
      } catch (_) {}
    }
  }

  Future<void> _loadData() async {
    // Get current user ID
    final userId = await AuthService.getUserId();
    setState(() {
      _currentUserId = userId;
    });

    // Load chat details
    final chatResult = await ChatService.getChat(widget.chatId);
    if (chatResult['success'] == true && mounted) {
      final chat = chatResult['chat'] as ChatDetails;
      setState(() {
        _groupName = chat.name;
        _groupAvatar = chat.avatarUrl;
        _participants = chat.participants;
      });
    }

    // Get unread info before loading messages
    final unreadInfo = await ChatService.getUnreadInfo(chatId: widget.chatId);
    if (unreadInfo['success'] == true && mounted) {
      final serverUnread = unreadInfo['unread_count'] as int? ?? 0;
      setState(() {
        _unreadCount = serverUnread;
        _firstUnreadMessageId = unreadInfo['first_unread_message_id'] as String?;
        if (_unreadCount > 0 && _firstUnreadMessageId != null) {
          _showUnreadDivider = true;
        }
        _updateFeedItems();
      });
      try {
        _unreadCountProvider?.setCount(widget.chatId, serverUnread);
      } catch (_) {}
    }

    // Load messages
    await _loadMessages();

    // Scroll to initial message if specified
    if (widget.initialMessageId != null) {
      _scrollToMessage(widget.initialMessageId!);
    } else if (_firstUnreadMessageId != null) {
      _scrollToFirstUnread();
    } else if (_unreadCount > 0) {
      await _markMessagesAsRead();
    }
  }

  Future<void> _loadMessages() async {
    setState(() => _isLoading = true);

    // 1. Сначала загрузить из Drift (мгновенно, offline-first)
    final db = AppDatabase();
    List<DbMessage> localMessages = [];
    try {
      localMessages = await db.getMessages(widget.chatId, limit: 50);
    } catch (e) {
      debugPrint('GroupChat: Drift getMessages error: $e');
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
        for (final m in _messages) {
          if (m.reactions.isNotEmpty) {
            _messageReactions[m.id] = Map.from(m.reactions);
          }
          if (m.myReactions.isNotEmpty) {
            _myReactions[m.id] = Set.from(m.myReactions);
          }
        }
        _updateFeedItems();
      });
      if (widget.initialMessageId == null &&
          (_firstUnreadMessageId == null || _unreadCount == 0)) {
        _scrollToBottom();
      }
    }

    // 2. Затем загрузить с сервера (обновление)
    try {
      final result =
          await ChatService.getMessages(chatId: widget.chatId, limit: 50);

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
            _messageReactions.clear();
            _myReactions.clear();
            _messages.addAll(mergedById.values);

            for (final m in _messages) {
              if (m.reactions.isNotEmpty) {
                _messageReactions[m.id] = Map.from(m.reactions);
              }
              if (m.myReactions.isNotEmpty) {
                _myReactions[m.id] = Set.from(m.myReactions);
              }
            }

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
            _updateFeedItems();

            // Сохранить в Drift для оффлайн-доступа
            try {
              db.saveMessages(
                  serverMessages.map((m) => _messageToCompanion(m)).toList());
            } catch (e) {
              debugPrint('GroupChat: Drift saveMessages error: $e');
            }
          }
        });
        if (localMessages.isEmpty &&
            widget.initialMessageId == null &&
            (_firstUnreadMessageId == null || _unreadCount == 0)) {
          _scrollToBottom();
        }
      }
    } catch (e) {
      debugPrint('GroupChat: Error loading from server: $e');
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
      chatId: widget.chatId,
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
          debugPrint('GroupChat: Drift saveMessages error: $e');
        }
      }

      setState(() {
        final existingIds = <String>{
          for (final m in _messages) m.id,
          for (final m in _messages) if (m.localId != null && m.localId!.isNotEmpty) m.localId!,
        };
        for (final m in newMessages) {
          if (!existingIds.contains(m.id) && (m.localId == null || !existingIds.contains(m.localId))) {
            _messages.add(m);
            existingIds.add(m.id);
            if (m.localId != null && m.localId!.isNotEmpty) existingIds.add(m.localId!);
            if (m.reactions.isNotEmpty) {
              _messageReactions[m.id] = Map.from(m.reactions);
            }
            if (m.myReactions.isNotEmpty) {
              _myReactions[m.id] = Set.from(m.myReactions);
            }
          }
        }
        _sortMessagesDescending(_messages);
        _updateFeedItems();
        _isLoadingMore = false;
      });
      return;
    }

    // Оффлайн-фоллбэк: если сервер недоступен, подгрузить из Drift
    try {
      final localMessages = await db.getMessages(
        widget.chatId,
        beforeCreatedAt: lastMessage?.createdAt,
        limit: 50,
      );

      if (localMessages.isNotEmpty && mounted) {
        setState(() {
          final existingIds = <String>{
            for (final m in _messages) m.id,
            for (final m in _messages) if (m.localId != null && m.localId!.isNotEmpty) m.localId!,
          };
          for (final m in localMessages.map((m) => Message.fromDbMessage(m))) {
            if (!existingIds.contains(m.id) && (m.localId == null || !existingIds.contains(m.localId))) {
              _messages.add(m);
              existingIds.add(m.id);
              if (m.localId != null && m.localId!.isNotEmpty) existingIds.add(m.localId!);
              if (m.reactions.isNotEmpty) {
                _messageReactions[m.id] = Map.from(m.reactions);
              }
              if (m.myReactions.isNotEmpty) {
                _myReactions[m.id] = Set.from(m.myReactions);
              }
            }
          }
          _sortMessagesDescending(_messages);
          _updateFeedItems();
          _isLoadingMore = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('GroupChat: Drift loadMore error: $e');
    }

    if (mounted) {
      setState(() => _isLoadingMore = false);
    }
  }

  /// Конвертация Message → MessagesCompanion для Drift
  MessagesCompanion _messageToCompanion(Message msg) {
    final hasServerId = msg.sendStatus == 1 && msg.id.isNotEmpty;
    final effectiveChatId = msg.chatId.isNotEmpty ? msg.chatId : widget.chatId;
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
      mediaPayload: (() {
        final mergedPayload = <String, dynamic>{
          if (msg.mediaPayload != null) ...msg.mediaPayload!,
          if (msg.readAt != null && msg.readAt!.isNotEmpty)
            'read_at': msg.readAt,
          if (msg.listenedAt != null && msg.listenedAt!.isNotEmpty)
            'listened_at': msg.listenedAt,
          if (msg.isListened) 'is_listened': true,
        };
        return mergedPayload.isNotEmpty
            ? Value<String?>(jsonEncode(mergedPayload))
            : const Value<String?>.absent();
      })(),
      invertMedia: Value(msg.invertMedia),
      isForward: Value(msg.isForward),
      forwardFromId: Value(msg.forwardFromId),
      forwardFromName: Value(msg.forwardFromName),
    );
  }

  Future<void> _sendMessage({
    String? cleanText,
    List<MessageEntity>? entities,
    LinkPreviewOptions? linkPreviewOptions,
    bool invertMedia = false,
  }) async {
    final String rawText = _messageController.text.trim();
    final String text = cleanText?.trim() ?? rawText;
    if ((text.isEmpty && _attachedFiles.isEmpty) || _isSending) return;

    if (_isEditing && _editingMessageId != null) {
      final messageId = _editingMessageId!;
      _cancelEditing();
      try {
        final parsed = cleanText != null ? null : EntityParser.parseMarkdown(rawText);
        final String effectiveText = cleanText ?? parsed!.cleanText;
        final List<MessageEntity>? effectiveEntities =
            entities ?? (parsed?.entities.isNotEmpty == true ? parsed!.entities : null);

        final res = await ChatService.editMessage(
          chatId: widget.chatId,
          messageId: messageId,
          content: effectiveText,
          entities: effectiveEntities,
        );
        if (res['success'] == true) {
          if (mounted) {
            setState(() {
              final idx = _messages.indexWhere((m) => m.id == messageId);
              if (idx != -1) {
                _messages[idx] = _messages[idx].copyWith(
                  content: effectiveText,
                  entities: effectiveEntities,
                  isEdited: true,
                );
              }
            });
          }
          await AppDatabase().updateMessageContent(
            messageId,
            effectiveText,
            effectiveEntities != null && effectiveEntities.isNotEmpty
                ? jsonEncode(effectiveEntities.map((e) => e.toJson()).toList())
                : null,
          );
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  res['message'] ?? context.l10n.translate('chat_edit_error'),
                ),
              ),
            );
          }
        }
      } catch (e) {
        debugPrint('Error editing group message: $e');
      }
      return;
    }

    final replyTo = _replyToMessage;
    final replyIsQuote = _isQuote;
    final replyQuoteText = _quoteText;
    final replyQuoteOffset = _quoteOffset;
    final replyQuoteLength = _quoteLength;

    _stopMyTyping();
    DraftService().deleteDraft(widget.chatId);
    _messageController.clear();
    if (_isDetachedHistoryWindow && _detachedLatestBackup.isNotEmpty) {
      _messages
        ..clear()
        ..addAll(_detachedLatestBackup);
      _hasMoreMessages = _detachedBackupHasMoreOlder;
      _isDetachedHistoryWindow = false;
      _hasMoreNewerMessages = false;
      _detachedLatestBackup = [];
    }
    setState(() {
      _isSending = true;
      _isUploading = _attachedFiles.isNotEmpty;
      _replyToMessage = null;
      _isQuote = false;
      _quoteText = null;
      _quoteOffset = 0;
      _quoteLength = 0;
      _showUnreadDivider = false;
      _firstUnreadMessageId = null;
      _firstUnreadFeedIndex = -1;
    });
    _scrollToBottom();

    try {
      final parsed = cleanText != null ? null : EntityParser.parseMarkdown(text);
      final String effectiveContentText = cleanText ?? parsed!.cleanText;
      final List<MessageEntity>? effectiveEntities =
          entities ?? (parsed?.entities.isNotEmpty == true ? parsed!.entities : null);

      // CASE 1: MULTIPLE VISUAL ATTACHMENTS (ALBUM: chunked into batches of up to 10 items)
      if (_attachedFiles.length >= 2 && _attachedFiles.every((f) => _isMediaFile(f.path))) {
        final allFiles = List<File>.from(_attachedFiles);
        _clearAttachedFiles();

        final totalFilesCount = allFiles.length;
        int overallProcessedCount = 0;

        for (int chunkStart = 0; chunkStart < totalFilesCount; chunkStart += 10) {
          final chunkEnd = math.min(chunkStart + 10, totalFilesCount);
          final chunkFiles = allFiles.sublist(chunkStart, chunkEnd);
          final isFirstChunk = (chunkStart == 0);
          final chunkCaption = isFirstChunk && effectiveContentText.isNotEmpty ? effectiveContentText : null;
          final chunkEntities = isFirstChunk ? effectiveEntities : null;

          final albumItems = <Map<String, dynamic>>[];
          final albumGroupedId =
              'album_${DateTime.now().millisecondsSinceEpoch}_${const Uuid().v4().substring(0, 8)}';

          for (int i = 0; i < chunkFiles.length; i++) {
            final file = chunkFiles[i];
            final isVideo = _isVideoFile(file.path);

            final uploadResult = await _fileService.uploadFileChunked(file, onProgress: (p) {
              if (mounted) {
                _uploadProgressNotifier.value = (overallProcessedCount + i + p) / totalFilesCount;
              }
            });

            final itemMediaPayload = {
              if (uploadResult.thumbBase64 != null) 'thumb_base64': uploadResult.thumbBase64,
              if (uploadResult.thumbUrl != null) 'thumb_url': uploadResult.thumbUrl,
              if (uploadResult.width > 0) 'width': uploadResult.width,
              if (uploadResult.height > 0) 'height': uploadResult.height,
              if (uploadResult.duration > 0) 'duration': uploadResult.duration,
              'file_size': uploadResult.fileSize,
              'is_video': isVideo,
            };

            albumItems.add({
              'file_url': uploadResult.url,
              'file_name': uploadResult.fileName,
              'file_size': uploadResult.fileSize,
              'message_type': isVideo ? 'video' : 'image',
              'media_payload': itemMediaPayload,
            });
          }

          overallProcessedCount += chunkFiles.length;

          if (chunkFiles.length >= 2) {
            Map<String, dynamic> res = await ChatService.sendMediaAlbum(
              chatId: widget.chatId,
              items: albumItems,
              groupedId: albumGroupedId,
              caption: chunkCaption,
              entities: chunkEntities,
              invertMedia: invertMedia,
              replyToMessageId: replyTo?.id,
            );

            // Fallback: If server album endpoint fails, send items sequentially with the same albumGroupedId
            if (res['success'] != true) {
              debugPrint('sendMediaAlbum failed in group (${res['message']}), falling back to individual messages with groupedId');
              final fallbackMsgs = <Message>[];
              for (int itemIdx = 0; itemIdx < albumItems.length; itemIdx++) {
                final item = albumItems[itemIdx];
                final isLast = itemIdx == albumItems.length - 1;
                final singleRes = await ChatService.sendMessage(
                  chatId: widget.chatId,
                  messageType: item['message_type'] ?? 'image',
                  content: isLast ? (chunkCaption ?? '') : '',
                  fileUrl: item['file_url'],
                  fileName: item['file_name'],
                  mediaPayload: item['media_payload'],
                  entities: isLast ? chunkEntities : null,
                  groupedId: albumGroupedId,
                  invertMedia: invertMedia,
                  replyToMessageId: replyTo?.id,
                );
                if (singleRes['success'] == true && singleRes['message'] is Message) {
                  fallbackMsgs.add(singleRes['message'] as Message);
                }
              }
              if (fallbackMsgs.isNotEmpty) {
                res = {
                  'success': true,
                  'grouped_id': albumGroupedId,
                  'messages': fallbackMsgs,
                };
              }
            }

            if (res['success'] == true) {
              final rawMessages = res['messages'] as List<dynamic>? ?? [];
              final newMsgs = <Message>[];
              for (final raw in rawMessages) {
                final msg = raw is Message
                    ? raw
                    : (raw is Map
                        ? Message.fromJson(Map<String, dynamic>.from(raw))
                        : null);
                if (msg != null) {
                  newMsgs.add(msg);
                }
              }
              for (final msg in newMsgs) {
                final existingIdx = _messages.indexWhere((m) => m.id == msg.id);
                if (existingIdx != -1) {
                  _messages[existingIdx] = msg;
                } else {
                  _messages.insert(0, msg);
                }
              }
              _updateFeedItems();
              final db = AppDatabase();
              await db.saveMessages(
                  newMsgs.map((m) => _messageToCompanion(m)).toList());
            } else {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(res['message'] ?? 'Failed to send album')),
                );
              }
            }
          } else {
            // Remainder 1 item: send as single message
            final item = albumItems.first;
            final isVideo = item['message_type'] == 'video';
            final res = await ChatService.sendMessage(
              chatId: widget.chatId,
              messageType: isVideo ? 'video' : 'image',
              content: chunkCaption ?? '',
              fileUrl: item['file_url'],
              fileName: item['file_name'],
              mediaPayload: item['media_payload'],
              entities: chunkEntities,
              replyToMessageId: replyTo?.id,
            );
            if (res['success'] == true && res['message'] is Message) {
              final sent = res['message'] as Message;
              _messages.insert(0, sent);
              _updateFeedItems();
              await AppDatabase().saveMessage(_messageToCompanion(sent));
            }
          }
        }

        if (mounted) {
          setState(() {
            _isUploading = false;
            _uploadProgressNotifier.value = 0.0;
            _isSending = false;
          });
          _scrollToBottom();
        }
        return;
      }

      // CASE 2: MULTIPLE DOCUMENTS OR NON-VISUAL ATTACHMENTS (Send individually)
      if (_attachedFiles.length >= 2) {
        final filesToSend = List<File>.from(_attachedFiles);
        _clearAttachedFiles();
        for (int i = 0; i < filesToSend.length; i++) {
          final file = filesToSend[i];
          final isVideo = _isVideoFile(file.path);
          final isImg = _isImageFile(file.path);
          final uploadResult = await _fileService.uploadFileChunked(file, onProgress: (p) {
            if (mounted) {
              _uploadProgressNotifier.value = (i + p) / filesToSend.length;
            }
          });

          final fileMessageType = isVideo ? 'video' : (isImg ? 'image' : _getMessageTypeFromMimeType(uploadResult.mimeType));
          final fileCaption = (i == 0 && effectiveContentText.isNotEmpty) ? effectiveContentText : '';
          final res = await ChatService.sendMessage(
            chatId: widget.chatId,
            content: fileCaption,
            messageType: fileMessageType,
            fileUrl: uploadResult.url,
            fileName: uploadResult.fileName,
            mediaPayload: uploadResult.toMediaPayload(),
            replyToMessageId: replyTo?.id,
            entities: (i == 0) ? effectiveEntities : null,
          );
          if (res['success'] == true && res['message'] is Message) {
            final sent = res['message'] as Message;
            if (mounted) {
              setState(() {
                if (!_messages.any((m) => m.id == sent.id)) {
                  _messages.insert(0, sent);
                  _updateFeedItems();
                }
              });
            }
            await AppDatabase().saveMessage(_messageToCompanion(sent));
          }
        }
        if (mounted) {
          setState(() {
            _isUploading = false;
            _uploadProgressNotifier.value = 0.0;
            _isSending = false;
          });
          _scrollToBottom();
        }
        return;
      }

      // CASE 3: SINGLE ATTACHMENT OR TEXT
      String messageType = 'text';
      String content = effectiveContentText;
      String? fileUrl;
      String? fileName;
      Map<String, dynamic>? singleMediaPayload;

      if (_attachedFiles.isNotEmpty) {
        final file = _attachedFiles.first;
        final isVideo = _isVideoFile(file.path);

        final uploadResult = await _fileService.uploadFileChunked(file, onProgress: (p) {
          _uploadProgressNotifier.value = p;
        });

        singleMediaPayload = {
          if (uploadResult.thumbBase64 != null) 'thumb_base64': uploadResult.thumbBase64,
          if (uploadResult.thumbUrl != null) 'thumb_url': uploadResult.thumbUrl,
          if (uploadResult.width > 0) 'width': uploadResult.width,
          if (uploadResult.height > 0) 'height': uploadResult.height,
          if (uploadResult.duration > 0) 'duration': uploadResult.duration,
          'file_size': uploadResult.size,
          'is_video': isVideo,
        };

        setState(() {
          _isUploading = false;
          _uploadProgressNotifier.value = 0.0;
        });

        messageType =
            isVideo ? 'video' : _getMessageTypeFromMimeType(uploadResult.mimeType);
        content = effectiveContentText;
        fileUrl = uploadResult.url;
        fileName = uploadResult.fileName;

        _clearAttachedFiles();
      }

      final syncService = SyncService();
      String? pendingLocalId;
      DbMessage? pendingMsg;
      try {
        pendingMsg = await syncService.createPendingMessage(
          chatId: widget.chatId,
          senderId: _currentUserId ?? '',
          content: content,
          messageType: messageType,
          fileUrl: fileUrl,
          fileName: fileName,
          mediaPayload: singleMediaPayload,
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
            _updateFeedItems();
            _isSending = false;
          });
          _scrollToBottom();
        }

        try {
          final result = await ChatService.sendMessage(
            chatId: widget.chatId,
            content: content,
            messageType: messageType,
            fileUrl: fileUrl,
            fileName: fileName,
            mediaPayload: singleMediaPayload,
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
              if (sentMessage is Message) {
                try {
                  await AppDatabase().saveMessage(_messageToCompanion(sentMessage.copyWith(
                    localId: pendingLocalId,
                    sendStatus: 1,
                    isQuote: sentMessage.isQuote || replyIsQuote,
                    quoteText: sentMessage.quoteText ?? replyQuoteText,
                    quoteOffset: sentMessage.quoteOffset != 0 ? sentMessage.quoteOffset : replyQuoteOffset,
                    quoteLength: sentMessage.quoteLength != 0 ? sentMessage.quoteLength : replyQuoteLength,
                  )));
                } catch (_) {}
              }
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
                    _updateFeedItems();
                  }
                });
              }
            }
          } else {
            final errMsg = result['message']?.toString() ?? 'Failed to send message';
            debugPrint('ChatService.sendMessage in group returned false: $errMsg');
            await syncService.markMessageFailed(pendingLocalId);
            if (mounted) {
              setState(() {
                final idx =
                    _messages.indexWhere((m) => m.localId == pendingLocalId);
                if (idx != -1) {
                  _messages[idx] =
                      _messages[idx].copyWith(sendStatus: 2); // failed
                  _updateFeedItems();
                }
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(errMsg)),
              );
            }
          }
        } catch (e) {
          debugPrint('ChatService.sendMessage in group exception: $e');
          await syncService.markMessageFailed(pendingLocalId);
          if (mounted) {
            setState(() {
              final idx =
                  _messages.indexWhere((m) => m.localId == pendingLocalId);
              if (idx != -1) {
                _messages[idx] =
                    _messages[idx].copyWith(sendStatus: 2); // failed
                _updateFeedItems();
              }
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Failed to send message: $e')),
            );
          }
        }
      } else {
        final result = await ChatService.sendMessage(
          chatId: widget.chatId,
          content: content,
          messageType: messageType,
          fileUrl: fileUrl,
          fileName: fileName,
          mediaPayload: singleMediaPayload,
        );

        if (mounted) {
          if (result['success'] == true) {
            final sentMsg = result['message'] as Message;
            setState(() {
              if (!_messages.any((m) => m.id == sentMsg.id)) {
                _messages.insert(0, sentMsg);
                _updateFeedItems();
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
    } catch (e) {
      debugPrint('[GroupChatScreen] Error in _sendMessage: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to send: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
          _isUploading = false;
          _uploadProgressNotifier.value = 0.0;
        });
      }
    }
  }

  String _getMessageTypeFromMimeType(String mimeType) {
    if (mimeType.startsWith('image/')) return 'image';
    if (mimeType.startsWith('video/')) return 'video';
    if (mimeType.startsWith('audio/')) return 'audio';
    return 'file';
  }

  void _showAttachmentPicker() async {
    _dismissKeyboardAndEmoji();
    final result = await AttachmentPickerBottomSheet.show(context, allowPoll: true);
    if (result == null || !mounted) return;

    if (result.files != null && result.files!.isNotEmpty) {
      if (result.asDocument) {
        setState(() {
          for (final file in result.files!) {
            _attachedFiles.add(file);
            _attachedFileNames.add(p.basename(file.path));
          }
        });
        if (result.sendImmediately) {
          _sendMessage();
        }
      } else if (result.sendImmediately) {
        setState(() {
          for (final file in result.files!) {
            _attachedFiles.add(file);
            _attachedFileNames.add(p.basename(file.path));
          }
        });
        _sendMessage();
      } else {
        await _openMediaSendScreen(result.files!);
      }
      return;
    }

    switch (result.action) {
      case AttachmentPickerAction.camera:
        _takePhoto();
        break;
      case AttachmentPickerAction.gallery:
        _pickMedia('media');
        break;
      case AttachmentPickerAction.file:
        _pickDocument();
        break;
      case AttachmentPickerAction.location:
        // Location sending in group chat
        break;
      case AttachmentPickerAction.contact:
        // Contact sending in group chat
        break;
      case AttachmentPickerAction.music:
        _pickAudio();
        break;
      case AttachmentPickerAction.poll:
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PollCreateScreen(chatId: widget.chatId),
          ),
        );
        break;
      case null:
        break;
    }
  }

  Future<void> _pickAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
      );
      if (result != null && result.files.isNotEmpty) {
        setState(() {
          for (final file in result.files) {
            if (file.path != null) {
              _attachedFiles.add(File(file.path!));
              _attachedFileNames.add(file.name);
            }
          }
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick audio: $e')),
        );
      }
    }
  }

  Future<void> _openMediaSendScreen(List<File> files) async {
    if (files.isEmpty) return;
    final result = await Navigator.push<MediaSendResult>(
      context,
      MaterialPageRoute(
        builder: (context) => MediaSendScreen(initialFiles: files),
      ),
    );

    if (result != null && result.files.isNotEmpty && mounted) {
      setState(() {
        for (final file in result.files) {
          _attachedFiles.add(file);
          _attachedFileNames.add(p.basename(file.path));
        }
        if (result.caption != null && result.caption!.isNotEmpty) {
          _messageController.text = result.caption!;
        }
      });
      _sendMessage();
    }
  }

  Future<void> _pickMedia(String type) async {
    try {
      if (type == 'video') {
        final result = await FilePicker.platform.pickFiles(
          type: FileType.video,
          allowMultiple: true,
        );
        if (result != null && result.files.isNotEmpty) {
          final List<File> picked = [];
          for (final file in result.files) {
            if (file.path != null) {
              picked.add(File(file.path!));
            }
          }
          if (picked.isNotEmpty) {
            await _openMediaSendScreen(picked);
          }
        }
      } else {
        List<XFile> pickedMedia = [];
        try {
          pickedMedia = await _imagePicker.pickMultipleMedia(
            maxWidth: 1920,
            maxHeight: 1920,
            imageQuality: 95,
          );
        } catch (_) {
          pickedMedia = await _imagePicker.pickMultiImage(
            maxWidth: 1920,
            maxHeight: 1920,
            imageQuality: 95,
          );
        }
        if (pickedMedia.isNotEmpty) {
          final picked = pickedMedia.map((x) => File(x.path)).toList();
          await _openMediaSendScreen(picked);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick $type: $e')),
        );
      }
    }
  }

  Future<void> _takePhoto() async {
    try {
      final XFile? photo = await _imagePicker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1920,
        imageQuality: 95,
      );

      if (photo != null) {
        await _openMediaSendScreen([File(photo.path)]);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to take photo: $e')),
        );
      }
    }
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        type: FileType.any,
      );

      if (result != null && result.files.isNotEmpty) {
        for (var file in result.files) {
          if (file.path != null) {
            setState(() {
              _attachedFiles.add(File(file.path!));
              _attachedFileNames.add(file.name);
            });
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to pick document: $e')),
        );
      }
    }
  }

  void _openFile(String fileUrl, String fileName, String messageType) {
    if (messageType == 'image') {
      FullscreenPhotoViewer.open(context, fileUrl);
      return;
    }
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const iconoir.OpenNewWindow(width: 22, height: 22),
              title: Text(context.l10n.translate('chat_open_file')),
              onTap: () {
                Navigator.pop(context);
                _downloadAndOpenFile(fileUrl, fileName);
              },
            ),
            ListTile(
              leading: const iconoir.Download(width: 22, height: 22),
              title: Text(context.l10n.translate('chat_download')),
              onTap: () {
                Navigator.pop(context);
                _downloadFile(fileUrl, fileName);
              },
            ),
            ListTile(
              leading: const iconoir.ShareAndroid(width: 22, height: 22),
              title: Text(context.l10n.translate('share')),
              onTap: () async {
                Navigator.pop(context);
                await SharePlus.instance.share(
                  ShareParams(text: fileUrl, subject: fileName),
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _downloadAndOpenFile(String fileUrl, String fileName) async {
    try {
      if (kIsWeb) {
        final uri = Uri.parse(fileUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, webOnlyWindowName: '_blank');
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Не удалось открыть файл')),
            );
          }
        }
      } else {
        final filePath = await _fileService.downloadToDownloads(
          fileUrl,
          fileName,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Файл скачан: $filePath')),
          );
          await _fileService.openFile(filePath);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при открытии файла: $e')),
        );
      }
    }
  }

  Future<void> _downloadFile(String fileUrl, String fileName) async {
    try {
      if (kIsWeb) {
        final uri = Uri.parse(AppConfig.resolveMediaUrl(fileUrl) ?? fileUrl);
        await launchUrl(uri, webOnlyWindowName: '_blank');
        return;
      }
      final filePath = await _fileService.downloadToDownloads(
        fileUrl,
        fileName,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Файл скачан: $filePath')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка при скачивании файла: $e')),
        );
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
        _updateFeedItems();
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
            _updateFeedItems();
          }
        });
      }
    } catch (e) {
      debugPrint('Retry getMessageByLocalId error: $e');
    }
  }

  int _findFeedIndexForMessage(String messageId) {
    return _feedItems.indexWhere((item) =>
        item.id == messageId ||
        (item is FeedAlbumItem &&
            item.album.items.any((ai) => ai.id == messageId)));
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

  /// Restores the contiguous latest messages tail when exiting a detached history window.
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
      _updateFeedItems();
    });
    if (scrollToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_scrollController.hasClients) return;
        _scrollController.jumpTo(0);
      });
    }
  }

  /// Scroll to the first unread message using exact RenderObject-guided seek
  Future<void> _scrollToFirstUnread() async {
    if (_firstUnreadMessageId == null || _hasScrolledToUnread) return;
    _hasScrolledToUnread = true;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted || !_scrollController.hasClients) return;
      final targetId = _firstUnreadMessageId;
      if (targetId == null) return;

      if (_unreadSeparatorKey.currentContext != null) {
        await Scrollable.ensureVisible(
          _unreadSeparatorKey.currentContext!,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOutCubic,
          alignment: 0.82,
        );
        return;
      }

      int targetFeedIndex = _firstUnreadFeedIndex;
      if (targetFeedIndex == -1) {
        targetFeedIndex = _findFeedIndexForMessage(targetId);
      }

      if (targetFeedIndex == -1 && mounted) {
        await _fetchMessagesAround(targetId);
        targetFeedIndex = _findFeedIndexForMessage(targetId);
      }

      int retries = 0;
      while (
          targetFeedIndex == -1 && _hasMoreMessages && retries < 3 && mounted) {
        await _loadMoreMessages();
        retries++;
        targetFeedIndex = _findFeedIndexForMessage(targetId);
      }

      if (!mounted || !_scrollController.hasClients) return;

      if (targetFeedIndex == -1) {
        if (_scrollController.position.hasContentDimensions) {
          _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
        }
        return;
      }

      _isProgrammaticJump = true;
      try {
        await ChatScrollNavigator.scrollToTarget(
          scrollController: _scrollController,
          targetIndex: targetFeedIndex,
          itemCount: _feedItems.length,
          isMounted: () => mounted,
          keyForIndex: (index) => _messageKeys[_feedItems[index].id],
          resolveTargetKey: () {
            if (_unreadSeparatorKey.currentContext != null) {
              return _unreadSeparatorKey;
            }
            final idx = _findFeedIndexForMessage(targetId);
            if (idx != -1) {
              return _messageKeys[_feedItems[idx].id];
            }
            return _messageKeys[targetId];
          },
          alignment: 0.82,
        );
      } finally {
        _isProgrammaticJump = false;
      }
    });
  }

  /// Fetch messages around a specific target message ID without creating missing message gaps.
  /// - If target is in `_detachedLatestBackup`, restores the latest tail.
  /// - If target is close enough (`<= 160` IDs from the oldest loaded message), bridges contiguously.
  /// - If target is far in history, switches to an isolated history window (`_isDetachedHistoryWindow = true`).
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
          chatId: widget.chatId,
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
              final existingIds = <String>{
                for (final m in _messages) m.id,
                for (final m in _messages)
                  if (m.localId != null && m.localId!.isNotEmpty) m.localId!,
              };
              for (final m in bridged) {
                if (!existingIds.contains(m.id) &&
                    (m.localId == null || !existingIds.contains(m.localId))) {
                  _messages.add(m);
                  existingIds.add(m.id);
                  if (m.reactions.isNotEmpty) {
                    _messageReactions[m.id] = Map.from(m.reactions);
                  }
                  if (m.myReactions.isNotEmpty) {
                    _myReactions[m.id] = Set.from(m.myReactions);
                  }
                }
              }
              _sortMessagesDescending(_messages);
              _updateFeedItems();
            });
            return;
          }
        }
      }

      final result = await ChatService.getMessages(
        chatId: widget.chatId,
        limit: 60,
        aroundMessageId: targetMessageId,
      );
      if (result['success'] == true && mounted) {
        final fetched = result['messages'] as List<Message>;
        if (fetched.isEmpty) return;

        final existingIds = <String>{
          for (final m in _messages) m.id,
          for (final m in _messages)
            if (m.localId != null && m.localId!.isNotEmpty) m.localId!,
        };
        final bool overlapsCurrent =
            fetched.any((m) => existingIds.contains(m.id));

        setState(() {
          for (final m in fetched) {
            if (m.reactions.isNotEmpty) {
              _messageReactions[m.id] = Map.from(m.reactions);
            }
            if (m.myReactions.isNotEmpty) {
              _myReactions[m.id] = Set.from(m.myReactions);
            }
          }

          if (overlapsCurrent && !_isDetachedHistoryWindow) {
            for (final m in fetched) {
              if (!existingIds.contains(m.id) &&
                  (m.localId == null || !existingIds.contains(m.localId))) {
                _messages.add(m);
                existingIds.add(m.id);
              }
            }
            _sortMessagesDescending(_messages);
            _updateFeedItems();
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
            _updateFeedItems();
            _showScrollDownFabNotifier.value = true;
          }
        });
      }
    } catch (e) {
      debugPrint('Error fetching messages around $targetMessageId: $e');
    }
  }

  /// Loads newer messages when scrolling down towards the present inside a detached history window.
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

    String? anchorFeedId;
    double? anchorScreenDy;
    for (int i = 0; i < _feedItems.length; i++) {
      final key = _messageKeys[_feedItems[i].id];
      final box = key?.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.attached && box.hasSize) {
        anchorFeedId = _feedItems[i].id;
        anchorScreenDy = box.localToGlobal(Offset.zero).dy;
        break;
      }
    }

    try {
      final result = await ChatService.getMessages(
        chatId: widget.chatId,
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

          for (final m in newerMessages) {
            if (m.reactions.isNotEmpty) {
              _messageReactions[m.id] = Map.from(m.reactions);
            }
            if (m.myReactions.isNotEmpty) {
              _myReactions[m.id] = Set.from(m.myReactions);
            }
          }

          _messages
            ..clear()
            ..addAll(merged.values);
          _sortMessagesDescending(_messages);
          _updateFeedItems();
          _isLoadingNewer = false;
        });

        if (anchorFeedId != null && anchorScreenDy != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted || !_scrollController.hasClients) return;
            final key = _messageKeys[anchorFeedId];
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
      debugPrint('Error loading newer group messages: $e');
      if (mounted) {
        setState(() => _isLoadingNewer = false);
      }
    }
  }

  /// Scroll to a specific message and highlight it using RenderObject-guided seek
  Future<void> _scrollToMessage(
    String messageId, {
    double alignment = 0.5,
    bool highlight = true,
  }) async {
    if (!mounted) return;

    if (_isDetachedHistoryWindow &&
        _findFeedIndexForMessage(messageId) == -1 &&
        _detachedLatestBackup.any((m) => m.id == messageId)) {
      await _restoreLatestMessagesTail();
    }

    int index = _findFeedIndexForMessage(messageId);
    if (index == -1) {
      await _fetchMessagesAround(messageId);
      if (!mounted) return;
      index = _findFeedIndexForMessage(messageId);
      int loadRetries = 0;
      while (index == -1 && _hasMoreMessages && loadRetries < 3 && mounted) {
        await _loadMoreMessages();
        loadRetries++;
        index = _findFeedIndexForMessage(messageId);
      }
      if (index == -1) return;
    }

    _isProgrammaticJump = true;
    try {
      final reached = await ChatScrollNavigator.scrollToTarget(
        scrollController: _scrollController,
        targetIndex: index,
        itemCount: _feedItems.length,
        isMounted: () => mounted,
        keyForIndex: (i) => _messageKeys[_feedItems[i].id],
        resolveTargetKey: () {
          final idx = _findFeedIndexForMessage(messageId);
          if (idx != -1) {
            return _messageKeys[_feedItems[idx].id];
          }
          return _messageKeys[messageId];
        },
        alignment: alignment,
      );
      if (reached && highlight && mounted) {
        _setHighlight(messageId);
      }
    } finally {
      _isProgrammaticJump = false;
    }
  }

  void _scheduleStickyDateUpdate() {
    if (_stickyDatePostFrameScheduled) return;
    _stickyDatePostFrameScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _stickyDatePostFrameScheduled = false;
      if (mounted) {
        _updateFloatingDateOnScroll();
      }
    });
  }

  /// Updates which day span owns the top sticky date slot.
  /// Exact inline-vs-sticky visibility and push-handoff are evaluated during
  /// flushPaint() by InlineChatDateHeader and FloatingChatDateHeader.
  void _updateFloatingDateOnScroll() {
    if (!mounted || _daySpans.isEmpty) {
      if (_stickyDateStateNotifier.value != StickyDateState.empty) {
        _stickyDateStateNotifier.value = StickyDateState.empty;
      }
      return;
    }

    final stickyBox =
        _stickyDateSlotKey.currentContext?.findRenderObject() as RenderBox?;
    if (stickyBox == null || !stickyBox.attached || !stickyBox.hasSize) {
      _scheduleStickyDateUpdate();
      return;
    }
    final stickyTopY = stickyBox.localToGlobal(Offset.zero).dy;

    int? mountedRefIdx;
    for (int i = 0; i < _feedItems.length; i++) {
      final key = _messageKeys[_feedItems[i].id];
      final box = key?.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.attached && box.hasSize) {
        mountedRefIdx = i;
        break;
      }
    }

    int? activeSpanIdx;
    for (int s = 0; s < _daySpans.length; s++) {
      final span = _daySpans[s];
      final sepKey = _dateSeparatorKeys[span.day];
      final sepBox = sepKey?.currentContext?.findRenderObject() as RenderBox?;

      bool isAtOrAboveSticky;
      if (sepBox != null && sepBox.attached && sepBox.hasSize) {
        final sepTopY = sepBox.localToGlobal(Offset.zero).dy;
        isAtOrAboveSticky = sepTopY <= stickyTopY + 0.5;
      } else if (mountedRefIdx != null) {
        isAtOrAboveSticky = span.oldestIdx > mountedRefIdx;
      } else {
        isAtOrAboveSticky = false;
      }

      if (isAtOrAboveSticky) {
        activeSpanIdx = s;
        break;
      }
    }

    final effectiveSpanIdx = activeSpanIdx ?? (_daySpans.length - 1);
    final activeSpan = _daySpans[effectiveSpanIdx];
    final nextNewerSpan =
        effectiveSpanIdx > 0 ? _daySpans[effectiveSpanIdx - 1] : null;

    final nextState = StickyDateState(
      day: activeSpan.day,
      label: _formatDateLabel(activeSpan.sampleDt),
      sameDaySepKey: _dateSeparatorKeys[activeSpan.day],
      nextDaySepKey: nextNewerSpan != null
          ? _dateSeparatorKeys[nextNewerSpan.day]
          : null,
    );

    if (_stickyDateStateNotifier.value != nextState) {
      _stickyDateStateNotifier.value = nextState;
    }
  }

  /// Opens the Telegram-style chat media calendar when tapping a date pill
  Future<void> _openCalendarForDate(DateTime initialDate) async {
    HapticUtils.selection();
    final selectedDay = await ChatHistoryCalendar.show(
      context: context,
      chatId: widget.chatId,
      initialDate: initialDate,
      currentMessages: _messages,
    );
    if (selectedDay != null && mounted) {
      await _jumpToCalendarDay(selectedDay);
    }
  }

  /// Jumps to the first message of the selected calendar day and saves jump history
  Future<void> _jumpToCalendarDay(ChatCalendarDayInfo dayInfo) async {
    if (!mounted || dayInfo.firstMessageId.isEmpty) return;

    // Record current visible message in _jumpHistory so ScrollDownFab can return back
    if (_feedItems.isNotEmpty) {
      String currentAnchorId = _feedItems.first.id;
      for (int i = 0; i < _feedItems.length; i++) {
        final key = _messageKeys[_feedItems[i].id];
        final box = key?.currentContext?.findRenderObject() as RenderBox?;
        if (box != null && box.attached && box.hasSize) {
          currentAnchorId = _feedItems[i].id;
          break;
        }
      }
      if (_jumpHistory.isEmpty || _jumpHistory.last != currentAnchorId) {
        _jumpHistory.add(currentAnchorId);
        _showScrollDownFabNotifier.value = true;
      }
    }

    await _scrollToMessage(
      dayInfo.firstMessageId,
      alignment: 0.78,
      highlight: true,
    );
  }

  void _setHighlight(String messageId) {
    if (!mounted) return;
    setState(() {
      _highlightMessageId = messageId;
    });

    _highlightTimer?.cancel();
    _highlightTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) {
        setState(() {
          _highlightMessageId = null;
        });
      }
    });
  }

  /// Handles tapping on a reply/forward header: scrolls locally or navigates to another chat
  Future<void> _handleReplyTap(String messageId, String? originalChatId, {String? fromMessageId}) async {
    if (originalChatId == null || originalChatId == widget.chatId) {
      if (fromMessageId != null && (_jumpHistory.isEmpty || _jumpHistory.last != fromMessageId)) {
        _jumpHistory.add(fromMessageId);
        _showScrollDownFabNotifier.value = true;
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
      widget.chatId,
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
      widget.chatId,
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
      widget.chatId,
      text: _messageController.text,
    );
  }

  String _formatTime(String timestamp) {
    return DateTimeUtils.formatTimeHHmm(timestamp);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _syncDebounceTimer?.cancel();
    _transitionTimer?.cancel();
    _stickyDateStateNotifier.dispose();
    _emojiPanelController.dispose();
    _inputFocusNode.removeListener(_onFocusChanged);
    TilingLayoutController.instance.removeListener(_onTilingLayoutChanged);
    if (_isDesktopPlatform) {
      HardwareKeyboard.instance.removeHandler(_handleGlobalDesktopKeyEvent);
    }

    // Flush any pending mark-as-read and draft before leaving
    _markReadTimer?.cancel();
    _flushMarkRead();
    if (!_isEditing) {
      DraftService().flushDraft(widget.chatId);
    }

    _showScrollDownFabNotifier.dispose();
    _uploadProgressNotifier.dispose();
    _stopMyTyping();
    _stopRecordingActionBroadcast();
    _tabController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _chatSubscription?.cancel();
    _typingTimer?.cancel();

    if (_registeredTileId != null) {
      TilingLayoutController.instance.unregisterTileBackHandler(
        _registeredTileId!,
        _handleTileBack,
      );
    }

    // Clear the open chat indicator in the provider
    try {
      _unreadCountProvider?.closeChat(widget.chatId);
    } catch (_) {}
    NotificationService().removeActiveChat(widget.chatId);

    if (_isVoiceRecording) {
      _voiceRecorderService.cancelRecording();
    }
    if (_isVideoRecording) {
      _videoRecorderService.cancelRecording();
    }
    _videoRecorderService.dispose();
    _voiceRecorderService.dispose();

    MediaPlaybackCoordinator.instance.unregisterChat(widget.chatId);
    ProximityAudioService.instance.unregisterOpenChat(widget.chatId);

    super.dispose();
  }

  Future<bool> _onRaiseToListenFirstUnplayed() async {
    if (!mounted || _isVoiceRecording || _isVideoRecording) return false;
    // Find the chronologically oldest unlistened incoming voice message
    for (int i = _messages.length - 1; i >= 0; i--) {
      final m = _messages[i];
      if (m.senderId != _currentUserId &&
          m.messageType == 'voice' &&
          !m.isListened) {
        final rawUrl = m.fileUrl ?? '';
        final resolvedUrl = AppConfig.resolveMediaUrl(rawUrl) ?? rawUrl;
        if (resolvedUrl.isEmpty) continue;

        final track = PlaybackTrack(
          messageId: m.id,
          chatId: widget.chatId,
          chatType: 'group',
          mediaType: 'voice',
          mediaUrl: resolvedUrl,
          senderName: m.senderName,
          chatTitle: widget.groupName,
          duration: m.duration != null && m.duration! > 0
              ? Duration(seconds: m.duration!)
              : null,
          waveform: m.waveform,
        );
        final remainingQueue = _buildPlaylistFrom(m.id);
        await MediaPlaybackCoordinator.instance.startPlayback(
          track: track,
          remainingQueue: remainingQueue,
          isIncomingUnplayed: true,
        );
        return true;
      }
    }
    return false;
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
            chatId: widget.chatId,
            chatType: 'group',
            mediaType: 'voice',
            mediaUrl: resolvedUrl,
            senderName: m.senderName,
            chatTitle: widget.groupName,
            duration: m.duration != null && m.duration! > 0 ? Duration(seconds: m.duration!) : null,
            waveform: m.waveform,
          ));
        } else if (m.isRound || (m.messageType == 'video' && m.isRound)) {
          playlist.add(PlaybackTrack(
            messageId: m.id,
            chatId: widget.chatId,
            chatType: 'group',
            mediaType: 'video_note',
            mediaUrl: resolvedUrl,
            senderName: m.senderName,
            chatTitle: widget.groupName,
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

  bool _inputHeightCheckScheduled = false;

  void _updateInputHeight() {
    if (_inputHeightCheckScheduled) return;
    _inputHeightCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _inputHeightCheckScheduled = false;
      if (!mounted) return;
      final RenderBox? renderBox =
          _inputKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize) {
        final newHeight = renderBox.size.height;
        if ((newHeight - _inputHeight).abs() > 0.5 && newHeight > 0) {
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
    final displayName = widget.groupName ?? (_groupName.isNotEmpty ? _groupName : 'Group');

    final tabBar = TabBar(
      controller: _tabController,
      tabs: const [
        Tab(text: 'Chat'),
        Tab(text: 'Members'),
      ],
    );

    final tabBarView = TabBarView(
      controller: _tabController,
      children: [
        _buildChatTab(),
        _buildMembersTab(),
      ],
    );

    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final bool isKeyboardVisible = bottomInset > 0;

    final int onlineCount = _participants.where((p) => p.isOnline).length;
    final String statusSubtitle;
    if (_isTyping && _typingUserName != null && _typingUserName!.isNotEmpty) {
      final String l10nKey;
      if (_typingAction == 'record_voice') {
        l10nKey = 'chat_user_recording_voice';
      } else if (_typingAction == 'record_round') {
        l10nKey = 'chat_user_recording_round';
      } else {
        l10nKey = 'chat_user_typing';
      }
      statusSubtitle = context.l10n
          .translate(l10nKey)
          .replaceAll('{name}', _typingUserName!);
    } else if (onlineCount >= 1) {
      statusSubtitle = context.l10n
          .translate('chat_status_members_and_online')
          .replaceAll('{count}', _participants.length.toString())
          .replaceAll('{online}', onlineCount.toString());
    } else {
      statusSubtitle = context.l10n
          .translate('chat_status_members_count')
          .replaceAll('{count}', _participants.length.toString());
    }

    return ChatScaffold(
      canPop: !_isSelectionMode && !_showEmojiPanel && !isKeyboardVisible && !_isVoiceRecording && !_isVideoRecording,
      onPopInvoked: (didPop, _) {
        if (!didPop) {
          if (_isSelectionMode) {
            _clearSelection();
          } else if (_showEmojiPanel) {
            _closeEmojiPanel();
          } else if (isKeyboardVisible) {
            FocusScope.of(context).unfocus();
          } else if (_isVideoRecording) {
            _onVideoRecordingCancelled();
          } else if (_isVoiceRecording) {
            _stopRecordingActionBroadcast();
            _voiceRecorderService.cancelRecording();
            setState(() => _isVoiceRecording = false);
          }
        }
      },
      appBar: Builder(
        builder: (context) {
          return FloatingGlassAppBar(
            name: displayName,
                avatarUrl: widget.groupAvatar ?? _groupAvatar,
                isOnline: false, // Group itself doesn't have online status
                statusText: statusSubtitle,
                statusColor: _isTyping
                    ? (Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF5CB8E6)
                        : Theme.of(context).colorScheme.primary)
                    : null,
                isChannel: false,
                isMuted: _isMuted,
                heroTag: displayName,
                profileScreenBuilder: (_) => GroupInfoScreen(
                  chatId: widget.chatId,
                  groupName: displayName,
                  groupAvatar: widget.groupAvatar ?? _groupAvatar,
                  heroTag: displayName,
                ),
                onBack: () => TilingLayoutController.popOrCloseChatTile(context),
                onTitleTap: () => Navigator.push(
                    context,
                    SwipeBackPageRoute(
                      builder: (_) => GroupInfoScreen(
                        chatId: widget.chatId,
                        groupName: displayName,
                        groupAvatar: widget.groupAvatar ?? _groupAvatar,
                        heroTag: displayName,
                      ),
                    )),
                onViewProfile: () => Navigator.push(
                    context,
                    SwipeBackPageRoute(
                      builder: (_) => GroupInfoScreen(
                        chatId: widget.chatId,
                        groupName: displayName,
                        groupAvatar: widget.groupAvatar ?? _groupAvatar,
                        heroTag: displayName,
                      ),
                    )),
                onVoiceCall: () {
                  /* TODO: Voice call */
                },
                onVideoCall: () {
                  /* TODO: Video call */
                },
                onSearch: () {
                  ChatActionsHelper.openSearch(
                    context: context,
                    chatId: widget.chatId,
                    chatName: displayName,
                  );
                },
                onToggleMute: () {
                  ChatActionsHelper.toggleMute(
                    chatId: widget.chatId,
                    currentMuted: _isMuted,
                    onMuteChanged: (newMuted) => setState(() => _isMuted = newMuted),
                  );
                },
                onClearHistory: () {
                  ChatActionsHelper.showClearHistoryDialog(
                    context: context,
                    chatId: widget.chatId,
                    onHistoryCleared: () {
                      if (mounted) {
                        setState(() {
                          _messages.clear();
                          _updateFeedItems();
                        });
                      }
                    },
                  );
                },
                onReport: () {
                  // TODO: Report dialog
                },
                isSelectionMode: _isSelectionMode,
                selectedCount: _selectedMessageIds.length,
                onCancelSelection: _clearSelection,
                onCopySelected: _copySelectedMessages,
                onForwardSelected: _forwardSelectedMessages,
                onDeleteSelected: _deleteSelectedMessages,
              );
        },
      ),
      body: Stack(
        children: [
          tabBarView,
          Positioned(
            top: MediaQuery.paddingOf(context).top + kFloatingAppBarTotalHeight,
            left: 0,
            right: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                MediaNotePlayerHeader(
                  chatId: widget.chatId,
                  onScrollToActive: () {
                    final activeId = VoicePlaybackService().activeMessageId ??
                        VideoNotePlaybackService().activeMessageId;
                    if (activeId != null) {
                      _scrollToMessage(activeId);
                    }
                  },
                ),
                const SizedBox(height: 8),
                Center(
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    decoration: BoxDecoration(
                      color: Theme.of(context)
                          .colorScheme
                          .surface
                          .withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: tabBar,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChatTab() {
    final topPadding = MediaQuery.of(context).padding.top +
        kToolbarHeight +
        kTextTabBarHeight +
        24.0;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    if (bottomInset > _keyboardHeight) {
      _keyboardHeight = bottomInset;
      _saveKeyboardHeight(bottomInset);
    }

    if (_isKeyboardRising && bottomInset >= _keyboardHeight - 10) {
      _transitionTimer?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isKeyboardRising) {
          _emojiPanelController.value = 0.0;
          setState(() {
            _showEmojiPanel = false;
            _isKeyboardRising = false;
          });
        }
      });
    } else if (_isKeyboardFalling && bottomInset == 0) {
      _transitionTimer?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isKeyboardFalling) {
          setState(() => _isKeyboardFalling = false);
        }
      });
    } else if (bottomInset > _lastBottomInset &&
        bottomInset > 50 &&
        _showEmojiPanel &&
        !_isKeyboardFalling) {
      if (!_isKeyboardRising) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_isKeyboardRising && _showEmojiPanel) {
            setState(() => _isKeyboardRising = true);
          }
        });
      }
    }

    // When system keyboard finishes closing on mobile and emoji panel is not open,
    // remove focus from the input field so the blinking cursor does not stay stuck.
    if (_isMobilePlatform &&
        _lastBottomInset > 0 &&
        bottomInset == 0 &&
        !_showEmojiPanel &&
        !_isKeyboardRising) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            !_showEmojiPanel &&
            !_isKeyboardRising &&
            MediaQuery.of(context).viewInsets.bottom == 0 &&
            _inputFocusNode.hasFocus) {
          _inputFocusNode.unfocus();
        }
      });
    }

    _lastBottomInset = bottomInset;
    final safeBottom = MediaQuery.paddingOf(context).bottom;

    return AnimatedBuilder(
      animation: _emojiPanelAnimation,
      builder: (context, _) {
        final animVal = _emojiPanelAnimation.value;
        final double effectiveBottom;
        if (_showEmojiPanel) {
          final targetPanelHeight = _keyboardHeight + safeBottom;
          final currentPanelHeight = safeBottom + (targetPanelHeight - safeBottom) * animVal;
          effectiveBottom = math.max(bottomInset, currentPanelHeight);
        } else {
          effectiveBottom = bottomInset > 0 ? bottomInset : safeBottom;
        }

        final messageList = ChatMessagesListView(
          isLoading: _isLoading,
          isLoadingMore: _isLoadingMore,
          itemCount: _feedItems.length,
          scrollController: _scrollController,
          topPadding: topPadding,
          bottomPadding: _inputHeight + effectiveBottom + 8,
          itemBuilder: (context, index) => _buildFeedItem(index),
        );

        return Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(
              child: Listener(
                onPointerDown: _handleChatPointerDown,
                onPointerMove: _handleChatPointerMove,
                onPointerUp: _handleChatPointerUp,
                onPointerCancel: _handleChatPointerCancel,
                behavior: HitTestBehavior.translucent,
                child: messageList,
              ),
            ),
            // Sticky date header (stays attached at the top of the chat reading area)
            Positioned(
              top: topPadding,
              left: 0,
              right: 0,
              child: Center(
                child: ValueListenableBuilder<StickyDateState>(
                  valueListenable: _stickyDateStateNotifier,
                  builder: (context, stickyState, _) {
                    return FloatingChatDateHeader(
                      key: _stickyDateSlotKey,
                      state: stickyState,
                      scrollListenable: _scrollController,
                      hiddenBySelectionMode: _isSelectionMode,
                      onTapDay: _openCalendarForDate,
                    );
                  },
                ),
              ),
            ),
            // Нижний scroll edge блюр: ПОД полем ввода (над сообщениями, но под полем ввода)
            ChatBottomScrollEdge(
              height: math.max(safeBottom + 52.0, 52.0),
            ),
            if (_showEmojiPanel)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                height: (_keyboardHeight + safeBottom) * animVal,
                child: ClipRect(
                  child: OverflowBox(
                    alignment: Alignment.topCenter,
                    minHeight: _keyboardHeight + safeBottom,
                    maxHeight: _keyboardHeight + safeBottom,
                    child: EmojiStickerPanel(
                      controller: _messageController,
                      onBackspace: _handleBackspace,
                      onClose: _closeEmojiPanel,
                      height: _keyboardHeight + safeBottom,
                      isVisible: _showEmojiPanel,
                    ),
                  ),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              bottom: effectiveBottom,
              child: Container(
                key: _inputKey,
                child: _buildMessageInput(),
              ),
            ),
            Positioned(
              right: 14,
              bottom: _inputHeight + 10 + effectiveBottom,
              child: ValueListenableBuilder<bool>(
                valueListenable: _showScrollDownFabNotifier,
                builder: (context, showFab, _) => ScrollDownFab(
                  visible: showFab,
                  unreadCount: _unreadCount,
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
                  onCancel: () {
                    _stopRecordingActionBroadcast();
                    setState(() => _isVoiceRecording = false);
                  },
                  onSend: (res) async {
                    _stopRecordingActionBroadcast();
                    setState(() => _isVoiceRecording = false);
                    await _sendVoiceMessage(res);
                  },
                  onTooShort: () {
                    _stopRecordingActionBroadcast();
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
    );
  }

  Widget _buildMembersTab() {
    if (_participants.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final glassEnabled = context.watch<LiquidGlassProvider>().enabled;
    final topPadding = glassEnabled
        ? MediaQuery.of(context).padding.top +
            kToolbarHeight +
            kTextTabBarHeight
        : 0.0;

    return ListView.builder(
      padding: EdgeInsets.only(
        top: topPadding,
        left: 8,
        right: 8,
        bottom: 8,
      ),
      itemCount: _participants.length,
      itemBuilder: (context, index) {
        final participant = _participants[index];
        final roleIcon = participant.role == 'owner'
            ? Icons.star
            : participant.role == 'admin'
                ? Icons.shield
                : null;

        return ListTile(
          leading: CircleAvatar(
            backgroundColor: const Color(0xFF0088CC),
            backgroundImage: getValidAvatarUrl(participant.avatarUrl) != null
                ? avatarImageProvider(participant.avatarUrl)
                : null,
            child: getValidAvatarUrl(participant.avatarUrl) == null
                ? Text(
                    participant.displayName.isNotEmpty
                        ? participant.displayName[0].toUpperCase()
                        : '?',
                    style: const TextStyle(color: Colors.white),
                  )
                : null,
          ),
          title: Text(participant.displayName),
          subtitle: Text('@${participant.username}'),
          trailing: roleIcon != null
              ? Icon(
                  roleIcon,
                  size: 18,
                  color:
                      participant.role == 'owner' ? Colors.amber : Colors.blue,
                )
              : null,
        );
      },
    );
  }

  Widget _buildFeedItem(int index) {
    if (index < 0 || index >= _feedItems.length) {
      return const SizedBox.shrink();
    }
    final item = _feedItems[index];
    if (item is FeedAlbumItem) {
      return _buildAlbumFeedItem(item.album, index);
    } else if (item is FeedSingleItem) {
      return _buildMessageItem(item.message, index);
    }
    return const SizedBox.shrink();
  }

  Widget _buildAlbumFeedItem(MediaAlbum album, int index) {
    final message = album.primaryMessage;
    final key = _messageKeys.putIfAbsent(message.id, () => GlobalKey());
    final bool isMe = message.senderId == _currentUserId;

    // Ensure all album item IDs map to this key so reply jumps locate the album
    for (final ai in album.items) {
      _messageKeys[ai.id] = key;
    }

    final bool isAlbumTargeted = _highlightMessageId == message.id ||
        album.items.any((ai) => ai.id == _highlightMessageId);
    final bool isSelected = _selectedMessageIds.contains(message.id);

    Widget albumWidget = MediaAlbumWidget(
      key: key,
      album: album,
      isMe: isMe,
      currentUserId: _currentUserId ?? '',
      chatType: 'group',
      senderName: isMe ? null : message.senderName,
      formatTime: _formatTime,
      onFileTap: (url, name, type) => _openFile(url, name, type),
      isHighlighted: isAlbumTargeted,
      highlightItemId: _highlightMessageId,
      isSelected: isSelected,
      isSelectionMode: _isSelectionMode,
    );

    albumWidget = SwipeToReplyWrapper(
      onReply: () => _startReply(message),
      enabled: !_isSelectionMode,
      child: albumWidget,
    );

    if (!isMe && !album.isRead) {
      final latestAlbumItemId = album.items.last.id;
      albumWidget = VisibleMessageDetector(
        messageId: latestAlbumItemId,
        onMessageSeen: () {
          for (final ai in album.items) {
            _onMessageVisible(ai.id);
          }
        },
        visibilityThreshold: 0.3,
        visibleDuration: const Duration(milliseconds: 300),
        child: albumWidget,
      );
    }

    final platform = Theme.of(context).platform;
    final bool isDesktop = platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS;

    albumWidget = Listener(
      onPointerDown: (event) =>
          _handleRowPointerDown(event, index, message, isMe, key),
      behavior: HitTestBehavior.translucent,
      child: GestureDetector(
        onTap: _isSelectionMode
            ? () => _toggleMessageSelection(message)
            : (isDesktop
                ? null
                : () {
                    _showContextMenu(message, isMe, key, enableBlur: true);
                  }),
        onLongPress: isDesktop
            ? null
            : () {
                _enterSelectionMode(message);
              },
        onSecondaryTapUp: (details) {
          if (_isSelectionMode) {
            _toggleMessageSelection(message);
            return;
          }
          final insideBubble = MessageBubble.isGlobalPointInsideBubble(
            key.currentContext,
            details.globalPosition,
          );
          _showContextMenu(
            message,
            isMe,
            key,
            forceOpen: true,
            enableBlur: insideBubble,
          );
        },
        behavior: HitTestBehavior.opaque,
        child: albumWidget,
      ),
    );

    albumWidget = ValueListenableBuilder<String?>(
      valueListenable: MessageContextMenuService().activeBlurMessageId,
      builder: (context, activeBlurId, child) {
        final isSeparatedForBlur = activeBlurId != null &&
            (activeBlurId == message.id ||
                album.items.any((ai) => ai.id == activeBlurId));
        return Visibility(
          visible: !isSeparatedForBlur,
          maintainSize: true,
          maintainAnimation: true,
          maintainState: true,
          child: child!,
        );
      },
      child: albumWidget,
    );

    final prevItem =
        index < _feedItems.length - 1 ? _feedItems[index + 1] : null;
    final (currentDt, currentDate) = _resolveDates(message.createdAt);
    final prevDate = prevItem != null ? _resolveDates(prevItem.createdAt).$2 : null;

    final items = <Widget>[];
    if (currentDate != prevDate) {
      final sepKey =
          _dateSeparatorKeys.putIfAbsent(currentDate, () => GlobalKey());
      items.add(
        InlineChatDateHeader(
          key: sepKey,
          day: currentDate,
          scrollListenable: _scrollController,
          stickySlotKey: _stickyDateSlotKey,
          stickyStateListenable: _stickyDateStateNotifier,
          child: DateSeparator(
            key: ValueKey<DateTime>(currentDate),
            dateLabel: _formatDateLabel(currentDt),
            onTap: () => _openCalendarForDate(currentDt),
          ),
        ),
      );
    }
    if (_showUnreadDivider && index == _firstUnreadFeedIndex) {
      items.add(
        UnreadSeparator(
          key: _unreadSeparatorKey,
        ),
      );
    }
    items.add(albumWidget);

    return RepaintBoundary(child: Column(children: items));
  }

  Widget _buildMessageItem(Message message, int index) {
    final bool isMe = message.senderId == _currentUserId;
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
    final isHighlighted = _highlightMessageId == message.id;
    final bool isSelected = _selectedMessageIds.contains(message.id);

    Widget messageWidget = MessageBubble(
      key: key,
      message: message,
      isMe: isMe,
      currentUserId: _currentUserId ?? '',
      senderName: isMe ? null : message.senderName,
      chatType: 'group',
      chatTitle: widget.groupName,
      isHighlighted: isHighlighted,
      isSelected: isSelected,
      isSelectionMode: _isSelectionMode,
      reactions: _messageReactions[message.id] ??
          (message.reactions.isNotEmpty ? message.reactions : null),
      myReactions: _myReactions[message.id] ??
          (message.myReactions.isNotEmpty ? message.myReactions : null),
      onReactionTap: (emoji) => _toggleReaction(message.id, emoji),
      onRetry: (msg) => _retryMessage(msg),
      onReplyTap: (replyToId, chatId) => _handleReplyTap(
        replyToId,
        chatId,
        fromMessageId: message.id,
      ),
      onFileTap: (url, name, type) => _openFile(url, name, type),
      formatTime: _formatTime,
    );

    if (!isMe && !message.isRead) {
      messageWidget = VisibleMessageDetector(
        messageId: message.id,
        onMessageSeen: () => _onMessageVisible(message.id),
        visibilityThreshold: 0.3,
        visibleDuration: const Duration(milliseconds: 300),
        child: messageWidget,
      );
    }

    messageWidget = SwipeToReplyWrapper(
      onReply: () => _startReply(message),
      enabled: !_isSelectionMode,
      child: messageWidget,
    );

    final platform = Theme.of(context).platform;
    final bool isDesktop = platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS;

    messageWidget = Listener(
      onPointerDown: (event) =>
          _handleRowPointerDown(event, index, message, isMe, key),
      behavior: HitTestBehavior.translucent,
      child: GestureDetector(
        onTap: _isSelectionMode
            ? () => _toggleMessageSelection(message)
            : (isDesktop
                ? null
                : () {
                    _showContextMenu(message, isMe, key, enableBlur: true);
                  }),
        onLongPress: isDesktop
            ? null
            : () {
                _enterSelectionMode(message);
              },
        onSecondaryTapUp: (details) {
          if (_isSelectionMode) {
            _toggleMessageSelection(message);
            return;
          }
          final insideBubble = MessageBubble.isGlobalPointInsideBubble(
            key.currentContext,
            details.globalPosition,
          );
          _showContextMenu(
            message,
            isMe,
            key,
            forceOpen: true,
            enableBlur: insideBubble,
          );
        },
        behavior: HitTestBehavior.opaque,
        child: messageWidget,
      ),
    );

    messageWidget = ValueListenableBuilder<String?>(
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

    final prevItem =
        index < _feedItems.length - 1 ? _feedItems[index + 1] : null;
    final (currentDt, currentDate) = _resolveDates(message.createdAt);
    final prevDate = prevItem != null ? _resolveDates(prevItem.createdAt).$2 : null;

    final items = <Widget>[];
    if (currentDate != prevDate) {
      final sepKey =
          _dateSeparatorKeys.putIfAbsent(currentDate, () => GlobalKey());
      items.add(
        InlineChatDateHeader(
          key: sepKey,
          day: currentDate,
          scrollListenable: _scrollController,
          stickySlotKey: _stickyDateSlotKey,
          stickyStateListenable: _stickyDateStateNotifier,
          child: DateSeparator(
            key: ValueKey<DateTime>(currentDate),
            dateLabel: _formatDateLabel(currentDt),
            onTap: () => _openCalendarForDate(currentDt),
          ),
        ),
      );
    }
    if (_showUnreadDivider && index == _firstUnreadFeedIndex) {
      items.add(
        UnreadSeparator(
          key: _unreadSeparatorKey,
        ),
      );
    }
    items.add(messageWidget);

    return RepaintBoundary(child: Column(children: items));
  }

  Widget _buildMessageInput() {
    return ChatInputBar(
      controller: _messageController,
      focusNode: _inputFocusNode,
      isEditing: _isEditing,
      onCancelEditing: _cancelEditing,
      onEditLastMessage: _editLastOwnMessage,
      isEmojiPanelOpen: _showEmojiPanel && !_isKeyboardRising,
      onTapInputWhenEmojiOpen: _onEmojiToggle,
      replyToMessage: _replyToMessage,
      isQuote: _isQuote,
      quoteText: _quoteText,
      quoteOffset: _quoteOffset,
      quoteLength: _quoteLength,
      onCancelReply: _cancelReply,
      onTapReply: _replyToMessage != null
          ? () => _scrollToMessage(_replyToMessage!.id)
          : null,
      attachedFiles: _attachedFiles,
      attachedFileNames: _attachedFileNames,
      onRemoveAttachment: _removeAttachedFile,
      isUploading: _isUploading,
      uploadProgress: _uploadProgress,
      uploadProgressNotifier: _uploadProgressNotifier,
      onAttach: _showAttachmentPicker,
      onEmoji: _onEmojiToggle,
      onChanged: _onInputTextChanged,
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

  bool _isVideoPointerDown = false;
  bool _isVoicePointerDown = false;

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
    _startRecordingActionBroadcast('record_round');
    final ok = await _videoRecorderService.startRecording();
    if (!_isVideoPointerDown && ok) {
      await _videoRecorderService.cancelRecording();
      if (mounted) {
        _onVideoRecordingTooShort();
      }
      return;
    }
    if (!ok && mounted) {
      _stopRecordingActionBroadcast();
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
    _stopRecordingActionBroadcast();
    _videoRecorderService.cancelRecording();
    setState(() => _isVideoRecording = false);
  }

  void _onVideoRecordingCancelled() {
    _stopRecordingActionBroadcast();
    setState(() => _isVideoRecording = false);
  }

  void _onVideoRecordingTooShort() {
    _stopRecordingActionBroadcast();
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
    _stopRecordingActionBroadcast();
    setState(() => _isVideoRecording = false);
    await _sendRoundVideoMessage(file);
  }

  Future<void> _onStartVoiceRecord() async {
    _isVoicePointerDown = true;
    _dismissKeyboardAndEmoji();
    final hasPerm = await _voiceRecorderService.hasPermission();
    if (!hasPerm) {
      _isVoicePointerDown = false;
      final isPermanentlyDenied = await _voiceRecorderService.isPermanentlyDenied();
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
      _startRecordingActionBroadcast('record_voice');
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
    _stopRecordingActionBroadcast();
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
          chatId: widget.chatId,
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
        debugPrint('SyncService createPendingMessage voice error: $e');
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
            _updateFeedItems();
          });
          _scrollToBottom();
        }
      }

      // 2. Upload voice file to MinIO storage
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

      // 3. Send message via ChatService
      final sendResult = await ChatService.sendMessage(
        chatId: widget.chatId,
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
                _updateFeedItems();
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
                _updateFeedItems();
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Voice message send error: $e');
      if (pendingLocalId != null) {
        await syncService.markMessageFailed(pendingLocalId);
        if (mounted) {
          setState(() {
            final idx =
                _messages.indexWhere((m) => m.localId == pendingLocalId);
            if (idx != -1) {
              _messages[idx] = _messages[idx].copyWith(sendStatus: 2);
              _updateFeedItems();
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

    final recordedDurationSec = math.max(1, _videoRecorderService.elapsed.inSeconds);
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
      // 1. Immediately create pending message with local file path for instant preview
      try {
        pendingMsg = await syncService.createPendingMessage(
          chatId: widget.chatId,
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
        debugPrint('SyncService createPendingMessage error: $e');
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
            _updateFeedItems();
          });
          _scrollToBottom();
        }
      }

      // 2. Upload file to MinIO storage
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

      // 3. Send message via ChatService
      final result = await ChatService.sendMessage(
        chatId: widget.chatId,
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
                _updateFeedItems();
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
                _updateFeedItems();
              }
            });
          }
        }
      }
    } catch (e) {
      debugPrint('Error sending round video message in group chat: $e');
      if (pendingLocalId != null) {
        await syncService.markMessageFailed(pendingLocalId);
        if (mounted) {
          setState(() {
            final idx =
                _messages.indexWhere((m) => m.localId == pendingLocalId);
            if (idx != -1) {
              _messages[idx] = _messages[idx].copyWith(sendStatus: 2);
              _updateFeedItems();
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

  /// Toggle reaction on a message — optimistic update + API call with rollback
  void _toggleReaction(String messageId, String emoji) {
    final previousMyReactions = Set<String>.from(_myReactions[messageId] ?? {});
    final previousReactions = Map<String, int>.from(_messageReactions[messageId] ?? {});

    setState(() {
      final mySet = _myReactions.putIfAbsent(messageId, () => <String>{});
      final reactions = _messageReactions.putIfAbsent(messageId, () => <String, int>{});

      final isCurrentlySelected = mySet.contains(emoji);
      if (isCurrentlySelected) {
        mySet.remove(emoji);
        if (mySet.isEmpty) {
          _myReactions.remove(messageId);
        }
        reactions[emoji] = (reactions[emoji] ?? 1) - 1;
        if (reactions[emoji]! <= 0) {
          reactions.remove(emoji);
        }
      } else {
        mySet.add(emoji);
        reactions[emoji] = (reactions[emoji] ?? 0) + 1;
      }

      final idx = _messages.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(
          reactions: Map.from(reactions),
          myReactions: Set.from(mySet),
        );
        _updateFeedItems();
      }
    });

    try {
      AppDatabase().updateMessageReactions(
        messageId,
        _messageReactions[messageId] ?? {},
        _myReactions[messageId] ?? {},
      );
    } catch (e) {
      debugPrint('GroupChatScreen: error saving reactions to DB: $e');
    }

    _sendReactionToggle(messageId, emoji, previousMyReactions, previousReactions);
  }

  Future<void> _sendReactionToggle(
    String messageId,
    String emoji,
    Set<String> previousMyReactions,
    Map<String, int> previousReactions,
  ) async {
    try {
      final res = await ChatService.toggleReaction(
        chatId: widget.chatId,
        messageId: messageId,
        emoji: emoji,
      );
      if (res['success'] != true) {
        debugPrint(
            'GroupChatScreen: toggleReaction returned success=false for msg=$messageId: ${res['message']}');
        _rollbackReaction(messageId, previousMyReactions, previousReactions);
      }
    } catch (e) {
      debugPrint('GroupChatScreen: toggleReaction exception: $e');
      _rollbackReaction(messageId, previousMyReactions, previousReactions);
    }
  }

  void _rollbackReaction(
    String messageId,
    Set<String> previousMyReactions,
    Map<String, int> previousReactions,
  ) {
    if (!mounted) return;
    setState(() {
      if (previousMyReactions.isEmpty) {
        _myReactions.remove(messageId);
      } else {
        _myReactions[messageId] = Set.from(previousMyReactions);
      }

      if (previousReactions.isEmpty) {
        _messageReactions.remove(messageId);
      } else {
        _messageReactions[messageId] = Map.from(previousReactions);
      }

      final idx = _messages.indexWhere((m) => m.id == messageId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(
          reactions: Map.from(_messageReactions[messageId] ?? {}),
          myReactions: Set.from(_myReactions[messageId] ?? {}),
        );
        _updateFeedItems();
      }
    });

    try {
      AppDatabase().updateMessageReactions(
        messageId,
        _messageReactions[messageId] ?? {},
        _myReactions[messageId] ?? {},
      );
    } catch (_) {}
  }

  List<String> _resolveSelectionIdsForMessage(Message message) {
    final gId = message.groupedId;
    if (gId != null && gId.isNotEmpty) {
      final albumIds = _messages
          .where((m) => m.groupedId == gId)
          .map((m) => m.id)
          .toList();
      if (albumIds.isNotEmpty) return albumIds;
    }
    return [message.id];
  }

  void _enterSelectionMode(Message message) {
    _dismissKeyboardAndEmoji();
    HapticUtils.selection();
    final ids = _resolveSelectionIdsForMessage(message);
    setState(() {
      _selectedMessageIds.addAll(ids);
    });
  }

  void _toggleMessageSelection(Message message) {
    HapticUtils.selection();
    final ids = _resolveSelectionIdsForMessage(message);
    setState(() {
      if (_selectedMessageIds.contains(message.id)) {
        _selectedMessageIds.removeAll(ids);
      } else {
        _selectedMessageIds.addAll(ids);
      }
    });
  }

  void _clearSelection() {
    if (_selectedMessageIds.isEmpty) return;
    setState(() {
      _selectedMessageIds.clear();
      _isLmbDraggingMessages = false;
      _dragSelectStartIndex = null;
      _dragSelectBaselineIds.clear();
    });
  }

  void _copySelectedMessages() {
    if (_selectedMessageIds.isEmpty) return;
    final selected = _messages
        .where((m) => _selectedMessageIds.contains(m.id) && m.content.trim().isNotEmpty)
        .toList()
        .reversed
        .map((m) => m.content.trim())
        .toList();
    if (selected.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: selected.join('\n\n')));
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
    if (_selectedMessageIds.isEmpty) return;
    final toDelete = _messages
        .where((m) => _selectedMessageIds.contains(m.id))
        .toList();
    _clearSelection();
    if (toDelete.isEmpty) return;
    for (final msg in toDelete) {
      _confirmDeleteMessage(msg);
    }
  }

  void _handleChatPointerDown(PointerDownEvent event) {
    _touchDownPos = event.position;
    _touchDownTime = event.timeStamp;
    _lastTouchPos = event.position;
    _lastTouchTime = event.timeStamp;
    _touchVelocityY = 0.0;
    _dismissedOnCurrentTouch = false;
  }

  void _handleRowPointerDown(
    PointerDownEvent event,
    int feedIndex,
    Message message,
    bool isMe,
    GlobalKey key,
  ) {
    _touchDownInsideBubble = MessageBubble.isGlobalPointInsideBubble(
      key.currentContext,
      event.position,
    );
    if (event.kind != PointerDeviceKind.mouse ||
        (event.buttons & kPrimaryMouseButton) == 0) {
      return;
    }
    _lmbDownGlobalPos = event.position;
    _lmbDownFeedIndex = feedIndex;
    _lmbDownMessage = message;
    _lmbDownKey = key;
    _lmbDownIsMe = isMe;
    _lmbDownInsideBubble = _touchDownInsideBubble;
    _lmbDownInsideText = MessageBubble.isGlobalPointInsideSelectableText(
      key.currentContext,
      event.position,
    );
    _isLmbDraggingMessages = false;
    _isLmbDirectTextSelecting = false;
  }

  int? _findFeedIndexAtGlobalPosition(Offset globalPos) {
    int? closestIndex;
    double closestDist = double.infinity;
    for (int i = 0; i < _feedItems.length; i++) {
      final item = _feedItems[i];
      final key = _messageKeys[item.id];
      final box = key?.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize || !box.attached) continue;
      final topLeft = box.localToGlobal(Offset.zero);
      final top = topLeft.dy;
      final bottom = top + box.size.height;
      if (globalPos.dy >= top && globalPos.dy <= bottom) {
        return i;
      }
      final dist = globalPos.dy < top ? (top - globalPos.dy) : (globalPos.dy - bottom);
      if (dist < closestDist) {
        closestDist = dist;
        closestIndex = i;
      }
    }
    return closestIndex;
  }

  List<String> _feedItemAllIds(int index) {
    final item = _feedItems[index];
    if (item is FeedAlbumItem) {
      return item.album.items.map((ai) => ai.id).toList();
    } else if (item is FeedSingleItem) {
      return [item.message.id];
    }
    return [item.id];
  }

  void _handleChatPointerMove(PointerMoveEvent event) {
    // Mobile fast-scroll detection: dismiss keyboard/emoji panel ONLY on fast vertical scroll
    if (_isMobilePlatform &&
        event.kind == PointerDeviceKind.touch &&
        !_dismissedOnCurrentTouch &&
        _touchDownPos != null &&
        _lastTouchPos != null &&
        _lastTouchTime != null) {
      final dtMicros = (event.timeStamp - _lastTouchTime!).inMicroseconds;
      if (dtMicros > 0) {
        final dy = (event.position.dy - _lastTouchPos!.dy).abs();
        final instVelY = (dy * 1000000.0) / dtMicros;
        _touchVelocityY = _touchVelocityY * 0.35 + instVelY * 0.65;
      }
      _lastTouchPos = event.position;
      _lastTouchTime = event.timeStamp;

      final totalDy = (event.position.dy - _touchDownPos!.dy).abs();
      final totalDx = (event.position.dx - _touchDownPos!.dx).abs();
      if (totalDy > 42.0 &&
          totalDy > totalDx * 1.8 &&
          _touchVelocityY > 1250.0) {
        final kbOpen = MediaQuery.of(context).viewInsets.bottom > 0;
        if (kbOpen || _showEmojiPanel || _inputFocusNode.hasFocus) {
          _dismissedOnCurrentTouch = true;
          _dismissKeyboardAndEmoji();
        }
      }
    }

    if (_lmbDownGlobalPos == null) return;
    if ((event.buttons & kPrimaryMouseButton) == 0) {
      _resetLmbDragState();
      return;
    }

    final dist = (event.position - _lmbDownGlobalPos!).distance;

    // 1. Direct text selection with blur when LMB drag starts on message text
    if (_lmbDownInsideText && !_isSelectionMode) {
      if (dist > 4.0) {
        if (!_isLmbDirectTextSelecting &&
            _lmbDownMessage != null &&
            _lmbDownKey != null) {
          _isLmbDirectTextSelecting = true;
          _showContextMenu(
            _lmbDownMessage!,
            _lmbDownIsMe,
            _lmbDownKey!,
            forceOpen: true,
            enableBlur: true,
            initialDragStartGlobalPosition: _lmbDownGlobalPos,
            initialDragCurrentGlobalPosition: event.position,
          );
        } else if (_isLmbDirectTextSelecting) {
          MessageContextMenuService().updateExternalDragSelection(event.position);
        }
      }
      return;
    }

    // 2. Consecutive message drag-selection when LMB drag starts beside the bubble (or in selection mode)
    if ((!_lmbDownInsideBubble || _isSelectionMode) &&
        _lmbDownFeedIndex != null &&
        _lmbDownMessage != null) {
      if (dist > 6.0) {
        if (!_isLmbDraggingMessages) {
          _isLmbDraggingMessages = true;
          _dragSelectStartIndex = _lmbDownFeedIndex;
          _dragSelectBaselineIds = Set<String>.from(_selectedMessageIds);
          _dragSelectTargetState =
              !_dragSelectBaselineIds.contains(_lmbDownMessage!.id);
          HapticUtils.selection();
        }
        final currentIndex =
            _findFeedIndexAtGlobalPosition(event.position) ?? _lmbDownFeedIndex!;
        final startIdx = math.min(_dragSelectStartIndex!, currentIndex);
        final endIdx = math.max(_dragSelectStartIndex!, currentIndex);

        final updated = Set<String>.from(_dragSelectBaselineIds);
        for (int i = startIdx; i <= endIdx; i++) {
          if (i >= 0 && i < _feedItems.length) {
            final msgIds = _feedItemAllIds(i);
            if (_dragSelectTargetState) {
              updated.addAll(msgIds);
            } else {
              updated.removeAll(msgIds);
            }
          }
        }
        if (updated.length != _selectedMessageIds.length ||
            !updated.containsAll(_selectedMessageIds)) {
          HapticUtils.selection();
          setState(() {
            _selectedMessageIds
              ..clear()
              ..addAll(updated);
          });
        }
      }
    }
  }

  void _handleChatPointerUp(PointerUpEvent event) {
    if (_touchDownPos != null && _touchDownTime != null) {
      final dist = (event.position - _touchDownPos!).distance;
      final elapsedMs = (event.timeStamp - _touchDownTime!).inMilliseconds;
      final isShortTap = dist < 12.0 && elapsedMs < 320;
      if (isShortTap && !_isSelectionMode && !_isLmbDirectTextSelecting && !_isLmbDraggingMessages) {
        if (_isMobilePlatform) {
          if (!_touchDownInsideBubble) {
            final kbOpen = MediaQuery.of(context).viewInsets.bottom > 0;
            if (kbOpen || _showEmojiPanel || _inputFocusNode.hasFocus) {
              _dismissKeyboardAndEmoji();
            }
          }
        } else if (_showEmojiPanel) {
          _closeEmojiPanel();
        }
      }
    }
    _touchDownPos = null;
    _touchDownTime = null;
    _lastTouchPos = null;
    _lastTouchTime = null;
    _touchVelocityY = 0.0;
    _dismissedOnCurrentTouch = false;
    _touchDownInsideBubble = false;

    if (_isLmbDirectTextSelecting) {
      _isLmbDirectTextSelecting = false;
      MessageContextMenuService().endExternalDragSelection();
    }
    _resetLmbDragState();
  }

  void _handleChatPointerCancel(PointerCancelEvent event) {
    _touchDownPos = null;
    _touchDownTime = null;
    _lastTouchPos = null;
    _lastTouchTime = null;
    _touchVelocityY = 0.0;
    _dismissedOnCurrentTouch = false;
    _touchDownInsideBubble = false;

    if (_isLmbDirectTextSelecting) {
      _isLmbDirectTextSelecting = false;
      MessageContextMenuService().endExternalDragSelection();
    }
    _resetLmbDragState();
  }

  void _resetLmbDragState() {
    _lmbDownGlobalPos = null;
    _lmbDownFeedIndex = null;
    _lmbDownMessage = null;
    _lmbDownKey = null;
    _isLmbDraggingMessages = false;
    _dragSelectStartIndex = null;
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
    final bool isGroupAdmin = _participants.any(
      (p) => p.id == _currentUserId && (p.role == 'owner' || p.role == 'admin'),
    );

    MessageContextMenuService().show(
      context: context,
      message: message,
      messageKey: key,
      isMe: isMe,
      currentUserId: _currentUserId,
      canManagePoll: isMe || isGroupAdmin,
      enableBlur: enableBlur,
      initialDragStartGlobalPosition: initialDragStartGlobalPosition,
      initialDragCurrentGlobalPosition: initialDragCurrentGlobalPosition,
      onPollUpdated: (updatedPoll) {
        if (!mounted) return;
        setState(() {
          final idx = _messages.indexWhere((m) => m.id == message.id);
          if (idx != -1) {
            _messages[idx] = _messages[idx].copyWith(mediaPayload: updatedPoll);
            _updateFeedItems();
          }
        });
      },
      onReply: () => _startReply(message),
      onQuote: (isVideoNote || isVoiceNote || isPoll) ? null : () => _startQuote(message, message.content, 0, message.content.length),
      onQuotePartial: (isVideoNote || isVoiceNote || isPoll)
          ? null
          : (selectedText, offset, length) =>
              _startQuote(message, selectedText, offset, length),
      onPin: () {},
      onEdit: (isVideoNote || isVoiceNote || isPoll) ? null : () {
        setState(() {
          _cancelReply();
          _messageController.loadMessage(message.content, message.entities);
          _isEditing = true;
          _editingMessageId = message.id;
        });
        _focusInputField();
      },
      onSelect: () => _enterSelectionMode(message),
      onDelete: (msg) => _confirmDeleteMessage(msg),
      onReaction: (msgId, emoji) => _toggleReaction(msgId, emoji),
      selectedEmojis: _myReactions[message.id] ?? message.myReactions,
    );
  }

  void _confirmDeleteMessage(Message message) {
    final deletedIndex = _messages.indexWhere((m) => m.id == message.id);
    ChatActionsHelper.confirmAndDeleteMessage(
      context: context,
      chatId: widget.chatId,
      message: message,
      onOptimisticDelete: () {
        if (mounted) {
          setState(() {
            _messages.removeWhere((m) => m.id == message.id);
            _updateFeedItems();
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
            _updateFeedItems();
          });
        }
      },
    );
  }

  /// Called when a message becomes visible — queues message for debounced read-up-to
  void _onMessageVisible(String messageId) {
    if (_pendingMarkRead.contains(messageId)) return;
    _pendingMarkRead.add(messageId);

    _markReadTimer?.cancel();
    _markReadTimer = Timer(const Duration(milliseconds: 300), () {
      _flushMarkRead();
    });
  }

  Future<void> _flushMarkRead() async {
    if (_pendingMarkRead.isEmpty || _isMarkingRead) return;
    _isMarkingRead = true;

    try {
      String? latestMessageId;
      int latestIndex = -1;
      for (final id in _pendingMarkRead) {
        final idx = _messages.indexWhere((m) => m.id == id);
        if (idx != -1 && idx < (latestIndex == -1 ? 999999 : latestIndex)) {
          latestIndex = idx;
          latestMessageId = id;
        }
      }

      _pendingMarkRead.clear();

      if (latestMessageId == null) return;

      final result = await ChatService.markMessagesReadUpTo(
        chatId: widget.chatId,
        messageId: latestMessageId,
      );

      final markedCount = result['marked_count'] as int? ?? 0;
      if (markedCount > 0) {
        _wsService.sendMessageRead(widget.chatId, markedCount: markedCount);

        if (mounted) {
          setState(() {
            _unreadCount = (_unreadCount - markedCount).clamp(0, _unreadCount);
            if (latestIndex != -1) {
              for (int i = latestIndex; i < _messages.length; i++) {
                if (_messages[i].senderId != _currentUserId &&
                    !_messages[i].isRead) {
                  _messages[i] = _messages[i].copyWith(isRead: true);
                }
              }
              _updateFeedItems();
            }
          });
          final provider = context.read<UnreadCountProvider>();
          provider.decrement(widget.chatId, markedCount);
        }
      }
    } finally {
      _isMarkingRead = false;
      if (_pendingMarkRead.isNotEmpty && mounted) {
        _markReadTimer?.cancel();
        _markReadTimer = Timer(const Duration(milliseconds: 300), () {
          _flushMarkRead();
        });
      }
    }
  }
}
