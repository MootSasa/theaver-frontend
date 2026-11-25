import 'dart:async';

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../l10n/app_localizations.dart';
import '../../services/chat_service.dart';
import '../../services/contacts_service.dart';
import '../../utils/haptic_utils.dart';
import '../../utils/image_utils.dart';
import '../common/peer_badges_widget.dart';
import '../design_system/theav_design_system.dart';

/// Opens a dual-mode Liquid-Glass-safe chat picker modal sheet for Mini Apps
/// (`switchInlineQuery`, `shareMessage`), filtering chats by type flags and
/// returning the selected `chat.id` or `null` if cancelled.
Future<String?> showMiniAppChatPickerSheet(
  BuildContext context, {
  bool allowUserChats = true,
  bool allowBotChats = true,
  bool allowGroupChats = true,
  bool allowChannelChats = true,
  String? title,
  List<dynamic>? debugChatsOverride,
}) {
  final effectiveTitle = (title != null && title.trim().isNotEmpty)
      ? title.trim()
      : context.trOr('miniapp_chat_picker_title', 'Выберите чат');
  return showTheavModalSheet<String>(
    context: context,
    useRootNavigator: true,
    barrierDismissible: true,
    title: effectiveTitle,
    showCloseButton: true,
    maxHeightFactor: 0.86,
    padding: const EdgeInsets.fromLTRB(0, 6, 0, 14),
    builder: (_) => MiniAppChatPickerSheet(
      allowUserChats: allowUserChats,
      allowBotChats: allowBotChats,
      allowGroupChats: allowGroupChats,
      allowChannelChats: allowChannelChats,
      debugChatsOverride: debugChatsOverride,
    ),
  );
}

/// Modal sheet body displaying searchable chats filtered by Mini App chat-type
/// capabilities (`users`, `bots`, `groups`, `channels`).
class MiniAppChatPickerSheet extends StatefulWidget {
  final bool allowUserChats;
  final bool allowBotChats;
  final bool allowGroupChats;
  final bool allowChannelChats;
  final List<dynamic>? debugChatsOverride;

  const MiniAppChatPickerSheet({
    super.key,
    this.allowUserChats = true,
    this.allowBotChats = true,
    this.allowGroupChats = true,
    this.allowChannelChats = true,
    this.debugChatsOverride,
  });

  @override
  State<MiniAppChatPickerSheet> createState() => _MiniAppChatPickerSheetState();
}

