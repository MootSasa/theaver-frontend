import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/account_manager.dart';
import '../../services/chat_service.dart';
import '../../services/database/app_database.dart';
import '../../services/notification_settings_provider.dart';
import '../../services/unread_count_provider.dart';
import '../../utils/image_utils.dart';
import '../../widgets/common/adaptive_switch.dart';
import '../../widgets/common/peer_badges_widget.dart';
import '../../widgets/settings/settings_floating_header.dart';
import '../../widgets/settings/settings_group.dart';

/// Displays archived chats synced via Drift and the backend archive API,
/// allowing users to open chats, unarchive them, and toggle
/// keepArchivedUnmuted behavior.
class ArchivedChatsScreen extends StatefulWidget {
  final void Function(Chat chat)? onOpenChat;

  const ArchivedChatsScreen({
    super.key,
    this.onOpenChat,
  });

  @override
  State<ArchivedChatsScreen> createState() => _ArchivedChatsScreenState();
}

class _ArchivedChatsScreenState extends State<ArchivedChatsScreen> {
  final Set<String> _unarchivingIds = {};

  Chat _dbChatToChat(DbChat model, UnreadCountProvider unreadProvider) {
    final effectiveUnread = unreadProvider.hasAuthoritativeCount(model.chatId)
        ? unreadProvider.getCount(model.chatId)
        : model.unreadCount;
    return Chat(
      id: model.chatId,
      chatType: model.chatType,
      name: model.name.trim().isEmpty ? '?' : model.name,
      avatarUrl: model.avatarUrl,
      lastMessage: model.lastMessage,
      lastMessageTime: model.lastMessageTime,
      lastMessageType: model.lastMessageType,
      lastMessageIsRound: model.lastMessageIsRound,
      lastMessageFileUrl: model.lastMessageFileUrl,
      lastMessageGroupedId: model.lastMessageGroupedId,
      otherUserId: model.otherUserId,
      updatedAt: model.updatedAt,
      unreadCount: effectiveUnread,
      isOnline: model.isOnline,
      lastSeen: model.lastSeen,
      isPinned: model.isPinned,
      lastReadInboxMessageId: model.lastReadInboxMessageId,
      lastReadOutboxMessageId: model.lastReadOutboxMessageId,
      pinnedMessageId: model.pinnedMessageId,
      username: model.username,
      isPublic: model.isPublic,
      isBot: model.isBot,
      isVerified: model.isVerified,
      isArchived: true,
    );
  }

