import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../services/chat_service.dart';

/// Compact glass banner displayed directly below the chat AppBar when the chat
/// has one or more pinned messages.
class PinnedMessageBanner extends StatelessWidget {
  final Message message;
  final int totalPinnedCount;
  final int currentPinnedIndex;
  final VoidCallback onTap;
  final VoidCallback? onUnpin;
  final bool canUnpin;

  const PinnedMessageBanner({
    super.key,
    required this.message,
    this.totalPinnedCount = 1,
    this.currentPinnedIndex = 0,
    required this.onTap,
    this.onUnpin,
    this.canUnpin = true,
  });

  String _formatPreview(Message msg) {
    final text = msg.content.trim();
    if (text.isNotEmpty) return text;
    switch (msg.messageType) {
      case 'image':
        return '📷 Фотография';
      case 'video':
        return msg.isRound ? '🎥 Видеосообщение' : '🎬 Видео';
      case 'voice':
        return '🎤 Голосовое сообщение';
      case 'audio':
        return '🎵 Аудиозапись';
      case 'poll':
        return '📊 Опрос';
      case 'file':
      case 'document':
        return '📎 ${msg.fileName ?? 'Файл'}';
      default:
        return 'Сообщение';
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primaryColor = theme.colorScheme.primary;

    final headerLabel = totalPinnedCount > 1
        ? 'Закреплённое сообщение #${currentPinnedIndex + 1}'
        : 'Закреплённое сообщение';

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Material(
          color: (isDark ? const Color(0xFF181B22) : Colors.white)
              .withValues(alpha: 0.84),
          child: InkWell(
            onTap: onTap,
            child: Container(
              height: 48,
              padding: const EdgeInsets.only(left: 12, right: 6),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(
                    color: theme.colorScheme.outlineVariant
                        .withValues(alpha: 0.22),
                    width: 0.8,
                  ),
                ),
              ),
              child: Row(
                children: [
                  // Vertical accent indicator bar (with multi-segment indicators if multiple pins exist)
                  SizedBox(
                    width: 3.5,
                    height: 32,
                    child: totalPinnedCount > 1
                        ? Column(
                            children: List.generate(
                              totalPinnedCount.clamp(1, 5),
                              (idx) {
                                final active = idx ==
                                    (currentPinnedIndex %
                                        totalPinnedCount.clamp(1, 5));
                                return Expanded(
                                  child: Container(
                                    margin: const EdgeInsets.symmetric(
                                      vertical: 1.0,
                                    ),
                                    decoration: BoxDecoration(
                                      color: active
                                          ? primaryColor
                                          : primaryColor.withValues(
                                              alpha: 0.28,
                                            ),
                                      borderRadius: BorderRadius.circular(2),
                                    ),
                                  ),
                                );
                              },
                            ),
                          )
                        : Container(
                            decoration: BoxDecoration(
                              color: primaryColor,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            iconoir.Pin(
                              width: 12,
                              height: 12,
                              color: primaryColor,
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                headerLabel,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: primaryColor,
                                  height: 1.15,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _formatPreview(message),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.85),
                            height: 1.15,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (canUnpin && onUnpin != null)
                    IconButton(
                      visualDensity: VisualDensity.compact,
                      tooltip: 'Открепить сообщение',
                      icon: iconoir.Xmark(
                        width: 18,
                        height: 18,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      onPressed: onUnpin,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
