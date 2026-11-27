import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/chat_folder.dart';
import '../../services/account_manager.dart';
import '../../services/chat_folder_service.dart';
import '../../services/contacts_service.dart';
import '../../services/database/app_database.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/image_utils.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/settings/settings_floating_header.dart';
import '../../widgets/settings/settings_group.dart';

/// Full-featured editor for creating and customizing chat folders:
/// name, icon, included chat types, and specific included/excluded chats.
class FolderEditScreen extends StatefulWidget {
  final ChatFolder? existingFolder;

  const FolderEditScreen({
    super.key,
    this.existingFolder,
  });

  static const List<({String name, IconData icon})> availableIcons = [
    (name: 'folder', icon: Icons.folder_outlined),
    (name: 'person', icon: Icons.person_outline),
    (name: 'group', icon: Icons.group_outlined),
    (name: 'campaign', icon: Icons.campaign_outlined),
    (name: 'work', icon: Icons.work_outline),
    (name: 'school', icon: Icons.school_outlined),
    (name: 'star', icon: Icons.star_outline),
    (name: 'favorite', icon: Icons.favorite_outline),
    (name: 'bots', icon: Icons.smart_toy_outlined),
    (name: 'unread', icon: Icons.mark_chat_unread_outlined),
    (name: 'archive', icon: Icons.archive_outlined),
    (name: 'games', icon: Icons.sports_esports_outlined),
  ];

  static IconData iconForName(String iconName, {String? folderId}) {
    if (iconName == 'folder' && folderId != null) {
      switch (folderId) {
        case 'all':
          return Icons.chat_bubble_outline;
        case 'personal':
          return Icons.person_outline;
        case 'groups':
          return Icons.group_outlined;
        case 'channels':
          return Icons.campaign_outlined;
      }
    }
    for (final entry in availableIcons) {
      if (entry.name == iconName) return entry.icon;
    }
    return Icons.folder_outlined;
  }

  @override
  State<FolderEditScreen> createState() => _FolderEditScreenState();
}

class _FolderEditScreenState extends State<FolderEditScreen> {
  final TextEditingController _nameController = TextEditingController();
  late String _iconName;
  late bool _includePrivate;
  late bool _includeGroups;
  late bool _includeChannels;
  late List<String> _includedChatIds;
  late List<String> _excludedChatIds;

  List<DbChat> _allChats = [];
  bool _loadingChats = true;
  bool _saving = false;

  bool get _isEditing => widget.existingFolder != null;

  @override
  void initState() {
    super.initState();
    final f = widget.existingFolder;
    _nameController.text = f?.name ?? '';
    _iconName = f?.iconName ?? 'folder';
    _includePrivate = f == null
        ? true
        : (f.includedTypes.contains('private') ||
            f.includedTypes.contains('saved'));
    _includeGroups = f?.includedTypes.contains('group') ?? false;
    _includeChannels = f?.includedTypes.contains('channel') ?? false;
    _includedChatIds = List<String>.from(f?.includedChatIds ?? const []);
    _excludedChatIds = List<String>.from(f?.excludedChatIds ?? const []);
    ContactsService.revisionNotifier.addListener(_onContactsRevisionChanged);
    _loadChats();
  }

  void _onContactsRevisionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ContactsService.revisionNotifier.removeListener(_onContactsRevisionChanged);
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadChats() async {
    try {
      final uid = AccountManager().currentAccount?.userId;
      final chats = await AppDatabase(uid).getChats();
      if (!mounted) return;
      setState(() {
        _allChats = chats;
        _loadingChats = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loadingChats = false);
      }
    }
  }

  String _resolvedChatTitle(DbChat c) {
    if (c.chatType == 'saved') {
      return context.l10n.translate('chat_saved_messages');
    }
    if (c.chatType == 'private' && !c.isBot) {
      return ContactsService.resolvePeerName(
        c.otherUserId,
        c.name,
        isBot: c.isBot,
      );
    }
    return c.name;
  }

  String? _resolvedChatAvatar(DbChat c) {
    if (c.chatType == 'private' && !c.isBot) {
      return ContactsService.resolvePeerAvatarUrl(
        c.otherUserId,
        c.avatarUrl,
        isBot: c.isBot,
      );
    }
    return c.avatarUrl;
  }

  String _chatDisplayName(String chatId) {
    for (final c in _allChats) {
      if (c.chatId == chatId) {
        return _resolvedChatTitle(c);
      }
    }
    return chatId;
  }

