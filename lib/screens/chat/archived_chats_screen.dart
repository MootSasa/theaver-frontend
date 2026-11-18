import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../services/account_manager.dart';
import '../../services/archive_preferences_service.dart';
import '../../services/chat_service.dart';
import '../../services/chat_swipe_service.dart';
import '../../services/database/app_database.dart';
import '../../services/draft_service.dart';
import '../../services/glass_toast_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/notification_settings_provider.dart';
import '../../services/settings_service.dart';
import '../../services/tiling_layout_controller.dart';
import '../../services/unread_count_provider.dart';
import '../../services/websocket_service.dart';
import '../../utils/date_time_utils.dart';
import '../../utils/haptic_utils.dart';
import '../../widgets/chat/chat_batch_dialogs.dart';
import '../../widgets/chat/chat_list_tile_item.dart';
import '../../widgets/chat/chat_selection_header.dart';

String _tr(
  BuildContext context,
  String key,
  String fallback, [
  Map<String, String>? params,
]) {
  final translated = AppLocalizations.of(context)?.translate(key, params);
  if (translated == null || translated.isEmpty || translated == key) {
    var result = fallback;
    params?.forEach((k, v) {
      result = result.replaceAll('{$k}', v);
    });
    return result;
  }
  return translated;
}

/// Telegram-style Archived Chats list screen with adaptive floating header,
/// animated multi-select morphing, live previews/drafts/typing indicators,
/// unarchive swipe override, independent archive pinning, and modal Archive Settings.
class ArchivedChatsScreen extends StatefulWidget {
  final void Function(Chat chat)? onOpenChat;
  final AppDatabase? database;

  const ArchivedChatsScreen({
    super.key,
    this.onOpenChat,
    this.database,
  });

  @override
  State<ArchivedChatsScreen> createState() => _ArchivedChatsScreenState();
}

class _ArchivedChatsScreenState extends State<ArchivedChatsScreen> {
  final WebSocketService _wsService = WebSocketService();
  final Map<String, ({String action, String? userName, Timer timer})>
      _chatTypingStates = {};
  final Map<String, List<MessageEntity>> _chatLastMessageEntities = {};
  final Map<String, String> _hydratedEntitySignatures = {};

  bool _isSelectMode = false;
  Set<String> _selectedChatIds = {};
  bool _isNormalMenuOpen = false;
  bool _isSelectionMenuOpen = false;
  bool _hadNonEmptyData = false;
  bool _autoPopScheduled = false;
  String _lastTilingSignature = '';

  String? get _currentUserId => AccountManager().currentAccount?.userId;

  AppDatabase _db() => widget.database ?? AppDatabase(_currentUserId);

  @override
  void initState() {
    super.initState();
    DraftService().draftsNotifier.addListener(_onServiceUpdate);
    ChatSwipeService().addListener(_onServiceUpdate);
    ArchivePreferencesService().addListener(_onServiceUpdate);
    TilingLayoutController.instance.addListener(_onTilingUpdate);
    _wsService.subscribe(WebSocketEventType.typing, _onChatTyping);
  }

  @override
  void dispose() {
    DraftService().draftsNotifier.removeListener(_onServiceUpdate);
    ChatSwipeService().removeListener(_onServiceUpdate);
    ArchivePreferencesService().removeListener(_onServiceUpdate);
    TilingLayoutController.instance.removeListener(_onTilingUpdate);
    _wsService.unsubscribe(WebSocketEventType.typing, _onChatTyping);
    for (final entry in _chatTypingStates.values) {
      entry.timer.cancel();
    }
    _chatTypingStates.clear();
    super.dispose();
  }

  void _onServiceUpdate() {
    if (mounted) setState(() {});
  }

  void _onTilingUpdate() {
    if (!mounted) return;
    final tiling = TilingLayoutController.instance;
    final openIds = tiling.chatTiles.map((t) => t.chatId).join(',');
    final focusedId = tiling.focusedChatTile?.chatId ?? '';
    final isTwoCol =
        tiling.windowSize.width >= TilingLayoutController.kTwoColumnBreakpoint;
    final sig = '$openIds|$focusedId|$isTwoCol|${tiling.isWorkspaceMounted}';
    if (sig != _lastTilingSignature) {
      _lastTilingSignature = sig;
      setState(() {});
    }
  }

