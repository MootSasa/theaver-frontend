import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/name_color_preset.dart';
import '../../models/theav_theme.dart';
import '../../services/chat_service.dart';
import '../../services/profile_theme_provider.dart';
import '../../utils/emoji_utils.dart';
import '../profile/reply_strip_painter.dart';

/// Displays a compact reply/quote preview above a message bubble.
/// Shows the original sender's name and a truncated preview of the content.
/// Tapping scrolls to the original message.
///
/// Handles gracefully the case when the original message was deleted
/// (shows "Сообщение удалено").
class MessageReplyInfo extends StatelessWidget {
  /// The reply info (cached preview data)
  final ReplyInfo? replyInfo;

  /// Whether this is a quote (partial text) rather than a full reply
  final bool isQuote;

  /// The quoted text fragment (for quotes)
  final String? quoteText;

  /// Callback when user taps to scroll to the original message
  final VoidCallback? onTap;

  /// Whether this is the current user's message (affects color)
  final bool isMe;

  /// Current authenticated user ID (to detect self-replies)
  final String? currentUserId;

  /// Optional override for the title (instead of senderName from replyInfo)
  final String? titleOverride;

  /// Optional override for the content (instead of content from replyInfo)
  final String? contentOverride;

  const MessageReplyInfo({
    Key? key,
    this.replyInfo,
    this.isQuote = false,
    this.quoteText,
    this.onTap,
    this.isMe = false,
    this.currentUserId,
    this.titleOverride,
    this.contentOverride,
  }) : super(key: key);

  /// Helper to create a forwarded message header
  factory MessageReplyInfo.forwarded({
    required String authorName,
    String? content,
    bool isMe = false,
    VoidCallback? onTap,
  }) {
    return MessageReplyInfo(
      titleOverride: authorName,
      contentOverride: content,
      isMe: isMe,
      onTap: onTap,
    );
  }

  String _truncate(String text, {int maxLen = 60}) {
    final cleaned = _cleanMarkdown(text);
    if (cleaned.length <= maxLen) return cleaned;
    return '${cleaned.substring(0, maxLen)}...';
  }

  String _cleanMarkdown(String text) {
    return text
        .replaceAll(RegExp(r'```[a-zA-Z0-9+#]*'), '') // Remove code block start/lang
        .replaceAll('```', '') // Remove code block end
        .replaceAll(RegExp(r'`'), '') // Remove inline code backticks
        .replaceAll(RegExp(r'[*_~]'), '') // Remove basic markdown formatting
        .replaceAll(RegExp(r'\n+'), ' ') // Replace newlines with spaces for single-line preview
        .trim();
  }

