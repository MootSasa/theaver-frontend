import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import '../../services/liquid_glass_provider.dart';

/// Компактная центрированная капсула музыкального статуса (`♪ Название трека - Автор >`).
///
/// Располагается по центру между круглыми кнопками быстрых действий и информационной панелью.
/// Если музыка не установлена — виджет не отображается (`SizedBox.shrink()`).
class LiquidGlassMusicStatus extends StatelessWidget {
  /// Включён ли стеклянный дизайн (полный или облегчённый)
  final bool enabled;

  /// Включён ли облегчённый режим (FakeGlass вместо LiquidGlass)
  final bool isLite;

  /// Название трека (если null или пусто — виджет скрыт)
  final String? trackTitle;

  /// Автор песни
  final String? trackAuthor;

  /// Коллбэк при нажатии на капсулу
  final VoidCallback? onTap;

  /// Активен ли цветной/градиентный пресет профиля
  final bool hasColoredTheme;

  /// Локализованная подпись «Музыка» (сохранена для обратной совместимости)
  final String musicLabel;

  const LiquidGlassMusicStatus({
    Key? key,
    required this.enabled,
    this.isLite = false,
    this.hasColoredTheme = false,
    this.trackTitle,
    this.trackAuthor,
    this.onTap,
    this.musicLabel = 'Музыка',
  }) : super(key: key);

  String get _formattedText {
    final title = (trackTitle ?? '').trim();
    final author = (trackAuthor ?? '').trim();
    if (author.isNotEmpty) {
      return '$title - $author';
    }
    return title;
  }

  @override
  Widget build(BuildContext context) {
    if (trackTitle == null || trackTitle!.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.82,
        ),
        child: enabled
            ? _buildGlassPill(context)
            : _buildClassicPill(context),
      ),
    );
  }

  Widget _buildPillRow(Color textColor, Color mutedColor) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        iconoir.MusicDoubleNote(
          width: 14,
          height: 14,
          color: mutedColor,
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            _formattedText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
              color: textColor,
              letterSpacing: -0.1,
            ),
          ),
        ),
        const SizedBox(width: 4),
        iconoir.NavArrowRight(
          width: 14,
          height: 14,
          color: mutedColor,
        ),
      ],
    );
  }

  Widget _buildGlassPill(BuildContext context) {
    final isDark =
        Theme.of(context).brightness == Brightness.dark || hasColoredTheme;
    final glassProvider = context.watch<LiquidGlassProvider>();
    final glassStyle = glassProvider.createStyle(
      context: context,
      isDarkOverride: isDark,
      isLiteOverride: isLite,
      color: isDark ? const Color(0x33202025) : const Color(0x66FFFFFF),
      refractionIndex: 1.15,
      refractionWidth: 22.0,
      shape: const LiquidGlassShape.roundedRectangle(
        cornerRadius: 15,
      ),
    );

    final textColor = isDark
        ? Colors.white.withValues(alpha: 0.9)
        : Colors.black.withValues(alpha: 0.85);
    final mutedColor = isDark
        ? Colors.white.withValues(alpha: 0.65)
        : Colors.black.withValues(alpha: 0.55);

    final content = Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: isDark
          ? null
          : BoxDecoration(
              borderRadius: BorderRadius.circular(15),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
      child: _buildPillRow(textColor, mutedColor),
    );

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: LiquidGlassLens(
        style: glassStyle,
        child: content,
      ),
    );
  }

  Widget _buildClassicPill(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark || hasColoredTheme;
    final textColor = isDark
        ? Colors.white.withValues(alpha: 0.92)
        : theme.colorScheme.onSurface;
    final mutedColor = isDark
        ? Colors.white.withValues(alpha: 0.68)
        : theme.colorScheme.onSurfaceVariant;

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(15),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              height: 30,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0x992C2C2E)
                    : const Color(0xB3FFFFFF),
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: isDark
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
              child: _buildPillRow(textColor, mutedColor),
            ),
          ),
        ),
      ),
    );
  }
}
