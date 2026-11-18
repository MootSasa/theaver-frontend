import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../services/chat_service.dart';
import '../../utils/haptic_utils.dart';
import '../design_system/theav_design_system.dart';

/// Granular Telegram-style administrator permissions editor, supporting custom
/// rank title (`adminTitle`, up to 16 chars) and anonymous group admin mode.
class AdminPermissionsWidget extends StatefulWidget {
  /// Backwards-compatible map input (`can_change_info`, `can_delete_messages`, ...).
  final Map<String, bool>? initialPermissions;
  final ValueChanged<Map<String, bool>>? onPermissionsChanged;

  /// Strongly-typed [AdminRights] input and callback.
  final AdminRights? initialRights;
  final ValueChanged<AdminRights>? onRightsChanged;

  /// Chat type: `'group'` or `'channel'`.
  final String chatType;

  /// Whether the caller is allowed to modify `can_add_admins`.
  final bool canEditAddAdmins;

  /// Whether the granular right switches are interactive (false for owner preview).
  final bool rightsEditable;

  /// Custom rank title (`Должность`, max 16 chars).
  final bool showCustomTitle;
  final String initialAdminTitle;
  final ValueChanged<String>? onAdminTitleChanged;

  /// Anonymous mode toggle (groups only).
  final bool showAnonymousToggle;
  final bool initialIsAnonymous;
  final ValueChanged<bool>? onIsAnonymousChanged;

  const AdminPermissionsWidget({
    super.key,
    this.initialPermissions,
    this.onPermissionsChanged,
    this.initialRights,
    this.onRightsChanged,
    this.chatType = 'group',
    this.canEditAddAdmins = true,
    this.rightsEditable = true,
    this.showCustomTitle = true,
    this.initialAdminTitle = '',
    this.onAdminTitleChanged,
    this.showAnonymousToggle = true,
    this.initialIsAnonymous = false,
    this.onIsAnonymousChanged,
  });

  @override
  AdminPermissionsWidgetState createState() => AdminPermissionsWidgetState();
}

class _AdminRightItem {
  final String keyName;
  final String title;
  final String? subtitle;
  final bool value;
  final bool enabled;
  final Widget Function(Color color) iconBuilder;
  final AdminRights Function(AdminRights current, bool nextValue) updater;

  const _AdminRightItem({
    required this.keyName,
    required this.title,
    this.subtitle,
    required this.value,
    this.enabled = true,
    required this.iconBuilder,
    required this.updater,
  });
}

class AdminPermissionsWidgetState extends State<AdminPermissionsWidget> {
  late AdminRights _rights;
  late bool _isAnonymous;
  late final TextEditingController _titleController;

  bool get _isChannel => widget.chatType == 'channel';

  @override
  void initState() {
    super.initState();
    _rights = _resolveInitialRights();
    _isAnonymous = !_isChannel && widget.initialIsAnonymous;
    _titleController = TextEditingController(
      text: widget.initialAdminTitle.length > 16
          ? widget.initialAdminTitle.substring(0, 16)
          : widget.initialAdminTitle,
    );
  }

  @override
  void didUpdateWidget(covariant AdminPermissionsWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.initialRights != widget.initialRights &&
        widget.initialRights != null) {
      _rights = widget.initialRights!;
    }
    if (oldWidget.initialIsAnonymous != widget.initialIsAnonymous) {
      _isAnonymous = !_isChannel && widget.initialIsAnonymous;
    }
    if (oldWidget.initialAdminTitle != widget.initialAdminTitle &&
        _titleController.text != widget.initialAdminTitle) {
      final truncated = widget.initialAdminTitle.length > 16
          ? widget.initialAdminTitle.substring(0, 16)
          : widget.initialAdminTitle;
      _titleController.value = TextEditingValue(
        text: truncated,
        selection: TextSelection.collapsed(offset: truncated.length),
      );
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    super.dispose();
  }

  AdminRights _resolveInitialRights() {
    if (widget.initialRights != null) return widget.initialRights!;
    final raw = widget.initialPermissions;
    if (raw != null) {
      return AdminRights(
        canChangeInfo: raw['can_change_info'] ?? false,
        canPostMessages: raw['can_post_messages'] ?? _isChannel,
        canEditMessages: raw['can_edit_messages'] ?? false,
        canDeleteMessages: raw['can_delete_messages'] ?? false,
        canBanUsers: raw['can_ban_users'] ?? false,
        canInviteUsers: raw['can_invite_users'] ?? false,
        canPinMessages: raw['can_pin_messages'] ?? false,
        canManageCalls: raw['can_manage_calls'] ?? false,
        canAddAdmins: raw['can_add_admins'] ?? false,
      );
    }
    return const AdminRights();
  }

  void _updateRights(AdminRights next) {
    setState(() => _rights = next);
    widget.onRightsChanged?.call(next);
    widget.onPermissionsChanged?.call(
      next.toJson().map((k, v) => MapEntry(k, v == true)),
    );
  }

