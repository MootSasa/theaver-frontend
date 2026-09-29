import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/name_color_preset.dart';
import '../../services/chat_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/profile_theme_provider.dart';
import '../../utils/emoji_utils.dart';
import '../profile/reply_strip_painter.dart';

/// A floating bubble shown above the message input field when the user
/// is composing a reply or quote.
class ReplyPreviewBar extends StatelessWidget {
  final Message replyToMessage;
  final bool isQuote;
  final String? quoteText;
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
    required this.onClose,
    this.onTap,
    this.enabled = false,
    this.isLite = false,
    this.currentUserId,
  }) : super(key: key);

  /// Truncate text for preview with ...
  String _truncate(String text, {int maxLen = 60}) {
    final clean = text
        .replaceAll(RegExp(r'```[a-zA-Z0-9+#]*'), '')
        .replaceAll('```', '')
        .replaceAll(RegExp(r'`'), '')
        .replaceAll(RegExp(r'[*_~]'), '')
        .replaceAll(RegExp(r'\n+'), ' ')
        .trim();
    if (clean.length <= maxLen) return clean;
    return '${clean.substring(0, maxLen)}...';
  }

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
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 15, sigmaY: 15),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    final lightAngle = glassProvider.getEffectiveLightAngle(reduceMotion: reduceMotion);

    final shape = LiquidGlassShape.continuousRoundedRectangle(
      cornerRadius: 16,
      clipQuality: LiquidGlassClipQuality.exact,
      borderWidth: 0.7,
      lightIntensity: isDark ? 0.7 : 0.95,
      lightDirection: lightAngle,
      borderType: const OpticalBorder(
        borderSaturation: 1.1,
        ambientIntensity: 0.85,
        borderSolidity: 0.95,
      ),
    );

    final style = LiquidGlassStyle(
      shape: shape,
      appearance: LiquidGlassAppearance(
        color: isDark ? const Color(0x33202025) : const Color(0x8FFFFFFF),
        blur: glassProvider.blurEffect,
        shadow: LiquidGlassShadow(
          blur: 16,
          opacity: isDark ? 0.40 : 0.18,
          offset: const Offset(0, 4),
          color: Colors.black,
        ),
      ),
      refraction: const LiquidGlassRefraction(
        distortion: 0.06,
        distortionWidth: 26,
      ),
      liteGlass: isLite ? LiquidGlassLitePickup.backdrop : null,
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

    // Determine preview text
    String previewText;
    if (isQuote && quoteText != null && quoteText!.isNotEmpty) {
      previewText = _truncate(quoteText!);
    } else if (replyToMessage.messageType != 'text') {
      final caption = replyToMessage.content.trim();
      final hasCaption = caption.isNotEmpty && caption != replyToMessage.messageType;
      switch (replyToMessage.messageType) {
        case 'image':
        case 'photo':
          previewText = hasCaption ? 'Фото: ${_truncate(caption)}' : 'Фото';
          break;
        case 'video':
          previewText = hasCaption ? 'Видео: ${_truncate(caption)}' : 'Видео';
          break;
        case 'audio':
          previewText = hasCaption ? 'Голосовое сообщение: ${_truncate(caption)}' : 'Голосовое сообщение';
          break;
        case 'file':
          previewText = hasCaption ? 'Файл: ${_truncate(caption)}' : 'Файл';
          break;
        case 'sticker':
          previewText = 'Стикер';
          break;
        default:
          previewText = _truncate(replyToMessage.content);
      }
    } else {
      previewText = _truncate(replyToMessage.content);
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
                                ? iconoir.Quote(
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
                            if (replyToMessage.messageType != 'text')
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
                                text: EmojiUtils.buildEmojiTextSpan(
                                  previewText,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
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
