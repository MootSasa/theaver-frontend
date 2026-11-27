import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../services/chat_service.dart';
import '../../services/contacts_service.dart';
import '../../services/database/app_database.dart';
import '../../services/glass_toast_service.dart';
import '../../utils/image_utils.dart';
import '../common/peer_badges_widget.dart';
import '../design_system/theav_design_system.dart';

/// Bottom sheet for server-side forwarding of one or more messages to any chat
/// (including "Saved Messages"), with `hideSender` / `hideCaption` toggles and
/// optional staged-in-chat or recipient-only picking modes.
class ForwardChatPickerSheet extends StatefulWidget {
  final String fromChatId;
  final List<String> messageIds;
  final void Function(String targetChatId)? onForwarded;
  final void Function({required bool hideSender, required bool hideCaption})?
      onStageInCurrentChat;
  final bool returnTargetOnly;

  const ForwardChatPickerSheet({
    super.key,
    required this.fromChatId,
    required this.messageIds,
    this.onForwarded,
    this.onStageInCurrentChat,
    this.returnTargetOnly = false,
  });

  /// Shows the forward chat picker modal bottom sheet and returns `true` if
  /// messages were forwarded (or staged in current chat).
  static Future<bool?> show(
    BuildContext context, {
    required String fromChatId,
    required List<String> messageIds,
    void Function(String targetChatId)? onForwarded,
    void Function({required bool hideSender, required bool hideCaption})?
        onStageInCurrentChat,
  }) {
    return showTheavModalSheet<bool>(
      context: context,
      title: messageIds.length > 1
          ? 'Переслать (${messageIds.length})'
          : 'Переслать сообщение',
      showCloseButton: true,
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 14),
      builder: (ctx) => ForwardChatPickerSheet(
        fromChatId: fromChatId,
        messageIds: messageIds,
        onForwarded: onForwarded,
        onStageInCurrentChat: onStageInCurrentChat,
      ),
    );
  }

  /// Picks a target chat without sending immediately (e.g. changing recipient).
  static Future<DbChat?> pickTargetChat(
    BuildContext context, {
    required String fromChatId,
    required int messageCount,
  }) {
    return showTheavModalSheet<DbChat>(
      context: context,
      title: 'Выбрать получателя',
      showCloseButton: true,
      padding: const EdgeInsets.fromLTRB(0, 6, 0, 14),
      builder: (ctx) => ForwardChatPickerSheet(
        fromChatId: fromChatId,
        messageIds: List<String>.filled(messageCount, ''),
        returnTargetOnly: true,
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
  bool _hideCaption = false;
  String? _forwardingToChatId;

  @override
  void initState() {
    super.initState();
    ContactsService.revisionNotifier.addListener(_onContactsRevisionChanged);
    _loadChats();
  }

  void _onContactsRevisionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    ContactsService.revisionNotifier.removeListener(_onContactsRevisionChanged);
    _searchController.dispose();
    super.dispose();
  }

  bool _isPrivateHumanChat(DbChat chat) =>
      chat.chatType == 'private' && !chat.isBot;

  String _resolvedChatTitle(DbChat chat) {
    if (chat.chatType == 'saved') return 'Избранное';
    if (_isPrivateHumanChat(chat)) {
      return ContactsService.resolvePeerName(
        chat.otherUserId,
        chat.name,
        isBot: chat.isBot,
      );
    }
    return chat.name;
  }

  String? _resolvedChatAvatar(DbChat chat) {
    if (_isPrivateHumanChat(chat)) {
      return ContactsService.resolvePeerAvatarUrl(
        chat.otherUserId,
        chat.avatarUrl,
        isBot: chat.isBot,
      );
    }
    return chat.avatarUrl;
  }

  Future<void> _loadChats() async {
    try {
      bool isAllowedTarget(DbChat c) =>
          !(c.chatType == 'system' &&
              (c.otherUserId == null || c.otherUserId!.isEmpty));
      final localChats =
          (await AppDatabase().getChats()).where(isAllowedTarget).toList();
      if (mounted) {
        setState(() {
          _chats = localChats;
          _isLoading = false;
        });
      }
      if (localChats.isEmpty) {
        final res = await ChatService.getChats();
        if (res['success'] == true && res['chats'] is List<Chat> && mounted) {
          final fresh =
              (await AppDatabase().getChats()).where(isAllowedTarget).toList();
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
    if (widget.returnTargetOnly) {
      Navigator.of(context).pop(targetChat);
      return;
    }
    if (targetChat.chatId == widget.fromChatId &&
        widget.onStageInCurrentChat != null) {
      widget.onStageInCurrentChat!(
        hideSender: _hideSender,
        hideCaption: _hideCaption,
      );
      Navigator.of(context).pop(true);
      return;
    }

    if (_forwardingToChatId != null) return;
    setState(() => _forwardingToChatId = targetChat.chatId);

    final res = await ChatService.forwardMessages(
      toChatId: targetChat.chatId,
      fromChatId: widget.fromChatId,
      messageIds: widget.messageIds,
      hideSender: _hideSender,
      hideCaption: _hideCaption,
    );

    if (!mounted) return;
    setState(() => _forwardingToChatId = null);

    if (res['success'] == true) {
      final count = widget.messageIds.length;
      final displayTarget = _resolvedChatTitle(targetChat);
      final label = count == 1
          ? 'Сообщение переслано в «$displayTarget»'
          : 'Переслано сообщений ($count) в «$displayTarget»';
      GlassToastService().show(
        context,
        label,
        iconWidget: iconoir.ForwardMessage(
          width: 18,
          height: 18,
          color: context.theav.onSurface,
        ),
      );
      widget.onForwarded?.call(targetChat.chatId);
      Navigator.of(context).pop(true);
    } else {
      final errMsg = res['message']?.toString() ?? 'Ошибка пересылки';
      GlassToastService().showError(context, errMsg);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final query = _searchController.text.trim().toLowerCase();

    final filtered = _chats.where((c) {
      if (query.isEmpty) return true;
      final resolvedName = _resolvedChatTitle(c).toLowerCase();
      final rawName =
          c.chatType == 'saved' ? 'избранное' : c.name.toLowerCase();
      final uname = (c.username ?? '').toLowerCase();
      return resolvedName.contains(query) ||
          rawName.contains(query) ||
          uname.contains(query);
    }).toList();

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.64,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TheavInsetGroup(
              margin: EdgeInsets.zero,
              children: [
                TheavInlineTextField(
                  controller: _searchController,
                  placeholder: 'Поиск чата или контакта...',
                  prefix: iconoir.Search(
                    width: 18,
                    height: 18,
                    color: palette.subtext,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
            if (!widget.returnTargetOnly) ...[
              const SizedBox(height: 8),
              TheavInsetGroup(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                children: [
                  TheavListRow(
                    leading: iconoir.EyeClosed(
                      width: 18,
                      height: 18,
                      color: _hideSender ? palette.primary : palette.subtext,
                    ),
                    title: 'Скрыть имя отправителя',
                    trailing: TheavSwitch(
                      value: _hideSender,
                      onChanged: (v) => setState(() => _hideSender = v),
                    ),
                    onTap: () => setState(() => _hideSender = !_hideSender),
                  ),
                  TheavListRow(
                    leading: iconoir.TextBox(
                      width: 18,
                      height: 18,
                      color: _hideCaption ? palette.primary : palette.subtext,
                    ),
                    title: 'Скрыть подпись',
                    trailing: TheavSwitch(
                      value: _hideCaption,
                      onChanged: (v) => setState(() => _hideCaption = v),
                    ),
                    onTap: () => setState(() => _hideCaption = !_hideCaption),
                  ),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : filtered.isEmpty
                      ? Center(
                          child: Text(
                            'Чаты не найдены',
                            style: TextStyle(color: palette.subtext),
                          ),
                        )
                      : ListView.builder(
                          itemCount: filtered.length,
                          itemBuilder: (context, index) {
                            final chat = filtered[index];
                            final isSaved = chat.chatType == 'saved';
                            final isCurrent = chat.chatId == widget.fromChatId;
                            final title = _resolvedChatTitle(chat);
                            final isBusy = _forwardingToChatId == chat.chatId;
                            final resolvedAvatar = _resolvedChatAvatar(chat);
                            final validAvatar =
                                getValidAvatarUrl(resolvedAvatar);
                            final avatarProvider = validAvatar != null
                                ? avatarImageProvider(resolvedAvatar)
                                : null;

                            return ListTile(
                              leading: isSaved
                                  ? CircleAvatar(
                                      radius: 21,
                                      backgroundColor: palette.primary,
                                      child: iconoir.Bookmark(
                                        width: 20,
                                        height: 20,
                                        color: palette.onPrimary,
                                      ),
                                    )
                                  : CircleAvatar(
                                      radius: 21,
                                      backgroundColor: palette.primary
                                          .withValues(alpha: 0.16),
                                      backgroundImage: avatarProvider,
                                      onBackgroundImageError:
                                          avatarProvider != null
                                              ? (_, __) {}
                                              : null,
                                      child: avatarProvider == null
                                          ? Text(
                                              title.isNotEmpty
                                                  ? title.characters.first
                                                      .toUpperCase()
                                                  : '?',
                                              style: TextStyle(
                                                color: palette.primary,
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
                                      style: TextStyle(
                                        color: palette.onSurface,
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
                              subtitle: (isCurrent &&
                                      widget.onStageInCurrentChat != null)
                                  ? Text(
                                      'Прикрепить над строкой ввода',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: palette.primary,
                                      ),
                                    )
                                  : (chat.username != null &&
                                          chat.username!.isNotEmpty
                                      ? Text(
                                          '@${chat.username}',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: palette.subtext,
                                          ),
                                        )
                                      : null),
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
                                      color: palette.primary,
                                    ),
                              onTap: () => _forwardToChat(chat),
                            );
                          },
                        ),
            ),
          ],
        ),
      );
    }
  }
