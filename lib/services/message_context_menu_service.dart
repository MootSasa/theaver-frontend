import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../services/chat_service.dart';
import '../widgets/chat/message_context_menu.dart';
import '../widgets/message/media_album_widget.dart';
import '../widgets/message/message_bubble.dart';
import '../widgets/message/poll_message_widget.dart';
import '../utils/emoji_utils.dart';

class MessageContextMenuService {
  static final MessageContextMenuService _instance =
      MessageContextMenuService._internal();
  factory MessageContextMenuService() => _instance;
  MessageContextMenuService._internal();

  bool _isShowing = false;
  NavigatorState? _activeNavigator;
  OverlayEntry? _activeOverlayEntry;
  GlobalKey<MessageContextMenuState>? _activeMenuKey;

  /// Notifies chat lists which message ID is currently separated into the blur
  /// overlay so the in-list widget can hide itself without layout shift.
  final ValueNotifier<String?> activeBlurMessageId = ValueNotifier<String?>(null);

  Offset? _pendingExternalStartPos;
  Offset? _pendingExternalCurrentPos;
  bool _isExternalDragActive = false;

  bool get isShowing => _isShowing;
  bool get hasActiveOverlay => _activeOverlayEntry != null;
  Offset? get pendingExternalStartPos => _pendingExternalStartPos;
  Offset? get pendingExternalCurrentPos => _pendingExternalCurrentPos;
  bool get isExternalDragActive => _isExternalDragActive;

  void clearActiveBlurMessage() {
    if (activeBlurMessageId.value != null) {
      activeBlurMessageId.value = null;
    }
  }

  void removeActiveOverlay() {
    _isShowing = false;
    clearActiveBlurMessage();
    _pendingExternalStartPos = null;
    _pendingExternalCurrentPos = null;
    _isExternalDragActive = false;
    _activeNavigator = null;
    _activeMenuKey = null;
    final entry = _activeOverlayEntry;
    _activeOverlayEntry = null;
    if (entry != null && entry.mounted) {
      entry.remove();
    }
  }

  void dismiss() {
    if (!_isShowing && _activeOverlayEntry == null) return;
    final nav = _activeNavigator;
    final hadOverlay = _activeOverlayEntry != null;
    removeActiveOverlay();
    if (!hadOverlay && nav != null && nav.mounted && nav.canPop()) {
      nav.pop();
    }
  }

  void updateExternalDragSelection(Offset globalPosition) {
    _pendingExternalCurrentPos = globalPosition;
    _isExternalDragActive = true;
    _activeMenuKey?.currentState?.updateExternalDrag(globalPosition);
  }

  void endExternalDragSelection() {
    _isExternalDragActive = false;
    _activeMenuKey?.currentState?.endExternalDrag();
  }

  void show({
    required BuildContext context,
    required Message message,
    required GlobalKey messageKey,
    required bool isMe,
    required VoidCallback onReply,
    VoidCallback? onQuote,
    void Function(String selectedText, int offset, int length)? onQuotePartial,
    VoidCallback? onPin,
    bool isPinned = false,
    VoidCallback? onForward,
    VoidCallback? onEdit,
    VoidCallback? onSelect,
    required Function(Message message) onDelete,
    required Function(String messageId, String emoji) onReaction,
    Set<String>? selectedEmojis,
    String? currentUserId,
    bool canManagePoll = false,
    ValueChanged<Map<String, dynamic>>? onPollUpdated,
    bool enableBlur = true,
    Offset? initialDragStartGlobalPosition,
    Offset? initialDragCurrentGlobalPosition,
  }) {
    if (_isShowing || message.isUnsupported) return;

    final RenderBox? renderBox =
        messageKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final navState = Navigator.of(context);
    final overlayState = navState.overlay ?? Overlay.maybeOf(context);
    if (overlayState == null) return;

    final navRenderObject = navState.context.findRenderObject();
    final offset = renderBox.localToGlobal(
      Offset.zero,
      ancestor: navRenderObject,
    );
    final size = renderBox.size;

    final originalWidget = messageKey.currentContext?.widget;
    String? detectedChatType;
    Widget Function(GlobalKey focusedKey)? focusedMessageBuilder;
    if (originalWidget is MessageBubble) {
      detectedChatType = originalWidget.chatType;
      focusedMessageBuilder = (focusedKey) => originalWidget.copyWithKey(focusedKey);
    } else if (originalWidget is MediaAlbumWidget) {
      detectedChatType = originalWidget.chatType;
      focusedMessageBuilder = (focusedKey) => originalWidget.copyWithKey(focusedKey);
    }

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

    final menuKey = GlobalKey<MessageContextMenuState>();
    _isShowing = true;
    _activeNavigator = navState;
    _activeMenuKey = menuKey;
    _pendingExternalStartPos = initialDragStartGlobalPosition;
    _pendingExternalCurrentPos =
        initialDragCurrentGlobalPosition ?? initialDragStartGlobalPosition;
    _isExternalDragActive = initialDragStartGlobalPosition != null;
    final String? targetBlurMessageId =
        (enableBlur && focusedMessageBuilder != null) ? message.id : null;

    // Insert via OverlayEntry instead of Navigator.push(PageRouteBuilder) because
    // Flutter's NavigatorState._flushHistoryUpdates() calls cancelPointer() on all
    // active pointers whenever a route is pushed, which would cancel an active LMB
    // text-selection drag in the chat after 1-2 characters.
    _activeOverlayEntry = OverlayEntry(
      builder: (overlayContext) => MessageContextMenu(
        key: menuKey,
        message: message,
        chatType: detectedChatType,
        messageOffset: offset,
        messageSize: size,
        isMe: isMe,
        sendStatus: message.sendStatus,
        messageKey: messageKey,
        activeBlurMessageId: targetBlurMessageId,
        messageContent: message.content,
        focusedMessageBuilder: focusedMessageBuilder,
        enableBlur: enableBlur,
        initialDragStartGlobalPosition: initialDragStartGlobalPosition,
        initialDragCurrentGlobalPosition: initialDragCurrentGlobalPosition,
        onReply: onReply,
        onQuote: (isPoll || isDice) ? null : onQuote,
        onQuotePartial: (isPoll || isDice) ? null : onQuotePartial,
        onCopy: () {
          Clipboard.setData(ClipboardData(text: message.content));
        },
        onPin: onPin,
        isPinned: isPinned,
        onForward: onForward,
        onEdit: (isPoll || isDice) ? null : onEdit,
        onSelect: onSelect,
        onViewPollResults: onViewPollResults,
        onRetractVote: onRetractVote,
        onStopPoll: onStopPoll,
        onDelete: () => onDelete(message),
        onReaction: (emoji) => onReaction(message.id, emoji),
        selectedEmojis: selectedEmojis ?? message.myReactions,
      ),
    );

    overlayState.insert(_activeOverlayEntry!);
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
