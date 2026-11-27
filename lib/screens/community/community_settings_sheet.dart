import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../l10n/app_localizations.dart';
import '../../models/avatar_editor_models.dart';
import '../../models/call_models.dart';
import '../../models/community_models.dart';
import '../../services/auth_service.dart';
import '../../services/community_service.dart';
import '../../services/contacts_service.dart';
import '../../services/file_service.dart';
import '../../services/glass_toast_service.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/avatar_editor/theav_avatar_picker_sheet.dart';
import '../../widgets/common/peer_badges_widget.dart';
import '../../widgets/community/community_channel_icon.dart';
import '../../widgets/community/community_overwrites_sheet.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/user/avatar_with_status.dart';
import '../../widgets/user/emoji_status_badge.dart';

/// Community administration sheet in dual-mode Telegram UI (`showTheavModalSheet`,
/// `TheavInsetGroup`, `TheavSwitch`, `showTheavDialog`) supporting Overview,
/// Invites, Categories & Channels (reorder + permission overwrites), Roles (19
/// bitmask flags + color + hoist/mentionable), Members/Bans, and Soundboard.
class CommunitySettingsSheet extends StatefulWidget {
  final Community community;
  final ValueChanged<Community> onCommunityUpdated;
  final int initialTab;
  final bool autoFetch;
  final List<CommunityMember>? initialMembers;
  final List<CommunityBan>? initialBans;
  final List<CommunityInvite>? initialInvites;
  final List<SoundboardItem>? initialSounds;

  const CommunitySettingsSheet({
    super.key,
    required this.community,
    required this.onCommunityUpdated,
    this.initialTab = 0,
    this.autoFetch = true,
    this.initialMembers,
    this.initialBans,
    this.initialInvites,
    this.initialSounds,
  });

  static Future<void> show(
    BuildContext context, {
    required Community community,
    required ValueChanged<Community> onCommunityUpdated,
    int initialTab = 0,
  }) {
    return showTheavModalSheet<void>(
      context: context,
      title: 'Управление сообществом',
      showCloseButton: true,
      maxHeightFactor: 0.92,
      padding: EdgeInsets.zero,
      builder: (_) => CommunitySettingsSheet(
        community: community,
        onCommunityUpdated: onCommunityUpdated,
        initialTab: initialTab,
      ),
    );
  }

  @override
  State<CommunitySettingsSheet> createState() => _CommunitySettingsSheetState();
}

class _CommunitySettingsSheetState extends State<CommunitySettingsSheet> {
  static const List<String> _kTabTitles = [
    'Обзор',
    'Каналы',
    'Роли',
    'Участники',
    'Звуки',
  ];

  static const List<String> _kRoleColors = [
    '#3B82F6',
    '#10B981',
    '#F59E0B',
    '#EF4444',
    '#8B5CF6',
    '#EC4899',
    '#06B6D4',
    '#99AAB5',
  ];

  static const List<({String header, List<int> bits})> _kPermissionGroups = [
    (
      header: 'ОБЩИЕ ПРАВА',
      bits: [
        CommunityPermissions.administrator,
        CommunityPermissions.viewChannel,
        CommunityPermissions.manageCommunity,
        CommunityPermissions.manageChannels,
        CommunityPermissions.manageRoles,
      ],
    ),
    (
      header: 'ТЕКСТОВЫЕ КАНАЛЫ',
      bits: [
        CommunityPermissions.sendMessages,
      ],
    ),
    (
      header: 'ГОЛОС, ТРИБУНА И СТРИМЫ',
      bits: [
        CommunityPermissions.connectVoice,
        CommunityPermissions.speakVoice,
        CommunityPermissions.video,
        CommunityPermissions.streamVideo,
        CommunityPermissions.screenShareHd,
        CommunityPermissions.prioritySpeaker,
        CommunityPermissions.useSoundboard,
        CommunityPermissions.manageStage,
      ],
    ),
    (
      header: 'МОДЕРАЦИЯ',
      bits: [
        CommunityPermissions.muteMembers,
        CommunityPermissions.deafenMembers,
        CommunityPermissions.moveMembers,
        CommunityPermissions.kickMembers,
        CommunityPermissions.banMembers,
      ],
    ),
  ];

  late int _activeTab;
  late Community _community;
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  late TextEditingController _roleNameCtrl;
  final TextEditingController _memberSearchCtrl = TextEditingController();

  late bool _isPublic;
  String? _avatarUrlOverride;
  bool _savingOverview = false;
  bool _uploadingAvatar = false;
  String? _currentUserId;

  CommunityRole? _selectedRole;
  List<CommunityMember> _members = const [];
  List<CommunityBan> _bans = const [];
  List<CommunityInvite> _invites = const [];
  List<SoundboardItem> _sounds = const [];
  int _membersSegment = 0; // 0: members, 1: bans
  String _memberQuery = '';
  bool _loadingMembers = false;
  bool _loadingBans = false;
  bool _loadingInvites = false;
  bool _loadingSounds = false;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab.clamp(0, _kTabTitles.length - 1);
    _community = widget.community;
    _nameCtrl = TextEditingController(text: _community.name);
    _descCtrl = TextEditingController(text: _community.description);
    _isPublic = _community.isPublic;
    if (_community.roles.isNotEmpty) {
      _selectedRole = _community.roles.first;
    }
    _roleNameCtrl = TextEditingController(text: _selectedRole?.name ?? '');

    if (widget.initialMembers != null) _members = widget.initialMembers!;
    if (widget.initialBans != null) _bans = widget.initialBans!;
    if (widget.initialInvites != null) _invites = widget.initialInvites!;
    if (widget.initialSounds != null) _sounds = widget.initialSounds!;

    ContactsService.revisionNotifier.addListener(_onContactsRevisionChanged);

