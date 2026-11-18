import 'dart:async';
import 'dart:io';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:image_picker/image_picker.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../l10n/app_localizations.dart';
import '../../models/theav_theme.dart';
import '../../services/account_manager.dart';
import '../../services/chat_service.dart';
import '../../services/database/app_database.dart';
import '../../services/file_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/image_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../../widgets/common/adaptive_switch.dart';
import '../../widgets/settings/settings_floating_header.dart';
import '../../widgets/user/avatar_with_status.dart';
import 'settings/admin_rights_screen.dart';
import 'settings/channel_discussion_settings_screen.dart';
import 'settings/chat_reactions_settings_screen.dart';
import 'settings/group_permissions_screen.dart';
import 'settings/invite_links_screen.dart';

/// Telegram-style management and edit hub for groups and channels.
class EditGroupChannelScreen extends StatefulWidget {
  final String chatId;
  final bool isChannel;
  final String initialName;
  final String initialDescription;
  final String? initialAvatarUrl;
  final bool initialIsPublic;
  final String? initialUsername;
  final bool initialHistoryForNew;
  final int initialSlowModeInterval;
  final bool? initialShowAuthorProfiles;
  final bool? initialSignMessages;
  final String? initialLinkedChatId;
  final LinkedChatSummary? initialLinkedChat;
  final GroupDefaultPermissions? initialDefaultPermissions;
  final ReactionSettings? initialReactionSettings;
  final String? inviteLink;

  const EditGroupChannelScreen({
    super.key,
    required this.chatId,
    this.isChannel = false,
    required this.initialName,
    this.initialDescription = '',
    this.initialAvatarUrl,
    this.initialIsPublic = false,
    this.initialUsername,
    this.initialHistoryForNew = true,
    this.initialSlowModeInterval = 0,
    this.initialShowAuthorProfiles,
    this.initialSignMessages,
    this.initialLinkedChatId,
    this.initialLinkedChat,
    this.initialDefaultPermissions,
    this.initialReactionSettings,
    this.inviteLink,
  });

  @override
  State<EditGroupChannelScreen> createState() => _EditGroupChannelScreenState();
}

class _EditGroupChannelScreenState extends State<EditGroupChannelScreen> {
  static final RegExp _usernameRegex = RegExp(r'^[a-zA-Z][a-zA-Z0-9_]{2,63}$');

  late final TextEditingController _nameController;
  late final TextEditingController _descriptionController;
  late final TextEditingController _usernameController;

  String? _avatarUrl;
  File? _pickedAvatarFile;
  late bool _isPublic;
  late bool _historyForNew;
  late int _slowModeInterval;
  late bool _signMessages;
  late bool _showAuthorProfiles;
  String? _linkedChatId;
  LinkedChatSummary? _linkedChat;
  late GroupDefaultPermissions _defaultPermissions;
  late ReactionSettings _reactionSettings;
  String? _inviteLink;
  String _myRole = 'admin';
  AdminRights? _myAdminPermissions;
  List<ChatParticipant> _members = [];

