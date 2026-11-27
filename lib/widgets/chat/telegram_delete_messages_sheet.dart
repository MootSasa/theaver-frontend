import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../design_system/theav_design_system.dart';

/// Result returned by [showTelegramDeleteMessagesSheet].
class TelegramDeleteMessagesResult {
  final bool confirmed;
  final bool revoke;
  final bool reportSpam;
  final bool banUser;
  final bool deleteAllFromUser;

  const TelegramDeleteMessagesResult({
    this.confirmed = false,
    this.revoke = false,
    this.reportSpam = false,
    this.banUser = false,
    this.deleteAllFromUser = false,
  });
}

/// Telegram-style bottom sheet for single or batch message deletion:
/// - In DMs: option to also delete for peer (`revoke`).
/// - In groups when an admin deletes another member's message(s):
///   moderation checkboxes (`reportSpam`, `deleteAllFromUser`, `banUser`).
Future<TelegramDeleteMessagesResult?> showTelegramDeleteMessagesSheet({
  required BuildContext context,
  required int messageCount,
  required String chatType,
  String? peerName,
  bool isSavedMessages = false,
  bool canRevoke = true,
  bool defaultRevoke = true,
  bool canModerateOther = false,
  String? targetAuthorName,
}) {
  return showTheavModalSheet<TelegramDeleteMessagesResult>(
    context: context,
    title: messageCount <= 1
        ? 'Удалить сообщение?'
        : 'Удалить сообщения ($messageCount)?',
    showCloseButton: true,
    padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
    builder: (ctx) => _TelegramDeleteSheetBody(
      messageCount: messageCount,
      chatType: chatType,
      peerName: peerName,
      isSavedMessages: isSavedMessages,
      canRevoke: canRevoke,
      defaultRevoke: defaultRevoke,
      canModerateOther: canModerateOther,
      targetAuthorName: targetAuthorName,
    ),
  );
}

class _TelegramDeleteSheetBody extends StatefulWidget {
  final int messageCount;
  final String chatType;
  final String? peerName;
  final bool isSavedMessages;
  final bool canRevoke;
  final bool defaultRevoke;
  final bool canModerateOther;
  final String? targetAuthorName;

  const _TelegramDeleteSheetBody({
    required this.messageCount,
    required this.chatType,
    this.peerName,
    required this.isSavedMessages,
    required this.canRevoke,
    required this.defaultRevoke,
    required this.canModerateOther,
    this.targetAuthorName,
  });

  @override
  State<_TelegramDeleteSheetBody> createState() =>
      _TelegramDeleteSheetBodyState();
}

class _TelegramDeleteSheetBodyState extends State<_TelegramDeleteSheetBody> {
  late bool _revoke;
  bool _reportSpam = false;
  bool _deleteAllFromUser = false;
  bool _banUser = false;

  bool get _isDmRevokeMode =>
      widget.chatType == 'private' &&
      !widget.isSavedMessages &&
      widget.canRevoke;

  bool get _isGroupModMode =>
      widget.chatType == 'group' && widget.canModerateOther;

