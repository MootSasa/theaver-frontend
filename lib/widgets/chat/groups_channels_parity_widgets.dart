import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../services/chat_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/groups_channels_parity_service.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/haptic_utils.dart';
import '../common/peer_badges_widget.dart';
import '../design_system/theav_design_system.dart';
import '../user/avatar_with_status.dart';

/// Compact circular avatar pill in chat/comment composers allowing admins who
/// own channels to toggle posting as themselves or as an administered channel.
class SendAsPeerSelectorPill extends StatelessWidget {
  final List<SendAsPeer> peers;
  final SendAsPeer? selectedPeer;
  final VoidCallback? onTap;
  final double size;

  const SendAsPeerSelectorPill({
    super.key,
    required this.peers,
    this.selectedPeer,
    this.onTap,
    this.size = 34.0,
  });

  @override
  Widget build(BuildContext context) {
    if (peers.length <= 1) return const SizedBox.shrink();
    final palette = context.theav;
    final active = selectedPeer ?? peers.first;
    final tooltipText = active.isChannel
        ? 'От имени канала: ${active.name}'
        : 'От своего имени: ${active.name}';

    return Tooltip(
      message: tooltipText,
      child: GestureDetector(
        onTap: onTap == null
            ? null
            : () {
                HapticUtils.selection();
                onTap!();
              },
        behavior: HitTestBehavior.opaque,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Container(
              width: size,
              height: size,
              padding: const EdgeInsets.all(1.5),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: active.isChannel
                      ? palette.primary
                      : palette.divider,
                  width: active.isChannel ? 1.5 : 0.8,
                ),
              ),
              child: AvatarWithStatus(
                avatarUrl: active.avatarUrl,
                name: active.name.isNotEmpty ? active.name : '?',
                radius: (size - 4) / 2,
                isOnline: false,
                showDecoration: false,
                animateDecoration: false,
              ),
            ),
            Positioned(
              right: -2,
              bottom: -2,
              child: Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: palette.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: palette.divider, width: 0.5),
                ),
                alignment: Alignment.center,
                child: active.isChannel
                    ? iconoir.Megaphone(
                        width: 8,
                        height: 8,
                        color: palette.primary,
                      )
                    : iconoir.NavArrowDown(
                        width: 9,
                        height: 9,
                        color: palette.subtext,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Opens a Telegram-style sheet to pick the posting identity ("Send As")
/// for a group or channel comment thread, persisting selection on the server.
Future<SendAsPeer?> showSendAsPeerSheet({
  required BuildContext context,
  required String chatId,
  required List<SendAsPeer> peers,
  String? selectedSendAsChatId,
}) async {
  if (peers.isEmpty) return null;
  final palette = context.theav;
  final currentId = selectedSendAsChatId ?? '';

  final picked = await showTheavModalSheet<SendAsPeer>(
    context: context,
    title: 'Отправлять сообщения как...',
    builder: (ctx) => SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
      child: TheavInsetGroup(
        footer:
            'Выбранный профиль будет использоваться для ваших сообщений в этом чате.',
        children: [
          for (final peer in peers)
            TheavListRow(
              leading: AvatarWithStatus(
                avatarUrl: peer.avatarUrl,
                name: peer.name,
                radius: 20,
                isOnline: false,
                showDecoration: false,
              ),
              titleWidget: Row(
                children: [
                  Flexible(
                    child: Text(
                      peer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.onSurface,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (peer.isVerified) ...[
                    const SizedBox(width: 5),
                    const PeerBadgesRow(isVerified: true, iconSize: 14),
                  ],
                ],
              ),
              subtitle: peer.isChannel
                  ? (peer.username.isNotEmpty
                      ? 'Канал · @${peer.username}'
                      : 'Публикации от имени канала')
                  : 'Личный аккаунт',
              trailing: TheavCheckCircle(
                selected: peer.isChannel
                    ? currentId == (peer.chatId ?? peer.id)
                    : currentId.isEmpty,
              ),
              onTap: () => Navigator.pop(ctx, peer),
            ),
        ],
      ),
    ),
  );

  if (picked == null) return null;
  final nextSendAsId = picked.isChannel ? (picked.chatId ?? picked.id) : null;
  final ok = await GroupsChannelsParityService.setSendAsPeer(
    chatId,
    nextSendAsId,
  );
  if (!ok) {
    if (context.mounted) {
      GlassToastService().showError(
        context,
        'Не удалось изменить профиль отправки',
      );
    }
    return null;
  }
  return picked;
}

/// Stacked circular `@` (unread mentions/replies) and `♡` (unread reactions)
/// jump FABs positioned above the scroll-to-bottom FAB in group chats.
class UnreadJumpFabsColumn extends StatelessWidget {
  final int unreadMentionsCount;
  final int unreadReactionsCount;
  final VoidCallback? onMentionsTap;
  final VoidCallback? onMentionsLongPress;
  final VoidCallback? onReactionsTap;
  final VoidCallback? onReactionsLongPress;

  const UnreadJumpFabsColumn({
    super.key,
    required this.unreadMentionsCount,
    required this.unreadReactionsCount,
    this.onMentionsTap,
    this.onMentionsLongPress,
    this.onReactionsTap,
    this.onReactionsLongPress,
  });

  @override
  Widget build(BuildContext context) {
    if (unreadMentionsCount <= 0 && unreadReactionsCount <= 0) {
      return const SizedBox.shrink();
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (unreadReactionsCount > 0) ...[
          _UnreadJumpFab(
            key: const ValueKey('unread_reactions_fab'),
            count: unreadReactionsCount,
            onTap: onReactionsTap,
            onLongPress: onReactionsLongPress,
            tooltip: 'Перейти к реакции (удерживайте чтобы прочитать все)',
            iconBuilder: (color) => iconoir.Heart(
              width: 20,
              height: 20,
              color: color,
            ),
          ),
          if (unreadMentionsCount > 0) const SizedBox(height: 10),
        ],
        if (unreadMentionsCount > 0)
          _UnreadJumpFab(
            key: const ValueKey('unread_mentions_fab'),
            count: unreadMentionsCount,
            onTap: onMentionsTap,
            onLongPress: onMentionsLongPress,
            tooltip: 'Перейти к упоминанию (удерживайте чтобы прочитать все)',
            iconBuilder: (color) => iconoir.AtSign(
              width: 20,
              height: 20,
              color: color,
            ),
          ),
      ],
    );
  }
}

class _UnreadJumpFab extends StatelessWidget {
  final int count;
  final Widget Function(Color color) iconBuilder;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final String tooltip;

  const _UnreadJumpFab({
    super.key,
    required this.count,
    required this.iconBuilder,
    this.onTap,
    this.onLongPress,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    return Tooltip(
      message: tooltip,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          SizedBox(
            width: 46,
            height: 46,
            child: TheavFloatingSurface(
              borderRadius: 23,
              child: Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: BorderRadius.circular(23),
                  onTap: () {
                    HapticUtils.selection();
                    onTap?.call();
                  },
                  onLongPress: () {
                    HapticUtils.impact();
                    onLongPress?.call();
                  },
                  child: Center(
                    child: iconBuilder(palette.primary),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: -5,
            right: -3,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5.5, vertical: 2),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              decoration: BoxDecoration(
                color: palette.primary,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: palette.surface, width: 1.5),
              ),
              child: Center(
                child: Text(
                  count > 99 ? '99+' : '$count',
                  style: TextStyle(
                    color: palette.onPrimary,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Compact horizontal topic switcher strip inside a Forum topic screen.
class ForumTopicChipStrip extends StatelessWidget {
  final List<ForumTopic> topics;
  final int activeTopicId;
  final ValueChanged<ForumTopic> onSelectTopic;
  final VoidCallback? onViewAllTopics;

  const ForumTopicChipStrip({
    super.key,
    required this.topics,
    required this.activeTopicId,
    required this.onSelectTopic,
    this.onViewAllTopics,
  });

  @override
  Widget build(BuildContext context) {
    if (topics.isEmpty) return const SizedBox.shrink();
    final palette = context.theav;

    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: topics.length + (onViewAllTopics != null ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          if (onViewAllTopics != null && index == topics.length) {
            return TheavFloatingPillButton(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              label: 'Все темы',
              onTap: onViewAllTopics,
            );
          }
          final topic = topics[index];
          final selected = topic.id == activeTopicId;
          final badgeColor = Color(topic.iconColor | 0xFF000000);
          return GestureDetector(
            onTap: () {
              HapticUtils.selection();
              onSelectTopic(topic);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 170),
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? palette.primary.withValues(alpha: 0.16)
                    : palette.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: selected ? palette.primary : palette.divider,
                  width: selected ? 1.0 : 0.5,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (topic.iconEmoji != null && topic.iconEmoji!.isNotEmpty)
                    Text(topic.iconEmoji!, style: const TextStyle(fontSize: 13))
                  else
                    Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: badgeColor.withValues(alpha: 0.22),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '#',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                          color: badgeColor,
                        ),
                      ),
                    ),
                  const SizedBox(width: 6),
                  Text(
                    topic.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected ? palette.primary : palette.onSurface,
                    ),
                  ),
                  if (topic.unreadCount > 0) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: palette.unreadBadge,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        '${topic.unreadCount}',
                        style: TextStyle(
                          color: palette.unreadBadgeText,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Modal sheet displaying public channels similar to [chatId] with quick subscribe/open.
Future<void> showSimilarChannelsSheet({
  required BuildContext context,
  required String chatId,
  ValueChanged<SimilarChannelItem>? onOpenChannel,
}) async {
  await showTheavModalSheet<void>(
    context: context,
    title: 'Похожие каналы',
    builder: (ctx) => _SimilarChannelsSheetBody(
      chatId: chatId,
      onOpenChannel: onOpenChannel,
    ),
  );
}

class _SimilarChannelsSheetBody extends StatefulWidget {
  final String chatId;
  final ValueChanged<SimilarChannelItem>? onOpenChannel;

  const _SimilarChannelsSheetBody({
    required this.chatId,
    this.onOpenChannel,
  });

  @override
  State<_SimilarChannelsSheetBody> createState() =>
      _SimilarChannelsSheetBodyState();
}

class _SimilarChannelsSheetBodyState extends State<_SimilarChannelsSheetBody> {
  List<SimilarChannelItem> _channels = [];
  final Set<String> _joiningIds = <String>{};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final items = await GroupsChannelsParityService.getSimilarChannels(
      widget.chatId,
      limit: 25,
    );
    if (!mounted) return;
    setState(() {
      _channels = items;
      _loading = false;
    });
  }

  Future<void> _joinOrOpen(SimilarChannelItem item) async {
    if (item.isMember) {
      Navigator.pop(context);
      widget.onOpenChannel?.call(item);
      return;
    }
    if (_joiningIds.contains(item.id)) return;
    setState(() => _joiningIds.add(item.id));
    final res = await ChatService.joinPublicChat(item.id);
    if (!mounted) return;
    setState(() => _joiningIds.remove(item.id));
    if (res['success'] == true) {
      final idx = _channels.indexWhere((c) => c.id == item.id);
      if (idx != -1) {
        setState(() {
          _channels[idx] = _channels[idx].copyWith(
            isMember: true,
            subscriberCount: _channels[idx].subscriberCount + 1,
          );
        });
      }
      GlassToastService().show(context, 'Вы подписались на «${item.name}»');
    } else {
      GlassToastService().showError(
        context,
        res['message']?.toString() ?? 'Не удалось подписаться',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 42),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.2)),
      );
    }
    if (_channels.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            iconoir.Megaphone(width: 36, height: 36, color: palette.subtext),
            const SizedBox(height: 12),
            Text(
              'Похожих каналов пока не найдено',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Рекомендации формируются автоматически по пересечению аудитории публичных каналов.',
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.subtext, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
      child: TheavInsetGroup(
        children: [
          for (final ch in _channels)
            TheavListRow(
              leading: AvatarWithStatus(
                avatarUrl: ch.avatarUrl,
                name: ch.name,
                radius: 22,
                isOnline: false,
                showDecoration: false,
              ),
              titleWidget: Row(
                children: [
                  Flexible(
                    child: Text(
                      ch.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.onSurface,
                        fontSize: 15.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (ch.isVerified) ...[
                    const SizedBox(width: 5),
                    const PeerBadgesRow(isVerified: true, iconSize: 14),
                  ],
                ],
              ),
              subtitle:
                  '${ch.subscriberCount} подп.${ch.username.isNotEmpty ? ' · @${ch.username}' : ''}',
              trailing: TheavFloatingPillButton(
                height: 32,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                isPrimary: !ch.isMember,
                enabled: !_joiningIds.contains(ch.id),
                label: ch.isMember ? 'Открыть' : 'Подписаться',
                onTap: () => _joinOrOpen(ch),
              ),
              onTap: widget.onOpenChannel != null
                  ? () {
                      Navigator.pop(context);
                      widget.onOpenChannel!(ch);
                    }
                  : () => _joinOrOpen(ch),
            ),
        ],
      ),
    );
  }
}

/// Paginated sheet showing members who joined via [linkItem].
Future<void> showInviteLinkImportersSheet({
  required BuildContext context,
  required String chatId,
  required InviteLinkItem linkItem,
}) async {
  final title = linkItem.title.trim().isNotEmpty
      ? 'Перешли: ${linkItem.title}'
      : 'Приглашённые по ссылке';
  await showTheavModalSheet<void>(
    context: context,
    title: title,
    builder: (ctx) => _InviteLinkImportersBody(
      chatId: chatId,
      linkItem: linkItem,
    ),
  );
}

class _InviteLinkImportersBody extends StatefulWidget {
  final String chatId;
  final InviteLinkItem linkItem;

  const _InviteLinkImportersBody({
    required this.chatId,
    required this.linkItem,
  });

  @override
  State<_InviteLinkImportersBody> createState() =>
      _InviteLinkImportersBodyState();
}

class _InviteLinkImportersBodyState extends State<_InviteLinkImportersBody> {
  final List<InviteLinkImporter> _items = [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _total = 0;

  @override
  void initState() {
    super.initState();
    _load(reset: true);
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loadingMore || !_hasMore)) return;
    if (reset) {
      setState(() => _loading = true);
    } else {
      setState(() => _loadingMore = true);
    }
    final res = await GroupsChannelsParityService.getInviteLinkImporters(
      widget.chatId,
      widget.linkItem.id,
      limit: 50,
      offset: reset ? 0 : _items.length,
    );
    if (!mounted) return;
    setState(() {
      if (reset) _items.clear();
      _items.addAll(res.importers);
      _total = res.total;
      _hasMore = res.hasMore;
      _loading = false;
      _loadingMore = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2.2)),
      );
    }
    if (_items.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 34),
        child: Text(
          'По этой ссылке пока никто не присоединился.',
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.subtext, fontSize: 14),
        ),
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TheavInsetGroup(
            header: 'ВСТУПИЛО: $_total',
            children: [
              for (final imp in _items)
                TheavListRow(
                  leading: AvatarWithStatus(
                    userId: imp.userId,
                    avatarUrl: imp.avatarUrl,
                    name: imp.displayName.isNotEmpty
                        ? imp.displayName
                        : '@${imp.username}',
                    radius: 20,
                    isOnline: false,
                  ),
                  title: imp.displayName.isNotEmpty
                      ? imp.displayName
                      : '@${imp.username}',
                  subtitle: [
                    if (imp.username.isNotEmpty) '@${imp.username}',
                    if (imp.joinedAt != null)
                      DateTimeUtils.formatTimeHHmm(imp.joinedAt),
                  ].join(' · '),
                  trailing: imp.viaJoinRequest
                      ? Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: palette.primary.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            'По заявке',
                            style: TextStyle(
                              color: palette.primary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        )
                      : null,
                ),
            ],
          ),
          if (_hasMore)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TheavFloatingPillButton(
                label: _loadingMore ? 'Загрузка...' : 'Загрузить ещё',
                enabled: !_loadingMore,
                onTap: () => _load(reset: false),
              ),
            ),
        ],
      ),
    );
  }
}

/// CustomPainter chart rendering daily joined vs left subscriber series for
/// [ChannelStatsScreen] without external charting dependencies.
class ChannelGrowthChart extends StatelessWidget {
  final List<ChannelDailyGrowthPoint> points;
  final double height;

  const ChannelGrowthChart({
    super.key,
    required this.points,
    this.height = 176,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    if (points.isEmpty) {
      return SizedBox(
        height: 96,
        child: Center(
          child: Text(
            'Недостаточно данных за период',
            style: TextStyle(color: palette.subtext, fontSize: 13),
          ),
        ),
      );
    }

    const joinedColor = Color(0xFF34C759);
    const leftColor = Color(0xFFFF453A);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              _legendDot(joinedColor, 'Присоединились', palette.subtext),
              const SizedBox(width: 16),
              _legendDot(leftColor, 'Покинули', palette.subtext),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: height,
            child: CustomPaint(
              painter: _ChannelGrowthPainter(
                points: points,
                joinedColor: joinedColor,
                leftColor: leftColor,
                gridColor: palette.divider,
                labelColor: palette.subtext,
              ),
              child: const SizedBox.expand(),
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _shortDate(points.first.date),
                style: TextStyle(fontSize: 11, color: palette.subtext),
              ),
              if (points.length > 2)
                Text(
                  _shortDate(points[points.length ~/ 2].date),
                  style: TextStyle(fontSize: 11, color: palette.subtext),
                ),
              Text(
                _shortDate(points.last.date),
                style: TextStyle(fontSize: 11, color: palette.subtext),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _shortDate(String iso) {
    if (iso.length >= 10) {
      return '${iso.substring(8, 10)}.${iso.substring(5, 7)}';
    }
    return iso;
  }

  Widget _legendDot(Color c, String label, Color textColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: c, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: textColor,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}

class _ChannelGrowthPainter extends CustomPainter {
  final List<ChannelDailyGrowthPoint> points;
  final Color joinedColor;
  final Color leftColor;
  final Color gridColor;
  final Color labelColor;

  _ChannelGrowthPainter({
    required this.points,
    required this.joinedColor,
    required this.leftColor,
    required this.gridColor,
    required this.labelColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (points.isEmpty) return;

    int maxVal = 1;
    for (final p in points) {
      maxVal = math.max(maxVal, math.max(p.joined, p.left));
    }

    const leftPad = 26.0;
    const topPad = 8.0;
    const bottomPad = 8.0;
    final chartW = (size.width - leftPad - 6).clamp(1.0, size.width);
    final chartH = (size.height - topPad - bottomPad).clamp(1.0, size.height);

    final gridPaint = Paint()
      ..color = gridColor
      ..strokeWidth = 0.6;

    for (int step = 0; step <= 2; step++) {
      final frac = step / 2.0;
      final y = topPad + chartH * (1.0 - frac);
      canvas.drawLine(
        Offset(leftPad, y),
        Offset(leftPad + chartW, y),
        gridPaint,
      );
      final val = (maxVal * frac).round();
      final tp = TextPainter(
        text: TextSpan(
          text: '$val',
          style: TextStyle(color: labelColor, fontSize: 10),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, Offset(0, y - tp.height / 2));
    }

    void drawSeries(List<int> values, Color color) {
      final path = Path();
      final fillPath = Path();
      final n = values.length;
      final stepX = n > 1 ? chartW / (n - 1) : 0.0;
      final offsets = <Offset>[];

      for (int i = 0; i < n; i++) {
        final x = n == 1 ? leftPad + chartW / 2 : leftPad + i * stepX;
        final y = topPad + chartH * (1.0 - (values[i] / maxVal));
        offsets.add(Offset(x, y));
      }

      if (offsets.length == 1) {
        canvas.drawCircle(offsets.first, 4.0, Paint()..color = color);
        return;
      }

      path.moveTo(offsets.first.dx, offsets.first.dy);
      fillPath.moveTo(offsets.first.dx, topPad + chartH);
      fillPath.lineTo(offsets.first.dx, offsets.first.dy);

      for (int i = 0; i < offsets.length - 1; i++) {
        final p0 = offsets[i];
        final p1 = offsets[i + 1];
        final midX = (p0.dx + p1.dx) / 2;
        path.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
        fillPath.cubicTo(midX, p0.dy, midX, p1.dy, p1.dx, p1.dy);
      }

      fillPath.lineTo(offsets.last.dx, topPad + chartH);
      fillPath.close();

      canvas.drawPath(
        fillPath,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.22),
              color.withValues(alpha: 0.01),
            ],
          ).createShader(Rect.fromLTWH(leftPad, topPad, chartW, chartH)),
      );

      canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..strokeWidth = 2.2
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round,
      );
    }

    drawSeries(points.map((e) => e.left).toList(), leftColor);
    drawSeries(points.map((e) => e.joined).toList(), joinedColor);
  }

  @override
  bool shouldRepaint(covariant _ChannelGrowthPainter oldDelegate) =>
      oldDelegate.points != points ||
      oldDelegate.joinedColor != joinedColor ||
      oldDelegate.leftColor != leftColor;
}
