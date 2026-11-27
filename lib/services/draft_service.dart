import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/chat_draft.dart';
import 'account_manager.dart';
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

  static const String _legacyStorageKey = 'chat_drafts_v1';
  static const String _storageKeyPrefix = 'chat_drafts_v2_';
  static const Duration kPublishDebounceDuration = Duration(milliseconds: 1500);

  final Map<String, ChatDraft> _drafts = {};
  final Map<String, ChatDraft> _publishedDrafts = {};
  final Map<String, Timer> _debounceTimers = {};
  final Map<String, int> _opGenerations = {};
  StreamSubscription<WebSocketEvent>? _wsSubscription;
  final StreamController<({String chatId, ChatDraft? draft})>
      _remoteUpdatesController =
      StreamController<({String chatId, ChatDraft? draft})>.broadcast();

  bool _initialized = false;
  String? _activeUserId;
  Future<void>? _pendingPersist;

  /// ValueNotifier exposing published main-chat drafts for reactive UI updates (e.g. chat list badge).
  final ValueNotifier<Map<String, ChatDraft>> draftsNotifier =
      ValueNotifier<Map<String, ChatDraft>>({});

  /// Stream of remote `draft_updated` changes for open chat screens.
  Stream<({String chatId, ChatDraft? draft})> get remoteUpdatesStream =>
      _remoteUpdatesController.stream;

  /// Composite scope key helpers for forum topics and channel comment threads (stored locally only).
  static String topicKey(String chatId, int topicId) => '$chatId:topic:$topicId';
  static String commentsKey(String channelId, String postId) =>
      'comments:$channelId:$postId';
  static bool isLocalOnlyScopeKey(String scopeKey) =>
      scopeKey.contains(':topic:') || scopeKey.startsWith('comments:');

  String _storageKeyForUser(String? userId) {
    final clean = userId?.trim();
    if (clean != null && clean.isNotEmpty) {
      return '$_storageKeyPrefix$clean';
    }
    return _legacyStorageKey;
  }

  String? _resolveUserId(String? explicitUserId) {
    if (explicitUserId != null) {
      final t = explicitUserId.trim();
      return t.isNotEmpty ? t : null;
    }
    try {
      final uid = AccountManager().currentAccount?.userId.trim();
      if (uid != null && uid.isNotEmpty) return uid;
    } catch (_) {}
    return _activeUserId;
  }

  int _bumpGeneration(String key) {
    final next = (_opGenerations[key] ?? 0) + 1;
    _opGenerations[key] = next;
    return next;
  }

  /// Initialize and restore saved drafts from local storage for [userId].
  Future<void> init({String? userId}) async {
    final resolvedUserId = _resolveUserId(userId);
    if (_initialized && resolvedUserId == _activeUserId) return;
    _activeUserId = resolvedUserId;
    _drafts.clear();
    _publishedDrafts.clear();
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = _storageKeyForUser(_activeUserId);
      String? raw = prefs.getString(key);
      if ((raw == null || raw.isEmpty) &&
          key != _legacyStorageKey &&
          prefs.containsKey(_legacyStorageKey)) {
        raw = prefs.getString(_legacyStorageKey);
        if (raw != null && raw.isNotEmpty) {
          await prefs.setString(key, raw);
        }
        await prefs.remove(_legacyStorageKey);
      }

      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw) as Map<String, dynamic>;
        bool purgedEmpty = false;
        for (final entry in decoded.entries) {
          if (entry.value is Map) {
            final draft = ChatDraft.fromJson(
              Map<String, dynamic>.from(entry.value as Map),
            );
            if (draft.isEmpty) {
              purgedEmpty = true;
              continue;
            }
            _drafts[entry.key] = draft;
            if (!isLocalOnlyScopeKey(entry.key)) {
              _publishedDrafts[entry.key] = draft;
            }
          }
        }
        if (purgedEmpty) {
          await _persistLocally();
        }
      }
      draftsNotifier.value = Map.unmodifiable(_publishedDrafts);
    } catch (e) {
      debugPrint('DraftService: Error initializing from local storage: $e');
    } finally {
      _initialized = true;
    }
  }

  /// Switches active account draft storage, canceling any pending debounced syncs
  /// from the previous account and reloading the incoming account's drafts.
  Future<void> switchAccount(String? newUserId) async {
    if (_pendingPersist != null) await _pendingPersist;
    for (final key in _debounceTimers.keys.toList()) {
      _bumpGeneration(key);
      _debounceTimers[key]?.cancel();
    }
    _debounceTimers.clear();
    _drafts.clear();
    _publishedDrafts.clear();
    draftsNotifier.value = const {};
    _initialized = false;
    _activeUserId = null;
    await init(userId: newUserId);
  }

  /// Wipes all cached drafts for [userId] (or active user) from memory and SharedPreferences.
  Future<void> clearAllLocalDrafts({String? userId}) async {
    if (_pendingPersist != null) await _pendingPersist;
    final targetUser = userId?.trim();
    for (final key in _debounceTimers.keys.toList()) {
      _bumpGeneration(key);
      _debounceTimers[key]?.cancel();
    }
    _debounceTimers.clear();
    if (targetUser == null ||
        targetUser.isEmpty ||
        targetUser == _activeUserId) {
      _drafts.clear();
      _publishedDrafts.clear();
      draftsNotifier.value = const {};
      _initialized = false;
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_storageKeyForUser(targetUser ?? _activeUserId));
      await prefs.remove(_legacyStorageKey);
    } catch (e) {
      debugPrint('DraftService: Error clearing local drafts: $e');
    }
  }

  void _initWebSocketListener() {
    _wsSubscription = WebSocketService().eventStream.listen((event) {
      if (event.type == WebSocketEventType.draftUpdated) {
        _handleServerDraftUpdate(event);
      }
    });
  }

  /// Applies a server `draft_updated` payload from WebSocket or delta sync.
  void applyServerDraftSyncEvent(String chatId, dynamic draftData) {
    if (chatId.isEmpty) return;
    if (_debounceTimers.containsKey(chatId)) {
      // Active local typing takes precedence over stale server echo.
      return;
    }
    if (draftData is Map) {
      final parsed = ChatDraft.fromJson(Map<String, dynamic>.from(draftData));
      if (parsed.isEmpty) {
        _clearRemoteState(chatId);
        return;
      }
      final existing = _drafts[chatId];
      final effectiveDraft = (existing != null &&
              existing.text == parsed.text &&
              existing.replyToMessageId == parsed.replyToMessageId &&
              !parsed.isQuote &&
              existing.isQuote &&
              existing.quoteText != null &&
              existing.quoteText!.isNotEmpty)
          ? parsed.copyWith(
              isQuote: true,
              quoteText: existing.quoteText,
              quoteOffset: existing.quoteOffset,
              quoteLength: existing.quoteLength,
            )
          : parsed;
      _drafts[chatId] = effectiveDraft;
      if (!isLocalOnlyScopeKey(chatId)) {
        _publishedDrafts[chatId] = effectiveDraft;
        draftsNotifier.value = Map.unmodifiable(_publishedDrafts);
      }
      _persistLocally();
      _remoteUpdatesController.add((chatId: chatId, draft: effectiveDraft));
    } else {
      _clearRemoteState(chatId);
    }
  }

  void _clearRemoteState(String chatId) {
    final hadAny = _drafts.remove(chatId) != null;
    final hadPublished = _publishedDrafts.remove(chatId) != null;
    if (hadPublished) {
      draftsNotifier.value = Map.unmodifiable(_publishedDrafts);
    }
    if (hadAny) {
      _persistLocally();
    }
    _remoteUpdatesController.add((chatId: chatId, draft: null));
  }

  void _handleServerDraftUpdate(WebSocketEvent event) {
    final chatId = event.data['chat_id']?.toString();
    if (chatId == null || chatId.isEmpty) return;
    applyServerDraftSyncEvent(chatId, event.data['draft']);
  }

  /// Get active in-memory draft for a chat or scoped key (used when opening/restoring chat input).
  ChatDraft? getDraft(String chatId) {
    final draft = _drafts[chatId];
    return (draft != null && draft.isNotEmpty) ? draft : null;
  }

  /// Get published draft for the main screen chat list preview.
  ChatDraft? getPublishedDraft(String chatId) {
    if (isLocalOnlyScopeKey(chatId)) return null;
    final draft = _publishedDrafts[chatId];
    return (draft != null && draft.isNotEmpty) ? draft : null;
  }

  static bool _sameEntities(List<MessageEntity> a, List<MessageEntity> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final ea = a[i];
      final eb = b[i];
      if (ea.type != eb.type ||
          ea.offset != eb.offset ||
          ea.length != eb.length ||
          ea.url != eb.url ||
          ea.customEmojiId != eb.customEmojiId ||
          ea.collapsed != eb.collapsed) {
        return false;
      }
    }
    return true;
  }

  /// Save draft locally immediately, and debounce publication to chat list & server sync.
  /// When [text] is blank/whitespace, clears any existing draft rather than storing a reply-only stub.
  void saveDraft(
    String chatId, {
    required String text,
    List<MessageEntity> entities = const [],
    String? replyToMessageId,
    String? quoteText,
    bool isQuote = false,
    int quoteOffset = 0,
    int quoteLength = 0,
    bool immediate = false,
  }) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) {
      if (_drafts.containsKey(chatId) ||
          _publishedDrafts.containsKey(chatId) ||
          _debounceTimers.containsKey(chatId)) {
        deleteDraft(chatId);
      }
      return;
    }

    final existing = _drafts[chatId];
    if (!immediate &&
        existing != null &&
        existing.text == text &&
        existing.replyToMessageId == replyToMessageId &&
        existing.quoteText == quoteText &&
        existing.isQuote == isQuote &&
        existing.quoteOffset == quoteOffset &&
        existing.quoteLength == quoteLength &&
        _sameEntities(existing.entities, entities)) {
      return;
    }

    final draft = ChatDraft(
      text: text,
      entities: entities,
      replyToMessageId: replyToMessageId,
      quoteText: quoteText,
      isQuote: isQuote,
      quoteOffset: quoteOffset,
      quoteLength: quoteLength,
      updatedAt: DateTime.now(),
    );

    final bool localOnly = isLocalOnlyScopeKey(chatId);
    final int gen = _bumpGeneration(chatId);

    // Instant local save for input restoration
    _drafts[chatId] = draft;
    _persistLocally();

    _debounceTimers[chatId]?.cancel();
    if (localOnly) {
      _debounceTimers.remove(chatId);
      return;
    }

    if (immediate) {
      _debounceTimers.remove(chatId);
      _publishedDrafts[chatId] = draft;
      draftsNotifier.value = Map.unmodifiable(_publishedDrafts);
      _syncToServer(chatId, draft, gen);
      return;
    }

    // Debounce chat list publication and server synchronization while actively typing
    _debounceTimers[chatId] = Timer(kPublishDebounceDuration, () {
      _debounceTimers.remove(chatId);
      if ((_opGenerations[chatId] ?? 0) != gen) return;
      _publishedDrafts[chatId] = draft;
      draftsNotifier.value = Map.unmodifiable(_publishedDrafts);
      _syncToServer(chatId, draft, gen);
    });
  }

  /// Cancels any pending debounced publish for [scopeKey] and removes local state
  /// without firing an extra `PUT /draft` call (used when the message send itself clears the server draft).
  void clearLocalDraftOnSend(String scopeKey) {
    _bumpGeneration(scopeKey);
    _debounceTimers.remove(scopeKey)?.cancel();
    final hadDraft = _drafts.remove(scopeKey) != null;
    final hadPublished = _publishedDrafts.remove(scopeKey) != null;
    if (hadPublished) {
      draftsNotifier.value = Map.unmodifiable(_publishedDrafts);
    }
    if (hadDraft) {
      _persistLocally();
    }
  }

  /// Alias to cancel any pending publish and clear local state without a server HTTP round-trip.
  void cancelPendingPublish(String scopeKey) => clearLocalDraftOnSend(scopeKey);

  /// Flushes any pending debounced draft to the chat list and server immediately
  /// (e.g. on screen exit, tile switch, or input blur).
  Future<void> flushDraft(String chatId) async {
    final timer = _debounceTimers.remove(chatId);
    final draft = _drafts[chatId];
    if (draft != null && draft.isNotEmpty) {
      if (!isLocalOnlyScopeKey(chatId)) {
        if (_publishedDrafts[chatId] != draft) {
          _publishedDrafts[chatId] = draft;
          draftsNotifier.value = Map.unmodifiable(_publishedDrafts);
        }
        if (timer != null) {
          timer.cancel();
          final gen = _opGenerations[chatId] ?? 0;
          await _syncToServer(chatId, draft, gen);
        }
      } else {
        timer?.cancel();
      }
    } else if (timer != null) {
      timer.cancel();
    }
  }

  /// Deletes draft locally and (for main chat keys) on server.
  Future<void> deleteDraft(String chatId) async {
    _bumpGeneration(chatId);
    _debounceTimers.remove(chatId)?.cancel();

    final hadDraft = _drafts.remove(chatId) != null;
    final hadPublished = _publishedDrafts.remove(chatId) != null;
    if (hadPublished) {
      draftsNotifier.value = Map.unmodifiable(_publishedDrafts);
    }
    if (hadDraft) {
      _persistLocally();
    }

    if (isLocalOnlyScopeKey(chatId)) return;

    try {
      await ChatService.deleteDraft(chatId: chatId);
    } catch (e) {
      debugPrint('DraftService: Error deleting draft on server: $e');
    }
  }

  /// Populate drafts from server chat list response.
  /// When [authoritative] is true, removes cached main-chat drafts for chats whose server `draft` is null.
  void populateFromChats(List<Chat> chats, {bool authoritative = false}) {
    bool changed = false;
    bool persisted = false;
    for (final chat in chats) {
      if (_debounceTimers.containsKey(chat.id)) continue;
      final serverDraft = chat.draft;
      if (serverDraft != null && serverDraft.isNotEmpty) {
        final existing = _drafts[chat.id];
        if (existing == null ||
            serverDraft.updatedAt.isAfter(existing.updatedAt)) {
          _drafts[chat.id] = serverDraft;
          _publishedDrafts[chat.id] = serverDraft;
          changed = true;
          persisted = true;
        }
      } else if (authoritative) {
        final removedLocal = _drafts.remove(chat.id) != null;
        final removedPub = _publishedDrafts.remove(chat.id) != null;
        if (removedPub) changed = true;
        if (removedLocal) persisted = true;
      }
    }
    if (changed) {
      draftsNotifier.value = Map.unmodifiable(_publishedDrafts);
    }
    if (persisted) {
      _persistLocally();
    }
  }

  Future<void> _syncToServer(
    String chatId,
    ChatDraft draft,
    int expectedGeneration,
  ) async {
    if (isLocalOnlyScopeKey(chatId)) return;
    if ((_opGenerations[chatId] ?? 0) != expectedGeneration) return;
    try {
      await ChatService.saveDraft(
        chatId: chatId,
        text: draft.text,
        entities: draft.entities,
        replyToMessageId: draft.replyToMessageId,
        quoteText: draft.quoteText,
        isQuote: draft.isQuote,
        quoteOffset: draft.quoteOffset,
        quoteLength: draft.quoteLength,
      );
    } catch (e) {
      debugPrint('DraftService: Error syncing draft to server: $e');
    }
  }

  Future<void> _persistLocally() {
    final String storageKey = _storageKeyForUser(_activeUserId);
    final map = <String, dynamic>{};
    for (final entry in _drafts.entries) {
      if (entry.value.isEmpty) continue;
      map[entry.key] = entry.value.toJson();
    }
    final String encoded = jsonEncode(map);
    final prev = _pendingPersist;
    late final Future<void> next;
    next = (prev != null ? prev.catchError((_) {}) : Future<void>.value())
        .then((_) async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString(storageKey, encoded);
      } catch (e) {
        debugPrint('DraftService: Error persisting to local storage: $e');
      }
    }).whenComplete(() {
      if (identical(_pendingPersist, next)) {
        _pendingPersist = null;
      }
    });
    _pendingPersist = next;
    return next;
  }

  void dispose() {
    _wsSubscription?.cancel();
    _wsSubscription = null;
    for (final timer in _debounceTimers.values) {
      timer.cancel();
    }
    _debounceTimers.clear();
  }

  @visibleForTesting
  void clearAllForTesting() {
    _debounceTimers.forEach((_, t) => t.cancel());
    _debounceTimers.clear();
    _opGenerations.clear();
    _drafts.clear();
    _publishedDrafts.clear();
    draftsNotifier.value = {};
    _initialized = false;
    _activeUserId = null;
    _pendingPersist = null;
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
