import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';
import 'auth_service.dart';
import 'avatar_sync_service.dart';
import 'chat_service.dart';
import 'community_service.dart';
import 'file_service.dart';
import 'media_cache_manager.dart';
import 'peer_customization_cache.dart';
import 'websocket_service.dart';
import 'database/app_database.dart';
import '../models/profile_customization.dart';

/// Сервис синхронизации данных между сервером и локальной БД (Drift/SQLite)
class SyncService {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  AppDatabase get _db => AppDatabase();
  // ignore: unused_field — будет использоваться для real-time sync через WebSocket
  final WebSocketService _ws = WebSocketService();
  final _uuid = const Uuid();

  /// Инициализация: открыть БД, запустить первичную синхронизацию
  Future<void> initialize() async {
    await _db.initialize();
    await syncFromServer();
  }

  /// Delta Sync: получить обновления с сервера и применить к локальной БД
  Future<void> syncFromServer() async {
    final userId = await AuthService.getUserId();
    if (userId == null) return;

    // Запуск отложенной синхронизации аватарок
    AvatarSyncService().syncPendingAvatar(userId);

    final lastUsn = await _db.getLastKnownUsn(userId);
    debugPrint('SyncService: Starting delta sync from USN $lastUsn');

    try {
      final result = await ChatService.getUpdates(sinceUsn: lastUsn);
      if (result['success'] != true) {
        debugPrint('SyncService: Delta sync failed: ${result['message']}');
        return;
      }

      final tooLong = result['too_long'] == true;
      final events = result['events'] as List<dynamic>? ?? [];
      final maxUsn = (result['max_usn'] as num?)?.toInt() ??
          (result['current_usn'] as num?)?.toInt() ??
          lastUsn;
      final hasMore = result['has_more'] as bool? ?? false;

      if (tooLong) {
        debugPrint(
            'SyncService: Server returned too_long=true, refreshing chats & advancing USN to $maxUsn');
        try {
          await ChatService.getChats();
        } catch (e) {
          debugPrint('SyncService: too_long getChats refresh failed: $e');
        }
        await _db.setLastKnownUsn(userId, maxUsn);
        return;
      }

      for (final event in events) {
        if (event is Map<String, dynamic>) {
          await _applyEvent(event);
        } else if (event is Map) {
          await _applyEvent(Map<String, dynamic>.from(event));
        }
      }

      // Обновить USN
      await _db.setLastKnownUsn(userId, maxUsn);
      debugPrint(
          'SyncService: Applied ${events.length} events, new USN=$maxUsn, hasMore=$hasMore');

      // Если есть ещё события — продолжить синхронизацию
      if (hasMore) {
        await syncFromServer();
      }
    } catch (e) {
      debugPrint('SyncService: Error during delta sync: $e');
    }
  }

