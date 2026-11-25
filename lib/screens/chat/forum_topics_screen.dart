import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../services/chat_realtime_manager.dart';
import '../../services/chat_service.dart';
import '../../services/contacts_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/groups_channels_parity_service.dart';
import '../../services/websocket_service.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/settings/settings_floating_header.dart';
import 'group_chat_screen.dart';

/// Result returned when [ForumTopicsScreen] is opened from [GroupChatScreen]
/// so topic/flat switching happens in-place without stacking duplicate chat routes.
class ForumTopicSelectionResult {
  final ForumTopic? topic;
  final bool viewFlatMessages;

  const ForumTopicSelectionResult({
    this.topic,
    this.viewFlatMessages = false,
  });
}

/// Forum Topics list screen for Forum Supergroups (`is_forum == true`), supporting
/// search, live updates, topic creation/editing/pin/close/hide/delete, and
/// "View as Messages" toggle into the flat group stream.
class ForumTopicsScreen extends StatefulWidget {
  final String chatId;
  final String chatName;
  final String? chatAvatar;
  final String? myRole;
  final AdminRights? myAdminPermissions;
  final GroupDefaultPermissions? defaultPermissions;
  final bool openedFromGroupChat;

  const ForumTopicsScreen({
    super.key,
    required this.chatId,
    required this.chatName,
    this.chatAvatar,
    this.myRole,
    this.myAdminPermissions,
    this.defaultPermissions,
    this.openedFromGroupChat = false,
  });

  @override
  State<ForumTopicsScreen> createState() => _ForumTopicsScreenState();
}

class _ForumTopicsScreenState extends State<ForumTopicsScreen> {
  static const List<int> _topicColors = [
    0xFF6FB9F0,
    0xFFFF9F43,
    0xFFCB86DB,
    0xFF8EEE98,
    0xFFFF93B2,
    0xFFFB6F5F,
  ];
  static const List<String> _topicEmojis = [
    '💬',
    '📢',
    '🔥',
    '💡',
    '🛠️',
    '🎨',
    '🎮',
    '📌',
    '❓',
    '✅',
  ];

  final TextEditingController _searchController = TextEditingController();
  List<ForumTopic> _topics = [];
  bool _loading = true;
  bool _showSearch = false;
  Timer? _debounce;
  ChatSubscription? _sub;

  bool get _isAdmin => widget.myRole == 'owner' || widget.myRole == 'admin';

  bool get _canCreateTopics {
    if (widget.myRole == 'owner') return true;
    if (widget.myRole == 'admin') {
      return widget.myAdminPermissions?.canManageTopics ?? true;
    }
    return widget.defaultPermissions?.canManageTopics ?? false;
  }

  bool get _canManageExistingTopics {
    if (widget.myRole == 'owner') return true;
    if (widget.myRole == 'admin') {
      return widget.myAdminPermissions?.canManageTopics ?? true;
    }
    return false;
  }

  @override
  void initState() {
    super.initState();
    ContactsService.revisionNotifier.addListener(_onContactsRevisionChanged);
    _searchController.addListener(_onSearchChanged);
    _bindRealtime();
    unawaited(_loadTopics());
  }

