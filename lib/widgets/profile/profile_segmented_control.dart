import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';

import '../../services/liquid_glass_provider.dart';
import '../../services/profile_theme_provider.dart';
import '../../utils/haptic_utils.dart';

/// Сегментированный переключатель (Segmented Control) для профиля и настроек оформления.
///
/// Поддерживает произвольное число вкладок (`labels`) и два режима дизайна:
/// - **Liquid Glass** (стеклянный дизайн с опцией lite)
/// - **Modern / Standard** (классический капсульный сегмент со скользящим ползунком)
class ProfileSegmentedControl extends StatelessWidget {
  /// Включён ли стеклянный дизайн Liquid Glass
  final bool enabled;

  /// Включён ли облегчённый стеклянный режим
  final bool isLite;

  /// Индекс выбранной вкладки (`0 .. labels.length - 1`)
  final int selectedIndex;

  /// Колбэк при переключении вкладки
  final ValueChanged<int> onTabChanged;

  /// Текст для первой вкладки (обратная совместимость для 2-секционного режима)
  final String wallLabel;

  /// Текст для второй вкладки (обратная совместимость для 2-секционного режима)
  final String giftsLabel;

  /// Произвольный список вкладок (например, 3 вкладки на экране «Оформление профиля»)
  final List<String>? labels;

  /// Высота переключателя (по умолчанию `30.0`)
  final double height;

  /// Использовать ли нейтральную палитру настроек вместо оттенка обложки профиля
  final bool neutralSurface;

  /// Опциональный пресет цвета профиля (например, для предпросмотра)
  final ProfileColorPreset? customPreset;

  const ProfileSegmentedControl({
    Key? key,
    required this.enabled,
    this.isLite = false,
    required this.selectedIndex,
    required this.onTabChanged,
    this.wallLabel = 'Стена',
    this.giftsLabel = 'Подарки',
    this.labels,
    this.height = 30.0,
    this.neutralSurface = false,
    this.customPreset,
  }) : super(key: key);

  List<String> get _effectiveLabels =>
      (labels != null && labels!.isNotEmpty) ? labels! : [wallLabel, giftsLabel];

  static Alignment _indicatorAlignment(int count, int clampedIndex) {
    if (count <= 1) return Alignment.center;
    final x = -1.0 + 2.0 * (clampedIndex / (count - 1));
    return Alignment(x, 0.0);
  }

  ProfileThemeProvider? _maybeWatchProfileTheme(BuildContext context) {
    try {
      return context.watch<ProfileThemeProvider>();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (enabled) {
      return _buildGlassSegmentedControl(context);
    }
    return _buildClassicSegmentedControl(context);
  }

  /// Классический капсульный дизайн со скользящим ползунком
  Widget _buildClassicSegmentedControl(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final items = _effectiveLabels;
    final count = items.length;
    final clamped = selectedIndex.clamp(0, count - 1);
    final outerRadius = height / 2.0;
    final innerRadius = (height - 4.0).clamp(8.0, 999.0) / 2.0;

    final ProfileThemeProvider? profileTheme =
        neutralSurface ? null : _maybeWatchProfileTheme(context);
    final preset =
        neutralSurface ? null : (customPreset ?? profileTheme?.currentPreset);
    final hasCustom = !neutralSurface &&
        (preset != null || (profileTheme?.hasCustomColor ?? false));

    final Color containerBg;
    final Color indicatorBg;
    final Gradient? indicatorGradient;
    final Color selectedTextColor;
    final Color unselectedTextColor;

    if (neutralSurface) {
      containerBg = isDark
          ? Colors.white.withValues(alpha: 0.07)
          : Colors.black.withValues(alpha: 0.055);
      indicatorBg = isDark ? const Color(0xFF2C2C32) : Colors.white;
      indicatorGradient = null;
      selectedTextColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
      unselectedTextColor = isDark
          ? Colors.white.withValues(alpha: 0.58)
          : Colors.black.withValues(alpha: 0.55);
    } else {
      containerBg = hasCustom && preset != null
          ? preset.ringColor.withValues(alpha: isDark ? 0.2 : 0.15)
          : (isDark
              ? Colors.white.withValues(alpha: 0.1)
              : const Color(0xFFEFEFF4));
      indicatorBg = hasCustom && preset != null
          ? preset.ringColor.withValues(alpha: isDark ? 0.85 : 0.95)
          : (isDark ? const Color(0xFF3A3A3C) : Colors.white);
      indicatorGradient =
          (hasCustom && preset != null && preset.isGradient && preset.gradientColors != null)
              ? LinearGradient(
                  colors: preset.gradientColors!,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                )
              : null;
      selectedTextColor = customPreset != null
          ? Colors.white
          : (hasCustom
              ? (indicatorBg.computeLuminance() > 0.5
                  ? Colors.black87
                  : Colors.white)
              : (isDark ? Colors.white : Colors.black));
      unselectedTextColor = customPreset != null
          ? Colors.white.withValues(alpha: 0.7)
          : (hasCustom
              ? (isDark
                  ? Colors.white.withValues(alpha: 0.65)
                  : Colors.black.withValues(alpha: 0.6))
              : (isDark
                  ? Colors.white.withValues(alpha: 0.55)
                  : Colors.black.withValues(alpha: 0.55)));
    }

    final indicatorShadow = isDark
        ? [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ]
        : [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.10),
              blurRadius: 4,
              offset: const Offset(0, 1.5),
            ),
          ];