  /// Применить одно событие обновления к локальной БД
  Future<void> _applyEvent(Map<String, dynamic> event) async {
    final eventType = event['event_type'] as String?;
    final payload = event['payload'] as Map<String, dynamic>? ?? {};
    final chatId =
        event['chat_id']?.toString() ?? payload['chat_id']?.toString();

    switch (eventType) {
      case 'new_message':
        await _applyNewMessage(payload);
        break;
      case 'edit_message':
      case 'message_edited':
        await _applyEditMessage(payload);
        break;
      case 'delete_message':
      case 'message_deleted':
        await _applyDeleteMessage(payload);
        break;
      case 'read_status':
      case 'message_read':
      case 'unread_count_updated':
        await _applyReadStatus(payload);
        break;
      case 'message_listened':
        break;
      case 'message_pinned':
      case 'pin_message':
        final pinChatId = payload['chat_id']?.toString() ?? chatId;
        final rawPinId = payload['pinned_message_id'] ?? payload['message_id'];
        final pinId = rawPinId is num
            ? rawPinId.toInt()
            : int.tryParse(rawPinId?.toString() ?? '');
        final hasPinIds = payload.containsKey('pinned_message_ids');
        final pinIds = _extractSyncPinnedIds(payload['pinned_message_ids']);
        if (pinChatId != null) {
          await _db.updateChatPinnedMessageId(
            pinChatId,
            pinId,
            pinnedMessageIds: pinIds,
            updatePinnedMessageIds: hasPinIds,
          );
        }
        break;
      case 'message_unpinned':
      case 'unpin_message':
        final unpinChatId = payload['chat_id']?.toString() ?? chatId;
        final rawNextPinId = payload['pinned_message_id'];
        final nextPinId = rawNextPinId is num
            ? rawNextPinId.toInt()
            : int.tryParse(rawNextPinId?.toString() ?? '');
        final hasUnpinIds = payload.containsKey('pinned_message_ids');
        final unpinIds = _extractSyncPinnedIds(payload['pinned_message_ids']);
        if (unpinChatId != null) {
          await _db.updateChatPinnedMessageId(
            unpinChatId,
            nextPinId,
            pinnedMessageIds: unpinIds,
            updatePinnedMessageIds: hasUnpinIds,
          );
        }
        break;
      case 'new_chat':
        await _applyNewChat(payload);
        break;
      case 'chat_update':
      case 'chat_updated':
      case 'chat_pinned':
        await _applyChatUpdate({
          if (chatId != null) 'chat_id': chatId,
          ...payload,
        });
        break;
      case 'chat_archive_updated':
        final archiveChatId = payload['chat_id']?.toString() ?? chatId;
        final isArchived =
            payload['is_archived'] == true || payload['is_archived'] == 1;
        if (archiveChatId != null && archiveChatId.isNotEmpty) {
          await _db.setChatArchived(archiveChatId, isArchived);
        }
        break;
      case 'chat_unread_marked':
        final markChatId = payload['chat_id']?.toString() ?? chatId;
        final isMarked = payload['is_marked_unread'] == true;
        if (markChatId != null && markChatId.isNotEmpty) {
          final existingChat = await _db.getChat(markChatId);
          if (isMarked && (existingChat == null || existingChat.unreadCount == 0)) {
            await _db.updateUnreadCount(markChatId, -1);
          } else if (!isMarked && existingChat?.unreadCount == -1) {
            await _db.updateUnreadCount(markChatId, 0);
          }
        }
        break;
      case 'delete_chat':
      case 'chat_deleted':
        if (chatId != null) {
          await _db.deleteChat(chatId);
          await _db.deleteMessagesForChat(chatId);
        }
        break;
      case 'history_cleared':
        if (chatId != null) {
          await _db.deleteMessagesForChat(chatId);
          await _db.updateChatPinnedMessageId(
            chatId,
            null,
            pinnedMessageIds: const [],
            updatePinnedMessageIds: true,
          );
          await _db.refreshChatLastMessageFromDb(chatId, allowClear: true);
        }
        break;
      case 'draft_updated':
        break;
      case 'message_burned':
        final burnMsgId = payload['message_id']?.toString();
        if (burnMsgId != null && burnMsgId.isNotEmpty) {
          await _db.markMessageBurned(
            burnMsgId,
            viewedAt: payload['viewed_at']?.toString(),
            expiresAt: payload['expires_at']?.toString(),
            isBurned: payload['is_burned'] == true,
          );
        }
        break;
      case 'chat_auto_delete_updated':
        final autoChatId = payload['chat_id']?.toString() ?? chatId;
        final rawTtl = payload['message_auto_delete_time'] ??
            payload['ttl_seconds'];
        final ttlSec = rawTtl is num
            ? rawTtl.toInt()
            : int.tryParse(rawTtl?.toString() ?? '') ?? 0;
        if (autoChatId != null && autoChatId.isNotEmpty) {
          await _db.updateChatAutoDeleteTime(autoChatId, ttlSec);
        }
        break;
      case 'chat_appearance_updated':
        final appChatId = payload['chat_id']?.toString() ?? chatId;
        final rawApp = payload['appearance'];
        if (appChatId != null && appChatId.isNotEmpty) {
          await _db.updateChatAppearanceJson(
            appChatId,
            rawApp is Map ? jsonEncode(rawApp) : null,
          );
        }
        break;
      case 'user_appearance_updated':
        final targetUserId = payload['user_id']?.toString();
        if (targetUserId != null && targetUserId.isNotEmpty) {
          PeerCustomizationCache.instance.mergeFromJson(targetUserId, payload);
          final cachedJson =
              PeerCustomizationCache.instance.getSync(targetUserId)?.toJsonString();
          await _db.updateUserCustomizationJson(targetUserId, cachedJson);
        }
        break;
      case 'chat_settings_updated':
      case 'message_views_updated':
      case 'post_comments_updated':
      case 'member_updated':
      case 'scheduled_messages_updated':
      case 'join_requests_updated':
        await ChatService.handleWebSocketEvent(
          WebSocketEvent(
            type: WebSocketEvent.fromJson({'type': eventType}).type,
            rawType: eventType ?? '',
            data: {
              if (chatId != null) 'chat_id': chatId,
              ...payload,
            },
            timestamp: DateTime.now().millisecondsSinceEpoch,
          ),
          db: _db,
        );
        break;
      default:
        debugPrint('SyncService: Unknown event type: $eventType');
    }
  }

  List<int> _extractSyncPinnedIds(dynamic raw) {
    if (raw is! List) return const [];
    final ids = <int>[];
    for (final item in raw) {
      final parsed = item is num ? item.toInt() : int.tryParse(item.toString());
      if (parsed != null && parsed > 0) ids.add(parsed);
    }
    return ids;
  }

