import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../models/theav_theme.dart';
import '../../utils/emoji_utils.dart';
import 'sticker_item_widget.dart';

/// Панель реакций — появляется при длинном нажатии на сообщение.
class ReactionsPanel extends StatelessWidget {
  final Function(String emoji) onReactionSelected;

  static const _defaultReactions = ['❤️', '👍', '😱', '😂', '😢', '🔥', '👏', '🎉'];

  const ReactionsPanel({Key? key, required this.onReactionSelected}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 48,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 8, offset: const Offset(0, 2)),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: _defaultReactions.map((emoji) => InkWell(
          onTap: () => onReactionSelected(emoji),
          borderRadius: BorderRadius.circular(20),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: EmojiUtils.appleEmoji(emoji, size: 22),
          ),
        )).toList(),
      ),
    );
  }
}

/// Отображение реакций под сообщением с плавной анимацией добавления и удаления
class MessageReactionsRow extends StatefulWidget {
  final Map<String, int> reactions; // emoji (or 'custom:<id>') → count
  final Set<String>? myReactions; // emoji, выбранные текущим пользователем
  final String? myReaction; // обратная совместимость для одиночной реакции
  final Function(String emoji)? onTap;
  final Map<String, List<Map<String, dynamic>>>? reactionUsers;

  const MessageReactionsRow({
    Key? key,
    required this.reactions,
    this.myReactions,
    this.myReaction,
    this.onTap,
    this.reactionUsers,
  }) : super(key: key);

  @override
  State<MessageReactionsRow> createState() => _MessageReactionsRowState();
}

class _ReactionItemEntry {
  final String emoji;
  int count;
  bool isMine;
  final AnimationController controller;
  bool isExiting = false;

  _ReactionItemEntry({
    required this.emoji,
    required this.count,
    required this.isMine,
    required this.controller,
  });
}

