import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../config/app_config.dart';
import 'auth_service.dart';
import 'database/app_database.dart';
import 'notification_service.dart';
import '../utils/date_time_utils.dart';

/// Chat represents a chat conversation.
class Chat {
  final String id;
  final String chatType; // 'private', 'group', 'channel', 'saved', 'system'
  final String name;
  final String? avatarUrl;
  final String? lastMessage;
  final String? lastMessageTime;
  final String? lastMessageType;
  final bool lastMessageIsRound;
  final String? lastMessageFileUrl;
  final String updatedAt;
  final int unreadCount;
  final bool isOnline; // Online status for private chats
  final String? lastSeen; // Last seen time for private chats
  final bool isPinned; // Whether chat is pinned
  final String? otherUserId;
  final String? lastMessageGroupedId;

  Chat({
    required this.id,
    required this.chatType,
    required this.name,
    this.avatarUrl,
    this.lastMessage,
    this.lastMessageTime,
    this.lastMessageType,
    this.lastMessageIsRound = false,
    this.lastMessageFileUrl,
    required this.updatedAt,
    this.unreadCount = 0,
    this.isOnline = false,
    this.lastSeen,
    this.isPinned = false,
    this.otherUserId,
    this.lastMessageGroupedId,
  });

  /// True if the last message in this chat is a round video note («кружочек»)
  bool get isLastMessageRoundVideo =>
      lastMessageIsRound ||
      lastMessageType == 'round' ||
      (lastMessage != null &&
          (lastMessage!.contains('video_note_') ||
              lastMessage == 'Видеосообщение' ||
              lastMessage == 'Video message'));

  factory Chat.fromJson(Map<String, dynamic> json) {
    final msgType = json['last_message_type']?.toString();
    final isRound = json['last_message_is_round'] == true ||
        msgType == 'round' ||
        (json['is_round'] == true);

    return Chat(
      id: json['id']?.toString() ?? json['chat_id']?.toString() ?? '',
      chatType: json['chat_type']?.toString() ?? 'private',
      name: json['name']?.toString() ?? '',
      avatarUrl: json['avatar_url']?.toString(),
      lastMessage: json['last_message']?.toString(),
      lastMessageTime: json['last_message_time']?.toString(),
      lastMessageType: msgType,
      lastMessageIsRound: isRound,
      lastMessageFileUrl: json['last_message_file_url']?.toString() ??
          json['file_url']?.toString(),
      updatedAt: json['updated_at']?.toString() ?? '',
      unreadCount: json['unread_count'] ?? 0,
      isOnline: json['is_online'] ?? false,
      lastSeen: json['last_seen']?.toString(),
      isPinned: json['is_pinned'] ?? false,
      otherUserId: json['other_user_id']?.toString() ?? json['otherUserId']?.toString(),
      lastMessageGroupedId: json['last_message_grouped_id']?.toString(),
    );
  }

  Chat copyWith({
    String? id,
    String? chatType,
    String? name,
    String? avatarUrl,
    String? lastMessage,
    String? lastMessageTime,
    String? lastMessageType,
    bool? lastMessageIsRound,
    String? lastMessageFileUrl,
    String? updatedAt,
    int? unreadCount,
    bool? isOnline,
    String? lastSeen,
    bool? isPinned,
    String? otherUserId,
    String? lastMessageGroupedId,
  }) {
    return Chat(
      id: id ?? this.id,
      chatType: chatType ?? this.chatType,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      lastMessageType: lastMessageType ?? this.lastMessageType,
      lastMessageIsRound: lastMessageIsRound ?? this.lastMessageIsRound,
      lastMessageFileUrl: lastMessageFileUrl ?? this.lastMessageFileUrl,
      updatedAt: updatedAt ?? this.updatedAt,
      unreadCount: unreadCount ?? this.unreadCount,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      isPinned: isPinned ?? this.isPinned,
      otherUserId: otherUserId ?? this.otherUserId,
      lastMessageGroupedId: lastMessageGroupedId ?? this.lastMessageGroupedId,
    );
  }
}

/// ReplyInfo holds cached preview data for the message being replied to.
/// Stored inline with the message for offline-first display without lookup.
class ReplyInfo {
  final String messageId;
  final String senderId;
  final String senderName;
  final String content; // truncated preview text
  final String messageType; // 'text', 'image', etc.
  final String? chatId; // The chat ID where the original message resides
  final String? nameColorPresetId;
  final String? replyStripStyle;

  const ReplyInfo({
    required this.messageId,
    required this.senderId,
    required this.senderName,
    required this.content,
    required this.messageType,
    this.chatId,
    this.nameColorPresetId,
    this.replyStripStyle,
  });

  factory ReplyInfo.fromJson(Map<String, dynamic> json) {
    return ReplyInfo(
      messageId: json['message_id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      senderName: json['sender_name']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      messageType: json['message_type']?.toString() ?? 'text',
      chatId: json['chat_id']?.toString(),
      nameColorPresetId: json['name_color_preset_id']?.toString() ??
          json['reply_to_sender_name_color_id']?.toString(),
      replyStripStyle: json['reply_strip_style']?.toString() ??
          json['reply_to_sender_strip_style']?.toString(),
    );
  }

  Map<String, dynamic> toJson() => {
        'message_id': messageId,
        'sender_id': senderId,
        'sender_name': senderName,
        'content': content,
        'message_type': messageType,
        if (chatId != null) 'chat_id': chatId,
        if (nameColorPresetId != null) 'name_color_preset_id': nameColorPresetId,
        if (replyStripStyle != null) 'reply_strip_style': replyStripStyle,
      };

  ReplyInfo copyWith({
    String? messageId,
    String? senderId,
    String? senderName,
    String? content,
    String? messageType,
    String? chatId,
    String? nameColorPresetId,
    String? replyStripStyle,
  }) {
    return ReplyInfo(
      messageId: messageId ?? this.messageId,
      senderId: senderId ?? this.senderId,
      senderName: senderName ?? this.senderName,
      content: content ?? this.content,
      messageType: messageType ?? this.messageType,
      chatId: chatId ?? this.chatId,
      nameColorPresetId: nameColorPresetId ?? this.nameColorPresetId,
      replyStripStyle: replyStripStyle ?? this.replyStripStyle,
    );
  }
}

/// MessageEntity represents a formatted range in text (Bold, Italic, Spoiler, Code, Link, etc.).
class MessageEntity {
  final String type; // 'bold', 'italic', 'code', 'pre', 'spoiler', 'strikethrough', 'underline', 'link', 'text_link', 'mention', 'blockquote', 'expandable_blockquote'
  final int offset;
  final int length;
  final String? url;
  final String? language; // For 'pre' code blocks
  final bool? collapsed; // For expandable/collapsible blockquotes

