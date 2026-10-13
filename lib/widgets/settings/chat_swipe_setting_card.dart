import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../services/chat_swipe_service.dart';
import '../../utils/haptic_utils.dart';

/// Interactive Telegram-style Chat Swipe gesture setting card
/// matching the user's mockup design.
class ChatSwipeSettingCard extends StatefulWidget {
  const ChatSwipeSettingCard({Key? key}) : super(key: key);

  @override
  State<ChatSwipeSettingCard> createState() => _ChatSwipeSettingCardState();
}

class _ChatSwipeSettingCardState extends State<ChatSwipeSettingCard> {
  final ChatSwipeService _swipeService = ChatSwipeService();

  @override
  void initState() {
    super.initState();
    _swipeService.addListener(_onServiceChanged);
  }

  @override
  void dispose() {
    _swipeService.removeListener(_onServiceChanged);
    super.dispose();
  }

  void _onServiceChanged() {
    if (mounted) setState(() {});
  }

  Widget _getActionIcon(ChatSwipeAction action, Color color, double size) {
    switch (action) {
      case ChatSwipeAction.pin:
        return iconoir.Pin(key: const ValueKey('pin'), color: color, width: size, height: size);
      case ChatSwipeAction.read:
        return iconoir.ChatBubble(key: const ValueKey('read'), color: color, width: size, height: size);
      case ChatSwipeAction.archive:
        return iconoir.Archive(key: const ValueKey('archive'), color: color, width: size, height: size);
      case ChatSwipeAction.mute:
        return iconoir.BellOff(key: const ValueKey('mute'), color: color, width: size, height: size);
      case ChatSwipeAction.delete:
        return iconoir.Trash(key: const ValueKey('delete'), color: color, width: size, height: size);
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentAction = _swipeService.action;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E232A) : const Color(0xFFF2F4F7);
    final innerChatBg = isDark ? const Color(0xFF15181C) : Colors.white;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cardBg,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(
                color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.05),
                width: 0.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Header in warm amber / gold matching screenshot
                const Text(
                  'Смахивание влево в списке чатов',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFE5B567),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    // Left Column: Live Animated Mockup Preview of swiped chat
                    Expanded(
                      flex: 11,
                      child: Container(
                        height: 64,
                        decoration: BoxDecoration(
                          color: innerChatBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05),
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: Row(
                          children: [
                            // Left part of mock chat: Avatar + placeholder text lines
                            Expanded(
                              flex: 12,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Row(
                                  children: [
                                    Container(
                                      width: 32,
                                      height: 32,
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF5D4037) : Colors.grey[400],
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Container(
                                            height: 6,
                                            width: 40,
                                            decoration: BoxDecoration(
                                              color: isDark ? const Color(0xFF4A443F) : Colors.grey[400],
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                          ),
                                          const SizedBox(height: 6),
                                          Container(
                                            height: 6,
                                            width: double.infinity,
                                            decoration: BoxDecoration(
                                              color: isDark ? const Color(0xFF38332E) : Colors.grey[300],
                                              borderRadius: BorderRadius.circular(3),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            // Right revealed action container
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.easeOutCubic,
                              width: 54,
                              height: double.infinity,
                              color: currentAction.color,
                              child: Center(
                                child: AnimatedSwitcher(
                                  duration: const Duration(milliseconds: 200),
                                  child: _getActionIcon(currentAction, Colors.white, 24),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 14),
                    // Right Column: Vertical list / selector of actions
                    Expanded(
                      flex: 10,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          for (int i = 0; i < ChatSwipeAction.values.length; i++) ...[
                            if (i > 0)
                              Divider(
                                height: 1,
                                thickness: 0.6,
                                color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.1),
                              ),
                            InkWell(
                              onTap: () {
                                HapticUtils.selection();
                                _swipeService.setAction(ChatSwipeAction.values[i]);
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                                child: Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    ChatSwipeAction.values[i].label,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: currentAction == ChatSwipeAction.values[i]
                                          ? FontWeight.w700
                                          : FontWeight.normal,
                                      color: currentAction == ChatSwipeAction.values[i]
                                          ? (isDark ? Colors.white : Colors.black87)
                                          : (isDark ? Colors.white38 : Colors.black38),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              'Выбор действия, которое будет выполняться при смахивании влево в списке чатов.',
              style: TextStyle(
                fontSize: 12.5,
                color: isDark ? Colors.grey[400] : Colors.grey[600],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
