import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/community_models.dart';
import '../models/profile_customization.dart';
import '../utils/date_time_utils.dart';
import 'chat_service.dart';
import 'community_service.dart';
import 'database/app_database.dart';
import 'peer_customization_cache.dart';
import 'sync_service.dart';
import 'websocket_service.dart';

/// Subscription handle for a specific chat.
class ChatSubscription {
  final String chatId;
  final void Function(WebSocketEvent event)? onNewMessage;
  final void Function(WebSocketEvent event)? onMessageEdited;
  final void Function(WebSocketEvent event)? onMessageDeleted;
  final void Function(WebSocketEvent event)? onReactionUpdated;
  final void Function(WebSocketEvent event)? onMessageRead;
  final void Function(WebSocketEvent event)? onMessageListened;
  final void Function(WebSocketEvent event)? onTyping;
  final void Function(WebSocketEvent event)? onEmojiInteraction;
  final void Function(WebSocketEvent event)? onUserStatus;
  final void Function(WebSocketEvent event)? onUserAvatarUpdated;
  final void Function(WebSocketEvent event)? onUserAppearanceUpdated;
  final void Function(WebSocketEvent event)? onUnreadCountUpdated;
  final void Function(WebSocketEvent event)? onMessagePinned;
  final void Function(WebSocketEvent event)? onMessageUnpinned;
  final void Function(WebSocketEvent event)? onCallbackQueryAnswer;
  final void Function(WebSocketEvent event)? onMessageViewsUpdated;
  final void Function(WebSocketEvent event)? onPostCommentsUpdated;
  final void Function(WebSocketEvent event)? onChatSettingsUpdated;
  final void Function(WebSocketEvent event)? onMemberUpdated;
  final void Function(WebSocketEvent event)? onChatDeleted;
  final void Function(WebSocketEvent event)? onScheduledMessagesUpdated;
  final void Function(WebSocketEvent event)? onJoinRequestsUpdated;
  final void Function(WebSocketEvent event)? onMessageBurned;
  final void Function(WebSocketEvent event)? onChatAutoDeleteUpdated;
  final void Function(WebSocketEvent event)? onChatAppearanceUpdated;
  final void Function(WebSocketEvent event)? onScreenshotTaken;
  final void Function(WebSocketEvent event)? onForumTopicUpdated;
  final void Function(WebSocketEvent event)? onUnreadBadgesUpdated;
  final VoidCallback? onReconnect;

  ChatSubscription({
    required this.chatId,
    this.onNewMessage,
    this.onMessageEdited,
    this.onMessageDeleted,
    this.onReactionUpdated,
    this.onMessageRead,
    this.onMessageListened,
    this.onTyping,
    this.onEmojiInteraction,
    this.onUserStatus,
    this.onUserAvatarUpdated,
    this.onUserAppearanceUpdated,
    this.onUnreadCountUpdated,
    this.onMessagePinned,
    this.onMessageUnpinned,
    this.onCallbackQueryAnswer,
    this.onMessageViewsUpdated,
    this.onPostCommentsUpdated,
    this.onChatSettingsUpdated,
    this.onMemberUpdated,
    this.onChatDeleted,
    this.onScheduledMessagesUpdated,
    this.onJoinRequestsUpdated,
    this.onMessageBurned,
    this.onChatAutoDeleteUpdated,
    this.onChatAppearanceUpdated,
    this.onScreenshotTaken,
    this.onForumTopicUpdated,
    this.onUnreadBadgesUpdated,
    this.onReconnect,
  });

  /// Cancels this subscription.
  void cancel() {
    ChatRealtimeManager().unbindChat(this);
  }
}

/// Central manager for WebSocket real-time chat events and local Drift synchronization.
class ChatRealtimeManager {
  static final ChatRealtimeManager _instance = ChatRealtimeManager._internal();
  factory ChatRealtimeManager() => _instance;
  ChatRealtimeManager._internal();

  final _uuid = const Uuid();
  StreamSubscription<WebSocketEvent>? _wsSubscription;
  final Map<String, Set<ChatSubscription>> _subscriptions = {};

  bool _isInitialized = false;

  /// Initializes the real-time manager and begins listening to WebSocket events.
  void init() {
    if (_isInitialized) return;
    _isInitialized = true;
    _wsSubscription =
        WebSocketService().eventStream.listen(_handleWebSocketEvent);
  }

  /// Disposes active subscriptions and cleans up.
  void dispose() {
    _wsSubscription?.cancel();
    _wsSubscription = null;
    _subscriptions.clear();
    _isInitialized = false;
  }

