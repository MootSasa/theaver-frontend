import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../models/name_color_preset.dart';
import '../common/glass_modal_sheet.dart';
import 'reply_strip_painter.dart';

/// Горизонтальный ряд выбора цвета имени в чатах.
class NameColorPaletteRow extends StatelessWidget {
  final NameColorPreset selectedPreset;
  final ReplyStripStyle selectedStyle;
  final ValueChanged<NameColorPreset> onPresetSelected;
  final VoidCallback onPickCustomColor;
  final EdgeInsetsGeometry padding;

  const NameColorPaletteRow({
    super.key,
    required this.selectedPreset,
    required this.selectedStyle,
    required this.onPresetSelected,
    required this.onPickCustomColor,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  Widget _buildNameColorCircle({
    required BuildContext context,
    required NameColorPreset preset,
    required ReplyStripStyle style,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    const size = 36.0;
    Widget circleContent;

    final c1 = preset.primaryColor;
    final c2 = preset.effectiveSecondary;
    final c3 = preset.effectiveTertiary;

    switch (style) {
      case ReplyStripStyle.solid:
        circleContent = Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: c1,
          ),
        );
        break;

      case ReplyStripStyle.dualColor:
      case ReplyStripStyle.segmented:
        circleContent = Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [c1, c1, c2, c2],
              stops: const [0.0, 0.5, 0.5, 1.0],
              transform: const GradientRotation(-math.pi / 4),
            ),
          ),
        );
        break;

      case ReplyStripStyle.candyCane:
        circleContent = Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(
              colors: [c1, c1, c2, c2],
              stops: const [0.0, 0.5, 0.5, 1.0],
              transform: const GradientRotation(-math.pi / 4),
            ),
          ),
          child: Center(
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: c3,
                border: Border.all(color: Colors.white30, width: 0.5),
              ),
            ),
          ),
        );
        break;
    }

    if (isSelected) {
      final ringColor = isDark ? Colors.white : c1;
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: size + 6,
          height: size + 6,
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: ringColor,
              width: 2.0,
            ),
          ),
          child: circleContent,
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: circleContent,
      ),
    );
  }

  Widget _buildCustomColorButton({
    required BuildContext context,
    required bool isSelected,
    required bool isDark,
    required VoidCallback onTap,
  }) {
    const size = 36.0;
    final theme = Theme.of(context);

    final child = Container(
      width: size,
      height: size,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: SweepGradient(
          colors: [
            Colors.red,
            Colors.yellow,
            Colors.green,
            Colors.cyan,
            Colors.blue,
            Colors.purple,
            Colors.red,
          ],
        ),
      ),
      child: const Icon(Icons.colorize, color: Colors.white, size: 18),
    );

    if (isSelected) {
      return GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: size + 6,
          height: size + 6,
          padding: const EdgeInsets.all(2.5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: isDark ? Colors.white : theme.colorScheme.primary,
              width: 2.0,
            ),
          ),
          child: child,
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isCustomSelected = selectedPreset.id.startsWith('custom_name_');

    return SizedBox(
      height: 44,
      child: ListView.separated(
        padding: padding,
        scrollDirection: Axis.horizontal,
        itemCount: NameColorPresets.defaults.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          if (index < NameColorPresets.defaults.length) {
            final preset = NameColorPresets.defaults[index];
            final isSelected = selectedPreset.id == preset.id;

            return _buildNameColorCircle(
              context: context,
              preset: preset,
              style: selectedStyle,
              isSelected: isSelected,
              isDark: isDark,
              onTap: () => onPresetSelected(preset),
            );
          }

          return _buildCustomColorButton(
            context: context,
            isSelected: isCustomSelected,
            isDark: isDark,
            onTap: onPickCustomColor,
          );
        },
      ),
    );
  }
}

/// 4-секционный выбор стиля полоски цитирования (адаптированный под светлую и тёмную темы).
class ReplyStripStyleSelector extends StatelessWidget {
  final NameColorPreset selectedPreset;
  final ReplyStripStyle selectedStyle;
  final ValueChanged<ReplyStripStyle> onStyleSelected;
  final EdgeInsetsGeometry padding;

  const ReplyStripStyleSelector({
    super.key,
    required this.selectedPreset,
    required this.selectedStyle,
    required this.onStyleSelected,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final unselectedBg = isDark
        ? Colors.white.withValues(alpha: 0.05)
        : Colors.black.withValues(alpha: 0.035);
    final unselectedBorder = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);

    return Padding(
      padding: padding,
      child: Row(
        children: ReplyStripStyle.values.map((style) {
          final isSelected = selectedStyle == style;

          return Expanded(
            child: GestureDetector(
              onTap: () => onStyleSelected(style),
              behavior: HitTestBehavior.opaque,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.symmetric(horizontal: 4),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: isSelected
                      ? selectedPreset.primaryColor
                          .withValues(alpha: isDark ? 0.18 : 0.12)
                      : unselectedBg,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isSelected
                        ? selectedPreset.primaryColor
                        : unselectedBorder,
                    width: isSelected ? 1.5 : 1.0,
                  ),
                ),
                child: Center(
                  child: ReplyStripWidget(
                    preset: selectedPreset,
                    style: style,
                    width: 5.5,
                    height: 28,
                    borderRadius: 2.5,
                  ),
                ),
              ),
            ),
          );
        }).toList(),
      ),
    );
  }
}

/// Составной виджет выбора цвета имени и стиля полоски цитирования.
class NameColorPicker extends StatelessWidget {
  final NameColorPreset selectedPreset;
  final ReplyStripStyle selectedStyle;
  final ValueChanged<NameColorPreset> onPresetSelected;
  final ValueChanged<ReplyStripStyle> onStyleSelected;
  final VoidCallback onPickCustomColor;
  final bool showSectionHeaders;

  const NameColorPicker({
    Key? key,
    required this.selectedPreset,
    required this.selectedStyle,
    required this.onPresetSelected,
    required this.onStyleSelected,
    required this.onPickCustomColor,
    this.showSectionHeaders = true,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final headerStyle = theme.textTheme.labelLarge?.copyWith(
      color: theme.colorScheme.primary,
      fontWeight: FontWeight.bold,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showSectionHeaders)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              translateOrFallback(
                context,
                'customizationNameColorTitle',
                'Name Color',
              ),
              style: headerStyle,
            ),
          ),
        NameColorPaletteRow(
          selectedPreset: selectedPreset,
          selectedStyle: selectedStyle,
          onPresetSelected: onPresetSelected,
          onPickCustomColor: onPickCustomColor,
        ),
        const SizedBox(height: 20),
        if (showSectionHeaders)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Text(
              translateOrFallback(
                context,
                'customizationReplyStripTitle',
                'Reply Strip Style',
              ),
              style: headerStyle,
            ),
          ),
        ReplyStripStyleSelector(
          selectedPreset: selectedPreset,
          selectedStyle: selectedStyle,
          onStyleSelected: onStyleSelected,
        ),
      ],
    );
  }
}
