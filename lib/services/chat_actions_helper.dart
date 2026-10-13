import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import 'chat_service.dart';
import 'draft_service.dart';
import 'database/app_database.dart';

/// ChatActionsHelper provides unified, tested implementations of common chat actions
/// across PrivateChatScreen, GroupChatScreen, and ChannelScreen.
class ChatActionsHelper {
  /// Confirms and deletes a message with optimistic UI removal, API call,
  /// local database cleanup, and rollback on error.
  static Future<void> confirmAndDeleteMessage({
    required BuildContext context,
    required String chatId,
    required Message message,
    required VoidCallback onOptimisticDelete,
    required VoidCallback onRollback,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          ctx.l10n.translate('chat_delete_message_title') ?? 'Delete Message',
        ),
        content: Text(
          ctx.l10n.translate('chat_delete_message_confirm') ??
              'Are you sure you want to delete this message?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.translate('cancel') ?? 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: Text(
              ctx.l10n.translate('chat_action_delete') ?? 'Delete',
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // Optimistically remove from UI
    onOptimisticDelete();

    // Call server API
    final result = await ChatService.deleteMessage(
      chatId: chatId,
      messageId: message.id,
    );

    if (result['success'] == true) {
      // Remove from local database on success
      try {
        await AppDatabase().deleteMessage(message.id);
      } catch (e) {
        debugPrint('ChatActionsHelper: error deleting from DB: $e');
      }
    } else {
      // Rollback on server error
      onRollback();
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              result['message'] ??
                  context.l10n.translate('error_failed_to_delete_message') ??
                  'Failed to delete message',
            ),
          ),
        );
      }
    }
  }

  /// Confirms and clears the chat history, deleting from server API,
  /// local SQLite/Drift database, and clearing unsent drafts.
  static Future<void> showClearHistoryDialog({
    required BuildContext context,
    required String chatId,
    required VoidCallback onHistoryCleared,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Chat History'),
        content: const Text(
          'Are you sure you want to clear all messages in this chat? This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(ctx.l10n.translate('cancel') ?? 'Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    final result = await ChatService.clearChatHistory(chatId: chatId);

    if (result['success'] == true) {
      // 1. Purge from local SQLite/Drift database
      try {
        await AppDatabase().deleteMessagesForChat(chatId);
      } catch (e) {
        debugPrint('ChatActionsHelper: error deleting messages from DB: $e');
      }

      // 2. Clear any active draft
      DraftService().deleteDraft(chatId);

      // 3. Notify UI
      onHistoryCleared();

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Chat history cleared')),
        );
      }
    } else {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Failed to clear history'),
          ),
        );
      }
    }
  }

  /// Opens chat messages search screen
  static void openSearch({
    required BuildContext context,
    required String chatId,
    required String chatName,
  }) {
    Navigator.pushNamed(
      context,
      '/search',
      arguments: {
        'chatId': chatId,
        'chatName': chatName,
      },
    );
  }

  /// Toggles mute status on server and notifies UI
  static Future<void> toggleMute({
    required String chatId,
    required bool currentMuted,
    required ValueChanged<bool> onMuteChanged,
  }) async {
    final newMuted = !currentMuted;
    onMuteChanged(newMuted);
    await ChatService.setMuteNotifications(chatId: chatId, muted: newMuted);
  }
}
