import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../../services/account_manager.dart';
import '../../../services/chat_service.dart';
import '../../../services/contacts_service.dart';
import '../../../services/glass_toast_service.dart';
import '../../../utils/haptic_utils.dart';
import '../../../utils/image_utils.dart';
import '../../../widgets/design_system/theav_design_system.dart';
import '../../../widgets/message/group_message_avatar_row.dart';
import '../../../widgets/settings/settings_floating_header.dart';
import '../../../widgets/user/avatar_with_status.dart';

/// Screen for promoting a member or editing granular administrator permissions,
/// rank title (`Должность`), and group anonymity, with a live Telegram-style
/// message bubble preview.
class AdminRightsScreen extends StatefulWidget {
  final String chatId;
  final String chatType;
  final ChatParticipant participant;
  final bool isOwnerCaller;
  final bool? callerCanEdit;
  final AdminRights? callerPermissions;

  const AdminRightsScreen({
    super.key,
    required this.chatId,
    required this.chatType,
    required this.participant,
    required this.isOwnerCaller,
    this.callerCanEdit,
    this.callerPermissions,
  });

  /// Determines whether the current caller (`callerUserId`, `callerRole`,
  /// `callerPermissions`) is allowed to promote, edit, or demote [target].
  static bool canCallerEditTarget({
    required ChatParticipant target,
    required String? callerUserId,
    required String callerRole,
    AdminRights? callerPermissions,
  }) {
    if (target.role == 'owner') {
      return false;
    }
    if (callerRole == 'owner') {
      return true;
    }
    if (callerRole == 'admin' && (callerPermissions?.canAddAdmins ?? false)) {
      if (callerUserId != null &&
          callerUserId.isNotEmpty &&
          target.id == callerUserId) {
        return false;
      }
      if (target.role == 'admin') {
        return callerUserId != null &&
            callerUserId.isNotEmpty &&
            target.promotedByUserId != null &&
            target.promotedByUserId.toString() == callerUserId;
      }
      return true;
    }
    return false;
  }

  @override
  State<AdminRightsScreen> createState() => _AdminRightsScreenState();
}

class _AdminRightToggleSpec {
  final String title;
  final String? subtitle;
  final bool value;
  final bool callerPossesses;
  final Widget Function(Color color) iconBuilder;
  final AdminRights Function(AdminRights current, bool nextValue) updater;

  const _AdminRightToggleSpec({
    required this.title,
    this.subtitle,
    required this.value,
    required this.callerPossesses,
    required this.iconBuilder,
    required this.updater,
  });
}

class _AdminRightsScreenState extends State<AdminRightsScreen> {
  late AdminRights _rights;
  late String _adminTitle;
  late bool _isAnonymous;
  late final TextEditingController _titleController;
  bool _isSaving = false;

  bool get _isChannel => widget.chatType == 'channel';
  bool get _isOwnerTarget => widget.participant.role == 'owner';
  bool get _isAdminTarget => widget.participant.role == 'admin';

  bool get _effectiveCanEdit {
    if (_isOwnerTarget) return false;
    if (widget.callerCanEdit != null) return widget.callerCanEdit!;
    if (widget.isOwnerCaller) return true;
    return AdminRightsScreen.canCallerEditTarget(
      target: widget.participant,
      callerUserId: AccountManager().currentAccount?.userId,
      callerRole: 'admin',
      callerPermissions: widget.callerPermissions,
    );
  }

  AdminRights _intersectWithCaller(AdminRights base) {
    if (widget.isOwnerCaller || widget.callerPermissions == null) {
      return base;
    }
    final cp = widget.callerPermissions!;
    return AdminRights(
      canChangeInfo: base.canChangeInfo && cp.canChangeInfo,
      canPostMessages: base.canPostMessages && cp.canPostMessages,
      canEditMessages: base.canEditMessages && cp.canEditMessages,
      canDeleteMessages: base.canDeleteMessages && cp.canDeleteMessages,
      canBanUsers: base.canBanUsers && cp.canBanUsers,
      canInviteUsers: base.canInviteUsers && cp.canInviteUsers,
      canPinMessages: base.canPinMessages && cp.canPinMessages,
      canManageCalls: base.canManageCalls && cp.canManageCalls,
      canAddAdmins: base.canAddAdmins && cp.canAddAdmins,
      canManageTopics: base.canManageTopics && cp.canManageTopics,
    );
  }