  List<_AdminRightItem> _buildRightItems() {
    return <_AdminRightItem>[
      _AdminRightItem(
        keyName: 'can_change_info',
        title: _isChannel
            ? 'Изменение профиля канала'
            : 'Изменение профиля группы',
        value: _rights.canChangeInfo,
        enabled: widget.rightsEditable,
        iconBuilder: (c) => iconoir.EditPencil(width: 20, height: 20, color: c),
        updater: (r, v) => r.copyWith(canChangeInfo: v),
      ),
      if (_isChannel)
        _AdminRightItem(
          keyName: 'can_post_messages',
          title: 'Публикация сообщений',
          value: _rights.canPostMessages,
          enabled: widget.rightsEditable,
          iconBuilder: (c) =>
              iconoir.SendDiagonal(width: 20, height: 20, color: c),
          updater: (r, v) => r.copyWith(canPostMessages: v),
        ),
      _AdminRightItem(
        keyName: 'can_edit_messages',
        title: 'Изменение сообщений',
        value: _rights.canEditMessages,
        enabled: widget.rightsEditable,
        iconBuilder: (c) => iconoir.Edit(width: 20, height: 20, color: c),
        updater: (r, v) => r.copyWith(canEditMessages: v),
      ),
      _AdminRightItem(
        keyName: 'can_delete_messages',
        title: 'Удаление сообщений',
        value: _rights.canDeleteMessages,
        enabled: widget.rightsEditable,
        iconBuilder: (c) => iconoir.Trash(width: 20, height: 20, color: c),
        updater: (r, v) => r.copyWith(canDeleteMessages: v),
      ),
      _AdminRightItem(
        keyName: 'can_ban_users',
        title: _isChannel
            ? 'Блокировка подписчиков'
            : 'Блокировка пользователей',
        value: _rights.canBanUsers,
        enabled: widget.rightsEditable,
        iconBuilder: (c) =>
            iconoir.Prohibition(width: 20, height: 20, color: c),
        updater: (r, v) => r.copyWith(canBanUsers: v),
      ),
      _AdminRightItem(
        keyName: 'can_invite_users',
        title: _isChannel
            ? 'Добавление подписчиков'
            : 'Добавление участников',
        value: _rights.canInviteUsers,
        enabled: widget.rightsEditable,
        iconBuilder: (c) => iconoir.UserPlus(width: 20, height: 20, color: c),
        updater: (r, v) => r.copyWith(canInviteUsers: v),
      ),
      _AdminRightItem(
        keyName: 'can_pin_messages',
        title: 'Закрепление сообщений',
        value: _rights.canPinMessages,
        enabled: widget.rightsEditable,
        iconBuilder: (c) => iconoir.Pin(width: 20, height: 20, color: c),
        updater: (r, v) => r.copyWith(canPinMessages: v),
      ),
      _AdminRightItem(
        keyName: 'can_manage_calls',
        title: _isChannel
            ? 'Управление трансляциями'
            : 'Управление видеочатами',
        value: _rights.canManageCalls,
        enabled: widget.rightsEditable,
        iconBuilder: (c) => iconoir.Phone(width: 20, height: 20, color: c),
        updater: (r, v) => r.copyWith(canManageCalls: v),
      ),
      _AdminRightItem(
        keyName: 'can_add_admins',
        title: 'Назначение администраторов',
        subtitle: widget.canEditAddAdmins
            ? null
            : 'Доступно только владельцу',
        value: _rights.canAddAdmins,
        enabled: widget.rightsEditable && widget.canEditAddAdmins,
        iconBuilder: (c) => iconoir.Crown(width: 20, height: 20, color: c),
        updater: (r, v) => r.copyWith(canAddAdmins: v),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final items = _buildRightItems();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TheavInsetGroup(
          header: 'ЧТО МОЖЕТ ДЕЛАТЬ АДМИНИСТРАТОР',
          children: [
            for (final item in items)
              TheavListRow(
                leading: item.iconBuilder(
                  item.enabled ? palette.primary : palette.subtext,
                ),
                title: item.title,
                subtitle: item.subtitle,
                enabled: item.enabled,
                trailing: TheavSwitch(
                  value: item.value,
                  onChanged: item.enabled
                      ? (nextVal) {
                          HapticUtils.selection();
                          _updateRights(item.updater(_rights, nextVal));
                        }
                      : null,
                ),
                onTap: item.enabled
                    ? () {
                        HapticUtils.selection();
                        _updateRights(item.updater(_rights, !item.value));
                      }
                    : null,
              ),
          ],
        ),
        if (!_isChannel && widget.showAnonymousToggle) ...[
          const SizedBox(height: 8),
          TheavInsetGroup(
            children: [
              TheavListRow(
                leading: iconoir.EyeClosed(
                  width: 20,
                  height: 20,
                  color: palette.primary,
                ),
                title: 'Анонимность',
                subtitle: 'Сообщения будут отправляться от имени группы',
                trailing: TheavSwitch(
                  value: _isAnonymous,
                  onChanged: (v) {
                    HapticUtils.selection();
                    setState(() => _isAnonymous = v);
                    widget.onIsAnonymousChanged?.call(v);
                  },
                ),
                onTap: () {
                  HapticUtils.selection();
                  final next = !_isAnonymous;
                  setState(() => _isAnonymous = next);
                  widget.onIsAnonymousChanged?.call(next);
                },
              ),
            ],
          ),
        ],
        if (widget.showCustomTitle) ...[
          const SizedBox(height: 8),
          TheavInsetGroup(
            header: 'ДОЛЖНОСТЬ',
            footer:
                'Должность отображается справа от имени в сообщениях группы (до 16 символов).',
            children: [
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
                  widget.onAdminTitleChanged?.call(value);
                },
              ),
            ],
          ),
        ],
      ],
    );
  }
}
