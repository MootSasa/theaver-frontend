import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../models/theav_theme.dart';
import '../../services/chat_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../utils/haptic_utils.dart';
import '../common/adaptive_switch.dart';
import '../settings/settings_floating_header.dart';

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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themeExt = theme.extension<TheavThemeExtension>();
    final glassProvider = maybeLiquidGlassProvider(context);
    final accentColor = themeExt?.palette.primary ??
        (isDark ? const Color(0xFF64B5F6) : const Color(0xFF0088CC));
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.68)
        : const Color(0xFF475569);
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);
    final items = _buildRightItems();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.only(left: 14, bottom: 8),
          child: Text(
            'ЧТО МОЖЕТ ДЕЛАТЬ АДМИНИСТРАТОР',
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
            mainAxisSize: MainAxisSize.min,
            children: [
              for (int i = 0; i < items.length; i++) ...[
                _buildToggleRow(
                  context,
                  item: items[i],
                  hasGlass: glassProvider != null,
                  accentColor: accentColor,
                  textColor: textColor,
                  subColor: subColor,
                ),
                if (i < items.length - 1)
                  Divider(height: 1, indent: 54, color: dividerColor),
              ],
            ],
          ),
        ),
        if (!_isChannel && widget.showAnonymousToggle) ...[
          const SizedBox(height: 16),
          _buildSurfaceCard(
            context,
            glassProvider: glassProvider,
            isDark: isDark,
            child: _buildSwitchTile(
              context,
              hasGlass: glassProvider != null,
              icon: iconoir.EyeClosed(
                width: 20,
                height: 20,
                color: accentColor,
              ),
              title: 'Анонимность',
              subtitle: 'Сообщения будут отправляться от имени группы',
              value: _isAnonymous,
              accentColor: accentColor,
              textColor: textColor,
              subColor: subColor,
              onChanged: (v) {
                HapticUtils.selection();
                setState(() => _isAnonymous = v);
                widget.onIsAnonymousChanged?.call(v);
              },
            ),
          ),
        ],
        if (widget.showCustomTitle) ...[
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.only(left: 14, bottom: 8),
            child: Text(
              'ДОЛЖНОСТЬ',
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
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: TextField(
                controller: _titleController,
                maxLength: 16,
                inputFormatters: [LengthLimitingTextInputFormatter(16)],
                style: TextStyle(fontSize: 15.5, color: textColor),
                onChanged: (value) {
                  widget.onAdminTitleChanged?.call(value);
                },
                decoration: InputDecoration(
                  hintText: 'Например: Модератор',
                  hintStyle: TextStyle(color: subColor),
                  border: InputBorder.none,
                  counterStyle: TextStyle(fontSize: 11.5, color: subColor),
                  prefixIconConstraints: const BoxConstraints(
                    minWidth: 34,
                    minHeight: 34,
                  ),
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(right: 10),
                    child: iconoir.ShieldCheck(
                      width: 20,
                      height: 20,
                      color: accentColor,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(left: 14, top: 6),
            child: Text(
              'Должность отображается справа от имени в сообщениях группы (до 16 символов).',
              style: TextStyle(fontSize: 12.5, color: subColor, height: 1.35),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildToggleRow(
    BuildContext context, {
    required _AdminRightItem item,
    required bool hasGlass,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
  }) {
    final iconColor = item.enabled ? accentColor : subColor;
    return _buildSwitchTile(
      context,
      hasGlass: hasGlass,
      icon: item.iconBuilder(iconColor),
      title: item.title,
      subtitle: item.subtitle,
      value: item.value,
      accentColor: accentColor,
      textColor: item.enabled ? textColor : subColor,
      subColor: subColor,
      onChanged: item.enabled
          ? (nextVal) {
              HapticUtils.selection();
              _updateRights(item.updater(_rights, nextVal));
            }
          : null,
    );
  }

  Widget _buildSwitchTile(
    BuildContext context, {
    required bool hasGlass,
    required Widget icon,
    required String title,
    String? subtitle,
    required bool value,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
    required ValueChanged<bool>? onChanged,
  }) {
    final switchWidget = hasGlass
        ? AdaptiveSwitch(
            value: value,
            onChanged: onChanged,
            activeColor: accentColor,
          )
        : Switch.adaptive(
            value: value,
            onChanged: onChanged,
            activeThumbColor: accentColor,
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
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: TextStyle(fontSize: 12.5, color: subColor),
              )
            : null,
        trailing: switchWidget,
        onTap: onChanged != null ? () => onChanged(!value) : null,
      ),
    );
  }

  Widget _buildSurfaceCard(
    BuildContext context, {
    required LiquidGlassProvider? glassProvider,
    required bool isDark,
    required Widget child,
  }) {
    final isGlass = glassProvider?.enabled ?? false;
    if (isGlass && glassProvider != null) {
      final style = glassProvider.createStyle(
        context: context,
        shape: const LiquidGlassShape.continuousRoundedRectangle(
          cornerRadius: 20,
        ),
      );
      return LiquidGlassLens(
        style: style,
        child: Container(
          decoration: isDark
              ? null
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(20),
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
        borderRadius: BorderRadius.circular(20),
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