  const MessageEntity({
    required this.type,
    required this.offset,
    required this.length,
    this.url,
    this.language,
    this.collapsed,
  });

  factory MessageEntity.fromJson(Map<String, dynamic> json) {
    return MessageEntity(
      type: json['type']?.toString() ?? 'bold',
      offset: (json['offset'] as num?)?.toInt() ?? 0,
      length: (json['length'] as num?)?.toInt() ?? 0,
      url: json['url']?.toString(),
      language: json['language']?.toString(),
      collapsed: json['collapsed'] as bool?,
    );
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        'offset': offset,
        'length': length,
        if (url != null) 'url': url,
        if (language != null) 'language': language,
        if (collapsed != null) 'collapsed': collapsed,
      };

  MessageEntity copyWith({
    String? type,
    int? offset,
    int? length,
    String? url,
    String? language,
    bool? collapsed,
  }) {
    return MessageEntity(
      type: type ?? this.type,
      offset: offset ?? this.offset,
      length: length ?? this.length,
      url: url ?? this.url,
      language: language ?? this.language,
      collapsed: collapsed ?? this.collapsed,
    );
  }
}

/// LinkPreviewOptions controls the presentation of link preview in messages.
class LinkPreviewOptions {
  final bool isDisabled;
  final String? url;
  final bool preferSmallMedia;
  final bool preferLargeMedia;
  final bool showAboveText;

  const LinkPreviewOptions({
    this.isDisabled = false,
    this.url,
    this.preferSmallMedia = false,
    this.preferLargeMedia = false,
    this.showAboveText = false,
  });

  factory LinkPreviewOptions.fromJson(Map<String, dynamic> json) {
    final rawDisabled = json['is_disabled'];
    final bool isDisabled = rawDisabled == true || rawDisabled == 1 || rawDisabled == 'true';
    final rawSmall = json['prefer_small_media'];
    final bool preferSmall = rawSmall == true || rawSmall == 1 || rawSmall == 'true';
    final rawLarge = json['prefer_large_media'];
    final bool preferLarge = rawLarge == true || rawLarge == 1 || rawLarge == 'true';
    final rawAbove = json['show_above_text'];
    final bool showAbove = rawAbove == true || rawAbove == 1 || rawAbove == 'true';

    return LinkPreviewOptions(
      isDisabled: isDisabled,
      url: json['url']?.toString(),
      preferSmallMedia: preferSmall,
      preferLargeMedia: preferLarge,
      showAboveText: showAbove,
    );
  }

  Map<String, dynamic> toJson() => {
        'is_disabled': isDisabled,
        if (url != null) 'url': url,
        'prefer_small_media': preferSmallMedia,
        'prefer_large_media': preferLargeMedia,
        'show_above_text': showAboveText,
      };

  LinkPreviewOptions copyWith({
    bool? isDisabled,
    String? url,
    bool? preferSmallMedia,
    bool? preferLargeMedia,
    bool? showAboveText,
  }) {
    return LinkPreviewOptions(
      isDisabled: isDisabled ?? this.isDisabled,
      url: url ?? this.url,
      preferSmallMedia: preferSmallMedia ?? this.preferSmallMedia,
      preferLargeMedia: preferLargeMedia ?? this.preferLargeMedia,
      showAboveText: showAboveText ?? this.showAboveText,
    );
  }
}

/// Message represents a message in a chat.
class Message {
  final String id; // serverId или localId если pending
  final String chatId;
  final String senderId;
  final String content;
  final String messageType;
  final bool isEdited;
  final String createdAt;
  final String senderName;
  final String? senderAvatarUrl;
  final String? fileUrl;
  final String? fileName;
  final String? replyToMessageId;
  final bool isRead;
  final String? readAt;

  // Reply / Quote fields
  final bool isQuote; // true = quote (partial text), false = full reply
  final String? quoteText; // выделенный текст цитаты
  final int quoteOffset; // смещение начала цитаты в оригинальном сообщении
  final int quoteLength; // длина цитируемого фрагмента

  // Cached reply preview (for offline-first display without lookup)
  final ReplyInfo? replyInfo;

  final String? localId; // UUID для pending-сообщений
  final int sendStatus; // 0=sending, 1=sent, 2=failed (MessageSendStatus)

  final String? senderNameColorId;
  final String? senderReplyStripStyle;

  // Forwarding fields
  final bool isForward;
  final String? forwardFromId;
  final String? forwardFromName;

  // Album grouping and text formatting entities
  final String? groupedId;
  final List<MessageEntity> entities;
  final LinkPreviewOptions? linkPreviewOptions;
  final bool invertMedia;

  // Reactions
  final Map<String, int> reactions; // emoji -> count
  final Set<String> myReactions; // emojis selected by current user

  // Round video note flag
  final bool isRound;

  // Voice message waveform and duration
  final List<int>? waveform;
  final int? duration;

  // Media album & message extra payload (dimensions, thumb_base64, file_size, etc.)
  final Map<String, dynamic>? mediaPayload;

  Message({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.content,
    required this.messageType,
    required this.isEdited,
    required this.createdAt,
    required this.senderName,
    this.senderAvatarUrl,
    this.fileUrl,
    this.fileName,
    this.replyToMessageId,
    this.isRead = false,
    this.readAt,
    this.isQuote = false,
    this.quoteText,
    this.quoteOffset = 0,
    this.quoteLength = 0,
    this.replyInfo,
    this.localId,
    this.sendStatus = 1, // по умолчанию sent
    this.senderNameColorId,
    this.senderReplyStripStyle,
    this.isForward = false,
    this.forwardFromId,
    this.forwardFromName,
    this.groupedId,
    this.entities = const [],
    this.linkPreviewOptions,
    this.invertMedia = false,
    this.reactions = const {},
    this.myReactions = const {},
    this.isRound = false,
    this.waveform,
    this.duration,
    this.mediaPayload,
  });