  /// Binds a screen/listener to a specific chat and returns a cancelable subscription.
  ChatSubscription bindChat({
    required String chatId,
    void Function(WebSocketEvent event)? onNewMessage,
    void Function(WebSocketEvent event)? onMessageEdited,
    void Function(WebSocketEvent event)? onMessageDeleted,
    void Function(WebSocketEvent event)? onReactionUpdated,
    void Function(WebSocketEvent event)? onMessageRead,
    void Function(WebSocketEvent event)? onMessageListened,
    void Function(WebSocketEvent event)? onTyping,
    void Function(WebSocketEvent event)? onEmojiInteraction,
    void Function(WebSocketEvent event)? onUserStatus,
    void Function(WebSocketEvent event)? onUserAvatarUpdated,
    void Function(WebSocketEvent event)? onUserAppearanceUpdated,
    void Function(WebSocketEvent event)? onUnreadCountUpdated,
    void Function(WebSocketEvent event)? onMessagePinned,
    void Function(WebSocketEvent event)? onMessageUnpinned,
    void Function(WebSocketEvent event)? onCallbackQueryAnswer,
    void Function(WebSocketEvent event)? onMessageViewsUpdated,
    void Function(WebSocketEvent event)? onPostCommentsUpdated,
    void Function(WebSocketEvent event)? onChatSettingsUpdated,
    void Function(WebSocketEvent event)? onMemberUpdated,
    void Function(WebSocketEvent event)? onChatDeleted,
    void Function(WebSocketEvent event)? onScheduledMessagesUpdated,
    void Function(WebSocketEvent event)? onJoinRequestsUpdated,
    void Function(WebSocketEvent event)? onMessageBurned,
    void Function(WebSocketEvent event)? onChatAutoDeleteUpdated,
    void Function(WebSocketEvent event)? onChatAppearanceUpdated,
    void Function(WebSocketEvent event)? onScreenshotTaken,
    void Function(WebSocketEvent event)? onForumTopicUpdated,
    void Function(WebSocketEvent event)? onUnreadBadgesUpdated,
    VoidCallback? onReconnect,
  }) {
    if (!_isInitialized) {
      init();
    }

    final sub = ChatSubscription(
      chatId: chatId,
      onNewMessage: onNewMessage,
      onMessageEdited: onMessageEdited,
      onMessageDeleted: onMessageDeleted,
      onReactionUpdated: onReactionUpdated,
      onMessageRead: onMessageRead,
      onMessageListened: onMessageListened,
      onTyping: onTyping,
      onEmojiInteraction: onEmojiInteraction,
      onUserStatus: onUserStatus,
      onUserAvatarUpdated: onUserAvatarUpdated,
      onUserAppearanceUpdated: onUserAppearanceUpdated,
      onUnreadCountUpdated: onUnreadCountUpdated,
      onMessagePinned: onMessagePinned,
      onMessageUnpinned: onMessageUnpinned,
      onCallbackQueryAnswer: onCallbackQueryAnswer,
      onMessageViewsUpdated: onMessageViewsUpdated,
      onPostCommentsUpdated: onPostCommentsUpdated,
      onChatSettingsUpdated: onChatSettingsUpdated,
      onMemberUpdated: onMemberUpdated,
      onChatDeleted: onChatDeleted,
      onScheduledMessagesUpdated: onScheduledMessagesUpdated,
      onJoinRequestsUpdated: onJoinRequestsUpdated,
      onMessageBurned: onMessageBurned,
      onChatAutoDeleteUpdated: onChatAutoDeleteUpdated,
      onChatAppearanceUpdated: onChatAppearanceUpdated,
      onScreenshotTaken: onScreenshotTaken,
      onForumTopicUpdated: onForumTopicUpdated,
      onUnreadBadgesUpdated: onUnreadBadgesUpdated,
      onReconnect: onReconnect,
    );

    _subscriptions.putIfAbsent(chatId, () => <ChatSubscription>{}).add(sub);
    return sub;
  }

  /// Unbinds a specific subscription.
  void unbindChat(ChatSubscription subscription) {
    final subs = _subscriptions[subscription.chatId];
    if (subs != null) {
      subs.remove(subscription);
      if (subs.isEmpty) {
        _subscriptions.remove(subscription.chatId);
      }
    }
  }

