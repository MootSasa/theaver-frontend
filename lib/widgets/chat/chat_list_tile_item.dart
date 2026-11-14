import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/profile_customization.dart';
import '../../models/theav_theme.dart';
import '../../services/chat_service.dart';
import '../../services/chat_swipe_service.dart';
import '../../services/draft_service.dart';
import '../../services/peer_customization_cache.dart';
import '../../services/tiling_layout_controller.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/emoji_utils.dart';
import '../../utils/image_utils.dart';
import '../common/peer_badges_widget.dart';
import '../user/avatar_with_status.dart';
import '../user/emoji_status_badge.dart';
import 'round_video_thumbnail.dart';
import 'swipeable_chat_tile.dart';

String _tr(BuildContext context, String key, String fallback) {
  final translated = AppLocalizations.of(context)?.translate(key);
  if (translated == null || translated.isEmpty || translated == key) {
    return fallback;
  }
  return translated;
}

/// Shared Telegram-style chat list row with animated selection state,
/// persistent timestamps/unread badges, mute indicators, drafts, typing
/// previews, custom emojis, and bounded swipe actions.
class ChatListTileItem extends StatelessWidget {
  final Chat chat;
  final bool isSelectMode;
  final bool isSelected;
  final bool isMuted;
  final String? currentUserId;
  final String? fallbackSavedAvatarUrl;
  final ({String action, String? userName})? typingInfo;
  final List<MessageEntity> fallbackEntities;
  final bool isOpenInTile;
  final bool isFocusedInTile;
  final ChatSwipeAction? swipeOverrideAction;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final GestureTapUpCallback? onSecondaryTapUp;
  final DraggingChatPayload Function(Rect initialRect, Offset globalPosition)?
      onCreateDragPayload;
  final Future<void> Function(ChatSwipeAction action) onSwipeAction;