  /// Whether this message has a reply or quote
  bool get hasReply => replyToMessageId != null && replyToMessageId!.isNotEmpty;

  String? get thumbBase64 => mediaPayload?['thumb_base64'] as String?;
  String? get thumbUrl => mediaPayload?['thumb_url'] as String? ?? mediaPayload?['thumbnail_url'] as String?;
  int? get mediaWidth => (mediaPayload?['width'] as num?)?.toInt();
  int? get mediaHeight => (mediaPayload?['height'] as num?)?.toInt();
  int? get mediaDuration => (mediaPayload?['duration'] as num?)?.toInt();
  int? get mediaFileSize => (mediaPayload?['file_size'] as num?)?.toInt();

  factory Message.fromJson(Map<String, dynamic> json) {
    // Parse replyInfo from nested object or flat fields
    ReplyInfo? replyInfo;
    if (json['reply_info'] != null && json['reply_info'] is Map) {
      replyInfo =
          ReplyInfo.fromJson(json['reply_info'] as Map<String, dynamic>);
    } else if (json['reply_to_message_id'] != null) {
      // Fallback: build ReplyInfo from flat fields
      replyInfo = ReplyInfo(
        messageId: json['reply_to_message_id']?.toString() ?? '',
        senderId: json['reply_to_sender_id']?.toString() ?? '',
        senderName: json['reply_to_sender_name']?.toString() ?? '',
        content: json['reply_to_content']?.toString() ?? '',
        messageType: json['reply_to_message_type']?.toString() ?? 'text',
        nameColorPresetId: json['reply_to_sender_name_color_id']?.toString() ??
            json['reply_to_name_color_preset_id']?.toString(),
        replyStripStyle: json['reply_to_sender_strip_style']?.toString() ??
            json['reply_to_strip_style']?.toString(),
      );
    }

    final Map<String, int> parsedReactions = {};
    final Set<String> parsedMyReactions = {};
    if (json['reactions'] is List) {
      for (final item in json['reactions']) {
        if (item is Map) {
          final emoji = item['emoji']?.toString() ?? '';
          final count = (item['count'] as num?)?.toInt() ?? 0;
          if (emoji.isNotEmpty && count > 0) {
            parsedReactions[emoji] = count;
          }
          if (item['is_mine'] == true && emoji.isNotEmpty) {
            parsedMyReactions.add(emoji);
          }
        }
      }
    } else if (json['reactions'] is Map) {
      (json['reactions'] as Map).forEach((k, v) {
        final emoji = k.toString();
        final count = (v as num?)?.toInt() ?? 0;
        if (emoji.isNotEmpty && count > 0) {
          parsedReactions[emoji] = count;
        }
      });
      if (json['my_reactions'] is List) {
        for (final e in json['my_reactions']) {
          if (e != null && e.toString().isNotEmpty) {
            parsedMyReactions.add(e.toString());
          }
        }
      } else if (json['my_reaction'] != null) {
        parsedMyReactions.add(json['my_reaction'].toString());
      }
    }

    List<int>? waveform;
    if (json['waveform'] is List) {
      waveform = (json['waveform'] as List).map((e) => (e as num).toInt()).toList();
    } else if (json['media_payload'] is Map && json['media_payload']['waveform'] is List) {
      waveform = (json['media_payload']['waveform'] as List).map((e) => (e as num).toInt()).toList();
    }

    int? duration;
    if (json['duration'] is num) {
      duration = (json['duration'] as num).toInt();
    } else if (json['media_payload'] is Map && json['media_payload']['duration'] is num) {
      duration = (json['media_payload']['duration'] as num).toInt();
    }

    return Message(
      id: json['id']?.toString() ?? '',
      chatId: json['chat_id']?.toString() ?? '',
      senderId: json['sender_id']?.toString() ?? '',
      content: json['content']?.toString() ?? '',
      messageType: json['message_type']?.toString() ?? 'text',
      isEdited: json['is_edited'] ?? false,
      createdAt: json['created_at']?.toString() ?? '',
      senderName: json['sender_name']?.toString() ?? 'Unknown',
      senderAvatarUrl: json['sender_avatar_url']?.toString(),
      fileUrl: json['file_url']?.toString(),
      fileName: json['file_name']?.toString(),
      replyToMessageId: json['reply_to_message_id']?.toString(),
      isRead: json['is_read'] ?? false,
      readAt: json['read_at']?.toString(),
      isQuote: json['is_quote'] ?? false,
      quoteText: json['quote_text']?.toString(),
      quoteOffset: (json['quote_offset'] as num?)?.toInt() ?? 0,
      quoteLength: (json['quote_length'] as num?)?.toInt() ?? 0,
      replyInfo: replyInfo,
      localId: json['local_id']?.toString(),
      sendStatus: (json['send_status'] as num?)?.toInt() ?? 1,
      senderNameColorId: json['sender_name_color_id']?.toString(),
      senderReplyStripStyle: json['sender_reply_strip_style']?.toString(),
      isForward: json['is_forward'] ?? false,
      forwardFromId: json['forward_from_id']?.toString(),
      forwardFromName: json['forward_from_name']?.toString(),
      groupedId: json['grouped_id']?.toString(),
      entities: () {
        final raw = json['entities'];
        if (raw is List) {
          return raw
              .whereType<Map>()
              .map((e) => MessageEntity.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        } else if (raw is String && raw.isNotEmpty && raw != 'null') {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is List) {
              return decoded
                  .whereType<Map>()
                  .map((e) => MessageEntity.fromJson(Map<String, dynamic>.from(e)))
                  .toList();
            }
          } catch (_) {}
        }
        return const <MessageEntity>[];
      }(),
      linkPreviewOptions: () {
        final raw = json['link_preview_options'];
        if (raw == null) return null;
        if (raw is Map) {
          try {
            return LinkPreviewOptions.fromJson(Map<String, dynamic>.from(raw));
          } catch (_) {
            return null;
          }
        }
        if (raw is String && raw.isNotEmpty && raw != 'null' && raw != '{}') {
          try {
            final decoded = jsonDecode(raw);
            if (decoded is Map) {
              return LinkPreviewOptions.fromJson(Map<String, dynamic>.from(decoded));
            }
          } catch (_) {}
        }
        return null;
      }(),
      invertMedia: json['invert_media'] == true ||
          json['invert_media'] == 1 ||
          json['invert_media'] == 'true',
      reactions: parsedReactions,
      myReactions: parsedMyReactions,
      isRound: json['is_round'] == true || json['message_type'] == 'round',
      waveform: waveform,
      duration: duration,
      mediaPayload: json['media_payload'] is Map
          ? Map<String, dynamic>.from(json['media_payload'] as Map)
          : (json['media_payload'] is String && (json['media_payload'] as String).isNotEmpty
              ? (() {
                  try {
                    final decoded = jsonDecode(json['media_payload'] as String);
                    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
                  } catch (_) {
                    return null;
                  }
                })()
              : null),
    );
  }