  /// Internal handler for incoming WebSocket events.
  Future<void> _handleWebSocketEvent(WebSocketEvent event) async {
    switch (event.type) {
      case WebSocketEventType.connected:
        _handleConnected();
        break;

      case WebSocketEventType.newMessage:
        await _handleNewMessage(event);
        break;

      case WebSocketEventType.messageEdited:
        await _handleMessageEdited(event);
        break;

      case WebSocketEventType.messageDeleted:
        await _handleMessageDeleted(event);
        break;

      case WebSocketEventType.messageReactionUpdated:
        await _handleReactionUpdated(event);
        break;

      case WebSocketEventType.messageRead:
        final readChatId = event.data['chat_id']?.toString();
        final readerId = event.data['reader_id']?.toString();
        final readAt = event.data['read_at']?.toString();
        final rawOutboxHwm =
            event.data['last_read_outbox_message_id'] ?? event.data['max_id'];
        final outboxHwm = rawOutboxHwm is num
            ? rawOutboxHwm.toInt()
            : int.tryParse(rawOutboxHwm?.toString() ?? '');
        final myUserId = WebSocketService().currentUserId;
        if (readChatId != null &&
            myUserId != null &&
            readerId != myUserId) {
          try {
            if (outboxHwm != null && outboxHwm > 0) {
              await AppDatabase().markOutboxMessagesReadUpTo(
                readChatId,
                myUserId,
                outboxHwm,
                readAt: readAt,
              );
            } else {
              await AppDatabase().markMessagesAsRead(
                readChatId,
                myUserId,
                readAt: readAt,
              );
            }
          } catch (_) {}
        }
        _dispatchForChat(readChatId, (s) => s.onMessageRead?.call(event));
        break;

      case WebSocketEventType.messageListened:
        final listenedChatId = event.data['chat_id']?.toString();
        final listenedMsgId = event.data['message_id']?.toString();
        final listenedReadAt = event.data['read_at']?.toString();
        final listenedAt = event.data['listened_at']?.toString();
        if (listenedMsgId != null) {
          try {
            await AppDatabase().updateMessageReadAndListened(
              listenedMsgId,
              readAt: listenedReadAt,
              listenedAt: listenedAt,
            );
          } catch (_) {}
        }
        _dispatchForChat(
            listenedChatId, (s) => s.onMessageListened?.call(event));
        break;

      case WebSocketEventType.typing:
        _dispatchForChat(event.data['chat_id']?.toString(),
            (s) => s.onTyping?.call(event));
        break;

      case WebSocketEventType.emojiInteraction:
        if (event.data['action']?.toString() == '__webrtc_call__') {
          break;
        }
        _dispatchForChat(event.data['chat_id']?.toString(),
            (s) => s.onEmojiInteraction?.call(event));
        break;

      case WebSocketEventType.unreadCountUpdated:
        final unreadChatId = event.data['chat_id']?.toString();
        final unreadCount = event.data['unread_count'] as int? ?? 0;
        final rawInboxHwm = event.data['last_read_inbox_message_id'];
        final inboxHwm = rawInboxHwm is num
            ? rawInboxHwm.toInt()
            : int.tryParse(rawInboxHwm?.toString() ?? '');
        if (unreadChatId != null) {
          if (CommunityService.isCommunityChannelId(unreadChatId)) {
            CommunityService.incrementChannelUnread(
              unreadChatId,
              absoluteUnread: unreadCount,
            );
          } else {
            try {
              if (inboxHwm != null && inboxHwm > 0) {
                await AppDatabase().updateChatReadHwm(
                  unreadChatId,
                  lastReadInboxMessageId: inboxHwm,
                  unreadCount: unreadCount,
                );
              } else {
                await AppDatabase()
                    .updateUnreadCount(unreadChatId, unreadCount);
              }
            } catch (_) {}
          }
        }
        _dispatchForChat(unreadChatId,
            (s) => s.onUnreadCountUpdated?.call(event));
        break;

      case WebSocketEventType.messagePinned:
        final pinChatId = event.data['chat_id']?.toString();
        final rawPinId =
            event.data['pinned_message_id'] ?? event.data['message_id'];
        final pinId = rawPinId is num
            ? rawPinId.toInt()
            : int.tryParse(rawPinId?.toString() ?? '');
        final hasPinIds = event.data.containsKey('pinned_message_ids');
        final pinIds = _extractPinnedIds(event.data['pinned_message_ids']);
        if (pinChatId != null) {
          try {
            await AppDatabase().updateChatPinnedMessageId(
              pinChatId,
              pinId,
              pinnedMessageIds: pinIds,
              updatePinnedMessageIds: hasPinIds,
            );
          } catch (_) {}
        }
        _dispatchForChat(pinChatId, (s) => s.onMessagePinned?.call(event));
        break;

      case WebSocketEventType.messageUnpinned:
        final unpinChatId = event.data['chat_id']?.toString();
        final rawNextPinId = event.data['pinned_message_id'];
        final nextPinId = rawNextPinId is num
            ? rawNextPinId.toInt()
            : int.tryParse(rawNextPinId?.toString() ?? '');
        final hasUnpinIds = event.data.containsKey('pinned_message_ids');
        final unpinIds = _extractPinnedIds(event.data['pinned_message_ids']);
        if (unpinChatId != null) {
          try {
            await AppDatabase().updateChatPinnedMessageId(
              unpinChatId,
              nextPinId,
              pinnedMessageIds: unpinIds,
              updatePinnedMessageIds: hasUnpinIds,
            );
          } catch (_) {}
        }
        _dispatchForChat(
            unpinChatId, (s) => s.onMessageUnpinned?.call(event));
        break;

      case WebSocketEventType.callbackQueryAnswer:
        final cbChatId = event.data['chat_id']?.toString();
        if (cbChatId != null) {
          _dispatchForChat(
              cbChatId, (s) => s.onCallbackQueryAnswer?.call(event));
        } else {
          _dispatchGlobal((s) => s.onCallbackQueryAnswer?.call(event));
        }
        break;

      case WebSocketEventType.newChat:
        await _handleNewChat(event);
        break;

      case WebSocketEventType.chatUpdate:
        await _handleChatUpdate(event);
        break;

      case WebSocketEventType.chatArchiveUpdated:
        final archiveChatId =
            event.data['chat_id']?.toString() ?? event.data['id']?.toString();
        final isArchived =
            event.data['is_archived'] == true || event.data['is_archived'] == 1;
        if (archiveChatId != null && archiveChatId.isNotEmpty) {
          try {
            await AppDatabase().setChatArchived(archiveChatId, isArchived);
          } catch (_) {}
        }
        break;

      case WebSocketEventType.userStatus:
        final statusUserId = event.data['user_id']?.toString();
        final statusIsOnline = event.data['is_online'] == true;
        final statusLastSeen = event.data['last_seen'] != null
            ? DateTimeUtils.parseUtcDateTime(event.data['last_seen'])
                ?.toIso8601String()
            : (statusIsOnline ? null : DateTime.now().toIso8601String());
        if (statusUserId != null) {
          try {
            await AppDatabase().updateUserStatus(
              statusUserId,
              isOnline: statusIsOnline,
              lastSeen: statusLastSeen,
            );
          } catch (_) {}
        }
        _dispatchGlobal((s) => s.onUserStatus?.call(event));
        break;

      case WebSocketEventType.userAvatarUpdated:
        await _handleUserAvatarUpdated(event);
        _dispatchGlobal((s) => s.onUserAvatarUpdated?.call(event));
        break;

      case WebSocketEventType.userAppearanceUpdated:
        final appUserId = event.data['user_id']?.toString();
        if (appUserId != null && appUserId.isNotEmpty) {
          PeerCustomizationCache.instance.mergeFromJson(appUserId, event.data);
          final cachedJson =
              PeerCustomizationCache.instance.getSync(appUserId)?.toJsonString();
          try {
            await AppDatabase().updateUserCustomizationJson(appUserId, cachedJson);
          } catch (_) {}
        }
        _dispatchGlobal((s) => s.onUserAppearanceUpdated?.call(event));
        break;

      case WebSocketEventType.messageViewsUpdated:
        await ChatService.handleWebSocketEvent(event);
        _dispatchForChat(
          event.data['chat_id']?.toString(),
          (s) => s.onMessageViewsUpdated?.call(event),
        );
        break;

      case WebSocketEventType.postCommentsUpdated:
        await ChatService.handleWebSocketEvent(event);
        _dispatchForChat(
          event.data['chat_id']?.toString(),
          (s) => s.onPostCommentsUpdated?.call(event),
        );
        break;

      case WebSocketEventType.chatSettingsUpdated:
        await ChatService.handleWebSocketEvent(event);
        _dispatchForChat(
          (event.data['chat_id'] ?? event.data['id'])?.toString(),
          (s) => s.onChatSettingsUpdated?.call(event),
        );
        break;

      case WebSocketEventType.memberUpdated:
        await ChatService.handleWebSocketEvent(event);
        _dispatchForChat(
          event.data['chat_id']?.toString(),
          (s) => s.onMemberUpdated?.call(event),
        );
        break;

      case WebSocketEventType.chatDeleted:
        await ChatService.handleWebSocketEvent(event);
        _dispatchForChat(
          (event.data['chat_id'] ?? event.data['id'])?.toString(),
          (s) => s.onChatDeleted?.call(event),
        );
        break;

      case WebSocketEventType.scheduledMessagesUpdated:
        await ChatService.handleWebSocketEvent(event);
        _dispatchForChat(
          (event.data['chat_id'] ?? event.data['id'])?.toString(),
          (s) => s.onScheduledMessagesUpdated?.call(event),
        );
        break;

      case WebSocketEventType.joinRequestsUpdated:
        await ChatService.handleWebSocketEvent(event);
        _dispatchForChat(
          (event.data['chat_id'] ?? event.data['id'])?.toString(),
          (s) => s.onJoinRequestsUpdated?.call(event),
        );
        break;

      case WebSocketEventType.chatUnreadMarked:
        final markChatId = event.data['chat_id']?.toString();
        final isMarked = event.data['is_marked_unread'] == true;
        if (markChatId != null && markChatId.isNotEmpty) {
          try {
            final dbChat = await AppDatabase().getChat(markChatId);
            if (isMarked && (dbChat == null || dbChat.unreadCount == 0)) {
              await AppDatabase().updateUnreadCount(markChatId, -1);
            } else if (!isMarked && dbChat?.unreadCount == -1) {
              await AppDatabase().updateUnreadCount(markChatId, 0);
            }
          } catch (_) {}
        }
        _dispatchForChat(
          markChatId,
          (s) => s.onUnreadCountUpdated?.call(event),
        );
        break;

      case WebSocketEventType.messageBurned:
        final burnChatId = event.data['chat_id']?.toString();
        final burnMsgId = event.data['message_id']?.toString();
        if (burnMsgId != null && burnMsgId.isNotEmpty) {
          try {
            await AppDatabase().markMessageBurned(
              burnMsgId,
              viewedAt: event.data['viewed_at']?.toString(),
              expiresAt: event.data['expires_at']?.toString(),
              isBurned: event.data['is_burned'] == true,
            );
          } catch (_) {}
        }
        _dispatchForChat(burnChatId, (s) => s.onMessageBurned?.call(event));
        break;

      case WebSocketEventType.chatAutoDeleteUpdated:
        final autoChatId = event.data['chat_id']?.toString();
        final rawTtl = event.data['message_auto_delete_time'] ??
            event.data['ttl_seconds'];
        final ttlSec = rawTtl is num
            ? rawTtl.toInt()
            : int.tryParse(rawTtl?.toString() ?? '') ?? 0;
        if (autoChatId != null && autoChatId.isNotEmpty) {
          try {
            await AppDatabase().updateChatAutoDeleteTime(autoChatId, ttlSec);
          } catch (_) {}
        }
        _dispatchForChat(
          autoChatId,
          (s) => s.onChatAutoDeleteUpdated?.call(event),
        );
        break;

      case WebSocketEventType.chatAppearanceUpdated:
        final appChatId = event.data['chat_id']?.toString();
        final rawApp = event.data['appearance'];
        if (appChatId != null && appChatId.isNotEmpty) {
          try {
            await AppDatabase().updateChatAppearanceJson(
              appChatId,
              rawApp is Map ? jsonEncode(rawApp) : null,
            );
          } catch (_) {}
        }
        _dispatchForChat(
          appChatId,
          (s) => s.onChatAppearanceUpdated?.call(event),
        );
        break;

      case WebSocketEventType.screenshotTaken:
        final scrChatId = event.data['chat_id']?.toString();
        _dispatchForChat(scrChatId, (s) => s.onScreenshotTaken?.call(event));
        break;

      case WebSocketEventType.forumTopicUpdated:
        final topicChatId = event.data['chat_id']?.toString();
        await ChatService.handleWebSocketEvent(event);
        _dispatchForChat(
          topicChatId,
          (s) => s.onForumTopicUpdated?.call(event),
        );
        break;

      case WebSocketEventType.unreadBadgesUpdated:
        final badgeChatId = event.data['chat_id']?.toString();
        await ChatService.handleWebSocketEvent(event);
        _dispatchForChat(
          badgeChatId,
          (s) => s.onUnreadBadgesUpdated?.call(event),
        );
        break;

      default:
        final rawNorm = (event.rawType.isNotEmpty
                ? event.rawType
                : (event.data['__raw_type'] ?? event.data['type'] ?? '')
                    .toString())
            .replaceAll('.', '_');
        final payload = event.data['payload'] is Map<String, dynamic>
            ? event.data['payload'] as Map<String, dynamic>
            : event.data;
        if (rawNorm == 'community_updated') {
          final commMap = payload['community'] is Map
              ? Map<String, dynamic>.from(payload['community'] as Map)
              : null;
          if (commMap != null) {
            CommunityService.cacheCommunity(Community.fromJson(commMap));
          }
        } else if (rawNorm == 'community_deleted') {
          final commId =
              (payload['community_id'] ?? payload['id'] ?? '').toString();
          if (commId.isNotEmpty) {
            CommunityService.removeCommunityFromCache(commId);
          }
        }
        break;
    }
  }

