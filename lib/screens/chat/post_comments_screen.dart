import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../l10n/app_localizations.dart';
import '../../models/name_color_preset.dart';
import '../../models/profile_customization.dart';
import '../../models/theav_theme.dart';
import '../../services/auth_service.dart';
import '../../services/chat_actions_helper.dart';
import '../../services/chat_realtime_manager.dart';
import '../../services/chat_service.dart';
import '../../services/database/app_database.dart';
import '../../services/file_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/groups_channels_parity_service.dart';
import '../../services/message_context_menu_service.dart';
import '../../services/peer_customization_cache.dart';
import '../../services/screen_protection_service.dart';
import '../../services/sticker_service.dart';
import '../../services/tiling_layout_controller.dart';
import '../../services/websocket_service.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/image_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../../widgets/chat/attachment_picker_bottom_sheet.dart';
import '../../widgets/chat/channel_post_card.dart';
import '../../widgets/chat/chat_input_bar.dart';
import '../../widgets/chat/chat_scaffold.dart';
import '../../widgets/chat/emoji_sticker_panel.dart';
import '../../widgets/chat/floating_glass_app_bar.dart';
import '../../widgets/chat/forward_chat_picker_sheet.dart';
import '../../widgets/chat/groups_channels_parity_widgets.dart';
import '../../widgets/chat/liquid_glass_input_field.dart';
import '../../widgets/chat/swipe_to_reply_wrapper.dart';
import '../../widgets/chat/unread_separator.dart';
import '../../widgets/message/fullscreen_photo_viewer.dart';
import '../../widgets/message/group_message_avatar_row.dart';
import '../../widgets/message/message_bubble.dart';
import '../settings/profile_screen.dart';
import 'channel_screen.dart';
import 'media_send_screen.dart';
import 'poll_create_screen.dart';

/// Discussion thread screen for a single channel post (`GET/POST /api/chats/:id/messages/:messageId/comments`).
class PostCommentsScreen extends StatefulWidget {
  final String channelId;
  final Message postMessage;
  final String? channelName;
  final String? channelAvatar;
  final String? linkedChatId;
  final bool showAuthorProfiles;
  final bool signMessages;
  final ReactionSettings? reactionSettings;

  const PostCommentsScreen({
    Key? key,
    required this.channelId,
    required this.postMessage,
    this.channelName,
    this.channelAvatar,
    this.linkedChatId,
    this.showAuthorProfiles = false,
    this.signMessages = false,
    this.reactionSettings,
  }) : super(key: key);

  @override
  State<PostCommentsScreen> createState() => _PostCommentsScreenState();
}

