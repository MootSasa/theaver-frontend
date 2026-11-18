import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../models/profile_customization.dart';
import '../../models/theav_theme.dart';
import '../../services/chat_service.dart';
import '../../services/peer_customization_cache.dart';
import '../../utils/date_time_utils.dart';
import '../common/peer_badges_widget.dart';
import '../user/avatar_with_status.dart';
import '../user/emoji_status_badge.dart';
import 'message_bubble.dart';

/// Whether two adjacent messages belong to the same continuous sender visual cluster
/// (non-system, matching sender / anonymous admin persona & admin title, same local
/// calendar day, within 5 minutes).
bool areMessagesInSameSenderCluster(Message a, Message b) {
  if (a.messageType == 'system' || b.messageType == 'system') return false;
  if (a.isFromAnonymousAdmin != b.isFromAnonymousAdmin) return false;
  if ((a.senderAdminTitle ?? '').trim() != (b.senderAdminTitle ?? '').trim()) {
    return false;
  }
  if (a.isFromAnonymousAdmin) {
    // Anonymous admin messages may carry senderId == "0" or "" when masked;
    // keep distinct if non-empty IDs or masked sender names differ.
    if (a.senderId != b.senderId) return false;
    if (a.senderName != b.senderName) return false;
  } else {
    if (a.senderId.isEmpty || a.senderId != b.senderId) return false;
  }
  final dtA = DateTimeUtils.parseUtcDateTime(a.createdAt)?.toLocal();
  final dtB = DateTimeUtils.parseUtcDateTime(b.createdAt)?.toLocal();
  if (dtA == null || dtB == null) return false;
  if (dtA.year != dtB.year || dtA.month != dtB.month || dtA.day != dtB.day) {
    return false;
  }
  return dtA.difference(dtB).abs() <= const Duration(minutes: 5);
}

/// Returns true if [current] starts a sender cluster (its header name + badges should show).
bool isFirstInSenderCluster({
  required Message current,
  Message? olderNeighbor,
}) {
  if (olderNeighbor == null) return true;
  return !areMessagesInSameSenderCluster(olderNeighbor, current);
}

/// Returns true if [current] ends a sender cluster (its 34dp avatar should show beside the bottom edge).
bool isLastInSenderCluster({
  required Message current,
  Message? newerNeighbor,
}) {
  if (newerNeighbor == null) return true;
  return !areMessagesInSameSenderCluster(current, newerNeighbor);
}

/// Clickable sender header rendered at the top of the first bubble in a group/channel cluster:
/// Colored Name + Emoji Status + Single Badge (or BOT/Verified) on left, and optional
/// flush-right muted 11sp rank/title (`adminTitle`, `владелец`, or `админ`).
class SenderHeaderRow extends StatelessWidget {
  final String senderName;
  final Color nameColor;
  final PeerCustomization? customization;
  final bool isBot;
  final bool isVerified;
  final String? adminTitle;
  final String? role;
  final Color? rankColor;
  final VoidCallback? onTapSender;

  const SenderHeaderRow({
    super.key,
    required this.senderName,
    required this.nameColor,
    this.customization,
    this.isBot = false,
    this.isVerified = false,
    this.adminTitle,
    this.role,
    this.rankColor,
    this.onTapSender,
  });