  void _onChatTyping(WebSocketEvent event) {
    final chatId = event.data['chat_id']?.toString();
    if (chatId == null || chatId.isEmpty) return;
    final typingUserId = event.data['user_id']?.toString();
    if (typingUserId != null && typingUserId == _currentUserId) return;

    final action = event.data['action']?.toString() ?? 'typing';
    final isTyping = event.data['is_typing'] != false && action != 'stop';

    if (!isTyping) {
      final existing = _chatTypingStates.remove(chatId);
      existing?.timer.cancel();
      if (mounted && existing != null) setState(() {});
      return;
    }

    final userName = event.data['user_name']?.toString();
    _chatTypingStates[chatId]?.timer.cancel();
    final timer = Timer(const Duration(seconds: 4), () {
      _chatTypingStates.remove(chatId);
      if (mounted) setState(() {});
    });
    _chatTypingStates[chatId] = (
      action: action,
      userName: userName,
      timer: timer,
    );
    if (mounted) setState(() {});
  }

  Chat _dbChatToChat(DbChat model, UnreadCountProvider? unreadProvider) {
    final effectiveUnread =
        (unreadProvider != null && unreadProvider.hasAuthoritativeCount(model.chatId))
            ? unreadProvider.getCount(model.chatId)
            : model.unreadCount;
    return Chat.fromDbChat(
      model,
      lastMessageEntities:
          _chatLastMessageEntities[model.chatId] ?? const <MessageEntity>[],
      unreadCountOverride: effectiveUnread,
    ).copyWith(
      name: model.name.trim().isEmpty ? '?' : model.name,
      isArchived: true,
    );
  }

  void _scheduleEntityHydration(List<DbChat> dbChats) {
    final db = _db();
    for (final dbChat in dbChats) {
      final sig =
          '${dbChat.lastMessageTime ?? ''}|${dbChat.lastMessage ?? ''}';
      if (_hydratedEntitySignatures[dbChat.chatId] == sig) continue;
      _hydratedEntitySignatures[dbChat.chatId] = sig;

      unawaited(() async {
        try {
          final lastMsg = await db.getLastMessageForChat(dbChat.chatId);
          if (!mounted || lastMsg == null) return;
          if (lastMsg.content == dbChat.lastMessage) {
            final dbEntities = Message.fromDbMessage(lastMsg).entities;
            if (dbEntities.isNotEmpty ||
                lastMsg.createdAt == dbChat.lastMessageTime) {
              if (mounted) {
                setState(() {
                  _chatLastMessageEntities[dbChat.chatId] = dbEntities;
                });
              }
            }
          }
        } catch (_) {}
      }());
    }
  }