  const ChatListTileItem({
    super.key,
    required this.chat,
    required this.isSelectMode,
    required this.isSelected,
    required this.isMuted,
    this.currentUserId,
    this.fallbackSavedAvatarUrl,
    this.typingInfo,
    this.fallbackEntities = const [],
    this.isOpenInTile = false,
    this.isFocusedInTile = false,
    this.swipeOverrideAction,
    required this.onTap,
    required this.onLongPress,
    this.onSecondaryTapUp,
    this.onCreateDragPayload,
    required this.onSwipeAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final hasUnread = chat.unreadCount > 0 || chat.unreadCount == -1;
    final isPrivateChat = chat.chatType == 'private';
    final isCommunity = chat.chatType == 'community';

    PeerCustomization? cachedCust;
    if (isPrivateChat &&
        chat.otherUserId != null &&
        chat.otherUserId!.isNotEmpty) {
      try {
        cachedCust = context.select<PeerCustomizationCache?, PeerCustomization?>(
          (cache) => cache?.getSync(chat.otherUserId),
        );
      } catch (_) {
        cachedCust = PeerCustomizationCache.instance.getSync(chat.otherUserId);
      }
    }
    final effectiveCust = isPrivateChat ? (cachedCust ?? chat.peerCustomization) : null;

    const double avatarRadius = 22.0;

    final String? effectiveAvatarUrl = chat.chatType == 'saved' &&
            (chat.avatarUrl == null || chat.avatarUrl!.isEmpty)
        ? fallbackSavedAvatarUrl
        : chat.avatarUrl;

    final Widget fallbackIcon = _buildFallbackIcon();

    final Widget avatarWidget = isPrivateChat
        ? AvatarWithStatus(
            userId: chat.otherUserId,
            avatarUrl: effectiveAvatarUrl,
            name: chat.name,
            radius: avatarRadius,
            isOnline: isSelectMode ? false : chat.isOnline,
            decorationOverride: effectiveCust?.avatarDecoration,
            showDecoration: true,
            animateDecoration: false,
          )
        : isCommunity
            ? Container(
                width: avatarRadius * 2,
                height: avatarRadius * 2,
                decoration: BoxDecoration(
                  color: primaryColor,
                  borderRadius: BorderRadius.circular(14),
                  image: effectiveAvatarUrl != null &&
                          effectiveAvatarUrl.isNotEmpty &&
                          avatarImageProvider(effectiveAvatarUrl) != null
                      ? DecorationImage(
                          image: avatarImageProvider(effectiveAvatarUrl)!,
                          fit: BoxFit.cover,
                        )
                      : null,
                ),
                alignment: Alignment.center,
                child: effectiveAvatarUrl == null || effectiveAvatarUrl.isEmpty
                    ? fallbackIcon
                    : null,
              )
            : SizedBox(
                width: avatarRadius * 2,
                height: avatarRadius * 2,
                child: CircleAvatar(
                  radius: avatarRadius,
                  backgroundColor: primaryColor,
                  backgroundImage:
                      effectiveAvatarUrl != null && effectiveAvatarUrl.isNotEmpty
                          ? avatarImageProvider(effectiveAvatarUrl)
                          : null,
                  child: effectiveAvatarUrl == null || effectiveAvatarUrl.isEmpty
                      ? fallbackIcon
                      : null,
                ),
              );

    final Widget leadingWidget = Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedScale(
          scale: (isSelectMode && isSelected) ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: avatarWidget,
        ),
        Positioned(
          right: -1,
          bottom: -1,
          child: IgnorePointer(
            child: AnimatedScale(
              scale: (isSelectMode && isSelected) ? 1.0 : 0.0,
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutBack,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: primaryColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.scaffoldBackgroundColor,
                    width: 2,
                  ),
                ),
                child: const Center(
                  child: iconoir.Check(
                    color: Colors.white,
                    width: 12,
                    height: 12,
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );

    final themeExt = theme.extension<TheavThemeExtension>();
    final badgeBgColor = isMuted
        ? (isDark
            ? Colors.white.withValues(alpha: 0.24)
            : Colors.grey.withValues(alpha: 0.48))
        : (themeExt?.palette.unreadBadge ?? primaryColor);
    final badgeTextColor = isMuted
        ? Colors.white
        : (themeExt?.palette.unreadBadgeText ?? theme.colorScheme.onPrimary);

    final Widget trailingWidget = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (chat.lastMessageTime != null)
          Text(
            _formatChatTime(context, chat.lastMessageTime!),
            style: TextStyle(
              fontSize: 12,
              color: (hasUnread && !isMuted) ? primaryColor : Colors.grey[500],
            ),
          ),
        const SizedBox(height: 4),
        if (hasUnread)
          Container(
            height: 18,
            constraints: const BoxConstraints(minWidth: 18),
            padding: chat.unreadCount == -1
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 5),
            decoration: BoxDecoration(
              color: badgeBgColor,
              borderRadius: BorderRadius.circular(9),
            ),
            child: Center(
              widthFactor: 1.0,
              heightFactor: 1.0,
              child: chat.unreadCount == -1
                  ? const SizedBox(width: 18, height: 18)
                  : Text(
                      chat.unreadCount > 99
                          ? '99+'
                          : chat.unreadCount.toString(),
                      style: TextStyle(
                        color: badgeTextColor,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                      ),
                      textAlign: TextAlign.center,
                    ),
            ),
          )
        else
          const SizedBox(height: 18),
      ],
    );

    final Color? rowBgColor = isSelected
        ? primaryColor.withValues(alpha: isDark ? 0.16 : 0.10)
        : isFocusedInTile
            ? primaryColor.withValues(alpha: 0.12)
            : isOpenInTile
                ? primaryColor.withValues(alpha: 0.06)
                : null;

    Widget rowContent = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      color: rowBgColor ?? Colors.transparent,
      child: Material(
        type: MaterialType.transparency,
        child: ListTile(
          onLongPress: onLongPress,
          onTap: onTap,
          leading: leadingWidget,
          title: Row(
            children: [
              if (chat.isPinned || chat.chatType == 'saved')
                Padding(
                  padding: const EdgeInsets.only(right: 4),
                  child: iconoir.Pin(
                    width: 14,
                    height: 14,
                    color: hasUnread ? primaryColor : Colors.grey[500],
                  ),
                ),
              Expanded(
                child: Row(
                  children: [
                    Flexible(
                      child: Text(
                        chat.chatType == 'saved'
                            ? _tr(context, 'chat_saved_messages', 'Избранное')
                            : chat.name,
                        style: TextStyle(
                          fontWeight:
                              hasUnread ? FontWeight.w600 : FontWeight.w500,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isPrivateChat &&
                        effectiveCust?.activeEmojiStatus != null) ...[
                      const SizedBox(width: 4),
                      EmojiStatusBadge(
                        status: effectiveCust!.activeEmojiStatus,
                        size: 15,
                        interactive: false,
                      ),
                    ],
                    PeerBadgesRow(
                      isBot: chat.isBot,
                      isVerified: chat.isVerified || chat.chatType == 'system',
                      badge: isPrivateChat ? effectiveCust?.visibleBadge : null,
                      interactiveBadge: false,
                      verifiedIconSize: 15,
                    ),
                    if (isMuted && chat.chatType != 'saved')
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: iconoir.BellOff(
                          width: 13.5,
                          height: 13.5,
                          color: Colors.grey[500],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          subtitle: _buildSubtitle(context, hasUnread),
          trailing: trailingWidget,
        ),
      ),
    );

    if (isSelectMode && onSecondaryTapUp != null) {
      rowContent = GestureDetector(
        behavior: HitTestBehavior.translucent,
        onSecondaryTapUp: onSecondaryTapUp,
        child: rowContent,
      );
    }

    return SwipeableChatTile(
      key: ValueKey('chat_swipe_${chat.id}'),
      chat: chat,
      enabled: !isSelectMode,
      overrideAction: swipeOverrideAction,
      onSecondaryTapUp: onSecondaryTapUp,
      onCreateDragPayload: onCreateDragPayload,
      onAction: onSwipeAction,
      child: rowContent,
    );
  }

  Widget _buildFallbackIcon() {
    switch (chat.chatType) {
      case 'private':
        return const iconoir.User(color: Colors.white, width: 22, height: 22);
      case 'group':
        return const iconoir.Group(color: Colors.white, width: 22, height: 22);
      case 'channel':
        return const iconoir.Megaphone(
          color: Colors.white,
          width: 22,
          height: 22,
        );
      case 'community':
        return const Icon(Icons.hub_rounded, color: Colors.white, size: 22);
      case 'saved':
        return const iconoir.Bookmark(
          color: Colors.white,
          width: 22,
          height: 22,
        );
      case 'system':
        return const iconoir.ShieldCheck(
          color: Colors.white,
          width: 22,
          height: 22,
        );
      default:
        return const iconoir.ChatBubble(
          color: Colors.white,
          width: 22,
          height: 22,
        );
    }
  }

  Widget? _buildSubtitle(BuildContext context, bool hasUnread) {
    final loc = AppLocalizations.of(context);
    final info = typingInfo;
    if (info != null) {
      final isGroup = chat.chatType == 'group';
      final userName = info.userName;
      final String statusText;
      if (isGroup && userName != null && userName.isNotEmpty) {
        final String key;
        if (info.action == 'record_voice') {
          key = 'chat_user_recording_voice';
        } else if (info.action == 'record_round') {
          key = 'chat_user_recording_round';
        } else {
          key = 'chat_user_typing';
        }
        statusText = (loc?.translate(key) ?? '$userName typing...')
            .replaceAll('{name}', userName);
      } else {
        final String key;
        if (info.action == 'record_voice') {
          key = 'chat_status_recording_voice';
        } else if (info.action == 'record_round') {
          key = 'chat_status_recording_round';
        } else {
          key = 'chat_status_typing';
        }
        statusText = loc?.translate(key) ?? 'typing...';
      }
      final accentColor = Theme.of(context).brightness == Brightness.dark
          ? const Color(0xFF5CB8E6)
          : Theme.of(context).colorScheme.primary;
      return Text(
        statusText,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: accentColor,
          fontWeight: FontWeight.w500,
          fontSize: 14,
        ),
      );
    }

    final draft = DraftService().getPublishedDraft(chat.id);
    if (draft != null && draft.isNotEmpty) {
      final draftPrefix = loc?.translate('chat_draft') ?? 'Черновик';
      final hasDraftText = draft.text.trim().isNotEmpty;
      final draftText = hasDraftText ? draft.text : '...';
      final draftStyle = TextStyle(
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.65),
        fontSize: 14,
      );
      return RichText(
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        text: TextSpan(
          children: [
            TextSpan(
              text: '$draftPrefix: ',
              style: const TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.w600,
                fontSize: 14,
              ),
            ),
            EmojiUtils.buildPreviewWithCustomEmojis(
              draftText,
              style: draftStyle,
              entities: hasDraftText ? draft.entities : const [],
              emojiSize: 16.0,
            ),
          ],
        ),
      );
    }

    if (chat.isLastMessageRoundVideo) {
      final primary = Theme.of(context).colorScheme.primary;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          RoundVideoThumbnail(
            videoUrl: chat.lastMessageFileUrl,
            size: 18,
          ),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              loc?.translate('chat_video_note') ?? 'Video message',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: primary,
                fontWeight: FontWeight.w500,
                fontSize: 14,
              ),
            ),
          ),
        ],
      );
    }

