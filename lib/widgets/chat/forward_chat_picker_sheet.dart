import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../services/chat_service.dart';
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
    return showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
    return showModalBottomSheet<DbChat>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
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
      final displayTarget =
          targetChat.chatType == 'saved' ? 'Избранное' : targetChat.name;
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
    final blurFilter = style.getBlurFilter(sigma: 22.0);
    final query = _searchController.text.trim().toLowerCase();

    final filtered = _chats.where((c) {
      if (query.isEmpty) return true;
      final displayName =
          c.chatType == 'saved' ? 'избранное' : c.name.toLowerCase();
      final uname = (c.username ?? '').toLowerCase();
      return displayName.contains(query) || uname.contains(query);
    }).toList();

    Widget sheetContainer = Container(
      height: MediaQuery.of(context).size.height * 0.76,
      decoration: BoxDecoration(
        color: style.overlayFill,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border(
          top: BorderSide(color: palette.divider, width: 0.6),
        ),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: [
            const SizedBox(height: 10),
            Container(
              width: 38,
              height: 4,
              decoration: BoxDecoration(
                color: palette.onSurface.withValues(alpha: 0.22),
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
                    color: palette.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      widget.returnTargetOnly
                          ? 'Выбрать получателя'
                          : (widget.messageIds.length > 1
                              ? 'Переслать (${widget.messageIds.length})'
                              : 'Переслать сообщение'),
                      style: TextStyle(
                        color: palette.onSurface,
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: iconoir.Xmark(
                      width: 20,
                      height: 20,
                      color: palette.subtext,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
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
                            final title = isSaved ? 'Избранное' : chat.name;
                            final isBusy = _forwardingToChatId == chat.chatId;
                            final validAvatar =
                                getValidAvatarUrl(chat.avatarUrl);

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
      ),
    );

    if (blurFilter != null) {
      sheetContainer = BackdropFilter(
        filter: blurFilter,
        child: sheetContainer,
      );
    }

    return ClipRRect(
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      child: sheetContainer,
    );
  }
}
