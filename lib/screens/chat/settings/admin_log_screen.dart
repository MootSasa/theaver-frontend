import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../../services/contacts_service.dart';
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
    (id: 'all', label: 'Все'),
    (id: 'messages', label: 'Сообщения'),
    (id: 'members', label: 'Участники'),
    (id: 'rights', label: 'Права'),
    (id: 'settings', label: 'Настройки'),
    (id: 'invites', label: 'Ссылки'),
    (id: 'topics', label: 'Темы'),
  ];

  final TextEditingController _searchController = TextEditingController();
  final List<AdminLogEvent> _events = [];
  final List<AdminLogEvent> _unfilteredEvents = [];
  String _selectedCategory = 'all';
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _loadRequestSeq = 0;
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    ContactsService.revisionNotifier.addListener(_onContactsRevisionChanged);
    _searchController.addListener(() {
      _debounce?.cancel();
      _debounce = Timer(const Duration(milliseconds: 280), () {
        unawaited(_load(reset: true));
      });
    });
    unawaited(_load(reset: true));
  }

  void _onContactsRevisionChanged() {
    if (!mounted) return;
    final q = _searchController.text.trim();
    if (q.isNotEmpty && _unfilteredEvents.isNotEmpty) {
      unawaited(_load(reset: true));
    } else {
      setState(() {});
    }
  }

  @override
  void dispose() {
    ContactsService.revisionNotifier.removeListener(_onContactsRevisionChanged);
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  bool _canResolveLogUserId(String? userId) {
    final uid = userId?.trim() ?? '';
    if (uid.isEmpty || uid == '0') return false;
    final numeric = int.tryParse(uid);
    if (numeric != null && numeric <= 0) return false;
    return ContactsService.shouldResolveUserIdentity(uid);
  }

  String _resolveActorName(AdminLogEvent ev) {
    final raw = ev.actorName.isNotEmpty
        ? ev.actorName
        : (ev.actorUsername.isNotEmpty ? '@${ev.actorUsername}' : '');
    if (!_canResolveLogUserId(ev.actorId)) return raw;
    return ContactsService.resolvePeerName(ev.actorId, raw);
  }

  String? _resolveActorAvatar(AdminLogEvent ev) {
    if (!_canResolveLogUserId(ev.actorId)) return ev.actorAvatar;
    return ContactsService.resolvePeerAvatarUrl(ev.actorId, ev.actorAvatar);
  }

  String _resolveTargetUserName(AdminLogEvent ev) {
    final raw = ev.targetUserName.isNotEmpty
        ? ev.targetUserName
        : (ev.targetUserUsername.isNotEmpty ? '@${ev.targetUserUsername}' : '');
    if (!_canResolveLogUserId(ev.targetUserId)) return raw;
    return ContactsService.resolvePeerName(ev.targetUserId, raw);
  }

  bool _matchesSearchQuery(AdminLogEvent ev, String queryLower) {
    if (_resolveActorName(ev).toLowerCase().contains(queryLower)) return true;
    if (_resolveTargetUserName(ev).toLowerCase().contains(queryLower)) {
      return true;
    }
    if (ev.actorName.toLowerCase().contains(queryLower) ||
        ev.actorUsername.toLowerCase().contains(queryLower) ||
        ev.targetUserName.toLowerCase().contains(queryLower) ||
        ev.targetUserUsername.toLowerCase().contains(queryLower)) {
      return true;
    }
    return _formatActionTitle(ev).toLowerCase().contains(queryLower) ||
        _formatDetails(ev).toLowerCase().contains(queryLower);
  }

  Future<void> _load({bool reset = false}) async {
    if (!reset && (_loadingMore || !_hasMore)) return;
    final int reqSeq = ++_loadRequestSeq;
    final trimmedQuery = _searchController.text.trim();
    if (mounted) {
      setState(() {
        if (reset) {
          _loading = true;
          _loadingMore = false;
        } else {
          _loadingMore = true;
        }
      });
    }
    final category = _selectedCategory == 'all' ? null : _selectedCategory;
    final needsUnfilteredSeed =
        reset && trimmedQuery.isNotEmpty && _unfilteredEvents.isEmpty;
    final resFuture = GroupsChannelsParityService.getAdminLog(
      widget.chatId,
      category: category,
      query: trimmedQuery,
      hours: 48,
      limit: 50,
      offset: reset ? 0 : _events.length,
    );
    final seedFuture = needsUnfilteredSeed
        ? GroupsChannelsParityService.getAdminLog(
            widget.chatId,
            category: category,
            hours: 48,
            limit: 50,
            offset: 0,
          )
        : null;
    final res = await resFuture;
    final seedRes = seedFuture != null ? await seedFuture : null;
    if (!mounted || reqSeq != _loadRequestSeq) return;
    setState(() {
      if (seedRes != null) {
        _unfilteredEvents
          ..clear()
          ..addAll(seedRes.events);
      }
      if (trimmedQuery.isEmpty) {
        if (reset) _unfilteredEvents.clear();
        _unfilteredEvents.addAll(res.events);
      }
      if (reset) _events.clear();
      final seenIds = {for (final e in _events) e.id};
      for (final e in res.events) {
        if (seenIds.add(e.id)) _events.add(e);
      }
      if (reset && trimmedQuery.isNotEmpty) {
        final qLower = trimmedQuery.toLowerCase();
        for (final e in _unfilteredEvents) {
          if (_matchesSearchQuery(e, qLower) && seenIds.add(e.id)) {
            _events.add(e);
          }
        }
        _events.sort((a, b) => b.id.compareTo(a.id));
      }
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
      case 'chat_history_cleared':
      case 'history_cleared':
        return 'Очистил(а) историю чата';
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
    final targetName = _resolveTargetUserName(ev);
    if (targetName.isNotEmpty) {
      parts.add('Пользователь: $targetName');
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
                      if (_selectedCategory == cat.id) return;
                      HapticUtils.selection();
                      setState(() {
                        _selectedCategory = cat.id;
                        _unfilteredEvents.clear();
                      });
                      unawaited(_load(reset: true));
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
            else if (_events.isEmpty)
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
                  for (final ev in _events)
                    Builder(
                      builder: (_) {
                        final actorName = _resolveActorName(ev);
                        final actorAvatar = _resolveActorAvatar(ev);
                        return TheavListRow(
                          leading: AvatarWithStatus(
                            userId: _canResolveLogUserId(ev.actorId)
                                ? ev.actorId
                                : null,
                            avatarUrl: actorAvatar,
                            name: actorName.isNotEmpty ? actorName : 'A',
                            radius: 19,
                            isOnline: false,
                            resolveContactOverride:
                                _canResolveLogUserId(ev.actorId),
                          ),
                          title: actorName.isNotEmpty
                              ? '$actorName — ${_formatActionTitle(ev)}'
                              : _formatActionTitle(ev),
                          subtitle: _formatDetails(ev),
                        );
                      },
                    ),
                ],
              ),
            if (_hasMore && !_loading && _events.isNotEmpty)
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
