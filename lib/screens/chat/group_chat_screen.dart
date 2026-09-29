import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:provider/provider.dart';
import 'package:dio/dio.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import '../../services/chat_service.dart';
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
import '../../services/notification_service.dart';
import '../../services/profile_theme_provider.dart';
import '../../services/message_context_menu_service.dart';
import '../../l10n/app_localizations.dart';
import '../../config/app_config.dart';
import 'package:drift/drift.dart' show Value;
import '../../utils/image_utils.dart';
import 'package:video_player/video_player.dart';
import '../../services/video_note_playback_service.dart';
import '../../widgets/chat/floating_video_note_overlay.dart';
import '../../widgets/message/video_message_widget.dart';
import '../../services/voice_note_recorder_service.dart';
import '../../services/voice_playback_service.dart';
import '../../widgets/chat/voice_recording_overlay.dart';
import '../../widgets/chat/media_note_player_header.dart';
import '../../utils/emoji_utils.dart';
import '../../widgets/chat/liquid_glass_input_field.dart';
import '../../widgets/chat/floating_glass_app_bar.dart';
import '../../widgets/chat/chat_scaffold.dart';
import '../../widgets/chat/chat_input_bar.dart';
import '../../widgets/chat/chat_messages_list_view.dart';
import '../../widgets/chat/visible_message_detector.dart';
import '../../widgets/chat/swipe_to_reply_wrapper.dart';
import '../../widgets/chat/unread_separator.dart';
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
import '../../widgets/chat/attachment_picker_bottom_sheet.dart';
import 'media_send_screen.dart';
import 'poll_create_screen.dart';

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
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final List<Message> _messages = [];
  final MarkdownTextEditingController _messageController = MarkdownTextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _hasMoreMessages = true;
  bool _isLoadingMore = false;
  bool _isMuted = false;
  bool _isSending = false;
  String? _currentUserId;
  String _groupName = '';
  String? _groupAvatar;
  List<ChatParticipant> _participants = [];
  bool _showScrollDownFab = false;
  double _lastScrollOffset = 0;
  double _accumulatedScrollDown = 0;
  double _accumulatedScrollUp = 0;
  String? _highlightMessageId;
  final Map<String, GlobalKey> _messageKeys = {};
  final GlobalKey _inputKey = GlobalKey();
  double _inputHeight = 90.0;
  Timer? _highlightTimer;
  final List<String> _jumpHistory = [];
  final Map<String, Map<String, int>> _messageReactions = {}; // msgId → {emoji → count}
  final Map<String, Set<String>> _myReactions = {}; // msgId → Set<emoji>

  // WebSocket
  final WebSocketService _wsService = WebSocketService();
  StreamSubscription<WebSocketEvent>? _wsSubscription;
  bool _isTyping = false;
  Timer? _typingTimer;
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
  List<FeedItem> get _feedItems =>
      groupMessagesIntoFeedItems(_messages, isReversed: true);

  // Attachments state
  final ImagePicker _imagePicker = ImagePicker();
  final List<File> _attachedFiles = [];
  final List<String> _attachedFileNames = [];
  bool _isUploading = false;
  double _uploadProgress = 0.0;

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
      _uploadProgress = 0.0;
    });
  }

  void _cancelEditing() {
    _stopMyTyping();
    setState(() {
      _isEditing = false;
      _editingMessageId = null;
      _messageController.clear();
    });
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadData();
    _initWebSocket();

    // Connect continuous video note playback and PiP callbacks
    VideoNotePlaybackService().onPlayNextRequested = _playNextVideoNote;
    VideoNotePlaybackService().onScrollToMessageRequested = (id) => _scrollToMessage(id);

    // Connect continuous voice note playback
    VoicePlaybackService().onPlayNextRequested = _playNextVoiceNote;
    VoicePlaybackService().onScrollToMessageRequested = (id) => _scrollToMessage(id);

    _scrollController.addListener(() {
      if (!_scrollController.hasClients || _messages.isEmpty) return;

      // Пагинация: когда пользователь проскроллил вверх — загрузить ещё
      if (_hasMoreMessages && !_isLoadingMore) {
        final maxScroll = _scrollController.position.maxScrollExtent;
        final currentScroll = _scrollController.offset;
        if (maxScroll > 0 && (currentScroll >= maxScroll * 0.75 || (maxScroll - currentScroll) < 600)) {
          _loadMoreMessages();
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
      
      // Clear jump history when near bottom
      if (offset < 100 && _jumpHistory.isNotEmpty) {
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
      if (offset <= threshold) {
        shouldShow = false;
      } else if (_jumpHistory.isNotEmpty) {
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
    });

    // Notify provider that this chat is open (so unread count is not incremented)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        context.read<UnreadCountProvider>().setOpenChat(widget.chatId);
      } catch (_) {}
      NotificationService().cancelChatNotifications(widget.chatId, chatTitle: widget.groupName);
    });
  }

  void _initWebSocket() {
    // Subscribe to WebSocket events for this chat
    // Note: We only use eventStream.listen, not subscribe() to avoid duplicate handling
    _wsSubscription = _wsService.eventStream.listen(_handleWebSocketEvent);
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
    } else if (event.type == WebSocketEventType.userStatus) {
      _onUserStatusUpdate(event);
    } else if (event.type == WebSocketEventType.messageReactionUpdated) {
      final chatId = event.data['chat_id']?.toString();
      if (chatId == widget.chatId) {
        _onMessageReactionUpdated(event);
      }
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
        if (_typingUserId == message.senderId || _isTyping) {
          _typingTimer?.cancel();
          _isTyping = false;
          _typingUserId = null;
          _typingUserName = null;
        }
        _messages.insert(0, message);
      });
      // Don't auto-scroll to bottom on new message - user should stay at current position
      // _scrollToBottom(); // Removed: user should control scroll position
    }
  }

  void _onTypingIndicator(WebSocketEvent event) {
    // Show/hide scroll-down FAB logic
    final showFab = _scrollController.hasClients && _scrollController.offset > 200;
    if (showFab != _showScrollDownFab) {
      setState(() => _showScrollDownFab = showFab);
    }

    final chatId = event.data['chat_id']?.toString();
    if (chatId != widget.chatId) return;

    final typingUserId = event.data['user_id']?.toString();
    if (typingUserId == _currentUserId) return;

    final bool isTyping = event.data['is_typing'] != false;
    if (!isTyping) {
      if (mounted && _typingUserId == typingUserId) {
        _typingTimer?.cancel();
        setState(() {
          _isTyping = false;
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
      });

      // Clear typing indicator after 4 seconds (Telegram-like smooth window)
      _typingTimer?.cancel();
      _typingTimer = Timer(const Duration(seconds: 4), () {
        if (mounted) {
          setState(() {
            _isTyping = false;
            _typingUserId = null;
            _typingUserName = null;
          });
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
      _wsService.sendTypingIndicator(widget.chatId, isTyping: false);
    }
  }

  void _onMessageRead(WebSocketEvent event) {
    // Handle read status update
    final readerId = event.data['reader_id']?.toString();
    if (readerId == _currentUserId) return;

    if (mounted) {
      setState(() {
        // Mark all messages sent by current user as read
        for (int i = 0; i < _messages.length; i++) {
          if (_messages[i].senderId == _currentUserId) {
            _messages[i] = _messages[i].copyWith(isRead: true);
          }
        }
      });
    }
  }

  Future<void> _markMessagesAsRead() async {
    await ChatService.markMessagesAsRead(
      chatId: widget.chatId,
      chatTitle: widget.groupName,
    );
    // Notify via WebSocket that messages were read
    _wsService.sendMessageRead(widget.chatId);
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

    // Load messages
    await _loadMessages();

    // Scroll to initial message if specified
    if (widget.initialMessageId != null) {
      _scrollToMessage(widget.initialMessageId!);
    }

    // Mark messages as read when opening chat
    await _markMessagesAsRead();
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
      });
      _scrollToBottom();
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
              debugPrint('GroupChat: Drift saveMessages error: $e');
            }
          }
        });
        if (localMessages.isEmpty) {
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
      debugPrint('GroupChat: Drift loadMore error: $e');
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

      try {
        db.saveMessages(
            newMessages.map((m) => _messageToCompanion(m)).toList());
      } catch (e) {
        debugPrint('GroupChat: Drift saveMessages error: $e');
      }

      setState(() {
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
    _messageController.clear();
    setState(() {
      _isSending = true;
      _isUploading = _attachedFiles.isNotEmpty;
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
          final albumGroupedId =
              'album_${DateTime.now().millisecondsSinceEpoch}_${const Uuid().v4().substring(0, 8)}';

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
          setState(() {
            _uploadProgress = p;
          });
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
              if (mounted) {
                setState(() {
                  final idx =
                      _messages.indexWhere((m) => m.localId == pendingLocalId);
                  if (idx != -1) {
                    if (sentMessage is Message) {
                      _messages[idx] = sentMessage.copyWith(
                        localId: pendingLocalId,
                        sendStatus: 1, // sent
                        replyInfo: sentMessage.replyInfo ??
                            _messages[idx].replyInfo,
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
            debugPrint('ChatService.sendMessage in group returned false: $errMsg');
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
          debugPrint('ChatService.sendMessage in group exception: $e');
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
          _uploadProgress = 0.0;
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

  /// Scroll to a specific message and highlight it
  Future<void> _scrollToMessage(String messageId, {int retryCount = 0}) async {
    if (!mounted) return;

    final key = _messageKeys[messageId];
    if (key?.currentContext != null) {
      await Scrollable.ensureVisible(
        key!.currentContext!,
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeOut,
        alignment: 0.5,
      );
      _setHighlight(messageId);
      return;
    }

    final index = _messages.indexWhere((m) => m.id == messageId);
    if (index == -1) {
      if (_hasMoreMessages && retryCount < 5) {
        await _loadMoreMessages();
        return _scrollToMessage(messageId, retryCount: retryCount + 1);
      }
      return;
    }

    const estimatedItemHeight = 110.0;
    final targetOffset = index * estimatedItemHeight;

    if ((_scrollController.offset - targetOffset).abs() > 2000) {
      _scrollController.jumpTo(targetOffset);
    } else {
      await _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }

    await Future.delayed(const Duration(milliseconds: 100));
    
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
      _replyToMessage = message;
      _isQuote = false;
      _quoteText = null;
      _quoteOffset = 0;
      _quoteLength = 0;
    });
    // Optional: focus field
  }

  void _startQuote(Message message, String selectedText, int offset, int length) {
    setState(() {
      _replyToMessage = message;
      _isQuote = true;
      _quoteText = selectedText;
      _quoteOffset = offset;
      _quoteLength = length;
    });
    _messageController.selection = TextSelection.collapsed(
      offset: _messageController.text.length,
    );
  }

  void _cancelReply() {
    setState(() {
      _replyToMessage = null;
      _isQuote = false;
      _quoteText = null;
      _quoteOffset = 0;
      _quoteLength = 0;
    });
  }

  String _formatTime(String timestamp) {
    return DateTimeUtils.formatTimeHHmm(timestamp);
  }

  @override
  void dispose() {
    _stopMyTyping();
    _tabController.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _wsSubscription?.cancel();
    _typingTimer?.cancel();

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
      statusSubtitle = context.l10n
          .translate('chat_user_typing')
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
      canPop: !isKeyboardVisible,
      onPopInvoked: (didPop, _) {
        if (!didPop && isKeyboardVisible) {
          FocusScope.of(context).unfocus();
        }
      },
      appBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FloatingGlassAppBar(
            name: displayName,
            avatarUrl: widget.groupAvatar ?? _groupAvatar,
            isOnline: false, // Group itself doesn't have online status
            statusText: statusSubtitle,
            statusColor: _isTyping
                ? (Theme.of(context).brightness == Brightness.dark
                    ? const Color(0xFF5CB8E6)
                    : Theme.of(context).colorScheme.primary)
                : null,
            onBack: () => Navigator.pop(context),
            onTitleTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => GroupInfoScreen(
                    chatId: widget.chatId,
                    groupName: displayName,
                    groupAvatar: widget.groupAvatar ?? _groupAvatar,
                  ),
                )),
            onAvatarTap: () {
              GlassChatMenu.show(
                context,
                isMuted: _isMuted,
                onVoiceCall: () {
                  /* TODO: Voice call */
                },
                onVideoCall: () {
                  /* TODO: Video call */
                },
                onSearch: () {
                  /* TODO: Search */
                },
                onToggleMute: () {
                  setState(() => _isMuted = !_isMuted);
                  ChatService.setMuteNotifications(
                      chatId: widget.chatId, muted: _isMuted);
                },
                onClearHistory: () {
                  // TODO: Clear history dialog
                },
                onReport: () {
                  // TODO: Report dialog
                },
                onViewProfile: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => GroupInfoScreen(
                        chatId: widget.chatId,
                        groupName: displayName,
                        groupAvatar: widget.groupAvatar ?? _groupAvatar,
                      ),
                    )),
              );
            },
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
      body: tabBarView,
    );
  }

  Widget _buildChatTab() {
    final topPadding = MediaQuery.of(context).padding.top +
        kToolbarHeight +
        kTextTabBarHeight +
        24.0;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    final typingWidget = _isTyping
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
                  '$_typingUserName is typing...',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          )
        : null;

    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final effectiveBottom = bottomInset > 0 ? bottomInset : safeBottom;

    final messageList = ChatMessagesListView(
      isLoading: _isLoading,
      isLoadingMore: _isLoadingMore,
      itemCount: _feedItems.length,
      scrollController: _scrollController,
      topPadding: topPadding,
      bottomPadding: _inputHeight + effectiveBottom + 8,
      typingIndicator: typingWidget,
      itemBuilder: (context, index) => _buildFeedItem(index),
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        Positioned.fill(child: messageList),
        // Нижний scroll edge блюр: ПОД полем ввода (над сообщениями, но под полем ввода)
        ChatBottomScrollEdge(
          height: math.max(safeBottom + 52.0, 52.0),
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
          child: ScrollDownFab(
            visible: _showScrollDownFab,
            unreadCount: 0,
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
        // Плавающий кружочек видеосообщения (PiP), если активный кружок ушел из поля зрения
        const Positioned.fill(
          child: FloatingVideoNoteOverlay(),
        ),
      ],
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

    Widget albumWidget = MediaAlbumWidget(
      key: key,
      album: album,
      isMe: isMe,
      currentUserId: _currentUserId ?? '',
      senderName: isMe ? null : message.senderName,
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
    final currentDt =
        DateTimeUtils.parseUtcDateTime(message.createdAt) ?? DateTime.now();
    final prevDt = prevItem != null
        ? (DateTimeUtils.parseUtcDateTime(prevItem.createdAt) ?? DateTime.now())
        : null;
    final currentDate = DateTimeUtils.startOfDay(currentDt);
    final prevDate = prevDt != null ? DateTimeUtils.startOfDay(prevDt) : null;

    final items = <Widget>[];
    if (currentDate != prevDate) {
      items.add(DateSeparator(
          dateLabel: DateTimeUtils.formatDateSeparator(currentDt,
              context: context)));
    }
    items.add(albumWidget);

    return RepaintBoundary(child: Column(children: items));
  }

  Widget _buildMessageItem(Message message, int index) {
    final bool isMe = message.senderId == _currentUserId;
    final key = _messageKeys.putIfAbsent(message.id, () => GlobalKey());
    final isHighlighted = _highlightMessageId == message.id;

    Widget messageWidget = MessageBubble(
      key: key,
      message: message,
      isMe: isMe,
      currentUserId: _currentUserId ?? '',
      senderName: isMe ? null : message.senderName,
      isHighlighted: isHighlighted,
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
      enabled: true,
      child: messageWidget,
    );

    messageWidget = GestureDetector(
      onTap: () {
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

    final prevItem =
        index < _feedItems.length - 1 ? _feedItems[index + 1] : null;
    final currentDt =
        DateTimeUtils.parseUtcDateTime(message.createdAt) ?? DateTime.now();
    final prevDt = prevItem != null
        ? (DateTimeUtils.parseUtcDateTime(prevItem.createdAt) ?? DateTime.now())
        : null;
    final currentDate = DateTimeUtils.startOfDay(currentDt);
    final prevDate = prevDt != null ? DateTimeUtils.startOfDay(prevDt) : null;

    final items = <Widget>[];
    if (currentDate != prevDate) {
      items.add(DateSeparator(
          dateLabel: DateTimeUtils.formatDateSeparator(currentDt,
              context: context)));
    }
    items.add(messageWidget);

    return RepaintBoundary(child: Column(children: items));
  }

  Widget _buildMessageInput() {
    return ChatInputBar(
      controller: _messageController,
      hintText: 'Type a message...',
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
      onAttach: _showAttachmentPicker,
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
      final uploadResult = await _fileService.uploadFile(file);

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
      final uploadResult = await _fileService.uploadFileChunked(file);

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
      debugPrint('Error sending round video message in group chat: $e');
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
    }
  }

  /// Toggle reaction on a message — optimistic update + API call
  void _toggleReaction(String messageId, String emoji) {
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
      debugPrint('GroupChatScreen: error saving reactions to DB: $e');
    }

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
            'GroupChatScreen: toggleReaction returned success=false for msg=$messageId: ${res['message']}');
      }
    } catch (e) {
      debugPrint('GroupChatScreen: toggleReaction exception: $e');
    }
  }

  void _showContextMenu(Message message, bool isMe, GlobalKey key) {
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
      onPin: () {},
      onEdit: (isVideoNote || isVoiceNote) ? null : () {
        setState(() {
          _cancelReply();
          _messageController.loadMessage(message.content, message.entities);
          _isEditing = true;
          _editingMessageId = message.id;
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
    setState(() {
      _messages.removeWhere((m) => m.id == message.id);
    });

    try {
      await AppDatabase().deleteMessage(message.id);
    } catch (e) {
      debugPrint('GroupChatScreen: error deleting from DB: $e');
    }

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

  /// Called when a message becomes visible — marks as read via API
  void _onMessageVisible(String messageId) {
    // Use the same read-up-to API as private chat
    _markMessagesReadUpTo(messageId);
  }

  Future<void> _markMessagesReadUpTo(String messageId) async {
    try {
      final token = await AuthService.getToken();
      final dio = Dio();
      await dio.post(
        '${AppConfig.baseUrl}/api/chats/${widget.chatId}/messages/read-up-to',
        data: {'message_id': messageId},
        options: Options(headers: {'Authorization': 'Bearer $token'}),
      );
    } catch (_) {}
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
