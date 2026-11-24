import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../../services/chat_service.dart';
import '../../../services/glass_toast_service.dart';
import '../../../utils/haptic_utils.dart';
import '../../../utils/swipe_back_route.dart';
import '../../../widgets/design_system/theav_design_system.dart';
import '../../../widgets/settings/settings_floating_header.dart';
import '../../../widgets/user/avatar_with_status.dart';

/// Channel discussion settings screen: view/unlink the linked discussion group,
/// link an existing admin/owned group, or create a new discussion group.
class ChannelDiscussionSettingsScreen extends StatefulWidget {
  final String channelId;
  final String channelName;
  final String? currentLinkedChatId;
  final LinkedChatSummary? currentLinkedChat;

  const ChannelDiscussionSettingsScreen({
    super.key,
    required this.channelId,
    required this.channelName,
    this.currentLinkedChatId,
    this.currentLinkedChat,
  });

  @override
  State<ChannelDiscussionSettingsScreen> createState() =>
      _ChannelDiscussionSettingsScreenState();
}

class _ChannelDiscussionSettingsScreenState
    extends State<ChannelDiscussionSettingsScreen> {
  String? _linkedChatId;
  LinkedChatSummary? _linkedChat;
  List<Chat> _adminGroups = [];
  bool _isLoading = true;
  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _linkedChatId = (widget.currentLinkedChatId != null &&
            widget.currentLinkedChatId!.trim().isNotEmpty)
        ? widget.currentLinkedChatId!.trim()
        : widget.currentLinkedChat?.id;
    _linkedChat = widget.currentLinkedChat;
    unawaited(_loadData());
  }

  Future<void> _loadData() async {
    try {
      final results = await Future.wait([
        ChatService.getChats(),
        if (_linkedChat == null || (_linkedChatId ?? '').isEmpty)
          ChatService.getGroupSettings(widget.channelId)
        else
          Future.value(const <String, dynamic>{}),
      ]);

      if (!mounted) return;
      final chatsRes = results[0];
      final settingsRes = results[1];

      final rawChats = chatsRes['chats'];
      final groups = <Chat>[];
      if (rawChats is List<Chat>) {
        for (final c in rawChats) {
          final isEligibleRole = c.myRole == 'owner' || c.myRole == 'admin';
          if (c.chatType == 'group' &&
              isEligibleRole &&
              !c.isCommunityChannel &&
              c.id != widget.channelId) {
            groups.add(c);
          }
        }
      }

      var resolvedLinkedId = _linkedChatId;
      var resolvedLinked = _linkedChat;
      if (settingsRes['success'] == true) {
        final rawId = settingsRes['linked_chat_id']?.toString().trim() ?? '';
        if (rawId.isNotEmpty) {
          resolvedLinkedId = rawId;
        }
        final summary = LinkedChatSummary.tryParse(settingsRes['linked_chat']);
        if (summary != null) {
          resolvedLinked = summary;
          resolvedLinkedId ??= summary.id;
        }
      }

      // Enrich missing linkedChat summary from user's groups list if available.
      if (resolvedLinked == null &&
          resolvedLinkedId != null &&
          resolvedLinkedId.isNotEmpty) {
        final match = groups.where((g) => g.id == resolvedLinkedId).firstOrNull;
        if (match != null) {
          resolvedLinked = LinkedChatSummary(
            id: match.id,
            name: match.name,
            username: match.username,
            avatarUrl: match.avatarUrl,
            chatType: match.chatType,
          );
        }
      }

      setState(() {
        _linkedChatId = resolvedLinkedId;
        _linkedChat = resolvedLinked;
        _adminGroups = groups;
        _isLoading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  bool get _hasLinkedGroup =>
      _linkedChatId != null && _linkedChatId!.trim().isNotEmpty;

  Future<void> _createDiscussionGroup() async {
    if (_isSubmitting) return;
    HapticUtils.tap();
    setState(() => _isSubmitting = true);

    final res = await ChatService.updateChannelDiscussionGroup(
      channelId: widget.channelId,
      createNew: true,
      newGroupName: '${widget.channelName.trim()} Chat',
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (res['success'] == true) {
      final summary = LinkedChatSummary.tryParse(res['linked_chat']);
      final newId = res['linked_chat_id']?.toString().trim() ?? summary?.id;
      setState(() {
        _linkedChatId = (newId != null && newId.isNotEmpty) ? newId : null;
        _linkedChat = summary;
      });
      GlassToastService().show(
        context,
        'Группа для обсуждения создана и привязана',
        iconWidget: const iconoir.Check(
          width: 18,
          height: 18,
          color: Color(0xFF34C759),
        ),
      );
      unawaited(_loadData());
    } else {
      GlassToastService().show(
        context,
        res['message']?.toString() ?? 'Не удалось создать группу',
      );
    }
  }

  Future<void> _linkGroup(Chat group) async {
    if (_isSubmitting) return;
    final extraNote =
        (group.linkedChatId != null &&
                group.linkedChatId!.isNotEmpty &&
                group.linkedChatId != widget.channelId)
            ? '\n\nЭта группа уже привязана к другому каналу — прежняя связь будет заменена.'
            : '';

    final confirmed = await showTheavDialog<bool>(
      context: context,
      title: 'Привязать «${group.name}»?',
      message:
          'Публикации канала «${widget.channelName}» будут автоматически пересылаться в эту группу для комментариев.$extraNote',
      actions: const [
        TheavDialogAction<bool>(label: 'Отмена', result: false),
        TheavDialogAction<bool>(
          label: 'Привязать',
          result: true,
          isPrimary: true,
        ),
      ],
    );
    if (confirmed != true || !mounted) return;

    HapticUtils.tap();
    setState(() => _isSubmitting = true);

    final res = await ChatService.updateChannelDiscussionGroup(
      channelId: widget.channelId,
      linkedChatId: group.id,
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (res['success'] == true) {
      final summary = LinkedChatSummary.tryParse(res['linked_chat']) ??
          LinkedChatSummary(
            id: group.id,
            name: group.name,
            username: group.username,
            avatarUrl: group.avatarUrl,
            chatType: group.chatType,
          );
      setState(() {
        _linkedChatId = group.id;
        _linkedChat = summary;
      });
      GlassToastService().show(
        context,
        'Группа «${group.name}» привязана',
      );
    } else {
      GlassToastService().show(
        context,
        res['message']?.toString() ?? 'Не удалось привязать группу',
      );
    }
  }

  Future<void> _unlinkGroup() async {
    if (_isSubmitting || !_hasLinkedGroup) return;
    final confirmed = await showTheavDialog<bool>(
      context: context,
      title: 'Отвязать группу?',
      message:
          'Комментарии под новыми публикациями канала перестанут отображаться.',
      actions: const [
        TheavDialogAction<bool>(label: 'Отмена', result: false),
        TheavDialogAction<bool>(
          label: 'Отвязать',
          result: true,
          isDestructive: true,
        ),
      ],
    );
    if (confirmed != true || !mounted) return;

    HapticUtils.tap();
    setState(() => _isSubmitting = true);

    final res = await ChatService.updateChannelDiscussionGroup(
      channelId: widget.channelId,
      linkedChatId: '',
    );

    if (!mounted) return;
    setState(() => _isSubmitting = false);

    if (res['success'] == true) {
      setState(() {
        _linkedChatId = null;
        _linkedChat = null;
      });
      GlassToastService().show(context, 'Группа обсуждения отвязана');
    } else {
      GlassToastService().show(
        context,
        res['message']?.toString() ?? 'Не удалось отвязать группу',
      );
    }
  }

  void _popWithResult() {
    if (!Navigator.of(context).canPop()) return;
    Navigator.pop(context, {
      'linked_chat_id': _linkedChatId ?? '',
      'linked_chat': _linkedChat,
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final availableGroups =
        _adminGroups.where((g) => g.id != _linkedChatId).toList();

    return SwipeBackPopScope(
      onSwipeBackPop: _popWithResult,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _popWithResult();
        },
        child: SettingsFloatingScaffold(
        title: 'Обсуждение',
        backgroundColor: palette.background,
        onBack: _popWithResult,
        actions: _isSubmitting
            ? [
                SettingsHeaderAction(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: palette.primary,
                    ),
                  ),
                ),
              ]
            : const [],
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            0,
            SettingsFloatingHeader.topClearanceOf(context) + 12,
            0,
            MediaQuery.paddingOf(context).bottom + 36,
          ),
          children: [
            TheavInsetGroup(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: palette.primary.withValues(alpha: 0.14),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: iconoir.ChatLines(
                          width: 22,
                          height: 22,
                          color: palette.primary,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          'Привяжите группу, чтобы подписчики могли оставлять комментарии под публикациями канала «${widget.channelName}».',
                          style: TextStyle(
                            fontSize: 13.5,
                            height: 1.38,
                            color: palette.subtext,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_hasLinkedGroup) ...[
              const SizedBox(height: 8),
              _buildLinkedGroupCard(context, palette: palette),
            ],
            const SizedBox(height: 8),
            TheavInsetGroup(
              children: [
                TheavListRow(
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: palette.primary.withValues(alpha: 0.14),
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: iconoir.Plus(
                      width: 20,
                      height: 20,
                      color: palette.primary,
                    ),
                  ),
                  title: 'Создать группу для обсуждения',
                  subtitle:
                      'Будет создана группа «${widget.channelName.trim()} Chat»',
                  enabled: !_isSubmitting,
                  onTap: _createDiscussionGroup,
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (availableGroups.isEmpty)
              TheavInsetGroup(
                header: 'ВАШИ ГРУППЫ (ВЛАДЕЛЕЦ ИЛИ АДМИН)',
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 20,
                      vertical: 22,
                    ),
                    child: Text(
                      'Нет других групп, в которых вы являетесь владельцем или администратором.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 14, color: palette.subtext),
                    ),
                  ),
                ],
              )
            else
              TheavInsetGroup(
                header: 'ВАШИ ГРУППЫ (ВЛАДЕЛЕЦ ИЛИ АДМИН)',
                dividerIndent: 70,
                children: [
                  for (final g in availableGroups)
                    TheavListRow(
                      leading: AvatarWithStatus(
                        avatarUrl: g.avatarUrl,
                        name: g.name,
                        radius: 21,
                      ),
                      title: g.name,
                      subtitle: g.username != null && g.username!.isNotEmpty
                          ? '@${g.username}'
                          : (g.myRole == 'owner'
                              ? 'Владелец'
                              : 'Администратор'),
                      trailing: iconoir.Link(
                        width: 18,
                        height: 18,
                        color: palette.primary,
                      ),
                      enabled: !_isSubmitting,
                      onTap: () => _linkGroup(g),
                    ),
                ],
              ),
          ],
        ),
      ),
      ),
    );
  }

  Widget _buildLinkedGroupCard(
    BuildContext context, {
    required TheavPalette palette,
  }) {
    final groupName = _linkedChat?.name.isNotEmpty == true
        ? _linkedChat!.name
        : 'Группа #${_linkedChatId ?? ''}';
    final subText = (_linkedChat?.username?.isNotEmpty == true)
        ? '@${_linkedChat!.username}'
        : (_linkedChat != null && _linkedChat!.memberCount > 0
            ? '${_linkedChat!.memberCount} участников'
            : 'Привязанная группа обсуждения');

    return TheavInsetGroup(
      header: 'ПРИВЯЗАННАЯ ГРУППА',
      children: [
        TheavListRow(
          leading: AvatarWithStatus(
            avatarUrl: _linkedChat?.avatarUrl,
            name: groupName,
            radius: 21,
          ),
          title: groupName,
          subtitle: subText,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: const Color(0xFF34C759).withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Text(
              'Активна',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Color(0xFF2E9E4C),
              ),
            ),
          ),
        ),
        TheavListRow(
          leading: iconoir.LinkSlash(
            width: 20,
            height: 20,
            color: palette.error,
          ),
          title: 'Отвязать группу',
          isDestructive: true,
          enabled: !_isSubmitting,
          onTap: _unlinkGroup,
        ),
      ],
    );
  }
}
