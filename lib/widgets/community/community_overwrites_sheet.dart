import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../models/community_models.dart';
import '../../services/community_service.dart';
import '../../services/glass_toast_service.dart';
import '../../utils/haptic_utils.dart';
import '../design_system/theav_design_system.dart';

/// Opens a dual-mode bottom sheet to configure role permission overwrites
/// (Deny / Inherit / Allow) for either a specific channel or a category.
Future<bool?> showCommunityOverwritesSheet(
  BuildContext context, {
  required Community community,
  required String targetName,
  String? chatId,
  String? categoryId,
}) {
  assert(chatId != null || categoryId != null);
  return showTheavModalSheet<bool>(
    context: context,
    title: 'Права: $targetName',
    showCloseButton: true,
    maxHeightFactor: 0.9,
    padding: EdgeInsets.zero,
    builder: (ctx) => _CommunityOverwritesBody(
      community: community,
      chatId: chatId,
      categoryId: categoryId,
    ),
  );
}

class _CommunityOverwritesBody extends StatefulWidget {
  final Community community;
  final String? chatId;
  final String? categoryId;

  const _CommunityOverwritesBody({
    required this.community,
    this.chatId,
    this.categoryId,
  });

  @override
  State<_CommunityOverwritesBody> createState() =>
      _CommunityOverwritesBodyState();
}

class _CommunityOverwritesBodyState extends State<_CommunityOverwritesBody> {
  static const List<({int bit, String title, String subtitle})> _kChannelFlags = [
    (
      bit: CommunityPermissions.viewChannel,
      title: 'Просмотр канала',
      subtitle: 'Видимость канала в дереве и чтение ленты',
    ),
    (
      bit: CommunityPermissions.sendMessages,
      title: 'Отправка сообщений',
      subtitle: 'Публикация сообщений и медиа в текстовом канале',
    ),
    (
      bit: CommunityPermissions.connectVoice,
      title: 'Подключение к голосу',
      subtitle: 'Вход в голосовую комнату или трибуну',
    ),
    (
      bit: CommunityPermissions.speakVoice,
      title: 'Говорить в комнате',
      subtitle: 'Включение микрофона в голосовом канале',
    ),
    (
      bit: CommunityPermissions.video,
      title: 'Видеокамера',
      subtitle: 'Трансляция веб-камеры в комнате',
    ),
    (
      bit: CommunityPermissions.streamVideo,
      title: 'Go Live (демонстрация экрана)',
      subtitle: 'Стриминг экрана или окна',
    ),
    (
      bit: CommunityPermissions.useSoundboard,
      title: 'Саундборд',
      subtitle: 'Воспроизведение звуковых клипов сообщества',
    ),
    (
      bit: CommunityPermissions.manageStage,
      title: 'Управление трибуной',
      subtitle: 'Приглашение спикеров на сцену и эфир',
    ),
    (
      bit: CommunityPermissions.manageChannels,
      title: 'Управление каналом',
      subtitle: 'Редактирование названия, темы и медленного режима',
    ),
  ];

  bool _loading = true;
  bool _saving = false;
  late String _selectedRoleId;
  final Map<String, CommunityPermissionOverwrite> _roleOverwrites = {};
  List<CommunityPermissionOverwrite> _memberOverwrites = const [];

  @override
  void initState() {
    super.initState();
    final roles = widget.community.roles;
    _selectedRoleId = roles.isNotEmpty ? roles.first.id : '';
    _loadOverwrites();
  }

  Future<void> _loadOverwrites() async {
    setState(() => _loading = true);
    final List<CommunityPermissionOverwrite> fetched;
    if (widget.chatId != null) {
      fetched = await CommunityService.getChannelOverwrites(
        widget.community.id,
        widget.chatId!,
      );
    } else {
      fetched = await CommunityService.getCategoryOverwrites(
        widget.community.id,
        widget.categoryId!,
      );
    }
    if (!mounted) return;
    _roleOverwrites.clear();
    final memberList = <CommunityPermissionOverwrite>[];
    for (final ow in fetched) {
      if (ow.targetType == 'role') {
        _roleOverwrites[ow.targetId] = ow;
      } else {
        memberList.add(ow);
      }
    }
    setState(() {
      _memberOverwrites = memberList;
      _loading = false;
    });
  }

  CommunityPermissionOverwrite _currentOverwrite(String roleId) {
    return _roleOverwrites[roleId] ??
        CommunityPermissionOverwrite(targetType: 'role', targetId: roleId);
  }