class _MiniAppChatPickerSheetState extends State<MiniAppChatPickerSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<Chat> _chats = const [];
  bool _isLoading = true;
  String? _loadError;

  @override
  void initState() {
    super.initState();
    ContactsService.revisionNotifier.addListener(_onContactsRevisionChanged);
    if (widget.debugChatsOverride != null) {
      _chats = _parseOverrideChats(widget.debugChatsOverride!);
      _isLoading = false;
    } else {
      unawaited(_fetchChats());
    }
  }

  void _onContactsRevisionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void didUpdateWidget(covariant MiniAppChatPickerSheet oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.debugChatsOverride != oldWidget.debugChatsOverride &&
        widget.debugChatsOverride != null) {
      setState(() {
        _chats = _parseOverrideChats(widget.debugChatsOverride!);
        _isLoading = false;
        _loadError = null;
      });
    }
  }

  @override
  void dispose() {
    ContactsService.revisionNotifier.removeListener(_onContactsRevisionChanged);
    _searchController.dispose();
    super.dispose();
  }

  List<Chat> _parseOverrideChats(List<dynamic> rawList) {
    final result = <Chat>[];
    for (final item in rawList) {
      if (item is Chat) {
        result.add(item);
      } else if (item is Map<String, dynamic>) {
        result.add(Chat.fromJson(item));
      } else if (item is Map) {
        result.add(Chat.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return result;
  }

  Future<void> _fetchChats() async {
    if (mounted) {
      setState(() {
        _isLoading = true;
        _loadError = null;
      });
    }
    final res = await ChatService.getChats();
    if (!mounted) return;
    final rawChats = res['chats'];
    if (res['success'] == true && rawChats is List) {
      setState(() {
        _chats = _parseOverrideChats(rawChats);
        _isLoading = false;
      });
    } else {
      setState(() {
        _chats = const [];
        _isLoading = false;
        _loadError = res['message']?.toString() ??
            context.trOr(
              'miniapp_chat_picker_load_error',
              'Не удалось загрузить чаты',
            );
      });
    }
  }

  bool _matchesChatTypeFilter(Chat chat) {
    final type = chat.chatType.toLowerCase().trim();
    if (type == 'system') return false;
    if (type == 'bot') return widget.allowBotChats;
    if (type == 'private') {
      return chat.isBot ? widget.allowBotChats : widget.allowUserChats;
    }
    if (type == 'saved') return widget.allowUserChats;
    if (type == 'group' || type == 'supergroup') {
      return widget.allowGroupChats;
    }
    if (type == 'channel') return widget.allowChannelChats;
    return false;
  }

  String _chatDisplayTitle(BuildContext context, Chat chat) {
    final type = chat.chatType.toLowerCase().trim();
    if (type == 'saved') {
      return context.trOr('miniapp_chat_saved_favorites', 'Избранное');
    }
    final rawTitle = chat.name.trim().isNotEmpty
        ? chat.name.trim()
        : (chat.username != null && chat.username!.trim().isNotEmpty
            ? '@${chat.username!.trim()}'
            : context.trOr(
                'miniapp_chat_fallback_name',
                'Чат {id}',
                {'id': chat.id},
              ));
    if (type == 'private' && !chat.isBot) {
      return ContactsService.resolvePeerName(
        chat.otherUserId,
        rawTitle,
        isBot: chat.isBot,
      );
    }
    return rawTitle;
  }

  String _chatSubtitle(BuildContext context, Chat chat) {
    final type = chat.chatType.toLowerCase().trim();
    final uname = chat.username?.trim() ?? '';
    final String kindLabel;
    if (type == 'saved') {
      kindLabel = context.trOr(
        'miniapp_chat_kind_saved',
        'Сохранённые сообщения',
      );
    } else if (chat.isBot || type == 'bot') {
      kindLabel = context.trOr('miniapp_chat_kind_bot', 'Бот');
    } else if (type == 'channel') {
      kindLabel = context.trOr('miniapp_chat_kind_channel', 'Канал');
    } else if (type == 'group' || type == 'supergroup') {
      kindLabel = context.trOr('miniapp_chat_kind_group', 'Группа');
    } else {
      kindLabel = context.trOr('miniapp_chat_kind_private', 'Личный чат');
    }
    if (uname.isNotEmpty) {
      return '@$uname • $kindLabel';
    }
    return kindLabel;
  }

  Widget _buildAvatar(Chat chat, String title, TheavPalette palette) {
    final type = chat.chatType.toLowerCase().trim();
    if (type == 'saved') {
      return CircleAvatar(
        radius: 21,
        backgroundColor: palette.primary,
        child: iconoir.Bookmark(
          width: 20,
          height: 20,
          color: palette.onPrimary,
        ),
      );
    }

    final rawAvatar = (type == 'private' && !chat.isBot)
        ? ContactsService.resolvePeerAvatarUrl(
            chat.otherUserId,
            chat.avatarUrl,
            isBot: chat.isBot,
          )
        : chat.avatarUrl;
    final validUrl = getValidAvatarUrl(rawAvatar);
    final provider = validUrl != null ? avatarImageProvider(rawAvatar) : null;
    final initial = title.isNotEmpty
        ? String.fromCharCode(title.runes.first).toUpperCase()
        : '?';

    return CircleAvatar(
      radius: 21,
      backgroundColor: palette.primary.withValues(alpha: 0.16),
      backgroundImage: provider,
      onBackgroundImageError: provider != null ? (_, __) {} : null,
      child: provider == null
          ? Text(
              initial,
              style: TextStyle(
                color: palette.primary,
                fontWeight: FontWeight.w700,
                fontSize: 15,
              ),
            )
          : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final query = _searchController.text.trim().toLowerCase();

    final filtered = _chats.where((chat) {
      if (!_matchesChatTypeFilter(chat)) return false;
      if (query.isEmpty) return true;
      final title = _chatDisplayTitle(context, chat).toLowerCase();
      final rawName = chat.name.toLowerCase();
      final uname = (chat.username ?? '').toLowerCase();
      return title.contains(query) ||
          rawName.contains(query) ||
          uname.contains(query);
    }).toList();

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.62,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TheavInsetGroup(
              margin: EdgeInsets.zero,
              children: [
                TheavInlineTextField(
                  key: const ValueKey('mini_app_chat_picker_search'),
                  controller: _searchController,
                  placeholder: context.trOr(
                    'miniapp_chat_picker_search_hint',
                    'Поиск чата...',
                  ),
                  prefix: iconoir.Search(
                    width: 18,
                    height: 18,
                    color: palette.subtext,
                  ),
                  suffix: _searchController.text.isNotEmpty
                      ? GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () {
                            _searchController.clear();
                            setState(() {});
                          },
                          child: iconoir.Xmark(
                            width: 16,
                            height: 16,
                            color: palette.subtext,
                          ),
                        )
                      : null,
                  onChanged: (_) => setState(() {}),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: palette.primary,
                    ),
                  )
                : _loadError != null && filtered.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                _loadError!,
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: palette.subtext,
                                  fontSize: 14,
                                ),
                              ),
                              const SizedBox(height: 12),
                              TheavFloatingPillButton(
                                label: context.trOr('common_retry', 'Повторить'),
                                isPrimary: true,
                                onTap: _fetchChats,
                              ),
                            ],
                          ),
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(
                            key: const ValueKey('mini_app_chat_picker_empty'),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  iconoir.ChatBubbleEmpty(
                                    width: 34,
                                    height: 34,
                                    color: palette.subtext.withValues(alpha: 0.7),
                                  ),
                                  const SizedBox(height: 8),
                                  Text(
                                    context.trOr(
                                      'miniapp_chat_picker_empty',
                                      'Подходящих чатов не найдено',
                                    ),
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: palette.subtext,
                                      fontSize: 14.5,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          )
                        : Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: style.isGlass
                                    ? palette.surface.withValues(
                                        alpha: style.isDark ? 0.72 : 0.84,
                                      )
                                    : Color.alphaBlend(
                                        palette.onSurface.withValues(
                                          alpha: style.isDark ? 0.035 : 0.02,
                                        ),
                                        palette.surface,
                                      ),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(
                                  color: style.isGlass
                                      ? (style.isDark
                                          ? Colors.white.withValues(alpha: 0.11)
                                          : Colors.black.withValues(alpha: 0.07))
                                      : palette.divider,
                                  width: style.isGlass ? 0.6 : 0.5,
                                ),
                              ),
                              child: ListView.separated(
                                key: const ValueKey('mini_app_chat_picker_list'),
                                padding: EdgeInsets.zero,
                                itemCount: filtered.length,
                                separatorBuilder: (_, __) => Divider(
                                  height: 0.5,
                                  thickness: 0.5,
                                  indent: 72,
                                  endIndent: 16,
                                  color: palette.divider,
                                ),
                                itemBuilder: (context, index) {
                                  final chat = filtered[index];
                                  final title = _chatDisplayTitle(context, chat);
                                  final subtitle = _chatSubtitle(context, chat);
                                  return Material(
                                    type: MaterialType.transparency,
                                    child: InkWell(
                                      key: ValueKey('mini_app_chat_item_${chat.id}'),
                                      borderRadius: BorderRadius.vertical(
                                        top: index == 0
                                            ? const Radius.circular(18)
                                            : Radius.zero,
                                        bottom: index == filtered.length - 1
                                            ? const Radius.circular(18)
                                            : Radius.zero,
                                      ),
                                      onTap: () {
                                        HapticUtils.tap();
                                        Navigator.of(context).pop(chat.id);
                                      },
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        child: Row(
                                          children: [
                                            _buildAvatar(chat, title, palette),
                                            const SizedBox(width: 12),
                                            Expanded(
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                crossAxisAlignment:
                                                    CrossAxisAlignment.start,
                                                children: [
                                                  Row(
                                                    children: [
                                                      Flexible(
                                                        child: Text(
                                                          title,
                                                          maxLines: 1,
                                                          overflow: TextOverflow
                                                              .ellipsis,
                                                          style: TextStyle(
                                                            color: palette
                                                                .onSurface,
                                                            fontSize: 15.5,
                                                            fontWeight:
                                                                FontWeight.w600,
                                                          ),
                                                        ),
                                                      ),
                                                      PeerBadgesRow(
                                                        isBot: chat.isBot,
                                                        isVerified:
                                                            chat.isVerified,
                                                        verifiedIconSize: 15,
                                                      ),
                                                    ],
                                                  ),
                                                  const SizedBox(height: 2),
                                                  Text(
                                                    subtitle,
                                                    maxLines: 1,
                                                    overflow:
                                                        TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                      color: palette.subtext,
                                                      fontSize: 12.5,
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            iconoir.NavArrowRight(
                                              width: 18,
                                              height: 18,
                                              color: palette.subtext
                                                  .withValues(alpha: 0.72),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