    if (widget.autoFetch) {
      _loadInitialData();
    }
  }

  void _onContactsRevisionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadInitialData() async {
    _currentUserId = await AuthService.getUserId();
    await Future.wait([
      _loadRolesAndMembers(),
      _loadInvites(),
      _loadBans(),
      _loadSounds(),
    ]);
  }

  Future<void> _loadRolesAndMembers() async {
    if (!mounted) return;
    setState(() => _loadingMembers = true);
    final roles = await CommunityService.getRoles(_community.id);
    final members = await CommunityService.getMembers(_community.id);
    if (!mounted) return;
    setState(() {
      _loadingMembers = false;
      if (roles.isNotEmpty) {
        _community = _community.copyWith(roles: roles);
        _selectRole(
          roles.firstWhere(
            (r) => r.id == _selectedRole?.id,
            orElse: () => roles.first,
          ),
        );
      }
      if (members.isNotEmpty) {
        _members = members;
      }
    });
    widget.onCommunityUpdated(_community);
  }

  Future<void> _loadInvites() async {
    if (!mounted) return;
    setState(() => _loadingInvites = true);
    final list = await CommunityService.listInvites(_community.id);
    if (!mounted) return;
    setState(() {
      _loadingInvites = false;
      _invites = list;
    });
  }

  Future<void> _loadBans() async {
    if (!mounted) return;
    setState(() => _loadingBans = true);
    final list = await CommunityService.getBans(_community.id);
    if (!mounted) return;
    setState(() {
      _loadingBans = false;
      _bans = list;
    });
  }

  Future<void> _loadSounds() async {
    if (!mounted) return;
    setState(() => _loadingSounds = true);
    final list = await CommunityService.getSoundboardSounds(_community.id);
    if (!mounted) return;
    setState(() {
      _loadingSounds = false;
      _sounds = list;
    });
  }

  void _selectRole(CommunityRole? role) {
    _selectedRole = role;
    _roleNameCtrl.text = role?.name ?? '';
  }

  @override
  void dispose() {
    ContactsService.revisionNotifier.removeListener(_onContactsRevisionChanged);
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _roleNameCtrl.dispose();
    _memberSearchCtrl.dispose();
    super.dispose();
  }

  String _resolveMemberName(
    CommunityMember m, {
    String emptyFallback = '',
  }) {
    final resolved = ContactsService.resolvePeerName(
      m.userId,
      m.effectiveDisplayName,
      isBot: m.isBot,
    ).trim();
    if (resolved.isNotEmpty) return resolved;
    if (m.username.trim().isNotEmpty) return m.username.trim();
    return emptyFallback;
  }

  String? _resolveMemberAvatar(CommunityMember m) {
    return ContactsService.resolvePeerAvatarUrl(
      m.userId,
      m.avatarUrl,
      isBot: m.isBot,
    );
  }

  String _resolveBanName(CommunityBan b) {
    final fallback = b.displayName.trim().isNotEmpty
        ? b.displayName.trim()
        : (b.username.trim().isNotEmpty ? '@${b.username.trim()}' : '');
    final resolved = ContactsService.resolvePeerName(
      b.userId,
      fallback,
    ).trim();
    if (resolved.isNotEmpty) return resolved;
    if (b.username.trim().isNotEmpty) return b.username.trim();
    return 'Пользователь';
  }

  String? _resolveBanAvatar(CommunityBan b) {
    return ContactsService.resolvePeerAvatarUrl(
      b.userId,
      b.avatarUrl,
    );
  }

  String _tr(BuildContext context, String key, String fallback) {
    final l10n = Localizations.of<AppLocalizations>(context, AppLocalizations);
    if (l10n != null) {
      final v = l10n.translate(key);
      if (v != key && v.isNotEmpty) return v;
    }
    return fallback;
  }

  // ---------------------------------------------------------------------------
  // Overview & Invites actions
  // ---------------------------------------------------------------------------

  Community _communityWithClearedAvatar(Community source) {
    return Community(
      id: source.id,
      name: source.name,
      description: source.description,
      avatarUrl: null,
      bannerUrl: source.bannerUrl,
      ownerId: source.ownerId,
      memberCount: source.memberCount,
      onlineCount: source.onlineCount,
      isMember: source.isMember,
      isPublic: source.isPublic,
      myPermissions: source.myPermissions,
      categories: source.categories,
      channels: source.channels,
      roles: source.roles,
      createdAt: source.createdAt,
    );
  }

  Future<void> _deleteCommunityAvatar() async {
    if (_uploadingAvatar) return;
    setState(() => _uploadingAvatar = true);
    try {
      final ok = await CommunityService.deleteCommunityAvatar(_community.id);
      if (!mounted) return;
      if (!ok) {
        GlassToastService().showError(
          context,
          _tr(context, 'common_error', 'Не удалось удалить фото'),
        );
        return;
      }
      setState(() {
        _avatarUrlOverride = null;
        _community = _communityWithClearedAvatar(_community);
      });
      widget.onCommunityUpdated(_community);
      GlassToastService().show(context, 'Фото сообщества удалено');
    } catch (_) {
      if (mounted) {
        GlassToastService().showError(
          context,
          _tr(context, 'common_error', 'Не удалось удалить фото'),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _confirmAndDeleteCommunityAvatar() async {
    if (_uploadingAvatar) return;
    HapticUtils.heavy();
    final confirmed = await showTheavDialog<bool>(
      context: context,
      title: _tr(context, 'avatar_delete_photo', 'Удалить фото'),
      message: _tr(
        context,
        'avatar_delete_confirm_community',
        'Удалить текущее фото сообщества?',
      ),
      actions: [
        TheavDialogAction<bool>(
          label: _tr(context, 'profile_cancel', 'Отмена'),
          result: false,
        ),
        TheavDialogAction<bool>(
          label: _tr(context, 'avatar_delete_photo', 'Удалить фото'),
          result: true,
          isDestructive: true,
        ),
      ],
    );
    if (confirmed == true && mounted) {
      await _deleteCommunityAvatar();
    }
  }

  Future<void> _pickAndUploadAvatar() async {
    if (_uploadingAvatar) return;
    HapticUtils.tap();
    final currentAvatar = _avatarUrlOverride ?? _community.avatarUrl;
    final hasCurrentAvatar =
        currentAvatar != null && currentAvatar.isNotEmpty;

    final picked = await TheavAvatarPickerSheet.pickAndEdit(
      context: context,
      maskShape: AvatarShapeMask.squircle,
      ctaMode: AvatarEditorCtaMode.setPhoto,
      subjectName: _community.name,
      canDeleteCurrent: hasCurrentAvatar,
    );
    if (picked == null || !mounted) return;

    if (picked.deletedCurrent) {
      await _deleteCommunityAvatar();
      return;
    }

    if (!picked.hasMedia) return;

    setState(() => _uploadingAvatar = true);
    try {
      final uploadFile = picked.file ??
          File(picked.fileName.isNotEmpty ? picked.fileName : 'avatar.jpg');
      final updated = await CommunityService.uploadCommunityAvatar(
        _community.id,
        uploadFile,
        bytes: picked.bytes,
        fileName: picked.fileName,
        avatarCrop: picked.miniCrop?.toCompactParam(),
      );
      if (!mounted) return;
      if (updated == null) {
        GlassToastService().showError(context, 'Не удалось загрузить фото');
        return;
      }
      setState(() {
        _avatarUrlOverride = null;
        _community = updated;
      });
      widget.onCommunityUpdated(_community);
      GlassToastService().show(context, 'Аватар сообщества обновлён');
    } catch (_) {
      if (mounted) {
        GlassToastService().showError(context, 'Не удалось загрузить фото');
      }
    } finally {
      if (mounted) setState(() => _uploadingAvatar = false);
    }
  }

  Future<void> _saveOverview() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) {
      GlassToastService().showError(context, 'Введите название сообщества');
      return;
    }
    setState(() => _savingOverview = true);
    final updated = await CommunityService.updateCommunity(
      _community.id,
      name: name,
      description: _descCtrl.text.trim(),
      avatarUrl: _avatarUrlOverride,
      isPublic: _isPublic,
    );
    if (!mounted) return;
    setState(() => _savingOverview = false);
    if (updated == null) {
      GlassToastService().showError(
        context,
        _tr(context, 'common_error', 'Ошибка сохранения'),
      );
      return;
    }
    setState(() => _community = updated);
    widget.onCommunityUpdated(_community);
    GlassToastService().show(
      context,
      _tr(context, 'settings_saved', 'Настройки сохранены'),
    );
  }

  Future<void> _generateInvite() async {
    final code = await CommunityService.createInviteCode(_community.id);
    if (!mounted) return;
    if (code == null || code.isEmpty) {
      GlassToastService().showError(
        context,
        'Не удалось создать код приглашения (проверьте права)',
      );
      return;
    }
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    GlassToastService().show(context, 'Код приглашения скопирован: $code');
    if (widget.autoFetch) {
      _loadInvites();
    }
  }

  Future<void> _revokeInvite(CommunityInvite invite) async {
    final ok = await CommunityService.deleteInvite(_community.id, invite.id);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _invites = _invites.where((i) => i.id != invite.id).toList();
      });
      GlassToastService().show(context, 'Приглашение отозвано');
    } else {
      GlassToastService().showError(context, 'Не удалось отозвать инвайт');
    }
  }

  Future<void> _confirmDeleteCommunity() async {
    final confirmed = await showTheavDialog<bool>(
      context: context,
      title: 'Удалить сообщество?',
      message:
          'Сообщество «${_community.name}» и все его каналы будут безвозвратно удалены.',
      actions: const [
        TheavDialogAction<bool>(label: 'Отмена', result: false),
        TheavDialogAction<bool>(
          label: 'Удалить',
          result: true,
          isDestructive: true,
        ),
      ],
    );
    if (confirmed != true) return;
    final ok = await CommunityService.deleteCommunity(_community.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      Navigator.of(context).maybePop();
    } else {
      GlassToastService().showError(
        context,
        'Не удалось удалить сообщество (только владелец)',
      );
    }
  }

  // ---------------------------------------------------------------------------
  // Channels & Categories actions
  // ---------------------------------------------------------------------------

  Future<void> _promptCreateCategory() async {
    final ctrl = TextEditingController();
    final name = await showTheavDialog<String>(
      context: context,
      title: 'Новая категория',
      content: TheavInsetGroup(
        margin: EdgeInsets.zero,
        children: [
          TheavInlineTextField(
            controller: ctrl,
            autofocus: true,
            placeholder: 'Например: ГОЛОСОВЫЕ КОМНАТЫ',
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
        ],
      ),
      customActions: [
        Builder(
          builder: (ctx) => Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Отмена'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
                child: const Text('Создать'),
              ),
            ],
          ),
        ),
      ],
    );
    if (name == null || name.isEmpty) return;

    final created = await CommunityService.createCategory(
      _community.id,
      name: name,
      position: _community.categories.length,
    );
    if (!mounted) return;
    if (created == null) {
      GlassToastService().showError(
        context,
        'Не удалось создать категорию (проверьте права доступа)',
      );
      return;
    }

    final fresh = await CommunityService.getCommunity(_community.id);
    if (!mounted) return;
    setState(() {
      _community = fresh ??
          _community.copyWith(
            categories: [..._community.categories, created],
          );
    });
    widget.onCommunityUpdated(_community);
  }

  Future<void> _editCategory(CommunityCategory cat) async {
    final ctrl = TextEditingController(text: cat.name);
    bool isPrivate = cat.isPrivate;

    final saved = await showTheavModalSheet<bool>(
      context: context,
      title: 'Категория',
      showCloseButton: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TheavInsetGroup(
                margin: EdgeInsets.zero,
                children: [
                  TheavInlineTextField(
                    controller: ctrl,
                    label: 'Название',
                    placeholder: 'Название категории',
                  ),
                  TheavListRow(
                    title: 'Приватная категория',
                    subtitle: 'Скрыть каналы от @everyone по умолчанию',
                    trailing: TheavSwitch(
                      value: isPrivate,
                      onChanged: (v) => setSheet(() => isPrivate = v),
                    ),
                    onTap: () => setSheet(() => isPrivate = !isPrivate),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: TheavFloatingPillButton(
                  label: 'Сохранить',
                  isPrimary: true,
                  onTap: () => Navigator.of(ctx).pop(true),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (saved != true || !mounted) return;
    final newName = ctrl.text.trim();
    if (newName.isEmpty) return;
    final ok = await CommunityService.updateCategory(
      _community.id,
      cat.id,
      name: newName,
      isPrivate: isPrivate,
    );
    if (!mounted) return;
    if (ok) {
      setState(() {
        _community = _community.copyWith(
          categories: _community.categories
              .map(
                (c) => c.id == cat.id
                    ? c.copyWith(name: newName, isPrivate: isPrivate)
                    : c,
              )
              .toList(),
        );
      });
      widget.onCommunityUpdated(_community);
    }
  }

  Future<void> _promptCreateChannel() async {
    final nameCtrl = TextEditingController();
    final topicCtrl = TextEditingController();
    String selectedType = 'text';
    String? selectedCategoryId = _community.categories.isNotEmpty
        ? _community.categories.first.id
        : null;

    const types = [
      (id: 'text', label: 'Текстовый (#)'),
      (id: 'announcement', label: 'Объявления'),
      (id: 'forum', label: 'Форум (ветки)'),
      (id: 'voice', label: 'Голосовой (144 FPS)'),
      (id: 'stage', label: 'Трибуна (Stage)'),
      (id: 'whiteboard', label: 'Доска (Miro)'),
    ];

    final createdRequested = await showTheavModalSheet<bool>(
      context: context,
      title: 'Создать канал',
      showCloseButton: true,
      maxHeightFactor: 0.9,
      padding: EdgeInsets.zero,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(0, 6, 0, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TheavInsetGroup(
                  header: 'ПАРАМЕТРЫ',
                  children: [
                    TheavInlineTextField(
                      controller: nameCtrl,
                      autofocus: true,
                      label: 'Название',
                      placeholder: 'general / gaming-144fps',
                    ),
                    TheavInlineTextField(
                      controller: topicCtrl,
                      label: 'Тема (необязательно)',
                      placeholder: 'О чём этот канал',
                    ),
                  ],
                ),
                TheavInsetGroup(
                  header: 'ТИП КАНАЛА',
                  children: types.map((t) {
                    final selected = t.id == selectedType;
                    return TheavListRow(
                      minHeight: 46,
                      leading: CommunityChannelIcon(
                        channelType: t.id,
                        size: 19,
                        isSelected: selected,
                      ),
                      title: t.label,
                      trailing: TheavCheckCircle(selected: selected),
                      onTap: () => setSheet(() => selectedType = t.id),
                    );
                  }).toList(),
                ),
                if (_community.categories.isNotEmpty)
                  TheavInsetGroup(
                    header: 'КАТЕГОРИЯ',
                    children: [
                      TheavListRow(
                        title: 'Без категории',
                        trailing: TheavCheckCircle(
                          selected: selectedCategoryId == null,
                        ),
                        onTap: () =>
                            setSheet(() => selectedCategoryId = null),
                      ),
                      ..._community.categories.map(
                        (cat) => TheavListRow(
                          leading: const iconoir.Folder(width: 18, height: 18),
                          title: cat.name,
                          trailing: TheavCheckCircle(
                            selected: selectedCategoryId == cat.id,
                          ),
                          onTap: () =>
                              setSheet(() => selectedCategoryId = cat.id),
                        ),
                      ),
                    ],
                  ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: TheavFloatingPillButton(
                      label: 'Создать канал',
                      icon: const iconoir.Plus(width: 18, height: 18),
                      isPrimary: true,
                      onTap: () => Navigator.of(ctx).pop(true),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (createdRequested != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;

    final created = await CommunityService.createChannel(
      _community.id,
      name: name,
      channelType: selectedType,
      categoryId: selectedCategoryId,
      topic: topicCtrl.text.trim(),
    );
    if (!mounted) return;
    if (created == null) {
      GlassToastService().showError(
        context,
        'Не удалось создать канал (проверьте права доступа)',
      );
      return;
    }

    final fresh = await CommunityService.getCommunity(_community.id);
    if (!mounted) return;
    setState(() {
      _community = fresh ??
          _community.copyWith(
            channels: [..._community.channels, created],
          );
    });
    widget.onCommunityUpdated(_community);
  }

  Future<void> _editChannel(CommunityChannel ch) async {
    final nameCtrl = TextEditingController(text: ch.name);
    final topicCtrl = TextEditingController(text: ch.topic);
    String? selectedCatId = ch.categoryId;
    int slowMode = ch.slowModeSeconds;
    const slowModeOptions = [0, 5, 15, 60, 300];

    final saved = await showTheavModalSheet<bool>(
      context: context,
      title: '# ${ch.name}',
      showCloseButton: true,
      maxHeightFactor: 0.88,
      padding: EdgeInsets.zero,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TheavInsetGroup(
                  header: 'ОСНОВНОЕ',
                  children: [
                    TheavInlineTextField(
                      controller: nameCtrl,
                      label: 'Название канала',
                      placeholder: 'Название',
                    ),
                    TheavInlineTextField(
                      controller: topicCtrl,
                      label: 'Тема / описание',
                      placeholder: 'Описание канала',
                      maxLines: 3,
                    ),
                  ],
                ),
                if (!ch.isAudioRoom && !ch.isWhiteboard)
                  TheavInsetGroup(
                    header: 'МЕДЛЕННЫЙ РЕЖИМ',
                    children: [
                      Padding(
                        padding: const EdgeInsets.all(12),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: slowModeOptions.map((sec) {
                            final active = slowMode == sec;
                            final label = sec == 0
                                ? 'Выкл'
                                : (sec >= 60 ? '${sec ~/ 60}м' : '$secс');
                            return GestureDetector(
                              onTap: () => setSheet(() => slowMode = sec),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 140),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: active
                                      ? context.theav.primary
                                      : context.theav.onSurface
                                          .withValues(alpha: 0.06),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  label,
                                  style: TextStyle(
                                    color: active
                                        ? Colors.white
                                        : context.theav.onSurface,
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                if (_community.categories.isNotEmpty)
                  TheavInsetGroup(
                    header: 'КАТЕГОРИЯ',
                    children: [
                      TheavListRow(
                        title: 'Без категории',
                        trailing: TheavCheckCircle(
                          selected: selectedCatId == null,
                        ),
                        onTap: () => setSheet(() => selectedCatId = null),
                      ),
                      ..._community.categories.map(
                        (cat) => TheavListRow(
                          title: cat.name,
                          trailing: TheavCheckCircle(
                            selected: selectedCatId == cat.id,
                          ),
                          onTap: () => setSheet(() => selectedCatId = cat.id),
                        ),
                      ),
                    ],
                  ),
                TheavInsetGroup(
                  header: 'ДОСТУП',
                  children: [
                    TheavListRow(
                      leading: const iconoir.ShieldCheck(width: 20, height: 20),
                      title: 'Переопределения прав ролей',
                      subtitle: 'Настроить видимость и права доступа в канале',
                      showChevron: true,
                      onTap: () => showCommunityOverwritesSheet(
                        ctx,
                        community: _community,
                        chatId: ch.id,
                        targetName: ch.name,
                      ),
                    ),
                  ],
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: SizedBox(
                    width: double.infinity,
                    child: TheavFloatingPillButton(
                      label: 'Сохранить',
                      isPrimary: true,
                      onTap: () => Navigator.of(ctx).pop(true),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    if (saved != true || !mounted) return;
    final newName = nameCtrl.text.trim();
    if (newName.isEmpty) return;

    final updated = await CommunityService.updateChannel(
      _community.id,
      ch.id,
      name: newName,
      topic: topicCtrl.text.trim(),
      categoryId: selectedCatId,
      clearCategory: selectedCatId == null && ch.categoryId != null,
      slowModeSeconds: slowMode,
    );
    if (!mounted) return;
    if (updated != null) {
      setState(() {
        _community = _community.copyWith(
          channels: _community.channels
              .map((c) => c.id == ch.id ? updated : c)
              .toList(),
        );
      });
      widget.onCommunityUpdated(_community);
      GlassToastService().show(context, 'Канал обновлён');
    } else {
      GlassToastService().showError(context, 'Не удалось обновить канал');
    }
  }

  Future<void> _moveChannel(int index, int delta) async {
    final targetIdx = index + delta;
    if (targetIdx < 0 || targetIdx >= _community.channels.length) return;
    HapticUtils.selection();
    final reordered = List<CommunityChannel>.from(_community.channels);
    final moved = reordered.removeAt(index);
    reordered.insert(targetIdx, moved);
    final updated = [
      for (int i = 0; i < reordered.length; i++)
        reordered[i].copyWith(position: i),
    ];
    setState(() {
      _community = _community.copyWith(channels: updated);
    });
    widget.onCommunityUpdated(_community);
    await CommunityService.reorderChannels(
      _community.id,
      updated
          .map(
            (c) => (
              chatId: c.id,
              categoryId: c.categoryId,
              position: c.position,
            ),
          )
          .toList(),
    );
  }

  Future<void> _deleteChannel(CommunityChannel ch) async {
    final confirmed = await showTheavDialog<bool>(
      context: context,
      title: 'Удалить канал #${ch.name}?',
      message: 'История сообщений в этом канале будет удалена.',
      actions: const [
        TheavDialogAction<bool>(label: 'Отмена', result: false),
        TheavDialogAction<bool>(
          label: 'Удалить',
          result: true,
          isDestructive: true,
        ),
      ],
    );
    if (confirmed != true) return;
    final ok = await CommunityService.deleteChannel(_community.id, ch.id);
    if (!mounted || !ok) return;
    setState(() {
      _community = _community.copyWith(
        channels: _community.channels.where((c) => c.id != ch.id).toList(),
      );
    });
    widget.onCommunityUpdated(_community);
  }

  Future<void> _deleteCategory(CommunityCategory cat) async {
    final confirmed = await showTheavDialog<bool>(
      context: context,
      title: 'Удалить категорию «${cat.name}»?',
      message: 'Каналы внутри категории станут общими без категории.',
      actions: const [
        TheavDialogAction<bool>(label: 'Отмена', result: false),
        TheavDialogAction<bool>(
          label: 'Удалить',
          result: true,
          isDestructive: true,
        ),
      ],
    );
    if (confirmed != true) return;
    final ok = await CommunityService.deleteCategory(_community.id, cat.id);
    if (!mounted || !ok) return;
    final fresh = await CommunityService.getCommunity(_community.id);
    if (!mounted) return;
    setState(() {
      _community = fresh ??
          _community.copyWith(
            categories:
                _community.categories.where((c) => c.id != cat.id).toList(),
          );
    });
    widget.onCommunityUpdated(_community);
  }

  // ---------------------------------------------------------------------------
  // Roles actions
  // ---------------------------------------------------------------------------

  Future<void> _updateSelectedRoleField({
    String? name,
    String? colorHex,
    bool? isHoisted,
    bool? isMentionable,
    int? permissions,
  }) async {
    final role = _selectedRole;
    if (role == null) return;
    HapticUtils.selection();
    final updatedRole = role.copyWith(
      name: name,
      colorHex: colorHex,
      isHoisted: isHoisted,
      isMentionable: isMentionable,
      permissions: permissions,
    );
    setState(() {
      _selectRole(updatedRole);
      _community = _community.copyWith(
        roles: _community.roles
            .map((r) => r.id == updatedRole.id ? updatedRole : r)
            .toList(),
      );
    });
    widget.onCommunityUpdated(_community);
    await CommunityService.updateRole(
      _community.id,
      role.id,
      name: name,
      colorHex: colorHex,
      isHoisted: isHoisted,
      isMentionable: isMentionable,
      permissions: permissions,
    );
  }

  Future<void> _toggleRolePermission(int bit) async {
    final role = _selectedRole;
    if (role == null || role.id == 'default_member') return;
    final hasBit = (role.permissions & bit) != 0;
    final newPerms =
        hasBit ? (role.permissions & ~bit) : (role.permissions | bit);
    await _updateSelectedRoleField(permissions: newPerms);
  }

  Future<void> _promptCreateRole() async {
    final ctrl = TextEditingController();
    final name = await showTheavDialog<String>(
      context: context,
      title: 'Новая роль',
      content: TheavInsetGroup(
        margin: EdgeInsets.zero,
        children: [
          TheavInlineTextField(
            controller: ctrl,
            autofocus: true,
            placeholder: 'Например: Модератор',
            onSubmitted: (v) => Navigator.of(context).pop(v.trim()),
          ),
        ],
      ),
      customActions: [
        Builder(
          builder: (ctx) => Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(),
                child: const Text('Отмена'),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
                child: const Text('Создать'),
              ),
            ],
          ),
        ),
      ],
    );
    if (name == null || name.isEmpty) return;
    final created = await CommunityService.createRole(
      _community.id,
      name: name,
      permissions: CommunityPermissions.viewChannel |
          CommunityPermissions.sendMessages |
          CommunityPermissions.connectVoice |
          CommunityPermissions.speakVoice,
    );
    if (!mounted || created == null) return;
    setState(() {
      _community = _community.copyWith(roles: [..._community.roles, created]);
      _selectRole(created);
    });
    widget.onCommunityUpdated(_community);
  }

  Future<void> _deleteSelectedRole() async {
    final role = _selectedRole;
    if (role == null || role.isEveryone) return;
    final confirmed = await showTheavDialog<bool>(
      context: context,
      title: 'Удалить роль «${role.name}»?',
      message: 'Участники с этой ролью потеряют её права.',
      actions: const [
        TheavDialogAction<bool>(label: 'Отмена', result: false),
        TheavDialogAction<bool>(
          label: 'Удалить',
          result: true,
          isDestructive: true,
        ),
      ],
    );
    if (confirmed != true) return;
    final ok = await CommunityService.deleteRole(_community.id, role.id);
    if (!mounted || !ok) return;
    final remaining = _community.roles.where((r) => r.id != role.id).toList();
    setState(() {
      _community = _community.copyWith(roles: remaining);
      _selectRole(remaining.isNotEmpty ? remaining.first : null);
    });
    widget.onCommunityUpdated(_community);
  }

  // ---------------------------------------------------------------------------
  // Members & Bans actions
  // ---------------------------------------------------------------------------

  Future<void> _showMemberActions(CommunityMember member) async {
    final assignableRoles =
        _community.roles.where((r) => !r.isEveryone).toList();
    final selectedRoleIds = Set<String>.from(member.roleIds);
    final memberName = _resolveMemberName(member, emptyFallback: 'Пользователь');

    await showTheavModalSheet<void>(
      context: context,
      title: memberName,
      showCloseButton: true,
      padding: EdgeInsets.zero,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (assignableRoles.isNotEmpty)
                  TheavInsetGroup(
                    header: 'РОЛИ УЧАСТНИКА',
                    children: assignableRoles.map((role) {
                      final hasRole = selectedRoleIds.contains(role.id);
                      final roleColor =
                          role.parsedColor ?? context.theav.primary;
                      return TheavListRow(
                        leading: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: roleColor,
                            shape: BoxShape.circle,
                          ),
                        ),
                        title: role.name,
                        trailing: TheavCheckCircle(selected: hasRole),
                        onTap: () async {
                          setSheet(() {
                            if (hasRole) {
                              selectedRoleIds.remove(role.id);
                            } else {
                              selectedRoleIds.add(role.id);
                            }
                          });
                          await CommunityService.setMemberRoles(
                            _community.id,
                            member.userId,
                            selectedRoleIds.toList(),
                          );
                          if (widget.autoFetch) {
                            _loadRolesAndMembers();
                          }
                        },
                      );
                    }).toList(),
                  ),
                TheavInsetGroup(
                  header: 'МОДЕРАЦИЯ',
                  children: [
                    TheavListRow(
                      leading: const iconoir.UserXmark(width: 20, height: 20),
                      title: 'Исключить (Kick)',
                      subtitle: 'Удалить участника с возможностью вернуться',
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        final ok = await CommunityService.kickMember(
                          _community.id,
                          member.userId,
                        );
                        if (ok && mounted && widget.autoFetch) {
                          final latestName = _resolveMemberName(
                            member,
                            emptyFallback: memberName,
                          );
                          GlassToastService().show(
                            context,
                            '$latestName исключён',
                          );
                          _loadRolesAndMembers();
                        }
                      },
                    ),
                    TheavListRow(
                      leading: const iconoir.Prohibition(width: 20, height: 20),
                      title: 'Заблокировать (Ban)',
                      isDestructive: true,
                      onTap: () async {
                        Navigator.of(ctx).pop();
                        await _promptBanMember(member);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _promptBanMember(CommunityMember member) async {
    final reasonCtrl = TextEditingController();
    final name = _resolveMemberName(member, emptyFallback: 'Пользователь');
    final confirmed = await showTheavDialog<bool>(
      context: context,
      title: 'Заблокировать $name?',
      content: TheavInsetGroup(
        margin: EdgeInsets.zero,
        children: [
          TheavInlineTextField(
            controller: reasonCtrl,
            placeholder: 'Причина блокировки (необязательно)',
          ),
        ],
      ),
      actions: const [
        TheavDialogAction<bool>(label: 'Отмена', result: false),
        TheavDialogAction<bool>(
          label: 'Заблокировать',
          result: true,
          isDestructive: true,
        ),
      ],
    );
    if (confirmed != true) return;
    final ok = await CommunityService.banMember(
      _community.id,
      member.userId,
      reason: reasonCtrl.text.trim(),
    );
    if (!mounted) return;
    if (ok) {
      final latestName = _resolveMemberName(member, emptyFallback: name);
      GlassToastService().show(context, '$latestName заблокирован');
      if (widget.autoFetch) {
        _loadRolesAndMembers();
        _loadBans();
      }
    } else {
      GlassToastService().showError(context, 'Не удалось заблокировать');
    }
  }

  Future<void> _unbanMember(CommunityBan ban) async {
    final ok = await CommunityService.unbanMember(_community.id, ban.userId);
    if (!mounted) return;
    if (ok) {
      setState(() {
        _bans = _bans.where((b) => b.userId != ban.userId).toList();
      });
      GlassToastService().show(context, 'Блокировка снята');
    } else {
      GlassToastService().showError(context, 'Не удалось снять блокировку');
    }
  }

  // ---------------------------------------------------------------------------
  // Soundboard actions
  // ---------------------------------------------------------------------------

  Future<void> _promptAddSound() async {
    final nameCtrl = TextEditingController();
    final urlCtrl = TextEditingController();
    String emoji = '🔊';
    bool uploading = false;
    const emojis = ['🔊', '📢', '🥁', '👏', '🎉', '🔔', '🔥', '🎺'];

    await showTheavModalSheet<void>(
      context: context,
      title: 'Добавить звук',
      showCloseButton: true,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheet) => SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TheavInsetGroup(
                margin: EdgeInsets.zero,
                children: [
                  TheavInlineTextField(
                    controller: nameCtrl,
                    label: 'Название клипа',
                    placeholder: 'Например: Победный горн',
                  ),
                  TheavInlineTextField(
                    controller: urlCtrl,
                    label: 'URL аудиофайла или загрузите файл',
                    placeholder: 'https://...',
                    suffix: uploading
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : GestureDetector(
                            onTap: () async {
                              final picked = await FilePicker.platform.pickFiles(
                                type: FileType.audio,
                              );
                              if (picked == null ||
                                  picked.files.single.path == null) {
                                return;
                              }
                              setSheet(() => uploading = true);
                              try {
                                final file = File(picked.files.single.path!);
                                final res = await FileService().uploadFile(file);
                                if (res.url.isNotEmpty) {
                                  urlCtrl.text = res.url;
                                  if (nameCtrl.text.trim().isEmpty) {
                                    nameCtrl.text = picked.files.single.name
                                        .split('.')
                                        .first;
                                  }
                                }
                              } finally {
                                if (ctx.mounted) {
                                  setSheet(() => uploading = false);
                                }
                              }
                            },
                            child: iconoir.CloudUpload(
                              width: 20,
                              height: 20,
                              color: context.theav.primary,
                            ),
                          ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                children: emojis.map((em) {
                  final active = emoji == em;
                  return GestureDetector(
                    onTap: () => setSheet(() => emoji = em),
                    child: Container(
                      width: 38,
                      height: 38,
                      decoration: BoxDecoration(
                        color: active
                            ? context.theav.primary.withValues(alpha: 0.18)
                            : context.theav.onSurface.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: active
                              ? context.theav.primary
                              : context.theav.divider,
                        ),
                      ),
                      alignment: Alignment.center,
                      child: Text(em, style: const TextStyle(fontSize: 18)),
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: TheavFloatingPillButton(
                  label: 'Сохранить клип',
                  isPrimary: true,
                  enabled: !uploading,
                  onTap: () async {
                    final clipName = nameCtrl.text.trim();
                    final clipUrl = urlCtrl.text.trim();
                    if (clipName.isEmpty || clipUrl.isEmpty) {
                      GlassToastService().showError(
                        ctx,
                        'Укажите название и аудиофайл',
                      );
                      return;
                    }
                    final created = await CommunityService.createSoundboardSound(
                      _community.id,
                      name: clipName,
                      fileUrl: clipUrl,
                      emoji: emoji,
                    );
                    if (!ctx.mounted || !mounted) return;
                    if (created != null) {
                      setState(() => _sounds = [..._sounds, created]);
                      Navigator.of(ctx).pop();
                      GlassToastService().show(context, 'Звук добавлен');
                    } else {
                      GlassToastService().showError(
                        ctx,
                        'Не удалось добавить звук',
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteSound(SoundboardItem item) async {
    final ok = await CommunityService.deleteSoundboardSound(
      _community.id,
      item.id,
    );
    if (!mounted) return;
    if (ok) {
      setState(() => _sounds = _sounds.where((s) => s.id != item.id).toList());
      GlassToastService().show(context, 'Звук удалён');
    } else {
      GlassToastService().showError(context, 'Не удалось удалить звук');
    }
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Dual-mode Pill Tab Strip
        SizedBox(
          height: 44,
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            scrollDirection: Axis.horizontal,
            itemCount: _kTabTitles.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (ctx, i) {
              final selected = i == _activeTab;
              return GestureDetector(
                onTap: () {
                  HapticUtils.selection();
                  setState(() => _activeTab = i);
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  decoration: BoxDecoration(
                    color: selected
                        ? palette.primary
                        : palette.onSurface.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: selected ? palette.primary : palette.divider,
                      width: 0.5,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: Text(
                    _kTabTitles[i],
                    style: TextStyle(
                      color: selected ? palette.onPrimary : palette.onSurface,
                      fontSize: 13.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 4),
        Flexible(
          child: _buildActiveTabBody(context, palette),
        ),
      ],
    );
  }

  Widget _buildActiveTabBody(BuildContext context, TheavPalette palette) {
    switch (_activeTab) {
      case 0:
        return _buildOverviewTab(context, palette);
      case 1:
        return _buildChannelsTab(context, palette);
      case 2:
        return _buildRolesTab(context, palette);
      case 3:
        return _buildMembersAndBansTab(context, palette);
      case 4:
        return _buildSoundboardTab(context, palette);
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildOverviewTab(BuildContext context, TheavPalette palette) {
    final bool isOwner =
        _currentUserId == null || _currentUserId == _community.ownerId;
    final String? effectiveAvatar = _avatarUrlOverride ?? _community.avatarUrl;
    final bool hasCurrentAvatar =
        effectiveAvatar != null && effectiveAvatar.isNotEmpty;

    return ListView(
      padding: const EdgeInsets.only(top: 6, bottom: 24),
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              GestureDetector(
                onTap: _uploadingAvatar ? null : _pickAndUploadAvatar,
                child: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    CommunityAvatar(
                      avatarUrl: effectiveAvatar,
                      name: _community.name,
                      size: 76,
                    ),
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          color: palette.primary,
                          shape: BoxShape.circle,
                          border: Border.all(color: palette.surface, width: 2),
                        ),
                        alignment: Alignment.center,
                        child: _uploadingAvatar
                            ? const SizedBox(
                                width: 13,
                                height: 13,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: Colors.white,
                                ),
                              )
                            : const iconoir.Camera(
                                width: 14,
                                height: 14,
                                color: Colors.white,
                              ),
                      ),
                    ),
                  ],
                ),
              ),
              if (hasCurrentAvatar && !_uploadingAvatar) ...[
                const SizedBox(height: 6),
                TextButton.icon(
                  onPressed: _confirmAndDeleteCommunityAvatar,
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                  ),
                  icon: iconoir.Trash(
                    width: 14,
                    height: 14,
                    color: palette.error,
                  ),
                  label: Text(
                    _tr(context, 'avatar_delete_photo', 'Удалить фото'),
                    style: TextStyle(
                      fontSize: 12.5,
                      fontWeight: FontWeight.w600,
                      color: palette.error,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        TheavInsetGroup(
          header: 'ОСНОВНОЕ',
          children: [
            TheavInlineTextField(
              controller: _nameCtrl,
              label: 'Название сообщества',
              placeholder: 'Название',
            ),
            TheavInlineTextField(
              controller: _descCtrl,
              label: 'Описание',
              placeholder: 'Чем занимается сообщество',
              maxLines: 3,
            ),
            TheavListRow(
              title: 'Публичное сообщество',
              subtitle: 'Видно в глобальном каталоге и поиске',
              trailing: TheavSwitch(
                value: _isPublic,
                onChanged: (v) => setState(() => _isPublic = v),
              ),
              onTap: () => setState(() => _isPublic = !_isPublic),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 10),
          child: SizedBox(
            width: double.infinity,
            child: TheavFloatingPillButton(
              label: _savingOverview ? 'Сохранение...' : 'Сохранить изменения',
              icon: const iconoir.Check(width: 18, height: 18),
              isPrimary: true,
              enabled: !_savingOverview,
              onTap: _saveOverview,
            ),
          ),
        ),
        TheavInsetGroup(
          header: 'ПРИГЛАШЕНИЯ',
          headerTrailing: _loadingInvites
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.6),
                )
              : null,
          children: [
            TheavListRow(
              leading: const iconoir.Link(width: 20, height: 20),
              title: 'Создать код приглашения',
              subtitle: 'Скопируется в буфер обмена',
              showChevron: true,
              onTap: _generateInvite,
            ),
            ..._invites.map((inv) {
              final usesLabel = inv.maxUses > 0
                  ? '${inv.uses}/${inv.maxUses} исп.'
                  : '${inv.uses} исп.';
              return TheavListRow(
                leading: const iconoir.Copy(width: 18, height: 18),
                title: inv.code,
                subtitle: inv.isExpired ? 'Истекло • $usesLabel' : usesLabel,
                onTap: () async {
                  await Clipboard.setData(ClipboardData(text: inv.code));
                  if (context.mounted) {
                    GlassToastService().show(
                      context,
                      'Скопировано: ${inv.code}',
                    );
                  }
                },
                trailing: GestureDetector(
                  onTap: () => _revokeInvite(inv),
                  child: iconoir.Trash(
                    width: 18,
                    height: 18,
                    color: palette.error,
                  ),
                ),
              );
            }),
          ],
        ),
        if (isOwner)
          TheavInsetGroup(
            header: 'ОПАСНАЯ ЗОНА',
            children: [
              TheavListRow(
                leading: const iconoir.Trash(width: 20, height: 20),
                title: 'Удалить сообщество',
                subtitle: 'Действие необратимо удалит все каналы и переписки',
                isDestructive: true,
                onTap: _confirmDeleteCommunity,
              ),
            ],
          ),
      ],
    );
  }

  Widget _buildChannelsTab(BuildContext context, TheavPalette palette) {
    return ListView(
      padding: const EdgeInsets.only(top: 6, bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: Row(
            children: [
              Expanded(
                child: TheavFloatingPillButton(
                  label: 'Категория',
                  icon: const iconoir.Folder(width: 17, height: 17),
                  onTap: _promptCreateCategory,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TheavFloatingPillButton(
                  label: 'Канал',
                  icon: const iconoir.Plus(width: 17, height: 17),
                  isPrimary: true,
                  onTap: _promptCreateChannel,
                ),
              ),
            ],
          ),
        ),
        if (_community.categories.isNotEmpty)
          TheavInsetGroup(
            header: 'КАТЕГОРИИ',
            children: _community.categories.map((cat) {
              return TheavListRow(
                leading: iconoir.Folder(
                  width: 19,
                  height: 19,
                  color: palette.primary,
                ),
                title: cat.name,
                subtitle: cat.isPrivate ? 'Приватная категория' : null,
                onTap: () => _editCategory(cat),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () => showCommunityOverwritesSheet(
                        context,
                        community: _community,
                        categoryId: cat.id,
                        targetName: cat.name,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: iconoir.Shield(
                          width: 17,
                          height: 17,
                          color: palette.primary,
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () => _deleteCategory(cat),
                      child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: iconoir.Trash(
                          width: 17,
                          height: 17,
                          color: palette.error,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        TheavInsetGroup(
          header: 'КАНАЛЫ (${_community.channels.length})',
          footer:
              'Нажмите на канал для редактирования медленного режима и прав доступа, или перемещайте стрелками.',
          children: _community.channels.isEmpty
              ? [
                  const TheavListRow(
                    title: 'Каналы ещё не созданы',
                    subtitle: 'Нажмите «+ Канал» выше',
                  ),
                ]
              : [
                  for (int i = 0; i < _community.channels.length; i++)
                    Builder(
                      builder: (ctx) {
                        final ch = _community.channels[i];
                        return TheavListRow(
                          leading: CommunityChannelIcon(
                            channelType: ch.channelType,
                            size: 19,
                          ),
                          title: ch.name,
                          subtitle:
                              CommunityChannelIcon.describeType(ch.channelType),
                          onTap: () => _editChannel(ch),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (i > 0)
                                GestureDetector(
                                  onTap: () => _moveChannel(i, -1),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: iconoir.NavArrowUp(
                                      width: 16,
                                      height: 16,
                                      color: palette.subtext,
                                    ),
                                  ),
                                ),
                              if (i < _community.channels.length - 1)
                                GestureDetector(
                                  onTap: () => _moveChannel(i, 1),
                                  child: Padding(
                                    padding: const EdgeInsets.all(4),
                                    child: iconoir.NavArrowDown(
                                      width: 16,
                                      height: 16,
                                      color: palette.subtext,
                                    ),
                                  ),
                                ),
                              GestureDetector(
                                onTap: () => showCommunityOverwritesSheet(
                                  ctx,
                                  community: _community,
                                  chatId: ch.id,
                                  targetName: '#${ch.name}',
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(5),
                                  child: iconoir.Shield(
                                    width: 16,
                                    height: 16,
                                    color: palette.primary,
                                  ),
                                ),
                              ),
                              GestureDetector(
                                onTap: () => _deleteChannel(ch),
                                child: Padding(
                                  padding: const EdgeInsets.all(5),
                                  child: iconoir.Trash(
                                    width: 16,
                                    height: 16,
                                    color: palette.error,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                ],
        ),
      ],
    );
  }

  Widget _buildRolesTab(BuildContext context, TheavPalette palette) {
    final role = _selectedRole;
    final flagByBit = {
      for (final f in CommunityPermissions.allFlags) f.bit: f,
    };

    return ListView(
      padding: const EdgeInsets.only(top: 6, bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 36,
                  child: ListView.separated(
                    scrollDirection: Axis.horizontal,
                    itemCount: _community.roles.length,
                    separatorBuilder: (_, __) => const SizedBox(width: 8),
                    itemBuilder: (ctx, i) {
                      final r = _community.roles[i];
                      final selected = r.id == role?.id;
                      final dotColor = r.parsedColor ?? palette.subtext;
                      return GestureDetector(
                        onTap: () {
                          HapticUtils.selection();
                          setState(() => _selectRole(r));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          decoration: BoxDecoration(
                            color: selected
                                ? palette.primary.withValues(alpha: 0.14)
                                : palette.onSurface.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: selected
                                  ? palette.primary
                                  : palette.divider,
                              width: selected ? 1.1 : 0.5,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Container(
                                width: 8,
                                height: 8,
                                decoration: BoxDecoration(
                                  color: dotColor,
                                  shape: BoxShape.circle,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                r.name,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: selected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: palette.onSurface,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _SmallActionIcon(
                icon: iconoir.PlusCircle(
                  width: 20,
                  height: 20,
                  color: palette.primary,
                ),
                onTap: _promptCreateRole,
              ),
              if (role != null && !role.isEveryone) ...[
                const SizedBox(width: 4),
                _SmallActionIcon(
                  icon: iconoir.Trash(
                    width: 19,
                    height: 19,
                    color: palette.error,
                  ),
                  onTap: _deleteSelectedRole,
                ),
              ],
            ],
          ),
        ),
        if (role != null) ...[
          TheavInsetGroup(
            header: 'НАСТРОЙКИ РОЛИ',
            children: [
              if (!role.isEveryone)
                TheavInlineTextField(
                  controller: _roleNameCtrl,
                  label: 'Название роли',
                  placeholder: 'Название',
                  onSubmitted: (v) {
                    if (v.trim().isNotEmpty) {
                      _updateSelectedRoleField(name: v.trim());
                    }
                  },
                  suffix: GestureDetector(
                    onTap: () {
                      final trimmed = _roleNameCtrl.text.trim();
                      if (trimmed.isNotEmpty) {
                        _updateSelectedRoleField(name: trimmed);
                        GlassToastService().show(context, 'Имя роли обновлено');
                      }
                    },
                    child: iconoir.Check(
                      width: 18,
                      height: 18,
                      color: palette.primary,
                    ),
                  ),
                ),
              if (!role.isEveryone)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Цвет роли',
                        style: TextStyle(
                          fontSize: 13,
                          color: palette.subtext,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 10,
                        runSpacing: 8,
                        children: _kRoleColors.map((hex) {
                          final colorVal = int.parse(
                            'ff${hex.substring(1)}',
                            radix: 16,
                          );
                          final c = Color(colorVal);
                          final isSelected =
                              role.colorHex.toUpperCase() == hex.toUpperCase();
                          return GestureDetector(
                            onTap: () =>
                                _updateSelectedRoleField(colorHex: hex),
                            child: Container(
                              width: 28,
                              height: 28,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: isSelected
                                      ? palette.onSurface
                                      : Colors.transparent,
                                  width: 2.2,
                                ),
                              ),
                              alignment: Alignment.center,
                              child: isSelected
                                  ? const iconoir.Check(
                                      width: 14,
                                      height: 14,
                                      color: Colors.white,
                                    )
                                  : null,
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              if (!role.isEveryone)
                TheavListRow(
                  title: 'Показывать отдельно (Hoisted)',
                  subtitle: 'Группировать участников с этой ролью в списке',
                  trailing: TheavSwitch(
                    value: role.isHoisted,
                    onChanged: (v) => _updateSelectedRoleField(isHoisted: v),
                  ),
                  onTap: () =>
                      _updateSelectedRoleField(isHoisted: !role.isHoisted),
                ),
              TheavListRow(
                title: 'Разрешить упоминания (@роль)',
                trailing: TheavSwitch(
                  value: role.isMentionable,
                  onChanged: (v) => _updateSelectedRoleField(isMentionable: v),
                ),
                onTap: () =>
                    _updateSelectedRoleField(isMentionable: !role.isMentionable),
              ),
            ],
          ),
          for (final group in _kPermissionGroups)
            TheavInsetGroup(
              header: group.header,
              dividerIndent: 16,
              children: group.bits
                  .map((bit) => flagByBit[bit])
                  .whereType<({int bit, String title, String subtitle})>()
                  .map((flag) {
                    final enabled = (role.permissions & flag.bit) != 0;
                    final locked = role.id == 'default_member';
                    return TheavListRow(
                      title: flag.title,
                      subtitle: flag.subtitle,
                      trailing: TheavSwitch(
                        value: enabled,
                        onChanged:
                            locked ? null : (_) => _toggleRolePermission(flag.bit),
                      ),
                      onTap: locked
                          ? null
                          : () => _toggleRolePermission(flag.bit),
                    );
                  })
                  .toList(),
            ),
        ],
      ],
    );
  }

  Widget _buildMembersAndBansTab(BuildContext context, TheavPalette palette) {
    final qLower = _memberQuery.trim().toLowerCase();
    final filteredMembers = qLower.isEmpty
        ? _members
        : _members.where((m) {
            final resolvedName = _resolveMemberName(m).toLowerCase();
            return resolvedName.contains(qLower) ||
                m.effectiveDisplayName.toLowerCase().contains(qLower) ||
                m.displayName.toLowerCase().contains(qLower) ||
                (m.originalDisplayName?.toLowerCase().contains(qLower) ?? false) ||
                m.nickname.toLowerCase().contains(qLower) ||
                m.username.toLowerCase().contains(qLower);
          }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
          child: TheavSegmentedControl<int>(
            useGlass: false,
            selected: _membersSegment,
            onChanged: (v) => setState(() => _membersSegment = v),
            options: [
              TheavSegmentOption(
                value: 0,
                label: 'Участники (${_members.length})',
              ),
              TheavSegmentOption(
                value: 1,
                label: 'Баны (${_bans.length})',
              ),
            ],
          ),
        ),
        if (_membersSegment == 0)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
            child: TheavInsetGroup(
              margin: EdgeInsets.zero,
              borderRadius: 14,
              children: [
                TheavInlineTextField(
                  controller: _memberSearchCtrl,
                  placeholder: 'Найти участника...',
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 9,
                  ),
                  prefix: iconoir.Search(
                    width: 17,
                    height: 17,
                    color: palette.subtext,
                  ),
                  onChanged: (v) => setState(() => _memberQuery = v),
                ),
              ],
            ),
          ),
        Expanded(
          child: _membersSegment == 0
              ? (_loadingMembers && _members.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(top: 4, bottom: 20),
                      children: [
                        TheavInsetGroup(
                          dividerIndent: 58,
                          children: filteredMembers.isEmpty
                              ? [
                                  const TheavListRow(
                                    title: 'Участники не найдены',
                                  ),
                                ]
                              : filteredMembers.map((m) {
                                  final memberName =
                                      _resolveMemberName(m, emptyFallback: 'U');
                                  final memberAvatarUrl =
                                      _resolveMemberAvatar(m);
                                  final canResolveIdentity =
                                      ContactsService.shouldResolveUserIdentity(
                                    m.userId,
                                    isBot: m.isBot,
                                  );
                                  final roleNames = _community.roles
                                      .where((r) => m.roleIds.contains(r.id))
                                      .map((r) => r.name)
                                      .join(', ');
                                  final topRole = highestColoredRoleForMember(
                                    m,
                                    _community.roles,
                                  );
                                  final cust = m.peerCustomization;

                                  return TheavListRow(
                                    leading: AvatarWithStatus(
                                      userId: m.userId,
                                      avatarUrl: memberAvatarUrl,
                                      name: memberName,
                                      radius: 19,
                                      isOnline: m.isOnline,
                                      decorationOverride: cust?.avatarDecoration,
                                      showDecoration: true,
                                      animateDecoration: false,
                                      resolveContactOverride:
                                          canResolveIdentity,
                                    ),
                                    titleWidget: Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            memberName,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              fontWeight: FontWeight.w600,
                                              color: topRole?.parsedColor ??
                                                  palette.onSurface,
                                            ),
                                          ),
                                        ),
                                        if (cust?.activeEmojiStatus != null) ...[
                                          const SizedBox(width: 4),
                                          EmojiStatusBadge(
                                            status: cust!.activeEmojiStatus,
                                            size: 14,
                                            interactive: false,
                                          ),
                                        ],
                                        PeerBadgesRow(
                                          isBot: m.isBot,
                                          isVerified: m.isVerified,
                                          badge: cust?.visibleBadge,
                                          interactiveBadge: false,
                                          verifiedIconSize: 14,
                                        ),
                                      ],
                                    ),
                                    subtitle: roleNames.isNotEmpty
                                        ? roleNames
                                        : '@everyone',
                                    showChevron: true,
                                    onTap: () => _showMemberActions(m),
                                  );
                                }).toList(),
                        ),
                      ],
                    ))
              : (_loadingBans && _bans.isEmpty
                  ? const Center(
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : ListView(
                      padding: const EdgeInsets.only(top: 4, bottom: 20),
                      children: [
                        TheavInsetGroup(
                          children: _bans.isEmpty
                              ? [
                                  const TheavListRow(
                                    title: 'Чёрный список пуст',
                                    subtitle: 'Заблокированных участников нет',
                                  ),
                                ]
                              : _bans.map((b) {
                                  final banName = _resolveBanName(b);
                                  final banAvatarUrl = _resolveBanAvatar(b);
                                  return TheavListRow(
                                    leading: AvatarWithStatus(
                                      userId: b.userId,
                                      avatarUrl: banAvatarUrl,
                                      name: banName,
                                      radius: 18,
                                      isOnline: false,
                                      showDecoration: false,
                                      resolveContactOverride: ContactsService
                                          .shouldResolveUserIdentity(b.userId),
                                    ),
                                    title: banName,
                                    subtitle: b.reason.isNotEmpty
                                        ? 'Причина: ${b.reason}'
                                        : (b.username.isNotEmpty
                                            ? '@${b.username}'
                                            : null),
                                    trailing: TextButton(
                                      onPressed: () => _unbanMember(b),
                                      child: const Text('Разбанить'),
                                    ),
                                  );
                                }).toList(),
                        ),
                      ],
                    )),
        ),
      ],
    );
  }

  Widget _buildSoundboardTab(BuildContext context, TheavPalette palette) {
    return ListView(
      padding: const EdgeInsets.only(top: 6, bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 10),
          child: SizedBox(
            width: double.infinity,
            child: TheavFloatingPillButton(
              label: 'Добавить звуковой клип',
              icon: const iconoir.MusicDoubleNote(width: 18, height: 18),
              isPrimary: true,
              onTap: _promptAddSound,
            ),
          ),
        ),
        if (_loadingSounds && _sounds.isEmpty)
          const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else
          TheavInsetGroup(
            header: 'САУНДБОРД СООБЩЕСТВА (${_sounds.length})',
            footer:
                'Звуки доступны в голосовых комнатах и на трибуне для участников с правом саундборда.',
            children: _sounds.isEmpty
                ? [
                    const TheavListRow(
                      title: 'Пользовательских звуков пока нет',
                      subtitle: 'Загрузите короткий аудиофайл (до 10 сек.)',
                    ),
                  ]
                : _sounds.map((s) {
                    final secStr =
                        '${(s.durationMs / 1000.0).toStringAsFixed(1)} с';
                    return TheavListRow(
                      leading: Text(
                        s.emoji.isNotEmpty ? s.emoji : '🔊',
                        style: const TextStyle(fontSize: 20),
                      ),
                      title: s.name,
                      subtitle: secStr,
                      trailing: GestureDetector(
                        onTap: () => _deleteSound(s),
                        child: iconoir.Trash(
                          width: 18,
                          height: 18,
                          color: palette.error,
                        ),
                      ),
                    );
                  }).toList(),
          ),
      ],
    );
  }
}

class _SmallActionIcon extends StatelessWidget {
  final Widget icon;
  final VoidCallback onTap;

  const _SmallActionIcon({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticUtils.tap();
        onTap();
      },
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: icon,
      ),
    );
  }
}
