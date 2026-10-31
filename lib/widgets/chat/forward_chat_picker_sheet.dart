import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../services/chat_service.dart';
import '../../services/database/app_database.dart';
import '../../services/glass_toast_service.dart';
import '../common/peer_badges_widget.dart';
import '../../utils/image_utils.dart';

/// Bottom sheet for server-side forwarding of one or more messages to any chat
/// (including "Saved Messages"), with an optional `hideSender` toggle.
class ForwardChatPickerSheet extends StatefulWidget {
  final String fromChatId;
  final List<String> messageIds;
  final void Function(String targetChatId)? onForwarded;

  const ForwardChatPickerSheet({
    super.key,
    required this.fromChatId,
    required this.messageIds,
    this.onForwarded,
  });

  /// Shows the forward chat picker modal bottom sheet and returns `true` if
  /// messages were forwarded.
  static Future<bool?> show(
    BuildContext context, {
    required String fromChatId,
    required List<String> messageIds,
    void Function(String targetChatId)? onForwarded,
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => ForwardChatPickerSheet(
        fromChatId: fromChatId,
        messageIds: messageIds,
        onForwarded: onForwarded,
      ),
    );
  }

  @override
  State<ForwardChatPickerSheet> createState() => _ForwardChatPickerSheetState();
}

class _ForwardChatPickerSheetState extends State<ForwardChatPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<DbChat> _chats = [];
  bool _isLoading = true;
  bool _hideSender = false;
  String? _forwardingToChatId;

  @override
  void initState() {
    super.initState();
    _loadChats();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadChats() async {
    try {
      final localChats = await AppDatabase().getChats();
      if (mounted) {
        setState(() {
          _chats = localChats;
          _isLoading = false;
        });
      }
      if (localChats.isEmpty) {
        final res = await ChatService.getChats();
        if (res['success'] == true && res['chats'] is List<Chat> && mounted) {
          final fresh = await AppDatabase().getChats();
          if (mounted) {
            setState(() {
              _chats = fresh;
            });
          }
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _forwardToChat(DbChat targetChat) async {
    if (_forwardingToChatId != null) return;
    setState(() => _forwardingToChatId = targetChat.chatId);

    final res = await ChatService.forwardMessages(
      toChatId: targetChat.chatId,
      fromChatId: widget.fromChatId,
      messageIds: widget.messageIds,
      hideSender: _hideSender,
    );

    if (!mounted) return;
    setState(() => _forwardingToChatId = null);

    if (res['success'] == true) {
      final count = widget.messageIds.length;
      final label = count == 1
          ? 'Сообщение переслано в «${targetChat.chatType == 'saved' ? 'Избранное' : targetChat.name}»'
          : 'Переслано сообщений ($count) в «${targetChat.chatType == 'saved' ? 'Избранное' : targetChat.name}»';
      GlassToastService().show(
        context,
        label,
        iconWidget: const iconoir.ForwardMessage(
          width: 18,
          height: 18,
          color: Colors.white,
        ),
      );
      widget.onForwarded?.call(targetChat.chatId);
      Navigator.of(context).pop(true);
    } else {
      final errMsg = res['message']?.toString() ?? 'Ошибка пересылки';
      GlassToastService().show(context, errMsg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final query = _searchController.text.trim().toLowerCase();

    final filtered = _chats.where((c) {
      if (query.isEmpty) return true;
      final displayName =
          c.chatType == 'saved' ? 'избранное' : c.name.toLowerCase();
      final uname = (c.username ?? '').toLowerCase();
      return displayName.contains(query) || uname.contains(query);
    }).toList();

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: Container(
          height: MediaQuery.of(context).size.height * 0.74,
          decoration: BoxDecoration(
            color: (isDark ? const Color(0xFF1A1D24) : Colors.white)
                .withValues(alpha: 0.92),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
            border: Border(
              top: BorderSide(
                color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25),
              ),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: theme.colorScheme.onSurfaceVariant
                      .withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 12, 12, 8),
                child: Row(
                  children: [
                    iconoir.ForwardMessage(
                      width: 20,
                      height: 20,
                      color: theme.colorScheme.primary,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        widget.messageIds.length > 1
                            ? 'Переслать (${widget.messageIds.length})'
                            : 'Переслать сообщение',
                        style: const TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                    IconButton(
                      icon: iconoir.Xmark(
                        width: 20,
                        height: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    hintText: 'Поиск чата или контакта...',
                    prefixIcon: Padding(
                      padding: const EdgeInsets.all(12),
                      child: iconoir.Search(
                        width: 18,
                        height: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.55),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => setState(() => _hideSender = !_hideSender),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: _hideSender
                          ? theme.colorScheme.primary.withValues(alpha: 0.12)
                          : theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        iconoir.EyeClosed(
                          width: 18,
                          height: 18,
                          color: _hideSender
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Скрыть имя отправителя',
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 24,
                          child: Switch(
                            value: _hideSender,
                            onChanged: (v) => setState(() => _hideSender = v),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const Divider(height: 12),
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : filtered.isEmpty
                        ? Center(
                            child: Text(
                              'Чаты не найдены',
                              style: TextStyle(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          )
                        : ListView.builder(
                            itemCount: filtered.length,
                            itemBuilder: (context, index) {
                              final chat = filtered[index];
                              final isSaved = chat.chatType == 'saved';
                              final title =
                                  isSaved ? 'Избранное' : chat.name;
                              final isBusy =
                                  _forwardingToChatId == chat.chatId;

                              final validAvatar = getValidAvatarUrl(chat.avatarUrl);

                              return ListTile(
                                leading: isSaved
                                    ? CircleAvatar(
                                        radius: 21,
                                        backgroundColor:
                                            theme.colorScheme.primary,
                                        child: const iconoir.Bookmark(
                                          width: 20,
                                          height: 20,
                                          color: Colors.white,
                                        ),
                                      )
                                    : CircleAvatar(
                                        radius: 21,
                                        backgroundColor: theme
                                            .colorScheme.primary
                                            .withValues(alpha: 0.16),
                                        backgroundImage: validAvatar != null
                                            ? avatarImageProvider(chat.avatarUrl)
                                            : null,
                                        child: validAvatar == null
                                            ? Text(
                                                title.isNotEmpty
                                                    ? title.characters.first
                                                        .toUpperCase()
                                                    : '?',
                                                style: TextStyle(
                                                  color: theme
                                                      .colorScheme.primary,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              )
                                            : null,
                                      ),
                                title: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        title,
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
                                      verifiedIconSize: 15,
                                    ),
                                  ],
                                ),
                                subtitle: chat.username != null &&
                                        chat.username!.isNotEmpty
                                    ? Text(
                                        '@${chat.username}',
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: theme
                                              .colorScheme.onSurfaceVariant,
                                        ),
                                      )
                                    : null,
                                trailing: isBusy
                                    ? const SizedBox(
                                        width: 20,
                                        height: 20,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                        ),
                                      )
                                    : iconoir.SendDiagonal(
                                        width: 18,
                                        height: 18,
                                        color: theme.colorScheme.primary,
                                      ),
                                onTap: () => _forwardToChat(chat),
                              );
                            },
                          ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
