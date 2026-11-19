import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../../services/groups_channels_parity_service.dart';
import '../../../utils/date_time_utils.dart';
import '../../../utils/haptic_utils.dart';
import '../../../widgets/design_system/theav_design_system.dart';
import '../../../widgets/settings/settings_floating_header.dart';
import '../../../widgets/user/avatar_with_status.dart';

/// Recent Actions (Admin Event Log) viewer for group and channel admins
/// (`GET /api/chats/:id/admin-log`).
class AdminLogScreen extends StatefulWidget {
  final String chatId;
  final String chatName;
  final bool isChannel;

  const AdminLogScreen({
    super.key,
    required this.chatId,
    required this.chatName,
    this.isChannel = false,
  });

  @override
  State<AdminLogScreen> createState() => _AdminLogScreenState();
}

class _AdminLogScreenState extends State<AdminLogScreen> {
  static const List<({String id, String label})> _categories = [
    (id: '', label: 'Все'),
    (id: 'messages', label: 'Сообщения'),
    (id: 'members', label: 'Участники'),
    (id: 'rights', label: 'Права'),
    (id: 'settings', label: 'Настройки'),
    (id: 'invites', label: 'Ссылки'),
    (id: 'topics', label: 'Темы'),
  ];

  final TextEditingController _searchController = TextEditingController();
  final List<AdminLogEvent> _events = [];
  String _selectedCategory = '';
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 280), () {
        unawaited(_load(reset: true));
      });
    });
    unawaited(_load(reset: true));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesCategory(AdminLogEvent ev) {
    final a = ev.action.toLowerCase();
    switch (_selectedCategory) {
      case 'messages':
        return a.contains('message') || a.contains('pin');
      case 'members':
        return a.contains('member') ||
            a.contains('ban') ||
            a.contains('restrict') ||
            a.contains('join');
      case 'rights':
        return a.contains('role') ||
            a.contains('admin') ||
            a.contains('right') ||
            a.contains('permission') ||
            a.contains('ownership');
      case 'settings':
        return a.contains('setting') ||
            a.contains('discussion') ||
            a.contains('auto_delete');
      case 'invites':
        return a.contains('invite');
      case 'topics':
        return a.contains('topic');
      default:
        return true;
    }
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loadingMore || !_hasMore)) return;
    if (mounted) {
      setState(() {
        if (reset) {
          _loading = true;
        } else {
          _loadingMore = true;
        }
      });
    }
    final res = await GroupsChannelsParityService.getAdminLog(
      widget.chatId,
      query: _searchController.text,
      hours: 48,
      limit: 50,
      offset: reset ? 0 : _events.length,
    );
    if (!mounted) return;
    setState(() {
      if (reset) _events.clear();
      _events.addAll(res.events);
      _hasMore = res.hasMore;
      _loading = false;
      _loadingMore = false;
    });
  }

  String _formatActionTitle(AdminLogEvent ev) {
    switch (ev.action) {
      case 'message_edited':
        return 'Изменил(а) сообщение';
      case 'message_deleted':
        return 'Удалил(а) сообщение';
      case 'message_pinned':
        return 'Закрепил(а) сообщение';
      case 'message_unpinned':
        return 'Открепил(а) сообщение';
      case 'settings_updated':
        return widget.isChannel
            ? 'Обновил(а) настройки канала'
            : 'Обновил(а) настройки группы';
      case 'discussion_group_updated':
        return 'Изменил(а) группу обсуждения';
      case 'auto_delete_updated':
        return 'Изменил(а) таймер автоудаления';
      case 'member_banned':
        return 'Заблокировал(а) участника';
      case 'member_unbanned':
        return 'Разблокировал(а) участника';
      case 'member_removed':
        return 'Исключил(а) участника';
      case 'member_restricted':
        return 'Ограничил(а) права участника';
      case 'member_role_updated':
      case 'admin_rights_updated':
        return 'Изменил(а) права администратора';
      case 'ownership_transferred':
        return 'Передал(а) права владельца';
      case 'invite_link_created':
        return 'Создал(а) пригласительную ссылку';
      case 'invite_link_updated':
        return 'Изменил(а) пригласительную ссылку';
      case 'invite_link_revoked':
        return 'Отозвал(а) пригласительную ссылку';
      case 'join_request_approved':
        return 'Одобрил(а) заявку на вступление';
      case 'join_request_declined':
        return 'Отклонил(а) заявку на вступление';
      case 'topic_created':
        return 'Создал(а) тему форума';
      case 'topic_updated':
        return 'Изменил(а) тему форума';
      case 'topic_deleted':
        return 'Удалил(а) тему форума';
      default:
        return ev.action;
    }
  }

  String _formatDetails(AdminLogEvent ev) {
    final parts = <String>[];
    if (ev.targetUserName.isNotEmpty) {
      parts.add('Пользователь: ${ev.targetUserName}');
    }
    if (ev.oldValue != null && ev.newValue != null) {
      final oldContent = ev.oldValue!['content']?.toString();
      final newContent = ev.newValue!['content']?.toString();
      if (oldContent != null && newContent != null && oldContent != newContent) {
        parts.add('«$oldContent» → «$newContent»');
      } else {
        final newTitle = ev.newValue!['title']?.toString();
        if (newTitle != null && newTitle.isNotEmpty) {
          parts.add('Тема: «$newTitle»');
        }
      }
    } else if (ev.newValue != null && ev.newValue!.isNotEmpty) {
      final summary = ev.newValue!.entries
          .take(3)
          .map((e) => '${e.key}: ${e.value}')
          .join(', ');
      if (summary.isNotEmpty) parts.add(summary);
    } else if (ev.oldValue != null && ev.oldValue!.isNotEmpty) {
      final oldContent = ev.oldValue!['content']?.toString();
      if (oldContent != null && oldContent.isNotEmpty) {
        parts.add('Текст: «$oldContent»');
      }
    }
    if (ev.createdAt != null) {
      parts.add(DateTimeUtils.formatTimeHHmm(ev.createdAt));
    }
    return parts.join(' · ');
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final filtered = _events.where(_matchesCategory).toList();

    return SettingsFloatingScaffold(
      title: 'Недавние действия',
      backgroundColor: palette.background,
      body: RefreshIndicator(
        onRefresh: () => _load(reset: true),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            0,
            SettingsFloatingHeader.topClearanceOf(context) + 12,
            0,
            MediaQuery.paddingOf(context).bottom + 32,
          ),
          children: [
            TheavInsetGroup(
              footer: 'События модерации за последние 48 часов (${widget.chatName}).',
              children: [
                TheavInlineTextField(
                  controller: _searchController,
                  placeholder: 'Поиск в журнале событий...',
                  prefix: iconoir.Search(
                    width: 18,
                    height: 18,
                    color: palette.subtext,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _categories.length,
                separatorBuilder: (_, __) => const SizedBox(width: 8),
                itemBuilder: (ctx, i) {
                  final cat = _categories[i];
                  return TheavFloatingPillButton(
                    height: 34,
                    padding: const EdgeInsets.symmetric(horizontal: 13),
                    label: cat.label,
                    isPrimary: _selectedCategory == cat.id,
                    onTap: () {
                      HapticUtils.selection();
                      setState(() => _selectedCategory = cat.id);
                    },
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 56),
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              )
            else if (filtered.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 52, 24, 24),
                child: Text(
                  'За последние 48 часов событий не найдено.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: palette.subtext, fontSize: 14),
                ),
              )
            else
              TheavInsetGroup(
                children: [
                  for (final ev in filtered)
                    TheavListRow(
                      leading: AvatarWithStatus(
                        userId: ev.actorId,
                        avatarUrl: ev.actorAvatar,
                        name: ev.actorName.isNotEmpty ? ev.actorName : 'A',
                        radius: 19,
                        isOnline: false,
                      ),
                      title: ev.actorName.isNotEmpty
                          ? '${ev.actorName} — ${_formatActionTitle(ev)}'
                          : _formatActionTitle(ev),
                      subtitle: _formatDetails(ev),
                    ),
                ],
              ),
            if (_hasMore && !_loading)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: TheavFloatingPillButton(
                  label: _loadingMore ? 'Загрузка...' : 'Загрузить ещё',
                  enabled: !_loadingMore,
                  onTap: () => _load(reset: false),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