  @override
  void initState() {
    super.initState();
    final baseRights = _isOwnerTarget
        ? const AdminRights.all()
        : (widget.participant.adminPermissions ?? const AdminRights());
    _rights = (!_isOwnerTarget && !_isAdminTarget)
        ? _intersectWithCaller(baseRights)
        : baseRights;
    _adminTitle = widget.participant.adminTitle.length > 16
        ? widget.participant.adminTitle.substring(0, 16)
        : widget.participant.adminTitle;
    _isAnonymous = !_isChannel && widget.participant.isAnonymous;
    _titleController = TextEditingController(text: _adminTitle);
    ContactsService.revisionNotifier.addListener(_onContactsRevisionChanged);
  }

  void _onContactsRevisionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ContactsService.revisionNotifier.removeListener(_onContactsRevisionChanged);
    _titleController.dispose();
    super.dispose();
  }

  String get _displayName {
    final name = widget.participant.displayName.trim();
    final fallback = name.isNotEmpty
        ? name
        : (widget.participant.username.trim().isNotEmpty
            ? '@${widget.participant.username.trim()}'
            : 'Пользователь');
    return ContactsService.resolvePeerName(
      widget.participant.id,
      fallback,
      isBot: widget.participant.isBot,
    );
  }

  String? get _avatarUrl => ContactsService.resolvePeerAvatarUrl(
        widget.participant.id,
        widget.participant.avatarUrl,
        isBot: widget.participant.isBot,
      );

  Future<void> _saveRights() async {
    if (!_effectiveCanEdit || _isSaving) return;
    HapticUtils.tap();
    setState(() => _isSaving = true);

    final effectiveRights = _intersectWithCaller(_rights);
    final ok = await ChatService.updateMemberAdminRights(
      chatId: widget.chatId,
      userId: widget.participant.id,
      role: _isOwnerTarget ? 'owner' : 'admin',
      permissions: _isOwnerTarget ? null : effectiveRights,
      adminTitle: _adminTitle.trim(),
      isAnonymous: _isChannel ? null : _isAnonymous,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (ok) {
      GlassToastService().show(
        context,
        'Права администратора сохранены',
        iconWidget: const iconoir.Check(
          width: 18,
          height: 18,
          color: Color(0xFF34C759),
        ),
      );
      Navigator.pop(context, true);
    } else {
      GlassToastService().show(
        context,
        'Не удалось сохранить права администратора',
      );
    }
  }

  Future<void> _demoteAdmin() async {
    if (!_effectiveCanEdit || _isSaving || _isOwnerTarget) return;
    final confirmed = await showTheavDialog<bool>(
      context: context,
      title: 'Разжаловать администратора?',
      message:
          '$_displayName потеряет все права администратора в этом ${_isChannel ? 'канале' : 'чате'}.',
      actions: const [
        TheavDialogAction<bool>(label: 'Отмена', result: false),
        TheavDialogAction<bool>(
          label: 'Разжаловать',
          result: true,
          isDestructive: true,
        ),
      ],
    );
    if (confirmed != true || !mounted) return;

    HapticUtils.tap();
    setState(() => _isSaving = true);

    final ok = await ChatService.updateMemberAdminRights(
      chatId: widget.chatId,
      userId: widget.participant.id,
      role: _isChannel ? 'subscriber' : 'member',
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (ok) {
      GlassToastService().show(
        context,
        'Администратор разжалован',
      );
      Navigator.pop(context, true);
    } else {
      GlassToastService().show(
        context,
        'Не удалось разжаловать администратора',
      );
    }
  }

  List<_AdminRightToggleSpec> _buildPermissionSpecs() {
    final cp = widget.callerPermissions;
    final isOwner = widget.isOwnerCaller;

    bool callerHas(bool Function(AdminRights p) getter, {bool fallback = true}) {
      if (isOwner) return true;
      if (cp == null) return fallback;
      return getter(cp);
    }

    return <_AdminRightToggleSpec>[
      _AdminRightToggleSpec(
        title: _isChannel
            ? 'Изменение профиля канала'
            : 'Изменение профиля группы',
        value: _rights.canChangeInfo,
        callerPossesses: callerHas((p) => p.canChangeInfo),
        iconBuilder: (c) => iconoir.EditPencil(width: 20, height: 20, color: c),
        updater: (r, v) => r.copyWith(canChangeInfo: v),
      ),
      if (_isChannel)
        _AdminRightToggleSpec(
          title: 'Публикация сообщений',
          value: _rights.canPostMessages,
          callerPossesses: callerHas((p) => p.canPostMessages),
          iconBuilder: (c) =>
              iconoir.SendDiagonal(width: 20, height: 20, color: c),
          updater: (r, v) => r.copyWith(canPostMessages: v),
        ),
      _AdminRightToggleSpec(
        title: 'Изменение сообщений',
        value: _rights.canEditMessages,
        callerPossesses: callerHas((p) => p.canEditMessages),
        iconBuilder: (c) => iconoir.Edit(width: 20, height: 20, color: c),
        updater: (r, v) => r.copyWith(canEditMessages: v),
      ),
      _AdminRightToggleSpec(
        title: 'Удаление сообщений',
        value: _rights.canDeleteMessages,
        callerPossesses: callerHas((p) => p.canDeleteMessages),
        iconBuilder: (c) => iconoir.Trash(width: 20, height: 20, color: c),
        updater: (r, v) => r.copyWith(canDeleteMessages: v),
      ),
      _AdminRightToggleSpec(
        title: _isChannel
            ? 'Блокировка подписчиков'
            : 'Блокировка пользователей',
        value: _rights.canBanUsers,
        callerPossesses: callerHas((p) => p.canBanUsers),
        iconBuilder: (c) =>
            iconoir.Prohibition(width: 20, height: 20, color: c),
        updater: (r, v) => r.copyWith(canBanUsers: v),
      ),
      _AdminRightToggleSpec(
        title: _isChannel
            ? 'Добавление подписчиков'
            : 'Добавление участников',
        value: _rights.canInviteUsers,
        callerPossesses: callerHas((p) => p.canInviteUsers),
        iconBuilder: (c) => iconoir.UserPlus(width: 20, height: 20, color: c),
        updater: (r, v) => r.copyWith(canInviteUsers: v),
      ),
      _AdminRightToggleSpec(
        title: 'Закрепление сообщений',
        value: _rights.canPinMessages,
        callerPossesses: callerHas((p) => p.canPinMessages),
        iconBuilder: (c) => iconoir.Pin(width: 20, height: 20, color: c),
        updater: (r, v) => r.copyWith(canPinMessages: v),
      ),
      _AdminRightToggleSpec(
        title: _isChannel
            ? 'Управление трансляциями'
            : 'Управление видеочатами',
        value: _rights.canManageCalls,
        callerPossesses: callerHas((p) => p.canManageCalls),
        iconBuilder: (c) => iconoir.Phone(width: 20, height: 20, color: c),
        updater: (r, v) => r.copyWith(canManageCalls: v),
      ),
      if (!_isChannel)
        _AdminRightToggleSpec(
          title: 'Управление темами',
          value: _rights.canManageTopics,
          callerPossesses: callerHas((p) => p.canManageTopics),
          iconBuilder: (c) =>
              iconoir.ChatLines(width: 20, height: 20, color: c),
          updater: (r, v) => r.copyWith(canManageTopics: v),
        ),
      _AdminRightToggleSpec(
        title: 'Назначение администраторов',
        subtitle: callerHas((p) => p.canAddAdmins, fallback: false)
            ? null
            : 'Недоступно для вашего уровня прав',
        value: _rights.canAddAdmins,
        callerPossesses: callerHas((p) => p.canAddAdmins, fallback: false),
        iconBuilder: (c) => iconoir.Crown(width: 20, height: 20, color: c),
        updater: (r, v) => r.copyWith(canAddAdmins: v),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = context.theav;
    final canEdit = _effectiveCanEdit;
    final specs = _buildPermissionSpecs();

    return SettingsFloatingScaffold(
      title: _isAdminTarget || _isOwnerTarget || !canEdit
          ? 'Права администратора'
          : 'Назначить админом',
      backgroundColor: palette.background,
      actions: canEdit
          ? [
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
                  icon: iconoir.Check(
                    width: 22,
                    height: 22,
                    color: palette.primary,
                  ),
                  onTap: _saveRights,
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
          _buildTargetUserCard(context, palette: palette),
          const SizedBox(height: 10),
          Padding(
            padding: const EdgeInsets.fromLTRB(32, 8, 32, 8),
            child: Text(
              'ПРЕДПРОСМОТР В ЧАТЕ',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: palette.subtext,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: _buildLivePreviewCard(
              context,
              isDark: isDark,
              accentColor: palette.primary,
              textColor: palette.onSurface,
              subColor: palette.subtext,
            ),
          ),
          const SizedBox(height: 12),
          TheavInsetGroup(
            header: 'ЧТО МОЖЕТ ДЕЛАТЬ АДМИНИСТРАТОР',
            footer: !canEdit
                ? (_isOwnerTarget
                    ? 'Владелец чата всегда обладает полными правами.'
                    : 'Вы не можете изменять права этого администратора.')
                : null,
            children: [
              for (final spec in specs)
                Builder(
                  builder: (_) {
                    final rowEnabled = canEdit && spec.callerPossesses;
                    final effectiveSubtitle = spec.subtitle ??
                        (canEdit && !spec.callerPossesses
                            ? 'Недоступно для вашего уровня прав'
                            : null);
                    return TheavListRow(
                      leading: spec.iconBuilder(
                        rowEnabled ? palette.primary : palette.subtext,
                      ),
                      title: spec.title,
                      subtitle: effectiveSubtitle,
                      enabled: rowEnabled,
                      trailing: TheavSwitch(
                        value: spec.value,
                        onChanged: rowEnabled
                            ? (nextVal) {
                                HapticUtils.selection();
                                setState(() {
                                  _rights = spec.updater(_rights, nextVal);
                                });
                              }
                            : null,
                      ),
                      onTap: rowEnabled
                          ? () {
                              HapticUtils.selection();
                              setState(() {
                                _rights = spec.updater(_rights, !spec.value);
                              });
                            }
                          : null,
                    );
                  },
                ),
            ],
          ),
          if (!_isChannel) ...[
            const SizedBox(height: 8),
            TheavInsetGroup(
              children: [
                TheavListRow(
                  leading: iconoir.EyeClosed(
                    width: 20,
                    height: 20,
                    color: canEdit ? palette.primary : palette.subtext,
                  ),
                  title: 'Анонимность',
                  subtitle: 'Сообщения будут отправляться от имени группы',
                  enabled: canEdit,
                  trailing: TheavSwitch(
                    value: _isAnonymous,
                    onChanged: canEdit
                        ? (v) {
                            HapticUtils.selection();
                            setState(() => _isAnonymous = v);
                          }
                        : null,
                  ),
                  onTap: canEdit
                      ? () {
                          HapticUtils.selection();
                          setState(() => _isAnonymous = !_isAnonymous);
                        }
                      : null,
                ),
              ],
            ),
          ],
          const SizedBox(height: 8),
          TheavInsetGroup(
            header: 'ДОЛЖНОСТЬ',
            footer:
                'Должность отображается справа от имени в сообщениях группы (до 16 символов).',
            children: [
              if (canEdit)
                TheavInlineTextField(
                  controller: _titleController,
                  placeholder: 'Например: Модератор',
                  maxLength: 16,
                  showCounter: true,
                  inputFormatters: [LengthLimitingTextInputFormatter(16)],
                  prefix: iconoir.ShieldCheck(
                    width: 20,
                    height: 20,
                    color: palette.primary,
                  ),
                  onChanged: (value) {
                    setState(() => _adminTitle = value);
                  },
                )
              else
                TheavListRow(
                  enabled: false,
                  leading: iconoir.ShieldCheck(
                    width: 20,
                    height: 20,
                    color: palette.subtext,
                  ),
                  title: _adminTitle.trim().isNotEmpty
                      ? _adminTitle.trim()
                      : (_isOwnerTarget ? 'Владелец' : 'Администратор'),
                ),
            ],
          ),
          if (_isAdminTarget && canEdit) ...[
            const SizedBox(height: 8),
            TheavInsetGroup(
              children: [
                TheavListRow(
                  leading: iconoir.UserXmark(
                    width: 20,
                    height: 20,
                    color: palette.error,
                  ),
                  title: 'Разжаловать администратора',
                  isDestructive: true,
                  enabled: !_isSaving,
                  onTap: _demoteAdmin,
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTargetUserCard(
    BuildContext context, {
    required TheavPalette palette,
  }) {
    final username = widget.participant.username.trim();
    final subtitle = username.isNotEmpty ? '@$username' : 'участник';

    return TheavInsetGroup(
      children: [
        TheavListRow(
          leading: AvatarWithStatus(
            userId: widget.participant.id,
            avatarUrl: _avatarUrl,
            name: _displayName,
            radius: 24,
            isOnline: false,
            resolveContactOverride: !widget.participant.isBot,
            decorationOverride:
                widget.participant.peerCustomization?.avatarDecoration,
          ),
          title: _displayName,
          subtitle: subtitle,
          trailing: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: palette.primary.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _isOwnerTarget
                  ? 'владелец'
                  : (_isAdminTarget ? 'админ' : 'новый админ'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: palette.primary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildLivePreviewCard(
    BuildContext context, {
    required bool isDark,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
  }) {
    final trimmedTitle = _adminTitle.trim();
    final isAnonGroup = _isAnonymous && !_isChannel;
    final effectiveSenderName =
        isAnonGroup ? 'Группа (анонимно)' : _displayName;
    final previewAvatarProvider =
        isAnonGroup ? null : avatarImageProvider(_avatarUrl);
    final previewBubbleColor =
        isDark ? const Color(0xFF23252C) : Colors.white;
    final gradientColors = isDark
        ? const [Color(0xFF141821), Color(0xFF1C2331)]
        : const [Color(0xFFDCECF8), Color(0xFFEAF2FA)];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isDark
              ? Colors.white.withValues(alpha: 0.10)
              : Colors.black.withValues(alpha: 0.06),
          width: 0.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          CircleAvatar(
            radius: 17,
            backgroundColor: accentColor.withValues(alpha: 0.22),
            backgroundImage: previewAvatarProvider,
            onBackgroundImageError:
                previewAvatarProvider != null ? (_, __) {} : null,
            child: isAnonGroup
                ? iconoir.Group(width: 17, height: 17, color: accentColor)
                : (previewAvatarProvider == null
                    ? Text(
                        effectiveSenderName.isNotEmpty
                            ? effectiveSenderName[0].toUpperCase()
                            : '?',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          color: accentColor,
                        ),
                      )
                    : null),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              decoration: BoxDecoration(
                color: previewBubbleColor,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                  bottomLeft: Radius.circular(4),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.08),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SenderHeaderRow(
                    senderName: effectiveSenderName,
                    senderId: _isAnonymous ? null : widget.participant.id,
                    nameColor: accentColor,
                    customization: _isAnonymous
                        ? null
                        : widget.participant.peerCustomization,
                    isBot: widget.participant.isBot,
                    isVerified: widget.participant.isVerified,
                    adminTitle: trimmedTitle.isNotEmpty ? trimmedTitle : null,
                    role: _isOwnerTarget ? 'owner' : 'admin',
                    rankColor: subColor,
                    isFromAnonymousAdmin: _isAnonymous,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Обновили правила чата и добавили новые реакции.',
                    style: TextStyle(
                      fontSize: 14.5,
                      height: 1.32,
                      color: textColor,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      '12:45',
                      style: TextStyle(fontSize: 11, color: subColor),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