    String? displaySubtitle;
    if (chat.isLastMessageUnsupported) {
      displaySubtitle =
          loc?.translate('message_unsupported_preview') ?? 'Unsupported message';
    } else if (chat.lastMessageType?.toLowerCase() == 'call') {
      displaySubtitle = Chat.formatCallPreview(
        chat.lastMessage,
        currentUserId: currentUserId,
      );
    } else {
      displaySubtitle = chat.lastMessage;
      if (displaySubtitle == null || displaySubtitle.trim().isEmpty) {
        if (chat.lastMessageGroupedId != null &&
            chat.lastMessageGroupedId!.isNotEmpty) {
          displaySubtitle = loc?.translate('chat_album') ?? 'Album';
        } else {
          final msgType = chat.lastMessageType?.toLowerCase();
          if (msgType == 'photo' || msgType == 'image') {
            displaySubtitle = loc?.translate('chat_photo') ?? 'Photo';
          } else if (msgType == 'video') {
            displaySubtitle = loc?.translate('chat_video') ?? 'Video';
          } else if (msgType == 'album') {
            displaySubtitle = loc?.translate('chat_album') ?? 'Album';
          } else if (msgType == 'voice' || msgType == 'audio') {
            displaySubtitle =
                loc?.translate('chat_voice_message') ?? 'Voice message';
          } else if (msgType == 'file') {
            displaySubtitle = loc?.translate('chat_file') ?? 'File';
          }
        }
      }
    }

