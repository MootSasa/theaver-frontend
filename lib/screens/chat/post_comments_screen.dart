import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../models/name_color_preset.dart';
import '../../models/profile_customization.dart';
import '../../models/theav_media_item.dart';
import '../../models/theav_theme.dart';
import '../../services/auth_service.dart';
import '../../services/chat_instant_cache.dart';
import '../../services/chat_realtime_manager.dart';
import '../../services/chat_service.dart';
import '../../services/contacts_service.dart';
import '../../services/database/app_database.dart';
import '../../services/draft_service.dart';
import '../../services/file_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/groups_channels_parity_service.dart';
import '../../services/media_send_coordinator.dart';
import '../../services/message_context_menu_service.dart';
import '../../services/peer_customization_cache.dart';
import '../../services/screen_protection_service.dart';
import '../../services/sticker_service.dart';
import '../../services/sync_service.dart';
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
import '../../widgets/chat/telegram_delete_messages_sheet.dart';
import '../../widgets/chat/unread_separator.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/media_viewer/theav_media_viewer.dart';
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

  /// In a comment thread view, top-level comments reference the mirrored
  /// discussion root post via [Message.replyToMessageId] so they display with
  /// a reply header in the linked group. Inside [PostCommentsScreen] itself
  /// the root post is already pinned above the thread, so strip that root-post
  /// reply metadata while keeping replies to other comments intact.
  static Message stripRootPostReplyForThreadView(
    Message comment, {
    String? rootMessageId,
    String? rootPostId,
  }) {
    final String? replyId = () {
      final direct = comment.replyToMessageId?.trim();
      if (direct != null && direct.isNotEmpty) return direct;
      final infoId = comment.replyInfo?.messageId.trim();
      if (infoId != null && infoId.isNotEmpty) return infoId;
      return null;
    }();
    if (replyId == null) return comment;

    final candidates = <String>{
      if (rootMessageId != null && rootMessageId.trim().isNotEmpty)
        rootMessageId.trim(),
      if (comment.threadRootMessageId != null &&
          comment.threadRootMessageId!.trim().isNotEmpty)
        comment.threadRootMessageId!.trim(),
      if (rootPostId != null && rootPostId.trim().isNotEmpty) rootPostId.trim(),
    };
    if (candidates.contains(replyId)) {
      return comment.copyWith(clearReply: true);
    }
    return comment;
  }

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

  // Local-only draft lifecycle for this post's comments thread
  String get _draftKey =>
      DraftService.commentsKey(widget.channelId, widget.postMessage.id);
  bool _suppressDraftSave = false;
  String? _pendingDraftReplyId;
  ({
    String text,
    List<MessageEntity> entities,
    Message? replyTo,
    bool isQuote,
    String? quoteText,
    int quoteOffset,
    int quoteLength,
  })? _stashedDraftBeforeEdit;

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
  StreamSubscription<MediaSendEvent>? _mediaSendSub;

  // Wave 3B parity state
  bool _canComment = true;
  bool _canDeleteOthers = false;
  bool _hasProtectedContent = false;
  String? _linkedGroupName;
  String? _linkedGroupAvatar;
  List<SendAsPeer> _sendAsPeers = [];
  String? _selectedSendAsChatId;
  String _selectedSendAsMode = 'user';

  bool get _effectiveSendAsAnon => _selectedSendAsMode == 'group';
  String? get _effectiveSendAsChannelId =>
      _selectedSendAsMode == 'channel' ? _selectedSendAsChatId : null;
  String get _effectiveSendAsMode => _selectedSendAsMode;

  String get _screenProtectionKey =>
      'post_comments_${widget.channelId}_${widget.postMessage.id}';

  bool get _isMobilePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);
  bool get _isSelectionMode => _selectedCommentIds.isNotEmpty;

  @override
  void initState() {
    super.initState();
    ContactsService.revisionNotifier.addListener(_onContactsRevisionChanged);
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

    final draft = DraftService().getDraft(_draftKey);
    if (draft != null && draft.isNotEmpty) {
      _suppressDraftSave = true;
      _messageController.loadMessage(draft.text, draft.entities);
      _suppressDraftSave = false;
      if (draft.replyToMessageId != null &&
          draft.replyToMessageId!.isNotEmpty) {
        _pendingDraftReplyId = draft.replyToMessageId;
      }
      if (draft.quoteText != null && draft.quoteText!.isNotEmpty) {
        _isQuote = draft.isQuote;
        _quoteText = draft.quoteText;
        _quoteOffset = draft.quoteOffset;
        _quoteLength = draft.quoteLength;
      }
    }
    _messageController.addListener(_onControllerDraftSync);

    _loadCachedKeyboardHeight();
    _initChannelSubscription();
    _bindLinkedGroupSubscription();
    _mediaSendSub = MediaSendCoordinator.instance.events.listen(
      _onMediaSendEvent,
    );
    _loadInitial();
  }

  @override
  void dispose() {
    ContactsService.revisionNotifier.removeListener(_onContactsRevisionChanged);
    _transitionTimer?.cancel();
    if (!_isEditing) {
      DraftService().flushDraft(_draftKey);
    }
    _messageController.removeListener(_onControllerDraftSync);
    StickerService.instance.unregisterInputTarget(_stickerInputTarget);
    _emojiPanelController.dispose();
    _inputFocusNode.removeListener(_onFocusChanged);
    _inputFocusNode.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _uploadProgressNotifier.dispose();
    _showScrollDownFabNotifier.dispose();
    _mediaSendSub?.cancel();
    _channelSubscription?.cancel();
    _groupSubscription?.cancel();
    unawaited(ScreenProtectionService.instance.release(_screenProtectionKey));
    super.dispose();
  }

  void _onContactsRevisionChanged() {
    if (mounted) setState(() {});
  }

  void _syncScreenProtection(bool protect) {
    unawaited(ScreenProtectionService.instance.sync(_screenProtectionKey, protect));
  }

  Future<void> _syncProtectionFromDb() async {
    bool protect = false;
    bool canDeleteOthers = false;
    String? linkedName = _linkedGroupName;
    String? linkedAvatar = _linkedGroupAvatar;

    bool roleAllowsDelete(String? role, AdminRights? perms) {
      if (role == 'owner') return true;
      if (role == 'admin') return perms?.canDeleteMessages ?? true;
      return false;
    }

    try {
      final chanInstant = ChatInstantCache.instance.getSync(widget.channelId);
      final grpInstant = (_linkedChatId != null && _linkedChatId!.isNotEmpty)
          ? ChatInstantCache.instance.getSync(_linkedChatId!)
          : null;
      if (chanInstant?.hasProtectedContent == true ||
          grpInstant?.hasProtectedContent == true) {
        protect = true;
      }
      if (roleAllowsDelete(
            chanInstant?.chatDetails?.myRole ?? chanInstant?.myRole,
            chanInstant?.chatDetails?.myAdminPermissions,
          ) ||
          roleAllowsDelete(
            grpInstant?.chatDetails?.myRole ?? grpInstant?.myRole,
            grpInstant?.chatDetails?.myAdminPermissions,
          )) {
        canDeleteOthers = true;
      }
      if (grpInstant?.chat?.name.isNotEmpty == true) {
        linkedName = grpInstant!.chat!.name;
      }
      linkedAvatar ??= grpInstant?.chat?.avatarUrl;

      final db = AppDatabase();
      final channelChat = await db.getChat(widget.channelId);
      final linkedChat = (_linkedChatId != null && _linkedChatId!.isNotEmpty)
          ? await db.getChat(_linkedChatId!)
          : null;
      if (channelChat?.hasProtectedContent == true ||
          linkedChat?.hasProtectedContent == true) {
        protect = true;
      }
      if (roleAllowsDelete(channelChat?.myRole, null) ||
          roleAllowsDelete(linkedChat?.myRole, null)) {
        canDeleteOthers = true;
      }
      if (linkedChat != null) {
        if (linkedChat.name.isNotEmpty) linkedName = linkedChat.name;
        if (linkedChat.avatarUrl != null && linkedChat.avatarUrl!.isNotEmpty) {
          linkedAvatar = linkedChat.avatarUrl;
        }
      }
    } catch (_) {}

    if (mounted) {
      if (_hasProtectedContent != protect ||
          _canDeleteOthers != canDeleteOthers ||
          _linkedGroupName != linkedName ||
          _linkedGroupAvatar != linkedAvatar) {
        setState(() {
          _hasProtectedContent = protect;
          _canDeleteOthers = canDeleteOthers;
          _linkedGroupName = linkedName;
          _linkedGroupAvatar = linkedAvatar;
        });
      }
      _syncScreenProtection(protect);
    }

    // Fetch authoritative permissions for channel & linked discussion group
    try {
      final futures = <Future<Map<String, dynamic>>>[
        ChatService.getChat(widget.channelId),
        if (_linkedChatId != null && _linkedChatId!.isNotEmpty)
          ChatService.getChat(_linkedChatId!),
      ];
      final results = await Future.wait(futures);
      if (!mounted) return;
      bool remoteProtect = protect;
      bool remoteCanDelete = canDeleteOthers;
      String? remoteGroupName = linkedName;
      String? remoteGroupAvatar = linkedAvatar;
      for (int i = 0; i < results.length; i++) {
        final r = results[i];
        if (r['success'] == true && r['chat'] is ChatDetails) {
          final details = r['chat'] as ChatDetails;
          if (details.hasProtectedContent) remoteProtect = true;
          if (roleAllowsDelete(details.myRole, details.myAdminPermissions)) {
            remoteCanDelete = true;
          }
          if (i == 1) {
            if (details.name.isNotEmpty) remoteGroupName = details.name;
            if (details.avatarUrl != null && details.avatarUrl!.isNotEmpty) {
              remoteGroupAvatar = details.avatarUrl;
            }
          }
        }
      }
      if (mounted) {
        setState(() {
          _hasProtectedContent = remoteProtect;
          _canDeleteOthers = remoteCanDelete;
          _linkedGroupName = remoteGroupName;
          _linkedGroupAvatar = remoteGroupAvatar;
        });
        _syncScreenProtection(remoteProtect);
      }
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
        _selectedSendAsMode = res.selectedSendAsMode;
        _selectedSendAsChatId = res.selectedSendAsChatId;
      });
    } catch (_) {}
  }

  SendAsPeer? get _activeSendAsPeer {
    if (_sendAsPeers.isEmpty) return null;
    for (final p in _sendAsPeers) {
      if (p.matchesSelection(
        selectedSendAsMode: _effectiveSendAsMode,
        selectedSendAsChatId: _effectiveSendAsChannelId,
      )) {
        return p;
      }
    }
    for (final p in _sendAsPeers) {
      if (p.isSelected) return p;
    }
    return _sendAsPeers.first;
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
    } else if (!_inputFocusNode.hasFocus && !_showEmojiPanel && !_isEditing) {
      DraftService().flushDraft(_draftKey);
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
          recentRepliers: (updatedRepliers.isNotEmpty || updatedCount == 0)
              ? updatedRepliers
              : _rootPost.recentRepliers,
        );
      }
      if (incomingComment != null) {
        _upsertComment(incomingComment);
      }
    });
  }

  void _onMediaSendEvent(MediaSendEvent event) {
    if (!mounted) return;
    if (event.chatId != widget.channelId ||
        event.threadRootMessageId != widget.postMessage.id) {
      return;
    }

    switch (event.type) {
      case MediaSendEventType.inserted:
        setState(() {
          for (final msg in event.messages) {
            final keyId = (msg.localId != null && msg.localId!.isNotEmpty)
                ? msg.localId!
                : msg.id;
            final exists = _comments.any((c) =>
                (c.localId != null && c.localId == keyId) ||
                c.id == msg.id ||
                c.id == keyId);
            if (!exists) {
              _comments.add(msg);
            }
          }
          _dedupeCommentsInPlace();
          _sortCommentsAscending();
        });
        if (event.messages.isNotEmpty) {
          _scrollToBottom();
        }
        break;

      case MediaSendEventType.updated:
      case MediaSendEventType.replacedWithServer:
      case MediaSendEventType.failed:
      case MediaSendEventType.albumDowngradedToSingle:
        setState(() {
          final maxLen = math.max(event.localIds.length, event.messages.length);
          for (int i = 0; i < maxLen; i++) {
            final targetLocalId = i < event.localIds.length
                ? event.localIds[i]
                : event.messages[i].localId;
            final incoming = i < event.messages.length ? event.messages[i] : null;
            if (targetLocalId == null && incoming == null) continue;

            final matchIdx = _comments.indexWhere((c) =>
                (targetLocalId != null &&
                    targetLocalId.isNotEmpty &&
                    ((c.localId != null && c.localId == targetLocalId) ||
                        c.id == targetLocalId)) ||
                (incoming != null && c.id == incoming.id));

            if (matchIdx != -1) {
              final existing = _comments[matchIdx];
              if (incoming != null) {
                _promoteCommentKey(
                  fromLocalId: existing.localId ?? targetLocalId,
                  toId: incoming.id,
                );
                final resolvedLocalId =
                    (incoming.localId != null && incoming.localId!.isNotEmpty)
                        ? incoming.localId
                        : (existing.localId ?? targetLocalId);
                _comments[matchIdx] = incoming.copyWith(
                  localId: resolvedLocalId,
                  sendStatus: event.type == MediaSendEventType.replacedWithServer
                      ? 1
                      : incoming.sendStatus,
                  replyInfo: incoming.replyInfo ?? existing.replyInfo,
                  isOwn: incoming.isOwn || existing.isOwn,
                );
                if (event.type == MediaSendEventType.replacedWithServer &&
                    targetLocalId != null &&
                    _selectedCommentIds.remove(targetLocalId)) {
                  _selectedCommentIds.add(incoming.id);
                }
              } else if (event.type == MediaSendEventType.failed) {
                _comments[matchIdx] = existing.copyWith(sendStatus: 2);
              }
            } else if (incoming != null &&
                event.type == MediaSendEventType.replacedWithServer) {
              _comments.add(incoming.copyWith(sendStatus: 1, isOwn: true));
            }
          }

          if (event.type == MediaSendEventType.replacedWithServer) {
            for (final msg in event.messages) {
              if (msg.threadRootMessageId != null &&
                  msg.threadRootMessageId!.isNotEmpty) {
                _rootMessageId ??= msg.threadRootMessageId;
              }
              if (msg.chatId.isNotEmpty &&
                  msg.chatId != widget.channelId &&
                  _linkedChatId == null) {
                _linkedChatId = msg.chatId;
              }
            }
            _commentsCount = math.max(
              _commentsCount,
              _comments.where((c) => c.sendStatus == 1).length,
            );
            _rootPost = _rootPost.copyWith(commentsCount: _commentsCount);
          }
          _dedupeCommentsInPlace();
          _sortCommentsAscending();
        });
        if (event.type == MediaSendEventType.replacedWithServer) {
          _bindLinkedGroupSubscription();
        }
        break;

      case MediaSendEventType.cancelled:
        final cancelSet =
            event.localIds.where((id) => id.isNotEmpty).toSet();
        if (cancelSet.isEmpty) return;
        setState(() {
          _comments.removeWhere((c) =>
              cancelSet.contains(c.id) ||
              (c.localId != null && cancelSet.contains(c.localId)));
          _selectedCommentIds.removeAll(cancelSet);
        });
        break;
    }
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

    final matchesExistingLocal = msg.localId != null &&
        msg.localId!.isNotEmpty &&
        _comments.any((c) => c.localId == msg.localId || c.id == msg.localId);
    if (_rootMessageId == null) {
      if (!matchesExistingLocal) return;
      _rootMessageId = threadRoot;
    } else if (threadRoot != _rootMessageId) {
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
    final bool replyDeleted =
        _replyToComment != null && _replyToComment!.id == msgId;
    if (_stashedDraftBeforeEdit?.replyTo?.id == msgId) {
      final s = _stashedDraftBeforeEdit!;
      _stashedDraftBeforeEdit = (
        text: s.text,
        entities: s.entities,
        replyTo: null,
        isQuote: false,
        quoteText: null,
        quoteOffset: 0,
        quoteLength: 0,
      );
    }
    setState(() {
      final before = _comments.length;
      _comments.removeWhere((c) => c.id == msgId);
      if (_comments.length < before && _commentsCount > 0) {
        _commentsCount--;
        _rootPost = _rootPost.copyWith(commentsCount: _commentsCount);
      }
      if (replyDeleted) {
        _replyToComment = null;
        _pendingDraftReplyId = null;
        _isQuote = false;
        _quoteText = null;
        _quoteOffset = 0;
        _quoteLength = 0;
      }
    });
    if (replyDeleted) {
      _saveCurrentDraft();
    }
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

  void _promoteCommentKey({String? fromLocalId, required String toId}) {
    if (fromLocalId != null &&
        fromLocalId.isNotEmpty &&
        fromLocalId != toId &&
        _commentKeys.containsKey(fromLocalId)) {
      final promoted = _commentKeys.remove(fromLocalId)!;
      _commentKeys.putIfAbsent(toId, () => promoted);
    }
  }

  void _dedupeCommentsInPlace() {
    if (_comments.length < 2) return;
    final seenById = <String, int>{};
    final seenByLocalId = <String, int>{};
    for (int i = 0; i < _comments.length; i++) {
      final c = _comments[i];
      final id = c.id;
      final lid =
          (c.localId != null && c.localId!.isNotEmpty) ? c.localId : null;
      int? dupIdx = seenById[id];
      if (dupIdx == null && lid != null) {
        dupIdx = seenByLocalId[lid];
      }
      if (dupIdx != null && dupIdx != i) {
        final existing = _comments[dupIdx];
        final bool incomingIsServer = int.tryParse(id) != null;
        final bool existingIsServer = int.tryParse(existing.id) != null;
        final Message winnerBase =
            (incomingIsServer && !existingIsServer) ? c : existing;
        final Message loser = identical(winnerBase, c) ? existing : c;
        final String? mergedLocalId =
            (winnerBase.localId != null && winnerBase.localId!.isNotEmpty)
                ? winnerBase.localId
                : loser.localId;
        final int mergedStatus =
            (winnerBase.sendStatus == 1 || loser.sendStatus == 1)
                ? 1
                : (winnerBase.sendStatus == 0 || loser.sendStatus == 0
                    ? 0
                    : 2);
        _promoteCommentKey(fromLocalId: mergedLocalId, toId: winnerBase.id);
        _comments[dupIdx] = winnerBase.copyWith(
          localId: mergedLocalId,
          sendStatus: mergedStatus,
          replyInfo: winnerBase.replyInfo ?? loser.replyInfo,
          isOwn: winnerBase.isOwn || loser.isOwn,
        );
        _comments.removeAt(i);
        i--;
        seenById[_comments[dupIdx].id] = dupIdx;
        if (mergedLocalId != null) {
          seenByLocalId[mergedLocalId] = dupIdx;
        }
        continue;
      }
      seenById[id] = i;
      if (lid != null) {
        seenByLocalId[lid] = i;
      }
    }
  }

  bool _upsertComment(Message incoming) {
    final idIdx = _comments.indexWhere((c) => c.id == incoming.id);
    final lidIdx = (incoming.localId != null && incoming.localId!.isNotEmpty)
        ? _comments.indexWhere(
            (c) => c.localId == incoming.localId || c.id == incoming.localId,
          )
        : -1;

    if (idIdx != -1 && lidIdx != -1 && idIdx != lidIdx) {
      final serverCopy = _comments[idIdx];
      final pendingCopy = _comments[lidIdx];
      _promoteCommentKey(fromLocalId: pendingCopy.localId, toId: incoming.id);
      _comments[idIdx] = incoming.copyWith(
        localId: pendingCopy.localId ?? serverCopy.localId ?? incoming.localId,
        sendStatus: 1,
        replyInfo: incoming.replyInfo ??
            serverCopy.replyInfo ??
            pendingCopy.replyInfo,
        isOwn: incoming.isOwn || serverCopy.isOwn || pendingCopy.isOwn,
      );
      _comments.removeAt(lidIdx);
      _dedupeCommentsInPlace();
      _sortCommentsAscending();
      return false;
    }

    final idx = idIdx != -1 ? idIdx : lidIdx;
    if (idx != -1) {
      final existing = _comments[idx];
      _promoteCommentKey(fromLocalId: existing.localId, toId: incoming.id);
      _comments[idx] = incoming.copyWith(
        localId: existing.localId ?? incoming.localId,
        sendStatus: 1,
        replyInfo: incoming.replyInfo ?? existing.replyInfo,
        isOwn: incoming.isOwn || existing.isOwn,
      );
      _dedupeCommentsInPlace();
      _sortCommentsAscending();
      return false;
    }
    _comments.add(incoming);
    _dedupeCommentsInPlace();
    _sortCommentsAscending();
    return true;
  }

  void _confirmSentComment(Message sent, {String? localId}) {
    if (sent.threadRootMessageId != null &&
        sent.threadRootMessageId!.isNotEmpty) {
      _rootMessageId ??= sent.threadRootMessageId;
    }
    if (sent.chatId.isNotEmpty && _linkedChatId == null) {
      _linkedChatId = sent.chatId;
    }
    final normalized = sent.copyWith(
      localId: (localId != null && localId.isNotEmpty) ? localId : sent.localId,
      sendStatus: 1,
      isOwn: true,
    );
    _upsertComment(normalized);
    _commentsCount = math.max(_commentsCount, _comments.length);
    _rootPost = _rootPost.copyWith(commentsCount: _commentsCount);
  }

  void _scrollToComment(String replyToId) {
    final keyCtx = _commentKeys[replyToId]?.currentContext;
    if (keyCtx != null) {
      Scrollable.ensureVisible(
        keyCtx,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
        alignment: 0.4,
      );
      return;
    }
    final idx = _comments.indexWhere((c) => c.id == replyToId);
    if (idx != -1 && _scrollController.hasClients) {
      final targetOffset = ((idx + 1) * 76.0).clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 280),
        curve: Curves.easeOutCubic,
      );
    }
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

  Future<List<Message>> _loadPendingAndFailedDbComments() async {
    try {
      final db = AppDatabase();
      final rows = await db.getThreadComments(
        widget.channelId,
        widget.postMessage.id,
        limit: 100,
      );
      final activeLocalIds = MediaSendCoordinator.instance.activeLocalIds;
      final result = <Message>[];
      for (final row in rows) {
        if (row.sendStatus != 0 && row.sendStatus != 2) continue;
        if (row.sendStatus == 0 &&
            row.serverId == null &&
            !activeLocalIds.contains(row.localId)) {
          await db.updateMessageStatus(
            row.localId,
            MessageSendStatus.failed.index,
          );
          result.add(
            Message.fromDbMessage(
              row.copyWith(sendStatus: MessageSendStatus.failed.index),
            ),
          );
        } else {
          result.add(Message.fromDbMessage(row));
        }
      }
      return result;
    } catch (_) {
      return const [];
    }
  }

  void _mergeUnsentComment(Message unsent) {
    final lid = (unsent.localId != null && unsent.localId!.isNotEmpty)
        ? unsent.localId
        : null;
    final idx = _comments.indexWhere(
      (c) =>
          c.id == unsent.id ||
          (lid != null &&
              ((c.localId != null && c.localId == lid) || c.id == lid)),
    );
    if (idx != -1) {
      if (_comments[idx].sendStatus == 1) {
        return;
      }
      _comments[idx] = unsent;
      return;
    }
    _comments.add(unsent);
  }

  Future<void> _loadInitial() async {
    _currentUserId = await AuthService.getUserId();

    final List<Message> initialLocal = [];
    // Load cached thread comments from Drift if we already have linkedChatId
    if (_linkedChatId != null && _rootMessageId != null) {
      try {
        final local = await AppDatabase().getThreadComments(
          _linkedChatId!,
          _rootMessageId!,
          limit: 100,
        );
        initialLocal.addAll(local.map((m) => Message.fromDbMessage(m)));
      } catch (_) {}
    }
    final pendingLocal = await _loadPendingAndFailedDbComments();
    if ((initialLocal.isNotEmpty || pendingLocal.isNotEmpty) && mounted) {
      setState(() {
        _comments
          ..clear()
          ..addAll(initialLocal);
        for (final p in pendingLocal) {
          _mergeUnsentComment(p);
        }
        _dedupeCommentsInPlace();
        _sortCommentsAscending();
        _isLoading = false;
      });
      _resolvePendingDraftReply();
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
    final pendingLocal = await _loadPendingAndFailedDbComments();
    if (!mounted) return;

    setState(() {
      _isLoading = false;
      final existingUnsent = _comments.where((c) => c.sendStatus != 1).toList();
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
      } else {
        _errorMessage = res.errorMessage;
      }

      for (final unsent in existingUnsent) {
        _mergeUnsentComment(unsent);
      }
      for (final p in pendingLocal) {
        _mergeUnsentComment(p);
      }
      _dedupeCommentsInPlace();
      _sortCommentsAscending();
      if (res.success) {
        _commentsCount = math.max(
          _rootPost.commentsCount,
          _comments.where((c) => c.sendStatus == 1).length,
        );
      }
    });
    if (res.success) {
      _resolvePendingDraftReply(serverLoaded: true);
    }
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
    bool isViewOnce = false,
    int ttlSeconds = 0,
    bool preserveComposerDraft = false,
    List<File>? overrideFiles,
    Map<String, String>? captionsByPath,
  }) async {
    if (!_canComment) return;
    final String controllerClean = _messageController.cleanText.trimRight();
    final List<MessageEntity> controllerEntities = _messageController.entities;
    final String text = (cleanText ?? controllerClean).trimRight();
    final List<MessageEntity> resolvedEntities = entities ?? controllerEntities;
    final bool hasOverrideFiles =
        overrideFiles != null && overrideFiles.isNotEmpty;
    final bool hasFilesToSend = hasOverrideFiles || _attachedFiles.isNotEmpty;
    if ((text.trim().isEmpty && !hasFilesToSend) ||
        (!hasFilesToSend && _isSending)) {
      return;
    }

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
    final String activeSendAsMode = _effectiveSendAsMode;
    final String? activeSendAsChatId = _effectiveSendAsChannelId;
    final bool sendAsAnon = _effectiveSendAsAnon;
    final SendAsPeer? activeSendAsPeer = _activeSendAsPeer;
    final bool sendingAsChannel =
        activeSendAsMode == 'channel' &&
        activeSendAsChatId != null &&
        activeSendAsChatId.isNotEmpty;
    final String anonGroupTitle =
        (_linkedGroupName != null && _linkedGroupName!.trim().isNotEmpty)
        ? _linkedGroupName!
        : (activeSendAsPeer != null && activeSendAsPeer.isGroupAnon && activeSendAsPeer.name.isNotEmpty
            ? activeSendAsPeer.name
            : (widget.channelName ?? 'Обсуждение'));

    final List<File> filesToSend = hasOverrideFiles
        ? List<File>.from(overrideFiles)
        : List<File>.from(_attachedFiles);
    final bool isMediaSend = filesToSend.isNotEmpty;
    _suppressDraftSave = true;
    try {
      setState(() {
        _attachedFiles.clear();
        _attachedFileNames.clear();
        if (!isMediaSend) {
          _isSending = true;
        }
        _replyToComment = null;
        _pendingDraftReplyId = null;
        _isQuote = false;
        _quoteText = null;
        _quoteOffset = 0;
        _quoteLength = 0;
      });
      if (!preserveComposerDraft) {
        _messageController.clear();
      }
    } finally {
      _suppressDraftSave = false;
    }
    if (!preserveComposerDraft) {
      DraftService().clearLocalDraftOnSend(_draftKey);
    } else if (replyTo != null) {
      _saveCurrentDraft(immediate: true);
    }

    if (isMediaSend) {
      try {
        await MediaSendCoordinator.instance.enqueueMediaOrFiles(
          chatId: widget.channelId,
          files: filesToSend,
          asDocument: asDocument,
          caption: text,
          captionsByPath: captionsByPath,
          entities: resolvedEntities,
          invertMedia: invertMedia,
          replyToMessageId: replyTo?.id,
          isQuote: capturedIsQuote,
          quoteText: capturedQuoteText,
          quoteOffset: capturedQuoteOffset,
          quoteLength: capturedQuoteLength,
          replyToSenderId: replyTo != null
              ? ((replyTo.isChannelOrPersonaAuthored ||
                      replyTo.id == _rootMessageId ||
                      replyTo.id == widget.postMessage.id)
                  ? '0'
                  : replyTo.senderId)
              : null,
          replyToSenderName: replyTo?.resolveEffectiveAuthorTitle(
            chatName: widget.channelName,
            chatType: (replyTo.id == widget.postMessage.id ||
                    replyTo.id == _rootMessageId)
                ? 'channel'
                : null,
          ),
          replyToContent: replyTo?.content,
          replyToMessageType: replyTo?.messageType ?? 'text',
          hasMediaSpoiler: hasMediaSpoiler,
          isViewOnce: isViewOnce,
          ttlSeconds: ttlSeconds,
          sendAsChatId: activeSendAsChatId,
          sendAsMode: activeSendAsMode,
          sendAsAnonymous: sendAsAnon,
          threadRootMessageId: widget.postMessage.id,
          senderId: _currentUserId,
          senderName: sendingAsChannel
              ? (activeSendAsPeer?.name ?? 'Канал')
              : (sendAsAnon ? anonGroupTitle : null),
          senderAvatarUrl: sendingAsChannel
              ? activeSendAsPeer?.avatarUrl
              : (sendAsAnon
                  ? (_linkedGroupAvatar ?? widget.channelAvatar)
                  : null),
          senderChatName: sendingAsChannel ? activeSendAsPeer?.name : null,
          senderChatAvatarUrl:
              sendingAsChannel ? activeSendAsPeer?.avatarUrl : null,
        );
      } catch (e) {
        if (mounted) {
          GlassToastService().show(context, 'Ошибка отправки: $e');
        }
      }
      return;
    }

    try {

      final localId = 'local_comment_${DateTime.now().microsecondsSinceEpoch}';
      final optimistic = Message(
        id: localId,
        localId: localId,
        chatId: _linkedChatId ?? widget.channelId,
        senderId: _currentUserId ?? '',
        content: text,
        messageType: 'text',
        replyToMessageId: replyTo?.id,
        replyInfo: replyTo != null
            ? ReplyInfo(
                messageId: replyTo.id,
                senderId: (replyTo.isChannelOrPersonaAuthored ||
                        replyTo.id == _rootMessageId ||
                        replyTo.id == widget.postMessage.id)
                    ? '0'
                    : replyTo.senderId,
                senderName: replyTo.resolveEffectiveAuthorTitle(
                  chatName: widget.channelName,
                  chatType: (replyTo.id == widget.postMessage.id ||
                          replyTo.id == _rootMessageId)
                      ? 'channel'
                      : null,
                ),
                senderChatId: replyTo.senderChatId,
                isFromAnonymousAdmin: replyTo.isFromAnonymousAdmin,
                content: replyTo.content,
                messageType: replyTo.messageType,
                entities: replyTo.entities,
              )
            : null,
        isEdited: false,
        createdAt: DateTime.now().toUtc().toIso8601String(),
        senderName: sendingAsChannel
            ? (activeSendAsPeer?.name ?? 'Канал')
            : (sendAsAnon ? anonGroupTitle : 'Вы'),
        senderAvatarUrl: sendingAsChannel
            ? activeSendAsPeer?.avatarUrl
            : (sendAsAnon
                ? (_linkedGroupAvatar ?? widget.channelAvatar)
                : null),
        senderChatId: sendingAsChannel ? activeSendAsChatId : null,
        senderChatName: sendingAsChannel ? activeSendAsPeer?.name : null,
        senderChatAvatarUrl:
            sendingAsChannel ? activeSendAsPeer?.avatarUrl : null,
        isFromAnonymousAdmin: !sendingAsChannel && sendAsAnon,
        isOwn: true,
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
        localId: localId,
        replyToMessageId: replyTo?.id,
        isQuote: capturedIsQuote,
        quoteText: capturedQuoteText,
        quoteOffset: capturedQuoteOffset,
        quoteLength: capturedQuoteLength,
        entities: resolvedEntities.isNotEmpty ? resolvedEntities : null,
        messageType: 'text',
        hasMediaSpoiler: hasMediaSpoiler,
        sendAsMode: activeSendAsMode,
        sendAsChatId: activeSendAsChatId,
        sendAsAnonymous: sendAsAnon,
      );

      if (!mounted) return;
      if (sent != null) {
        setState(() {
          _confirmSentComment(sent, localId: localId);
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
    final localId = 'local_comment_${DateTime.now().microsecondsSinceEpoch}';
    final sent = await ChatService.sendPostComment(
      channelId: widget.channelId,
      messageId: widget.postMessage.id,
      content: fallback,
      localId: localId,
      replyToMessageId: replyTo?.id,
      fileUrl: item.fileUrl,
      fileName: 'sticker.${item.format}',
      messageType: 'sticker',
      sendAsMode: _effectiveSendAsMode,
      sendAsChatId: _effectiveSendAsChannelId,
      sendAsAnonymous: _effectiveSendAsAnon,
    );
    if (sent != null && mounted) {
      setState(() {
        _confirmSentComment(sent, localId: localId);
      });
      _bindLinkedGroupSubscription();
      _scrollToBottom();
    }
  }

  Future<void> _sendGifComment(GifItemModel gif) async {
    if (!_canComment) return;
    final replyTo = _replyToComment;
    _cancelReply();
    final localId = 'local_comment_${DateTime.now().microsecondsSinceEpoch}';
    final sent = await ChatService.sendPostComment(
      channelId: widget.channelId,
      messageId: widget.postMessage.id,
      content: 'GIF',
      localId: localId,
      replyToMessageId: replyTo?.id,
      fileUrl: gif.url,
      fileName: 'animation.gif',
      messageType: 'gif',
      sendAsMode: _effectiveSendAsMode,
      sendAsChatId: _effectiveSendAsChannelId,
      sendAsAnonymous: _effectiveSendAsAnon,
    );
    if (sent != null && mounted) {
      setState(() {
        _confirmSentComment(sent, localId: localId);
      });
      _bindLinkedGroupSubscription();
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

  void _saveCurrentDraft({bool immediate = false}) {
    if (_suppressDraftSave || _isEditing || !_canComment) return;
    DraftService().saveDraft(
      _draftKey,
      text: _messageController.cleanText,
      entities: _messageController.entities,
      replyToMessageId: _replyToComment?.id,
      quoteText: _quoteText,
      isQuote: _isQuote,
      quoteOffset: _quoteOffset,
      quoteLength: _quoteLength,
      immediate: immediate,
    );
  }

  void _onControllerDraftSync() {
    _saveCurrentDraft();
  }

  void _resolvePendingDraftReply({bool serverLoaded = false}) {
    final pendingId = _pendingDraftReplyId;
    if (pendingId == null || pendingId.isEmpty) return;
    Message? found;
    for (final c in _comments) {
      if (c.id == pendingId) {
        found = c;
        break;
      }
    }
    if (found != null) {
      _pendingDraftReplyId = null;
      if (!_isEditing && _replyToComment == null && mounted) {
        setState(() => _replyToComment = found);
      }
      return;
    }
    if (serverLoaded) {
      _pendingDraftReplyId = null;
      if (!_isEditing && mounted && (_isQuote || _quoteText != null)) {
        setState(() {
          _isQuote = false;
          _quoteText = null;
          _quoteOffset = 0;
          _quoteLength = 0;
        });
      }
      _saveCurrentDraft(immediate: true);
    }
  }

  void _enterEditMode(Message comment) {
    if (!_isEditing) {
      _stashedDraftBeforeEdit = (
        text: _messageController.cleanText,
        entities: List<MessageEntity>.from(_messageController.entities),
        replyTo: _replyToComment,
        isQuote: _isQuote,
        quoteText: _quoteText,
        quoteOffset: _quoteOffset,
        quoteLength: _quoteLength,
      );
    }
    _suppressDraftSave = true;
    try {
      setState(() {
        _replyToComment = null;
        _pendingDraftReplyId = null;
        _isQuote = false;
        _quoteText = null;
        _quoteOffset = 0;
        _quoteLength = 0;
        _isEditing = true;
        _editingCommentId = comment.id;
        _messageController.loadMessage(
          comment.content,
          comment.entities,
        );
      });
    } finally {
      _suppressDraftSave = false;
    }
    _focusInput();
  }

  void _startReply(Message comment) {
    final stashed = _stashedDraftBeforeEdit;
    _stashedDraftBeforeEdit = null;
    _suppressDraftSave = true;
    try {
      setState(() {
        if (_isEditing) {
          _isEditing = false;
          _editingCommentId = null;
          if (stashed != null && stashed.text.isNotEmpty) {
            _messageController.loadMessage(stashed.text, stashed.entities);
          } else {
            _messageController.clear();
          }
        }
        _replyToComment = comment;
        _pendingDraftReplyId = null;
        _isQuote = false;
        _quoteText = null;
        _quoteOffset = 0;
        _quoteLength = 0;
      });
    } finally {
      _suppressDraftSave = false;
    }
    _saveCurrentDraft();
    _focusInput();
  }

  void _startQuote(
    Message comment,
    String selectedText,
    int offset,
    int length,
  ) {
    final stashed = _stashedDraftBeforeEdit;
    _stashedDraftBeforeEdit = null;
    _suppressDraftSave = true;
    try {
      setState(() {
        if (_isEditing) {
          _isEditing = false;
          _editingCommentId = null;
          if (stashed != null && stashed.text.isNotEmpty) {
            _messageController.loadMessage(stashed.text, stashed.entities);
          } else {
            _messageController.clear();
          }
        }
        _replyToComment = comment;
        _pendingDraftReplyId = null;
        _isQuote = true;
        _quoteText = selectedText;
        _quoteOffset = offset;
        _quoteLength = length;
      });
    } finally {
      _suppressDraftSave = false;
    }
    _saveCurrentDraft();
    _focusInput();
  }

  void _cancelReply() {
    setState(() {
      _replyToComment = null;
      _pendingDraftReplyId = null;
      _isQuote = false;
      _quoteText = null;
      _quoteOffset = 0;
      _quoteLength = 0;
    });
    _saveCurrentDraft(immediate: true);
  }

  void _cancelEditing() {
    final stashed = _stashedDraftBeforeEdit;
    _stashedDraftBeforeEdit = null;
    _suppressDraftSave = true;
    try {
      setState(() {
        _isEditing = false;
        _editingCommentId = null;
        if (stashed != null) {
          _messageController.loadMessage(stashed.text, stashed.entities);
          _replyToComment = stashed.replyTo;
          _isQuote = stashed.isQuote;
          _quoteText = stashed.quoteText;
          _quoteOffset = stashed.quoteOffset;
          _quoteLength = stashed.quoteLength;
        } else {
          _messageController.clear();
        }
      });
    } finally {
      _suppressDraftSave = false;
    }
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
      if (!_messageController.selection.isValid) {
        _messageController.selection = TextSelection.collapsed(
          offset: _messageController.text.length,
        );
      }
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_showEmojiPanel || _isKeyboardRising) return;
          if (!_inputFocusNode.hasFocus) _inputFocusNode.requestFocus();
          if (_isMobilePlatform) {
            SystemChannels.textInput.invokeMethod('TextInput.hide');
          }
        });
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
        if (_isMobilePlatform) {
          SystemChannels.textInput.invokeMethod('TextInput.hide');
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_showEmojiPanel || _isKeyboardRising) return;
          if (!_inputFocusNode.hasFocus) _inputFocusNode.requestFocus();
          if (_isMobilePlatform) {
            SystemChannels.textInput.invokeMethod('TextInput.hide');
          }
        });
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
        await _sendComment(
          cleanText: '',
          entities: const [],
          asDocument: result.asDocument,
          preserveComposerDraft: true,
          overrideFiles: result.files!,
        );
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
          await _sendComment(
            cleanText: mediaRes.caption ?? '',
            entities: const [],
            hasMediaSpoiler: mediaRes.hasMediaSpoiler,
            asDocument: mediaRes.asDocument,
            isViewOnce: mediaRes.isViewOnce,
            ttlSeconds: mediaRes.ttlSeconds,
            preserveComposerDraft: true,
            overrideFiles: mediaRes.files,
            captionsByPath: mediaRes.captionsByPath,
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
        List<XFile> pickedMedia = [];
        try {
          pickedMedia = await _imagePicker.pickMultipleMedia(
            maxWidth: 1920,
            maxHeight: 1920,
            imageQuality: 92,
          );
        } catch (_) {
          final XFile? single = await _imagePicker.pickMedia(
            maxWidth: 1920,
            maxHeight: 1920,
            imageQuality: 92,
          );
          if (single != null) pickedMedia = [single];
        }
        if (pickedMedia.isNotEmpty && mounted) {
          setState(() {
            for (final media in pickedMedia) {
              _attachedFiles.add(File(media.path));
              _attachedFileNames.add(p.basename(media.path));
            }
          });
        }
        break;
      case AttachmentPickerAction.file:
        final picked = await FilePicker.platform.pickFiles(
          type: FileType.any,
          allowMultiple: true,
        );
        if (picked != null && picked.files.isNotEmpty && mounted) {
          setState(() {
            for (final f in picked.files) {
              if (f.path != null) {
                _attachedFiles.add(File(f.path!));
                _attachedFileNames.add(f.name);
              }
            }
          });
        }
        break;
      case AttachmentPickerAction.poll:
        if (_linkedChatId != null && _linkedChatId!.isNotEmpty) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PollCreateScreen(
                chatId: _linkedChatId!,
                sendAsMode: _effectiveSendAsMode,
                sendAsChatId: _effectiveSendAsChannelId,
                sendAsAnonymous: _effectiveSendAsAnon,
                replyToMessageId: _replyToComment?.id ?? _rootMessageId,
              ),
            ),
          );
        }
        break;
      default:
        break;
    }
  }

  void _openFile(
    String fileUrl,
    String fileName,
    String messageType, {
    Message? sourceMessage,
  }) {
    final resolved = AppConfig.resolveMediaUrl(fileUrl) ?? fileUrl;
    final lowerType = messageType.toLowerCase();
    if (lowerType == 'image' || lowerType == 'photo') {
      FullscreenPhotoViewer.open(context, resolved);
      return;
    }
    if (lowerType == 'video') {
      final baseMsg = (sourceMessage ?? _rootPost).copyWith(
        fileUrl: resolved,
        fileName: fileName.isNotEmpty ? fileName : sourceMessage?.fileName,
        messageType: 'video',
      );
      _openThreadMediaViewer(baseMsg, localFilePath: fileUrl != resolved ? fileUrl : null);
      return;
    }
    final sheetTitle = fileName.trim().isNotEmpty
        ? fileName
        : (lowerType == 'audio' ? 'Аудиозапись' : 'Файл');
    showTheavModalSheet<void>(
      context: context,
      title: sheetTitle,
      showCloseButton: true,
      builder: (sheetCtx) => TheavInsetGroup(
        margin: EdgeInsets.zero,
        children: [
          TheavListRow(
            leading: const iconoir.OpenNewWindow(width: 20, height: 20),
            title: context.l10n.translate('chat_open_file'),
            onTap: () {
              Navigator.pop(sheetCtx);
              _downloadAndOpenFile(resolved, sheetTitle);
            },
          ),
          if (!_hasProtectedContent) ...[
            TheavListRow(
              leading: const iconoir.Download(width: 20, height: 20),
              title: context.l10n.translate('chat_download'),
              onTap: () {
                Navigator.pop(sheetCtx);
                _downloadFile(resolved, sheetTitle);
              },
            ),
            TheavListRow(
              leading: const iconoir.ShareAndroid(width: 20, height: 20),
              title: context.l10n.translate('share'),
              onTap: () async {
                Navigator.pop(sheetCtx);
                await SharePlus.instance.share(
                  ShareParams(text: resolved, subject: sheetTitle),
                );
              },
            ),
          ],
        ],
      ),
    );
  }

  Future<void> _downloadAndOpenFile(String fileUrl, String fileName) async {
    try {
      if (kIsWeb) {
        final uri = Uri.parse(fileUrl);
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, webOnlyWindowName: '_blank');
        }
      } else {
        final filePath = await _fileService.downloadToDownloads(
          fileUrl,
          fileName,
        );
        if (mounted) {
          GlassToastService().show(context, 'Файл скачан: $filePath');
          await _fileService.openFile(filePath);
        }
      }
    } catch (e) {
      if (mounted) {
        GlassToastService().show(context, 'Ошибка при открытии файла: $e');
      }
    }
  }

  Future<void> _downloadFile(String fileUrl, String fileName) async {
    try {
      if (kIsWeb) {
        final uri = Uri.parse(fileUrl);
        await launchUrl(uri, webOnlyWindowName: '_blank');
        return;
      }
      final filePath = await _fileService.downloadToDownloads(
        fileUrl,
        fileName,
      );
      if (mounted) {
        GlassToastService().show(context, 'Файл скачан: $filePath');
      }
    } catch (e) {
      if (mounted) {
        GlassToastService().show(context, 'Ошибка при скачивании файла: $e');
      }
    }
  }

  void _openUserProfile(Message msg) {
    final hasSenderChat = msg.senderChatId != null &&
        msg.senderChatId!.trim().isNotEmpty &&
        msg.senderChatId!.trim() != '0';
    if (hasSenderChat) {
      _openChannelProfileById(
        msg.senderChatId!,
        name: msg.senderChatName?.trim().isNotEmpty == true
            ? msg.senderChatName
            : msg.senderName,
        avatarUrl: msg.senderChatAvatarUrl ?? msg.senderAvatarUrl,
      );
      return;
    }
    if (msg.isFromAnonymousAdmin) {
      _openLinkedGroupProfile();
      return;
    }
    if (msg.isMirroredChannelPost ||
        msg.id == _rootMessageId ||
        msg.id == _rootPost.id) {
      return;
    }
    if (msg.senderId.isEmpty || msg.senderId == '0') return;
    HapticUtils.tap();
    final canResolve = ContactsService.shouldResolveUserIdentity(
      msg.senderId,
      senderChatId: msg.senderChatId,
      isAnonymousAdmin: msg.isFromAnonymousAdmin,
      isMirroredChannelPost: msg.isMirroredChannelPost,
    );
    final effectiveName = canResolve
        ? ContactsService.resolvePeerName(msg.senderId, msg.senderName)
        : msg.senderName;
    final effectiveAvatar = canResolve
        ? ContactsService.resolvePeerAvatarUrl(msg.senderId, msg.senderAvatarUrl)
        : msg.senderAvatarUrl;
    Navigator.push(
      context,
      SwipeBackPageRoute(
        builder: (_) => ProfileScreen(
          entityType: ProfileEntityType.user,
          userId: msg.senderId,
          initialName: effectiveName,
          initialAvatarUrl: effectiveAvatar,
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

  bool _isOwnComment(Message c) =>
      c.isOwn ||
      (_currentUserId != null &&
          _currentUserId!.isNotEmpty &&
          c.senderId == _currentUserId);

  bool get _canDeleteSelectedComments {
    if (_selectedCommentIds.isEmpty) return false;
    final selected = _comments
        .where((c) => _selectedCommentIds.contains(c.id))
        .toList();
    if (selected.isEmpty) return false;
    return selected.every((c) => _isOwnComment(c) || _canDeleteOthers);
  }

  void _confirmDeleteComment(Message comment) {
    unawaited(_deleteCommentsWithSheet([comment]));
  }

  void _deleteSelectedComments() {
    if (_selectedCommentIds.isEmpty) return;
    final targets = _comments
        .where(
          (c) =>
              _selectedCommentIds.contains(c.id) &&
              (_isOwnComment(c) || _canDeleteOthers),
        )
        .toList();
    setState(() => _selectedCommentIds.clear());
    if (targets.isEmpty) return;
    unawaited(_deleteCommentsWithSheet(targets));
  }

  Future<void> _deleteCommentsWithSheet(List<Message> targets) async {
    if (targets.isEmpty) return;
    final bool allMine = targets.every(_isOwnComment);
    if (!allMine && !_canDeleteOthers) return;

    final unsentMessages = targets
        .where((m) => m.sendStatus != 1 || m.id.startsWith('local_'))
        .toList();
    final serverMessages = targets
        .where((m) => m.sendStatus == 1 && !m.id.startsWith('local_'))
        .toList();

    final bool canModerate = !allMine && _canDeleteOthers;
    final String? authorName = targets.length == 1
        ? () {
            final target = targets.first;
            final isRootPost = target.id == _rootMessageId ||
                target.id == _rootPost.id ||
                target.isMirroredChannelPost;
            final fallbackTitle = target.resolveEffectiveAuthorTitle(
              chatName: _linkedGroupName ?? widget.channelName,
              chatType: isRootPost ? 'channel' : null,
            );
            return ContactsService.resolvePeerName(
              target.senderId,
              fallbackTitle,
              senderChatId: target.senderChatId,
              isAnonymousAdmin: target.isFromAnonymousAdmin,
              isMirroredChannelPost: isRootPost,
            );
          }()
        : null;

    final res = await showTelegramDeleteMessagesSheet(
      context: context,
      messageCount: targets.length,
      chatType: 'group',
      canRevoke: serverMessages.isNotEmpty && (allMine || _canDeleteOthers),
      defaultRevoke: serverMessages.isNotEmpty && (allMine || _canDeleteOthers),
      canModerateOther: serverMessages.isNotEmpty && canModerate,
      targetAuthorName: authorName,
    );
    if (res == null || !res.confirmed || !mounted) return;

    if (unsentMessages.isNotEmpty) {
      final unsentIds = <String>{};
      for (final m in unsentMessages) {
        final lid = m.localId ?? m.id;
        unsentIds.add(m.id);
        unsentIds.add(lid);
        await MediaSendCoordinator.instance.cancelUpload(lid);
        await AppDatabase().deleteMessage(lid);
        if (m.id != lid) {
          await AppDatabase().deleteMessage(m.id);
        }
      }
      if (mounted) {
        setState(() {
          _comments.removeWhere(
            (c) =>
                unsentIds.contains(c.id) ||
                (c.localId != null && unsentIds.contains(c.localId)),
          );
          _selectedCommentIds.removeAll(unsentIds);
        });
      }
    }

    if (serverMessages.isEmpty || !mounted) return;

    final ids = serverMessages.map((c) => c.id).toList();
    final backup = List<Message>.from(_comments);
    final prevCount = _commentsCount;
    setState(() {
      _comments.removeWhere((c) => ids.contains(c.id));
      _selectedCommentIds.removeAll(ids);
      _commentsCount = math.max(0, _commentsCount - serverMessages.length);
      _rootPost = _rootPost.copyWith(commentsCount: _commentsCount);
    });

    final targetChatId = serverMessages.first.chatId.isNotEmpty
        ? serverMessages.first.chatId
        : (_linkedChatId ?? widget.channelId);

    final apiRes = await ChatService.deleteMessagesBatch(
      chatId: targetChatId,
      messageIds: ids,
      revoke: res.revoke,
      reportSpam: res.reportSpam,
      banUser: res.banUser,
      deleteAllFromUser: res.deleteAllFromUser,
    );
    if (apiRes['success'] == true) {
      if (res.deleteAllFromUser && serverMessages.isNotEmpty && mounted) {
        final offenderId = serverMessages.first.senderId;
        if (offenderId.isNotEmpty && offenderId != '0') {
          setState(() {
            final before = _comments.length;
            _comments.removeWhere((c) => c.senderId == offenderId);
            final removedExtra = before - _comments.length;
            if (removedExtra > 0) {
              _commentsCount = math.max(0, _commentsCount - removedExtra);
              _rootPost = _rootPost.copyWith(commentsCount: _commentsCount);
            }
          });
        }
      }
    } else if (mounted) {
      setState(() {
        _comments
          ..clear()
          ..addAll(backup);
        _commentsCount = prevCount;
        _rootPost = _rootPost.copyWith(commentsCount: _commentsCount);
      });
      GlassToastService().showError(
        context,
        apiRes['message']?.toString() ?? 'Не удалось удалить комментарии',
      );
    }
  }

  Future<void> _retryComment(Message comment) async {
    final localId = (comment.localId != null && comment.localId!.isNotEmpty)
        ? comment.localId!
        : comment.id;
    if (localId.isEmpty) return;

    final dbRow = await AppDatabase().getMessageByLocalId(localId);
    if (dbRow != null) {
      if (mounted) {
        setState(() {
          final idx = _comments.indexWhere(
            (c) =>
                (c.localId != null && c.localId == localId) ||
                c.id == localId,
          );
          if (idx != -1) {
            _comments[idx] = _comments[idx].copyWith(sendStatus: 0);
          }
        });
      }
      await SyncService().retryFailedMessage(localId);
      return;
    }

    if (!mounted) return;
    setState(() {
      final idx = _comments.indexWhere(
        (c) => (c.localId != null && c.localId == localId) || c.id == localId,
      );
      if (idx != -1) {
        _comments[idx] = _comments[idx].copyWith(sendStatus: 0);
      }
    });
    final sent = await ChatService.sendPostComment(
      channelId: widget.channelId,
      messageId: widget.postMessage.id,
      content: comment.content,
      localId: localId,
      replyToMessageId: comment.replyToMessageId,
      isQuote: comment.isQuote,
      quoteText: comment.quoteText,
      quoteOffset: comment.quoteOffset,
      quoteLength: comment.quoteLength,
      entities: comment.entities.isNotEmpty ? comment.entities : null,
      messageType: comment.messageType,
      hasMediaSpoiler: comment.hasMediaSpoiler,
      sendAsMode: (comment.senderChatId != null &&
              comment.senderChatId!.isNotEmpty)
          ? 'channel'
          : (comment.isFromAnonymousAdmin ? 'group' : 'user'),
      sendAsChatId: comment.senderChatId,
      sendAsAnonymous: comment.isFromAnonymousAdmin,
    );
    if (!mounted) return;
    if (sent != null) {
      setState(() {
        _confirmSentComment(sent, localId: localId);
      });
      _bindLinkedGroupSubscription();
    } else {
      setState(() {
        final idx = _comments.indexWhere(
          (c) =>
              (c.localId != null && c.localId == localId) || c.id == localId,
        );
        if (idx != -1) {
          _comments[idx] = _comments[idx].copyWith(sendStatus: 2);
        }
      });
    }
  }

  void _showCommentContextMenu(Message comment, GlobalKey key, bool isMe) {
    MessageContextMenuService().show(
      context: context,
      message: comment,
      messageKey: key,
      isMe: isMe,
      currentUserId: _currentUserId,
      hasProtectedContent: _hasProtectedContent,
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
      onForward: _hasProtectedContent
          ? null
          : () {
              ForwardChatPickerSheet.show(
                context,
                fromChatId: comment.chatId.isNotEmpty
                    ? comment.chatId
                    : (_linkedChatId ?? widget.channelId),
                messageIds: [comment.id],
              );
            },
      onEdit: (_canComment && isMe && comment.messageType == 'text')
          ? () => _enterEditMode(comment)
          : null,
      onDelete: (isMe || _canDeleteOthers) ? _confirmDeleteComment : null,
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
      swipeBackBlocked: _isSelectionMode,
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
        hasProtectedContent: _hasProtectedContent,
        onCancelSelection: () => setState(() => _selectedCommentIds.clear()),
        onReplySelected: (_selectedCommentIds.length == 1 && _canComment)
            ? () {
                final id = _selectedCommentIds.first;
                final target = _comments
                    .where((c) => c.id == id)
                    .firstOrNull;
                setState(() => _selectedCommentIds.clear());
                if (target != null) _startReply(target);
              }
            : null,
        onCopySelected: _hasProtectedContent
            ? null
            : () {
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
        onForwardSelected: _hasProtectedContent
            ? null
            : () {
                final ids = _selectedCommentIds.toList();
                setState(() => _selectedCommentIds.clear());
                ForwardChatPickerSheet.show(
                  context,
                  fromChatId: _linkedChatId ?? widget.channelId,
                  messageIds: ids,
                );
              },
        onDeleteSelected:
            _canDeleteSelectedComments ? _deleteSelectedComments : null,
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
                      hasProtectedContent: _hasProtectedContent,
                      onReactionTap: _toggleRootPostReaction,
                      onFileTap: (url, name, type) => _openFile(
                        url,
                        name,
                        type,
                        sourceMessage: _rootPost,
                      ),
                      onMediaTap: (post, {localFilePath}) =>
                          _openThreadMediaViewer(
                        post,
                        localFilePath: localFilePath,
                      ),
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
                          replyFallbackAuthorName: widget.channelName,
                          hintText: _effectiveSendAsAnon
                              ? context.trOr(
                                  'send_as_anonymous_hint',
                                  'Написать анонимно...',
                                )
                              : 'Добавить комментарий...',
                          isAnonymousAdmin: _effectiveSendAsAnon,
                          anonymousGroupAvatarUrl:
                              _linkedGroupAvatar ?? widget.channelAvatar,
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
                              ? InlineSendAsSelectorButton(
                                  chatId: _linkedChatId ?? widget.channelId,
                                  peers: _sendAsPeers,
                                  selectedPeer: _activeSendAsPeer,
                                  onPeerSelected: (picked) {
                                    setState(() {
                                      _selectedSendAsMode = picked.peerType;
                                      _selectedSendAsChatId = picked.isChannel
                                          ? (picked.chatId ?? picked.id)
                                          : null;
                                    });
                                  },
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

  void _openThreadMediaViewer(
    Message targetMessage, {
    String? localFilePath,
  }) {
    final timeline = buildChatMediaTimeline(
      <Message>[_rootPost, ..._comments],
      isReversed: false,
      hasProtectedContent: _hasProtectedContent,
    );
    int initialIndex = timeline.indexWhere(
      (it) =>
          it.messageId == targetMessage.id ||
          (targetMessage.localId != null && it.id == targetMessage.localId),
    );
    final List<TheavMediaItem> items;
    if (initialIndex == -1 || timeline.isEmpty) {
      items = <TheavMediaItem>[
        TheavMediaItem.fromMessage(
          targetMessage,
          localFilePathOverride: localFilePath,
          hasProtectedContent: _hasProtectedContent,
        ),
      ];
      initialIndex = 0;
    } else {
      items = timeline;
    }

    TheavMediaViewer.open<void>(
      context,
      items: items,
      initialIndex: initialIndex,
      config: TheavMediaViewerConfig(
        onJumpToMessage: (viewerCtx, item) {
          Navigator.of(viewerCtx).pop();
          final mid = item.messageId;
          if (mid == _rootPost.id) {
            if (_scrollController.hasClients) {
              _scrollController.animateTo(
                0.0,
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
              );
            }
          } else if (mid != null && mid.isNotEmpty) {
            _scrollToComment(mid);
          }
        },
        onForwardItem: _hasProtectedContent
            ? null
            : (viewerCtx, item) async {
                final mid = item.messageId;
                final fromCid = _linkedChatId ?? widget.channelId;
                if (mid != null && mid.isNotEmpty && fromCid.isNotEmpty) {
                  await ForwardChatPickerSheet.show(
                    viewerCtx,
                    fromChatId: fromCid,
                    messageIds: <String>[mid],
                  );
                }
              },
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
    _promoteCommentKey(fromLocalId: comment.localId, toId: comment.id);
    final key = _commentKeys.putIfAbsent(comment.id, () => GlobalKey());
    final displayComment = PostCommentsScreen.stripRootPostReplyForThreadView(
      comment,
      rootMessageId: _rootMessageId,
      rootPostId: _rootPost.id,
    );
    final bool isMe = _isOwnComment(comment);
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
        comment.senderChatId != null &&
        comment.senderChatId!.trim().isNotEmpty &&
        comment.senderChatId!.trim() != '0';
    final bool isChannelPostRoot =
        comment.id == _rootMessageId ||
        comment.id == _rootPost.id ||
        comment.isMirroredChannelPost;

    final PeerCustomization? senderCust =
        (!hasSenderChat &&
            !comment.isFromAnonymousAdmin &&
            !isChannelPostRoot &&
            comment.senderId.isNotEmpty &&
            comment.senderId != '0')
        ? (PeerCustomizationCache.instance.getSync(comment.senderId) ??
              comment.senderCustomization)
        : null;

    final bool canResolveCommentAuthor = ContactsService.shouldResolveUserIdentity(
      comment.senderId,
      senderChatId: comment.senderChatId,
      isAnonymousAdmin: comment.isFromAnonymousAdmin,
      isMirroredChannelPost: isChannelPostRoot,
    );

    final String resolvedSenderName = hasSenderChat
        ? (comment.senderChatName?.trim().isNotEmpty == true
              ? comment.senderChatName!
              : (comment.senderName.trim().isNotEmpty
                    ? comment.senderName
                    : 'Канал'))
        : (comment.isFromAnonymousAdmin
              ? (comment.senderName.trim().isNotEmpty &&
                        comment.senderName != 'Вы'
                    ? comment.senderName
                    : (_linkedGroupName ?? widget.channelName ?? 'Обсуждение'))
              : (canResolveCommentAuthor
                    ? ContactsService.resolvePeerName(
                        comment.senderId,
                        comment.senderName,
                        senderChatId: comment.senderChatId,
                        isAnonymousAdmin: comment.isFromAnonymousAdmin,
                        isMirroredChannelPost: isChannelPostRoot,
                      )
                    : comment.senderName));
    final String? resolvedSenderAvatar = hasSenderChat
        ? comment.senderChatAvatarUrl
        : (canResolveCommentAuthor
              ? ContactsService.resolvePeerAvatarUrl(
                  comment.senderId,
                  comment.senderAvatarUrl,
                  senderChatId: comment.senderChatId,
                  isAnonymousAdmin: comment.isFromAnonymousAdmin,
                  isMirroredChannelPost: isChannelPostRoot,
                )
              : comment.senderAvatarUrl);

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

    final bool showSenderHeader = firstInCluster &&
        (showAvatarGutter ||
            (isMe && (hasSenderChat || comment.isFromAnonymousAdmin)));
    final String? resolvedAdminTitle = hasSenderChat
        ? 'канал'
        : (comment.isFromAnonymousAdmin &&
                (comment.senderAdminTitle == null ||
                    comment.senderAdminTitle!.trim().isEmpty)
            ? 'анонимно'
            : comment.senderAdminTitle);
    final bool isSenderVerified = hasSenderChat
        ? _sendAsPeers.any(
            (p) =>
                p.isChannel &&
                (p.chatId == comment.senderChatId ||
                    p.id == comment.senderChatId) &&
                p.isVerified,
          )
        : false;

    final Widget? senderHeaderWidget = showSenderHeader
        ? SenderHeaderRow(
            senderName: resolvedSenderName,
            senderId: comment.senderId,
            senderChatId: comment.senderChatId,
            isFromAnonymousAdmin: comment.isFromAnonymousAdmin,
            isMirroredChannelPost: isChannelPostRoot,
            nameColor: (hasSenderChat || comment.isFromAnonymousAdmin)
                ? (isMe
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.primary)
                : _resolveSenderColor(comment),
            customization: senderCust,
            isVerified: isSenderVerified,
            adminTitle: resolvedAdminTitle,
            role: (hasSenderChat || comment.isFromAnonymousAdmin)
                ? null
                : comment.senderRole,
            rankColor: isMe
                ? Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.72)
                : null,
            onTapSender: onSenderTap,
          )
        : null;

    Widget rowWidget = MessageBubble(
      key: key,
      message: displayComment,
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
      hasProtectedContent: _hasProtectedContent,
      reactions: comment.reactions.isNotEmpty ? comment.reactions : null,
      myReactions: comment.myReactions.isNotEmpty ? comment.myReactions : null,
      onRetry: (msg) => _retryComment(msg),
      onReplyTap: (replyToId, _) => _scrollToComment(replyToId),
      onReactionTap: (emoji) {
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
        _toggleCommentReaction(comment.id, emoji);
      },
      onFileTap: (url, name, type) {
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
        _openFile(url, name, type, sourceMessage: comment);
      },
      onMediaTap: _isSelectionMode
          ? null
          : (msg, {localFilePath}) => _openThreadMediaViewer(
                msg,
                localFilePath: localFilePath,
              ),
      formatTime: _formatTime,
    );

    if (showAvatarGutter) {
      rowWidget = GroupMessageAvatarRow(
        senderId: hasSenderChat ? comment.senderChatId! : comment.senderId,
        senderChatId: comment.senderChatId,
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
      onSecondaryTapUp: (_) {
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
        _showCommentContextMenu(comment, key, isMe);
      },
      child: rowWidget,
    );

    return rowWidget;
  }
}
