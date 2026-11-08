import '../services/chat_service.dart';

/// Represents an unsent draft message for a chat
class ChatDraft {
  final String text;
  final List<MessageEntity> entities;
  final String? replyToMessageId;
  final String? quoteText;
  final bool isQuote;
  final DateTime updatedAt;

  ChatDraft({
    required this.text,
    this.entities = const [],
    this.replyToMessageId,
    this.quoteText,
    this.isQuote = false,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  bool get isEmpty => text.trim().isEmpty && replyToMessageId == null;
  bool get isNotEmpty => !isEmpty;

  Map<String, dynamic> toJson() => {
        'text': text,
        if (entities.isNotEmpty)
          'entities': entities.map((e) => e.toJson()).toList(),
        'reply_to_message_id': replyToMessageId,
        'quote_text': quoteText,
        'is_quote': isQuote,
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
    return ChatDraft(
      text: json['text'] as String? ?? '',
      entities: parsedEntities,
      replyToMessageId: json['reply_to_message_id']?.toString() ??
          json['replyToMessageId']?.toString(),
      quoteText:
          json['quote_text'] as String? ?? json['quoteText'] as String?,
      isQuote:
          json['is_quote'] as bool? ?? json['isQuote'] as bool? ?? false,
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
    String? quoteText,
    bool? isQuote,
    DateTime? updatedAt,
  }) {
    return ChatDraft(
      text: text ?? this.text,
      entities: entities ?? this.entities,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      quoteText: quoteText ?? this.quoteText,
      isQuote: isQuote ?? this.isQuote,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