  String? get _resolvedRankLabel {
    final trimmed = adminTitle?.trim() ?? '';
    if (trimmed.isNotEmpty) return trimmed;
    if (role == 'owner') return 'владелец';
    if (role == 'admin') return 'админ';
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final status = customization?.activeEmojiStatus;
    final badge = customization?.visibleBadge;
    final rankLabel = _resolvedRankLabel;
    final theme = Theme.of(context);
    final themeExt = theme.extension<TheavThemeExtension>();
    final Color effectiveRankColor = rankColor ??
        (themeExt?.palette.chatBubbleIncomingText ?? theme.colorScheme.onSurface)
            .withValues(alpha: 0.65);

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTapSender,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Flexible(
                  child: Text(
                    senderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: nameColor,
                    ),
                  ),
                ),
                if (status != null) ...[
                  const SizedBox(width: 4),
                  EmojiStatusBadge(
                    status: status,
                    size: 15,
                    animate: false,
                    interactive: true,
                    fallbackColor: nameColor,
                  ),
                ],
                PeerBadgesRow(
                  isBot: isBot,
                  isVerified: isVerified,
                  badge: badge,
                  interactiveBadge: true,
                  verifiedIconSize: 14,
                  accentColor: nameColor,
                ),
              ],
            ),
          ),
          if (rankLabel != null) ...[
            const SizedBox(width: 8),
            Text(
              rankLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w500,
                color: effectiveRankColor,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Telegram-style incoming group/channel/community row with a 40dp left avatar gutter
/// (`34dp` avatar + `6dp` spacing) placed outside the message bubble's `MetaData` box.
class GroupMessageAvatarRow extends StatelessWidget {
  final Widget child;
  final String senderId;
  final String senderName;
  final String? senderAvatarUrl;
  final bool showAvatar;
  final PeerCustomization? customizationOverride;
  final VoidCallback? onAvatarTap;
  final double avatarRadius;
  final bool isSelectionMode;
  final bool isSelected;
  final bool isHighlighted;
  final bool isFromAnonymousAdmin;
  final String? groupAvatarUrl;
  final String? groupName;
  final VoidCallback? onTapGroupAvatar;

  const GroupMessageAvatarRow({
    super.key,
    required this.child,
    required this.senderId,
    required this.senderName,
    this.senderAvatarUrl,
    this.showAvatar = true,
    this.customizationOverride,
    this.onAvatarTap,
    this.avatarRadius = 17.0,
    this.isSelectionMode = false,
    this.isSelected = false,
    this.isHighlighted = false,
    this.isFromAnonymousAdmin = false,
    this.groupAvatarUrl,
    this.groupName,
    this.onTapGroupAvatar,
  });

  static const double gutterWidth = 40.0;

  @override
  Widget build(BuildContext context) {
    PeerCustomization? cached;
    if (!isFromAnonymousAdmin) {
      try {
        cached = context.select<PeerCustomizationCache?, PeerCustomization?>(
          (cache) => senderId.isNotEmpty ? cache?.getSync(senderId) : null,
        );
      } catch (_) {
        cached = senderId.isNotEmpty
            ? PeerCustomizationCache.instance.getSync(senderId)
            : null;
      }
    }

    final effectiveCustomization =
        isFromAnonymousAdmin ? null : (cached ?? customizationOverride);
    final effectiveAvatarUrl = isFromAnonymousAdmin
        ? ((groupAvatarUrl != null && groupAvatarUrl!.isNotEmpty)
            ? groupAvatarUrl
            : senderAvatarUrl)
        : senderAvatarUrl;
    final effectiveName = isFromAnonymousAdmin
        ? ((groupName != null && groupName!.isNotEmpty)
            ? groupName!
            : senderName)
        : senderName;
    final effectiveTap =
        isFromAnonymousAdmin ? (onTapGroupAvatar ?? onAvatarTap) : onAvatarTap;

    final diameter = avatarRadius * 2;
    final themeExt = Theme.of(context).extension<TheavThemeExtension>();
    final Color rowHighlightColor = themeExt?.palette.messageSelectionOverlay ??
        Theme.of(context).colorScheme.primary.withValues(alpha: 0.18);

    final Widget avatarAndBubble = Padding(
      padding: const EdgeInsets.only(left: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 4.0),
            child: SizedBox(
              width: diameter,
              child: showAvatar
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: effectiveTap,
                      child: AvatarWithStatus(
                        userId: isFromAnonymousAdmin ? null : senderId,
                        avatarUrl: effectiveAvatarUrl,
                        name: effectiveName,
                        radius: avatarRadius,
                        isOnline: false,
                        decorationOverride:
                            effectiveCustomization?.avatarDecoration,
                        showDecoration: !isFromAnonymousAdmin,
                        animateDecoration: false,
                      ),
                    )
                  : const SizedBox.shrink(),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(child: child),
        ],
      ),
    );

    final Widget rowContent = isSelectionMode
        ? Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.only(left: 10.0, right: 2.0),
                child: MessageSelectionCheckbox(isSelected: isSelected),
              ),
              Expanded(child: avatarAndBubble),
            ],
          )
        : avatarAndBubble;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      width: double.infinity,
      color: (isSelected || isHighlighted)
          ? rowHighlightColor
          : Colors.transparent,
      child: rowContent,
    );
  }
}
