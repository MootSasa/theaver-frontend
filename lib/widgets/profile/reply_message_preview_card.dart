import 'package:flutter/material.dart';

import '../../models/name_color_preset.dart';
import '../../models/profile_customization.dart';
import '../common/glass_modal_sheet.dart';
import '../common/peer_badges_widget.dart';
import '../user/avatar_with_status.dart';
import '../user/emoji_status_badge.dart';
import 'reply_strip_painter.dart';

/// Реалистичная карточка предпросмотра сообщения в групповом чате Theaver
/// (аватар с рамкой слева, цветное имя, эмодзи-статус, бейдж и цитата ответа).
class ReplyMessagePreviewCard extends StatelessWidget {
  final NameColorPreset preset;
  final ReplyStripStyle stripStyle;
  final String userName;
  final String? avatarUrl;
  final String? userId;
  final AvatarDecorationPreset? avatarDecoration;
  final EmojiStatusData? emojiStatus;
  final UserBadge? badge;
  final EdgeInsetsGeometry margin;
  final bool? isDarkBackdropOverride;
  final bool showCanvasFrame;

  const ReplyMessagePreviewCard({
    Key? key,
    required this.preset,
    required this.stripStyle,
    required this.userName,
    this.avatarUrl,
    this.userId,
    this.avatarDecoration,
    this.emojiStatus,
    this.badge,
    this.margin = const EdgeInsets.symmetric(horizontal: 16),
    this.isDarkBackdropOverride,
    this.showCanvasFrame = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isDarkCanvas = isDarkBackdropOverride ?? isDark;
    final activeStatus = emojiStatus?.activeOrNull;

    final chatCanvasColor = isDarkBackdropOverride != null
        ? (isDarkCanvas
            ? Colors.black.withValues(alpha: 0.24)
            : Colors.white.withValues(alpha: 0.76))
        : (isDark
            ? Colors.white.withValues(alpha: 0.04)
            : Colors.black.withValues(alpha: 0.035));
    final bubbleColor =
        isDarkCanvas ? const Color(0xFF21242C) : Colors.white;
    final quoteBodyColor = isDarkCanvas
        ? Colors.white.withValues(alpha: 0.78)
        : const Color(0xFF1C2530).withValues(alpha: 0.82);

    final rowContent = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: AvatarWithStatus(
            userId: userId,
            avatarUrl: avatarUrl,
            name: userName,
            radius: 18,
            isOnline: false,
            decorationOverride: avatarDecoration,
            showDecoration: avatarDecoration != null,
            animateDecoration: true,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Container(
            padding: const EdgeInsets.fromLTRB(11, 9, 11, 9),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(15),
                topRight: Radius.circular(15),
                bottomRight: Radius.circular(15),
                bottomLeft: Radius.circular(5),
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black
                      .withValues(alpha: isDarkCanvas ? 0.16 : 0.05),
                  blurRadius: 6,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Имя отправителя + эмодзи-статус + бейдж
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 220),
                        style: TextStyle(
                          color: preset.primaryColor,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                        child: Text(
                          userName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    if (activeStatus != null) ...[
                      const SizedBox(width: 5),
                      EmojiStatusBadge(
                        status: activeStatus,
                        size: 16,
                        animate: true,
                        interactive: false,
                        fallbackColor: preset.primaryColor,
                      ),
                    ],
                    if (badge != null)
                      PeerBadgesRow(
                        isBot: false,
                        isVerified: false,
                        badge: badge,
                        interactiveBadge: false,
                        accentColor: preset.primaryColor,
                      ),
                  ],
                ),
                const SizedBox(height: 6),

                // Блок цитаты ответа (Reply Quote)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                  decoration: BoxDecoration(
                    color: preset.getOpaqueCardBackgroundColor(isDarkCanvas),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: IntrinsicHeight(
                    child: Row(
                      children: [
                        ReplyStripWidget(
                          preset: preset,
                          style: stripStyle,
                          width: 3.5,
                          borderRadius: 2,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                userName,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                  color: preset.primaryColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 1.5),
                              Text(
                                translateOrFallback(
                                  context,
                                  'customizationChatPreviewQuote',
                                  'Updated profile design in Theaver',
                                ),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: quoteBodyColor,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 7),

                // Текст сообщения + время
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: Text(
                        translateOrFallback(
                          context,
                          'customizationChatPreviewMessage',
                          'This is how your name, badge, and reply quote look in group chats.',
                        ),
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.28,
                          color: isDarkCanvas
                              ? Colors.white
                              : const Color(0xFF1C1C1E),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '12:45',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDarkCanvas ? Colors.white38 : Colors.black38,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );

    if (!showCanvasFrame) {
      return Padding(
        padding: margin,
        child: rowContent,
      );
    }

    return Container(
      width: double.infinity,
      margin: margin,
      padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
      decoration: BoxDecoration(
        color: chatCanvasColor,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDarkCanvas
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      child: rowContent,
    );
  }
}