  /// Создать Message из Drift DbMessage
  factory Message.fromDbMessage(DbMessage model) {
    // Build ReplyInfo from cached fields
    ReplyInfo? replyInfo;
    if (model.replyToMessageId != null) {
      replyInfo = ReplyInfo(
        messageId: model.replyToMessageId!,
        senderId: model.replyToSenderId ?? '',
        senderName: model.replyToSenderName ?? '',
        content: model.replyToContent ?? '',
        messageType: model.replyToMessageType,
      );
    }

    List<MessageEntity> parsedEntities = [];
    if (model.entities != null && model.entities!.isNotEmpty) {
      try {
        final decoded = jsonDecode(model.entities!) as List;
        parsedEntities = decoded
            .map((e) => MessageEntity.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (_) {}
    }

    final Map<String, int> dbReactions = {};
    final Set<String> dbMyReactions = {};
    if (model.reactions != null && model.reactions!.isNotEmpty) {
      try {
        final decoded = jsonDecode(model.reactions!);
        if (decoded is Map) {
          if (decoded['reactions'] is Map) {
            (decoded['reactions'] as Map).forEach((k, v) {
              final emoji = k.toString();
              final count = (v as num?)?.toInt() ?? 0;
              if (emoji.isNotEmpty && count > 0) {
                dbReactions[emoji] = count;
              }
            });
          }
          if (decoded['my_reactions'] is List) {
            for (final e in decoded['my_reactions']) {
              if (e != null && e.toString().isNotEmpty) {
                dbMyReactions.add(e.toString());
              }
            }
          }
        }
      } catch (_) {}
    }

    LinkPreviewOptions? parsedLinkPreviewOptions;
    if (model.linkPreviewOptions != null &&
        model.linkPreviewOptions!.isNotEmpty) {
      try {
        final decoded = jsonDecode(model.linkPreviewOptions!);
        if (decoded is Map<String, dynamic>) {
          parsedLinkPreviewOptions = LinkPreviewOptions.fromJson(decoded);
        }
      } catch (_) {}
    }

    Map<String, dynamic>? dbMediaPayload;
    List<int>? dbWaveform;
    int? dbDuration;
    // Prefer dedicated mediaPayload column, fall back to linkPreviewOptions for legacy data
    final rawMediaPayload = (model.mediaPayload != null && model.mediaPayload!.isNotEmpty)
        ? model.mediaPayload
        : (model.messageType == 'voice' ? model.linkPreviewOptions : null);

    if (rawMediaPayload != null && rawMediaPayload.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawMediaPayload);
        if (decoded is Map<String, dynamic>) {
          dbMediaPayload = decoded;
        } else if (decoded is Map) {
          dbMediaPayload = Map<String, dynamic>.from(decoded);
        }
        if (dbMediaPayload != null) {
          if (dbMediaPayload['waveform'] is List) {
            dbWaveform = (dbMediaPayload['waveform'] as List)
                .map((e) => (e as num).toInt())
                .toList();
          }
          if (dbMediaPayload['duration'] is num) {
            dbDuration = (dbMediaPayload['duration'] as num).toInt();
          }
        }
      } catch (_) {}
    }

    return Message(
      id: model.serverId ?? model.localId,
      chatId: model.chatId,
      senderId: model.senderId,
      content: model.content,
      messageType: model.messageType,
      isEdited: model.isEdited,
      createdAt: model.createdAt,
      senderName: model.senderName ?? '',
      senderAvatarUrl: model.senderAvatarUrl,
      fileUrl: model.fileUrl,
      fileName: model.fileName,
      replyToMessageId: model.replyToMessageId,
      isRead: model.isRead,
      isQuote: model.isQuote,
      quoteText: model.quoteText,
      quoteOffset: model.quoteOffset,
      quoteLength: model.quoteLength,
      replyInfo: replyInfo,
      localId: model.localId,
      sendStatus: model.sendStatus,
      isForward: model.isForward,
      forwardFromId: model.forwardFromId,
      forwardFromName: model.forwardFromName,
      groupedId: model.groupedId,
      entities: parsedEntities,
      linkPreviewOptions: parsedLinkPreviewOptions,
      invertMedia: model.invertMedia,
      reactions: dbReactions,
      myReactions: dbMyReactions,
      isRound: model.isRound,
      waveform: dbWaveform,
      duration: dbDuration,
      mediaPayload: dbMediaPayload,
    );
  }

