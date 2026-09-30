import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/services.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/chat_service.dart';
import '../../services/auth_service.dart';
import '../../services/websocket_service.dart';
import '../../services/file_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/unread_count_provider.dart';
import '../../services/sync_service.dart';
import '../../services/notification_service.dart';
import '../../services/profile_theme_provider.dart';
import '../../utils/emoji_utils.dart';
import '../../services/database/app_database.dart';
import '../../l10n/app_localizations.dart';
import 'package:drift/drift.dart' show Value;
import '../../widgets/chat/liquid_glass_input_field.dart';
import '../../widgets/chat/floating_glass_app_bar.dart';
import '../../widgets/chat/chat_scaffold.dart';
import '../../widgets/chat/chat_input_bar.dart';
import '../../widgets/chat/visible_message_detector.dart';
import '../../widgets/chat/swipe_to_reply_wrapper.dart';
import '../../widgets/chat/unread_separator.dart';
import '../../widgets/chat/emoji_sticker_panel.dart';
import '../../widgets/message/fullscreen_photo_viewer.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../services/message_context_menu_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/wallpaper_provider.dart';
import '../../widgets/message/message_bubble.dart';
import 'package:uuid/uuid.dart';
import '../../models/media_album.dart';
import '../../widgets/message/media_album_widget.dart';
import '../../utils/swipe_back_route.dart';
import '../../utils/entity_parser.dart';
import 'group_chat_screen.dart';
import 'channel_screen.dart';
import '../../utils/date_time_utils.dart';
import '../../services/video_note_recorder_service.dart';
import '../../widgets/chat/round_video_recording_overlay.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:video_player/video_player.dart';
import '../../config/app_config.dart';
import '../../services/video_note_playback_service.dart';
import '../../widgets/chat/floating_video_note_overlay.dart';
import '../../widgets/message/video_message_widget.dart';
import '../../services/voice_note_recorder_service.dart';
import '../../services/voice_playback_service.dart';
import '../../widgets/chat/voice_recording_overlay.dart';
import '../../widgets/chat/media_note_player_header.dart';
import 'package:path/path.dart' as p;
import '../../widgets/chat/attachment_picker_bottom_sheet.dart';
import 'media_send_screen.dart';
import 'poll_create_screen.dart';

class PrivateChatScreen extends StatefulWidget {
  final String chatId;
  final String? otherUserName;
  final String? otherUserAvatar;
  final String? initialMessageId;
  final bool? otherUserOnline;
  final DateTime? otherUserLastSeen;
  final String? otherUserId;

  const PrivateChatScreen({
    Key? key,
    required this.chatId,
    this.otherUserName,
    this.otherUserAvatar,
    this.initialMessageId,
    this.otherUserOnline,
    this.otherUserLastSeen,
    this.otherUserId,
  }) : super(key: key);

  @override
  State<PrivateChatScreen> createState() => _PrivateChatScreenState();
}

class _PrivateChatScreenState extends State<PrivateChatScreen> {
  final List<Message> _messages = [];
  final MarkdownTextEditingController _textController = MarkdownTextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _inputFocusNode = FocusNode();
  bool _isLoading = true;
  bool _isSending = false;
  String? _currentUserId;
  String _chatName = '';
  String? _chatAvatar;
  String? _otherUserId;
  String _chatType = 'private'; // 'private', 'saved'
  bool _isOtherUserOnline = false;
  DateTime? _otherUserLastSeen;
  bool _isSearchMode = false;
  bool _showEmojiPanel = false;
  bool _isKeyboardRising = false;
  bool _isKeyboardFalling = false;
  double _keyboardHeight = 280.0; // Better default height for most devices
  double _lastBottomInset = 0;
  Timer? _transitionTimer;
  int _searchCurrentIndex = 0;
  int _searchTotalCount = 0;
  String _searchQuery = '';
  final Map<String, Map<String, int>> _messageReactions = {}; // msgId → {emoji → count}
  final Map<String, Set<String>> _myReactions = {}; // msgId → Set<emoji>
  bool _showScrollDownFab = false;
  double _lastScrollOffset = 0;
  double _accumulatedScrollDown = 0;
  double _accumulatedScrollUp = 0;
  List<int> _searchResultIndices = []; // indices of messages matching search
  final List<String> _jumpHistory = [];

  // Unread messages tracking
  String?
      _firstUnreadMessageId; // ID of the oldest unread message (divider anchor)
  int _unreadCount = 0; // Number of unread messages in this chat
  bool _hasScrolledToUnread =
      false; // Whether we've scrolled to the unread area
  bool _showUnreadDivider =
      false; // Show unread divider (persists until user leaves chat)
  int _dividerUnreadCount = 0; // Count shown in divider (frozen at entry time)
  final Set<String> _pendingMarkRead =
      {}; // Messages queued to be marked as read (debounced)
  Timer? _markReadTimer; // Debounce timer for batch mark-as-read
  bool _isMarkingRead = false; // Prevent concurrent mark-as-read calls

  // WebSocket
  final WebSocketService _wsService = WebSocketService();
  StreamSubscription<WebSocketEvent>? _wsSubscription;
  bool _isTyping = false;
  Timer? _typingTimer;
  // ignore: unused_field
  String? _typingUserId;

  // File attachment
  final FileService _fileService = FileService();
  final ImagePicker _imagePicker = ImagePicker();
  final List<File> _attachedFiles = [];
  final List<String> _attachedFileNames = [];
  double _uploadProgress = 0.0;
  bool _isUploading = false;

  List<FeedItem> get _feedItems =>
      groupMessagesIntoFeedItems(_messages, isReversed: true);

  bool _isVideoFile(String filePath) {
    final clean = filePath.split('?').first.toLowerCase();
    return clean.endsWith('.mp4') ||
        clean.endsWith('.mov') ||
        clean.endsWith('.avi') ||
        clean.endsWith('.mkv') ||
        clean.endsWith('.webm');
  }

  bool _isImageFile(String filePath) {
    final clean = filePath.split('?').first.toLowerCase();
    return clean.endsWith('.jpg') ||
        clean.endsWith('.jpeg') ||
        clean.endsWith('.png') ||
        clean.endsWith('.webp') ||
        clean.endsWith('.heic') ||
        clean.endsWith('.gif') ||
        clean.endsWith('.bmp');
  }

  bool _isMediaFile(String filePath) =>
      _isImageFile(filePath) || _isVideoFile(filePath);

  // Reply / Quote state
  Message? _replyToMessage;     // Message being replied to
  bool _isQuote = false;        // Whether this is a quote (partial text)
  String? _quoteText;           // Selected text for quote
  int _quoteOffset = 0;         // Offset of quote in original message
  int _quoteLength = 0;         // Length of quoted fragment
  String? _highlightMessageId;  // Message ID to highlight (scroll-to)
  Timer? _highlightTimer;       // Timer to clear highlight

  // Editing state
  bool _isEditing = false;
  String? _editingMessageId;

  // GlobalKeys for messages to allow precise scrolling
  final Map<String, GlobalKey> _messageKeys = {};
  final GlobalKey _inputKey = GlobalKey();
  double _inputHeight = 90.0;

  // Video Note («Кружочки») state
  final VideoNoteRecorderService _videoRecorderService = VideoNoteRecorderService();
  final GlobalKey _videoOverlayKey = GlobalKey();
  bool _isVideoRecording = false;

  // Voice Note («Голосовые сообщения») state
  final VoiceNoteRecorderService _voiceRecorderService = VoiceNoteRecorderService();
  final GlobalKey _voiceOverlayKey = GlobalKey();
  bool _isVoiceRecording = false;

  // Пагинация
  bool _hasMoreMessages = true;
  bool _isLoadingMore = false;

