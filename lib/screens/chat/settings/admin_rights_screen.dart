import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../../services/chat_service.dart';
import '../../../services/glass_toast_service.dart';
import '../../../utils/haptic_utils.dart';
import '../../../widgets/chat/admin_permissions_widget.dart';
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

  const AdminRightsScreen({
    super.key,
    required this.chatId,
    required this.chatType,
    required this.participant,
    required this.isOwnerCaller,
  });

  @override
  State<AdminRightsScreen> createState() => _AdminRightsScreenState();
}

class _AdminRightsScreenState extends State<AdminRightsScreen> {
  late AdminRights _rights;
  late String _adminTitle;
  late bool _isAnonymous;
  bool _isSaving = false;

  bool get _isChannel => widget.chatType == 'channel';
  bool get _isOwnerTarget => widget.participant.role == 'owner';
  bool get _isAdminTarget => widget.participant.role == 'admin';

  @override
  void initState() {
    super.initState();
    _rights = _isOwnerTarget
        ? const AdminRights.all()
        : (widget.participant.adminPermissions ?? const AdminRights());
    _adminTitle = widget.participant.adminTitle;
    _isAnonymous = !_isChannel && widget.participant.isAnonymous;
  }

  String get _displayName {
    final name = widget.participant.displayName.trim();
    if (name.isNotEmpty) return name;
    if (widget.participant.username.trim().isNotEmpty) {
      return '@${widget.participant.username.trim()}';
    }
    return 'Пользователь';
  }

  Future<void> _saveRights() async {
    if (_isSaving) return;
    HapticUtils.tap();
    setState(() => _isSaving = true);

    final ok = await ChatService.updateMemberAdminRights(
      chatId: widget.chatId,
      userId: widget.participant.id,
      role: _isOwnerTarget ? 'owner' : 'admin',
      permissions: _isOwnerTarget ? null : _rights,
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
    if (_isSaving || _isOwnerTarget) return;
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final palette = context.theav;

    return SettingsFloatingScaffold(
      title: _isAdminTarget || _isOwnerTarget
          ? 'Права администратора'
          : 'Назначить админом',
      backgroundColor: palette.background,
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
            onTap: _saveRights,
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
          AdminPermissionsWidget(
            chatType: widget.chatType,
            initialRights: _rights,
            initialAdminTitle: _adminTitle,
            initialIsAnonymous: _isAnonymous,
            rightsEditable: !_isOwnerTarget,
            canEditAddAdmins: widget.isOwnerCaller,
            showCustomTitle: true,
            showAnonymousToggle: !_isChannel,
            onRightsChanged: (next) => setState(() => _rights = next),
            onAdminTitleChanged: (next) => setState(() => _adminTitle = next),
            onIsAnonymousChanged: (next) => setState(() => _isAnonymous = next),
          ),
          if (_isAdminTarget) ...[
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
    final subtitle = username.isNotEmpty
        ? '@$username'
        : (widget.participant.isOnline ? 'в сети' : 'участник');

    return TheavInsetGroup(
      children: [
        TheavListRow(
          leading: AvatarWithStatus(
            userId: widget.participant.id,
            avatarUrl: widget.participant.avatarUrl,
            name: _displayName,
            radius: 24,
            isOnline: widget.participant.isOnline,
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
    final effectiveSenderName =
        (_isAnonymous && !_isChannel) ? 'Группа (анонимно)' : _displayName;
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
            child: _isAnonymous && !_isChannel
                ? iconoir.Group(width: 17, height: 17, color: accentColor)
                : Text(
                    effectiveSenderName.isNotEmpty
                        ? effectiveSenderName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      fontSize: 13.5,
                      fontWeight: FontWeight.w700,
                      color: accentColor,
                    ),
                  ),
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
                    nameColor: accentColor,
                    customization: _isAnonymous
                        ? null
                        : widget.participant.peerCustomization,
                    isBot: widget.participant.isBot,
                    isVerified: widget.participant.isVerified,
                    adminTitle: trimmedTitle.isNotEmpty ? trimmedTitle : null,
                    role: _isOwnerTarget ? 'owner' : 'admin',
                    rankColor: subColor,
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
