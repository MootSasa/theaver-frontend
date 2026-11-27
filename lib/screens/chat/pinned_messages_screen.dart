import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../services/chat_service.dart';
import '../../services/contacts_service.dart';
import '../../services/database/app_database.dart';
import '../../services/glass_toast_service.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/settings/settings_floating_header.dart';

/// Displays all pinned messages in a chat/group/channel with tap-to-jump and
/// optional individual unpin / unpin-all actions.
class PinnedMessagesScreen extends StatefulWidget {
  final String chatId;
  final String chatTitle;
  final bool canPinMessages;
  final List<Message> initialPinnedMessages;

  const PinnedMessagesScreen({
    super.key,
    required this.chatId,
    required this.chatTitle,
    this.canPinMessages = false,
    this.initialPinnedMessages = const [],
  });

  @override
  State<PinnedMessagesScreen> createState() => _PinnedMessagesScreenState();
}

class _PinnedMessagesScreenState extends State<PinnedMessagesScreen> {
  List<Message> _pinned = [];
  bool _loading = true;
  bool _mutating = false;

  @override
  void initState() {
    super.initState();
    ContactsService.revisionNotifier.addListener(_onContactsRevisionChanged);
    _pinned = List<Message>.from(widget.initialPinnedMessages);
    _loadPinned();
  }

  @override
  void dispose() {
    ContactsService.revisionNotifier.removeListener(_onContactsRevisionChanged);
    super.dispose();
  }