  List<Chat> _sortArchivedChats(List<Chat> input) {
    final sorted = List<Chat>.from(input);
    sorted.sort((a, b) {
      if (a.isPinned != b.isPinned) {
        return a.isPinned ? -1 : 1;
      }
      final dtA = DateTimeUtils.parseUtcDateTime(a.updatedAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      final dtB = DateTimeUtils.parseUtcDateTime(b.updatedAt) ??
          DateTime.fromMillisecondsSinceEpoch(0);
      return dtB.compareTo(dtA);
    });
    return sorted;
  }

  void _enterSelectMode([String? initialChatId]) {
    setState(() {
      _isNormalMenuOpen = false;
      _isSelectionMenuOpen = false;
      _isSelectMode = true;
      if (initialChatId != null) {
        _selectedChatIds = {initialChatId};
      } else {
        _selectedChatIds = {};
      }
    });
  }

  void _exitSelectMode() {
    setState(() {
      _isSelectMode = false;
      _isSelectionMenuOpen = false;
      _selectedChatIds = {};
    });
  }

  void _toggleChatSelection(String chatId) {
    setState(() {
      if (_selectedChatIds.contains(chatId)) {
        _selectedChatIds.remove(chatId);
        if (_selectedChatIds.isEmpty) {
          _isSelectMode = false;
          _isSelectionMenuOpen = false;
        }
      } else {
        _selectedChatIds.add(chatId);
      }
    });
  }

  void _selectAllOrDeselect(List<Chat> chats) {
    final allSelected =
        chats.isNotEmpty && chats.every((c) => _selectedChatIds.contains(c.id));
    setState(() {
      if (allSelected) {
        _selectedChatIds = {};
      } else {
        _selectedChatIds = chats.map((c) => c.id).toSet();
      }
    });
  }

  Future<void> _markAllArchivedRead(List<Chat> chats) async {
    final unreadChats =
        chats.where((c) => c.unreadCount > 0 || c.unreadCount == -1).toList();
    if (unreadChats.isEmpty) return;

    final db = _db();
    final ids = unreadChats.map((c) => c.id).toList();
    UnreadCountProvider? unreadProvider;
    try {
      unreadProvider = context.read<UnreadCountProvider>();
    } catch (_) {}

    await db.batchMarkAsRead(ids);
    for (final id in ids) {
      unreadProvider?.setCount(id, 0);
    }

    for (final chat in unreadChats) {
      if (chat.unreadCount > 0) {
        unawaited(ChatService.markMessagesAsRead(chatId: chat.id));
      }
    }
  }

  Future<void> _batchTogglePin(List<Chat> chats) async {
    final pinnable = chats.where((c) => c.chatType != 'saved').toList();
    if (pinnable.isEmpty) return;

    final allPinned = pinnable.every((c) => c.isPinned);
    final newPinned = !allPinned;
    final db = _db();

    await db.batchSetPinned(pinnable.map((c) => c.id).toList(), newPinned);
    if (_isSelectMode) _exitSelectMode();

    for (final chat in pinnable) {
      if (newPinned) {
        await ChatService.pinChat(chatId: chat.id);
      } else {
        await ChatService.unpinChat(chatId: chat.id);
      }
    }
  }

  Future<void> _batchToggleMute(List<Chat> chats) async {
    final muteable = chats
        .where((c) => c.chatType != 'saved' && c.chatType != 'community')
        .toList();
    if (muteable.isEmpty) return;

    NotificationSettingsProvider? notifProvider;
    try {
      notifProvider = context.read<NotificationSettingsProvider>();
    } catch (_) {}
    if (notifProvider == null) return;

    final allMuted = muteable.every(
      (c) => notifProvider!.isChatMuted(c.id, chatType: c.chatType),
    );
    final targetState = allMuted ? MuteState.notMuted : MuteState.muted;

    for (final chat in muteable) {
      await notifProvider.setMuteState(chat.id, targetState);
    }
    if (_isSelectMode) _exitSelectMode();
  }

  Future<void> _batchUnarchive(List<Chat> chats) async {
    if (chats.isEmpty) return;
    final toastText = _tr(
      context,
      'archive_restored_toast',
      'Возвращено из архива: ${chats.length}',
      {'count': '${chats.length}'},
    );
    final undoLabel = _tr(context, 'common_undo', 'Отменить');
    final errorText =
        _tr(context, 'archived_unarchive_error', 'Не удалось разархивировать');

    final db = _db();
    final ids = chats.map((c) => c.id).toList();
    await db.batchSetArchived(ids, false);
    if (_isSelectMode) _exitSelectMode();

    bool anyFailure = false;
    final failedIds = <String>[];
    for (final chat in chats) {
      final res = await ChatService.unarchiveChat(chatId: chat.id);
      if (res['success'] != true) {
        anyFailure = true;
        failedIds.add(chat.id);
      }
    }

    if (failedIds.isNotEmpty) {
      await db.batchSetArchived(failedIds, true);
    }

    if (!mounted) return;
    if (anyFailure) {
      GlassToastService().showError(context, errorText);
      return;
    }

    GlassToastService().show(
      context,
      toastText,
      actionLabel: undoLabel,
      onAction: () {
        unawaited(() async {
          await db.batchSetArchived(ids, true);
          for (final chat in chats) {
            await ChatService.archiveChat(chatId: chat.id);
          }
        }());
      },
    );
  }

  Future<void> _batchToggleRead(List<Chat> chats) async {
    if (chats.isEmpty) return;
    final db = _db();
    final ids = chats.map((c) => c.id).toList();
    UnreadCountProvider? unreadProvider;
    try {
      unreadProvider = context.read<UnreadCountProvider>();
    } catch (_) {}

    final anyUnread =
        chats.any((c) => c.unreadCount > 0 || c.unreadCount == -1);
    if (anyUnread) {
      await db.batchMarkAsRead(ids);
      for (final id in ids) {
        unreadProvider?.setCount(id, 0);
      }
      if (_isSelectMode) _exitSelectMode();
      for (final chat in chats) {
        if (chat.unreadCount > 0) {
          unawaited(ChatService.markMessagesAsRead(chatId: chat.id));
        }
      }
    } else {
      await db.batchMarkAsUnread(ids);
      for (final id in ids) {
        unreadProvider?.setCount(id, -1);
      }
      if (_isSelectMode) _exitSelectMode();
    }
  }

  Future<void> _batchDelete(List<Chat> chats) async {
    final deletable = chats.where((c) => c.chatType != 'saved').toList();
    if (deletable.isEmpty) return;

    final confirmed =
        await ChatBatchDialogs.confirmDeleteChats(context, deletable);
    if (!confirmed || !mounted) return;

    final db = _db();
    final ids = deletable.map((c) => c.id).toList();
    await db.batchDeleteChats(ids);
    if (_isSelectMode) _exitSelectMode();

    for (final chat in deletable) {
      await ChatService.deleteChat(chat.id);
    }
  }

  void _openArchivedChat(Chat chat, {bool inAdjacentTile = false}) {
    if (!inAdjacentTile && widget.onOpenChat != null) {
      widget.onOpenChat!(chat);
      return;
    }
    ChatBatchDialogs.openChat(
      context,
      chat,
      inAdjacentTile: inAdjacentTile,
      currentUserId: _currentUserId,
      onReturned: () {
        if (mounted) {
          unawaited(_db().refreshChatLastMessageFromDb(chat.id));
        }
      },
    );
  }

  Future<void> _handleSwipeAction(Chat chat, ChatSwipeAction action) async {
    switch (action) {
      case ChatSwipeAction.archive:
        await _batchUnarchive([chat]);
        break;
      case ChatSwipeAction.pin:
        await _batchTogglePin([chat]);
        break;
      case ChatSwipeAction.read:
        await _batchToggleRead([chat]);
        break;
      case ChatSwipeAction.mute:
        await _batchToggleMute([chat]);
        break;
      case ChatSwipeAction.delete:
        await _batchDelete([chat]);
        break;
    }
  }

  Future<void> _showArchivedChatContextMenu(
    Chat chat,
    Offset globalPos,
  ) async {
    final overlay = Overlay.of(context, rootOverlay: true)
        .context
        .findRenderObject() as RenderBox?;
    if (overlay == null) return;

    final canSplit = TilingLayoutController.instance.windowSize.width >=
        TilingLayoutController.kTwoColumnBreakpoint;
    final hasUnread = chat.unreadCount > 0 || chat.unreadCount == -1;
    final isMuted = context
        .read<NotificationSettingsProvider>()
        .isChatMuted(chat.id, chatType: chat.chatType);
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final selected = await showMenu<String>(
      context: context,
      useRootNavigator: true,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(globalPos.dx, globalPos.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      items: [
        if (canSplit)
          PopupMenuItem<String>(
            value: 'open_adjacent',
            child: Row(
              children: [
                iconoir.ViewColumns2(
                  width: 18,
                  height: 18,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Text(_tr(
                  context,
                  'selection_open_adjacent',
                  'Открыть в соседнем окне',
                )),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'open',
          child: Row(
            children: [
              iconoir.ChatBubble(width: 18, height: 18, color: onSurface),
              const SizedBox(width: 10),
              Text(_tr(context, 'chat_open_chat', 'Открыть чат')),
            ],
          ),
        ),
        if (chat.chatType != 'saved')
          PopupMenuItem<String>(
            value: 'pin',
            child: Row(
              children: [
                chat.isPinned
                    ? iconoir.PinSlash(width: 18, height: 18, color: onSurface)
                    : iconoir.Pin(width: 18, height: 18, color: onSurface),
                const SizedBox(width: 10),
                Text(_tr(
                  context,
                  chat.isPinned ? 'selection_unpin' : 'selection_pin',
                  chat.isPinned ? 'Открепить' : 'Закрепить',
                )),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'read',
          child: Row(
            children: [
              iconoir.DoubleCheck(width: 18, height: 18, color: onSurface),
              const SizedBox(width: 10),
              Text(_tr(
                context,
                hasUnread ? 'selection_mark_read' : 'selection_mark_unread',
                hasUnread
                    ? 'Отметить прочитанным'
                    : 'Отметить непрочитанным',
              )),
            ],
          ),
        ),
        PopupMenuItem<String>(
          value: 'unarchive',
          child: Row(
            children: [
              Icon(Icons.unarchive_outlined, size: 18, color: onSurface),
              const SizedBox(width: 10),
              Text(_tr(context, 'selection_unarchive', 'Из архива')),
            ],
          ),
        ),
        if (chat.chatType != 'saved' && chat.chatType != 'community')
          PopupMenuItem<String>(
            value: 'mute',
            child: Row(
              children: [
                isMuted
                    ? iconoir.Bell(width: 18, height: 18, color: onSurface)
                    : iconoir.BellOff(width: 18, height: 18, color: onSurface),
                const SizedBox(width: 10),
                Text(_tr(
                  context,
                  isMuted ? 'selection_unmute' : 'selection_mute',
                  isMuted ? 'Включить звук' : 'Без звука',
                )),
              ],
            ),
          ),
        PopupMenuItem<String>(
          value: 'select',
          child: Row(
            children: [
              iconoir.ListSelect(width: 18, height: 18, color: onSurface),
              const SizedBox(width: 10),
              Text(_tr(context, 'chat_select_chats', 'Выбрать чаты')),
            ],
          ),
        ),
        if (chat.chatType != 'community')
          PopupMenuItem<String>(
            value: 'clear_history',
            child: Row(
              children: [
                iconoir.Erase(width: 18, height: 18, color: onSurface),
                const SizedBox(width: 10),
                Text(_tr(context, 'selection_clear_history', 'Очистить историю')),
              ],
            ),
          ),
        if (chat.chatType != 'saved')
          PopupMenuItem<String>(
            value: 'delete',
            child: Row(
              children: [
                const iconoir.Trash(width: 18, height: 18, color: Colors.red),
                const SizedBox(width: 10),
                Text(
                  _tr(context, 'selection_delete', 'Удалить'),
                  style: const TextStyle(color: Colors.red),
                ),
              ],
            ),
          ),
      ],
    );

    if (!mounted || selected == null) return;
    switch (selected) {
      case 'open_adjacent':
        _openArchivedChat(chat, inAdjacentTile: true);
        break;
      case 'open':
        _openArchivedChat(chat);
        break;
      case 'pin':
        await _batchTogglePin([chat]);
        break;
      case 'read':
        await _batchToggleRead([chat]);
        break;
      case 'unarchive':
        await _batchUnarchive([chat]);
        break;
      case 'mute':
        await _batchToggleMute([chat]);
        break;
      case 'select':
        _enterSelectMode(chat.id);
        break;
      case 'clear_history':
        await ChatBatchDialogs.executeClearHistory(
          context,
          [chat],
          currentUserId: _currentUserId,
        );
        break;
      case 'delete':
        await _batchDelete([chat]);
        break;
    }
  }

  Widget _buildHeader(
    BuildContext context,
    List<Chat> chats,
    NotificationSettingsProvider? notifProvider,
  ) {
    final anyArchiveUnread =
        chats.any((c) => c.unreadCount > 0 || c.unreadCount == -1);
    final selectedChats =
        chats.where((c) => _selectedChatIds.contains(c.id)).toList();
    final pinnable = selectedChats.where((c) => c.chatType != 'saved').toList();
    final muteable = selectedChats
        .where((c) => c.chatType != 'saved' && c.chatType != 'community')
        .toList();
    final allPinned =
        pinnable.isNotEmpty && pinnable.every((c) => c.isPinned);
    final allMuted = muteable.isNotEmpty &&
        notifProvider != null &&
        muteable.every(
          (c) => notifProvider.isChatMuted(c.id, chatType: c.chatType),
        );
    final anySelectedUnread =
        selectedChats.any((c) => c.unreadCount > 0 || c.unreadCount == -1);
    final allSelected =
        chats.isNotEmpty && selectedChats.length == chats.length;
    final canSplit = TilingLayoutController.instance.windowSize.width >=
        TilingLayoutController.kTwoColumnBreakpoint;

    final normalMenuItems = <SelectionMorphMenuItem>[
      if (anyArchiveUnread)
        SelectionMorphMenuItem(
          id: 'mark_all_read',
          label: _tr(context, 'archive_mark_all_read', 'Прочитать все'),
          iconBuilder: (color, size) =>
              iconoir.DoubleCheck(color: color, width: size, height: size),
        ),
      if (chats.isNotEmpty)
        SelectionMorphMenuItem(
          id: 'select_chats',
          label: _tr(context, 'chat_select_chats', 'Выбрать чаты'),
          iconBuilder: (color, size) =>
              iconoir.ListSelect(color: color, width: size, height: size),
        ),
      SelectionMorphMenuItem(
        id: 'archive_settings',
        label: _tr(context, 'archive_settings', 'Настройки архива'),
        iconBuilder: (color, size) =>
            iconoir.Settings(color: color, width: size, height: size),
      ),
    ];

    final overflowItems = <SelectionMorphMenuItem>[
      if (selectedChats.length == 1 && canSplit)
        SelectionMorphMenuItem(
          id: 'open_adjacent',
          label: _tr(
            context,
            'selection_open_adjacent',
            'Открыть в соседнем окне',
          ),
          iconBuilder: (color, size) =>
              iconoir.ViewColumns2(color: color, width: size, height: size),
        ),
      if (selectedChats.isNotEmpty)
        SelectionMorphMenuItem(
          id: 'toggle_read',
          label: _tr(
            context,
            anySelectedUnread ? 'selection_mark_read' : 'selection_mark_unread',
            anySelectedUnread
                ? 'Отметить прочитанным'
                : 'Отметить непрочитанным',
          ),
          iconBuilder: (color, size) =>
              iconoir.DoubleCheck(color: color, width: size, height: size),
        ),
      if (selectedChats.isNotEmpty)
        SelectionMorphMenuItem(
          id: 'add_to_folder',
          label: _tr(context, 'selection_add_to_folder', 'Добавить в папку'),
          iconBuilder: (color, size) =>
              iconoir.Folder(color: color, width: size, height: size),
        ),
      if (selectedChats.isNotEmpty)
        SelectionMorphMenuItem(
          id: 'clear_history',
          label: _tr(context, 'selection_clear_history', 'Очистить историю'),
          iconBuilder: (color, size) =>
              iconoir.Erase(color: color, width: size, height: size),
        ),
      if (chats.isNotEmpty)
        SelectionMorphMenuItem(
          id: 'select_all',
          label: _tr(
            context,
            allSelected ? 'selection_deselect_all' : 'selection_select_all',
            allSelected ? 'Снять выделение' : 'Выбрать все',
          ),
          iconBuilder: (color, size) =>
              iconoir.ListSelect(color: color, width: size, height: size),
        ),
    ];

    return ChatListAdaptiveTopBar(
      isSelectMode: _isSelectMode,
      selectedCount: selectedChats.length,
      onCancelSelection: _exitSelectMode,
      isSelectionOverflowOpen: _isSelectionMenuOpen,
      onSelectionOverflowOpenChanged: (open) {
        setState(() => _isSelectionMenuOpen = open);
      },
      selectionConfig: SelectionQuickActionsConfig(
        canPin: pinnable.isNotEmpty,
        isUnpin: allPinned,
        onPin: () => _batchTogglePin(selectedChats),
        canMute: muteable.isNotEmpty && notifProvider != null,
        isUnmute: allMuted,
        onMute: () => _batchToggleMute(selectedChats),
        canArchive: selectedChats.isNotEmpty,
        isUnarchive: true,
        onArchive: () => _batchUnarchive(selectedChats),
        canDelete: pinnable.isNotEmpty,
        onDelete: () => _batchDelete(selectedChats),
        overflowItems: overflowItems,
        onOverflowAction: (id) async {
          switch (id) {
            case 'open_adjacent':
              if (selectedChats.isNotEmpty) {
                final target = selectedChats.first;
                _exitSelectMode();
                _openArchivedChat(target, inAdjacentTile: true);
              }
              break;
            case 'toggle_read':
              await _batchToggleRead(selectedChats);
              break;
            case 'add_to_folder':
              final applied = await ChatBatchDialogs.showAddToFolderSheet(
                context,
                selectedChats,
              );
              if (applied && mounted) _exitSelectMode();
              break;
            case 'clear_history':
              await ChatBatchDialogs.executeClearHistory(
                context,
                selectedChats,
                currentUserId: _currentUserId,
                onBeforeExecute: _exitSelectMode,
              );
              break;
            case 'select_all':
              _selectAllOrDeselect(chats);
              break;
          }
        },
      ),
      showBackButton: true,
      onBack: () => Navigator.of(context).maybePop(),
      normalTitle: _tr(context, 'archive_title', 'Архив'),
      normalTitleKey: 'archive_title',
      normalMenuItems: normalMenuItems,
      isNormalMenuOpen: _isNormalMenuOpen,
      onNormalMenuOpenChanged: (open) {
        setState(() => _isNormalMenuOpen = open);
      },
      onNormalMenuAction: (id) {
        switch (id) {
          case 'mark_all_read':
            unawaited(_markAllArchivedRead(chats));
            break;
          case 'select_chats':
            _enterSelectMode();
            break;
          case 'archive_settings':
            unawaited(ChatBatchDialogs.showArchiveSettingsSheet(context));
            break;
        }
      },
    );
  }

  Widget _buildBodyList(
    BuildContext context,
    AsyncSnapshot<List<DbChat>> snapshot,
    List<Chat> chats,
    NotificationSettingsProvider? notifProvider,
    double topPadding,
  ) {
    final double safeTopPadding = topPadding > 0 ? topPadding : 0.0;
    if (snapshot.connectionState == ConnectionState.waiting && chats.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: safeTopPadding),
        child: const Center(child: CircularProgressIndicator()),
      );
    }

    if (chats.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.only(
            top: safeTopPadding,
            left: 32,
            right: 32,
            bottom: 32,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              iconoir.Archive(
                width: 60,
                height: 60,
                color: Colors.grey[500],
              ),
              const SizedBox(height: 16),
              Text(
                _tr(context, 'archived_chats_empty', 'Архив пуст'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              Text(
                _tr(
                  context,
                  'archived_chats_empty_hint',
                  'Смахните чат на главном экране или используйте контекстное меню',
                ),
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13.5, color: Colors.grey[500]),
              ),
            ],
          ),
        ),
      );
    }

    final tiling = TilingLayoutController.instance;
    final fallbackSavedAvatar =
        AccountManager().currentAccount?.avatarUrl ??
            AccountManager().currentAccount?.localAvatarPath;

    return ListView.builder(
      cacheExtent: 1500.0,
      physics: const AlwaysScrollableScrollPhysics(
        parent: BouncingScrollPhysics(),
      ),
      padding: EdgeInsets.only(
        top: safeTopPadding,
        bottom: 24.0 + MediaQuery.paddingOf(context).bottom,
      ),
      itemCount: chats.length,
      itemBuilder: (itemContext, index) {
        final chat = chats[index];
        final isSelected = _selectedChatIds.contains(chat.id);
        final isMuted = notifProvider?.isChatMuted(
              chat.id,
              chatType: chat.chatType,
            ) ??
            false;
        final typing = _chatTypingStates[chat.id];

        return ChatListTileItem(
          key: ValueKey<String>('archived_row_${chat.id}'),
          chat: chat,
          isSelectMode: _isSelectMode,
          isSelected: isSelected,
          isMuted: isMuted,
          currentUserId: _currentUserId,
          fallbackSavedAvatarUrl: fallbackSavedAvatar,
          typingInfo: typing != null
              ? (action: typing.action, userName: typing.userName)
              : null,
          fallbackEntities: _chatLastMessageEntities[chat.id] ?? const [],
          isOpenInTile: tiling.isChatOpen(chat.id),
          isFocusedInTile: tiling.focusedChatTile?.chatId == chat.id,
          swipeOverrideAction: ChatSwipeAction.archive,
          onTap: () {
            if (_isSelectMode) {
              HapticUtils.selection();
              _toggleChatSelection(chat.id);
            } else {
              HapticUtils.tap();
              _openArchivedChat(chat);
            }
          },
          onLongPress: () {
            HapticUtils.impact();
            if (_isSelectMode) {
              _toggleChatSelection(chat.id);
            } else {
              _enterSelectMode(chat.id);
            }
          },
          onSecondaryTapUp: (details) {
            _showArchivedChatContextMenu(chat, details.globalPosition);
          },
          onCreateDragPayload: (initialRect, globalPos) =>
              ChatBatchDialogs.createDragPayload(
            context,
            chat,
            initialRect,
            globalPos,
          ),
          onSwipeAction: (action) => _handleSwipeAction(chat, action),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final glassProvider = LiquidGlassProvider.maybeOf(context);
    final glassEnabled = glassProvider?.enabled ?? false;
    UnreadCountProvider? unreadProvider;
    NotificationSettingsProvider? notifProvider;
    try {
      unreadProvider = context.watch<UnreadCountProvider>();
    } catch (_) {}
    try {
      notifProvider = context.watch<NotificationSettingsProvider>();
    } catch (_) {}

    final statusBarHeight = MediaQuery.of(context).padding.top;
    final topPadding = statusBarHeight + 60.0;

    return PopScope(
      canPop: !_isSelectMode && !_isNormalMenuOpen && !_isSelectionMenuOpen,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_isNormalMenuOpen || _isSelectionMenuOpen) {
          setState(() {
            _isNormalMenuOpen = false;
            _isSelectionMenuOpen = false;
          });
        } else if (_isSelectMode) {
          _exitSelectMode();
        }
      },
      child: StreamBuilder<List<DbChat>>(
        stream: _db().watchArchivedChats(),
        builder: (context, snapshot) {
          final dbChats = snapshot.data ?? const <DbChat>[];
          if (dbChats.isNotEmpty) {
            _scheduleEntityHydration(dbChats);
          }

          final chats = _sortArchivedChats(
            dbChats.map((c) => _dbChatToChat(c, unreadProvider)).toList(),
          );

          if (chats.isNotEmpty) {
            _hadNonEmptyData = true;
            _autoPopScheduled = false;
            if (_isSelectMode && _selectedChatIds.isNotEmpty) {
              final availableIds = chats.map((c) => c.id).toSet();
              if (!_selectedChatIds.any(availableIds.contains)) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (mounted && _isSelectMode) _exitSelectMode();
                });
              }
            }
          } else if (_hadNonEmptyData &&
              !_autoPopScheduled &&
              (ModalRoute.of(context)?.isCurrent ?? false)) {
            _autoPopScheduled = true;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              Navigator.of(context).maybePop();
            });
          }

          final headerWidget = _buildHeader(context, chats, notifProvider);
          final bodyList = _buildBodyList(
            context,
            snapshot,
            chats,
            notifProvider,
            topPadding,
          );

          if (glassEnabled) {
            return LiquidGlassScaffold(
              pixelRatio: 1.0,
              useSync: true,
              batch: false,
              backgroundColor: Theme.of(context).scaffoldBackgroundColor,
              appBar: headerWidget,
              appBarTopMargin: 8.0,
              lenses: [
                if (_isNormalMenuOpen || _isSelectionMenuOpen)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      setState(() {
                        _isNormalMenuOpen = false;
                        _isSelectionMenuOpen = false;
                      });
                    },
                  ),
              ],
              body: Scaffold(
                backgroundColor: Colors.transparent,
                body: bodyList,
              ),
            );
          }

          return Scaffold(
            backgroundColor: Theme.of(context).scaffoldBackgroundColor,
            body: Stack(
              children: [
                Positioned.fill(child: bodyList),
                if (_isNormalMenuOpen || _isSelectionMenuOpen)
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        setState(() {
                          _isNormalMenuOpen = false;
                          _isSelectionMenuOpen = false;
                        });
                      },
                    ),
                  ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 8.0),
                      child: headerWidget,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
