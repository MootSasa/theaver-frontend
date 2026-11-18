import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../../services/chat_service.dart';
import '../../../services/glass_toast_service.dart';
import '../../../utils/haptic_utils.dart';
import '../../../widgets/design_system/theav_design_system.dart';
import '../../../widgets/settings/settings_floating_header.dart';
import '../../../widgets/user/avatar_with_status.dart';

/// Group permissions, slow mode ([TheavSteppedSlider]), and modal sub-sheets
/// for per-user restriction exceptions and blacklist management.
///
/// Saves exclusively via the right `44x44` check button in [SettingsFloatingHeader].
class GroupPermissionsScreen extends StatefulWidget {
  final String chatId;
  final GroupDefaultPermissions initialPermissions;
  final int initialSlowMode;

  const GroupPermissionsScreen({
    super.key,
    required this.chatId,
    required this.initialPermissions,
    required this.initialSlowMode,
  });

  @override
  State<GroupPermissionsScreen> createState() => _GroupPermissionsScreenState();
}

class _GroupPermissionsScreenState extends State<GroupPermissionsScreen> {
  static const List<int> _slowModeStops = [0, 10, 30, 60, 300, 900, 3600];
  static const List<String> _slowModeLabels = [
    'Выкл',
    '10с',
    '30с',
    '1м',
    '5м',
    '15м',
    '1ч',
  ];

  late GroupDefaultPermissions _permissions;
  late int _slowModeInterval;
  bool _mediaExpanded = true;
  bool _isSaving = false;
  bool _savedAtLeastOnce = false;
  bool _membersChanged = false;

  List<ChatParticipant> _allMembers = [];
  List<ChatParticipant> _bannedMembers = [];

  @override
  void initState() {
    super.initState();
    _permissions = widget.initialPermissions;
    _slowModeInterval = _nearestSlowModeStop(widget.initialSlowMode);
    _mediaExpanded = _permissions.canSendMessages;
    unawaited(_loadLists());
  }

