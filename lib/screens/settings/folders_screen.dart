import 'package:flutter/material.dart';
import '../../l10n/app_localizations.dart';
import '../../models/chat_folder.dart';
import '../../services/chat_folder_service.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../../widgets/settings/settings_floating_header.dart';
import 'folder_edit_screen.dart';

/// Screen allowing the user to view, reorder, create, edit, and delete
/// chat folders. Folders sync across devices per account.
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

  IconData _getFolderIcon(ChatFolder folder) =>
      FolderEditScreen.iconForName(folder.iconName, folderId: folder.id);

  String _getFolderDescription(BuildContext context, ChatFolder folder) {
    final l10n = context.l10n;
    if (folder.id == 'all') {
      return l10n.translate('folders_all_chats_desc');
    }
    final types = folder.includedTypes;
    final parts = <String>[];
    if (types.contains('private') || types.contains('saved')) {
      parts.add(l10n.translate('folders_type_private'));
    }
    if (types.contains('group')) {
      parts.add(l10n.translate('folders_type_groups'));
    }
    if (types.contains('channel')) {
      parts.add(l10n.translate('folders_type_channels'));
    }
    if (folder.includedChatIds.isNotEmpty) {
      parts.add('+${folder.includedChatIds.length}');
    }
    if (folder.excludedChatIds.isNotEmpty) {
      parts.add('-${folder.excludedChatIds.length}');
    }
    if (parts.isEmpty) {
      return l10n.translate('folders_empty');
    }
    return parts.join(', ');
  }

  void _openFolderEditor([ChatFolder? existing]) {
    Navigator.push(
      context,
      SwipeBackPageRoute(
        builder: (_) => FolderEditScreen(existingFolder: existing),
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
              if (dialogCtx.mounted) Navigator.of(dialogCtx).pop();
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

    return SettingsFloatingScaffold(
      title: l10n.translate('folders_title'),
      padBodyTop: true,
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
                          l10n.translate('folders_reorder_hint'),
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
                        onTap: isSystemAll ? null : () => _openFolderEditor(folder),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (!isSystemAll)
                              PopupMenuButton<String>(
                                icon: const Icon(Icons.more_vert),
                                onSelected: (val) {
                                  if (val == 'edit') {
                                    _openFolderEditor(folder);
                                  } else if (val == 'delete') {
                                    _showDeleteFolderConfirmation(folder);
                                  }
                                },
                                itemBuilder: (context) => [
                                  PopupMenuItem(
                                    value: 'edit',
                                    child: ListTile(
                                      leading: const Icon(Icons.edit),
                                      title: Text(l10n.translate('folders_edit_title')),
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
        onPressed: () => _openFolderEditor(),
        child: const Icon(Icons.add),
      ),
    );
  }
}
