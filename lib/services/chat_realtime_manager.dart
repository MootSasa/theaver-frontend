import 'dart:async';
import 'dart:convert';
import 'package:drift/drift.dart' as drift;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import 'database/app_database.dart';
import 'websocket_service.dart';

/// Subscription handle for a specific chat.
class ChatSubscription {
  final String chatId;
  final void Function(WebSocketEvent event)? onNewMessage;
  final void Function(WebSocketEvent event)? onMessageEdited;
  final void Function(WebSocketEvent event)? onMessageDeleted;
  final void Function(WebSocketEvent event)? onReactionUpdated;
  final void Function(WebSocketEvent event)? onMessageRead;
  final void Function(WebSocketEvent event)? onTyping;
  final void Function(WebSocketEvent event)? onUserStatus;
  final void Function(WebSocketEvent event)? onUserAvatarUpdated;
  final void Function(WebSocketEvent event)? onUserAppearanceUpdated;
  final void Function(WebSocketEvent event)? onUnreadCountUpdated;
  final VoidCallback? onReconnect;

  ChatSubscription({
    required this.chatId,
    this.onNewMessage,
    this.onMessageEdited,
    this.onMessageDeleted,
    this.onReactionUpdated,
    this.onMessageRead,
    this.onTyping,
    this.onUserStatus,
    this.onUserAvatarUpdated,
    this.onUserAppearanceUpdated,
    this.onUnreadCountUpdated,
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
    void Function(WebSocketEvent event)? onTyping,
    void Function(WebSocketEvent event)? onUserStatus,
    void Function(WebSocketEvent event)? onUserAvatarUpdated,
    void Function(WebSocketEvent event)? onUserAppearanceUpdated,
    void Function(WebSocketEvent event)? onUnreadCountUpdated,
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
      onTyping: onTyping,
      onUserStatus: onUserStatus,
      onUserAvatarUpdated: onUserAvatarUpdated,
      onUserAppearanceUpdated: onUserAppearanceUpdated,
      onUnreadCountUpdated: onUnreadCountUpdated,
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
        _dispatchForChat(event.data['chat_id']?.toString(),
            (s) => s.onMessageRead?.call(event));
        break;

      case WebSocketEventType.typing:
        _dispatchForChat(event.data['chat_id']?.toString(),
            (s) => s.onTyping?.call(event));
        break;

      case WebSocketEventType.unreadCountUpdated:
        _dispatchForChat(event.data['chat_id']?.toString(),
            (s) => s.onUnreadCountUpdated?.call(event));
        break;

      case WebSocketEventType.userStatus:
        _dispatchGlobal((s) => s.onUserStatus?.call(event));
        break;

      case WebSocketEventType.userAvatarUpdated:
        _dispatchGlobal((s) => s.onUserAvatarUpdated?.call(event));
        break;

      case WebSocketEventType.userAppearanceUpdated:
        _dispatchGlobal((s) => s.onUserAppearanceUpdated?.call(event));
        break;

      default:
        break;
    }
  }

  void _handleConnected() {
    for (final subs in _subscriptions.values) {
      for (final s in List.of(subs)) {
        s.onReconnect?.call();
      }
    }
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
    } catch (e) {
      debugPrint('ChatRealtimeManager: Error saving message to Drift: $e');
    }

    _dispatchForChat(chatId, (s) => s.onNewMessage?.call(event));
  }

  Future<void> _handleMessageEdited(WebSocketEvent event) async {
    final chatId = event.data['chat_id']?.toString();
    final messageId =
        event.data['message_id']?.toString() ?? event.data['id']?.toString();
    final content = event.data['content']?.toString() ?? '';

    if (messageId != null) {
      String? entitiesStr;
      if (event.data['entities'] != null) {
        entitiesStr = event.data['entities'] is String
            ? event.data['entities'] as String
            : jsonEncode(event.data['entities']);
      }
      try {
        await AppDatabase()
            .updateMessageContent(messageId, content, entitiesStr);
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

    if (messageId != null) {
      try {
        await AppDatabase().deleteMessage(messageId);
      } catch (e) {
        debugPrint(
            'ChatRealtimeManager: Error deleting message from Drift: $e');
      }
    }

    _dispatchForChat(chatId, (s) => s.onMessageDeleted?.call(event));
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
      entities: drift.Value(entitiesStr),
      linkPreviewOptions: drift.Value(linkPreviewOptionsStr),
      invertMedia: drift.Value(invertMedia),
      isRound: drift.Value(isRound),
      groupedId: drift.Value(groupedId),
    ));
  }
}
