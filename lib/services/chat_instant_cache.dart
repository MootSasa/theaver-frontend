import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'bot_service.dart';
import 'chat_service.dart';
import 'database/app_database.dart';
import 'dm_parity_service.dart';

/// Instant synchronous snapshot for zero-jank Frame-0 rendering when opening a chat.
class ChatInstantSnapshot {
  final String chatId;
  final Chat? chat;
  final List<Message>? messages;
  final ChatDetails? chatDetails;
  final List<Message>? pinnedMessages;
  final ChatAppearanceConfig? appearance;
  final double? keyboardHeight;
  final double? inputHeight;

  // Lightweight persistent chrome metadata (restored from SharedPreferences on cold boot)
  final bool? isBot;
  final bool? isVerified;
  final String? username;
  final String? bio;
  final String? myRole;
  final bool? isMember;
  final int? memberCount;
  final int? subscriberCount;
  final LinkedChatSummary? linkedChat;
  final int? pinnedMessagesCount;
  final int? messageAutoDeleteTime;
  final bool? hasProtectedContent;

  const ChatInstantSnapshot({
    required this.chatId,
    this.chat,
    this.messages,
    this.chatDetails,
    this.pinnedMessages,
    this.appearance,
    this.keyboardHeight,
    this.inputHeight,
    this.isBot,
    this.isVerified,
    this.username,
    this.bio,
    this.myRole,
    this.isMember,
    this.memberCount,
    this.subscriberCount,
    this.linkedChat,
    this.pinnedMessagesCount,
    this.messageAutoDeleteTime,
    this.hasProtectedContent,
  });

  bool get hasMessages => messages != null && messages!.isNotEmpty;

  Message? get effectivePinnedMessage {
    if (chatDetails?.pinnedMessage != null) return chatDetails!.pinnedMessage;
    if (pinnedMessages != null && pinnedMessages!.isNotEmpty) {
      return pinnedMessages!.first;
    }
    return chat?.pinnedMessage;
  }

  List<int> get effectivePinnedIds {
    if (chatDetails != null && chatDetails!.pinnedMessageIds.isNotEmpty) {
      return chatDetails!.pinnedMessageIds;
    }
    if (chat != null && chat!.pinnedMessageIds.isNotEmpty) {
      return chat!.pinnedMessageIds;
    }
    final single = chatDetails?.pinnedMessageId ?? chat?.pinnedMessageId;
    if (single != null && single > 0) return <int>[single];
    return const <int>[];
  }

  int get effectivePinnedCount {
    if (pinnedMessages != null && pinnedMessages!.isNotEmpty) {
      return pinnedMessages!.length;
    }
    if (pinnedMessagesCount != null && pinnedMessagesCount! > 0) {
      return pinnedMessagesCount!;
    }
    final ids = effectivePinnedIds;
    if (ids.isNotEmpty) return ids.length;
    return effectivePinnedMessage != null ? 1 : 0;
  }

  ChatInstantSnapshot copyWith({
    Chat? chat,
    List<Message>? messages,
    ChatDetails? chatDetails,
    List<Message>? pinnedMessages,
    ChatAppearanceConfig? appearance,
    double? keyboardHeight,
    double? inputHeight,
    bool? isBot,
    bool? isVerified,
    String? username,
    String? bio,
    String? myRole,
    bool? isMember,
    int? memberCount,
    int? subscriberCount,
    LinkedChatSummary? linkedChat,
    int? pinnedMessagesCount,
    int? messageAutoDeleteTime,
    bool? hasProtectedContent,
  }) {
    return ChatInstantSnapshot(
      chatId: chatId,
      chat: chat ?? this.chat,
      messages: messages ?? this.messages,
      chatDetails: chatDetails ?? this.chatDetails,
      pinnedMessages: pinnedMessages ?? this.pinnedMessages,
      appearance: appearance ?? this.appearance,
      keyboardHeight: keyboardHeight ?? this.keyboardHeight,
      inputHeight: inputHeight ?? this.inputHeight,
      isBot: isBot ?? this.isBot,
      isVerified: isVerified ?? this.isVerified,
      username: username ?? this.username,
      bio: bio ?? this.bio,
      myRole: myRole ?? this.myRole,
      isMember: isMember ?? this.isMember,
      memberCount: memberCount ?? this.memberCount,
      subscriberCount: subscriberCount ?? this.subscriberCount,
      linkedChat: linkedChat ?? this.linkedChat,
      pinnedMessagesCount: pinnedMessagesCount ?? this.pinnedMessagesCount,
      messageAutoDeleteTime:
          messageAutoDeleteTime ?? this.messageAutoDeleteTime,
      hasProtectedContent: hasProtectedContent ?? this.hasProtectedContent,
    );
  }
}

