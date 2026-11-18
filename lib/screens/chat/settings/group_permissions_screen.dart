import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../../models/theav_theme.dart';
import '../../../services/chat_service.dart';
import '../../../services/glass_toast_service.dart';
import '../../../services/liquid_glass_provider.dart';
import '../../../utils/haptic_utils.dart';
import '../../../widgets/common/adaptive_switch.dart';
import '../../../widgets/settings/settings_floating_header.dart';
import '../../../widgets/user/avatar_with_status.dart';

/// Group permissions, slow mode, per-user restriction exceptions, and blacklist screen.
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
  int _activeTab = 0; // 0 = Разрешения, 1 = Исключения, 2 = Чёрный список
  bool _isSaving = false;
  bool _isLoadingMembers = true;
  bool _isLoadingBanned = true;
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
        _isLoadingMembers = false;
        _isLoadingBanned = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _isLoadingMembers = false;
        _isLoadingBanned = false;
      });
    }
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
      GlassToastService().show(
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themeExt = theme.extension<TheavThemeExtension>();
    final glassProvider = maybeLiquidGlassProvider(context);
    final accentColor = themeExt?.palette.primary ??
        (isDark ? const Color(0xFF64B5F6) : const Color(0xFF0088CC));
    final bgColor = isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF5F5F7);
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.68)
        : const Color(0xFF475569);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _popWithResult();
      },
      child: SettingsFloatingScaffold(
        title: 'Разрешения',
        backgroundColor: bgColor,
        onBack: _popWithResult,
        actions: [
          if (_isSaving)
            const SettingsHeaderAction(
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            SettingsHeaderAction(
              tooltip: 'Сохранить',
              foregroundColor: accentColor,
              icon: iconoir.Check(width: 22, height: 22, color: accentColor),
              onTap: () => _savePermissionsAndPop(popAfterSave: true),
            ),
        ],
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            SettingsFloatingHeader.topClearanceOf(context) + 12,
            16,
            36,
          ),
          children: [
            _buildSegmentedTabs(
              context,
              glassProvider: glassProvider,
              isDark: isDark,
              accentColor: accentColor,
              textColor: textColor,
              subColor: subColor,
            ),
            const SizedBox(height: 18),
            if (_activeTab == 0)
              _buildGlobalPermissionsTab(
                context,
                glassProvider: glassProvider,
                isDark: isDark,
                accentColor: accentColor,
                textColor: textColor,
                subColor: subColor,
              )
            else if (_activeTab == 1)
              _buildExceptionsTab(
                context,
                glassProvider: glassProvider,
                isDark: isDark,
                accentColor: accentColor,
                textColor: textColor,
                subColor: subColor,
              )
            else
              _buildBlacklistTab(
                context,
                glassProvider: glassProvider,
                isDark: isDark,
                accentColor: accentColor,
                textColor: textColor,
                subColor: subColor,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSegmentedTabs(
    BuildContext context, {
    required LiquidGlassProvider? glassProvider,
    required bool isDark,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
  }) {
    final labels = [
      'Разрешения',
      'Исключения (${_restrictedMembers.length})',
      'Чёрный список (${_bannedMembers.length})',
    ];
    final selectedFg = accentColor.computeLuminance() > 0.35
        ? const Color(0xFF0F172A)
        : Colors.white;

    return _buildSurfaceCard(
      context,
      glassProvider: glassProvider,
      isDark: isDark,
      radius: 18,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Row(
          children: [
            for (int i = 0; i < labels.length; i++)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    HapticUtils.selection();
                    setState(() => _activeTab = i);
                  },
                  child: AnimatedContainer(
                    duration: MediaQuery.disableAnimationsOf(context)
                        ? Duration.zero
                        : const Duration(milliseconds: 200),
                    curve: Curves.easeOutCubic,
                    constraints: const BoxConstraints(minHeight: 40),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _activeTab == i
                          ? accentColor
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(14),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      labels[i],
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: _activeTab == i ? selectedFg : textColor,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildGlobalPermissionsTab(
    BuildContext context, {
    required LiquidGlassProvider? glassProvider,
    required bool isDark,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
  }) {
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    final stopIdx = _slowModeStops.indexOf(_slowModeInterval).clamp(0, 6);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 14, bottom: 8),
          child: Text(
            'ЧТО МОГУТ ДЕЛАТЬ УЧАСТНИКИ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
              color: subColor,
            ),
          ),
        ),
        _buildSurfaceCard(
          context,
          glassProvider: glassProvider,
          isDark: isDark,
          child: Column(
            children: [
              _buildSwitchRow(
                glassProvider: glassProvider,
                icon: iconoir.ChatBubble(
                  width: 20,
                  height: 20,
                  color: accentColor,
                ),
                title: 'Отправка сообщений',
                value: _permissions.canSendMessages,
                accentColor: accentColor,
                textColor: textColor,
                onChanged: (v) {
                  HapticUtils.selection();
                  setState(() {
                    _permissions = _permissions.copyWith(canSendMessages: v);
                    _mediaExpanded = v;
                  });
                },
              ),
              if (_permissions.canSendMessages)
                Divider(height: 1, indent: 54, color: dividerColor),
              AnimatedSize(
                duration: disableAnim
                    ? Duration.zero
                    : const Duration(milliseconds: 220),
                curve: Curves.easeOutCubic,
                child: _permissions.canSendMessages
                    ? Column(
                        children: [
                          InkWell(
                            onTap: () {
                              HapticUtils.selection();
                              setState(
                                () => _mediaExpanded = !_mediaExpanded,
                              );
                            },
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(minHeight: 46),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 8,
                                ),
                                child: Row(
                                  children: [
                                    SizedBox(
                                      width: 28,
                                      child: Center(
                                        child: iconoir.MediaImage(
                                          width: 19,
                                          height: 19,
                                          color: subColor,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 14),
                                    Expanded(
                                      child: Text(
                                        'Медиа и вложения',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: subColor,
                                        ),
                                      ),
                                    ),
                                    Text(
                                      '${(_permissions.canSendMedia ? 1 : 0) + (_permissions.canSendStickersGifs ? 1 : 0) + (_permissions.canSendPolls ? 1 : 0)}/3',
                                      style: TextStyle(
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                        color: accentColor,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    AnimatedRotation(
                                      turns: _mediaExpanded ? 0.25 : 0.0,
                                      duration: disableAnim
                                          ? Duration.zero
                                          : const Duration(milliseconds: 200),
                                      child: iconoir.NavArrowRight(
                                        width: 16,
                                        height: 16,
                                        color: subColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                          AnimatedSize(
                            duration: disableAnim
                                ? Duration.zero
                                : const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            child: _mediaExpanded
                                ? Padding(
                                    padding: const EdgeInsets.only(left: 16),
                                    child: Column(
                                      children: [
                                        Divider(
                                          height: 1,
                                          indent: 38,
                                          color: dividerColor,
                                        ),
                                        _buildSwitchRow(
                                          glassProvider: glassProvider,
                                          icon: iconoir.MediaImage(
                                            width: 18,
                                            height: 18,
                                            color: accentColor,
                                          ),
                                          title: 'Отправка медиа',
                                          value: _permissions.canSendMedia,
                                          accentColor: accentColor,
                                          textColor: textColor,
                                          onChanged: (v) {
                                            HapticUtils.selection();
                                            setState(() {
                                              _permissions = _permissions
                                                  .copyWith(canSendMedia: v);
                                            });
                                          },
                                        ),
                                        Divider(
                                          height: 1,
                                          indent: 38,
                                          color: dividerColor,
                                        ),
                                        _buildSwitchRow(
                                          glassProvider: glassProvider,
                                          icon: iconoir.Emoji(
                                            width: 18,
                                            height: 18,
                                            color: accentColor,
                                          ),
                                          title: 'Стикеры и GIF',
                                          value:
                                              _permissions.canSendStickersGifs,
                                          accentColor: accentColor,
                                          textColor: textColor,
                                          onChanged: (v) {
                                            HapticUtils.selection();
                                            setState(() {
                                              _permissions =
                                                  _permissions.copyWith(
                                                canSendStickersGifs: v,
                                              );
                                            });
                                          },
                                        ),
                                        Divider(
                                          height: 1,
                                          indent: 38,
                                          color: dividerColor,
                                        ),
                                        _buildSwitchRow(
                                          glassProvider: glassProvider,
                                          icon: iconoir.StatsReport(
                                            width: 18,
                                            height: 18,
                                            color: accentColor,
                                          ),
                                          title: 'Опросы',
                                          value: _permissions.canSendPolls,
                                          accentColor: accentColor,
                                          textColor: textColor,
                                          onChanged: (v) {
                                            HapticUtils.selection();
                                            setState(() {
                                              _permissions = _permissions
                                                  .copyWith(canSendPolls: v);
                                            });
                                          },
                                        ),
                                      ],
                                    ),
                                  )
                                : const SizedBox.shrink(),
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
              Divider(height: 1, indent: 54, color: dividerColor),
              _buildSwitchRow(
                glassProvider: glassProvider,
                icon: iconoir.UserPlus(
                  width: 20,
                  height: 20,
                  color: accentColor,
                ),
                title: 'Добавление участников',
                value: _permissions.canInviteUsers,
                accentColor: accentColor,
                textColor: textColor,
                onChanged: (v) {
                  HapticUtils.selection();
                  setState(() {
                    _permissions = _permissions.copyWith(canInviteUsers: v);
                  });
                },
              ),
              Divider(height: 1, indent: 54, color: dividerColor),
              _buildSwitchRow(
                glassProvider: glassProvider,
                icon: iconoir.Pin(width: 20, height: 20, color: accentColor),
                title: 'Закрепление сообщений',
                value: _permissions.canPinMessages,
                accentColor: accentColor,
                textColor: textColor,
                onChanged: (v) {
                  HapticUtils.selection();
                  setState(() {
                    _permissions = _permissions.copyWith(canPinMessages: v);
                  });
                },
              ),
              Divider(height: 1, indent: 54, color: dividerColor),
              _buildSwitchRow(
                glassProvider: glassProvider,
                icon: iconoir.EditPencil(
                  width: 20,
                  height: 20,
                  color: accentColor,
                ),
                title: 'Изменение профиля группы',
                value: _permissions.canChangeInfo,
                accentColor: accentColor,
                textColor: textColor,
                onChanged: (v) {
                  HapticUtils.selection();
                  setState(() {
                    _permissions = _permissions.copyWith(canChangeInfo: v);
                  });
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.only(left: 14, bottom: 8),
          child: Row(
            children: [
              iconoir.Timer(width: 15, height: 15, color: subColor),
              const SizedBox(width: 6),
              Text(
                'МЕДЛЕННЫЙ РЕЖИМ',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: subColor,
                ),
              ),
            ],
          ),
        ),
        _buildSurfaceCard(
          context,
          glassProvider: glassProvider,
          isDark: isDark,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Задержка между сообщениями',
                      style: TextStyle(
                        fontSize: 14.5,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        _slowModeLabels[stopIdx],
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                          color: accentColor,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                SliderTheme(
                  data: SliderTheme.of(context).copyWith(
                    activeTrackColor: accentColor,
                    inactiveTrackColor: accentColor.withValues(alpha: 0.2),
                    thumbColor: accentColor,
                    overlayColor: accentColor.withValues(alpha: 0.16),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: stopIdx.toDouble(),
                    min: 0,
                    max: (_slowModeStops.length - 1).toDouble(),
                    divisions: _slowModeStops.length - 1,
                    label: _slowModeLabels[stopIdx],
                    onChanged: (v) {
                      final idx = v.round().clamp(0, _slowModeStops.length - 1);
                      if (_slowModeStops[idx] != _slowModeInterval) {
                        HapticUtils.selection();
                        setState(() => _slowModeInterval = _slowModeStops[idx]);
                      }
                    },
                  ),
                ),
                Row(
                  children: [
                    for (int i = 0; i < _slowModeStops.length; i++)
                      Expanded(
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            HapticUtils.selection();
                            setState(
                              () => _slowModeInterval = _slowModeStops[i],
                            );
                          },
                          child: Container(
                            constraints: const BoxConstraints(minHeight: 36),
                            alignment: Alignment.center,
                            child: Text(
                              _slowModeLabels[i],
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: i == stopIdx
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                                color: i == stopIdx ? accentColor : subColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(left: 14, top: 8, right: 14),
          child: Text(
            _slowModeDescription(_slowModeInterval),
            style: TextStyle(fontSize: 12.5, color: subColor, height: 1.35),
          ),
        ),
        const SizedBox(height: 22),
        Builder(
          builder: (_) {
            final buttonFg = accentColor.computeLuminance() > 0.35
                ? const Color(0xFF0F172A)
                : Colors.white;
            return SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _isSaving
                    ? null
                    : () => _savePermissionsAndPop(popAfterSave: true),
                style: FilledButton.styleFrom(
                  backgroundColor: accentColor,
                  foregroundColor: buttonFg,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: iconoir.Check(
                  width: 20,
                  height: 20,
                  color: buttonFg,
                ),
                label: const Text(
                  'Сохранить разрешения',
                  style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildExceptionsTab(
    BuildContext context, {
    required LiquidGlassProvider? glassProvider,
    required bool isDark,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
  }) {
    final restricted = _restrictedMembers;
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSurfaceCard(
          context,
          glassProvider: glassProvider,
          isDark: isDark,
          child: ListTile(
            minTileHeight: 52,
            leading: iconoir.Plus(width: 22, height: 22, color: accentColor),
            title: Text(
              'Добавить исключение',
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                color: accentColor,
              ),
            ),
            onTap: _openAddExceptionPicker,
          ),
        ),
        const SizedBox(height: 14),
        if (_isLoadingMembers)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (restricted.isEmpty)
          _buildEmptyStateCard(
            context,
            glassProvider: glassProvider,
            isDark: isDark,
            accentColor: accentColor,
            textColor: textColor,
            subColor: subColor,
            icon: iconoir.Lock(width: 26, height: 26, color: accentColor),
            title: 'Нет исключений',
            subtitle:
                'Участники с индивидуальными ограничениями прав появятся в этом списке.',
          )
        else
          _buildSurfaceCard(
            context,
            glassProvider: glassProvider,
            isDark: isDark,
            child: Column(
              children: [
                for (int i = 0; i < restricted.length; i++) ...[
                  ListTile(
                    minTileHeight: 58,
                    leading: AvatarWithStatus(
                      userId: restricted[i].id,
                      avatarUrl: restricted[i].avatarUrl,
                      name: restricted[i].displayName,
                      radius: 21,
                    ),
                    title: Text(
                      restricted[i].displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    subtitle: Text(
                      _formatRestrictionsSummary(restricted[i]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: subColor),
                    ),
                    trailing: iconoir.NavArrowRight(
                      width: 18,
                      height: 18,
                      color: subColor,
                    ),
                    onTap: () => _openRestrictionEditorSheet(restricted[i]),
                  ),
                  if (i < restricted.length - 1)
                    Divider(height: 1, indent: 70, color: dividerColor),
                ],
              ],
            ),
          ),
      ],
    );
  }

  Widget _buildBlacklistTab(
    BuildContext context, {
    required LiquidGlassProvider? glassProvider,
    required bool isDark,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
  }) {
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSurfaceCard(
          context,
          glassProvider: glassProvider,
          isDark: isDark,
          child: ListTile(
            minTileHeight: 52,
            leading: const iconoir.UserXmark(
              width: 22,
              height: 22,
              color: Colors.redAccent,
            ),
            title: const Text(
              'Заблокировать участника',
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w600,
                color: Colors.redAccent,
              ),
            ),
            onTap: _openAddBanPicker,
          ),
        ),
        const SizedBox(height: 14),
        if (_isLoadingBanned)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator()),
          )
        else if (_bannedMembers.isEmpty)
          _buildEmptyStateCard(
            context,
            glassProvider: glassProvider,
            isDark: isDark,
            accentColor: accentColor,
            textColor: textColor,
            subColor: subColor,
            icon: const iconoir.UserXmark(
              width: 26,
              height: 26,
              color: Colors.redAccent,
            ),
            title: 'Чёрный список пуст',
            subtitle:
                'Заблокированные пользователи не смогут вернуться в группу и просматривать её.',
          )
        else
          _buildSurfaceCard(
            context,
            glassProvider: glassProvider,
            isDark: isDark,
            child: Column(
              children: [
                for (int i = 0; i < _bannedMembers.length; i++) ...[
                  ListTile(
                    minTileHeight: 60,
                    leading: AvatarWithStatus(
                      userId: _bannedMembers[i].id,
                      avatarUrl: _bannedMembers[i].avatarUrl,
                      name: _bannedMembers[i].displayName,
                      radius: 21,
                    ),
                    title: Text(
                      _bannedMembers[i].displayName.isNotEmpty
                          ? _bannedMembers[i].displayName
                          : '@${_bannedMembers[i].username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    subtitle: _bannedMembers[i].username.isNotEmpty
                        ? Text(
                            '@${_bannedMembers[i].username}',
                            style: TextStyle(fontSize: 12.5, color: subColor),
                          )
                        : null,
                    trailing: TextButton(
                      onPressed: () => _unbanUser(_bannedMembers[i]),
                      style: TextButton.styleFrom(
                        minimumSize: const Size(44, 44),
                        foregroundColor: accentColor,
                      ),
                      child: const Text(
                        'Разблокировать',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                  if (i < _bannedMembers.length - 1)
                    Divider(height: 1, indent: 70, color: dividerColor),
                ],
              ],
            ),
          ),
      ],
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
      GlassToastService().show(context, 'Не удалось заблокировать пользователя');
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
      GlassToastService().show(context, 'Не удалось снять блокировку');
    }
  }

  Future<ChatParticipant?> _pickMemberSheet({
    required String title,
    required List<ChatParticipant> members,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.65)
        : const Color(0xFF475569);

    return showModalBottomSheet<ChatParticipant>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SettingsAttachedSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: members.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (_, idx) {
                  final m = members[idx];
                  return ListTile(
                    minTileHeight: 54,
                    leading: AvatarWithStatus(
                      userId: m.id,
                      avatarUrl: m.avatarUrl,
                      name: m.displayName,
                      radius: 20,
                    ),
                    title: Text(
                      m.displayName.isNotEmpty
                          ? m.displayName
                          : '@${m.username}',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                    subtitle: m.username.isNotEmpty
                        ? Text(
                            '@${m.username}',
                            style: TextStyle(color: subColor, fontSize: 12.5),
                          )
                        : null,
                    onTap: () => Navigator.pop(ctx, m),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openRestrictionEditorSheet(ChatParticipant member) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeExt = Theme.of(context).extension<TheavThemeExtension>();
    final accentColor = themeExt?.palette.primary ??
        (isDark ? const Color(0xFF64B5F6) : const Color(0xFF0088CC));
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.68)
        : const Color(0xFF475569);

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
    Duration? duration; // null = Навсегда
    var saving = false;

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          final durations = <({String label, Duration? value})>[
            (label: 'Навсегда', value: null),
            (label: '1 час', value: const Duration(hours: 1)),
            (label: '1 день', value: const Duration(days: 1)),
            (label: '1 неделя', value: const Duration(days: 7)),
            (label: '1 месяц', value: const Duration(days: 30)),
          ];

          return SettingsAttachedSheet(
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Ограничения: ${member.displayName}',
                    style: TextStyle(
                      fontSize: 17.5,
                      fontWeight: FontWeight.w700,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _sheetToggle(
                    'Отправка сообщений',
                    current.canSendMessages,
                    accentColor,
                    textColor,
                    (v) => setSheetState(
                      () => current = current.copyWith(canSendMessages: v),
                    ),
                  ),
                  _sheetToggle(
                    'Отправка медиа',
                    current.canSendMedia,
                    accentColor,
                    textColor,
                    (v) => setSheetState(
                      () => current = current.copyWith(canSendMedia: v),
                    ),
                  ),
                  _sheetToggle(
                    'Стикеры и GIF',
                    current.canSendStickersGifs,
                    accentColor,
                    textColor,
                    (v) => setSheetState(
                      () => current = current.copyWith(canSendStickersGifs: v),
                    ),
                  ),
                  _sheetToggle(
                    'Опросы',
                    current.canSendPolls,
                    accentColor,
                    textColor,
                    (v) => setSheetState(
                      () => current = current.copyWith(canSendPolls: v),
                    ),
                  ),
                  _sheetToggle(
                    'Добавление участников',
                    current.canInviteUsers,
                    accentColor,
                    textColor,
                    (v) => setSheetState(
                      () => current = current.copyWith(canInviteUsers: v),
                    ),
                  ),
                  _sheetToggle(
                    'Закрепление сообщений',
                    current.canPinMessages,
                    accentColor,
                    textColor,
                    (v) => setSheetState(
                      () => current = current.copyWith(canPinMessages: v),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'СРОК ОГРАНИЧЕНИЯ',
                    style: TextStyle(
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                      color: subColor,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final opt in durations)
                        ChoiceChip(
                          label: Text(opt.label),
                          selected: duration == opt.value,
                          onSelected: (_) =>
                              setSheetState(() => duration = opt.value),
                          selectedColor: accentColor.withValues(alpha: 0.22),
                          labelStyle: TextStyle(
                            color: duration == opt.value
                                ? accentColor
                                : textColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      if (member.memberRestrictions != null) ...[
                        Expanded(
                          child: OutlinedButton(
                            onPressed: saving
                                ? null
                                : () async {
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
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 46),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text('Сбросить'),
                          ),
                        ),
                        const SizedBox(width: 10),
                      ],
                      Expanded(
                        child: Builder(
                          builder: (_) {
                            final buttonFg =
                                accentColor.computeLuminance() > 0.35
                                    ? const Color(0xFF0F172A)
                                    : Colors.white;
                            return FilledButton(
                              onPressed: saving
                                  ? null
                                  : () async {
                                      setSheetState(() => saving = true);
                                      final until = duration != null
                                          ? DateTime.now().add(duration!)
                                          : null;
                                      final ok = await ChatService
                                          .updateMemberRestrictions(
                                        chatId: widget.chatId,
                                        userId: member.id,
                                        restrictions: current,
                                        restrictedUntil: until,
                                      );
                                      if (ctx.mounted) Navigator.pop(ctx, ok);
                                    },
                              style: FilledButton.styleFrom(
                                backgroundColor: accentColor,
                                foregroundColor: buttonFg,
                                minimumSize: const Size(0, 46),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                              child: const Text('Сохранить'),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
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
    Color accentColor,
    Color textColor,
    ValueChanged<bool> onChanged,
  ) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      minTileHeight: 46,
      title: Text(title, style: TextStyle(color: textColor, fontSize: 15)),
      trailing: Switch.adaptive(
        value: value,
        activeThumbColor: accentColor,
        onChanged: onChanged,
      ),
      onTap: () => onChanged(!value),
    );
  }

  Widget _buildSwitchRow({
    required LiquidGlassProvider? glassProvider,
    required Widget icon,
    required String title,
    required bool value,
    required Color accentColor,
    required Color textColor,
    required ValueChanged<bool> onChanged,
  }) {
    final trailing = glassProvider != null
        ? AdaptiveSwitch(
            value: value,
            onChanged: onChanged,
            activeColor: accentColor,
          )
        : Switch.adaptive(
            value: value,
            activeThumbColor: accentColor,
            onChanged: onChanged,
          );

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 52),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        leading: SizedBox(width: 28, child: Center(child: icon)),
        title: Text(
          title,
          style: TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w500,
            color: textColor,
          ),
        ),
        trailing: trailing,
        onTap: () => onChanged(!value),
      ),
    );
  }

  Widget _buildEmptyStateCard(
    BuildContext context, {
    required LiquidGlassProvider? glassProvider,
    required bool isDark,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
    required Widget icon,
    required String title,
    required String subtitle,
  }) {
    return _buildSurfaceCard(
      context,
      glassProvider: glassProvider,
      isDark: isDark,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
        child: Column(
          children: [
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.14),
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: icon,
            ),
            const SizedBox(height: 12),
            Text(
              title,
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, color: subColor, height: 1.35),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSurfaceCard(
    BuildContext context, {
    required LiquidGlassProvider? glassProvider,
    required bool isDark,
    double radius = 20,
    required Widget child,
  }) {
    if ((glassProvider?.enabled ?? false) && glassProvider != null) {
      final style = glassProvider.createStyle(
        context: context,
        shape: LiquidGlassShape.continuousRoundedRectangle(
          cornerRadius: radius,
        ),
      );
      return LiquidGlassLens(
        style: style,
        child: Container(
          decoration: isDark
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                ),
          child: Material(type: MaterialType.transparency, child: child),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.08),
          width: 0.5,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(type: MaterialType.transparency, child: child),
    );
  }
}
