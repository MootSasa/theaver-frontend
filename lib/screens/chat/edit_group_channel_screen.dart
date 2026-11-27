import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../l10n/app_localizations.dart';
import '../../models/avatar_editor_models.dart';
import '../../services/account_manager.dart';
import '../../services/chat_instant_cache.dart';
import '../../services/chat_service.dart';
import '../../services/contacts_service.dart';
import '../../services/database/app_database.dart';
import '../../services/glass_toast_service.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/image_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../../widgets/avatar_editor/theav_avatar_picker_sheet.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/settings/settings_floating_header.dart';
import '../../widgets/user/avatar_with_status.dart';
import 'forum_topics_screen.dart';
import 'settings/admin_log_screen.dart';
import 'settings/admin_rights_screen.dart';
import 'settings/channel_discussion_settings_screen.dart';
import 'settings/channel_stats_screen.dart';
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
  final bool initialHasProtectedContent;
  final bool canEditAdminSettings;
  final bool initialIsForum;
  final bool initialParticipantsHidden;
  final bool initialAggressiveAntiSpam;

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
    this.initialHasProtectedContent = false,
    this.canEditAdminSettings = true,
    this.initialIsForum = false,
    this.initialParticipantsHidden = false,
    this.initialAggressiveAntiSpam = false,
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
  Uint8List? _pickedAvatarBytes;
  Uint8List? _pickedAvatarPreviewBytes;
  String? _pickedAvatarFileName;
  String? _pickedAvatarCrop;
  bool _deleteAvatarRequested = false;
  late bool _isPublic;
  late bool _historyForNew;
  late int _slowModeInterval;
  late bool _signMessages;
  late bool _showAuthorProfiles;
  late bool _hasProtectedContent;
  late bool _isForum;
  late bool _participantsHidden;
  late bool _aggressiveAntiSpam;
  String? _linkedChatId;
  LinkedChatSummary? _linkedChat;
  late GroupDefaultPermissions _defaultPermissions;
  late ReactionSettings _reactionSettings;
  String? _inviteLink;
  String _myRole = 'admin';
  AdminRights? _myAdminPermissions;
  List<ChatParticipant> _members = [];

  bool get _canEditAdminSettingsEffective =>
      widget.canEditAdminSettings &&
      (_myRole == 'owner' || _myRole == 'admin');

  String? _usernameServerError;
  bool _isSaving = false;
  bool _subSettingsChanged = false;
  bool _nameEditedByUser = false;
  bool _descriptionEditedByUser = false;
  bool _usernameEditedByUser = false;
  bool _publicEditedByUser = false;
  bool _isApplyingServerSettings = false;

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
    _hasProtectedContent = widget.initialHasProtectedContent;
    _isForum = !widget.isChannel && widget.initialIsForum;
    _participantsHidden = !widget.isChannel && widget.initialParticipantsHidden;
    _aggressiveAntiSpam = !widget.isChannel && widget.initialAggressiveAntiSpam;
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
    _myRole = widget.canEditAdminSettings ? 'admin' : 'member';
    ContactsService.revisionNotifier.addListener(_onContactsRevisionChanged);

    _usernameController.addListener(() {
      if (!_isApplyingServerSettings) {
        _usernameEditedByUser = true;
      }
      if (!mounted) return;
      if (_usernameServerError != null) {
        setState(() => _usernameServerError = null);
      } else {
        setState(() {});
      }
    });
    _nameController.addListener(() {
      if (!_isApplyingServerSettings) {
        _nameEditedByUser = true;
      }
      if (mounted) setState(() {});
    });
    _descriptionController.addListener(() {
      if (!_isApplyingServerSettings) {
        _descriptionEditedByUser = true;
      }
    });

    unawaited(_loadChatSettings());
  }

  Future<void> _loadChatSettings() async {
    try {
      final shouldLoadMembers = widget.canEditAdminSettings || !widget.isChannel;
      final results = await Future.wait([
        ChatService.getGroupSettings(widget.chatId),
        shouldLoadMembers
            ? ChatService.getGroupMembers(widget.chatId)
            : Future.value(<ChatParticipant>[]),
      ]);
      if (!mounted) return;

      final res = results[0] as Map<String, dynamic>;
      final members = results[1] as List<ChatParticipant>;
      final currentUserId = AccountManager().currentAccount?.userId;

      setState(() {
        if (members.isNotEmpty) {
          _members = members;
        }
        if (res['success'] == true) {
          _isApplyingServerSettings = true;
          try {
            if (!_nameEditedByUser &&
                res['name'] != null &&
                res['name'].toString().isNotEmpty) {
              _nameController.text = res['name'].toString();
            }
            if (!_descriptionEditedByUser && res['description'] != null) {
              _descriptionController.text = res['description'].toString();
            }
            if (!_usernameEditedByUser && res['username'] != null) {
              _usernameController.text = res['username'].toString();
            }
          } finally {
            _isApplyingServerSettings = false;
          }
          final srvAvatar = res['avatar_url']?.toString();
          if (srvAvatar != null && srvAvatar.isNotEmpty) {
            _avatarUrl = srvAvatar;
          }
          if (!_publicEditedByUser &&
              !_usernameEditedByUser &&
              res['is_public'] is bool) {
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
          final protectedRaw = res['has_protected_content'];
          if (protectedRaw != null) {
            _hasProtectedContent = protectedRaw == true ||
                protectedRaw == 1 ||
                protectedRaw == 'true';
          }
          if (res['my_role'] != null) {
            _myRole = res['my_role'].toString();
          }
          if (!widget.isChannel) {
            if (res['is_forum'] is bool) {
              _isForum = res['is_forum'] as bool;
            }
            if (res['participants_hidden'] is bool) {
              _participantsHidden = res['participants_hidden'] as bool;
            }
            if (res['has_aggressive_anti_spam_enabled'] is bool) {
              _aggressiveAntiSpam =
                  res['has_aggressive_anti_spam_enabled'] as bool;
            }
          }
          final adminPerms = AdminRights.tryParse(res['my_admin_permissions']);
          if (adminPerms != null) {
            _myAdminPermissions = adminPerms;
          }
        }
        if (currentUserId != null && _members.isNotEmpty) {
          final me = _members.where((m) => m.id == currentUserId).firstOrNull;
          if (me != null) {
            if (me.role == 'owner' || me.role == 'admin') {
              _myRole = me.role;
            }
            if (_myAdminPermissions == null && me.adminPermissions != null) {
              _myAdminPermissions = me.adminPermissions;
            }
          }
        }
      });
    } catch (_) {}
  }

  void _onContactsRevisionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ContactsService.revisionNotifier.removeListener(_onContactsRevisionChanged);
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
    if (p.canSendPhotos) count++;
    if (p.canSendVideos) count++;
    if (p.canSendMusic) count++;
    if (p.canSendFiles) count++;
    if (p.canSendVoiceNotes) count++;
    if (p.canSendVideoNotes) count++;
    if (p.canSendStickersGifs) count++;
    if (p.canSendPolls) count++;
    if (p.canAddWebPagePreviews) count++;
    if (p.canInviteUsers) count++;
    if (p.canPinMessages) count++;
    if (p.canChangeInfo) count++;
    if (_isForum && p.canManageTopics) count++;
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

  bool get _hasNewPickedAvatar =>
      _pickedAvatarFile != null ||
      (_pickedAvatarBytes != null && _pickedAvatarBytes!.isNotEmpty);

  bool get _hasActiveAvatarPreview {
    if (_hasNewPickedAvatar) return true;
    if (_deleteAvatarRequested) return false;
    final valid = getValidAvatarUrl(_avatarUrl);
    return valid != null && valid.isNotEmpty;
  }

  ImageProvider? get _previewAvatarImage {
    if (_pickedAvatarPreviewBytes != null &&
        _pickedAvatarPreviewBytes!.isNotEmpty) {
      return MemoryImage(_pickedAvatarPreviewBytes!);
    }
    if (_pickedAvatarBytes != null && _pickedAvatarBytes!.isNotEmpty) {
      return MemoryImage(_pickedAvatarBytes!);
    }
    if (_pickedAvatarFile != null) {
      return FileImage(_pickedAvatarFile!);
    }
    if (_deleteAvatarRequested) return null;
    final valid = getValidAvatarUrl(_avatarUrl);
    if (valid == null || valid.isEmpty) return null;
    return avatarImageProvider(valid, maxDecodeDimension: 288);
  }

  Future<void> _pickAvatar() async {
    HapticUtils.tap();
    final trimmedName = _nameController.text.trim();
    final picked = await TheavAvatarPickerSheet.pickAndEdit(
      context: context,
      maskShape: AvatarShapeMask.circle,
      ctaMode: AvatarEditorCtaMode.setPhoto,
      subjectName: trimmedName.isNotEmpty ? trimmedName : widget.initialName,
      canDeleteCurrent: _hasActiveAvatarPreview,
    );
    if (picked == null || !mounted) return;
    if (picked.deletedCurrent) {
      setState(() {
        _pickedAvatarFile = null;
        _pickedAvatarBytes = null;
        _pickedAvatarPreviewBytes = null;
        _pickedAvatarFileName = null;
        _pickedAvatarCrop = null;
        _deleteAvatarRequested = true;
      });
      return;
    }
    if (picked.hasMedia) {
      setState(() {
        _pickedAvatarFile = picked.file;
        _pickedAvatarBytes = picked.bytes;
        _pickedAvatarPreviewBytes = picked.effectivePreviewBytes;
        _pickedAvatarFileName = picked.fileName;
        _pickedAvatarCrop = picked.miniCrop?.toCompactParam();
        _deleteAvatarRequested = false;
      });
    }
  }

  Future<void> _confirmAndStageDeleteAvatar() async {
    if (!_hasActiveAvatarPreview || _isSaving) return;
    HapticUtils.heavy();
    final confirmed = await showTheavDialog<bool>(
      context: context,
      title: _tr('avatar_delete_photo', 'Удалить фото'),
      message: _tr(
        'avatar_delete_confirm_chat',
        'Удалить текущее фото чата?',
      ),
      actions: [
        TheavDialogAction<bool>(
          label: _tr('profile_cancel', 'Отмена'),
          result: false,
        ),
        TheavDialogAction<bool>(
          label: _tr('avatar_delete_photo', 'Удалить фото'),
          result: true,
          isDestructive: true,
        ),
      ],
    );
    if (confirmed == true && mounted) {
      setState(() {
        _pickedAvatarFile = null;
        _pickedAvatarBytes = null;
        _pickedAvatarPreviewBytes = null;
        _pickedAvatarFileName = null;
        _pickedAvatarCrop = null;
        _deleteAvatarRequested = true;
      });
    }
  }

  Future<void> _syncChatAvatarLocalCaches(
    String avatarUrl, {
    List<ChatAvatarItem>? avatars,
  }) async {
    try {
      await AppDatabase().updateChatAvatar(widget.chatId, avatarUrl);
    } catch (_) {}
    final snap = ChatInstantCache.instance.getSync(widget.chatId);
    if (snap?.chat != null) {
      ChatInstantCache.instance.putChatSummaries([
        snap!.chat!.copyWith(avatarUrl: avatarUrl),
      ]);
    }
    if (snap?.chatDetails != null) {
      ChatInstantCache.instance.putChatDetails(
        snap!.chatDetails!.copyWith(
          avatarUrl: avatarUrl,
          avatars: avatars,
        ),
      );
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
    if (_canEditAdminSettingsEffective && !_isUsernameValid) {
      GlassToastService().show(
        context,
        _usernameValidationHint ?? 'Некорректный формат @username',
      );
      return;
    }

    HapticUtils.tap();
    setState(() => _isSaving = true);

    try {
      if (_deleteAvatarRequested && !_hasNewPickedAvatar) {
        final hasServerAvatar = getValidAvatarUrl(_avatarUrl) != null;
        if (hasServerAvatar) {
          final delRes = await ChatService.deleteChatAvatar(widget.chatId);
          if (!mounted) return;
          if (delRes['success'] != true) {
            GlassToastService().showError(
              context,
              delRes['message']?.toString() ?? 'Не удалось удалить фото',
            );
            return;
          }
          final nextUrl = delRes['avatar_url']?.toString().trim() ?? '';
          _avatarUrl = nextUrl;
          _deleteAvatarRequested = false;
          await _syncChatAvatarLocalCaches(nextUrl);
        } else {
          _deleteAvatarRequested = false;
        }
      } else if (_hasNewPickedAvatar) {
        final uploadFile = _pickedAvatarFile ??
            File(
              (_pickedAvatarFileName != null &&
                      _pickedAvatarFileName!.trim().isNotEmpty)
                  ? _pickedAvatarFileName!.trim()
                  : 'avatar.jpg',
            );
        final uploadRes = await ChatService.uploadChatAvatar(
          widget.chatId,
          uploadFile,
          bytes: _pickedAvatarBytes,
          fileName: _pickedAvatarFileName,
          avatarCrop: _pickedAvatarCrop,
        );
        if (!mounted) return;
        if (uploadRes['success'] != true) {
          GlassToastService().showError(
            context,
            uploadRes['message']?.toString() ?? 'Не удалось загрузить фото',
          );
          return;
        }
        final uploadedUrl = uploadRes['avatar_url']?.toString().trim() ?? '';
        final List<ChatAvatarItem>? updatedAvatars =
            uploadRes['avatars'] is List<ChatAvatarItem>
                ? uploadRes['avatars'] as List<ChatAvatarItem>
                : null;
        _avatarUrl = uploadedUrl;
        _pickedAvatarFile = null;
        _pickedAvatarBytes = null;
        _pickedAvatarPreviewBytes = null;
        _pickedAvatarFileName = null;
        _pickedAvatarCrop = null;
        _deleteAvatarRequested = false;
        await _syncChatAvatarLocalCaches(uploadedUrl, avatars: updatedAvatars);
      }

      final cleanUsername = _cleanUsername;
      final payload = _canEditAdminSettingsEffective
          ? <String, dynamic>{
              'name': newName,
              'description': _descriptionController.text.trim(),
              'is_public': _isPublic,
              'username': _isPublic ? cleanUsername : '',
              if (!widget.isChannel) 'history_for_new': _historyForNew,
              if (!widget.isChannel) 'slow_mode_interval': _slowModeInterval,
              if (!widget.isChannel) 'is_forum': _isForum,
              if (!widget.isChannel)
                'participants_hidden': _participantsHidden,
              if (!widget.isChannel)
                'has_aggressive_anti_spam_enabled': _aggressiveAntiSpam,
              'has_protected_content': _hasProtectedContent,
              if (widget.isChannel) 'sign_messages': _signMessages,
              if (widget.isChannel)
                'show_author_profiles':
                    _signMessages ? _showAuthorProfiles : false,
            }
          : <String, dynamic>{
              'name': newName,
              'description': _descriptionController.text.trim(),
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

      if (!mounted) return;
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
      'has_protected_content': _hasProtectedContent,
      if (!widget.isChannel) 'is_forum': _isForum,
      if (!widget.isChannel) 'participants_hidden': _participantsHidden,
      if (!widget.isChannel)
        'has_aggressive_anti_spam_enabled': _aggressiveAntiSpam,
      if (_linkedChat != null) 'linked_chat': _linkedChat,
      'default_permissions': _defaultPermissions,
      'reaction_settings': _reactionSettings,
      if (_inviteLink != null) 'invite_link': _inviteLink,
    };
  }

  void _handleBack() {
    if (!Navigator.of(context).canPop()) return;
    if (_subSettingsChanged) {
      Navigator.pop<Map<String, dynamic>>(context, _buildResultMap());
    } else {
      Navigator.pop(context);
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
          isForum: _isForum,
          initialParticipantsHidden: _participantsHidden,
          initialAggressiveAntiSpam: _aggressiveAntiSpam,
        ),
      ),
    );
    if (!mounted || res == null) return;
    if (res['saved'] == true) {
      setState(() {
        if (res['default_permissions'] is GroupDefaultPermissions) {
          _defaultPermissions =
              res['default_permissions'] as GroupDefaultPermissions;
        }
        if (res['slow_mode_interval'] is int) {
          _slowModeInterval = res['slow_mode_interval'] as int;
        }
        if (res['participants_hidden'] is bool) {
          _participantsHidden = res['participants_hidden'] as bool;
        }
        if (res['has_aggressive_anti_spam_enabled'] is bool) {
          _aggressiveAntiSpam =
              res['has_aggressive_anti_spam_enabled'] as bool;
        }
        _subSettingsChanged = true;
      });
    } else if (res['members_changed'] == true) {
      final updatedMembers = await ChatService.getGroupMembers(widget.chatId);
      if (mounted) {
        setState(() {
          _members = updatedMembers;
          _subSettingsChanged = true;
        });
      }
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
        updatedPrimary != (_inviteLink ?? '') &&
        mounted) {
      setState(() {
        _inviteLink = updatedPrimary;
        _subSettingsChanged = true;
      });
    }
  }

  Future<void> _showHistoryVisibilitySheet() async {
    HapticUtils.tap();
    final palette = context.theav;

    final selected = await showTheavModalSheet<bool>(
      context: context,
      title: 'История чата для новых участников',
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
        child: TheavInsetGroup(
          children: [
            TheavListRow(
              leading: iconoir.Eye(
                width: 20,
                height: 20,
                color: palette.primary,
              ),
              title: 'Видна',
              subtitle:
                  'Новые участники увидят сообщения, отправленные до их вступления',
              trailing: TheavCheckCircle(selected: _historyForNew),
              onTap: () => Navigator.pop(ctx, true),
            ),
            TheavListRow(
              leading: iconoir.EyeClosed(
                width: 20,
                height: 20,
                color: palette.primary,
              ),
              title: 'Скрыта',
              subtitle:
                  'Новые участники увидят переписку только с момента вступления',
              trailing: TheavCheckCircle(selected: !_historyForNew),
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

    final palette = context.theav;
    final currentUserId = AccountManager().currentAccount?.userId;
    final meInList = currentUserId != null
        ? _members.where((m) => m.id == currentUserId).firstOrNull
        : null;
    final effectiveCallerRole =
        (meInList?.role == 'owner' || _myRole == 'owner')
            ? 'owner'
            : (meInList?.role ?? _myRole);
    final AdminRights? effectiveCallerPerms = effectiveCallerRole == 'owner'
        ? const AdminRights.all()
        : (_myAdminPermissions ?? meInList?.adminPermissions);
    final canAddAdmins = effectiveCallerRole == 'owner' ||
        (effectiveCallerPerms?.canAddAdmins ?? false);

    final admins = _members
        .where((m) => m.role == 'owner' || m.role == 'admin')
        .toList();
    final regularMembers = _members
        .where((m) => m.role != 'owner' && m.role != 'admin')
        .toList();

    final picked = await showTheavModalSheet<ChatParticipant>(
      context: context,
      title: 'Администраторы',
      builder: (ctx) => ValueListenableBuilder<int>(
        valueListenable: ContactsService.revisionNotifier,
        builder: (_, __, ___) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (admins.isNotEmpty)
                TheavInsetGroup(
                  children: [
                    for (final admin in admins)
                      Builder(
                        builder: (_) {
                          final rawName = admin.displayName.isNotEmpty
                              ? admin.displayName
                              : '@${admin.username}';
                          final adminName = ContactsService.resolvePeerName(
                            admin.id,
                            rawName,
                            isBot: admin.isBot,
                          );
                          final adminAvatar =
                              ContactsService.resolvePeerAvatarUrl(
                            admin.id,
                            admin.avatarUrl,
                            isBot: admin.isBot,
                          );
                          return TheavListRow(
                            leading: AvatarWithStatus(
                              userId: admin.id,
                              avatarUrl: adminAvatar,
                              name: adminName,
                              radius: 20,
                              resolveContactOverride: !admin.isBot,
                            ),
                            title: adminName,
                            subtitle: admin.adminTitle.isNotEmpty
                                ? admin.adminTitle
                                : (admin.role == 'owner'
                                    ? 'Владелец'
                                    : 'Администратор'),
                            showChevron: true,
                            onTap: () => Navigator.pop(ctx, admin),
                          );
                        },
                      ),
                  ],
                ),
              if (canAddAdmins && regularMembers.isNotEmpty) ...[
                const SizedBox(height: 8),
                TheavInsetGroup(
                  header: 'НАЗНАЧИТЬ ИЗ УЧАСТНИКОВ',
                  children: [
                    for (final member in regularMembers)
                      Builder(
                        builder: (_) {
                          final rawName = member.displayName.isNotEmpty
                              ? member.displayName
                              : '@${member.username}';
                          final memberName = ContactsService.resolvePeerName(
                            member.id,
                            rawName,
                            isBot: member.isBot,
                          );
                          final memberAvatar =
                              ContactsService.resolvePeerAvatarUrl(
                            member.id,
                            member.avatarUrl,
                            isBot: member.isBot,
                          );
                          return TheavListRow(
                            leading: AvatarWithStatus(
                              userId: member.id,
                              avatarUrl: memberAvatar,
                              name: memberName,
                              radius: 19,
                              resolveContactOverride: !member.isBot,
                            ),
                            title: memberName,
                            trailing: iconoir.Plus(
                              width: 18,
                              height: 18,
                              color: palette.primary,
                            ),
                            onTap: () => Navigator.pop(ctx, member),
                          );
                        },
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );

    if (picked != null && mounted) {
      final callerCanEdit = AdminRightsScreen.canCallerEditTarget(
        target: picked,
        callerUserId: currentUserId,
        callerRole: effectiveCallerRole,
        callerPermissions: effectiveCallerPerms,
      );
      final changed = await Navigator.push<bool>(
        context,
        SwipeBackPageRoute(
          builder: (_) => AdminRightsScreen(
            chatId: widget.chatId,
            chatType: widget.isChannel ? 'channel' : 'group',
            participant: picked,
            isOwnerCaller: effectiveCallerRole == 'owner',
            callerCanEdit: callerCanEdit,
            callerPermissions: effectiveCallerPerms,
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

  Future<void> _openTransferOwnershipFlow() async {
    HapticUtils.tap();
    if (_members.isEmpty) {
      final loaded = await ChatService.getGroupMembers(widget.chatId);
      if (mounted) setState(() => _members = loaded);
    }
    if (!mounted) return;

    final currentUserId = AccountManager().currentAccount?.userId;
    final candidates = _members
        .where((m) => m.id != currentUserId && !m.isBot && !m.isBanned)
        .toList()
      ..sort((a, b) {
        final aIsAdmin = a.role == 'admin' ? 0 : 1;
        final bIsAdmin = b.role == 'admin' ? 0 : 1;
        if (aIsAdmin != bIsAdmin) return aIsAdmin.compareTo(bIsAdmin);
        final aName = ContactsService.resolvePeerName(
          a.id,
          a.displayName.isNotEmpty ? a.displayName : '@${a.username}',
          isBot: a.isBot,
        ).toLowerCase();
        final bName = ContactsService.resolvePeerName(
          b.id,
          b.displayName.isNotEmpty ? b.displayName : '@${b.username}',
          isBot: b.isBot,
        ).toLowerCase();
        return aName.compareTo(bName);
      });

    if (candidates.isEmpty) {
      GlassToastService().show(context, 'Нет участников для передачи прав');
      return;
    }

    final picked = await showTheavModalSheet<ChatParticipant>(
      context: context,
      title: 'Передать права владельца',
      builder: (ctx) => ValueListenableBuilder<int>(
        valueListenable: ContactsService.revisionNotifier,
        builder: (_, __, ___) => SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(0, 4, 0, 20),
          child: TheavInsetGroup(
            children: [
              for (final member in candidates)
                Builder(
                  builder: (_) {
                    final rawName = member.displayName.isNotEmpty
                        ? member.displayName
                        : '@${member.username}';
                    final memberName = ContactsService.resolvePeerName(
                      member.id,
                      rawName,
                      isBot: member.isBot,
                    );
                    final memberAvatar = ContactsService.resolvePeerAvatarUrl(
                      member.id,
                      member.avatarUrl,
                      isBot: member.isBot,
                    );
                    return TheavListRow(
                      leading: AvatarWithStatus(
                        userId: member.id,
                        avatarUrl: memberAvatar,
                        name: memberName,
                        radius: 20,
                        resolveContactOverride: !member.isBot,
                      ),
                      title: memberName,
                      subtitle: member.role == 'admin'
                          ? (member.adminTitle.isNotEmpty
                              ? member.adminTitle
                              : 'Администратор')
                          : (widget.isChannel ? 'Подписчик' : 'Участник'),
                      showChevron: true,
                      onTap: () => Navigator.pop(ctx, member),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
    if (picked == null || !mounted) return;

    final candidateName = ContactsService.resolvePeerName(
      picked.id,
      picked.displayName.isNotEmpty
          ? picked.displayName
          : '@${picked.username}',
      isBot: picked.isBot,
    );
    final confirmed = await showTheavDialog<bool>(
      context: context,
      title: 'Передать права владельца?',
      message:
          'Вы передадите все права владельца участнику $candidateName. Это действие нельзя отменить.',
      actions: const [
        TheavDialogAction<bool>(label: 'Отмена', result: false),
        TheavDialogAction<bool>(
          label: 'Передать',
          result: true,
          isDestructive: true,
        ),
      ],
    );
    if (confirmed != true || !mounted) return;

    var res = await ChatService.transferChatOwnership(
      chatId: widget.chatId,
      newOwnerId: picked.id,
    );
    if (!mounted) return;

    final errCode = res['error']?.toString() ?? '';
    final errMsgLower = (res['message']?.toString() ?? '').toLowerCase();
    final needsPassword = res['success'] != true &&
        (errCode == 'PASSWORD_HASH_INVALID' ||
            errMsgLower.contains('password') ||
            errMsgLower.contains('парол'));

    if (needsPassword) {
      final pwdController = TextEditingController();
      final submitted = await showTheavDialog<bool>(
        context: context,
        title: 'Подтверждение 2FA',
        message: 'Введите облачный пароль для передачи прав владельца',
        content: TheavInsetGroup(
          margin: EdgeInsets.zero,
          children: [
            TheavInlineTextField(
              controller: pwdController,
              placeholder: 'Облачный пароль',
              obscureText: true,
              autofocus: true,
            ),
          ],
        ),
        actions: const [
          TheavDialogAction<bool>(label: 'Отмена', result: false),
          TheavDialogAction<bool>(
            label: 'Подтвердить',
            result: true,
            isPrimary: true,
          ),
        ],
      );
      final pwd = pwdController.text;
      pwdController.dispose();
      if (submitted != true || pwd.isEmpty || !mounted) return;

      res = await ChatService.transferChatOwnership(
        chatId: widget.chatId,
        newOwnerId: picked.id,
        password: pwd,
      );
      if (!mounted) return;
    }

    if (res['success'] == true) {
      setState(() {
        _myRole = 'admin';
        _subSettingsChanged = true;
      });
      GlassToastService().show(context, 'Права владельца переданы');
      unawaited(_loadChatSettings());
    } else {
      GlassToastService().showError(
        context,
        res['message']?.toString() ?? 'Не удалось передать права владельца',
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final disableAnim = MediaQuery.disableAnimationsOf(context);
    final previewAvatarImage = _previewAvatarImage;
    final slowBadge = _slowModeBadge(_slowModeInterval);

    return SwipeBackPopScope(
      onSwipeBackPop: _handleBack,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _handleBack();
        },
        child: SettingsFloatingScaffold(
        title: widget.isChannel
            ? _tr('edit_channel_title', 'Изменить канал')
            : _tr('edit_group_title', 'Изменить группу'),
        backgroundColor: palette.background,
        onBack: _handleBack,
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
              onTap: _saveChanges,
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
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  GestureDetector(
                    onTap: _pickAvatar,
                    child: Stack(
                      children: [
                        CircleAvatar(
                          radius: 48,
                          backgroundColor: palette.primary.withValues(alpha: 0.2),
                          backgroundImage: previewAvatarImage,
                          child: previewAvatarImage == null
                              ? Text(
                                  _nameController.text.trim().isNotEmpty
                                      ? _nameController.text
                                          .trim()[0]
                                          .toUpperCase()
                                      : (widget.isChannel ? 'C' : 'G'),
                                  style: TextStyle(
                                    fontSize: 34,
                                    fontWeight: FontWeight.w600,
                                    color: palette.primary,
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
                              color: palette.primary,
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: palette.background,
                                width: 2,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: iconoir.Camera(
                              width: 16,
                              height: 16,
                              color: palette.onPrimary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      TextButton.icon(
                        onPressed: _isSaving ? null : _pickAvatar,
                        icon: iconoir.MediaImage(
                          width: 15,
                          height: 15,
                          color: palette.primary,
                        ),
                        label: Text(
                          _tr('avatar_choose_photo', 'Выбрать фото'),
                          style: TextStyle(
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600,
                            color: palette.primary,
                          ),
                        ),
                      ),
                      if (_hasActiveAvatarPreview)
                        TextButton.icon(
                          onPressed:
                              _isSaving ? null : _confirmAndStageDeleteAvatar,
                          icon: iconoir.Trash(
                            width: 15,
                            height: 15,
                            color: palette.error,
                          ),
                          label: Text(
                            _tr('avatar_delete_photo', 'Удалить фото'),
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w600,
                              color: palette.error,
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Название и описание
            TheavInsetGroup(
              dividerIndent: 16,
              children: [
                TheavInlineTextField(
                  controller: _nameController,
                  label: widget.isChannel
                      ? _tr('channel_name_label', 'Название канала')
                      : _tr('group_name_label', 'Название группы'),
                  placeholder: widget.isChannel
                      ? 'Название канала'
                      : 'Название группы',
                ),
                TheavInlineTextField(
                  controller: _descriptionController,
                  label: _tr(
                    'group_info_description',
                    'Описание (необязательно)',
                  ),
                  placeholder: 'Расскажите подробнее...',
                  maxLines: 3,
                  minLines: 1,
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (_canEditAdminSettingsEffective) ...[
              // Тип: Публичный vs Частный + @username
              TheavInsetGroup(
                footer: _isPublic ? _usernameValidationHint : null,
                children: [
                  TheavListRow(
                    leading: iconoir.Globe(
                      width: 20,
                      height: 20,
                      color: palette.primary,
                    ),
                    title: widget.isChannel
                        ? _tr('channel_public_toggle', 'Публичный канал')
                        : _tr('group_info_public', 'Публичная группа'),
                    subtitle: _isPublic
                        ? 'Можно найти через поиск и открыть по @username'
                        : 'Доступ только по пригласительной ссылке',
                    trailing: TheavSwitch(
                      value: _isPublic,
                      onChanged: (v) {
                        HapticUtils.selection();
                        setState(() {
                          _publicEditedByUser = true;
                          _isPublic = v;
                        });
                      },
                    ),
                    onTap: () {
                      HapticUtils.selection();
                      setState(() {
                        _publicEditedByUser = true;
                        _isPublic = !_isPublic;
                      });
                    },
                  ),
                  if (_isPublic)
                    TheavInlineTextField(
                      controller: _usernameController,
                      label: 'Публичный @username',
                      placeholder: 'username',
                      prefix: Text(
                        '@',
                        style: TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w600,
                          color: palette.primary,
                        ),
                      ),
                      suffix: _cleanUsername.isNotEmpty
                          ? (_isUsernameValid
                              ? const iconoir.CheckCircle(
                                  width: 18,
                                  height: 18,
                                  color: Color(0xFF34C759),
                                )
                              : iconoir.WarningCircle(
                                  width: 18,
                                  height: 18,
                                  color: palette.error,
                                ))
                          : null,
                    ),
                  TheavListRow(
                    leading: iconoir.Lock(
                      width: 20,
                      height: 20,
                      color: palette.primary,
                    ),
                    title: 'Запретить копирование и пересылку',
                    subtitle:
                        'Участники не смогут копировать и сохранять контент',
                    trailing: TheavSwitch(
                      value: _hasProtectedContent,
                      onChanged: (v) {
                        HapticUtils.selection();
                        setState(() => _hasProtectedContent = v);
                      },
                    ),
                    onTap: () {
                      HapticUtils.selection();
                      setState(
                        () => _hasProtectedContent = !_hasProtectedContent,
                      );
                    },
                  ),
                ],
              ),

              // Подпись авторов в канале
              if (widget.isChannel) ...[
                const SizedBox(height: 8),
                TheavInsetGroup(
                  children: [
                    TheavListRow(
                      leading: iconoir.EditPencil(
                        width: 20,
                        height: 20,
                        color: palette.primary,
                      ),
                      title: 'Подписывать сообщения',
                      subtitle: 'Показывать имя автора в нижней строке поста',
                      trailing: TheavSwitch(
                        value: _signMessages,
                        onChanged: (v) {
                          HapticUtils.selection();
                          setState(() {
                            _signMessages = v;
                            if (!v) _showAuthorProfiles = false;
                          });
                        },
                      ),
                      onTap: () {
                        HapticUtils.selection();
                        setState(() {
                          _signMessages = !_signMessages;
                          if (!_signMessages) _showAuthorProfiles = false;
                        });
                      },
                    ),
                    if (_signMessages)
                      AnimatedSize(
                        duration: disableAnim
                            ? Duration.zero
                            : const Duration(milliseconds: 200),
                        curve: Curves.easeOutCubic,
                        child: TheavListRow(
                          leading: iconoir.User(
                            width: 20,
                            height: 20,
                            color: palette.primary,
                          ),
                          title: 'Профили авторов',
                          subtitle:
                              'Отображать аватар и ссылку на профиль автора поста',
                          trailing: TheavSwitch(
                            value: _showAuthorProfiles,
                            onChanged: (v) {
                              HapticUtils.selection();
                              setState(() => _showAuthorProfiles = v);
                            },
                          ),
                          onTap: () {
                            HapticUtils.selection();
                            setState(
                              () =>
                                  _showAuthorProfiles = !_showAuthorProfiles,
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ],

              // Telegram-навигация управления
              const SizedBox(height: 8),
              TheavInsetGroup(
                children: [
                  if (widget.isChannel)
                    TheavListRow(
                      leading: iconoir.ChatLines(
                        width: 20,
                        height: 20,
                        color: palette.primary,
                      ),
                      title: 'Обсуждение',
                      valueText: _linkedChat?.name.isNotEmpty == true
                          ? _linkedChat!.name
                          : ((_linkedChatId ?? '').isNotEmpty
                              ? 'Группа #$_linkedChatId'
                              : 'Добавить группу'),
                      showChevron: true,
                      onTap: _openDiscussionSettings,
                    )
                  else ...[
                    TheavListRow(
                      leading: iconoir.ChatLines(
                        width: 20,
                        height: 20,
                        color: palette.primary,
                      ),
                      title: 'Темы (Форум)',
                      subtitle: 'Организовать обсуждения по отдельным веткам',
                      trailing: TheavSwitch(
                        value: _isForum,
                        onChanged: (v) {
                          HapticUtils.selection();
                          setState(() => _isForum = v);
                        },
                      ),
                      onTap: () {
                        HapticUtils.selection();
                        setState(() => _isForum = !_isForum);
                      },
                    ),
                    if (_isForum)
                      TheavListRow(
                        leading: iconoir.List(
                          width: 20,
                          height: 20,
                          color: palette.primary,
                        ),
                        title: 'Управление темами форума',
                        showChevron: true,
                        onTap: () {
                          HapticUtils.tap();
                          Navigator.push(
                            context,
                            SwipeBackPageRoute(
                              builder: (_) => ForumTopicsScreen(
                                chatId: widget.chatId,
                                chatName: _nameController.text.trim().isNotEmpty
                                    ? _nameController.text.trim()
                                    : widget.initialName,
                                chatAvatar: _avatarUrl,
                                myRole: _myRole,
                                myAdminPermissions: _myAdminPermissions,
                                defaultPermissions: _defaultPermissions,
                              ),
                            ),
                          );
                        },
                      ),
                    TheavListRow(
                      leading: iconoir.Lock(
                        width: 20,
                        height: 20,
                        color: palette.primary,
                      ),
                      title: 'Разрешения',
                      valueText:
                          '${_enabledPermissionsCount(_defaultPermissions)}/${_isForum ? 14 : 13}${slowBadge.isNotEmpty ? ' • $slowBadge' : ''}',
                      showChevron: true,
                      onTap: _openGroupPermissions,
                    ),
                    TheavListRow(
                      leading: iconoir.Clock(
                        width: 20,
                        height: 20,
                        color: palette.primary,
                      ),
                      title: 'История чата для новых участников',
                      valueText: _historyForNew ? 'Видна' : 'Скрыта',
                      showChevron: true,
                      onTap: _showHistoryVisibilitySheet,
                    ),
                  ],
                  TheavListRow(
                    leading: iconoir.Heart(
                      width: 20,
                      height: 20,
                      color: palette.primary,
                    ),
                    title: 'Реакции',
                    valueText: _reactionSummary(),
                    showChevron: true,
                    onTap: _openReactionsSettings,
                  ),
                  TheavListRow(
                    leading: iconoir.Link(
                      width: 20,
                      height: 20,
                      color: palette.primary,
                    ),
                    title: 'Пригласительные ссылки',
                    valueText: (_inviteLink ?? '').isNotEmpty ? 'Активна' : '',
                    showChevron: true,
                    onTap: _openInviteLinks,
                  ),
                  TheavListRow(
                    leading: iconoir.ShieldCheck(
                      width: 20,
                      height: 20,
                      color: palette.primary,
                    ),
                    title: 'Администраторы',
                    valueText: '$_adminsCount',
                    showChevron: true,
                    onTap: _openAdminsSheet,
                  ),
                  TheavListRow(
                    leading: iconoir.PageSearch(
                      width: 20,
                      height: 20,
                      color: palette.primary,
                    ),
                    title: 'Недавние действия',
                    showChevron: true,
                    onTap: () {
                      HapticUtils.tap();
                      Navigator.push(
                        context,
                        SwipeBackPageRoute(
                          builder: (_) => AdminLogScreen(
                            chatId: widget.chatId,
                            chatName: _nameController.text.trim().isNotEmpty
                                ? _nameController.text.trim()
                                : widget.initialName,
                            isChannel: widget.isChannel,
                          ),
                        ),
                      );
                    },
                  ),
                  if (widget.isChannel)
                    TheavListRow(
                      leading: iconoir.StatsUpSquare(
                        width: 20,
                        height: 20,
                        color: palette.primary,
                      ),
                      title: 'Статистика',
                      showChevron: true,
                      onTap: () {
                        HapticUtils.tap();
                        Navigator.push(
                          context,
                          SwipeBackPageRoute(
                            builder: (_) => ChannelStatsScreen(
                              chatId: widget.chatId,
                              channelName: _nameController.text.trim().isNotEmpty
                                  ? _nameController.text.trim()
                                  : widget.initialName,
                            ),
                          ),
                        );
                      },
                    ),
                  if (_myRole == 'owner')
                    TheavListRow(
                      leading: iconoir.Crown(
                        width: 20,
                        height: 20,
                        color: palette.primary,
                      ),
                      title: 'Передать права владельца',
                      showChevron: true,
                      onTap: _openTransferOwnershipFlow,
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
      ),
    );
  }
}