/// Process-wide synchronous RAM cache backed by Drift & SharedPreferences.
///
/// Populated during `main()` startup and as chats/messages flow through
/// [MainScreen], WebSocket events, and chat screens, allowing `initState()` in
/// [PrivateChatScreen], [GroupChatScreen], and [ChannelScreen] to render the
/// exact final Frame-0 structure without loading spinners or post-open shifts.
class ChatInstantCache {
  ChatInstantCache._();
  static final ChatInstantCache instance = ChatInstantCache._();

  static const String _metaPrefix = 'instant_chat_meta_v1_';
  static const String _appearancePrefix = 'instant_chat_appearance_v1_';
  static const String _inputHeightPrefix = 'instant_chat_input_h_v1_';
  static const int _maxCachedMessagesPerChat = 50;

  /// Shallow structural comparison of two ordered message lists to avoid
  /// redundant `setState` rebuilds after Frame-0 cache hydration.
  static bool messagesEqual(List<Message> a, List<Message> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      final ma = a[i];
      final mb = b[i];
      if (ma.id != mb.id ||
          ma.localId != mb.localId ||
          ma.content != mb.content ||
          ma.isEdited != mb.isEdited ||
          ma.sendStatus != mb.sendStatus ||
          ma.isRead != mb.isRead ||
          ma.isListened != mb.isListened ||
          ma.reactions.length != mb.reactions.length ||
          ma.myReactions.length != mb.myReactions.length ||
          ma.commentsCount != mb.commentsCount ||
          ma.viewsCount != mb.viewsCount) {
        return false;
      }
    }
    return true;
  }

  final Map<String, ChatInstantSnapshot> _snapshots = {};
  double _globalKeyboardHeight = 280.0;
  bool _initialized = false;

  double get globalKeyboardHeight => _globalKeyboardHeight;

  /// Loads persisted lightweight chrome metadata, appearance configs, keyboard
  /// height, and cached [BotInfo] into RAM at startup.
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final kbdHeight = prefs.getDouble('keyboard_height') ??
          prefs.getDouble('cached_keyboard_height');
      if (kbdHeight != null && kbdHeight > 150 && kbdHeight < 600) {
        _globalKeyboardHeight = kbdHeight;
      }

      for (final key in prefs.getKeys()) {
        if (key.startsWith(_metaPrefix)) {
          final chatId = key.substring(_metaPrefix.length);
          final raw = prefs.getString(key);
          if (chatId.isEmpty || raw == null || raw.isEmpty) continue;
          final restored = _decodeMetaSnapshot(chatId, raw);
          if (restored != null) {
            _snapshots[chatId] = restored;
          }
        } else if (key.startsWith(_appearancePrefix)) {
          final chatId = key.substring(_appearancePrefix.length);
          final raw = prefs.getString(key);
          if (chatId.isEmpty || raw == null || raw.isEmpty) continue;
          final cfg = ChatAppearanceConfig.tryParseJsonString(raw);
          if (cfg != null) {
            final cur =
                _snapshots[chatId] ?? ChatInstantSnapshot(chatId: chatId);
            _snapshots[chatId] = cur.copyWith(appearance: cfg);
          }
        } else if (key.startsWith(_inputHeightPrefix)) {
          final chatId = key.substring(_inputHeightPrefix.length);
          final h = prefs.getDouble(key);
          if (chatId.isNotEmpty && h != null && h > 24 && h < 320) {
            final cur =
                _snapshots[chatId] ?? ChatInstantSnapshot(chatId: chatId);
            _snapshots[chatId] = cur.copyWith(inputHeight: h);
          }
        } else if (key.startsWith(BotService.persistedPrefix)) {
          final raw = prefs.getString(key);
          if (raw == null || raw.isEmpty) continue;
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map) {
              final suffix = key.substring(BotService.persistedPrefix.length);
              final sepIdx = suffix.indexOf('_');
              final fallbackId =
                  sepIdx > 0 ? suffix.substring(0, sepIdx) : suffix;
              final ctxChatId =
                  sepIdx > 0 ? suffix.substring(sepIdx + 1) : null;
              final info = BotInfo.fromJson(
                Map<String, dynamic>.from(decoded),
                fallbackUserId: fallbackId,
              );
              BotService.seedBotInfoCache(info, chatId: ctxChatId);
            }
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('ChatInstantCache.init error: $e');
    }
  }

  /// Synchronous lookup guaranteed safe to call inside `State.initState()`.
  ChatInstantSnapshot? getSync(String chatId) {
    if (chatId.isEmpty) return null;
    final snap = _snapshots[chatId];
    if (snap == null) return null;
    if (snap.keyboardHeight == null) {
      return snap.copyWith(keyboardHeight: _globalKeyboardHeight);
    }
    return snap;
  }

  /// Prewarms RAM snapshots from Drift DB for top active chats.
  Future<void> prewarmFromDatabase(
    String? userId, {
    Iterable<String>? chatIds,
    int maxChats = 20,
  }) async {
    try {
      final db = AppDatabase(userId);
      await db.ensureInitialized();
      List<String> targetIds;
      if (chatIds != null) {
        targetIds = chatIds.where((id) => id.isNotEmpty).take(maxChats).toList();
      } else {
        final dbChats = await db.getChats();
        putChatSummaries(
          dbChats.map((c) => Chat.fromDbChat(c)).toList(),
        );
        targetIds = dbChats.take(maxChats).map((c) => c.chatId).toList();
      }

      for (final id in targetIds) {
        final existing = _snapshots[id];
        if (existing != null && existing.hasMessages) continue;
        final dbMsgs = await db.getMessages(id, limit: 35);
        if (dbMsgs.isNotEmpty) {
          final parsed = dbMsgs.map((m) => Message.fromDbMessage(m)).toList();
          putMessages(id, parsed);
        }
      }
    } catch (e) {
      debugPrint('ChatInstantCache.prewarmFromDatabase error: $e');
    }
  }

  void putChatSummaries(List<Chat> chats) {
    for (final chat in chats) {
      if (chat.id.isEmpty) continue;
      final cur = _snapshots[chat.id] ?? ChatInstantSnapshot(chatId: chat.id);
      ChatAppearanceConfig? parsedAppearance = cur.appearance;
      if (parsedAppearance == null && chat.appearance != null) {
        parsedAppearance = ChatAppearanceConfig.fromJson(chat.appearance!);
      }
      _snapshots[chat.id] = cur.copyWith(
        chat: chat,
        appearance: parsedAppearance,
        isBot: chat.isBot ? true : cur.isBot,
        isVerified: chat.isVerified ? true : cur.isVerified,
        username: (chat.username != null && chat.username!.isNotEmpty)
            ? chat.username
            : cur.username,
        myRole: (chat.myRole != null && chat.myRole!.isNotEmpty)
            ? chat.myRole
            : cur.myRole,
        isMember: chat.isMember,
        messageAutoDeleteTime: chat.messageAutoDeleteTime > 0
            ? chat.messageAutoDeleteTime
            : cur.messageAutoDeleteTime,
        hasProtectedContent: chat.hasProtectedContent || (cur.hasProtectedContent ?? false),
      );
    }
  }

  void putChatDetails(ChatDetails details) {
    if (details.id.isEmpty) return;
    final cur =
        _snapshots[details.id] ?? ChatInstantSnapshot(chatId: details.id);
    final parsedAppearance = details.appearance != null
        ? ChatAppearanceConfig.fromJson(details.appearance!)
        : cur.appearance;
    final pinnedList = cur.pinnedMessages ??
        (details.pinnedMessage != null ? [details.pinnedMessage!] : null);
    final pinnedCount = details.pinnedMessageIds.isNotEmpty
        ? details.pinnedMessageIds.length
        : (details.pinnedMessage != null ? 1 : 0);

    final updated = cur.copyWith(
      chatDetails: details,
      pinnedMessages: pinnedList,
      pinnedMessagesCount: pinnedCount,
      appearance: parsedAppearance,
      isVerified: details.isVerified,
      username: details.username ?? cur.username,
      bio: details.description ?? cur.bio,
      myRole: details.myRole ?? cur.myRole,
      isMember: details.isMember,
      memberCount: details.memberCount,
      subscriberCount: details.subscriberCount,
      linkedChat: details.linkedChat ?? cur.linkedChat,
      messageAutoDeleteTime: details.messageAutoDeleteTime,
      hasProtectedContent: details.hasProtectedContent,
    );
    _snapshots[details.id] = updated;
    _persistMetaSnapshot(updated);
    if (parsedAppearance != null) {
      _persistAppearance(details.id, parsedAppearance);
    }
  }

  void putPrivatePeerMeta(
    String chatId, {
    bool? isBot,
    bool? isVerified,
    String? username,
    String? bio,
  }) {
    if (chatId.isEmpty) return;
    final cur = _snapshots[chatId] ?? ChatInstantSnapshot(chatId: chatId);
    final updated = cur.copyWith(
      isBot: isBot ?? cur.isBot,
      isVerified: isVerified ?? cur.isVerified,
      username: username ?? cur.username,
      bio: bio ?? cur.bio,
    );
    _snapshots[chatId] = updated;
    _persistMetaSnapshot(updated);
  }

  void putMessages(String chatId, List<Message> messages) {
    if (chatId.isEmpty) return;
    final capped = messages.length > _maxCachedMessagesPerChat
        ? messages.sublist(0, _maxCachedMessagesPerChat)
        : List<Message>.from(messages);
    final cur = _snapshots[chatId] ?? ChatInstantSnapshot(chatId: chatId);
    _snapshots[chatId] = cur.copyWith(messages: capped);
  }

  void upsertMessage(String chatId, Message message) {
    if (chatId.isEmpty) return;
    final cur = _snapshots[chatId] ?? ChatInstantSnapshot(chatId: chatId);
    final list = List<Message>.from(cur.messages ?? const []);
    final idx = list.indexWhere(
      (m) =>
          m.id == message.id ||
          (message.localId != null &&
              message.localId!.isNotEmpty &&
              m.localId == message.localId),
    );
    if (idx >= 0) {
      list[idx] = message;
    } else {
      list.insert(0, message);
      if (list.length > _maxCachedMessagesPerChat) {
        list.removeRange(_maxCachedMessagesPerChat, list.length);
      }
    }
    _snapshots[chatId] = cur.copyWith(messages: list);
  }

  void removeMessages(String chatId, Iterable<String> messageIds) {
    if (chatId.isEmpty) return;
    final cur = _snapshots[chatId];
    if (cur?.messages == null) return;
    final idSet = messageIds.toSet();
    final filtered = cur!.messages!
        .where((m) => !idSet.contains(m.id) && !idSet.contains(m.localId))
        .toList();
    _snapshots[chatId] = cur.copyWith(messages: filtered);
  }

  void putPinnedMessages(String chatId, List<Message> pinned) {
    if (chatId.isEmpty) return;
    final cur = _snapshots[chatId] ?? ChatInstantSnapshot(chatId: chatId);
    final updated = cur.copyWith(
      pinnedMessages: List<Message>.from(pinned),
      pinnedMessagesCount: pinned.length,
    );
    _snapshots[chatId] = updated;
    _persistMetaSnapshot(updated);
  }

  void putAppearance(String chatId, ChatAppearanceConfig? config) {
    if (chatId.isEmpty || config == null) return;
    final cur = _snapshots[chatId] ?? ChatInstantSnapshot(chatId: chatId);
    _snapshots[chatId] = cur.copyWith(appearance: config);
    _persistAppearance(chatId, config);
  }

  void setKeyboardHeight(double height, {String? chatId}) {
    if (height <= 150 || height >= 600) return;
    _globalKeyboardHeight = height;
    if (chatId != null && chatId.isNotEmpty) {
      final cur = _snapshots[chatId] ?? ChatInstantSnapshot(chatId: chatId);
      _snapshots[chatId] = cur.copyWith(keyboardHeight: height);
    }
  }

  void setInputHeight(String chatId, double height) {
    if (chatId.isEmpty || height <= 24 || height >= 320) return;
    final cur = _snapshots[chatId] ?? ChatInstantSnapshot(chatId: chatId);
    if (cur.inputHeight != null && (cur.inputHeight! - height).abs() < 0.5) {
      return;
    }
    _snapshots[chatId] = cur.copyWith(inputHeight: height);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setDouble('$_inputHeightPrefix$chatId', height))
        .catchError((_) => false);
  }

  /// Propagates a contact name/avatar override for [userId] into cached [Chat]
  /// summaries, [ChatDetails.participants], and cached [Message] entries
  /// (`senderId == userId && senderChatId == null`).
  void applyUserContactOverride(
    String userId, {
    String? effectiveName,
    String? effectiveAvatarUrl,
    bool updateAvatar = true,
  }) {
    final uid = userId.trim();
    if (uid.isEmpty || uid == '0') return;

    final trimmedName = effectiveName?.trim() ?? '';
    final hasName = trimmedName.isNotEmpty;
    final trimmedAvatar = effectiveAvatarUrl?.trim() ?? '';
    if (!hasName && !updateAvatar) return;

    Message? updateMessage(Message m) {
      bool changed = false;
      final bool isHumanSender = m.senderId == uid &&
          (m.senderChatId == null || m.senderChatId!.trim().isEmpty) &&
          !m.isFromAnonymousAdmin;

      String nextSenderName = m.senderName;
      String? nextSenderAvatar = m.senderAvatarUrl;
      if (isHumanSender) {
        if (hasName && m.senderName != trimmedName) {
          nextSenderName = trimmedName;
          changed = true;
        }
        if (updateAvatar && (m.senderAvatarUrl ?? '') != trimmedAvatar) {
          nextSenderAvatar = trimmedAvatar;
          changed = true;
        }
      }

      ReplyInfo? nextReply = m.replyInfo;
      if (hasName &&
          nextReply != null &&
          nextReply.senderId == uid &&
          nextReply.senderName != trimmedName) {
        nextReply = nextReply.copyWith(senderName: trimmedName);
        changed = true;
      }

      String? nextFwdName = m.forwardFromName;
      String? nextFwdAvatar = m.forwardFromAvatarUrl;
      if (m.isForward && m.forwardFromId == uid) {
        if (hasName && m.forwardFromName != trimmedName) {
          nextFwdName = trimmedName;
          changed = true;
        }
        if (updateAvatar && (m.forwardFromAvatarUrl ?? '') != trimmedAvatar) {
          nextFwdAvatar = trimmedAvatar;
          changed = true;
        }
      }

      if (!changed) return null;
      return m.copyWith(
        senderName: nextSenderName,
        senderAvatarUrl: nextSenderAvatar,
        replyInfo: nextReply,
        forwardFromName: nextFwdName,
        forwardFromAvatarUrl: nextFwdAvatar,
      );
    }

    for (final entry in _snapshots.entries.toList()) {
      final snap = entry.value;
      bool snapChanged = false;
      bool metaChanged = false;

      Chat? nextChat = snap.chat;
      if (nextChat != null) {
        bool chatChanged = false;
        String cName = nextChat.name;
        String? cAvatar = nextChat.avatarUrl;
        String? cLastSenderName = nextChat.lastMessageSenderName;
        Message? cPinned = nextChat.pinnedMessage;

        if (nextChat.chatType == 'private' && nextChat.otherUserId == uid) {
          if (hasName && nextChat.name != trimmedName) {
            cName = trimmedName;
            chatChanged = true;
          }
          if (updateAvatar && (nextChat.avatarUrl ?? '') != trimmedAvatar) {
            cAvatar = trimmedAvatar;
            chatChanged = true;
          }
        }
        if (hasName &&
            nextChat.lastMessageSenderId == uid &&
            nextChat.lastMessageSenderName != trimmedName) {
          cLastSenderName = trimmedName;
          chatChanged = true;
        }
        if (cPinned != null) {
          final updatedPinned = updateMessage(cPinned);
          if (updatedPinned != null) {
            cPinned = updatedPinned;
            chatChanged = true;
          }
        }
        if (chatChanged) {
          nextChat = nextChat.copyWith(
            name: cName,
            avatarUrl: cAvatar,
            lastMessageSenderName: cLastSenderName,
            pinnedMessage: cPinned,
          );
          snapChanged = true;
        }
      }

      ChatDetails? nextDetails = snap.chatDetails;
      if (nextDetails != null) {
        bool detailsChanged = false;
        String dName = nextDetails.name;
        String? dAvatar = nextDetails.avatarUrl;
        Message? dPinned = nextDetails.pinnedMessage;

        bool hasParticipantMatch = false;
        final nextParticipants = nextDetails.participants.map((p) {
          if (p.id != uid) return p;
          hasParticipantMatch = true;
          final pName = hasName ? trimmedName : p.displayName;
          final pAvatar = updateAvatar ? trimmedAvatar : p.avatarUrl;
          if (pName != p.displayName || (p.avatarUrl ?? '') != pAvatar) {
            detailsChanged = true;
            return p.copyWith(displayName: pName, avatarUrl: pAvatar);
          }
          return p;
        }).toList();

        if (nextDetails.chatType == 'private' &&
            (hasParticipantMatch || nextChat?.otherUserId == uid)) {
          if (hasName && nextDetails.name != trimmedName) {
            dName = trimmedName;
            detailsChanged = true;
          }
          if (updateAvatar && (nextDetails.avatarUrl ?? '') != trimmedAvatar) {
            dAvatar = trimmedAvatar;
            detailsChanged = true;
          }
        }
        if (dPinned != null) {
          final updatedPinned = updateMessage(dPinned);
          if (updatedPinned != null) {
            dPinned = updatedPinned;
            detailsChanged = true;
          }
        }
        if (detailsChanged) {
          nextDetails = nextDetails.copyWith(
            name: dName,
            avatarUrl: dAvatar,
            participants: nextParticipants,
            pinnedMessage: dPinned,
          );
          snapChanged = true;
          metaChanged = true;
        }
      }

      List<Message>? nextMessages = snap.messages;
      if (nextMessages != null && nextMessages.isNotEmpty) {
        bool msgsChanged = false;
        final updatedList = <Message>[];
        for (final m in nextMessages) {
          final u = updateMessage(m);
          if (u != null) {
            updatedList.add(u);
            msgsChanged = true;
          } else {
            updatedList.add(m);
          }
        }
        if (msgsChanged) {
          nextMessages = updatedList;
          snapChanged = true;
        }
      }

      List<Message>? nextPinnedList = snap.pinnedMessages;
      if (nextPinnedList != null && nextPinnedList.isNotEmpty) {
        bool pinnedChanged = false;
        final updatedPinnedList = <Message>[];
        for (final m in nextPinnedList) {
          final u = updateMessage(m);
          if (u != null) {
            updatedPinnedList.add(u);
            pinnedChanged = true;
          } else {
            updatedPinnedList.add(m);
          }
        }
        if (pinnedChanged) {
          nextPinnedList = updatedPinnedList;
          snapChanged = true;
          metaChanged = true;
        }
      }

      if (snapChanged) {
        final updatedSnap = snap.copyWith(
          chat: nextChat,
          chatDetails: nextDetails,
          messages: nextMessages,
          pinnedMessages: nextPinnedList,
        );
        _snapshots[entry.key] = updatedSnap;
        if (metaChanged) {
          _persistMetaSnapshot(updatedSnap);
        }
      }
    }
  }

  @visibleForTesting
  void seedSnapshotForTesting(ChatInstantSnapshot snapshot) {
    _snapshots[snapshot.chatId] = snapshot;
  }

  @visibleForTesting
  void clearForTesting() {
    clearMemory();
  }

  void clearMemory() {
    _snapshots.clear();
  }

  void _persistAppearance(String chatId, ChatAppearanceConfig config) {
    final raw = jsonEncode(config.toJson());
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString('$_appearancePrefix$chatId', raw))
        .catchError((_) => false);
  }

  void _persistMetaSnapshot(ChatInstantSnapshot snap) {
    final details = snap.chatDetails;
    final pinned = snap.effectivePinnedMessage;
    final payload = <String, dynamic>{
      'id': snap.chatId,
      if (details != null) 'chat_type': details.chatType,
      if (details != null) 'name': details.name,
      if (details?.avatarUrl != null) 'avatar_url': details!.avatarUrl,
      if (details != null) 'created_by': details.createdBy,
      if (details != null) 'created_at': details.createdAt,
      if (details != null) 'updated_at': details.updatedAt,
      if (snap.isBot != null) 'is_bot': snap.isBot,
      if (snap.isVerified != null) 'is_verified': snap.isVerified,
      if (snap.username != null) 'username': snap.username,
      if (snap.bio != null) 'description': snap.bio,
      if (snap.myRole != null) 'my_role': snap.myRole,
      if (snap.isMember != null) 'is_member': snap.isMember,
      if (snap.memberCount != null) 'member_count': snap.memberCount,
      if (snap.subscriberCount != null)
        'subscriber_count': snap.subscriberCount,
      if (snap.linkedChat != null) 'linked_chat': snap.linkedChat!.toJson(),
      if (snap.pinnedMessagesCount != null)
        'pinned_messages_count': snap.pinnedMessagesCount,
      if (details?.pinnedMessageId != null)
        'pinned_message_id': details!.pinnedMessageId,
      if (details != null && details.pinnedMessageIds.isNotEmpty)
        'pinned_message_ids': details.pinnedMessageIds,
      if (pinned != null) 'pinned_message': _encodeLightweightMessage(pinned),
      if (snap.messageAutoDeleteTime != null)
        'message_auto_delete_time': snap.messageAutoDeleteTime,
      if (snap.hasProtectedContent != null)
        'has_protected_content': snap.hasProtectedContent,
      if (details != null) 'sign_messages': details.signMessages,
      if (details != null) 'show_author_profiles': details.showAuthorProfiles,
      if (details != null) 'is_public': details.isPublic,
      if (details != null) 'is_forum': details.isForum,
      if (details != null) 'participants_hidden': details.participantsHidden,
      if (details != null) 'slow_mode_interval': details.slowModeInterval,
      if (details != null)
        'slow_mode_wait_seconds': details.slowModeWaitSeconds,
      if (details != null)
        'slow_mode_next_send_date': details.slowModeNextSendDate,
      if (details != null) 'has_active_call': details.hasActiveCall,
      if (details?.activeCallId != null)
        'active_call_id': details!.activeCallId,
      if (details?.defaultPermissions != null)
        'default_permissions': details!.defaultPermissions!.toJson(),
      if (details?.myAdminPermissions != null)
        'my_admin_permissions': details!.myAdminPermissions!.toJson(),
      if (details?.myRestrictions != null)
        'my_restrictions': details!.myRestrictions!.toJson(),
      if (details?.restrictedUntil != null)
        'restricted_until': details!.restrictedUntil!.toUtc().toIso8601String(),
      if (details != null && details.myAdminTitle.isNotEmpty)
        'my_admin_title': details.myAdminTitle,
      if (details != null && details.myIsAnonymous) 'my_is_anonymous': true,
      if (details?.reactionSettings != null)
        'reaction_settings': details!.reactionSettings!.toJson(),
      if (details?.mySendAsChatId != null)
        'my_send_as_chat_id': details!.mySendAsChatId,
    };

    final raw = jsonEncode(payload);
    SharedPreferences.getInstance()
        .then((prefs) => prefs.setString('$_metaPrefix${snap.chatId}', raw))
        .catchError((_) => false);
  }

  Map<String, dynamic> _encodeLightweightMessage(Message m) => {
        'id': m.id,
        'chat_id': m.chatId,
        'sender_id': m.senderId,
        'content': m.content,
        'message_type': m.messageType,
        'is_edited': m.isEdited,
        'created_at': m.createdAt,
        'sender_name': m.senderName,
        if (m.fileUrl != null) 'file_url': m.fileUrl,
        if (m.fileName != null) 'file_name': m.fileName,
        if (m.isSilent) 'is_silent': true,
        if (m.viewsCount > 0) 'views_count': m.viewsCount,
        if (m.authorSignature != null) 'author_signature': m.authorSignature,
      };

  ChatInstantSnapshot? _decodeMetaSnapshot(String chatId, String raw) {
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return null;
      final map = Map<String, dynamic>.from(decoded);
      final ChatDetails? details = map.containsKey('chat_type')
          ? ChatDetails.fromJson(map)
          : null;
      final pinned = details?.pinnedMessage;
      return ChatInstantSnapshot(
        chatId: chatId,
        chatDetails: details,
        pinnedMessages: pinned != null ? [pinned] : null,
        isBot: map['is_bot'] as bool?,
        isVerified: map['is_verified'] as bool?,
        username: map['username']?.toString(),
        bio: map['description']?.toString(),
        myRole: map['my_role']?.toString(),
        isMember: map['is_member'] as bool?,
        memberCount: (map['member_count'] as num?)?.toInt(),
        subscriberCount: (map['subscriber_count'] as num?)?.toInt(),
        linkedChat: LinkedChatSummary.tryParse(map['linked_chat']),
        pinnedMessagesCount: (map['pinned_messages_count'] as num?)?.toInt(),
        messageAutoDeleteTime:
            (map['message_auto_delete_time'] as num?)?.toInt(),
        hasProtectedContent: map['has_protected_content'] as bool?,
      );
    } catch (_) {
      return null;
    }
  }
}