  Future<void> _unarchiveChat(Chat chat) async {
    if (_unarchivingIds.contains(chat.id)) return;
    setState(() => _unarchivingIds.add(chat.id));

    final uid = AccountManager().currentAccount?.userId;
    final db = AppDatabase(uid);
    try {
      await db.setChatArchived(chat.id, false);
      final res = await ChatService.unarchiveChat(chatId: chat.id);
      if (res['success'] != true) {
        await db.setChatArchived(chat.id, true);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                res['message']?.toString() ??
                    context.l10n.translate('archived_unarchive_error'),
              ),
            ),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n
                  .translate('archived_unarchived_toast')
                  .replaceAll('{name}', chat.name),
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _unarchivingIds.remove(chat.id));
      }
    }
  }

  Widget _buildLeadingAvatar(BuildContext context, Chat chat) {
    final provider =
        chat.avatarUrl != null && chat.avatarUrl!.isNotEmpty
            ? avatarImageProvider(chat.avatarUrl!)
            : null;
    if (provider != null) {
      return CircleAvatar(
        radius: 22,
        backgroundImage: provider,
      );
    }

    final primary = Theme.of(context).colorScheme.primary;
    Widget fallbackIcon;
    switch (chat.chatType) {
      case 'group':
        fallbackIcon = const iconoir.Group(color: Colors.white, width: 20, height: 20);
        break;
      case 'channel':
        fallbackIcon = const iconoir.Megaphone(color: Colors.white, width: 20, height: 20);
        break;
      default:
        fallbackIcon = const iconoir.ChatBubble(color: Colors.white, width: 20, height: 20);
    }
    return CircleAvatar(
      radius: 22,
      backgroundColor: primary.withValues(alpha: 0.85),
      child: fallbackIcon,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final uid = AccountManager().currentAccount?.userId;
    final db = AppDatabase(uid);
    final unreadProvider = context.watch<UnreadCountProvider>();
    final notifProvider = context.watch<NotificationSettingsProvider>();

    return SettingsFloatingScaffold(
      title: l10n.translate('archived_chats_title'),
      padBodyTop: true,
      body: StreamBuilder<List<DbChat>>(
        stream: db.watchArchivedChats(),
        builder: (context, snapshot) {
          final dbChats = snapshot.data ?? const <DbChat>[];
          final chats = dbChats
              .map((c) => _dbChatToChat(c, unreadProvider))
              .toList();

          if (snapshot.connectionState == ConnectionState.waiting &&
              chats.isEmpty) {
            return const Center(child: CircularProgressIndicator());
          }

          return ListView(
            padding: const EdgeInsets.only(top: 8, bottom: 24),
            children: [
              SettingsGroup(
                children: [
                  ListTile(
                    leading: Icon(
                      Icons.mark_chat_unread_outlined,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    title: Text(l10n.translate('notifications_keep_archived_unmuted')),
                    trailing: AdaptiveSwitch(
                      value: notifProvider.globalSettings.keepArchivedUnmuted,
                      onChanged: (val) {
                        notifProvider.updateGlobalSettings(
                          keepArchivedUnmuted: val,
                        );
                      },
                    ),
                  ),
                ],
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
                child: Text(
                  l10n.translate('notifications_keep_archived_unmuted_desc'),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
              ),
              const SizedBox(height: 8),
              if (chats.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 64,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      iconoir.Archive(
                        width: 56,
                        height: 56,
                        color: Colors.grey[500],
                      ),
                      const SizedBox(height: 16),
                      Text(
                        l10n.translate('archived_chats_empty'),
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        l10n.translate('archived_chats_empty_hint'),
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                      ),
                    ],
                  ),
                )
              else
                SettingsGroup(
                  title: l10n.translate('archived_chats_list_header'),
                  children: chats.map((chat) {
                    final isMuted = notifProvider.isChatMuted(
                      chat.id,
                      chatType: chat.chatType,
                    );
                    final hasUnread = chat.unreadCount > 0 || chat.unreadCount == -1;

                    return Dismissible(
                      key: ValueKey('archived_chat_${chat.id}'),
                      direction: DismissDirection.endToStart,
                      background: Container(
                        alignment: Alignment.centerRight,
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        color: Theme.of(context).colorScheme.primary,
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              l10n.translate('archived_unarchive_action'),
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(width: 8),
                            const iconoir.Archive(
                              width: 20,
                              height: 20,
                              color: Colors.white,
                            ),
                          ],
                        ),
                      ),
                      confirmDismiss: (_) async {
                        await _unarchiveChat(chat);
                        return false;
                      },
                      child: ListTile(
                        leading: _buildLeadingAvatar(context, chat),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                chat.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                            PeerBadgesRow(
                              isBot: chat.isBot,
                              isVerified: chat.isVerified,
                              verifiedIconSize: 14,
                            ),
                            if (isMuted) ...[
                              const SizedBox(width: 6),
                              iconoir.BellOff(
                                width: 14,
                                height: 14,
                                color: Colors.grey[500],
                              ),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          chat.lastMessage ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (hasUnread)
                              Container(
                                margin: const EdgeInsets.only(right: 8),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: isMuted
                                      ? Colors.grey
                                      : Theme.of(context).colorScheme.primary,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  chat.unreadCount > 0
                                      ? '${chat.unreadCount}'
                                      : '',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            IconButton(
                              tooltip: l10n.translate('archived_unarchive_action'),
                              icon: const Icon(Icons.unarchive_outlined),
                              onPressed: _unarchivingIds.contains(chat.id)
                                  ? null
                                  : () => _unarchiveChat(chat),
                            ),
                          ],
                        ),
                        onTap: () {
                          if (widget.onOpenChat != null) {
                            widget.onOpenChat!(chat);
                          }
                        },
                      ),
                    );
                  }).toList(),
                ),
            ],
          );
        },
      ),
    );
  }
}