  void _handleConnected() {
    for (final subs in _subscriptions.values) {
      for (final s in List.of(subs)) {
        s.onReconnect?.call();
      }
    }
    try {
      SyncService().syncFromServer();
    } catch (_) {}
  }

  void _dispatchForChat(
      String? chatId, void Function(ChatSubscription) callback) {
    if (chatId == null) return;
    final subs = _subscriptions[chatId];
    if (subs != null) {
      for (final s in List.of(subs)) {
        callback(s);
      }
    }
  }

  void _dispatchGlobal(void Function(ChatSubscription) callback) {
    for (final subs in _subscriptions.values) {
      for (final s in List.of(subs)) {
        callback(s);
      }
    }
  }

  Future<void> _handleNewMessage(WebSocketEvent event) async {
    final chatId = event.data['chat_id']?.toString();
    final messageData =
        event.data['message'] as Map<String, dynamic>? ?? event.data;
    if (chatId == null) return;

    try {
      await _persistMessageToDrift(chatId, messageData);

      final content = messageData['content']?.toString() ?? '';
      final createdAt = messageData['created_at']?.toString() ??
          DateTime.now().toIso8601String();
      final messageType = messageData['message_type']?.toString() ?? 'text';
      final isRound = messageData['is_round'] == true || messageType == 'round';
      final fileUrl = messageData['file_url']?.toString();
      final groupedId = messageData['grouped_id']?.toString();

      final isCommunityChannel =
          event.data['community_id'] != null ||
          messageData['community_id'] != null ||
          CommunityService.isCommunityChannelId(chatId);

      final threadRootId =
          messageData['thread_root_message_id']?.toString().trim();
      final isThreadComment = threadRootId != null && threadRootId.isNotEmpty;

      final existing = await AppDatabase().getChat(chatId);
      if (isCommunityChannel) {
        if (existing != null) {
          await AppDatabase().deleteChat(chatId);
        }
        final hasActiveSub =
            (_subscriptions[chatId]?.isNotEmpty ?? false);
        if (!hasActiveSub) {
          CommunityService.incrementChannelUnread(chatId);
        }
      } else if (existing == null && !isThreadComment) {
        final chatType = event.data['chat_type']?.toString() ?? 'private';
        await AppDatabase().saveChat(ChatsCompanion(
          chatId: drift.Value(chatId),
          chatType: drift.Value(chatType),
          name: drift.Value(messageData['sender_name']?.toString() ?? ''),
          avatarUrl: drift.Value(messageData['sender_avatar_url']?.toString()),
          lastMessage: drift.Value(content),
          lastMessageTime: drift.Value(createdAt),
          lastMessageType: drift.Value(messageType),
          lastMessageIsRound: drift.Value(isRound),
          lastMessageFileUrl: drift.Value(fileUrl),
          lastMessageGroupedId: drift.Value(groupedId),
          lastMessageSenderId:
              drift.Value(messageData['sender_id']?.toString()),
          lastMessageSenderName:
              drift.Value(messageData['sender_name']?.toString()),
          otherUserId: drift.Value(messageData['sender_id']?.toString()),
          updatedAt: drift.Value(createdAt),
          unreadCount: const drift.Value(0),
          isOnline: const drift.Value(false),
          isPinned: const drift.Value(false),
          showAuthorProfiles: drift.Value(chatType != 'channel'),
        ));
      } else if (existing != null) {
        await AppDatabase().updateChatLastMessage(
          chatId: chatId,
          content: content,
          createdAt: createdAt,
          messageType: messageType,
          isRound: isRound,
          fileUrl: fileUrl,
          groupedId: groupedId,
          senderId: messageData['sender_id']?.toString(),
          senderName: messageData['sender_name']?.toString(),
          incrementUnread: false,
        );
      }
    } catch (e) {
      debugPrint('ChatRealtimeManager: Error saving message to Drift: $e');
    }

    _dispatchForChat(chatId, (s) => s.onNewMessage?.call(event));
  }