  /// Copy with method for updating message state
  Message copyWith({
    String? id,
    String? chatId,
    String? senderId,
    String? content,
    String? messageType,
    bool? isEdited,
    String? createdAt,
    String? senderName,
    String? senderAvatarUrl,
    String? fileUrl,
    String? fileName,
    String? replyToMessageId,
    bool? isRead,
    String? readAt,
    bool? isQuote,
    String? quoteText,
    int? quoteOffset,
    int? quoteLength,
    ReplyInfo? replyInfo,
    String? localId,
    int? sendStatus,
    String? senderNameColorId,
    String? senderReplyStripStyle,
    bool? isForward,
    String? forwardFromId,
    String? forwardFromName,
    String? groupedId,
    List<MessageEntity>? entities,
    LinkPreviewOptions? linkPreviewOptions,
    bool? invertMedia,
    Map<String, int>? reactions,
    Set<String>? myReactions,
    bool? isRound,
    List<int>? waveform,
    int? duration,
    Map<String, dynamic>? mediaPayload,
  }) {
    return Message(
      id: id ?? this.id,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      messageType: messageType ?? this.messageType,
      isEdited: isEdited ?? this.isEdited,
      createdAt: createdAt ?? this.createdAt,
      senderName: senderName ?? this.senderName,
      senderAvatarUrl: senderAvatarUrl ?? this.senderAvatarUrl,
      fileUrl: fileUrl ?? this.fileUrl,
      fileName: fileName ?? this.fileName,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      isRead: isRead ?? this.isRead,
      readAt: readAt ?? this.readAt,
      isQuote: isQuote ?? this.isQuote,
      quoteText: quoteText ?? this.quoteText,
      quoteOffset: quoteOffset ?? this.quoteOffset,
      quoteLength: quoteLength ?? this.quoteLength,
      replyInfo: replyInfo ?? this.replyInfo,
      localId: localId ?? this.localId,
      sendStatus: sendStatus ?? this.sendStatus,
      senderNameColorId: senderNameColorId ?? this.senderNameColorId,
      senderReplyStripStyle: senderReplyStripStyle ?? this.senderReplyStripStyle,
      isForward: isForward ?? this.isForward,
      forwardFromId: forwardFromId ?? this.forwardFromId,
      forwardFromName: forwardFromName ?? this.forwardFromName,
      groupedId: groupedId ?? this.groupedId,
      entities: entities ?? this.entities,
      linkPreviewOptions: linkPreviewOptions ?? this.linkPreviewOptions,
      invertMedia: invertMedia ?? this.invertMedia,
      reactions: reactions ?? this.reactions,
      myReactions: myReactions ?? this.myReactions,
      isRound: isRound ?? this.isRound,
      waveform: waveform ?? this.waveform,
      duration: duration ?? this.duration,
      mediaPayload: mediaPayload ?? this.mediaPayload,
    );
  }
}

/// ChatDetails represents detailed information about a chat.
class ChatDetails {
  final String id;
  final String chatType;
  final String name;
  final String? avatarUrl;
  final String createdBy;
  final String createdAt;
  final String updatedAt;
  final List<ChatParticipant> participants;

  ChatDetails({
    required this.id,
    required this.chatType,
    required this.name,
    this.avatarUrl,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    required this.participants,
  });

  factory ChatDetails.fromJson(Map<String, dynamic> json) {
    var participantsList = <ChatParticipant>[];
    if (json['participants'] != null && json['participants'] is List) {
      for (var p in json['participants']) {
        participantsList.add(ChatParticipant.fromJson(p));
      }
    }
    return ChatDetails(
      id: json['id']?.toString() ?? '',
      chatType: json['chat_type']?.toString() ?? 'private',
      name: json['name']?.toString() ?? '',
      avatarUrl: json['avatar_url']?.toString(),
      createdBy: json['created_by']?.toString() ?? '',
      createdAt: json['created_at']?.toString() ?? '',
      updatedAt: json['updated_at']?.toString() ?? '',
      participants: participantsList,
    );
  }
}

/// ChatParticipant represents a participant in a chat.
class ChatParticipant {
  final String id;
  final String username;
  final String displayName;
  final String? avatarUrl;
  final String role;
  final bool isOnline;
  final DateTime? lastSeen;

  ChatParticipant({
    required this.id,
    required this.username,
    required this.displayName,
    this.avatarUrl,
    required this.role,
    this.isOnline = false,
    this.lastSeen,
  });

  ChatParticipant copyWith({
    String? id,
    String? username,
    String? displayName,
    String? avatarUrl,
    String? role,
    bool? isOnline,
    DateTime? lastSeen,
  }) {
    return ChatParticipant(
      id: id ?? this.id,
      username: username ?? this.username,
      displayName: displayName ?? this.displayName,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
    );
  }

  factory ChatParticipant.fromJson(Map<String, dynamic> json) {
    return ChatParticipant(
      id: json['id']?.toString() ?? '',
      username: json['username']?.toString() ?? '',
      displayName: json['display_name']?.toString() ?? '',
      avatarUrl: json['avatar_url']?.toString(),
      role: json['role']?.toString() ?? 'member',
      isOnline: json['is_online'] == true,
      lastSeen: DateTimeUtils.parseUtcDateTime(json['last_seen']),
    );
  }
}