  int _nearestSlowModeStop(int raw) {
    if (_slowModeStops.contains(raw)) return raw;
    int best = 0;
    int bestDiff = 1 << 30;
    for (final stop in _slowModeStops) {
      final diff = (stop - raw).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = stop;
      }
    }
    return best;
  }

  Future<void> _loadLists() async {
    try {
      final results = await Future.wait([
        ChatService.getGroupMembers(widget.chatId),
        ChatService.getBannedChatMembers(widget.chatId),
      ]);
      if (!mounted) return;
      setState(() {
        _allMembers = results[0];
        _bannedMembers = results[1];
      });
    } catch (_) {}
  }

  List<ChatParticipant> get _restrictedMembers {
    final now = DateTime.now();
    return _allMembers.where((m) {
      if (m.memberRestrictions == null) return false;
      if (m.restrictedUntil != null && !m.restrictedUntil!.isAfter(now)) {
        return false;
      }
      return true;
    }).toList();
  }

  List<ChatParticipant> get _eligibleRegularMembers {
    return _allMembers
        .where((m) => m.role != 'owner' && m.role != 'admin')
        .toList();
  }

  String _slowModeDescription(int interval) {
    switch (interval) {
      case 0:
        return 'Участники могут отправлять сообщения без задержки.';
      case 10:
        return 'Участники могут отправлять не более одного сообщения каждые 10 секунд.';
      case 30:
        return 'Участники могут отправлять не более одного сообщения каждые 30 секунд.';
      case 60:
        return 'Участники могут отправлять не более одного сообщения в минуту.';
      case 300:
        return 'Участники могут отправлять не более одного сообщения раз в 5 минут.';
      case 900:
        return 'Участники могут отправлять не более одного сообщения раз в 15 минут.';
      case 3600:
        return 'Участники могут отправлять не более одного сообщения в час.';
      default:
        return 'Интервал между сообщениями: $interval с.';
    }
  }

  Future<void> _savePermissionsAndPop({bool popAfterSave = true}) async {
    if (_isSaving) return;
    HapticUtils.tap();
    setState(() => _isSaving = true);

    final res = await ChatService.updateGroupSettings(widget.chatId, {
      'default_permissions': _permissions.toJson(),
      'slow_mode_interval': _slowModeInterval,
    });

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (res['success'] == true) {
      _savedAtLeastOnce = true;
      GlassToastService().show(
        context,
        'Разрешения сохранены',
        iconWidget: const iconoir.Check(
          width: 18,
          height: 18,
          color: Color(0xFF34C759),
        ),
      );
      if (popAfterSave) {
        Navigator.pop(context, _buildResult());
      }
    } else {
      GlassToastService().showError(
        context,
        res['message']?.toString() ?? 'Не удалось сохранить разрешения',
      );
    }
  }

  Map<String, dynamic> _buildResult() {
    return {
      'default_permissions': _permissions,
      'slow_mode_interval': _slowModeInterval,
      'saved': _savedAtLeastOnce,
      'members_changed': _membersChanged,
    };
  }

  void _popWithResult() {
    Navigator.pop(context, _buildResult());
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    final stopIdx = _slowModeStops.indexOf(_slowModeInterval).clamp(0, 6);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _popWithResult();
      },
      child: SettingsFloatingScaffold(
        title: 'Разрешения',
        backgroundColor: palette.background,
        onBack: _popWithResult,
        actions: [
          if (_isSaving)
            SettingsHeaderAction(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: palette.primary,
                ),
              ),
            )
          else
            SettingsHeaderAction(
              tooltip: 'Сохранить',
              foregroundColor: palette.primary,
              icon: iconoir.Check(width: 22, height: 22, color: palette.primary),
              onTap: () => _savePermissionsAndPop(popAfterSave: true),
            ),
        ],
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            0,
            SettingsFloatingHeader.topClearanceOf(context) + 12,
            0,
            MediaQuery.paddingOf(context).bottom + 36,
          ),
          children: [
            TheavInsetGroup(
              header: 'ЧТО МОГУТ ДЕЛАТЬ УЧАСТНИКИ',
              children: [
                TheavListRow(
                  leading: iconoir.ChatBubble(
                    width: 20,
                    height: 20,
                    color: palette.primary,
                  ),
                  title: 'Отправка сообщений',
                  trailing: TheavSwitch(
                    value: _permissions.canSendMessages,
                    onChanged: (v) {
                      HapticUtils.selection();
                      setState(() {
                        _permissions = _permissions.copyWith(canSendMessages: v);
                        _mediaExpanded = v;
                      });
                    },
                  ),
                  onTap: () {
                    HapticUtils.selection();
                    final next = !_permissions.canSendMessages;
                    setState(() {
                      _permissions = _permissions.copyWith(canSendMessages: next);
                      _mediaExpanded = next;
                    });
                  },
                ),
                if (_permissions.canSendMessages) ...[
                  TheavListRow(
                    leading: iconoir.MediaImage(
                      width: 19,
                      height: 19,
                      color: palette.subtext,
                    ),
                    title: 'Медиа и вложения',
                    valueText:
                        '${(_permissions.canSendMedia ? 1 : 0) + (_permissions.canSendStickersGifs ? 1 : 0) + (_permissions.canSendPolls ? 1 : 0)}/3',
                    trailing: AnimatedRotation(
                      turns: _mediaExpanded ? 0.25 : 0.0,
                      duration: disableAnim
                          ? Duration.zero
                          : const Duration(milliseconds: 200),
                      child: iconoir.NavArrowRight(
                        width: 16,
                        height: 16,
                        color: palette.subtext,
                      ),
                    ),
                    onTap: () {
                      HapticUtils.selection();
                      setState(() => _mediaExpanded = !_mediaExpanded);
                    },
                  ),
                  if (_mediaExpanded) ...[
                    _nestedSwitchRow(
                      palette: palette,
                      icon: iconoir.MediaImage(
                        width: 18,
                        height: 18,
                        color: palette.primary,
                      ),
                      title: 'Отправка медиа',
                      value: _permissions.canSendMedia,
                      onChanged: (v) {
                        HapticUtils.selection();
                        setState(() {
                          _permissions = _permissions.copyWith(canSendMedia: v);
                        });
                      },
                    ),
                    _nestedSwitchRow(
                      palette: palette,
                      icon: iconoir.Emoji(
                        width: 18,
                        height: 18,
                        color: palette.primary,
                      ),
                      title: 'Стикеры и GIF',
                      value: _permissions.canSendStickersGifs,
                      onChanged: (v) {
                        HapticUtils.selection();
                        setState(() {
                          _permissions =
                              _permissions.copyWith(canSendStickersGifs: v);
                        });
                      },
                    ),
                    _nestedSwitchRow(
                      palette: palette,
                      icon: iconoir.StatsReport(
                        width: 18,
                        height: 18,
                        color: palette.primary,
                      ),
                      title: 'Опросы',
                      value: _permissions.canSendPolls,
                      onChanged: (v) {
                        HapticUtils.selection();
                        setState(() {
                          _permissions = _permissions.copyWith(canSendPolls: v);
                        });
                      },
                    ),
                  ],
                ],
                TheavListRow(
                  leading: iconoir.UserPlus(
                    width: 20,
                    height: 20,
                    color: palette.primary,
                  ),
                  title: 'Добавление участников',
                  trailing: TheavSwitch(
                    value: _permissions.canInviteUsers,
                    onChanged: (v) {
                      HapticUtils.selection();
                      setState(() {
                        _permissions = _permissions.copyWith(canInviteUsers: v);
                      });
                    },
                  ),
                  onTap: () {
                    HapticUtils.selection();
                    setState(() {
                      _permissions = _permissions.copyWith(
                        canInviteUsers: !_permissions.canInviteUsers,
                      );
                    });
                  },
                ),
                TheavListRow(
                  leading: iconoir.Pin(
                    width: 20,
                    height: 20,
                    color: palette.primary,
                  ),
                  title: 'Закрепление сообщений',
                  trailing: TheavSwitch(
                    value: _permissions.canPinMessages,
                    onChanged: (v) {
                      HapticUtils.selection();
                      setState(() {
                        _permissions = _permissions.copyWith(canPinMessages: v);
                      });
                    },
                  ),
                  onTap: () {
                    HapticUtils.selection();
                    setState(() {
                      _permissions = _permissions.copyWith(
                        canPinMessages: !_permissions.canPinMessages,
                      );
                    });
                  },
                ),
                TheavListRow(
                  leading: iconoir.EditPencil(
                    width: 20,
                    height: 20,
                    color: palette.primary,
                  ),
                  title: 'Изменение профиля группы',
                  trailing: TheavSwitch(
                    value: _permissions.canChangeInfo,
                    onChanged: (v) {
                      HapticUtils.selection();
                      setState(() {
                        _permissions = _permissions.copyWith(canChangeInfo: v);
                      });
                    },
                  ),
                  onTap: () {
                    HapticUtils.selection();
                    setState(() {
                      _permissions = _permissions.copyWith(
                        canChangeInfo: !_permissions.canChangeInfo,
                      );
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            TheavInsetGroup(
              header: 'МЕДЛЕННЫЙ РЕЖИМ',
              footer: _slowModeDescription(_slowModeInterval),
              children: [
                TheavSteppedSlider(
                  title: 'Задержка между сообщениями',
                  selectedIndex: stopIdx,
                  labels: _slowModeLabels,
                  onChanged: (idx) {
                    setState(() => _slowModeInterval = _slowModeStops[idx]);
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),
            TheavInsetGroup(
              header: 'ОГРАНИЧЕНИЯ И ДОСТУП',
              children: [
                TheavListRow(
                  leading: iconoir.Lock(
                    width: 20,
                    height: 20,
                    color: palette.primary,
                  ),
                  title: 'Исключения',
                  valueText: '${_restrictedMembers.length}',
                  showChevron: true,
                  onTap: _openExceptionsSheet,
                ),
                TheavListRow(
                  leading: iconoir.UserXmark(
                    width: 20,
                    height: 20,
                    color: palette.error,
                  ),
                  title: 'Чёрный список',
                  valueText: '${_bannedMembers.length}',
                  showChevron: true,
                  onTap: _openBlacklistSheet,
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _nestedSwitchRow({
    required TheavPalette palette,
    required Widget icon,
    required String title,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return TheavListRow(
      padding: const EdgeInsets.fromLTRB(34, 10, 16, 10),
      leading: icon,
      title: title,
      trailing: TheavSwitch(value: value, onChanged: onChanged),
      onTap: () => onChanged(!value),
    );
  }

  Future<void> _openExceptionsSheet() async {
    await showTheavModalSheet<void>(
      context: context,
      title: 'Исключения (${_restrictedMembers.length})',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final palette = ctx.theav;
          final restricted = _restrictedMembers;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TheavInsetGroup(
                  children: [
                    TheavListRow(
                      leading: iconoir.Plus(
                        width: 20,
                        height: 20,
                        color: palette.primary,
                      ),
                      title: 'Добавить исключение',
                      onTap: () async {
                        await _openAddExceptionPicker();
                        if (ctx.mounted) setSheetState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (restricted.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Участники с индивидуальными ограничениями прав появятся здесь.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13.5, color: palette.subtext),
                    ),
                  )
                else
                  TheavInsetGroup(
                    children: [
                      for (final m in restricted)
                        TheavListRow(
                          leading: AvatarWithStatus(
                            userId: m.id,
                            avatarUrl: m.avatarUrl,
                            name: m.displayName,
                            radius: 20,
                          ),
                          title: m.displayName,
                          subtitle: _formatRestrictionsSummary(m),
                          showChevron: true,
                          onTap: () async {
                            await _openRestrictionEditorSheet(m);
                            if (ctx.mounted) setSheetState(() {});
                          },
                        ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _openBlacklistSheet() async {
    await showTheavModalSheet<void>(
      context: context,
      title: 'Чёрный список (${_bannedMembers.length})',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final palette = ctx.theav;
          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TheavInsetGroup(
                  children: [
                    TheavListRow(
                      leading: iconoir.UserXmark(
                        width: 20,
                        height: 20,
                        color: palette.error,
                      ),
                      title: 'Заблокировать участника',
                      isDestructive: true,
                      onTap: () async {
                        await _openAddBanPicker();
                        if (ctx.mounted) setSheetState(() {});
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (_bannedMembers.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Заблокированные пользователи не смогут вернуться в группу и просматривать её.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13.5, color: palette.subtext),
                    ),
                  )
                else
                  TheavInsetGroup(
                    children: [
                      for (final banned in _bannedMembers)
                        TheavListRow(
                          leading: AvatarWithStatus(
                            userId: banned.id,
                            avatarUrl: banned.avatarUrl,
                            name: banned.displayName,
                            radius: 20,
                          ),
                          title: banned.displayName.isNotEmpty
                              ? banned.displayName
                              : '@${banned.username}',
                          subtitle: banned.username.isNotEmpty
                              ? '@${banned.username}'
                              : null,
                          trailing: TheavFloatingPillButton(
                            height: 32,
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            label: 'Разблокировать',
                            onTap: () async {
                              await _unbanUser(banned);
                              if (ctx.mounted) setSheetState(() {});
                            },
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }

  String _formatRestrictionsSummary(ChatParticipant member) {
    final r = member.memberRestrictions;
    if (r == null) return 'Без ограничений';
    if (!r.canSendMessages) return 'Только чтение';
    final denied = <String>[];
    if (!r.canSendMedia) denied.add('без медиа');
    if (!r.canSendStickersGifs) denied.add('без стикеров');
    if (!r.canSendPolls) denied.add('без опросов');
    if (!r.canInviteUsers) denied.add('без приглашений');
    if (!r.canPinMessages) denied.add('без закрепления');
    if (denied.isEmpty) return 'Индивидуальные права';
    return denied.take(2).join(', ');
  }

  Future<void> _openAddExceptionPicker() async {
    final candidates = _eligibleRegularMembers;
    if (candidates.isEmpty) {
      GlassToastService().show(context, 'Нет доступных участников');
      return;
    }
    final picked = await _pickMemberSheet(
      title: 'Выберите участника',
      members: candidates,
    );
    if (picked != null && mounted) {
      await _openRestrictionEditorSheet(picked);
    }
  }

  Future<void> _openAddBanPicker() async {
    final candidates = _eligibleRegularMembers;
    if (candidates.isEmpty) {
      GlassToastService().show(context, 'Нет доступных участников');
      return;
    }
    final picked = await _pickMemberSheet(
      title: 'Заблокировать участника',
      members: candidates,
    );
    if (picked == null || !mounted) return;
    final ok = await ChatService.banChatMember(
      chatId: widget.chatId,
      userId: picked.id,
    );
    if (!mounted) return;
    if (ok) {
      _membersChanged = true;
      GlassToastService().show(context, 'Пользователь заблокирован');
      await _loadLists();
    } else {
      GlassToastService().showError(
        context,
        'Не удалось заблокировать пользователя',
      );
    }
  }

  Future<void> _unbanUser(ChatParticipant user) async {
    HapticUtils.tap();
    final ok = await ChatService.unbanChatMember(
      chatId: widget.chatId,
      userId: user.id,
    );
    if (!mounted) return;
    if (ok) {
      _membersChanged = true;
      setState(() {
        _bannedMembers.removeWhere((m) => m.id == user.id);
      });
      GlassToastService().show(context, 'Пользователь разблокирован');
    } else {
      GlassToastService().showError(context, 'Не удалось снять блокировку');
    }
  }

  Future<ChatParticipant?> _pickMemberSheet({
    required String title,
    required List<ChatParticipant> members,
  }) {
    return showTheavModalSheet<ChatParticipant>(
      context: context,
      title: title,
      builder: (ctx) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
        child: TheavInsetGroup(
          children: [
            for (final m in members)
              TheavListRow(
                leading: AvatarWithStatus(
                  userId: m.id,
                  avatarUrl: m.avatarUrl,
                  name: m.displayName,
                  radius: 20,
                ),
                title: m.displayName.isNotEmpty
                    ? m.displayName
                    : '@${m.username}',
                subtitle: m.username.isNotEmpty ? '@${m.username}' : null,
                showChevron: true,
                onTap: () => Navigator.pop(ctx, m),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRestrictionEditorSheet(ChatParticipant member) async {
    var current = member.memberRestrictions ??
        MemberRestrictions(
          canSendMessages: _permissions.canSendMessages,
          canSendMedia: _permissions.canSendMedia,
          canSendStickersGifs: _permissions.canSendStickersGifs,
          canSendPolls: _permissions.canSendPolls,
          canPinMessages: _permissions.canPinMessages,
          canInviteUsers: _permissions.canInviteUsers,
          canChangeInfo: _permissions.canChangeInfo,
        );
    Duration? duration;
    var saving = false;

    final saved = await showTheavModalSheet<bool>(
      context: context,
      title: 'Ограничения: ${member.displayName}',
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final palette = ctx.theav;
          final durations = <({String label, Duration? value})>[
            (label: 'Навсегда', value: null),
            (label: '1 час', value: const Duration(hours: 1)),
            (label: '1 день', value: const Duration(days: 1)),
            (label: '1 неделя', value: const Duration(days: 7)),
            (label: '1 месяц', value: const Duration(days: 30)),
          ];

          return SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TheavInsetGroup(
                  dividerIndent: 16,
                  children: [
                    _sheetToggle(
                      'Отправка сообщений',
                      current.canSendMessages,
                      (v) => setSheetState(
                        () => current = current.copyWith(canSendMessages: v),
                      ),
                    ),
                    _sheetToggle(
                      'Отправка медиа',
                      current.canSendMedia,
                      (v) => setSheetState(
                        () => current = current.copyWith(canSendMedia: v),
                      ),
                    ),
                    _sheetToggle(
                      'Стикеры и GIF',
                      current.canSendStickersGifs,
                      (v) => setSheetState(
                        () => current =
                            current.copyWith(canSendStickersGifs: v),
                      ),
                    ),
                    _sheetToggle(
                      'Опросы',
                      current.canSendPolls,
                      (v) => setSheetState(
                        () => current = current.copyWith(canSendPolls: v),
                      ),
                    ),
                    _sheetToggle(
                      'Добавление участников',
                      current.canInviteUsers,
                      (v) => setSheetState(
                        () => current = current.copyWith(canInviteUsers: v),
                      ),
                    ),
                    _sheetToggle(
                      'Закрепление сообщений',
                      current.canPinMessages,
                      (v) => setSheetState(
                        () => current = current.copyWith(canPinMessages: v),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 22),
                  child: Text(
                    'СРОК ОГРАНИЧЕНИЯ',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: palette.subtext,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final opt in durations)
                        TheavFloatingPillButton(
                          height: 36,
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          label: opt.label,
                          isPrimary: duration == opt.value,
                          onTap: () => setSheetState(() => duration = opt.value),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 18),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    children: [
                      if (member.memberRestrictions != null) ...[
                        Expanded(
                          child: TheavFloatingPillButton(
                            enabled: !saving,
                            label: 'Сбросить',
                            onTap: () async {
                              setSheetState(() => saving = true);
                              final ok =
                                  await ChatService.updateMemberRestrictions(
                                chatId: widget.chatId,
                                userId: member.id,
                                restrictions: const MemberRestrictions(),
                                restrictedUntil: null,
                              );
                              if (ctx.mounted) Navigator.pop(ctx, ok);
                            },
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: TheavFloatingPillButton(
                          isPrimary: true,
                          enabled: !saving,
                          label: saving ? 'Сохранение...' : 'Сохранить',
                          onTap: () async {
                            setSheetState(() => saving = true);
                            final until = duration != null
                                ? DateTime.now().add(duration!)
                                : null;
                            final ok =
                                await ChatService.updateMemberRestrictions(
                              chatId: widget.chatId,
                              userId: member.id,
                              restrictions: current,
                              restrictedUntil: until,
                            );
                            if (ctx.mounted) Navigator.pop(ctx, ok);
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    if (saved == true && mounted) {
      _membersChanged = true;
      GlassToastService().show(context, 'Ограничения обновлены');
      await _loadLists();
    }
  }

  Widget _sheetToggle(
    String title,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return TheavListRow(
      title: title,
      trailing: TheavSwitch(value: value, onChanged: onChanged),
      onTap: () => onChanged(!value),
    );
  }
}
