import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../../models/theav_theme.dart';
import '../../../services/chat_service.dart';
import '../../../services/glass_toast_service.dart';
import '../../../services/liquid_glass_provider.dart';
import '../../../utils/haptic_utils.dart';
import '../../../widgets/chat/admin_permissions_widget.dart';
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        title: Text(
          'Разжаловать администратора?',
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        content: Text(
          '$_displayName потеряет все права администратора в этом ${_isChannel ? 'канале' : 'чате'}.',
          style: TextStyle(
            color: isDark ? Colors.white70 : const Color(0xFF475569),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Разжаловать',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
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
    final buttonFg = accentColor.computeLuminance() > 0.35
        ? const Color(0xFF0F172A)
        : Colors.white;

    return SettingsFloatingScaffold(
      title: _isAdminTarget || _isOwnerTarget
          ? 'Права администратора'
          : 'Назначить админом',
      backgroundColor: bgColor,
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
            onTap: _saveRights,
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
          _buildTargetUserCard(
            context,
            glassProvider: glassProvider,
            isDark: isDark,
            accentColor: accentColor,
            textColor: textColor,
            subColor: subColor,
          ),
          const SizedBox(height: 18),
          Padding(
            padding: const EdgeInsets.only(left: 14, bottom: 8),
            child: Text(
              'ПРЕДПРОСМОТР В ЧАТЕ',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                letterSpacing: 0.4,
                color: subColor,
              ),
            ),
          ),
          _buildLivePreviewCard(
            context,
            isDark: isDark,
            accentColor: accentColor,
            textColor: textColor,
            subColor: subColor,
          ),
          const SizedBox(height: 20),
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
          const SizedBox(height: 24),
          SizedBox(
            height: 48,
            child: FilledButton.icon(
              onPressed: _isSaving ? null : _saveRights,
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
                'Сохранить',
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (_isAdminTarget) ...[
            const SizedBox(height: 12),
            SizedBox(
              height: 48,
              child: OutlinedButton.icon(
                onPressed: _isSaving ? null : _demoteAdmin,
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: BorderSide(
                    color: Colors.redAccent.withValues(alpha: 0.45),
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
                icon: const iconoir.UserXmark(
                  width: 20,
                  height: 20,
                  color: Colors.redAccent,
                ),
                label: const Text(
                  'Разжаловать администратора',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTargetUserCard(
    BuildContext context, {
    required LiquidGlassProvider? glassProvider,
    required bool isDark,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
  }) {
    final username = widget.participant.username.trim();
    final subtitle = username.isNotEmpty
        ? '@$username'
        : (widget.participant.isOnline ? 'в сети' : 'участник');

    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: [
          AvatarWithStatus(
            userId: widget.participant.id,
            avatarUrl: widget.participant.avatarUrl,
            name: _displayName,
            radius: 26,
            isOnline: widget.participant.isOnline,
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _displayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 16.5,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    color: widget.participant.isOnline
                        ? accentColor
                        : subColor,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              _isOwnerTarget
                  ? 'владелец'
                  : (_isAdminTarget ? 'админ' : 'новый админ'),
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: accentColor,
              ),
            ),
          ),
        ],
      ),
    );

    if ((glassProvider?.enabled ?? false) && glassProvider != null) {
      final style = glassProvider.createStyle(
        context: context,
        shape: const LiquidGlassShape.continuousRoundedRectangle(
          cornerRadius: 20,
        ),
      );
      return LiquidGlassLens(style: style, child: row);
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
      child: row,
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
