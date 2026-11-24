import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart' show SchedulerBinding, SchedulerPhase;
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:provider/provider.dart';
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/services.dart';
import '../../services/glass_toast_service.dart';
import '../../widgets/chat/forward_options_sheet.dart';
import '../../widgets/chat/send_options_popup.dart';
import '../../widgets/chat/telegram_delete_messages_sheet.dart';
import '../../widgets/design_system/theav_design_system.dart';
import 'pinned_messages_screen.dart';
import 'scheduled_messages_screen.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/link_opener.dart';
import '../../services/chat_service.dart';
import '../../models/chat_draft.dart';
import '../../services/draft_service.dart';
import '../../services/chat_actions_helper.dart';
import '../../services/auth_service.dart';
import '../../services/groups_channels_parity_service.dart';
import '../../services/notification_settings_provider.dart';
import '../../services/screen_protection_service.dart';
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
import '../../services/peer_customization_cache.dart';
import '../../services/profile_instant_cache.dart';
import '../../services/profile_theme_provider.dart';
import '../../models/name_color_preset.dart';
import '../../models/profile_customization.dart';
import '../../widgets/message/group_message_avatar_row.dart';
import '../settings/profile_screen.dart';
import '../../services/message_context_menu_service.dart';
import '../../l10n/app_localizations.dart';
import '../../config/app_config.dart';
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
import '../../widgets/chat/groups_channels_parity_widgets.dart';
import '../../widgets/chat/chat_scaffold.dart';
import '../../widgets/chat/chat_input_bar.dart';
import '../../widgets/chat/chat_messages_list_view.dart';
import '../../widgets/chat/chat_messages_shimmer.dart';
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
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:uuid/uuid.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:share_plus/share_plus.dart';
import '../../utils/blur_utils.dart';
import '../../utils/swipe_back_route.dart';
import 'private_chat_screen.dart';
import 'channel_screen.dart';
import 'forum_topics_screen.dart';
import '../../utils/date_time_utils.dart';
import 'group_info_screen.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import '../../widgets/chat/attachment_picker_bottom_sheet.dart';
import '../../widgets/chat/emoji_sticker_panel.dart';
import '../../widgets/chat/forward_chat_picker_sheet.dart';
import '../../widgets/chat/live_chat_call_banner.dart';
import '../../widgets/chat/message_reply_info.dart';
import '../../widgets/chat/pinned_message_banner.dart';
import '../../widgets/message/telegram_service_message_widget.dart';
import 'media_send_screen.dart';
import 'poll_create_screen.dart';
import '../../services/tiling_layout_controller.dart';
import '../../services/proximity_audio_service.dart';
import '../../services/sticker_service.dart';
import '../../widgets/tiling/tile_viewport_scope.dart';
import '../call/group_call_screen.dart';
import '../../services/bot_service.dart';
import '../../services/deep_link_service.dart';
import '../../services/dm_parity_service.dart';
import '../../services/account_manager.dart';
import '../../services/chat_instant_cache.dart';
import 'package:geolocator/geolocator.dart';
import '../../widgets/chat/contact_picker_sheet.dart';
import '../../widgets/chat/dm_parity_sheets.dart';
import '../../widgets/chat/location_picker_sheet.dart';
import '../../widgets/chat/bot_commands_popup.dart';
import '../../widgets/chat/mention_and_bot_popup.dart';
import '../../widgets/chat/reply_keyboard_panel.dart';
import '../../widgets/bot/inline_results_popup.dart';
import '../../widgets/bot/mini_app_webview_sheet.dart';

class GroupChatScreen extends StatefulWidget {
  static const String routeName = '/group_chat';

  final String chatId;
  final String? groupName;
  final String? groupAvatar;
  final String? initialMessageId;
  final ForumTopic? activeTopic;
  final bool initialIsForum;
  final String? communityName;
  final bool communityReadOnly;
  final String? communityReadOnlyReason;
  final VoidCallback? onOpenCommunityChannels;
  final VoidCallback? onOpenCommunityMembers;
  final VoidCallback? onOpenCommunitySettings;

  const GroupChatScreen({
    Key? key,
    required this.chatId,
    this.groupName,
    this.groupAvatar,
    this.initialMessageId,
    this.activeTopic,
    this.initialIsForum = false,
    this.communityName,
    this.communityReadOnly = false,
    this.communityReadOnlyReason,
    this.onOpenCommunityChannels,
    this.onOpenCommunityMembers,
    this.onOpenCommunitySettings,
  }) : super(key: key);

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
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
  final List<MessageEntity> _pendingCustomEmojiEntities = [];
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
  bool _isMuted = false;
  bool _isSending = false;
  String? _currentUserId;
  String _groupName = '';
  String? _groupAvatar;
  String? _groupDescription;
  bool _isVerified = false;
  ChatDetails? _chatDetails;
  String? _myRole;
  bool _isMember = true;
  bool _myIsAnonymous = false;
  String _myAdminTitle = '';
  AdminRights? _myAdminPermissions;
  GroupDefaultPermissions _defaultPermissions = const GroupDefaultPermissions();
  MemberRestrictions? _myRestrictions;
  DateTime? _restrictedUntil;
  ReactionSettings _reactionSettings = const ReactionSettings();
  int _slowModeInterval = 0;
  bool _isJoiningGroup = false;
  StreamSubscription<ChatRealtimeUpdate>? _realtimeSub;
  final GlobalKey _topBannerKey = GlobalKey();
  double _topBannerHeight = 0.0;
  bool _topBannerHeightCheckScheduled = false;
  Message? _pinnedMessage;
  List<Message> _pinnedMessages = [];
  int _currentPinnedIndex = 0;
  bool _hasProtectedContent = false;
  int _scheduledCount = 0;
  StagedForwardPayload? _stagedForward;
  int _slowmodeRemainingSeconds = 0;
  Timer? _slowmodeTimer;
  Timer? _entrySettleTimer;
  List<ChatParticipant> _participants = [];
  int _cachedMemberCount = 0;

  // Wave 3B parity state
  bool _isForum = false;
  ForumTopic? _activeTopic;
  List<ForumTopic> _forumTopics = [];
  List<SendAsPeer> _sendAsPeers = [];
  String? _selectedSendAsChatId;
  String _selectedSendAsMode = 'user';
  bool _hasLoadedSendAsPeers = false;
  int _unreadMentionsCount = 0;
  int _unreadReactionsCount = 0;

  // Wave 4B bots & mini apps state
  List<BotCommand> _groupBotCommands = const [];
  bool _isBotCommandsOpen = false;
  bool _isReplyKeyboardOpen = true;
  final InlineQueryController _inlineQueryController = InlineQueryController();
  List<BotInfo> _inlineDirectoryBots = const [];
  String? _activeMentionQuery;
  int _mentionTokenStart = -1;
  int _mentionTokenEnd = -1;
  bool _mentionIsAtStart = false;

  // Parity state (Auto-delete, Appearance, Translation, Live Location)
  int _autoDeleteSeconds = 0;
  ChatAppearanceConfig? _chatAppearance;
  final Map<String, TranslationResult> _translationsByMsgId = {};
  final Set<String> _translatingMsgIds = {};
  String? _activeLiveLocationMessageId;
  Timer? _liveLocationTimer;
  DateTime? _liveLocationExpiresAt;

  String get _screenProtectionKey => 'group_chat_${widget.chatId}';

  bool get _isAdmin => _myRole == 'owner' || _myRole == 'admin';
  bool get _isActiveTopicClosed =>
      (_activeTopic?.isClosed == true) && !_isAdmin;
  int? get _activeTopicId => _activeTopic?.id;

  GroupDefaultPermissions get _effectivePermissions {
    if (_chatDetails != null) {
      return _chatDetails!.effectivePermissions;
    }
    if (_myRole == 'owner' || _myRole == 'admin') {
      return const GroupDefaultPermissions(
        canSendMessages: true,
        canSendMedia: true,
        canSendStickersGifs: true,
        canSendPolls: true,
        canPinMessages: true,
        canInviteUsers: true,
        canChangeInfo: true,
      );
    }
    if (_myRestrictions != null &&
        (_restrictedUntil == null ||
            DateTime.now().isBefore(_restrictedUntil!))) {
      return _defaultPermissions.intersectWith(_myRestrictions);
    }
    return _defaultPermissions;
  }

  bool get _isGuestViewer => !_isMember || _myRole == 'guest';
  bool get _canSendMessages =>
      !widget.communityReadOnly &&
      !_isGuestViewer &&
      !_isActiveTopicClosed &&
      _effectivePermissions.canSendMessages;
  bool get _effectiveSendAsAnon => _selectedSendAsMode == 'group';
  String? get _effectiveSendAsChannelId =>
      _selectedSendAsMode == 'channel' ? _selectedSendAsChatId : null;
  String get _effectiveSendAsMode => _selectedSendAsMode;
  bool _isOwnMessage(Message m) {
    if (m.channelPostId != null && m.channelPostId!.isNotEmpty) {
      return false;
    }
    return m.isOwn ||
        (_currentUserId != null &&
            _currentUserId!.isNotEmpty &&
            m.senderId == _currentUserId);
  }
  bool get _canDeleteOthers {
    if (_isGuestViewer) return false;
    if (_myRole == 'owner') return true;
    if (_myRole == 'admin') {
      return _myAdminPermissions?.canDeleteMessages ?? true;
    }
    return false;
  }
  bool get _canDeleteSelectedMessages {
    if (_selectedMessageIds.isEmpty) return false;
    final selected = _messages
        .where((m) => _selectedMessageIds.contains(m.id))
        .toList();
    if (selected.isEmpty) return false;
    return selected.every((m) => _isOwnMessage(m) || _canDeleteOthers);
  }
  bool get _canPinMessages {
    if (_isGuestViewer) return false;
    if (_myRole == 'owner') return true;
    if (_myRole == 'admin') {
      return _myAdminPermissions?.canPinMessages ?? true;
    }
    return _effectivePermissions.canPinMessages;
  }
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

