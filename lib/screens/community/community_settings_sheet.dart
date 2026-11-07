import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/community_models.dart';
import '../../models/theav_theme.dart';
import '../../services/community_service.dart';

/// Community administration bottom sheet for managing Overview, Categories,
/// Channels (`#text`, `🔊 voice`, `🎙️ stage`), Roles (64-bit bitmask permissions),
/// and Invite Codes.
class CommunitySettingsSheet extends StatefulWidget {
  final Community community;
  final ValueChanged<Community> onCommunityUpdated;

  const CommunitySettingsSheet({
    super.key,
    required this.community,
    required this.onCommunityUpdated,
  });

  static Future<void> show(
    BuildContext context, {
    required Community community,
    required ValueChanged<Community> onCommunityUpdated,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => CommunitySettingsSheet(
        community: community,
        onCommunityUpdated: onCommunityUpdated,
      ),
    );
  }

  @override
  State<CommunitySettingsSheet> createState() => _CommunitySettingsSheetState();
}

class _CommunitySettingsSheetState extends State<CommunitySettingsSheet>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  late Community _community;
  late TextEditingController _nameCtrl;
  late TextEditingController _descCtrl;
  late bool _isPublic;
  String? _inviteCode;
  bool _savingOverview = false;
  CommunityRole? _selectedRole;
  List<CommunityMember> _members = const [];
  bool _loadingMembers = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _community = widget.community;
    _nameCtrl = TextEditingController(text: _community.name);
    _descCtrl = TextEditingController(text: _community.description);
    _isPublic = _community.isPublic;
    if (_community.roles.isNotEmpty) {
      _selectedRole = _community.roles.first;
    }
    _loadRolesAndMembers();
  }

  Future<void> _loadRolesAndMembers() async {
    setState(() => _loadingMembers = true);
    final rolesFuture = CommunityService.getRoles(_community.id);
    final membersFuture = CommunityService.getMembers(_community.id);
    final roles = await rolesFuture;
    final members = await membersFuture;
    if (!mounted) return;
    setState(() {
      _loadingMembers = false;
      if (roles.isNotEmpty) {
        _community = _community.copyWith(roles: roles);
        _selectedRole = roles.firstWhere(
          (r) => r.id == _selectedRole?.id,
          orElse: () => roles.first,
        );
      }
      _members = members;
    });
    widget.onCommunityUpdated(_community);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveOverview() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;
    setState(() => _savingOverview = true);
    final updated = await CommunityService.updateCommunity(
      _community.id,
      name: name,
      description: _descCtrl.text.trim(),
      isPublic: _isPublic,
    );
    if (!mounted) return;
    setState(() {
      _savingOverview = false;
      _community = updated ??
          _community.copyWith(
            name: name,
            description: _descCtrl.text.trim(),
            isPublic: _isPublic,
          );
    });
    widget.onCommunityUpdated(_community);
  }

  Future<void> _generateInvite() async {
    final code = await CommunityService.createInviteCode(_community.id);
    if (!mounted) return;
    if (code == null || code.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось создать код приглашения (проверьте права)'),
        ),
      );
      return;
    }
    setState(() => _inviteCode = code);
    await Clipboard.setData(ClipboardData(text: code));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Код приглашения скопирован: $code')),
    );
  }

  Future<void> _confirmDeleteCommunity() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Удалить сообщество?'),
        content: Text(
          'Сообщество «${_community.name}» и все его каналы будут безвозвратно удалены.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final ok = await CommunityService.deleteCommunity(_community.id);
    if (!mounted) return;
    if (ok) {
      Navigator.of(context).pop();
      Navigator.of(context).maybePop();
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось удалить сообщество (только владелец)'),
        ),
      );
    }
  }

  Future<void> _promptCreateCategory() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новая категория'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Например: ГОЛОСОВЫЕ КОМНАТЫ',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
    if (name == null || name.isEmpty) return;

    final created = await CommunityService.createCategory(
      _community.id,
      name: name,
      position: _community.categories.length,
    );
    if (!mounted) return;
    if (created == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось создать категорию (проверьте права доступа)'),
        ),
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

  Future<void> _promptCreateChannel() async {
    final nameCtrl = TextEditingController();
    String selectedType = 'text';
    String? selectedCategoryId = _community.categories.isNotEmpty
        ? _community.categories.first.id
        : null;

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          title: const Text('Создать канал'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: nameCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Название канала',
                  hintText: 'general / gaming-144fps',
                ),
              ),
              const SizedBox(height: 14),
              const Text(
                'Тип канала',
                style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(
                    value: 'text',
                    icon: Icon(Icons.tag_rounded, size: 15),
                    label: Text('Текст'),
                  ),
                  ButtonSegment(
                    value: 'announcement',
                    icon: Icon(Icons.campaign_rounded, size: 15),
                    label: Text('Анонсы'),
                  ),
                  ButtonSegment(
                    value: 'voice',
                    icon: Icon(Icons.volume_up_rounded, size: 15),
                    label: Text('Голос'),
                  ),
                  ButtonSegment(
                    value: 'stage',
                    icon: Icon(Icons.podcasts_rounded, size: 15),
                    label: Text('Трибуна'),
                  ),
                  ButtonSegment(
                    value: 'whiteboard',
                    icon: Icon(Icons.draw_rounded, size: 15),
                    label: Text('Доска'),
                  ),
                ],
                selected: {selectedType},
                onSelectionChanged: (s) =>
                    setDialogState(() => selectedType = s.first),
              ),
              if (_community.categories.isNotEmpty) ...[
                const SizedBox(height: 14),
                DropdownButtonFormField<String?>(
                  initialValue: selectedCategoryId,
                  decoration: const InputDecoration(labelText: 'Категория'),
                  items: [
                    const DropdownMenuItem<String?>(
                      value: null,
                      child: Text('Без категории'),
                    ),
                    ..._community.categories.map(
                      (c) => DropdownMenuItem<String?>(
                        value: c.id,
                        child: Text(c.name),
                      ),
                    ),
                  ],
                  onChanged: (v) =>
                      setDialogState(() => selectedCategoryId = v),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Отмена'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Создать'),
            ),
          ],
        ),
      ),
    );

    if (result != true) return;
    final name = nameCtrl.text.trim();
    if (name.isEmpty) return;

    final created = await CommunityService.createChannel(
      _community.id,
      name: name,
      channelType: selectedType,
      categoryId: selectedCategoryId,
    );
    if (!mounted) return;
    if (created == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Не удалось создать канал (проверьте права доступа)'),
        ),
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

  Future<void> _toggleRolePermission(int bit) async {
    final role = _selectedRole;
    if (role == null || role.id == 'default_member') return;
    HapticFeedback.selectionClick();
    final hasBit = (role.permissions & bit) != 0;
    final newPerms =
        hasBit ? (role.permissions & ~bit) : (role.permissions | bit);
    final updatedRole = role.copyWith(permissions: newPerms);
    setState(() {
      _selectedRole = updatedRole;
      final roles = _community.roles
          .map((r) => r.id == updatedRole.id ? updatedRole : r)
          .toList();
      _community = _community.copyWith(roles: roles);
    });
    widget.onCommunityUpdated(_community);
    await CommunityService.updateRole(
      _community.id,
      role.id,
      permissions: newPerms,
    );
  }

  Future<void> _promptCreateRole() async {
    final ctrl = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Новая роль'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Например: Модератор'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text.trim()),
            child: const Text('Создать'),
          ),
        ],
      ),
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
      _selectedRole = created;
    });
    widget.onCommunityUpdated(_community);
  }

  Future<void> _deleteSelectedRole() async {
    final role = _selectedRole;
    if (role == null || role.isEveryone) return;
    final ok = await CommunityService.deleteRole(_community.id, role.id);
    if (!mounted || !ok) return;
    final remaining = _community.roles.where((r) => r.id != role.id).toList();
    setState(() {
      _community = _community.copyWith(roles: remaining);
      _selectedRole = remaining.isNotEmpty ? remaining.first : null;
    });
    widget.onCommunityUpdated(_community);
  }

  Future<void> _deleteChannel(CommunityChannel ch) async {
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

  Future<void> _showMemberActions(CommunityMember member) async {
    final assignableRoles =
        _community.roles.where((r) => !r.isEveryone).toList();
    final selectedRoleIds = Set<String>.from(member.roleIds);

    await showModalBottomSheet(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  member.displayName.isNotEmpty
                      ? member.displayName
                      : member.username,
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 10),
                if (assignableRoles.isNotEmpty) ...[
                  const Text(
                    'Роли участника:',
                    style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    children: assignableRoles.map((role) {
                      final hasRole = selectedRoleIds.contains(role.id);
                      return FilterChip(
                        label: Text(role.name),
                        selected: hasRole,
                        onSelected: (val) async {
                          setSheetState(() {
                            if (val) {
                              selectedRoleIds.add(role.id);
                            } else {
                              selectedRoleIds.remove(role.id);
                            }
                          });
                          await CommunityService.setMemberRoles(
                            _community.id,
                            member.userId,
                            selectedRoleIds.toList(),
                          );
                          _loadRolesAndMembers();
                        },
                      );
                    }).toList(),
                  ),
                  const Divider(height: 24),
                ],
                ListTile(
                  leading: const Icon(
                    Icons.person_remove_rounded,
                    color: Colors.orange,
                  ),
                  title: const Text('Исключить (Kick)'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final ok = await CommunityService.kickMember(
                      _community.id,
                      member.userId,
                    );
                    if (ok && mounted) {
                      _loadRolesAndMembers();
                    }
                  },
                ),
                ListTile(
                  leading: const Icon(
                    Icons.gavel_rounded,
                    color: Colors.redAccent,
                  ),
                  title: const Text('Заблокировать (Ban)'),
                  onTap: () async {
                    Navigator.of(ctx).pop();
                    final ok = await CommunityService.banMember(
                      _community.id,
                      member.userId,
                    );
                    if (ok && mounted) {
                      _loadRolesAndMembers();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final p = context.theav;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;
    final mq = MediaQuery.of(context);

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      child: BackdropFilter.grouped(
        filter: ui.ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          height: mq.size.height * 0.82,
          decoration: BoxDecoration(
            color: isDark
                ? p.surfaceElevated.withValues(alpha: 0.95)
                : Colors.white.withValues(alpha: 0.96),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border(top: BorderSide(color: p.borderSubtle, width: 0.8)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: p.textTertiary.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 16, 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.hub_rounded,
                      color: primaryColor,
                      size: 24,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Настройки «${_community.name}»',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: p.textPrimary,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close_rounded, color: p.textSecondary),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: primaryColor,
                unselectedLabelColor: p.textSecondary,
                indicatorColor: primaryColor,
                tabs: const [
                  Tab(text: 'Обзор'),
                  Tab(text: 'Каналы'),
                  Tab(text: 'Роли и права'),
                  Tab(text: 'Участники'),
                ],
              ),
              Expanded(
                child: TabBarView(
                  controller: _tabController,
                  children: [
                    // 1. Overview Tab
                    ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        TextField(
                          controller: _nameCtrl,
                          decoration: InputDecoration(
                            labelText: 'Название сообщества',
                            filled: true,
                            fillColor:
                                p.surfaceSecondary.withValues(alpha: 0.5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 14),
                        TextField(
                          controller: _descCtrl,
                          maxLines: 3,
                          decoration: InputDecoration(
                            labelText: 'Описание сообщества',
                            filled: true,
                            fillColor:
                                p.surfaceSecondary.withValues(alpha: 0.5),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SwitchListTile.adaptive(
                          contentPadding: EdgeInsets.zero,
                          value: _isPublic,
                          activeTrackColor: primaryColor,
                          title: Text(
                            'Публичное сообщество',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              color: p.textPrimary,
                            ),
                          ),
                          subtitle: Text(
                            'Доступно в глобальном каталоге сообществ',
                            style: TextStyle(
                              fontSize: 12,
                              color: p.textSecondary,
                            ),
                          ),
                          onChanged: (v) => setState(() => _isPublic = v),
                        ),
                        const SizedBox(height: 12),
                        FilledButton.icon(
                          onPressed: _savingOverview ? null : _saveOverview,
                          icon: const Icon(Icons.check_rounded),
                          label: Text(
                            _savingOverview
                                ? 'Сохранение...'
                                : 'Сохранить изменения',
                          ),
                        ),
                        const SizedBox(height: 24),
                        Divider(color: p.borderSubtle),
                        const SizedBox(height: 12),
                        Text(
                          'Приглашение участников',
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: p.textPrimary,
                          ),
                        ),
                        const SizedBox(height: 8),
                        OutlinedButton.icon(
                          onPressed: _generateInvite,
                          icon: const Icon(Icons.link_rounded),
                          label: Text(
                            _inviteCode != null
                                ? 'Код: $_inviteCode (Скопирован)'
                                : 'Создать код приглашения',
                          ),
                        ),
                        const SizedBox(height: 24),
                        Divider(color: p.borderSubtle),
                        const SizedBox(height: 12),
                        OutlinedButton.icon(
                          style: OutlinedButton.styleFrom(
                            foregroundColor: Colors.redAccent,
                            side: const BorderSide(color: Colors.redAccent),
                          ),
                          onPressed: _confirmDeleteCommunity,
                          icon: const Icon(Icons.delete_forever_rounded),
                          label: const Text('Удалить сообщество'),
                        ),
                      ],
                    ),

                    // 2. Channels & Categories Tab
                    ListView(
                      padding: const EdgeInsets.all(20),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _promptCreateCategory,
                                icon: const Icon(
                                  Icons.create_new_folder_outlined,
                                  size: 18,
                                ),
                                label: const Text('+ Категория'),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: _promptCreateChannel,
                                icon: const Icon(Icons.add_rounded, size: 18),
                                label: const Text('+ Канал'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 18),
                        if (_community.categories.isNotEmpty) ...[
                          Text(
                            'Категории',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.w700,
                              color: p.textSecondary,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ..._community.categories.map((cat) {
                            return ListTile(
                              dense: true,
                              contentPadding:
                                  const EdgeInsets.symmetric(horizontal: 8),
                              leading: Icon(
                                Icons.folder_outlined,
                                color: p.textSecondary,
                              ),
                              title: Text(
                                cat.name,
                                style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: p.textPrimary,
                                ),
                              ),
                              trailing: IconButton(
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  size: 18,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () => _deleteCategory(cat),
                              ),
                            );
                          }),
                          Divider(color: p.borderSubtle, height: 20),
                        ],
                        ..._community.channels.map((ch) {
                          return ListTile(
                            contentPadding:
                                const EdgeInsets.symmetric(horizontal: 8),
                            leading: Icon(
                              ch.isStage
                                  ? Icons.podcasts_rounded
                                  : ch.isVoice
                                      ? Icons.volume_up_rounded
                                      : ch.isWhiteboard
                                          ? Icons.draw_rounded
                                          : ch.isAnnouncement
                                              ? Icons.campaign_rounded
                                              : Icons.tag_rounded,
                              color: ch.isAudioRoom
                                  ? const Color(0xFF00C853)
                                  : ch.isWhiteboard
                                      ? const Color(0xFFAA00FF)
                                      : primaryColor,
                            ),
                            title: Text(
                              ch.name,
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                color: p.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              ch.isStage
                                  ? 'Трибуна (Stage)'
                                  : ch.isVoice
                                      ? 'Голосовой канал + Go Live 144 FPS'
                                      : ch.isWhiteboard
                                          ? 'Интерактивная доска (Miro-style)'
                                          : ch.isAnnouncement
                                              ? 'Канал объявлений'
                                              : 'Текстовый канал',
                              style: TextStyle(
                                fontSize: 12,
                                color: p.textSecondary,
                              ),
                            ),
                            trailing: IconButton(
                              icon: const Icon(
                                Icons.delete_outline_rounded,
                                size: 19,
                                color: Colors.redAccent,
                              ),
                              onPressed: () => _deleteChannel(ch),
                            ),
                          );
                        }),
                      ],
                    ),

                    // 3. Roles & Bitmask Permissions Tab
                    ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: _community.roles.map((r) {
                                    final selected = r.id == _selectedRole?.id;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 8),
                                      child: ChoiceChip(
                                        label: Text(r.name),
                                        selected: selected,
                                        onSelected: (_) => setState(
                                            () => _selectedRole = r),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Создать роль',
                              icon: Icon(Icons.add_circle_outline_rounded,
                                  color: primaryColor),
                              onPressed: _promptCreateRole,
                            ),
                            if (_selectedRole != null &&
                                !_selectedRole!.isEveryone)
                              IconButton(
                                tooltip: 'Удалить роль',
                                icon: const Icon(
                                  Icons.delete_outline_rounded,
                                  color: Colors.redAccent,
                                ),
                                onPressed: _deleteSelectedRole,
                              ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: primaryColor.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.shield_rounded, color: primaryColor),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'Роль: ${_selectedRole?.name ?? "@everyone"} (Битовая маска прав)',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: p.textPrimary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...CommunityPermissions.allFlags.map((flag) {
                          final enabled =
                              ((_selectedRole?.permissions ?? 0) & flag.bit) !=
                                  0;
                          return SwitchListTile.adaptive(
                            value: enabled,
                            activeTrackColor: primaryColor,
                            title: Text(
                              flag.title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: p.textPrimary,
                              ),
                            ),
                            subtitle: Text(
                              flag.subtitle,
                              style: TextStyle(
                                fontSize: 12,
                                color: p.textSecondary,
                              ),
                            ),
                            onChanged: (_) => _toggleRolePermission(flag.bit),
                          );
                        }),
                      ],
                    ),

                    // 4. Members Tab
                    _loadingMembers
                        ? const Center(child: CircularProgressIndicator())
                        : ListView.builder(
                            padding: const EdgeInsets.all(16),
                            itemCount: _members.length,
                            itemBuilder: (ctx, i) {
                              final m = _members[i];
                              final roleNames = _community.roles
                                  .where((r) => m.roleIds.contains(r.id))
                                  .map((r) => r.name)
                                  .join(', ');
                              return ListTile(
                                leading: CircleAvatar(
                                  backgroundColor:
                                      primaryColor.withValues(alpha: 0.18),
                                  child: Text(
                                    (m.displayName.isNotEmpty
                                            ? m.displayName
                                            : m.username.isNotEmpty
                                                ? m.username
                                                : 'U')[0]
                                        .toUpperCase(),
                                    style: TextStyle(
                                      fontWeight: FontWeight.w700,
                                      color: primaryColor,
                                    ),
                                  ),
                                ),
                                title: Text(
                                  m.displayName.isNotEmpty
                                      ? m.displayName
                                      : m.username,
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    color: p.textPrimary,
                                  ),
                                ),
                                subtitle: Text(
                                  roleNames.isNotEmpty
                                      ? roleNames
                                      : '@everyone',
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: p.textSecondary,
                                  ),
                                ),
                                trailing: IconButton(
                                  icon: Icon(
                                    Icons.more_vert_rounded,
                                    color: p.textSecondary,
                                  ),
                                  onPressed: () => _showMemberActions(m),
                                ),
                              );
                            },
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
