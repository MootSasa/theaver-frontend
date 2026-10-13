/// Represents an unsent draft message for a chat
class ChatDraft {
  final String text;
  final String? replyToMessageId;
  final String? quoteText;
  final bool isQuote;
  final DateTime updatedAt;

  ChatDraft({
    required this.text,
    this.replyToMessageId,
    this.quoteText,
    this.isQuote = false,
    DateTime? updatedAt,
  }) : updatedAt = updatedAt ?? DateTime.now();

  bool get isEmpty => text.trim().isEmpty && replyToMessageId == null;
  bool get isNotEmpty => !isEmpty;

  Map<String, dynamic> toJson() => {
        'text': text,
        'reply_to_message_id': replyToMessageId,
        'quote_text': quoteText,
        'is_quote': isQuote,
        'updated_at': updatedAt.toIso8601String(),
      };

  factory ChatDraft.fromJson(Map<String, dynamic> json) => ChatDraft(
        text: json['text'] as String? ?? '',
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

  ChatDraft copyWith({
    String? text,
    String? replyToMessageId,
    String? quoteText,
    bool? isQuote,
    DateTime? updatedAt,
  }) {
    return ChatDraft(
      text: text ?? this.text,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      quoteText: quoteText ?? this.quoteText,
      isQuote: isQuote ?? this.isQuote,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
