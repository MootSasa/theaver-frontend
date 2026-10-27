import 'dart:async';
import 'package:flutter/foundation.dart';
import 'database/app_database.dart';
import 'websocket_service.dart';
import 'chat_service.dart';
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

  /// Set of chatIds that have received an explicit count update before full initial load
  final Set<String> _knownChatIds = {};

  /// Whether loadFromChats has been called at least once for the active session
  bool _hasLoadedInitialChats = false;

  /// Map of chatId -> reference count of mounted chat tiles showing this chat.
  /// Messages in any open chat should NOT increment unread badges.
  final Map<String, int> _openChatCounts = {};

  /// Legacy single-chat tracker fallback when setOpenChat(null) is called without chatId
  String? _lastSetOpenChatId;

  /// Stream subscription for WebSocket events
  StreamSubscription<WebSocketEvent>? _wsSubscription;

  /// Whether the provider has authoritative count data for [chatId]
  bool hasAuthoritativeCount(String chatId) =>
      _hasLoadedInitialChats || _knownChatIds.contains(chatId);

  /// Get unread count for a specific chat
  int getCount(String chatId) => _counts[chatId] ?? 0;

  /// Check whether a chat is currently open in any tile
  bool isChatOpen(String chatId) => (_openChatCounts[chatId] ?? 0) > 0;

  /// Check whether a chat is manually marked as unread
  bool isMarkedUnread(String chatId) => _counts[chatId] == -1;

  /// Check whether a chat has unread messages or is marked as unread
  bool hasUnread(String chatId) => (_counts[chatId] ?? 0) > 0 || _counts[chatId] == -1;

  /// Get total unread count across all chats (marked unread chats count as +1)
  int get totalUnread => _counts.values.fold(
        0,
        (sum, count) => sum + (count == -1 ? 1 : (count > 0 ? count : 0)),
      );

  /// Get number of chats with unread messages for a specific filter
  int getUnreadChatCountForFilter(bool Function(String chatId, String chatType) matchesFilter) {
    int count = 0;
    _counts.forEach((chatId, unreadCount) {
      // We need chat type info here — the caller should pass it
      if (unreadCount > 0 || unreadCount == -1) count++;
    });
    return count;
  }

  /// Register a chat as open in a tile/screen
  void openChat(String chatId) {
    if (chatId.isEmpty) return;
    _openChatCounts[chatId] = (_openChatCounts[chatId] ?? 0) + 1;
    _lastSetOpenChatId = chatId;
    NotificationService().addActiveChat(chatId);
  }

  /// Unregister a chat when its tile/screen is closed or disposed
  void closeChat(String chatId) {
    if (chatId.isEmpty) return;
    final current = _openChatCounts[chatId] ?? 0;
    if (current <= 1) {
      _openChatCounts.remove(chatId);
      NotificationService().removeActiveChat(chatId);
    } else {
      _openChatCounts[chatId] = current - 1;
    }
    if (_lastSetOpenChatId == chatId && !_openChatCounts.containsKey(chatId)) {
      _lastSetOpenChatId = _openChatCounts.keys.lastOrNull;
    }
  }

  /// Set currently open chat (compatible with both single-screen and multi-tile callers)
  void setOpenChat(String? chatId, {String? previousChatId}) {
    if (chatId != null && chatId.isNotEmpty) {
      openChat(chatId);
    } else {
      final toClose = previousChatId ?? _lastSetOpenChatId;
      if (toClose != null) {
        closeChat(toClose);
      }
    }
  }

  /// Initialize: load counts from server and subscribe to WebSocket
  Future<void> initialize() async {
    // Subscribe to WebSocket events
    _wsSubscription = _wsService.eventStream.listen(_handleWebSocketEvent);
    _wsService.subscribe(WebSocketEventType.unreadCountUpdated, _onUnreadCountUpdated);
    _wsService.subscribe(WebSocketEventType.newMessage, _onNewMessage);
  }

  /// Load counts from the server (getChats API returns unread_count per chat)
  void loadFromChats(List<Chat> chats) {
    _counts.clear();
    _knownChatIds.clear();
    _hasLoadedInitialChats = true;
    for (final chat in chats) {
      _knownChatIds.add(chat.id);
      if (chat.unreadCount > 0 || chat.unreadCount == -1) {
        _counts[chat.id] = chat.unreadCount;
      }
    }
    notifyListeners();
  }

  /// Set count for a specific chat (from server response)
  void setCount(String chatId, int count) {
    _knownChatIds.add(chatId);
    if (count == 0) {
      _counts.remove(chatId);
    } else {
      _counts[chatId] = count;
    }
    _persistCountToDb(chatId, count);
    notifyListeners();
  }

  /// Optimistically increment unread count for a chat (when new message arrives)
  void increment(String chatId) {
    // Don't increment if user has this chat open in any tile
    if (isChatOpen(chatId)) return;
    _knownChatIds.add(chatId);
    final current = _counts[chatId] ?? 0;
    final nextCount = current == -1 ? 1 : current + 1;
    _counts[chatId] = nextCount;
    _persistCountToDb(chatId, nextCount);
    notifyListeners();
  }

  /// Optimistically decrement unread count for a chat (when messages marked as read)
  void decrement(String chatId, int count) {
    _knownChatIds.add(chatId);
    final current = _counts[chatId] ?? 0;
    if (current == -1) {
      _counts.remove(chatId);
      _persistCountToDb(chatId, 0);
      NotificationService().cancelChatNotifications(chatId);
      notifyListeners();
      return;
    }
    final newCount = (current - count).clamp(0, current);
    if (newCount == 0) {
      _counts.remove(chatId);
      NotificationService().cancelChatNotifications(chatId);
    } else {
      _counts[chatId] = newCount;
    }
    _persistCountToDb(chatId, newCount);
    notifyListeners();
  }

  /// Clear unread count for a chat (optimistically)
  void clear(String chatId) {
    _knownChatIds.add(chatId);
    _counts.remove(chatId);
    _persistCountToDb(chatId, 0);
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
      _knownChatIds.add(chatId);
      if (unreadCount == 0) {
        _counts.remove(chatId);
        NotificationService().cancelChatNotifications(chatId);
      } else {
        _counts[chatId] = unreadCount;
      }
      _persistCountToDb(chatId, unreadCount);
      notifyListeners();
    }
  }

  /// Handle new_message — authoritative count is managed by unread_count_updated event
  void _onNewMessage(WebSocketEvent event) {
    final chatId = event.data['chat_id']?.toString();
    if (chatId == null) return;

    // If payload contains authoritative unread_count, apply it.
    // Do NOT blindly increment here, as the server broadcasts unread_count_updated
    // with the exact count from PostgreSQL on every new message.
    if (event.data.containsKey('unread_count') && event.data['unread_count'] is int) {
      final unreadCount = event.data['unread_count'] as int;
      _knownChatIds.add(chatId);
      if (unreadCount == 0) {
        _counts.remove(chatId);
      } else {
        _counts[chatId] = unreadCount;
      }
      _persistCountToDb(chatId, unreadCount);
      notifyListeners();
    }
  }

  void _persistCountToDb(String chatId, int count) {
    try {
      AppDatabase().updateUnreadCount(chatId, count);
    } catch (_) {}
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