/// ChatService handles all chat-related API operations.
class ChatService {
  /// Creates a new chat.
  ///
  /// [chatType] - Type of chat: 'private', 'group', or 'channel'
  /// [name] - Name for group/channel (optional for private)
  /// [participantIds] - List of user IDs to add as participants
  static Future<Map<String, dynamic>> createChat({
    required String chatType,
    String? name,
    required List<String> participantIds,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({
          'chat_type': chatType,
          'name': name,
          'participant_ids': participantIds,
        }),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'chat': Chat.fromJson(data['chat']),
          'message': data['message'] ?? 'Chat created successfully',
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to create chat',
        };
      }
    } catch (e) {
      debugPrint('Create chat error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Gets the list of chats for the current user.
  static Future<Map<String, dynamic>> getChats() async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {
          'success': false,
          'message': 'Not authenticated',
          'chats': <Chat>[]
        };
      }

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        List<Chat> chats = [];
        if (data['chats'] != null && data['chats'] is List) {
          for (var chat in data['chats']) {
            chats.add(Chat.fromJson(chat));
          }
        }
        return {'success': true, 'chats': chats};
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to get chats',
          'chats': <Chat>[],
        };
      }
    } catch (e) {
      debugPrint('Get chats error: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
        'chats': <Chat>[]
      };
    }
  }

  /// Gets detailed information about a specific chat.
  static Future<Map<String, dynamic>> getChat(String chatId) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'chat': ChatDetails.fromJson(data['chat']),
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to get chat',
        };
      }
    } catch (e) {
      debugPrint('Get chat error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Gets messages for a specific chat.
  ///
  /// [chatId] - The ID of the chat
  /// [limit] - Maximum number of messages to return (default: 50)
  /// [offset] - Number of messages to skip (for pagination, legacy)
  /// [beforeMessageId] - Cursor-based pagination: load messages older than this ID
  static Future<Map<String, dynamic>> getMessages({
    required String chatId,
    int limit = 50,
    int offset = 0,
    String? beforeMessageId,
    String? beforeCreatedAt,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {
          'success': false,
          'message': 'Not authenticated',
          'messages': <Message>[]
        };
      }

      var url = '${AppConfig.baseUrl}/api/chats/$chatId/messages?limit=$limit';
      if (beforeMessageId != null && beforeMessageId.isNotEmpty) {
        url += '&before_message_id=$beforeMessageId';
      }
      if (beforeCreatedAt != null && beforeCreatedAt.isNotEmpty) {
        url += '&before_created_at=${Uri.encodeComponent(beforeCreatedAt)}';
      } else if (beforeMessageId == null && offset > 0) {
        url += '&offset=$offset';
      }

      final response = await http.get(
        Uri.parse(url),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        List<Message> messages = [];
        if (data['messages'] != null && data['messages'] is List) {
          for (var msg in data['messages']) {
            messages.add(Message.fromJson(msg));
          }
        }
        return {
          'success': true,
          'messages': messages,
          'has_more': data['has_more'] ?? (messages.length >= limit),
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to get messages',
          'messages': <Message>[],
        };
      }
    } catch (e) {
      debugPrint('Get messages error: $e');
      return {
        'success': false,
        'message': 'Network error: ${e.toString()}',
        'messages': <Message>[]
      };
    }
  }

  /// Delta Sync: получить обновления с сервера после указанного USN
  ///
  /// [sinceUsn] - Last known Update Sequence Number
  /// [limit] - Maximum number of events to return (default: 100)
  static Future<Map<String, dynamic>> getUpdates({
    required int sinceUsn,
    int limit = 100,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.get(
        Uri.parse(
            '${AppConfig.baseUrl}/api/updates?since_usn=$sinceUsn&limit=$limit'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'events': data['events'] ?? [],
          'max_usn': data['max_usn'] ?? sinceUsn,
          'has_more': data['has_more'] ?? false,
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to get updates',
        };
      }
    } catch (e) {
      debugPrint('Get updates error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Sends a message to a chat.
  ///
  /// [chatId] - The ID of the chat
  /// [content] - The message content
  /// [messageType] - Type of message: 'text', 'image', 'video', 'file', 'audio', etc.
  /// [fileUrl] - URL of the file (for media messages)
  /// [fileName] - Name of the file (for file messages)
  /// [replyToMessageId] - ID of the message being replied to (optional)
  /// [localId] - Local message ID for offline-first tracking (optional)
  /// [isQuote] - Whether this is a quote (partial text) reply (optional)
  /// [quoteText] - The quoted text fragment (optional)
  /// [quoteOffset] - Offset of the quote in the original message (optional)
  /// [quoteLength] - Length of the quoted fragment (optional)
  static Future<Map<String, dynamic>> sendMessage({
    required String chatId,
    required String content,
    String messageType = 'text',
    String? fileUrl,
    String? fileName,
    String? replyToMessageId,
    String? localId,
    bool isQuote = false,
    String? quoteText,
    int quoteOffset = 0,
    int quoteLength = 0,
    List<MessageEntity>? entities,
    LinkPreviewOptions? linkPreviewOptions,
    bool invertMedia = false,
    bool isRound = false,
    List<int>? waveform,
    int? duration,
    String? groupedId,
    Map<String, dynamic>? mediaPayload,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      String effectiveMessageType = messageType;
      bool effectiveIsRound = isRound;
      if (effectiveMessageType == 'round') {
        effectiveMessageType = 'video';
        effectiveIsRound = true;
      }

      final body = <String, dynamic>{
        'content': content,
        'message_type': effectiveMessageType,
      };
      if (fileUrl != null) body['file_url'] = fileUrl;
      if (fileName != null) body['file_name'] = fileName;
      if (effectiveIsRound) body['is_round'] = true;
      if (waveform != null && waveform.isNotEmpty) body['waveform'] = waveform;
      if (duration != null && duration > 0) body['duration'] = duration;
      if (groupedId != null && groupedId.isNotEmpty) body['grouped_id'] = groupedId;
      if (mediaPayload != null && mediaPayload.isNotEmpty) body['media_payload'] = mediaPayload;
      if (replyToMessageId != null) {
        body['reply_to_message_id'] = replyToMessageId;
        if (isQuote) {
          body['is_quote'] = true;
          if (quoteText != null) body['quote_text'] = quoteText;
          if (quoteOffset > 0) body['quote_offset'] = quoteOffset;
          if (quoteLength > 0) body['quote_length'] = quoteLength;
        }
      }
      if (localId != null) body['local_id'] = localId;
      if (entities != null && entities.isNotEmpty) {
        body['entities'] = entities.map((e) => e.toJson()).toList();
      }
      if (linkPreviewOptions != null) {
        body['link_preview_options'] = linkPreviewOptions.toJson();
      }
      if (invertMedia) {
        body['invert_media'] = true;
      }

      if (AppConfig.enableDebugLogging) {
        debugPrint(
            'SendMessage: POST ${AppConfig.baseUrl}/api/chats/$chatId/messages');
        debugPrint('SendMessage: body = $body');
      }

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/messages'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      if (AppConfig.enableDebugLogging) {
        debugPrint(
            'SendMessage: Response ${response.statusCode}: ${response.body}');
      }

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        Message parsedMessage;
        try {
          final rawMsg = data['message'];
          if (rawMsg is Map) {
            parsedMessage = Message.fromJson(Map<String, dynamic>.from(rawMsg));
          } else {
            throw const FormatException('Expected map for message');
          }
        } catch (parseError) {
          debugPrint('Error parsing sent message: $parseError');
          final rawMsg = data['message'] is Map ? (data['message'] as Map) : {};
          parsedMessage = Message(
            id: rawMsg['id']?.toString() ?? localId ?? '',
            chatId: chatId,
            senderId: rawMsg['sender_id']?.toString() ?? '',
            content: rawMsg['content']?.toString() ?? content,
            messageType: rawMsg['message_type']?.toString() ?? effectiveMessageType,
            isEdited: rawMsg['is_edited'] == true,
            createdAt: rawMsg['created_at']?.toString() ?? DateTime.now().toIso8601String(),
            senderName: rawMsg['sender_name']?.toString() ?? 'You',
            fileUrl: rawMsg['file_url']?.toString() ?? fileUrl,
            fileName: rawMsg['file_name']?.toString() ?? fileName,
            localId: localId,
            sendStatus: 1,
            groupedId: rawMsg['grouped_id']?.toString() ?? groupedId,
          );
        }
        return {
          'success': true,
          'message': parsedMessage,
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to send message',
        };
      }
    } catch (e) {
      debugPrint('Send message error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Отправить медиа-альбом (2-10 фото/видео) с общим grouped_id
  static Future<Map<String, dynamic>> sendMediaAlbum({
    required String chatId,
    required List<Map<String, dynamic>> items,
    String? groupedId,
    String? caption,
    List<MessageEntity>? entities,
    bool invertMedia = false,
    String? replyToMessageId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final body = <String, dynamic>{
        'items': items,
      };
      if (groupedId != null && groupedId.isNotEmpty) {
        body['grouped_id'] = groupedId;
      }
      if (caption != null && caption.isNotEmpty) {
        body['caption'] = caption;
      }
      if (entities != null && entities.isNotEmpty) {
        body['entities'] = entities.map((e) => e.toJson()).toList();
      }
      if (invertMedia) {
        body['invert_media'] = true;
      }
      if (replyToMessageId != null && replyToMessageId.isNotEmpty) {
        body['reply_to_message_id'] = replyToMessageId;
      }

      if (AppConfig.enableDebugLogging) {
        debugPrint(
            'SendMediaAlbum: POST ${AppConfig.baseUrl}/api/chats/$chatId/messages/album');
        debugPrint('SendMediaAlbum: body = $body');
      }

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/messages/album'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      if (AppConfig.enableDebugLogging) {
        debugPrint(
            'SendMediaAlbum: Response ${response.statusCode}: ${response.body}');
      }

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        final rawMessages = data['messages'] as List<dynamic>? ?? [];
        final parsedMessages = <Message>[];
        for (final m in rawMessages) {
          try {
            if (m is Map) {
              parsedMessages.add(Message.fromJson(Map<String, dynamic>.from(m)));
            }
          } catch (e) {
            debugPrint('Failed to parse album message: $e');
          }
        }
        return {
          'success': true,
          'grouped_id': data['grouped_id'],
          'messages': parsedMessages,
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to send media album',
        };
      }
    } catch (e) {
      debugPrint('Send media album error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Marks all messages in a chat as read.
  ///
  /// [chatId] - The ID of the chat
  static Future<Map<String, dynamic>> markMessagesAsRead({
    required String chatId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/messages/read'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        NotificationService().cancelChatNotifications(chatId);
        return {
          'success': true,
          'marked_count': data['marked_count'] ?? 0,
          'unread_count': data['unread_count'] ?? 0,
          'message': data['message'] ?? 'Messages marked as read',
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to mark messages as read',
        };
      }
    } catch (e) {
      debugPrint('Mark messages as read error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Edits a message in a chat.
  ///
  /// [chatId] - The ID of the chat containing the message
  /// [messageId] - The ID of the message to edit
  /// [content] - The new content for the message
  static Future<Map<String, dynamic>> editMessage({
    required String chatId,
    required String messageId,
    required String content,
    List<MessageEntity>? entities,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final body = <String, dynamic>{
        'content': content,
      };
      if (entities != null && entities.isNotEmpty) {
        body['entities'] = entities.map((e) => e.toJson()).toList();
      }

      final response = await http.put(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/messages/$messageId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode(body),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'message': data['message'] ?? 'Message edited successfully',
          'message_id': data['message_id']?.toString() ?? messageId,
          'content': data['content'] ?? content,
          'is_edited': true,
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to edit message',
        };
      }
    } catch (e) {
      debugPrint('Edit message error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Deletes a message from a chat for everyone.
  static Future<Map<String, dynamic>> deleteMessage({
    required String chatId,
    required String messageId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/messages/$messageId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'message': data['message'] ?? 'Message deleted successfully',
          'message_id': data['message_id']?.toString() ?? messageId,
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to delete message',
        };
      }
    } catch (e) {
      debugPrint('Delete message error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Clears the chat history for a specific chat.
  ///
  /// [chatId] - The ID of the chat to clear
  static Future<Map<String, dynamic>> clearChatHistory({
    required String chatId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/messages'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'message': data['message'] ?? 'Chat history cleared',
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to clear chat history',
        };
      }
    } catch (e) {
      debugPrint('Clear chat history error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Blocks a user.
  ///
  /// [userId] - The ID of the user to block
  static Future<Map<String, dynamic>> blockUser({
    required String userId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/security/blocked'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'blocked_user_id': userId}),
      );

      final data = jsonDecode(response.body);
      if ((response.statusCode == 200 || response.statusCode == 201) &&
          (data['success'] == true || data['success'] == null)) {
        return {
          'success': true,
          'message': data['message'] ?? 'User blocked successfully',
        };
      } else {
        return {
          'success': false,
          'message': data['error'] ?? data['message'] ?? 'Failed to block user',
        };
      }
    } catch (e) {
      debugPrint('Block user error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Unblocks a user.
  ///
  /// [userId] - The ID of the user to unblock
  static Future<Map<String, dynamic>> unblockUser({
    required String userId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/api/security/blocked/$userId'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 &&
          (data['success'] == true || data['success'] == null)) {
        return {
          'success': true,
          'message': data['message'] ?? 'User unblocked successfully',
        };
      } else {
        return {
          'success': false,
          'message': data['error'] ?? data['message'] ?? 'Failed to unblock user',
        };
      }
    } catch (e) {
      debugPrint('Unblock user error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Sets mute status for chat notifications.
  ///
  /// [chatId] - The ID of the chat
  /// [muted] - Whether to mute or unmute notifications
  static Future<Map<String, dynamic>> setMuteNotifications({
    required String chatId,
    required bool muted,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/notifications'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'muted': muted}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'muted': data['muted'] ?? muted,
          'message': data['message'] ?? 'Notification settings updated',
        };
      } else {
        return {
          'success': false,
          'message':
              data['message'] ?? 'Failed to update notification settings',
        };
      }
    } catch (e) {
      debugPrint('Set mute notifications error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Marks all messages up to a specific message as read.
  /// Used for progressive read tracking as user scrolls through messages.
  ///
  /// [chatId] - The ID of the chat
  /// [messageId] - The ID of the message up to which all messages should be marked as read
  static Future<Map<String, dynamic>> markMessagesReadUpTo({
    required String chatId,
    required String messageId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/messages/read-up-to'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'message_id': messageId}),
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'marked_count': data['marked_count'] ?? 0,
          'unread_count': data['unread_count'] ?? 0,
          'message': data['message'] ?? 'Messages marked as read',
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to mark messages as read',
        };
      }
    } catch (e) {
      debugPrint('Mark messages read up to error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Gets information about unread messages in a chat.
  /// Returns the ID of the first unread message and total unread count.
  ///
  /// [chatId] - The ID of the chat
  static Future<Map<String, dynamic>> getUnreadInfo({
    required String chatId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/unread-info'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'unread_count': data['unread_count'] ?? 0,
          'first_unread_message_id': data['first_unread_message_id'],
          'first_unread_message_created_at':
              data['first_unread_message_created_at'],
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to get unread info',
        };
      }
    } catch (e) {
      debugPrint('Get unread info error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Pins a chat to the top of the chat list.
  ///
  /// [chatId] - The ID of the chat to pin
  static Future<Map<String, dynamic>> pinChat({
    required String chatId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/pin'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'is_pinned': data['is_pinned'] ?? true,
          'message': data['message'] ?? 'Chat pinned successfully',
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to pin chat',
        };
      }
    } catch (e) {
      debugPrint('Pin chat error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Unpins a chat from the top of the chat list.
  ///
  /// [chatId] - The ID of the chat to unpin
  static Future<Map<String, dynamic>> unpinChat({
    required String chatId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/unpin'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'is_pinned': data['is_pinned'] ?? false,
          'message': data['message'] ?? 'Chat unpinned successfully',
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to unpin chat',
        };
      }
    } catch (e) {
      debugPrint('Unpin chat error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Gets or creates the "Saved Messages" / "Favorites" chat for the current user.
  /// This is a special chat with the user themselves.
  static Future<Map<String, dynamic>> getOrCreateSavedChat() async {
    try {
      final token = await AuthService.getToken();
      if (token == null) {
        return {'success': false, 'message': 'Not authenticated'};
      }

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/saved'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
      );

      final data = jsonDecode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {
          'success': true,
          'chat': Chat.fromJson(data['chat']),
        };
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to get saved chat',
        };
      }
    } catch (e) {
      debugPrint('Get saved chat error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Delete or leave a chat.
  /// - Private: removes the user from the chat
  /// - Group: if owner, deletes the entire chat; otherwise leaves
  /// - Channel: unsubscribes
  static Future<Map<String, dynamic>> deleteChat(String chatId) async {
    try {
      final token = await AuthService.getToken();
      final response = await http.delete(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId'),
        headers: {
          'Content-Type': 'application/json',
          if (token != null) 'Authorization': 'Bearer $token',
        },
      );

      final data = json.decode(response.body);
      if (response.statusCode == 200 && data['success'] == true) {
        return {'success': true};
      } else {
        return {
          'success': false,
          'message': data['message'] ?? 'Failed to delete chat',
        };
      }
    } catch (e) {
      debugPrint('Delete chat error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Toggle reaction on a message (add or remove)
  static Future<Map<String, dynamic>> toggleReaction({
    required String chatId,
    required String messageId,
    required String emoji,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return {'success': false, 'message': 'Not authenticated'};

      final response = await http.post(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/messages/$messageId/reactions'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'emoji': emoji}),
      );

      if (AppConfig.enableDebugLogging) {
        debugPrint(
            'ToggleReaction: POST ${AppConfig.baseUrl}/api/chats/$chatId/messages/$messageId/reactions emoji=$emoji');
        debugPrint(
            'ToggleReaction: Response ${response.statusCode}: ${response.body}');
      }

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(response.body);
        return {
          'success': data['success'] ?? false,
          'active': data['active'] ?? false,
          'action': data['action'] ?? (data['active'] == true ? 'added' : 'removed'),
          'reactions': data['reactions'],
        };
      } else {
        debugPrint('ToggleReaction failed: ${response.statusCode} ${response.body}');
        return {
          'success': false,
          'message': 'Server error: ${response.statusCode}',
        };
      }
    } catch (e) {
      debugPrint('Toggle reaction error: $e');
      return {'success': false, 'message': 'Network error: ${e.toString()}'};
    }
  }

  /// Get reactions for a message
  static Future<Map<String, dynamic>> getReactions({
    required String chatId,
    required String messageId,
  }) async {
    try {
      final token = await AuthService.getToken();
      if (token == null) return {'success': false, 'message': 'Not authenticated'};

      final response = await http.get(
        Uri.parse('${AppConfig.baseUrl}/api/chats/$chatId/messages/$messageId/reactions'),
        headers: {'Authorization': 'Bearer $token'},
      );

      final data = jsonDecode(response.body);
      return data;
    } catch (e) {
      debugPrint('Get reactions error: $e');
      return {'success': false, 'reactions': []};
    }
  }
}
