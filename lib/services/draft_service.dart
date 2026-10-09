import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_draft.dart';
import 'chat_service.dart';
import 'websocket_service.dart';

/// DraftService manages unsent message drafts both locally (for instant UI & offline)
/// and synchronized with the server (for multi-device sync, like Telegram).
class DraftService {
  static final DraftService _instance = DraftService._internal();
  factory DraftService() => _instance;
  DraftService._internal() {
    _initWebSocketListener();
  }

  static const String _storageKey = 'chat_drafts_v1';
  final Map<String, ChatDraft> _drafts = {};
  final Map<String, Timer> _debounceTimers = {};
  StreamSubscription<WebSocketEvent>? _wsSubscription;
  bool _initialized = false;

  /// ValueNotifier exposing all current drafts for reactive UI updates (e.g. chat list badge)
  final ValueNotifier<Map<String, ChatDraft>> draftsNotifier =
      ValueNotifier<Map<String, ChatDraft>>({});

  /// Initialize and restore saved drafts from local storage
  Future<void> init() async {
    if (_initialized) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_storageKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        for (final entry in decoded.entries) {
          if (entry.value is Map<String, dynamic>) {
            _drafts[entry.key] =
                ChatDraft.fromJson(entry.value as Map<String, dynamic>);
          }
        }
        draftsNotifier.value = Map.unmodifiable(_drafts);
      }
    } catch (e) {
      debugPrint('DraftService: Error initializing from local storage: $e');
    } finally {
      _initialized = true;
    }
  }

  void _initWebSocketListener() {
    _wsSubscription = WebSocketService().eventStream.listen((event) {
      if (event.type == WebSocketEventType.draftUpdated) {
        _handleServerDraftUpdate(event);
      }
    });
  }

  void _handleServerDraftUpdate(WebSocketEvent event) {
    final chatId = event.data['chat_id']?.toString();
    if (chatId == null || chatId.isEmpty) return;

    final draftData = event.data['draft'];
    if (draftData is Map<String, dynamic>) {
      final remoteDraft = ChatDraft.fromJson(draftData);
      // Only replace if local is not being typed actively (no pending debounce)
      if (!_debounceTimers.containsKey(chatId)) {
        _drafts[chatId] = remoteDraft;
        draftsNotifier.value = Map.unmodifiable(_drafts);
        _persistLocally();
      }
    } else {
      // Draft was cleared remotely
      if (!_debounceTimers.containsKey(chatId)) {
        _drafts.remove(chatId);
        draftsNotifier.value = Map.unmodifiable(_drafts);
        _persistLocally();
      }
    }
  }

  /// Get active draft for a chat
  ChatDraft? getDraft(String chatId) {
    return _drafts[chatId];
  }

  /// Save draft locally immediately, and debounce sync to the server
  void saveDraft(
    String chatId, {
    required String text,
    String? replyToMessageId,
    String? quoteText,
    bool isQuote = false,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty && (replyToMessageId == null || replyToMessageId.isEmpty)) {
      deleteDraft(chatId);
      return;
    }

    final draft = ChatDraft(
      text: text,
      replyToMessageId: replyToMessageId,
      quoteText: quoteText,
      isQuote: isQuote,
      updatedAt: DateTime.now(),
    );

    // Instant local save
    _drafts[chatId] = draft;
    draftsNotifier.value = Map.unmodifiable(_drafts);
    _persistLocally();

    // Debounce server synchronization (600ms)
    _debounceTimers[chatId]?.cancel();
    _debounceTimers[chatId] = Timer(const Duration(milliseconds: 600), () {
      _debounceTimers.remove(chatId);
      _syncToServer(chatId, draft);
    });
  }

  /// Flushes any pending debounced draft to the server immediately (e.g. on screen exit)
  Future<void> flushDraft(String chatId) async {
    final timer = _debounceTimers.remove(chatId);
    if (timer != null) {
      timer.cancel();
      final draft = _drafts[chatId];
      if (draft != null) {
        await _syncToServer(chatId, draft);
      }
    }
  }

  /// Deletes draft locally and on server (e.g. on message send or clearing input)
  Future<void> deleteDraft(String chatId) async {
    _debounceTimers[chatId]?.cancel();
    _debounceTimers.remove(chatId);

    if (_drafts.containsKey(chatId)) {
      _drafts.remove(chatId);
      draftsNotifier.value = Map.unmodifiable(_drafts);
      _persistLocally();
    }

    // Call server to clear
    try {
      await ChatService.deleteDraft(chatId: chatId);
    } catch (e) {
      debugPrint('DraftService: Error deleting draft on server: $e');
    }
  }

  /// Populate drafts from server chat list response (if present and newer)
  void populateFromChats(List<Chat> chats) {
    bool changed = false;
    for (final chat in chats) {
      if (chat.draft != null && chat.draft!.isNotEmpty) {
        final existing = _drafts[chat.id];
        if (existing == null || chat.draft!.updatedAt.isAfter(existing.updatedAt)) {
          if (!_debounceTimers.containsKey(chat.id)) {
            _drafts[chat.id] = chat.draft!;
            changed = true;
          }
        }
      }
    }
    if (changed) {
      draftsNotifier.value = Map.unmodifiable(_drafts);
      _persistLocally();
    }
  }

  Future<void> _syncToServer(String chatId, ChatDraft draft) async {
    try {
      await ChatService.saveDraft(
        chatId: chatId,
        text: draft.text,
        replyToMessageId: draft.replyToMessageId,
        quoteText: draft.quoteText,
        isQuote: draft.isQuote,
      );
    } catch (e) {
      debugPrint('DraftService: Error syncing draft to server: $e');
    }
  }

  Future<void> _persistLocally() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final map = <String, dynamic>{};
      for (final entry in _drafts.entries) {
        map[entry.key] = entry.value.toJson();
      }
      await prefs.setString(_storageKey, jsonEncode(map));
    } catch (e) {
      debugPrint('DraftService: Error persisting to local storage: $e');
    }
  }

  @visibleForTesting
  void clearAllForTesting() {
    _debounceTimers.forEach((_, t) => t.cancel());
    _debounceTimers.clear();
    _drafts.clear();
    draftsNotifier.value = {};
    _initialized = false;
  }

  @visibleForTesting
  void handleDraftEvent(String chatId, dynamic draftData) {
    _handleServerDraftUpdate(WebSocketEvent(
      type: WebSocketEventType.draftUpdated,
      data: {'chat_id': chatId, 'draft': draftData},
      timestamp: DateTime.now().millisecondsSinceEpoch,
    ));
  }
}