  String? _usernameServerError;
  bool _isSaving = false;
  bool _subSettingsChanged = false;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.initialName);
    _descriptionController =
        TextEditingController(text: widget.initialDescription);
    _usernameController =
        TextEditingController(text: widget.initialUsername ?? '');
    _avatarUrl = widget.initialAvatarUrl;
    _isPublic = widget.initialIsPublic;
    _historyForNew = widget.initialHistoryForNew;
    _slowModeInterval = widget.initialSlowModeInterval;
    _signMessages = widget.initialSignMessages ?? false;
    _showAuthorProfiles = widget.isChannel
        ? (_signMessages && (widget.initialShowAuthorProfiles ?? false))
        : (widget.initialShowAuthorProfiles ?? true);
    _linkedChatId = widget.initialLinkedChatId;
    _linkedChat = widget.initialLinkedChat;
    _defaultPermissions =
        widget.initialDefaultPermissions ?? const GroupDefaultPermissions();
    _reactionSettings = widget.initialReactionSettings ?? const ReactionSettings();
    _inviteLink = widget.inviteLink;

    _usernameController.addListener(() {
      if (_usernameServerError != null) {
        setState(() => _usernameServerError = null);
      } else {
        setState(() {});
      }
    });
    _nameController.addListener(() {
      if (mounted) setState(() {});
    });

    unawaited(_loadChatSettings());
  }

  Future<void> _loadChatSettings() async {
    try {
      final results = await Future.wait([
        ChatService.getGroupSettings(widget.chatId),
        ChatService.getGroupMembers(widget.chatId),
      ]);
      if (!mounted) return;

      final res = results[0] as Map<String, dynamic>;
      final members = results[1] as List<ChatParticipant>;

      setState(() {
        if (members.isNotEmpty) {
          _members = members;
        }
        if (res['success'] == true) {
          if (res['name'] != null && res['name'].toString().isNotEmpty) {
            _nameController.text = res['name'].toString();
          }
          if (res['description'] != null) {
            _descriptionController.text = res['description'].toString();
          }
          if (res['username'] != null) {
            _usernameController.text = res['username'].toString();
          }
          final srvAvatar = res['avatar_url']?.toString();
          if (srvAvatar != null && srvAvatar.isNotEmpty) {
            _avatarUrl = srvAvatar;
          }
          if (res['is_public'] is bool) {
            _isPublic = res['is_public'] as bool;
          }
          final histRaw = res['history_for_new_members'] ?? res['history_for_new'];
          if (histRaw is bool) {
            _historyForNew = histRaw;
          }
          if (res['slow_mode_interval'] is num) {
            _slowModeInterval = (res['slow_mode_interval'] as num).toInt();
          }
          if (widget.isChannel) {
            if (res['sign_messages'] is bool) {
              _signMessages = res['sign_messages'] as bool;
            }
            if (res['show_author_profiles'] is bool) {
              _showAuthorProfiles =
                  _signMessages && (res['show_author_profiles'] as bool);
            }
            final rawLinkedId = res['linked_chat_id']?.toString().trim();
            _linkedChatId =
                (rawLinkedId != null && rawLinkedId.isNotEmpty) ? rawLinkedId : null;
            _linkedChat = LinkedChatSummary.tryParse(res['linked_chat']);
          }
          final parsedPerms = GroupDefaultPermissions.tryParse(
            res['default_permissions'],
          );
          if (parsedPerms != null) {
            _defaultPermissions = parsedPerms;
          }
          final parsedReactions = ReactionSettings.fromChatJson(res);
          if (parsedReactions != null) {
            _reactionSettings = parsedReactions;
          }
          final rawInvite = res['invite_link']?.toString().trim();
          if (rawInvite != null && rawInvite.isNotEmpty) {
            _inviteLink = rawInvite;
          }
          if (res['my_role'] != null) {
            _myRole = res['my_role'].toString();
          }
          final adminPerms = AdminRights.tryParse(res['my_admin_permissions']);
          if (adminPerms != null) {
            _myAdminPermissions = adminPerms;
          }
        }
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _nameController.dispose();
    _descriptionController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  String _tr(String key, String fallback) {
    try {
      final val = context.l10n.translate(key);
      if (val.isNotEmpty && val != key) return val;
    } catch (_) {}
    return fallback;
  }

  String get _cleanUsername =>
      _usernameController.text.trim().replaceAll('@', '');

  String? get _usernameValidationHint {
    if (!_isPublic) return null;
    if (_usernameServerError != null) return _usernameServerError;
    final clean = _cleanUsername;
    if (clean.isEmpty) {
      return 'Введите публичное @username (например, my_channel) или оставьте пустым';
    }
    if (!_usernameRegex.hasMatch(clean)) {
      return 'От 3 до 64 символов: латинские буквы, цифры и _, начинается с буквы';
    }
    return null;
  }

  bool get _isUsernameValid {
    if (!_isPublic) return true;
    final clean = _cleanUsername;
    return clean.isEmpty || _usernameRegex.hasMatch(clean);
  }

  int get _adminsCount {
    final cnt = _members
        .where((m) => m.role == 'owner' || m.role == 'admin')
        .length;
    return cnt > 0 ? cnt : 1;
  }

  int _enabledPermissionsCount(GroupDefaultPermissions p) {
    int count = 0;
    if (p.canSendMessages) count++;
    if (p.canSendMedia) count++;
    if (p.canSendStickersGifs) count++;
    if (p.canSendPolls) count++;
    if (p.canInviteUsers) count++;
    if (p.canPinMessages) count++;
    if (p.canChangeInfo) count++;
    return count;
  }

  String _slowModeBadge(int interval) {
    switch (interval) {
      case 0:
        return '';
      case 10:
        return '10с';
      case 30:
        return '30с';
      case 60:
        return '1м';
      case 300:
        return '5м';
      case 900:
        return '15м';
      case 3600:
        return '1ч';
      default:
        return '$interval с';
    }
  }

  String _reactionSummary() {
    if (_reactionSettings.isNone) return 'Выкл';
    if (_reactionSettings.isSelected) {
      return 'Выбрано ${_reactionSettings.allowedReactions.length}';
    }
    return 'Все';
  }

  Future<void> _pickAvatar() async {
    HapticUtils.tap();
    final picker = ImagePicker();
    final picked = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 88,
    );
    if (picked != null && mounted) {
      setState(() {
        _pickedAvatarFile = File(picked.path);
      });
    }
  }

  Future<void> _saveChanges() async {
    if (_isSaving) return;
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      GlassToastService().show(
        context,
        _tr('group_name_empty_error', 'Введите название'),
      );
      return;
    }
    if (!_isUsernameValid) {
      GlassToastService().show(
        context,
        _usernameValidationHint ?? 'Некорректный формат @username',
      );
      return;
    }

    HapticUtils.tap();
    setState(() => _isSaving = true);

    try {
      String? finalAvatarUrl = _avatarUrl;
      if (_pickedAvatarFile != null) {
        final uploadRes = await FileService().uploadFile(_pickedAvatarFile!);
        finalAvatarUrl = uploadRes.url;
      }

      final cleanUsername = _cleanUsername;
      final payload = <String, dynamic>{
        'name': newName,
        'description': _descriptionController.text.trim(),
        if (finalAvatarUrl != null) 'avatar_url': finalAvatarUrl,
        'is_public': _isPublic,
        'username': _isPublic ? cleanUsername : '',
        if (!widget.isChannel) 'history_for_new': _historyForNew,
        if (!widget.isChannel) 'slow_mode_interval': _slowModeInterval,
        if (widget.isChannel) 'sign_messages': _signMessages,
        if (widget.isChannel)
          'show_author_profiles': _signMessages ? _showAuthorProfiles : false,
      };

      final res = await ChatService.updateGroupSettings(widget.chatId, payload);
      if (!mounted) return;

      if (res['success'] != true) {
        final msg = res['message']?.toString() ?? 'Ошибка сохранения';
        if (res['status_code'] == 409 ||
            msg.toLowerCase().contains('username')) {
          setState(() => _usernameServerError = msg);
        }
        GlassToastService().show(context, msg);
        return;
      }

      try {
        if (finalAvatarUrl != null && finalAvatarUrl.isNotEmpty) {
          await AppDatabase().updateChatAvatar(widget.chatId, finalAvatarUrl);
        }
      } catch (_) {}

      if (!mounted) return;
      _avatarUrl = finalAvatarUrl;
      Navigator.pop<Map<String, dynamic>>(context, _buildResultMap());
    } catch (e) {
      if (!mounted) return;
      GlassToastService().show(context, 'Ошибка сохранения: $e');
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Map<String, dynamic> _buildResultMap() {
    return {
      'name': _nameController.text.trim(),
      'description': _descriptionController.text.trim(),
      if (_avatarUrl != null) 'avatar_url': _avatarUrl,
      'is_public': _isPublic,
      'username': _isPublic ? _cleanUsername : '',
      'history_for_new': _historyForNew,
      'slow_mode_interval': _slowModeInterval,
      if (widget.isChannel) 'sign_messages': _signMessages,
      if (widget.isChannel)
        'show_author_profiles': _signMessages ? _showAuthorProfiles : false,
      'linked_chat_id': _linkedChatId ?? '',
      if (_linkedChat != null) 'linked_chat': _linkedChat,
      'default_permissions': _defaultPermissions,
      'reaction_settings': _reactionSettings,
      if (_inviteLink != null) 'invite_link': _inviteLink,
    };
  }

  void _handleBack() {
    if (_subSettingsChanged) {
      Navigator.pop<Map<String, dynamic>>(context, _buildResultMap());
    } else {
      Navigator.maybePop(context);
    }
  }

  Future<void> _openDiscussionSettings() async {
    HapticUtils.tap();
    final res = await Navigator.push<Map<String, dynamic>>(
      context,
      SwipeBackPageRoute(
        builder: (_) => ChannelDiscussionSettingsScreen(
          channelId: widget.chatId,
          channelName: _nameController.text.trim().isNotEmpty
              ? _nameController.text.trim()
              : widget.initialName,
          currentLinkedChatId: _linkedChatId,
          currentLinkedChat: _linkedChat,
        ),
      ),
    );
    if (res != null && mounted) {
      setState(() {
        final rawId = res['linked_chat_id']?.toString().trim() ?? '';
        _linkedChatId = rawId.isNotEmpty ? rawId : null;
        _linkedChat = res['linked_chat'] as LinkedChatSummary?;
        _subSettingsChanged = true;
      });
    }
  }

  Future<void> _openGroupPermissions() async {
    HapticUtils.tap();
    final res = await Navigator.push<Map<String, dynamic>>(
      context,
      SwipeBackPageRoute(
        builder: (_) => GroupPermissionsScreen(
          chatId: widget.chatId,
          initialPermissions: _defaultPermissions,
          initialSlowMode: _slowModeInterval,
        ),
      ),
    );
    if (res != null && mounted) {
      setState(() {
        if (res['default_permissions'] is GroupDefaultPermissions) {
          _defaultPermissions =
              res['default_permissions'] as GroupDefaultPermissions;
        }
        if (res['slow_mode_interval'] is int) {
          _slowModeInterval = res['slow_mode_interval'] as int;
        }
        _subSettingsChanged = true;
      });
    }
  }

  Future<void> _openReactionsSettings() async {
    HapticUtils.tap();
    final updated = await Navigator.push<ReactionSettings>(
      context,
      SwipeBackPageRoute(
        builder: (_) => ChatReactionsSettingsScreen(
          chatId: widget.chatId,
          initialSettings: _reactionSettings,
        ),
      ),
    );
    if (updated != null && mounted) {
      setState(() {
        _reactionSettings = updated;
        _subSettingsChanged = true;
      });
    }
  }

  Future<void> _openInviteLinks() async {
    HapticUtils.tap();
    final updatedPrimary = await Navigator.push<String>(
      context,
      SwipeBackPageRoute(
        builder: (_) => InviteLinksScreen(
          chatId: widget.chatId,
          chatType: widget.isChannel ? 'channel' : 'group',
          primaryInviteLink: _inviteLink,
        ),
      ),
    );
    if (updatedPrimary != null &&
        updatedPrimary.isNotEmpty &&
        updatedPrimary != _inviteLink &&
        mounted) {
      setState(() {
        _inviteLink = updatedPrimary;
        _subSettingsChanged = true;
      });
    }
  }

  Future<void> _showHistoryVisibilitySheet() async {
    HapticUtils.tap();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeExt = Theme.of(context).extension<TheavThemeExtension>();
    final accentColor = themeExt?.palette.primary ??
        (isDark ? const Color(0xFF64B5F6) : const Color(0xFF0088CC));
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.68)
        : const Color(0xFF475569);

    final selected = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SettingsAttachedSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'История чата для новых участников',
              style: TextStyle(
                fontSize: 17.5,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              minTileHeight: 54,
              leading: iconoir.Eye(width: 22, height: 22, color: accentColor),
              title: Text(
                'Видна',
                style: TextStyle(fontWeight: FontWeight.w600, color: textColor),
              ),
              subtitle: Text(
                'Новые участники увидят сообщения, отправленные до их вступления',
                style: TextStyle(fontSize: 12.5, color: subColor),
              ),
              trailing: _historyForNew
                  ? iconoir.Check(width: 20, height: 20, color: accentColor)
                  : null,
              onTap: () => Navigator.pop(ctx, true),
            ),
            const Divider(height: 1),
            ListTile(
              contentPadding: EdgeInsets.zero,
              minTileHeight: 54,
              leading:
                  iconoir.EyeClosed(width: 22, height: 22, color: accentColor),
              title: Text(
                'Скрыта',
                style: TextStyle(fontWeight: FontWeight.w600, color: textColor),
              ),
              subtitle: Text(
                'Новые участники увидят переписку только с момента вступления',
                style: TextStyle(fontSize: 12.5, color: subColor),
              ),
              trailing: !_historyForNew
                  ? iconoir.Check(width: 20, height: 20, color: accentColor)
                  : null,
              onTap: () => Navigator.pop(ctx, false),
            ),
          ],
        ),
      ),
    );
    if (selected != null && mounted) {
      HapticUtils.selection();
      setState(() => _historyForNew = selected);
    }
  }

  Future<void> _openAdminsSheet() async {
    HapticUtils.tap();
    if (_members.isEmpty) {
      final loaded = await ChatService.getGroupMembers(widget.chatId);
      if (mounted) setState(() => _members = loaded);
    }
    if (!mounted) return;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final themeExt = Theme.of(context).extension<TheavThemeExtension>();
    final accentColor = themeExt?.palette.primary ??
        (isDark ? const Color(0xFF64B5F6) : const Color(0xFF0088CC));
    final textColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
    final subColor = isDark
        ? Colors.white.withValues(alpha: 0.68)
        : const Color(0xFF475569);
    final currentUserId = AccountManager().currentAccount?.userId;
    final canAddAdmins =
        _myRole == 'owner' || (_myAdminPermissions?.canAddAdmins ?? false);

    final admins = _members
        .where((m) => m.role == 'owner' || m.role == 'admin')
        .toList();
    final regularMembers = _members
        .where((m) => m.role != 'owner' && m.role != 'admin')
        .toList();

    final picked = await showModalBottomSheet<ChatParticipant>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => SettingsAttachedSheet(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Администраторы',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: textColor,
              ),
            ),
            const SizedBox(height: 10),
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: [
                  for (final admin in admins)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      minTileHeight: 54,
                      leading: AvatarWithStatus(
                        userId: admin.id,
                        avatarUrl: admin.avatarUrl,
                        name: admin.displayName,
                        radius: 20,
                      ),
                      title: Text(
                        admin.displayName.isNotEmpty
                            ? admin.displayName
                            : '@${admin.username}',
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          color: textColor,
                        ),
                      ),
                      subtitle: Text(
                        admin.adminTitle.isNotEmpty
                            ? admin.adminTitle
                            : (admin.role == 'owner'
                                ? 'Владелец'
                                : 'Администратор'),
                        style: TextStyle(fontSize: 12.5, color: subColor),
                      ),
                      trailing: (admin.role != 'owner' ||
                              admin.id == currentUserId)
                          ? iconoir.NavArrowRight(
                              width: 18,
                              height: 18,
                              color: subColor,
                            )
                          : null,
                      onTap: (admin.role != 'owner' || admin.id == currentUserId)
                          ? () => Navigator.pop(ctx, admin)
                          : null,
                    ),
                  if (canAddAdmins && regularMembers.isNotEmpty) ...[
                    const Divider(height: 20),
                    Text(
                      'НАЗНАЧИТЬ ИЗ УЧАСТНИКОВ',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: subColor,
                      ),
                    ),
                    const SizedBox(height: 6),
                    for (final member in regularMembers)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        minTileHeight: 52,
                        leading: AvatarWithStatus(
                          userId: member.id,
                          avatarUrl: member.avatarUrl,
                          name: member.displayName,
                          radius: 19,
                        ),
                        title: Text(
                          member.displayName.isNotEmpty
                              ? member.displayName
                              : '@${member.username}',
                          style: TextStyle(
                            fontWeight: FontWeight.w500,
                            color: textColor,
                          ),
                        ),
                        trailing: iconoir.Plus(
                          width: 18,
                          height: 18,
                          color: accentColor,
                        ),
                        onTap: () => Navigator.pop(ctx, member),
                      ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );

    if (picked != null && mounted) {
      final changed = await Navigator.push<bool>(
        context,
        SwipeBackPageRoute(
          builder: (_) => AdminRightsScreen(
            chatId: widget.chatId,
            chatType: widget.isChannel ? 'channel' : 'group',
            participant: picked,
            isOwnerCaller: _myRole == 'owner',
          ),
        ),
      );
      if (changed == true && mounted) {
        _subSettingsChanged = true;
        final updatedMembers = await ChatService.getGroupMembers(widget.chatId);
        if (mounted) setState(() => _members = updatedMembers);
      }
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
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    final validAvatar = getValidAvatarUrl(_avatarUrl);

    final slowBadge = _slowModeBadge(_slowModeInterval);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _handleBack();
      },
      child: SettingsFloatingScaffold(
        title: widget.isChannel
            ? _tr('edit_channel_title', 'Изменить канал')
            : _tr('edit_group_title', 'Изменить группу'),
        backgroundColor: bgColor,
        onBack: _handleBack,
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
              onTap: _saveChanges,
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
            // 1. Аватар
            Center(
              child: GestureDetector(
                onTap: _pickAvatar,
                child: Stack(
                  children: [
                    CircleAvatar(
                      radius: 48,
                      backgroundColor: accentColor.withValues(alpha: 0.2),
                      backgroundImage: _pickedAvatarFile != null
                          ? FileImage(_pickedAvatarFile!) as ImageProvider
                          : (validAvatar != null && validAvatar.isNotEmpty
                              ? CachedNetworkImageProvider(validAvatar)
                              : null),
                      child: (_pickedAvatarFile == null &&
                              (validAvatar == null || validAvatar.isEmpty))
                          ? Text(
                              _nameController.text.trim().isNotEmpty
                                  ? _nameController.text.trim()[0].toUpperCase()
                                  : (widget.isChannel ? 'C' : 'G'),
                              style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.w600,
                                color: accentColor,
                              ),
                            )
                          : null,
                    ),
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: accentColor,
                          shape: BoxShape.circle,
                          border: Border.all(color: bgColor, width: 2),
                        ),
                        alignment: Alignment.center,
                        child: const iconoir.Camera(
                          width: 16,
                          height: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 22),

            // 2. Название и описание
            _buildCard(
              context,
              glassProvider: glassProvider,
              isDark: isDark,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Column(
                  children: [
                    TextField(
                      controller: _nameController,
                      style: TextStyle(fontSize: 16, color: textColor),
                      decoration: InputDecoration(
                        labelText: widget.isChannel
                            ? _tr('channel_name_label', 'Название канала')
                            : _tr('group_name_label', 'Название группы'),
                        labelStyle: TextStyle(color: subColor),
                        border: InputBorder.none,
                      ),
                    ),
                    Divider(height: 1, color: dividerColor),
                    TextField(
                      controller: _descriptionController,
                      maxLines: 3,
                      minLines: 1,
                      style: TextStyle(fontSize: 15, color: textColor),
                      decoration: InputDecoration(
                        labelText: _tr(
                          'group_info_description',
                          'Описание (необязательно)',
                        ),
                        labelStyle: TextStyle(color: subColor),
                        border: InputBorder.none,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),

            // 3. Тип: Публичный vs Частный + @username
            _buildCard(
              context,
              glassProvider: glassProvider,
              isDark: isDark,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildSwitchRow(
                    glassProvider: glassProvider,
                    icon: iconoir.Globe(
                      width: 20,
                      height: 20,
                      color: accentColor,
                    ),
                    title: widget.isChannel
                        ? _tr('channel_public_toggle', 'Публичный канал')
                        : _tr('group_info_public', 'Публичная группа'),
                    subtitle: _isPublic
                        ? 'Можно найти через поиск и открыть по @username'
                        : 'Доступ только по пригласительной ссылке',
                    value: _isPublic,
                    accentColor: accentColor,
                    textColor: textColor,
                    subColor: subColor,
                    onChanged: (v) {
                      HapticUtils.selection();
                      setState(() => _isPublic = v);
                    },
                  ),
                  AnimatedSize(
                    duration: disableAnim
                        ? Duration.zero
                        : const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: _isPublic
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Divider(
                                height: 1,
                                indent: 54,
                                color: dividerColor,
                              ),
                              Padding(
                                padding: const EdgeInsets.fromLTRB(
                                  16,
                                  6,
                                  16,
                                  10,
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    TextField(
                                      controller: _usernameController,
                                      style: TextStyle(
                                        fontSize: 15.5,
                                        color: textColor,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: 'Публичный @username',
                                        labelStyle: TextStyle(color: subColor),
                                        prefixText: '@',
                                        prefixStyle: TextStyle(
                                          fontSize: 15.5,
                                          fontWeight: FontWeight.w600,
                                          color: accentColor,
                                        ),
                                        suffixIcon: _cleanUsername.isNotEmpty
                                            ? Padding(
                                                padding:
                                                    const EdgeInsets.all(12),
                                                child: _isUsernameValid
                                                    ? const iconoir.CheckCircle(
                                                        width: 18,
                                                        height: 18,
                                                        color:
                                                            Color(0xFF34C759),
                                                      )
                                                    : const iconoir
                                                        .WarningCircle(
                                                        width: 18,
                                                        height: 18,
                                                        color: Colors.redAccent,
                                                      ),
                                              )
                                            : null,
                                        border: InputBorder.none,
                                      ),
                                    ),
                                    if (_usernameValidationHint != null)
                                      Text(
                                        _usernameValidationHint!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: _usernameServerError != null ||
                                                  (_cleanUsername.isNotEmpty &&
                                                      !_isUsernameValid)
                                              ? Colors.redAccent
                                              : subColor,
                                        ),
                                      )
                                    else if (_cleanUsername.isNotEmpty)
                                      Text(
                                        'Ссылка: https://theaver.app/@$_cleanUsername',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: accentColor,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),

            // 4. Подпись авторов в канале (2 уровня)
            if (widget.isChannel) ...[
              const SizedBox(height: 16),
              _buildCard(
                context,
                glassProvider: glassProvider,
                isDark: isDark,
                child: Column(
                  children: [
                    _buildSwitchRow(
                      glassProvider: glassProvider,
                      icon: iconoir.EditPencil(
                        width: 20,
                        height: 20,
                        color: accentColor,
                      ),
                      title: 'Подписывать сообщения',
                      subtitle: 'Показывать имя автора в нижней строке поста',
                      value: _signMessages,
                      accentColor: accentColor,
                      textColor: textColor,
                      subColor: subColor,
                      onChanged: (v) {
                        HapticUtils.selection();
                        setState(() {
                          _signMessages = v;
                          if (!v) _showAuthorProfiles = false;
                        });
                      },
                    ),
                    AnimatedSize(
                      duration: disableAnim
                          ? Duration.zero
                          : const Duration(milliseconds: 220),
                      curve: Curves.easeOutCubic,
                      child: AnimatedOpacity(
                        duration: disableAnim
                            ? Duration.zero
                            : const Duration(milliseconds: 180),
                        opacity: _signMessages ? 1.0 : 0.0,
                        child: _signMessages
                            ? Column(
                                children: [
                                  Divider(
                                    height: 1,
                                    indent: 54,
                                    color: dividerColor,
                                  ),
                                  _buildSwitchRow(
                                    glassProvider: glassProvider,
                                    icon: iconoir.User(
                                      width: 20,
                                      height: 20,
                                      color: accentColor,
                                    ),
                                    title: 'Профили авторов',
                                    subtitle:
                                        'Отображать аватар и ссылку на профиль автора поста',
                                    value: _showAuthorProfiles,
                                    accentColor: accentColor,
                                    textColor: textColor,
                                    subColor: subColor,
                                    onChanged: (v) {
                                      HapticUtils.selection();
                                      setState(() => _showAuthorProfiles = v);
                                    },
                                  ),
                                ],
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // 5. Telegram-навигация управления
            const SizedBox(height: 16),
            _buildCard(
              context,
              glassProvider: glassProvider,
              isDark: isDark,
              child: Column(
                children: [
                  if (widget.isChannel) ...[
                    _buildNavRow(
                      icon: iconoir.ChatLines(
                        width: 20,
                        height: 20,
                        color: accentColor,
                      ),
                      title: 'Обсуждение',
                      trailingText: _linkedChat?.name.isNotEmpty == true
                          ? _linkedChat!.name
                          : ((_linkedChatId ?? '').isNotEmpty
                              ? 'Группа #$_linkedChatId'
                              : 'Добавить группу'),
                      accentColor: accentColor,
                      textColor: textColor,
                      subColor: subColor,
                      onTap: _openDiscussionSettings,
                    ),
                    Divider(height: 1, indent: 54, color: dividerColor),
                  ] else ...[
                    _buildNavRow(
                      icon: iconoir.Lock(
                        width: 20,
                        height: 20,
                        color: accentColor,
                      ),
                      title: 'Разрешения',
                      trailingText:
                          '${_enabledPermissionsCount(_defaultPermissions)}/7',
                      trailingBadge: slowBadge.isNotEmpty ? slowBadge : null,
                      accentColor: accentColor,
                      textColor: textColor,
                      subColor: subColor,
                      onTap: _openGroupPermissions,
                    ),
                    Divider(height: 1, indent: 54, color: dividerColor),
                    _buildNavRow(
                      icon: iconoir.Clock(
                        width: 20,
                        height: 20,
                        color: accentColor,
                      ),
                      title: 'История чата для новых участников',
                      trailingText: _historyForNew ? 'Видна' : 'Скрыта',
                      accentColor: accentColor,
                      textColor: textColor,
                      subColor: subColor,
                      onTap: _showHistoryVisibilitySheet,
                    ),
                    Divider(height: 1, indent: 54, color: dividerColor),
                  ],
                  _buildNavRow(
                    icon: iconoir.Heart(
                      width: 20,
                      height: 20,
                      color: accentColor,
                    ),
                    title: 'Реакции',
                    trailingText: _reactionSummary(),
                    accentColor: accentColor,
                    textColor: textColor,
                    subColor: subColor,
                    onTap: _openReactionsSettings,
                  ),
                  Divider(height: 1, indent: 54, color: dividerColor),
                  _buildNavRow(
                    icon: iconoir.Link(
                      width: 20,
                      height: 20,
                      color: accentColor,
                    ),
                    title: 'Пригласительные ссылки',
                    trailingText:
                        (_inviteLink ?? '').isNotEmpty ? 'Активна' : '',
                    accentColor: accentColor,
                    textColor: textColor,
                    subColor: subColor,
                    onTap: _openInviteLinks,
                  ),
                  Divider(height: 1, indent: 54, color: dividerColor),
                  _buildNavRow(
                    icon: iconoir.ShieldCheck(
                      width: 20,
                      height: 20,
                      color: accentColor,
                    ),
                    title: 'Администраторы',
                    trailingText: '$_adminsCount',
                    accentColor: accentColor,
                    textColor: textColor,
                    subColor: subColor,
                    onTap: _openAdminsSheet,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNavRow({
    required Widget icon,
    required String title,
    required String trailingText,
    String? trailingBadge,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
    required VoidCallback onTap,
  }) {
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
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (trailingBadge != null && trailingBadge.isNotEmpty) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  trailingBadge,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                    color: accentColor,
                  ),
                ),
              ),
              const SizedBox(width: 6),
            ],
            if (trailingText.isNotEmpty)
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 130),
                child: Text(
                  trailingText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: accentColor,
                  ),
                ),
              ),
            const SizedBox(width: 4),
            iconoir.NavArrowRight(width: 18, height: 18, color: subColor),
          ],
        ),
        onTap: onTap,
      ),
    );
  }

  Widget _buildSwitchRow({
    required LiquidGlassProvider? glassProvider,
    required Widget icon,
    required String title,
    String? subtitle,
    required bool value,
    required Color accentColor,
    required Color textColor,
    required Color subColor,
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
        subtitle: subtitle != null
            ? Text(
                subtitle,
                style: TextStyle(fontSize: 12.5, color: subColor),
              )
            : null,
        trailing: trailing,
        onTap: () => onChanged(!value),
      ),
    );
  }

  Widget _buildCard(
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
