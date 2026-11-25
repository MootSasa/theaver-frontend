import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../../services/chat_service.dart';
import '../../../services/contacts_service.dart';
import '../../../services/glass_toast_service.dart';
import '../../../services/groups_channels_parity_service.dart';
import '../../../utils/haptic_utils.dart';
import '../../../utils/swipe_back_route.dart';
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
  final bool isForum;
  final bool initialParticipantsHidden;
  final bool initialAggressiveAntiSpam;

  const GroupPermissionsScreen({
    super.key,
    required this.chatId,
    required this.initialPermissions,
    required this.initialSlowMode,
    this.isForum = false,
    this.initialParticipantsHidden = false,
    this.initialAggressiveAntiSpam = false,
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
  late bool _participantsHidden;
  late bool _aggressiveAntiSpam;
  late GroupDefaultPermissions _savedPermissions;
  late int _savedSlowModeInterval;
  late bool _savedParticipantsHidden;
  late bool _savedAggressiveAntiSpam;
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
    _participantsHidden = widget.initialParticipantsHidden;
    _aggressiveAntiSpam = widget.initialAggressiveAntiSpam;
    _savedPermissions = _permissions;
    _savedSlowModeInterval = _slowModeInterval;
    _savedParticipantsHidden = _participantsHidden;
    _savedAggressiveAntiSpam = _aggressiveAntiSpam;
    _mediaExpanded = _permissions.canSendMessages;
    ContactsService.revisionNotifier.addListener(_onContactsRevisionChanged);
    unawaited(_loadLists());
  }

  void _onContactsRevisionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ContactsService.revisionNotifier.removeListener(_onContactsRevisionChanged);
    super.dispose();
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
      'participants_hidden': _participantsHidden,
      'has_aggressive_anti_spam_enabled': _aggressiveAntiSpam,
    });

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (res['success'] == true) {
      _savedAtLeastOnce = true;
      _savedPermissions = _permissions;
      _savedSlowModeInterval = _slowModeInterval;
      _savedParticipantsHidden = _participantsHidden;
      _savedAggressiveAntiSpam = _aggressiveAntiSpam;
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
      if (_savedAtLeastOnce) ...{
        'default_permissions': _savedPermissions,
        'slow_mode_interval': _savedSlowModeInterval,
        'participants_hidden': _savedParticipantsHidden,
        'has_aggressive_anti_spam_enabled': _savedAggressiveAntiSpam,
      },
      'saved': _savedAtLeastOnce,
      'members_changed': _membersChanged,
    };
  }

  void _popWithResult() {
    if (!Navigator.of(context).canPop()) return;
    Navigator.pop(context, _buildResult());
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    final stopIdx = _slowModeStops.indexOf(_slowModeInterval).clamp(0, 6);

    return SwipeBackPopScope(
      onSwipeBackPop: _popWithResult,
      child: PopScope(
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
                    valueText: '${_enabledMediaCount(_permissions)}/9',
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
                      title: 'Фотографии',
                      value: _permissions.canSendPhotos,
                      onChanged: (v) => _setGranularMedia(
                        _permissions.copyWith(canSendPhotos: v),
                      ),
                    ),
                    _nestedSwitchRow(
                      palette: palette,
                      icon: iconoir.VideoCamera(
                        width: 18,
                        height: 18,
                        color: palette.primary,
                      ),
                      title: 'Видеозаписи',
                      value: _permissions.canSendVideos,
                      onChanged: (v) => _setGranularMedia(
                        _permissions.copyWith(canSendVideos: v),
                      ),
                    ),
                    _nestedSwitchRow(
                      palette: palette,
                      icon: iconoir.MusicDoubleNote(
                        width: 18,
                        height: 18,
                        color: palette.primary,
                      ),
                      title: 'Музыка',
                      value: _permissions.canSendMusic,
                      onChanged: (v) => _setGranularMedia(
                        _permissions.copyWith(canSendMusic: v),
                      ),
                    ),
                    _nestedSwitchRow(
                      palette: palette,
                      icon: iconoir.Page(
                        width: 18,
                        height: 18,
                        color: palette.primary,
                      ),
                      title: 'Файлы',
                      value: _permissions.canSendFiles,
                      onChanged: (v) => _setGranularMedia(
                        _permissions.copyWith(canSendFiles: v),
                      ),
                    ),
                    _nestedSwitchRow(
                      palette: palette,
                      icon: iconoir.Microphone(
                        width: 18,
                        height: 18,
                        color: palette.primary,
                      ),
                      title: 'Голосовые сообщения',
                      value: _permissions.canSendVoiceNotes,
                      onChanged: (v) => _setGranularMedia(
                        _permissions.copyWith(canSendVoiceNotes: v),
                      ),
                    ),
                    _nestedSwitchRow(
                      palette: palette,
                      icon: iconoir.Camera(
                        width: 18,
                        height: 18,
                        color: palette.primary,
                      ),
                      title: 'Видеосообщения',
                      value: _permissions.canSendVideoNotes,
                      onChanged: (v) => _setGranularMedia(
                        _permissions.copyWith(canSendVideoNotes: v),
                      ),
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
                    _nestedSwitchRow(
                      palette: palette,
                      icon: iconoir.Link(
                        width: 18,
                        height: 18,
                        color: palette.primary,
                      ),
                      title: 'Предпросмотр ссылок',
                      value: _permissions.canAddWebPagePreviews,
                      onChanged: (v) {
                        HapticUtils.selection();
                        setState(() {
                          _permissions = _permissions.copyWith(
                            canAddWebPagePreviews: v,
                          );
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
                if (widget.isForum)
                  TheavListRow(
                    leading: iconoir.ChatLines(
                      width: 20,
                      height: 20,
                      color: palette.primary,
                    ),
                    title: 'Создание и управление темами',
                    trailing: TheavSwitch(
                      value: _permissions.canManageTopics,
                      onChanged: (v) {
                        HapticUtils.selection();
                        setState(() {
                          _permissions = _permissions.copyWith(
                            canManageTopics: v,
                          );
                        });
                      },
                    ),
                    onTap: () {
                      HapticUtils.selection();
                      setState(() {
                        _permissions = _permissions.copyWith(
                          canManageTopics: !_permissions.canManageTopics,
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
              header: 'МОДЕРАЦИЯ И ПРИВАТНОСТЬ',
              children: [
                TheavListRow(
                  leading: iconoir.EyeClosed(
                    width: 20,
                    height: 20,
                    color: palette.primary,
                  ),
                  title: 'Скрыть список участников',
                  subtitle: 'Участники видят только администраторов группы',
                  trailing: TheavSwitch(
                    value: _participantsHidden,
                    onChanged: (v) {
                      HapticUtils.selection();
                      setState(() => _participantsHidden = v);
                    },
                  ),
                  onTap: () {
                    HapticUtils.selection();
                    setState(
                      () => _participantsHidden = !_participantsHidden,
                    );
                  },
                ),
                TheavListRow(
                  leading: iconoir.ShieldCheck(
                    width: 20,
                    height: 20,
                    color: palette.primary,
                  ),
                  title: 'Агрессивный антиспам',
                  subtitle:
                      'Автоматическое удаление спам-сообщений и подозрительных ссылок',
                  trailing: TheavSwitch(
                    value: _aggressiveAntiSpam,
                    onChanged: (v) {
                      HapticUtils.selection();
                      setState(() => _aggressiveAntiSpam = v);
                    },
                  ),
                  onTap: () {
                    HapticUtils.selection();
                    setState(
                      () => _aggressiveAntiSpam = !_aggressiveAntiSpam,
                    );
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
      ),
    );
  }

  int _enabledMediaCount(GroupDefaultPermissions p) {
    int count = 0;
    if (p.canSendPhotos) count++;
    if (p.canSendVideos) count++;
    if (p.canSendMusic) count++;
    if (p.canSendFiles) count++;
    if (p.canSendVoiceNotes) count++;
    if (p.canSendVideoNotes) count++;
    if (p.canSendStickersGifs) count++;
    if (p.canSendPolls) count++;
    if (p.canAddWebPagePreviews) count++;
    return count;
  }

  void _setGranularMedia(GroupDefaultPermissions next) {
    HapticUtils.selection();
    final anyMedia = next.canSendPhotos ||
        next.canSendVideos ||
        next.canSendMusic ||
        next.canSendFiles ||
        next.canSendVoiceNotes ||
        next.canSendVideoNotes;
    setState(() {
      _permissions = next.copyWith(canSendMedia: anyMedia);
    });
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
                  ValueListenableBuilder<int>(
                    valueListenable: ContactsService.revisionNotifier,
                    builder: (_, __, ___) => TheavInsetGroup(
                      children: [
                        for (final m in restricted)
                          Builder(
                            builder: (_) {
                              final rawName = m.displayName.isNotEmpty
                                  ? m.displayName
                                  : '@${m.username}';
                              final mName = ContactsService.resolvePeerName(
                                m.id,
                                rawName,
                                isBot: m.isBot,
                              );
                              final mAvatar =
                                  ContactsService.resolvePeerAvatarUrl(
                                m.id,
                                m.avatarUrl,
                                isBot: m.isBot,
                              );
                              return TheavListRow(
                                leading: AvatarWithStatus(
                                  userId: m.id,
                                  avatarUrl: mAvatar,
                                  name: mName,
                                  radius: 20,
                                  resolveContactOverride: !m.isBot,
                                  decorationOverride:
                                      m.peerCustomization?.avatarDecoration,
                                ),
                                title: mName,
                                subtitle: _formatRestrictionsSummary(m),
                                showChevron: true,
                                onTap: () async {
                                  await _openRestrictionEditorSheet(m);
                                  if (ctx.mounted) setSheetState(() {});
                                },
                              );
                            },
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
  }

  Future<void> _openBlacklistSheet() async {
    final searchCtrl = TextEditingController();
    var pagedBanned = List<ChatParticipant>.from(_bannedMembers);
    var loading = false;
    var loadingMore = false;
    var hasMore = pagedBanned.length >= 50;
    Timer? debounce;

    Future<void> fetchPage(
      StateSetter setSheetState, {
      required bool reset,
    }) async {
      if (!reset && (loadingMore || !hasMore)) return;
      setSheetState(() {
        if (reset) {
          loading = true;
        } else {
          loadingMore = true;
        }
      });
      final res = await GroupsChannelsParityService.getBannedMembersPaged(
        widget.chatId,
        query: searchCtrl.text,
        limit: 50,
        offset: reset ? 0 : pagedBanned.length,
      );
      if (!mounted) return;
      setSheetState(() {
        if (reset) pagedBanned = [];
        final seen = {for (final b in pagedBanned) b.id};
        for (final b in res.bannedMembers) {
          if (seen.add(b.id)) pagedBanned.add(b);
        }
        final trimmed = searchCtrl.text.trim().toLowerCase();
        if (reset && trimmed.isNotEmpty) {
          for (final b in _bannedMembers) {
            final resolved = ContactsService.resolvePeerName(
              b.id,
              b.displayName,
              isBot: b.isBot,
            ).toLowerCase();
            if ((resolved.contains(trimmed) ||
                    b.displayName.toLowerCase().contains(trimmed) ||
                    b.username.toLowerCase().contains(trimmed)) &&
                seen.add(b.id)) {
              pagedBanned.add(b);
            }
          }
        }
        hasMore = res.hasMore;
        loading = false;
        loadingMore = false;
        if (reset && searchCtrl.text.trim().isEmpty) {
          _bannedMembers = List<ChatParticipant>.from(pagedBanned);
        }
      });
    }

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
                    TheavInlineTextField(
                      controller: searchCtrl,
                      placeholder: 'Поиск в чёрном списке...',
                      prefix: iconoir.Search(
                        width: 18,
                        height: 18,
                        color: palette.subtext,
                      ),
                      onChanged: (_) {
                        debounce?.cancel();
                        debounce = Timer(const Duration(milliseconds: 280), () {
                          unawaited(fetchPage(setSheetState, reset: true));
                        });
                      },
                    ),
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
                        if (ctx.mounted) {
                          await fetchPage(setSheetState, reset: true);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                if (loading)
                  const Padding(
                    padding: EdgeInsets.all(24),
                    child: Center(
                      child: CircularProgressIndicator(strokeWidth: 2.2),
                    ),
                  )
                else if (pagedBanned.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      searchCtrl.text.trim().isNotEmpty
                          ? 'Никого не найдено.'
                          : 'Заблокированные пользователи не смогут вернуться в группу и просматривать её.',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13.5, color: palette.subtext),
                    ),
                  )
                else ...[
                  ValueListenableBuilder<int>(
                    valueListenable: ContactsService.revisionNotifier,
                    builder: (_, __, ___) => TheavInsetGroup(
                      children: [
                        for (final banned in pagedBanned)
                          Builder(
                            builder: (_) {
                              final rawName = banned.displayName.isNotEmpty
                                  ? banned.displayName
                                  : '@${banned.username}';
                              final bannedName = ContactsService.resolvePeerName(
                                banned.id,
                                rawName,
                                isBot: banned.isBot,
                              );
                              final bannedAvatar =
                                  ContactsService.resolvePeerAvatarUrl(
                                banned.id,
                                banned.avatarUrl,
                                isBot: banned.isBot,
                              );
                              return TheavListRow(
                                leading: AvatarWithStatus(
                                  userId: banned.id,
                                  avatarUrl: bannedAvatar,
                                  name: bannedName,
                                  radius: 20,
                                  resolveContactOverride: !banned.isBot,
                                  decorationOverride:
                                      banned.peerCustomization?.avatarDecoration,
                                ),
                                title: bannedName,
                                subtitle: banned.username.isNotEmpty
                                    ? '@${banned.username}'
                                    : null,
                                trailing: TheavFloatingPillButton(
                                  height: 32,
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10),
                                  label: 'Разблокировать',
                                  onTap: () async {
                                    await _unbanUser(banned);
                                    if (ctx.mounted) {
                                      setSheetState(() {
                                        pagedBanned.removeWhere(
                                          (m) => m.id == banned.id,
                                        );
                                      });
                                    }
                                  },
                                ),
                              );
                            },
                          ),
                      ],
                    ),
                  ),
                  if (hasMore)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: TheavFloatingPillButton(
                        label: loadingMore ? 'Загрузка...' : 'Загрузить ещё',
                        enabled: !loadingMore,
                        onTap: () => fetchPage(setSheetState, reset: false),
                      ),
                    ),
                ],
              ],
            ),
          );
        },
      ),
    );
    debounce?.cancel();
    searchCtrl.dispose();
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
      builder: (ctx) => ValueListenableBuilder<int>(
        valueListenable: ContactsService.revisionNotifier,
        builder: (_, __, ___) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
          child: TheavInsetGroup(
            children: [
              for (final m in members)
                Builder(
                  builder: (_) {
                    final rawName = m.displayName.isNotEmpty
                        ? m.displayName
                        : '@${m.username}';
                    final mName = ContactsService.resolvePeerName(
                      m.id,
                      rawName,
                      isBot: m.isBot,
                    );
                    final mAvatar = ContactsService.resolvePeerAvatarUrl(
                      m.id,
                      m.avatarUrl,
                      isBot: m.isBot,
                    );
                    return TheavListRow(
                      leading: AvatarWithStatus(
                        userId: m.id,
                        avatarUrl: mAvatar,
                        name: mName,
                        radius: 20,
                        resolveContactOverride: !m.isBot,
                        decorationOverride:
                            m.peerCustomization?.avatarDecoration,
                      ),
                      title: mName,
                      subtitle: m.username.isNotEmpty ? '@${m.username}' : null,
                      showChevron: true,
                      onTap: () => Navigator.pop(ctx, m),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _openRestrictionEditorSheet(ChatParticipant member) async {
    var current = member.memberRestrictions ??
        MemberRestrictions(
          canSendMessages: _permissions.canSendMessages,
          canSendMedia: _permissions.canSendMedia,
          canSendPhotos: _permissions.canSendPhotos,
          canSendVideos: _permissions.canSendVideos,
          canSendMusic: _permissions.canSendMusic,
          canSendFiles: _permissions.canSendFiles,
          canSendVoiceNotes: _permissions.canSendVoiceNotes,
          canSendVideoNotes: _permissions.canSendVideoNotes,
          canSendStickersGifs: _permissions.canSendStickersGifs,
          canSendPolls: _permissions.canSendPolls,
          canAddWebPagePreviews: _permissions.canAddWebPagePreviews,
          canPinMessages: _permissions.canPinMessages,
          canInviteUsers: _permissions.canInviteUsers,
          canChangeInfo: _permissions.canChangeInfo,
          canManageTopics: _permissions.canManageTopics,
        );
    Duration? duration;
    var saving = false;

    final resolvedMemberName = ContactsService.resolvePeerName(
      member.id,
      member.displayName.isNotEmpty ? member.displayName : '@${member.username}',
      isBot: member.isBot,
    );
    final saved = await showTheavModalSheet<bool>(
      context: context,
      title: 'Ограничения: $resolvedMemberName',
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

          void setMediaSub(MemberRestrictions next) {
            final anyMedia = next.canSendPhotos ||
                next.canSendVideos ||
                next.canSendMusic ||
                next.canSendFiles ||
                next.canSendVoiceNotes ||
                next.canSendVideoNotes;
            setSheetState(() => current = next.copyWith(canSendMedia: anyMedia));
          }

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
                      'Фотографии',
                      current.canSendPhotos,
                      (v) => setMediaSub(current.copyWith(canSendPhotos: v)),
                    ),
                    _sheetToggle(
                      'Видеозаписи',
                      current.canSendVideos,
                      (v) => setMediaSub(current.copyWith(canSendVideos: v)),
                    ),
                    _sheetToggle(
                      'Музыка',
                      current.canSendMusic,
                      (v) => setMediaSub(current.copyWith(canSendMusic: v)),
                    ),
                    _sheetToggle(
                      'Файлы',
                      current.canSendFiles,
                      (v) => setMediaSub(current.copyWith(canSendFiles: v)),
                    ),
                    _sheetToggle(
                      'Голосовые сообщения',
                      current.canSendVoiceNotes,
                      (v) => setMediaSub(
                        current.copyWith(canSendVoiceNotes: v),
                      ),
                    ),
                    _sheetToggle(
                      'Видеосообщения',
                      current.canSendVideoNotes,
                      (v) => setMediaSub(
                        current.copyWith(canSendVideoNotes: v),
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
                      'Предпросмотр ссылок',
                      current.canAddWebPagePreviews,
                      (v) => setSheetState(
                        () => current =
                            current.copyWith(canAddWebPagePreviews: v),
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
                    _sheetToggle(
                      'Изменение профиля',
                      current.canChangeInfo,
                      (v) => setSheetState(
                        () => current = current.copyWith(canChangeInfo: v),
                      ),
                    ),
                    if (widget.isForum)
                      _sheetToggle(
                        'Управление темами',
                        current.canManageTopics,
                        (v) => setSheetState(
                          () => current = current.copyWith(canManageTopics: v),
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
