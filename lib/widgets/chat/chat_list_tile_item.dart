import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';

import '../../config/app_config.dart';
import '../../l10n/app_localizations.dart';
import '../../models/chat_draft.dart';
import '../../models/profile_customization.dart';
import '../../models/theav_theme.dart';
import '../../services/chat_service.dart';
import '../../services/chat_swipe_service.dart';
import '../../services/draft_service.dart';
import '../../services/peer_customization_cache.dart';
import '../../services/power_saving_provider.dart';
import '../../services/tiling_layout_controller.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/emoji_utils.dart';
import '../../utils/image_utils.dart';
import '../common/peer_badges_widget.dart';
import '../message/message_status_widget.dart';
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
/// previews, custom emojis, active call rings, group author prefixes,
/// media thumbnails, and bounded swipe actions.
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
  final bool? lastMessageIsRead;
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
    this.lastMessageIsRead,
    this.swipeOverrideAction,
    required this.onTap,
    required this.onLongPress,
    this.onSecondaryTapUp,
    this.onCreateDragPayload,
    required this.onSwipeAction,
  });

  bool get _isLastMessageOutgoing =>
      currentUserId != null &&
      currentUserId!.isNotEmpty &&
      chat.lastMessageSenderId != null &&
      chat.lastMessageSenderId != '0' &&
      chat.lastMessageSenderId == currentUserId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final hasUnread = chat.unreadCount > 0 || chat.unreadCount == -1;
    final isPrivateChat = chat.chatType == 'private';
    final isCommunity = chat.chatType == 'community';
    final isChannel = chat.chatType == 'channel';
    final isGroup = chat.chatType == 'group';

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

    final Widget baseAvatarWidget = isPrivateChat
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

    final Widget avatarWidget = chat.hasActiveCall
        ? _ActiveCallAvatarRing(
            size: avatarRadius * 2,
            accentColor: primaryColor,
            isSquareRounded: isCommunity,
            child: baseAvatarWidget,
          )
        : baseAvatarWidget;

    final Widget leadingWidget = Stack(
      clipBehavior: Clip.none,
      children: [
        AnimatedScale(
          scale: (isSelectMode && isSelected) ? 0.92 : 1.0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          child: avatarWidget,
        ),
        if (chat.hasActiveCall && !(isSelectMode && isSelected))
          Positioned(
            right: -2,
            bottom: -2,
            child: IgnorePointer(
              child: Container(
                width: 16,
                height: 16,
                decoration: BoxDecoration(
                  color: primaryColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.scaffoldBackgroundColor,
                    width: 1.5,
                  ),
                ),
                alignment: Alignment.center,
                child: const iconoir.SoundHigh(
                  width: 10,
                  height: 10,
                  color: Colors.white,
                ),
              ),
            ),
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

    final ChatDraft? rawDraft =
        _canShowDraft ? DraftService().getPublishedDraft(chat.id) : null;
    final ChatDraft? activeDraft =
        (rawDraft != null && rawDraft.isNotEmpty) ? rawDraft : null;

    final bool showOutgoingStatus =
        activeDraft == null &&
        _isLastMessageOutgoing &&
        !isChannel &&
        chat.chatType != 'saved';

    String? displayTimeIso = chat.lastMessageTime;
    if (activeDraft != null) {
      final lastDt = DateTimeUtils.parseUtcDateTime(chat.lastMessageTime);
      if (lastDt == null || activeDraft.updatedAt.isAfter(lastDt)) {
        displayTimeIso = activeDraft.updatedAt.toUtc().toIso8601String();
      }
    }

    final Widget trailingWidget = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        if (displayTimeIso != null)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showOutgoingStatus) ...[
                MessageStatusWidget(
                  isRead: lastMessageIsRead ?? (chat.lastReadOutboxMessageId > 0),
                  isOutgoing: true,
                  accentColor: primaryColor,
                ),
                const SizedBox(width: 3),
              ],
              Text(
                _formatChatTime(context, displayTimeIso),
                style: TextStyle(
                  fontSize: 12,
                  color: (hasUnread && !isMuted) ? primaryColor : Colors.grey[500],
                ),
              ),
            ],
          ),
        const SizedBox(height: 4),
        if (hasUnread ||
            chat.unreadMentionsCount > 0 ||
            chat.unreadReactionsCount > 0)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (chat.unreadMentionsCount > 0) ...[
                Container(
                  height: 18,
                  constraints: const BoxConstraints(minWidth: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: primaryColor,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Center(
                    widthFactor: 1.0,
                    heightFactor: 1.0,
                    child: Text(
                      chat.unreadMentionsCount > 99
                          ? '@ 99+'
                          : '@',
                      style: TextStyle(
                        color: theme.colorScheme.onPrimary,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
                if (chat.unreadReactionsCount > 0 || hasUnread)
                  const SizedBox(width: 4),
              ],
              if (chat.unreadReactionsCount > 0) ...[
                Container(
                  height: 18,
                  constraints: const BoxConstraints(minWidth: 18),
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: primaryColor.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: primaryColor.withValues(alpha: 0.45),
                      width: 0.8,
                    ),
                  ),
                  child: Center(
                    widthFactor: 1.0,
                    heightFactor: 1.0,
                    child: Text(
                      '♡',
                      style: TextStyle(
                        color: primaryColor,
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        height: 1.0,
                      ),
                    ),
                  ),
                ),
                if (hasUnread) const SizedBox(width: 4),
              ],
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
                ),
            ],
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

    final Color typeIconColor = hasUnread
        ? theme.colorScheme.onSurface.withValues(alpha: 0.85)
        : theme.colorScheme.onSurface.withValues(alpha: 0.65);

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
                    if (isChannel || isGroup || isCommunity)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: isChannel
                            ? iconoir.Megaphone(
                                width: 15,
                                height: 15,
                                color: typeIconColor,
                              )
                            : isCommunity
                                ? iconoir.Community(
                                    width: 15,
                                    height: 15,
                                    color: typeIconColor,
                                  )
                                : (chat.isForum
                                      ? iconoir.ChatLines(
                                          width: 15,
                                          height: 15,
                                          color: typeIconColor,
                                        )
                                      : iconoir.Group(
                                          width: 15,
                                          height: 15,
                                          color: typeIconColor,
                                        )),
                      ),
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

  bool get _canShowDraft =>
      chat.chatType != 'channel' ||
      chat.canPostInChannel ||
      chat.myRole == 'owner' ||
      chat.myRole == 'admin' ||
      chat.myRole == 'moderator';

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
        return const iconoir.Community(
          color: Colors.white,
          width: 22,
          height: 22,
        );
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

  String? _resolveGroupSenderPrefix(BuildContext context) {
    if (chat.chatType != 'group') return null;
    final msgType = chat.lastMessageType?.toLowerCase() ?? '';
    if (msgType == 'system') return null;

    if (_isLastMessageOutgoing) {
      final you = _tr(context, 'chat_reply_you', 'Вы');
      return '$you: ';
    }
    final senderName = chat.lastMessageSenderName?.trim();
    if (senderName != null && senderName.isNotEmpty) {
      return '$senderName: ';
    }
    return null;
  }

  Widget? _buildSubtitle(BuildContext context, bool hasUnread) {
    final loc = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final accentColor = isDark
        ? const Color(0xFF5CB8E6)
        : theme.colorScheme.primary;

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

    final ChatDraft? rawDraft =
        _canShowDraft ? DraftService().getPublishedDraft(chat.id) : null;
    final ChatDraft? draft =
        (rawDraft != null && rawDraft.isNotEmpty) ? rawDraft : null;
    if (draft != null) {
      final draftPrefix = loc?.translate('chat_draft') ?? 'Черновик';
      final draftText = draft.text;
      final draftStyle = TextStyle(
        color: theme.colorScheme.onSurface.withValues(alpha: 0.65),
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
              entities: draft.entities,
              emojiSize: 16.0,
            ),
          ],
        ),
      );
    }

    final String? groupPrefix = _resolveGroupSenderPrefix(context);
    final TextStyle prefixStyle = TextStyle(
      color: accentColor,
      fontWeight: FontWeight.w500,
      fontSize: 14,
    );

    if (chat.isLastMessageRoundVideo) {
      final primary = theme.colorScheme.primary;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (groupPrefix != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                groupPrefix,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: prefixStyle,
              ),
            ),
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

    final String msgTypeLower = chat.lastMessageType?.toLowerCase() ?? '';
    bool isCallPreview = false;
    bool isVideoCallPreview = false;
    String? displaySubtitle;

    if (chat.isLastMessageUnsupported) {
      displaySubtitle =
          loc?.translate('message_unsupported_preview') ?? 'Unsupported message';
    } else if (msgTypeLower == 'call') {
      isCallPreview = true;
      var formattedCall = Chat.formatCallPreview(
        chat.lastMessage,
        currentUserId: currentUserId,
      );
      if (formattedCall.startsWith('📹 ')) {
        isVideoCallPreview = true;
        formattedCall = formattedCall.substring('📹 '.length);
      } else if (formattedCall.startsWith('📞 ')) {
        formattedCall = formattedCall.substring('📞 '.length);
      }
      displaySubtitle = formattedCall;
    } else {
      displaySubtitle = chat.lastMessage;
      if (displaySubtitle == null || displaySubtitle.trim().isEmpty) {
        if (chat.lastMessageGroupedId != null &&
            chat.lastMessageGroupedId!.isNotEmpty) {
          displaySubtitle = loc?.translate('chat_album') ?? 'Album';
        } else {
          if (msgTypeLower == 'photo' || msgTypeLower == 'image') {
            displaySubtitle = loc?.translate('chat_photo') ?? 'Photo';
          } else if (msgTypeLower == 'video') {
            displaySubtitle = loc?.translate('chat_video') ?? 'Video';
          } else if (msgTypeLower == 'gif' || msgTypeLower == 'animation') {
            displaySubtitle = 'GIF';
          } else if (msgTypeLower == 'album') {
            displaySubtitle = loc?.translate('chat_album') ?? 'Album';
          } else if (msgTypeLower == 'voice' || msgTypeLower == 'audio') {
            displaySubtitle =
                loc?.translate('chat_voice_message') ?? 'Voice message';
          } else if (msgTypeLower == 'file' || msgTypeLower == 'document') {
            displaySubtitle = loc?.translate('chat_file') ?? 'File';
          } else if (msgTypeLower == 'sticker') {
            displaySubtitle = loc?.translate('chat_sticker') ?? 'Стикер';
          }
        }
      }
    }

    if (displaySubtitle == null || displaySubtitle.trim().isEmpty) {
      return null;
    }

    final themeExt = theme.extension<TheavThemeExtension>();
    final subtitleColor = hasUnread
        ? (themeExt?.palette.chatSubtitleUnread ?? theme.colorScheme.onSurface)
        : (themeExt?.palette.chatSubtitle ??
            theme.colorScheme.onSurface.withValues(alpha: 0.6));

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

    final previewSpan = EmojiUtils.buildPreviewWithCustomEmojis(
      displaySubtitle,
      style: subtitleStyle,
      entities: effectiveEntities,
      emojiSize: 16.0,
    );

    final String? rawThumbUrl = chat.lastMessageFileUrl?.trim();
    final bool hasVisualMediaThumb = rawThumbUrl != null &&
        rawThumbUrl.isNotEmpty &&
        (msgTypeLower == 'photo' ||
            msgTypeLower == 'image' ||
            msgTypeLower == 'video' ||
            msgTypeLower == 'gif' ||
            msgTypeLower == 'animation' ||
            msgTypeLower == 'album' ||
            (msgTypeLower.isEmpty &&
                chat.lastMessageGroupedId != null &&
                chat.lastMessageGroupedId!.isNotEmpty));

    if (hasVisualMediaThumb) {
      return Row(
        children: [
          if (groupPrefix != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                groupPrefix,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: prefixStyle,
              ),
            ),
          _buildMediaThumbnail(context, rawThumbUrl, msgTypeLower),
          const SizedBox(width: 5),
          Expanded(
            child: RichText(
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              text: previewSpan,
            ),
          ),
        ],
      );
    }

    if (isCallPreview) {
      return Row(
        children: [
          if (groupPrefix != null)
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 110),
              child: Text(
                groupPrefix,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: prefixStyle,
              ),
            ),
          isVideoCallPreview
              ? iconoir.VideoCamera(
                  width: 14,
                  height: 14,
                  color: subtitleColor,
                )
              : iconoir.Phone(
                  width: 14,
                  height: 14,
                  color: subtitleColor,
                ),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              displaySubtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: subtitleStyle,
            ),
          ),
        ],
      );
    }

    return RichText(
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      text: groupPrefix != null
          ? TextSpan(
              children: [
                TextSpan(text: groupPrefix, style: prefixStyle),
                previewSpan,
              ],
            )
          : previewSpan,
    );
  }

  Widget _buildMediaThumbnail(
    BuildContext context,
    String rawUrl,
    String msgTypeLower,
  ) {
    final theme = Theme.of(context);
    final resolved =
        AppConfig.resolveMediaUrl(rawUrl) ?? getValidAvatarUrl(rawUrl) ?? rawUrl;
    final isVideo = msgTypeLower == 'video';

    Widget fallback = Container(
      width: 18,
      height: 18,
      color: theme.colorScheme.primary.withValues(alpha: 0.14),
      alignment: Alignment.center,
      child: isVideo
          ? iconoir.VideoCamera(
              width: 11,
              height: 11,
              color: theme.colorScheme.primary,
            )
          : iconoir.MediaImage(
              width: 11,
              height: 11,
              color: theme.colorScheme.primary,
            ),
    );

    Widget imageWidget;
    if (resolved.startsWith('http://') || resolved.startsWith('https://')) {
      imageWidget = CachedNetworkImage(
        imageUrl: resolved,
        width: 18,
        height: 18,
        fit: BoxFit.cover,
        memCacheWidth: 54,
        memCacheHeight: 54,
        placeholder: (_, __) => fallback,
        errorWidget: (_, __, ___) => fallback,
      );
    } else if (resolved.startsWith('data:')) {
      final provider = avatarImageProvider(resolved);
      imageWidget = provider != null
          ? Image(
              image: provider,
              width: 18,
              height: 18,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => fallback,
            )
          : fallback;
    } else if (!kIsWeb && resolved.isNotEmpty) {
      try {
        final localPath = resolved.startsWith('file://')
            ? Uri.parse(resolved).toFilePath()
            : resolved;
        final file = File(localPath);
        imageWidget = file.existsSync()
            ? Image.file(
                file,
                width: 18,
                height: 18,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => fallback,
              )
            : fallback;
      } catch (_) {
        imageWidget = fallback;
      }
    } else {
      imageWidget = fallback;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(4),
      child: SizedBox(
        width: 18,
        height: 18,
        child: imageWidget,
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

class _ActiveCallAvatarRing extends StatefulWidget {
  final double size;
  final Color accentColor;
  final bool isSquareRounded;
  final Widget child;

  const _ActiveCallAvatarRing({
    required this.size,
    required this.accentColor,
    this.isSquareRounded = false,
    required this.child,
  });

  @override
  State<_ActiveCallAvatarRing> createState() => _ActiveCallAvatarRingState();
}

class _ActiveCallAvatarRingState extends State<_ActiveCallAvatarRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final disableAnimations = MediaQuery.disableAnimationsOf(context) ||
        !PowerSavingProvider.instance.allowAnimations;
    if (disableAnimations) {
      if (_controller.isAnimating) _controller.stop();
      _controller.value = 0.5;
    } else if (!_controller.isAnimating) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final secondaryAccent = Color.lerp(
      widget.accentColor,
      const Color(0xFF10B981),
      0.55,
    )!;
    final radius = widget.isSquareRounded ? 15.0 : widget.size / 2;

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final pulse = _controller.value;
              final haloAlpha = 0.28 + (0.24 * pulse);
              final ringScale = 1.0 + (0.04 * pulse);
              return Transform.scale(
                scale: ringScale,
                child: Container(
                  width: widget.size,
                  height: widget.size,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(radius),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [widget.accentColor, secondaryAccent],
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: widget.accentColor.withValues(alpha: haloAlpha),
                        blurRadius: 8,
                        spreadRadius: 0.5,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          Transform.scale(
            scale: 0.88,
            child: widget.child,
          ),
        ],
      ),
    );
  }
}
