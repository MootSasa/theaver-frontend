import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../../services/groups_channels_parity_service.dart';
import '../../../widgets/chat/groups_channels_parity_widgets.dart';
import '../../../widgets/design_system/theav_design_system.dart';
import '../../../widgets/settings/settings_floating_header.dart';

/// Opens a Telegram-style detailed post analytics modal sheet
/// (`GET /api/chats/:id/messages/:messageId/stats`).
Future<void> showPostStatsSheet({
  required BuildContext context,
  required String chatId,
  required String messageId,
  String? previewText,
}) async {
  await showTheavModalSheet<void>(
    context: context,
    title: 'Статистика публикации',
    builder: (ctx) => _PostStatsSheetBody(
      chatId: chatId,
      messageId: messageId,
      previewText: previewText,
    ),
  );
}

class _PostStatsSheetBody extends StatefulWidget {
  final String chatId;
  final String messageId;
  final String? previewText;

  const _PostStatsSheetBody({
    required this.chatId,
    required this.messageId,
    this.previewText,
  });

  @override
  State<_PostStatsSheetBody> createState() => _PostStatsSheetBodyState();
}

class _PostStatsSheetBodyState extends State<_PostStatsSheetBody> {
  PostStats? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final s = await GroupsChannelsParityService.getPostStats(
      widget.chatId,
      widget.messageId,
    );
    if (!mounted) return;
    setState(() {
      _stats = s;
      _loading = false;
    });
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
    final s = _stats;
    if (s == null) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 34),
        child: Text(
          'Статистика для этой публикации недоступна.',
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.subtext, fontSize: 14),
        ),
      );
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 22),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.previewText != null && widget.previewText!.trim().isNotEmpty)
            TheavInsetGroup(
              children: [
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Text(
                    widget.previewText!.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.subtext,
                      fontSize: 13.5,
                      height: 1.35,
                    ),
                  ),
                ),
              ],
            ),
          TheavInsetGroup(
            header: 'ОХВАТ И ВОВЛЕЧЁННОСТЬ',
            children: [
              TheavListRow(
                leading: iconoir.Eye(width: 20, height: 20, color: palette.primary),
                title: 'Просмотры',
                valueText: '${s.viewsCount} (уникальных: ${s.uniqueViewers})',
              ),
              TheavListRow(
                leading: iconoir.ForwardMessage(
                  width: 20,
                  height: 20,
                  color: palette.primary,
                ),
                title: 'Пересылки',
                valueText: '${s.forwardsCount}',
              ),
              TheavListRow(
                leading: iconoir.ChatBubble(
                  width: 20,
                  height: 20,
                  color: palette.primary,
                ),
                title: 'Комментарии',
                valueText: '${s.commentsCount}',
              ),
              TheavListRow(
                leading: iconoir.Heart(
                  width: 20,
                  height: 20,
                  color: palette.primary,
                ),
                title: 'Реакции',
                valueText: '${s.reactionsTotal}',
              ),
              TheavListRow(
                leading: iconoir.StatsUpSquare(
                  width: 20,
                  height: 20,
                  color: palette.primary,
                ),
                title: 'Вовлечённость (ERR)',
                valueText: '${s.engagementRate.toStringAsFixed(1)}%',
              ),
            ],
          ),
          if (s.reactionsBreakdown.isNotEmpty) ...[
            const SizedBox(height: 8),
            TheavInsetGroup(
              header: 'РЕАКЦИИ ПО ЭМОДЗИ',
              children: [
                for (final item in s.reactionsBreakdown)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    child: Row(
                      children: [
                        Text(item.emoji, style: const TextStyle(fontSize: 20)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              minHeight: 7,
                              value: s.reactionsTotal > 0
                                  ? item.count / s.reactionsTotal
                                  : 0,
                              backgroundColor: palette.divider,
                              valueColor: AlwaysStoppedAnimation<Color>(
                                palette.primary,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          '${item.count}',
                          style: TextStyle(
                            color: palette.onSurface,
                            fontWeight: FontWeight.w600,
                            fontSize: 13.5,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

/// Telegram-style Channel Analytics screen (`GET /api/chats/:id/stats`)
/// showing KPI summary cards, growth chart, and top posts.
class ChannelStatsScreen extends StatefulWidget {
  final String chatId;
  final String channelName;

  const ChannelStatsScreen({
    super.key,
    required this.chatId,
    required this.channelName,
  });

  @override
  State<ChannelStatsScreen> createState() => _ChannelStatsScreenState();
}

class _ChannelStatsScreenState extends State<ChannelStatsScreen> {
  ChannelStats? _stats;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final s = await GroupsChannelsParityService.getChannelStats(widget.chatId);
    if (!mounted) return;
    setState(() {
      _stats = s;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final s = _stats;

    return SettingsFloatingScaffold(
      title: 'Статистика канала',
      backgroundColor: palette.background,
      body: RefreshIndicator(
        onRefresh: _load,
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            0,
            SettingsFloatingHeader.topClearanceOf(context) + 12,
            0,
            MediaQuery.paddingOf(context).bottom + 36,
          ),
          children: [
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 64),
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              )
            else if (s == null)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
                child: Text(
                  'Не удалось загрузить статистику канала.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.subtext, fontSize: 14.5),
                ),
              )
            else ...[
              TheavInsetGroup(
                header: 'ОБЗОР (${widget.channelName.toUpperCase()})',
                children: [
                  TheavListRow(
                    leading: iconoir.Group(
                      width: 20,
                      height: 20,
                      color: palette.primary,
                    ),
                    title: 'Подписчики',
                    valueText: '${s.subscribersCount}',
                  ),
                  TheavListRow(
                    leading: iconoir.BellNotification(
                      width: 20,
                      height: 20,
                      color: palette.primary,
                    ),
                    title: 'Уведомления включены',
                    valueText:
                        '${s.notificationsEnabledPercent.toStringAsFixed(1)}%',
                  ),
                  TheavListRow(
                    leading: iconoir.StatsUpSquare(
                      width: 20,
                      height: 20,
                      color: palette.primary,
                    ),
                    title: 'Прирост за 7 дней',
                    valueText: '+${s.joined7d} / -${s.left7d}',
                  ),
                  TheavListRow(
                    leading: iconoir.Calendar(
                      width: 20,
                      height: 20,
                      color: palette.primary,
                    ),
                    title: 'Прирост за 30 дней',
                    valueText: '+${s.joined30d} / -${s.left30d}',
                  ),
                  TheavListRow(
                    leading: iconoir.Eye(
                      width: 20,
                      height: 20,
                      color: palette.primary,
                    ),
                    title: 'Просмотры на пост (средн.)',
                    valueText: s.avgViewsPerPost.toStringAsFixed(1),
                  ),
                  TheavListRow(
                    leading: iconoir.ForwardMessage(
                      width: 20,
                      height: 20,
                      color: palette.primary,
                    ),
                    title: 'Публикации · Пересылки · Реакции',
                    valueText:
                        '${s.postsCount} · ${s.totalForwards} · ${s.totalReactions}',
                  ),
                ],
              ),
              const SizedBox(height: 8),
              TheavInsetGroup(
                header: 'ДИНАМИКА ПОДПИСОК (14 ДНЕЙ)',
                children: [
                  ChannelGrowthChart(points: s.dailyGrowth),
                ],
              ),
              if (s.topPosts.isNotEmpty) ...[
                const SizedBox(height: 8),
                TheavInsetGroup(
                  header: 'ПОПУЛЯРНЫЕ ПУБЛИКАЦИИ',
                  children: [
                    for (final post in s.topPosts)
                      TheavListRow(
                        leading: iconoir.Post(
                          width: 20,
                          height: 20,
                          color: palette.primary,
                        ),
                        title: post.content.trim().isNotEmpty
                            ? post.content.trim()
                            : '[${post.messageType}]',
                        subtitle:
                            '${post.viewsCount} просм. · ${post.forwardsCount} перес. · ${post.commentsCount} комм. · ${post.reactionsCount} реакц.',
                        showChevron: true,
                        onTap: () => showPostStatsSheet(
                          context: context,
                          chatId: widget.chatId,
                          messageId: post.messageId,
                          previewText: post.content,
                        ),
                      ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}