  List<int> _extractPinnedIds(dynamic raw) {
    if (raw is! List) return const [];
    final ids = <int>[];
    for (final item in raw) {
      final parsed = item is num ? item.toInt() : int.tryParse(item.toString());
      if (parsed != null && parsed > 0) ids.add(parsed);
    }
    return ids;
  }

  Future<void> _handleMessageEdited(WebSocketEvent event) async {
    final chatId = event.data['chat_id']?.toString();
    final messageId =
        event.data['message_id']?.toString() ?? event.data['id']?.toString();
    final content = event.data['content']?.toString();

    if (messageId != null) {
      String? entitiesStr;
      if (event.data['entities'] != null) {
        entitiesStr = event.data['entities'] is String
            ? event.data['entities'] as String
            : jsonEncode(event.data['entities']);
      }
      Map<String, dynamic>? incomingMediaMap;
      if (event.data['media_payload'] is Map) {
        incomingMediaMap =
            Map<String, dynamic>.from(event.data['media_payload'] as Map);
      } else if (event.data['media_payload'] is String &&
          (event.data['media_payload'] as String).isNotEmpty) {
        try {
          final dec = jsonDecode(event.data['media_payload'] as String);
          if (dec is Map) incomingMediaMap = Map<String, dynamic>.from(dec);
        } catch (_) {}
      } else if (event.data['poll'] is Map) {
        incomingMediaMap =
            Map<String, dynamic>.from(event.data['poll'] as Map);
      }

      DbMessage? existingMsg;
      try {
        existingMsg = await AppDatabase().getMessageByServerId(messageId);
      } catch (_) {}

      Map<String, dynamic>? existingMediaMap;
      if (existingMsg?.mediaPayload != null &&
          existingMsg!.mediaPayload!.isNotEmpty) {
        try {
          final dec = jsonDecode(existingMsg.mediaPayload!);
          if (dec is Map) existingMediaMap = Map<String, dynamic>.from(dec);
        } catch (_) {}
      }

      final mergedMedia = ChatService.mergeIncomingMediaPayload(
        existingMediaMap,
        incomingMediaMap,
        replyMarkup: event.data['reply_markup'],
      );
      final String? mediaPayloadStr =
          mergedMedia != null ? jsonEncode(mergedMedia) : null;

      final bool? hasMediaSpoiler = event.data.containsKey('has_media_spoiler')
          ? (event.data['has_media_spoiler'] == true ||
              event.data['has_media_spoiler'] == 1)
          : null;
      final isPollEvent = event.data['message_type'] == 'poll' ||
          existingMsg?.messageType == 'poll';
      final bool effectiveIsEdited = event.data.containsKey('is_edited')
          ? (event.data['is_edited'] == true
              ? true
              : (existingMsg?.isEdited ?? false))
          : (isPollEvent ? (existingMsg?.isEdited ?? false) : true);
      final effectiveContent = content ?? existingMsg?.content ?? '';

      final bool? invertMedia = event.data.containsKey('invert_media')
          ? (event.data['invert_media'] == true ||
              event.data['invert_media'] == 1)
          : null;
      final String? editedFileUrl = event.data.containsKey('file_url')
          ? event.data['file_url']?.toString()
          : null;
      final String? editedFileName = event.data.containsKey('file_name')
          ? event.data['file_name']?.toString()
          : null;
      final String? editedMessageType = event.data.containsKey('message_type')
          ? event.data['message_type']?.toString()
          : null;

      try {
        await AppDatabase().updateMessageContent(
          messageId,
          effectiveContent,
          entitiesStr,
          mediaPayloadStr,
          effectiveIsEdited,
          hasMediaSpoiler,
          editedFileUrl,
          editedFileName,
          editedMessageType,
          invertMedia,
        );
        if (chatId != null) {
          await AppDatabase().refreshChatLastMessageFromDb(chatId);
        }
      } catch (e) {
        debugPrint('ChatRealtimeManager: Error updating message in Drift: $e');
      }
    }

    _dispatchForChat(chatId, (s) => s.onMessageEdited?.call(event));
  }

  Future<void> _handleMessageDeleted(WebSocketEvent event) async {
    final chatId = event.data['chat_id']?.toString();
    final messageId =
        event.data['message_id']?.toString() ?? event.data['id']?.toString();
    final rawBatch = event.data['message_ids'];
    final batchIds = <String>[
      if (rawBatch is List)
        ...rawBatch.map((e) => e.toString()).where((e) => e.isNotEmpty),
      if (messageId != null && messageId.isNotEmpty) messageId,
    ];

    if (batchIds.isNotEmpty) {
      try {
        if (batchIds.length == 1) {
          await AppDatabase().deleteMessage(batchIds.first);
        } else {
          await AppDatabase().deleteMessagesBatch(batchIds);
        }
        if (chatId != null) {
          await AppDatabase().refreshChatLastMessageFromDb(chatId);
        }
      } catch (e) {
        debugPrint(
            'ChatRealtimeManager: Error deleting message from Drift: $e');
      }
    }

    _dispatchForChat(chatId, (s) => s.onMessageDeleted?.call(event));
  }

