import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:image_picker/image_picker.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:uuid/uuid.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import '../../models/chat_draft.dart';
import '../../models/profile_customization.dart';
import '../../services/chat_service.dart';
import '../../services/contacts_service.dart';
import '../../services/auth_service.dart';
import '../../services/websocket_service.dart';
import '../../services/unread_count_provider.dart';
import '../../services/database/app_database.dart';
import '../../services/sync_service.dart';
import '../../services/chat_realtime_manager.dart';
import '../../services/notification_service.dart';
import '../../services/peer_customization_cache.dart';
import '../../services/profile_instant_cache.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/chat/liquid_glass_input_field.dart';
import '../../widgets/chat/floating_glass_app_bar.dart';
import '../../widgets/chat/chat_scaffold.dart';
import '../../widgets/chat/chat_messages_list_view.dart';
import '../../widgets/chat/chat_messages_shimmer.dart';
import '../../widgets/chat/chat_scroll_navigator.dart';
import '../../widgets/chat/emoji_sticker_panel.dart';
import '../../widgets/message/message_bubble.dart';
import '../../widgets/chat/swipe_to_reply_wrapper.dart';
import '../../widgets/chat/unread_separator.dart';
import '../../utils/swipe_back_route.dart';
import 'private_chat_screen.dart';
import 'group_chat_screen.dart';
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
import 'package:permission_handler/permission_handler.dart';
import '../../services/draft_service.dart';
import '../../services/chat_actions_helper.dart';
import '../../services/glass_toast_service.dart';
import '../../widgets/chat/forward_options_sheet.dart';
import '../../widgets/chat/send_options_popup.dart';
import '../../widgets/chat/telegram_delete_messages_sheet.dart';
import 'pinned_messages_screen.dart';
import 'scheduled_messages_screen.dart';
import '../../services/message_context_menu_service.dart';
import '../../services/notification_settings_provider.dart';
import '../../services/screen_protection_service.dart';
import '../../widgets/chat/forward_chat_picker_sheet.dart';
import '../../widgets/chat/groups_channels_parity_widgets.dart';
import '../../widgets/chat/pinned_message_banner.dart';
import '../settings/profile_screen.dart';
import 'settings/channel_stats_screen.dart';
import '../../services/tiling_layout_controller.dart';
import '../../services/sticker_service.dart';
import '../../widgets/tiling/tile_viewport_scope.dart';
import '../../models/media_album.dart';
import '../../widgets/chat/chat_history_calendar.dart';
import '../../widgets/chat/channel_post_card.dart';
import '../../widgets/chat/channel_bottom_capsule_bar.dart';
import '../../widgets/chat/live_chat_call_banner.dart';
import '../../widgets/message/telegram_service_message_widget.dart';
import '../../widgets/chat/attachment_picker_bottom_sheet.dart';
import '../../services/bot_service.dart';
import '../../services/deep_link_service.dart';
import '../../services/dm_parity_service.dart';
import '../../widgets/chat/dm_parity_sheets.dart';
import '../../services/account_manager.dart';
import '../../services/chat_instant_cache.dart';
import '../../widgets/chat/contact_picker_sheet.dart';
import '../../widgets/chat/location_picker_sheet.dart';
import '../../widgets/chat/mention_and_bot_popup.dart';
import '../../widgets/bot/inline_results_popup.dart';
import '../../widgets/bot/mini_app_webview_sheet.dart';
import '../../widgets/message/fullscreen_photo_viewer.dart';
import 'media_send_screen.dart';
import 'poll_create_screen.dart';
import 'post_comments_screen.dart';



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
  late final ChatStickerInputTarget _stickerInputTarget;
  String? _lastActiveTileId;

  bool get _isDesktopPlatform =>
      !kIsWeb && (Platform.isWindows || Platform.isLinux || Platform.isMacOS);

  bool get _isMobilePlatform =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS);

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
  bool _isVerified = false;
  bool _showAuthorProfiles = false;
  bool _signMessages = false;
  String _myRole = 'guest';
  bool _isMember = true;
  bool _canPostInChannel = false;
  bool _canEditMessages = false;
  bool _canDeleteMessages = false;
  bool _canPinMessages = false;
  String? _linkedChatId;
  LinkedChatSummary? _linkedChat;
  String? _channelDescription;
  ReactionSettings? _reactionSettings;
  bool _hasActiveCall = false;
  bool _isSilentBroadcast = false;
  bool? _savedSilentBroadcastPref;
  bool _seededFromChatDetails = false;
  List<BotInfo> _inlineDirectoryBots = const [];
  String? _activeMentionQuery;
  int _mentionTokenStart = -1;
  int _mentionTokenEnd = -1;
  bool _mentionIsAtStart = false;
  final InlineQueryController _inlineQueryController = InlineQueryController();
  final Map<String, TranslationResult> _translationsByMsgId = {};
  final Set<String> _translatingMsgIds = {};
  List<ChatParticipant> _participants = [];
  Message? _pinnedMessage;
  List<Message> _pinnedMessages = [];
  int _currentPinnedIndex = 0;
  bool _hasProtectedContent = false;
  int _scheduledCount = 0;
  StagedForwardPayload? _stagedForward;
  bool _showScrollDownFab = false;
  double _lastScrollOffset = 0;
  double _accumulatedScrollDown = 0;
  double _accumulatedScrollUp = 0;
  double _newestMessageHeight = 150.0;
  double _lastStickyDateEvalOffset = -1000.0;
  String? _highlightMessageId;
  bool _hasScrolledToHighlight = false;
  final GlobalKey _inputKey = GlobalKey();
  double _inputHeight = 90.0;
  final Map<String, GlobalKey> _messageKeys = {};
  final List<String> _jumpHistory = [];

  // Feed albums, reactions, unread tracking & sticky date state
  List<FeedItem> _feedItems = [];
  final Map<String, Map<String, int>> _messageReactions = {};
  final Map<String, Set<String>> _myReactions = {};
  int _unreadCount = 0;
  String? _firstUnreadMessageId;
  bool _showUnreadDivider = false;
  int _firstUnreadFeedIndex = -1;
  final GlobalKey _unreadSeparatorKey = GlobalKey();
  final Map<String, GlobalKey> _dateSeparatorKeys = {};
  final GlobalKey _stickyDateSlotKey = GlobalKey();
  final ValueNotifier<StickyDateState> _stickyDateStateNotifier =
      ValueNotifier<StickyDateState>(StickyDateState.empty);
  List<({DateTime day, DateTime sampleDt, int newestIdx, int oldestIdx})>
      _daySpans = [];
  bool _stickyDatePostFrameScheduled = false;
  final Map<String, (DateTime, DateTime)> _dateCache = {};

  // Batch channel post view tracking (1.5s debounce)
  final Set<String> _viewedPostIdsThisSession = <String>{};
  final Set<String> _pendingViewIds = <String>{};
  Timer? _viewsFlushTimer;
  Timer? _entrySettleTimer;

  DateTime _dateOnly(DateTime dt) {
    final local = dt.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  (DateTime, DateTime) _resolveDates(String createdAt) {
    final cached = _dateCache[createdAt];
    if (cached != null) return cached;
    final dt = DateTimeUtils.parseUtcDateTime(createdAt) ?? DateTime.now();
    final day = _dateOnly(dt);
    final result = (dt, day);
    if (_dateCache.length > 500) _dateCache.clear();
    _dateCache[createdAt] = result;
    return result;
  }

  String _formatDateLabel(DateTime dt) =>
      DateTimeUtils.formatDateSeparator(dt, context: context);

  GlobalKey _dateSeparatorKeyFor(DateTime day, Message primaryMessage) {
    final stableId = (primaryMessage.localId != null &&
            primaryMessage.localId!.isNotEmpty)
        ? primaryMessage.localId!
        : primaryMessage.id;
    return _dateSeparatorKeys.putIfAbsent(
      '${day.millisecondsSinceEpoch}_$stableId',
      () => GlobalKey(),
    );
  }

  GlobalKey _dateSeparatorKeyForFeedIndex(DateTime day, int feedIndex) {
    if (feedIndex < 0 || feedIndex >= _feedItems.length) {
      return _dateSeparatorKeys.putIfAbsent(
        '${day.millisecondsSinceEpoch}_idx_$feedIndex',
        () => GlobalKey(),
      );
    }
    final item = _feedItems[feedIndex];
    final msg = item is FeedAlbumItem
        ? item.album.primaryMessage
        : (item as FeedSingleItem).message;
    return _dateSeparatorKeyFor(day, msg);
  }

  bool _isOwnChannelPost(Message m) {
    if (m.isOwn) return true;
    final uid = _currentUserId;
    if (uid == null || uid.isEmpty) return false;
    return m.senderId == uid || m.postAuthorId == uid;
  }

  bool _canEditChannelPost(Message m) =>
      _canEditMessages || (_canPostInChannel && _isOwnChannelPost(m));

  bool _canDeleteChannelPosts(Iterable<Message> msgs) =>
      _canDeleteMessages ||
      (_canPostInChannel && msgs.isNotEmpty && msgs.every(_isOwnChannelPost));

  bool get _canDeleteSelectedChannelPosts {
    if (_selectedMessageIds.isEmpty) return false;
    if (_canDeleteMessages) return true;
    if (!_canPostInChannel) return false;
    final selected = _messages
        .where((m) => _selectedMessageIds.contains(m.id))
        .toList();
    return selected.isNotEmpty && selected.every(_isOwnChannelPost);
  }

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
    for (final span in spans) {
      _dateSeparatorKeyForFeedIndex(span.day, span.oldestIdx);
    }
    _daySpans = spans;

    if (_messageKeys.length > _messages.length * 2 + 200) {
      final activeIds = <String>{
        for (final m in _messages) m.id,
        for (final m in _messages)
          if (m.localId != null && m.localId!.isNotEmpty) m.localId!,
      };
      _messageKeys.removeWhere((id, _) => !activeIds.contains(id));
    }
    _scheduleStickyDateUpdate();
  }

  void _syncReactionCacheFromMessages(List<Message> msgs) {
    for (final m in msgs) {
      if (m.reactions.isNotEmpty) {
        _messageReactions[m.id] = Map<String, int>.from(m.reactions);
      } else {
        _messageReactions.remove(m.id);
      }
      if (m.myReactions.isNotEmpty) {
        _myReactions[m.id] = Set<String>.from(m.myReactions);
      } else {
        _myReactions.remove(m.id);
      }
    }
  }

  void _applyChatDetails(ChatDetails chat, {bool fromInitialCache = false}) {
    if (!fromInitialCache) {
      ChatInstantCache.instance.putChatDetails(chat);
    }
    _seededFromChatDetails = true;
    _channelName = chat.name;
    _channelAvatar = chat.avatarUrl;
    _channelDescription = chat.description;
    _subscriberCount = chat.effectiveMemberCount;
    _isVerified = chat.isVerified;
    _showAuthorProfiles = chat.showAuthorProfiles;
    _signMessages = chat.signMessages;
    _linkedChatId = chat.linkedChatId;
    _linkedChat = chat.linkedChat;
    _reactionSettings = chat.reactionSettings;
    _hasActiveCall = chat.hasActiveCall;
    _hasProtectedContent = chat.hasProtectedContent;
    unawaited(
      ScreenProtectionService.instance.sync(
        'channel_${widget.channelId}',
        _hasProtectedContent,
      ),
    );
    _isMuted = NotificationSettingsProvider().isChatMuted(
      widget.channelId,
      chatType: 'channel',
    );
    _participants = chat.participants;
    if (chat.pinnedMessage != null) {
      _pinnedMessage = chat.pinnedMessage;
      _pinnedMessages = [chat.pinnedMessage!];
    }

    _isMember = chat.isMember;
    final resolvedRole = (chat.myRole != null && chat.myRole!.isNotEmpty)
        ? chat.myRole!
        : (_isMember
            ? (chat.participants
                    .where((p) => p.id == _currentUserId)
                    .map((p) => p.role)
                    .firstOrNull ??
                'subscriber')
            : 'guest');
    _myRole = _isMember ? resolvedRole : 'guest';

    final isOwner = _myRole == 'owner' ||
        chat.participants
            .any((p) => p.id == _currentUserId && p.role == 'owner');
    final isAdminRole = isOwner ||
        _myRole == 'admin' ||
        chat.participants.any((p) =>
            p.id == _currentUserId && (p.role == 'owner' || p.role == 'admin'));
    _isAdmin = _isMember && isAdminRole;
    _canPostInChannel = _isMember && chat.canPostInChannel;
    _canEditMessages = isOwner ||
        (_isAdmin && (chat.myAdminPermissions?.canEditMessages ?? false));
    _canDeleteMessages = isOwner ||
        (_isAdmin && (chat.myAdminPermissions?.canDeleteMessages ?? true));
    _canPinMessages = isOwner ||
        (_isAdmin && (chat.myAdminPermissions?.canPinMessages ?? true));
    if (!_canPostInChannel) {
      _isSilentBroadcast = false;
      if (!fromInitialCache && !_isEditing && !_userEditedComposer) {
        _pendingDraftReplyId = null;
        if (_messageController.text.isNotEmpty || _replyToMessage != null) {
          _suppressDraftSave = true;
          try {
            _messageController.clear();
            _replyToMessage = null;
            _isQuote = false;
            _quoteText = null;
            _quoteOffset = 0;
            _quoteLength = 0;
          } finally {
            _suppressDraftSave = false;
          }
        }
        DraftService().cancelPendingPublish(_draftKey);
      }
    } else if (_savedSilentBroadcastPref != null) {
      _isSilentBroadcast = _savedSilentBroadcastPref!;
    }
  }

  String get _silentBroadcastPrefKey =>
      'channel_silent_broadcast_${widget.channelId}';

  Future<void> _loadSilentBroadcastPreference() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getBool(_silentBroadcastPrefKey);
      if (saved == null || !mounted) return;
      _savedSilentBroadcastPref = saved;
      if (_canPostInChannel && _isSilentBroadcast != saved) {
        setState(() => _isSilentBroadcast = saved);
      }
    } catch (_) {}
  }

  Future<void> _setSilentBroadcast(bool silent) async {
    _savedSilentBroadcastPref = silent;
    if (mounted) {
      setState(() => _isSilentBroadcast = silent);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_silentBroadcastPrefKey, silent);
    } catch (_) {}
  }

  void _enqueuePostViews(Iterable<String> messageIds) {
    bool added = false;
    for (final rawId in messageIds) {
      final id = rawId.trim();
      if (id.isEmpty ||
          int.tryParse(id) == null ||
          _viewedPostIdsThisSession.contains(id) ||
          _pendingViewIds.contains(id)) {
        continue;
      }
      _pendingViewIds.add(id);
      added = true;
    }
    if (!added) return;
    _viewsFlushTimer?.cancel();
    _viewsFlushTimer = Timer(const Duration(milliseconds: 1500), () {
      unawaited(_flushPendingViews());
    });
  }

  Message _feedItemPrimaryMessage(FeedItem item) {
    return item is FeedAlbumItem
        ? item.album.primaryMessage
        : (item as FeedSingleItem).message;
  }

  Future<void> _flushPendingViews() async {
    if (_pendingViewIds.isEmpty) return;
    final batch = _pendingViewIds.toList(growable: false);
    _pendingViewIds.clear();
    _viewedPostIdsThisSession.addAll(batch);
    try {
      await ChatService.recordMessageViews(
        chatId: widget.channelId,
        messageIds: batch,
      );
    } catch (e) {
      debugPrint('ChannelScreen: recordMessageViews error: $e');
    }
  }

  void _applyViewsMap(
    Map<String, int> viewsById, {
    Map<String, int> forwardsById = const {},
  }) {
    if (viewsById.isEmpty && forwardsById.isEmpty) return;
    bool changed = false;
    if (mounted) {
      setState(() {
        for (int i = 0; i < _messages.length; i++) {
          final id = _messages[i].id;
          final nextViews = viewsById[id];
          final nextForwards = forwardsById[id];
          final viewsChanged =
              nextViews != null && nextViews != _messages[i].viewsCount;
          final forwardsChanged =
              nextForwards != null && nextForwards != _messages[i].forwardsCount;
          if (viewsChanged || forwardsChanged) {
            _messages[i] = _messages[i].copyWith(
              viewsCount: nextViews ?? _messages[i].viewsCount,
              forwardsCount: nextForwards ?? _messages[i].forwardsCount,
            );
            changed = true;
          }
        }
        for (int i = 0; i < _detachedLatestBackup.length; i++) {
          final id = _detachedLatestBackup[i].id;
          final nextViews = viewsById[id];
          final nextForwards = forwardsById[id];
          if ((nextViews != null &&
                  nextViews != _detachedLatestBackup[i].viewsCount) ||
              (nextForwards != null &&
                  nextForwards != _detachedLatestBackup[i].forwardsCount)) {
            _detachedLatestBackup[i] = _detachedLatestBackup[i].copyWith(
              viewsCount: nextViews ?? _detachedLatestBackup[i].viewsCount,
              forwardsCount:
                  nextForwards ?? _detachedLatestBackup[i].forwardsCount,
            );
          }
        }
        if (changed) {
          _updateFeedItems();
        }
      });
    }
    try {
      if (viewsById.isNotEmpty) {
        AppDatabase().updateMessagesViews(viewsById);
      }
      if (forwardsById.isNotEmpty) {
        AppDatabase().updateMessagesForwards(forwardsById);
      }
    } catch (_) {}
  }

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

  // Draft lifecycle state
  String get _draftKey => widget.channelId;
  bool _suppressDraftSave = false;
  bool _userEditedComposer = false;
  String? _pendingDraftReplyId;
  StreamSubscription<({String chatId, ChatDraft? draft})>? _draftRemoteSub;
  ({
    String text,
    List<MessageEntity> entities,
    Message? replyTo,
    bool isQuote,
    String? quoteText,
    int quoteOffset,
    int quoteLength,
  })? _stashedDraftBeforeEdit;

  // File upload & voice/video note recording state
  final FileService _fileService = FileService();
  final ImagePicker _imagePicker = ImagePicker();
  final List<File> _attachedFiles = [];
  final List<String> _attachedFileNames = [];
  LinkPreviewOptions? _linkPreviewOptions;
  bool _invertMedia = false;
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
  StreamSubscription<ChatRealtimeUpdate>? _realtimeUpdateSub;
  UnreadCountProvider? _unreadCountProvider;
  String? _registeredTileId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUserId = AccountManager().currentAccount?.userId;
    _highlightMessageId = widget.highlightMessageId;
    final instant = ChatInstantCache.instance.getSync(widget.channelId);
    final chanSnap = ProfileInstantCache.instance.getGroupSnapshotSync(widget.channelId);

    _isMuted = NotificationSettingsProvider().isChatMuted(
          widget.channelId,
          chatType: 'channel',
        ) ||
        ProfileInstantCache.instance.isChatMutedSync(widget.channelId);
    unawaited(_loadSilentBroadcastPreference());
    _keyboardHeight =
        instant?.keyboardHeight ?? ChatInstantCache.instance.globalKeyboardHeight;
    if (instant?.inputHeight != null) {
      _inputHeight = instant!.inputHeight!;
    }
    if (instant?.chatDetails != null) {
      _applyChatDetails(instant!.chatDetails!, fromInitialCache: true);
    }
    if ((widget.channelName != null && widget.channelName!.isNotEmpty) ||
        _channelName.isEmpty) {
      _channelName = (widget.channelName != null && widget.channelName!.isNotEmpty)
          ? widget.channelName!
          : (instant?.chat?.name ?? _channelName);
    }
    _channelAvatar =
        widget.channelAvatar ?? instant?.chat?.avatarUrl ?? _channelAvatar;
    if (_subscriberCount == 0) {
      _subscriberCount =
          instant?.subscriberCount ?? instant?.memberCount ?? chanSnap?.memberCount ?? 0;
    }
    _isVerified = instant?.isVerified ?? instant?.chat?.isVerified ?? _isVerified;
    _linkedChat ??= instant?.linkedChat;
    _linkedChatId ??= instant?.linkedChat?.id ?? instant?.chat?.linkedChatId;
    if (!_seededFromChatDetails) {
      final cachedRole = instant?.myRole ?? instant?.chat?.myRole;
      if (cachedRole != null && cachedRole.isNotEmpty) {
        _myRole = cachedRole;
        _isMember = instant?.isMember ?? instant?.chat?.isMember ?? (cachedRole != 'guest');
        _isAdmin = _isMember && (cachedRole == 'owner' || cachedRole == 'admin');
        _canPostInChannel = _isAdmin;
      } else if (instant?.isMember != null) {
        _isMember = instant!.isMember!;
      }
      _hasProtectedContent =
          instant?.hasProtectedContent ?? instant?.chat?.hasProtectedContent ?? _hasProtectedContent;
    }
    final instantPinned = instant?.effectivePinnedMessage;
    if (_pinnedMessage == null && instantPinned != null) {
      _pinnedMessage = instantPinned;
      _pinnedMessages = instant?.pinnedMessages ?? [instantPinned];
    }

    if (instant != null && instant.hasMessages) {
      _messages.addAll(instant.messages!);
      _syncReactionCacheFromMessages(_messages);
      _isLoading = false;
      _hasMoreMessages = _messages.length >= 35;
      _updateFeedItems();
    } else {
      unawaited(_loadMessages());
    }

    _emojiPanelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _emojiPanelAnimation = CurvedAnimation(
      parent: _emojiPanelController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    _initWebSocket();
    _entrySettleTimer = Timer(const Duration(milliseconds: 320), () {
      if (!mounted) return;
      ProfileInstantCache.instance.prefetchGroupOrChannel(widget.channelId);
      unawaited(_loadData());
      unawaited(_loadCachedKeyboardHeight());
      unawaited(_loadInlineDirectoryBots());
    });
    _inputFocusNode.addListener(_onFocusChanged);
    _stickerInputTarget = ChatStickerInputTarget(
      chatId: widget.channelId,
      chatTitle: widget.channelName,
      avatarUrl: widget.channelAvatar,
      controller: _messageController,
      onBackspace: _handleBackspace,
      onInsertEmoji: _insertEmojiText,
      onInsertCustomEmoji: _insertCustomEmojiItem,
      onSendSticker: _sendStickerMessage,
      onSendGif: _sendGifMessage,
    );
    StickerService.instance.registerInputTarget(_stickerInputTarget);
    _lastActiveTileId = TilingLayoutController.instance.activeTileId;
    TilingLayoutController.instance.addListener(_onTilingLayoutChanged);
    ContactsService.revisionNotifier.addListener(_onContactsRevisionChanged);
    if (_isDesktopPlatform) {
      HardwareKeyboard.instance.addHandler(_handleGlobalDesktopKeyEvent);
    }

    // Restore draft if exists
    final draft = DraftService().getDraft(_draftKey);
    if (draft != null &&
        draft.isNotEmpty &&
        (_canPostInChannel || !_seededFromChatDetails)) {
      _suppressDraftSave = true;
      _messageController.loadMessage(draft.text, draft.entities);
      _suppressDraftSave = false;
      if (_replyToMessage == null &&
          draft.replyToMessageId != null &&
          draft.replyToMessageId!.isNotEmpty) {
        _pendingDraftReplyId = draft.replyToMessageId;
      }
      if (draft.quoteText != null && draft.quoteText!.isNotEmpty) {
        _isQuote = draft.isQuote;
        _quoteText = draft.quoteText;
        _quoteOffset = draft.quoteOffset;
        _quoteLength = draft.quoteLength;
      }
      _resolvePendingDraftReply();
    }
    _draftRemoteSub = DraftService().remoteUpdatesStream.listen((event) {
      if (event.chatId == _draftKey) {
        _applyRemoteDraft(event.draft);
      }
    });
    _messageController.addListener(_onInputTextChanged);
    DeepLinkService.pendingInlinePrefill.addListener(
      _onPendingInlinePrefillChanged,
    );
    final pendingPrefill =
        DeepLinkService.consumeInlinePrefill(widget.channelId);
    final initialInlineText =
        (pendingPrefill != null && pendingPrefill.isNotEmpty)
            ? pendingPrefill
            : (draft != null &&
                    BotService.parseInlineBotInput(draft.text) != null
                ? draft.text
                : null);
    if (initialInlineText != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        _insertInlineQueryText(initialInlineText);
      });
    }

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
      if (!_isDetachedHistoryWindow && offset < 50 && _messages.isNotEmpty) {
        final firstMsgId = _messages.first.id;
        final key = _feedItems.isNotEmpty
            ? _messageKeys[_feedItemKeyId(_feedItems.first)]
            : _messageKeys[firstMsgId];
        final renderBox = key?.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox != null && renderBox.hasSize && renderBox.size.height > 20.0) {
          _newestMessageHeight = renderBox.size.height;
        }
        if (_unreadCount > 0 && _isMember) {
          _markMessagesAsRead();
        }
      }
      final double threshold = _newestMessageHeight;

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

      if ((offset - _lastStickyDateEvalOffset).abs() >= 48.0) {
        _lastStickyDateEvalOffset = offset;
        _scheduleStickyDateUpdate();
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
      if (_isDesktopPlatform && (_canPostInChannel || _isAdmin) && _isMyTileActive()) {
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
      ChatInstantCache.instance.setKeyboardHeight(cached, chatId: widget.channelId);
      if (mounted && (cached - _keyboardHeight).abs() > 0.5) {
        setState(() => _keyboardHeight = cached);
      }
    }
  }

  Future<void> _saveKeyboardHeight(double height) async {
    ChatInstantCache.instance.setKeyboardHeight(height, chatId: widget.channelId);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('cached_keyboard_height', height);
  }

  void _onFocusChanged() {
    if (_inputFocusNode.hasFocus) {
      StickerService.instance.registerInputTarget(_stickerInputTarget);
    }
    if (_inputFocusNode.hasFocus && _showEmojiPanel && !_isMobilePlatform) {
      _closeEmojiPanel();
    } else if (!_inputFocusNode.hasFocus &&
        !_showEmojiPanel &&
        !_isEditing &&
        _canPostInChannel) {
      DraftService().flushDraft(_draftKey);
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

  void _enterEditMode(Message message) {
    if (!_isEditing) {
      _stashedDraftBeforeEdit = (
        text: _messageController.cleanText,
        entities: List<MessageEntity>.from(_messageController.entities),
        replyTo: _replyToMessage,
        isQuote: _isQuote,
        quoteText: _quoteText,
        quoteOffset: _quoteOffset,
        quoteLength: _quoteLength,
      );
    }
    _suppressDraftSave = true;
    try {
      setState(() {
        _isEditing = true;
        _editingMessageId = message.id;
        _replyToMessage = null;
        _pendingDraftReplyId = null;
        _isQuote = false;
        _quoteText = null;
        _quoteOffset = 0;
        _quoteLength = 0;
        _messageController.loadMessage(message.content, message.entities);
        _messageController.selection = TextSelection.fromPosition(
          TextPosition(offset: _messageController.text.length),
        );
      });
    } finally {
      _suppressDraftSave = false;
    }
    _focusInputField();
  }

  void _editLastOwnMessage() {
    if (!_isAdmin && !_canPostInChannel) return;
    for (final msg in _messages) {
      if (_canEditChannelPost(msg) &&
          msg.messageType == 'text' &&
          !msg.isRound &&
          msg.content.trim().isNotEmpty) {
        _enterEditMode(msg);
        return;
      }
    }
  }

  void _onEmojiToggle() {
    StickerService.instance.registerInputTarget(_stickerInputTarget);
    if (TilingLayoutController.instance.isWorkspaceMounted &&
        !TilingLayoutController.instance.isSinglePane) {
      if (_registeredTileId != null) {
        TilingLayoutController.instance.setFocusedTile(_registeredTileId!);
      }
      TilingLayoutController.instance.toggleEmojiSidecar();
      return;
    }

    _transitionTimer?.cancel();
    final kbOpen = MediaQuery.viewInsetsOf(context).bottom > 0;

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
          if (!_inputFocusNode.hasFocus) {
            _inputFocusNode.requestFocus();
          }
          if (_isMobilePlatform) {
            SystemChannels.textInput.invokeMethod('TextInput.hide');
          }
        });
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
        if (_isMobilePlatform) {
          SystemChannels.textInput.invokeMethod('TextInput.hide');
        }
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !_showEmojiPanel || _isKeyboardRising) return;
          if (!_inputFocusNode.hasFocus) {
            _inputFocusNode.requestFocus();
          }
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

  void _insertEmojiText(String emoji) {
    final text = _messageController.text;
    final selection = _messageController.selection;
    int start = selection.start;
    int end = selection.end;
    if (start < 0 || end < 0 || start > text.length) {
      start = text.length;
      end = text.length;
    }
    final newText = text.replaceRange(start, end, emoji);
    _messageController.value = TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(offset: start + emoji.length),
    );
    if (!_inputFocusNode.hasFocus) {
      _inputFocusNode.requestFocus();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_inputFocusNode.hasFocus) {
        _inputFocusNode.requestFocus();
      }
    });
  }

  void _insertCustomEmojiItem(StickerItem item) {
    _messageController.insertCustomEmoji(item);
    if (!_inputFocusNode.hasFocus) {
      _inputFocusNode.requestFocus();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_inputFocusNode.hasFocus) {
        _inputFocusNode.requestFocus();
      }
    });
  }

  Future<void> _sendStickerMessage(StickerItem item) async {
    final replyTo = _replyToMessage;
    _cancelReply();
    final fallback = item.emojis.isNotEmpty ? item.emojis.first : '😀';
    final localId = 'local_sticker_${DateTime.now().microsecondsSinceEpoch}';
    final payload = <String, dynamic>{
      'url': item.fileUrl,
      if (item.thumbnailUrl.isNotEmpty) 'thumbnail_url': item.thumbnailUrl,
      'width': item.width,
      'height': item.height,
      'format': item.format,
      'sticker_id': item.id,
      'pack_id': item.packId,
      if (item.effectAnimationUrl.isNotEmpty)
        'effect_animation_url': item.effectAnimationUrl,
    };
    try {
      final res = await ChatService.sendMessage(
        chatId: widget.channelId,
        content: fallback,
        messageType: 'sticker',
        fileUrl: item.fileUrl,
        fileName: 'sticker.${item.format}',
        mediaPayload: payload,
        replyToMessageId: replyTo?.id,
        localId: localId,
        isSilent: _isSilentBroadcast,
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
          _scrollToBottom();
        }
        await AppDatabase()
            .saveMessage(sent.toCompanion(fallbackChatId: widget.channelId));
      } else if (res['message'] != null && mounted) {
        GlassToastService().show(context, res['message'].toString());
      }
    } catch (e) {
      debugPrint('Error sending sticker in channel: $e');
    }
  }

  Future<void> _sendGifMessage(GifItemModel gif) async {
    final replyTo = _replyToMessage;
    _cancelReply();
    final localId = 'local_gif_${DateTime.now().microsecondsSinceEpoch}';
    final payload = <String, dynamic>{
      'url': gif.url,
      'preview_url': gif.previewUrl,
      'width': gif.width,
      'height': gif.height,
      'gif_id': gif.id,
    };
    try {
      final res = await ChatService.sendMessage(
        chatId: widget.channelId,
        content: 'GIF',
        messageType: 'gif',
        fileUrl: gif.url,
        fileName: 'animation.gif',
        mediaPayload: payload,
        replyToMessageId: replyTo?.id,
        localId: localId,
        isSilent: _isSilentBroadcast,
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
          _scrollToBottom();
        }
        await AppDatabase()
            .saveMessage(sent.toCompanion(fallbackChatId: widget.channelId));
      } else if (res['message'] != null && mounted) {
        GlassToastService().show(context, res['message'].toString());
      }
    } catch (e) {
      debugPrint('Error sending gif in channel: $e');
    }
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
    if (ModalRoute.of(context)?.isCurrent == false) return false;
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
      onReactionUpdated: _onMessageReactionUpdated,
      onUnreadCountUpdated: _onUnreadCountUpdated,
      onMessagePinned: _onMessagePinned,
      onMessageUnpinned: _onMessageUnpinned,
      onScheduledMessagesUpdated: (_) => unawaited(_loadScheduledCount()),
      onUserAppearanceUpdated: _onUserAppearanceUpdated,
      onMessageViewsUpdated: (e) => _handleMessageViewsUpdatedData(e.data),
      onPostCommentsUpdated: (e) => _handlePostCommentsUpdatedData(e.data),
      onChatSettingsUpdated: (e) => _handleChatSettingsUpdatedData(e.data),
      onMemberUpdated: _onMemberUpdated,
      onChatDeleted: _onChatDeleted,
      onReconnect: _triggerSilentSync,
    );

    _realtimeUpdateSub?.cancel();
    _realtimeUpdateSub = ChatService.realtimeUpdates
        .where((u) => u.chatId == widget.channelId)
        .listen((update) {
      if (!mounted) return;
      switch (update.type) {
        case WebSocketEventType.messageViewsUpdated:
          _handleMessageViewsUpdatedData(update.data);
          break;
        case WebSocketEventType.postCommentsUpdated:
          _handlePostCommentsUpdatedData(update.data);
          break;
        case WebSocketEventType.chatSettingsUpdated:
          _handleChatSettingsUpdatedData(update.data);
          break;
        default:
          break;
      }
    });
  }

  void _handleMessageViewsUpdatedData(Map<String, dynamic> data) {
    final viewsById = <String, int>{};
    final forwardsById = <String, int>{};
    final rawViews = data['views'];
    if (rawViews is List) {
      for (final item in rawViews) {
        if (item is Map) {
          final id = (item['message_id'] ?? item['id'] ?? '').toString().trim();
          final rawCount = item['views_count'] ?? item['count'];
          final count = rawCount is num
              ? rawCount.toInt()
              : int.tryParse(rawCount?.toString() ?? '');
          if (id.isNotEmpty && count != null && count >= 0) {
            viewsById[id] = count;
          }
          if (id.isNotEmpty && item.containsKey('forwards_count')) {
            final rawFwd = item['forwards_count'];
            final fwd = rawFwd is num
                ? rawFwd.toInt()
                : int.tryParse(rawFwd?.toString() ?? '');
            if (fwd != null && fwd >= 0) {
              forwardsById[id] = fwd;
            }
          }
        }
      }
    } else if (data['message_id'] != null) {
      final id = data['message_id'].toString().trim();
      final rawCount = data['views_count'];
      final count = rawCount is num
          ? rawCount.toInt()
          : int.tryParse(rawCount?.toString() ?? '');
      if (id.isNotEmpty && count != null && count >= 0) {
        viewsById[id] = count;
      }
      if (id.isNotEmpty && data.containsKey('forwards_count')) {
        final rawFwd = data['forwards_count'];
        final fwd = rawFwd is num
            ? rawFwd.toInt()
            : int.tryParse(rawFwd?.toString() ?? '');
        if (fwd != null && fwd >= 0) {
          forwardsById[id] = fwd;
        }
      }
    }
    if (viewsById.isNotEmpty || forwardsById.isNotEmpty) {
      _applyViewsMap(viewsById, forwardsById: forwardsById);
    }
  }

  void _handlePostCommentsUpdatedData(Map<String, dynamic> data) {
    final targetIds = <String>{};
    final primaryId = (data['message_id'] ??
            data['post_message_id'] ??
            data['channel_post_id'] ??
            '')
        .toString()
        .trim();
    if (primaryId.isNotEmpty) targetIds.add(primaryId);
    if (data['message_ids'] is List) {
      for (final item in data['message_ids'] as List) {
        final id = item?.toString().trim() ?? '';
        if (id.isNotEmpty) targetIds.add(id);
      }
    }
    if (targetIds.isEmpty) return;

    final rawCount = data['comments_count'];
    final commentsCount = rawCount is num
        ? rawCount.toInt()
        : int.tryParse(rawCount?.toString() ?? '');
    final hasRepliers = data.containsKey('recent_repliers');
    final parsedRepliers =
        hasRepliers ? RecentReplier.parseList(data['recent_repliers']) : null;

    if (mounted) {
      bool changed = false;
      setState(() {
        for (int i = 0; i < _messages.length; i++) {
          if (targetIds.contains(_messages[i].id)) {
            _messages[i] = _messages[i].copyWith(
              commentsCount: commentsCount ?? _messages[i].commentsCount,
              recentRepliers: parsedRepliers ?? _messages[i].recentRepliers,
            );
            changed = true;
          }
        }
        for (int i = 0; i < _detachedLatestBackup.length; i++) {
          if (targetIds.contains(_detachedLatestBackup[i].id)) {
            _detachedLatestBackup[i] = _detachedLatestBackup[i].copyWith(
              commentsCount:
                  commentsCount ?? _detachedLatestBackup[i].commentsCount,
              recentRepliers:
                  parsedRepliers ?? _detachedLatestBackup[i].recentRepliers,
            );
          }
        }
        if (changed) {
          _updateFeedItems();
        }
      });
    }

    for (final id in targetIds) {
      try {
        AppDatabase().updatePostCommentsMeta(
          messageId: id,
          commentsCount: commentsCount,
          recentRepliersJson:
              hasRepliers ? jsonEncode(data['recent_repliers']) : null,
        );
      } catch (_) {}
    }
  }

  void _handleChatSettingsUpdatedData(Map<String, dynamic> data) {
    if (!mounted) return;
    setState(() {
      if (data.containsKey('name')) {
        final nextName = data['name']?.toString().trim() ?? '';
        if (nextName.isNotEmpty) _channelName = nextName;
      }
      if (data.containsKey('avatar_url')) {
        final rawAvatar = data['avatar_url']?.toString().trim();
        _channelAvatar =
            (rawAvatar != null && rawAvatar.isNotEmpty) ? rawAvatar : null;
      }
      if (data.containsKey('description')) {
        final rawDesc = data['description']?.toString().trim();
        _channelDescription =
            (rawDesc != null && rawDesc.isNotEmpty) ? rawDesc : null;
      }
      if (data.containsKey('sign_messages')) {
        final val = data['sign_messages'];
        _signMessages = val == true || val == 1 || val == 'true';
      }
      if (data.containsKey('show_author_profiles')) {
        final val = data['show_author_profiles'];
        _showAuthorProfiles = val == true || val == 1 || val == 'true';
      }
      if (data['linked_chat'] is Map) {
        final summary = LinkedChatSummary.fromJson(
          Map<String, dynamic>.from(data['linked_chat'] as Map),
        );
        if (summary.id.isNotEmpty) {
          _linkedChat = summary;
          _linkedChatId = summary.id;
        }
      } else if (data.containsKey('linked_chat_id')) {
        final rawLinked = data['linked_chat_id']?.toString().trim() ?? '';
        if (rawLinked.isEmpty || rawLinked == '0' || rawLinked == 'null') {
          _linkedChatId = null;
          _linkedChat = null;
        } else {
          _linkedChatId = rawLinked;
        }
      }
      if (data.containsKey('reaction_settings') ||
          data.containsKey('reaction_mode') ||
          data.containsKey('allowed_reactions')) {
        final nextReactions = ReactionSettings.fromChatJson(data);
        if (nextReactions != null) {
          _reactionSettings = nextReactions;
        }
      }
      if (data.containsKey('has_active_call')) {
        final val = data['has_active_call'];
        _hasActiveCall = val == true || val == 1 || val == 'true';
      }
      if (data.containsKey('has_protected_content')) {
        final val = data['has_protected_content'];
        _hasProtectedContent = val == true || val == 1 || val == 'true';
        unawaited(
          ScreenProtectionService.instance.sync(
            'channel_${widget.channelId}',
            _hasProtectedContent,
          ),
        );
      }
      if (data.containsKey('subscriber_count') ||
          data.containsKey('member_count')) {
        final rawCnt = data['subscriber_count'] ?? data['member_count'];
        final parsed = rawCnt is num
            ? rawCnt.toInt()
            : int.tryParse(rawCnt?.toString() ?? '');
        if (parsed != null && parsed >= 0) {
          _subscriberCount = parsed;
        }
      }
    });
    unawaited(_refreshChannelDetails());
  }

  void _onMemberUpdated(WebSocketEvent event) {
    final targetUserId = (event.data['user_id'] ?? '').toString().trim();
    final action = (event.data['action'] ?? '').toString().trim();
    if (_currentUserId != null &&
        targetUserId == _currentUserId &&
        (action == 'removed' || action == 'banned' || action == 'left')) {
      if (mounted) {
        GlassToastService().show(context, 'Вы больше не участник этого канала');
        Navigator.of(context).maybePop();
      }
      return;
    }
    unawaited(_refreshChannelDetails());
  }

  void _onChatDeleted(WebSocketEvent event) {
    if (!mounted) return;
    GlassToastService().show(context, 'Канал был удалён');
    Navigator.of(context).maybePop();
  }

  void _onUnreadCountUpdated(WebSocketEvent event) {
    if (!mounted) return;
    final rawCount = event.data['unread_count'];
    final nextCount = rawCount is num
        ? rawCount.toInt()
        : int.tryParse(rawCount?.toString() ?? '');
    if (nextCount != null && nextCount >= 0 && nextCount != _unreadCount) {
      setState(() => _unreadCount = nextCount);
    }
  }

  void _onMessageReactionUpdated(WebSocketEvent event) {
    final messageId = event.data['message_id']?.toString();
    if (messageId == null) return;

    final userId = event.data['user_id']?.toString();
    final emoji = event.data['emoji']?.toString();
    final action = event.data['action']?.toString();
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
    } else if (event.data['reactions'] is Map) {
      (event.data['reactions'] as Map).forEach((k, v) {
        final cnt = v is num ? v.toInt() : int.tryParse(v.toString()) ?? 0;
        if (cnt > 0) reactionsMap[k.toString()] = cnt;
      });
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
      } catch (_) {}
    }
  }

  void _toggleReaction(String messageId, String emoji) {
    if (_reactionSettings != null && !_reactionSettings!.isReactionAllowed(emoji)) {
      if (mounted) {
        GlassToastService().show(context, 'Эта реакция отключена в канале');
      }
      return;
    }

    final previousMyReactions = Set<String>.from(_myReactions[messageId] ?? {});
    final previousReactions =
        Map<String, int>.from(_messageReactions[messageId] ?? {});

    setState(() {
      final mySet = _myReactions.putIfAbsent(messageId, () => <String>{});
      final reactions =
          _messageReactions.putIfAbsent(messageId, () => <String, int>{});

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
    } catch (_) {}

    unawaited(_sendReactionToggle(
        messageId, emoji, previousMyReactions, previousReactions));
  }

  Future<void> _sendReactionToggle(
    String messageId,
    String emoji,
    Set<String> previousMyReactions,
    Map<String, int> previousReactions,
  ) async {
    try {
      final res = await ChatService.toggleReaction(
        chatId: widget.channelId,
        messageId: messageId,
        emoji: emoji,
      );
      if (res['success'] != true) {
        _rollbackReaction(messageId, previousMyReactions, previousReactions);
        if (res['message'] != null && mounted) {
          GlassToastService().show(context, res['message'].toString());
        }
      }
    } catch (_) {
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
          reactions: Map.from(previousReactions),
          myReactions: Set.from(previousMyReactions),
        );
        _updateFeedItems();
      }
    });
  }

  Future<void> _loadPinnedMessagesList() async {
    try {
      final list = await ChatService.getPinnedMessages(chatId: widget.channelId);
      if (!mounted) return;
      ChatInstantCache.instance.putPinnedMessages(widget.channelId, list);
      final nextIndex =
          list.isNotEmpty ? _currentPinnedIndex.clamp(0, list.length - 1) : 0;
      final nextPinned = list.isNotEmpty ? list[nextIndex] : null;
      if (_pinnedMessages.length == list.length &&
          _pinnedMessage?.id == nextPinned?.id &&
          _currentPinnedIndex == nextIndex) {
        return;
      }
      setState(() {
        _pinnedMessages = list;
        if (list.isNotEmpty) {
          _currentPinnedIndex = nextIndex;
          _pinnedMessage = nextPinned;
        } else {
          _pinnedMessage = null;
          _currentPinnedIndex = 0;
        }
      });
    } catch (_) {}
  }

  Future<void> _loadScheduledCount() async {
    if (!_canPostInChannel) return;
    try {
      final items = await ChatService.getScheduledMessages(widget.channelId);
      if (mounted && _scheduledCount != items.length) {
        setState(() => _scheduledCount = items.length);
      }
    } catch (_) {}
  }

  void _onMessagePinned(WebSocketEvent event) {
    if (!mounted) return;
    final msgRaw = event.data['message'] ?? event.data['pinned_message'];
    final msgId = event.data['message_id']?.toString() ??
        event.data['pinned_message_id']?.toString();
    setState(() {
      Message? parsed;
      if (msgRaw is Map<String, dynamic>) {
        parsed = Message.fromJson(msgRaw);
      } else if (msgId != null && msgId.isNotEmpty) {
        final found = _messages.where((m) => m.id == msgId);
        if (found.isNotEmpty) parsed = found.first;
      }
      if (parsed != null) {
        _pinnedMessages.removeWhere((m) => m.id == parsed!.id);
        _pinnedMessages.insert(0, parsed);
        _currentPinnedIndex = 0;
        _pinnedMessage = parsed;
      }
    });
    unawaited(_loadPinnedMessagesList());
  }

  void _onMessageUnpinned(WebSocketEvent event) {
    if (!mounted) return;
    final msgId = event.data['message_id']?.toString() ??
        event.data['pinned_message_id']?.toString();
    setState(() {
      if (msgId != null && msgId.isNotEmpty) {
        _pinnedMessages.removeWhere((m) => m.id == msgId);
        if (_pinnedMessages.isEmpty) {
          _pinnedMessage = null;
          _currentPinnedIndex = 0;
        } else {
          _currentPinnedIndex = _currentPinnedIndex.clamp(0, _pinnedMessages.length - 1);
          _pinnedMessage = _pinnedMessages[_currentPinnedIndex];
        }
      } else {
        _pinnedMessages.clear();
        _pinnedMessage = null;
        _currentPinnedIndex = 0;
      }
    });
    unawaited(_loadPinnedMessagesList());
  }

  void _onUserAppearanceUpdated(WebSocketEvent event) {
    final userId = event.data['user_id']?.toString();
    if (userId == null || userId.isEmpty || !mounted) return;
    PeerCustomizationCache.instance.mergeFromJson(userId, event.data);
    final updatedCust = PeerCustomizationCache.instance.getSync(userId);
    final nameColorPresetId = event.data['name_color_preset_id']?.toString();
    final replyStripStyle = event.data['reply_strip_style']?.toString();

    setState(() {
      for (int i = 0; i < _messages.length; i++) {
        final m = _messages[i];
        bool changed = false;
        String? newSenderColor = m.senderNameColorId;
        String? newSenderStrip = m.senderReplyStripStyle;
        PeerCustomization? newSenderCust = m.senderCustomization;
        ReplyInfo? newReplyInfo = m.replyInfo;

        if (m.senderId == userId) {
          if (nameColorPresetId != null) newSenderColor = nameColorPresetId;
          if (replyStripStyle != null) newSenderStrip = replyStripStyle;
          if (updatedCust != null) newSenderCust = updatedCust;
          changed = true;
        }
        if (m.replyInfo != null && m.replyInfo!.senderId == userId) {
          newReplyInfo = m.replyInfo!.copyWith(
            nameColorPresetId:
                nameColorPresetId ?? m.replyInfo!.nameColorPresetId,
            replyStripStyle: replyStripStyle ?? m.replyInfo!.replyStripStyle,
            replyEmoji: updatedCust?.replyEmoji,
            clearReplyEmoji: updatedCust != null && updatedCust.replyEmoji == null,
          );
          changed = true;
        }
        if (changed) {
          _messages[i] = m.copyWith(
            senderNameColorId: newSenderColor,
            senderReplyStripStyle: newSenderStrip,
            senderCustomization: newSenderCust,
            replyInfo: newReplyInfo,
          );
        }
      }
    });
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
      final result =
          await ChatService.getMessages(chatId: widget.channelId, limit: 50);
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
            _syncReactionCacheFromMessages(serverMessages);
            _updateFeedItems();
          });
        }
        _resolvePendingDraftReply(serverLoaded: true);

        try {
          db.saveMessages(
              serverMessages.map((m) => _messageToCompanion(m)).toList());
        } catch (e) {
          debugPrint('Drift saveMessages in channel sync error: $e');
        }

        // Refresh channel info / subscriber count
        try {
          final chatResult = await ChatService.getChat(widget.channelId);
          if (chatResult['success'] == true && mounted) {
            final chat = chatResult['chat'] as ChatDetails;
            setState(() => _applyChatDetails(chat));
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
    final rawIds = event.data['message_ids'];
    final deletedIds = <String>{
      if (event.data['message_id'] != null) event.data['message_id'].toString(),
      if (rawIds is List) ...rawIds.map((e) => e.toString()),
    };
    if (deletedIds.isEmpty) return;

    if (mounted) {
      final bool replyDeleted =
          _replyToMessage != null && deletedIds.contains(_replyToMessage!.id);
      if (_stashedDraftBeforeEdit?.replyTo != null &&
          deletedIds.contains(_stashedDraftBeforeEdit!.replyTo!.id)) {
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
        _messages.removeWhere((m) => deletedIds.contains(m.id));
        _detachedLatestBackup.removeWhere((m) => deletedIds.contains(m.id));
        for (final id in deletedIds) {
          _messageReactions.remove(id);
          _myReactions.remove(id);
          _selectedMessageIds.remove(id);
        }
        if (replyDeleted) {
          _replyToMessage = null;
          _pendingDraftReplyId = null;
          _isQuote = false;
          _quoteText = null;
          _quoteOffset = 0;
          _quoteLength = 0;
        }
        _updateFeedItems();
      });
      if (replyDeleted) {
        _saveCurrentDraft();
      }
    }

    try {
      AppDatabase().deleteMessagesBatch(deletedIds.toList());
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
    final dynamic replyMarkup = event.data['reply_markup'];

    List<MessageEntity>? parsedEntities;
    if (event.data['entities'] is List) {
      parsedEntities = (event.data['entities'] as List)
          .whereType<Map>()
          .map((e) => MessageEntity.fromJson(Map<String, dynamic>.from(e)))
          .toList();
    }

    final isPollEvent = event.data['message_type'] == 'poll' ||
        event.data['poll'] is Map ||
        (newMediaPayload != null &&
            (newMediaPayload.containsKey('poll_id') ||
                newMediaPayload.containsKey('options')));
    if (newContent == null &&
        newMediaPayload == null &&
        parsedEntities == null &&
        replyMarkup == null) {
      return;
    }

    String? effectiveContent = newContent;
    Map<String, dynamic>? mergedPayloadForDb = newMediaPayload != null
        ? ChatService.mergeIncomingMediaPayload(
            null,
            newMediaPayload,
            replyMarkup: replyMarkup,
          )
        : (replyMarkup != null
            ? ChatService.mergeIncomingMediaPayload(
                null,
                null,
                replyMarkup: replyMarkup,
              )
            : null);
    bool effectiveIsEdited = event.data.containsKey('is_edited')
        ? event.data['is_edited'] == true
        : !isPollEvent;

    if (mounted) {
      setState(() {
        final index = _messages.indexWhere((m) => m.id == messageId);
        if (index != -1) {
          final current = _messages[index];
          effectiveContent ??= current.content;
          final isPollMsg = current.messageType == 'poll' || isPollEvent;
          final mergedMedia = ChatService.mergeIncomingMediaPayload(
            current.mediaPayload,
            newMediaPayload,
            replyMarkup: replyMarkup,
          );
          mergedPayloadForDb = mergedMedia;
          final bool nextIsEdited = event.data.containsKey('is_edited')
              ? (event.data['is_edited'] == true ? true : current.isEdited)
              : (isPollMsg ? current.isEdited : true);
          effectiveIsEdited = nextIsEdited;
          _messages[index] = current.copyWith(
            content: effectiveContent,
            entities: parsedEntities ?? current.entities,
            mediaPayload: mergedMedia,
            isEdited: nextIsEdited,
          );
          _updateFeedItems();
        }
      });
    }

    try {
      AppDatabase().updateMessageContent(
        messageId,
        effectiveContent ?? '',
        parsedEntities != null
            ? jsonEncode(parsedEntities.map((e) => e.toJson()).toList())
            : null,
        mergedPayloadForDb != null ? jsonEncode(mergedPayloadForDb) : null,
        effectiveIsEdited,
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
      if (mounted) {
        setState(() {
          final existing = _messages[existingIndex];
          _messages[existingIndex] = message.copyWith(
            localId: existing.localId ?? message.localId,
            sendStatus: 1,
            replyInfo: message.replyInfo ?? existing.replyInfo,
            isQuote: message.isQuote || existing.isQuote,
            quoteText: message.quoteText ?? existing.quoteText,
            quoteOffset:
                message.quoteOffset != 0 ? message.quoteOffset : existing.quoteOffset,
            quoteLength:
                message.quoteLength != 0 ? message.quoteLength : existing.quoteLength,
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
      final isNearBottom = !_isDetachedHistoryWindow &&
          (!_scrollController.hasClients || _scrollController.offset < 120);
      final isIncoming =
          message.senderId != _currentUserId && _currentUserId != null;

      if (_isDetachedHistoryWindow) {
        if (!_detachedLatestBackup.any((m) => m.id == message.id)) {
          _detachedLatestBackup.insert(0, message);
        }
        if (isIncoming) {
          setState(() => _unreadCount++);
        }
      } else {
        setState(() {
          _messages.insert(0, message);
          _syncReactionCacheFromMessages([message]);
          if (isIncoming && !isNearBottom) {
            _unreadCount++;
            if (_firstUnreadMessageId == null) {
              _firstUnreadMessageId = message.id;
              _showUnreadDivider = true;
            }
          }
          _updateFeedItems();
        });
      }
      if (isIncoming && isNearBottom && _isMember) {
        unawaited(_markMessagesAsRead());
      }
    }
  }

  Future<void> _markMessagesAsRead() async {
    if (!_isMember) return;
    final result = await ChatService.markMessagesAsRead(
      chatId: widget.channelId,
      chatTitle: widget.channelName,
    );
    final markedCount = result['marked_count'] as int? ?? 0;
    _wsService.sendMessageRead(widget.channelId, markedCount: markedCount);
    if (mounted && _unreadCount != 0) {
      setState(() => _unreadCount = 0);
    }
    if (result['success'] == true || markedCount > 0) {
      try {
        _unreadCountProvider?.clear(widget.channelId);
      } catch (_) {}
    }
  }

  Future<void> _refreshChannelDetails() async {
    if (mounted) {
      final syncedMuted = NotificationSettingsProvider().isChatMuted(
        widget.channelId,
        chatType: 'channel',
      );
      if (_isMuted != syncedMuted) {
        setState(() => _isMuted = syncedMuted);
      }
    }
    try {
      final chatResult = await ChatService.getChat(widget.channelId);
      if (chatResult['success'] == true && mounted) {
        final chat = chatResult['chat'] as ChatDetails;
        setState(() => _applyChatDetails(chat));
      }
    } catch (_) {}
  }

  Future<void> _loadData() async {
    // Load cached channel flags from Drift if not already seeded with full ChatDetails
    if (!_seededFromChatDetails) {
      try {
        final db = AppDatabase();
        await db.ensureInitialized();
        final cachedChat = await (db.select(db.chats)
              ..where((t) => t.chatId.equals(widget.channelId)))
            .getSingleOrNull();
        if (cachedChat != null && mounted && !_seededFromChatDetails) {
          final cachedReactions =
              ReactionSettings.tryParse(cachedChat.reactionSettingsJson);
          final nextRole =
              (cachedChat.myRole != null && cachedChat.myRole!.isNotEmpty)
                  ? cachedChat.myRole!
                  : _myRole;
          final nextMember =
              (cachedChat.myRole != null && cachedChat.myRole!.isNotEmpty)
                  ? nextRole != 'guest'
                  : _isMember;
          final nextAdmin =
              (cachedChat.myRole != null && cachedChat.myRole!.isNotEmpty)
                  ? (nextRole == 'owner' || nextRole == 'admin')
                  : _isAdmin;
          final bool changed =
              (cachedChat.name.isNotEmpty && cachedChat.name != _channelName) ||
                  (cachedChat.avatarUrl != null &&
                      cachedChat.avatarUrl!.isNotEmpty &&
                      cachedChat.avatarUrl != _channelAvatar) ||
                  cachedChat.showAuthorProfiles != _showAuthorProfiles ||
                  cachedChat.signMessages != _signMessages ||
                  cachedChat.linkedChatId != _linkedChatId ||
                  cachedChat.hasActiveCall != _hasActiveCall ||
                  nextRole != _myRole ||
                  nextMember != _isMember ||
                  nextAdmin != _isAdmin;
          if (changed) {
            setState(() {
              if (cachedChat.name.isNotEmpty) _channelName = cachedChat.name;
              if (cachedChat.avatarUrl != null &&
                  cachedChat.avatarUrl!.isNotEmpty) {
                _channelAvatar = cachedChat.avatarUrl;
              }
              _showAuthorProfiles = cachedChat.showAuthorProfiles;
              _signMessages = cachedChat.signMessages;
              _linkedChatId = cachedChat.linkedChatId;
              _hasActiveCall = cachedChat.hasActiveCall;
              if (cachedChat.myRole != null && cachedChat.myRole!.isNotEmpty) {
                _myRole = nextRole;
                _isMember = nextMember;
                _isAdmin = nextAdmin;
                _canPostInChannel = nextAdmin;
              }
              if (cachedReactions != null) {
                _reactionSettings = cachedReactions;
              }
            });
          }
        }
      } catch (_) {}
    }

    // Get current user ID before applying chat permissions
    final userId = await AuthService.getUserId();
    if (mounted && userId != _currentUserId) {
      setState(() => _currentUserId = userId);
    }

    // Start loading local Drift messages + channel details in parallel
    final loadMessagesFuture = _loadMessages();

    final chatResult = await ChatService.getChat(widget.channelId);
    if (chatResult['success'] == true && mounted) {
      final chat = chatResult['chat'] as ChatDetails;
      setState(() => _applyChatDetails(chat));
      if (chat.pinnedMessage != null ||
          chat.pinnedMessageId != null ||
          chat.pinnedMessageIds.isNotEmpty) {
        unawaited(_loadPinnedMessagesList());
      }
      unawaited(_loadScheduledCount());
      if ((_canPostInChannel || _isAdmin) && _isDesktopPlatform) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _isMyTileActive()) {
            _inputFocusNode.requestFocus();
          }
        });
      }
    }

    await loadMessagesFuture;

    if (!mounted) return;

    if (_isMember) {
      if (_highlightMessageId == null) {
        try {
          final unreadInfo =
              await ChatService.getUnreadInfo(chatId: widget.channelId);
          if (unreadInfo['success'] == true && mounted) {
            final unreadCount = (unreadInfo['unread_count'] as int?) ?? 0;
            final firstUnreadId =
                unreadInfo['first_unread_message_id']?.toString();
            if (unreadCount > 0 &&
                firstUnreadId != null &&
                firstUnreadId.isNotEmpty) {
              setState(() {
                _unreadCount = unreadCount;
                _firstUnreadMessageId = firstUnreadId;
                _showUnreadDivider = true;
                _updateFeedItems();
              });
              _scrollToFirstUnread();
              return;
            }
          }
        } catch (_) {}
      }
      await _markMessagesAsRead();
    }
  }

  Future<void> _loadMessages() async {
    final bool hadInitialMessages = _messages.isNotEmpty;
    if (_messages.isEmpty && !_isLoading) {
      setState(() => _isLoading = true);
    }

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

      final parsedLocal =
          fixedMessages.map((m) => Message.fromDbMessage(m)).toList();
      _sortMessagesDescending(parsedLocal);
      ChatInstantCache.instance.putMessages(widget.channelId, parsedLocal);

      if (_isLoading || !ChatInstantCache.messagesEqual(_messages, parsedLocal)) {
        setState(() {
          _isLoading = false;
          _messages.clear();
          _messages.addAll(parsedLocal);
          _syncReactionCacheFromMessages(_messages);
          _hasMoreMessages = localMessages.length >= 50;
          _updateFeedItems();
        });
      }
      _resolvePendingDraftReply();

      if (_highlightMessageId != null && !_hasScrolledToHighlight) {
        _scrollToMessage(_highlightMessageId!);
        _hasScrolledToHighlight = true;
      }
    }

    try {
      final result =
          await ChatService.getMessages(chatId: widget.channelId, limit: 50);

      if (mounted) {
        if (result['success'] == true) {
          final serverMessages = result['messages'] as List<Message>;
          final nextHasMore =
              result['has_more'] as bool? ?? (serverMessages.length >= 50);

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
                quoteOffset:
                    m.quoteOffset != 0 ? m.quoteOffset : existing.quoteOffset,
                quoteLength:
                    m.quoteLength != 0 ? m.quoteLength : existing.quoteLength,
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

          final mergedList = mergedById.values.toList();
          _sortMessagesDescending(mergedList);
          ChatInstantCache.instance.putMessages(widget.channelId, mergedList);

          final bool needsUiUpdate = _isLoading ||
              _hasMoreMessages != nextHasMore ||
              !ChatInstantCache.messagesEqual(_messages, mergedList);

          if (needsUiUpdate) {
            setState(() {
              _isLoading = false;
              _hasMoreMessages = nextHasMore;
              _messages.clear();
              _messages.addAll(mergedList);
              _syncReactionCacheFromMessages(serverMessages);
              _updateFeedItems();
            });
          }
          _resolvePendingDraftReply(serverLoaded: true);

          try {
            db.saveMessages(
                serverMessages.map((m) => _messageToCompanion(m)).toList());
          } catch (e) {
            debugPrint('Channel: Drift saveMessages error: $e');
          }
        } else if (_isLoading) {
          setState(() => _isLoading = false);
        }

        if (_highlightMessageId != null && !_hasScrolledToHighlight) {
          _scrollToMessage(_highlightMessageId!);
          _hasScrolledToHighlight = true;
        } else if (!hadInitialMessages &&
            localMessages.isEmpty &&
            !_showUnreadDivider) {
          _scrollToBottom();
        }
      }
    } catch (e) {
      debugPrint('Channel: Error loading from server: $e');
      if (mounted && _isLoading) {
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
      _hasMoreMessages =
          result['has_more'] as bool? ?? (newMessages.length >= 50);

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
        _syncReactionCacheFromMessages(newMessages);
        _updateFeedItems();
        _isLoadingMore = false;
      });
      return;
    }

    try {
      final localMessages = await db.getMessages(
        widget.channelId,
        beforeCreatedAt: lastMessage?.createdAt,
        limit: 50,
      );

      if (localMessages.isNotEmpty && mounted) {
        setState(() {
          for (final m in localMessages.map((m) => Message.fromDbMessage(m))) {
            if (!_messages.any((existing) =>
                existing.id == m.id ||
                (m.localId != null && existing.localId == m.localId))) {
              _messages.add(m);
            }
          }
          _sortMessagesDescending(_messages);
          _syncReactionCacheFromMessages(_messages);
          _updateFeedItems();
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

  /// Конвертация Message → MessagesCompanion для Drift (включая поля каналов)
  MessagesCompanion _messageToCompanion(Message msg) =>
      msg.toCompanion(fallbackChatId: widget.channelId);

  void _sortMessagesDescending(List<Message> list) {
    list.sort((a, b) {
      final cmp = b.createdAtEpochMs.compareTo(a.createdAtEpochMs);
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
      _updateFeedItems();
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
              _syncReactionCacheFromMessages(bridged);
              _updateFeedItems();
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
          _syncReactionCacheFromMessages(fetched);
          _updateFeedItems();
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
    for (int i = 0; i < _feedItems.length; i++) {
      final item = _feedItems[i];
      final keyId = item is FeedAlbumItem
          ? item.album.primaryMessage.id
          : (item as FeedSingleItem).message.id;
      final key = _messageKeys[keyId];
      final box = key?.currentContext?.findRenderObject() as RenderBox?;
      if (box != null && box.attached && box.hasSize) {
        anchorMsgId = keyId;
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
          _syncReactionCacheFromMessages(newerMessages);
          _updateFeedItems();
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

  int _findFeedIndexForMessageId(String messageId) {
    return _feedItems.indexWhere((item) =>
        item.id == messageId ||
        (item is FeedAlbumItem &&
            item.album.items.any((ai) => ai.id == messageId)));
  }

  String _feedItemKeyId(FeedItem item) {
    return item is FeedAlbumItem
        ? item.album.primaryMessage.id
        : (item as FeedSingleItem).message.id;
  }

  /// Scroll to a specific message and highlight it using RenderObject-guided seek
  Future<void> _scrollToMessage(String messageId) async {
    if (!mounted) return;

    if (_isDetachedHistoryWindow &&
        !_messages.any((m) => m.id == messageId) &&
        _detachedLatestBackup.any((m) => m.id == messageId)) {
      await _restoreLatestMessagesTail();
    }

    int feedIndex = _findFeedIndexForMessageId(messageId);
    if (feedIndex == -1) {
      await _fetchMessagesAround(messageId);
      if (!mounted) return;
      feedIndex = _findFeedIndexForMessageId(messageId);
      int loadRetries = 0;
      while (feedIndex == -1 && _hasMoreMessages && loadRetries < 3 && mounted) {
        await _loadMoreMessages();
        loadRetries++;
        feedIndex = _findFeedIndexForMessageId(messageId);
      }
      if (feedIndex == -1) return;
    }

    _isProgrammaticJump = true;
    try {
      final reached = await ChatScrollNavigator.scrollToTarget(
        scrollController: _scrollController,
        targetIndex: feedIndex,
        itemCount: _feedItems.length,
        isMounted: () => mounted,
        keyForIndex: (i) => _messageKeys[_feedItemKeyId(_feedItems[i])],
        resolveTargetKey: () {
          final idx = _findFeedIndexForMessageId(messageId);
          if (idx != -1) {
            return _messageKeys[_feedItemKeyId(_feedItems[idx])];
          }
          return _messageKeys[messageId];
        },
        alignment: 0.5,
      );
      if (reached && mounted) {
        _setHighlight(messageId);
      }
    } finally {
      _isProgrammaticJump = false;
      _scheduleStickyDateUpdate();
    }
  }

  Future<void> _scrollToFirstUnread() async {
    final targetId = _firstUnreadMessageId;
    if (targetId == null || targetId.isEmpty || !mounted) return;

    int feedIndex = _findFeedIndexForMessageId(targetId);
    if (feedIndex == -1) {
      await _fetchMessagesAround(targetId);
      if (!mounted) return;
      feedIndex = _findFeedIndexForMessageId(targetId);
    }
    if (feedIndex == -1) return;

    _isProgrammaticJump = true;
    try {
      await ChatScrollNavigator.scrollToTarget(
        scrollController: _scrollController,
        targetIndex: feedIndex,
        itemCount: _feedItems.length,
        isMounted: () => mounted,
        keyForIndex: (i) => _messageKeys[_feedItemKeyId(_feedItems[i])],
        resolveTargetKey: () {
          final idx = _findFeedIndexForMessageId(targetId);
          if (idx != -1) {
            return _messageKeys[_feedItemKeyId(_feedItems[idx])];
          }
          return _messageKeys[targetId];
        },
        alignment: 0.72,
      );
    } finally {
      _isProgrammaticJump = false;
      _scheduleStickyDateUpdate();
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

  void _updateFloatingDateOnScroll() {
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      _scheduleStickyDateUpdate();
      return;
    }

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

    int? minActiveIdx;
    int? maxActiveIdx;
    bool activeRangeComputed = false;
    void ensureActiveRange() {
      if (activeRangeComputed) return;
      activeRangeComputed = true;
      for (int i = 0; i < _feedItems.length; i++) {
        final key = _messageKeys[_feedItemKeyId(_feedItems[i])];
        final box = key?.currentContext?.findRenderObject() as RenderBox?;
        if (isChatRenderBoxActivelyLaidOut(box)) {
          minActiveIdx ??= i;
          maxActiveIdx = i;
        }
      }
    }

    int? activeSpanIdx;
    for (int s = 0; s < _daySpans.length; s++) {
      final span = _daySpans[s];
      final sepKey = _dateSeparatorKeyForFeedIndex(span.day, span.oldestIdx);
      final sepBox = sepKey.currentContext?.findRenderObject() as RenderBox?;

      bool isAtOrAboveSticky;
      if (isChatRenderBoxActivelyLaidOut(sepBox)) {
        final sepTopY = sepBox!.localToGlobal(Offset.zero).dy;
        isAtOrAboveSticky = sepTopY <= stickyTopY + 0.5;
      } else {
        final oldestItemKey =
            _messageKeys[_feedItemKeyId(_feedItems[span.oldestIdx])];
        final oldestItemBox =
            oldestItemKey?.currentContext?.findRenderObject() as RenderBox?;
        if (isChatRenderBoxActivelyLaidOut(oldestItemBox)) {
          final itemTopY = oldestItemBox!.localToGlobal(Offset.zero).dy;
          isAtOrAboveSticky = itemTopY <= stickyTopY + 0.5;
        } else {
          ensureActiveRange();
          if (maxActiveIdx != null && minActiveIdx != null) {
            if (span.oldestIdx > maxActiveIdx!) {
              isAtOrAboveSticky = true;
            } else if (span.oldestIdx < minActiveIdx!) {
              isAtOrAboveSticky = false;
            } else {
              isAtOrAboveSticky = false;
              for (int i = span.oldestIdx; i >= minActiveIdx!; i--) {
                final k = _messageKeys[_feedItemKeyId(_feedItems[i])];
                final b = k?.currentContext?.findRenderObject() as RenderBox?;
                if (isChatRenderBoxActivelyLaidOut(b)) {
                  isAtOrAboveSticky =
                      b!.localToGlobal(Offset.zero).dy <= stickyTopY + 0.5;
                  break;
                }
              }
            }
          } else {
            isAtOrAboveSticky = false;
          }
        }
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
      sameDaySepKey:
          _dateSeparatorKeyForFeedIndex(activeSpan.day, activeSpan.oldestIdx),
      nextDaySepKey: nextNewerSpan != null
          ? _dateSeparatorKeyForFeedIndex(
              nextNewerSpan.day,
              nextNewerSpan.oldestIdx,
            )
          : null,
      hasOlderDay: effectiveSpanIdx < _daySpans.length - 1,
    );

    if (_stickyDateStateNotifier.value != nextState) {
      _stickyDateStateNotifier.value = nextState;
    }
  }

  Future<void> _openCalendarForDate(DateTime initialDate) async {
    _dismissKeyboardAndEmoji();
    final selectedDay = await ChatHistoryCalendar.show(
      context: context,
      chatId: widget.channelId,
      initialDate: initialDate,
      currentMessages: _messages,
    );
    if (selectedDay == null ||
        selectedDay.firstMessageId.isEmpty ||
        !mounted) {
      return;
    }
    await _jumpToCalendarDay(selectedDay);
  }

  Future<void> _jumpToCalendarDay(ChatCalendarDayInfo dayInfo) async {
    if (_feedItems.isNotEmpty) {
      String fromId = _feedItemKeyId(_feedItems.first);
      for (int i = 0; i < _feedItems.length; i++) {
        final keyId = _feedItemKeyId(_feedItems[i]);
        final box = _messageKeys[keyId]?.currentContext?.findRenderObject()
            as RenderBox?;
        if (box != null && box.attached && box.hasSize) {
          fromId = keyId;
          break;
        }
      }
      if (_jumpHistory.isEmpty || _jumpHistory.last != fromId) {
        _jumpHistory.add(fromId);
        if (mounted) setState(() => _showScrollDownFab = true);
      }
    }
    await _scrollToMessage(dayInfo.firstMessageId);
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
        GlassToastService().show(
          context,
          result['message'] ?? 'У вас нет доступа к этому сообщению',
          isError: true,
        );
      }
    }
  }

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
        clean.endsWith('.gif') ||
        clean.endsWith('.bmp') ||
        clean.endsWith('.heic');
  }

  bool _isAudioFile(String filePath) {
    final clean = filePath.split('?').first.toLowerCase();
    return clean.endsWith('.mp3') ||
        clean.endsWith('.m4a') ||
        clean.endsWith('.wav') ||
        clean.endsWith('.ogg') ||
        clean.endsWith('.aac') ||
        clean.endsWith('.flac');
  }

  String _detectMessageType(String fileName) {
    if (_isImageFile(fileName)) return 'image';
    if (_isVideoFile(fileName)) return 'video';
    if (_isAudioFile(fileName)) return 'audio';
    return 'document';
  }

  Future<void> _sendMessage({
    String? cleanText,
    List<MessageEntity>? entities,
    LinkPreviewOptions? linkPreviewOptions,
    bool invertMedia = false,
    bool isSilent = false,
    bool hasMediaSpoiler = false,
    bool asDocument = false,
    bool preserveComposerDraft = false,
  }) async {
    final String controllerCleanText = _messageController.cleanText.trimRight();
    final List<MessageEntity> controllerEntities = _messageController.entities;
    final String text = (cleanText ?? controllerCleanText).trimRight();
    final List<MessageEntity> resolvedEntities = entities ?? controllerEntities;
    if ((text.trim().isEmpty &&
            _attachedFiles.isEmpty &&
            _stagedForward == null) ||
        _isSending ||
        _isUploading) {
      return;
    }
    final bool effectiveSilent = isSilent || _isSilentBroadcast;

    if (!_isEditing && _stagedForward != null && _canPostInChannel) {
      final staged = _stagedForward!;
      setState(() => _stagedForward = null);
      final fwdRes = await ChatService.forwardMessages(
        toChatId: widget.channelId,
        fromChatId: staged.fromChatId,
        messageIds: staged.messages.map((m) => m.id).toList(),
        hideSender: staged.hideSender,
        hideCaption: staged.hideCaption,
        isSilent: effectiveSilent,
      );
      if (fwdRes['success'] == true) {
        _triggerSilentSync();
      } else if (mounted) {
        GlassToastService().showError(
          context,
          fwdRes['message']?.toString() ?? 'Ошибка пересылки',
        );
      }
      if (text.trim().isEmpty && _attachedFiles.isEmpty) {
        return;
      }
    }

    final String effectiveContent = text;
    final List<MessageEntity>? effectiveEntities =
        resolvedEntities.isNotEmpty ? resolvedEntities : null;

    if (_isEditing && _editingMessageId != null) {
      final editingId = _editingMessageId!;
      _cancelEditing();
      setState(() {
        final index = _messages.indexWhere((m) => m.id == editingId);
        if (index != -1) {
          _messages[index] = _messages[index].copyWith(
            content: effectiveContent,
            isEdited: true,
            entities: effectiveEntities ?? const [],
          );
          _updateFeedItems();
        }
      });
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

    final filesToSend = List<File>.from(_attachedFiles);
    final fileNamesToSend = List<String>.from(_attachedFileNames);
    final replyTo = _replyToMessage;
    final replyIsQuote = _isQuote;
    final replyQuoteText = _quoteText;
    final replyQuoteOffset = _quoteOffset;
    final replyQuoteLength = _quoteLength;
    final LinkPreviewOptions? effectiveLinkPreview =
        linkPreviewOptions ?? _linkPreviewOptions;
    final bool effectiveInvert = invertMedia || _invertMedia;

    _suppressDraftSave = true;
    try {
      setState(() {
        _attachedFiles.clear();
        _attachedFileNames.clear();
        _linkPreviewOptions = null;
        _invertMedia = false;
        _replyToMessage = null;
        _pendingDraftReplyId = null;
        _isQuote = false;
        _quoteText = null;
        _quoteOffset = 0;
        _quoteLength = 0;
        if (filesToSend.isEmpty) {
          _isSending = true;
        } else {
          _isUploading = true;
        }
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
    _scrollToBottom();

    // Multi / single file or album publishing path
    if (filesToSend.isNotEmpty) {
      try {
        final uploadedItems = <Map<String, dynamic>>[];
        for (int i = 0; i < filesToSend.length; i++) {
          final file = filesToSend[i];
          final name = i < fileNamesToSend.length
              ? fileNamesToSend[i]
              : p.basename(file.path);
          final msgType = asDocument ? 'file' : _detectMessageType(name);
          final useChunked = msgType == 'video' ||
              (!kIsWeb && await file.length() > 5 * 1024 * 1024);
          final uploadResult = useChunked
              ? await _fileService.uploadFileChunked(
                  file,
                  onProgress: (progress) {
                    if (mounted) {
                      _uploadProgressNotifier.value =
                          (i + progress) / filesToSend.length;
                    }
                  },
                )
              : await _fileService.uploadFile(
                  file,
                  onProgress: (progress) {
                    if (mounted) {
                      _uploadProgressNotifier.value =
                          (i + progress) / filesToSend.length;
                    }
                  },
                );
          if (!kIsWeb && (msgType == 'image' || msgType == 'video')) {
            await MediaCacheManager.instance
                .seedCacheFromFile(uploadResult.url, file);
          }
          uploadedItems.add({
            'message_type': msgType,
            'file_url': uploadResult.url,
            'file_name': uploadResult.fileName,
            'media_payload': uploadResult.toMediaPayload(),
          });
        }

        final isMediaAlbum = uploadedItems.length > 1 &&
            uploadedItems.every((it) =>
                it['message_type'] == 'image' || it['message_type'] == 'video');

        if (isMediaAlbum) {
          for (int offset = 0; offset < uploadedItems.length; offset += 10) {
            final end = math.min(offset + 10, uploadedItems.length);
            final chunk = uploadedItems.sublist(offset, end);
            final albumGroupedId = const Uuid().v4();
            final chunkCaption = offset == 0 ? effectiveContent : '';
            final chunkEntities = offset == 0 ? effectiveEntities : null;

            Map<String, dynamic> res = await ChatService.sendMediaAlbum(
              chatId: widget.channelId,
              items: chunk,
              groupedId: albumGroupedId,
              caption: chunkCaption,
              entities: chunkEntities,
              invertMedia: effectiveInvert,
              replyToMessageId: replyTo?.id,
              isSilent: effectiveSilent,
              hasMediaSpoiler: hasMediaSpoiler,
            );

            if (res['success'] != true && res['retry_after'] == null) {
              final fallbackMsgs = <Message>[];
              for (int idx = 0; idx < chunk.length; idx++) {
                final item = chunk[idx];
                final isLast = idx == chunk.length - 1;
                final singleRes = await ChatService.sendMessage(
                  chatId: widget.channelId,
                  messageType: item['message_type'] ?? 'image',
                  content: isLast ? chunkCaption : '',
                  fileUrl: item['file_url'],
                  fileName: item['file_name'],
                  mediaPayload: item['media_payload'],
                  entities: isLast ? chunkEntities : null,
                  groupedId: albumGroupedId,
                  invertMedia: effectiveInvert,
                  replyToMessageId: replyTo?.id,
                  isSilent: effectiveSilent,
                  hasMediaSpoiler: hasMediaSpoiler,
                );
                if (singleRes['success'] == true &&
                    singleRes['message'] is Message) {
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

            if (res['success'] == true && mounted) {
              final rawMessages = res['messages'] as List<dynamic>? ?? [];
              final newMsgs = <Message>[];
              for (final raw in rawMessages) {
                final msg = raw is Message
                    ? raw
                    : (raw is Map
                        ? Message.fromJson(Map<String, dynamic>.from(raw))
                        : null);
                if (msg != null) newMsgs.add(msg);
              }
              setState(() {
                for (final msg in newMsgs) {
                  final existingIdx = _messages.indexWhere((m) => m.id == msg.id);
                  if (existingIdx != -1) {
                    _messages[existingIdx] = msg;
                  } else {
                    _messages.insert(0, msg);
                  }
                }
                _sortMessagesDescending(_messages);
                _updateFeedItems();
              });
              try {
                await AppDatabase().saveMessages(
                  newMsgs.map((m) => _messageToCompanion(m)).toList(),
                );
              } catch (_) {}
            } else if (res['message'] != null && mounted) {
              GlassToastService().show(context, res['message'].toString());
            }
          }
        } else {
          for (int i = 0; i < uploadedItems.length; i++) {
            final item = uploadedItems[i];
            final isLast = i == uploadedItems.length - 1;
            final res = await ChatService.sendMessage(
              chatId: widget.channelId,
              messageType: item['message_type'] ?? 'document',
              content: isLast ? effectiveContent : '',
              fileUrl: item['file_url'],
              fileName: item['file_name'],
              mediaPayload: item['media_payload'],
              entities: isLast ? effectiveEntities : null,
              linkPreviewOptions: isLast ? effectiveLinkPreview : null,
              invertMedia: effectiveInvert,
              replyToMessageId: replyTo?.id,
              isQuote: replyIsQuote,
              quoteText: replyQuoteText,
              quoteOffset: replyQuoteOffset,
              quoteLength: replyQuoteLength,
              isSilent: effectiveSilent,
              hasMediaSpoiler: hasMediaSpoiler,
            );
            if (res['success'] == true && res['message'] is Message && mounted) {
              final sent = res['message'] as Message;
              setState(() {
                if (!_messages.any((m) => m.id == sent.id)) {
                  _messages.insert(0, sent);
                  _sortMessagesDescending(_messages);
                  _updateFeedItems();
                }
              });
              try {
                await AppDatabase().saveMessage(_messageToCompanion(sent));
              } catch (_) {}
            } else if (res['message'] != null && mounted) {
              GlassToastService().show(context, res['message'].toString());
            }
          }
        }
      } catch (e) {
        debugPrint('Channel file upload/send error: $e');
        if (mounted) {
          GlassToastService().show(
            context,
            context.l10n.translate('chat_upload_error'),
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
      return;
    }

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
        linkPreviewOptions: effectiveLinkPreview,
        invertMedia: effectiveInvert,
        isSilent: effectiveSilent,
      );
    } catch (e) {
      debugPrint('SyncService createPendingMessage error: $e');
    }

    if (pendingMsg != null && mounted) {
      pendingLocalId = pendingMsg.localId;
      var message = Message.fromDbMessage(pendingMsg);
      if (replyTo != null) {
        final channelTitle =
            _channelName.isNotEmpty ? _channelName : widget.channelName;
        message = message.copyWith(
          replyInfo: ReplyInfo(
            messageId: replyTo.id,
            senderId: '0',
            senderName: replyTo.resolveEffectiveAuthorTitle(
              chatName: channelTitle,
              chatType: 'channel',
            ),
            content: replyTo.content,
            messageType: replyTo.messageType,
            entities: replyTo.entities,
            nameColorPresetId: 'name_red',
            replyStripStyle: 'solid',
            replyEmoji: null,
          ),
        );
      }
      if (mounted) {
        setState(() {
          _messages.insert(0, message);
          _isSending = false;
          _updateFeedItems();
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
          linkPreviewOptions: effectiveLinkPreview,
          invertMedia: effectiveInvert,
          isSilent: effectiveSilent,
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
                      sendStatus: 1,
                      replyInfo: sentMessage.replyInfo ?? existing.replyInfo,
                      isQuote:
                          sentMessage.isQuote || existing.isQuote || replyIsQuote,
                      quoteText: sentMessage.quoteText ??
                          existing.quoteText ??
                          replyQuoteText,
                      quoteOffset: sentMessage.quoteOffset != 0
                          ? sentMessage.quoteOffset
                          : (existing.quoteOffset != 0
                              ? existing.quoteOffset
                              : replyQuoteOffset),
                      quoteLength: sentMessage.quoteLength != 0
                          ? sentMessage.quoteLength
                          : (existing.quoteLength != 0
                              ? existing.quoteLength
                              : replyQuoteLength),
                    );
                  } else {
                    _messages[idx] = _messages[idx].copyWith(
                      id: serverId,
                      sendStatus: 1,
                    );
                  }
                  _updateFeedItems();
                }
              });
            }
          }
        } else {
          final errMsg =
              result['message']?.toString() ?? 'Failed to send message';
          debugPrint('ChatService.sendMessage in channel returned false: $errMsg');
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
            GlassToastService().show(context, errMsg);
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
              _messages[idx] = _messages[idx].copyWith(sendStatus: 2);
              _updateFeedItems();
            }
          });
          GlassToastService().show(context, 'Failed to send message: $e');
        }
      }
    } else {
      final result = await ChatService.sendMessage(
        chatId: widget.channelId,
        content: effectiveContent,
        entities: effectiveEntities,
        linkPreviewOptions: effectiveLinkPreview,
        invertMedia: effectiveInvert,
        replyToMessageId: replyTo?.id,
        isQuote: replyIsQuote,
        quoteText: replyQuoteText,
        quoteOffset: replyQuoteOffset,
        quoteLength: replyQuoteLength,
        isSilent: effectiveSilent,
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
          GlassToastService().show(context, result['message'] ?? 'Failed to send message');
        }
      }
    }
  }

  /// Show attachment picker bottom sheet (media/files/polls)
  Future<void> _showAttachmentPicker() async {
    _dismissKeyboardAndEmoji();
    final result =
        await AttachmentPickerBottomSheet.show(context, allowPoll: true);
    if (result == null || !mounted) return;

    if (result.files != null && result.files!.isNotEmpty) {
      if (result.asDocument || result.sendImmediately) {
        setState(() {
          for (final file in result.files!) {
            _attachedFiles.add(file);
            _attachedFileNames.add(p.basename(file.path));
          }
        });
        if (result.sendImmediately) {
          _sendMessage();
        }
      } else {
        await _openMediaSendScreen(result.files!);
      }
      return;
    }

    switch (result.action) {
      case AttachmentPickerAction.camera:
        await _takePhoto();
        break;
      case AttachmentPickerAction.gallery:
        await _pickMedia('media');
        break;
      case AttachmentPickerAction.file:
        await _pickDocument();
        break;
      case AttachmentPickerAction.music:
        await _pickAudio();
        break;
      case AttachmentPickerAction.poll:
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PollCreateScreen(
              chatId: widget.channelId,
              isChannel: true,
              isSilent: _isSilentBroadcast,
            ),
          ),
        );
        break;
      case AttachmentPickerAction.location:
        await _sendLocation();
        break;
      case AttachmentPickerAction.contact:
        await _sendContact();
        break;
      case AttachmentPickerAction.miniApp:
        final shortcut = result.miniAppShortcut;
        if (shortcut != null) {
          final bid = (shortcut['bot_id'] ?? '').toString().trim();
          final buser = (shortcut['bot_username'] ?? '').toString().trim();
          final targetBotId = bid.isNotEmpty ? bid : buser;
          if (targetBotId.isNotEmpty) {
            await openMiniAppSheet(
              context,
              botId: targetBotId,
              botName: shortcut['bot_name']?.toString(),
              botUsername: buser.isNotEmpty ? buser : null,
              isVerified: shortcut['is_verified'] == true,
              url: shortcut['url']?.toString(),
              appShortName: shortcut['app_short_name']?.toString(),
              chatId: widget.channelId,
              mode: (shortcut['mode'] ?? 'attach').toString(),
              buttonText: (shortcut['title'] ?? '').toString(),
              onSwitchInlineQuery: _insertInlineQueryText,
            );
          }
        }
        break;
      case null:
        break;
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
    if (result == null || result.files.isEmpty || !mounted) return;

    if (result.scheduleAt != null) {
      setState(() => _isUploading = true);
      try {
        for (int i = 0; i < result.files.length; i++) {
          final file = result.files[i];
          final uploadResult = await _fileService.uploadFileChunked(file);
          final msgType = result.asDocument
              ? 'file'
              : _detectMessageType(p.basename(file.path));
          final caption = result.captionsByPath[file.path] ??
              (i == 0 ? (result.caption ?? '') : '');
          await ChatService.createScheduledMessage(
            chatId: widget.channelId,
            content: caption,
            messageType: msgType,
            scheduleAt: result.scheduleAt,
            fileUrl: uploadResult.url,
            fileName: uploadResult.fileName,
            hasMediaSpoiler: result.hasMediaSpoiler,
            mediaPayload: uploadResult.toMediaPayload(),
            isSilent: result.isSilent || _isSilentBroadcast,
          );
        }
        unawaited(_loadScheduledCount());
        if (mounted) {
          GlassToastService().show(context, 'Публикация запланирована');
        }
      } finally {
        if (mounted) setState(() => _isUploading = false);
      }
      return;
    }

    setState(() {
      for (final file in result.files) {
        _attachedFiles.add(file);
        _attachedFileNames.add(p.basename(file.path));
      }
    });
    _sendMessage(
      cleanText: result.caption ?? '',
      entities: const [],
      isSilent: result.isSilent,
      hasMediaSpoiler: result.hasMediaSpoiler,
      asDocument: result.asDocument,
      preserveComposerDraft: true,
    );
  }

  Future<void> _pickMedia(String type) async {
    try {
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
      if (pickedMedia.isNotEmpty && mounted) {
        await _openMediaSendScreen(
            pickedMedia.map((x) => File(x.path)).toList());
      }
    } catch (e) {
      if (mounted) {
        GlassToastService().show(context, 'Failed to pick media: $e');
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
      if (photo != null && mounted) {
        await _openMediaSendScreen([File(photo.path)]);
      }
    } catch (e) {
      if (mounted) {
        GlassToastService().show(context, 'Failed to take photo: $e');
      }
    }
  }

  Future<void> _pickDocument() async {
    try {
      final result = await FilePicker.platform.pickFiles(allowMultiple: true);
      if (result != null && result.files.isNotEmpty && mounted) {
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
        GlassToastService().show(context, 'Failed to pick file: $e');
      }
    }
  }

  Future<void> _pickAudio() async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        allowMultiple: true,
      );
      if (result != null && result.files.isNotEmpty && mounted) {
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
        GlassToastService().show(context, 'Failed to pick audio: $e');
      }
    }
  }

  void _openFile(String fileUrl, String fileName, String messageType) {
    final resolved = AppConfig.resolveMediaUrl(fileUrl) ?? fileUrl;
    if (messageType == 'image') {
      FullscreenPhotoViewer.open(context, resolved);
      return;
    }
    showTheavModalSheet<void>(
      context: context,
      title: fileName,
      showCloseButton: true,
      builder: (sheetCtx) => TheavInsetGroup(
        margin: EdgeInsets.zero,
        children: [
          TheavListRow(
            leading: const iconoir.OpenNewWindow(width: 20, height: 20),
            title: context.l10n.translate('chat_open_file'),
            onTap: () {
              Navigator.pop(sheetCtx);
              _downloadAndOpenFile(resolved, fileName);
            },
          ),
          TheavListRow(
            leading: const iconoir.Download(width: 20, height: 20),
            title: context.l10n.translate('chat_download'),
            onTap: () {
              Navigator.pop(sheetCtx);
              _downloadFile(resolved, fileName);
            },
          ),
          TheavListRow(
            leading: const iconoir.ShareAndroid(width: 20, height: 20),
            title: context.l10n.translate('share'),
            onTap: () async {
              Navigator.pop(sheetCtx);
              await SharePlus.instance.share(
                ShareParams(text: resolved, subject: fileName),
              );
            },
          ),
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
        await launchUrl(Uri.parse(fileUrl), webOnlyWindowName: '_blank');
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

  Future<void> _loadInlineDirectoryBots() async {
    final bots = await BotService.getBotsDirectory(inlineOnly: true);
    if (mounted && bots.isNotEmpty) {
      setState(() => _inlineDirectoryBots = bots);
    }
  }

  void _updateMentionAutocompleteState() {
    if (!mounted || !_canPostInChannel) return;
    if (_inlineQueryController.isActive) {
      if (_activeMentionQuery != null) {
        setState(() {
          _activeMentionQuery = null;
          _mentionTokenStart = -1;
          _mentionTokenEnd = -1;
          _mentionIsAtStart = false;
        });
      }
      return;
    }
    final sel = _messageController.selection;
    final cursor =
        sel.isValid ? sel.extentOffset : _messageController.text.length;
    final token =
        BotService.parseActiveMentionToken(_messageController.text, cursor);
    if (token == null) {
      if (_activeMentionQuery != null) {
        setState(() {
          _activeMentionQuery = null;
          _mentionTokenStart = -1;
          _mentionTokenEnd = -1;
          _mentionIsAtStart = false;
        });
      }
      return;
    }
    if (_activeMentionQuery != token.query ||
        _mentionTokenStart != token.start ||
        _mentionTokenEnd != token.end ||
        _mentionIsAtStart != token.isAtMessageStart) {
      setState(() {
        _activeMentionQuery = token.query;
        _mentionTokenStart = token.start;
        _mentionTokenEnd = token.end;
        _mentionIsAtStart = token.isAtMessageStart;
      });
    }
  }

  void _onPendingInlinePrefillChanged() {
    if (!mounted) return;
    final prefill = DeepLinkService.consumeInlinePrefill(widget.channelId);
    if (prefill != null && prefill.isNotEmpty) {
      _insertInlineQueryText(prefill);
    }
  }

  void _insertInlineQueryText(String text) {
    _messageController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _inputFocusNode.requestFocus();
    _inlineQueryController.onTextChanged(
      text,
      chatId: widget.channelId,
      chatType: 'channel',
    );
  }

  Future<void> _handleInlinePopupHeaderButtonTap(
    BuildContext ctx,
    BotInlineResultsButton btn,
  ) async {
    final inlineUsername =
        (_inlineQueryController.activeBotUsername ?? '').trim();
    final respBotId = (_inlineQueryController.response?.botId ?? '').trim();
    BotInfo? botMeta;
    for (final b in _inlineDirectoryBots) {
      if ((respBotId.isNotEmpty && b.userId == respBotId) ||
          (inlineUsername.isNotEmpty &&
              (b.username ?? '').toLowerCase() ==
                  inlineUsername.toLowerCase())) {
        botMeta = b;
        break;
      }
    }
    if (botMeta == null && respBotId.isNotEmpty) {
      botMeta = BotService.getCachedBotInfo(respBotId);
    }
    if (botMeta == null && inlineUsername.isNotEmpty) {
      botMeta = await BotService.resolveBotByUsername(inlineUsername);
    }
    if (!ctx.mounted) return;

    final effectiveBotId = respBotId.isNotEmpty
        ? respBotId
        : (botMeta?.userId.isNotEmpty == true ? botMeta!.userId : inlineUsername);
    final effectiveUsername = (botMeta?.username?.isNotEmpty == true)
        ? botMeta!.username!
        : inlineUsername;

    if (btn.webAppUrl != null && btn.webAppUrl!.isNotEmpty) {
      if (effectiveBotId.isEmpty) return;
      await openMiniAppSheet(
        ctx,
        botId: effectiveBotId,
        botName: botMeta?.displayName,
        botUsername: effectiveUsername.isNotEmpty ? effectiveUsername : null,
        isVerified: botMeta?.isVerified,
        url: btn.webAppUrl,
        chatId: widget.channelId,
        mode: 'inline',
        buttonText: btn.text,
        onSwitchInlineQuery: _insertInlineQueryText,
      );
      return;
    }

    if (btn.startParameter != null) {
      final startCmd = btn.startParameter!.isNotEmpty
          ? '/start ${btn.startParameter}'
          : '/start';
      final targetBotUserId = (botMeta != null && botMeta.userId.isNotEmpty)
          ? botMeta.userId
          : (int.tryParse(respBotId) != null ? respBotId : '');
      if (targetBotUserId.isEmpty) return;

      final res = await ChatService.createChat(
        chatType: 'private',
        participantIds: [targetBotUserId],
      );
      if (!mounted) return;
      if (res['success'] == true) {
        final chat = res['chat'];
        final targetChatId = chat is Chat
            ? chat.id
            : (res['chat_id']?.toString() ?? '');
        if (targetChatId.isNotEmpty) {
          await ChatService.sendMessage(
            chatId: targetChatId,
            content: startCmd,
          );
          _inlineQueryController.clear();
          _messageController.clear();
          if (!mounted) return;
          final botTitle = (botMeta?.displayName.isNotEmpty == true)
              ? botMeta!.displayName
              : (effectiveUsername.isNotEmpty ? '@$effectiveUsername' : 'Бот');
          if (TilingLayoutController.instance.isWorkspaceMounted) {
            TilingLayoutController.instance.openChatInActiveTile(
              chatId: targetChatId,
              chatType: 'private',
              chatName: botTitle,
              avatarUrl: botMeta?.avatarUrl,
              otherUserId: targetBotUserId,
            );
          } else {
            await Navigator.of(context).push(
              SwipeBackPageRoute(
                builder: (_) => PrivateChatScreen(
                  chatId: targetChatId,
                  otherUserId: targetBotUserId,
                  otherUserName: botTitle,
                  otherUserAvatar: botMeta?.avatarUrl,
                ),
              ),
            );
          }
        }
      } else {
        GlassToastService().showError(
          context,
          res['message']?.toString() ?? 'Не удалось открыть чат с ботом',
        );
      }
    }
  }

  void _applyMentionSelection(String username) {
    final text = _messageController.text;
    final cleanUname = username.trim().replaceFirst(RegExp(r'^@+'), '');
    if (cleanUname.isEmpty) return;

    final start = _mentionTokenStart;
    final end = _mentionTokenEnd;
    if (start < 0 || end < start || end > text.length) {
      _insertInlineQueryText('@$cleanUname ');
      return;
    }

    final insertion = '@$cleanUname ';
    final updated = text.replaceRange(start, end, insertion);
    final newCursor = start + insertion.length;
    setState(() {
      _activeMentionQuery = null;
      _mentionTokenStart = -1;
      _mentionTokenEnd = -1;
      _mentionIsAtStart = false;
    });
    _messageController.value = TextEditingValue(
      text: updated,
      selection: TextSelection.collapsed(offset: newCursor),
    );
    _inputFocusNode.requestFocus();
  }

  void _saveCurrentDraft({bool immediate = false}) {
    if (_suppressDraftSave || _isEditing || !_canPostInChannel) return;
    DraftService().saveDraft(
      _draftKey,
      text: _messageController.cleanText,
      entities: _messageController.entities,
      replyToMessageId: _replyToMessage?.id,
      quoteText: _quoteText,
      isQuote: _isQuote,
      quoteOffset: _quoteOffset,
      quoteLength: _quoteLength,
      immediate: immediate,
    );
  }

  void _applyRemoteDraft(ChatDraft? draft) {
    if (!mounted ||
        _isEditing ||
        _inputFocusNode.hasFocus ||
        !_canPostInChannel) {
      return;
    }
    _suppressDraftSave = true;
    try {
      if (draft == null || draft.isEmpty) {
        _messageController.clear();
        setState(() {
          _replyToMessage = null;
          _pendingDraftReplyId = null;
          _isQuote = false;
          _quoteText = null;
          _quoteOffset = 0;
          _quoteLength = 0;
        });
      } else {
        _messageController.loadMessage(draft.text, draft.entities);
        Message? resolvedReply;
        if (draft.replyToMessageId != null &&
            draft.replyToMessageId!.isNotEmpty) {
          for (final m in _messages) {
            if (m.id == draft.replyToMessageId) {
              resolvedReply = m;
              break;
            }
          }
        }
        setState(() {
          _replyToMessage = resolvedReply;
          _pendingDraftReplyId =
              resolvedReply == null ? draft.replyToMessageId : null;
          _isQuote =
              draft.isQuote &&
              draft.quoteText != null &&
              draft.quoteText!.isNotEmpty;
          _quoteText = _isQuote ? draft.quoteText : null;
          _quoteOffset = _isQuote ? draft.quoteOffset : 0;
          _quoteLength = _isQuote ? draft.quoteLength : 0;
        });
      }
    } finally {
      _suppressDraftSave = false;
    }
  }

  void _resolvePendingDraftReply({bool serverLoaded = false}) {
    final pendingId = _pendingDraftReplyId;
    if (pendingId == null || pendingId.isEmpty) return;
    Message? found;
    for (final m in _messages) {
      if (m.id == pendingId) {
        found = m;
        break;
      }
    }
    if (found != null) {
      _pendingDraftReplyId = null;
      if (!_isEditing && _replyToMessage == null && mounted) {
        setState(() => _replyToMessage = found);
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

  void _onInputTextChanged() {
    if (!_suppressDraftSave && !_isEditing) {
      _userEditedComposer = true;
    }
    _saveCurrentDraft();
    if (_canPostInChannel) {
      _inlineQueryController.onTextChanged(
        _messageController.text,
        chatId: widget.channelId,
        chatType: 'channel',
      );
      _updateMentionAutocompleteState();
    }
  }

  void _startReply(Message message) {
    final stashed = _stashedDraftBeforeEdit;
    _stashedDraftBeforeEdit = null;
    _suppressDraftSave = true;
    try {
      setState(() {
        if (_isEditing) {
          _isEditing = false;
          _editingMessageId = null;
          if (stashed != null && stashed.text.isNotEmpty) {
            _messageController.loadMessage(stashed.text, stashed.entities);
          } else {
            _messageController.clear();
          }
        }
        _replyToMessage = message;
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
    _focusInputField();
  }

  void _startQuote(Message message, String selectedText, int offset, int length) {
    final stashed = _stashedDraftBeforeEdit;
    _stashedDraftBeforeEdit = null;
    _suppressDraftSave = true;
    try {
      setState(() {
        if (_isEditing) {
          _isEditing = false;
          _editingMessageId = null;
          if (stashed != null && stashed.text.isNotEmpty) {
            _messageController.loadMessage(stashed.text, stashed.entities);
          } else {
            _messageController.clear();
          }
        }
        _replyToMessage = message;
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
    _messageController.selection = TextSelection.collapsed(
      offset: _messageController.text.length,
    );
    _focusInputField();
  }

  void _cancelReply() {
    setState(() {
      _replyToMessage = null;
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
        _editingMessageId = null;
        if (stashed != null) {
          _messageController.loadMessage(stashed.text, stashed.entities);
          _replyToMessage = stashed.replyTo;
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

  String _formatTime(String timestamp) {
    return DateTimeUtils.formatTimeHHmm(timestamp);
  }

  @override
  void dispose() {
    unawaited(
      ScreenProtectionService.instance.release('channel_${widget.channelId}'),
    );
    WidgetsBinding.instance.removeObserver(this);
    _entrySettleTimer?.cancel();
    _transitionTimer?.cancel();
    _syncDebounceTimer?.cancel();
    _viewsFlushTimer?.cancel();
    unawaited(_flushPendingViews());
    _realtimeUpdateSub?.cancel();

    if (!_isDetachedHistoryWindow && _messages.isNotEmpty) {
      ChatInstantCache.instance.putMessages(widget.channelId, _messages);
    }
    if (!_isEditing && _canPostInChannel) {
      DraftService().flushDraft(_draftKey);
    }
    _draftRemoteSub?.cancel();
    StickerService.instance.unregisterInputTarget(_stickerInputTarget);
    _messageController.removeListener(_onInputTextChanged);
    _inlineQueryController.dispose();
    _emojiPanelController.dispose();
    _inputFocusNode.removeListener(_onFocusChanged);
    _inputFocusNode.dispose();
    _messageController.dispose();
    _scrollController.dispose();
    _stickyDateStateNotifier.dispose();
    _chatSubscription?.cancel();

    TilingLayoutController.instance.removeListener(_onTilingLayoutChanged);
    ContactsService.revisionNotifier.removeListener(_onContactsRevisionChanged);
    DeepLinkService.pendingInlinePrefill.removeListener(
      _onPendingInlinePrefillChanged,
    );
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

  void _onContactsRevisionChanged() {
    if (mounted) setState(() {});
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

        final bool exposeAuthor = _signMessages &&
            _showAuthorProfiles &&
            ContactsService.shouldResolveUserIdentity(
              m.senderId,
              senderChatId: m.senderChatId,
              isAnonymousAdmin: m.isFromAnonymousAdmin,
            );
        final String trackSenderName = exposeAuthor
            ? ContactsService.resolvePeerName(m.senderId, m.senderName)
            : (_channelName.isNotEmpty
                ? _channelName
                : (widget.channelName ?? m.senderName));

        if (m.messageType == 'voice') {
          playlist.add(PlaybackTrack(
            messageId: m.id,
            chatId: widget.channelId,
            chatType: 'channel',
            mediaType: 'voice',
            mediaUrl: resolvedUrl,
            senderId: exposeAuthor ? m.senderId : null,
            senderName: trackSenderName,
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
            senderId: exposeAuthor ? m.senderId : null,
            senderName: trackSenderName,
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
      final RenderBox? renderBox =
          _inputKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize) {
        final newHeight = renderBox.size.height;
        if ((newHeight - _inputHeight).abs() > 0.5 && newHeight > 0) {
          ChatInstantCache.instance.setInputHeight(widget.channelId, newHeight);
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
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

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
            MediaQuery.viewInsetsOf(context).bottom == 0 &&
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

    final safeBottom = MediaQuery.paddingOf(context).bottom;
    final canCompose = _canPostInChannel || _isAdmin;
    final String heroTag = 'chat_avatar_${widget.channelId}';

    return ChatScaffold(
      swipeBackBlocked:
          _isSelectionMode || _isVoiceRecording || _isVideoRecording,
      canPop: !isKeyboardVisible &&
          !_showEmojiPanel &&
          !_isSelectionMode &&
          !_isVoiceRecording &&
          !_isVideoRecording,
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
            _voiceRecorderService.cancelRecording();
            setState(() => _isVoiceRecording = false);
          }
        }
      },
      appBar: FloatingGlassAppBar(
        name: displayName,
        avatarUrl: widget.channelAvatar ?? _channelAvatar,
        isOnline: false, // Channel doesn't have online status
        isVerified: _isVerified,
        statusText: subscriberText,
        isChannel: true, // Calls hidden in channel
        isMuted: _isMuted,
        heroTag: heroTag,
        isSelectionMode: _isSelectionMode,
        selectedCount: _selectedMessageIds.length,
        hasProtectedContent: _hasProtectedContent,
        onCancelSelection: _clearSelection,
        onReplySelected: (_selectedMessageIds.length == 1 && _canPostInChannel)
            ? () {
                final id = _selectedMessageIds.first;
                final msg = _messages.where((m) => m.id == id).firstOrNull;
                _clearSelection();
                if (msg != null) _startReply(msg);
              }
            : null,
        onCopySelected: _copySelectedMessages,
        onPinSelected: (_selectedMessageIds.length == 1 && _canPinMessages)
            ? () {
                final id = _selectedMessageIds.first;
                final msg = _messages.where((m) => m.id == id).firstOrNull;
                _clearSelection();
                if (msg != null) _togglePinMessage(msg);
              }
            : null,
        onForwardSelected: _forwardSelectedMessages,
        onDeleteSelected: _canDeleteSelectedChannelPosts
            ? _deleteSelectedMessages
            : null,
        profileScreenBuilder: (_) => ProfileScreen(
          entityType: ProfileEntityType.channel,
          chatId: widget.channelId,
          initialName: displayName,
          initialAvatarUrl: widget.channelAvatar ?? _channelAvatar,
          heroTag: heroTag,
          onUpdate: _refreshChannelDetails,
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
                heroTag: heroTag,
                onUpdate: _refreshChannelDetails,
                onJumpToMessageId: (msgId) => _scrollToMessage(msgId),
              ),
            ),
          ).then((_) {
            if (!mounted) return;
            setState(() {
              _isMuted = NotificationSettingsProvider().isChatMuted(
                widget.channelId,
                chatType: 'channel',
              );
            });
            unawaited(_refreshChannelDetails());
          });
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
                heroTag: heroTag,
                onUpdate: _refreshChannelDetails,
                onJumpToMessageId: (msgId) => _scrollToMessage(msgId),
              ),
            ),
          ).then((_) {
            if (!mounted) return;
            setState(() {
              _isMuted = NotificationSettingsProvider().isChatMuted(
                widget.channelId,
                chatType: 'channel',
              );
            });
            unawaited(_refreshChannelDetails());
          });
        },
        onSearch: () {
          ChatActionsHelper.openSearch(
            context: context,
            chatId: widget.channelId,
            chatName: displayName,
            onMessageSelected: (msgId) => _scrollToMessage(msgId),
          );
        },
        onToggleMute: () {
          ChatActionsHelper.toggleMute(
            chatId: widget.channelId,
            currentMuted: _isMuted,
            onMuteChanged: (newMuted) => setState(() => _isMuted = newMuted),
          );
        },
        onClearHistory: _isAdmin
            ? () {
                ChatActionsHelper.showClearHistoryDialog(
                  context: context,
                  chatId: widget.channelId,
                  onHistoryCleared: () {
                    if (mounted) {
                      setState(() {
                        _messages.clear();
                        _updateFeedItems();
                      });
                    }
                  },
                );
              }
            : null,
        onReport: () {
          unawaited(
            showAbuseReportSheet(
              context,
              chatId: widget.channelId,
            ),
          );
        },
        extraMenuItems: [
          if (_isAdmin)
            FloatingChatMenuItem(
              label: 'Статистика канала',
              iconBuilder: (c) => iconoir.StatsUpSquare(
                color: c,
                width: 20,
                height: 20,
              ),
              onTap: () {
                Navigator.push(
                  context,
                  SwipeBackPageRoute(
                    builder: (_) => ChannelStatsScreen(
                      chatId: widget.channelId,
                      channelName: displayName,
                    ),
                  ),
                );
              },
            ),
          FloatingChatMenuItem(
            label: 'Похожие каналы',
            iconBuilder: (c) => iconoir.Megaphone(
              color: c,
              width: 20,
              height: 20,
            ),
            onTap: () {
              showSimilarChannelsSheet(
                context: context,
                chatId: widget.channelId,
                onOpenChannel: (ch) {
                  Navigator.push(
                    context,
                    SwipeBackPageRoute(
                      builder: (_) => ChannelScreen(
                        channelId: ch.id,
                        channelName: ch.name,
                        channelAvatar: ch.avatarUrl,
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ],
      ),
      body: AnimatedBuilder(
        animation: _emojiPanelAnimation,
        builder: (context, child) {
          final emojiPanelHeight =
              _emojiPanelAnimation.value * (_keyboardHeight + safeBottom);
          final keyboardOrEmoji = (_isKeyboardFalling || _isKeyboardRising)
              ? (_keyboardHeight + safeBottom)
              : (bottomInset > emojiPanelHeight ? bottomInset : emojiPanelHeight);
          final effectiveBottom = math.max(safeBottom, keyboardOrEmoji);
          final double bannersOffset =
              (_pinnedMessage != null ? 52.0 : 0.0) +
                  (_hasActiveCall ? 60.0 : 0.0);

          final int listItemCount = _isLoading
              ? 0
              : (_feedItems.isEmpty
                  ? 1
                  : _feedItems.length + (!_hasMoreMessages ? 1 : 0));

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
                  isChannel: true,
                  itemCount: listItemCount,
                  scrollController: _scrollController,
                  topPadding: topPadding + bannersOffset,
                  bottomPadding: _inputHeight + effectiveBottom + 8,
                  emptyTitle: 'Нет публикаций',
                  itemBuilder: (context, index) {
                    if (_feedItems.isEmpty ||
                        (!_hasMoreMessages && index == _feedItems.length)) {
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 20),
                        child: Center(
                          child: TelegramChatCreatedIntroCard(
                            isChannel: true,
                            title: displayName,
                            description: _channelDescription,
                          ),
                        ),
                      );
                    }
                    final item = _feedItems[index];
                    final primary = _feedItemPrimaryMessage(item);
                    final isNewPost = index == 0 &&
                        (primary.sendStatus == 0 ||
                            (DateTimeUtils.parseUtcDateTime(item.createdAt)
                                    ?.toLocal()
                                    .isAfter(DateTime.now().subtract(
                                        const Duration(seconds: 2))) ??
                                false));
                    return TelegramMessageEntrance(
                      key: ValueKey(
                          'entrance_${primary.localId ?? item.id}'),
                      animate: isNewPost,
                      isMe: false,
                      child: _buildChannelFeedItem(item, index),
                    );
                  },
                ),
              ),
              Positioned(
                top: topPadding + 4.0,
                left: 0,
                right: 0,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    LiveChatCallBanner(
                      chatId: widget.channelId,
                      chatTitle: displayName,
                      currentUserId: _currentUserId ?? '',
                      isChannel: true,
                    ),
                    PinnedMessageBanner(
                      message: _pinnedMessage,
                      totalPinnedCount: math.max(1, _pinnedMessages.length),
                      currentPinnedIndex: _currentPinnedIndex,
                      canUnpin: _canPinMessages,
                      onTap: () {
                        if (_pinnedMessages.isNotEmpty) {
                          final idx = _currentPinnedIndex.clamp(0, _pinnedMessages.length - 1);
                          final msg = _pinnedMessages[idx];
                          _scrollToMessage(msg.id);
                          if (_pinnedMessages.length > 1) {
                            setState(() {
                              _currentPinnedIndex = (idx + 1) % _pinnedMessages.length;
                              _pinnedMessage = _pinnedMessages[_currentPinnedIndex];
                            });
                          }
                        } else {
                          final msg = _pinnedMessage;
                          if (msg != null) _scrollToMessage(msg.id);
                        }
                      },
                      onOpenPinnedList: () async {
                        final jumpId = await Navigator.of(context).push<String>(
                          SwipeBackPageRoute(
                            builder: (_) => PinnedMessagesScreen(
                              chatId: widget.channelId,
                              chatTitle: displayName,
                              canPinMessages: _canPinMessages,
                              initialPinnedMessages: _pinnedMessages,
                            ),
                          ),
                        );
                        if (!mounted) return;
                        unawaited(_loadPinnedMessagesList());
                        if (jumpId != null && jumpId.isNotEmpty) {
                          _scrollToMessage(jumpId);
                        }
                      },
                      onUnpin: _canPinMessages
                          ? () async {
                              final msg = _pinnedMessage;
                              if (msg == null) return;
                              await _togglePinMessage(msg);
                            }
                          : null,
                    ),
                    MediaNotePlayerHeader(
                      chatId: widget.channelId,
                      onScrollToActive: () {
                        final activeId =
                            VoicePlaybackService().activeMessageId ??
                                VideoNotePlaybackService().activeMessageId;
                        if (activeId != null) {
                          _scrollToMessage(activeId);
                        }
                      },
                    ),
                  ],
                ),
              ),
              Positioned(
                top: topPadding + bannersOffset + 4.0,
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
                        onNeedsSync: _scheduleStickyDateUpdate,
                      );
                    },
                  ),
                ),
              ),
              ChatBottomScrollEdge(
                height: math.max(safeBottom + 52.0, 52.0),
              ),
              Positioned(
                right: 14,
                bottom: _inputHeight + 10 + effectiveBottom,
                child: ScrollDownFab(
                  visible: _showScrollDownFab,
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
                      if (_unreadCount > 0 && _isMember) {
                        unawaited(_markMessagesAsRead());
                      }
                    }
                  },
                ),
              ),
              if (canCompose &&
                  (_emojiPanelAnimation.value > 0 || _showEmojiPanel))
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  height: (_isKeyboardFalling || _isKeyboardRising)
                      ? (_keyboardHeight + safeBottom)
                      : emojiPanelHeight,
                  child: ClipRect(
                    clipBehavior: _emojiPanelAnimation.value < 0.999
                        ? Clip.hardEdge
                        : Clip.none,
                    child: OverflowBox(
                      alignment: Alignment.topCenter,
                      maxHeight: _keyboardHeight + safeBottom,
                      minHeight: _keyboardHeight + safeBottom,
                      child: EmojiStickerPanel(
                        controller: _messageController,
                        focusNode: _inputFocusNode,
                        onEmojiSelected: _insertEmojiText,
                        onBackspace: _handleBackspace,
                        onClose: _closeEmojiPanel,
                        onCustomEmojiSelected: _insertCustomEmojiItem,
                        onStickerSelected: _sendStickerMessage,
                        onGifSelected: _sendGifMessage,
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
                  child: _buildBottomBar(displayName),
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
                      GlassToastService().show(
                        context,
                        context.l10n.translate('chat_voice_too_short'),
                        duration: const Duration(seconds: 2),
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

  ChatParticipant? _findParticipant(String senderId) {
    if (senderId.isEmpty) return null;
    for (final p in _participants) {
      if (p.id == senderId) return p;
    }
    return null;
  }

  void _openAuthorProfile(Message message) {
    final authorId =
        (message.postAuthorId != null && message.postAuthorId!.isNotEmpty)
            ? message.postAuthorId!
            : message.senderId;
    if (authorId.isEmpty || authorId == '0') return;
    HapticUtils.tap();
    final participant = _findParticipant(authorId);
    final isBot = participant?.isBot ?? false;
    final canResolve = ContactsService.shouldResolveUserIdentity(
      authorId,
      senderChatId: message.senderChatId,
      isAnonymousAdmin: message.isFromAnonymousAdmin,
      isBot: isBot,
    );
    final rawName = participant?.displayName.isNotEmpty == true
        ? participant!.displayName
        : (message.senderName.isNotEmpty
            ? message.senderName
            : (_channelName.isNotEmpty ? _channelName : 'Channel'));
    final resolvedName = canResolve
        ? ContactsService.resolvePeerName(
            authorId,
            rawName,
            senderChatId: message.senderChatId,
            isAnonymousAdmin: message.isFromAnonymousAdmin,
            isBot: isBot,
          )
        : rawName;
    final rawAvatar = participant?.avatarUrl ?? message.senderAvatarUrl;
    final resolvedAvatar = canResolve
        ? ContactsService.resolvePeerAvatarUrl(
            authorId,
            rawAvatar,
            senderChatId: message.senderChatId,
            isAnonymousAdmin: message.isFromAnonymousAdmin,
            isBot: isBot,
          )
        : rawAvatar;
    Navigator.push(
      context,
      SwipeBackPageRoute(
        builder: (_) => ProfileScreen(
          entityType: ProfileEntityType.user,
          userId: authorId,
          initialName: resolvedName,
          initialAvatarUrl: resolvedAvatar,
          initialIsOnline: participant?.isOnline,
          initialLastSeen: participant?.lastSeen,
        ),
      ),
    );
  }

  void _openUserProfileById(String userId) {
    if (userId.isEmpty || userId == '0') return;
    HapticUtils.tap();
    final participant = _findParticipant(userId);
    final isBot = participant?.isBot ?? false;
    final canResolve = ContactsService.shouldResolveUserIdentity(
      userId,
      isBot: isBot,
    );
    final rawName = participant?.displayName.isNotEmpty == true
        ? participant!.displayName
        : (_channelName.isNotEmpty ? _channelName : 'User');
    final resolvedName = canResolve
        ? ContactsService.resolvePeerName(userId, rawName, isBot: isBot)
        : rawName;
    final resolvedAvatar = canResolve
        ? ContactsService.resolvePeerAvatarUrl(
            userId,
            participant?.avatarUrl,
            isBot: isBot,
          )
        : participant?.avatarUrl;
    Navigator.push(
      context,
      SwipeBackPageRoute(
        builder: (_) => ProfileScreen(
          entityType: ProfileEntityType.user,
          userId: userId,
          initialName: resolvedName,
          initialAvatarUrl: resolvedAvatar,
          initialIsOnline: participant?.isOnline,
          initialLastSeen: participant?.lastSeen,
        ),
      ),
    );
  }

  void _openPostComments(Message postMessage) {
    _dismissKeyboardAndEmoji();
    HapticUtils.tap();
    Navigator.push(
      context,
      SwipeBackPageRoute(
        builder: (_) => PostCommentsScreen(
          channelId: widget.channelId,
          postMessage: postMessage,
          channelName: _channelName.isNotEmpty
              ? _channelName
              : widget.channelName,
          channelAvatar: widget.channelAvatar ?? _channelAvatar,
          linkedChatId: _linkedChatId,
          showAuthorProfiles: _showAuthorProfiles,
          signMessages: _signMessages,
          reactionSettings: _reactionSettings,
        ),
      ),
    );
  }

  void _toggleFeedSelection(Message primaryMsg, MediaAlbum? album) {
    final ids = album != null
        ? album.items.map((m) => m.id).toList()
        : [primaryMsg.id];
    HapticUtils.selection();
    setState(() {
      final allSelected = ids.every(_selectedMessageIds.contains);
      if (allSelected) {
        _selectedMessageIds.removeAll(ids);
      } else {
        _selectedMessageIds.addAll(ids);
      }
    });
  }

  void _enterFeedSelection(Message primaryMsg, MediaAlbum? album) {
    _dismissKeyboardAndEmoji();
    HapticUtils.selection();
    setState(() {
      if (album != null) {
        _selectedMessageIds.addAll(album.items.map((m) => m.id));
      } else {
        _selectedMessageIds.add(primaryMsg.id);
      }
    });
  }

  Widget _buildChannelFeedItem(FeedItem item, int feedIndex) {
    final MediaAlbum? album = item is FeedAlbumItem ? item.album : null;
    final Message message = _feedItemPrimaryMessage(item);

    final GlobalKey key;
    final hasLocalId = message.localId != null && message.localId!.isNotEmpty;
    if (hasLocalId &&
        message.localId != message.id &&
        _messageKeys.containsKey(message.localId!)) {
      key = _messageKeys.remove(message.localId!)!;
      _messageKeys[message.id] = key;
    } else {
      key = _messageKeys.putIfAbsent(message.id, () => GlobalKey());
    }

    final prevItem =
        feedIndex + 1 < _feedItems.length ? _feedItems[feedIndex + 1] : null;
    final (currentDt, currentDate) = _resolveDates(item.createdAt);
    final prevDate =
        prevItem != null ? _resolveDates(prevItem.createdAt).$2 : null;

    final items = <Widget>[];
    if (currentDate != prevDate) {
      final sepKey = _dateSeparatorKeyFor(currentDate, message);
      items.add(
        RepaintBoundary(
          child: InlineChatDateHeader(
            key: sepKey,
            day: currentDate,
            scrollListenable: _scrollController,
            stickySlotKey: _stickyDateSlotKey,
            stickyStateListenable: _stickyDateStateNotifier,
            onNeedsSync: _scheduleStickyDateUpdate,
            child: DateSeparator(
              key: ValueKey<DateTime>(currentDate),
              dateLabel: _formatDateLabel(currentDt),
              onTap: () => _openCalendarForDate(currentDt),
            ),
          ),
        ),
      );
    }

    if (_showUnreadDivider && feedIndex == _firstUnreadFeedIndex) {
      items.add(UnreadSeparator(key: _unreadSeparatorKey));
    }

    if (album == null && message.messageType == 'system') {
      items.add(
        Padding(
          key: key,
          padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 12),
          child: TelegramServiceMessageWidget(
            message: message,
            isChannel: true,
            onTapUser: _openUserProfileById,
            onTapPinnedMessage: (msgId) => _scrollToMessage(msgId),
            onTapPhoto: (url) {
              final resolved = AppConfig.resolveMediaUrl(url) ?? url;
              FullscreenPhotoViewer.open(context, resolved);
            },
          ),
        ),
      );
      return RepaintBoundary(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: items,
        ),
      );
    }

    final isHighlighted = message.id == _highlightMessageId ||
        (album != null &&
            album.items.any((ai) => ai.id == _highlightMessageId));
    final isSelected = _selectedMessageIds.contains(message.id) ||
        (album != null &&
            album.items.any((ai) => _selectedMessageIds.contains(ai.id)));
    final bool isMe = message.senderId == _currentUserId || _isAdmin;

    Widget postWidget = ChannelPostCard(
      key: key,
      message: album == null ? message : null,
      album: album,
      currentUserId: _currentUserId ?? '',
      channelName: _channelName.isNotEmpty
          ? _channelName
          : (widget.channelName ?? 'Channel'),
      channelAvatar: widget.channelAvatar ?? _channelAvatar,
      signMessages: _signMessages,
      showAuthorProfiles: _showAuthorProfiles,
      linkedChatId: _linkedChatId,
      reactionSettings: _reactionSettings,
      reactionsOverride: _messageReactions[message.id],
      myReactionsOverride: _myReactions[message.id],
      isHighlighted: isHighlighted,
      isSelected: isSelected,
      isSelectionMode: _isSelectionMode,
      highlightItemId: _highlightMessageId,
      formatTime: _formatTime,
      onReactionTap: (emoji) {
        if (_isSelectionMode) {
          _toggleFeedSelection(message, album);
          return;
        }
        _toggleReaction(message.id, emoji);
      },
      onShareTap: () {
        if (_isSelectionMode) {
          _toggleFeedSelection(message, album);
          return;
        }
        _forwardMessagesToPickedChat(
          album != null
              ? album.items.map((m) => m.id).toList()
              : [message.id],
        );
      },
      onCommentsTap: () {
        if (_isSelectionMode) {
          _toggleFeedSelection(message, album);
          return;
        }
        _openPostComments(message);
      },
      onAuthorTap:
          _isSelectionMode ? null : () => _openAuthorProfile(message),
      onReplyTap: _isSelectionMode
          ? (_, __) => _toggleFeedSelection(message, album)
          : (replyToId, chatId) => _handleReplyTap(
                replyToId,
                chatId,
                fromMessageId: message.id,
              ),
      onFileTap: (url, name, type) {
        if (_isSelectionMode) {
          _toggleFeedSelection(message, album);
          return;
        }
        _openFile(url, name, type);
      },
      onRetry: (msg) => _retryMessage(msg),
      hasProtectedContent: _hasProtectedContent,
      onInsertInlineQuery: _canPostInChannel ? _insertInlineQueryText : null,
      translation: _translationsByMsgId[message.id],
      isTranslating: _translatingMsgIds.contains(message.id),
      onHideTranslation: () {
        setState(() => _translationsByMsgId.remove(message.id));
      },
      onHashtagTap: (_) {
        if (_isSelectionMode) {
          _toggleFeedSelection(message, album);
          return;
        }
        ChatActionsHelper.openSearch(
          context: context,
          chatId: widget.channelId,
          chatName: _channelName.isNotEmpty
              ? _channelName
              : (widget.channelName ?? 'Канал'),
          onMessageSelected: (msgId) => _scrollToMessage(msgId),
        );
      },
      onBodyTap: _isSelectionMode
          ? null
          : () => _showContextMenu(
                message,
                isMe,
                key,
                album: album,
                enableBlur: true,
              ),
      onDoubleTap: _isSelectionMode
          ? null
          : () => _toggleReaction(message.id, '❤️'),
    );

    postWidget = SwipeToReplyWrapper(
      onReply: () => _startReply(message),
      enabled: _canPostInChannel && !_isSelectionMode,
      child: postWidget,
    );

    final platform = Theme.of(context).platform;
    final bool isDesktop = platform == TargetPlatform.windows ||
        platform == TargetPlatform.linux ||
        platform == TargetPlatform.macOS;

    postWidget = Listener(
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
            _toggleFeedSelection(message, album);
            return;
          }
          if (!isDesktop) {
            _showContextMenu(
              message,
              isMe,
              key,
              album: album,
              enableBlur: true,
            );
          }
        },
        onDoubleTap: _isSelectionMode
            ? null
            : () => _toggleReaction(message.id, '❤️'),
        onLongPress: isDesktop
            ? null
            : () {
                _enterFeedSelection(message, album);
              },
        onSecondaryTapUp: (details) {
          if (_isSelectionMode) {
            _toggleFeedSelection(message, album);
            return;
          }
          final bool clickedOnBubble = MessageBubble.isGlobalPointInsideBubble(
            key.currentContext,
            details.globalPosition,
          );
          _showContextMenu(
            message,
            isMe,
            key,
            album: album,
            forceOpen: true,
            enableBlur: clickedOnBubble,
          );
        },
        behavior: HitTestBehavior.opaque,
        child: postWidget,
      ),
    );

    postWidget = ValueListenableBuilder<String?>(
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
      child: postWidget,
    );

    final viewIds = album != null
        ? album.items.map((m) => m.id).toList()
        : [message.id];
    postWidget = VisibilityDetector(
      key: Key('ch_view_${item.id}'),
      onVisibilityChanged: (info) {
        if (info.visibleFraction >= 0.35) {
          _enqueuePostViews(viewIds);
        }
      },
      child: postWidget,
    );

    items.add(postWidget);

    return RepaintBoundary(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: items,
      ),
    );
  }

  Future<void> _deleteMessagesWithSheet(List<Message> targets) async {
    if (targets.isEmpty) return;
    final canRevokeTargets = _canDeleteChannelPosts(targets);
    final res = await showTelegramDeleteMessagesSheet(
      context: context,
      messageCount: targets.length,
      chatType: 'channel',
      canRevoke: canRevokeTargets,
      defaultRevoke: canRevokeTargets,
    );
    if (res == null || !res.confirmed || !mounted) return;

    final ids = targets.map((m) => m.id).toList();
    final backup = List<Message>.from(_messages);
    setState(() {
      _messages.removeWhere((m) => ids.contains(m.id));
      _selectedMessageIds.removeAll(ids);
      _updateFeedItems();
    });

    final apiRes = await ChatService.deleteMessagesBatch(
      chatId: widget.channelId,
      messageIds: ids,
      revoke: res.revoke,
    );
    if (apiRes['success'] != true && mounted) {
      setState(() {
        _messages
          ..clear()
          ..addAll(backup);
        _updateFeedItems();
      });
      GlassToastService().showError(
        context,
        apiRes['message']?.toString() ?? 'Не удалось удалить публикации',
      );
    }
  }

  Future<void> _togglePinMessage(Message message) async {
    final isCurrentlyPinned = _pinnedMessage?.id == message.id;
    if (isCurrentlyPinned) {
      setState(() => _pinnedMessage = null);
      final res = await ChatService.unpinMessage(
        chatId: widget.channelId,
        messageId: message.id,
      );
      if (res['success'] == true && mounted) {
        GlassToastService().show(
          context,
          'Пост откреплен',
          iconWidget: iconoir.PinSlash(
            width: 20,
            height: 20,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        );
      }
    } else {
      setState(() => _pinnedMessage = message);
      final res = await ChatService.pinMessage(
        chatId: widget.channelId,
        messageId: message.id,
      );
      if (res['success'] == true && mounted) {
        GlassToastService().show(
          context,
          'Пост закреплен',
          iconWidget: iconoir.Pin(
            width: 20,
            height: 20,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        );
      }
    }
  }

  Future<void> _forwardMessagesToPickedChat(List<String> messageIds) async {
    if (messageIds.isEmpty) return;
    if (_hasProtectedContent) {
      GlassToastService().show(
        context,
        'Копирование и пересылка запрещены в этом канале',
      );
      return;
    }
    await ForwardChatPickerSheet.show(
      context,
      fromChatId: widget.channelId,
      messageIds: messageIds,
      onStageInCurrentChat: _canPostInChannel
          ? ({required hideSender, required hideCaption}) {
              final stagedMsgs = _messages
                  .where((m) => messageIds.contains(m.id))
                  .toList()
                  .reversed
                  .toList();
              if (stagedMsgs.isEmpty || !mounted) return;
              setState(() {
                _stagedForward = StagedForwardPayload(
                  fromChatId: widget.channelId,
                  messages: stagedMsgs,
                  hideSender: hideSender,
                  hideCaption: hideCaption,
                );
              });
            }
          : null,
      onForwarded: (targetChatId) {
        if (targetChatId == widget.channelId) _triggerSilentSync();
      },
    );
  }

  Future<void> _openStagedForwardOptions() async {
    final staged = _stagedForward;
    if (staged == null) return;
    final res = await showForwardOptionsSheet(
      context: context,
      payload: staged,
    );
    if (!mounted || res == null) return;
    if (res.cancelForward) {
      setState(() => _stagedForward = null);
      return;
    }
    final updated = staged.copyWith(
      hideSender: res.hideSender,
      hideCaption: res.hideCaption,
    );
    if (res.changeRecipient) {
      final target = await ForwardChatPickerSheet.pickTargetChat(
        context,
        fromChatId: updated.fromChatId,
        messageCount: updated.messages.length,
      );
      if (!mounted || target == null) return;
      if (target.chatId == widget.channelId) {
        setState(() => _stagedForward = updated);
        return;
      }
      final fwdRes = await ChatService.forwardMessages(
        toChatId: target.chatId,
        fromChatId: updated.fromChatId,
        messageIds: updated.messages.map((m) => m.id).toList(),
        hideSender: updated.hideSender,
        hideCaption: updated.hideCaption,
        isSilent: _isSilentBroadcast,
      );
      if (!mounted) return;
      if (fwdRes['success'] == true) {
        setState(() => _stagedForward = null);
        GlassToastService().show(
          context,
          'Переслано в «${target.chatType == 'saved' ? 'Избранное' : target.name}»',
        );
      } else {
        GlassToastService().showError(
          context,
          fwdRes['message']?.toString() ?? 'Ошибка пересылки',
        );
      }
      return;
    }
    setState(() => _stagedForward = updated);
  }

  Future<void> _openScheduledMessages() async {
    await Navigator.of(context).push(
      SwipeBackPageRoute(
        builder: (_) => ScheduledMessagesScreen(
          chatId: widget.channelId,
          chatTitle: _channelName,
        ),
      ),
    );
    if (mounted) unawaited(_loadScheduledCount());
  }

  Future<void> _handleSendLongPress() async {
    final parsedText = _messageController.cleanText.trimRight();
    if (parsedText.trim().isEmpty && _attachedFiles.isEmpty) return;
    final choice = await showSendOptionsPopup(
      context: context,
      isPrivateChat: false,
    );
    if (!mounted || choice == null) return;
    if (choice == SendOptionChoice.sendSilent) {
      await _sendMessage(isSilent: true);
      return;
    }
    if (choice != SendOptionChoice.schedule) return;
    final scheduleAt = await showTheavScheduleSheet(context: context);
    if (!mounted || scheduleAt == null) return;

    final entities = _messageController.entities;
    if (_attachedFiles.isNotEmpty) {
      setState(() => _isUploading = true);
      try {
        for (int i = 0; i < _attachedFiles.length; i++) {
          final file = _attachedFiles[i];
          final uploadResult = await _fileService.uploadFileChunked(file);
          final msgType = _detectMessageType(p.basename(file.path));
          await ChatService.createScheduledMessage(
            chatId: widget.channelId,
            content: i == 0 ? parsedText : '',
            messageType: msgType,
            scheduleAt: scheduleAt,
            fileUrl: uploadResult.url,
            fileName: uploadResult.fileName,
            mediaPayload: uploadResult.toMediaPayload(),
            entities: i == 0 && entities.isNotEmpty ? entities : null,
            isSilent: _isSilentBroadcast,
          );
        }
        setState(() {
          _attachedFiles.clear();
          _attachedFileNames.clear();
        });
      } finally {
        if (mounted) setState(() => _isUploading = false);
      }
    } else {
      await ChatService.createScheduledMessage(
        chatId: widget.channelId,
        content: parsedText,
        scheduleAt: scheduleAt,
        entities: entities.isNotEmpty ? entities : null,
        isSilent: _isSilentBroadcast,
      );
    }
    _suppressDraftSave = true;
    try {
      if (_replyToMessage != null && mounted) {
        setState(() {
          _replyToMessage = null;
          _pendingDraftReplyId = null;
          _isQuote = false;
          _quoteText = null;
          _quoteOffset = 0;
          _quoteLength = 0;
        });
      }
      _messageController.clear();
    } finally {
      _suppressDraftSave = false;
    }
    DraftService().clearLocalDraftOnSend(_draftKey);
    unawaited(_loadScheduledCount());
    if (mounted) {
      GlassToastService().show(context, 'Публикация запланирована');
    }
  }

  MediaAlbum? _resolveAlbumForMessage(Message message) {
    final gId = message.groupedId;
    if (gId == null || gId.isEmpty) return null;
    for (final item in _feedItems) {
      if (item is FeedAlbumItem &&
          (item.album.groupedId == gId ||
              item.album.items.any((ai) => ai.id == message.id))) {
        return item.album;
      }
    }
    return null;
  }

  void _showContextMenu(
    Message message,
    bool isMe,
    GlobalKey key, {
    MediaAlbum? album,
    bool forceOpen = false,
    bool enableBlur = true,
    Offset? initialDragStartGlobalPosition,
    Offset? initialDragCurrentGlobalPosition,
  }) {
    _dismissKeyboardAndEmoji();
    final MediaAlbum? resolvedAlbum = album ?? _resolveAlbumForMessage(message);
    final List<String> targetIds = resolvedAlbum != null
        ? resolvedAlbum.items.map((m) => m.id).toList()
        : [message.id];
    final List<Message> targetMessages = resolvedAlbum != null
        ? _messages.where((m) => targetIds.contains(m.id)).toList()
        : [message];
    final bool isVideoNote = message.isRound || (message.messageType == 'video' && message.isRound);
    final bool isVoiceNote = message.messageType == 'voice';
    final bool isPoll = message.messageType == 'poll';

    MessageContextMenuService().show(
      context: context,
      message: message,
      messageKey: key,
      isMe: isMe,
      enableBlur: enableBlur,
      hasProtectedContent: _hasProtectedContent,
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
            _updateFeedItems();
          }
        });
      },
      onReply: _canPostInChannel ? () => _startReply(message) : null,
      onQuote: (_canPostInChannel && !isVideoNote && !isVoiceNote && !isPoll)
          ? () => _startQuote(message, message.content, 0, message.content.length)
          : null,
      onQuotePartial: (_canPostInChannel && !isVideoNote && !isVoiceNote && !isPoll)
          ? (selectedText, offset, length) =>
              _startQuote(message, selectedText, offset, length)
          : null,
      onSelect: () => _enterFeedSelection(message, resolvedAlbum),
      onPin: _canPinMessages ? () => _togglePinMessage(message) : null,
      isPinned: _pinnedMessage?.id == message.id,
      onForward: () => _forwardMessagesToPickedChat(targetIds),
      onEdit: (_canEditChannelPost(message) &&
              !isVideoNote &&
              !isVoiceNote &&
              !isPoll)
          ? () => _enterEditMode(message)
          : null,
      onViewStats: _isAdmin
          ? () => showPostStatsSheet(
                context: context,
                chatId: widget.channelId,
                messageId: message.id,
                previewText: message.content,
              )
          : null,
      onTranslate: message.content.trim().isNotEmpty
          ? () => unawaited(_toggleTranslateMessage(message))
          : null,
      isTranslated: _translationsByMsgId.containsKey(message.id),
      onReplyInAnotherChat: !_hasProtectedContent
          ? () => unawaited(_replyInAnotherChat(message))
          : null,
      onDelete: _canDeleteChannelPosts(
              targetMessages.isNotEmpty ? targetMessages : [message])
          ? (_) => _deleteMessagesWithSheet(
                targetMessages.isNotEmpty ? targetMessages : [message],
              )
          : null,
      onReaction: (msgId, emoji) => _toggleReaction(msgId, emoji),
      selectedEmojis: _myReactions[message.id] ?? message.myReactions,
    );
  }

  Future<void> _sendLocation() async {
    if (!_canPostInChannel) return;
    final picked = await showLocationPickerSheet(context);
    if (!mounted || picked == null) return;
    final res = await ChatService.sendMessage(
      chatId: widget.channelId,
      content: '',
      messageType: picked.messageType,
      latitude: picked.latitude,
      longitude: picked.longitude,
      livePeriod: picked.livePeriod,
      heading: picked.heading,
      horizontalAccuracy: picked.horizontalAccuracy,
      placeName: picked.placeName,
      address: picked.address,
      isSilent: _isSilentBroadcast,
    );
    if (!mounted) return;
    if (res['success'] == true && res['message'] is Message) {
      final sent = res['message'] as Message;
      setState(() {
        if (!_messages.any((m) => m.id == sent.id)) {
          _messages.insert(0, sent);
          _updateFeedItems();
        }
      });
      await AppDatabase().saveMessage(_messageToCompanion(sent));
      _scrollToBottom();
    } else {
      GlassToastService().showError(
        context,
        res['message']?.toString() ?? 'Не удалось отправить геопозицию',
      );
    }
  }

  Future<void> _sendContact() async {
    if (!_canPostInChannel) return;
    final picked = await showContactPickerSheet(context);
    if (!mounted || picked == null) return;
    final res = await ChatService.sendMessage(
      chatId: widget.channelId,
      content: picked.displayName,
      messageType: 'contact',
      contact: picked.toPayload(),
      isSilent: _isSilentBroadcast,
    );
    if (!mounted) return;
    if (res['success'] == true && res['message'] is Message) {
      final sent = res['message'] as Message;
      setState(() {
        if (!_messages.any((m) => m.id == sent.id)) {
          _messages.insert(0, sent);
          _updateFeedItems();
        }
      });
      await AppDatabase().saveMessage(_messageToCompanion(sent));
      _scrollToBottom();
    } else {
      GlassToastService().showError(
        context,
        res['message']?.toString() ?? 'Не удалось отправить контакт',
      );
    }
  }

  Future<void> _toggleTranslateMessage(Message message) async {
    if (_translationsByMsgId.containsKey(message.id)) {
      setState(() => _translationsByMsgId.remove(message.id));
      return;
    }
    if (_translatingMsgIds.contains(message.id)) return;
    setState(() => _translatingMsgIds.add(message.id));
    final localeCode = Localizations.localeOf(context).languageCode;
    final targetLang = localeCode.isNotEmpty ? localeCode : 'ru';
    final res = await DmParityService.translateMessage(
      chatId: widget.channelId,
      messageId: message.id,
      targetLang: targetLang,
    );
    if (!mounted) return;
    setState(() {
      _translatingMsgIds.remove(message.id);
      if (res['success'] == true && res['translation'] is TranslationResult) {
        _translationsByMsgId[message.id] =
            res['translation'] as TranslationResult;
      }
    });
    if (res['success'] != true && mounted) {
      GlassToastService().showError(
        context,
        res['message']?.toString() ?? 'Не удалось перевести пост',
      );
    }
  }

  Future<void> _replyInAnotherChat(Message message) async {
    final target = await ForwardChatPickerSheet.pickTargetChat(
      context,
      fromChatId: widget.channelId,
      messageCount: 1,
    );
    if (!mounted || target == null) return;
    if (target.chatId == widget.channelId && _canPostInChannel) {
      _startReply(message);
      return;
    }
    if (target.chatType == 'private' || target.chatType == 'saved') {
      await Navigator.of(context).push(
        SwipeBackPageRoute(
          builder: (_) => PrivateChatScreen(
            chatId: target.chatId,
            otherUserName:
                target.chatType == 'saved' ? 'Избранное' : target.name,
            otherUserAvatar: target.avatarUrl,
            otherUserId: target.otherUserId,
            initialReplyMessage: message,
            initialReplyChatId: widget.channelId,
            initialReplyChatName: _channelName.isNotEmpty
                ? _channelName
                : (widget.channelName ?? 'Канал'),
          ),
        ),
      );
    } else {
      GlassToastService().show(
        context,
        'Ответ в другой чат пока поддержан только для личных чатов',
      );
    }
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
    if (_hasProtectedContent) {
      GlassToastService().show(
        context,
        'Копирование и пересылка запрещены в этом канале',
      );
      return;
    }
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
    final ids = _selectedMessageIds.toList();
    _clearSelection();
    _forwardMessagesToPickedChat(ids);
  }

  void _deleteSelectedMessages() {
    final selected = _getOrderedSelectedMessages();
    if (selected.isEmpty) return;
    _clearSelection();
    _deleteMessagesWithSheet(selected);
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
            final isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
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
          final isKeyboardOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
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
    for (int i = 0; i < _feedItems.length; i++) {
      final msg = _feedItemPrimaryMessage(_feedItems[i]);
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
      if (i < 0 || i >= _feedItems.length) continue;
      final item = _feedItems[i];
      final ids = item is FeedAlbumItem
          ? item.album.items.map((m) => m.id)
          : [_feedItemPrimaryMessage(item).id];
      for (final id in ids) {
        if (_dragSelectTargetState) {
          nextIds.add(id);
        } else {
          nextIds.remove(id);
        }
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

  Widget _buildBottomBar(String displayName) {
    final bar = ChannelBottomCapsuleBar(
      channelId: widget.channelId,
      channelName: displayName,
      myRole: _myRole,
      isMember: _isMember,
      canPostInChannel: _canPostInChannel,
      isMuted: _isMuted,
      linkedChatId: _linkedChatId,
      linkedChatName: _linkedChat?.name,
      linkedChatAvatar: _linkedChat?.avatarUrl,
      isSilentBroadcast: _isSilentBroadcast,
      onToggleSilentBroadcast: (silent) {
        unawaited(_setSilentBroadcast(silent));
      },
      onMuteChanged: (newMuted) {
        setState(() => _isMuted = newMuted);
      },
      onSubscribed: (joinedChat) {
        if (!mounted) return;
        setState(() {
          _isMember = true;
          if (_myRole == 'guest') {
            _myRole = 'subscriber';
          }
          if (joinedChat != null && joinedChat.name.isNotEmpty) {
            _channelName = joinedChat.name;
          }
        });
        unawaited(_refreshChannelDetails());
        unawaited(_markMessagesAsRead());
      },
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
      onTapReply: _replyToMessage != null
          ? () => _scrollToMessage(_replyToMessage!.id)
          : null,
      attachedFiles: _attachedFiles,
      attachedFileNames: _attachedFileNames,
      onRemoveAttachment: (index) {
        setState(() {
          if (index >= 0 && index < _attachedFiles.length) {
            _attachedFiles.removeAt(index);
          }
          if (index >= 0 && index < _attachedFileNames.length) {
            _attachedFileNames.removeAt(index);
          }
        });
      },
      isEditing: _isEditing,
      onCancelEditing: _cancelEditing,
      onEditLastMessage: _editLastOwnMessage,
      isEmojiPanelOpen: _showEmojiPanel && !_isKeyboardRising,
      onTapInputWhenEmojiOpen: _onEmojiToggle,
      onEmoji: _onEmojiToggle,
      forwardPreviewBanner: _stagedForward != null
          ? ForwardPreviewBar(
              payload: _stagedForward!,
              onTapOptions: _openStagedForwardOptions,
              onCancel: () => setState(() => _stagedForward = null),
            )
          : null,
      scheduledCount: _scheduledCount,
      onOpenScheduled: _openScheduledMessages,
      onSendLongPress: _handleSendLongPress,
      onAttach: _showAttachmentPicker,
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
      linkPreviewOptions: _linkPreviewOptions,
      onLinkPreviewOptionsChanged: (opts) {
        setState(() => _linkPreviewOptions = opts);
      },
      invertMedia: _invertMedia,
      onInvertMediaChanged: (val) {
        setState(() => _invertMedia = val);
      },
    );

    if (!_canPostInChannel) return bar;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        ListenableBuilder(
          listenable: _inlineQueryController,
          builder: (ctx, _) {
            if (!_inlineQueryController.isActive) {
              return const SizedBox.shrink();
            }
            return InlineResultsPopup(
              botUsername: _inlineQueryController.activeBotUsername ?? '',
              query: _inlineQueryController.query,
              response: _inlineQueryController.response,
              isLoading: _inlineQueryController.isLoading,
              isLoadingMore: _inlineQueryController.isLoadingMore,
              onClose: _inlineQueryController.clear,
              onLoadMore: () => _inlineQueryController.loadMore(
                chatId: widget.channelId,
                chatType: 'channel',
              ),
              onTapHeaderButton: (btn) =>
                  _handleInlinePopupHeaderButtonTap(ctx, btn),
              onSelectResult: (item) async {
                final ok = await _inlineQueryController.sendSelectedResult(
                  chatId: widget.channelId,
                  result: item,
                  replyToMessageId: _replyToMessage?.id,
                  isSilent: _isSilentBroadcast,
                );
                if (!ctx.mounted) return;
                if (ok) {
                  _suppressDraftSave = true;
                  try {
                    if (_replyToMessage != null && mounted) {
                      setState(() {
                        _replyToMessage = null;
                        _pendingDraftReplyId = null;
                        _isQuote = false;
                        _quoteText = null;
                        _quoteOffset = 0;
                        _quoteLength = 0;
                      });
                    }
                    _messageController.clear();
                    _inlineQueryController.clear();
                  } finally {
                    _suppressDraftSave = false;
                  }
                  DraftService().clearLocalDraftOnSend(_draftKey);
                } else {
                  GlassToastService().show(
                    ctx,
                    'Не удалось отправить результат',
                  );
                }
              },
            );
          },
        ),
        if (_activeMentionQuery != null && !_inlineQueryController.isActive)
          MentionAndBotPopup(
            query: _activeMentionQuery!,
            isAtMessageStart: _mentionIsAtStart,
            participants: _participants
                .where((p) => p.id != _currentUserId && p.username.isNotEmpty)
                .map(
                  (p) {
                    final isBot = p.isBot ||
                        p.username.toLowerCase().endsWith('bot') ||
                        p.username.toLowerCase() == 'botmother' ||
                        p.username.toLowerCase() == 'walt';
                    final rawName =
                        p.displayName.isNotEmpty ? p.displayName : p.username;
                    final displayName = !isBot
                        ? ContactsService.resolvePeerName(
                            p.id,
                            rawName,
                            isBot: isBot,
                          )
                        : rawName;
                    final avatarUrl = !isBot
                        ? ContactsService.resolvePeerAvatarUrl(
                            p.id,
                            p.avatarUrl,
                            isBot: isBot,
                          )
                        : p.avatarUrl;
                    return MentionCandidate(
                      id: p.id,
                      username: p.username,
                      displayName: displayName,
                      avatarUrl: avatarUrl,
                      isBot: isBot,
                    );
                  },
                )
                .toList(),
            inlineBots: _inlineDirectoryBots,
            onSelectMention: (cand) => _applyMentionSelection(cand.username),
            onSelectInlineBot: (bot) {
              if (bot.username != null && bot.username!.isNotEmpty) {
                _applyMentionSelection(bot.username!);
              }
            },
            onClose: () => setState(() => _activeMentionQuery = null),
          ),
        bar,
      ],
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
          GlassToastService().show(
            context,
            context.l10n.translate('chat_video_note_permission_denied'),
            actionLabel: context.l10n.translate('settings_title'),
            onAction: () => openAppSettings(),
          );
        }
        return;
      }

      final granted = await _videoRecorderService.requestPermissions();
      if (!granted) {
        if (mounted) {
          GlassToastService().show(
            context,
            context.l10n.translate('chat_video_note_permission_denied'),
            actionLabel: context.l10n.translate('settings_title'),
            onAction: () => openAppSettings(),
          );
        }
        return;
      }

      if (mounted) {
        GlassToastService().show(
          context,
          context.l10n.translate('chat_video_note_hold_hint'),
          duration: const Duration(seconds: 3),
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
      GlassToastService().show(
        context,
        isPermDenied
                ? context.l10n.translate('chat_video_note_permission_denied')
                : (_videoRecorderService.errorMessage ??
                    context.l10n
                        .translate('chat_video_note_permission_denied')),
        actionLabel: context.l10n.translate('settings_title'),
        onAction: () => openAppSettings(),
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
    GlassToastService().show(
      context,
      context.l10n.translate('chat_video_note_too_short'),
      duration: const Duration(seconds: 2),
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
          GlassToastService().show(
            context,
            context.l10n.translate('chat_voice_permission_denied'),
            actionLabel: context.l10n.translate('settings_title'),
            onAction: () => openAppSettings(),
          );
        }
        return;
      }
      final granted = await _voiceRecorderService.requestPermissions();
      if (!granted) return;
      if (mounted) {
        GlassToastService().show(
          context,
          context.l10n.translate('chat_video_note_hold_hint'),
          duration: const Duration(seconds: 3),
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
          : file.path.split(!kIsWeb ? Platform.pathSeparator : '/').last;
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
          isSilent: _isSilentBroadcast,
        );
      } catch (e) {
        debugPrint('SyncService createPendingMessage voice error in channel: $e');
      }

      if (pendingMsg != null && mounted) {
        pendingLocalId = pendingMsg.localId;
        var message = Message.fromDbMessage(pendingMsg).copyWith(
          waveform: result.waveform,
          duration: result.duration.inSeconds,
          isSilent: _isSilentBroadcast,
        );
        if (replyTo != null) {
          final channelTitle =
              _channelName.isNotEmpty ? _channelName : widget.channelName;
          message = message.copyWith(
            replyInfo: ReplyInfo(
              messageId: replyTo.id,
              senderId: '0',
              senderName: replyTo.resolveEffectiveAuthorTitle(
                chatName: channelTitle,
                chatType: 'channel',
              ),
              content: replyTo.content,
              messageType: replyTo.messageType,
              entities: replyTo.entities,
              nameColorPresetId: 'name_red',
              replyStripStyle: 'solid',
              replyEmoji: null,
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
        isSilent: _isSilentBroadcast,
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
          : file.path.split(!kIsWeb ? Platform.pathSeparator : '/').last;
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
          isSilent: _isSilentBroadcast,
        );
      } catch (e) {
        debugPrint('SyncService createPendingMessage video error in channel: $e');
      }

      if (pendingMsg != null && mounted) {
        pendingLocalId = pendingMsg.localId;
        var message = Message.fromDbMessage(pendingMsg).copyWith(
          duration: recordedDurationSec,
        );
        if (replyTo != null) {
          final channelTitle =
              _channelName.isNotEmpty ? _channelName : widget.channelName;
          message = message.copyWith(
            replyInfo: ReplyInfo(
              messageId: replyTo.id,
              senderId: '0',
              senderName: replyTo.resolveEffectiveAuthorTitle(
                chatName: channelTitle,
                chatType: 'channel',
              ),
              content: replyTo.content,
              messageType: replyTo.messageType,
              entities: replyTo.entities,
              nameColorPresetId: 'name_red',
              replyStripStyle: 'solid',
              replyEmoji: null,
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
        isSilent: _isSilentBroadcast,
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
        GlassToastService().show(context, context.l10n.translate('chat_upload_error'));
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