  Future<void> _pickChats({required bool isIncluded}) async {
    final l10n = context.l10n;
    final initialSelected =
        Set<String>.from(isIncluded ? _includedChatIds : _excludedChatIds);
    String searchQuery = '';

    final result = await showTheavModalSheet<Set<String>>(
      context: context,
      enableDrag: false,
      builder: (_) => const SizedBox.shrink(),
      customSheetBuilder: (sheetCtx) {
        return ValueListenableBuilder<int>(
          valueListenable: ContactsService.revisionNotifier,
          builder: (_, __, ___) => StatefulBuilder(
            builder: (context, setSheetState) {
              final q = searchQuery.trim().toLowerCase();
              final filtered = _allChats.where((c) {
                if (q.isEmpty) return true;
                final resolvedName = _resolvedChatTitle(c).toLowerCase();
                return resolvedName.contains(q) ||
                    c.name.toLowerCase().contains(q) ||
                    (c.username?.toLowerCase().contains(q) ?? false);
              }).toList();
            final media = MediaQuery.of(context);
            final double sheetHeight = media.size.height * 0.78;

            return Align(
              alignment: Alignment.bottomCenter,
              heightFactor: 1.0,
              child: SizedBox(
                height: sheetHeight,
                child: TheavSheetSurface(
                  cornerRadius: 24.0,
                  child: SafeArea(
                    top: false,
                    child: Padding(
                      padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
                      child: Column(
                        children: [
                          GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onVerticalDragEnd: (d) {
                              if ((d.primaryVelocity ?? 0.0) > 650.0) {
                                Navigator.pop(sheetCtx);
                              }
                            },
                            child: Container(
                              width: 112,
                              padding: const EdgeInsets.only(top: 10, bottom: 4),
                              alignment: Alignment.center,
                              child: Container(
                                width: 36,
                                height: 4,
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .onSurface
                                      .withValues(alpha: 0.24),
                                  borderRadius: BorderRadius.circular(2),
                                ),
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    isIncluded
                                        ? l10n.translate('folders_included_chats')
                                        : l10n.translate('folders_excluded_chats'),
                                    style: Theme.of(context)
                                        .textTheme
                                        .titleMedium
                                        ?.copyWith(fontWeight: FontWeight.w600),
                                  ),
                                ),
                                TextButton(
                                  onPressed: () =>
                                      Navigator.pop(sheetCtx, initialSelected),
                                  child: Text(l10n.translate('common_done')),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 4,
                            ),
                            child: TextField(
                              decoration: InputDecoration(
                                prefixIcon: const Icon(Icons.search),
                                hintText: l10n.translate('search_hint'),
                                isDense: true,
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                              onChanged: (v) =>
                                  setSheetState(() => searchQuery = v),
                            ),
                          ),
                          Expanded(
                            child: _loadingChats
                                ? const Center(
                                    child: CircularProgressIndicator())
                                : filtered.isEmpty
                                    ? Center(
                                        child: Text(
                                          l10n.translate('chat_no_chats'),
                                          style: TextStyle(
                                              color: Colors.grey[600]),
                                        ),
                                      )
                                    : ListView.builder(
                                        itemCount: filtered.length,
                                        itemBuilder: (_, idx) {
                                          final chat = filtered[idx];
                                          final checked = initialSelected
                                              .contains(chat.chatId);
                                          final resolvedAvatar =
                                              _resolvedChatAvatar(chat);
                                          final provider =
                                              resolvedAvatar != null &&
                                                      resolvedAvatar.isNotEmpty
                                                  ? avatarImageProvider(
                                                      resolvedAvatar)
                                                  : null;
                                          final title = _resolvedChatTitle(chat);
                                          return CheckboxListTile(
                                            value: checked,
                                            secondary: CircleAvatar(
                                              radius: 18,
                                              backgroundImage: provider,
                                              onBackgroundImageError:
                                                  provider != null
                                                      ? (_, __) {}
                                                      : null,
                                              child: provider == null
                                                  ? Text(
                                                      title.isNotEmpty
                                                          ? title[0]
                                                              .toUpperCase()
                                                          : '?',
                                                    )
                                                  : null,
                                            ),
                                            title: Text(
                                              title,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            subtitle: Text(
                                              chat.chatType,
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey[500],
                                              ),
                                            ),
                                            onChanged: (val) {
                                              setSheetState(() {
                                                if (val == true) {
                                                  initialSelected
                                                      .add(chat.chatId);
                                                } else {
                                                  initialSelected
                                                      .remove(chat.chatId);
                                                }
                                              });
                                            },
                                          );
                                        },
                                      ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      );
    },
    );

    if (result != null && mounted) {
      setState(() {
        if (isIncluded) {
          _includedChatIds = result.toList();
          _excludedChatIds.removeWhere((id) => result.contains(id));
        } else {
          _excludedChatIds = result.toList();
          _includedChatIds.removeWhere((id) => result.contains(id));
        }
      });
    }
  }

  Future<void> _save() async {
    final l10n = context.l10n;
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('folders_name_required'))),
      );
      return;
    }

    final includedTypes = <String>[];
    if (_includePrivate) {
      includedTypes.add('private');
      includedTypes.add('saved');
    }
    if (_includeGroups) includedTypes.add('group');
    if (_includeChannels) includedTypes.add('channel');

    if (includedTypes.isEmpty && _includedChatIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.translate('folders_select_source_hint'))),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      final service = ChatFolderService();
      if (_isEditing) {
        final updated = widget.existingFolder!.copyWith(
          name: name,
          iconName: _iconName,
          includedTypes: includedTypes,
          includedChatIds: _includedChatIds,
          excludedChatIds: _excludedChatIds,
        );
        await service.updateFolder(updated);
      } else {
        final created = ChatFolder(
          id: 'folder_${DateTime.now().millisecondsSinceEpoch}',
          name: name,
          iconName: _iconName,
          includedTypes: includedTypes,
          includedChatIds: _includedChatIds,
          excludedChatIds: _excludedChatIds,
          order: service.folders.length,
        );
        await service.addFolder(created);
      }
      if (mounted) Navigator.of(context).pop();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final primary = Theme.of(context).colorScheme.primary;

    return SettingsFloatingScaffold(
      title: _isEditing
          ? l10n.translate('folders_edit_title')
          : l10n.translate('folders_new_folder'),
      padBodyTop: true,
      actions: [
        SettingsHeaderAction(
          icon: Icon(Icons.check, color: primary),
          tooltip: l10n.translate('save'),
          enabled: !_saving,
          onTap: _save,
        ),
      ],
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 12),
        children: [
          SettingsGroup(
            title: l10n.translate('folders_folder_name'),
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: TextField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    hintText: l10n.translate('folders_new_folder_name'),
                    border: InputBorder.none,
                  ),
                  textCapitalization: TextCapitalization.sentences,
                  autofocus: !_isEditing,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsGroup(
            title: l10n.translate('folders_icon_header'),
            children: [
              Padding(
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: FolderEditScreen.availableIcons.map((entry) {
                    final selected = _iconName == entry.name;
                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        HapticUtils.selection();
                        setState(() => _iconName = entry.name);
                      },
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: selected
                              ? primary.withValues(alpha: 0.16)
                              : Colors.grey.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? primary : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          entry.icon,
                          color: selected ? primary : Colors.grey[600],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsGroup(
            title: l10n.translate('folders_chat_types_header'),
            children: [
              CheckboxListTile(
                title: Text(l10n.translate('folders_type_private')),
                value: _includePrivate,
                onChanged: (val) =>
                    setState(() => _includePrivate = val ?? false),
              ),
              CheckboxListTile(
                title: Text(l10n.translate('folders_type_groups')),
                value: _includeGroups,
                onChanged: (val) =>
                    setState(() => _includeGroups = val ?? false),
              ),
              CheckboxListTile(
                title: Text(l10n.translate('folders_type_channels')),
                value: _includeChannels,
                onChanged: (val) =>
                    setState(() => _includeChannels = val ?? false),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsGroup(
            title: l10n.translate('folders_included_chats'),
            children: [
              ListTile(
                leading: Icon(Icons.add_circle_outline, color: primary),
                title: Text(l10n.translate('folders_add_chats')),
                trailing: Text(
                  '${_includedChatIds.length}',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                onTap: () => _pickChats(isIncluded: true),
              ),
              if (_includedChatIds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _includedChatIds
                        .map(
                          (id) => InputChip(
                            label: Text(_chatDisplayName(id)),
                            onDeleted: () => setState(
                              () => _includedChatIds.remove(id),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsGroup(
            title: l10n.translate('folders_excluded_chats'),
            children: [
              ListTile(
                leading: const Icon(Icons.remove_circle_outline, color: Colors.red),
                title: Text(l10n.translate('folders_exclude_chats')),
                trailing: Text(
                  '${_excludedChatIds.length}',
                  style: TextStyle(color: Colors.grey[600]),
                ),
                onTap: () => _pickChats(isIncluded: false),
              ),
              if (_excludedChatIds.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 6,
                    children: _excludedChatIds
                        .map(
                          (id) => InputChip(
                            label: Text(_chatDisplayName(id)),
                            onDeleted: () => setState(
                              () => _excludedChatIds.remove(id),
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton(
              onPressed: _saving ? null : _save,
              child: Text(l10n.translate('save')),
            ),
          ),
        ],
      ),
    );
  }
}