  Future<void> _handleNewChat(WebSocketEvent event) async {
    final chatData = event.data['chat'] as Map<String, dynamic>? ?? event.data;
    final chatId = chatData['chat_id']?.toString() ?? chatData['id']?.toString();
    if (chatId == null) return;
    try {
      final chatType = chatData['chat_type']?.toString() ?? 'private';
      final showAuthor = chatData.containsKey('show_author_profiles')
          ? (chatData['show_author_profiles'] == true ||
              chatData['show_author_profiles'] == 1)
          : (chatType != 'channel');
      final perms = GroupDefaultPermissions.tryParse(
        chatData['default_permissions'] ?? chatData['chat_permissions'],
      );
      final reactions = ReactionSettings.fromChatJson(chatData);
      final linkedChatId = chatData['linked_chat_id']?.toString().trim();

      await AppDatabase().saveChat(ChatsCompanion(
        chatId: drift.Value(chatId),
        chatType: drift.Value(chatType),
        name: drift.Value(chatData['name']?.toString() ?? ''),
        avatarUrl: drift.Value(chatData['avatar_url']?.toString()),
        lastMessage: drift.Value(chatData['last_message']?.toString()),
        lastMessageTime: drift.Value(chatData['last_message_time']?.toString()),
        lastMessageType: drift.Value(chatData['last_message_type']?.toString()),
        lastMessageIsRound: drift.Value(chatData['last_message_is_round'] == true),
        lastMessageFileUrl: drift.Value(chatData['last_message_file_url']?.toString()),
        lastMessageGroupedId: drift.Value(chatData['last_message_grouped_id']?.toString()),
        otherUserId: drift.Value(chatData['other_user_id']?.toString()),
        updatedAt: drift.Value(chatData['updated_at']?.toString() ?? DateTime.now().toIso8601String()),
        unreadCount: drift.Value(chatData['unread_count'] as int? ?? 0),
        isOnline: drift.Value(chatData['is_online'] == true),
        lastSeen: drift.Value(chatData['last_seen']?.toString()),
        isPinned: drift.Value(chatData['is_pinned'] == true),
        showAuthorProfiles: drift.Value(showAuthor),
        signMessages: drift.Value(
          chatData['sign_messages'] == true || chatData['sign_messages'] == 1,
        ),
        linkedChatId: drift.Value(
          (linkedChatId != null && linkedChatId.isNotEmpty)
              ? linkedChatId
              : null,
        ),
        myRole: drift.Value(chatData['my_role']?.toString()),
        lastMessageSenderId:
            drift.Value(chatData['last_message_sender_id']?.toString()),
        lastMessageSenderName:
            drift.Value(chatData['last_message_sender_name']?.toString()),
        hasActiveCall: drift.Value(
          chatData['has_active_call'] == true ||
              chatData['has_active_call'] == 1,
        ),
        chatPermissionsJson: perms != null
            ? drift.Value(jsonEncode(perms.toJson()))
            : const drift.Value.absent(),
        reactionSettingsJson: reactions != null
            ? drift.Value(jsonEncode(reactions.toJson()))
            : const drift.Value.absent(),
        peerCustomizationJson: drift.Value(chatData['peer_customization'] is Map
            ? jsonEncode(chatData['peer_customization'])
            : chatData['peer_customization']?.toString()),
        hasProtectedContent: drift.Value(
          chatData['has_protected_content'] == true ||
              chatData['has_protected_content'] == 1,
        ),
        pinnedMessageIdsJson: chatData['pinned_message_ids'] is List
            ? drift.Value(jsonEncode(
                _extractPinnedIds(chatData['pinned_message_ids'])))
            : const drift.Value.absent(),
      ));
    } catch (e) {
      debugPrint('ChatRealtimeManager: Error saving new chat to Drift: $e');
    }
  }

  Future<void> _handleChatUpdate(WebSocketEvent event) async {
    final chatId = event.data['chat_id']?.toString() ?? event.data['id']?.toString();
    if (chatId == null) return;
    try {
      final existing = await AppDatabase().getChat(chatId);
      if (existing == null) return;

      final perms = GroupDefaultPermissions.tryParse(
        event.data['default_permissions'] ?? event.data['chat_permissions'],
      );
      final reactions = ReactionSettings.fromChatJson(event.data);
      final rawLinked = event.data['linked_chat_id']?.toString().trim();

      final companion = ChatsCompanion(
        chatId: drift.Value(chatId),
        name: event.data.containsKey('name')
            ? drift.Value(event.data['name'].toString())
            : drift.Value(existing.name),
        avatarUrl: event.data.containsKey('avatar_url')
            ? drift.Value(event.data['avatar_url']?.toString())
            : drift.Value(existing.avatarUrl),
        unreadCount: event.data.containsKey('unread_count')
            ? drift.Value(event.data['unread_count'] as int? ?? existing.unreadCount)
            : drift.Value(existing.unreadCount),
        isPinned: event.data.containsKey('is_pinned')
            ? drift.Value(event.data['is_pinned'] as bool? ?? existing.isPinned)
            : drift.Value(existing.isPinned),
        isArchived: event.data.containsKey('is_archived')
            ? drift.Value(
                event.data['is_archived'] == true || event.data['is_archived'] == 1)
            : drift.Value(existing.isArchived),
        updatedAt: event.data.containsKey('updated_at')
            ? drift.Value(event.data['updated_at'].toString())
            : drift.Value(existing.updatedAt),
        showAuthorProfiles: event.data.containsKey('show_author_profiles')
            ? drift.Value(
                event.data['show_author_profiles'] == true ||
                    event.data['show_author_profiles'] == 1,
              )
            : drift.Value(existing.showAuthorProfiles),
        signMessages: event.data.containsKey('sign_messages')
            ? drift.Value(
                event.data['sign_messages'] == true ||
                    event.data['sign_messages'] == 1,
              )
            : drift.Value(existing.signMessages),
        linkedChatId: event.data.containsKey('linked_chat_id')
            ? drift.Value(
                (rawLinked != null && rawLinked.isNotEmpty) ? rawLinked : null,
              )
            : drift.Value(existing.linkedChatId),
        myRole: event.data.containsKey('my_role')
            ? drift.Value(event.data['my_role']?.toString())
            : drift.Value(existing.myRole),
        hasActiveCall: event.data.containsKey('has_active_call')
            ? drift.Value(
                event.data['has_active_call'] == true ||
                    event.data['has_active_call'] == 1,
              )
            : drift.Value(existing.hasActiveCall),
        chatPermissionsJson: perms != null
            ? drift.Value(jsonEncode(perms.toJson()))
            : drift.Value(existing.chatPermissionsJson),
        reactionSettingsJson: reactions != null
            ? drift.Value(jsonEncode(reactions.toJson()))
            : drift.Value(existing.reactionSettingsJson),
        peerCustomizationJson: event.data.containsKey('peer_customization')
            ? drift.Value(event.data['peer_customization'] is Map
                ? jsonEncode(event.data['peer_customization'])
                : event.data['peer_customization']?.toString())
            : drift.Value(existing.peerCustomizationJson),
        hasProtectedContent: event.data.containsKey('has_protected_content')
            ? drift.Value(
                event.data['has_protected_content'] == true ||
                    event.data['has_protected_content'] == 1,
              )
            : drift.Value(existing.hasProtectedContent),
        pinnedMessageIdsJson: event.data.containsKey('pinned_message_ids')
            ? drift.Value(jsonEncode(
                _extractPinnedIds(event.data['pinned_message_ids'])))
            : drift.Value(existing.pinnedMessageIdsJson),
      );
      await AppDatabase().saveChat(companion);
    } catch (e) {
      debugPrint('ChatRealtimeManager: Error updating chat in Drift: $e');
    }
  }