    if (displaySubtitle == null || displaySubtitle.trim().isEmpty) {
      return null;
    }

    final themeExt = Theme.of(context).extension<TheavThemeExtension>();
    final subtitleColor = hasUnread
        ? (themeExt?.palette.chatSubtitleUnread ??
            Theme.of(context).colorScheme.onSurface)
        : (themeExt?.palette.chatSubtitle ??
            Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6));

    final subtitleStyle = TextStyle(
      color: subtitleColor,
      fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
      fontSize: 14,
    );
    final effectiveEntities = (displaySubtitle == chat.lastMessage)
        ? (chat.lastMessageEntities.isNotEmpty
            ? chat.lastMessageEntities
            : fallbackEntities)
        : const <MessageEntity>[];

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: EmojiUtils.buildPreviewWithCustomEmojis(
        displaySubtitle,
        style: subtitleStyle,
        entities: effectiveEntities,
        emojiSize: 16.0,
      ),
    );
  }

  String _formatChatTime(BuildContext context, String timestamp) {
    try {
      final localDateTime = DateTimeUtils.parseUtcDateTime(timestamp);
      if (localDateTime == null) return '';
      final now = DateTime.now();

      if (DateTimeUtils.isToday(localDateTime, now: now)) {
        return '${localDateTime.hour.toString().padLeft(2, '0')}:${localDateTime.minute.toString().padLeft(2, '0')}';
      } else if (DateTimeUtils.isYesterday(localDateTime, now: now)) {
        return _tr(context, 'date_yesterday', 'Вчера');
      } else {
        final days = DateTimeUtils.startOfDay(now)
            .difference(DateTimeUtils.startOfDay(localDateTime))
            .inDays;
        if (days < 7 && days > 0 && AppLocalizations.of(context) != null) {
          return DateTimeUtils.formatWeekday(localDateTime.weekday, context);
        }
        return '${localDateTime.day}.${localDateTime.month}';
      }
    } catch (_) {
      return '';
    }
  }
}