  @override
  void initState() {
    super.initState();
    if (widget.otherUserOnline != null) {
      _isOtherUserOnline = widget.otherUserOnline!;
    }
    if (widget.otherUserLastSeen != null) {
      _otherUserLastSeen = widget.otherUserLastSeen;
    }
    if (widget.otherUserId != null) {
      _otherUserId = widget.otherUserId;
    }
    _loadData();
    _initWebSocket();
    _scrollController.addListener(_onScroll);
    _inputFocusNode.addListener(_onFocusChanged);

    // Connect continuous video note playback and PiP callbacks
    VideoNotePlaybackService().onPlayNextRequested = _playNextVideoNote;
    VideoNotePlaybackService().onScrollToMessageRequested = (id) => _scrollToMessage(id);

    // Connect continuous voice note playback
    VoicePlaybackService().onPlayNextRequested = _playNextVoiceNote;
    VoicePlaybackService().onScrollToMessageRequested = (id) => _scrollToMessage(id);

    // Notify provider that this chat is open (so unread count is not incremented)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        context.read<UnreadCountProvider>().setOpenChat(widget.chatId);
      } catch (_) {}
      NotificationService().cancelChatNotifications(widget.chatId, chatTitle: widget.otherUserName);
    });
  }

  void _onFocusChanged() {
    if (_inputFocusNode.hasFocus && _showEmojiPanel) {
      setState(() {
        _isKeyboardRising = true;
      });
    }
  }

  void _initWebSocket() {
    // Subscribe to WebSocket events for this chat
    // Note: We only use eventStream.listen, not subscribe() to avoid duplicate handling
    _wsSubscription = _wsService.eventStream.listen(_handleWebSocketEvent);
  }

  Future<void> _saveKeyboardHeight(double height) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble('keyboard_height', height);
    } catch (e) {
      debugPrint('Error saving keyboard height: $e');
    }
  }

  void _handleWebSocketEvent(WebSocketEvent event) {
    // Handle events specific to this chat
    if (event.type == WebSocketEventType.newMessage) {
      final chatId = event.data['chat_id']?.toString();
      if (chatId == widget.chatId) {
        _onNewMessage(event);
      }
    } else if (event.type == WebSocketEventType.messageRead) {
      final chatId = event.data['chat_id']?.toString();
      if (chatId == widget.chatId) {
        _onMessageRead(event);
      }
    } else if (event.type == WebSocketEventType.typing) {
      final chatId = event.data['chat_id']?.toString();
      if (chatId == widget.chatId) {
        _onTypingIndicator(event);
      }
    } else if (event.type == WebSocketEventType.userStatus) {
      _onUserStatusUpdate(event);
    } else if (event.type == WebSocketEventType.unreadCountUpdated) {
      final chatId = event.data['chat_id']?.toString();
      if (chatId == widget.chatId) {
        _onUnreadCountUpdated(event);
      }
    } else if (event.type == WebSocketEventType.messageEdited) {
      final chatId = event.data['chat_id']?.toString();
      if (chatId == widget.chatId) {
        _onMessageEdited(event);
      }
    } else if (event.type == WebSocketEventType.messageDeleted) {
      final chatId = event.data['chat_id']?.toString();
      if (chatId == widget.chatId) {
        _onMessageDeleted(event);
      }
    } else if (event.type == WebSocketEventType.messageReactionUpdated) {
      final chatId = event.data['chat_id']?.toString();
      if (chatId == widget.chatId) {
        _onMessageReactionUpdated(event);
      }
    } else if (event.type == WebSocketEventType.userAvatarUpdated) {
      final userId = event.data['user_id']?.toString();
      final avatarUrl = event.data['avatar_url']?.toString();
      if ((userId == widget.otherUserId || userId == _otherUserId) && mounted) {
        PaintingBinding.instance.imageCache.clear();
        PaintingBinding.instance.imageCache.clearLiveImages();
        setState(() {
          _chatAvatar = avatarUrl;
        });
      }
    } else if (event.type == WebSocketEventType.userAppearanceUpdated) {
      _onUserAppearanceUpdated(event);
    }
  }

  void _onUserAppearanceUpdated(WebSocketEvent event) {
    final userId = event.data['user_id']?.toString();
    final nameColorPresetId = event.data['name_color_preset_id']?.toString();
    final replyStripStyle = event.data['reply_strip_style']?.toString();
    if (userId == null || !mounted) return;

    setState(() {
      for (int i = 0; i < _messages.length; i++) {
        final m = _messages[i];
        bool changed = false;
        String? newSenderColor = m.senderNameColorId;
        String? newSenderStrip = m.senderReplyStripStyle;
        ReplyInfo? newReplyInfo = m.replyInfo;

        if (m.senderId == userId) {
          if (nameColorPresetId != null) newSenderColor = nameColorPresetId;
          if (replyStripStyle != null) newSenderStrip = replyStripStyle;
          changed = true;
        }

        if (m.replyInfo != null && m.replyInfo!.senderId == userId) {
          newReplyInfo = m.replyInfo!.copyWith(
            nameColorPresetId: nameColorPresetId ?? m.replyInfo!.nameColorPresetId,
            replyStripStyle: replyStripStyle ?? m.replyInfo!.replyStripStyle,
          );
          changed = true;
        }

        if (changed) {
          _messages[i] = m.copyWith(
            senderNameColorId: newSenderColor,
            senderReplyStripStyle: newSenderStrip,
            replyInfo: newReplyInfo,
          );
        }
      }

      if (_replyToMessage != null && _replyToMessage!.senderId == userId) {
        _replyToMessage = _replyToMessage!.copyWith(
          senderNameColorId: nameColorPresetId ?? _replyToMessage!.senderNameColorId,
          senderReplyStripStyle: replyStripStyle ?? _replyToMessage!.senderReplyStripStyle,
        );
      }
    });
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
        }
      });

      try {
        AppDatabase().updateMessageReactions(
          messageId,
          reactionsMap,
          _myReactions[messageId] ?? {},
        );
      } catch (e) {
        debugPrint('PrivateChatScreen: error updating reactions in DB: $e');
      }
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
    } catch (e) {
      debugPrint('PrivateChatScreen: error deleting message from DB: $e');
    }
  }

  void _onMessageEdited(WebSocketEvent event) {
    final messageId = event.data['message_id']?.toString();
    final newContent = event.data['content']?.toString();
    if (messageId == null || newContent == null) return;

    List<MessageEntity>? newEntities;
    if (event.data['entities'] != null) {
      try {
        final list = event.data['entities'] as List;
        newEntities = list
            .map((e) => MessageEntity.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    if (mounted) {
      setState(() {
        final index = _messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          _messages[index] = _messages[index].copyWith(
            content: newContent,
            entities: newEntities ?? _messages[index].entities,
            isEdited: true,
          );
        }
      });
    }

    try {
      AppDatabase().updateMessageContent(
        messageId,
        newContent,
        newEntities != null && newEntities.isNotEmpty
            ? jsonEncode(newEntities.map((e) => e.toJson()).toList())
            : null,
      );
    } catch (_) {}
  }

  void _onUnreadCountUpdated(WebSocketEvent event) {
    final newUnreadCount = event.data['unread_count'] as int? ?? 0;
    if (mounted) {
      setState(() {
        _unreadCount = newUnreadCount;
        if (_unreadCount == 0) {
          _firstUnreadMessageId = null;
          _hasScrolledToUnread = false;
          _showUnreadDivider = false;
        }
      });
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
          _messages[existingIndex] = message.copyWith(
            localId: _messages[existingIndex].localId ?? message.localId,
            sendStatus: 1,
            replyInfo: message.replyInfo ?? _messages[existingIndex].replyInfo,
            groupedId: message.groupedId ?? _messages[existingIndex].groupedId,
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
      setState(() {
        // If typing user sent message, immediately cancel typing
        if (_typingUserId == message.senderId || _isTyping) {
          _typingTimer?.cancel();
          _isTyping = false;
          _typingUserId = null;
        }
        _messages.insert(0, message);
      });

      // If message is from other user, queue it for mark-as-read
      if (message.senderId != _currentUserId) {
        _onMessageVisible(message.id);
      }
    }
  }

  void _onTypingIndicator(WebSocketEvent event) {
    final chatId = event.data['chat_id']?.toString();
    if (chatId != widget.chatId) return;

    final typingUserId = event.data['user_id']?.toString();
    if (typingUserId == _currentUserId) return;

    final bool isTyping = event.data['is_typing'] != false;

    if (mounted) {
      if (!isTyping) {
        // User stopped typing / cleared input field
        _typingTimer?.cancel();
        setState(() {
          _isTyping = false;
          _typingUserId = null;
        });
        return;
      }

      setState(() {
        _typingUserId = typingUserId;
        _isTyping = true;
      });

      // Clear typing indicator after 4 seconds (Telegram-like smooth safety window)
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() {
            _isTyping = false;
            _typingUserId = null;
          });
        }
      });
    }
  }

  void _onEmojiToggle() {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    _transitionTimer?.cancel();

    if (_showEmojiPanel || _isKeyboardRising) {
      if (_isKeyboardRising && !_showEmojiPanel) {
        // User clicked while transitioning, force close panel
        setState(() {
          _isKeyboardRising = false;
          _showEmojiPanel = false;
        });
        _inputFocusNode.unfocus();
        SystemChannels.textInput.invokeMethod('TextInput.hide');
        return;
      }

      // Panel is open, switch to keyboard
      setState(() {
        _isKeyboardRising = true;
        // Keep _showEmojiPanel = true to prevent jump, will be hidden in build()
      });
      _inputFocusNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.show');

      // Safety for floating windows: if no inset change in 600ms, hide panel
      _transitionTimer = Timer(const Duration(milliseconds: 600), () {
        if (mounted && _isKeyboardRising && _showEmojiPanel) {
          setState(() {
            _showEmojiPanel = false;
            _isKeyboardRising = false;
          });
        }
      });
    } else {
      // Switch to panel: (Panel renders UNDER keyboard first)
      setState(() {
        _showEmojiPanel = true;
        _isKeyboardRising = false;
        if (bottomInset > 0) {
          _isKeyboardFalling = true;
        }
      });
      // Now hide keyboard - it will slide down and reveal the panel
      if (bottomInset > 0 || _inputFocusNode.hasFocus) {
        SystemChannels.textInput.invokeMethod('TextInput.hide');
        _inputFocusNode.unfocus();
      }
    }
  }

  void _handleBackspace() {
    final text = _textController.text;
    final selection = _textController.selection;

    if (!selection.isValid || (selection.isCollapsed && selection.start == 0)) {
      return;
    }

    if (selection.isCollapsed) {
      final textBefore = text.substring(0, selection.start);
      final charBefore = textBefore.characters.last;
      final newText = text.replaceRange(
        selection.start - charBefore.length,
        selection.start,
        '',
      );
      _textController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(
          offset: selection.start - charBefore.length,
        ),
      );
    } else {
      final newText = text.replaceRange(selection.start, selection.end, '');
      _textController.value = TextEditingValue(
        text: newText,
        selection: TextSelection.collapsed(offset: selection.start),
      );
    }
  }

  void _onUserStatusUpdate(WebSocketEvent event) {
    final userId = event.data['user_id']?.toString();
    if (userId != _otherUserId) return;

    if (mounted) {
      setState(() {
        _isOtherUserOnline = event.data['is_online'] == true;
        if (event.data['last_seen'] != null) {
          _otherUserLastSeen =
              DateTimeUtils.parseUtcDateTime(event.data['last_seen']);
        } else if (!_isOtherUserOnline) {
          _otherUserLastSeen = DateTime.now();
        }
      });
    }
  }

  Timer? _typingKeepAliveTimer;
  bool _amITyping = false;

  void _onInputTextChanged(String text) {
    final bool hasText = text.trim().isNotEmpty;
    if (hasText) {
      if (!_amITyping) {
        _amITyping = true;
        _wsService.sendTypingIndicator(widget.chatId, isTyping: true);
      }
      _typingKeepAliveTimer ??= Timer.periodic(const Duration(milliseconds: 2000), (_) {
        if (_textController.text.trim().isNotEmpty) {
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
      _wsService.sendTypingIndicator(widget.chatId, isTyping: false);
    }
  }

  void _onMessageRead(WebSocketEvent event) {
    // Handle read status update - mark all our messages in this chat as read
    final readerId = event.data['reader_id']?.toString();
    if (readerId == _currentUserId) return; // We are the reader, not the sender

    if (mounted) {
      setState(() {
        // Mark all messages sent by current user as read
        for (int i = 0; i < _messages.length; i++) {
          if (_messages[i].senderId == _currentUserId) {
            _messages[i] = _messages[i].copyWith(isRead: true);
          }
        }
      });

      // Обновить статус isRead в Drift для персистенции
      final db = AppDatabase();
      try {
        db.markMessagesAsRead(widget.chatId, _currentUserId ?? '');
      } catch (e) {
        debugPrint('Drift markMessagesAsRead error: $e');
      }
    }
  }

  /// Called by VisibleMessageDetector when an unread incoming message becomes visible.
  /// Queues the message for batch mark-as-read (debounced).
  void _onMessageVisible(String messageId) {
    if (_pendingMarkRead.contains(messageId)) return;
    _pendingMarkRead.add(messageId);

    // Debounce: flush after 300ms of no new visible messages
    _markReadTimer?.cancel();
    _markReadTimer = Timer(const Duration(milliseconds: 300), () {
      _flushMarkRead();
    });
  }

  /// Flush pending mark-as-read: find the latest visible message and mark up to it
  Future<void> _flushMarkRead() async {
    if (_pendingMarkRead.isEmpty || _isMarkingRead) return;
    _isMarkingRead = true;

    // Find the latest message among the pending ones (highest created_at = lowest index in reversed list)
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
    _isMarkingRead = false;

    if (latestMessageId == null) return;

    // Mark all messages up to and including this one as read
    final result = await ChatService.markMessagesReadUpTo(
      chatId: widget.chatId,
      messageId: latestMessageId,
    );

    final markedCount = result['marked_count'] as int? ?? 0;
    if (markedCount > 0) {
      _wsService.sendMessageRead(widget.chatId, markedCount: markedCount);

      // Optimistically update local unread count
      if (mounted) {
        setState(() {
          _unreadCount = (_unreadCount - markedCount).clamp(0, _unreadCount);
        });
      }

      // Update the provider
      if (mounted) {
        final provider = context.read<UnreadCountProvider>();
        provider.decrement(widget.chatId, markedCount);
      }
    }
  }

  /// Mark all unread messages in this chat as read (used when entering chat)
  Future<void> _markAllMessagesAsRead() async {
    final result = await ChatService.markMessagesAsRead(
      chatId: widget.chatId,
      chatTitle: widget.otherUserName,
    );
    final markedCount = result['marked_count'] as int? ?? 0;
    if (markedCount > 0) {
      _wsService.sendMessageRead(widget.chatId, markedCount: markedCount);

      // Optimistically clear unread count, but KEEP the divider
      // (_showUnreadDivider and _firstUnreadMessageId persist until user leaves chat)
      if (mounted) {
        setState(() {
          _unreadCount = 0;
        });
      }

      // Update the provider
      if (mounted) {
        final provider = context.read<UnreadCountProvider>();
        provider.clear(widget.chatId);
      }
    }
  }

  // === Reply / Quote methods ===

  /// Start a reply to a message (full message reply)
  void _startReply(Message message) {
    setState(() {
      _replyToMessage = message;
      _isQuote = false;
      _quoteText = null;
      _quoteOffset = 0;
      _quoteLength = 0;
    });
    // Focus the input field
    _textController.selection = TextSelection.collapsed(
      offset: _textController.text.length,
    );
  }

  /// Start a quote reply (partial text)
  void _startQuote(Message message, String selectedText, int offset, int length) {
    setState(() {
      _replyToMessage = message;
      _isQuote = true;
      _quoteText = selectedText;
      _quoteOffset = offset;
      _quoteLength = length;
    });
    // Focus the input field
    _textController.selection = TextSelection.collapsed(
      offset: _textController.text.length,
    );
  }

  /// Cancel the current reply/quote
  void _cancelReply() {
    setState(() {
      _replyToMessage = null;
      _isQuote = false;
      _quoteText = null;
      _quoteOffset = 0;
      _quoteLength = 0;
    });
  }

  /// Cancel current message editing
  void _cancelEditing() {
    _stopMyTyping();
    setState(() {
      _isEditing = false;
      _editingMessageId = null;
      _textController.clear();
    });
  }

  /// Scroll to a specific message and highlight it
  Future<void> _scrollToMessage(String messageId, {int retryCount = 0}) async {
    if (!mounted) return;

    final key = _messageKeys[messageId];
    if (key?.currentContext != null) {
      // Message is already built and has a context, scroll precisely
      await Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        alignment: 0.5, // Center the message in view
      );
      _setHighlight(messageId);
      return;
    }

    // If message is not built yet, we need to find it in the list
    int index = _messages.indexWhere((m) => m.id == messageId);
    
    // If message not in list, try to load more
    if (index == -1) {
      if (_hasMoreMessages && retryCount < 5) {
        await _loadMoreMessages();
        // Recurse to try finding it again
        return _scrollToMessage(messageId, retryCount: retryCount + 1);
      }
      return; // Not found even after loading more
    }

    // Message is in the list but not built. 
    // In a reversed ListView, higher index means OLDER message = HIGHER scroll offset.
    // We'll jump close to the target then let it refine.
    const estimatedItemHeight = 110.0;
    final targetOffset = index * estimatedItemHeight;

    // Use jump if far, animate if close
    if ((_scrollController.offset - targetOffset).abs() > 2000) {
      _scrollController.jumpTo(targetOffset);
    } else {
      await _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    // Wait a bit for ListView to build the items at this offset
    await Future.delayed(const Duration(milliseconds: 100));
    
    // Retry to refine position if message is now built
    if (retryCount < 10) {
      return _scrollToMessage(messageId, retryCount: retryCount + 1);
    }
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
    // If original message is in this chat, just scroll to it
    if (originalChatId == null || originalChatId == widget.chatId) {
      if (fromMessageId != null && (_jumpHistory.isEmpty || _jumpHistory.last != fromMessageId)) {
        _jumpHistory.add(fromMessageId);
        setState(() {
          _showScrollDownFab = true;
        });
      }
      await _scrollToMessage(messageId);
      return;
    }

    // Original message is in a DIFFERENT chat.
    // 1. Check if we have access and get chat details
    final result = await ChatService.getChat(originalChatId);
    if (result['success'] == true) {
      final chat = result['chat'] as ChatDetails;
      
      // 2. Navigate to the appropriate screen
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
      // User doesn't have access or network error
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

  /// Handle scroll events — пагинация при прокрутке вверх + FAB visibility
  void _onScroll() {
    if (!_scrollController.hasClients || _messages.isEmpty) return;

    // Пагинация: когда пользователь проскроллил вверх — загрузить ещё
    if (_hasMoreMessages && !_isLoadingMore) {
      final maxScroll = _scrollController.position.maxScrollExtent;
      final currentScroll = _scrollController.offset;
      // В reverse=true: верх = maxScrollExtent, низ = 0
      // Когда scrollOffset приближается к maxScrollExtent — загрузить старые
      if (maxScroll > 0 && (currentScroll >= maxScroll * 0.75 || (maxScroll - currentScroll) < 600)) {
        _loadMoreMessages();
      }
    }

    // Show/hide scroll-down FAB logic: 
    // - Hide if scrolling UP (towards older messages)
    // - Show if scrolling DOWN (towards newer messages)
    // - Hide if we reached the top of the newest message
    final offset = _scrollController.offset;
    final delta = offset - _lastScrollOffset;
    _lastScrollOffset = offset;

    if (delta < 0) {
      // Scrolling DOWN (towards 0, newer messages in reverse list)
      _accumulatedScrollDown -= delta;
      _accumulatedScrollUp = 0;
    } else if (delta > 0) {
      // Scrolling UP (towards older messages)
      _accumulatedScrollUp += delta;
      _accumulatedScrollDown = 0;
    }

    final isScrollingDown = _scrollController.position.userScrollDirection == ScrollDirection.forward;
    
    // Clear jump history when near bottom
    if (offset < 100 && _jumpHistory.isNotEmpty) {
      _jumpHistory.clear();
    }

    // Dynamic threshold: height of the newest message
    double threshold = 150.0; // Default
    if (_messages.isNotEmpty) {
      final firstMsgId = _messages.first.id;
      final key = _messageKeys[firstMsgId];
      final renderBox = key?.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize) {
        threshold = renderBox.size.height; // Message height + small buffer
      }
    }
    
    bool shouldShow = _showScrollDownFab;
    if (offset <= threshold) {
      shouldShow = false;
    } else if (_jumpHistory.isNotEmpty) {
      // Always show if we have return history and are away from bottom
      shouldShow = true;
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
        _chatType = chat.chatType;
      });
      // Find the other participant for private chat
      for (var participant in chat.participants) {
        if (participant.id != _currentUserId) {
          setState(() {
            _chatName = participant.displayName.isNotEmpty
                ? participant.displayName
                : participant.username;
            _chatAvatar = participant.avatarUrl;
            _otherUserId = participant.id;
            _isOtherUserOnline = participant.isOnline;
            _otherUserLastSeen = participant.lastSeen;
          });
          break;
        }
      }
    }

    // Get unread info before loading messages
    final unreadInfo = await ChatService.getUnreadInfo(chatId: widget.chatId);
    if (unreadInfo['success'] == true) {
      setState(() {
        _unreadCount = unreadInfo['unread_count'] as int? ?? 0;
        _firstUnreadMessageId =
            unreadInfo['first_unread_message_id'] as String?;
        // Установить разделитель при входе в чат (если есть непрочитанные)
        if (_unreadCount > 0 && _firstUnreadMessageId != null) {
          _showUnreadDivider = true;
          _dividerUnreadCount = _unreadCount;
        }
      });
    }

    // Load saved keyboard height
    try {
      final prefs = await SharedPreferences.getInstance();
      final savedHeight = prefs.getDouble('keyboard_height');
      if (savedHeight != null && savedHeight > 100 && mounted) {
        setState(() {
          _keyboardHeight = savedHeight;
        });
      }
    } catch (e) {
      debugPrint('Error loading keyboard height: $e');
    }

    // Load messages
    await _loadMessages();

    // Scroll to initial message if specified (e.g. from cross-chat navigation)
    if (widget.initialMessageId != null) {
      _scrollToMessage(widget.initialMessageId!);
    } else if (_firstUnreadMessageId != null) {
      // Scroll to first unread message if exists (before marking as read,
      // so user can see where they left off)
      _scrollToFirstUnread();
    }

    // Mark ALL unread messages as read after scrolling
    // (use markMessagesAsRead which marks all, not just up to first unread)
    if (_unreadCount > 0) {
      _markAllMessagesAsRead();
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
      debugPrint('Drift getMessages error: $e');
    }

    if (localMessages.isNotEmpty && mounted) {
      // Обработать "зависшие" sending-сообщения:
      // - Если serverId уже установлен → сообщение было подтверждено, исправить на sent
      // - Если serverId null → приложение закрылось до подтверждения, пометить как failed
      final fixedMessages = localMessages.map((m) {
        if (m.sendStatus == MessageSendStatus.sending.index) {
          if (m.serverId != null) {
            // Сообщение было подтверждено сервером, но статус не обновился
            db.updateMessageSendStatus(
                m.localId, m.serverId!, MessageSendStatus.sent.index);
            return m.copyWith(sendStatus: MessageSendStatus.sent.index);
          } else {
            // Действительно зависшее сообщение
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
      });
    }

    // 2. Затем загрузить с сервера (обновление)
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

          // Merge server messages without truncating older messages already loaded into _messages
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
          _messageReactions.clear();
          _myReactions.clear();
          _messages.addAll(merged.values.toSet());

          for (final m in _messages) {
            if (m.reactions.isNotEmpty) {
              _messageReactions[m.id] = Map.from(m.reactions);
            }
            if (m.myReactions.isNotEmpty) {
              _myReactions[m.id] = Set.from(m.myReactions);
            }
          }

          // Сортировка по createdAt по убыванию (новейшие первыми)
          // для корректного отображения в reverse=true ListView
          _messages.sort((a, b) {
            try {
              final ta = DateTime.parse(a.createdAt);
              final tb = DateTime.parse(b.createdAt);
              final cmp = tb.compareTo(ta); // descending
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
            debugPrint('Drift saveMessages error: $e');
          }
        } else if (localMessages.isEmpty) {
          // Нет ни локальных, ни серверных — показать пустое состояние
        }
      });

      if (_firstUnreadMessageId == null || _unreadCount == 0) {
        _scrollToBottom();
      }
    }
  }

  /// Загрузить старые сообщения (пагинация)
  Future<void> _loadMoreMessages() async {
    if (_isLoadingMore || !_hasMoreMessages) return;

    setState(() => _isLoadingMore = true);

    // Получить последнее (самое старое) сообщение
    final lastMessage = _messages.isNotEmpty ? _messages.last : null;

    // Сначала попробовать загрузить из Drift
    final db = AppDatabase();
    try {
      final localMessages = await db.getMessages(
        widget.chatId,
        beforeCreatedAt: lastMessage?.createdAt,
        limit: 50,
      );

      if (localMessages.isNotEmpty) {
        setState(() {
          // Дедупликация: добавлять только сообщения, которых ещё нет
          for (final m
              in localMessages.map((m) => Message.fromDbMessage(m))) {
            if (!_messages.any((existing) =>
                existing.id == m.id ||
                (m.localId != null && existing.localId == m.localId))) {
              _messages.add(m);
              if (m.reactions.isNotEmpty) {
                _messageReactions[m.id] = Map.from(m.reactions);
              }
              if (m.myReactions.isNotEmpty) {
                _myReactions[m.id] = Set.from(m.myReactions);
              }
            }
          }
          final dateMap = <String, int>{};
          for (final m in _messages) {
            dateMap[m.id] = DateTime.tryParse(m.createdAt)?.millisecondsSinceEpoch ?? 0;
          }
          _messages.sort((a, b) {
            final ta = dateMap[a.id] ?? 0;
            final tb = dateMap[b.id] ?? 0;
            final cmp = tb.compareTo(ta);
            if (cmp != 0) return cmp;
            return (int.tryParse(b.id) ?? 0).compareTo(int.tryParse(a.id) ?? 0);
          });
          _isLoadingMore = false;
        });
        return;
      }
    } catch (e) {
      debugPrint('Drift loadMore error: $e');
    }

    // Если в Drift нет — найти самый старый числовой serverId и загрузить с сервера
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

      // Сохранить в Drift
      try {
        db.saveMessages(
            newMessages.map((m) => _messageToCompanion(m)).toList());
      } catch (e) {
        debugPrint('Drift saveMessages error: $e');
      }

      setState(() {
        // Дедупликация: добавлять только сообщения, которых ещё нет
        for (final m in newMessages) {
          if (!_messages.any((existing) => existing.id == m.id)) {
            _messages.add(m);
            if (m.reactions.isNotEmpty) {
              _messageReactions[m.id] = Map.from(m.reactions);
            }
            if (m.myReactions.isNotEmpty) {
              _myReactions[m.id] = Set.from(m.myReactions);
            }
          }
        }
        final dateMap = <String, int>{};
        for (final m in _messages) {
          dateMap[m.id] = DateTime.tryParse(m.createdAt)?.millisecondsSinceEpoch ?? 0;
        }
        _messages.sort((a, b) {
          final ta = dateMap[a.id] ?? 0;
          final tb = dateMap[b.id] ?? 0;
          final cmp = tb.compareTo(ta);
          if (cmp != 0) return cmp;
          return (int.tryParse(b.id) ?? 0).compareTo(int.tryParse(a.id) ?? 0);
        });
        _isLoadingMore = false;
      });
    } else if (mounted) {
      setState(() => _isLoadingMore = false);
    }
  }

  /// Конвертация Message → MessagesCompanion для Drift
  MessagesCompanion _messageToCompanion(Message msg) {
    // pending (sendStatus==0) or failed (sendStatus==2): serverId отсутствует в Drift
    final isSent = msg.sendStatus == 1 && msg.id != msg.localId;
    return MessagesCompanion(
      serverId: isSent ? Value(msg.id) : const Value.absent(),
      localId: Value(msg.localId ?? msg.id),
      chatId: Value(msg.chatId),
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

  /// Scroll to the first unread message
  void _scrollToFirstUnread() {
    if (_firstUnreadMessageId == null || _hasScrolledToUnread) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;

      final index = _messages.indexWhere((m) => m.id == _firstUnreadMessageId);
      if (index == -1) {
        _scrollToBottom();
        return;
      }

      // In reversed list, we need to calculate the offset
      // Each message is approximately 60-100 pixels, we'll estimate
      // Scroll to show the unread message with some context above
      const estimatedItemHeight = 80.0;
      final targetOffset =
          (index - 2).clamp(0, _messages.length - 1) * estimatedItemHeight;

      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 500),
        curve: Curves.easeOut,
      );

      setState(() {
        _hasScrolledToUnread = true;
      });
    });
  }

  Future<void> _sendMessage({
    String? cleanText,
    List<MessageEntity>? entities,
    LinkPreviewOptions? linkPreviewOptions,
    bool invertMedia = false,
  }) async {
    final String rawText = _textController.text.trim();
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
        debugPrint('Error editing message: $e');
      }
      return;
    }

    // Capture reply/quote state before clearing
    final replyTo = _replyToMessage;
    final replyIsQuote = _isQuote;
    final replyQuoteText = _quoteText;
    final replyQuoteOffset = _quoteOffset;
    final replyQuoteLength = _quoteLength;

    _stopMyTyping();
    _textController.clear();
    setState(() {
      _isSending = true;
      _isUploading = _attachedFiles.isNotEmpty;
      // Clear reply state
      _replyToMessage = null;
      _isQuote = false;
      _quoteText = null;
      _quoteOffset = 0;
      _quoteLength = 0;
    });

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
          final albumGroupedId = 'album_${DateTime.now().millisecondsSinceEpoch}_${const Uuid().v4().substring(0, 8)}';

          for (int i = 0; i < chunkFiles.length; i++) {
            final file = chunkFiles[i];
            final isVideo = _isVideoFile(file.path);

            final uploadResult = await _fileService.uploadFileChunked(file, onProgress: (p) {
              if (mounted) {
                setState(() {
                  _uploadProgress = (overallProcessedCount + i + p) / totalFilesCount;
                });
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

            // Fallback: If server album endpoint fails (e.g. older backend or DB error),
            // send items sequentially with the same albumGroupedId so they are still presented as an album!
            if (res['success'] != true) {
              debugPrint('sendMediaAlbum failed (${res['message']}), falling back to individual messages with groupedId');
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
                final msg = raw is Message ? raw : Message.fromJson(raw as Map<String, dynamic>);
                newMsgs.add(msg);
              }
              for (final msg in newMsgs) {
                final existingIdx = _messages.indexWhere((m) => m.id == msg.id);
                if (existingIdx != -1) {
                  _messages[existingIdx] = msg;
                } else {
                  _messages.insert(0, msg);
                }
              }
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
              await AppDatabase().saveMessage(_messageToCompanion(sent));
            }
          }
        }

        if (mounted) {
          setState(() {
            _isUploading = false;
            _uploadProgress = 0.0;
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
              setState(() {
                _uploadProgress = (i + p) / filesToSend.length;
              });
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
            replyToMessageId: replyTo?.id,
            entities: (i == 0) ? effectiveEntities : null,
          );
          if (res['success'] == true && res['message'] is Message) {
            final sent = res['message'] as Message;
            if (mounted) {
              setState(() {
                if (!_messages.any((m) => m.id == sent.id)) {
                  _messages.insert(0, sent);
                }
              });
            }
            await AppDatabase().saveMessage(_messageToCompanion(sent));
          }
        }
        if (mounted) {
          setState(() {
            _isUploading = false;
            _uploadProgress = 0.0;
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
          setState(() { _uploadProgress = p; });
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
          _uploadProgress = 0.0;
        });

        messageType = isVideo ? 'video' : _getMessageTypeFromMimeType(uploadResult.mimeType);
        content = effectiveContentText; // Can be empty!
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
          mediaPayload: singleMediaPayload,
        );
      } catch (e) {
        debugPrint('SyncService createPendingMessage error: $e');
      }

      // 2. Мгновенно добавить в UI со статусом "sending"
      if (pendingMsg != null) {
        pendingLocalId = pendingMsg.localId; // non-null capture для замыканий
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

        // 3. Отправить на сервер в фоне
        try {
          final result = await ChatService.sendMessage(
            chatId: widget.chatId,
            content: content,
            messageType: messageType,
            localId: pendingLocalId,
            fileUrl: fileUrl,
            fileName: fileName,
            replyToMessageId: replyTo?.id,
            isQuote: replyIsQuote,
            quoteText: replyQuoteText,
            quoteOffset: replyQuoteOffset,
            quoteLength: replyQuoteLength,
            entities: effectiveEntities,
            linkPreviewOptions: linkPreviewOptions,
            invertMedia: invertMedia,
            mediaPayload: singleMediaPayload,
          );

          if (result['success'] == true) {
            // 4. Подтвердить — заменить localId на serverId и обновить сообщение из ответа сервера
            final sentMessage = result['message'];
            final serverId = sentMessage is Message ? sentMessage.id : null;
            if (serverId != null && serverId.isNotEmpty) {
              await syncService.confirmMessageSent(pendingLocalId, serverId);
              // Обновить в UI
              if (mounted) {
                setState(() {
                  final idx =
                      _messages.indexWhere((m) => m.localId == pendingLocalId);
                  if (idx != -1) {
                    if (sentMessage is Message) {
                      _messages[idx] = sentMessage.copyWith(
                        localId: pendingLocalId,
                        sendStatus: 1, // sent
                        replyInfo: sentMessage.replyInfo ?? _messages[idx].replyInfo,
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
            // 5. Пометить как failed
            final errMsg = result['message']?.toString() ?? 'Failed to send message';
            debugPrint('ChatService.sendMessage returned false: $errMsg');
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
          debugPrint('ChatService.sendMessage exception: $e');
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
        // Fallback: SyncService недоступен — отправить напрямую через API
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
              // Дедупликация: не добавлять если WS уже принёс это сообщение
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
    } catch (e) {
      debugPrint('Send message error: $e');
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
          _uploadProgress = 0.0;
        });
      }
    }
  }

  /// Повторить отправку failed-сообщения
  Future<void> _retryMessage(Message message) async {
    if (message.localId == null) return;
    final syncService = SyncService();

    // Обновить UI на "sending"
    setState(() {
      final idx = _messages.indexWhere((m) => m.localId == message.localId);
      if (idx != -1) {
        _messages[idx] = _messages[idx].copyWith(sendStatus: 0);
      }
    });

    await syncService.retryFailedMessage(message.localId!);

    // Перезагрузить сообщение из БД
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

  /// Get message type from mime type
  String _getMessageTypeFromMimeType(String mimeType) {
    if (mimeType.startsWith('image/')) return 'image';
    if (mimeType.startsWith('video/')) return 'video';
    if (mimeType.startsWith('audio/')) return 'audio';
    return 'file';
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

  String _formatTime(String timestamp) {
    return DateTimeUtils.formatTimeHHmm(timestamp);
  }

  /// Validates and returns a valid avatar URL, or null if invalid
  // ignore: unused_element
  String? _getValidAvatarUrl(String? url) {
    if (url == null || url.isEmpty) return null;
    try {
      final uri = Uri.parse(url);
      if (uri.hasScheme && (uri.scheme == 'http' || uri.scheme == 'https')) {
        return url;
      }
      return null;
    } catch (e) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    _updateInputHeight();
    final displayName = widget.otherUserName ?? _chatName;

    return Consumer<LiquidGlassProvider>(
      builder: (context, glassProvider, _) {
        final glassEnabled = glassProvider.enabled;

        return ChatScaffold(
          canPop: !_showEmojiPanel && MediaQuery.of(context).viewInsets.bottom == 0,
          onPopInvoked: (didPop, _) {
            if (!didPop) {
              if (_showEmojiPanel) {
                setState(() => _showEmojiPanel = false);
              } else if (MediaQuery.of(context).viewInsets.bottom > 0) {
                FocusScope.of(context).unfocus();
              }
            }
          },
          appBar: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              FloatingGlassAppBar(
                name: displayName,
                avatarUrl: _chatAvatar ?? widget.otherUserAvatar,
                isOnline: _isOtherUserOnline,
                lastSeen: _otherUserLastSeen,
                statusText: _isTyping ? context.l10n.translate('chat_typing') : null,
                isChannel: false,
                isMuted: _isMuted,
                onBack: () => Navigator.pop(context),
                onTitleTap: _viewUserProfile,
                onViewProfile: _viewUserProfile,
                onVoiceCall: _startVoiceCall,
                onVideoCall: _startVideoCall,
                onSearch: _searchMessages,
                onToggleMute: _toggleMuteNotifications,
                onClearHistory: _showClearHistoryDialog,
                onReport: _showBlockUserDialog,
              ),
              MediaNotePlayerHeader(
                onScrollToActive: () {
                  final activeId = VoicePlaybackService().activeMessageId ??
                      VideoNotePlaybackService().activeMessageId;
                  if (activeId != null) {
                    _scrollToMessage(activeId);
                  }
                },
              ),
            ],
          ),
          body: _buildChatContent(glassEnabled),
        );
      },
    );
  }

  // Выделен метод для построения контента чата (сообщения + поле ввода)
  Widget _buildChatContent(bool glassEnabled) {
    final wallpaperPath = context.watch<WallpaperProvider>().wallpaperPath;
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;

    // В glass-режиме Scaffold без appBar, поэтому нужно учесть
    // высоту статус-бара + AppBar для верхнего отступа контента
    final topPadding = mediaQuery.padding.top + kToolbarHeight + 16.0;
    final bottomInset = mediaQuery.viewInsets.bottom;

    // Cap panel height to ensure it doesn't cover the entire chat in small windows
    // but allow it to be as large as the keyboard if possible.
    final double maxPossibleHeight = math.max(200.0, screenHeight - topPadding - 120.0);
    
    // Update keyboard height only when it grows or is stable
    if (bottomInset > 100) {
      if (bottomInset > _keyboardHeight) {
        // Update immediately to prevent jump when keyboard is taller than cache
        _keyboardHeight = bottomInset;
      }
    }

    // The panel height should exactly match our best knowledge of the keyboard height
    final double targetPanelHeight = _keyboardHeight;

    // Keyboard-to-Emoji or Emoji-to-Keyboard stabilization:
    if (_isKeyboardFalling && bottomInset == 0) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _isKeyboardFalling) {
          setState(() => _isKeyboardFalling = false);
        }
      });
    }

    if (_isKeyboardRising && _showEmojiPanel) {
      // Hide panel only when keyboard is high enough or stable
      final bool keyboardCoveredPanel = bottomInset >= targetPanelHeight - 5;
      final bool keyboardIsStable = bottomInset > 100 && bottomInset == _lastBottomInset;
      
      if (keyboardCoveredPanel || keyboardIsStable) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isKeyboardRising) {
            _transitionTimer?.cancel();
            setState(() {
              // Crucial: Update height to actual current inset to prevent any jump 
              // at the moment of switching shouldShowPanel from true to false.
              _keyboardHeight = bottomInset; 
              _isKeyboardRising = false;
              _showEmojiPanel = false;
            });
            _saveKeyboardHeight(bottomInset);
          }
        });
      }
    }
    
    _lastBottomInset = bottomInset;

    final bool shouldShowPanel = _showEmojiPanel || _isKeyboardRising;
    
    // If we are searching inside the panel (keyboard is up but not for main input), we lift the panel.
    // We don't lift it if the keyboard is just falling from the main input.
    final bool isSearchingInPanel = _showEmojiPanel && bottomInset > 0 && !_isKeyboardRising && !_isKeyboardFalling;

    final double safeBottom = MediaQuery.paddingOf(context).bottom;

    // Total stable offset for message list and input field.
    final double bottomOffset = isSearchingInPanel
        ? (targetPanelHeight + bottomInset)
        : (shouldShowPanel 
            ? math.max(targetPanelHeight, bottomInset) 
            : (bottomInset > 0 ? bottomInset : safeBottom));

    // The actual height of the emoji panel container.
    final double effectivePanelHeight = shouldShowPanel ? targetPanelHeight : 0;

    final typingIndicator = _isTyping
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                const SizedBox(width: 8),
                Text(
                  '$_chatName is typing...',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          )
        : const SizedBox.shrink();

    final messageList = _isLoading
        ? const Center(child: CircularProgressIndicator())
        : _messages.isEmpty
            ? Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.chat_bubble_outline,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'No messages yet',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Start the conversation!',
                      style: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[500],
                      ),
                    ),
                  ],
                ),
              )
            : Column(
                children: [
                  if (_isLoadingMore)
                    const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Center(
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    ),
                  Expanded(
                    child: ListView.builder(
                      controller: _scrollController,
                      reverse: true,
                      cacheExtent: 600.0,
                      // В glass-режиме добавляем верхний отступ,
                      // чтобы сообщения не прятались за glass AppBar
                      padding: EdgeInsets.only(
                        top: topPadding,
                        bottom: _inputHeight + bottomOffset,
                      ),
                      itemCount: _feedItems.length +
                          (_showUnreadDivider && _firstUnreadMessageId != null
                              ? 1
                              : 0),
                      itemBuilder: (context, index) {
                        // Insert unread divider between unread and read messages.
                        if (_showUnreadDivider &&
                            _firstUnreadMessageId != null) {
                          final unreadIndex = _feedItems.indexWhere((item) =>
                              item.id == _firstUnreadMessageId ||
                              (item is FeedAlbumItem &&
                                  item.album.items.any((ai) => ai.id == _firstUnreadMessageId)));
                          if (unreadIndex != -1) {
                            final dividerPosition = unreadIndex + 1;

                            if (index == dividerPosition) {
                              return _buildUnreadDivider();
                            }
                            if (index < dividerPosition) {
                              return _buildFeedItem(index);
                            }
                            final adjustedIndex = index - 1;
                            if (adjustedIndex >= 0 &&
                                adjustedIndex < _feedItems.length) {
                              return _buildFeedItem(adjustedIndex);
                            }
                          }
                        }

                        if (index < 0 || index >= _feedItems.length) {
                          return const SizedBox.shrink();
                        }

                        return _buildFeedItem(index);
                      },
                    ),
                  ),
                ],
              );

    final messageInput = _buildMessageInput();

    final bool isKeyboardVisible = bottomInset > 0;

    // Use PopScope to handle back button for closing emoji panel
    return PopScope(
      canPop: !_showEmojiPanel && !isKeyboardVisible,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) {
          if (_showEmojiPanel) {
            setState(() => _showEmojiPanel = false);
          } else if (isKeyboardVisible) {
            FocusScope.of(context).unfocus();
          }
        }
      },
      child: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                // Background wallpaper
                if (wallpaperPath != null)
                  Positioned.fill(
                    child: Image.file(
                      File(wallpaperPath),
                      fit: BoxFit.cover,
                    ),
                  ),
                // Сообщения на весь экран (с верхним отступом через ListView.padding)
                Positioned.fill(
                  child: Column(
                    children: [
                      typingIndicator,
                      Expanded(child: messageList),
                    ],
                  ),
                ),
                // Нижний scroll edge блюр: ПОД полем ввода (над сообщениями, но под полем ввода)
                ChatBottomScrollEdge(
                  height: math.max(safeBottom + 52.0, 52.0),
                ),
                // Кнопка прокрутки вниз (теперь здесь, в главном Stack чата)
                Positioned(
                  right: 14,
                  bottom: _inputHeight + 10 + bottomOffset,
                  child: ScrollDownFab(
                    visible: _showScrollDownFab,
                    unreadCount: _unreadCount,
                    onPressed: () {
                      if (_jumpHistory.isNotEmpty) {
                        final lastId = _jumpHistory.removeLast();
                        _scrollToMessage(lastId);
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
                // Поле ввода внизу (внутри Stack над сообщениями)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: bottomOffset,
                  child: Container(
                    key: _inputKey,
                    child: messageInput,
                  ),
                ),
                // Панель эмодзи/стикеров ВНУТРИ Stack
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: isSearchingInPanel ? bottomInset : 0,
                  child: AnimatedContainer(
                    duration: Duration(
                        milliseconds: (shouldShowPanel || bottomInset > 0) ? 0 : 200),
                    curve: Curves.easeOutCubic,
                    height: effectivePanelHeight,
                    clipBehavior: Clip.hardEdge,
                    decoration: const BoxDecoration(),
                    child: EmojiStickerPanel(
                      controller: _textController,
                      onBackspace: _handleBackspace,
                      onClose: () => setState(() => _showEmojiPanel = false),
                      height: targetPanelHeight,
                    ),
                  ),
                ),
                // Полноэкранный Telegram-оверлей записи видеосообщения («кружочка»)
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
                // Полноэкранный Telegram-оверлей записи голосового сообщения
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
                // Плавающий кружочек видеосообщения (PiP), если активный кружок ушел из поля зрения
                const Positioned.fill(
                  child: FloatingVideoNoteOverlay(),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUnreadDivider() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      child: Row(
        children: [
          Expanded(
            child: Container(
              height: 1,
              color: Colors.grey[300],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              'Непрочитанные сообщения ($_dividerUnreadCount)',
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          Expanded(
            child: Container(
              height: 1,
              color: Colors.grey[300],
            ),
          ),
        ],
      ),
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

    Widget albumWidget = MediaAlbumWidget(
      key: key,
      album: album,
      isMe: isMe,
      currentUserId: _currentUserId ?? '',
      chatType: _chatType,
      formatTime: _formatTime,
      onFileTap: (url, name, type) => _openFile(url, name, type),
    );

    albumWidget = Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: albumWidget,
    );

    albumWidget = SwipeToReplyWrapper(
      onReply: () => _startReply(message),
      enabled: true,
      child: albumWidget,
    );

    if (!isMe && !album.isRead) {
      albumWidget = VisibleMessageDetector(
        messageId: message.id,
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

    albumWidget = GestureDetector(
      onTap: () {
        _showContextMenu(message, isMe, key);
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: albumWidget,
      ),
    );

    final prevItem =
        index < _feedItems.length - 1 ? _feedItems[index + 1] : null;
    final currentDt = DateTime.tryParse(message.createdAt) ?? DateTime.now();
    final prevDt = prevItem != null
        ? (DateTime.tryParse(prevItem.createdAt) ?? DateTime.now())
        : null;
    final currentDate = _dateOnly(currentDt);
    final prevDate = prevDt != null ? _dateOnly(prevDt) : null;

    final items = <Widget>[];
    if (currentDate != prevDate) {
      items.add(DateSeparator(dateLabel: _formatDateLabel(currentDt)));
    }

    items.add(albumWidget);

    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items,
      ),
    );
  }

  Widget _buildMessageItem(Message message, int index) {
    final key = _messageKeys.putIfAbsent(message.id, () => GlobalKey());
    final bool isMe = message.senderId == _currentUserId;
    final isHighlighted = _highlightMessageId == message.id;

    Widget messageWidget = MessageBubble(
      key: key,
      message: message,
      isMe: isMe,
      currentUserId: _currentUserId ?? '',
      chatType: _chatType,
      isHighlighted: isHighlighted,
      reactions: _messageReactions[message.id] ?? (message.reactions.isNotEmpty ? message.reactions : null),
      myReactions: _myReactions[message.id] ?? (message.myReactions.isNotEmpty ? message.myReactions : null),
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

    // Wrap with SwipeToReplyWrapper
    messageWidget = SwipeToReplyWrapper(
      onReply: () => _startReply(message),
      enabled: true,
      child: messageWidget,
    );

    // Wrap incoming unread messages with VisibleMessageDetector
    if (!isMe && !message.isRead) {
      messageWidget = VisibleMessageDetector(
        messageId: message.id,
        onMessageSeen: () => _onMessageVisible(message.id),
        visibilityThreshold: 0.3,
        visibleDuration: const Duration(milliseconds: 300),
        child: messageWidget,
      );
    }

    // Context menu trigger
    messageWidget = GestureDetector(
      onTap: () {
        debugPrint('DEBUG: GestureDetector.onTap for message ${message.id}');
        _showContextMenu(message, isMe, key);
      },
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: double.infinity,
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: messageWidget,
      ),
    );

    // Add date separator if needed
    final prevItem =
        index < _feedItems.length - 1 ? _feedItems[index + 1] : null;
    final currentDt = DateTime.tryParse(message.createdAt) ?? DateTime.now();
    final prevDt = prevItem != null
        ? (DateTime.tryParse(prevItem.createdAt) ?? DateTime.now())
        : null;
    final currentDate = _dateOnly(currentDt);
    final prevDate = prevDt != null ? _dateOnly(prevDt) : null;

    final items = <Widget>[];
    if (currentDate != prevDate) {
      items.add(DateSeparator(dateLabel: _formatDateLabel(currentDt)));
    }

    // Add unread separator
    if (_showUnreadDivider && message.id == _firstUnreadMessageId) {
      items.add(UnreadSeparator(
        count: _dividerUnreadCount,
        onTap: () {},
      ));
    }

    items.add(messageWidget);

    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items,
      ),
    );
  }

  Widget _buildMessageInput() {
    return ChatInputBar(
      controller: _textController,
      focusNode: _inputFocusNode,
      isEditing: _isEditing,
      onCancelEditing: _cancelEditing,
      replyToMessage: _replyToMessage,
      isQuote: _isQuote,
      quoteText: _quoteText,
      onCancelReply: _cancelReply,
      onTapReply: _replyToMessage != null
          ? () => _scrollToMessage(_replyToMessage!.id)
          : null,
      attachedFiles: _attachedFiles,
      attachedFileNames: _attachedFileNames,
      onRemoveAttachment: _removeAttachedFile,
      isUploading: _isUploading,
      uploadProgress: _uploadProgress,
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
      onAttach: _showAttachmentPicker,
      onEmoji: _onEmojiToggle,
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
    final hasPerms = await _videoRecorderService.hasPermissions();
    if (!hasPerms) {
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

    HapticFeedback.heavyImpact();
    setState(() => _isVideoRecording = true);
    final ok = await _videoRecorderService.startRecording();
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
    if (!_isVideoRecording) return;
    final state = _videoOverlayKey.currentState as dynamic;
    state?.handlePointerUp();
  }

  void _onVideoRecordCancel() {
    if (!_isVideoRecording) return;
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
    final hasPerm = await _voiceRecorderService.hasPermission();
    if (!hasPerm) {
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

    VoicePlaybackService().stopVoice();
    VideoNotePlaybackService().stopActivePlayback();

    final started = await _voiceRecorderService.startRecording();
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
    if (!_isVoiceRecording) return;
    final state = _voiceOverlayKey.currentState as dynamic;
    state?.handlePointerUp();
  }

  void _onVoiceRecordCancel() {
    if (!_isVoiceRecording) return;
    _voiceRecorderService.cancelRecording();
    setState(() => _isVoiceRecording = false);
  }

  Future<void> _sendVoiceMessage(VoiceRecordResult result) async {
    final file = result.file;
    final voiceLabel =
        AppLocalizations.of(context)?.translate('chat_voice_message') ??
            'Voice message';
    if (!await file.exists() || await file.length() == 0) {
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
      final fileName = file.path.split(Platform.pathSeparator).last;
      // 1. Immediately create pending message with local file path for instant preview
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

      // 2. Upload voice file to MinIO storage
      setState(() => _isUploading = true);
      final uploadResult = await _fileService.uploadFile(
        file,
        onProgress: (progress) {
          if (mounted) setState(() => _uploadProgress = progress);
        },
      );

      // 3. Send message via ChatService
      final sendResult = await ChatService.sendMessage(
        chatId: widget.chatId,
        content: voiceLabel,
        messageType: 'voice',
        localId: pendingLocalId,
        fileUrl: uploadResult.url,
        fileName: uploadResult.fileName,
        replyToMessageId: replyTo?.id,
        isQuote: replyIsQuote,
        quoteText: replyQuoteText,
        quoteOffset: replyQuoteOffset,
        quoteLength: replyQuoteLength,
        waveform: result.waveform,
        duration: result.duration.inSeconds,
      );

      if (sendResult['success'] == true) {
        final sentMessage = sendResult['message'];
        final serverId = sentMessage is Message ? sentMessage.id : null;
        if (serverId != null && serverId.isNotEmpty && pendingLocalId != null) {
          await syncService.confirmMessageSent(pendingLocalId, serverId);
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
                    duration: sentMessage.duration ?? _messages[idx].duration,
                  );
                } else {
                  _messages[idx] = _messages[idx].copyWith(
                    id: serverId,
                    sendStatus: 1,
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
      debugPrint('Voice message send error: $e');
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
          _uploadProgress = 0.0;
        });
      }
    }
  }

  Future<void> _sendRoundVideoMessage(File file) async {
    final videoNoteLabel =
        AppLocalizations.of(context)?.translate('chat_video_note') ??
            'Video message';
    if (!await file.exists() || await file.length() == 0) {
      debugPrint('Video file is empty or does not exist');
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
      final fileName = file.path.split(Platform.pathSeparator).last;
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

      // 2. Upload file to MinIO storage
      setState(() => _isUploading = true);
      final uploadResult = await _fileService.uploadFileChunked(
        file,
        onProgress: (progress) {
          if (mounted) setState(() => _uploadProgress = progress);
        },
      );

      // 3. Send message via ChatService
      final result = await ChatService.sendMessage(
        chatId: widget.chatId,
        content: videoNoteLabel,
        messageType: 'video',
        localId: pendingLocalId,
        fileUrl: uploadResult.url,
        fileName: uploadResult.fileName,
        isRound: true,
        replyToMessageId: replyTo?.id,
        isQuote: replyIsQuote,
        quoteText: replyQuoteText,
        quoteOffset: replyQuoteOffset,
        quoteLength: replyQuoteLength,
      );

      if (result['success'] == true) {
        final sentMessage = result['message'];
        final serverId = sentMessage is Message ? sentMessage.id : null;
        if (serverId != null && serverId.isNotEmpty && pendingLocalId != null) {
          await syncService.confirmMessageSent(pendingLocalId, serverId);
          if (mounted) {
            setState(() {
              final idx =
                  _messages.indexWhere((m) => m.localId == pendingLocalId);
              if (idx != -1) {
                if (sentMessage is Message) {
                  _messages[idx] = sentMessage.copyWith(
                    localId: pendingLocalId,
                    sendStatus: 1,
                    isRound: true,
                  );
                } else {
                  _messages[idx] = _messages[idx].copyWith(
                    id: serverId,
                    sendStatus: 1,
                    isRound: true,
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
      debugPrint('[PrivateChatScreen] Error sending round video message: $e');
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
          _uploadProgress = 0.0;
        });
      }
    }
  }


  /// Navigate to user profile screen
  void _viewUserProfile() {
    if (_otherUserId != null) {
      Navigator.pushNamed(
        context,
        '/profile',
        arguments: {'userId': _otherUserId},
      );
    }
  }

  /// Open search screen for this chat
  void _searchMessages() {
    Navigator.pushNamed(
      context,
      '/search',
      arguments: {
        'chatId': widget.chatId,
        'chatName': _chatName,
      },
    );
  }

  /// Show confirmation dialog for clearing chat history
  void _showClearHistoryDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear History'),
        content: Text('Delete all messages in this chat with $_chatName?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _clearChatHistory();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
  }

  /// Clear all messages in this chat
  Future<void> _clearChatHistory() async {
    final result = await ChatService.clearChatHistory(chatId: widget.chatId);
    if (mounted) {
      if (result['success'] == true) {
        setState(() {
          _messages.clear();
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chat history cleared')),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(result['message'] ?? 'Failed to clear history')),
        );
      }
    }
  }

  /// Show confirmation dialog for blocking user
  void _showBlockUserDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Block User'),
        content:
            Text('Block $_chatName? They won\'t be able to send you messages.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await _blockUser();
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Block'),
          ),
        ],
      ),
    );
  }

  /// Block the user
  Future<void> _blockUser() async {
    if (_otherUserId == null) return;

    final result = await ChatService.blockUser(userId: _otherUserId!);
    if (mounted) {
      if (result['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$_chatName has been blocked')),
        );
        Navigator.pop(context); // Return to previous screen
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(result['message'] ?? 'Failed to block user')),
        );
      }
    }
  }

  /// Toggle mute notifications for this chat
  bool _isMuted = false;

  void _toggleMuteNotifications() {
    setState(() {
      _isMuted = !_isMuted;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_isMuted
            ? 'Notifications muted for this chat'
            : 'Notifications enabled for this chat'),
      ),
    );

    // Persist mute state via ChatService
    ChatService.setMuteNotifications(chatId: widget.chatId, muted: _isMuted);
  }

  /// Start a video call with the other user
  void _startVideoCall() {
    if (_otherUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to start call - user not found')),
      );
      return;
    }
    Navigator.pushNamed(
      context,
      '/video-call',
      arguments: {
        'chatId': widget.chatId,
        'userId': _otherUserId,
        'userName': _chatName,
        'isVideo': true,
      },
    );
  }

  /// Start a voice call with the other user
  void _startVoiceCall() {
    if (_otherUserId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to start call - user not found')),
      );
      return;
    }
    Navigator.pushNamed(
      context,
      '/voice-call',
      arguments: {
        'chatId': widget.chatId,
        'userId': _otherUserId,
        'userName': _chatName,
        'isVideo': false,
      },
    );
  }

  /// Show attachment picker bottom sheet
  void _showAttachmentPicker() async {
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
        _sendLocation();
        break;
      case AttachmentPickerAction.contact:
        _sendContact();
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
          _textController.text = result.caption!;
        }
      });
      _sendMessage();
    }
  }

  /// Pick and send media (image or video)
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

  /// Take photo with camera
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

  /// Pick and send a document
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

  /// Remove attached file
  void _removeAttachedFile(int index) {
    setState(() {
      _attachedFiles.removeAt(index);
      _attachedFileNames.removeAt(index);
    });
  }

  /// Clear all attached files
  void _clearAttachedFiles() {
    setState(() {
      _attachedFiles.clear();
      _attachedFileNames.clear();
    });
  }

  /// Send current location
  Future<void> _sendLocation() async {
    // This would use geolocator package
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Send location functionality will be implemented')),
    );
  }

  /// Send a contact
  Future<void> _sendContact() async {
    // This would use contacts_service package
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
          content: Text('Send contact functionality will be implemented')),
    );
  }

  /// Open file when tapped
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

  /// Download and open file
  Future<void> _downloadAndOpenFile(String fileUrl, String fileName) async {
    try {
      if (kIsWeb) {
        // On web, use url_launcher to open the file in a new tab
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
        // On mobile/desktop, download and open
        final filePath = await _fileService.downloadToDownloads(
          fileUrl,
          fileName,
        );
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Файл скачан: $filePath')),
          );
          // Open the file
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

  /// Download file only
  Future<void> _downloadFile(String fileUrl, String fileName) async {
    try {
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

  @override
  void dispose() {
    // Stop typing indicator if active
    _stopMyTyping();

    // Flush any pending mark-as-read before leaving
    _markReadTimer?.cancel();
    _flushMarkRead();

    _textController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _wsSubscription?.cancel();
    _typingTimer?.cancel();
    _highlightTimer?.cancel();

    // Clear the open chat indicator in the provider
    try {
      context.read<UnreadCountProvider>().setOpenChat(null);
    } catch (_) {}

    _videoRecorderService.dispose();
    _voiceRecorderService.dispose();

    if (VideoNotePlaybackService().onPlayNextRequested == _playNextVideoNote) {
      VideoNotePlaybackService().onPlayNextRequested = null;
      VideoNotePlaybackService().onScrollToMessageRequested = null;
      VideoNotePlaybackService().stopActivePlayback();
    }

    if (VoicePlaybackService().onPlayNextRequested == _playNextVoiceNote) {
      VoicePlaybackService().onPlayNextRequested = null;
      VoicePlaybackService().onScrollToMessageRequested = null;
      VoicePlaybackService().stopVoice();
    }

    super.dispose();
  }

  void _playNextVoiceNote(String currentMessageId) {
    if (!mounted) return;
    final currentIndex = _messages.indexWhere(
        (m) => m.id == currentMessageId || m.localId == currentMessageId);
    if (currentIndex > 0) {
      for (int i = currentIndex - 1; i >= 0; i--) {
        final m = _messages[i];
        if (m.messageType == 'voice') {
          final rawUrl = m.fileUrl ?? '';
          final resolvedUrl = AppConfig.resolveMediaUrl(rawUrl) ?? rawUrl;
          if (resolvedUrl.isNotEmpty) {
            VoicePlaybackService().playVoice(
              messageId: m.id,
              audioUrl: resolvedUrl,
              senderName: m.senderName,
            );
            return;
          }
        }
      }
    }
    // End of playback chain reached: clear active state and dismiss header
    VoicePlaybackService().stopVoice();
  }

  void _playNextVideoNote(String currentMessageId) {
    if (!mounted) return;
    final currentIndex = _messages.indexWhere(
        (m) => m.id == currentMessageId || m.localId == currentMessageId);
    if (currentIndex > 0) {
      for (int i = currentIndex - 1; i >= 0; i--) {
        final m = _messages[i];
        if (m.isRound || (m.messageType == 'video' && m.isRound)) {
          final rawUrl = m.fileUrl ?? '';
          final resolvedUrl = AppConfig.resolveMediaUrl(rawUrl) ?? rawUrl;
          if (resolvedUrl.isNotEmpty) {
            final cached = VideoNoteControllerPool.get(resolvedUrl);
            if (cached != null && cached.value.isInitialized) {
              cached.seekTo(Duration.zero);
              cached.setLooping(false);
              cached.setVolume(1.0);
              cached.play();
              VideoNotePlaybackService().setActivePlayback(
                messageId: m.id,
                videoUrl: resolvedUrl,
                controller: cached,
                senderName: m.senderName,
                initialInView: VideoNotePlaybackService().isMessageInView(m.id),
              );
            } else {
              final uri = Uri.tryParse(resolvedUrl);
              final ctrl = uri != null && (uri.scheme == 'http' || uri.scheme == 'https')
                  ? VideoPlayerController.networkUrl(uri)
                  : VideoPlayerController.file(File(resolvedUrl.replaceFirst('file://', '')));
              ctrl.initialize().then((_) {
                if (!mounted) {
                  ctrl.dispose();
                  return;
                }
                ctrl.setLooping(false);
                ctrl.setVolume(1.0);
                ctrl.play();
                VideoNoteControllerPool.put(resolvedUrl, ctrl);
                VideoNotePlaybackService().setActivePlayback(
                  messageId: m.id,
                  videoUrl: resolvedUrl,
                  controller: ctrl,
                  senderName: m.senderName,
                  initialInView: VideoNotePlaybackService().isMessageInView(m.id),
                );
              }).catchError((err) {
                debugPrint('Play next init error: $err');
                VideoNotePlaybackService().stopActivePlayback();
              });
            }
            return;
          }
        }
      }
    }
    VideoNotePlaybackService().stopActivePlayback();
  }

  void _updateInputHeight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final RenderBox? renderBox =
          _inputKey.currentContext?.findRenderObject() as RenderBox?;
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

  /// Toggle reaction on a message — optimistic update + API call
  void _toggleReaction(String messageId, String emoji) {
    // Optimistic update
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
      }
    });

    try {
      AppDatabase().updateMessageReactions(
        messageId,
        _messageReactions[messageId] ?? {},
        _myReactions[messageId] ?? {},
      );
    } catch (e) {
      debugPrint('PrivateChatScreen: error saving reactions to DB: $e');
    }

    // API call
    _sendReactionToggle(messageId, emoji);
  }

  Future<void> _sendReactionToggle(String messageId, String emoji) async {
    try {
      final res = await ChatService.toggleReaction(
        chatId: widget.chatId,
        messageId: messageId,
        emoji: emoji,
      );
      if (res['success'] != true) {
        debugPrint(
            'PrivateChatScreen: toggleReaction returned success=false for msg=$messageId: ${res['message']}');
      }
    } catch (e) {
      debugPrint('PrivateChatScreen: toggleReaction exception: $e');
    }
  }

  /// Extract date-only from DateTime
  DateTime _dateOnly(DateTime dt) => DateTimeUtils.startOfDay(dt);

  /// Format date label for date separator
  String _formatDateLabel(DateTime dt) =>
      DateTimeUtils.formatDateSeparator(dt, context: context);

  /// Show enhanced context menu on single tap
  void _showContextMenu(Message message, bool isMe, GlobalKey key) {
    debugPrint('DEBUG: _showContextMenu called for message ${message.id}');
    
    // Do not show context menu when clicking exactly on a big animated emoji.
    // The GestureDetector inside _bubbleBuilder handles the animation/tap.
    if (message.messageType == 'text' && _isSingleEmoji(message.content)) {
      if (EmojiUtils.getAnimatedEmojiPath(message.content) != null) {
        return;
      }
    }

    final bool isVideoNote = message.isRound || (message.messageType == 'video' && message.isRound);
    final bool isVoiceNote = message.messageType == 'voice';

    MessageContextMenuService().show(
      context: context,
      message: message,
      messageKey: key,
      isMe: isMe,
      onReply: () => _startReply(message),
      onQuote: (isVideoNote || isVoiceNote) ? null : () => _startQuote(message, message.content, 0, message.content.length),
      onPin: () {
        // TODO: Pin message
        GlassToastService().show(
          context,
          'Сообщение закреплено',
          iconWidget: iconoir.Pin(
            width: 20,
            height: 20,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        );
      },
      onEdit: (isVideoNote || isVoiceNote) ? null : () {
        setState(() {
          _cancelReply();
          _textController.loadMessage(message.content, message.entities);
          _isEditing = true;
          _editingMessageId = message.id;
          _inputFocusNode.requestFocus();
        });
      },
      onDelete: (msg) => _confirmDeleteMessage(msg),
      onReaction: (msgId, emoji) => _toggleReaction(msgId, emoji),
      selectedEmojis: _myReactions[message.id] ?? message.myReactions,
    );
  }

  void _confirmDeleteMessage(Message message) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(ctx.l10n.translate('chat_delete_message_title')),
        content: Text(ctx.l10n.translate('chat_delete_message_confirm')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(ctx.l10n.translate('cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteMessage(message);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(ctx.l10n.translate('chat_action_delete')),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteMessage(Message message) async {
    // Optimistically remove from UI
    setState(() {
      _messages.removeWhere((m) => m.id == message.id);
    });

    // Remove from local database
    try {
      await AppDatabase().deleteMessage(message.id);
    } catch (e) {
      debugPrint('PrivateChatScreen: error deleting from DB: $e');
    }

    // Call server API
    final result = await ChatService.deleteMessage(
      chatId: widget.chatId,
      messageId: message.id,
    );

    if (result['success'] != true && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(result['message'] ?? 'Failed to delete message')),
      );
    }
  }

  /// Helper to check if string is exactly one emoji
  bool _isSingleEmoji(String text) {
    if (text.isEmpty) return false;
    final trimmed = text.trim();
    final chars = trimmed.characters;
    if (chars.length != 1) return false;

    final rune = chars.first.runes.first;
    // Common emoji ranges
    return (rune >= 0x1F300 && rune <= 0x1FAFF) ||
        (rune >= 0x1F600 && rune <= 0x1F64F) ||
        (rune >= 0x1F680 && rune <= 0x1F6FF) ||
        (rune >= 0x2600 && rune <= 0x26FF) ||
        (rune >= 0x2700 && rune <= 0x27BF) ||
        (rune >= 0xFE00 && rune <= 0xFE0F) ||
        (rune >= 0x1F900 && rune <= 0x1F9FF);
  }
}
