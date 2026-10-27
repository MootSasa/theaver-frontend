import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/name_color_preset.dart';
import '../../models/theav_theme.dart';
import '../../services/chat_service.dart';
import '../../services/profile_theme_provider.dart';
import '../../utils/emoji_utils.dart';
import '../../utils/entity_parser.dart';
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

  /// Offset of the quoted fragment in the original message
  final int quoteOffset;

  /// Length of the quoted fragment in the original message
  final int quoteLength;

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

  /// Optional explicit entities override for the original message
  final List<MessageEntity> entitiesOverride;

  const MessageReplyInfo({
    Key? key,
    this.replyInfo,
    this.isQuote = false,
    this.quoteText,
    this.quoteOffset = 0,
    this.quoteLength = 0,
    this.onTap,
    this.isMe = false,
    this.currentUserId,
    this.titleOverride,
    this.contentOverride,
    this.entitiesOverride = const [],
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

  static const int _kMaxPreviewCacheSize = 256;
  static final Map<int, TextSpan> _previewSpanCache = <int, TextSpan>{};

  /// Builds a single-line truncated [TextSpan] preserving the original message's
  /// formatting entities (bold, italic, underline, strikethrough, code, spoiler, link)
  /// as well as custom emojis.
  static TextSpan buildFormattedPreviewSpan({
    required String rawText,
    List<MessageEntity> entities = const [],
    bool isQuote = false,
    String? quoteText,
    int quoteOffset = 0,
    int quoteLength = 0,
    required TextStyle baseStyle,
    required Color accentColor,
    required bool isDark,
    String? prefix,
    int maxLen = 60,
  }) {
    final int cacheKey = Object.hash(
      rawText,
      entities.length,
      isQuote,
      quoteText,
      quoteOffset,
      quoteLength,
      baseStyle.color,
      baseStyle.fontSize,
      accentColor,
      isDark,
      prefix,
      maxLen,
    );
    final cached = _previewSpanCache[cacheKey];
    if (cached != null) return cached;

    String sourceText;
    List<MessageEntity> sourceEntities;

    if (isQuote && quoteText != null && quoteText.isNotEmpty) {
      String origText = rawText;
      List<MessageEntity> origEntities = entities;
      if (origEntities.isEmpty && origText.isNotEmpty) {
        final parsedOrig = EntityParser.parseMarkdown(origText);
        origText = parsedOrig.cleanText;
        origEntities = parsedOrig.entities;
      }

      int sliceStart = -1;
      int sliceEnd = -1;
      if (quoteLength > 0 &&
          quoteOffset >= 0 &&
          quoteOffset + quoteLength <= origText.length) {
        sliceStart = quoteOffset;
        sliceEnd = quoteOffset + quoteLength;
      } else if (origText.isNotEmpty) {
        final cleanQuote = EntityParser.parseMarkdown(quoteText).cleanText;
        if (cleanQuote.isNotEmpty) {
          final idx = origText.indexOf(cleanQuote);
          if (idx != -1) {
            sliceStart = idx;
            sliceEnd = idx + cleanQuote.length;
          }
        }
      }

      if (sliceStart != -1 && sliceEnd > sliceStart) {
        sourceText = origText.substring(sliceStart, sliceEnd);
        sourceEntities = <MessageEntity>[];
        for (final e in origEntities) {
          final s = math.max(sliceStart, e.offset);
          final end = math.min(sliceEnd, e.offset + e.length);
          if (s < end) {
            sourceEntities.add(
              e.copyWith(offset: s - sliceStart, length: end - s),
            );
          }
        }
      } else {
        final parsedQuote = EntityParser.parseMarkdown(quoteText);
        sourceText = parsedQuote.cleanText;
        sourceEntities = parsedQuote.entities;
      }
    } else {
      if (entities.isNotEmpty) {
        sourceText = rawText;
        sourceEntities = entities;
      } else {
        final parsed = EntityParser.parseMarkdown(rawText);
        sourceText = parsed.cleanText;
        sourceEntities = parsed.entities;
      }
    }

    // If there are no formatting entities, strip any leftover unclosed markdown tokens
    if (sourceEntities.isEmpty) {
      sourceText = sourceText
          .replaceAll(RegExp(r'```[a-zA-Z0-9+#]*'), '')
          .replaceAll('```', '')
          .replaceAll(RegExp(r'(?:^|\n)\s*(?:\*\*)?>\s?'), ' ');
    }

    final int effectiveMaxLen = isQuote ? math.max(maxLen, 220) : maxLen;

    // Collapse consecutive whitespace (preserving single newlines when isQuote is true) while mapping entity indices
    final indexMap = List<int>.filled(sourceText.length + 1, 0);
    final sb = StringBuffer();
    bool lastWasSpace = true; // skip leading whitespace
    bool lastWasNewline = false;
    for (int i = 0; i < sourceText.length; i++) {
      indexMap[i] = sb.length;
      final ch = sourceText[i];
      if (ch == '\r') continue;
      if (ch == '\n' && isQuote) {
        if (!lastWasNewline && sb.isNotEmpty) {
          sb.write('\n');
          lastWasNewline = true;
          lastWasSpace = true;
        }
      } else if (ch == '\n' || ch == ' ' || ch == '\t') {
        if (!lastWasSpace) {
          sb.write(' ');
          lastWasSpace = true;
          lastWasNewline = false;
        }
      } else {
        sb.write(ch);
        lastWasSpace = false;
        lastWasNewline = false;
      }
    }
    indexMap[sourceText.length] = sb.length;

    String singleLine = sb.toString().trimRight();
    final bool isTruncated = singleLine.length > effectiveMaxLen;
    if (isTruncated) {
      singleLine = singleLine.substring(0, effectiveMaxLen);
    }
    for (int i = 0; i <= sourceText.length; i++) {
      if (indexMap[i] > singleLine.length) {
        indexMap[i] = singleLine.length;
      }
    }

    final mappedEntities = <MessageEntity>[];
    for (final e in sourceEntities) {
      final s = indexMap[e.offset.clamp(0, sourceText.length)];
      final end = indexMap[(e.offset + e.length).clamp(0, sourceText.length)];
      if (s < end) {
        mappedEntities.add(e.copyWith(offset: s, length: end - s));
      }
    }

    final children = <InlineSpan>[];
    if (prefix != null && prefix.isNotEmpty) {
      children.add(EmojiUtils.buildEmojiTextSpan(prefix, style: baseStyle));
    }

    if (singleLine.isEmpty) {
      return TextSpan(style: baseStyle, children: children);
    }

    final points = <int>{0, singleLine.length};
    for (final e in mappedEntities) {
      points.add(e.offset);
      points.add(e.offset + e.length);
    }
    final sortedPoints = points.toList()..sort();

    for (int i = 0; i < sortedPoints.length - 1; i++) {
      final segStart = sortedPoints[i];
      final segEnd = sortedPoints[i + 1];
      if (segStart >= segEnd) continue;

      final segText = singleLine.substring(segStart, segEnd);
      final active = mappedEntities
          .where((e) => e.offset <= segStart && (e.offset + e.length) >= segEnd)
          .toList();

      TextStyle segStyle = baseStyle;
      final hasLink = active.any(
        (e) => e.type == 'text_link' || e.type == 'link' || e.type == 'url',
      );
      final hasSpoiler = active.any((e) => e.type == 'spoiler');

      if (hasLink) {
        segStyle = segStyle.copyWith(color: accentColor);
      }
      if (hasSpoiler) {
        final bool isLightText = (baseStyle.color?.computeLuminance() ?? 0.0) > 0.5;
        segStyle = segStyle.copyWith(
          backgroundColor:
              isLightText ? const Color(0x38FFFFFF) : const Color(0x22000000),
          color: isLightText ? Colors.white54 : Colors.black45,
        );
      }

      final hasStrike = active.any((e) => e.type == 'strikethrough');
      final hasUnderline = active.any((e) => e.type == 'underline') || hasLink;
      if (hasStrike && hasUnderline) {
        segStyle = segStyle.copyWith(
          decoration: TextDecoration.combine([
            TextDecoration.lineThrough,
            TextDecoration.underline,
          ]),
          decorationColor: segStyle.color,
        );
      } else if (hasStrike) {
        segStyle = segStyle.copyWith(
          decoration: TextDecoration.lineThrough,
          decorationColor: segStyle.color,
        );
      } else if (hasUnderline) {
        segStyle = segStyle.copyWith(
          decoration: TextDecoration.underline,
          decorationColor: segStyle.color,
        );
      }

      if (active.any((e) => e.type == 'bold')) {
        segStyle = segStyle.copyWith(fontWeight: FontWeight.bold);
      }
      if (active.any((e) => e.type == 'italic')) {
        segStyle = segStyle.copyWith(fontStyle: FontStyle.italic);
      }
      if (active.any((e) => e.type == 'code' || e.type == 'pre')) {
        segStyle = segStyle.copyWith(fontFamily: 'monospace');
      }

      children.add(EmojiUtils.buildEmojiTextSpan(segText, style: segStyle));
    }

    if (isTruncated) {
      children.add(TextSpan(text: '...', style: baseStyle));
    }

    final result = TextSpan(style: baseStyle, children: children);
    if (_previewSpanCache.length >= _kMaxPreviewCacheSize) {
      _previewSpanCache.remove(_previewSpanCache.keys.first);
    }
    _previewSpanCache[cacheKey] = result;
    return result;
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
    final bgColor = preset.getOpaqueCardBackgroundColor(isDark);
    final rawAccent = isReplyingToMe
        ? ((p?.hasCustomChatReplyTitle ?? false) ? p!.chatReplyTitle : preset.primaryColor)
        : preset.primaryColor;
    final accentColor = NameColorPreset.resolveReadableAccentColor(bgColor, rawAccent);
    final textColor = NameColorPreset.resolveReadableTextColor(
      bgColor,
      configuredColor: p?.chatReplyText,
      isExplicitCustom: p?.hasCustomChatReplyText ?? false,
    );

    final effectiveEntities = entitiesOverride.isNotEmpty
        ? entitiesOverride
        : (replyInfo?.entities ?? const <MessageEntity>[]);
    final basePreviewStyle = TextStyle(
      color: textColor,
      fontSize: 12,
    );

    // Determine preview span
    TextSpan? previewSpan;
    if (isDeleted) {
      previewSpan = TextSpan(text: 'Сообщение удалено', style: basePreviewStyle);
    } else if (contentOverride != null) {
      if (contentOverride!.trim().isNotEmpty) {
        previewSpan = buildFormattedPreviewSpan(
          rawText: contentOverride!,
          entities: effectiveEntities,
          baseStyle: basePreviewStyle,
          accentColor: accentColor,
          isDark: isDark,
        );
      }
    } else if (isQuote && quoteText != null && quoteText!.isNotEmpty) {
      previewSpan = buildFormattedPreviewSpan(
        rawText: replyInfo?.content ?? quoteText!,
        entities: effectiveEntities,
        isQuote: true,
        quoteText: quoteText,
        quoteOffset: quoteOffset,
        quoteLength: quoteLength,
        baseStyle: basePreviewStyle,
        accentColor: accentColor,
        isDark: isDark,
      );
    } else if (replyInfo != null && replyInfo!.isUnsupported) {
      final unsupportedLabel =
          context.l10n.translate('message_unsupported_preview');
      previewSpan = EmojiUtils.buildEmojiTextSpan(
        unsupportedLabel,
        style: basePreviewStyle,
      );
    } else if (replyInfo != null && replyInfo!.messageType != 'text') {
      // Show media type indicator with optional caption
      final caption = replyInfo!.content.trim();
      final hasCaption = caption.isNotEmpty && caption != replyInfo!.messageType;
      String mediaLabel;
      switch (replyInfo!.messageType) {
        case 'image':
        case 'photo':
          mediaLabel = hasCaption ? '📷 ' : '📷 Фото';
          break;
        case 'video':
          mediaLabel = hasCaption ? '🎥 ' : '🎥 Видео';
          break;
        case 'audio':
        case 'voice':
          mediaLabel = hasCaption ? '🎤 ' : '🎤 Голосовое сообщение';
          break;
        case 'file':
        case 'document':
          mediaLabel = hasCaption ? '📎 ' : '📎 Файл';
          break;
        case 'sticker':
          mediaLabel = '🎭 Стикер';
          break;
        case 'poll':
          final pollLabel = context.l10n.translate('chat_poll');
          mediaLabel = hasCaption ? '📊 ' : '📊 $pollLabel';
          break;
        default:
          mediaLabel = '';
      }
      if (hasCaption && replyInfo!.messageType != 'sticker') {
        previewSpan = buildFormattedPreviewSpan(
          rawText: replyInfo!.content,
          entities: effectiveEntities,
          prefix: mediaLabel,
          baseStyle: basePreviewStyle,
          accentColor: accentColor,
          isDark: isDark,
        );
      } else if (mediaLabel.isNotEmpty) {
        previewSpan = EmojiUtils.buildEmojiTextSpan(
          mediaLabel,
          style: basePreviewStyle,
        );
      } else if (replyInfo!.content.trim().isNotEmpty) {
        previewSpan = buildFormattedPreviewSpan(
          rawText: replyInfo!.content,
          entities: effectiveEntities,
          baseStyle: basePreviewStyle,
          accentColor: accentColor,
          isDark: isDark,
        );
      }
    } else if (replyInfo != null && replyInfo!.content.trim().isNotEmpty) {
      previewSpan = buildFormattedPreviewSpan(
        rawText: replyInfo!.content,
        entities: effectiveEntities,
        baseStyle: basePreviewStyle,
        accentColor: accentColor,
        isDark: isDark,
      );
    }

    final bool hasPreview =
        previewSpan != null && previewSpan.toPlainText().trim().isNotEmpty;

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
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              bottom: 0,
              left: 0,
              child: ReplyStripWidget(
                preset: preset,
                style: stripStyle,
                width: 3.5,
                borderRadius: 2,
              ),
            ),
            if (isQuote && !isDeleted)
              Positioned(
                top: 2,
                right: 0,
                child: iconoir.QuoteSolid(
                  width: 14,
                  height: 14,
                  color: accentColor.withValues(alpha: 0.45),
                ),
              ),
            Padding(
              padding: EdgeInsets.only(
                left: 11.5,
                right: (isQuote && !isDeleted) ? 16.0 : 0.0,
              ),
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
                  if (!isDeleted && title.isNotEmpty && hasPreview)
                    const SizedBox(height: 2),
                  // Preview text
                  if (hasPreview)
                    if (isQuote && !isDeleted)
                      RichText(
                        text: previewSpan,
                        maxLines: 3,
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
                              text: previewSpan,
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
    );
  }
}
