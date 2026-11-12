import 'dart:convert';

/// Normalizes push / local-notification payloads into a flat `Map<String, dynamic>`.
///
/// HMS delivers tap data in several shapes depending on EMUI version and plugin
/// path (`extras`, `remoteMessage.dataOfMap`, JSON strings). FCM delivers a flat
/// `data` map. Local notifications carry a JSON string payload.
Map<String, dynamic> normalizePushPayload(dynamic raw) {
  final Map<String, dynamic> result = <String, dynamic>{};
  _mergeInto(result, raw, depth: 0);
  return result;
}

void _mergeInto(Map<String, dynamic> target, dynamic raw, {required int depth}) {
  if (raw == null || depth > 4) return;

  if (raw is String) {
    if (raw.isEmpty) return;
    dynamic decoded;
    try {
      decoded = json.decode(raw);
    } catch (_) {
      decoded = null;
    }
    if (decoded is Map) {
      _mergeInto(target, decoded, depth: depth + 1);
    } else if (depth == 0 && target.isEmpty) {
      // Legacy local payload: a bare chat ID (e.g. "15").
      target['chat_id'] = raw;
      target['type'] = 'new_message';
    }
    return;
  }

  if (raw is! Map) return;
  final map = Map<String, dynamic>.from(raw);

  // Copy scalar top-level values (do not let nested containers shadow them).
  map.forEach((key, value) {
    if (value is! Map && !(key == 'data' && value is String && _looksLikeJson(value))) {
      target.putIfAbsent(key, () => value);
    }
  });

  for (final nestedKey in const <String>['remoteMessage', 'extras', 'dataOfMap', 'data']) {
    final nested = map[nestedKey];
    if (nested is Map || (nested is String && _looksLikeJson(nested))) {
      _mergeInto(target, nested, depth: depth + 1);
    }
  }
}

bool _looksLikeJson(String s) {
  final t = s.trimLeft();
  return t.startsWith('{');
}

bool payloadBool(dynamic v) => v == true || v == 'true' || v == 1 || v == '1';

String payloadString(Map<String, dynamic> data, List<String> keys, [String fallback = '']) {
  for (final key in keys) {
    final value = data[key];
    if (value == null) continue;
    final s = value.toString();
    if (s.isNotEmpty && s != 'null') return s;
  }
  return fallback;
}

/// A chat message notification extracted from a WebSocket event or a push payload.
class ChatMessageNotification {
  const ChatMessageNotification({
    required this.chatId,
    required this.chatName,
    required this.senderName,
    required this.text,
    this.senderId = '',
    this.messageId,
    this.avatarUrl,
    this.senderAvatarUrl,
    this.mediaUrl,
    this.isGroup = false,
    this.isChannel = false,
    this.isMention = false,
    this.messageType = '',
  });

  final String chatId;
  final String chatName;
  final String senderName;
  final String senderId;
  final String text;
  final String? messageId;
  final String? avatarUrl;
  final String? senderAvatarUrl;
  final String? mediaUrl;
  final bool isGroup;
  final bool isChannel;
  final bool isMention;
  final String messageType;

  /// Fallback text for media messages without a caption.
  static String describeMedia(String msgType) {
    switch (msgType) {
      case 'voice':
        return '🎤 Голосовое сообщение';
      case 'video_note':
        return '📹 Видеосообщение';
      case 'image':
      case 'photo':
        return '📷 Фотография';
      case 'video':
        return '🎥 Видео';
      case 'file':
        return '📎 Файл';
      case 'sticker':
        return 'Стикер';
      case 'gif':
        return 'GIF';
      default:
        return 'Новое сообщение';
    }
  }