  void _onContactsRevisionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadPinned() async {
    try {
      final fetched = await ChatService.getPinnedMessages(chatId: widget.chatId);
      if (fetched.isNotEmpty) {
        if (mounted) {
          setState(() {
            _pinned = fetched;
            _loading = false;
          });
        }
        return;
      }
      // Fallback to local Drift cache using stored pinnedMessageIds
      final db = AppDatabase();
      final dbChat = await db.getChat(widget.chatId);
      if (dbChat != null) {
        final chat = Chat.fromDbChat(dbChat);
        final targetIds = chat.pinnedMessageIds.map((e) => e.toString()).toSet();
        if (targetIds.isNotEmpty) {
          final localMsgs = await db.getMessages(widget.chatId, limit: 200);
          final matched = localMsgs
              .map((m) => Message.fromDbMessage(m))
              .where((m) => targetIds.contains(m.id))
              .toList();
          if (mounted && matched.isNotEmpty) {
            setState(() {
              _pinned = matched;
              _loading = false;
            });
            return;
          }
        }
      }
    } catch (_) {}
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  Future<void> _unpinOne(Message msg) async {
    if (_mutating) return;
    setState(() => _mutating = true);
    final res = await ChatService.unpinMessage(
      chatId: widget.chatId,
      messageId: msg.id,
    );
    if (!mounted) return;
    setState(() => _mutating = false);
    if (res['success'] == true) {
      setState(() {
        _pinned.removeWhere((m) => m.id == msg.id);
      });
      GlassToastService().show(context, 'Сообщение откреплено');
      if (_pinned.isEmpty && mounted) {
        Navigator.of(context).pop();
      }
    } else {
      GlassToastService().showError(
        context,
        res['message']?.toString() ?? 'Не удалось открепить сообщение',
      );
    }
  }

  Future<void> _unpinAll() async {
    if (_pinned.isEmpty || _mutating) return;
    final confirmed = await showTheavDialog<bool>(
      context: context,
      title: 'Открепить все сообщения?',
      message:
          'Все закреплённые сообщения (${_pinned.length}) будут откреплены в этом чате.',
      actions: const [
        TheavDialogAction<bool>(label: 'Отмена', result: false),
        TheavDialogAction<bool>(
          label: 'Открепить все',
          result: true,
          isDestructive: true,
        ),
      ],
    );
    if (confirmed != true || !mounted) return;

    setState(() => _mutating = true);
    final ok = await ChatService.unpinAllMessages(chatId: widget.chatId);
    if (!mounted) return;
    setState(() => _mutating = false);
    if (ok) {
      setState(() => _pinned.clear());
      GlassToastService().show(context, 'Все сообщения откреплены');
      Navigator.of(context).pop();
    } else {
      GlassToastService().showError(
        context,
        'Не удалось открепить сообщения',
      );
    }
  }

  String _describeMessage(Message msg) {
    final trimmed = msg.content.trim();
    if (trimmed.isNotEmpty) return trimmed;
    switch (msg.messageType) {
      case 'image':
      case 'photo':
        return 'Фотография';
      case 'video':
        return msg.isRound ? 'Видеосообщение' : 'Видео';
      case 'voice':
        return 'Голосовое сообщение';
      case 'audio':
        return 'Аудиозапись';
      case 'poll':
        return 'Опрос';
      case 'file':
      case 'document':
        return msg.fileName ?? 'Документ';
      default:
        return 'Сообщение';
    }
  }

  Widget _iconForMessage(Message msg, TheavPalette palette) {
    switch (msg.messageType) {
      case 'image':
      case 'photo':
        return iconoir.MediaImage(width: 20, height: 20, color: palette.primary);
      case 'video':
        return iconoir.VideoCamera(width: 20, height: 20, color: palette.primary);
      case 'voice':
      case 'audio':
        return iconoir.Microphone(width: 20, height: 20, color: palette.primary);
      case 'poll':
        return iconoir.StatsReport(width: 20, height: 20, color: palette.primary);
      case 'file':
      case 'document':
        return iconoir.Page(width: 20, height: 20, color: palette.primary);
      default:
        return iconoir.Pin(width: 20, height: 20, color: palette.primary);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final topClearance = SettingsFloatingHeader.topClearanceOf(context);

    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          if (_loading && _pinned.isEmpty)
            const Center(child: CircularProgressIndicator())
          else if (_pinned.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    iconoir.Pin(
                      width: 44,
                      height: 44,
                      color: palette.subtext.withValues(alpha: 0.55),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Нет закреплённых сообщений',
                      style: TextStyle(
                        color: palette.onSurface,
                        fontSize: 16.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            )
          else
            ListView(
              padding: EdgeInsets.fromLTRB(0, topClearance + 8, 0, 28),
              children: [
                TheavInsetGroup(
                  header: 'Закреплено: ${_pinned.length}',
                  children: _pinned.map((msg) {
                    final rawSender = msg.senderName.trim().isNotEmpty
                        ? msg.senderName.trim()
                        : widget.chatTitle;
                    final sender = (msg.isChannelOrPersonaAuthored ||
                            msg.isMirroredChannelPost)
                        ? msg.resolveEffectiveAuthorTitle(
                            chatName: widget.chatTitle,
                          )
                        : ContactsService.resolvePeerName(
                            msg.senderId,
                            rawSender,
                            senderChatId: msg.senderChatId,
                            isAnonymousAdmin: msg.isFromAnonymousAdmin,
                            isMirroredChannelPost: msg.isMirroredChannelPost,
                          );
                    final timeStr = DateTimeUtils.formatTimeHHmm(msg.createdAt);
                    return TheavListRow(
                      leading: _iconForMessage(msg, palette),
                      title: '$sender • $timeStr',
                      subtitle: _describeMessage(msg),
                      trailing: widget.canPinMessages
                          ? IconButton(
                              tooltip: 'Открепить',
                              icon: iconoir.Xmark(
                                width: 18,
                                height: 18,
                                color: palette.subtext,
                              ),
                              onPressed:
                                  _mutating ? null : () => _unpinOne(msg),
                            )
                          : null,
                      onTap: () {
                        HapticUtils.tap();
                        Navigator.of(context).pop<String>(msg.id);
                      },
                    );
                  }).toList(),
                ),
              ],
            ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SettingsFloatingHeader(
              title: 'Закреплённые',
              actions: [
                if (widget.canPinMessages && _pinned.isNotEmpty)
                  SettingsHeaderAction(
                    tooltip: 'Открепить все',
                    enabled: !_mutating,
                    foregroundColor: palette.error,
                    icon: iconoir.Trash(
                      width: 19,
                      height: 19,
                      color: palette.error,
                    ),
                    onTap: _unpinAll,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
