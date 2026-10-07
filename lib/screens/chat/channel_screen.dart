import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:convert';
import '../../services/chat_service.dart';
import '../../services/auth_service.dart';
import '../../services/websocket_service.dart';
import '../../services/unread_count_provider.dart';
import '../../services/database/app_database.dart';
import '../../services/sync_service.dart';
import '../../services/notification_service.dart';
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

// --- НАСТРОЙКИ СТИЛЯ СООБЩЕНИЙ ---
/// Радиус скругления «облачка» сообщения в канале.
const double _kChannelMessageBorderRadius = 12.0;
// ---------------------------------

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

class _ChannelScreenState extends State<ChannelScreen> {
  final List<Message> _messages = [];
  final MarkdownTextEditingController _messageController = MarkdownTextEditingController();
  final ScrollController _scrollController = ScrollController();

  bool _isLoading = true;
  bool _hasMoreMessages = true;
  bool _isLoadingMore = false;
  bool _isSending = false;
  String? _currentUserId;
  String _channelName = '';
  String? _channelAvatar;
  int _subscriberCount = 0;
  bool _isAdmin = false;
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

  // Reply / Quote state
  Message? _replyToMessage;
  bool _isQuote = false;
  String? _quoteText;
  int _quoteOffset = 0;
  int _quoteLength = 0;

  // WebSocket
  final WebSocketService _wsService = WebSocketService();
  StreamSubscription<WebSocketEvent>? _wsSubscription;

