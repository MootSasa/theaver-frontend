import '../services/chat_service.dart';

/// Represents an unsent draft message for a chat.
class ChatDraft {
  final String text;
  final List<MessageEntity> entities;
  final String? replyToMessageId;
  final String? quoteText;
  final bool isQuote;
  final int quoteOffset;
  final int quoteLength;
  final DateTime updatedAt;

  ChatDraft({
    required this.text,
    this.entities = const [],
    this.replyToMessageId,
    this.quoteText,
    this.isQuote = false,
    this.quoteOffset = 0,
    this.quoteLength = 0,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  /// A draft with empty or whitespace-only text is always considered empty,
  /// even if a stale [replyToMessageId] is still attached.
  bool get isEmpty => text.trim().isEmpty;
  bool get isNotEmpty => !isEmpty;

  Map<String, dynamic> toJson() => {
        'text': text,
        if (entities.isNotEmpty)
          'entities': entities.map((e) => e.toJson()).toList(),
        'reply_to_message_id': replyToMessageId,
        'quote_text': quoteText,
        'is_quote': isQuote,
        if (quoteOffset > 0) 'quote_offset': quoteOffset,
        if (quoteLength > 0) 'quote_length': quoteLength,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ChatDraft.fromJson(Map<String, dynamic> json) {
    final rawEntities = json['entities'];
    final parsedEntities = <MessageEntity>[];
    if (rawEntities is List) {
      for (final item in rawEntities) {
        if (item is Map<String, dynamic>) {
          parsedEntities.add(MessageEntity.fromJson(item));
        } else if (item is Map) {
          parsedEntities.add(
            MessageEntity.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      }
    }
    int parseInt(dynamic v) => v is int ? v : (v is num ? v.toInt() : int.tryParse(v?.toString() ?? '') ?? 0);

    return ChatDraft(
      text: json['text'] as String? ?? '',
      entities: parsedEntities,
      replyToMessageId: json['reply_to_message_id']?.toString() ??
          json['replyToMessageId']?.toString(),
      quoteText:
          json['quote_text'] as String? ?? json['quoteText'] as String?,
      isQuote:
          json['is_quote'] as bool? ?? json['isQuote'] as bool? ?? false,
      quoteOffset: parseInt(json['quote_offset'] ?? json['quoteOffset']),
      quoteLength: parseInt(json['quote_length'] ?? json['quoteLength']),
      updatedAt: DateTime.tryParse(json['updated_at']?.toString() ??
              json['updatedAt']?.toString() ??
              '') ??
          DateTime.now(),
    );
  }

  ChatDraft copyWith({
    String? text,
    List<MessageEntity>? entities,
    String? replyToMessageId,
    bool clearReply = false,
    String? quoteText,
    bool? isQuote,
    int? quoteOffset,
    int? quoteLength,
    DateTime? updatedAt,
  }) {
    return ChatDraft(
      text: text ?? this.text,
      entities: entities ?? this.entities,
      replyToMessageId:
          clearReply ? null : (replyToMessageId ?? this.replyToMessageId),
      quoteText: clearReply ? null : (quoteText ?? this.quoteText),
      isQuote: clearReply ? false : (isQuote ?? this.isQuote),
      quoteOffset: clearReply ? 0 : (quoteOffset ?? this.quoteOffset),
      quoteLength: clearReply ? 0 : (quoteLength ?? this.quoteLength),
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
