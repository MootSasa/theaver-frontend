import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/name_color_preset.dart';
import '../../services/chat_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/profile_theme_provider.dart';
import '../../utils/blur_utils.dart';
import '../../utils/emoji_utils.dart';
import '../profile/reply_strip_painter.dart';
import 'message_reply_info.dart';

/// A floating bubble shown above the message input field when the user
/// is composing a reply or quote.
class ReplyPreviewBar extends StatelessWidget {
  final Message replyToMessage;
  final bool isQuote;
  final String? quoteText;
  final int? quoteOffset;
  final int? quoteLength;
  final VoidCallback onClose;
  final VoidCallback? onTap;
  final bool enabled;
  final bool isLite;
  final String? currentUserId;

  const ReplyPreviewBar({
    Key? key,
    required this.replyToMessage,
    this.isQuote = false,
    this.quoteText,
    this.quoteOffset,
    this.quoteLength,
    required this.onClose,
    this.onTap,
    this.enabled = false,
    this.isLite = false,
    this.currentUserId,
  }) : super(key: key);

  /// Get icon for message type
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
    if (!enabled) {
      return _buildClassicBar(context);
    }
    return _buildGlassBar(context);
  }

  Widget _buildClassicBar(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter.grouped(
          filter: BlurUtils.createDownsampledBlur(15),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.65)
                  : Colors.white.withValues(alpha: 0.65),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.black12,
                width: 0.5,
              ),
            ),
            child: _buildContent(context),
          ),
        ),
      ),
    );
  }

  Widget _buildGlassBar(BuildContext context) {
    final glassProvider = context.watch<LiquidGlassProvider>();

    final style = glassProvider.createStyle(
      context: context,
      cornerRadius: 16,
      refractionIndex: 1.1,
      refractionWidth: 24,
      isLiteOverride: isLite,
    );

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: LiquidGlassLens(
        style: style,
        child: _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    final theme = Theme.of(context);
    final profileTheme = context.watch<ProfileThemeProvider>();

    final isSenderMe = currentUserId != null && replyToMessage.senderId == currentUserId;
    final displayName = isSenderMe
        ? context.l10n.translate('chat_reply_you')
        : (replyToMessage.senderName.isNotEmpty ? replyToMessage.senderName : 'Сообщение');

    // Telegram-style: Color and style of original message in reply preview match what that user selected in their settings
    final NameColorPreset authorPreset;
    final ReplyStripStyle authorStripStyle;
    if (isSenderMe) {
      authorPreset = profileTheme.currentNameColorPreset;
      authorStripStyle = profileTheme.currentStripStyle;
    } else if (replyToMessage.senderNameColorId != null && replyToMessage.senderNameColorId!.isNotEmpty) {
      authorPreset = NameColorPresets.getById(replyToMessage.senderNameColorId!);
      authorStripStyle = ReplyStripStyle.values.firstWhere(
        (s) => s.name == replyToMessage.senderReplyStripStyle,
        orElse: () => ReplyStripStyle.solid,
      );
    } else {
      // Replying to another user whose preset is not explicitly set: use default author preset, NOT viewer's preset
      authorPreset = NameColorPresets.getById('name_red');
      authorStripStyle = ReplyStripStyle.solid;
    }

    final accentColor = authorPreset.primaryColor;

    final isDark = theme.brightness == Brightness.dark;
    final basePreviewStyle = TextStyle(
      fontSize: 13,
      fontStyle: FontStyle.normal,
      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
    );

    // Determine preview span with original message formatting
    final InlineSpan previewSpan;
    if (!isQuote && replyToMessage.messageType != 'text') {
      final caption = replyToMessage.content.trim();
      final hasCaption = caption.isNotEmpty && caption != replyToMessage.messageType;
      String? mediaLabel;
      switch (replyToMessage.messageType) {
        case 'image':
        case 'photo':
          mediaLabel = 'Фото';
          break;
        case 'video':
          mediaLabel = 'Видео';
          break;
        case 'audio':
          mediaLabel = 'Голосовое сообщение';
          break;
        case 'file':
          mediaLabel = 'Файл';
          break;
        case 'sticker':
          mediaLabel = 'Стикер';
          break;
        case 'poll':
          mediaLabel = context.l10n.translate('chat_poll');
          break;
      }
      if (mediaLabel != null) {
        if (hasCaption && replyToMessage.messageType != 'sticker') {
          previewSpan = TextSpan(
            style: basePreviewStyle,
            children: [
              TextSpan(text: '$mediaLabel: '),
              MessageReplyInfo.buildFormattedPreviewSpan(
                rawText: replyToMessage.content,
                entities: replyToMessage.entities,
                baseStyle: basePreviewStyle,
                accentColor: accentColor,
                isDark: isDark,
              ),
            ],
          );
        } else {
          previewSpan = EmojiUtils.buildEmojiTextSpan(mediaLabel, style: basePreviewStyle);
        }
      } else {
        previewSpan = MessageReplyInfo.buildFormattedPreviewSpan(
          rawText: replyToMessage.content,
          entities: replyToMessage.entities,
          baseStyle: basePreviewStyle,
          accentColor: accentColor,
          isDark: isDark,
        );
      }
    } else {
      previewSpan = MessageReplyInfo.buildFormattedPreviewSpan(
        rawText: replyToMessage.content,
        entities: replyToMessage.entities,
        isQuote: isQuote,
        quoteText: quoteText,
        quoteOffset: quoteOffset ?? 0,
        quoteLength: quoteLength ?? 0,
        baseStyle: basePreviewStyle,
        accentColor: accentColor,
        isDark: isDark,
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Content
          Flexible(
            child: GestureDetector(
              onTap: onTap,
              behavior: HitTestBehavior.opaque,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Vertical accent bar with custom strip style
                  ReplyStripWidget(
                    preset: authorPreset,
                    style: authorStripStyle,
                    width: 3.5,
                    height: 32,
                    borderRadius: 2,
                  ),
                  const SizedBox(width: 10),
                  Flexible(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // Header: Reply/Quote label + sender name
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            isQuote
                                ? iconoir.QuoteSolid(
                                    width: 14,
                                    height: 14,
                                    color: accentColor,
                                  )
                                : iconoir.Reply(
                                    width: 14,
                                    height: 14,
                                    color: accentColor,
                                  ),
                            const SizedBox(width: 4),
                            Text(
                              isQuote ? 'Цитата' : 'Ответ',
                              style: TextStyle(
                                color: accentColor,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                displayName,
                                style: TextStyle(
                                  color: theme.colorScheme.onSurface,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        // Preview text or media indicator
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isQuote && replyToMessage.messageType != 'text')
                              Padding(
                                padding: const EdgeInsets.only(right: 4),
                                child: _buildMessageTypeIcon(
                                  replyToMessage.messageType,
                                  theme.colorScheme.onSurface.withValues(alpha: 0.5),
                                  14,
                                ),
                              ),
                            Flexible(
                              child: RichText(
                                text: previewSpan,
                                maxLines: isQuote ? 2 : 1,
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
          if (isQuote) ...[
            const SizedBox(width: 6),
            iconoir.QuoteSolid(
              width: 14,
              height: 14,
              color: accentColor.withValues(alpha: 0.45),
            ),
          ],
          const SizedBox(width: 8),
          // Close button
          IconButton(
            icon: iconoir.Xmark(
              width: 18,
              height: 18,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
            onPressed: onClose,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            splashRadius: 16,
          ),
        ],
      ),
    );
  }
}
