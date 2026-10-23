import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../services/chat_service.dart';
import '../widgets/chat/message_context_menu.dart';
import '../widgets/message/poll_message_widget.dart';
import '../utils/emoji_utils.dart';

class MessageContextMenuService {
  static final MessageContextMenuService _instance =
      MessageContextMenuService._internal();
  factory MessageContextMenuService() => _instance;
  MessageContextMenuService._internal();

  bool _isShowing = false;

  void show({
    required BuildContext context,
    required Message message,
    required GlobalKey messageKey,
    required bool isMe,
    required VoidCallback onReply,
    VoidCallback? onQuote,
    required VoidCallback onPin,
    VoidCallback? onEdit,
    required Function(Message message) onDelete,
    required Function(String messageId, String emoji) onReaction,
    Set<String>? selectedEmojis,
    String? currentUserId,
    bool canManagePoll = false,
    ValueChanged<Map<String, dynamic>>? onPollUpdated,
  }) {
    if (_isShowing || message.isUnsupported) return;

    final RenderBox? renderBox =
        messageKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final offset = renderBox.localToGlobal(Offset.zero);
    final size = renderBox.size;

    final bool isPoll = message.messageType == 'poll';
    final bool isDice = message.messageType == 'dice' || EmojiUtils.isDiceEmoji(message.content);
    final Map<String, dynamic>? pollData = isPoll ? message.mediaPayload : null;
    final int? pollId = PollMessageWidget.getPollId(pollData);
    final String? effectiveUserId =
        (currentUserId != null && currentUserId.isNotEmpty)
            ? currentUserId
            : (isMe ? message.senderId : null);

    VoidCallback? onViewPollResults;
    VoidCallback? onRetractVote;
    VoidCallback? onStopPoll;

    if (isPoll && pollData != null && pollId != null) {
      final bool isClosed = pollData['is_closed'] == true;
      final String createdBy = pollData['created_by']?.toString() ?? '';
      final bool isPollCreator = isMe ||
          (effectiveUserId != null &&
              effectiveUserId.isNotEmpty &&
              (createdBy == effectiveUserId ||
                  message.senderId == effectiveUserId));

      if (PollMessageWidget.canViewResults(pollData, effectiveUserId)) {
        onViewPollResults = () {
          if (!context.mounted) return;
          PollMessageWidget.showResultsSheet(
            context,
            chatId: message.chatId,
            messageId: message.id,
            questionFallback: message.content,
            pollData: pollData,
            currentUserId: effectiveUserId ?? '',
          );
        };
      }

      if (PollMessageWidget.canRetractVote(pollData, effectiveUserId)) {
        onRetractVote = () async {
          final updated = await PollMessageWidget.retractVote(
            chatId: message.chatId,
            messageId: message.id,
            question: message.content,
            pollId: pollId,
          );
          if (updated != null) {
            onPollUpdated?.call(updated);
          }
        };
      }

      if (!isClosed && (isPollCreator || canManagePoll)) {
        onStopPoll = () {
          if (!context.mounted) return;
          _showStopPollConfirmation(
            context: context,
            message: message,
            pollId: pollId,
            onPollUpdated: onPollUpdated,
          );
        };
      }
    }

    _isShowing = true;

    Navigator.push(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierDismissible: true,
        pageBuilder: (context, _, __) => MessageContextMenu(
          messageOffset: offset,
          messageSize: size,
          isMe: isMe,
          sendStatus: message.sendStatus,
          onReply: onReply,
          onQuote: (isPoll || isDice) ? null : onQuote,
          onCopy: () {
            Clipboard.setData(ClipboardData(text: message.content));
          },
          onPin: onPin,
          onEdit: (isPoll || isDice) ? null : onEdit,
          onViewPollResults: onViewPollResults,
          onRetractVote: onRetractVote,
          onStopPoll: onStopPoll,
          onDelete: () => onDelete(message),
          onReaction: (emoji) => onReaction(message.id, emoji),
          selectedEmojis: selectedEmojis ?? message.myReactions,
        ),
        transitionsBuilder: (context, animation, _, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    ).then((_) {
      _isShowing = false;
    });
  }

  void _showStopPollConfirmation({
    required BuildContext context,
    required Message message,
    required int pollId,
    ValueChanged<Map<String, dynamic>>? onPollUpdated,
  }) {
    final l10n = context.l10n;
    showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(l10n.translate('poll_stop_confirm_title')),
        content: Text(l10n.translate('poll_stop_confirm_desc')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, false),
            child: Text(l10n.translate('cancel')),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx, true),
            child: Text(
              l10n.translate('poll_stop_confirm_action'),
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    ).then((confirmed) async {
      if (confirmed == true) {
        final updated = await PollMessageWidget.closePoll(
          chatId: message.chatId,
          messageId: message.id,
          question: message.content,
          pollId: pollId,
        );
        if (updated != null) {
          onPollUpdated?.call(updated);
        }
      }
    });
  }
}
