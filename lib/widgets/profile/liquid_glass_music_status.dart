import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import '../../services/liquid_glass_provider.dart';

/// Горизонтальная стеклянная плашка музыкального статуса.
///
/// Показывает иконку ноты + название трека + автора песни.
/// Если музыка не установлена — виджет не отображается.
///
/// При нажатии — пока ничего не происходит (TODO: в будущем —
/// воспроизведение музыки другим пользователем).
class LiquidGlassMusicStatus extends StatelessWidget {
  /// Включён ли стеклянный дизайн (полный или облегчённый)
  final bool enabled;

  /// Включён ли облегчённый режим (FakeGlass вместо LiquidGlass)
  final bool isLite;

  /// Название трека (если null — виджет скрыт)
  final String? trackTitle;

  /// Автор песни
  final String? trackAuthor;

  /// Локализованная подпись «Музыка»
  final String musicLabel;

  const LiquidGlassMusicStatus({
    Key? key,
    required this.enabled,
    this.isLite = false,
    this.trackTitle,
    this.trackAuthor,
    this.musicLabel = 'Музыка',
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    // Если трек не установлен — не показываем виджет
    if (trackTitle == null || trackTitle!.isEmpty) {
      return const SizedBox.shrink();
    }

    if (enabled) {
      return _buildGlassStatus(context);
    }
    return _buildClassicStatus(context);
  }

  /// Стеклянная плашка
  Widget _buildGlassStatus(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final glassProvider = context.watch<LiquidGlassProvider>();
    final glassStyle = glassProvider.createStyle(
      context: context,
      isLiteOverride: isLite,
    );

    final statusContent = Container(
      height: 48,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      decoration: isDark
          ? null
          : BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.12),
                width: 0.5,
              ),
            ),
      child: Row(
        children: [
          // Иконка ноты
          Icon(
            Icons.music_note,
            size: 20,
            color: isDark ? Colors.white70 : const Color(0xFF0088CC),
          ),
          const SizedBox(width: 12),
          // Название трека + автор
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  trackTitle!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                    color: isDark ? Colors.white : Colors.black87,
                  ),
                ),
                if (trackAuthor != null && trackAuthor!.isNotEmpty)
                  Text(
                    trackAuthor!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: isDark ? Colors.white54 : Colors.black54,
                    ),
                  ),
              ],
            ),
          ),
          // Иконка «play» — задел на будущее
          Icon(
            Icons.play_circle_outline,
            size: 24,
            color: isDark ? Colors.white38 : const Color(0xFF0088CC).withValues(alpha: 0.5),
          ),
        ],
      ),
    );

    // TODO: при нажатии — воспроизведение музыки (задел на будущее)
    return GestureDetector(
      onTap: () {
        // TODO: реализовать воспроизведение музыки
      },
      child: LiquidGlassLens(
        style: glassStyle.copyWith(
          shape: const LiquidGlassShape.continuousRoundedRectangle(
            cornerRadius: 24,
          ),
        ),
        child: statusContent,
      ),
    );
  }

  /// Классическая плашка (без glass)
  Widget _buildClassicStatus(BuildContext context) {
    final theme = Theme.of(context);

    // TODO: при нажатии — воспроизведение музыки (задел на будущее)
    return GestureDetector(
      onTap: () {
        // TODO: реализовать воспроизведение музыки
      },
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
            color: theme.colorScheme.outline.withValues(alpha: 0.2),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.music_note,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    trackTitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  if (trackAuthor != null && trackAuthor!.isNotEmpty)
                    Text(
                      trackAuthor!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
            Icon(
              Icons.play_circle_outline,
              size: 24,
              color: theme.colorScheme.primary.withValues(alpha: 0.5),
            ),
          ],
        ),
      ),
    );
  }
}