  @override
  void initState() {
    super.initState();
    if (_isDmRevokeMode) {
      _revoke = widget.defaultRevoke;
    } else if (widget.chatType == 'channel' || widget.isSavedMessages) {
      _revoke = true;
    } else {
      _revoke = widget.canRevoke && widget.defaultRevoke;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final String safePeer =
        (widget.peerName != null && widget.peerName!.trim().isNotEmpty)
            ? widget.peerName!.trim()
            : 'собеседника';
    final String safeAuthor =
        (widget.targetAuthorName != null &&
                widget.targetAuthorName!.trim().isNotEmpty)
            ? widget.targetAuthorName!.trim()
            : 'пользователя';

    final String summaryText = widget.isSavedMessages
        ? (widget.messageCount <= 1
            ? 'Сообщение будет удалено из «Избранного».'
            : 'Выбранные сообщения (${widget.messageCount}) будут удалены из «Избранного».')
        : widget.chatType == 'channel'
            ? (widget.messageCount <= 1
                ? 'Пост будет безвозвратно удалён у всех подписчиков канала.'
                : 'Выбранные посты (${widget.messageCount}) будут безвозвратно удалены у всех подписчиков.')
            : _isDmRevokeMode
                ? (_revoke
                    ? 'Сообщение будет удалено у вас и у $safePeer.'
                    : 'Сообщение будет удалено только у вас.')
                : (widget.chatType == 'group' && widget.canRevoke)
                    ? 'Выбранное будет удалено для всех участников группы.'
                    : 'Сообщение будет удалено только из вашей истории.';

    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
            child: Text(
              summaryText,
              style: TextStyle(
                color: palette.subtext,
                fontSize: 14,
                height: 1.35,
              ),
            ),
          ),
          if (_isDmRevokeMode)
            TheavInsetGroup(
              margin: const EdgeInsets.only(bottom: 12),
              dividerIndent: 16,
              children: [
                TheavListRow(
                  leading: iconoir.Trash(
                    width: 20,
                    height: 20,
                    color: palette.primary,
                  ),
                  title: 'Также удалить для $safePeer',
                  trailing: TheavCheckCircle(
                    selected: _revoke,
                    onTap: () => setState(() => _revoke = !_revoke),
                  ),
                  onTap: () => setState(() => _revoke = !_revoke),
                ),
              ],
            ),
          if (_isGroupModMode)
            TheavInsetGroup(
              header: 'Модерация участника',
              margin: const EdgeInsets.only(bottom: 12),
              dividerIndent: 54,
              children: [
                TheavListRow(
                  leading: iconoir.WarningTriangle(
                    width: 20,
                    height: 20,
                    color: palette.error,
                  ),
                  title: 'Пожаловаться на спам',
                  trailing: TheavCheckCircle(
                    selected: _reportSpam,
                    activeColor: palette.error,
                    onTap: () => setState(() => _reportSpam = !_reportSpam),
                  ),
                  onTap: () => setState(() => _reportSpam = !_reportSpam),
                ),
                TheavListRow(
                  leading: iconoir.SwipeTwoFingersUpGesture(
                    width: 20,
                    height: 20,
                    color: palette.error,
                  ),
                  title: 'Удалить все от $safeAuthor',
                  trailing: TheavCheckCircle(
                    selected: _deleteAllFromUser,
                    activeColor: palette.error,
                    onTap: () =>
                        setState(() => _deleteAllFromUser = !_deleteAllFromUser),
                  ),
                  onTap: () =>
                      setState(() => _deleteAllFromUser = !_deleteAllFromUser),
                ),
                TheavListRow(
                  leading: iconoir.Prohibition(
                    width: 20,
                    height: 20,
                    color: palette.error,
                  ),
                  title: 'Заблокировать $safeAuthor',
                  isDestructive: true,
                  trailing: TheavCheckCircle(
                    selected: _banUser,
                    activeColor: palette.error,
                    onTap: () => setState(() => _banUser = !_banUser),
                  ),
                  onTap: () => setState(() => _banUser = !_banUser),
                ),
              ],
            ),
          if (widget.chatType == 'group' &&
              !_isGroupModMode &&
              widget.canRevoke)
            TheavInsetGroup(
              margin: const EdgeInsets.only(bottom: 12),
              dividerIndent: 16,
              children: [
                TheavListRow(
                  leading: iconoir.Trash(
                    width: 20,
                    height: 20,
                    color: palette.primary,
                  ),
                  title: 'Удалить для всех участников',
                  trailing: TheavCheckCircle(
                    selected: _revoke,
                    onTap: () => setState(() => _revoke = !_revoke),
                  ),
                  onTap: () => setState(() => _revoke = !_revoke),
                ),
              ],
            ),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: TheavFloatingPillButton(
                  label: 'Отмена',
                  onTap: () => Navigator.of(context).pop(null),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: TheavFloatingPillButton(
                  label: widget.messageCount <= 1
                      ? 'Удалить'
                      : 'Удалить (${widget.messageCount})',
                  icon: iconoir.Trash(
                    width: 18,
                    height: 18,
                    color: palette.error,
                  ),
                  isDestructive: true,
                  onTap: () {
                    Navigator.of(context).pop(
                      TelegramDeleteMessagesResult(
                        confirmed: true,
                        revoke: _revoke,
                        reportSpam: _reportSpam,
                        banUser: _banUser,
                        deleteAllFromUser: _deleteAllFromUser,
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