  @override
  void initState() {
    super.initState();
    _highlightMessageId = widget.highlightMessageId;
    _loadData();
    _initWebSocket();

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
        context.read<UnreadCountProvider>().setOpenChat(widget.channelId);
      } catch (_) {}
      NotificationService().cancelChatNotifications(widget.channelId, chatTitle: widget.channelName);
    });
  }

  void _initWebSocket() {
    // Subscribe to WebSocket events for this channel
    // Note: We only use eventStream.listen, not subscribe() to avoid duplicate handling
    _wsSubscription = _wsService.eventStream.listen(_handleWebSocketEvent);
  }

  void _handleWebSocketEvent(WebSocketEvent event) {
    if (event.type == WebSocketEventType.newMessage) {
      final chatId = event.data['chat_id']?.toString();
      if (chatId == widget.channelId) {
        _onNewMessage(event);
      }
    } else if (event.type == WebSocketEventType.messageEdited) {
      final chatId = event.data['chat_id']?.toString();
      if (chatId == widget.channelId) {
        _onMessageEdited(event);
      }
    } else if (event.type == WebSocketEventType.messageDeleted) {
      final chatId = event.data['chat_id']?.toString();
      if (chatId == widget.channelId) {
        _onMessageDeleted(event);
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
    } catch (_) {}
  }

  void _onMessageEdited(WebSocketEvent event) {
    final messageId = event.data['message_id']?.toString();
    final newContent = event.data['content']?.toString();
    if (messageId == null || newContent == null) return;

    if (mounted) {
      setState(() {
        final index = _messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          _messages[index] = _messages[index].copyWith(
            content: newContent,
            isEdited: true,
          );
        }
      });
    }

    try {
      AppDatabase().updateMessageContent(messageId, newContent);
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
        _messages.insert(0, message);
      });
      // Don't auto-scroll to bottom on new message - user should stay at current position
      // _scrollToBottom(); // Removed: user should control scroll position
    }
  }

  Future<void> _markMessagesAsRead() async {
    await ChatService.markMessagesAsRead(
      chatId: widget.channelId,
      chatTitle: widget.channelName,
    );
    // Notify via WebSocket that messages were read
    _wsService.sendMessageRead(widget.channelId);
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

    // Сначала попробовать загрузить из Drift
    final db = AppDatabase();
    try {
      final localMessages = await db.getMessages(
        widget.channelId,
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
      debugPrint('Channel: Drift loadMore error: $e');
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
      chatId: widget.channelId,
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
        debugPrint('Channel: Drift saveMessages error: $e');
      }

      setState(() {
        for (final m in newMessages) {
          if (!_messages.any((existing) => existing.id == m.id)) {
            _messages.add(m);
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

    const estimatedItemHeight = 120.0;
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

    final replyTo = _replyToMessage;
    final replyIsQuote = _isQuote;
    final replyQuoteText = _quoteText;
    final replyQuoteOffset = _quoteOffset;
    final replyQuoteLength = _quoteLength;

    _messageController.clear();
    setState(() {
      _isSending = true;
      _replyToMessage = null;
      _isQuote = false;
      _quoteText = null;
      _quoteOffset = 0;
      _quoteLength = 0;
    });

    final parsed = cleanText != null ? null : EntityParser.parseMarkdown(text);
    final String effectiveContent = cleanText ?? parsed!.cleanText;
    final List<MessageEntity>? effectiveEntities =
        entities ?? (parsed?.entities.isNotEmpty == true ? parsed!.entities : null);

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

  void _startReply(Message message) {
    setState(() {
      _replyToMessage = message;
      _isQuote = false;
      _quoteText = null;
      _quoteOffset = 0;
      _quoteLength = 0;
    });
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
    _messageController.dispose();
    _scrollController.dispose();
    _wsSubscription?.cancel();

    _updateInputHeight();

    // Clear the open chat indicator in the provider
    try {
      context.read<UnreadCountProvider>().setOpenChat(null);
    } catch (_) {}

    super.dispose();
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
    final bool isKeyboardVisible = bottomInset > 0;

    final String subscriberText = context.l10n
        .translate('chat_status_subscribers_count')
        .replaceAll('{count}', _subscriberCount.toString());

    return ChatScaffold(
      canPop: !isKeyboardVisible,
      onPopInvoked: (didPop, _) {
        if (!didPop && isKeyboardVisible) {
          FocusScope.of(context).unfocus();
        }
      },
      appBar: FloatingGlassAppBar(
        name: displayName,
        avatarUrl: widget.channelAvatar ?? _channelAvatar,
        isOnline: false, // Channel doesn't have online status
        statusText: subscriberText,
        isChannel: true, // Calls hidden in channel
        isMuted: false, // TODO: Get muted state
        onBack: () => Navigator.pop(context),
        onTitleTap: () {
          // TODO: Open channel info
        },
        onViewProfile: () {
          // TODO: View channel info
        },
        onSearch: () {
          // TODO: Search
        },
        onToggleMute: () {
          // TODO: Toggle notifications
        },
        onClearHistory: () {
          // TODO: Clear history
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
          } else {
            _scrollController.animateTo(
              0,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            );
          }
        },
      ),
      body: ChatMessagesListView(
        isLoading: _isLoading,
        isLoadingMore: _isLoadingMore,
        itemCount: _messages.length,
        scrollController: _scrollController,
        topPadding: topPadding,
        bottomPadding: _isAdmin ? _inputHeight + 8 : 16,
        emptyTitle: 'No posts yet',
        itemBuilder: (context, index) {
          final message = _messages[index];
          return _buildChannelMessage(message);
        },
      ),
      bottomBar: _isAdmin
          ? Container(
              key: _inputKey,
              child: _buildMessageInput(),
            )
          : null,
    );
  }

  Widget _buildChannelMessage(Message message) {
    final key = _messageKeys.putIfAbsent(message.id, () => GlobalKey());
    final isHighlighted = message.id == _highlightMessageId;
    final bool isBigEmoji = message.messageType == 'text' &&
        message.fileUrl == null &&
        !message.hasReply &&
        _isSingleEmoji(message.content);

    Widget messageWidget = AnimatedContainer(
      key: key,
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      width: double.infinity,
      color: isHighlighted
          ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.15)
          : Colors.transparent,
      child: isBigEmoji
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 16.0),
              child: Align(
                alignment: Alignment.centerLeft, // Channels usually left-aligned
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final double emojiFontSize = 64.0;
                    
                    Widget metadataRow = Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.35),
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
                          Text(
                            '0',
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _formatTime(message.createdAt),
                            style: const TextStyle(color: Colors.white, fontSize: 10),
                          ),
                        ],
                      ),
                    );

                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        GestureDetector(
                          child: EmojiUtils.getAnimatedEmojiPath(message.content) != null
                              ? LottieEmoji(
                                  assetPath: EmojiUtils.getAnimatedEmojiPath(message.content)!,
                                  emoji: message.content,
                                  width: emojiFontSize * 1.8,
                                  height: emojiFontSize * 1.8,
                                  onTap: () => HapticUtils.tap(),
                                  isMe: false, // In channels usually left-aligned effects
                                  autoPlay: DateTime.tryParse(message.createdAt)
                                          ?.toLocal()
                                          .isAfter(DateTime.now().subtract(
                                              const Duration(seconds: 2))) ??
                                      false,
                                )
                              : Padding(
                                  padding: const EdgeInsets.only(right: 10.0),
                                  child: EmojiUtils.appleEmoji(
                                    message.content,
                                    size: emojiFontSize,
                                  ),
                                ),
                        ),
                        Positioned(
                          bottom: 12,
                          right: -16,
                          child: metadataRow,
                        ),
                      ],
                    );
                  },
                ),
              ),
            )
          : Card(
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
              if (message.messageType != 'text' && message.fileUrl != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8.0),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(8.0),
                    child: Image.network(
                      message.fileUrl!,
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
                  final textStyle = Theme.of(context).textTheme.bodyMedium;
                  // Conservative estimate for metadata width (Views + Time + Icons + Padding)
                  const double metadataWidth = 85.0;
                  const double safetyMargin = 12.0;
                  final double maxContentWidth = constraints.maxWidth;

                  final TextPainter textPainter = TextPainter(
                    text: TextSpan(text: message.content, style: textStyle),
                    textDirection: TextDirection.ltr,
                  )..layout(maxWidth: maxContentWidth);

                  final lineMetrics = textPainter.computeLineMetrics();
                  final double lastLineWidth =
                      lineMetrics.isNotEmpty ? lineMetrics.last.width : 0;

                  // Check if content ends with a block element (Code block or LaTeX)
                  final bool endsWithBlock = message.content.trim().endsWith('```') ||
                                             message.content.trim().endsWith('\$\$');

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
                      Stack(
                        clipBehavior: Clip.none,
                        children: [
                          TextMessageWidget(
                            text: message.content,
                            isMe: false,
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
                      if (!fitsInline)
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

    // Wrap with SwipeToReplyWrapper for swipe-to-reply gesture
    return SwipeToReplyWrapper(
      onReply: () => _startReply(message),
      enabled: _isAdmin, // Users can only reply if they can post (simple rule for now)
      child: messageWidget,
    );
  }

  Widget _buildMessageInput() {
    return ChatInputBar(
      controller: _messageController,
      hintText: 'Write a post...',
      replyToMessage: _replyToMessage,
      isQuote: _isQuote,
      quoteText: _quoteText,
      onCancelReply: _cancelReply,
      onTapReply: _replyToMessage != null ? () => _scrollToMessage(_replyToMessage!.id) : null,
      onSend: _sendMessage,
      onSendDetailed: (cleanText, entities, linkPreviewOptions, invertMedia) {
        _sendMessage(
          cleanText: cleanText,
          entities: entities,
          linkPreviewOptions: linkPreviewOptions,
          invertMedia: invertMedia,
        );
      },
      currentUserId: _currentUserId,
      isSending: _isSending,
    );
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