class _PostCommentsScreenState extends State<PostCommentsScreen>
    with SingleTickerProviderStateMixin {
  final ScrollController _scrollController = ScrollController();
  final MarkdownTextEditingController _messageController =
      MarkdownTextEditingController();
  final FocusNode _inputFocusNode = FocusNode();
  final GlobalKey _inputKey = GlobalKey();
  final ImagePicker _imagePicker = ImagePicker();
  final FileService _fileService = FileService();
  final ValueNotifier<double> _uploadProgressNotifier = ValueNotifier<double>(
    0.0,
  );
  final ValueNotifier<bool> _showScrollDownFabNotifier = ValueNotifier<bool>(
    false,
  );
  final Map<String, GlobalKey> _commentKeys = {};
  final Set<String> _selectedCommentIds = <String>{};

  late Message _rootPost;
  final List<Message> _comments = [];
  String? _currentUserId;
  String? _linkedChatId;
  String? _rootMessageId;
  int _commentsCount = 0;
  bool _hasMore = false;
  bool _isLoading = true;
  bool _isLoadingOlder = false;
  bool _isSending = false;
  bool _isUploading = false;
  double _inputHeight = 64.0;
  String? _errorMessage;

  // Reply / Edit state
  Message? _replyToComment;
  bool _isQuote = false;
  String? _quoteText;
  int _quoteOffset = 0;
  int _quoteLength = 0;
  bool _isEditing = false;
  String? _editingCommentId;

  // Attachments
  final List<File> _attachedFiles = [];
  final List<String> _attachedFileNames = [];

  // Emoji panel
  bool _showEmojiPanel = false;
  bool _isKeyboardRising = false;
  bool _isKeyboardFalling = false;
  double _keyboardHeight = 270.0;
  double _lastBottomInset = 0.0;
  Timer? _transitionTimer;
  late AnimationController _emojiPanelController;
  late Animation<double> _emojiPanelAnimation;
  late final ChatStickerInputTarget _stickerInputTarget;

  // Realtime subscriptions
  ChatSubscription? _channelSubscription;
  ChatSubscription? _groupSubscription;

  // Wave 3B parity state
  bool _canComment = true;
  List<SendAsPeer> _sendAsPeers = [];
  String? _selectedSendAsChatId;

  String get _screenProtectionKey =>
      'post_comments_${widget.channelId}_${widget.postMessage.id}';

  bool get _isMobilePlatform =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);
  bool get _isSelectionMode => _selectedCommentIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    _rootPost = widget.postMessage;
    _commentsCount = widget.postMessage.commentsCount;
    _linkedChatId =
        (widget.linkedChatId != null && widget.linkedChatId!.isNotEmpty)
        ? widget.linkedChatId
        : null;

    _emojiPanelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _emojiPanelAnimation = CurvedAnimation(
      parent: _emojiPanelController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _stickerInputTarget = ChatStickerInputTarget(
      chatId: _linkedChatId ?? widget.channelId,
      chatTitle: widget.channelName,
      avatarUrl: widget.channelAvatar,
      controller: _messageController,
      onBackspace: _handleBackspace,
      onInsertEmoji: _insertEmojiText,
      onInsertCustomEmoji: _insertCustomEmojiItem,
      onSendSticker: _sendStickerComment,
      onSendGif: _sendGifComment,
    );
    StickerService.instance.registerInputTarget(_stickerInputTarget);
    _inputFocusNode.addListener(_onFocusChanged);
    _scrollController.addListener(_onScroll);

    _loadCachedKeyboardHeight();
    _initChannelSubscription();
    _bindLinkedGroupSubscription();
    _loadInitial();
  }

  @override
  void dispose() {
    _transitionTimer?.cancel();
    StickerService.instance.unregisterInputTarget(_stickerInputTarget);
    _emojiPanelController.dispose();
    _inputFocusNode.removeListener(_onFocusChanged);
    _inputFocusNode.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _uploadProgressNotifier.dispose();
    _showScrollDownFabNotifier.dispose();
    _channelSubscription?.cancel();
    _groupSubscription?.cancel();
    unawaited(ScreenProtectionService.instance.release(_screenProtectionKey));
    super.dispose();
  }

  void _syncScreenProtection(bool protect) {
    unawaited(ScreenProtectionService.instance.sync(_screenProtectionKey, protect));
  }

  Future<void> _syncProtectionFromDb() async {
    try {
      final db = AppDatabase();
      final channelChat = await db.getChat(widget.channelId);
      final linkedChat = (_linkedChatId != null && _linkedChatId!.isNotEmpty)
          ? await db.getChat(_linkedChatId!)
          : null;
      if (!mounted) return;
      final bool protect =
          (channelChat?.hasProtectedContent == true) ||
          (linkedChat?.hasProtectedContent == true);
      _syncScreenProtection(protect);
    } catch (_) {}
  }

  Future<void> _loadSendAsPeers() async {
    final targetChatId = _linkedChatId;
    if (targetChatId == null || targetChatId.isEmpty) return;
    try {
      final res = await GroupsChannelsParityService.getSendAsPeers(
        targetChatId,
      );
      if (!mounted) return;
      setState(() {
        _sendAsPeers = res.peers;
        _selectedSendAsChatId = res.selectedSendAsChatId;
      });
    } catch (_) {}
  }

  SendAsPeer? get _activeSendAsPeer {
    if (_sendAsPeers.isEmpty) return null;
    final sel = _selectedSendAsChatId;
    if (sel != null && sel.isNotEmpty) {
      for (final p in _sendAsPeers) {
        if (p.isChannel && (p.chatId == sel || p.id == sel)) {
          return p;
        }
      }
    }
    for (final p in _sendAsPeers) {
      if (p.isSelected) return p;
    }
    return _sendAsPeers.first;
  }

  Future<void> _openSendAsPicker() async {
    final targetChatId = _linkedChatId;
    if (targetChatId == null || targetChatId.isEmpty || _sendAsPeers.isEmpty) {
      return;
    }
    final picked = await showSendAsPeerSheet(
      context: context,
      chatId: targetChatId,
      peers: _sendAsPeers,
      selectedSendAsChatId: _selectedSendAsChatId,
    );
    if (picked != null && mounted) {
      setState(() {
        _selectedSendAsChatId = picked.isChannel
            ? (picked.chatId ?? picked.id)
            : null;
      });
    }
  }

  void _openChannelProfileById(
    String channelId, {
    String? name,
    String? avatarUrl,
  }) {
    if (channelId.isEmpty) return;
    HapticUtils.tap();
    Navigator.push(
      context,
      SwipeBackPageRoute(
        builder: (_) => ChannelScreen(
          channelId: channelId,
          channelName: name,
          channelAvatar: avatarUrl,
        ),
      ),
    );
  }

  Future<void> _loadCachedKeyboardHeight() async {
    final prefs = await SharedPreferences.getInstance();
    final cached = prefs.getDouble('cached_keyboard_height');
    if (cached != null && cached > 150 && mounted) {
      setState(() => _keyboardHeight = cached);
    }
  }

  Future<void> _saveKeyboardHeight(double height) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('cached_keyboard_height', height);
  }

  void _onFocusChanged() {
    if (_inputFocusNode.hasFocus) {
      StickerService.instance.registerInputTarget(_stickerInputTarget);
    }
    if (_inputFocusNode.hasFocus && _showEmojiPanel && !_isMobilePlatform) {
      _closeEmojiPanel();
    }
  }

  void _onScroll() {
    if (!_scrollController.hasClients) return;
    final pos = _scrollController.position;
    final bool shouldShowFab =
        pos.maxScrollExtent > 120 && (pos.maxScrollExtent - pos.pixels) > 140;
    if (shouldShowFab != _showScrollDownFabNotifier.value) {
      _showScrollDownFabNotifier.value = shouldShowFab;
    }
  }

  void _initChannelSubscription() {
    _channelSubscription = ChatRealtimeManager().bindChat(
      chatId: widget.channelId,
      onPostCommentsUpdated: _onPostCommentsUpdated,
      onMessageEdited: (event) {
        final mid = event.data['message_id']?.toString();
        if (mid == widget.postMessage.id && mounted) {
          setState(() {
            _rootPost = _rootPost.copyWith(
              content: event.data['content']?.toString() ?? _rootPost.content,
              isEdited: true,
            );
          });
        }
      },
      onReactionUpdated: (event) {
        final mid = event.data['message_id']?.toString();
        if (mid == widget.postMessage.id) {
          _applyReactionEventToPost(event);
        }
      },
    );
  }

  void _bindLinkedGroupSubscription() {
    final groupId = _linkedChatId;
    if (groupId == null || groupId.isEmpty) return;
    if (_groupSubscription?.chatId == groupId) return;

    _groupSubscription?.cancel();
    _groupSubscription = ChatRealtimeManager().bindChat(
      chatId: groupId,
      onNewMessage: _onLinkedGroupNewMessage,
      onMessageEdited: _onLinkedGroupMessageEdited,
      onMessageDeleted: _onLinkedGroupMessageDeleted,
      onReactionUpdated: _onLinkedGroupReactionUpdated,
      onReconnect: _refreshLatestComments,
    );
  }

  void _onPostCommentsUpdated(WebSocketEvent event) {
    final msgId = (event.data['message_id'] ?? event.data['post_id'] ?? '')
        .toString();
    final rawIds = event.data['message_ids'];
    final bool matchesIds =
        rawIds is List && rawIds.any((e) => e.toString() == _rootPost.id);
    if (msgId != _rootPost.id && !matchesIds) return;

    final linkedId = event.data['linked_chat_id']?.toString().trim();
    if (linkedId != null && linkedId.isNotEmpty && linkedId != _linkedChatId) {
      _linkedChatId = linkedId;
      _bindLinkedGroupSubscription();
    }
    final rootMsgId = event.data['root_message_id']?.toString().trim();
    if (rootMsgId != null && rootMsgId.isNotEmpty) {
      _rootMessageId ??= rootMsgId;
    }

    final int? updatedCount = event.data['comments_count'] is num
        ? (event.data['comments_count'] as num).toInt()
        : int.tryParse(event.data['comments_count']?.toString() ?? '');
    final updatedRepliers = RecentReplier.parseList(
      event.data['recent_repliers'],
    );
    final rawComment = event.data['comment'];
    final Message? incomingComment = rawComment is Map
        ? Message.fromJson(Map<String, dynamic>.from(rawComment))
        : null;

    if (!mounted) return;
    setState(() {
      if (updatedCount != null) {
        _commentsCount = updatedCount;
        _rootPost = _rootPost.copyWith(
          commentsCount: updatedCount,
          recentRepliers: updatedRepliers.isNotEmpty
              ? updatedRepliers
              : _rootPost.recentRepliers,
        );
      }
      if (incomingComment != null) {
        _upsertComment(incomingComment);
      }
    });
  }

  void _onLinkedGroupNewMessage(WebSocketEvent event) {
    final rawMsg =
        (event.data['message'] as Map<String, dynamic>?) ??
        (event.data.containsKey('content') && event.data.containsKey('id')
            ? event.data
            : null);
    if (rawMsg == null) return;
    final msg = Message.fromJson(rawMsg);
    final threadRoot = msg.threadRootMessageId?.trim();
    if (threadRoot == null || threadRoot.isEmpty) return;

    if (_rootMessageId != null && threadRoot != _rootMessageId) {
      return;
    }
    if (_rootMessageId == null) {
      return;
    }

    final wasAtBottom =
        !_scrollController.hasClients ||
        (_scrollController.position.maxScrollExtent -
                _scrollController.offset) <
            120;

    if (!mounted) return;
    setState(() {
      final isNew = _upsertComment(msg);
      if (isNew) {
        _commentsCount = math.max(_commentsCount + 1, _comments.length);
        _rootPost = _rootPost.copyWith(commentsCount: _commentsCount);
      }
    });
    if (wasAtBottom) {
      _scrollToBottom();
    }
  }

  void _onLinkedGroupMessageEdited(WebSocketEvent event) {
    final msgId = event.data['message_id']?.toString();
    if (msgId == null || !mounted) return;
    final newContent = event.data['content']?.toString();
    setState(() {
      final idx = _comments.indexWhere((c) => c.id == msgId);
      if (idx != -1) {
        _comments[idx] = _comments[idx].copyWith(
          content: newContent ?? _comments[idx].content,
          isEdited: true,
        );
      }
    });
  }

  void _onLinkedGroupMessageDeleted(WebSocketEvent event) {
    final msgId = event.data['message_id']?.toString();
    if (msgId == null || !mounted) return;
    setState(() {
      final before = _comments.length;
      _comments.removeWhere((c) => c.id == msgId);
      if (_comments.length < before && _commentsCount > 0) {
        _commentsCount--;
        _rootPost = _rootPost.copyWith(commentsCount: _commentsCount);
      }
    });
  }

  void _onLinkedGroupReactionUpdated(WebSocketEvent event) {
    final msgId = event.data['message_id']?.toString();
    if (msgId == null || !mounted) return;
    final idx = _comments.indexWhere((c) => c.id == msgId);
    if (idx == -1) return;

    final parsed = _parseReactionPayload(event.data, _comments[idx]);
    setState(() {
      _comments[idx] = _comments[idx].copyWith(
        reactions: parsed.$1,
        myReactions: parsed.$2,
      );
    });
  }

  void _applyReactionEventToPost(WebSocketEvent event) {
    if (!mounted) return;
    final parsed = _parseReactionPayload(event.data, _rootPost);
    setState(() {
      _rootPost = _rootPost.copyWith(
        reactions: parsed.$1,
        myReactions: parsed.$2,
      );
    });
  }

  (Map<String, int>, Set<String>) _parseReactionPayload(
    Map<String, dynamic> data,
    Message current,
  ) {
    final reactionsMap = <String, int>{};
    if (data['reactions'] is List) {
      for (final r in data['reactions'] as List) {
        if (r is Map && r['emoji'] != null && r['count'] != null) {
          final cnt = (r['count'] as num).toInt();
          if (cnt > 0) {
            reactionsMap[r['emoji'].toString()] = cnt;
          }
        }
      }
    }
    final mySet = Set<String>.from(current.myReactions);
    final userId = data['user_id']?.toString();
    final emoji = data['emoji']?.toString();
    final action = data['action']?.toString();
    final bool? active = data['active'] is bool ? data['active'] as bool : null;
    if (userId != null && userId == _currentUserId && emoji != null) {
      if (action == 'added' || active == true) {
        mySet.add(emoji);
      } else if (action == 'removed' || active == false) {
        mySet.remove(emoji);
      }
    }
    return (reactionsMap, mySet);
  }

  bool _upsertComment(Message incoming) {
    final idx = _comments.indexWhere(
      (c) =>
          c.id == incoming.id ||
          (incoming.localId != null &&
              incoming.localId!.isNotEmpty &&
              c.localId == incoming.localId),
    );
    if (idx != -1) {
      final existing = _comments[idx];
      _comments[idx] = incoming.copyWith(
        localId: existing.localId ?? incoming.localId,
        sendStatus: 1,
        replyInfo: incoming.replyInfo ?? existing.replyInfo,
      );
      return false;
    }
    _comments.add(incoming);
    _sortCommentsAscending();
    return true;
  }

  void _sortCommentsAscending() {
    _comments.sort((a, b) {
      final dtA = DateTimeUtils.parseUtcDateTime(a.createdAt);
      final dtB = DateTimeUtils.parseUtcDateTime(b.createdAt);
      if (dtA != null && dtB != null) {
        final cmp = dtA.compareTo(dtB);
        if (cmp != 0) return cmp;
      }
      return (int.tryParse(a.id) ?? 0).compareTo(int.tryParse(b.id) ?? 0);
    });
  }

  Future<void> _loadInitial() async {
    _currentUserId = await AuthService.getUserId();

    // Load cached thread comments from Drift if we already have linkedChatId
    if (_linkedChatId != null && _rootMessageId != null) {
      try {
        final local = await AppDatabase().getThreadComments(
          _linkedChatId!,
          _rootMessageId!,
          limit: 100,
        );
        if (local.isNotEmpty && mounted) {
          setState(() {
            _comments
              ..clear()
              ..addAll(local.map((m) => Message.fromDbMessage(m)));
            _sortCommentsAscending();
            _isLoading = false;
          });
        }
      } catch (_) {}
    }

    unawaited(_syncProtectionFromDb());
    await _refreshLatestComments();
  }

  Future<void> _refreshLatestComments() async {
    final res = await ChatService.getPostComments(
      channelId: widget.channelId,
      messageId: widget.postMessage.id,
      limit: 50,
    );
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      if (res.success) {
        _errorMessage = null;
        _canComment = res.canComment;
        if (!res.canComment && _showEmojiPanel) {
          _showEmojiPanel = false;
        }
        if (res.linkedChatId != null && res.linkedChatId!.isNotEmpty) {
          _linkedChatId = res.linkedChatId;
        }
        if (res.rootPost != null) {
          _rootPost = res.rootPost!;
        }
        _hasMore = res.hasMore;

        for (final c in res.comments) {
          if (c.threadRootMessageId != null &&
              c.threadRootMessageId!.isNotEmpty) {
            _rootMessageId ??= c.threadRootMessageId;
          }
          _upsertComment(c);
        }
        _commentsCount = math.max(
          _rootPost.commentsCount,
          _comments.length,
        );
      } else {
        _errorMessage = res.errorMessage;
      }
    });
    _bindLinkedGroupSubscription();
    unawaited(_syncProtectionFromDb());
    if (_canComment && _linkedChatId != null && _linkedChatId!.isNotEmpty) {
      unawaited(_loadSendAsPeers());
    }
  }

  Future<void> _loadOlderComments() async {
    if (_isLoadingOlder || !_hasMore || _comments.isEmpty) return;
    String? oldestServerId;
    for (final c in _comments) {
      if (int.tryParse(c.id) != null) {
        oldestServerId = c.id;
        break;
      }
    }
    if (oldestServerId == null) return;

    setState(() => _isLoadingOlder = true);
    final res = await ChatService.getPostComments(
      channelId: widget.channelId,
      messageId: widget.postMessage.id,
      limit: 50,
      beforeId: oldestServerId,
    );
    if (!mounted) return;
    setState(() {
      _isLoadingOlder = false;
      if (res.success) {
        _hasMore = res.hasMore;
        for (final c in res.comments) {
          _upsertComment(c);
        }
      }
    });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
      );
    });
  }

  void _scrollToTop() {
    if (!_scrollController.hasClients) return;
    _scrollController.animateTo(
      0.0,
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _sendComment({
    String? cleanText,
    List<MessageEntity>? entities,
    LinkPreviewOptions? linkPreviewOptions,
    bool invertMedia = false,
    bool hasMediaSpoiler = false,
    bool asDocument = false,
  }) async {
    if (!_canComment) return;
    final String controllerClean = _messageController.cleanText.trimRight();
    final List<MessageEntity> controllerEntities = _messageController.entities;
    final String text = (cleanText ?? controllerClean).trimRight();
    final List<MessageEntity> resolvedEntities = entities ?? controllerEntities;
    if ((text.trim().isEmpty && _attachedFiles.isEmpty) || _isSending) return;

    if (_isEditing && _editingCommentId != null) {
      final editId = _editingCommentId!;
      final targetChatId = _linkedChatId ?? widget.channelId;
      _cancelEditing();
      final res = await ChatService.editMessage(
        chatId: targetChatId,
        messageId: editId,
        content: text,
        entities: resolvedEntities.isNotEmpty ? resolvedEntities : null,
      );
      if (!mounted) return;
      if (res['success'] == true) {
        setState(() {
          final idx = _comments.indexWhere((c) => c.id == editId);
          if (idx != -1) {
            _comments[idx] = _comments[idx].copyWith(
              content: text,
              entities: resolvedEntities,
              isEdited: true,
            );
          }
        });
      } else {
        GlassToastService().show(
          context,
          res['message']?.toString() ?? 'Не удалось отредактировать',
        );
      }
      return;
    }

    final replyTo = _replyToComment;
    final bool capturedIsQuote = _isQuote;
    final String? capturedQuoteText = _quoteText;
    final int capturedQuoteOffset = _quoteOffset;
    final int capturedQuoteLength = _quoteLength;
    final String? activeSendAsChatId = _selectedSendAsChatId;
    final SendAsPeer? activeSendAsPeer = _activeSendAsPeer;
    final bool sendingAsChannel =
        activeSendAsChatId != null &&
        activeSendAsChatId.isNotEmpty &&
        activeSendAsPeer != null &&
        activeSendAsPeer.isChannel;

    final List<File> filesToSend = List<File>.from(_attachedFiles);
    _attachedFiles.clear();
    _attachedFileNames.clear();
    _messageController.clear();
    setState(() {
      _isSending = true;
      _isUploading = filesToSend.isNotEmpty;
      _replyToComment = null;
      _isQuote = false;
      _quoteText = null;
      _quoteOffset = 0;
      _quoteLength = 0;
    });

    try {
      String? fileUrl;
      String? fileName;
      String messageType = 'text';
      if (filesToSend.isNotEmpty) {
        final file = filesToSend.first;
        final uploadRes = await _fileService.uploadFileChunked(
          file,
          onProgress: (p) {
            if (mounted) _uploadProgressNotifier.value = p;
          },
        );
        fileUrl = uploadRes.url;
        fileName = uploadRes.fileName;
        if (asDocument) {
          messageType = 'file';
        } else if (uploadRes.mimeType.startsWith('image/')) {
          messageType = 'image';
        } else if (uploadRes.mimeType.startsWith('video/')) {
          messageType = 'video';
        } else if (uploadRes.mimeType.startsWith('audio/')) {
          messageType = 'audio';
        } else {
          messageType = 'file';
        }
      }

      final localId = 'local_comment_${DateTime.now().microsecondsSinceEpoch}';
      final optimistic = Message(
        id: localId,
        localId: localId,
        chatId: _linkedChatId ?? widget.channelId,
        senderId: _currentUserId ?? '',
        content: text,
        messageType: messageType,
        fileUrl: fileUrl,
        fileName: fileName,
        replyToMessageId: replyTo?.id,
        replyInfo: replyTo != null
            ? ReplyInfo(
                messageId: replyTo.id,
                senderId: replyTo.senderId,
                senderName: replyTo.senderName,
                content: replyTo.content,
                messageType: replyTo.messageType,
                entities: replyTo.entities,
              )
            : null,
        isEdited: false,
        createdAt: DateTime.now().toUtc().toIso8601String(),
        senderName: sendingAsChannel ? activeSendAsPeer.name : 'Вы',
        senderChatId: sendingAsChannel ? activeSendAsChatId : null,
        senderChatName: sendingAsChannel ? activeSendAsPeer.name : null,
        senderChatAvatarUrl: sendingAsChannel
            ? activeSendAsPeer.avatarUrl
            : null,
        sendStatus: 0,
        hasMediaSpoiler: hasMediaSpoiler,
        entities: resolvedEntities,
      );

      if (mounted) {
        setState(() {
          _comments.add(optimistic);
          _isUploading = false;
          _uploadProgressNotifier.value = 0.0;
        });
        _scrollToBottom();
      }

      final sent = await ChatService.sendPostComment(
        channelId: widget.channelId,
        messageId: widget.postMessage.id,
        content: text,
        replyToMessageId: replyTo?.id,
        isQuote: capturedIsQuote,
        quoteText: capturedQuoteText,
        quoteOffset: capturedQuoteOffset,
        quoteLength: capturedQuoteLength,
        entities: resolvedEntities.isNotEmpty ? resolvedEntities : null,
        fileUrl: fileUrl,
        fileName: fileName,
        messageType: messageType,
        hasMediaSpoiler: hasMediaSpoiler,
        sendAsChatId: activeSendAsChatId,
      );

      if (!mounted) return;
      if (sent != null) {
        setState(() {
          if (sent.threadRootMessageId != null &&
              sent.threadRootMessageId!.isNotEmpty) {
            _rootMessageId ??= sent.threadRootMessageId;
          }
          if (sent.chatId.isNotEmpty && _linkedChatId == null) {
            _linkedChatId = sent.chatId;
          }
          final idx = _comments.indexWhere((c) => c.localId == localId);
          if (idx != -1) {
            final alreadyById = _comments.indexWhere((c) => c.id == sent.id);
            if (alreadyById != -1 && alreadyById != idx) {
              _comments.removeAt(idx);
            } else {
              _comments[idx] = sent.copyWith(localId: localId, sendStatus: 1);
            }
          } else {
            _upsertComment(sent);
          }
          _commentsCount = math.max(_commentsCount, _comments.length);
          _rootPost = _rootPost.copyWith(commentsCount: _commentsCount);
        });
        _bindLinkedGroupSubscription();
      } else {
        setState(() {
          final idx = _comments.indexWhere((c) => c.localId == localId);
          if (idx != -1) {
            _comments[idx] = _comments[idx].copyWith(sendStatus: 2);
          }
        });
        GlassToastService().show(context, 'Не удалось отправить комментарий');
      }
    } catch (e) {
      if (mounted) {
        GlassToastService().show(context, 'Ошибка отправки: $e');
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

  Future<void> _sendStickerComment(StickerItem item) async {
    if (!_canComment) return;
    final replyTo = _replyToComment;
    _cancelReply();
    final fallback = item.emojis.isNotEmpty ? item.emojis.first : '😀';
    final sent = await ChatService.sendPostComment(
      channelId: widget.channelId,
      messageId: widget.postMessage.id,
      content: fallback,
      replyToMessageId: replyTo?.id,
      fileUrl: item.fileUrl,
      fileName: 'sticker.${item.format}',
      messageType: 'sticker',
      sendAsChatId: _selectedSendAsChatId,
    );
    if (sent != null && mounted) {
      setState(() {
        _upsertComment(sent);
        _commentsCount = math.max(_commentsCount, _comments.length);
        _rootPost = _rootPost.copyWith(commentsCount: _commentsCount);
      });
      _scrollToBottom();
    }
  }

  Future<void> _sendGifComment(GifItemModel gif) async {
    if (!_canComment) return;
    final replyTo = _replyToComment;
    _cancelReply();
    final sent = await ChatService.sendPostComment(
      channelId: widget.channelId,
      messageId: widget.postMessage.id,
      content: 'GIF',
      replyToMessageId: replyTo?.id,
      fileUrl: gif.url,
      fileName: 'animation.gif',
      messageType: 'gif',
      sendAsChatId: _selectedSendAsChatId,
    );
    if (sent != null && mounted) {
      setState(() {
        _upsertComment(sent);
        _commentsCount = math.max(_commentsCount, _comments.length);
        _rootPost = _rootPost.copyWith(commentsCount: _commentsCount);
      });
      _scrollToBottom();
    }
  }

  Future<void> _toggleCommentReaction(String messageId, String emoji) async {
    final idx = _comments.indexWhere((c) => c.id == messageId);
    if (idx == -1) return;
    final current = _comments[idx];
    final prevMy = Set<String>.from(current.myReactions);
    final prevReactions = Map<String, int>.from(current.reactions);
    final bool isRemoving = prevMy.contains(emoji);

    final settings = widget.reactionSettings;
    if (!isRemoving && settings != null && !settings.isReactionAllowed(emoji)) {
      GlassToastService().show(
        context,
        settings.isNone
            ? 'Реакции отключены'
            : 'Эта реакция отключена администратором',
      );
      return;
    }

    final nextMy = Set<String>.from(prevMy);
    final nextReactions = Map<String, int>.from(prevReactions);
    if (isRemoving) {
      nextMy.remove(emoji);
      final left = (nextReactions[emoji] ?? 1) - 1;
      if (left <= 0) {
        nextReactions.remove(emoji);
      } else {
        nextReactions[emoji] = left;
      }
    } else {
      nextMy.add(emoji);
      nextReactions[emoji] = (nextReactions[emoji] ?? 0) + 1;
    }

    setState(() {
      _comments[idx] = current.copyWith(
        reactions: nextReactions,
        myReactions: nextMy,
      );
    });

    final targetChatId = current.chatId.isNotEmpty
        ? current.chatId
        : (_linkedChatId ?? widget.channelId);
    final res = await ChatService.toggleReaction(
      chatId: targetChatId,
      messageId: messageId,
      emoji: emoji,
    );
    if (res['success'] != true && mounted) {
      setState(() {
        final rollbackIdx = _comments.indexWhere((c) => c.id == messageId);
        if (rollbackIdx != -1) {
          _comments[rollbackIdx] = _comments[rollbackIdx].copyWith(
            reactions: prevReactions,
            myReactions: prevMy,
          );
        }
      });
      if (res['message'] != null) {
        GlassToastService().show(context, res['message'].toString());
      }
    }
  }

  Future<void> _toggleRootPostReaction(String emoji) async {
    final prevMy = Set<String>.from(_rootPost.myReactions);
    final prevReactions = Map<String, int>.from(_rootPost.reactions);
    final bool isRemoving = prevMy.contains(emoji);

    final settings = widget.reactionSettings;
    if (!isRemoving && settings != null && !settings.isReactionAllowed(emoji)) {
      GlassToastService().show(
        context,
        settings.isNone
            ? 'Реакции отключены в этом канале'
            : 'Эта реакция отключена администратором',
      );
      return;
    }

    final nextMy = Set<String>.from(prevMy);
    final nextReactions = Map<String, int>.from(prevReactions);
    if (isRemoving) {
      nextMy.remove(emoji);
      final left = (nextReactions[emoji] ?? 1) - 1;
      if (left <= 0) {
        nextReactions.remove(emoji);
      } else {
        nextReactions[emoji] = left;
      }
    } else {
      nextMy.add(emoji);
      nextReactions[emoji] = (nextReactions[emoji] ?? 0) + 1;
    }

    setState(() {
      _rootPost = _rootPost.copyWith(
        reactions: nextReactions,
        myReactions: nextMy,
      );
    });

    final res = await ChatService.toggleReaction(
      chatId: widget.channelId,
      messageId: _rootPost.id,
      emoji: emoji,
    );
    if (res['success'] != true && mounted) {
      setState(() {
        _rootPost = _rootPost.copyWith(
          reactions: prevReactions,
          myReactions: prevMy,
        );
      });
    }
  }

  void _startReply(Message comment) {
    setState(() {
      _isEditing = false;
      _editingCommentId = null;
      _replyToComment = comment;
      _isQuote = false;
      _quoteText = null;
      _quoteOffset = 0;
      _quoteLength = 0;
    });
    _focusInput();
  }

  void _startQuote(
    Message comment,
    String selectedText,
    int offset,
    int length,
  ) {
    setState(() {
      _isEditing = false;
      _editingCommentId = null;
      _replyToComment = comment;
      _isQuote = true;
      _quoteText = selectedText;
      _quoteOffset = offset;
      _quoteLength = length;
    });
    _focusInput();
  }

  void _cancelReply() {
    setState(() {
      _replyToComment = null;
      _isQuote = false;
      _quoteText = null;
      _quoteOffset = 0;
      _quoteLength = 0;
    });
  }

  void _cancelEditing() {
    setState(() {
      _isEditing = false;
      _editingCommentId = null;
      _messageController.clear();
    });
  }

  void _focusInput() {
    if (_showEmojiPanel) _closeEmojiPanel();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _inputFocusNode.requestFocus();
      if (_isMobilePlatform) {
        SystemChannels.textInput.invokeMethod('TextInput.show');
      }
    });
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

  void _onEmojiToggle() {
    StickerService.instance.registerInputTarget(_stickerInputTarget);
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
        }
        _transitionTimer = Timer(const Duration(milliseconds: 500), () {
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
        if (!_inputFocusNode.hasFocus) _inputFocusNode.requestFocus();
        if (_isMobilePlatform) {
          SystemChannels.textInput.invokeMethod('TextInput.hide');
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
          if (!_inputFocusNode.hasFocus) _inputFocusNode.requestFocus();
          SystemChannels.textInput.invokeMethod('TextInput.show');
        });
        _transitionTimer = Timer(const Duration(milliseconds: 500), () {
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
      _messageController.value = TextEditingValue(
        text: text.replaceRange(selection.start, selection.end, ''),
        selection: TextSelection.collapsed(offset: selection.start),
      );
      return;
    }
    final cursorPos = (selection.isValid && selection.baseOffset >= 0)
        ? selection.baseOffset
        : text.length;
    if (cursorPos <= 0) return;
    final before = text.substring(0, cursorPos).characters.skipLast(1).toString();
    final after = text.substring(cursorPos);
    _messageController.value = TextEditingValue(
      text: before + after,
      selection: TextSelection.collapsed(offset: before.length),
    );
  }

  void _insertEmojiText(String emoji) {
    final text = _messageController.text;
    final selection = _messageController.selection;
    int start = selection.start;
    int end = selection.end;
    if (start < 0 || end < 0 || start > text.length) {
      start = text.length;
      end = text.length;
    }
    _messageController.value = TextEditingValue(
      text: text.replaceRange(start, end, emoji),
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
  }

  void _insertCustomEmojiItem(StickerItem item) {
    _messageController.insertCustomEmoji(item);
  }

  Future<void> _showAttachmentPicker() async {
    final result = await AttachmentPickerBottomSheet.show(
      context,
      allowPoll: false,
    );
    if (result == null || !mounted) return;

    if (result.files != null && result.files!.isNotEmpty) {
      if (result.sendImmediately) {
        setState(() {
          for (final file in result.files!) {
            _attachedFiles.add(file);
            _attachedFileNames.add(p.basename(file.path));
          }
        });
        await _sendComment();
      } else {
        final mediaRes = await Navigator.push<MediaSendResult>(
          context,
          MaterialPageRoute(
            builder: (_) => MediaSendScreen(
              initialFiles: result.files!,
              showSilentOption: false,
            ),
          ),
        );
        if (mediaRes != null && mediaRes.files.isNotEmpty && mounted) {
          setState(() {
            _attachedFiles.add(mediaRes.files.first);
            _attachedFileNames.add(p.basename(mediaRes.files.first.path));
            if (mediaRes.caption != null && mediaRes.caption!.isNotEmpty) {
              _messageController.text = mediaRes.caption!;
            }
          });
          await _sendComment(
            hasMediaSpoiler: mediaRes.hasMediaSpoiler,
            asDocument: mediaRes.asDocument,
          );
        }
      }
      return;
    }

    switch (result.action) {
      case AttachmentPickerAction.camera:
        final XFile? photo = await _imagePicker.pickImage(
          source: ImageSource.camera,
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 92,
        );
        if (photo != null && mounted) {
          setState(() {
            _attachedFiles.add(File(photo.path));
            _attachedFileNames.add(p.basename(photo.path));
          });
        }
        break;
      case AttachmentPickerAction.gallery:
        final XFile? media = await _imagePicker.pickMedia(
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 92,
        );
        if (media != null && mounted) {
          setState(() {
            _attachedFiles.add(File(media.path));
            _attachedFileNames.add(p.basename(media.path));
          });
        }
        break;
      case AttachmentPickerAction.file:
        final picked = await FilePicker.platform.pickFiles(type: FileType.any);
        if (picked != null && picked.files.isNotEmpty && mounted) {
          final f = picked.files.first;
          if (f.path != null) {
            setState(() {
              _attachedFiles.add(File(f.path!));
              _attachedFileNames.add(f.name);
            });
          }
        }
        break;
      case AttachmentPickerAction.poll:
        if (_linkedChatId != null && _linkedChatId!.isNotEmpty) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PollCreateScreen(
                chatId: _linkedChatId!,
                sendAsChatId: _selectedSendAsChatId,
              ),
            ),
          );
        }
        break;
      default:
        break;
    }
  }

  void _openUserProfile(Message msg) {
    if (msg.senderId.isEmpty || msg.senderId == '0') return;
    HapticUtils.tap();
    Navigator.push(
      context,
      SwipeBackPageRoute(
        builder: (_) => ProfileScreen(
          entityType: ProfileEntityType.user,
          userId: msg.senderId,
          initialName: msg.senderName,
          initialAvatarUrl: msg.senderAvatarUrl,
        ),
      ),
    );
  }

  void _openLinkedGroupProfile() {
    final grpId = _linkedChatId;
    if (grpId == null || grpId.isEmpty) return;
    HapticUtils.tap();
    Navigator.push(
      context,
      SwipeBackPageRoute(
        builder: (_) => ProfileScreen(
          entityType: ProfileEntityType.group,
          chatId: grpId,
          initialName: widget.channelName ?? 'Обсуждение',
          initialAvatarUrl: widget.channelAvatar,
        ),
      ),
    );
  }

  void _confirmDeleteComment(Message comment) {
    final targetChatId = comment.chatId.isNotEmpty
        ? comment.chatId
        : (_linkedChatId ?? widget.channelId);
    final idx = _comments.indexWhere((c) => c.id == comment.id);
    ChatActionsHelper.confirmAndDeleteMessage(
      context: context,
      chatId: targetChatId,
      message: comment,
      onOptimisticDelete: () {
        if (!mounted) return;
        setState(() {
          _comments.removeWhere((c) => c.id == comment.id);
          if (_commentsCount > 0) _commentsCount--;
          _rootPost = _rootPost.copyWith(commentsCount: _commentsCount);
        });
      },
      onRollback: () {
        if (!mounted) return;
        setState(() {
          if (idx >= 0 && idx <= _comments.length) {
            _comments.insert(idx, comment);
          } else {
            _upsertComment(comment);
          }
          _commentsCount++;
          _rootPost = _rootPost.copyWith(commentsCount: _commentsCount);
        });
      },
    );
  }

  void _showCommentContextMenu(Message comment, GlobalKey key, bool isMe) {
    MessageContextMenuService().show(
      context: context,
      message: comment,
      messageKey: key,
      isMe: isMe,
      currentUserId: _currentUserId,
      onReply: _canComment ? () => _startReply(comment) : null,
      onQuote: (_canComment && comment.content.trim().isNotEmpty)
          ? () => _startQuote(
              comment,
              comment.content,
              0,
              comment.content.length,
            )
          : null,
      onQuotePartial: _canComment
          ? (selectedText, offset, length) =>
              _startQuote(comment, selectedText, offset, length)
          : null,
      onSelect: () {
        setState(() => _selectedCommentIds.add(comment.id));
      },
      onForward: () {
        ForwardChatPickerSheet.show(
          context,
          fromChatId: comment.chatId.isNotEmpty
              ? comment.chatId
              : (_linkedChatId ?? widget.channelId),
          messageIds: [comment.id],
        );
      },
      onEdit: (_canComment && isMe && comment.messageType == 'text')
          ? () {
              setState(() {
                _replyToComment = null;
                _isEditing = true;
                _editingCommentId = comment.id;
                _messageController.loadMessage(
                  comment.content,
                  comment.entities,
                );
              });
              _focusInput();
            }
          : null,
      onDelete: isMe ? _confirmDeleteComment : null,
      onReaction: (msgId, emoji) => _toggleCommentReaction(msgId, emoji),
      selectedEmojis: comment.myReactions,
    );
  }

  void _updateInputHeight() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final box = _inputKey.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.hasSize && box.size.height > 0) {
        if ((box.size.height - _inputHeight).abs() > 1.0) {
          setState(() => _inputHeight = box.size.height);
        }
      }
    });
  }

  String _pluralMessagesSubtitle(int count) {
    final mod100 = count % 100;
    final mod10 = count % 10;
    if (mod10 == 1 && mod100 != 11) return '$count сообщение';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 12 || mod100 > 14)) {
      return '$count сообщения';
    }
    return '$count сообщений';
  }

  String _formatTime(String ts) => DateTimeUtils.formatTimeHHmm(ts);

  Color _resolveSenderColor(Message msg) {
    if (msg.senderNameColorId != null && msg.senderNameColorId!.isNotEmpty) {
      return NameColorPresets.getById(msg.senderNameColorId!).primaryColor;
    }
    final idx = msg.senderId.hashCode.abs() % NameColorPresets.defaults.length;
    return NameColorPresets.defaults[idx].primaryColor;
  }

  @override
  Widget build(BuildContext context) {
    _updateInputHeight();
    final topPadding = ChatScaffold.getTopContentPadding(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final safeBottom = MediaQuery.paddingOf(context).bottom;

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

    final theme = Theme.of(context);
    final themeExt = theme.extension<TheavThemeExtension>();
    final isDark = theme.brightness == Brightness.dark;

    return ChatScaffold(
      canPop: bottomInset == 0 && !_showEmojiPanel && !_isSelectionMode,
      onPopInvoked: (didPop, _) {
        if (!didPop) {
          if (_isSelectionMode) {
            setState(() => _selectedCommentIds.clear());
          } else if (_showEmojiPanel) {
            _closeEmojiPanel();
          } else if (bottomInset > 0) {
            FocusScope.of(context).unfocus();
          }
        }
      },
      appBar: FloatingGlassAppBar(
        name: 'Комментарии',
        statusText: _pluralMessagesSubtitle(_commentsCount),
        isOnline: false,
        isChannel: true,
        avatarWidget: _buildAppBarAvatar(theme, themeExt),
        isSelectionMode: _isSelectionMode,
        selectedCount: _selectedCommentIds.length,
        onCancelSelection: () => setState(() => _selectedCommentIds.clear()),
        onCopySelected: () {
          final text = _comments
              .where((c) => _selectedCommentIds.contains(c.id))
              .map((c) => c.content.trim())
              .where((s) => s.isNotEmpty)
              .join('\n\n');
          if (text.isNotEmpty) {
            Clipboard.setData(ClipboardData(text: text));
            GlassToastService().show(
              context,
              context.l10n.translate('copied_to_clipboard'),
              iconWidget: iconoir.Check(
                width: 20,
                height: 20,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            );
          }
          setState(() => _selectedCommentIds.clear());
        },
        onForwardSelected: () {
          final ids = _selectedCommentIds.toList();
          setState(() => _selectedCommentIds.clear());
          ForwardChatPickerSheet.show(
            context,
            fromChatId: _linkedChatId ?? widget.channelId,
            messageIds: ids,
          );
        },
        onBack: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else {
            TilingLayoutController.popOrCloseChatTile(context);
          }
        },
        onTitleTap: _scrollToTop,
      ),
      body: AnimatedBuilder(
        animation: _emojiPanelAnimation,
        builder: (context, _) {
          final animVal = _emojiPanelAnimation.value;
          final double effectiveBottom;
          if (_showEmojiPanel) {
            final targetPanelHeight = _keyboardHeight + safeBottom;
            final currentHeight =
                safeBottom + (targetPanelHeight - safeBottom) * animVal;
            effectiveBottom = math.max(bottomInset, currentHeight);
          } else {
            effectiveBottom = bottomInset > 0 ? bottomInset : safeBottom;
          }

          return Stack(
            fit: StackFit.expand,
            children: [
              ListView.builder(
                controller: _scrollController,
                padding: EdgeInsets.only(
                  top: topPadding + 4.0,
                  left: 8.0,
                  right: 8.0,
                  bottom: _inputHeight + effectiveBottom + 14.0,
                ),
                itemCount: 2 + (_hasMore ? 1 : 0) + _comments.length,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return ChannelPostCard(
                      message: _rootPost,
                      currentUserId: _currentUserId ?? '',
                      channelName: widget.channelName ?? '',
                      channelAvatar: widget.channelAvatar,
                      signMessages: widget.signMessages,
                      showAuthorProfiles: widget.showAuthorProfiles,
                      linkedChatId: _linkedChatId,
                      showCommentsRow: false,
                      reactionSettings: widget.reactionSettings,
                      onReactionTap: _toggleRootPostReaction,
                      onFileTap: (url, name, type) {
                        if (type == 'image') {
                          FullscreenPhotoViewer.open(context, url);
                        }
                      },
                    );
                  }
                  if (index == 1) {
                    return _buildCommentsDivider(
                      theme: theme,
                      themeExt: themeExt,
                      isDark: isDark,
                    );
                  }
                  int commentIdx = index - 2;
                  if (_hasMore) {
                    if (commentIdx == 0) {
                      return Center(
                        child: TextButton(
                          onPressed: _isLoadingOlder
                              ? null
                              : _loadOlderComments,
                          child: _isLoadingOlder
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                )
                              : const Text('Показать предыдущие комментарии'),
                        ),
                      );
                    }
                    commentIdx -= 1;
                  }

                  if (_isLoading && _comments.isEmpty) {
                    return const Padding(
                      padding: EdgeInsets.symmetric(vertical: 28),
                      child: Center(child: CircularProgressIndicator()),
                    );
                  }

                  return _buildCommentRow(commentIdx);
                },
              ),
              if (!_isLoading && _comments.isEmpty && _errorMessage != null)
                Positioned(
                  top: topPadding + 180,
                  left: 24,
                  right: 24,
                  child: Center(
                    child: Text(
                      _errorMessage!,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.65,
                        ),
                      ),
                    ),
                  ),
                ),
              ChatBottomScrollEdge(height: math.max(safeBottom + 52.0, 52.0)),
              if (_canComment && _showEmojiPanel)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: (_keyboardHeight + safeBottom) * animVal,
                  child: ClipRect(
                    clipBehavior:
                        animVal < 0.999 ? Clip.hardEdge : Clip.none,
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      minHeight: _keyboardHeight + safeBottom,
                      maxHeight: _keyboardHeight + safeBottom,
                      child: EmojiStickerPanel(
                        controller: _messageController,
                        focusNode: _inputFocusNode,
                        onEmojiSelected: _insertEmojiText,
                        onBackspace: _handleBackspace,
                        onClose: _closeEmojiPanel,
                        onCustomEmojiSelected: _insertCustomEmojiItem,
                        onStickerSelected: _sendStickerComment,
                        onGifSelected: _sendGifComment,
                        height: _keyboardHeight + safeBottom,
                        isVisible: _showEmojiPanel,
                      ),
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: _canComment ? effectiveBottom : 0,
                child: Container(
                  key: _inputKey,
                  child: _canComment
                      ? ChatInputBar(
                          controller: _messageController,
                          focusNode: _inputFocusNode,
                          hintText: 'Добавить комментарий...',
                          isUploading: _isUploading,
                          uploadProgressNotifier: _uploadProgressNotifier,
                          attachedFiles: _attachedFiles,
                          attachedFileNames: _attachedFileNames,
                          onRemoveAttachment: (idx) {
                            if (idx >= 0 && idx < _attachedFiles.length) {
                              setState(() {
                                _attachedFiles.removeAt(idx);
                                _attachedFileNames.removeAt(idx);
                              });
                            }
                          },
                          replyToMessage: _replyToComment,
                          isQuote: _isQuote,
                          quoteText: _quoteText,
                          quoteOffset: _quoteOffset,
                          quoteLength: _quoteLength,
                          onCancelReply: _cancelReply,
                          isEditing: _isEditing,
                          onCancelEditing: _cancelEditing,
                          isEmojiPanelOpen:
                              _showEmojiPanel && !_isKeyboardRising,
                          onTapInputWhenEmojiOpen: _onEmojiToggle,
                          onEmoji: _onEmojiToggle,
                          onAttach: _showAttachmentPicker,
                          onSend: _sendComment,
                          onSendDetailed:
                              (
                                cleanText,
                                entities,
                                linkPreviewOptions,
                                invertMedia,
                              ) {
                                _sendComment(
                                  cleanText: cleanText,
                                  entities: entities,
                                  linkPreviewOptions: linkPreviewOptions,
                                  invertMedia: invertMedia,
                                );
                              },
                          sendAsLeadingWidget: _sendAsPeers.length > 1
                              ? SendAsPeerSelectorPill(
                                  peers: _sendAsPeers,
                                  selectedPeer: _activeSendAsPeer,
                                  onTap: _openSendAsPicker,
                                )
                              : null,
                          currentUserId: _currentUserId,
                          isSending: _isSending,
                        )
                      : _buildReadOnlyCommentsBanner(safeBottom),
                ),
              ),
              Positioned(
                right: 14,
                bottom: _inputHeight + 10 + effectiveBottom,
                child: ValueListenableBuilder<bool>(
                  valueListenable: _showScrollDownFabNotifier,
                  builder: (context, showFab, _) => ScrollDownFab(
                    visible: showFab,
                    unreadCount: 0,
                    onPressed: _scrollToBottom,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildReadOnlyCommentsBanner(double safeBottom) {
    final palette = context.theav;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, math.max(safeBottom, 12)),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: 0.94),
        border: Border(
          top: BorderSide(color: palette.divider, width: 0.6),
        ),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          iconoir.Lock(width: 16, height: 16, color: palette.subtext),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              'Комментарии отключены. Доступен только просмотр истории.',
              style: TextStyle(
                fontSize: 13.5,
                color: palette.subtext,
                fontWeight: FontWeight.w500,
              ),
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAppBarAvatar(ThemeData theme, TheavThemeExtension? themeExt) {
    final validUrl = getValidAvatarUrl(widget.channelAvatar);
    final provider = validUrl != null ? avatarImageProvider(validUrl) : null;
    if (provider != null) {
      return CircleAvatar(radius: 20, backgroundImage: provider);
    }
    return CircleAvatar(
      radius: 20,
      backgroundColor: (themeExt?.palette.primary ?? theme.colorScheme.primary)
          .withValues(alpha: 0.16),
      child: iconoir.ChatLines(
        width: 20,
        height: 20,
        color: themeExt?.palette.primary ?? theme.colorScheme.primary,
      ),
    );
  }

  Widget _buildCommentsDivider({
    required ThemeData theme,
    required TheavThemeExtension? themeExt,
    required bool isDark,
  }) {
    final label = _commentsCount == 0
        ? '0 комментариев'
        : ChannelPostCard.formatCommentsLabel(_commentsCount);
    final textColor =
        themeExt?.palette.subtext ??
        (isDark ? Colors.white70 : Colors.black.withValues(alpha: 0.72));
    final lineColor =
        themeExt?.palette.divider ??
        (isDark ? Colors.white24 : Colors.black.withValues(alpha: 0.12));

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Row(
        children: [
          Expanded(child: Container(height: 0.5, color: lineColor)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
                color: textColor,
              ),
            ),
          ),
          Expanded(child: Container(height: 0.5, color: lineColor)),
        ],
      ),
    );
  }

  Widget _buildCommentRow(int index) {
    if (index < 0 || index >= _comments.length) {
      return const SizedBox.shrink();
    }
    final comment = _comments[index];
    final key = _commentKeys.putIfAbsent(comment.id, () => GlobalKey());
    final bool isMe =
        comment.senderId == _currentUserId && !comment.isFromAnonymousAdmin;
    final Message? olderNeighbor = index > 0 ? _comments[index - 1] : null;
    final Message? newerNeighbor = index + 1 < _comments.length
        ? _comments[index + 1]
        : null;

    final bool firstInCluster = isFirstInSenderCluster(
      current: comment,
      olderNeighbor: olderNeighbor,
    );
    final bool lastInCluster = isLastInSenderCluster(
      current: comment,
      newerNeighbor: newerNeighbor,
    );

    final bool showAvatarGutter = !isMe && comment.messageType != 'system';
    final bool isSelected = _selectedCommentIds.contains(comment.id);

    final bool hasSenderChat =
        comment.senderChatId != null && comment.senderChatId!.isNotEmpty;

    final PeerCustomization? senderCust =
        (!hasSenderChat &&
            !comment.isFromAnonymousAdmin &&
            comment.senderId.isNotEmpty &&
            comment.senderId != '0')
        ? (PeerCustomizationCache.instance.getSync(comment.senderId) ??
              comment.senderCustomization)
        : null;

    final String resolvedSenderName = hasSenderChat
        ? (comment.senderChatName?.trim().isNotEmpty == true
              ? comment.senderChatName!
              : (comment.senderName.trim().isNotEmpty
                    ? comment.senderName
                    : 'Канал'))
        : (comment.isFromAnonymousAdmin
              ? (comment.senderName.trim().isNotEmpty
                    ? comment.senderName
                    : (widget.channelName ?? 'Channel'))
              : comment.senderName);
    final String? resolvedSenderAvatar = hasSenderChat
        ? comment.senderChatAvatarUrl
        : comment.senderAvatarUrl;

    final VoidCallback? onSenderTap = _isSelectionMode
        ? null
        : (hasSenderChat
              ? () => _openChannelProfileById(
                  comment.senderChatId!,
                  name: resolvedSenderName,
                  avatarUrl: resolvedSenderAvatar,
                )
              : (comment.isFromAnonymousAdmin
                    ? _openLinkedGroupProfile
                    : () => _openUserProfile(comment)));

    final Widget? senderHeaderWidget = (showAvatarGutter && firstInCluster)
        ? SenderHeaderRow(
            senderName: resolvedSenderName,
            nameColor: (hasSenderChat || comment.isFromAnonymousAdmin)
                ? Theme.of(context).colorScheme.primary
                : _resolveSenderColor(comment),
            customization: senderCust,
            adminTitle: hasSenderChat ? 'канал' : comment.senderAdminTitle,
            role: hasSenderChat ? null : comment.senderRole,
            onTapSender: onSenderTap,
          )
        : null;

    Widget rowWidget = MessageBubble(
      key: key,
      message: comment,
      isMe: isMe,
      currentUserId: _currentUserId ?? '',
      senderName: (isMe || showAvatarGutter || comment.messageType == 'system')
          ? null
          : resolvedSenderName,
      senderHeaderWidget: senderHeaderWidget,
      hasAvatarGutter: showAvatarGutter,
      isFirstInCluster: firstInCluster,
      isLastInCluster: lastInCluster,
      chatType: 'group',
      chatTitle: widget.channelName,
      isSelected: isSelected,
      isSelectionMode: _isSelectionMode,
      reactions: comment.reactions.isNotEmpty ? comment.reactions : null,
      myReactions: comment.myReactions.isNotEmpty ? comment.myReactions : null,
      onReactionTap: (emoji) => _toggleCommentReaction(comment.id, emoji),
      onFileTap: (url, name, type) {
        if (type == 'image') {
          FullscreenPhotoViewer.open(context, url);
        }
      },
      formatTime: _formatTime,
    );

    if (showAvatarGutter) {
      rowWidget = GroupMessageAvatarRow(
        senderId: hasSenderChat ? comment.senderChatId! : comment.senderId,
        senderName: resolvedSenderName,
        senderAvatarUrl: resolvedSenderAvatar,
        showAvatar: lastInCluster,
        customizationOverride: senderCust,
        isSelectionMode: _isSelectionMode,
        isSelected: isSelected,
        isFromAnonymousAdmin: !hasSenderChat && comment.isFromAnonymousAdmin,
        groupAvatarUrl: widget.channelAvatar,
        groupName: widget.channelName,
        onTapGroupAvatar: _openLinkedGroupProfile,
        onAvatarTap: _isSelectionMode
            ? () => setState(() {
                if (isSelected) {
                  _selectedCommentIds.remove(comment.id);
                } else {
                  _selectedCommentIds.add(comment.id);
                }
              })
            : onSenderTap,
        child: rowWidget,
      );
    }

    rowWidget = SwipeToReplyWrapper(
      onReply: () => _startReply(comment),
      enabled: !_isSelectionMode && _canComment,
      child: rowWidget,
    );

    final platform = Theme.of(context).platform;
    final bool isDesktop =
        platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS;

    rowWidget = GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        if (_isSelectionMode) {
          setState(() {
            if (isSelected) {
              _selectedCommentIds.remove(comment.id);
            } else {
              _selectedCommentIds.add(comment.id);
            }
          });
          return;
        }
        if (!isDesktop) {
          _showCommentContextMenu(comment, key, isMe);
        }
      },
      onLongPress: isDesktop
          ? null
          : () => setState(() => _selectedCommentIds.add(comment.id)),
      onSecondaryTapUp: (_) => _showCommentContextMenu(comment, key, isMe),
      child: rowWidget,
    );

    return rowWidget;
  }
}