  Future<void> _handleUserAvatarUpdated(WebSocketEvent event) async {
    final userId = event.data['user_id']?.toString();
    final avatarUrl = event.data['avatar_url']?.toString();
    if (userId == null) return;
    try {
      await AppDatabase().updateUserAvatarInChats(userId, avatarUrl);
      final allChats = await AppDatabase().getChats();
      for (final chat in allChats) {
        if (chat.chatType == 'private' && chat.otherUserId == userId) {
          await AppDatabase().updateChatAvatar(chat.chatId, avatarUrl);
        }
      }
    } catch (e) {
      debugPrint('ChatRealtimeManager: Error updating user avatar in Drift: $e');
    }
  }

  Future<void> _handleReactionUpdated(WebSocketEvent event) async {
    final chatId = event.data['chat_id']?.toString();
    final messageId = event.data['message_id']?.toString();

    if (messageId != null) {
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

      final Set<String> myReactions = {};
      if (event.data['my_reactions'] is List) {
        for (final e in event.data['my_reactions']) {
          myReactions.add(e.toString());
        }
      }

      try {
        await AppDatabase()
            .updateMessageReactions(messageId, reactionsMap, myReactions);
      } catch (e) {
        debugPrint(
            'ChatRealtimeManager: Error updating reactions in Drift: $e');
      }
    }

    _dispatchForChat(chatId, (s) => s.onReactionUpdated?.call(event));
  }