  @override
  void dispose() {
    ContactsService.revisionNotifier.removeListener(_onContactsRevisionChanged);
    _debounce?.cancel();
    _sub?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onContactsRevisionChanged() {
    if (mounted) setState(() {});
  }

  void _bindRealtime() {
    _sub = ChatRealtimeManager().bindChat(
      chatId: widget.chatId,
      onForumTopicUpdated: _onForumTopicUpdated,
      onNewMessage: (event) {
        final msg = event.data['message'] is Map
            ? Map<String, dynamic>.from(event.data['message'] as Map)
            : event.data;
        final tid = (msg['topic_id'] as num?)?.toInt() ??
            int.tryParse(msg['topic_id']?.toString() ?? '');
        if (tid == null || tid <= 0 || !mounted) return;
        unawaited(_loadTopics(silent: true));
      },
    );
  }

  void _onForumTopicUpdated(WebSocketEvent event) {
    if (!mounted) return;
    final action = (event.data['action'] ?? '').toString();
    final rawTopic = event.data['topic'];
    if (action == 'deleted') {
      final delId = (rawTopic is Map ? rawTopic['id'] : event.data['topic_id'])
          ?.toString();
      final parsedId = int.tryParse(delId ?? '');
      if (parsedId != null) {
        setState(() => _topics.removeWhere((t) => t.id == parsedId));
      }
      return;
    }
    if (rawTopic is Map) {
      final updated = ForumTopic.fromJson(Map<String, dynamic>.from(rawTopic));
      setState(() {
        final idx = _topics.indexWhere((t) => t.id == updated.id);
        if (idx != -1) {
          _topics[idx] = updated;
        } else {
          _topics.add(updated);
        }
        _sortTopics();
      });
    } else {
      unawaited(_loadTopics(silent: true));
    }
  }

  void _sortTopics() {
    _topics.sort((a, b) {
      if (a.isPinned != b.isPinned) return a.isPinned ? -1 : 1;
      if (a.isGeneral != b.isGeneral) return a.isGeneral ? -1 : 1;
      final aAt = a.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      final bAt = b.lastMessageAt ?? DateTime.fromMillisecondsSinceEpoch(0);
      return bAt.compareTo(aAt);
    });
  }

  void _onSearchChanged() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 260), () {
      unawaited(_loadTopics(silent: true));
    });
  }

  Future<void> _loadTopics({bool silent = false}) async {
    if (!silent && mounted) setState(() => _loading = true);
    final res = await GroupsChannelsParityService.getTopics(
      widget.chatId,
      query: _showSearch ? _searchController.text : null,
    );
    if (!mounted) return;
    setState(() {
      _topics = List<ForumTopic>.from(
        res.topics.where((t) => !t.isHidden || _isAdmin),
      );
      _sortTopics();
      _loading = false;
    });
  }

  void _openFlatMessages() {
    HapticUtils.tap();
    if (widget.openedFromGroupChat) {
      Navigator.pop(
        context,
        const ForumTopicSelectionResult(viewFlatMessages: true),
      );
      return;
    }
    Navigator.push(
      context,
      SwipeBackPageRoute(
        builder: (_) => GroupChatScreen(
          chatId: widget.chatId,
          groupName: widget.chatName,
          groupAvatar: widget.chatAvatar,
          initialIsForum: true,
        ),
      ),
    ).then((_) {
      if (mounted) unawaited(_loadTopics(silent: true));
    });
  }

  void _openTopic(ForumTopic topic) {
    HapticUtils.tap();
    if (widget.openedFromGroupChat) {
      Navigator.pop(
        context,
        ForumTopicSelectionResult(topic: topic),
      );
      return;
    }
    Navigator.push(
      context,
      SwipeBackPageRoute(
        builder: (_) => GroupChatScreen(
          chatId: widget.chatId,
          groupName: widget.chatName,
          groupAvatar: widget.chatAvatar,
          activeTopic: topic,
          initialIsForum: true,
        ),
      ),
    ).then((_) {
      if (mounted) unawaited(_loadTopics(silent: true));
    });
  }

  Future<void> _openCreateOrEditTopicSheet({ForumTopic? existing}) async {
    HapticUtils.tap();
    final titleCtrl = TextEditingController(text: existing?.title ?? '');
    int selectedColor = existing?.iconColor ?? _topicColors.first;
    String selectedEmoji = existing?.iconEmoji ?? '';
    bool saving = false;

    final saved = await showTheavModalSheet<ForumTopic>(
      context: context,
      title: existing == null ? 'Новая тема' : 'Изменить тему',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final palette = ctx.theav;
          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              0,
              4,
              0,
              MediaQuery.viewInsetsOf(ctx).bottom + 20,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TheavInsetGroup(
                  header: 'НАЗВАНИЕ ТЕМЫ',
                  children: [
                    TheavInlineTextField(
                      controller: titleCtrl,
                      placeholder: 'Например: Обсуждение релизов',
                      autofocus: true,
                      maxLength: 64,
                      showCounter: true,
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Text(
                    'ИКОНКА И ЦВЕТ',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: palette.subtext,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 40,
                  child: ListView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    children: [
                      for (final c in _topicColors)
                        Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: GestureDetector(
                            onTap: () {
                              HapticUtils.selection();
                              setSheetState(() => selectedColor = c);
                            },
                            child: Container(
                              width: 34,
                              height: 34,
                              decoration: BoxDecoration(
                                color: Color(c),
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: selectedColor == c
                                      ? palette.onSurface
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: selectedColor == c
                                  ? const iconoir.Check(
                                      width: 16,
                                      height: 16,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      TheavFloatingPillButton(
                        height: 36,
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        label: '#',
                        isPrimary: selectedEmoji.isEmpty,
                        onTap: () => setSheetState(() => selectedEmoji = ''),
                      ),
                      for (final em in _topicEmojis)
                        GestureDetector(
                          onTap: () {
                            HapticUtils.selection();
                            setSheetState(() => selectedEmoji = em);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 140),
                            width: 38,
                            height: 36,
                            decoration: BoxDecoration(
                              color: selectedEmoji == em
                                  ? palette.primary.withValues(alpha: 0.18)
                                  : palette.surface,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: selectedEmoji == em
                                    ? palette.primary
                                    : palette.divider,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: Text(em, style: const TextStyle(fontSize: 18)),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: TheavFloatingPillButton(
                    isPrimary: true,
                    enabled: !saving,
                    label: saving
                        ? 'Сохранение...'
                        : (existing == null ? 'Создать тему' : 'Сохранить'),
                    onTap: () async {
                      final trimmed = titleCtrl.text.trim();
                      if (trimmed.isEmpty) {
                        GlassToastService().show(ctx, 'Введите название темы');
                        return;
                      }
                      setSheetState(() => saving = true);
                      final topic = existing == null
                          ? await GroupsChannelsParityService.createTopic(
                              widget.chatId,
                              title: trimmed,
                              iconColor: selectedColor,
                              iconEmoji: selectedEmoji.isNotEmpty
                                  ? selectedEmoji
                                  : null,
                            )
                          : await GroupsChannelsParityService.updateTopic(
                              widget.chatId,
                              existing.id,
                              title: trimmed,
                              iconColor: selectedColor,
                              iconEmoji: selectedEmoji,
                            );
                      if (!ctx.mounted) return;
                      if (topic != null) {
                        Navigator.pop(ctx, topic);
                      } else {
                        setSheetState(() => saving = false);
                        GlassToastService().showError(
                          ctx,
                          'Не удалось сохранить тему',
                        );
                      }
                    },
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    titleCtrl.dispose();
    if (saved != null && mounted) {
      unawaited(_loadTopics(silent: true));
      if (existing == null) {
        _openTopic(saved);
      }
    }
  }

  Future<void> _showTopicActions(ForumTopic topic) async {
    if (!_canManageExistingTopics) return;
    HapticUtils.impact();
    final palette = context.theav;

    final action = await showTheavModalSheet<String>(
      context: context,
      title: topic.title,
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
        child: TheavInsetGroup(
          children: [
            TheavListRow(
              leading: iconoir.Pin(
                width: 20,
                height: 20,
                color: palette.primary,
              ),
              title: topic.isPinned ? 'Открепить тему' : 'Закрепить тему',
              onTap: () => Navigator.pop(ctx, 'pin'),
            ),
            TheavListRow(
              leading: iconoir.Lock(
                width: 20,
                height: 20,
                color: palette.primary,
              ),
              title: topic.isClosed ? 'Открыть тему' : 'Закрыть тему',
              onTap: () => Navigator.pop(ctx, 'close'),
            ),
            TheavListRow(
              leading: iconoir.EditPencil(
                width: 20,
                height: 20,
                color: palette.primary,
              ),
              title: 'Изменить',
              onTap: () => Navigator.pop(ctx, 'edit'),
            ),
            if (topic.isGeneral)
              TheavListRow(
                leading: iconoir.EyeClosed(
                  width: 20,
                  height: 20,
                  color: palette.primary,
                ),
                title: topic.isHidden ? 'Показать General' : 'Скрыть General',
                onTap: () => Navigator.pop(ctx, 'hide'),
              )
            else
              TheavListRow(
                leading: iconoir.Trash(
                  width: 20,
                  height: 20,
                  color: palette.error,
                ),
                title: 'Удалить тему',
                isDestructive: true,
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
          ],
        ),
      ),
    );

    if (!mounted || action == null) return;
    switch (action) {
      case 'pin':
        await GroupsChannelsParityService.updateTopic(
          widget.chatId,
          topic.id,
          isPinned: !topic.isPinned,
        );
        unawaited(_loadTopics(silent: true));
        break;
      case 'close':
        await GroupsChannelsParityService.updateTopic(
          widget.chatId,
          topic.id,
          isClosed: !topic.isClosed,
        );
        unawaited(_loadTopics(silent: true));
        break;
      case 'hide':
        await GroupsChannelsParityService.updateTopic(
          widget.chatId,
          topic.id,
          isHidden: !topic.isHidden,
        );
        unawaited(_loadTopics(silent: true));
        break;
      case 'edit':
        await _openCreateOrEditTopicSheet(existing: topic);
        break;
      case 'delete':
        final ok = await showTheavDialog<bool>(
          context: context,
          title: 'Удалить тему «${topic.title}»?',
          message: 'Все сообщения внутри темы будут удалены.',
          actions: const [
            TheavDialogAction<bool>(label: 'Отмена', result: false),
            TheavDialogAction<bool>(
              label: 'Удалить',
              result: true,
              isDestructive: true,
            ),
          ],
        );
        if (ok == true) {
          final deleted = await GroupsChannelsParityService.deleteTopic(
            widget.chatId,
            topic.id,
          );
          if (deleted && mounted) {
            setState(() => _topics.removeWhere((t) => t.id == topic.id));
          }
        }
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;

    return SettingsFloatingScaffold(
      title: widget.chatName,
      backgroundColor: palette.background,
      actions: [
        SettingsHeaderAction(
          tooltip: _showSearch ? 'Закрыть поиск' : 'Поиск тем',
          icon: iconoir.Search(width: 20, height: 20, color: palette.onSurface),
          onTap: () {
            setState(() {
              _showSearch = !_showSearch;
              if (!_showSearch) {
                _searchController.clear();
              }
            });
          },
        ),
        SettingsHeaderAction(
          tooltip: 'Показать как сообщения',
          icon: iconoir.ChatLines(
            width: 20,
            height: 20,
            color: palette.onSurface,
          ),
          onTap: _openFlatMessages,
        ),
        if (_canCreateTopics)
          SettingsHeaderAction(
            tooltip: 'Создать тему',
            foregroundColor: palette.primary,
            icon: iconoir.Plus(width: 22, height: 22, color: palette.primary),
            onTap: () => _openCreateOrEditTopicSheet(),
          ),
      ],
      body: RefreshIndicator(
        onRefresh: () => _loadTopics(),
        child: ListView(
          padding: EdgeInsets.fromLTRB(
            0,
            SettingsFloatingHeader.topClearanceOf(context) + 12,
            0,
            MediaQuery.paddingOf(context).bottom + 32,
          ),
          children: [
            if (_showSearch)
              TheavInsetGroup(
                children: [
                  TheavInlineTextField(
                    controller: _searchController,
                    placeholder: 'Поиск по темам...',
                    autofocus: true,
                    prefix: iconoir.Search(
                      width: 18,
                      height: 18,
                      color: palette.subtext,
                    ),
                  ),
                ],
              ),
            if (_loading)
              const Padding(
                padding: EdgeInsets.only(top: 64),
                child: Center(
                  child: CircularProgressIndicator(strokeWidth: 2.2),
                ),
              )
            else if (_topics.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 60, 24, 24),
                child: Column(
                  children: [
                    iconoir.ChatLines(
                      width: 42,
                      height: 42,
                      color: palette.subtext,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Тем пока нет',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: palette.onSurface,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'Создайте первую тему или откройте общий поток сообщений.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13.5, color: palette.subtext),
                    ),
                  ],
                ),
              )
            else
              TheavInsetGroup(
                header: 'ТЕМЫ ФОРУМА (${_topics.length})',
                children: [
                  for (final topic in _topics) _buildTopicRow(topic, palette),
                ],
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildTopicRow(ForumTopic topic, TheavPalette palette) {
    final color = Color(topic.iconColor | 0xFF000000);
    final rawSenderName = topic.lastMessageSenderName?.trim() ?? '';
    final resolvedSenderName = (topic.lastMessageSenderId != null &&
            topic.lastMessageSenderId!.isNotEmpty &&
            rawSenderName.isNotEmpty)
        ? ContactsService.resolvePeerName(
            topic.lastMessageSenderId,
            rawSenderName,
          )
        : rawSenderName;
    final preview = topic.lastMessage?.trim().isNotEmpty == true
        ? (resolvedSenderName.isNotEmpty
            ? '$resolvedSenderName: ${topic.lastMessage}'
            : topic.lastMessage!)
        : 'Нет сообщений';

    return TheavListRow(
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.16),
          borderRadius: BorderRadius.circular(13),
        ),
        alignment: Alignment.center,
        child: (topic.iconEmoji != null && topic.iconEmoji!.isNotEmpty)
            ? Text(topic.iconEmoji!, style: const TextStyle(fontSize: 20))
            : Text(
                '#',
                style: TextStyle(
                  color: color,
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                ),
              ),
      ),
      titleWidget: Row(
        children: [
          if (topic.isPinned) ...[
            iconoir.Pin(width: 13, height: 13, color: palette.primary),
            const SizedBox(width: 4),
          ],
          if (topic.isClosed) ...[
            iconoir.Lock(width: 13, height: 13, color: palette.subtext),
            const SizedBox(width: 4),
          ],
          Expanded(
            child: Text(
              topic.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.onSurface,
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (topic.lastMessageAt != null)
            Text(
              DateTimeUtils.formatTimeHHmm(topic.lastMessageAt),
              style: TextStyle(color: palette.subtext, fontSize: 11.5),
            ),
        ],
      ),
      subtitle: preview,
      trailing: topic.unreadCount > 0
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: palette.unreadBadge,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                topic.unreadCount > 99 ? '99+' : '${topic.unreadCount}',
                style: TextStyle(
                  color: palette.unreadBadgeText,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
            )
          : null,
      showChevron: topic.unreadCount <= 0,
      onTap: () => _openTopic(topic),
      onLongPress: _canManageExistingTopics
          ? () => _showTopicActions(topic)
          : null,
    );
  }
}