  Future<void> _applyNewMessage(Map<String, dynamic> payload) async {
    final serverId =
        (payload['message_id'] ?? payload['id'])?.toString();
    final chatId = payload['chat_id']?.toString();
    if (serverId == null || chatId == null) return;

    // Проверить, есть ли уже это сообщение (по serverId)
    final existing = await _db.getMessageByServerId(serverId);
    if (existing != null) return; // Уже есть — пропускаем

    String? entitiesStr;
    if (payload['entities'] != null) {
      if (payload['entities'] is String) {
        entitiesStr = payload['entities'] as String;
      } else {
        entitiesStr = jsonEncode(payload['entities']);
      }
    }
    String? linkPreviewOptionsStr;
    final msgType = payload['message_type']?.toString() ?? 'text';
    if (msgType == 'voice' && (payload['waveform'] != null || payload['duration'] != null)) {
      linkPreviewOptionsStr = jsonEncode({
        if (payload['waveform'] != null) 'waveform': payload['waveform'],
        if (payload['duration'] != null) 'duration': payload['duration'],
      });
    } else if (payload['link_preview_options'] != null) {
      if (payload['link_preview_options'] is String) {
        linkPreviewOptionsStr = payload['link_preview_options'] as String;
      } else {
        linkPreviewOptionsStr = jsonEncode(payload['link_preview_options']);
      }
    }
    final bool invertMedia = payload['invert_media'] == true ||
        payload['invert_media'] == 1 ||
        payload['invert_media'] == 'true';
    final String? groupedId = payload['grouped_id']?.toString();
    Map<String, dynamic> mediaPayloadMap = {};
    if (payload['media_payload'] is Map) {
      mediaPayloadMap =
          Map<String, dynamic>.from(payload['media_payload'] as Map);
    } else if (payload['media_payload'] is String &&
        (payload['media_payload'] as String).isNotEmpty) {
      try {
        final decoded = jsonDecode(payload['media_payload'] as String);
        if (decoded is Map) {
          mediaPayloadMap = Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    if (payload['reply_markup'] != null) {
      mediaPayloadMap['reply_markup'] = payload['reply_markup'];
    }
    if (payload['via_bot_id'] != null) {
      mediaPayloadMap['via_bot_id'] = payload['via_bot_id'];
    }
    if (payload['via_bot_username'] != null) {
      mediaPayloadMap['via_bot_username'] = payload['via_bot_username'];
    }
    if (payload['can_comment'] == true) {
      mediaPayloadMap['can_comment'] = true;
    }
    if (payload['channel_post_id'] != null &&
        payload['channel_post_id'].toString().isNotEmpty) {
      mediaPayloadMap['channel_post_id'] =
          payload['channel_post_id'].toString();
    }
    final String? mediaPayloadStr =
        mediaPayloadMap.isNotEmpty ? jsonEncode(mediaPayloadMap) : null;
    final recentRepliersList =
        RecentReplier.parseList(payload['recent_repliers']);
    final String? recentRepliersStr = recentRepliersList.isNotEmpty
        ? jsonEncode(recentRepliersList.map((r) => r.toJson()).toList())
        : null;
    final String? rawThreadRootId =
        payload['thread_root_message_id']?.toString().trim();
    final bool isThreadComment =
        rawThreadRootId != null && rawThreadRootId.isNotEmpty;

    final String? senderCustJsonStr = () {
      final raw = payload['sender_customization'];
      if (raw is Map) {
        final cust = PeerCustomization.fromJson(Map<String, dynamic>.from(raw));
        final sid = payload['sender_id']?.toString() ?? '';
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
        (payload['forwarded_from_avatar_url'] ?? payload['forward_from_avatar_url'])
            ?.toString();

    await _db.saveMessage(MessagesCompanion(
      serverId: Value(serverId),
      localId: Value(_uuid.v4()),
      chatId: Value(chatId),
      senderId: Value(payload['sender_id']?.toString() ?? ''),
      content: Value(payload['content']?.toString() ?? ''),
      messageType: Value(payload['message_type']?.toString() ?? 'text'),
      fileUrl: Value(() {
        final raw = payload['file_url']?.toString().trim();
        return (raw != null && raw.isNotEmpty) ? raw : null;
      }()),
      fileName: Value(() {
        final raw = payload['file_name']?.toString().trim();
        return (raw != null && raw.isNotEmpty) ? raw : null;
      }()),
      replyToMessageId: Value(payload['reply_to_message_id']?.toString()),
      isQuote: Value(payload['is_quote'] as bool? ?? false),
      quoteText: Value(payload['quote_text']?.toString()),
      quoteOffset: Value(payload['quote_offset'] as int? ?? 0),
      quoteLength: Value(payload['quote_length'] as int? ?? 0),
      replyToSenderId: Value(payload['reply_to_sender_id']?.toString()),
      replyToSenderName: Value(payload['reply_to_sender_name']?.toString()),
      replyToContent: Value(payload['reply_to_content']?.toString()),
      replyToMessageType:
          Value(payload['reply_to_message_type']?.toString() ?? 'text'),
      isRead: const Value(false),
      isEdited: const Value(false),
      sendStatus: Value(MessageSendStatus.sent.index),
      senderName: Value(payload['sender_name']?.toString()),
      senderAvatarUrl: Value(payload['sender_avatar_url']?.toString()),
      createdAt: Value(payload['created_at']?.toString() ??
          DateTime.now().toIso8601String()),
      isForward: Value(payload['is_forward'] == true ||
          payload['is_forwarded'] == true ||
          payload['forward_from_id'] != null ||
          payload['forwarded_from_user_id'] != null ||
          payload['forwarded_from_chat_id'] != null ||
          (payload['forward_from_name'] != null &&
              payload['forward_from_name'].toString().isNotEmpty) ||
          (payload['forwarded_from_name'] != null &&
              payload['forwarded_from_name'].toString().isNotEmpty)),
      forwardFromId: Value((payload['forward_from_id'] ??
              payload['forwarded_from_user_id'] ??
              payload['forwarded_from_chat_id'])
          ?.toString()),
      forwardFromName: Value(
          (payload['forward_from_name'] ?? payload['forwarded_from_name'])
              ?.toString()),
      forwardFromAvatarUrl: Value(fwdAvatarUrl),
      senderCustomizationJson: Value(senderCustJsonStr),
      entities: Value(entitiesStr),
      linkPreviewOptions: Value(linkPreviewOptionsStr),
      mediaPayload: Value(mediaPayloadStr),
      invertMedia: Value(invertMedia),
      isRound: Value(payload['is_round'] == true ||
          payload['message_type'] == 'round'),
      groupedId: Value(groupedId),
      viewsCount: Value((payload['views_count'] as num?)?.toInt() ?? 0),
      authorSignature: Value(payload['author_signature']?.toString()),
      postAuthorId: Value(payload['post_author_id']?.toString()),
      senderRole: Value(payload['sender_role']?.toString()),
      senderAdminTitle: Value(payload['sender_admin_title']?.toString()),
      isFromAnonymousAdmin:
          Value(payload['is_from_anonymous_admin'] == true),
      isSilent: Value(payload['is_silent'] == true),
      commentsCount: Value((payload['comments_count'] as num?)?.toInt() ?? 0),
      recentRepliersJson: Value(recentRepliersStr),
      threadRootMessageId: Value(isThreadComment ? rawThreadRootId : null),
      hasMediaSpoiler: Value(
        payload['has_media_spoiler'] == true ||
            payload['has_media_spoiler'] == 1 ||
            mediaPayloadMap['has_media_spoiler'] == true,
      ),
      expiresAt: Value(payload['expires_at']?.toString()),
      ttlSeconds: Value((payload['ttl_seconds'] as num?)?.toInt() ??
          int.tryParse(payload['ttl_seconds']?.toString() ?? '') ??
          0),
      isViewOnce: Value(
        payload['is_view_once'] == true || payload['is_view_once'] == 1,
      ),
      viewedAt: Value(payload['viewed_at']?.toString()),
      isBurned: Value(payload['is_burned'] == true ||
          ((payload['is_view_once'] == true || payload['is_view_once'] == 1) &&
              payload['viewed_at'] != null &&
              payload['viewed_at'].toString().isNotEmpty)),
      replyToChatId: Value(payload['reply_to_chat_id']?.toString()),
      replyToChatName: Value(payload['reply_to_chat_name']?.toString()),
      replyToChatType: Value(payload['reply_to_chat_type']?.toString()),
      effectId: Value(payload['effect_id']?.toString()),
      savedTagsJson: payload['saved_tags'] is List
          ? Value(jsonEncode(payload['saved_tags']))
          : const Value.absent(),
    ));

    final isCommunityChannel =
        payload['community_id'] != null ||
        CommunityService.isCommunityChannelId(chatId);

    // Also update chat's last message if message is newer (only for standalone chats, not community channels)
    final chat = await _db.getChat(chatId);
    if (isCommunityChannel) {
      if (chat != null) {
        await _db.deleteChat(chatId);
      }
      return;
    }
    if (isThreadComment) {
      return;
    }

    final msgCreatedAt = payload['created_at']?.toString() ?? '';
    final safeCreatedAt = msgCreatedAt.isNotEmpty
        ? msgCreatedAt
        : DateTime.now().toIso8601String();
    final isRound = payload['is_round'] == true ||
        payload['message_type'] == 'round';
    final messageType = payload['message_type']?.toString() ?? 'text';
    final content = payload['content']?.toString() ?? '';

    if (chat != null) {
      bool isNewer = true;
      if (chat.lastMessageTime != null) {
        final newTime = DateTime.tryParse(safeCreatedAt);
        final oldTime = DateTime.tryParse(chat.lastMessageTime!);
        if (newTime != null && oldTime != null) {
          isNewer = newTime.isAfter(oldTime) || newTime.isAtSameMomentAs(oldTime);
        } else {
          isNewer = safeCreatedAt.compareTo(chat.lastMessageTime!) >= 0;
        }
      }
      if (isNewer) {
        await _db.updateChatLastMessage(
          chatId: chatId,
          content: content,
          createdAt: safeCreatedAt,
          messageType: messageType,
          isRound: isRound,
          fileUrl: payload['file_url']?.toString(),
          groupedId: groupedId,
          senderId: payload['sender_id']?.toString(),
          senderName: payload['sender_name']?.toString(),
          incrementUnread: false,
        );
      }
    } else {
      final stubChatType = payload['chat_type']?.toString() ?? 'private';
      // Upsert chat stub so it immediately appears in the chat list
      await _db.saveChat(ChatsCompanion(
        chatId: Value(chatId),
        chatType: Value(stubChatType),
        name: Value(payload['sender_name']?.toString() ?? 'Чат'),
        avatarUrl: Value(payload['sender_avatar_url']?.toString()),
        lastMessage: Value(content),
        lastMessageTime: Value(safeCreatedAt),
        lastMessageType: Value(messageType),
        lastMessageIsRound: Value(isRound),
        lastMessageFileUrl: Value(payload['file_url']?.toString()),
        lastMessageGroupedId: Value(groupedId),
        lastMessageSenderId: Value(payload['sender_id']?.toString()),
        lastMessageSenderName: Value(payload['sender_name']?.toString()),
        otherUserId: Value(payload['sender_id']?.toString()),
        updatedAt: Value(safeCreatedAt),
        unreadCount: const Value(1),
        showAuthorProfiles: Value(stubChatType != 'channel'),
      ));
    }
  }

  Future<void> _applyEditMessage(Map<String, dynamic> payload) async {
    final serverId = payload['message_id']?.toString();
    if (serverId == null) return;

    String? entitiesStr;
    if (payload['entities'] != null) {
      if (payload['entities'] is String) {
        entitiesStr = payload['entities'] as String;
      } else {
        entitiesStr = jsonEncode(payload['entities']);
      }
    }

    Map<String, dynamic>? incomingMediaMap;
    if (payload['media_payload'] is Map) {
      incomingMediaMap =
          Map<String, dynamic>.from(payload['media_payload'] as Map);
    } else if (payload['media_payload'] is String &&
        (payload['media_payload'] as String).isNotEmpty) {
      try {
        final dec = jsonDecode(payload['media_payload'] as String);
        if (dec is Map) incomingMediaMap = Map<String, dynamic>.from(dec);
      } catch (_) {}
    } else if (payload['poll'] is Map) {
      incomingMediaMap = Map<String, dynamic>.from(payload['poll'] as Map);
    }

    final existingMsg = await _db.getMessageByServerId(serverId);
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
      replyMarkup: payload['reply_markup'],
    );
    final String? mediaPayloadStr =
        mergedMedia != null ? jsonEncode(mergedMedia) : null;

    final isPollUpdate = payload['message_type'] == 'poll' ||
        existingMsg?.messageType == 'poll';
    final bool? hasMediaSpoiler = payload.containsKey('has_media_spoiler')
        ? (payload['has_media_spoiler'] == true ||
            payload['has_media_spoiler'] == 1)
        : null;
    final bool effectiveIsEdited = payload.containsKey('is_edited')
        ? (payload['is_edited'] == true
            ? true
            : (existingMsg?.isEdited ?? false))
        : (isPollUpdate ? (existingMsg?.isEdited ?? false) : true);
    final bool? invertMedia = payload.containsKey('invert_media')
        ? (payload['invert_media'] == true || payload['invert_media'] == 1)
        : null;
    final String? editedFileUrl = payload.containsKey('file_url')
        ? payload['file_url']?.toString()
        : null;
    final String? editedFileName = payload.containsKey('file_name')
        ? payload['file_name']?.toString()
        : null;
    final String? editedMessageType = payload.containsKey('message_type')
        ? payload['message_type']?.toString()
        : null;
    await _db.updateMessageContent(
      serverId,
      payload['content']?.toString() ?? existingMsg?.content ?? '',
      entitiesStr,
      mediaPayloadStr,
      effectiveIsEdited,
      hasMediaSpoiler,
      editedFileUrl,
      editedFileName,
      editedMessageType,
      invertMedia,
    );
    final chatId = payload['chat_id']?.toString();
    if (chatId != null) {
      await _db.refreshChatLastMessageFromDb(chatId);
    }
  }

  Future<void> _applyDeleteMessage(Map<String, dynamic> payload) async {
    final serverId = payload['message_id']?.toString();
    final rawBatch = payload['message_ids'];
    final ids = <String>[
      if (rawBatch is List)
        ...rawBatch.map((e) => e.toString()).where((e) => e.isNotEmpty),
      if (serverId != null && serverId.isNotEmpty) serverId,
    ];
    if (ids.isEmpty) return;
    if (ids.length == 1) {
      await _db.deleteMessage(ids.first);
    } else {
      await _db.deleteMessagesBatch(ids);
    }
    final chatId = payload['chat_id']?.toString();
    if (chatId != null) {
      await _db.refreshChatLastMessageFromDb(chatId);
    }
  }

  Future<void> _applyReadStatus(Map<String, dynamic> payload) async {
    final chatId = payload['chat_id']?.toString();
    if (chatId == null) return;

    final unreadCount = payload['unread_count'] as int?;
    final rawInboxHwm = payload['last_read_inbox_message_id'];
    final inboxHwm = rawInboxHwm is num
        ? rawInboxHwm.toInt()
        : int.tryParse(rawInboxHwm?.toString() ?? '');
    final rawOutboxHwm =
        payload['last_read_outbox_message_id'] ?? payload['max_id'];
    final outboxHwm = rawOutboxHwm is num
        ? rawOutboxHwm.toInt()
        : int.tryParse(rawOutboxHwm?.toString() ?? '');

    if (outboxHwm != null && outboxHwm > 0) {
      final myUserId = await AuthService.getUserId() ?? '';
      await _db.markOutboxMessagesReadUpTo(
        chatId,
        myUserId,
        outboxHwm,
        readAt: payload['read_at']?.toString(),
      );
    }
    if ((inboxHwm != null && inboxHwm > 0) || unreadCount != null) {
      await _db.updateChatReadHwm(
        chatId,
        lastReadInboxMessageId: inboxHwm,
        lastReadOutboxMessageId: outboxHwm,
        unreadCount: unreadCount,
      );
    }
  }

  Future<void> _applyNewChat(Map<String, dynamic> payload) async {
    final chatId = payload['chat_id']?.toString();
    if (chatId == null) return;

    final existing = await _db.getChat(chatId);
    if (existing != null) return;

    final chatType = payload['chat_type']?.toString() ?? 'private';
    String name = payload['name']?.toString() ?? '';
    if (name.trim().isEmpty || name.trim() == '?') {
      if (chatType == 'saved') {
        name = 'Избранное';
      } else if (chatType == 'private') {
        name = 'Пользователь';
      } else {
        name = 'Чат';
      }
    }

    final showAuthor = payload.containsKey('show_author_profiles')
        ? (payload['show_author_profiles'] == true ||
            payload['show_author_profiles'] == 1)
        : (chatType != 'channel');
    final perms = GroupDefaultPermissions.tryParse(
      payload['default_permissions'] ?? payload['chat_permissions'],
    );
    final reactions = ReactionSettings.fromChatJson(payload);
    final linkedChatId = payload['linked_chat_id']?.toString().trim();

    await _db.saveChat(ChatsCompanion(
      chatId: Value(chatId),
      chatType: Value(chatType),
      name: Value(name),
      avatarUrl: Value(payload['avatar_url']?.toString()),
      otherUserId: Value(payload['other_user_id']?.toString()),
      updatedAt: Value(payload['updated_at']?.toString() ??
          DateTime.now().toIso8601String()),
      unreadCount: const Value(0),
      isOnline: const Value(false),
      isPinned: const Value(false),
      showAuthorProfiles: Value(showAuthor),
      signMessages: Value(
        payload['sign_messages'] == true || payload['sign_messages'] == 1,
      ),
      linkedChatId: Value(
        (linkedChatId != null && linkedChatId.isNotEmpty) ? linkedChatId : null,
      ),
      myRole: Value(payload['my_role']?.toString()),
      hasActiveCall: Value(
        payload['has_active_call'] == true || payload['has_active_call'] == 1,
      ),
      chatPermissionsJson: perms != null
          ? Value(jsonEncode(perms.toJson()))
          : const Value.absent(),
      reactionSettingsJson: reactions != null
          ? Value(jsonEncode(reactions.toJson()))
          : const Value.absent(),
      peerCustomizationJson: Value(payload['peer_customization'] is Map
          ? jsonEncode(payload['peer_customization'])
          : payload['peer_customization']?.toString()),
      hasProtectedContent: Value(
        payload['has_protected_content'] == true ||
            payload['has_protected_content'] == 1,
      ),
      pinnedMessageIdsJson: payload['pinned_message_ids'] is List
          ? Value(jsonEncode(
              _extractSyncPinnedIds(payload['pinned_message_ids'])))
          : const Value.absent(),
    ));
  }

  Future<void> _applyChatUpdate(Map<String, dynamic> payload) async {
    final chatId = payload['chat_id']?.toString();
    if (chatId == null) return;

    final chat = await _db.getChat(chatId);
    if (chat == null) return;

    final perms = GroupDefaultPermissions.tryParse(
      payload['default_permissions'] ?? payload['chat_permissions'],
    );
    final reactions = ReactionSettings.fromChatJson(payload);
    final rawLinked = payload['linked_chat_id']?.toString().trim();

    // Build companion with only updated fields
    final companion = ChatsCompanion(
      chatId: Value(chatId),
      name: payload.containsKey('name')
          ? Value(payload['name'].toString())
          : Value(chat.name),
      avatarUrl: payload.containsKey('avatar_url')
          ? Value(payload['avatar_url']?.toString())
          : Value(chat.avatarUrl),
      unreadCount: payload.containsKey('unread_count')
          ? Value(payload['unread_count'] as int? ?? chat.unreadCount)
          : Value(chat.unreadCount),
      isPinned: payload.containsKey('is_pinned')
          ? Value(payload['is_pinned'] as bool? ?? chat.isPinned)
          : Value(chat.isPinned),
      isArchived: payload.containsKey('is_archived')
          ? Value(payload['is_archived'] == true || payload['is_archived'] == 1)
          : Value(chat.isArchived),
      updatedAt: payload.containsKey('updated_at')
          ? Value(payload['updated_at'].toString())
          : Value(chat.updatedAt),
      showAuthorProfiles: payload.containsKey('show_author_profiles')
          ? Value(
              payload['show_author_profiles'] == true ||
                  payload['show_author_profiles'] == 1,
            )
          : Value(chat.showAuthorProfiles),
      signMessages: payload.containsKey('sign_messages')
          ? Value(
              payload['sign_messages'] == true || payload['sign_messages'] == 1,
            )
          : Value(chat.signMessages),
      linkedChatId: payload.containsKey('linked_chat_id')
          ? Value((rawLinked != null && rawLinked.isNotEmpty) ? rawLinked : null)
          : Value(chat.linkedChatId),
      myRole: payload.containsKey('my_role')
          ? Value(payload['my_role']?.toString())
          : Value(chat.myRole),
      hasActiveCall: payload.containsKey('has_active_call')
          ? Value(
              payload['has_active_call'] == true ||
                  payload['has_active_call'] == 1,
            )
          : Value(chat.hasActiveCall),
      chatPermissionsJson: perms != null
          ? Value(jsonEncode(perms.toJson()))
          : Value(chat.chatPermissionsJson),
      reactionSettingsJson: reactions != null
          ? Value(jsonEncode(reactions.toJson()))
          : Value(chat.reactionSettingsJson),
      peerCustomizationJson: payload.containsKey('peer_customization')
          ? Value(payload['peer_customization'] is Map
              ? jsonEncode(payload['peer_customization'])
              : payload['peer_customization']?.toString())
          : Value(chat.peerCustomizationJson),
      hasProtectedContent: payload.containsKey('has_protected_content')
          ? Value(
              payload['has_protected_content'] == true ||
                  payload['has_protected_content'] == 1,
            )
          : Value(chat.hasProtectedContent),
      pinnedMessageIdsJson: payload.containsKey('pinned_message_ids')
          ? Value(jsonEncode(
              _extractSyncPinnedIds(payload['pinned_message_ids'])))
          : Value(chat.pinnedMessageIdsJson),
    );

    await _db.saveChat(companion);
  }

  /// Создать локальное pending-сообщение (оптимистичный UI)
  Future<DbMessage> createPendingMessage({
    required String chatId,
    required String senderId,
    required String content,
    String messageType = 'text',
    String? fileUrl,
    String? fileName,
    String? replyToMessageId,
    bool isQuote = false,
    String? quoteText,
    int quoteOffset = 0,
    int quoteLength = 0,
    String? replyToSenderId,
    String? replyToSenderName,
    String? replyToContent,
    String replyToMessageType = 'text',
    dynamic entities,
    dynamic linkPreviewOptions,
    bool invertMedia = false,
    bool isRound = false,
    List<int>? waveform,
    int? duration,
    String? groupedId,
    dynamic mediaPayload,
    bool isSilent = false,
    String? threadRootMessageId,
    bool hasMediaSpoiler = false,
    String? replyToChatId,
    String? replyToChatName,
    String? replyToChatType,
    String? effectId,
    bool isViewOnce = false,
    int ttlSeconds = 0,
  }) async {
    final localId = _uuid.v4();
    final now = DateTime.now().toUtc().toIso8601String();

    final String? entitiesStr = entities is List
        ? jsonEncode(entities.map((e) => e is MessageEntity ? e.toJson() : e).toList())
        : (entities is String ? entities : null);
    String? linkPreviewOptionsStr =
        (messageType == 'voice' || messageType == 'video' || isRound) &&
                (waveform != null || duration != null)
            ? jsonEncode({
                if (waveform != null) 'waveform': waveform,
                if (duration != null) 'duration': duration,
              })
            : (linkPreviewOptions is LinkPreviewOptions
                ? jsonEncode(linkPreviewOptions.toJson())
                : (linkPreviewOptions is Map
                    ? jsonEncode(linkPreviewOptions)
                    : (linkPreviewOptions is String ? linkPreviewOptions : null)));
    if (linkPreviewOptionsStr == null && mediaPayload != null) {
      linkPreviewOptionsStr = mediaPayload is String
          ? mediaPayload
          : jsonEncode(mediaPayload);
    }

    await _db.saveMessage(MessagesCompanion(
      serverId: const Value.absent(), // Нет серверного ID пока
      localId: Value(localId),
      chatId: Value(chatId),
      senderId: Value(senderId),
      content: Value(content),
      messageType: Value(messageType),
      fileUrl: Value(fileUrl),
      fileName: Value(fileName),
      replyToMessageId: Value(replyToMessageId),
      isQuote: Value(isQuote),
      quoteText: Value(quoteText),
      quoteOffset: Value(quoteOffset),
      quoteLength: Value(quoteLength),
      replyToSenderId: Value(replyToSenderId),
      replyToSenderName: Value(replyToSenderName),
      replyToContent: Value(replyToContent),
      replyToMessageType: Value(replyToMessageType),
      isRead: const Value(true), // Свои сообщения всегда "прочитаны"
      isEdited: const Value(false),
      sendStatus: Value(MessageSendStatus.sending.index),
      createdAt: Value(now),
      entities: Value(entitiesStr),
      linkPreviewOptions: Value(linkPreviewOptionsStr),
      invertMedia: Value(invertMedia),
      isRound: Value(isRound),
      groupedId: Value(groupedId),
      isSilent: Value(isSilent),
      threadRootMessageId: Value(threadRootMessageId),
      hasMediaSpoiler: Value(hasMediaSpoiler),
      ttlSeconds: Value(ttlSeconds),
      isViewOnce: Value(isViewOnce),
      isBurned: const Value(false),
      replyToChatId: Value(replyToChatId),
      replyToChatName: Value(replyToChatName),
      replyToChatType: Value(replyToChatType),
      effectId: Value(effectId),
    ));

    // Return the saved message as DbMessage
    return DbMessage(
      serverId: null,
      localId: localId,
      chatId: chatId,
      senderId: senderId,
      content: content,
      messageType: messageType,
      fileUrl: fileUrl,
      fileName: fileName,
      replyToMessageId: replyToMessageId,
      isQuote: isQuote,
      quoteText: quoteText,
      quoteOffset: quoteOffset,
      quoteLength: quoteLength,
      replyToSenderId: replyToSenderId,
      replyToSenderName: replyToSenderName,
      replyToContent: replyToContent,
      replyToMessageType: replyToMessageType,
      isRead: true,
      isEdited: false,
      sendStatus: MessageSendStatus.sending.index,
      senderName: null,
      senderAvatarUrl: null,
      createdAt: now,
      isForward: false,
      forwardFromId: null,
      forwardFromName: null,
      groupedId: groupedId,
      entities: entitiesStr,
      reactions: null,
      linkPreviewOptions: linkPreviewOptionsStr,
      invertMedia: invertMedia,
      isRound: isRound,
      viewsCount: 0,
      authorSignature: null,
      postAuthorId: null,
      senderRole: null,
      senderAdminTitle: null,
      isFromAnonymousAdmin: false,
      isSilent: isSilent,
      commentsCount: 0,
      recentRepliersJson: null,
      threadRootMessageId: threadRootMessageId,
      hasMediaSpoiler: hasMediaSpoiler,
      expiresAt: null,
      ttlSeconds: ttlSeconds,
      isViewOnce: isViewOnce,
      viewedAt: null,
      isBurned: false,
      replyToChatId: replyToChatId,
      replyToChatName: replyToChatName,
      replyToChatType: replyToChatType,
      effectId: effectId,
      savedTagsJson: null,
      topicId: null,
      forwardsCount: 0,
      senderChatId: null,
      senderChatName: null,
      senderChatAvatarUrl: null,
    );
  }

  /// Подтвердить отправку — заменить localId на serverId
  Future<void> confirmMessageSent(String localId, String serverId,
      {String? remoteFileUrl}) async {
    await _db.updateMessageSendStatus(
        localId, serverId, MessageSendStatus.sent.index,
        fileUrl: remoteFileUrl);
  }

  /// Пометить сообщение как failed
  Future<void> markMessageFailed(String localId) async {
    await _db.updateMessageStatus(localId, MessageSendStatus.failed.index);
  }

  /// Повторить отправку failed-сообщения
  Future<void> retryFailedMessage(String localId) async {
    final msg = await _db.getMessageByLocalId(localId);
    if (msg == null || msg.sendStatus != MessageSendStatus.failed.index) return;

    await _db.updateMessageStatus(localId, MessageSendStatus.sending.index);

    try {
      String? remoteFileUrl = msg.fileUrl;
      Map<String, dynamic>? mediaPayload;
      List<int>? waveform;
      int? duration;

      if (msg.linkPreviewOptions != null && msg.linkPreviewOptions!.isNotEmpty) {
        try {
          final decoded = jsonDecode(msg.linkPreviewOptions!);
          if (decoded is Map<String, dynamic>) {
            if (decoded['waveform'] is List) {
              waveform = (decoded['waveform'] as List).map((e) => (e as num).toInt()).toList();
            }
            if (decoded['duration'] is num) {
              duration = (decoded['duration'] as num).toInt();
            }
            if (decoded.containsKey('thumb_url') || decoded.containsKey('thumb_base64')) {
              mediaPayload = decoded;
            }
          }
        } catch (_) {}
      }

      File? uploadedLocalFile;
      if (remoteFileUrl != null &&
          remoteFileUrl.isNotEmpty &&
          !remoteFileUrl.startsWith('http://') &&
          !remoteFileUrl.startsWith('https://') &&
          !remoteFileUrl.startsWith('/api/')) {
        final localPath = remoteFileUrl.startsWith('file://')
            ? Uri.parse(remoteFileUrl).toFilePath()
            : remoteFileUrl;
        final localFile = File(localPath);
        final fileService = FileService();
        final uploadResult = (msg.messageType == 'voice' || msg.messageType == 'audio')
            ? await fileService.uploadFile(localFile)
            : await fileService.uploadFileChunked(localFile);

        uploadedLocalFile = localFile;
        remoteFileUrl = uploadResult.url;
        mediaPayload = uploadResult.toMediaPayload();
        if ((duration == null || duration <= 0) && uploadResult.duration > 0) {
          duration = uploadResult.duration;
        }
      }

      final result = await ChatService.sendMessage(
        chatId: msg.chatId,
        content: msg.content,
        messageType: msg.messageType,
        localId: msg.localId,
        fileUrl: remoteFileUrl,
        fileName: msg.fileName,
        replyToMessageId: msg.replyToMessageId,
        isQuote: msg.isQuote,
        quoteText: msg.quoteText,
        quoteOffset: msg.quoteOffset,
        quoteLength: msg.quoteLength,
        invertMedia: msg.invertMedia,
        isRound: msg.isRound,
        waveform: waveform,
        duration: duration,
        mediaPayload: mediaPayload,
      );

      if (result['success'] == true) {
        if (!kIsWeb &&
            uploadedLocalFile != null &&
            remoteFileUrl != null &&
            remoteFileUrl.isNotEmpty) {
          await MediaCacheManager.instance
              .seedCacheFromFile(remoteFileUrl, uploadedLocalFile);
        }
        final sentMessage = result['message'];
        final serverId = sentMessage is Message ? sentMessage.id : null;
        if (serverId != null && serverId.isNotEmpty) {
          await confirmMessageSent(localId, serverId, remoteFileUrl: remoteFileUrl);
        }
      } else {
        await markMessageFailed(localId);
      }
    } catch (e) {
      debugPrint('SyncService: Retry failed: $e');
      await markMessageFailed(localId);
    }
  }
}