  // Draft lifecycle state (uses :topic: scope key when inside a forum topic)
  String get _draftKey => _activeTopicId != null
      ? DraftService.topicKey(widget.chatId, _activeTopicId!)
      : widget.chatId;
  bool _suppressDraftSave = false;
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
  final Map<String, GlobalKey> _dateSeparatorKeys = {};
  final GlobalKey _stickyDateSlotKey = GlobalKey();
  final ValueNotifier<StickyDateState> _stickyDateStateNotifier =
      ValueNotifier<StickyDateState>(StickyDateState.empty);
  List<({DateTime day, DateTime sampleDt, int newestIdx, int oldestIdx})>
      _daySpans = [];
  bool _stickyDatePostFrameScheduled = false;

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
        '${day.millisecondsSinceEpoch}',
        () => GlobalKey(),
      );
    }
    final item = _feedItems[feedIndex];
    final msg = item is FeedAlbumItem
        ? item.album.primaryMessage
        : (item as FeedSingleItem).message;
    return _dateSeparatorKeyFor(day, msg);
  }

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

  void _dedupeMessagesInPlace() {
    if (_messages.length < 2) return;
    final seenById = <String, int>{};
    final seenByLocalId = <String, int>{};
    for (int i = 0; i < _messages.length; i++) {
      final m = _messages[i];
      final id = m.id;
      final lid =
          (m.localId != null && m.localId!.isNotEmpty) ? m.localId : null;

      int? dupIdx = seenById[id];
      if (dupIdx == null && lid != null) {
        dupIdx = seenByLocalId[lid];
      }
      if (dupIdx != null && dupIdx != i) {
        final existing = _messages[dupIdx];
        final bool incomingIsServer = int.tryParse(id) != null;
        final bool existingIsServer = int.tryParse(existing.id) != null;
        final Message winnerBase =
            (incomingIsServer && !existingIsServer) ? m : existing;
        final Message loser = identical(winnerBase, m) ? existing : m;
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
        if (mergedLocalId != null &&
            mergedLocalId != winnerBase.id &&
            _messageKeys.containsKey(mergedLocalId)) {
          final promoted = _messageKeys.remove(mergedLocalId)!;
          _messageKeys.putIfAbsent(winnerBase.id, () => promoted);
        }
        _messages[dupIdx] = winnerBase.copyWith(
          localId: mergedLocalId,
          sendStatus: mergedStatus,
          replyInfo: winnerBase.replyInfo ?? loser.replyInfo,
          isOwn: winnerBase.isOwn || loser.isOwn,
        );
        _messages.removeAt(i);
        i--;
        seenById[_messages[dupIdx].id] = dupIdx;
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

  void _mergeConfirmedPendingMessage({
    required String? pendingLocalId,
    required String serverId,
    required Message Function(Message existing) buildMerged,
  }) {
    final hasLocal = pendingLocalId != null && pendingLocalId.isNotEmpty;
    final idx =
        hasLocal ? _messages.indexWhere((m) => m.localId == pendingLocalId) : -1;
    final alreadyById = serverId.isNotEmpty
        ? _messages.indexWhere((m) => m.id == serverId)
        : -1;
    if (idx != -1) {
      final merged = buildMerged(_messages[idx]);
      if (alreadyById != -1 && alreadyById != idx) {
        final existingServer = _messages[alreadyById];
        if (hasLocal &&
            pendingLocalId != serverId &&
            _messageKeys.containsKey(pendingLocalId)) {
          final promoted = _messageKeys.remove(pendingLocalId)!;
          _messageKeys.putIfAbsent(serverId, () => promoted);
        }
        _messages[alreadyById] = merged.copyWith(
          replyInfo: merged.replyInfo ?? existingServer.replyInfo,
          isOwn: merged.isOwn || existingServer.isOwn,
        );
        _messages.removeAt(idx);
      } else {
        _messages[idx] = merged;
      }
    } else if (alreadyById != -1) {
      _messages[alreadyById] = buildMerged(_messages[alreadyById]);
    }
    _updateFeedItems();
  }

  void _updateFeedItems() {
    _dedupeMessagesInPlace();
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

  GlobalKey _obtainPrimaryMessageKey(Message message) {
    final hasLocalId = message.localId != null && message.localId!.isNotEmpty;
    if (hasLocalId &&
        message.localId != message.id &&
        _messageKeys.containsKey(message.localId!)) {
      final promoted = _messageKeys.remove(message.localId!)!;
      _messageKeys[message.id] = promoted;
      return promoted;
    }
    return _messageKeys.putIfAbsent(message.id, () => GlobalKey());
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

  void _saveCurrentDraft({bool immediate = false}) {
    if (_suppressDraftSave || _isEditing || !_canSendMessages) return;
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
    if (!mounted || _isEditing || _inputFocusNode.hasFocus) return;
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

  void _restoreDraftForCurrentScope() {
    final draft = DraftService().getDraft(_draftKey);
    _suppressDraftSave = true;
    try {
      if (draft != null && draft.isNotEmpty) {
        _messageController.loadMessage(draft.text, draft.entities);
        _replyToMessage = null;
        _pendingDraftReplyId =
            (draft.replyToMessageId != null &&
                    draft.replyToMessageId!.isNotEmpty)
                ? draft.replyToMessageId
                : null;
        if (draft.quoteText != null && draft.quoteText!.isNotEmpty) {
          _isQuote = draft.isQuote;
          _quoteText = draft.quoteText;
          _quoteOffset = draft.quoteOffset;
          _quoteLength = draft.quoteLength;
        } else {
          _isQuote = false;
          _quoteText = null;
          _quoteOffset = 0;
          _quoteLength = 0;
        }
      } else {
        _messageController.clear();
        _replyToMessage = null;
        _pendingDraftReplyId = null;
        _isQuote = false;
        _quoteText = null;
        _quoteOffset = 0;
        _quoteLength = 0;
      }
    } finally {
      _suppressDraftSave = false;
    }
    _resolvePendingDraftReply();
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
      });
    } finally {
      _suppressDraftSave = false;
    }
    _focusInputField();
  }

  void _cancelEditing() {
    _stopMyTyping();
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

  UnreadCountProvider? _unreadCountProvider;
  String? _registeredTileId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _currentUserId = AccountManager().currentAccount?.userId;
    final instant = ChatInstantCache.instance.getSync(widget.chatId);
    final groupSnap = ProfileInstantCache.instance.getGroupSnapshotSync(widget.chatId);

    _isForum = widget.initialIsForum ||
        widget.activeTopic != null ||
        (instant?.chatDetails?.isForum ?? instant?.chat?.isForum ?? false);
    _activeTopic = widget.activeTopic;
    _isMuted = NotificationSettingsProvider().isChatMuted(
          widget.chatId,
          chatType: 'group',
        ) ||
        ProfileInstantCache.instance.isChatMutedSync(widget.chatId);
    _keyboardHeight =
        instant?.keyboardHeight ?? ChatInstantCache.instance.globalKeyboardHeight;
    if (instant?.inputHeight != null) {
      _inputHeight = instant!.inputHeight!;
    }
    if (_activeTopicId == null && instant?.chatDetails != null) {
      _seedFromChatDetails(instant!.chatDetails!);
    }
    _groupName = (widget.groupName != null && widget.groupName!.isNotEmpty)
        ? widget.groupName!
        : (instant?.chat?.name ?? _groupName);
    _groupAvatar = widget.groupAvatar ?? instant?.chat?.avatarUrl ?? _groupAvatar;
    _myRole ??= instant?.myRole ?? instant?.chat?.myRole;
    _isMember = instant?.isMember ?? instant?.chat?.isMember ?? _isMember;
    _isVerified = instant?.isVerified ?? instant?.chat?.isVerified ?? _isVerified;
    _hasProtectedContent =
        instant?.hasProtectedContent ?? instant?.chat?.hasProtectedContent ?? _hasProtectedContent;
    if (_autoDeleteSeconds == 0) {
      _autoDeleteSeconds =
          instant?.messageAutoDeleteTime ?? instant?.chat?.messageAutoDeleteTime ?? 0;
    }
    if (_cachedMemberCount == 0) {
      _cachedMemberCount = instant?.memberCount ?? groupSnap?.memberCount ?? 0;
    }
    final instantPinned = instant?.effectivePinnedMessage;
    if (_pinnedMessage == null && instantPinned != null) {
      _pinnedMessage = instantPinned;
      _pinnedMessages = instant?.pinnedMessages ?? [instantPinned];
    }
    _chatAppearance ??=
        (instant?.appearance == null || instant!.appearance!.isEmpty)
            ? null
            : instant.appearance;

    if (_activeTopicId == null && instant != null && instant.hasMessages) {
      _messages.addAll(instant.messages!);
      for (final m in _messages) {
        if (m.reactions.isNotEmpty) {
          _messageReactions[m.id] = Map<String, int>.from(m.reactions);
        }
        if (m.myReactions.isNotEmpty) {
          _myReactions[m.id] = Set<String>.from(m.myReactions);
        }
      }
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
      ProfileInstantCache.instance.prefetchGroupOrChannel(widget.chatId);
      unawaited(_loadData());
      unawaited(_loadCachedKeyboardHeight());
      unawaited(_loadInlineDirectoryBots());
      unawaited(_loadChatAppearance());
      StickerService.instance.loadMyPacks();
    });
    _inputFocusNode.addListener(_onFocusChanged);
    _stickerInputTarget = ChatStickerInputTarget(
      chatId: widget.chatId,
      chatTitle: widget.groupName,
      avatarUrl: widget.groupAvatar,
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
    if (_isDesktopPlatform) {
      HardwareKeyboard.instance.addHandler(_handleGlobalDesktopKeyEvent);
    }

    // Restore draft if exists
    final draft = DraftService().getDraft(_draftKey);
    if (draft != null && draft.isNotEmpty) {
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
    _messageController.addListener(_onControllerDraftSync);
    DeepLinkService.pendingInlinePrefill.addListener(
      _onPendingInlinePrefillChanged,
    );
    final pendingPrefill = DeepLinkService.consumeInlinePrefill(widget.chatId);
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
        final key = _feedItems.isNotEmpty
            ? _messageKeys[_feedItems.first.id]
            : _messageKeys[firstMsgId];
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
        StickerService.instance.registerInputTarget(_stickerInputTarget);
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && !_isSelectionMode) {
            _inputFocusNode.requestFocus();
          }
        });
      }
    }
  }

  bool _handleGlobalDesktopKeyEvent(KeyEvent event) {
    if (!mounted || !_isDesktopPlatform) return false;
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return false;
    if (!_canSendMessages) return false;
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
      ChatInstantCache.instance.setKeyboardHeight(cached, chatId: widget.chatId);
      if (mounted && (cached - _keyboardHeight).abs() > 0.5) {
        setState(() => _keyboardHeight = cached);
      }
    }
  }

  Future<void> _saveKeyboardHeight(double height) async {
    ChatInstantCache.instance.setKeyboardHeight(height, chatId: widget.chatId);
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
      if (_isOwnMessage(msg) &&
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
    _onInputTextChanged(newText);
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
    _onInputTextChanged(_messageController.text);
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
    if (!_canSendMessages || !_effectivePermissions.canSendStickersGifs) {
      if (mounted) {
        GlassToastService().show(
          context,
          'Администраторы ограничили отправку стикеров и GIF',
        );
      }
      return;
    }
    final bool sendAnon = _effectiveSendAsAnon;
    final String sendMode = _effectiveSendAsMode;
    final String? sendChannelId = _effectiveSendAsChannelId;
    final SendAsPeer? activePeer = _activeSendAsPeer;
    final bool sendingAsChannel =
        sendMode == 'channel' &&
        sendChannelId != null &&
        sendChannelId.isNotEmpty;
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
    final optimistic = Message(
      id: localId,
      localId: localId,
      chatId: widget.chatId,
      senderId: _currentUserId ?? '',
      content: fallback,
      messageType: 'sticker',
      fileUrl: item.fileUrl,
      fileName: 'sticker.${item.format}',
      mediaPayload: payload,
      replyToMessageId: replyTo?.id,
      isEdited: false,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      senderName: sendingAsChannel
          ? (activePeer?.name ?? 'Канал')
          : (sendAnon
              ? (_groupName.isNotEmpty
                  ? _groupName
                  : (widget.groupName ?? 'Group'))
              : 'You'),
      senderAvatarUrl: sendingAsChannel
          ? activePeer?.avatarUrl
          : (sendAnon ? (_groupAvatar ?? widget.groupAvatar) : null),
      sendStatus: 0,
      senderRole: sendingAsChannel ? null : _myRole,
      senderAdminTitle: sendingAsChannel
          ? null
          : (_myAdminTitle.isNotEmpty ? _myAdminTitle : null),
      isFromAnonymousAdmin: !sendingAsChannel && sendAnon,
      topicId: _activeTopicId,
      senderChatId: sendingAsChannel ? sendChannelId : null,
      senderChatName: sendingAsChannel ? activePeer?.name : null,
      senderChatAvatarUrl: sendingAsChannel ? activePeer?.avatarUrl : null,
      isOwn: true,
    );
    if (mounted) {
      setState(() {
        _messages.insert(0, optimistic);
        _updateFeedItems();
      });
      _scrollToBottom();
    }
    try {
      final res = await ChatService.sendMessage(
        chatId: widget.chatId,
        content: fallback,
        messageType: 'sticker',
        fileUrl: item.fileUrl,
        fileName: 'sticker.${item.format}',
        mediaPayload: payload,
        replyToMessageId: replyTo?.id,
        localId: localId,
        sendAsMode: sendMode,
        sendAsAnonymous: sendAnon,
        topicId: _activeTopicId,
        sendAsChatId: sendChannelId,
      );
      if (res['success'] == true && res['message'] is Message) {
        final sent = res['message'] as Message;
        _maybeStartLocalSlowmode();
        if (mounted) {
          setState(() {
            final idx = _messages.indexWhere(
              (m) => m.localId == localId || m.id == localId || m.id == sent.id,
            );
            if (idx != -1) {
              _messages[idx] = sent.copyWith(localId: localId, sendStatus: 1);
            } else {
              _messages.insert(0, sent);
            }
            _updateFeedItems();
          });
          _scrollToBottom();
        }
        await AppDatabase().saveMessage(_messageToCompanion(sent));
      } else {
        final retryAfter = res['retry_after'];
        if (retryAfter is int && retryAfter > 0) {
          _startSlowmodeCountdown(retryAfter);
        }
        if (mounted) {
          setState(() {
            _messages.removeWhere((m) => m.localId == localId || m.id == localId);
            _updateFeedItems();
          });
          if (res['message'] != null) {
            GlassToastService().show(context, res['message'].toString());
          }
        }
      }
    } catch (e) {
      debugPrint('Error sending sticker in group: $e');
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.localId == localId || m.id == localId);
          _updateFeedItems();
        });
      }
    }
  }

  Future<void> _sendGifMessage(GifItemModel gif) async {
    if (!_canSendMessages || !_effectivePermissions.canSendStickersGifs) {
      if (mounted) {
        GlassToastService().show(
          context,
          'Администраторы ограничили отправку стикеров и GIF',
        );
      }
      return;
    }
    final bool sendAnon = _effectiveSendAsAnon;
    final String sendMode = _effectiveSendAsMode;
    final String? sendChannelId = _effectiveSendAsChannelId;
    final SendAsPeer? activePeer = _activeSendAsPeer;
    final bool sendingAsChannel =
        sendMode == 'channel' &&
        sendChannelId != null &&
        sendChannelId.isNotEmpty;
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
    final optimistic = Message(
      id: localId,
      localId: localId,
      chatId: widget.chatId,
      senderId: _currentUserId ?? '',
      content: 'GIF',
      messageType: 'gif',
      fileUrl: gif.url,
      fileName: 'animation.gif',
      mediaPayload: payload,
      replyToMessageId: replyTo?.id,
      isEdited: false,
      createdAt: DateTime.now().toUtc().toIso8601String(),
      senderName: sendingAsChannel
          ? (activePeer?.name ?? 'Канал')
          : (sendAnon
              ? (_groupName.isNotEmpty
                  ? _groupName
                  : (widget.groupName ?? 'Group'))
              : 'You'),
      senderAvatarUrl: sendingAsChannel
          ? activePeer?.avatarUrl
          : (sendAnon ? (_groupAvatar ?? widget.groupAvatar) : null),
      sendStatus: 0,
      senderRole: sendingAsChannel ? null : _myRole,
      senderAdminTitle: sendingAsChannel
          ? null
          : (_myAdminTitle.isNotEmpty ? _myAdminTitle : null),
      isFromAnonymousAdmin: !sendingAsChannel && sendAnon,
      topicId: _activeTopicId,
      senderChatId: sendingAsChannel ? sendChannelId : null,
      senderChatName: sendingAsChannel ? activePeer?.name : null,
      senderChatAvatarUrl: sendingAsChannel ? activePeer?.avatarUrl : null,
      isOwn: true,
    );
    if (mounted) {
      setState(() {
        _messages.insert(0, optimistic);
        _updateFeedItems();
      });
      _scrollToBottom();
    }
    try {
      final res = await ChatService.sendMessage(
        chatId: widget.chatId,
        content: 'GIF',
        messageType: 'gif',
        fileUrl: gif.url,
        fileName: 'animation.gif',
        mediaPayload: payload,
        replyToMessageId: replyTo?.id,
        localId: localId,
        sendAsMode: sendMode,
        sendAsAnonymous: sendAnon,
        topicId: _activeTopicId,
        sendAsChatId: sendChannelId,
      );
      if (res['success'] == true && res['message'] is Message) {
        final sent = res['message'] as Message;
        _maybeStartLocalSlowmode();
        if (mounted) {
          setState(() {
            final idx = _messages.indexWhere(
              (m) => m.localId == localId || m.id == localId || m.id == sent.id,
            );
            if (idx != -1) {
              _messages[idx] = sent.copyWith(localId: localId, sendStatus: 1);
            } else {
              _messages.insert(0, sent);
            }
            _updateFeedItems();
          });
          _scrollToBottom();
        }
        await AppDatabase().saveMessage(_messageToCompanion(sent));
      } else {
        final retryAfter = res['retry_after'];
        if (retryAfter is int && retryAfter > 0) {
          _startSlowmodeCountdown(retryAfter);
        }
        if (mounted) {
          setState(() {
            _messages.removeWhere((m) => m.localId == localId || m.id == localId);
            _updateFeedItems();
          });
          GlassToastService().show(
            context,
            res['message']?.toString() ?? 'Не удалось отправить GIF',
          );
        }
      }
    } catch (e) {
      debugPrint('Error sending gif in group: $e');
      if (mounted) {
        setState(() {
          _messages.removeWhere((m) => m.localId == localId || m.id == localId);
          _updateFeedItems();
        });
      }
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
      onMessagePinned: _onMessagePinned,
      onMessageUnpinned: _onMessageUnpinned,
      onScheduledMessagesUpdated: (_) => unawaited(_loadScheduledCount()),
      onCallbackQueryAnswer: _onCallbackQueryAnswer,
      onTyping: _onTypingIndicator,
      onUserStatus: _onUserStatusUpdate,
      onUserAppearanceUpdated: _onUserAppearanceUpdated,
      onUnreadCountUpdated: _onUnreadCountUpdated,
      onUnreadBadgesUpdated: _onUnreadBadgesUpdated,
      onForumTopicUpdated: (_) => unawaited(_loadForumTopics()),
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
            if (_messages[i].senderId == userId && !_messages[i].isFromAnonymousAdmin) {
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
      onChatSettingsUpdated: (event) {
        _applyChatSettingsEvent(event.data);
        unawaited(_refreshChatDetails());
      },
      onMemberUpdated: (event) {
        final targetId = event.data['user_id']?.toString();
        final action = event.data['action']?.toString();
        if (targetId == _currentUserId &&
            (action == 'removed' || action == 'banned')) {
          if (mounted) {
            GlassToastService().show(
              context,
              action == 'banned'
                  ? 'Вы были заблокированы в группе'
                  : 'Вы были исключены из группы',
            );
            TilingLayoutController.popOrCloseChatTile(context);
          }
          return;
        }
        unawaited(_refreshChatDetails());
      },
      onChatDeleted: (_) {
        if (!mounted) return;
        GlassToastService().show(context, 'Группа была удалена');
        TilingLayoutController.popOrCloseChatTile(context);
      },
      onReconnect: () {
        _triggerSilentSync();
        unawaited(_refreshChatDetails());
      },
    );

    _realtimeSub = ChatService.realtimeUpdates.listen((update) {
      if (!mounted || update.chatId != widget.chatId) return;
      if (update.type == WebSocketEventType.chatSettingsUpdated) {
        _applyChatSettingsEvent(update.data);
        unawaited(_refreshChatDetails());
      } else if (update.type == WebSocketEventType.memberUpdated) {
        unawaited(_refreshChatDetails());
      }
    });
  }

  void _applyChatSettingsEvent(Map<String, dynamic> data) {
    if (!mounted) return;
    final perms = GroupDefaultPermissions.tryParse(
      data['default_permissions'] ?? data['chat_permissions'],
    );
    final reactions = ReactionSettings.fromChatJson(data);
    setState(() {
      if (data.containsKey('name') && data['name'] != null) {
        _groupName = data['name'].toString();
      }
      if (data.containsKey('avatar_url')) {
        _groupAvatar = data['avatar_url']?.toString();
      }
      if (data.containsKey('description')) {
        _groupDescription = data['description']?.toString();
      }
      if (perms != null) {
        _defaultPermissions = perms;
      }
      if (reactions != null) {
        _reactionSettings = reactions;
      }
      if (data.containsKey('slow_mode_interval')) {
        final rawSlow = data['slow_mode_interval'];
        if (rawSlow is num) {
          _slowModeInterval = rawSlow.toInt();
        }
      }
      if (data.containsKey('has_protected_content')) {
        final val = data['has_protected_content'];
        _hasProtectedContent = val == true || val == 1 || val == 'true';
      }
      if (data.containsKey('is_forum')) {
        final val = data['is_forum'];
        _isForum = val == true || val == 1 || val == 'true';
      }
    });
    _syncScreenProtection(_hasProtectedContent);
    if (_isForum) {
      unawaited(_loadForumTopics());
    }
  }

  Future<void> _refreshChatDetails() async {
    try {
      final chatResult = await ChatService.getChat(widget.chatId);
      if (chatResult['success'] == true && mounted) {
        _applyChatDetails(chatResult['chat'] as ChatDetails);
      }
    } catch (_) {}
  }

  void _seedFromChatDetails(ChatDetails chat) {
    _chatDetails = chat;
    if (chat.name.isNotEmpty) _groupName = chat.name;
    if (chat.avatarUrl != null && chat.avatarUrl!.isNotEmpty) {
      _groupAvatar = chat.avatarUrl;
    }
    _groupDescription = chat.description;
    if (chat.participants.isNotEmpty) {
      _participants = chat.participants;
    }
    if (chat.effectiveMemberCount > 0) {
      _cachedMemberCount = chat.effectiveMemberCount;
    }
    _isVerified = chat.isVerified;
    _myRole = chat.myRole;
    _isMember = chat.isMember;
    _myIsAnonymous = chat.myIsAnonymous;
    _myAdminTitle = chat.myAdminTitle;
    _myAdminPermissions = chat.myAdminPermissions;
    _defaultPermissions =
        chat.defaultPermissions ?? const GroupDefaultPermissions();
    _myRestrictions = chat.myRestrictions;
    _restrictedUntil = chat.restrictedUntil;
    _reactionSettings = chat.reactionSettings ?? const ReactionSettings();
    _slowModeInterval = chat.slowModeInterval;
    _autoDeleteSeconds = chat.messageAutoDeleteTime;
    _hasProtectedContent = chat.hasProtectedContent;
    _isForum = chat.isForum || _activeTopic != null;
    _unreadMentionsCount = chat.unreadMentionsCount;
    _unreadReactionsCount = chat.unreadReactionsCount;
    _isMuted = NotificationSettingsProvider().isChatMuted(
      widget.chatId,
      chatType: 'group',
    );
    _selectedSendAsChatId ??= chat.mySendAsChatId;
    if (!_hasLoadedSendAsPeers) {
      final rawMode = chat.mySendAsMode?.trim().toLowerCase();
      if (rawMode == 'user' || rawMode == 'group' || rawMode == 'channel') {
        _selectedSendAsMode = rawMode!;
        if (rawMode == 'channel' &&
            chat.mySendAsChatId != null &&
            chat.mySendAsChatId!.trim().isNotEmpty) {
          _selectedSendAsChatId = chat.mySendAsChatId!.trim();
        }
      } else if (chat.mySendAsChatId != null &&
          chat.mySendAsChatId!.trim().isNotEmpty) {
        _selectedSendAsMode = 'channel';
        _selectedSendAsChatId = chat.mySendAsChatId!.trim();
      } else if (_myIsAnonymous &&
          (_myRole == 'owner' || _myRole == 'admin')) {
        _selectedSendAsMode = 'group';
      } else {
        _selectedSendAsMode = 'user';
      }
    }
    if (chat.pinnedMessage != null) {
      _pinnedMessage = chat.pinnedMessage;
      _pinnedMessages = [chat.pinnedMessage!];
    }
  }

  void _applyChatDetails(ChatDetails chat) {
    if (!mounted) return;
    ChatInstantCache.instance.putChatDetails(chat);
    setState(() => _seedFromChatDetails(chat));
    _syncScreenProtection(chat.hasProtectedContent);
    if (chat.isForum || _isForum) {
      unawaited(_loadForumTopics());
    }
    unawaited(_loadSendAsPeers());
    if (chat.slowModeWaitSeconds > 0 && !chat.isAdmin) {
      _startSlowmodeCountdown(chat.slowModeWaitSeconds);
    }
    unawaited(_refreshGroupBotCommands(chat.participants));
  }

  Future<void> _refreshGroupBotCommands(List<ChatParticipant> participants) async {
    final bots = participants
        .where(
          (p) =>
              p.isBot ||
              p.username.toLowerCase().endsWith('bot') ||
              p.username.toLowerCase() == 'botmother' ||
              p.username.toLowerCase() == 'walt',
        )
        .take(5)
        .toList();
    if (bots.isEmpty) {
      if (_groupBotCommands.isNotEmpty && mounted) {
        setState(() => _groupBotCommands = const []);
      }
      return;
    }

    final collected = <BotCommand>[];
    final seen = <String>{};
    for (final bot in bots) {
      final info = await BotService.getBotInfo(
        bot.id,
        chatId: widget.chatId,
        forceRefresh: true,
      );
      if (info == null) continue;
      for (final cmd in info.commands) {
        final key = '${cmd.command.toLowerCase()}_${bot.username.toLowerCase()}';
        if (seen.add(key)) {
          final desc = bot.username.isNotEmpty && cmd.description.isNotEmpty
              ? '${cmd.description} (@${bot.username})'
              : cmd.description;
          collected.add(BotCommand(command: cmd.command, description: desc));
        }
      }
    }
    if (mounted) {
      setState(() => _groupBotCommands = collected);
    }
  }

  void _syncScreenProtection(bool protect) {
    unawaited(
      ScreenProtectionService.instance.sync(_screenProtectionKey, protect),
    );
  }

  Future<void> _loadForumTopics() async {
    try {
      final res = await GroupsChannelsParityService.getTopics(widget.chatId);
      if (!mounted) return;
      ForumTopic? refreshedActive = _activeTopic;
      if (_activeTopic != null) {
        for (final t in res.topics) {
          if (t.id == _activeTopic!.id) {
            refreshedActive = t;
            break;
          }
        }
      }
      setState(() {
        _isForum = res.isForum || _isForum;
        _forumTopics = res.topics;
        _activeTopic = refreshedActive;
      });
      _updateTopBannerHeight();
    } catch (_) {}
  }

  Future<void> _switchToTopic(ForumTopic topic) async {
    if (_activeTopic?.id == topic.id) return;
    if (_isEditing) {
      _cancelEditing();
    } else {
      DraftService().flushDraft(_draftKey);
    }
    setState(() {
      _activeTopic = topic;
      _messages.clear();
      _messageReactions.clear();
      _myReactions.clear();
      _isLoading = true;
      _hasMoreMessages = true;
      _isDetachedHistoryWindow = false;
      _hasMoreNewerMessages = false;
      _updateFeedItems();
    });
    _restoreDraftForCurrentScope();
    _updateTopBannerHeight();
    await _loadMessages();
  }

  Future<void> _switchToFlatMessages() async {
    if (_activeTopic == null) return;
    if (_isEditing) {
      _cancelEditing();
    } else {
      DraftService().flushDraft(_draftKey);
    }
    setState(() {
      _activeTopic = null;
      _messages.clear();
      _messageReactions.clear();
      _myReactions.clear();
      _isLoading = true;
      _hasMoreMessages = true;
      _isDetachedHistoryWindow = false;
      _hasMoreNewerMessages = false;
      _updateFeedItems();
    });
    _restoreDraftForCurrentScope();
    _updateTopBannerHeight();
    await _loadMessages();
  }

  Future<void> _openForumTopicsScreen() async {
    final displayName = _groupName.isNotEmpty
        ? _groupName
        : (widget.groupName ?? 'Форум');
    final selection = await Navigator.of(context).push<ForumTopicSelectionResult>(
      SwipeBackPageRoute(
        builder: (_) => ForumTopicsScreen(
          chatId: widget.chatId,
          chatName: displayName,
          chatAvatar: widget.groupAvatar ?? _groupAvatar,
          myRole: _myRole,
          myAdminPermissions: _myAdminPermissions,
          defaultPermissions: _defaultPermissions,
          openedFromGroupChat: true,
        ),
      ),
    );
    if (!mounted) return;
    unawaited(_loadForumTopics());
    if (selection != null) {
      if (selection.topic != null) {
        await _switchToTopic(selection.topic!);
      } else if (selection.viewFlatMessages) {
        await _switchToFlatMessages();
      }
    }
  }

  Future<void> _loadSendAsPeers() async {
    if (_isGuestViewer) return;
    try {
      final res = await GroupsChannelsParityService.getSendAsPeers(
        widget.chatId,
      );
      if (!mounted) return;
      setState(() {
        _hasLoadedSendAsPeers = true;
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

  Future<void> _jumpToNextUnreadMention() async {
    final res = await GroupsChannelsParityService.getUnreadMentions(
      widget.chatId,
    );
    if (!mounted) return;
    if (res.messageIds.isEmpty) {
      setState(() => _unreadMentionsCount = res.count);
      return;
    }
    final targetId = res.messageIds.first;
    _scrollToMessage(targetId);
    final remaining = await GroupsChannelsParityService.markUnreadMentionsRead(
      widget.chatId,
      messageIds: [targetId],
    );
    if (mounted) {
      setState(() {
        _unreadMentionsCount = remaining ?? math.max(0, res.count - 1);
      });
    }
  }

  Future<void> _markAllMentionsRead() async {
    final remaining = await GroupsChannelsParityService.markUnreadMentionsRead(
      widget.chatId,
    );
    if (mounted) {
      setState(() => _unreadMentionsCount = remaining ?? 0);
    }
  }

  Future<void> _jumpToNextUnreadReaction() async {
    final res = await GroupsChannelsParityService.getUnreadReactions(
      widget.chatId,
    );
    if (!mounted) return;
    if (res.messageIds.isEmpty) {
      setState(() => _unreadReactionsCount = res.count);
      return;
    }
    final targetId = res.messageIds.first;
    _scrollToMessage(targetId);
    final remaining = await GroupsChannelsParityService.markUnreadReactionsRead(
      widget.chatId,
      messageIds: [targetId],
    );
    if (mounted) {
      setState(() {
        _unreadReactionsCount = remaining ?? math.max(0, res.count - 1);
      });
    }
  }

  Future<void> _markAllReactionsRead() async {
    final remaining = await GroupsChannelsParityService.markUnreadReactionsRead(
      widget.chatId,
    );
    if (mounted) {
      setState(() => _unreadReactionsCount = remaining ?? 0);
    }
  }

  void _maybeStartLocalSlowmode() {
    if (_slowModeInterval > 0 && _chatDetails?.isAdmin != true) {
      _startSlowmodeCountdown(_slowModeInterval);
    }
  }

  Future<void> _loadPinnedMessagesList() async {
    try {
      final list = await ChatService.getPinnedMessages(chatId: widget.chatId);
      if (!mounted) return;
      ChatInstantCache.instance.putPinnedMessages(widget.chatId, list);
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
    try {
      final items = await ChatService.getScheduledMessages(widget.chatId);
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

  void _onCallbackQueryAnswer(WebSocketEvent event) {
    if (!mounted) return;
    final text = event.data['text']?.toString();
    final showAlert = event.data['show_alert'] == true;
    final url = event.data['url']?.toString();
    if (url != null && url.isNotEmpty) {
      unawaited(LinkOpener.openUrl(context, url));
    }
    if (text == null || text.isEmpty) return;
    if (showAlert) {
      showTheavDialog<void>(
        context: context,
        title: 'Уведомление',
        message: text,
        actions: const [
          TheavDialogAction<void>(label: 'OK', isPrimary: true),
        ],
      );
    } else {
      GlassToastService().show(context, text, icon: Icons.info_outline);
    }
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
      final result = await ChatService.getMessages(
        chatId: widget.chatId,
        limit: 50,
        topicId: _activeTopicId,
      );
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
        _resolvePendingDraftReply(serverLoaded: true);

        try {
          db.saveMessages(serverMessages.map((m) => _messageToCompanion(m)).toList());
        } catch (e) {
          debugPrint('Drift saveMessages in group sync error: $e');
        }

        try {
          final unreadInfo = await ChatService.getUnreadInfo(chatId: widget.chatId);
          if (unreadInfo['success'] == true && mounted) {
            final serverUnreadCount = unreadInfo['unread_count'] as int? ?? 0;
            final mentionsCount =
                unreadInfo['unread_mentions_count'] as int? ?? _unreadMentionsCount;
            final reactionsCount =
                unreadInfo['unread_reactions_count'] as int? ?? _unreadReactionsCount;
            setState(() {
              _unreadCount = serverUnreadCount;
              _unreadMentionsCount = mentionsCount;
              _unreadReactionsCount = reactionsCount;
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
        _selectedMessageIds.removeAll(deletedIds);
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
      if (updatedCust != null) {
        final pIdx = _participants.indexWhere((p) => p.id == userId);
        if (pIdx != -1) {
          _participants[pIdx] = _participants[pIdx].copyWith(
            peerCustomization: updatedCust,
          );
        }
      }
      _updateFeedItems();
    });
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
    final dynamic replyMarkup = event.data['reply_markup'];

    final isPollEvent = event.data['message_type'] == 'poll' ||
        event.data['poll'] is Map ||
        (newMediaPayload != null &&
            (newMediaPayload.containsKey('poll_id') ||
                newMediaPayload.containsKey('options')));
    if (newContent == null &&
        newMediaPayload == null &&
        newEntities == null &&
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
            entities: newEntities ?? current.entities,
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
        newEntities != null && newEntities.isNotEmpty
            ? jsonEncode(newEntities.map((e) => e.toJson()).toList())
            : null,
        mergedPayloadForDb != null ? jsonEncode(mergedPayloadForDb) : null,
        effectiveIsEdited,
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

  void _onUnreadBadgesUpdated(WebSocketEvent event) {
    final mentions = int.tryParse(
      '${event.data['unread_mentions_count'] ?? ''}',
    );
    final reactions = int.tryParse(
      '${event.data['unread_reactions_count'] ?? ''}',
    );
    if (!mounted || (mentions == null && reactions == null)) return;
    setState(() {
      if (mentions != null) _unreadMentionsCount = mentions;
      if (reactions != null) _unreadReactionsCount = reactions;
    });
  }

  void _onNewMessage(WebSocketEvent event) {
    final messageData = (event.data['message'] as Map<String, dynamic>?) ??
        (event.data.containsKey('content') && event.data.containsKey('id')
            ? event.data
            : null);
    if (messageData == null) return;

    final message = Message.fromJson(messageData);

    if (_activeTopic != null) {
      final activeTid = _activeTopic!.id;
      final incomingTid = message.topicId;
      final bool isGeneralTopic =
          _activeTopic!.isGeneral || _activeTopic!.id == 1;
      final bool belongsToTopic = incomingTid != null
          ? incomingTid == activeTid
          : isGeneralTopic;
      if (!belongsToTopic) {
        try {
          AppDatabase().saveMessage(_messageToCompanion(message));
        } catch (_) {}
        if (_isForum) {
          unawaited(_loadForumTopics());
        }
        return;
      }
    }

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

  Future<void> _loadInlineDirectoryBots() async {
    final bots = await BotService.getBotsDirectory(inlineOnly: true);
    if (mounted && bots.isNotEmpty) {
      setState(() => _inlineDirectoryBots = bots);
    }
  }

  Future<void> _loadChatAppearance() async {
    final cfg = await DmParityService.getChatAppearance(widget.chatId);
    if (!mounted) return;
    final nextCfg = (cfg == null || cfg.isEmpty) ? null : cfg;
    if (nextCfg != null) {
      ChatInstantCache.instance.putAppearance(widget.chatId, nextCfg);
    }
    if (_chatAppearance?.themeId == nextCfg?.themeId &&
        _chatAppearance?.wallpaperUrl == nextCfg?.wallpaperUrl &&
        _chatAppearance?.accentColorId == nextCfg?.accentColorId) {
      return;
    }
    setState(() {
      _chatAppearance = nextCfg;
    });
  }

  void _updateMentionAutocompleteState() {
    if (!mounted) return;
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
    _onInputTextChanged(updated);
  }

  void _onControllerDraftSync() {
    _saveCurrentDraft();
    _updateMentionAutocompleteState();
  }

  void _onInputTextChanged(String text) {
    _saveCurrentDraft();

    if (_groupBotCommands.isNotEmpty) {
      final shouldShowCommands =
          text.startsWith('/') && !text.contains(' ') && !text.contains('\n');
      if (_isBotCommandsOpen != shouldShowCommands) {
        setState(() => _isBotCommandsOpen = shouldShowCommands);
      }
    }

    _inlineQueryController.onTextChanged(
      text,
      chatId: widget.chatId,
      chatType: 'group',
    );
    _updateMentionAutocompleteState();

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
        AppDatabase()
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

      AppDatabase().updateMessageReadAndListened(
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
    AppDatabase().updateMessageReadAndListened(
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
    // Start loading local Drift messages immediately without waiting for network calls
    final loadMessagesFuture = _loadMessages();

    // Get current user ID
    final userId = await AuthService.getUserId();
    if (mounted && userId != _currentUserId) {
      setState(() {
        _currentUserId = userId;
      });
    }

    try {
      final cachedChat = await AppDatabase().getChat(widget.chatId);
      if (cachedChat != null && mounted) {
        if (cachedChat.hasProtectedContent && !_hasProtectedContent) {
          setState(() => _hasProtectedContent = true);
          _syncScreenProtection(true);
        }
        if (cachedChat.isForum && !_isForum) {
          setState(() => _isForum = true);
          unawaited(_loadForumTopics());
        }
      }
    } catch (_) {}

    // Load chat details
    final chatResult = await ChatService.getChat(widget.chatId);
    if (chatResult['success'] == true && mounted) {
      final chat = chatResult['chat'] as ChatDetails;
      _applyChatDetails(chat);
      if (chat.pinnedMessage != null ||
          chat.pinnedMessageId != null ||
          chat.pinnedMessageIds.isNotEmpty) {
        unawaited(_loadPinnedMessagesList());
      }
      unawaited(_loadScheduledCount());
    }

    // Get unread info
    final unreadInfo = await ChatService.getUnreadInfo(chatId: widget.chatId);
    if (unreadInfo['success'] == true && mounted) {
      final serverUnread = unreadInfo['unread_count'] as int? ?? 0;
      final serverMentions =
          unreadInfo['unread_mentions_count'] as int? ?? _unreadMentionsCount;
      final serverReactions =
          unreadInfo['unread_reactions_count'] as int? ?? _unreadReactionsCount;
      setState(() {
        _unreadCount = serverUnread;
        _unreadMentionsCount = serverMentions;
        _unreadReactionsCount = serverReactions;
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

    // Ensure message loading has completed
    await loadMessagesFuture;

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
    final bool hadInitialMessages = _messages.isNotEmpty;
    if (_messages.isEmpty && !_isLoading) {
      setState(() => _isLoading = true);
    }

    // 1. Сначала загрузить из Drift (мгновенно, offline-first)
    final db = AppDatabase();
    List<DbMessage> localMessages = [];
    try {
      localMessages = await db.getMessages(
        widget.chatId,
        limit: 50,
        includeThreadComments: true,
        topicId: _activeTopicId,
      );
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

      final parsedLocal =
          fixedMessages.map((m) => Message.fromDbMessage(m)).toList();
      _sortMessagesDescending(parsedLocal);
      if (_activeTopicId == null) {
        ChatInstantCache.instance.putMessages(widget.chatId, parsedLocal);
      }

      if (_isLoading || !ChatInstantCache.messagesEqual(_messages, parsedLocal)) {
        setState(() {
          _isLoading = false;
          _messages.clear();
          _messages.addAll(parsedLocal);
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
      }
      _resolvePendingDraftReply();
      if (!hadInitialMessages &&
          widget.initialMessageId == null &&
          (_firstUnreadMessageId == null || _unreadCount == 0)) {
        _scrollToBottom();
      }
    }

    // 2. Затем загрузить с сервера (обновление)
    try {
      final result = await ChatService.getMessages(
        chatId: widget.chatId,
        limit: 50,
        topicId: _activeTopicId,
      );

      if (mounted) {
        if (result['success'] == true) {
          final serverMessages = result['messages'] as List<Message>;
          final nextHasMore =
              result['has_more'] as bool? ?? (serverMessages.length >= 50);

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
          if (_activeTopicId == null) {
            ChatInstantCache.instance.putMessages(widget.chatId, mergedList);
          }

          final bool needsUiUpdate = _isLoading ||
              _hasMoreMessages != nextHasMore ||
              !ChatInstantCache.messagesEqual(_messages, mergedList);

          if (needsUiUpdate) {
            setState(() {
              _isLoading = false;
              _hasMoreMessages = nextHasMore;
              _messages.clear();
              _messageReactions.clear();
              _myReactions.clear();
              _messages.addAll(mergedList);

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
          }
          _resolvePendingDraftReply(serverLoaded: true);

          // Сохранить в Drift для оффлайн-доступа
          try {
            db.saveMessages(
                serverMessages.map((m) => _messageToCompanion(m)).toList());
          } catch (e) {
            debugPrint('GroupChat: Drift saveMessages error: $e');
          }
        } else if (_isLoading) {
          setState(() => _isLoading = false);
        }
        if (!hadInitialMessages &&
            localMessages.isEmpty &&
            widget.initialMessageId == null &&
            (_firstUnreadMessageId == null || _unreadCount == 0)) {
          _scrollToBottom();
        }
      }
    } catch (e) {
      debugPrint('GroupChat: Error loading from server: $e');
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
      topicId: _activeTopicId,
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
        includeThreadComments: true,
        topicId: _activeTopicId,
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
    return msg.toCompanion(fallbackChatId: widget.chatId);
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
        _isSending) {
      return;
    }

    if (!_isEditing && _stagedForward != null && _canSendMessages) {
      final staged = _stagedForward!;
      setState(() => _stagedForward = null);
      final fwdRes = await ChatService.forwardMessages(
        toChatId: widget.chatId,
        fromChatId: staged.fromChatId,
        messageIds: staged.messages.map((m) => m.id).toList(),
        hideSender: staged.hideSender,
        hideCaption: staged.hideCaption,
        topicId: _activeTopicId,
        sendAsMode: _effectiveSendAsMode,
        sendAsChatId: _effectiveSendAsChannelId,
        sendAsAnonymous: _effectiveSendAsAnon,
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
    if (!_isEditing && !_canSendMessages) {
      if (mounted) {
        GlassToastService().show(
          context,
          'Отправка сообщений ограничена',
          iconWidget: iconoir.Lock(
            width: 18,
            height: 18,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        );
      }
      return;
    }
    if (!_isEditing &&
        _attachedFiles.isNotEmpty &&
        !_effectivePermissions.canSendMedia) {
      if (mounted) {
        GlassToastService().show(
          context,
          'Отправка медиа ограничена администратором',
          iconWidget: iconoir.Lock(
            width: 18,
            height: 18,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        );
      }
      return;
    }

    if (_isEditing && _editingMessageId != null) {
      final messageId = _editingMessageId!;
      _cancelEditing();
      try {
        final String effectiveText = text;
        final List<MessageEntity>? effectiveEntities =
            resolvedEntities.isNotEmpty ? resolvedEntities : null;

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
            GlassToastService().show(context, res['message'] ?? context.l10n.translate('chat_edit_error'));
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
    _suppressDraftSave = true;
    try {
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
        _pendingDraftReplyId = null;
        _isQuote = false;
        _quoteText = null;
        _quoteOffset = 0;
        _quoteLength = 0;
        _showUnreadDivider = false;
        _firstUnreadMessageId = null;
        _firstUnreadFeedIndex = -1;
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

    try {
      final String effectiveContentText = text;
      final List<MessageEntity> mergedEntities = [
        ...resolvedEntities,
        ..._pendingCustomEmojiEntities.where(
          (ce) =>
              ce.offset >= 0 &&
              ce.offset + ce.length <= effectiveContentText.length,
        ),
      ];
      _pendingCustomEmojiEntities.clear();
      final List<MessageEntity>? effectiveEntities =
          mergedEntities.isNotEmpty ? mergedEntities : null;
      final bool sendAnon = _effectiveSendAsAnon;
      final String sendMode = _effectiveSendAsMode;
      final String? sendChannelId = _effectiveSendAsChannelId;

      // CASE 1: MULTIPLE VISUAL ATTACHMENTS (ALBUM: chunked into batches of up to 10 items)
      if (!asDocument && _attachedFiles.length >= 2 && _attachedFiles.every((f) => _isMediaFile(f.path))) {
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
              isSilent: isSilent,
              sendAsMode: sendMode,
              sendAsAnonymous: sendAnon,
              hasMediaSpoiler: hasMediaSpoiler,
              topicId: _activeTopicId,
              sendAsChatId: sendChannelId,
            );

            // Fallback: If server album endpoint fails, send items sequentially with the same albumGroupedId
            if (res['success'] != true && (res['retry_after'] == null)) {
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
                  isSilent: isSilent,
                  sendAsMode: sendMode,
                  sendAsAnonymous: sendAnon,
                  hasMediaSpoiler: hasMediaSpoiler,
                  topicId: _activeTopicId,
                  sendAsChatId: sendChannelId,
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
              _maybeStartLocalSlowmode();
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
              final retryAfter = res['retry_after'];
              if (retryAfter is int && retryAfter > 0) {
                _startSlowmodeCountdown(retryAfter);
              }
              if (mounted) {
                GlassToastService().show(
                  context,
                  retryAfter is int && retryAfter > 0
                      ? 'Подождите $retryAfter сек. перед отправкой'
                      : (res['message']?.toString() ?? 'Failed to send album'),
                  iconWidget: iconoir.Clock(
                    width: 18,
                    height: 18,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
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
              isSilent: isSilent,
              sendAsMode: sendMode,
              sendAsAnonymous: sendAnon,
              hasMediaSpoiler: hasMediaSpoiler,
              topicId: _activeTopicId,
              sendAsChatId: sendChannelId,
            );
            if (res['success'] == true && res['message'] is Message) {
              _maybeStartLocalSlowmode();
              final sent = res['message'] as Message;
              final existingIdx = _messages.indexWhere((m) => m.id == sent.id);
              if (existingIdx != -1) {
                _messages[existingIdx] = sent;
              } else {
                _messages.insert(0, sent);
              }
              _updateFeedItems();
              await AppDatabase().saveMessage(_messageToCompanion(sent));
            } else {
              final retryAfter = res['retry_after'];
              if (retryAfter is int && retryAfter > 0) {
                _startSlowmodeCountdown(retryAfter);
              }
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

          final fileMessageType = asDocument ? 'file' : (isVideo ? 'video' : (isImg ? 'image' : _getMessageTypeFromMimeType(uploadResult.mimeType)));
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
            isSilent: isSilent,
            sendAsMode: sendMode,
            sendAsAnonymous: sendAnon,
            hasMediaSpoiler: hasMediaSpoiler,
            topicId: _activeTopicId,
            sendAsChatId: sendChannelId,
          );
          if (res['success'] == true && res['message'] is Message) {
            _maybeStartLocalSlowmode();
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
          } else {
            final retryAfter = res['retry_after'];
            if (retryAfter is int && retryAfter > 0) {
              _startSlowmodeCountdown(retryAfter);
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

        messageType = asDocument
            ? 'file'
            : (isVideo ? 'video' : _getMessageTypeFromMimeType(uploadResult.mimeType));
        content = effectiveContentText;
        fileUrl = uploadResult.url;
        fileName = uploadResult.fileName;

        _clearAttachedFiles();
      }

      final syncService = SyncService();
      final activeSendAsPeer = _activeSendAsPeer;
      final bool sendingAsChannel =
          sendMode == 'channel' &&
          sendChannelId != null &&
          sendChannelId.isNotEmpty;
      final String? pendingSenderName = sendingAsChannel
          ? activeSendAsPeer?.name
          : (sendAnon
                ? (_groupName.isNotEmpty
                      ? _groupName
                      : (widget.groupName ?? 'Group'))
                : null);
      final String? pendingSenderAvatar = sendingAsChannel
          ? activeSendAsPeer?.avatarUrl
          : (sendAnon ? (_groupAvatar ?? widget.groupAvatar) : null);
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
          hasMediaSpoiler: hasMediaSpoiler,
          isSilent: isSilent,
          senderName: pendingSenderName,
          senderAvatarUrl: pendingSenderAvatar,
          isFromAnonymousAdmin: !sendingAsChannel && sendAnon,
          topicId: _activeTopicId,
          senderChatId: sendingAsChannel ? sendChannelId : null,
          senderChatName: sendingAsChannel ? activeSendAsPeer?.name : null,
          senderChatAvatarUrl:
              sendingAsChannel ? activeSendAsPeer?.avatarUrl : null,
          isOwn: true,
        );
      } catch (e) {
        debugPrint('SyncService createPendingMessage error: $e');
      }

      if (pendingMsg != null && mounted) {
        pendingLocalId = pendingMsg.localId;
        final profileTheme = context.read<ProfileThemeProvider>();
        var message = Message.fromDbMessage(pendingMsg).copyWith(
          senderName: pendingSenderName,
          senderAvatarUrl: pendingSenderAvatar,
          senderRole: sendingAsChannel ? null : _myRole,
          senderAdminTitle: sendingAsChannel
              ? null
              : (_myAdminTitle.isNotEmpty ? _myAdminTitle : null),
          isFromAnonymousAdmin: !sendingAsChannel && sendAnon,
          topicId: _activeTopicId,
          senderChatId: sendingAsChannel ? sendChannelId : null,
          senderChatName: sendingAsChannel ? activeSendAsPeer?.name : null,
          senderChatAvatarUrl:
              sendingAsChannel ? activeSendAsPeer?.avatarUrl : null,
          isOwn: true,
        );
        if (replyTo != null) {
          final isPersonaOrChannel = replyTo.isChannelOrPersonaAuthored;
          final isReplyToMe = !isPersonaOrChannel &&
              replyTo.senderId.isNotEmpty &&
              replyTo.senderId != '0' &&
              replyTo.senderId == _currentUserId;
          final fallbackTitle = _groupName.isNotEmpty
              ? _groupName
              : widget.groupName;
          message = message.copyWith(
            replyInfo: ReplyInfo(
              messageId: replyTo.id,
              senderId: isPersonaOrChannel ? '0' : replyTo.senderId,
              senderName: replyTo.resolveEffectiveAuthorTitle(
                chatName: fallbackTitle,
              ),
              content: replyTo.content,
              messageType: replyTo.messageType,
              entities: replyTo.entities,
              nameColorPresetId: isReplyToMe
                  ? profileTheme.currentNameColorPreset.id
                  : (isPersonaOrChannel
                        ? 'name_red'
                        : (replyTo.senderNameColorId ?? 'name_red')),
              replyStripStyle: isReplyToMe
                  ? profileTheme.currentStripStyle.name
                  : (isPersonaOrChannel
                        ? 'solid'
                        : (replyTo.senderReplyStripStyle ?? 'solid')),
              replyEmoji: isReplyToMe
                  ? profileTheme.currentReplyEmoji
                  : (isPersonaOrChannel
                        ? null
                        : PeerCustomizationCache.instance
                              .getSync(replyTo.senderId)
                              ?.replyEmoji),
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
            isSilent: isSilent,
            sendAsMode: sendMode,
            sendAsAnonymous: sendAnon,
            hasMediaSpoiler: hasMediaSpoiler,
            topicId: _activeTopicId,
            sendAsChatId: sendChannelId,
          );

          if (result['success'] == true) {
            _maybeStartLocalSlowmode();
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
                  _mergeConfirmedPendingMessage(
                    pendingLocalId: pendingLocalId,
                    serverId: serverId,
                    buildMerged: (existing) {
                      if (sentMessage is Message) {
                        return sentMessage.copyWith(
                          localId: pendingLocalId,
                          sendStatus: 1, // sent
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
                      }
                      return existing.copyWith(
                        id: serverId,
                        sendStatus: 1, // sent
                      );
                    },
                  );
                });
              }
            }
          } else {
            final errMsg = result['message']?.toString() ?? 'Failed to send message';
            final retryAfter = result['retry_after'];
            if (retryAfter is int && retryAfter > 0) {
              _startSlowmodeCountdown(retryAfter);
            }
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
              GlassToastService().show(
                context,
                retryAfter is int && retryAfter > 0
                    ? 'Подождите $retryAfter сек. перед отправкой'
                    : errMsg,
                iconWidget: retryAfter is int && retryAfter > 0
                    ? iconoir.Clock(
                        width: 18,
                        height: 18,
                        color: Theme.of(context).colorScheme.onSurface,
                      )
                    : iconoir.WarningCircle(
                        width: 18,
                        height: 18,
                        color: Theme.of(context).colorScheme.error,
                      ),
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
            GlassToastService().show(context, 'Failed to send message: $e');
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
          isSilent: isSilent,
          sendAsMode: sendMode,
          sendAsAnonymous: sendAnon,
          hasMediaSpoiler: hasMediaSpoiler,
          topicId: _activeTopicId,
          sendAsChatId: sendChannelId,
        );

        if (mounted) {
          if (result['success'] == true) {
            _maybeStartLocalSlowmode();
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
            final retryAfter = result['retry_after'];
            if (retryAfter is int && retryAfter > 0) {
              _startSlowmodeCountdown(retryAfter);
            }
            setState(() => _isSending = false);
            GlassToastService().show(
              context,
              retryAfter is int && retryAfter > 0
                  ? 'Подождите $retryAfter сек. перед отправкой'
                  : (result['message']?.toString() ?? 'Failed to send message'),
              iconWidget: iconoir.Clock(
                width: 18,
                height: 18,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('[GroupChatScreen] Error in _sendMessage: $e');
      if (mounted) {
        GlassToastService().show(context, 'Failed to send: $e');
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
    if (!_canSendMessages) return;
    final bool allowMedia = _effectivePermissions.canSendMedia;
    final bool allowPolls = _effectivePermissions.canSendPolls;
    if (!allowMedia) {
      if (allowPolls) {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => PollCreateScreen(
              chatId: widget.chatId,
              topicId: _activeTopicId,
              sendAsMode: _effectiveSendAsMode,
              sendAsChatId: _effectiveSendAsChannelId,
              sendAsAnonymous: _effectiveSendAsAnon,
              replyToMessageId: _replyToMessage?.id,
            ),
          ),
        );
      } else if (mounted) {
        GlassToastService().show(
          context,
          'Отправка медиа ограничена',
          iconWidget: iconoir.Lock(
            width: 18,
            height: 18,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        );
      }
      return;
    }
    final result = await AttachmentPickerBottomSheet.show(
      context,
      allowPoll: allowPolls,
    );
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
            builder: (_) => PollCreateScreen(
              chatId: widget.chatId,
              topicId: _activeTopicId,
              sendAsMode: _effectiveSendAsMode,
              sendAsChatId: _effectiveSendAsChannelId,
              sendAsAnonymous: _effectiveSendAsAnon,
              replyToMessageId: _replyToMessage?.id,
            ),
          ),
        );
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
              chatId: widget.chatId,
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
        GlassToastService().show(context, 'Failed to pick audio: $e');
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

    if (result == null || result.files.isEmpty || !mounted) return;

    if (result.scheduleAt != null) {
      setState(() => _isUploading = true);
      try {
        for (int i = 0; i < result.files.length; i++) {
          final file = result.files[i];
          final uploadResult = await _fileService.uploadFileChunked(file);
          final isVideo = _isVideoFile(file.path);
          final msgType = result.asDocument
              ? 'file'
              : (isVideo
                  ? 'video'
                  : (_isImageFile(file.path)
                      ? 'image'
                      : _getMessageTypeFromMimeType(uploadResult.mimeType)));
          final caption = result.captionsByPath[file.path] ??
              (i == 0 ? (result.caption ?? '') : '');
          await ChatService.createScheduledMessage(
            chatId: widget.chatId,
            content: caption,
            messageType: msgType,
            scheduleAt: result.scheduleAt,
            fileUrl: uploadResult.url,
            fileName: uploadResult.fileName,
            hasMediaSpoiler: result.hasMediaSpoiler,
            mediaPayload: uploadResult.toMediaPayload(),
            isSilent: result.isSilent,
            topicId: _activeTopicId,
            sendAsMode: _effectiveSendAsMode,
            sendAsChatId: _effectiveSendAsChannelId,
            sendAsAnonymous: _effectiveSendAsAnon,
          );
        }
        unawaited(_loadScheduledCount());
        if (mounted) {
          GlassToastService().show(context, 'Медиа запланировано');
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
        GlassToastService().show(context, 'Failed to pick $type: $e');
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
        GlassToastService().show(context, 'Failed to take photo: $e');
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
        GlassToastService().show(context, 'Failed to pick document: $e');
      }
    }
  }

  void _openFile(String fileUrl, String fileName, String messageType) {
    if (messageType == 'image') {
      FullscreenPhotoViewer.open(context, fileUrl);
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
              _downloadAndOpenFile(fileUrl, fileName);
            },
          ),
          TheavListRow(
            leading: const iconoir.Download(width: 20, height: 20),
            title: context.l10n.translate('chat_download'),
            onTap: () {
              Navigator.pop(sheetCtx);
              _downloadFile(fileUrl, fileName);
            },
          ),
          TheavListRow(
            leading: const iconoir.ShareAndroid(width: 20, height: 20),
            title: context.l10n.translate('share'),
            onTap: () async {
              Navigator.pop(sheetCtx);
              await SharePlus.instance.share(
                ShareParams(text: fileUrl, subject: fileName),
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
        } else {
          if (mounted) {
            GlassToastService().show(context, 'Не удалось открыть файл');
          }
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
        final uri = Uri.parse(AppConfig.resolveMediaUrl(fileUrl) ?? fileUrl);
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
    list.sort((a, b) {
      final cmp = b.createdAtEpochMs.compareTo(a.createdAtEpochMs);
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
          topicId: _activeTopicId,
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
        topicId: _activeTopicId,
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
        topicId: _activeTopicId,
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

  double _lastStickyDateEvalOffset = -1000.0;

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
        final key = _messageKeys[_feedItems[i].id];
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
        final oldestItemKey = _messageKeys[_feedItems[span.oldestIdx].id];
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
                final k = _messageKeys[_feedItems[i].id];
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
        GlassToastService().show(
          context,
          result['message'] ?? 'У вас нет доступа к этому сообщению',
          isError: true,
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
    if (!_canSendMessages) {
      GlassToastService().show(
        context,
        _isGuestViewer
            ? 'Вступите в группу, чтобы отвечать'
            : 'Отправка сообщений ограничена',
        iconWidget: iconoir.Lock(
          width: 18,
          height: 18,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      );
      return;
    }
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
    if (!_canSendMessages) {
      GlassToastService().show(
        context,
        _isGuestViewer
            ? 'Вступите в группу, чтобы цитировать'
            : 'Отправка сообщений ограничена',
        iconWidget: iconoir.Lock(
          width: 18,
          height: 18,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      );
      return;
    }
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

  String _formatTime(String timestamp) {
    return DateTimeUtils.formatTimeHHmm(timestamp);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _entrySettleTimer?.cancel();
    _syncDebounceTimer?.cancel();
    _transitionTimer?.cancel();
    _stickyDateStateNotifier.dispose();
    _emojiPanelController.dispose();
    StickerService.instance.unregisterInputTarget(_stickerInputTarget);
    _inputFocusNode.removeListener(_onFocusChanged);
    DeepLinkService.pendingInlinePrefill.removeListener(
      _onPendingInlinePrefillChanged,
    );
    TilingLayoutController.instance.removeListener(_onTilingLayoutChanged);
    if (_isDesktopPlatform) {
      HardwareKeyboard.instance.removeHandler(_handleGlobalDesktopKeyEvent);
    }

    // Flush any pending mark-as-read and draft before leaving
    _markReadTimer?.cancel();
    _flushMarkRead();
    if (_activeTopicId == null &&
        !_isDetachedHistoryWindow &&
        _messages.isNotEmpty) {
      ChatInstantCache.instance.putMessages(widget.chatId, _messages);
    }
    if (!_isEditing) {
      DraftService().flushDraft(_draftKey);
    }
    _draftRemoteSub?.cancel();

    _showScrollDownFabNotifier.dispose();
    _uploadProgressNotifier.dispose();
    _stopMyTyping();
    _stopRecordingActionBroadcast();
    _messageController.dispose();
    _inlineQueryController.dispose();
    _scrollController.dispose();
    _inputFocusNode.dispose();
    _chatSubscription?.cancel();
    _realtimeSub?.cancel();
    _typingTimer?.cancel();
    _slowmodeTimer?.cancel();
    _liveLocationTimer?.cancel();

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
    unawaited(ScreenProtectionService.instance.release(_screenProtectionKey));

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
          ChatInstantCache.instance.setInputHeight(widget.chatId, newHeight);
          setState(() {
            _inputHeight = newHeight;
          });
        }
      }
    });
  }

  void _updateTopBannerHeight() {
    if (_topBannerHeightCheckScheduled) return;
    _topBannerHeightCheckScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _topBannerHeightCheckScheduled = false;
      if (!mounted) return;
      final RenderBox? renderBox =
          _topBannerKey.currentContext?.findRenderObject() as RenderBox?;
      if (renderBox != null && renderBox.hasSize) {
        final newHeight = renderBox.size.height;
        if ((newHeight - _topBannerHeight).abs() > 0.5) {
          setState(() {
            _topBannerHeight = newHeight;
          });
        }
      } else if (_topBannerHeight != 0.0) {
        setState(() {
          _topBannerHeight = 0.0;
        });
      }
    });
  }

  Future<void> _openGroupInfo() async {
    final displayName =
        widget.groupName ?? (_groupName.isNotEmpty ? _groupName : 'Group');
    final heroTag = 'chat_avatar_${widget.chatId}';
    await Navigator.push(
      context,
      SwipeBackPageRoute(
        builder: (_) => GroupInfoScreen(
          chatId: widget.chatId,
          groupName: displayName,
          groupAvatar: widget.groupAvatar ?? _groupAvatar,
          heroTag: heroTag,
          onJumpToMessageId: (msgId) => _scrollToMessage(msgId),
        ),
      ),
    );
    if (mounted) {
      setState(() {
        _isMuted = NotificationSettingsProvider().isChatMuted(
          widget.chatId,
          chatType: 'group',
        );
      });
      unawaited(_refreshChatDetails());
    }
  }

  Future<void> _joinPublicGroup() async {
    if (_isJoiningGroup) return;
    HapticUtils.tap();
    setState(() => _isJoiningGroup = true);
    try {
      final joined = await ChatService.joinPublicChatModel(widget.chatId);
      if (!mounted) return;
      if (joined != null) {
        setState(() {
          _isMember = true;
          if (_myRole == null || _myRole == 'guest') {
            _myRole = 'member';
          }
        });
        await _refreshChatDetails();
        await _loadData();
      } else {
        GlassToastService().show(
          context,
          'Не удалось вступить в группу',
          iconWidget: iconoir.WarningCircle(
            width: 18,
            height: 18,
            color: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } catch (e) {
      debugPrint('GroupChatScreen: joinPublicChatModel error: $e');
      if (mounted) {
        GlassToastService().show(
          context,
          'Ошибка при вступлении в группу',
          iconWidget: iconoir.WarningCircle(
            width: 18,
            height: 18,
            color: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isJoiningGroup = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    _updateInputHeight();
    _updateTopBannerHeight();
    final displayName = widget.groupName ?? (_groupName.isNotEmpty ? _groupName : 'Group');

    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final bool isKeyboardVisible = bottomInset > 0;

    final int onlineCount = _participants.where((p) => p.isOnline).length;
    final int memberCount =
        (_chatDetails != null && _chatDetails!.effectiveMemberCount > 0)
            ? _chatDetails!.effectiveMemberCount
            : (_participants.isNotEmpty
                ? _participants.length
                : _cachedMemberCount);
    final bool canStartOrJoinCall = _chatDetails == null ||
        _chatDetails!.hasActiveCall ||
        _chatDetails!.canManageCallsEffective;
    void openGroupCall() {
      if (!canStartOrJoinCall) {
        GlassToastService().showError(
          context,
          'Начать голосовой чат могут только администраторы',
        );
        return;
      }
      Navigator.of(context, rootNavigator: true).push(
        MaterialPageRoute(
          builder: (_) => GroupCallScreen(
            callId: widget.chatId,
            chatId: widget.chatId,
            userId: _currentUserId ?? 'local',
            title: displayName,
          ),
        ),
      );
    }

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
          .replaceAll('{count}', memberCount.toString())
          .replaceAll('{online}', onlineCount.toString());
    } else {
      statusSubtitle = context.l10n
          .translate('chat_status_members_count')
          .replaceAll('{count}', memberCount.toString());
    }

    final String heroTag = 'chat_avatar_${widget.chatId}';

    return ChatScaffold(
      swipeBackBlocked:
          _isSelectionMode || _isVoiceRecording || _isVideoRecording,
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
                isVerified: _isVerified,
                statusText: (!_isTyping && _activeTopic != null)
                    ? '${_activeTopic!.title} · $statusSubtitle'
                    : ((!_isTyping &&
                            widget.communityName != null &&
                            widget.communityName!.isNotEmpty)
                        ? '${widget.communityName} · $statusSubtitle'
                        : statusSubtitle),
                statusColor: _isTyping
                    ? (Theme.of(context).brightness == Brightness.dark
                        ? const Color(0xFF5CB8E6)
                        : Theme.of(context).colorScheme.primary)
                    : null,
                isChannel: false,
                isMuted: _isMuted,
                heroTag: heroTag,
                profileScreenBuilder: (_) => GroupInfoScreen(
                  chatId: widget.chatId,
                  groupName: displayName,
                  groupAvatar: widget.groupAvatar ?? _groupAvatar,
                  heroTag: heroTag,
                  onJumpToMessageId: (msgId) => _scrollToMessage(msgId),
                ),
                onBack: () => TilingLayoutController.popOrCloseChatTile(context),
                onTitleTap: _openGroupInfo,
                onViewProfile: _openGroupInfo,
                onVoiceCall: openGroupCall,
                onVideoCall: openGroupCall,
                onSearch: () {
                  ChatActionsHelper.openSearch(
                    context: context,
                    chatId: widget.chatId,
                    chatName: displayName,
                    onMessageSelected: (msgId) => _scrollToMessage(msgId),
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
                  unawaited(
                    showAbuseReportSheet(
                      context,
                      chatId: widget.chatId,
                    ),
                  );
                },
                autoDeleteSeconds: _autoDeleteSeconds,
                onAutoDelete: _isAdmin ? _openAutoDeleteSheet : null,
                onChatAppearance: _openChatAppearanceSheet,
                isSelectionMode: _isSelectionMode,
                selectedCount: _selectedMessageIds.length,
                hasProtectedContent: _hasProtectedContent,
                onCancelSelection: _clearSelection,
                onReplySelected: (_selectedMessageIds.length == 1 && _canSendMessages)
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
                onDeleteSelected:
                    _canDeleteSelectedMessages ? _deleteSelectedMessages : null,
                extraMenuItems: [
                  if (_isForum)
                    FloatingChatMenuItem(
                      label: 'Темы форума',
                      iconBuilder: (c) => iconoir.ChatLines(
                        color: c,
                        width: 20,
                        height: 20,
                      ),
                      onTap: _openForumTopicsScreen,
                    ),
                  if (widget.onOpenCommunityChannels != null)
                    FloatingChatMenuItem(
                      label: 'Каналы сообщества',
                      iconBuilder: (c) => iconoir.List(
                        color: c,
                        width: 20,
                        height: 20,
                      ),
                      onTap: widget.onOpenCommunityChannels!,
                    ),
                  if (widget.onOpenCommunityMembers != null)
                    FloatingChatMenuItem(
                      label: 'Участники',
                      iconBuilder: (c) => iconoir.Group(
                        color: c,
                        width: 20,
                        height: 20,
                      ),
                      onTap: widget.onOpenCommunityMembers!,
                    ),
                  if (widget.onOpenCommunitySettings != null)
                    FloatingChatMenuItem(
                      label: 'Настройки сообщества',
                      iconBuilder: (c) => iconoir.Settings(
                        color: c,
                        width: 20,
                        height: 20,
                      ),
                      onTap: widget.onOpenCommunitySettings!,
                    ),
                ],
              );
        },
      ),
      body: Stack(
        children: [
          _buildChatTab(),
          Positioned(
            top: MediaQuery.paddingOf(context).top + kFloatingAppBarTotalHeight,
            left: 0,
            right: 0,
            child: Column(
              key: _topBannerKey,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_isForum && _forumTopics.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: ForumTopicChipStrip(
                      topics: _forumTopics,
                      activeTopicId: _activeTopic?.id ??
                          _forumTopics
                              .firstWhere(
                                (t) => t.isGeneral,
                                orElse: () => _forumTopics.first,
                              )
                              .id,
                      onSelectTopic: _switchToTopic,
                      onViewAllTopics: _openForumTopicsScreen,
                    ),
                  ),
                LiveChatCallBanner(
                  chatId: widget.chatId,
                  chatTitle: displayName,
                  currentUserId: _currentUserId ?? '',
                  isChannel: false,
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
                          chatId: widget.chatId,
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
                  chatId: widget.chatId,
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
          ),
        ],
      ),
    );
  }

  Widget _buildChatTab() {
    final topPadding = MediaQuery.paddingOf(context).top +
        kFloatingAppBarTotalHeight +
        _topBannerHeight +
        8.0;
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

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
            MediaQuery.viewInsetsOf(context).bottom == 0 &&
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

        final displayName =
            widget.groupName ?? (_groupName.isNotEmpty ? _groupName : 'Group');
        final bool showHistoryStartIntro = !_isLoading &&
            !_isLoadingMore &&
            !_hasMoreMessages &&
            !_isDetachedHistoryWindow &&
            _feedItems.isNotEmpty;

        final Widget messageList = (!_isLoading && _feedItems.isEmpty)
            ? Padding(
                padding: EdgeInsets.only(
                  top: topPadding,
                  bottom: _inputHeight + effectiveBottom + 8,
                ),
                child: Center(
                  child: SingleChildScrollView(
                    child: TelegramChatCreatedIntroCard(
                      isChannel: false,
                      title: displayName,
                      description: _groupDescription,
                    ),
                  ),
                ),
              )
            : ChatMessagesListView(
                isLoading: _isLoading,
                isLoadingMore: _isLoadingMore,
                itemCount: showHistoryStartIntro
                    ? _feedItems.length + 1
                    : _feedItems.length,
                scrollController: _scrollController,
                topPadding: topPadding,
                bottomPadding: _inputHeight + effectiveBottom + 8,
                itemBuilder: (context, index) => _buildFeedItem(
                  index,
                  displayName: displayName,
                ),
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
                      onNeedsSync: _scheduleStickyDateUpdate,
                    );
                  },
                ),
              ),
            ),
            // Нижний scroll edge блюр: ПОД полем ввода (над сообщениями, но под полем ввода)
            ChatBottomScrollEdge(
              height: math.max(safeBottom + 52.0, 52.0),
            ),
            if (_showEmojiPanel && _canSendMessages)
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
                      onStickerSelected: _sendStickerMessage,
                      onGifSelected: _sendGifMessage,
                      emojiOnly: !_effectivePermissions.canSendStickersGifs,
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
            Positioned(
              right: 14,
              bottom: _inputHeight + 10 + effectiveBottom,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  UnreadJumpFabsColumn(
                    unreadMentionsCount: _unreadMentionsCount,
                    unreadReactionsCount: _unreadReactionsCount,
                    onMentionsTap: _jumpToNextUnreadMention,
                    onMentionsLongPress: _markAllMentionsRead,
                    onReactionsTap: _jumpToNextUnreadReaction,
                    onReactionsLongPress: _markAllReactionsRead,
                  ),
                  if (_unreadMentionsCount > 0 || _unreadReactionsCount > 0)
                    const SizedBox(height: 10),
                  ValueListenableBuilder<bool>(
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
                ],
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
    );
  }

  String _formatRestrictionUntil(DateTime until) {
    final local = until.toLocal();
    final now = DateTime.now();
    final hh = local.hour.toString().padLeft(2, '0');
    final mm = local.minute.toString().padLeft(2, '0');
    final sameDay =
        local.year == now.year && local.month == now.month && local.day == now.day;
    if (sameDay) {
      return '$hh:$mm';
    }
    final dd = local.day.toString().padLeft(2, '0');
    final mo = local.month.toString().padLeft(2, '0');
    return '$dd.$mo $hh:$mm';
  }

  Widget _buildGlassCapsuleBar({
    Key? key,
    required Widget child,
    VoidCallback? onTap,
    Color? accentTint,
  }) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final glassProvider = LiquidGlassProvider.maybeOf(context);
    final bool glassEnabled = glassProvider?.enabled ?? false;
    final bool isLite = glassProvider?.isLite ?? false;

    final Widget interactiveChild = onTap != null
        ? Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(22),
              onTap: onTap,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  child: Center(child: child),
                ),
              ),
            ),
          )
        : ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              child: Center(child: child),
            ),
          );

    final Widget capsule;
    if (glassEnabled && glassProvider != null) {
      capsule = LiquidGlassLens(
        style: glassProvider.createStyle(
          context: context,
          cornerRadius: 22,
          refractionIndex: 1.1,
          refractionWidth: 20,
          isLiteOverride: isLite,
        ),
        child: Container(
          decoration: accentTint != null
              ? BoxDecoration(
                  color: accentTint.withValues(alpha: isDark ? 0.16 : 0.10),
                  borderRadius: BorderRadius.circular(22),
                )
              : null,
          child: interactiveChild,
        ),
      );
    } else {
      final Color baseBg = isDark
          ? Colors.black.withValues(alpha: 0.70)
          : Colors.white.withValues(alpha: 0.85);
      final Color effectiveBg = accentTint != null
          ? Color.alphaBlend(
              accentTint.withValues(alpha: isDark ? 0.18 : 0.10),
              baseBg,
            )
          : baseBg;
      capsule = ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter.grouped(
          filter: BlurUtils.createDownsampledBlur(12),
          child: Container(
            decoration: BoxDecoration(
              color: effectiveBg,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.14)
                    : Colors.black.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
            child: interactiveChild,
          ),
        ),
      );
    }

    return Padding(
      key: key,
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: capsule,
    );
  }

  Widget _buildBottomBar(String displayName) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final disableAnimations = MediaQuery.disableAnimationsOf(context);
    final Color primaryAccent = isDark
        ? const Color(0xFF7DD3FC)
        : const Color(0xFF0369A1);
    final Color mutedTextColor = isDark
        ? Colors.white.withValues(alpha: 0.90)
        : const Color(0xFF1E293B);

    final Widget barChild;
    if (_isGuestViewer) {
      barChild = _buildGlassCapsuleBar(
        key: const ValueKey('group_bottom_guest_join'),
        accentTint: primaryAccent,
        onTap: _isJoiningGroup ? null : _joinPublicGroup,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_isJoiningGroup)
              SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: primaryAccent,
                ),
              )
            else
              iconoir.Group(
                width: 18,
                height: 18,
                color: primaryAccent,
              ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Вступить в группу',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: primaryAccent,
                ),
              ),
            ),
          ],
        ),
      );
    } else if (_isActiveTopicClosed) {
      barChild = _buildGlassCapsuleBar(
        key: const ValueKey('group_bottom_topic_closed'),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconoir.Lock(
              width: 16,
              height: 16,
              color: mutedTextColor,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Тема закрыта администраторами',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: mutedTextColor,
                ),
              ),
            ),
          ],
        ),
      );
    } else if (widget.communityReadOnly) {
      barChild = _buildGlassCapsuleBar(
        key: const ValueKey('group_bottom_community_readonly'),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconoir.Lock(
              width: 16,
              height: 16,
              color: mutedTextColor,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                widget.communityReadOnlyReason ?? 'Только для чтения',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: mutedTextColor,
                ),
              ),
            ),
          ],
        ),
      );
    } else if (!_effectivePermissions.canSendMessages) {
      final hasUntil = _restrictedUntil != null &&
          DateTime.now().isBefore(_restrictedUntil!);
      final label = hasUntil
          ? 'Отправка сообщений ограничена до ${_formatRestrictionUntil(_restrictedUntil!)}'
          : 'Отправка сообщений ограничена';
      barChild = _buildGlassCapsuleBar(
        key: const ValueKey('group_bottom_restricted'),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconoir.Lock(
              width: 16,
              height: 16,
              color: mutedTextColor,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13.5,
                  fontWeight: FontWeight.w500,
                  color: mutedTextColor,
                ),
              ),
            ),
          ],
        ),
      );
    } else {
      barChild = KeyedSubtree(
        key: const ValueKey('group_bottom_input'),
        child: _buildMessageInput(),
      );
    }

    return AnimatedSize(
      duration:
          disableAnimations ? Duration.zero : const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: barChild,
    );
  }

  Message? _feedItemMessage(int idx) {
    if (idx < 0 || idx >= _feedItems.length) return null;
    final item = _feedItems[idx];
    if (item is FeedSingleItem) return item.message;
    if (item is FeedAlbumItem) return item.album.primaryMessage;
    return null;
  }

  ChatParticipant? _findParticipant(String senderId) {
    if (senderId.isEmpty) return null;
    for (final p in _participants) {
      if (p.id == senderId) return p;
    }
    return null;
  }

  Color _resolveSenderNameColor(Message message) {
    final colorId = message.senderNameColorId ??
        _findParticipant(message.senderId)
            ?.peerCustomization
            ?.nameColorPresetId;
    if (colorId != null && colorId.isNotEmpty) {
      return NameColorPresets.getById(colorId).primaryColor;
    }
    final idx =
        message.senderId.hashCode.abs() % NameColorPresets.defaults.length;
    return NameColorPresets.defaults[idx].primaryColor;
  }

  void _openUserProfileById(String userId) {
    if (userId.isEmpty || userId == '0') return;
    HapticUtils.tap();
    final participant = _findParticipant(userId);
    Navigator.push(
      context,
      SwipeBackPageRoute(
        builder: (_) => ProfileScreen(
          entityType: ProfileEntityType.user,
          userId: userId,
          initialName: participant?.displayName,
          initialAvatarUrl: participant?.avatarUrl,
          initialIsOnline: participant?.isOnline,
          initialLastSeen: participant?.lastSeen,
        ),
      ),
    );
  }

  void _openSenderProfile(Message message) {
    if (message.isFromAnonymousAdmin) {
      _openGroupInfo();
      return;
    }
    if (message.senderId.isEmpty || message.senderId == '0') return;
    HapticUtils.tap();
    final participant = _findParticipant(message.senderId);
    Navigator.push(
      context,
      SwipeBackPageRoute(
        builder: (_) => ProfileScreen(
          entityType: ProfileEntityType.user,
          userId: message.senderId,
          initialName: participant?.displayName.isNotEmpty == true
              ? participant!.displayName
              : message.senderName,
          initialAvatarUrl: participant?.avatarUrl ?? message.senderAvatarUrl,
          initialIsOnline: participant?.isOnline,
          initialLastSeen: participant?.lastSeen,
        ),
      ),
    );
  }

  Widget _buildFeedItem(int index, {String? displayName}) {
    if (index == _feedItems.length &&
        !_hasMoreMessages &&
        !_isDetachedHistoryWindow &&
        !_isLoadingMore) {
      final title = displayName ??
          (widget.groupName ?? (_groupName.isNotEmpty ? _groupName : 'Group'));
      return TelegramChatCreatedIntroCard(
        isChannel: false,
        title: title,
        description: _groupDescription,
      );
    }
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

  Widget? _buildAlbumReplyOrForwardWidget(Message message, bool isMe) {
    final theme = Theme.of(context);
    final Color subtextColor = isMe
        ? theme.colorScheme.onPrimary.withValues(alpha: 0.76)
        : theme.colorScheme.onSurface.withValues(alpha: 0.65);

    if (message.hasReply) {
      final Widget baseReply = MessageReplyInfo(
        replyInfo: message.replyInfo,
        isQuote: message.isQuote,
        quoteText: message.quoteText,
        quoteOffset: message.quoteOffset,
        quoteLength: message.quoteLength,
        isMe: isMe,
        currentUserId: _currentUserId,
        onTap: _isSelectionMode
            ? null
            : () => _handleReplyTap(
                  message.replyToMessageId!,
                  message.replyInfo?.chatId,
                  fromMessageId: message.id,
                ),
      );
      final String? originChatName = message.replyToChatName?.trim();
      if (originChatName != null && originChatName.isNotEmpty) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 2.0),
              child: Text(
                'из «$originChatName»',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: subtextColor,
                ),
              ),
            ),
            baseReply,
          ],
        );
      }
      return baseReply;
    }

    if (message.forwardFromName != null &&
        message.forwardFromName!.trim().isNotEmpty) {
      return MessageReplyInfo.forwarded(
        authorName: message.forwardFromName!,
        authorAvatarUrl: message.forwardFromAvatarUrl,
        isMe: isMe,
      );
    }
    return null;
  }

  Widget _buildAlbumFeedItem(MediaAlbum album, int index) {
    final message = album.primaryMessage;
    final key = _obtainPrimaryMessageKey(message);
    final bool isMe = _isOwnMessage(message);

    final bool isAlbumTargeted = _highlightMessageId == message.id ||
        album.items.any((ai) => ai.id == _highlightMessageId);
    final bool isSelected = _selectedMessageIds.contains(message.id) ||
        album.items.any((ai) => _selectedMessageIds.contains(ai.id));
    final bool isAnonMsg = message.isFromAnonymousAdmin;
    final bool hasSenderChat =
        message.senderChatId != null && message.senderChatId!.isNotEmpty;
    final bool canCluster = message.messageType != 'system' &&
        (message.senderId.isNotEmpty || isAnonMsg || hasSenderChat);
    final Message? olderMsg =
        (_showUnreadDivider && index == _firstUnreadFeedIndex)
            ? null
            : _feedItemMessage(index + 1);
    final Message? newerMsg =
        (_showUnreadDivider && (index - 1) == _firstUnreadFeedIndex)
            ? null
            : _feedItemMessage(index - 1);
    final bool firstInCluster = canCluster
        ? isFirstInSenderCluster(
            current: message,
            olderNeighbor: olderMsg,
          )
        : true;
    final bool lastInCluster = canCluster
        ? isLastInSenderCluster(
            current: message,
            newerNeighbor: newerMsg,
          )
        : true;
    final bool showGroupSenderAvatar = !isMe &&
        message.messageType != 'system' &&
        (message.senderId.isNotEmpty || isAnonMsg || hasSenderChat);
    final ChatParticipant? participant =
        (showGroupSenderAvatar && !isAnonMsg && !hasSenderChat)
            ? _findParticipant(message.senderId)
            : null;
    final PeerCustomization? senderCust =
        (showGroupSenderAvatar && !isAnonMsg && !hasSenderChat)
        ? (PeerCustomizationCache.instance.getSync(message.senderId) ??
            participant?.peerCustomization ??
            message.senderCustomization)
        : null;
    final String effectiveGroupName =
        widget.groupName ?? (_groupName.isNotEmpty ? _groupName : 'Group');
    final String? effectiveGroupAvatar = widget.groupAvatar ?? _groupAvatar;
    final String resolvedSenderName = hasSenderChat
        ? (message.senderChatName?.trim().isNotEmpty == true
              ? message.senderChatName!
              : (message.senderName.trim().isNotEmpty
                    ? message.senderName
                    : 'Канал'))
        : (isAnonMsg
              ? (message.senderName.trim().isNotEmpty &&
                        message.senderName != 'You'
                    ? message.senderName
                    : effectiveGroupName)
              : message.senderName);
    final String? resolvedSenderAvatar = hasSenderChat
        ? message.senderChatAvatarUrl
        : (participant?.avatarUrl ?? message.senderAvatarUrl);
    final VoidCallback? onSenderTap = _isSelectionMode
        ? null
        : (hasSenderChat
              ? () => _openChannelProfileById(
                  message.senderChatId!,
                  name: resolvedSenderName,
                  avatarUrl: resolvedSenderAvatar,
                )
              : (isAnonMsg
                    ? _openGroupInfo
                    : () => _openSenderProfile(message)));
    final String? resolvedAdminTitle = (hasSenderChat || message.isMirroredChannelPost)
        ? 'канал'
        : (isAnonMsg &&
                (message.senderAdminTitle == null ||
                    message.senderAdminTitle!.trim().isEmpty)
            ? 'анонимно'
            : ((message.senderAdminTitle != null &&
                    message.senderAdminTitle!.trim().isNotEmpty)
                ? message.senderAdminTitle
                : participant?.adminTitle));
    final String? resolvedRole = (hasSenderChat || message.isMirroredChannelPost || isAnonMsg)
        ? null
        : ((message.senderRole != null && message.senderRole!.trim().isNotEmpty)
            ? message.senderRole
            : participant?.role);
    final bool isSenderVerified = hasSenderChat
        ? _sendAsPeers.any(
            (p) =>
                p.isChannel &&
                (p.chatId == message.senderChatId ||
                    p.id == message.senderChatId) &&
                p.isVerified,
          )
        : (isAnonMsg ? _isVerified : (participant?.isVerified ?? false));
    final bool showSenderHeader = firstInCluster &&
        (showGroupSenderAvatar || (isMe && (hasSenderChat || isAnonMsg)));
    final Widget? senderHeaderWidget = showSenderHeader
        ? SenderHeaderRow(
            senderName: resolvedSenderName,
            nameColor: (hasSenderChat || isAnonMsg)
                ? (isMe
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.primary)
                : _resolveSenderNameColor(message),
            customization: senderCust,
            isBot: !isAnonMsg && !hasSenderChat && (participant?.isBot ?? false),
            isVerified: isSenderVerified,
            adminTitle: resolvedAdminTitle,
            role: resolvedRole,
            rankColor: isMe
                ? Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.72)
                : null,
            onTapSender: onSenderTap,
          )
        : null;
    final Widget? replyOrForwardWidget =
        _buildAlbumReplyOrForwardWidget(message, isMe);

    Widget albumWidget = MediaAlbumWidget(
      key: key,
      album: album,
      isMe: isMe,
      currentUserId: _currentUserId ?? '',
      chatType: 'group',
      senderName: (isMe || showGroupSenderAvatar) ? null : resolvedSenderName,
      headerWidget: senderHeaderWidget,
      senderHeaderWidget: senderHeaderWidget,
      replyOrForwardWidget: replyOrForwardWidget,
      reactions: _messageReactions[message.id] ??
          (message.reactions.isNotEmpty ? message.reactions : null),
      myReactions: _myReactions[message.id] ??
          (message.myReactions.isNotEmpty ? message.myReactions : null),
      onReactionTap: (emoji) {
        if (_isSelectionMode) {
          _toggleMessageSelection(message);
          return;
        }
        _toggleReaction(message.id, emoji);
      },
      hasAvatarGutter: showGroupSenderAvatar,
      isFirstInCluster: firstInCluster,
      isLastInCluster: lastInCluster,
      formatTime: _formatTime,
      onFileTap: (url, name, type) {
        if (_isSelectionMode) {
          _toggleMessageSelection(message);
          return;
        }
        _openFile(url, name, type);
      },
      isHighlighted: isAlbumTargeted,
      highlightItemId: _highlightMessageId,
      isSelected: isSelected,
      isSelectionMode: _isSelectionMode,
      hasProtectedContent: _hasProtectedContent,
    );

    if (showGroupSenderAvatar) {
      albumWidget = GroupMessageAvatarRow(
        senderId: hasSenderChat ? message.senderChatId! : message.senderId,
        senderName: resolvedSenderName,
        senderAvatarUrl: resolvedSenderAvatar,
        showAvatar: lastInCluster,
        customizationOverride: senderCust,
        isSelectionMode: _isSelectionMode,
        isSelected: isSelected,
        isHighlighted: isAlbumTargeted,
        isFromAnonymousAdmin: !hasSenderChat && isAnonMsg,
        groupAvatarUrl: effectiveGroupAvatar,
        groupName: effectiveGroupName,
        onTapGroupAvatar: _isSelectionMode
            ? () => _toggleMessageSelection(message)
            : _openGroupInfo,
        onAvatarTap: _isSelectionMode
            ? () => _toggleMessageSelection(message)
            : onSenderTap,
        child: albumWidget,
      );
    }

    albumWidget = SwipeToReplyWrapper(
      onReply: () => _startReply(message),
      enabled: !_isSelectionMode && _canSendMessages,
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
                    _showContextMenu(
                      message,
                      isMe,
                      key,
                      album: album,
                      enableBlur: true,
                    );
                  }),
        onDoubleTap: _isSelectionMode
            ? null
            : () => _toggleReaction(message.id, '❤️'),
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
            album: album,
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
    final bool isMe = _isOwnMessage(message);
    final GlobalKey key = _obtainPrimaryMessageKey(message);
    final hasLocalId = message.localId != null && message.localId!.isNotEmpty;

    if (message.messageType == 'system') {
      final prevItem =
          index < _feedItems.length - 1 ? _feedItems[index + 1] : null;
      final (currentDt, currentDate) = _resolveDates(message.createdAt);
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
      if (_showUnreadDivider && index == _firstUnreadFeedIndex) {
        items.add(
          UnreadSeparator(
            key: _unreadSeparatorKey,
          ),
        );
      }
      items.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: TelegramServiceMessageWidget(
            key: key,
            message: message,
            isChannel: false,
            onTapUser: (userId) => _openUserProfileById(userId),
            onTapPinnedMessage: (msgId) => _scrollToMessage(msgId),
            onTapPhoto: (photoUrl) {
              final resolved = AppConfig.resolveMediaUrl(photoUrl) ?? photoUrl;
              FullscreenPhotoViewer.open(context, resolved);
            },
          ),
        ),
      );
      return RepaintBoundary(child: Column(children: items));
    }

    final isHighlighted = _highlightMessageId == message.id;
    final bool isSelected = _selectedMessageIds.contains(message.id);
    final bool isAnonMsg = message.isFromAnonymousAdmin;
    final bool hasSenderChat =
        message.senderChatId != null && message.senderChatId!.isNotEmpty;
    final bool canCluster = message.messageType != 'system' &&
        (message.senderId.isNotEmpty || isAnonMsg || hasSenderChat);
    final Message? olderMsg =
        (_showUnreadDivider && index == _firstUnreadFeedIndex)
            ? null
            : _feedItemMessage(index + 1);
    final Message? newerMsg =
        (_showUnreadDivider && (index - 1) == _firstUnreadFeedIndex)
            ? null
            : _feedItemMessage(index - 1);
    final bool firstInCluster = canCluster
        ? isFirstInSenderCluster(
            current: message,
            olderNeighbor: olderMsg,
          )
        : true;
    final bool lastInCluster = canCluster
        ? isLastInSenderCluster(
            current: message,
            newerNeighbor: newerMsg,
          )
        : true;
    final bool showGroupSenderAvatar = !isMe &&
        message.messageType != 'system' &&
        (message.senderId.isNotEmpty || isAnonMsg || hasSenderChat);
    final ChatParticipant? participant =
        (showGroupSenderAvatar && !isAnonMsg && !hasSenderChat)
            ? _findParticipant(message.senderId)
            : null;
    final PeerCustomization? senderCust =
        (showGroupSenderAvatar && !isAnonMsg && !hasSenderChat)
        ? (PeerCustomizationCache.instance.getSync(message.senderId) ??
            participant?.peerCustomization ??
            message.senderCustomization)
        : null;
    final String effectiveGroupName =
        widget.groupName ?? (_groupName.isNotEmpty ? _groupName : 'Group');
    final String? effectiveGroupAvatar = widget.groupAvatar ?? _groupAvatar;
    final String resolvedSenderName = hasSenderChat
        ? (message.senderChatName?.trim().isNotEmpty == true
              ? message.senderChatName!
              : (message.senderName.trim().isNotEmpty
                    ? message.senderName
                    : 'Канал'))
        : (isAnonMsg
              ? (message.senderName.trim().isNotEmpty &&
                        message.senderName != 'You'
                    ? message.senderName
                    : effectiveGroupName)
              : message.senderName);
    final String? resolvedSenderAvatar = hasSenderChat
        ? message.senderChatAvatarUrl
        : (participant?.avatarUrl ?? message.senderAvatarUrl);
    final VoidCallback? onSenderTap = _isSelectionMode
        ? null
        : (hasSenderChat
              ? () => _openChannelProfileById(
                  message.senderChatId!,
                  name: resolvedSenderName,
                  avatarUrl: resolvedSenderAvatar,
                )
              : (isAnonMsg
                    ? _openGroupInfo
                    : () => _openSenderProfile(message)));
    final String? resolvedAdminTitle = (hasSenderChat || message.isMirroredChannelPost)
        ? 'канал'
        : (isAnonMsg &&
                (message.senderAdminTitle == null ||
                    message.senderAdminTitle!.trim().isEmpty)
            ? 'анонимно'
            : ((message.senderAdminTitle != null &&
                    message.senderAdminTitle!.trim().isNotEmpty)
                ? message.senderAdminTitle
                : participant?.adminTitle));
    final String? resolvedRole = (hasSenderChat || message.isMirroredChannelPost || isAnonMsg)
        ? null
        : ((message.senderRole != null && message.senderRole!.trim().isNotEmpty)
            ? message.senderRole
            : participant?.role);
    final bool isSenderVerified = hasSenderChat
        ? _sendAsPeers.any(
            (p) =>
                p.isChannel &&
                (p.chatId == message.senderChatId ||
                    p.id == message.senderChatId) &&
                p.isVerified,
          )
        : (isAnonMsg ? _isVerified : (participant?.isVerified ?? false));
    final bool showSenderHeader = firstInCluster &&
        (showGroupSenderAvatar || (isMe && (hasSenderChat || isAnonMsg)));
    final Widget? senderHeaderWidget = showSenderHeader
        ? SenderHeaderRow(
            senderName: resolvedSenderName,
            nameColor: (hasSenderChat || isAnonMsg)
                ? (isMe
                      ? Theme.of(context).colorScheme.onPrimary
                      : Theme.of(context).colorScheme.primary)
                : _resolveSenderNameColor(message),
            customization: senderCust,
            isBot: !isAnonMsg && !hasSenderChat && (participant?.isBot ?? false),
            isVerified: isSenderVerified,
            adminTitle: resolvedAdminTitle,
            role: resolvedRole,
            rankColor: isMe
                ? Theme.of(context).colorScheme.onPrimary.withValues(alpha: 0.72)
                : null,
            onTapSender: onSenderTap,
          )
        : null;

    Widget messageWidget = MessageBubble(
      key: key,
      message: message,
      isMe: isMe,
      currentUserId: _currentUserId ?? '',
      senderName: (isMe || showGroupSenderAvatar) ? null : resolvedSenderName,
      senderHeaderWidget: senderHeaderWidget,
      hasAvatarGutter: showGroupSenderAvatar,
      isFirstInCluster: firstInCluster,
      isLastInCluster: lastInCluster,
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
      hasProtectedContent: _hasProtectedContent,
      translation: _translationsByMsgId[message.id],
      isTranslating: _translatingMsgIds.contains(message.id),
      onHideTranslation: () {
        setState(() => _translationsByMsgId.remove(message.id));
      },
      onStopLiveLocation: () => _stopLiveLocation(message.id),
      onOpenContactUser: (uid) {
        if (uid.isEmpty) return;
        Navigator.of(context).push(
          SwipeBackPageRoute(
            builder: (_) => ProfileScreen(
              entityType: ProfileEntityType.user,
              userId: uid,
            ),
          ),
        );
      },
      onInsertInlineQuery: _insertInlineQueryText,
      onCommandTap: (cmd) {
        if (_canSendMessages) {
          _sendMessage(cleanText: cmd);
        }
      },
      onHashtagTap: (_) {
        ChatActionsHelper.openSearch(
          context: context,
          chatId: widget.chatId,
          chatName: _groupName.isNotEmpty
              ? _groupName
              : (widget.groupName ?? 'Группа'),
          onMessageSelected: (msgId) => _scrollToMessage(msgId),
        );
      },
    );

    if (showGroupSenderAvatar) {
      messageWidget = GroupMessageAvatarRow(
        senderId: hasSenderChat ? message.senderChatId! : message.senderId,
        senderName: resolvedSenderName,
        senderAvatarUrl: resolvedSenderAvatar,
        showAvatar: lastInCluster,
        customizationOverride: senderCust,
        isSelectionMode: _isSelectionMode,
        isSelected: isSelected,
        isHighlighted: isHighlighted,
        isFromAnonymousAdmin: !hasSenderChat && isAnonMsg,
        groupAvatarUrl: effectiveGroupAvatar,
        groupName: effectiveGroupName,
        onTapGroupAvatar: _isSelectionMode
            ? () => _toggleMessageSelection(message)
            : _openGroupInfo,
        onAvatarTap: _isSelectionMode
            ? () => _toggleMessageSelection(message)
            : onSenderTap,
        child: messageWidget,
      );
    }

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
      enabled: !_isSelectionMode && _canSendMessages,
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
                    _showContextMenu(
                      message,
                      isMe,
                      key,
                      enableBlur: true,
                    );
                  }),
        onDoubleTap: _isSelectionMode
            ? null
            : () => _toggleReaction(message.id, '❤️'),
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
    if (_showUnreadDivider && index == _firstUnreadFeedIndex) {
      items.add(
        UnreadSeparator(
          key: _unreadSeparatorKey,
        ),
      );
    }
    final isNewMessage = index == 0 &&
        (message.sendStatus == 0 ||
            (DateTime.tryParse(message.createdAt)
                    ?.toLocal()
                    .isAfter(DateTime.now().subtract(const Duration(seconds: 2))) ??
                false));
    items.add(
      TelegramMessageEntrance(
        key: ValueKey('entrance_${message.localId ?? message.id}'),
        animate: isNewMessage,
        isMe: isMe,
        child: messageWidget,
      ),
    );

    return RepaintBoundary(child: Column(children: items));
  }

  void _startSlowmodeCountdown(int seconds) {
    if (seconds <= 0) return;
    _slowmodeTimer?.cancel();
    if (mounted) {
      setState(() => _slowmodeRemainingSeconds = seconds);
    }
    _slowmodeTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_slowmodeRemainingSeconds <= 1) {
        timer.cancel();
        setState(() => _slowmodeRemainingSeconds = 0);
      } else {
        setState(() => _slowmodeRemainingSeconds--);
      }
    });
  }

  Future<void> _togglePinMessage(Message message) async {
    if (!_canPinMessages) return;
    final isCurrentlyPinned = _pinnedMessage?.id == message.id;
    if (isCurrentlyPinned) {
      setState(() => _pinnedMessage = null);
      final res = await ChatService.unpinMessage(
        chatId: widget.chatId,
        messageId: message.id,
      );
      if (res['success'] == true && mounted) {
        GlassToastService().show(
          context,
          'Сообщение откреплено',
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
        chatId: widget.chatId,
        messageId: message.id,
      );
      if (res['success'] == true && mounted) {
        GlassToastService().show(
          context,
          'Сообщение закреплено',
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
        'Копирование и пересылка запрещены в этом чате',
      );
      return;
    }
    await ForwardChatPickerSheet.show(
      context,
      fromChatId: widget.chatId,
      messageIds: messageIds,
      onStageInCurrentChat: _canSendMessages
          ? ({required hideSender, required hideCaption}) {
              final stagedMsgs = _messages
                  .where((m) => messageIds.contains(m.id))
                  .toList()
                  .reversed
                  .toList();
              if (stagedMsgs.isEmpty || !mounted) return;
              setState(() {
                _stagedForward = StagedForwardPayload(
                  fromChatId: widget.chatId,
                  messages: stagedMsgs,
                  hideSender: hideSender,
                  hideCaption: hideCaption,
                );
              });
            }
          : null,
      onForwarded: (targetChatId) {
        if (targetChatId == widget.chatId) _triggerSilentSync();
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
      if (target.chatId == widget.chatId) {
        setState(() => _stagedForward = updated);
        return;
      }
      final fwdRes = await ChatService.forwardMessages(
        toChatId: target.chatId,
        fromChatId: updated.fromChatId,
        messageIds: updated.messages.map((m) => m.id).toList(),
        hideSender: updated.hideSender,
        hideCaption: updated.hideCaption,
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
          chatId: widget.chatId,
          chatTitle: _groupName,
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
          final isVideo = _isVideoFile(file.path);
          final msgType = isVideo
              ? 'video'
              : (_isImageFile(file.path) ? 'image' : _getMessageTypeFromMimeType(uploadResult.mimeType));
          await ChatService.createScheduledMessage(
            chatId: widget.chatId,
            content: i == 0 ? parsedText : '',
            messageType: msgType,
            scheduleAt: scheduleAt,
            fileUrl: uploadResult.url,
            fileName: uploadResult.fileName,
            mediaPayload: uploadResult.toMediaPayload(),
            entities: i == 0 && entities.isNotEmpty ? entities : null,
            topicId: _activeTopicId,
            sendAsMode: _effectiveSendAsMode,
            sendAsChatId: _effectiveSendAsChannelId,
            sendAsAnonymous: _effectiveSendAsAnon,
          );
        }
        _clearAttachedFiles();
      } finally {
        if (mounted) setState(() => _isUploading = false);
      }
    } else {
      await ChatService.createScheduledMessage(
        chatId: widget.chatId,
        content: parsedText,
        scheduleAt: scheduleAt,
        entities: entities.isNotEmpty ? entities : null,
        topicId: _activeTopicId,
        sendAsMode: _effectiveSendAsMode,
        sendAsChatId: _effectiveSendAsChannelId,
        sendAsAnonymous: _effectiveSendAsAnon,
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
      GlassToastService().show(context, 'Сообщение запланировано');
    }
  }

  Widget? _buildPollOnlyTrailingButton(BuildContext context) {
    final perms = _effectivePermissions;
    if (perms.canSendMedia || !perms.canSendPolls) return null;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final glassProvider = LiquidGlassProvider.maybeOf(context);
    final bool glassEnabled = glassProvider?.enabled ?? false;
    final bool isLite = glassProvider?.isLite ?? false;
    final Color iconColor = theme.colorScheme.onSurface.withValues(alpha: 0.82);

    final Widget tapTarget = Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: () {
          _dismissKeyboardAndEmoji();
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => PollCreateScreen(
                chatId: widget.chatId,
                topicId: _activeTopicId,
                sendAsMode: _effectiveSendAsMode,
                sendAsChatId: _effectiveSendAsChannelId,
                sendAsAnonymous: _effectiveSendAsAnon,
                replyToMessageId: _replyToMessage?.id,
              ),
            ),
          );
        },
        child: SizedBox(
          width: 44,
          height: 44,
          child: Center(
            child: iconoir.StatsUpSquare(
              width: 20,
              height: 20,
              color: iconColor,
            ),
          ),
        ),
      ),
    );

    final Widget pill;
    if (glassEnabled && glassProvider != null) {
      pill = LiquidGlassLens(
        style: glassProvider.createStyle(
          context: context,
          cornerRadius: 22,
          refractionIndex: 1.1,
          refractionWidth: 20,
          isLiteOverride: isLite,
        ),
        child: tapTarget,
      );
    } else {
      pill = ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter.grouped(
          filter: BlurUtils.createDownsampledBlur(12),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.65)
                  : Colors.white.withValues(alpha: 0.72),
              shape: BoxShape.circle,
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.14)
                    : Colors.black.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
            child: tapTarget,
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: pill,
    );
  }

  void _onPendingInlinePrefillChanged() {
    if (!mounted) return;
    final prefill = DeepLinkService.consumeInlinePrefill(widget.chatId);
    if (prefill != null && prefill.isNotEmpty) {
      _insertInlineQueryText(prefill);
    }
  }

  void _insertInlineQueryText(String text) {
    if (_isBotCommandsOpen) {
      setState(() => _isBotCommandsOpen = false);
    }
    _messageController.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
    _inputFocusNode.requestFocus();
    _inlineQueryController.onTextChanged(
      text,
      chatId: widget.chatId,
      chatType: 'group',
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
        chatId: widget.chatId,
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

  ({
    List<List<Map<String, dynamic>>> rows,
    bool oneTime,
    String? botId,
  }) get _activeGroupReplyKeyboard {
    for (final msg in _messages) {
      if (msg.senderId == _currentUserId) continue;
      if (msg.removeReplyKeyboard) {
        return (rows: const [], oneTime: false, botId: null);
      }
      if (msg.replyKeyboard.isNotEmpty) {
        return (
          rows: msg.replyKeyboard,
          oneTime: msg.oneTimeReplyKeyboard,
          botId: msg.viaBotId ?? msg.senderId,
        );
      }
    }
    return (rows: const [], oneTime: false, botId: null);
  }

  Widget _buildMessageInput() {
    final perms = _effectivePermissions;
    final replyKbInfo = _activeGroupReplyKeyboard;
    final hasReplyKb = replyKbInfo.rows.isNotEmpty;

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
                chatId: widget.chatId,
                chatType: 'group',
              ),
              onTapHeaderButton: (btn) =>
                  _handleInlinePopupHeaderButtonTap(ctx, btn),
              onSelectResult: (item) async {
                final ok = await _inlineQueryController.sendSelectedResult(
                  chatId: widget.chatId,
                  result: item,
                  replyToMessageId: _replyToMessage?.id,
                  topicId: _activeTopicId,
                  sendAsMode: _effectiveSendAsMode,
                  sendAsChatId: _effectiveSendAsChannelId,
                  sendAsAnonymous: _effectiveSendAsAnon,
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
                  (p) => MentionCandidate(
                    id: p.id,
                    username: p.username,
                    displayName:
                        p.displayName.isNotEmpty ? p.displayName : p.username,
                    avatarUrl: p.avatarUrl,
                    isBot: p.isBot ||
                        p.username.toLowerCase().endsWith('bot') ||
                        p.username.toLowerCase() == 'botmother' ||
                        p.username.toLowerCase() == 'walt',
                    roleLabel: p.role == 'owner'
                        ? 'Владелец'
                        : (p.role == 'admin' ? 'Админ' : null),
                  ),
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
        if (_groupBotCommands.isNotEmpty)
          BotCommandsPopup(
            isOpen: _isBotCommandsOpen,
            commands: _groupBotCommands,
            filterQuery: _messageController.text,
            onClose: () => setState(() => _isBotCommandsOpen = false),
            onSelectCommand: (cmd) {
              setState(() => _isBotCommandsOpen = false);
              _messageController.text = cmd.normalizedCommand;
              _sendMessage(cleanText: cmd.normalizedCommand);
            },
          ),
        ChatInputBar(
          controller: _messageController,
          focusNode: _inputFocusNode,
          replyFallbackAuthorName:
              _groupName.isNotEmpty ? _groupName : widget.groupName,
          hintText: _effectiveSendAsAnon
              ? context.trOr(
                  'send_as_anonymous_hint',
                  'Написать анонимно...',
                )
              : null,
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
          slowmodeRemainingSeconds: _slowmodeRemainingSeconds,
          canSendMedia: perms.canSendMedia,
          canSendStickersGifs: perms.canSendStickersGifs,
          canSendPolls: perms.canSendPolls,
          isAnonymousAdmin: _effectiveSendAsAnon,
          anonymousGroupAvatarUrl: widget.groupAvatar ?? _groupAvatar,
          showBotCommandsButton: _groupBotCommands.isNotEmpty,
          isBotCommandsOpen: _isBotCommandsOpen,
          onToggleBotCommands: () {
            setState(() => _isBotCommandsOpen = !_isBotCommandsOpen);
          },
          hasReplyKeyboard: hasReplyKb,
          isReplyKeyboardOpen: _isReplyKeyboardOpen,
          onToggleReplyKeyboard: () {
            setState(() => _isReplyKeyboardOpen = !_isReplyKeyboardOpen);
          },
          sendAsLeadingWidget: _sendAsPeers.length > 1
              ? InlineSendAsSelectorButton(
                  chatId: widget.chatId,
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
          trailing: _buildPollOnlyTrailingButton(context),
        ),
        if (hasReplyKb)
          ReplyKeyboardPanel(
            isOpen: _isReplyKeyboardOpen,
            rows: replyKbInfo.rows,
            onButtonPressed: (btnText) {
              if (replyKbInfo.oneTime) {
                setState(() => _isReplyKeyboardOpen = false);
              }
              _messageController.text = btnText;
              _sendMessage(cleanText: btnText);
            },
            onButtonAction: (btn) {
              if (replyKbInfo.oneTime) {
                setState(() => _isReplyKeyboardOpen = false);
              }
              final wa = btn['web_app'];
              final waMap = wa is Map ? wa : null;
              final waUrl = waMap != null
                  ? waMap['url']?.toString()
                  : (wa is String ? wa : null);
              final targetBotId = (waMap?['bot_id'] ?? btn['bot_id'] ?? replyKbInfo.botId)
                  ?.toString()
                  .trim();
              if (waUrl != null &&
                  waUrl.isNotEmpty &&
                  targetBotId != null &&
                  targetBotId.isNotEmpty) {
                openMiniAppSheet(
                  context,
                  botId: targetBotId,
                  botUsername: (waMap?['bot_username'] ?? btn['bot_username'])
                      ?.toString(),
                  url: waUrl,
                  chatId: widget.chatId,
                  mode: 'keyboard',
                  buttonText: (btn['text'] ?? '').toString(),
                  onSwitchInlineQuery: _insertInlineQueryText,
                );
              } else if (btn['request_location'] == true) {
                _sendRequestedLocation();
              } else if (btn['request_contact'] == true) {
                _sendOwnContact();
              } else if (btn['request_poll'] != null && perms.canSendPolls) {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PollCreateScreen(
                      chatId: widget.chatId,
                      topicId: _activeTopicId,
                      sendAsMode: _effectiveSendAsMode,
                      sendAsChatId: _effectiveSendAsChannelId,
                      sendAsAnonymous: _effectiveSendAsAnon,
                      replyToMessageId: _replyToMessage?.id,
                    ),
                  ),
                );
              } else {
                final text = (btn['text'] ?? '').toString();
                if (text.isNotEmpty) {
                  _messageController.text = text;
                  _sendMessage(cleanText: text);
                }
              }
            },
          ),
      ],
    );
  }

  bool _isVideoPointerDown = false;
  bool _isVoicePointerDown = false;

  Future<void> _onStartVideoRecord() async {
    if (!_canSendMessages || !_effectivePermissions.canSendMedia) return;
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
    GlassToastService().show(
      context,
      context.l10n.translate('chat_video_note_too_short'),
      duration: const Duration(seconds: 2),
    );
  }

  Future<void> _onVideoRecordingSend(File file) async {
    _stopRecordingActionBroadcast();
    setState(() => _isVideoRecording = false);
    await _sendRoundVideoMessage(file);
  }

  Future<void> _onStartVoiceRecord() async {
    if (!_canSendMessages || !_effectivePermissions.canSendMedia) return;
    _isVoicePointerDown = true;
    _dismissKeyboardAndEmoji();
    final hasPerm = await _voiceRecorderService.hasPermission();
    if (!hasPerm) {
      _isVoicePointerDown = false;
      final isPermanentlyDenied = await _voiceRecorderService.isPermanentlyDenied();
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

    final bool sendAnon = _effectiveSendAsAnon;
    final String sendMode = _effectiveSendAsMode;
    final String? sendChannelId = _effectiveSendAsChannelId;
    final SendAsPeer? activePeer = _activeSendAsPeer;
    final bool sendingAsChannel =
        sendMode == 'channel' &&
        sendChannelId != null &&
        sendChannelId.isNotEmpty;
    final String? pendingSenderName = sendingAsChannel
        ? activePeer?.name
        : (sendAnon
            ? (_groupName.isNotEmpty
                ? _groupName
                : (widget.groupName ?? 'Group'))
            : null);
    final String? pendingSenderAvatar = sendingAsChannel
        ? activePeer?.avatarUrl
        : (sendAnon ? (_groupAvatar ?? widget.groupAvatar) : null);

    try {
      final fileName = kIsWeb
          ? 'voice_${DateTime.now().millisecondsSinceEpoch}.webm'
          : file.path.split(!kIsWeb ? Platform.pathSeparator : '/').last;
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
          senderName: pendingSenderName,
          senderAvatarUrl: pendingSenderAvatar,
          isFromAnonymousAdmin: !sendingAsChannel && sendAnon,
          topicId: _activeTopicId,
          senderChatId: sendingAsChannel ? sendChannelId : null,
          senderChatName: sendingAsChannel ? activePeer?.name : null,
          senderChatAvatarUrl: sendingAsChannel ? activePeer?.avatarUrl : null,
          isOwn: true,
        );
      } catch (e) {
        debugPrint('SyncService createPendingMessage voice error: $e');
      }

      if (pendingMsg != null && mounted) {
        pendingLocalId = pendingMsg.localId;
        final profileTheme = context.read<ProfileThemeProvider>();
        var message = Message.fromDbMessage(pendingMsg).copyWith(
          waveform: result.waveform,
          duration: result.duration.inSeconds,
          senderName: pendingSenderName,
          senderAvatarUrl: pendingSenderAvatar,
          senderRole: sendingAsChannel ? null : _myRole,
          senderAdminTitle: sendingAsChannel
              ? null
              : (_myAdminTitle.isNotEmpty ? _myAdminTitle : null),
          isFromAnonymousAdmin: !sendingAsChannel && sendAnon,
          topicId: _activeTopicId,
          senderChatId: sendingAsChannel ? sendChannelId : null,
          senderChatName: sendingAsChannel ? activePeer?.name : null,
          senderChatAvatarUrl: sendingAsChannel ? activePeer?.avatarUrl : null,
          isOwn: true,
        );
        if (replyTo != null) {
          final isPersonaOrChannel = replyTo.isChannelOrPersonaAuthored;
          final isReplyToMe = !isPersonaOrChannel &&
              replyTo.senderId.isNotEmpty &&
              replyTo.senderId != '0' &&
              replyTo.senderId == _currentUserId;
          final fallbackTitle = _groupName.isNotEmpty
              ? _groupName
              : widget.groupName;
          message = message.copyWith(
            replyInfo: ReplyInfo(
              messageId: replyTo.id,
              senderId: isPersonaOrChannel ? '0' : replyTo.senderId,
              senderName: replyTo.resolveEffectiveAuthorTitle(
                chatName: fallbackTitle,
              ),
              content: replyTo.content,
              messageType: replyTo.messageType,
              entities: replyTo.entities,
              nameColorPresetId: isReplyToMe
                  ? profileTheme.currentNameColorPreset.id
                  : (isPersonaOrChannel
                        ? 'name_red'
                        : (replyTo.senderNameColorId ?? 'name_red')),
              replyStripStyle: isReplyToMe
                  ? profileTheme.currentStripStyle.name
                  : (isPersonaOrChannel
                        ? 'solid'
                        : (replyTo.senderReplyStripStyle ?? 'solid')),
              replyEmoji: isReplyToMe
                  ? profileTheme.currentReplyEmoji
                  : (isPersonaOrChannel
                        ? null
                        : PeerCustomizationCache.instance
                              .getSync(replyTo.senderId)
                              ?.replyEmoji),
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
        sendAsMode: sendMode,
        sendAsAnonymous: sendAnon,
        topicId: _activeTopicId,
        sendAsChatId: sendChannelId,
      );

      if (sendResult['success'] == true) {
        _maybeStartLocalSlowmode();
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
              _mergeConfirmedPendingMessage(
                pendingLocalId: pendingLocalId,
                serverId: serverId,
                buildMerged: (existing) {
                  if (sentMessage is Message) {
                    return sentMessage.copyWith(
                      localId: pendingLocalId,
                      sendStatus: 1,
                      replyInfo: existing.replyInfo ?? sentMessage.replyInfo,
                      waveform: sentMessage.waveform ?? existing.waveform,
                      duration: sentMessage.duration ?? effectiveDuration,
                      fileUrl: uploadResult.url,
                    );
                  }
                  return existing.copyWith(
                    id: serverId,
                    sendStatus: 1,
                    duration: effectiveDuration,
                    fileUrl: uploadResult.url,
                  );
                },
              );
            });
          }
        }
      } else {
        final retryAfter = sendResult['retry_after'];
        if (retryAfter is int && retryAfter > 0) {
          _startSlowmodeCountdown(retryAfter);
        }
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

    final bool sendAnon = _effectiveSendAsAnon;
    final String sendMode = _effectiveSendAsMode;
    final String? sendChannelId = _effectiveSendAsChannelId;
    final SendAsPeer? activePeer = _activeSendAsPeer;
    final bool sendingAsChannel =
        sendMode == 'channel' &&
        sendChannelId != null &&
        sendChannelId.isNotEmpty;
    final String? pendingSenderName = sendingAsChannel
        ? activePeer?.name
        : (sendAnon
            ? (_groupName.isNotEmpty
                ? _groupName
                : (widget.groupName ?? 'Group'))
            : null);
    final String? pendingSenderAvatar = sendingAsChannel
        ? activePeer?.avatarUrl
        : (sendAnon ? (_groupAvatar ?? widget.groupAvatar) : null);

    try {
      final fileName = kIsWeb
          ? 'video_note_${DateTime.now().millisecondsSinceEpoch}.webm'
          : file.path.split(!kIsWeb ? Platform.pathSeparator : '/').last;
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
          senderName: pendingSenderName,
          senderAvatarUrl: pendingSenderAvatar,
          isFromAnonymousAdmin: !sendingAsChannel && sendAnon,
          topicId: _activeTopicId,
          senderChatId: sendingAsChannel ? sendChannelId : null,
          senderChatName: sendingAsChannel ? activePeer?.name : null,
          senderChatAvatarUrl: sendingAsChannel ? activePeer?.avatarUrl : null,
          isOwn: true,
        );
      } catch (e) {
        debugPrint('SyncService createPendingMessage error: $e');
      }

      if (pendingMsg != null && mounted) {
        pendingLocalId = pendingMsg.localId;
        final profileTheme = context.read<ProfileThemeProvider>();
        var message = Message.fromDbMessage(pendingMsg).copyWith(
          duration: recordedDurationSec,
          senderName: pendingSenderName,
          senderAvatarUrl: pendingSenderAvatar,
          senderRole: sendingAsChannel ? null : _myRole,
          senderAdminTitle: sendingAsChannel
              ? null
              : (_myAdminTitle.isNotEmpty ? _myAdminTitle : null),
          isFromAnonymousAdmin: !sendingAsChannel && sendAnon,
          topicId: _activeTopicId,
          senderChatId: sendingAsChannel ? sendChannelId : null,
          senderChatName: sendingAsChannel ? activePeer?.name : null,
          senderChatAvatarUrl: sendingAsChannel ? activePeer?.avatarUrl : null,
          isOwn: true,
        );
        if (replyTo != null) {
          final isPersonaOrChannel = replyTo.isChannelOrPersonaAuthored;
          final isReplyToMe = !isPersonaOrChannel &&
              replyTo.senderId.isNotEmpty &&
              replyTo.senderId != '0' &&
              replyTo.senderId == _currentUserId;
          final fallbackTitle = _groupName.isNotEmpty
              ? _groupName
              : widget.groupName;
          message = message.copyWith(
            replyInfo: ReplyInfo(
              messageId: replyTo.id,
              senderId: isPersonaOrChannel ? '0' : replyTo.senderId,
              senderName: replyTo.resolveEffectiveAuthorTitle(
                chatName: fallbackTitle,
              ),
              content: replyTo.content,
              messageType: replyTo.messageType,
              entities: replyTo.entities,
              nameColorPresetId: isReplyToMe
                  ? profileTheme.currentNameColorPreset.id
                  : (isPersonaOrChannel
                        ? 'name_red'
                        : (replyTo.senderNameColorId ?? 'name_red')),
              replyStripStyle: isReplyToMe
                  ? profileTheme.currentStripStyle.name
                  : (isPersonaOrChannel
                        ? 'solid'
                        : (replyTo.senderReplyStripStyle ?? 'solid')),
              replyEmoji: isReplyToMe
                  ? profileTheme.currentReplyEmoji
                  : (isPersonaOrChannel
                        ? null
                        : PeerCustomizationCache.instance
                              .getSync(replyTo.senderId)
                              ?.replyEmoji),
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
        sendAsMode: sendMode,
        sendAsAnonymous: sendAnon,
        topicId: _activeTopicId,
        sendAsChatId: sendChannelId,
      );

      if (result['success'] == true) {
        _maybeStartLocalSlowmode();
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
              _mergeConfirmedPendingMessage(
                pendingLocalId: pendingLocalId,
                serverId: serverId,
                buildMerged: (existing) {
                  if (sentMessage is Message) {
                    return sentMessage.copyWith(
                      localId: pendingLocalId,
                      replyInfo: existing.replyInfo ?? sentMessage.replyInfo,
                      sendStatus: 1,
                      isRound: true,
                      duration: sentMessage.duration ?? effectiveDuration,
                      fileUrl: uploadResult.url,
                    );
                  }
                  return existing.copyWith(
                    id: serverId,
                    sendStatus: 1,
                    isRound: true,
                    duration: effectiveDuration,
                    fileUrl: uploadResult.url,
                  );
                },
              );
            });
          }
        }
      } else {
        final retryAfter = result['retry_after'];
        if (retryAfter is int && retryAfter > 0) {
          _startSlowmodeCountdown(retryAfter);
        }
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

  /// Toggle reaction on a message — optimistic update + API call with rollback
  void _toggleReaction(String messageId, String emoji) {
    if (_isGuestViewer) {
      GlassToastService().show(
        context,
        'Вступите в группу, чтобы ставить реакции',
        iconWidget: iconoir.Group(
          width: 18,
          height: 18,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      );
      return;
    }
    final previousMyReactions = Set<String>.from(_myReactions[messageId] ?? {});
    final bool isCurrentlySelected = previousMyReactions.contains(emoji);
    if (!isCurrentlySelected && !_reactionSettings.isReactionAllowed(emoji)) {
      GlassToastService().show(
        context,
        _reactionSettings.isNone
            ? 'Реакции отключены в этой группе'
            : 'Эта реакция отключена в группе',
        iconWidget: iconoir.Lock(
          width: 18,
          height: 18,
          color: Theme.of(context).colorScheme.onSurface,
        ),
      );
      return;
    }
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
    if (_hasProtectedContent) {
      GlassToastService().show(
        context,
        'Копирование и пересылка запрещены в этом чате',
      );
      return;
    }
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
    final ids = _selectedMessageIds.toList();
    _clearSelection();
    _forwardMessagesToPickedChat(ids);
  }

  void _deleteSelectedMessages() {
    if (_selectedMessageIds.isEmpty) return;
    final toDelete = _messages
        .where(
          (m) =>
              _selectedMessageIds.contains(m.id) &&
              (_isOwnMessage(m) || _canDeleteOthers),
        )
        .toList();
    _clearSelection();
    if (toDelete.isEmpty) return;
    _deleteMessagesWithSheet(toDelete);
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
        final kbOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
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
            final kbOpen = MediaQuery.viewInsetsOf(context).bottom > 0;
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
        : _resolveSelectionIdsForMessage(message);
    final List<Message> targetMessages =
        _messages.where((m) => targetIds.contains(m.id)).toList();
    final bool isVideoNote = message.isRound || (message.messageType == 'video' && message.isRound);
    final bool isVoiceNote = message.messageType == 'voice';
    final bool isPoll = message.messageType == 'poll';
    final bool isGroupAdmin = _myRole == 'owner' ||
        _myRole == 'admin' ||
        _participants.any(
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
      hasProtectedContent: _hasProtectedContent,
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
      onReply: _canSendMessages ? () => _startReply(message) : null,
      onQuote: (!_canSendMessages || isVideoNote || isVoiceNote || isPoll)
          ? null
          : () => _startQuote(message, message.content, 0, message.content.length),
      onQuotePartial: (!_canSendMessages || isVideoNote || isVoiceNote || isPoll)
          ? null
          : (selectedText, offset, length) =>
              _startQuote(message, selectedText, offset, length),
      onPin: _canPinMessages ? () => _togglePinMessage(message) : null,
      isPinned: _pinnedMessage?.id == message.id,
      onForward: _hasProtectedContent
          ? null
          : () => _forwardMessagesToPickedChat(targetIds),
      onEdit: (!isMe || !_canSendMessages || isVideoNote || isVoiceNote || isPoll)
          ? null
          : () => _enterEditMode(message),
      onSelect: () => _enterSelectionMode(message),
      onTranslate: message.content.trim().isNotEmpty
          ? () => unawaited(_toggleTranslateMessage(message))
          : null,
      isTranslated: _translationsByMsgId.containsKey(message.id),
      onReplyInAnotherChat: !_hasProtectedContent
          ? () => unawaited(_replyInAnotherChat(message))
          : null,
      onDelete: (isMe || _canDeleteOthers)
          ? (_) => _deleteMessagesWithSheet(
                targetMessages.isNotEmpty ? targetMessages : [message],
              )
          : null,
      onReaction: (msgId, emoji) => _toggleReaction(msgId, emoji),
      selectedEmojis: _myReactions[message.id] ?? message.myReactions,
    );
  }

  Future<void> _sendLocation() async {
    if (!_canSendMessages) return;
    final picked = await showLocationPickerSheet(context);
    if (!mounted || picked == null) return;
    final res = await ChatService.sendMessage(
      chatId: widget.chatId,
      content: '',
      messageType: picked.messageType,
      latitude: picked.latitude,
      longitude: picked.longitude,
      livePeriod: picked.livePeriod,
      heading: picked.heading,
      horizontalAccuracy: picked.horizontalAccuracy,
      placeName: picked.placeName,
      address: picked.address,
      topicId: _activeTopicId,
      sendAsMode: _effectiveSendAsMode,
      sendAsChatId: _effectiveSendAsChannelId,
      sendAsAnonymous: _effectiveSendAsAnon,
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
      if (picked.messageType == 'live_location' && (picked.livePeriod ?? 0) > 0) {
        _startLiveLocationUpdater(sent.id, picked.livePeriod ?? 900);
      }
    } else {
      GlassToastService().showError(
        context,
        res['message']?.toString() ?? 'Не удалось отправить геопозицию',
      );
    }
  }

  void _startLiveLocationUpdater(String messageId, int livePeriodSeconds) {
    _liveLocationTimer?.cancel();
    _activeLiveLocationMessageId = messageId;
    _liveLocationExpiresAt = DateTime.now()
        .toUtc()
        .add(Duration(seconds: livePeriodSeconds));
    _liveLocationTimer = Timer.periodic(const Duration(seconds: 30), (_) async {
      final targetId = _activeLiveLocationMessageId;
      final expiresAt = _liveLocationExpiresAt;
      if (!mounted || targetId == null || expiresAt == null) {
        _liveLocationTimer?.cancel();
        return;
      }
      if (DateTime.now().toUtc().isAfter(expiresAt)) {
        _liveLocationTimer?.cancel();
        _activeLiveLocationMessageId = null;
        return;
      }
      try {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
        await DmParityService.updateLiveLocation(
          widget.chatId,
          targetId,
          latitude: pos.latitude,
          longitude: pos.longitude,
          heading: pos.heading >= 0 && pos.heading <= 360
              ? pos.heading.round()
              : null,
          horizontalAccuracy: pos.accuracy > 0 ? pos.accuracy : null,
        );
      } catch (_) {}
    });
  }

  Future<void> _stopLiveLocation(String messageId) async {
    if (_activeLiveLocationMessageId == messageId) {
      _liveLocationTimer?.cancel();
      _liveLocationTimer = null;
      _activeLiveLocationMessageId = null;
      _liveLocationExpiresAt = null;
    }
    final res = await DmParityService.updateLiveLocation(
      widget.chatId,
      messageId,
      stop: true,
    );
    if (!mounted) return;
    if (res['success'] == true) {
      final rawPayload = res['media_payload'];
      setState(() {
        final idx = _messages.indexWhere((m) => m.id == messageId);
        if (idx != -1) {
          final current = _messages[idx];
          final nextPayload = rawPayload is Map
              ? Map<String, dynamic>.from(rawPayload)
              : {
                  ...?current.mediaPayload,
                  'is_live_active': false,
                };
          _messages[idx] = current.copyWith(mediaPayload: nextPayload);
          _updateFeedItems();
        }
      });
      GlassToastService().show(context, 'Трансляция геопозиции остановлена');
    } else {
      GlassToastService().showError(
        context,
        res['message']?.toString() ?? 'Не удалось остановить трансляцию',
      );
    }
  }

  Future<void> _sendRequestedLocation() async {
    if (!_canSendMessages) return;
    final confirmed = await showTheavDialog<bool>(
          context: context,
          title: 'Отправить геопозицию',
          message: 'Отправить ваше текущее местоположение в этот чат?',
          actions: const [
            TheavDialogAction<bool>(label: 'Отмена', result: false),
            TheavDialogAction<bool>(
              label: 'Отправить',
              result: true,
              isPrimary: true,
            ),
          ],
        ) ??
        false;
    if (!confirmed || !mounted) return;

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (mounted) {
          GlassToastService().showError(
            context,
            'Службы геолокации отключены',
          );
        }
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (mounted) {
          GlassToastService().showError(
            context,
            'Нет разрешения на доступ к геопозиции',
          );
        }
        return;
      }

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      if (!mounted) return;

      final res = await ChatService.sendMessage(
        chatId: widget.chatId,
        content: '',
        messageType: 'location',
        latitude: pos.latitude,
        longitude: pos.longitude,
        horizontalAccuracy: pos.accuracy > 0 ? pos.accuracy : null,
        topicId: _activeTopicId,
        sendAsMode: _effectiveSendAsMode,
        sendAsChatId: _effectiveSendAsChannelId,
        sendAsAnonymous: _effectiveSendAsAnon,
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
    } catch (e) {
      if (mounted) {
        GlassToastService().showError(
          context,
          'Не удалось получить геопозицию',
        );
      }
    }
  }

  Future<void> _sendOwnContact() async {
    if (!_canSendMessages) return;
    var acc = AccountManager().currentAccount;
    String phone = acc?.phone?.trim() ?? '';
    String firstName = acc?.name?.trim() ?? '';
    String lastName = acc?.surname?.trim() ?? '';
    String displayName = acc?.displayName?.trim() ?? '';
    String username = acc?.username?.trim() ?? '';
    String avatarUrl = acc?.avatarUrl?.trim() ?? '';
    String userId = acc?.userId ?? _currentUserId ?? '';

    if (phone.isEmpty || (firstName.isEmpty && displayName.isEmpty)) {
      final profileRes = await AuthService.getCurrentUser();
      if (!mounted) return;
      acc = AccountManager().currentAccount;
      final u = profileRes['user'] is Map
          ? Map<String, dynamic>.from(profileRes['user'] as Map)
          : const <String, dynamic>{};
      if (phone.isEmpty) {
        phone = (acc?.phone ?? u['phone'] ?? '').toString().trim();
      }
      if (firstName.isEmpty) {
        firstName = (acc?.name ?? u['name'] ?? '').toString().trim();
      }
      if (lastName.isEmpty) {
        lastName = (acc?.surname ?? u['surname'] ?? '').toString().trim();
      }
      if (displayName.isEmpty) {
        displayName =
            (acc?.displayName ?? u['display_name'] ?? '').toString().trim();
      }
      if (username.isEmpty) {
        username = (acc?.username ?? u['username'] ?? '').toString().trim();
      }
      if (avatarUrl.isEmpty) {
        avatarUrl =
            (acc?.avatarUrl ?? u['avatar_url'] ?? '').toString().trim();
      }
      if (userId.isEmpty) {
        userId = (acc?.userId ?? u['id'] ?? '').toString().trim();
      }
    }

    if (firstName.isEmpty && displayName.isNotEmpty) {
      final parts = displayName.split(RegExp(r'\s+'));
      firstName = parts.first;
      if (lastName.isEmpty && parts.length > 1) {
        lastName = parts.sublist(1).join(' ');
      }
    }
    if (firstName.isEmpty) {
      firstName = username.isNotEmpty ? username : 'Пользователь';
    }

    if (!mounted) return;
    final confirmed = await showTheavDialog<bool>(
          context: context,
          title: 'Поделиться контактом',
          message: phone.isNotEmpty
              ? 'Отправить ваш номер телефона ($phone) в этот чат?'
              : 'Отправить ваш профиль контакта в этот чат?',
          actions: const [
            TheavDialogAction<bool>(label: 'Отмена', result: false),
            TheavDialogAction<bool>(
              label: 'Поделиться',
              result: true,
              isPrimary: true,
            ),
          ],
        ) ??
        false;
    if (!confirmed || !mounted) return;

    final fullName = '$firstName $lastName'.trim();
    final contactPayload = <String, dynamic>{
      if (userId.isNotEmpty) 'user_id': userId,
      'first_name': firstName,
      if (lastName.isNotEmpty) 'last_name': lastName,
      if (displayName.isNotEmpty) 'display_name': displayName,
      if (phone.isNotEmpty) 'phone_number': phone,
      if (username.isNotEmpty) 'username': username,
      if (avatarUrl.isNotEmpty) 'avatar_url': avatarUrl,
    };

    final res = await ChatService.sendMessage(
      chatId: widget.chatId,
      content: fullName.isNotEmpty
          ? fullName
          : (phone.isNotEmpty ? phone : 'Контакт'),
      messageType: 'contact',
      contact: contactPayload,
      topicId: _activeTopicId,
      sendAsMode: _effectiveSendAsMode,
      sendAsChatId: _effectiveSendAsChannelId,
      sendAsAnonymous: _effectiveSendAsAnon,
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

  Future<void> _sendContact() async {
    if (!_canSendMessages) return;
    final picked = await showContactPickerSheet(context);
    if (!mounted || picked == null) return;
    final res = await ChatService.sendMessage(
      chatId: widget.chatId,
      content: picked.displayName,
      messageType: 'contact',
      contact: picked.toPayload(),
      topicId: _activeTopicId,
      sendAsMode: _effectiveSendAsMode,
      sendAsChatId: _effectiveSendAsChannelId,
      sendAsAnonymous: _effectiveSendAsAnon,
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

  Future<void> _openAutoDeleteSheet() async {
    final sec = await showAutoDeleteTimerSheet(
      context,
      currentSeconds: _autoDeleteSeconds,
    );
    if (!mounted || sec == null) return;
    final res = await DmParityService.setChatAutoDelete(widget.chatId, sec);
    if (!mounted) return;
    if (res['success'] == true) {
      setState(() => _autoDeleteSeconds = sec);
      GlassToastService().show(
        context,
        sec == 0 ? 'Автоудаление отключено' : 'Автоудаление обновлено',
      );
    } else {
      GlassToastService().showError(
        context,
        res['message']?.toString() ?? 'Не удалось обновить автоудаление',
      );
    }
  }

  Future<void> _openChatAppearanceSheet() async {
    final res = await showChatAppearanceSheet(
      context,
      chatId: widget.chatId,
      current: _chatAppearance,
      canApplyForBoth: _isAdmin,
    );
    if (!mounted || res == null || !res.changed) return;
    final nextCfg =
        (res.appearance == null || res.appearance!.isEmpty) ? null : res.appearance;
    if (nextCfg != null) {
      ChatInstantCache.instance.putAppearance(widget.chatId, nextCfg);
    }
    setState(() {
      _chatAppearance = nextCfg;
    });
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
      chatId: widget.chatId,
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
        res['message']?.toString() ?? 'Не удалось перевести сообщение',
      );
    }
  }

  Future<void> _replyInAnotherChat(Message message) async {
    final target = await ForwardChatPickerSheet.pickTargetChat(
      context,
      fromChatId: widget.chatId,
      messageCount: 1,
    );
    if (!mounted || target == null) return;
    if (target.chatId == widget.chatId) {
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
            initialReplyChatId: widget.chatId,
            initialReplyChatName: _groupName.isNotEmpty
                ? _groupName
                : (widget.groupName ?? 'Группа'),
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

  Future<void> _deleteMessagesWithSheet(List<Message> targets) async {
    if (targets.isEmpty) return;
    final bool allMine = targets.every(_isOwnMessage);
    final bool isAdmin = _canDeleteOthers;
    if (!allMine && !isAdmin) return;
    final bool canModerate = !allMine && isAdmin;
    final String? authorName =
        targets.length == 1 ? targets.first.senderName : null;

    final res = await showTelegramDeleteMessagesSheet(
      context: context,
      messageCount: targets.length,
      chatType: 'group',
      canRevoke: allMine || isAdmin,
      defaultRevoke: allMine || isAdmin,
      canModerateOther: canModerate,
      targetAuthorName: authorName,
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
      chatId: widget.chatId,
      messageIds: ids,
      revoke: res.revoke,
      reportSpam: res.reportSpam,
      banUser: res.banUser,
      deleteAllFromUser: res.deleteAllFromUser,
    );
    if (apiRes['success'] == true) {
      if (res.deleteAllFromUser && targets.isNotEmpty && mounted) {
        final offenderId = targets.first.senderId;
        setState(() {
          _messages.removeWhere((m) => m.senderId == offenderId);
          _updateFeedItems();
        });
      }
    } else if (mounted) {
      setState(() {
        _messages
          ..clear()
          ..addAll(backup);
        _updateFeedItems();
      });
      GlassToastService().showError(
        context,
        apiRes['message']?.toString() ?? 'Не удалось удалить сообщения',
      );
    }
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
