import 'dart:async';
import 'package:flutter/foundation.dart';
import 'websocket_service.dart';
import 'chat_service.dart';
import 'auth_service.dart';
import 'notification_service.dart';

/// Provider that manages unread message counts per chat.
/// It is the single source of truth for unread counts on the client.
/// Updates come from:
///   1. Server via WebSocket (unread_count_updated) — authoritative
///   2. Initial load from server API (getChats)
///   3. Optimistic local updates (increment on new_message, decrement on mark-as-read)
class UnreadCountProvider extends ChangeNotifier {
  final WebSocketService _wsService = WebSocketService();

  /// Map of chatId -> unreadCount
  final Map<String, int> _counts = {};

  /// Currently open chat ID — messages in this chat should NOT increment unread
  String? _currentlyOpenChatId;

  /// Current user ID for filtering own messages
  String? _currentUserId;

  /// Stream subscription for WebSocket events
  StreamSubscription<WebSocketEvent>? _wsSubscription;

  /// Get unread count for a specific chat
  int getCount(String chatId) => _counts[chatId] ?? 0;

  /// Get total unread count across all chats
  int get totalUnread => _counts.values.fold(0, (sum, count) => sum + count);

  /// Get number of chats with unread messages for a specific filter
  int getUnreadChatCountForFilter(bool Function(String chatId, String chatType) matchesFilter) {
    int count = 0;
    _counts.forEach((chatId, unreadCount) {
      // We need chat type info here — the caller should pass it
      if (unreadCount > 0) count++;
    });
    return count;
  }

  /// Set currently open chat (called when navigating into a chat screen)
  void setOpenChat(String? chatId) {
    _currentlyOpenChatId = chatId;
    NotificationService().setActiveChat(chatId);
  }

  /// Initialize: load counts from server and subscribe to WebSocket
  Future<void> initialize() async {
    _currentUserId = await AuthService.getUserId();

    // Subscribe to WebSocket events
    _wsSubscription = _wsService.eventStream.listen(_handleWebSocketEvent);
    _wsService.subscribe(WebSocketEventType.unreadCountUpdated, _onUnreadCountUpdated);
    _wsService.subscribe(WebSocketEventType.newMessage, _onNewMessage);
  }

  /// Load counts from the server (getChats API returns unread_count per chat)
  void loadFromChats(List<Chat> chats) {
    _counts.clear();
    for (final chat in chats) {
      if (chat.unreadCount > 0) {
        _counts[chat.id] = chat.unreadCount;
      }
    }
    notifyListeners();
  }

  /// Set count for a specific chat (from server response)
  void setCount(String chatId, int count) {
    if (count == 0) {
      _counts.remove(chatId);
    } else {
      _counts[chatId] = count;
    }
    notifyListeners();
  }

  /// Optimistically increment unread count for a chat (when new message arrives)
  void increment(String chatId) {
    // Don't increment if user is currently in this chat
    if (_currentlyOpenChatId == chatId) return;
    _counts[chatId] = (_counts[chatId] ?? 0) + 1;
    notifyListeners();
  }

  /// Optimistically decrement unread count for a chat (when messages marked as read)
  void decrement(String chatId, int count) {
    final current = _counts[chatId] ?? 0;
    final newCount = (current - count).clamp(0, current);
    if (newCount == 0) {
      _counts.remove(chatId);
      NotificationService().cancelChatNotifications(chatId);
    } else {
      _counts[chatId] = newCount;
    }
    notifyListeners();
  }

  /// Clear unread count for a chat (optimistically)
  void clear(String chatId) {
    _counts.remove(chatId);
    NotificationService().cancelChatNotifications(chatId);
    notifyListeners();
  }

  /// Handle WebSocket events
  void _handleWebSocketEvent(WebSocketEvent event) {
    // General handler — specific events are handled via subscribe()
  }

  /// Handle unread_count_updated from server — AUTHORITATIVE source
  void _onUnreadCountUpdated(WebSocketEvent event) {
    final chatId = event.data['chat_id']?.toString();
    final unreadCount = event.data['unread_count'] as int? ?? 0;

    if (chatId != null) {
      if (unreadCount == 0) {
        _counts.remove(chatId);
        NotificationService().cancelChatNotifications(chatId);
      } else {
        _counts[chatId] = unreadCount;
      }
      notifyListeners();
      // Persist to local storage
      _persistCounts();
    }
  }

  /// Handle new_message — optimistically increment unread for non-open chats
  void _onNewMessage(WebSocketEvent event) {
    final chatId = event.data['chat_id']?.toString();
    final messageData = event.data['message'] as Map<String, dynamic>?;
    final senderId = messageData?['sender_id']?.toString();

    if (chatId == null) return;

    // Don't increment for own messages
    if (senderId != null && senderId == _currentUserId) return;

    // Don't increment if user is currently in this chat
    if (_currentlyOpenChatId == chatId) return;

    // Optimistically increment — server will send unreadCountUpdated as confirmation
    _counts[chatId] = (_counts[chatId] ?? 0) + 1;
    notifyListeners();
  }

  /// Persist counts to local storage
  Future<void> _persistCounts() async {
    // Local storage saves full chat objects, so we don't need separate persistence
    // The main_screen will save chats with updated unread counts
  }

  /// Sync counts from server on reconnect (reload chats)
  Future<void> syncFromServer() async {
    try {
      final result = await ChatService.getChats();
      if (result['success'] == true) {
        final chats = result['chats'] as List<Chat>;
        loadFromChats(chats);
      }
    } catch (e) {
      debugPrint('UnreadCountProvider: Failed to sync from server: $e');
    }
  }

  @override
  void dispose() {
    _wsSubscription?.cancel();
    _wsService.unsubscribe(WebSocketEventType.unreadCountUpdated, _onUnreadCountUpdated);
    _wsService.unsubscribe(WebSocketEventType.newMessage, _onNewMessage);
    super.dispose();
  }
}
