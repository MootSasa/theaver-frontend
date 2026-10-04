import '../../models/theav_theme.dart';
import '../../utils/image_utils.dart';
import '../../utils/emoji_utils.dart';
import '../../utils/date_time_utils.dart';
import '../../l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'round_video_thumbnail.dart';

class ChatListItem extends StatelessWidget {
  final String chatName;
  final String lastMessage;
  final DateTime lastMessageTime;
  final String avatarUrl;
  final bool isOnline;
  final bool isGroup;
  final bool isRoundVideo;
  final String? videoUrl;
  final int unreadCount;
  final VoidCallback onTap;

  const ChatListItem({
    Key? key,
    required this.chatName,
    required this.lastMessage,
    required this.lastMessageTime,
    required this.avatarUrl,
    required this.isOnline,
    required this.isGroup,
    this.isRoundVideo = false,
    this.videoUrl,
    this.unreadCount = 0,
    required this.onTap,
  }) : super(key: key);

  String _formatTime(DateTime time) {
    final localTime = time.toLocal();
    final now = DateTime.now();

    if (DateTimeUtils.isToday(localTime, now: now)) {
      return '${localTime.hour.toString().padLeft(2, '0')}:${localTime.minute.toString().padLeft(2, '0')}';
    } else if (DateTimeUtils.isYesterday(localTime, now: now)) {
      return 'Yesterday';
    } else {
      return '${localTime.day}/${localTime.month}/${localTime.year}';
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasUnread = unreadCount > 0;
    final theme = Theme.of(context);
    final themeExt = theme.extension<TheavThemeExtension>();
    final p = themeExt?.palette;
    final primaryColor = p?.primary ?? theme.colorScheme.primary;
    final onPrimaryColor = p?.onPrimary ?? theme.colorScheme.onPrimary;
    final onlineColor = p?.onlineIndicator ?? const Color(0xFF4CAF50);
    final surfaceColor = p?.surface ?? theme.colorScheme.surface;
    final subtextColor = p?.subtext ?? (theme.brightness == Brightness.dark ? Colors.white60 : Colors.grey[600]!);
    final unreadBg = p?.unreadBadge ?? primaryColor;
    final unreadText = p?.unreadBadgeText ?? onPrimaryColor;
    
    return ListTile(
      onTap: onTap,
      leading: Stack(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: primaryColor,
            backgroundImage: avatarImageProvider(avatarUrl),
            onBackgroundImageError: (_, __) {},
            child: avatarImageProvider(avatarUrl) == null
                ? Text(
                    chatName.isNotEmpty ? chatName[0].toUpperCase() : '?',
                    style: TextStyle(color: onPrimaryColor, fontWeight: FontWeight.bold),
                  )
                : null,
          ),
          if (!isGroup && isOnline)
            Positioned(
              bottom: 0,
              right: 0,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: onlineColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: surfaceColor, width: 2),
                ),
              ),
            ),
        ],
      ),
      title: Row(
        children: [
          Expanded(
            child: Text(
              chatName,
              style: TextStyle(
                fontWeight: hasUnread ? FontWeight.w600 : FontWeight.normal,
                fontSize: 16,
                color: p?.onSurface,
              ),
            ),
          ),
          if (hasUnread)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: unreadBg,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                unreadCount > 99 ? '99+' : unreadCount.toString(),
                style: TextStyle(
                  color: unreadText,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
        ],
      ),
      subtitle: Row(
        children: [
          if (isRoundVideo) ...[
            RoundVideoThumbnail(
              videoUrl: videoUrl,
              size: 18,
            ),
            const SizedBox(width: 6),
          ],
          Expanded(
            child: isRoundVideo
                ? Text(
                    (lastMessage.isNotEmpty &&
                            lastMessage != 'Видеосообщение' &&
                            lastMessage != 'Video message')
                        ? lastMessage
                        : (AppLocalizations.of(context)
                                ?.translate('chat_video_note') ??
                            'Video message'),
                    style: TextStyle(
                      color: unreadBg,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  )
                : RichText(
                    text: EmojiUtils.buildEmojiTextSpan(
                      lastMessage,
                      style: TextStyle(
                        color: hasUnread ? (p?.onSurface ?? Colors.grey[800]) : subtextColor,
                        fontSize: 14,
                        fontWeight: hasUnread ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
          ),
          const SizedBox(width: 8),
          Text(
            _formatTime(lastMessageTime),
            style: TextStyle(
              fontSize: 12,
              color: hasUnread ? unreadBg : subtextColor,
            ),
          ),
        ],
      ),
    );
  }
}