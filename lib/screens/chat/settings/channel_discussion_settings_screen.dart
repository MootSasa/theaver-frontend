import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../../models/theav_theme.dart';
import '../../../services/chat_service.dart';
import '../../../services/glass_toast_service.dart';
import '../../../services/liquid_glass_provider.dart';
import '../../../utils/haptic_utils.dart';
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.72)
        : const Color(0xFF475569);

    final extraNote =
        (group.linkedChatId != null &&
                group.linkedChatId!.isNotEmpty &&
                group.linkedChatId != widget.channelId)
            ? '\n\nЭта группа уже привязана к другому каналу — прежняя связь будет заменена.'
            : '';

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        title: Text(
          'Привязать «${group.name}»?',
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        content: Text(
          'Публикации канала «${widget.channelName}» будут автоматически пересылаться в эту группу для комментариев.$extraNote',
          style: TextStyle(color: subColor),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Отмена'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Привязать'),
          ),
        ],
      ),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: isDark ? const Color(0xFF2C2C2E) : Colors.white,
        title: Text(
          'Отвязать группу?',
          style: TextStyle(color: isDark ? Colors.white : Colors.black87),
        ),
        content: Text(
          'Комментарии под новыми публикациями канала перестанут отображаться.',
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
              'Отвязать',
              style: TextStyle(color: Colors.redAccent),
            ),
          ),
        ],
      ),
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
    Navigator.pop(context, {
      'linked_chat_id': _linkedChatId ?? '',
      'linked_chat': _linkedChat,
    });
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
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);

    final availableGroups =
        _adminGroups.where((g) => g.id != _linkedChatId).toList();

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _popWithResult();
      },
      child: SettingsFloatingScaffold(
        title: 'Обсуждение',
        backgroundColor: bgColor,
        onBack: _popWithResult,
        actions: _isSubmitting
            ? const [
                SettingsHeaderAction(
                  child: SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              ]
            : const [],
        body: ListView(
          padding: EdgeInsets.fromLTRB(
            16,
            SettingsFloatingHeader.topClearanceOf(context) + 12,
            16,
            36,
          ),
          children: [
            _buildSurfaceCard(
              context,
              glassProvider: glassProvider,
              isDark: isDark,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.14),
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: iconoir.ChatLines(
                        width: 22,
                        height: 22,
                        color: accentColor,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        'Привяжите группу, чтобы подписчики могли оставлять комментарии под публикациями канала «${widget.channelName}».',
                        style: TextStyle(
                          fontSize: 13.5,
                          height: 1.38,
                          color: subColor,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            if (_hasLinkedGroup) ...[
              Padding(
                padding: const EdgeInsets.only(left: 14, bottom: 8),
                child: Text(
                  'ПРИВЯЗАННАЯ ГРУППА',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: subColor,
                  ),
                ),
              ),
              _buildLinkedGroupCard(
                context,
                glassProvider: glassProvider,
                isDark: isDark,
                accentColor: accentColor,
                textColor: textColor,
                subColor: subColor,
              ),
              const SizedBox(height: 18),
            ],
            _buildSurfaceCard(
              context,
              glassProvider: glassProvider,
              isDark: isDark,
              child: ListTile(
                minTileHeight: 56,
                leading: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.14),
                    shape: BoxShape.circle,
                  ),
                  alignment: Alignment.center,
                  child: iconoir.Plus(
                    width: 20,
                    height: 20,
                    color: accentColor,
                  ),
                ),
                title: Text(
                  'Создать группу для обсуждения',
                  style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: accentColor,
                  ),
                ),
                subtitle: Text(
                  'Будет создана группа «${widget.channelName.trim()} Chat»',
                  style: TextStyle(fontSize: 12.5, color: subColor),
                ),
                onTap: _isSubmitting ? null : _createDiscussionGroup,
              ),
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.only(left: 14, bottom: 8),
              child: Text(
                'ВАШИ ГРУППЫ (ВЛАДЕЛЕЦ ИЛИ АДМИН)',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: subColor,
                ),
              ),
            ),
            if (_isLoading)
              const Padding(
                padding: EdgeInsets.all(28),
                child: Center(child: CircularProgressIndicator()),
              )
            else if (availableGroups.isEmpty)
              _buildSurfaceCard(
                context,
                glassProvider: glassProvider,
                isDark: isDark,
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 22,
                  ),
                  child: Text(
                    'Нет других групп, в которых вы являетесь владельцем или администратором.',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 14, color: subColor),
                  ),
                ),
              )
            else
              _buildSurfaceCard(
                context,
                glassProvider: glassProvider,
                isDark: isDark,
                child: Column(
                  children: [
                    for (int i = 0; i < availableGroups.length; i++) ...[
                      ListTile(
                        minTileHeight: 58,
                        leading: AvatarWithStatus(
                          avatarUrl: availableGroups[i].avatarUrl,
                          name: availableGroups[i].name,
                          radius: 21,
                        ),
                        title: Text(
                          availableGroups[i].name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: textColor,
                          ),
                        ),
                        subtitle: Text(
                          availableGroups[i].username != null &&
                                  availableGroups[i].username!.isNotEmpty
                              ? '@${availableGroups[i].username}'
                              : (availableGroups[i].myRole == 'owner'
                                  ? 'Владелец'
                                  : 'Администратор'),
                          style: TextStyle(fontSize: 12.5, color: subColor),
                        ),
                        trailing: iconoir.Link(
                          width: 18,
                          height: 18,
                          color: accentColor,
                        ),
                        onTap: _isSubmitting
                            ? null
                            : () => _linkGroup(availableGroups[i]),
                      ),
                      if (i < availableGroups.length - 1)
                        Divider(height: 1, indent: 70, color: dividerColor),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildLinkedGroupCard(
    BuildContext context, {
    required LiquidGlassProvider? glassProvider,
    required bool isDark,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
  }) {
    final groupName = _linkedChat?.name.isNotEmpty == true
        ? _linkedChat!.name
        : 'Группа #${_linkedChatId ?? ''}';
    final subText = (_linkedChat?.username?.isNotEmpty == true)
        ? '@${_linkedChat!.username}'
        : (_linkedChat != null && _linkedChat!.memberCount > 0
            ? '${_linkedChat!.memberCount} участников'
            : 'Привязанная группа обсуждения');

    return _buildSurfaceCard(
      context,
      glassProvider: glassProvider,
      isDark: isDark,
      child: Column(
        children: [
          ListTile(
            minTileHeight: 62,
            leading: AvatarWithStatus(
              avatarUrl: _linkedChat?.avatarUrl,
              name: groupName,
              radius: 22,
            ),
            title: Text(
              groupName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 15.5,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            subtitle: Text(
              subText,
              style: TextStyle(fontSize: 12.5, color: subColor),
            ),
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
          Divider(
            height: 1,
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.black.withValues(alpha: 0.08),
          ),
          ListTile(
            minTileHeight: 50,
            leading: const iconoir.LinkSlash(
              width: 20,
              height: 20,
              color: Colors.redAccent,
            ),
            title: const Text(
              'Отвязать группу',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w600,
                color: Colors.redAccent,
              ),
            ),
            onTap: _isSubmitting ? null : _unlinkGroup,
          ),
        ],
      ),
    );
  }

  Widget _buildSurfaceCard(
    BuildContext context, {
    required LiquidGlassProvider? glassProvider,
    required bool isDark,
    required Widget child,
  }) {
    if ((glassProvider?.enabled ?? false) && glassProvider != null) {
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
