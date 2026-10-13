import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../l10n/app_localizations.dart';
import '../../models/chat_folder.dart';
import '../../services/chat_folder_service.dart';
import '../../utils/haptic_utils.dart';

/// Screen allowing the user to view, reorder, create, rename, and delete
/// custom chat folders. Folders sync across devices per account.
class FoldersScreen extends StatefulWidget {
  const FoldersScreen({Key? key}) : super(key: key);

  @override
  State<FoldersScreen> createState() => _FoldersScreenState();
}

class _FoldersScreenState extends State<FoldersScreen> {
  final ChatFolderService _folderService = ChatFolderService();

  @override
  void initState() {
    super.initState();
    _folderService.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _folderService.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  IconData _getFolderIcon(ChatFolder folder) {
    switch (folder.id) {
      case 'all':
        return Icons.chat_bubble_outline;
      case 'personal':
        return Icons.person_outline;
      case 'groups':
        return Icons.group_outlined;
      case 'channels':
        return Icons.campaign_outlined;
      default:
        return Icons.folder_outlined;
    }
  }

  String _getFolderDescription(BuildContext context, ChatFolder folder) {
    if (folder.id == 'all') {
      return 'Все чаты и каналы';
    }
    final types = folder.includedTypes;
    final parts = <String>[];
    if (types.contains('private') || types.contains('saved')) parts.add('Личные');
    if (types.contains('group')) parts.add('Группы');
    if (types.contains('channel')) parts.add('Каналы');
    if (parts.isEmpty) {
      return folder.includedChatIds.isNotEmpty
          ? '${folder.includedChatIds.length} выбранных чатов'
          : 'Пустая папка';
    }
    return parts.join(', ');
  }

  void _showAddFolderDialog() {
    final l10n = context.l10n;
    final nameController = TextEditingController();
    bool includePrivate = true;
    bool includeGroups = false;
    bool includeChannels = false;

    showDialog(
      context: context,
      builder: (dialogCtx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(l10n.translate('folders_new_folder')),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: l10n.translate('folders_folder_name'),
                    hintText: 'Например, Работа или Учёба',
                  ),
                  autofocus: true,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Включить типы чатов:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                ),
                CheckboxListTile(
                  title: const Text('Личные чаты'),
                  value: includePrivate,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) =>
                      setDialogState(() => includePrivate = val ?? false),
                ),
                CheckboxListTile(
                  title: const Text('Группы'),
                  value: includeGroups,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) =>
                      setDialogState(() => includeGroups = val ?? false),
                ),
                CheckboxListTile(
                  title: const Text('Каналы'),
                  value: includeChannels,
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  onChanged: (val) =>
                      setDialogState(() => includeChannels = val ?? false),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogCtx).pop(),
              child: Text(l10n.translate('folders_cancel')),
            ),
            ElevatedButton(
              onPressed: () async {
                final folderName = nameController.text.trim();
                if (folderName.isEmpty) return;

                final includedTypes = <String>[];
                if (includePrivate) {
                  includedTypes.add('private');
                  includedTypes.add('saved');
                }
                if (includeGroups) includedTypes.add('group');
                if (includeChannels) includedTypes.add('channel');

                final newFolder = ChatFolder(
                  id: 'folder_${DateTime.now().millisecondsSinceEpoch}',
                  name: folderName,
                  iconName: 'folder',
                  includedTypes: includedTypes,
                  order: _folderService.folders.length,
                );

                await _folderService.addFolder(newFolder);
                if (context.mounted) {
                  Navigator.of(dialogCtx).pop();
                }
              },
              child: Text(l10n.translate('folders_add')),
            ),
          ],
        ),
      ),
    );
  }

  void _showRenameFolderDialog(ChatFolder folder) {
    final l10n = context.l10n;
    final nameController = TextEditingController(text: folder.name);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l10n.translate('folders_rename_folder')),
        content: TextField(
          controller: nameController,
          decoration: InputDecoration(
            hintText: l10n.translate('folders_new_folder_name'),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(l10n.translate('folders_cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              final newName = nameController.text.trim();
              if (newName.isNotEmpty && newName != folder.name) {
                await _folderService.updateFolder(folder.copyWith(name: newName));
              }
              if (context.mounted) Navigator.of(dialogCtx).pop();
            },
            child: Text(l10n.translate('folders_rename')),
          ),
        ],
      ),
    );
  }

  void _showDeleteFolderConfirmation(ChatFolder folder) {
    final l10n = context.l10n;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l10n.translate('folders_delete_folder')),
        content: Text(
          l10n
              .translate('folders_delete_confirm')
              .replaceAll('{folder}', folder.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(l10n.translate('folders_cancel')),
          ),
          ElevatedButton(
            onPressed: () async {
              await _folderService.removeFolder(folder.id);
              if (context.mounted) Navigator.of(dialogCtx).pop();
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: Text(l10n.translate('folders_delete')),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final folders = _folderService.folders;

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.translate('folders_title')),
      ),
      body: folders.isEmpty
          ? Center(
              child: Text(
                l10n.translate('folders_empty'),
                textAlign: TextAlign.center,
              ),
            )
          : Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, size: 16, color: Colors.grey[600]),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Зажмите и перетаскивайте папки, чтобы изменить их порядок на главном экране.',
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: ReorderableListView.builder(
                    itemCount: folders.length,
                    onReorder: (oldIndex, newIndex) {
                      HapticUtils.selection();
                      _folderService.reorderFolders(oldIndex, newIndex);
                    },
                    itemBuilder: (context, index) {
                      final folder = folders[index];
                      final isSystemAll = folder.id == 'all';

                      return ListTile(
                        key: ValueKey(folder.id),
                        leading: Icon(
                          _getFolderIcon(folder),
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(
                          folder.name,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(
                          _getFolderDescription(context, folder),
                          style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isSystemAll)
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert),
                                onSelected: (val) {
                                  if (val == 'rename') {
                                    _showRenameFolderDialog(folder);
                                  } else if (val == 'delete') {
                                    _showDeleteFolderConfirmation(folder);
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'rename',
                                    child: ListTile(
                                      leading: const Icon(Icons.edit),
                                      title: Text(l10n.translate('folders_rename')),
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'delete',
                                    child: ListTile(
                                      leading: const Icon(Icons.delete, color: Colors.red),
                                      title: Text(
                                        l10n.translate('folders_delete'),
                                        style: const TextStyle(color: Colors.red),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ReorderableDragStartListener(
                              index: index,
                              child: const Padding(
                                padding: EdgeInsets.all(8.0),
                                child: Icon(Icons.drag_handle, color: Colors.grey),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddFolderDialog,
        child: const Icon(Icons.add),
      ),
    );
  }
}