  void _updateBit(int bit, PermissionOverwriteState state) {
    if (_selectedRoleId.isEmpty) return;
    HapticUtils.selection();
    final current = _currentOverwrite(_selectedRoleId);
    final updated = current.withBitState(bit, state);
    setState(() {
      if (updated.isEmpty) {
        _roleOverwrites.remove(_selectedRoleId);
      } else {
        _roleOverwrites[_selectedRoleId] = updated;
      }
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() => _saving = true);
    final all = <CommunityPermissionOverwrite>[
      ..._roleOverwrites.values.where((o) => !o.isEmpty),
      ..._memberOverwrites.where((o) => !o.isEmpty),
    ];
    final bool ok;
    if (widget.chatId != null) {
      ok = await CommunityService.setChannelOverwrites(
        widget.community.id,
        widget.chatId!,
        all,
      );
    } else {
      ok = await CommunityService.setCategoryOverwrites(
        widget.community.id,
        widget.categoryId!,
        all,
      );
    }
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok) {
      GlassToastService().show(context, 'Переопределения прав сохранены');
      Navigator.of(context).pop(true);
    } else {
      GlassToastService().showError(context, 'Не удалось сохранить права');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final roles = widget.community.roles;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (roles.isNotEmpty)
          SizedBox(
            height: 44,
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              scrollDirection: Axis.horizontal,
              itemCount: roles.length,
              separatorBuilder: (_, __) => const SizedBox(width: 8),
              itemBuilder: (ctx, i) {
                final role = roles[i];
                final selected = role.id == _selectedRoleId;
                final roleColor = role.parsedColor ?? palette.primary;
                final hasOverride =
                    _roleOverwrites.containsKey(role.id) &&
                    !_roleOverwrites[role.id]!.isEmpty;
                return GestureDetector(
                  onTap: () {
                    HapticUtils.selection();
                    setState(() => _selectedRoleId = role.id);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 160),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: selected
                          ? roleColor.withValues(alpha: 0.16)
                          : palette.onSurface.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected
                            ? roleColor
                            : palette.divider,
                        width: selected ? 1.1 : 0.5,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            color: role.isEveryone
                                ? palette.subtext
                                : roleColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 7),
                        Text(
                          role.name,
                          style: TextStyle(
                            color: selected ? palette.onSurface : palette.subtext,
                            fontSize: 13.5,
                            fontWeight: selected
                                ? FontWeight.w600
                                : FontWeight.w500,
                          ),
                        ),
                        if (hasOverride) ...[
                          const SizedBox(width: 6),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: palette.primary,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        const SizedBox(height: 8),
        Flexible(
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.all(40),
                  child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
                )
              : roles.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Нет доступных ролей для настройки',
                        style: TextStyle(color: palette.subtext),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 12),
                      children: [
                        TheavInsetGroup(
                          header: widget.categoryId != null
                              ? 'ПРАВА КАТЕГОРИИ'
                              : 'ПРАВА КАНАЛА',
                          footer:
                              'Нажмите ✕ чтобы запретить, / чтобы наследовать от роли и ✓ чтобы явно разрешить.',
                          dividerIndent: 16,
                          children: _kChannelFlags.map((flag) {
                            final current = _currentOverwrite(_selectedRoleId);
                            final state = current.stateForBit(flag.bit);
                            return TheavListRow(
                              title: flag.title,
                              subtitle: flag.subtitle,
                              trailing: _TriStateOverwriteControl(
                                state: state,
                                onChanged: (s) => _updateBit(flag.bit, s),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 14),
            child: SizedBox(
              width: double.infinity,
              child: TheavFloatingPillButton(
                label: _saving ? 'Сохранение...' : 'Сохранить переопределения',
                icon: _saving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const iconoir.ShieldCheck(width: 18, height: 18),
                isPrimary: true,
                enabled: !_saving && !_loading && roles.isNotEmpty,
                onTap: _save,
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _TriStateOverwriteControl extends StatelessWidget {
  final PermissionOverwriteState state;
  final ValueChanged<PermissionOverwriteState> onChanged;

  const _TriStateOverwriteControl({
    required this.state,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    return Container(
      height: 30,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: palette.onSurface.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: palette.divider, width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildSegment(
            context,
            selected: state == PermissionOverwriteState.deny,
            activeColor: palette.error,
            child: iconoir.Xmark(
              width: 14,
              height: 14,
              color: state == PermissionOverwriteState.deny
                  ? Colors.white
                  : palette.subtext,
            ),
            onTap: () => onChanged(PermissionOverwriteState.deny),
          ),
          _buildSegment(
            context,
            selected: state == PermissionOverwriteState.inherit,
            activeColor: palette.subtext.withValues(alpha: 0.45),
            child: Text(
              '/',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: state == PermissionOverwriteState.inherit
                    ? Colors.white
                    : palette.subtext,
              ),
            ),
            onTap: () => onChanged(PermissionOverwriteState.inherit),
          ),
          _buildSegment(
            context,
            selected: state == PermissionOverwriteState.allow,
            activeColor: const Color(0xFF10B981),
            child: iconoir.Check(
              width: 14,
              height: 14,
              color: state == PermissionOverwriteState.allow
                  ? Colors.white
                  : palette.subtext,
            ),
            onTap: () => onChanged(PermissionOverwriteState.allow),
          ),
        ],
      ),
    );
  }

  Widget _buildSegment(
    BuildContext context, {
    required bool selected,
    required Color activeColor,
    required Widget child,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 140),
        width: 28,
        height: 26,
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}