  Future<void> _persistMessageToDrift(
      String chatId, Map<String, dynamic> msgData) async {
    final serverId =
        msgData['id']?.toString() ?? msgData['server_id']?.toString();
    if (serverId == null) return;

    String? entitiesStr;
    if (msgData['entities'] != null) {
      entitiesStr = msgData['entities'] is String
          ? msgData['entities'] as String
          : jsonEncode(msgData['entities']);
    }

    String? linkPreviewOptionsStr;
    final msgType = msgData['message_type']?.toString() ?? 'text';
    if (msgType == 'voice' &&
        (msgData['waveform'] != null || msgData['duration'] != null)) {
      linkPreviewOptionsStr = jsonEncode({
        if (msgData['waveform'] != null) 'waveform': msgData['waveform'],
        if (msgData['duration'] != null) 'duration': msgData['duration'],
      });
    } else if (msgData['link_preview_options'] != null) {
      linkPreviewOptionsStr = msgData['link_preview_options'] is String
          ? msgData['link_preview_options'] as String
          : jsonEncode(msgData['link_preview_options']);
    }
    if (linkPreviewOptionsStr == null && msgData['media_payload'] != null) {
      linkPreviewOptionsStr = msgData['media_payload'] is String
          ? msgData['media_payload'] as String
          : jsonEncode(msgData['media_payload']);
    }

    final bool invertMedia = msgData['invert_media'] == true ||
        msgData['invert_media'] == 1 ||
        msgData['invert_media'] == 'true';
    final String? groupedId = msgData['grouped_id']?.toString();
    final bool isRound =
        msgData['is_round'] == true || msgType == 'round';

    Map<String, dynamic> mediaPayloadMap = {};
    if (msgData['media_payload'] is Map) {
      mediaPayloadMap = Map<String, dynamic>.from(msgData['media_payload'] as Map);
    } else if (msgData['media_payload'] is String &&
        (msgData['media_payload'] as String).isNotEmpty) {
      try {
        final decoded = jsonDecode(msgData['media_payload'] as String);
        if (decoded is Map) {
          mediaPayloadMap = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    if (msgData['reply_markup'] != null) {
      mediaPayloadMap['reply_markup'] = msgData['reply_markup'];
    }
    if (msgData['via_bot_id'] != null) {
      mediaPayloadMap['via_bot_id'] = msgData['via_bot_id'];
    }
    if (msgData['via_bot_username'] != null) {
      mediaPayloadMap['via_bot_username'] = msgData['via_bot_username'];
    }
    if (msgData['can_comment'] == true) {
      mediaPayloadMap['can_comment'] = true;
    }
    if (msgData['channel_post_id'] != null &&
        msgData['channel_post_id'].toString().isNotEmpty) {
      mediaPayloadMap['channel_post_id'] =
          msgData['channel_post_id'].toString();
    }
    final String? mediaPayloadStr =
        mediaPayloadMap.isNotEmpty ? jsonEncode(mediaPayloadMap) : null;
    final recentRepliersList =
        RecentReplier.parseList(msgData['recent_repliers']);
    final String? recentRepliersStr = recentRepliersList.isNotEmpty
        ? jsonEncode(recentRepliersList.map((r) => r.toJson()).toList())
        : null;
    final String? rawThreadRootId =
        msgData['thread_root_message_id']?.toString().trim();

    final String? senderCustJsonStr = () {
      final raw = msgData['sender_customization'];
      if (raw is Map) {
        final cust = PeerCustomization.fromJson(Map<String, dynamic>.from(raw));
        final sid = msgData['sender_id']?.toString() ?? '';
        if (sid.isNotEmpty) {
          PeerCustomizationCache.instance.put(sid, cust, notify: false);
        }
        return cust.toJsonString();
      } else if (raw is String && raw.isNotEmpty) {
        return raw;
      }
      return null;
    }();
    final String? fwdAvatarUrl =
        (msgData['forwarded_from_avatar_url'] ?? msgData['forward_from_avatar_url'])
            ?.toString();

    await AppDatabase().saveMessage(MessagesCompanion(
      serverId: drift.Value(serverId),
      localId: drift.Value(_uuid.v4()),
      chatId: drift.Value(chatId),
      senderId: drift.Value(msgData['sender_id']?.toString() ?? ''),
      content: drift.Value(msgData['content']?.toString() ?? ''),
      messageType: drift.Value(msgType),
      fileUrl: drift.Value(msgData['file_url']?.toString()),
      fileName: drift.Value(msgData['file_name']?.toString()),
      replyToMessageId:
          drift.Value(msgData['reply_to_message_id']?.toString()),
      isQuote: drift.Value(msgData['is_quote'] as bool? ?? false),
      quoteText: drift.Value(msgData['quote_text']?.toString()),
      quoteOffset: drift.Value(msgData['quote_offset'] as int? ?? 0),
      quoteLength: drift.Value(msgData['quote_length'] as int? ?? 0),
      replyToSenderId:
          drift.Value(msgData['reply_to_sender_id']?.toString()),
      replyToSenderName:
          drift.Value(msgData['reply_to_sender_name']?.toString()),
      replyToContent: drift.Value(msgData['reply_to_content']?.toString()),
      replyToMessageType:
          drift.Value(msgData['reply_to_message_type']?.toString() ?? 'text'),
      isRead: drift.Value(msgData['is_read'] == true),
      isEdited: drift.Value(msgData['is_edited'] == true),
      sendStatus: drift.Value(MessageSendStatus.sent.index),
      senderName: drift.Value(msgData['sender_name']?.toString()),
      senderAvatarUrl: drift.Value(msgData['sender_avatar_url']?.toString()),
      createdAt: drift.Value(msgData['created_at']?.toString() ??
          DateTime.now().toIso8601String()),
      isForward: drift.Value(msgData['is_forward'] == true ||
          msgData['forward_from_id'] != null ||
          (msgData['forward_from_name'] != null &&
              msgData['forward_from_name'].toString().isNotEmpty)),
      forwardFromId: drift.Value(msgData['forward_from_id']?.toString()),
      forwardFromName: drift.Value(msgData['forward_from_name']?.toString()),
      entities: drift.Value(entitiesStr),
      linkPreviewOptions: drift.Value(linkPreviewOptionsStr),
      mediaPayload: drift.Value(mediaPayloadStr),
      invertMedia: drift.Value(invertMedia),
      isRound: drift.Value(isRound),
      groupedId: drift.Value(groupedId),
      forwardFromAvatarUrl: drift.Value(fwdAvatarUrl),
      senderCustomizationJson: drift.Value(senderCustJsonStr),
      viewsCount: drift.Value((msgData['views_count'] as num?)?.toInt() ?? 0),
      authorSignature: drift.Value(msgData['author_signature']?.toString()),
      postAuthorId: drift.Value(msgData['post_author_id']?.toString()),
      senderRole: drift.Value(msgData['sender_role']?.toString()),
      senderAdminTitle: drift.Value(msgData['sender_admin_title']?.toString()),
      isFromAnonymousAdmin:
          drift.Value(msgData['is_from_anonymous_admin'] == true),
      isSilent: drift.Value(msgData['is_silent'] == true),
      commentsCount:
          drift.Value((msgData['comments_count'] as num?)?.toInt() ?? 0),
      recentRepliersJson: drift.Value(recentRepliersStr),
      threadRootMessageId: drift.Value(
        (rawThreadRootId != null && rawThreadRootId.isNotEmpty)
            ? rawThreadRootId
            : null,
      ),
      hasMediaSpoiler: drift.Value(
        msgData['has_media_spoiler'] == true ||
            msgData['has_media_spoiler'] == 1 ||
            mediaPayloadMap['has_media_spoiler'] == true,
      ),
      expiresAt: drift.Value(msgData['expires_at']?.toString()),
      ttlSeconds: drift.Value((msgData['ttl_seconds'] as num?)?.toInt() ??
          int.tryParse(msgData['ttl_seconds']?.toString() ?? '') ??
          0),
      isViewOnce: drift.Value(
        msgData['is_view_once'] == true || msgData['is_view_once'] == 1,
      ),
      viewedAt: drift.Value(msgData['viewed_at']?.toString()),
      isBurned: drift.Value(msgData['is_burned'] == true ||
          ((msgData['is_view_once'] == true || msgData['is_view_once'] == 1) &&
              msgData['viewed_at'] != null &&
              msgData['viewed_at'].toString().isNotEmpty)),
      replyToChatId: drift.Value(msgData['reply_to_chat_id']?.toString()),
      replyToChatName: drift.Value(msgData['reply_to_chat_name']?.toString()),
      replyToChatType: drift.Value(msgData['reply_to_chat_type']?.toString()),
      effectId: drift.Value(msgData['effect_id']?.toString()),
      topicId: drift.Value(
        (msgData['topic_id'] as num?)?.toInt() ??
            int.tryParse(msgData['topic_id']?.toString() ?? ''),
      ),
      forwardsCount: drift.Value(
        (msgData['forwards_count'] as num?)?.toInt() ?? 0,
      ),
      senderChatId: drift.Value(msgData['sender_chat_id']?.toString()),
      senderChatName: drift.Value(msgData['sender_chat_name']?.toString()),
      senderChatAvatarUrl:
          drift.Value(msgData['sender_chat_avatar_url']?.toString()),
      savedTagsJson: msgData['saved_tags'] is List
          ? drift.Value(jsonEncode(msgData['saved_tags']))
          : const drift.Value.absent(),
    ));
  }
}
