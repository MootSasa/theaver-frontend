import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../services/chat_service.dart';
import '../../services/contacts_service.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/haptic_utils.dart';
import '../design_system/theav_design_system.dart';
import 'telegram_avatar_stack.dart';

/// Compact Telegram-style read/views header row embedded inside [MessageContextMenu].
///
/// - Channels: shows view count (`iconoir.Eye`).
/// - Groups: lazily fetches `ChatService.getMessageReaders` and displays
///   overlapping reader avatars + inline expand list.
/// - Direct messages: shows read/unread state & timestamp.
class MessageSeenView extends StatefulWidget {
  final Message message;
  final String? chatType;
  final bool isMe;

  const MessageSeenView({
    super.key,
    required this.message,
    this.chatType,
    required this.isMe,
  });

  @override
  State<MessageSeenView> createState() => _MessageSeenViewState();
}

class _MessageSeenViewState extends State<MessageSeenView> {
  bool _loading = false;
  bool _expanded = false;
  List<Map<String, dynamic>> _readers = const [];
  int _totalCount = 0;

  @override
  void initState() {
    super.initState();
    ContactsService.revisionNotifier.addListener(_onContactsRevisionChanged);
    if (widget.chatType == 'group' && widget.message.sendStatus == 1) {
      _loadReaders();
    }
  }

  @override
  void dispose() {
    ContactsService.revisionNotifier.removeListener(_onContactsRevisionChanged);
    super.dispose();
  }

  void _onContactsRevisionChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _loadReaders() async {
    if (_loading) return;
    _loading = true;
    try {
      final res = await ChatService.getMessageReaders(
        chatId: widget.message.chatId,
        messageId: widget.message.id,
      );
      if (!mounted) return;
      final rawList = (res['readers'] as List?) ?? const [];
      final parsed = rawList
          .whereType<Map>()
          .map((m) => Map<String, dynamic>.from(m))
          .toList();
      final total = (res['total_count'] as num?)?.toInt() ??
          (res['count'] as num?)?.toInt() ??
          parsed.length;
      setState(() {
        _readers = parsed;
        _totalCount = total;
      });
    } catch (_) {
    } finally {
      _loading = false;
    }
  }

  String _formatViews(int views) {
    if (views >= 1000000) {
      return '${(views / 1000000).toStringAsFixed(1)}M';
    }
    if (views >= 1000) {
      return '${(views / 1000).toStringAsFixed(1)}K';
    }
    return '$views';
  }

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context, listen: false);
    final palette = style.palette;

    if (widget.chatType == 'channel') {
      final views = widget.message.viewsCount;
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: palette.surface.withValues(alpha: style.isGlass ? 0.84 : 1.0),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: palette.divider, width: 0.5),
        ),
        child: Row(
          children: [
            iconoir.Eye(width: 17, height: 17, color: palette.primary),
            const SizedBox(width: 8),
            Text(
              views > 0
                  ? 'Просмотров: ${_formatViews(views)}'
                  : 'Нет просмотров',
              style: TextStyle(
                color: palette.onSurface,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      );
    }

    if (widget.chatType == 'group') {
      if (_readers.isEmpty && !widget.message.isRead) {
        return const SizedBox.shrink();
      }
      final String label = _readers.isNotEmpty
          ? 'Прочитано ($_totalCount)'
          : 'Прочитано';
      return GestureDetector(
        onTap: _readers.isNotEmpty
            ? () {
                HapticUtils.selection();
                setState(() => _expanded = !_expanded);
              }
            : null,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: palette.surface.withValues(alpha: style.isGlass ? 0.84 : 1.0),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: palette.divider, width: 0.5),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  iconoir.DoubleCheck(
                    width: 16,
                    height: 16,
                    color: palette.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      label,
                      style: TextStyle(
                        color: palette.onSurface,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (_readers.isNotEmpty)
                    TelegramAvatarStack(
                      users: _readers,
                      maxCount: 3,
                      size: 20,
                    ),
                  if (_readers.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    AnimatedRotation(
                      turns: _expanded ? 0.5 : 0.0,
                      duration: const Duration(milliseconds: 160),
                      child: iconoir.NavArrowDown(
                        width: 16,
                        height: 16,
                        color: palette.subtext,
                      ),
                    ),
                  ],
                ],
              ),
              if (_expanded && _readers.isNotEmpty) ...[
                const SizedBox(height: 8),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: ListView.separated(
                    shrinkWrap: true,
                    padding: EdgeInsets.zero,
                    itemCount: _readers.length,
                    separatorBuilder: (_, __) => Divider(
                      height: 0.5,
                      thickness: 0.5,
                      color: palette.divider,
                    ),
                    itemBuilder: (_, i) {
                      final r = _readers[i];
                      final readerId =
                          (r['user_id'] ?? r['id'] ?? '').toString().trim();
                      final isBot = r['is_bot'] == true || r['is_bot'] == 1;
                      final rawName = (r['display_name'] ??
                              r['name'] ??
                              r['username'] ??
                              'Пользователь')
                          .toString();
                      final name = ContactsService.resolvePeerName(
                        readerId,
                        rawName,
                        isBot: isBot,
                      );
                      final readAt = r['read_at']?.toString();
                      return Padding(
                        padding: const EdgeInsets.symmetric(vertical: 5),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: palette.onSurface,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                            if (readAt != null && readAt.isNotEmpty)
                              Text(
                                DateTimeUtils.formatTimeHHmm(readAt),
                                style: TextStyle(
                                  color: palette.subtext,
                                  fontSize: 12,
                                ),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ],
          ),
        ),
      );
    }

    if (!widget.isMe) return const SizedBox.shrink();

    final String statusText;
    final Widget statusIcon;
    if (widget.message.isListened) {
      statusText = widget.message.listenedAt != null
          ? 'Прослушано в ${DateTimeUtils.formatTimeHHmm(widget.message.listenedAt!)}'
          : 'Прослушано';
      statusIcon =
          iconoir.DoubleCheck(width: 16, height: 16, color: palette.primary);
    } else if (widget.message.isRead) {
      statusText = widget.message.readAt != null
          ? 'Прочитано в ${DateTimeUtils.formatTimeHHmm(widget.message.readAt!)}'
          : 'Прочитано';
      statusIcon =
          iconoir.DoubleCheck(width: 16, height: 16, color: palette.primary);
    } else {
      statusText = 'Доставлено, не прочитано';
      statusIcon = iconoir.Check(width: 16, height: 16, color: palette.subtext);
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: palette.surface.withValues(alpha: style.isGlass ? 0.84 : 1.0),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: palette.divider, width: 0.5),
      ),
      child: Row(
        children: [
          statusIcon,
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              statusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.onSurface,
                fontSize: 13.5,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