    return Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: containerBg,
        borderRadius: BorderRadius.circular(outerRadius),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = constraints.maxWidth / count;

          return Stack(
            children: [
              AnimatedAlign(
                alignment: _indicatorAlignment(count, clamped),
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: Container(
                  width: tabWidth,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: indicatorGradient == null ? indicatorBg : null,
                    gradient: indicatorGradient,
                    borderRadius: BorderRadius.circular(innerRadius),
                    boxShadow: indicatorShadow,
                  ),
                ),
              ),
              Row(
                children: [
                  for (int i = 0; i < count; i++)
                    Expanded(
                      child: _SegmentTab(
                        label: items[i],
                        isSelected: clamped == i,
                        selectedColor: selectedTextColor,
                        unselectedColor: unselectedTextColor,
                        isDark: isDark,
                        onTap: () {
                          if (clamped != i) {
                            HapticUtils.selection();
                            onTabChanged(i);
                          }
                        },
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  /// Liquid Glass дизайн со скользящим стеклянным ползунком
  Widget _buildGlassSegmentedControl(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = _effectiveLabels;
    final count = items.length;
    final clamped = selectedIndex.clamp(0, count - 1);
    final outerRadius = height / 2.0;
    final innerRadius = (height - 4.0).clamp(8.0, 999.0) / 2.0;

    final ProfileThemeProvider? profileTheme =
        neutralSurface ? null : _maybeWatchProfileTheme(context);
    final preset =
        neutralSurface ? null : (customPreset ?? profileTheme?.currentPreset);
    final hasCustom = !neutralSurface &&
        (preset != null || (profileTheme?.hasCustomColor ?? false));

    final Color glassIndicatorColor;
    final Color glassIndicatorBorderColor;
    final Color selectedTextColor;
    final Color unselectedTextColor;

    if (neutralSurface) {
      glassIndicatorColor = isDark
          ? Colors.white.withValues(alpha: 0.18)
          : Colors.white.withValues(alpha: 0.80);
      glassIndicatorBorderColor = isDark
          ? Colors.white.withValues(alpha: 0.24)
          : Colors.white.withValues(alpha: 0.92);
      selectedTextColor = isDark ? Colors.white : const Color(0xFF1C1C1E);
      unselectedTextColor = isDark
          ? Colors.white.withValues(alpha: 0.58)
          : Colors.black.withValues(alpha: 0.55);
    } else {
      glassIndicatorColor = customPreset != null
          ? Colors.white.withValues(alpha: 0.25)
          : (hasCustom && preset != null
              ? preset.ringColor.withValues(alpha: isDark ? 0.35 : 0.45)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.18)
                  : Colors.white.withValues(alpha: 0.65)));

      glassIndicatorBorderColor = customPreset != null
          ? Colors.white.withValues(alpha: 0.4)
          : (hasCustom && preset != null
              ? preset.statusColor.withValues(alpha: isDark ? 0.5 : 0.8)
              : (isDark
                  ? Colors.white.withValues(alpha: 0.2)
                  : Colors.white.withValues(alpha: 0.9)));

      selectedTextColor = customPreset != null
          ? Colors.white
          : (hasCustom && preset != null
              ? preset.statusColor
              : (isDark ? Colors.white : Colors.black));

      unselectedTextColor = customPreset != null
          ? Colors.white.withValues(alpha: 0.7)
          : (hasCustom
              ? (isDark
                  ? Colors.white.withValues(alpha: 0.65)
                  : Colors.black.withValues(alpha: 0.6))
              : (isDark
                  ? Colors.white.withValues(alpha: 0.55)
                  : Colors.black.withValues(alpha: 0.55)));
    }

    final glassContent = Container(
      height: height,
      width: double.infinity,
      padding: const EdgeInsets.all(2),
      decoration: (isDark && !hasCustom && !neutralSurface)
          ? null
          : BoxDecoration(
              borderRadius: BorderRadius.circular(outerRadius),
              border: Border.all(
                color: hasCustom && preset != null
                    ? preset.ringColor.withValues(alpha: 0.25)
                    : (isDark
                        ? Colors.white.withValues(alpha: 0.10)
                        : Colors.black.withValues(alpha: 0.08)),
                width: 0.5,
              ),
            ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = constraints.maxWidth / count;

          return Stack(
            children: [
              AnimatedAlign(
                alignment: _indicatorAlignment(count, clamped),
                duration: const Duration(milliseconds: 240),
                curve: Curves.easeOutCubic,
                child: Container(
                  width: tabWidth,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: glassIndicatorColor,
                    borderRadius: BorderRadius.circular(innerRadius),
                    border: Border.all(
                      color: glassIndicatorBorderColor,
                      width: 0.8,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: isDark
                            ? Colors.black.withValues(alpha: 0.3)
                            : Colors.black.withValues(alpha: 0.08),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
              Row(
                children: [
                  for (int i = 0; i < count; i++)
                    Expanded(
                      child: _SegmentTab(
                        label: items[i],
                        isSelected: clamped == i,
                        selectedColor: selectedTextColor,
                        unselectedColor: unselectedTextColor,
                        isDark: isDark,
                        isGlass: true,
                        onTap: () {
                          if (clamped != i) {
                            HapticUtils.selection();
                            onTabChanged(i);
                          }
                        },
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );

    final glassProvider = context.watch<LiquidGlassProvider>();
    final glassStyle = glassProvider.createStyle(
      context: context,
      isLiteOverride: isLite,
      shape: LiquidGlassShape.roundedRectangle(
        cornerRadius: outerRadius,
      ),
    );

    return LiquidGlassLens(
      style: glassStyle,
      child: glassContent,
    );
  }
}

/// Виджет отдельной вкладки сегмента
class _SegmentTab extends StatelessWidget {
  final String label;
  final bool isSelected;
  final Color? selectedColor;
  final Color? unselectedColor;
  final bool isDark;
  final bool isGlass;
  final VoidCallback onTap;

  const _SegmentTab({
    Key? key,
    required this.label,
    required this.isSelected,
    this.selectedColor,
    this.unselectedColor,
    required this.isDark,
    this.isGlass = false,
    required this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final Color textColor;
    if (isSelected) {
      textColor = selectedColor ?? (isDark ? Colors.white : Colors.black);
    } else {
      textColor = unselectedColor ??
          (isDark
              ? Colors.white.withValues(alpha: 0.55)
              : Colors.black.withValues(alpha: 0.55));
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 6),
          child: AnimatedDefaultTextStyle(
            duration: const Duration(milliseconds: 150),
            style: TextStyle(
              color: textColor,
              fontSize: 13.5,
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              letterSpacing: -0.1,
            ),
            child: Text(
              label,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ),
      ),
    );
  }
}
