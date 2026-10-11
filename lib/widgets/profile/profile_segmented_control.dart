import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';

import '../../services/liquid_glass_provider.dart';

import '../../services/profile_theme_provider.dart';
import '../../utils/haptic_utils.dart';

/// Сегментированный переключатель (Segmented Control) для профиля.
///
/// Поддерживает два режима дизайна:
/// - **Liquid Glass** (стеклянный премиум-дизайн с опцией lite)
/// - **Modern / Standard** (классический iOS-style капсульный сегмент)
class ProfileSegmentedControl extends StatelessWidget {
  /// Включён ли стеклянный дизайн Liquid Glass
  final bool enabled;

  /// Включён ли облегчённый стеклянный режим
  final bool isLite;

  /// Выбранная вкладка (0 - Стена, 1 - Подарки)
  final int selectedIndex;

  /// Колбэк при переключении вкладки
  final ValueChanged<int> onTabChanged;

  /// Текст для вкладки «Стена»
  final String wallLabel;

  /// Текст для вкладки «Подарки»
  final String giftsLabel;

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
    this.customPreset,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (enabled) {
      return _buildGlassSegmentedControl(context);
    }
    return _buildClassicSegmentedControl(context);
  }

  /// Классический (Modern) дизайн в стиле iOS
  Widget _buildClassicSegmentedControl(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profileTheme = context.watch<ProfileThemeProvider>();
    final preset = customPreset ?? profileTheme.currentPreset;
    final hasCustom = preset != null || profileTheme.hasCustomColor;

    final containerBg = hasCustom
        ? preset!.ringColor.withValues(alpha: isDark ? 0.2 : 0.15)
        : (isDark
            ? Colors.white.withValues(alpha: 0.1)
            : const Color(0xFFEFEFF4));

    final indicatorBg = hasCustom
        ? preset!.ringColor.withValues(alpha: isDark ? 0.85 : 0.95)
        : (isDark
            ? const Color(0xFF3A3A3C)
            : Colors.white);

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
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 4,
              offset: const Offset(0, 1.5),
            ),
          ];

    final Gradient? indicatorGradient = (hasCustom && preset!.isGradient && preset.gradientColors != null)
        ? LinearGradient(
            colors: preset.gradientColors!,
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          )
        : null;

    final selectedTextColor = customPreset != null
        ? Colors.white
        : (hasCustom
            ? (indicatorBg.computeLuminance() > 0.5 ? Colors.black87 : Colors.white)
            : (isDark ? Colors.white : Colors.black));

    final unselectedTextColor = customPreset != null
        ? Colors.white.withValues(alpha: 0.7)
        : (hasCustom
            ? (isDark ? Colors.white.withValues(alpha: 0.65) : Colors.black.withValues(alpha: 0.6))
            : (isDark ? Colors.white.withValues(alpha: 0.55) : Colors.black.withValues(alpha: 0.55)));

    return Container(
      height: 30,
      width: double.infinity,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: containerBg,
        borderRadius: BorderRadius.circular(15),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final tabWidth = (constraints.maxWidth) / 2;

          return Stack(
            children: [
              // Скользящий бегунок (активная вкладка)
              AnimatedAlign(
                alignment: selectedIndex == 0
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                child: Container(
                  width: tabWidth,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    color: indicatorGradient == null ? indicatorBg : null,
                    gradient: indicatorGradient,
                    borderRadius: BorderRadius.circular(13),
                    boxShadow: indicatorShadow,
                  ),
                ),
              ),

              // Вкладки
              Row(
                children: [
                  Expanded(
                    child: _SegmentTab(
                      label: wallLabel,
                      isSelected: selectedIndex == 0,
                      selectedColor: selectedTextColor,
                      unselectedColor: unselectedTextColor,
                      isDark: isDark,
                      onTap: () {
                        if (selectedIndex != 0) {
                          HapticUtils.selection();
                          onTabChanged(0);
                        }
                      },
                    ),
                  ),
                  Expanded(
                    child: _SegmentTab(
                      label: giftsLabel,
                      isSelected: selectedIndex == 1,
                      selectedColor: selectedTextColor,
                      unselectedColor: unselectedTextColor,
                      isDark: isDark,
                      onTap: () {
                        if (selectedIndex != 1) {
                          HapticUtils.selection();
                          onTabChanged(1);
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

  /// Премиальный Liquid Glass дизайн
  Widget _buildGlassSegmentedControl(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final profileTheme = context.watch<ProfileThemeProvider>();
    final preset = customPreset ?? profileTheme.currentPreset;
    final hasCustom = preset != null || profileTheme.hasCustomColor;


    final glassIndicatorColor = customPreset != null
        ? Colors.white.withValues(alpha: 0.25)
        : (hasCustom
            ? preset!.ringColor.withValues(alpha: isDark ? 0.35 : 0.45)
            : (isDark
                ? Colors.white.withValues(alpha: 0.18)
                : Colors.white.withValues(alpha: 0.65)));

    final glassIndicatorBorderColor = customPreset != null
        ? Colors.white.withValues(alpha: 0.4)
        : (hasCustom
            ? preset!.statusColor.withValues(alpha: isDark ? 0.5 : 0.8)
            : (isDark
                ? Colors.white.withValues(alpha: 0.2)
                : Colors.white.withValues(alpha: 0.9)));

    final selectedTextColor = customPreset != null
        ? Colors.white
        : (hasCustom
            ? preset!.statusColor
            : (isDark ? Colors.white : Colors.black));

    final unselectedTextColor = customPreset != null
        ? Colors.white.withValues(alpha: 0.7)
        : (hasCustom
            ? (isDark ? Colors.white.withValues(alpha: 0.65) : Colors.black.withValues(alpha: 0.6))
            : (isDark ? Colors.white.withValues(alpha: 0.55) : Colors.black.withValues(alpha: 0.55)));

    final glassContent = Container(
        height: 30,
        width: double.infinity,
        padding: const EdgeInsets.all(2),
        decoration: (isDark && !hasCustom)
            ? null
            : BoxDecoration(
                borderRadius: BorderRadius.circular(15),
                border: Border.all(
                  color: hasCustom
                      ? preset!.ringColor.withValues(alpha: 0.25)
                      : Colors.black.withValues(alpha: 0.12),
                  width: 0.5,
                ),
              ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final tabWidth = (constraints.maxWidth) / 2;

            return Stack(
              children: [
                // Скользящий стеклянный бегунок
                AnimatedAlign(
                  alignment: selectedIndex == 0
                      ? Alignment.centerLeft
                      : Alignment.centerRight,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOutCubic,
                  child: Container(
                    width: tabWidth,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: glassIndicatorColor,
                      borderRadius: BorderRadius.circular(13),
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

                // Вкладки
                Row(
                  children: [
                    Expanded(
                      child: _SegmentTab(
                        label: wallLabel,
                        isSelected: selectedIndex == 0,
                        selectedColor: selectedTextColor,
                        unselectedColor: unselectedTextColor,
                        isDark: isDark,
                        isGlass: true,
                        onTap: () {
                          if (selectedIndex != 0) {
                            HapticUtils.selection();
                            onTabChanged(0);
                          }
                        },
                      ),
                    ),
                    Expanded(
                      child: _SegmentTab(
                        label: giftsLabel,
                        isSelected: selectedIndex == 1,
                        selectedColor: selectedTextColor,
                        unselectedColor: unselectedTextColor,
                        isDark: isDark,
                        isGlass: true,
                        onTap: () {
                          if (selectedIndex != 1) {
                            HapticUtils.selection();
                            onTabChanged(1);
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
      shape: const LiquidGlassShape.roundedRectangle(
        cornerRadius: 15,
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
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 150),
          style: TextStyle(
            color: textColor,
            fontSize: 13,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
            fontFamily: '.SF Pro Text',
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ),
    );
  }
}
