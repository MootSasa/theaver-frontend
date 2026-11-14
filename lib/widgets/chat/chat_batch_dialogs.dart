import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../models/community_models.dart';
import '../../screens/chat/channel_screen.dart';
import '../../screens/chat/group_chat_screen.dart';
import '../../screens/chat/private_chat_screen.dart';
import '../../screens/chat/system_notifications_screen.dart';
import '../../screens/community/community_screen.dart';
import '../../services/account_manager.dart';
import '../../services/archive_preferences_service.dart';
import '../../services/chat_folder_service.dart';
import '../../services/chat_service.dart';
import '../../services/community_service.dart';
import '../../services/database/app_database.dart';
import '../../services/notification_service.dart';
import '../../services/notification_settings_provider.dart';
import '../../services/tiling_layout_controller.dart';
import '../../services/unread_count_provider.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';
import '../common/adaptive_switch.dart';
import '../settings/settings_group.dart';

String _tr(
  BuildContext context,
  String key,
  String fallback, [
  Map<String, String>? params,
]) {
  final translated = AppLocalizations.of(context)?.translate(key, params);
  if (translated == null || translated.isEmpty || translated == key) {
    var result = fallback;
    params?.forEach((k, v) {
      result = result.replaceAll('{$k}', v);
    });
    return result;
  }
  return translated;
}

/// Shared dialogs, bottom sheets, drag payload builders, and chat navigation
/// helpers used by both `MainScreen` and `ArchivedChatsScreen`.
class ChatBatchDialogs {
  const ChatBatchDialogs._();

  static Future<bool> confirmDeleteChats(
    BuildContext context,
    List<Chat> chats,
  ) async {
    final deletable = chats.where((c) => c.chatType != 'saved').toList();
    if (deletable.isEmpty) return false;

    final String title;
    final String body;
    final String confirmLabel;

    if (deletable.length == 1) {
      final chat = deletable.first;
      if (chat.chatType == 'group') {
        title = _tr(context, 'chats_leave_group_title', 'Покинуть группу?');
        body = _tr(
          context,
          'chats_leave_group_confirm',
          'Вы покинете группу «${chat.name}» и она исчезнет из списка чатов.',
          {'name': chat.name},
        );
        confirmLabel = _tr(context, 'chats_leave_group_action', 'Покинуть');
      } else if (chat.chatType == 'channel') {
        title = _tr(context, 'chats_leave_channel_title', 'Покинуть канал?');
        body = _tr(
          context,
          'chats_leave_channel_confirm',
          'Вы отпишетесь от канала «${chat.name}».',
          {'name': chat.name},
        );
        confirmLabel = _tr(context, 'chats_leave_group_action', 'Покинуть');
      } else {
        title = _tr(context, 'chats_delete_private_title', 'Удалить чат?');
        body = _tr(
          context,
          'chats_delete_private_confirm',
          'Удалить переписку с «${chat.name}»?',
          {'name': chat.name},
        );
        confirmLabel = _tr(context, 'selection_delete', 'Удалить');
      }
    } else {
      final countStr = '${deletable.length}';
      title = _tr(
        context,
        'chats_delete_batch_title',
        'Удалить выбранные чаты ($countStr)?',
        {'count': countStr},
      );
      body = _tr(
        context,
        'chats_delete_batch_confirm',
        'Личные чаты будут удалены, а из выбранных групп и каналов будет выполнен выход.',
      );
      confirmLabel = _tr(context, 'selection_delete', 'Удалить');
    }

    final cancelLabel = _tr(context, 'common_cancel', 'Отмена');

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    return confirmed == true;
  }