class _MessageReactionsRowState extends State<MessageReactionsRow>
    with TickerProviderStateMixin {
  final List<_ReactionItemEntry> _items = [];

  Set<String> _getEffectiveMyReactions() {
    if (widget.myReactions != null) {
      return widget.myReactions!;
    }
    if (widget.myReaction != null && widget.myReaction!.isNotEmpty) {
      return {widget.myReaction!};
    }
    return const {};
  }

  @override
  void initState() {
    super.initState();
    final myReactions = _getEffectiveMyReactions();
    for (final entry in widget.reactions.entries) {
      if (entry.value > 0) {
        final controller = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 250),
          value: 1.0,
        );
        _items.add(_ReactionItemEntry(
          emoji: entry.key,
          count: entry.value,
          isMine: myReactions.contains(entry.key),
          controller: controller,
        ));
      }
    }
  }

  @override
  void didUpdateWidget(MessageReactionsRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final myReactions = _getEffectiveMyReactions();
    final newMap = widget.reactions;

    // 1. Пометить на удаление отсутствующие реакции
    for (final item in _items) {
      final newCount = newMap[item.emoji] ?? 0;
      if (newCount <= 0) {
        if (!item.isExiting) {
          item.isExiting = true;
          item.controller.reverse().then((_) {
            if (mounted) {
              setState(() {
                _items.remove(item);
                item.controller.dispose();
              });
            }
          });
        }
      } else {
        item.count = newCount;
        item.isMine = myReactions.contains(item.emoji);
      }
    }

    // 2. Добавить новые реакции в начало списка (слева первой строки)
    final existingEmojis = _items.where((i) => !i.isExiting).map((i) => i.emoji).toSet();
    for (final entry in newMap.entries) {
      if (entry.value > 0 && !existingEmojis.contains(entry.key)) {
        final controller = AnimationController(
          vsync: this,
          duration: const Duration(milliseconds: 250),
        );
        final newEntry = _ReactionItemEntry(
          emoji: entry.key,
          count: entry.value,
          isMine: myReactions.contains(entry.key),
          controller: controller,
        );
        // Новый бейдж всегда вставляется слева (индекс 0)
        _items.insert(0, newEntry);
        controller.forward();
      }
    }
  }

  @override
  void dispose() {
    for (final item in _items) {
      item.controller.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_items.isEmpty) return const SizedBox.shrink();

    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: _items.map((item) {
        return KeyedSubtree(
          key: ValueKey(item.emoji),
          child: AnimatedBuilder(
            animation: item.controller,
            builder: (context, child) {
              if (item.controller.value == 0 && item.isExiting) {
                return const SizedBox.shrink();
              }
              return SizeTransition(
                sizeFactor: CurvedAnimation(
                  parent: item.controller,
                  curve: Curves.easeInOutCubic,
                ),
                axis: Axis.horizontal,
                axisAlignment: -1.0, // раскрывается слева направо, сжимается влево
                child: ScaleTransition(
                  scale: CurvedAnimation(
                    parent: item.controller,
                    curve: Curves.easeOutBack,
                  ),
                  child: FadeTransition(
                    opacity: CurvedAnimation(
                      parent: item.controller,
                      curve: Curves.easeIn,
                    ),
                    child: child,
                  ),
                ),
              );
            },
            child: _buildBadge(item),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildBadge(_ReactionItemEntry item) {
    final theme = Theme.of(context);
    final themeExt = theme.extension<TheavThemeExtension>();
    final p = themeExt?.palette;
    final colorScheme = theme.colorScheme;
    final isMine = item.isMine;

    final activeBg = p?.reactionActiveBackground ?? colorScheme.primaryContainer;
    final inactiveBg = p?.reactionInactiveBackground ?? colorScheme.surfaceContainerHighest;
    final activeText = p?.reactionActiveText ?? colorScheme.primary;
    final inactiveText = p?.subtext ?? (theme.brightness == Brightness.dark ? Colors.white60 : Colors.grey[600]!);

    final isCustom = item.emoji.startsWith('custom:');
    final customStickerId =
        isCustom ? item.emoji.substring('custom:'.length).trim() : '';

    return InkWell(
      onTap: () => widget.onTap?.call(item.emoji),
      onLongPress: () => _showReactionUsersSheet(context, item),
      borderRadius: BorderRadius.circular(12),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: isMine ? activeBg : inactiveBg,
          borderRadius: BorderRadius.circular(12),
          border: isMine
              ? Border.all(color: activeText, width: 1.2)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            isCustom
                ? InlineCustomEmojiWidget(
                    customEmojiId: customStickerId,
                    size: 16,
                    adaptiveTextColor: isMine ? activeText : inactiveText,
                  )
                : EmojiUtils.appleEmoji(item.emoji, size: 14),
            if (item.count > 1) ...[
              const SizedBox(width: 3),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                transitionBuilder: (child, anim) =>
                    ScaleTransition(scale: anim, child: child),
                child: Text(
                  '${item.count}',
                  key: ValueKey<int>(item.count),
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: isMine ? activeText : inactiveText,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showReactionUsersSheet(BuildContext context, _ReactionItemEntry item) {
    HapticFeedback.selectionClick();
    final theme = Theme.of(context);
    final users = widget.reactionUsers?[item.emoji] ?? const [];
    final isCustom = item.emoji.startsWith('custom:');
    final customId = isCustom ? item.emoji.substring('custom:'.length) : '';

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: theme.colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    isCustom
                        ? InlineCustomEmojiWidget(
                            customEmojiId: customId,
                            size: 22,
                          )
                        : EmojiUtils.appleEmoji(item.emoji, size: 22),
                    const SizedBox(width: 10),
                    Text(
                      'Реакции: ${item.count}',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
                if (users.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 6),
                  ...users.take(15).map((u) {
                    final name =
                        (u['display_name'] ?? u['username'] ?? 'Пользователь')
                            .toString();
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 6),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 12,
                            backgroundColor:
                                theme.colorScheme.primary.withValues(alpha: 0.2),
                            child: Text(
                              name.isNotEmpty ? name[0].toUpperCase() : '?',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.primary,
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              name,
                              style: TextStyle(
                                fontSize: 14,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
