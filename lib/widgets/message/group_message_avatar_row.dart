import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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
/// (non-system, matching sender / anonymous admin / send-as channel persona & admin title,
/// same local calendar day, within 5 minutes).
bool areMessagesInSameSenderCluster(Message a, Message b) {
  if (a.messageType == 'system' || b.messageType == 'system') return false;
  final senderChatA = (a.senderChatId ?? '').trim();
  final senderChatB = (b.senderChatId ?? '').trim();
  if (senderChatA != senderChatB) return false;
  if (a.isFromAnonymousAdmin != b.isFromAnonymousAdmin) return false;
  if ((a.senderAdminTitle ?? '').trim() != (b.senderAdminTitle ?? '').trim()) {
    return false;
  }
  if (senderChatA.isNotEmpty) {
    // Both messages are sent on behalf of the exact same channel (senderChatA == senderChatB).
    if ((a.senderChatName ?? '').trim() != (b.senderChatName ?? '').trim()) {
      return false;
    }
  } else if (a.isFromAnonymousAdmin) {
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

enum _SenderHeaderSlot {
  name,
  emojiStatus,
  badges,
  rank,
}

class _SenderHeaderParentData extends ContainerBoxParentData<RenderBox> {
  _SenderHeaderSlot? slot;
}

class _SenderHeaderChild extends ParentDataWidget<_SenderHeaderParentData> {
  final _SenderHeaderSlot slot;

  const _SenderHeaderChild({
    required this.slot,
    required super.child,
  });

  @override
  void applyParentData(RenderObject renderObject) {
    final parentData = renderObject.parentData as _SenderHeaderParentData;
    if (parentData.slot != slot) {
      parentData.slot = slot;
      final targetParent = renderObject.parent;
      if (targetParent is RenderObject) {
        targetParent.markNeedsLayout();
      }
    }
  }

  @override
  Type get debugTypicalAncestorWidgetClass => _SenderHeaderLayout;
}

class _SenderHeaderLayout extends MultiChildRenderObjectWidget {
  _SenderHeaderLayout({
    required Widget nameWidget,
    Widget? emojiStatusWidget,
    Widget? badgesWidget,
    Widget? rankWidget,
  }) : super(
          children: [
            _SenderHeaderChild(
              slot: _SenderHeaderSlot.name,
              child: nameWidget,
            ),
            if (emojiStatusWidget != null)
              _SenderHeaderChild(
                slot: _SenderHeaderSlot.emojiStatus,
                child: emojiStatusWidget,
              ),
            if (badgesWidget != null)
              _SenderHeaderChild(
                slot: _SenderHeaderSlot.badges,
                child: badgesWidget,
              ),
            if (rankWidget != null)
              _SenderHeaderChild(
                slot: _SenderHeaderSlot.rank,
                child: rankWidget,
              ),
          ],
        );

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSenderHeader();
  }
}

/// Custom intrinsic-safe layout for [SenderHeaderRow].
///
/// Avoids [LayoutBuilder] so [RenderBubbleLayout] can query min/max intrinsic
/// dimensions during bubble sizing without throwing.
class _RenderSenderHeader extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _SenderHeaderParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _SenderHeaderParentData> {
  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _SenderHeaderParentData) {
      child.parentData = _SenderHeaderParentData();
    }
  }

  ({
    RenderBox? name,
    RenderBox? status,
    RenderBox? badges,
    RenderBox? rank,
  }) _resolveSlots() {
    RenderBox? name;
    RenderBox? status;
    RenderBox? badges;
    RenderBox? rank;
    RenderBox? child = firstChild;
    while (child != null) {
      final pd = child.parentData as _SenderHeaderParentData;
      switch (pd.slot) {
        case _SenderHeaderSlot.name:
          name = child;
          break;
        case _SenderHeaderSlot.emojiStatus:
          status = child;
          break;
        case _SenderHeaderSlot.badges:
          badges = child;
          break;
        case _SenderHeaderSlot.rank:
          rank = child;
          break;
        case null:
          break;
      }
      child = pd.nextSibling;
    }
    return (name: name, status: status, badges: badges, rank: rank);
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0.0;

  @override
  double computeMaxIntrinsicWidth(double height) {
    final slots = _resolveSlots();
    double width = 0.0;
    if (slots.name != null) {
      width += slots.name!.getMaxIntrinsicWidth(height);
    }
    if (slots.status != null) {
      final double sw = slots.status!.getMaxIntrinsicWidth(height);
      if (sw > 0.0) {
        width += 4.0 + sw;
      }
    }
    if (slots.badges != null) {
      final double bw = slots.badges!.getMaxIntrinsicWidth(height);
      if (bw > 0.0) {
        width += 4.0 + bw;
      }
    }
    if (slots.rank != null) {
      final double rw = math.min(92.0, slots.rank!.getMaxIntrinsicWidth(height));
      if (rw > 0.0) {
        width += 6.0 + rw;
      }
    }
    return width;
  }

  @override
  double computeMinIntrinsicHeight(double width) {
    double maxH = 0.0;
    RenderBox? child = firstChild;
    while (child != null) {
      maxH = math.max(maxH, child.getMinIntrinsicHeight(width));
      child = (child.parentData as _SenderHeaderParentData).nextSibling;
    }
    return maxH;
  }

  @override
  double computeMaxIntrinsicHeight(double width) {
    double maxH = 0.0;
    RenderBox? child = firstChild;
    while (child != null) {
      maxH = math.max(maxH, child.getMaxIntrinsicHeight(width));
      child = (child.parentData as _SenderHeaderParentData).nextSibling;
    }
    return maxH;
  }

  @override
  void performLayout() {
    final slots = _resolveSlots();
    final double naturalMaxW = computeMaxIntrinsicWidth(double.infinity);
    final double availW = constraints.maxWidth.isFinite
        ? constraints.maxWidth
        : constraints.constrainWidth(naturalMaxW);

    if (availW <= 0.0) {
      RenderBox? child = firstChild;
      while (child != null) {
        child.layout(BoxConstraints.tight(Size.zero), parentUsesSize: true);
        final pd = child.parentData as _SenderHeaderParentData;
        pd.offset = Offset.zero;
        child = pd.nextSibling;
      }
      size = constraints.constrain(Size.zero);
      return;
    }

    double rankW = 0.0;
    bool showRank = false;
    if (slots.rank != null) {
      if (availW >= 72.0) {
        final double maxRankW = math.min(92.0, math.max(0.0, availW * 0.42));
        slots.rank!.layout(
          BoxConstraints(maxWidth: maxRankW),
          parentUsesSize: true,
        );
        rankW = slots.rank!.size.width;
        showRank = rankW > 0.0 && slots.rank!.size.height > 0.0;
      } else {
        slots.rank!.layout(
          BoxConstraints.tight(Size.zero),
          parentUsesSize: true,
        );
      }
    }

    final double rankReserved = showRank ? (6.0 + rankW) : 0.0;
    final double leftMaxW = math.max(0.0, availW - rankReserved);

    double statusW = 0.0;
    bool showStatus = false;
    if (slots.status != null) {
      if (leftMaxW >= 54.0) {
        slots.status!.layout(
          BoxConstraints(maxWidth: math.min(24.0, leftMaxW)),
          parentUsesSize: true,
        );
        statusW = slots.status!.size.width;
        showStatus = statusW > 0.0 && slots.status!.size.height > 0.0;
      } else {
        slots.status!.layout(
          BoxConstraints.tight(Size.zero),
          parentUsesSize: true,
        );
      }
    }

    final double afterStatusAvail = math.max(
      0.0,
      leftMaxW - (showStatus ? 4.0 + statusW : 0.0),
    );
    double badgesW = 0.0;
    bool showBadges = false;
    if (slots.badges != null) {
      if (leftMaxW >= 44.0 && afterStatusAvail > 0.0) {
        final double maxBadgesW = math.min(
          afterStatusAvail,
          math.max(16.0, leftMaxW * 0.48),
        );
        slots.badges!.layout(
          BoxConstraints(maxWidth: maxBadgesW),
          parentUsesSize: true,
        );
        badgesW = slots.badges!.size.width;
        showBadges = badgesW > 0.0 && slots.badges!.size.height > 0.0;
      } else {
        slots.badges!.layout(
          BoxConstraints.tight(Size.zero),
          parentUsesSize: true,
        );
      }
    }

    final double badgesGap = showBadges ? (showStatus ? 2.0 : 4.0) : 0.0;
    final double nameMaxW = math.max(
      0.0,
      afterStatusAvail - (showBadges ? badgesGap + badgesW : 0.0),
    );
    double nameW = 0.0;
    if (slots.name != null) {
      slots.name!.layout(
        BoxConstraints(maxWidth: nameMaxW),
        parentUsesSize: true,
      );
      nameW = slots.name!.size.width;
    }

    final double leftUsedW = nameW +
        (showStatus ? 4.0 + statusW : 0.0) +
        (showBadges ? badgesGap + badgesW : 0.0);
    final double totalNaturalW = leftUsedW + (showRank ? 6.0 + rankW : 0.0);

    double rowHeight = 0.0;
    if (slots.name != null) {
      rowHeight = math.max(rowHeight, slots.name!.size.height);
    }
    if (showStatus) {
      rowHeight = math.max(rowHeight, slots.status!.size.height);
    }
    if (showBadges) {
      rowHeight = math.max(rowHeight, slots.badges!.size.height);
    }
    if (showRank) {
      rowHeight = math.max(rowHeight, slots.rank!.size.height);
    }

    final double targetW = constraints.hasBoundedWidth &&
            constraints.minWidth == constraints.maxWidth
        ? constraints.maxWidth
        : constraints.constrainWidth(totalNaturalW);
    size = constraints.constrain(Size(targetW, rowHeight));

    double cursorX = 0.0;
    if (slots.name != null) {
      final pd = slots.name!.parentData as _SenderHeaderParentData;
      pd.offset = Offset(cursorX, (size.height - slots.name!.size.height) / 2);
      cursorX += nameW;
    }
    if (slots.status != null) {
      final pd = slots.status!.parentData as _SenderHeaderParentData;
      if (showStatus) {
        cursorX += 4.0;
        pd.offset = Offset(
          cursorX,
          (size.height - slots.status!.size.height) / 2,
        );
        cursorX += statusW;
      } else {
        pd.offset = Offset.zero;
      }
    }
    if (slots.badges != null) {
      final pd = slots.badges!.parentData as _SenderHeaderParentData;
      if (showBadges) {
        cursorX += badgesGap;
        pd.offset = Offset(
          cursorX,
          (size.height - slots.badges!.size.height) / 2,
        );
        cursorX += badgesW;
      } else {
        pd.offset = Offset.zero;
      }
    }
    if (slots.rank != null) {
      final pd = slots.rank!.parentData as _SenderHeaderParentData;
      if (showRank) {
        final double rankX = math.max(
          cursorX + 6.0,
          size.width - rankW,
        );
        pd.offset = Offset(
          rankX,
          (size.height - slots.rank!.size.height) / 2,
        );
      } else {
        pd.offset = Offset.zero;
      }
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    RenderBox? child = firstChild;
    while (child != null) {
      final pd = child.parentData as _SenderHeaderParentData;
      if (!child.size.isEmpty) {
        context.paintChild(child, pd.offset + offset);
      }
      child = pd.nextSibling;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    RenderBox? child = lastChild;
    while (child != null) {
      final pd = child.parentData as _SenderHeaderParentData;
      if (!child.size.isEmpty) {
        final bool isHit = result.addWithPaintOffset(
          offset: pd.offset,
          position: position,
          hitTest: (BoxHitTestResult result, Offset transformed) {
            return child!.hitTest(result, position: transformed);
          },
        );
        if (isHit) return true;
      }
      child = pd.previousSibling;
    }
    return false;
  }
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
    final bool hasAnyBadge = isBot || isVerified || badge != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTapSender,
      child: _SenderHeaderLayout(
        nameWidget: Text(
          senderName,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.bold,
            color: nameColor,
          ),
        ),
        emojiStatusWidget: status != null
            ? EmojiStatusBadge(
                status: status,
                size: 15,
                animate: false,
                interactive: true,
                fallbackColor: nameColor,
              )
            : null,
        badgesWidget: hasAnyBadge
            ? FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: PeerBadgesRow(
                  isBot: isBot,
                  isVerified: isVerified,
                  badge: badge,
                  interactiveBadge: true,
                  verifiedIconSize: 14,
                  accentColor: nameColor,
                ),
              )
            : null,
        rankWidget: rankLabel != null
            ? Text(
                rankLabel,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w500,
                  color: effectiveRankColor,
                ),
              )
            : null,
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