  static Future<bool> executeClearHistory(
    BuildContext context,
    List<Chat> chats, {
    String? currentUserId,
    VoidCallback? onBeforeExecute,
  }) async {
    final clearable = chats.where((c) => c.chatType != 'community').toList();
    if (clearable.isEmpty) return false;

    final countStr = '${clearable.length}';
    final title =
        _tr(context, 'chats_clear_history_title', 'Очистить историю?');
    final body = _tr(
      context,
      'chats_clear_history_confirm',
      'Все сообщения в выбранных чатах ($countStr) будут безвозвратно удалены.',
      {'count': countStr},
    );
    final cancelLabel = _tr(context, 'common_cancel', 'Отмена');
    final confirmLabel =
        _tr(context, 'selection_clear_history', 'Очистить историю');
    final clearedToast =
        _tr(context, 'chats_history_cleared_toast', 'История очищена');

    UnreadCountProvider? unreadProvider;
    try {
      unreadProvider = context.read<UnreadCountProvider>();
    } catch (_) {}
    final messenger = ScaffoldMessenger.maybeOf(context);

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(cancelLabel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(confirmLabel),
          ),
        ],
      ),
    );

    if (confirmed != true) return false;
    onBeforeExecute?.call();

    final db = AppDatabase(currentUserId);
    final ids = clearable.map((c) => c.id).toList();
    for (final chat in clearable) {
      await ChatService.clearChatHistory(chatId: chat.id);
      await db.deleteMessagesForChat(chat.id);
      await db.refreshChatLastMessageFromDb(chat.id, allowClear: true);
      unreadProvider?.setCount(chat.id, 0);
    }
    await db.batchMarkAsRead(ids);

    messenger?.showSnackBar(SnackBar(content: Text(clearedToast)));
    return true;
  }

  static Future<bool> showAddToFolderSheet(
    BuildContext context,
    List<Chat> chats,
  ) async {
    if (chats.isEmpty) return false;
    final folderService = ChatFolderService();
    final customFolders = folderService.folders
        .where((f) => f.id != 'all' && f.id != 'communities')
        .toList();

    final Set<String> selectedFolderIds = {
      for (final folder in customFolders)
        if (chats.every((c) => folder.includedChatIds.contains(c.id))) folder.id,
    };

    final title = _tr(context, 'chats_add_to_folder_title', 'Добавить в папку');
    final emptyText = _tr(
      context,
      'chats_add_to_folder_empty',
      'Нет пользовательских папок',
    );
    final applyLabel = _tr(context, 'common_apply', 'Готово');
    final updatedToast =
        _tr(context, 'chats_folders_updated', 'Папки обновлены');
    final messenger = ScaffoldMessenger.maybeOf(context);

    final applied = await showModalBottomSheet<bool>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        title,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  if (customFolders.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 28,
                      ),
                      child: Text(
                        emptyText,
                        style: TextStyle(color: Colors.grey[500]),
                        textAlign: TextAlign.center,
                      ),
                    )
                  else ...[
                    ConstrainedBox(
                      constraints: const BoxConstraints(maxHeight: 340),
                      child: SingleChildScrollView(
                        child: SettingsGroup(
                          children: customFolders.map((folder) {
                            final checked =
                                selectedFolderIds.contains(folder.id);
                            return ListTile(
                              leading: iconoir.Folder(
                                width: 20,
                                height: 20,
                                color: Theme.of(context).colorScheme.primary,
                              ),
                              title: Text(
                                folder.name,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                              trailing: Checkbox(
                                value: checked,
                                onChanged: (_) {
                                  HapticUtils.selection();
                                  setSheetState(() {
                                    if (checked) {
                                      selectedFolderIds.remove(folder.id);
                                    } else {
                                      selectedFolderIds.add(folder.id);
                                    }
                                  });
                                },
                              ),
                              onTap: () {
                                HapticUtils.selection();
                                setSheetState(() {
                                  if (checked) {
                                    selectedFolderIds.remove(folder.id);
                                  } else {
                                    selectedFolderIds.add(folder.id);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => Navigator.of(sheetContext).pop(true),
                          child: Text(applyLabel),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );

    if (applied != true) return false;

    final chatIds = chats.map((c) => c.id).toSet();
    final updated = folderService.folders.map((folder) {
      if (folder.id == 'all' || folder.id == 'communities') {
        return folder;
      }
      final nextIncluded = folder.includedChatIds.toSet();
      final nextExcluded = folder.excludedChatIds.toSet();
      if (selectedFolderIds.contains(folder.id)) {
        nextIncluded.addAll(chatIds);
        nextExcluded.removeAll(chatIds);
      } else {
        nextIncluded.removeAll(chatIds);
      }
      return folder.copyWith(
        includedChatIds: nextIncluded.toList(),
        excludedChatIds: nextExcluded.toList(),
      );
    }).toList();

    await folderService.saveFolders(updated);
    messenger?.showSnackBar(SnackBar(content: Text(updatedToast)));
    return true;
  }

  static Future<void> showArchiveSettingsSheet(BuildContext context) async {
    final archivePrefs = ArchivePreferencesService();
    final sheetTitle = _tr(context, 'archive_settings', 'Настройки архива');
    final keepUnmutedTitle = _tr(
      context,
      'notifications_keep_archived_unmuted',
      'Не доставать чаты со звуком',
    );
    final keepUnmutedDesc = _tr(
      context,
      'archive_keep_unmuted_desc',
      'Чаты с включёнными уведомлениями останутся в архиве при получении новых сообщений.',
    );
    final hideAboveTitle = _tr(
      context,
      'archive_hide_above_list',
      'Скрыть над списком',
    );
    final hideAboveDesc = _tr(
      context,
      'archive_hide_above_list_desc',
      'Строка архива скроется из списка чатов. Потяните список вниз или откройте меню «⋮», чтобы войти в архив.',
    );

    await showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        return ListenableBuilder(
          listenable: archivePrefs,
          builder: (context, _) {
            NotificationSettingsProvider? notifProvider;
            try {
              notifProvider = context.watch<NotificationSettingsProvider>();
            } catch (_) {}

            final keepUnmuted =
                notifProvider?.globalSettings.keepArchivedUnmuted ?? false;

            return Padding(
              padding: const EdgeInsets.only(top: 12, bottom: 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        sheetTitle,
                        style: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SettingsGroup(
                    children: [
                      ListTile(
                        leading: Icon(
                          Icons.mark_chat_unread_outlined,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(keepUnmutedTitle),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            keepUnmutedDesc,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                        trailing: AdaptiveSwitch(
                          value: keepUnmuted,
                          onChanged: notifProvider == null
                              ? null
                              : (val) {
                                  notifProvider!.updateGlobalSettings(
                                    keepArchivedUnmuted: val,
                                  );
                                },
                        ),
                      ),
                      ListTile(
                        leading: iconoir.Archive(
                          width: 22,
                          height: 22,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        title: Text(hideAboveTitle),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text(
                            hideAboveDesc,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: Colors.grey[600],
                            ),
                          ),
                        ),
                        trailing: AdaptiveSwitch(
                          value: archivePrefs.isHiddenAboveList,
                          onChanged: (val) {
                            archivePrefs.setHiddenAboveList(val);
                          },
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  static DraggingChatPayload createDragPayload(
    BuildContext context,
    Chat chat,
    Rect initialRect,
    Offset globalPos,
  ) {
    final account = AccountManager().currentAccount;
    final effectiveSavedAvatar =
        chat.avatarUrl ?? account?.avatarUrl ?? account?.localAvatarPath;
    final displayName = chat.chatType == 'saved'
        ? _tr(context, 'chat_saved_messages', 'Избранное')
        : (chat.chatType == 'system' && chat.name.isEmpty
            ? _tr(context, 'system_notifications_title', 'Системные уведомления')
            : chat.name);

    return DraggingChatPayload(
      chatId: chat.id,
      chatType: chat.chatType,
      chatName: displayName,
      avatarUrl: chat.chatType == 'saved' ? effectiveSavedAvatar : chat.avatarUrl,
      otherUserId: chat.otherUserId,
      otherUserOnline: chat.isOnline,
      otherUserLastSeen: DateTimeUtils.parseUtcDateTime(chat.lastSeen),
      initialGlobalRect: initialRect,
      currentGlobalPos: globalPos,
    );
  }

  static void openChat(
    BuildContext context,
    Chat chat, {
    bool inAdjacentTile = false,
    String? currentUserId,
    List<Community> communities = const [],
    VoidCallback? onCommunityChanged,
    VoidCallback? onReturned,
  }) {
    final uid = currentUserId ?? AccountManager().currentAccount?.userId;
    if (chat.unreadCount == -1) {
      AppDatabase(uid).updateUnreadCount(chat.id, 0);
      try {
        context.read<UnreadCountProvider>().setCount(chat.id, 0);
      } catch (_) {}
    }

    final account = AccountManager().currentAccount;
    final effectiveSavedAvatar =
        chat.avatarUrl ?? account?.avatarUrl ?? account?.localAvatarPath;
    final displayName = chat.chatType == 'saved'
        ? _tr(context, 'chat_saved_messages', 'Избранное')
        : (chat.chatType == 'system' && chat.name.isEmpty
            ? _tr(context, 'system_notifications_title', 'Системные уведомления')
            : chat.name);
    final effectiveAvatar =
        chat.chatType == 'saved' ? effectiveSavedAvatar : chat.avatarUrl;

    if (chat.chatType == 'community') {
      final rawCommId = chat.otherUserId ??
          (chat.id.startsWith('community_')
              ? chat.id.substring('community_'.length)
              : chat.id);
      final comm = communities.firstWhere(
        (c) => c.id == rawCommId,
        orElse: () =>
            CommunityService.getCachedCommunity(rawCommId) ??
            Community(
              id: rawCommId,
              name: chat.name,
              description: chat.lastMessage ?? '',
              avatarUrl: chat.avatarUrl,
              createdAt: DateTime.now(),
            ),
      );
      if (comm.isMember) {
        CommunityService.cacheCommunity(comm);
      }
      if (!TilingLayoutController.instance.isWorkspaceMounted) {
        Navigator.push(
          context,
          SwipeBackPageRoute(
            builder: (_) => CommunityScreen(
              community: comm,
              onCommunityJoined: onCommunityChanged != null
                  ? (_) => onCommunityChanged()
                  : null,
              onCommunityLeft: onCommunityChanged,
            ),
          ),
        ).then((_) {
          onCommunityChanged?.call();
          onReturned?.call();
        });
        return;
      }
    }

    if (TilingLayoutController.instance.isWorkspaceMounted) {
      if (inAdjacentTile) {
        TilingLayoutController.instance.openChatInAdjacentTile(
          chatId: chat.id,
          chatType: chat.chatType,
          chatName: displayName,
          avatarUrl: effectiveAvatar,
          otherUserId: chat.otherUserId,
          otherUserOnline: chat.isOnline,
          otherUserLastSeen: DateTimeUtils.parseUtcDateTime(chat.lastSeen),
        );
      } else {
        TilingLayoutController.instance.openChatInActiveTile(
          chatId: chat.id,
          chatType: chat.chatType,
          chatName: displayName,
          avatarUrl: effectiveAvatar,
          otherUserId: chat.otherUserId,
          otherUserOnline: chat.isOnline,
          otherUserLastSeen: DateTimeUtils.parseUtcDateTime(chat.lastSeen),
        );
      }
      return;
    }

    UnreadCountProvider? unreadProvider;
    try {
      unreadProvider = context.read<UnreadCountProvider>();
      unreadProvider.openChat(chat.id);
    } catch (_) {}
    NotificationService().addActiveChat(chat.id);

    void handleReturn() {
      unreadProvider?.closeChat(chat.id);
      NotificationService().removeActiveChat(chat.id);
      onReturned?.call();
    }

    switch (chat.chatType) {
      case 'private':
        Navigator.push(
          context,
          SwipeBackPageRoute(
            builder: (_) => PrivateChatScreen(
              chatId: chat.id,
              otherUserName: chat.name,
              otherUserAvatar: chat.avatarUrl,
              otherUserOnline: chat.isOnline,
              otherUserLastSeen:
                  DateTimeUtils.parseUtcDateTime(chat.lastSeen),
              otherUserId: chat.otherUserId,
            ),
          ),
        ).then((_) => handleReturn());
        break;
      case 'saved':
        Navigator.push(
          context,
          SwipeBackPageRoute(
            builder: (_) => PrivateChatScreen(
              chatId: chat.id,
              otherUserName: displayName,
              otherUserAvatar: effectiveSavedAvatar,
            ),
          ),
        ).then((_) => handleReturn());
        break;
      case 'system':
        Navigator.push(
          context,
          SwipeBackPageRoute(
            builder: (_) => SystemNotificationsScreen(
              chatId: chat.id,
              chatName: displayName,
            ),
          ),
        ).then((_) => handleReturn());
        break;
      case 'group':
        Navigator.push(
          context,
          SwipeBackPageRoute(
            builder: (_) => GroupChatScreen(
              chatId: chat.id,
              groupName: chat.name,
              groupAvatar: chat.avatarUrl,
            ),
          ),
        ).then((_) => handleReturn());
        break;
      case 'channel':
        Navigator.push(
          context,
          SwipeBackPageRoute(
            builder: (_) => ChannelScreen(
              channelId: chat.id,
              channelName: chat.name,
              channelAvatar: chat.avatarUrl,
            ),
          ),
        ).then((_) => handleReturn());
        break;
    }
  }
}
