import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:drift/drift.dart' show Value;
import 'package:uuid/uuid.dart';
import 'auth_service.dart';
import 'avatar_sync_service.dart';
import 'chat_service.dart';
import 'file_service.dart';
import 'media_cache_manager.dart';
import 'websocket_service.dart';
import 'database/app_database.dart';

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

      final events = result['events'] as List<dynamic>? ?? [];
      final maxUsn = result['max_usn'] as int? ?? lastUsn;
      final hasMore = result['has_more'] as bool? ?? false;

      for (final event in events) {
        await _applyEvent(event as Map<String, dynamic>);
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
    final chatId = event['chat_id']?.toString();

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
      case 'message_pinned':
      case 'pin_message':
        final pinChatId = payload['chat_id']?.toString() ?? chatId;
        final rawPinId = payload['pinned_message_id'] ?? payload['message_id'];
        final pinId = rawPinId is num
            ? rawPinId.toInt()
            : int.tryParse(rawPinId?.toString() ?? '');
        if (pinChatId != null) {
          await _db.updateChatPinnedMessageId(pinChatId, pinId);
        }
        break;
      case 'message_unpinned':
      case 'unpin_message':
        final unpinChatId = payload['chat_id']?.toString() ?? chatId;
        final rawNextPinId = payload['pinned_message_id'];
        final nextPinId = rawNextPinId is num
            ? rawNextPinId.toInt()
            : int.tryParse(rawNextPinId?.toString() ?? '');
        if (unpinChatId != null) {
          await _db.updateChatPinnedMessageId(unpinChatId, nextPinId);
        }
        break;
      case 'new_chat':
        await _applyNewChat(payload);
        break;
      case 'chat_update':
        await _applyChatUpdate(payload);
        break;
      case 'delete_chat':
        if (chatId != null) {
          await _db.deleteChat(chatId);
          await _db.deleteMessagesForChat(chatId);
        }
        break;
      default:
        debugPrint('SyncService: Unknown event type: $eventType');
    }
  }

  Future<void> _applyNewMessage(Map<String, dynamic> payload) async {
    final serverId = payload['message_id']?.toString();
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
    final String? mediaPayloadStr =
        mediaPayloadMap.isNotEmpty ? jsonEncode(mediaPayloadMap) : null;

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
          payload['forward_from_id'] != null ||
          (payload['forward_from_name'] != null &&
              payload['forward_from_name'].toString().isNotEmpty)),
      forwardFromId: Value(payload['forward_from_id']?.toString()),
      forwardFromName: Value(payload['forward_from_name']?.toString()),
      entities: Value(entitiesStr),
      linkPreviewOptions: Value(linkPreviewOptionsStr),
      mediaPayload: Value(mediaPayloadStr),
      invertMedia: Value(invertMedia),
      isRound: Value(payload['is_round'] == true ||
          payload['message_type'] == 'round'),
      groupedId: Value(groupedId),
    ));

    // Also update chat's last message if message is newer
    final chat = await _db.getChat(chatId);
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
          incrementUnread: false,
        );
      }
    } else {
      // Upsert chat stub so it immediately appears in the chat list
      await _db.saveChat(ChatsCompanion(
        chatId: Value(chatId),
        chatType: Value(payload['chat_type']?.toString() ?? 'private'),
        name: Value(payload['sender_name']?.toString() ?? 'Чат'),
        avatarUrl: Value(payload['sender_avatar_url']?.toString()),
        lastMessage: Value(content),
        lastMessageTime: Value(safeCreatedAt),
        lastMessageType: Value(messageType),
        lastMessageIsRound: Value(isRound),
        lastMessageFileUrl: Value(payload['file_url']?.toString()),
        lastMessageGroupedId: Value(groupedId),
        otherUserId: Value(payload['sender_id']?.toString()),
        updatedAt: Value(safeCreatedAt),
        unreadCount: const Value(1),
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

    String? mediaPayloadStr;
    if (payload['media_payload'] != null) {
      mediaPayloadStr = payload['media_payload'] is String
          ? payload['media_payload'] as String
          : jsonEncode(payload['media_payload']);
    }

    final isPollUpdate = payload['message_type'] == 'poll';
    await _db.updateMessageContent(
      serverId,
      payload['content']?.toString() ?? '',
      entitiesStr,
      mediaPayloadStr,
      !isPollUpdate,
    );
    final chatId = payload['chat_id']?.toString();
    if (chatId != null) {
      await _db.refreshChatLastMessageFromDb(chatId);
    }
  }

  Future<void> _applyDeleteMessage(Map<String, dynamic> payload) async {
    final serverId = payload['message_id']?.toString();
    if (serverId == null) return;
    await _db.deleteMessage(serverId);
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
    ));
  }

  Future<void> _applyChatUpdate(Map<String, dynamic> payload) async {
    final chatId = payload['chat_id']?.toString();
    if (chatId == null) return;

    final chat = await _db.getChat(chatId);
    if (chat == null) return;

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
      updatedAt: payload.containsKey('updated_at')
          ? Value(payload['updated_at'].toString())
          : Value(chat.updatedAt),
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
