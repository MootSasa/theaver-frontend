import 'package:flutter/material.dart';
import '../l10n/app_localizations.dart';
import '../screens/search/search_screen.dart';
import '../utils/swipe_back_route.dart';
import '../widgets/design_system/theav_overlays.dart';
import 'chat_service.dart';
import 'draft_service.dart';
import 'glass_toast_service.dart';
import 'search_service.dart';
import 'database/app_database.dart';

/// ChatActionsHelper provides unified, tested implementations of common chat actions
/// across PrivateChatScreen, GroupChatScreen, and ChannelScreen.
class ChatActionsHelper {
  static String _tr(BuildContext context, String key, String fallback) {
    final res = AppLocalizations.of(context)?.translate(key);
    if (res == null || res.isEmpty || res == key) return fallback;
    return res;
  }

  /// Confirms and deletes a message with optimistic UI removal, API call,
  /// local database cleanup, and rollback on error.
  static Future<void> confirmAndDeleteMessage({
    required BuildContext context,
    required String chatId,
    required Message message,
    required VoidCallback onOptimisticDelete,
    required VoidCallback onRollback,
  }) async {
    final confirmed = await showTheavDialog<bool>(
      context: context,
      title: _tr(context, 'chat_delete_message_title', 'Delete Message'),
      message: _tr(
        context,
        'chat_delete_message_confirm',
        'Are you sure you want to delete this message?',
      ),
      actions: [
        TheavDialogAction<bool>(
          label: _tr(context, 'cancel', 'Cancel'),
          result: false,
        ),
        TheavDialogAction<bool>(
          label: _tr(context, 'chat_action_delete', 'Delete'),
          result: true,
          isDestructive: true,
        ),
      ],
    );

    if (confirmed != true) return;

    onOptimisticDelete();

    final result = await ChatService.deleteMessage(
      chatId: chatId,
      messageId: message.id,
    );

    if (result['success'] == true) {
      try {
        await AppDatabase().deleteMessage(message.id);
      } catch (e) {
        debugPrint('ChatActionsHelper: error deleting from DB: $e');
      }
    } else {
      onRollback();
      if (context.mounted) {
        final err = result['message']?.toString();
        GlassToastService().showError(
          context,
          (err != null && err.isNotEmpty)
              ? err
              : _tr(
                  context,
                  'error_failed_to_delete_message',
                  'Failed to delete message',
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
    final confirmed = await showTheavDialog<bool>(
      context: context,
      title: 'Очистить историю',
      message:
          'Вы уверены, что хотите удалить все сообщения в этом чате? Это действие необратимо.',
      actions: [
        TheavDialogAction<bool>(
          label: _tr(context, 'cancel', 'Отмена'),
          result: false,
        ),
        const TheavDialogAction<bool>(
          label: 'Очистить',
          result: true,
          isDestructive: true,
        ),
      ],
    );

    if (confirmed != true) return;

    final result = await ChatService.clearChatHistory(chatId: chatId);

    if (result['success'] == true) {
      try {
        await AppDatabase().deleteMessagesForChat(chatId);
      } catch (e) {
        debugPrint('ChatActionsHelper: error deleting messages from DB: $e');
      }

      await DraftService().deleteDraft(chatId);
      onHistoryCleared();

      if (context.mounted) {
        GlassToastService().show(context, 'История чата очищена');
      }
    } else if (context.mounted) {
      GlassToastService().showError(
        context,
        result['message']?.toString() ?? 'Не удалось очистить историю',
      );
    }
  }

  /// Opens chat messages search screen.
  static Future<void> openSearch({
    required BuildContext context,
    required String chatId,
    required String chatName,
    ValueChanged<String>? onMessageSelected,
  }) async {
    final result = await Navigator.of(context).push(
      SwipeBackPageRoute(
        builder: (_) => SearchScreen(
          initialChatId: chatId,
          initialChatName: chatName,
        ),
      ),
    );
    if (result is Map<String, dynamic> && result['type'] == 'message') {
      final data = result['data'];
      if (data is SearchResultMessage && data.id.isNotEmpty) {
        onMessageSelected?.call(data.id);
      } else if (data is Map && data['id'] != null) {
        onMessageSelected?.call(data['id'].toString());
      }
    }
  }

  /// Toggles mute status on server and notifies UI.
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