  /// From a `new_message` WebSocket event (`{chat_id, message: {...}, ...}`).
  static ChatMessageNotification? fromWebSocket(Map<String, dynamic> data) {
    final msg = data['message'] is Map
        ? Map<String, dynamic>.from(data['message'] as Map)
        : <String, dynamic>{};
    final chatId = payloadString(data, const ['chat_id'], payloadString(msg, const ['chat_id']));
    if (chatId.isEmpty) return null;
    final msgType = payloadString(msg, const ['message_type'], payloadString(data, const ['message_type']));
    final senderName = payloadString(msg, const ['sender_name'], payloadString(data, const ['sender_name']));
    final chatName = payloadString(data, const ['chat_name'], senderName.isNotEmpty ? senderName : 'Theaver');
    var text = payloadString(msg, const ['content'], payloadString(data, const ['message_text', 'content']));
    if (text.isEmpty) text = describeMedia(msgType);

    String? mediaUrl = payloadString(msg, const ['media_url', 'file_url'], payloadString(data, const ['media_url', 'file_url']));
    if (mediaUrl.isEmpty) {
      final mp = msg['media_payload'] ?? data['media_payload'];
      mediaUrl = mp is Map
          ? payloadString(Map<String, dynamic>.from(mp), const ['thumb_url', 'thumbnail_url', 'photo'])
          : '';
    }
    final chatType = payloadString(data, const ['chat_type'], payloadString(msg, const ['chat_type']));
    final isChannel = chatType == 'channel' || payloadBool(data['is_channel']);
    final isGroup = !isChannel &&
        (payloadBool(data['is_group']) || payloadBool(msg['is_group']) || chatType == 'group');

    return ChatMessageNotification(
      chatId: chatId,
      chatName: chatName,
      senderName: senderName,
      senderId: payloadString(msg, const ['sender_id'], payloadString(data, const ['sender_id'])),
      text: text,
      messageId: _nullIfEmpty(payloadString(msg, const ['id'], payloadString(data, const ['id', 'message_id']))),
      avatarUrl: _nullIfEmpty(payloadString(data, const ['avatar_url', 'chat_avatar'])),
      senderAvatarUrl: _nullIfEmpty(payloadString(msg, const ['sender_avatar_url', 'sender_avatar'])),
      mediaUrl: _nullIfEmpty(mediaUrl),
      isGroup: isGroup,
      isChannel: isChannel,
      messageType: msgType,
    );
  }

  /// From a flat FCM/HMS `new_message` data payload (see backend NotifyUserAboutMessage).
  static ChatMessageNotification? fromPush(Map<String, dynamic> data) {
    final chatId = payloadString(data, const ['chat_id']);
    if (chatId.isEmpty) return null;
    final senderName = payloadString(data, const ['sender_name']);
    final chatType = payloadString(data, const ['chat_type']);
    final isChannel = chatType == 'channel' || payloadBool(data['is_channel']);
    return ChatMessageNotification(
      chatId: chatId,
      chatName: payloadString(data, const ['chat_name'], senderName.isNotEmpty ? senderName : 'Theaver'),
      senderName: senderName,
      text: payloadString(data, const ['message_text', 'content'], 'Новое сообщение'),
      messageId: _nullIfEmpty(payloadString(data, const ['id', 'message_id'])),
      avatarUrl: _nullIfEmpty(payloadString(data, const ['avatar_url', 'avatar'])),
      mediaUrl: _nullIfEmpty(payloadString(data, const ['media_url', 'image', 'file_url'])),
      isGroup: !isChannel && payloadBool(data['is_group']),
      isChannel: isChannel,
      isMention: payloadBool(data['is_mention']),
      messageType: payloadString(data, const ['message_type']),
    );
  }

  /// Payload attached to the local notification (used on tap / actions).
  Map<String, dynamic> toTapPayload() => <String, dynamic>{
        'type': 'new_message',
        'chat_id': chatId,
        'chat_name': chatName,
        'sender_name': senderName,
        'is_group': isGroup,
        'is_channel': isChannel,
        'chat_type': isChannel ? 'channel' : (isGroup ? 'group' : 'private'),
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (messageId != null) 'id': messageId,
      };

  static String? _nullIfEmpty(String s) => s.isEmpty ? null : s;
}
