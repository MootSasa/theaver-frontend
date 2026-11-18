import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../services/chat_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/websocket_service.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/chat/send_options_popup.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../../widgets/settings/settings_floating_header.dart';

/// Screen displaying pending scheduled messages and send-when-online items for
/// a chat, supporting Send Now, Reschedule, and Delete actions.
class ScheduledMessagesScreen extends StatefulWidget {
  final String chatId;
  final String chatTitle;

  const ScheduledMessagesScreen({
    super.key,
    required this.chatId,
    required this.chatTitle,
  });

  @override
  State<ScheduledMessagesScreen> createState() =>
      _ScheduledMessagesScreenState();
}

class _ScheduledMessagesScreenState extends State<ScheduledMessagesScreen> {
  List<ScheduledMessage> _items = [];
  bool _loading = true;
  bool _busy = false;
  StreamSubscription<ChatRealtimeUpdate>? _realtimeSub;

  @override
  void initState() {
    super.initState();
    _load();
    _realtimeSub = ChatService.realtimeUpdates.listen((upd) {
      if (!mounted || upd.chatId != widget.chatId) return;
      if (upd.type == WebSocketEventType.scheduledMessagesUpdated) {
        _load();
      }
    });
  }

  @override
  void dispose() {
    _realtimeSub?.cancel();
    super.dispose();
  }

  Future<void> _load() async {
    final list = await ChatService.getScheduledMessages(widget.chatId);
    if (!mounted) return;
    setState(() {
      _items = list;
      _loading = false;
    });
  }

  String _formatSchedule(ScheduledMessage item) {
    if (item.sendWhenOnline) return 'Когда будет в сети';
    final dt = item.scheduleAt?.toLocal();
    if (dt == null) return 'Запланировано';
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '${dt.day.toString().padLeft(2, '0')}.${dt.month.toString().padLeft(2, '0')}.${dt.year} в $hh:$mm';
  }

  String _previewContent(ScheduledMessage item) {
    final t = item.content.trim();
    if (t.isNotEmpty) return t;
    switch (item.messageType) {
      case 'image':
      case 'photo':
        return 'Фотография';
      case 'video':
        return item.isRound ? 'Видеосообщение' : 'Видео';
      case 'voice':
        return 'Голосовое сообщение';
      case 'file':
      case 'document':
        return item.fileName ?? 'Документ';
      default:
        return 'Сообщение';
    }
  }

  Future<void> _openItemActions(ScheduledMessage item) async {
    final choice = await showTheavModalSheet<String>(
      context: context,
      title: _formatSchedule(item),
      showCloseButton: true,
      builder: (ctx) {
        final palette = ctx.theav;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TheavInsetGroup(
              margin: const EdgeInsets.only(bottom: 8),
              children: [
                TheavListRow(
                  leading: iconoir.Send(
                    width: 20,
                    height: 20,
                    color: palette.primary,
                  ),
                  title: 'Отправить сейчас',
                  onTap: () => Navigator.of(ctx).pop('send_now'),
                ),
                if (!item.sendWhenOnline)
                  TheavListRow(
                    leading: iconoir.Calendar(
                      width: 20,
                      height: 20,
                      color: palette.primary,
                    ),
                    title: 'Изменить время',
                    onTap: () => Navigator.of(ctx).pop('reschedule'),
                  ),
                TheavListRow(
                  leading: iconoir.Trash(
                    width: 20,
                    height: 20,
                    color: palette.error,
                  ),
                  title: 'Удалить',
                  isDestructive: true,
                  onTap: () => Navigator.of(ctx).pop('delete'),
                ),
              ],
            ),
          ],
        );
      },
    );

    if (choice == null || !mounted) return;
    if (choice == 'send_now') {
      await _sendNow(item);
    } else if (choice == 'reschedule') {
      await _reschedule(item);
    } else if (choice == 'delete') {
      await _deleteItem(item);
    }
  }

  Future<void> _sendNow(ScheduledMessage item) async {
    if (_busy) return;
    setState(() => _busy = true);
    final sent = await ChatService.sendScheduledMessageNow(
      chatId: widget.chatId,
      schedId: item.id,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (sent != null) {
      setState(() => _items.removeWhere((e) => e.id == item.id));
      GlassToastService().show(context, 'Сообщение отправлено');
      if (_items.isEmpty && mounted) {
        Navigator.of(context).pop(true);
      }
    } else {
      GlassToastService().showError(context, 'Не удалось отправить сообщение');
    }
  }

  Future<void> _reschedule(ScheduledMessage item) async {
    final newDt = await showTheavScheduleSheet(
      context: context,
      initialDateTime: item.scheduleAt,
      confirmLabel: 'Сохранить',
    );
    if (newDt == null || !mounted) return;
    setState(() => _busy = true);
    final updated = await ChatService.updateScheduledMessage(
      chatId: widget.chatId,
      schedId: item.id,
      scheduleAt: newDt,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (updated != null) {
      setState(() {
        final idx = _items.indexWhere((e) => e.id == item.id);
        if (idx >= 0) _items[idx] = updated;
      });
      GlassToastService().show(context, 'Время отправки обновлено');
    } else {
      GlassToastService().showError(context, 'Не удалось изменить время');
    }
  }

  Future<void> _deleteItem(ScheduledMessage item) async {
    if (_busy) return;
    setState(() => _busy = true);
    final ok = await ChatService.deleteScheduledMessage(
      chatId: widget.chatId,
      schedId: item.id,
    );
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok) {
      setState(() => _items.removeWhere((e) => e.id == item.id));
      GlassToastService().show(context, 'Отложенное сообщение удалено');
    } else {
      GlassToastService().showError(context, 'Не удалось удалить сообщение');
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final topClearance = SettingsFloatingHeader.topClearanceOf(context);
    final onlineItems = _items.where((i) => i.sendWhenOnline).toList();
    final timedItems = _items.where((i) => !i.sendWhenOnline).toList();

    return Scaffold(
      backgroundColor: palette.background,
      body: Stack(
        children: [
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else if (_items.isEmpty)
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    iconoir.Calendar(
                      width: 44,
                      height: 44,
                      color: palette.subtext.withValues(alpha: 0.55),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Нет отложенных сообщений',
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
                if (onlineItems.isNotEmpty)
                  TheavInsetGroup(
                    header: 'Когда будет в сети',
                    children: onlineItems
                        .map((item) => _buildRow(item, palette))
                        .toList(),
                  ),
                if (timedItems.isNotEmpty)
                  TheavInsetGroup(
                    header: 'Запланировано (${timedItems.length})',
                    children: timedItems
                        .map((item) => _buildRow(item, palette))
                        .toList(),
                  ),
              ],
            ),
          const Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SettingsFloatingHeader(
              title: 'Отложенные',
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRow(ScheduledMessage item, TheavPalette palette) {
    return TheavListRow(
      leading: item.sendWhenOnline
          ? iconoir.Wifi(width: 20, height: 20, color: palette.primary)
          : iconoir.Calendar(width: 20, height: 20, color: palette.primary),
      title: _previewContent(item),
      subtitle: _formatSchedule(item),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (item.isSilent)
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: iconoir.BellOff(
                width: 16,
                height: 16,
                color: palette.subtext,
              ),
            ),
          iconoir.MoreVert(
            width: 18,
            height: 18,
            color: palette.subtext,
          ),
        ],
      ),
      onTap: () {
        HapticUtils.tap();
        _openItemActions(item);
      },
    );
  }
}