  Widget _buildMessageTypeIcon(String messageType, Color color, double size) {
    switch (messageType) {
      case 'image':
      case 'photo':
        return iconoir.MediaImage(width: size, height: size, color: color);
      case 'video':
        return iconoir.VideoCamera(width: size, height: size, color: color);
      case 'audio':
      case 'voice':
        return iconoir.Microphone(width: size, height: size, color: color);
      case 'file':
      case 'document':
        return iconoir.Page(width: size, height: size, color: color);
      case 'sticker':
        return iconoir.Emoji(width: size, height: size, color: color);
      case 'poll':
        return iconoir.StatsReport(width: size, height: size, color: color);
      default:
        return iconoir.ChatBubble(width: size, height: size, color: color);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    // If no reply info AND no overrides, show nothing
    if (replyInfo == null && titleOverride == null) return const SizedBox.shrink();

    // Check if original message was deleted.
    final isDeleted = replyInfo == null ? false : replyInfo!.messageId.isEmpty;

    // Retrieve profile theme for fallback
    final profileTheme = context.watch<ProfileThemeProvider>();

    final bool isReplyingToMe =
        (replyInfo != null && currentUserId != null && replyInfo!.senderId == currentUserId) ||
        (replyInfo == null && isMe);

    // Telegram-style: Color and style of original message in reply preview match what that user selected in their settings
    final NameColorPreset preset;
    final ReplyStripStyle stripStyle;

    if (isReplyingToMe) {
      preset = profileTheme.currentNameColorPreset;
      stripStyle = profileTheme.currentStripStyle;
    } else if (replyInfo?.nameColorPresetId != null && replyInfo!.nameColorPresetId!.isNotEmpty) {
      preset = NameColorPresets.getById(replyInfo!.nameColorPresetId!);
      stripStyle = ReplyStripStyle.values.firstWhere(
        (s) => s.name == replyInfo!.replyStripStyle,
        orElse: () => ReplyStripStyle.solid,
      );
    } else if (replyInfo != null) {
      // Replying to another user whose preset is not explicitly set: use default author preset, NOT viewer's preset
      preset = NameColorPresets.getById('name_red');
      stripStyle = ReplyStripStyle.solid;
    } else {
      preset = profileTheme.currentNameColorPreset;
      stripStyle = profileTheme.currentStripStyle;
    }

    // Accent and vibrant opaque background color derived from preset and theme palette
    final themeExt = Theme.of(context).extension<TheavThemeExtension>();
    final p = themeExt?.palette;
    final accentColor = isReplyingToMe ? (p?.chatReplyTitle ?? preset.primaryColor) : preset.primaryColor;
    final bgColor = preset.getOpaqueCardBackgroundColor(isDark);
    final textColor = p?.chatReplyText ?? (isDark ? Colors.white70 : const Color(0xFF1C2530));

    // Determine preview text
    String previewText;
    if (isDeleted) {
      previewText = 'Сообщение удалено';
    } else if (contentOverride != null) {
      previewText = _truncate(contentOverride!);
    } else if (isQuote && quoteText != null && quoteText!.isNotEmpty) {
      previewText = _truncate(quoteText!);
    } else if (replyInfo != null && replyInfo!.messageType != 'text') {
      // Show media type indicator with optional caption
      final caption = replyInfo!.content.trim();
      final hasCaption = caption.isNotEmpty && caption != replyInfo!.messageType;
      switch (replyInfo!.messageType) {
        case 'image':
        case 'photo':
          previewText = hasCaption ? '📷 ${_truncate(caption)}' : '📷 Фото';
          break;
        case 'video':
          previewText = hasCaption ? '🎥 ${_truncate(caption)}' : '🎥 Видео';
          break;
        case 'audio':
        case 'voice':
          previewText = hasCaption ? '🎤 ${_truncate(caption)}' : '🎤 Голосовое сообщение';
          break;
        case 'file':
        case 'document':
          previewText = hasCaption ? '📎 ${_truncate(caption)}' : '📎 Файл';
          break;
        case 'sticker':
          previewText = '🎭 Стикер';
          break;
        default:
          previewText = _truncate(replyInfo!.content);
      }
    } else if (replyInfo != null) {
      previewText = _truncate(replyInfo!.content);
    } else {
      previewText = '';
    }

    final youTitle = context.l10n.translate('chat_reply_you');
    String title = titleOverride ?? '';
    if (title.isEmpty) {
      if (isReplyingToMe) {
        title = youTitle;
      } else if (replyInfo != null && replyInfo!.senderName.isNotEmpty) {
        title = replyInfo!.senderName;
      } else {
        title = 'Сообщение';
      }
    }
    if (title == 'Вы' || title == 'You') {
      title = youTitle;
    }

    return GestureDetector(
      onTap: isDeleted ? null : onTap,
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: IntrinsicHeight(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Accent strip with strip style (solid, dualColor, candyCane, segmented)
              ReplyStripWidget(
                preset: preset,
                style: stripStyle,
                width: 3.5,
                borderRadius: 2,
              ),
              const SizedBox(width: 8),

              // Quoted content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Sender name / Title
                    if (!isDeleted && title.isNotEmpty)
                      Text(
                        title,
                        style: TextStyle(
                          color: accentColor,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    if (!isDeleted && title.isNotEmpty && previewText.isNotEmpty)
                      const SizedBox(height: 2),
                    // Preview text
                    if (previewText.isNotEmpty)
                      if (isQuote && !isDeleted)
                        RichText(
                          text: EmojiUtils.buildEmojiTextSpan(
                            previewText,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 12,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      else
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isDeleted && replyInfo != null && replyInfo!.messageType != 'text')
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: _buildMessageTypeIcon(replyInfo!.messageType, textColor, 12),
                              ),
                            Flexible(
                              child: RichText(
                                text: EmojiUtils.buildEmojiTextSpan(
                                  previewText,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 12,
                                  ),
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
