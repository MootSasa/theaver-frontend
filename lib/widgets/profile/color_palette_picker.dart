import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:ios_color_picker/show_ios_color_picker.dart';

import '../../services/profile_theme_provider.dart';
import '../../utils/haptic_utils.dart';
import '../common/glass_modal_sheet.dart';

/// Виджет горизонтальной двухрядной палитры круглых цветов обложки профиля.
class ColorPalettePicker extends StatefulWidget {
  final ProfileColorPreset? selectedPreset;
  final ValueChanged<ProfileColorPreset> onSelect;
  final VoidCallback? onPickCustomColor;
  final EdgeInsetsGeometry horizontalPadding;

  const ColorPalettePicker({
    Key? key,
    required this.selectedPreset,
    required this.onSelect,
    this.onPickCustomColor,
    this.horizontalPadding = const EdgeInsets.symmetric(horizontal: 16),
  }) : super(key: key);

  @override
  State<ColorPalettePicker> createState() => _ColorPalettePickerState();
}

class _ColorPalettePickerState extends State<ColorPalettePicker> {
  final IOSColorPickerController _colorPickerController =
      IOSColorPickerController();

  @override
  void dispose() {
    _colorPickerController.dispose();
    super.dispose();
  }

  void _openColorPicker() {
    if (widget.onPickCustomColor != null) {
      widget.onPickCustomColor!();
      return;
    }
    HapticUtils.selection();

    final startingColor = (widget.selectedPreset?.isCustom == true &&
                widget.selectedPreset?.isGradient != true
            ? widget.selectedPreset!.backgroundColor
            : (widget.selectedPreset?.backgroundColor ??
                const Color(0xFF2B82C9)))
        .withValues(alpha: 1.0);

    _colorPickerController.showIOSCustomColorPicker(
      context: context,
      startingColor: startingColor,
      onColorChanged: (color) {
        final opaqueColor = color.withValues(alpha: 1.0);
        widget.onSelect(ProfileColorPreset.fromCustomColor(opaqueColor));
      },
    );
  }

  void _openGradientColorPicker() {
    HapticUtils.selection();

    Color color1 = const Color(0xFF5AB6F0);
    Color color2 = const Color(0xFF2575C0);

    if (widget.selectedPreset?.isCustom == true &&
        widget.selectedPreset?.isGradient == true &&
        widget.selectedPreset?.gradientColors != null &&
        widget.selectedPreset!.gradientColors!.length >= 2) {
      color1 = widget.selectedPreset!.gradientColors![0];
      color2 = widget.selectedPreset!.gradientColors![1];
    }

    _showGradientPickerSheet(context, color1, color2);
  }

  void _showGradientPickerSheet(
    BuildContext context,
    Color initialColor1,
    Color initialColor2,
  ) {
    Color c1 = initialColor1.withValues(alpha: 1.0);
    Color c2 = initialColor2.withValues(alpha: 1.0);

    widget.onSelect(ProfileColorPreset.fromCustomGradient(c1, c2));

    showTheavGlassModalSheet<void>(
      context: context,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        final isDark = theme.brightness == Brightness.dark;
        final borderSwatchColor = isDark
            ? Colors.white.withValues(alpha: 0.38)
            : Colors.black.withValues(alpha: 0.16);

        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  translateOrFallback(
                    ctx,
                    'customizationGradientSheetTitle',
                    'Two-Color Gradient',
                  ),
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 18),
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [c1, c1, c2, c2],
                      stops: const [0.0, 0.5, 0.5, 1.0],
                      transform: const GradientRotation(-math.pi / 4),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.22),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 22),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    GestureDetector(
                      onTap: () {
                        HapticUtils.selection();
                        _colorPickerController.showIOSCustomColorPicker(
                          context: ctx,
                          startingColor: c1,
                          onColorChanged: (newColor) {
                            final opaque = newColor.withValues(alpha: 1.0);
                            setSheetState(() => c1 = opaque);
                            widget.onSelect(
                              ProfileColorPreset.fromCustomGradient(c1, c2),
                            );
                          },
                        );
                      },
                      child: Column(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: c1,
                              border: Border.all(
                                color: borderSwatchColor,
                                width: 2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            translateOrFallback(
                              ctx,
                              'customizationFirstColor',
                              'First color',
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.swap_horiz_rounded,
                      color: theme.colorScheme.onSurfaceVariant
                          .withValues(alpha: 0.6),
                      size: 26,
                    ),
                    GestureDetector(
                      onTap: () {
                        HapticUtils.selection();
                        _colorPickerController.showIOSCustomColorPicker(
                          context: ctx,
                          startingColor: c2,
                          onColorChanged: (newColor) {
                            final opaque = newColor.withValues(alpha: 1.0);
                            setSheetState(() => c2 = opaque);
                            widget.onSelect(
                              ProfileColorPreset.fromCustomGradient(c1, c2),
                            );
                          },
                        );
                      },
                      child: Column(
                        children: [
                          Container(
                            width: 46,
                            height: 46,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: c2,
                              border: Border.all(
                                color: borderSwatchColor,
                                width: 2,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            translateOrFallback(
                              ctx,
                              'customizationSecondColor',
                              'Second color',
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    style: TextButton.styleFrom(
                      backgroundColor:
                          theme.colorScheme.primary.withValues(alpha: 0.12),
                      foregroundColor: theme.colorScheme.primary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    onPressed: () => Navigator.pop(ctx),
                    child: Text(
                      translateOrFallback(ctx, 'ok', 'OK'),
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: widget.horizontalPadding,
            itemCount: ProfileColorPresets.row1Solids.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index < ProfileColorPresets.row1Solids.length) {
                final preset = ProfileColorPresets.row1Solids[index];
                return _buildColorCircle(
                  context: context,
                  preset: preset,
                  isSelected: widget.selectedPreset?.id == preset.id,
                  isDark: isDark,
                );
              }
              final isCustomSolidSelected =
                  widget.selectedPreset?.isCustom == true &&
                      widget.selectedPreset?.isGradient != true;
              return _buildCustomColorButton(
                context: context,
                isSelected: isCustomSolidSelected,
                isDark: isDark,
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        SizedBox(
          height: 44,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: widget.horizontalPadding,
            itemCount: ProfileColorPresets.row2Gradients.length + 1,
            separatorBuilder: (_, __) => const SizedBox(width: 10),
            itemBuilder: (context, index) {
              if (index < ProfileColorPresets.row2Gradients.length) {
                final preset = ProfileColorPresets.row2Gradients[index];
                return _buildColorCircle(
                  context: context,
                  preset: preset,
                  isSelected: widget.selectedPreset?.id == preset.id,
                  isDark: isDark,
                );
              }
              final isCustomGradientSelected =
                  widget.selectedPreset?.isCustom == true &&
                      widget.selectedPreset?.isGradient == true;
              return _buildCustomGradientColorButton(
                context: context,
                isSelected: isCustomGradientSelected,
                isDark: isDark,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildColorCircle({
    required BuildContext context,
    required ProfileColorPreset preset,
    required bool isSelected,
    required bool isDark,
  }) {
    const size = 36.0;

    final Widget circleContent = preset.isGradient
        ? Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                colors: [
                  preset.gradientColors![0],
                  preset.gradientColors![0],
                  preset.gradientColors![1],
                  preset.gradientColors![1],
                ],
                stops: const [0.0, 0.5, 0.5, 1.0],
                transform: const GradientRotation(-math.pi / 4),
              ),
            ),
          )
        : Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: preset.backgroundColor,
            ),
          );

    if (isSelected) {
      final ringColor = (!isDark && preset.ringColor.computeLuminance() > 0.72)
          ? preset.backgroundColor
          : preset.ringColor;

      return GestureDetector(
        onTap: () {
          HapticUtils.selection();
          widget.onSelect(preset);
        },
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
      onTap: () {
        HapticUtils.selection();
        widget.onSelect(preset);
      },
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
  }) {
    const size = 36.0;
    final theme = Theme.of(context);

    final child = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: isSelected && widget.selectedPreset?.isCustom == true
            ? null
            : const SweepGradient(
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
        color: isSelected && widget.selectedPreset?.isCustom == true
            ? widget.selectedPreset!.backgroundColor
            : null,
      ),
      child: const Center(
        child: Icon(
          Icons.palette_rounded,
          size: 18,
          color: Colors.white,
        ),
      ),
    );

    if (isSelected) {
      return GestureDetector(
        onTap: _openColorPicker,
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
      onTap: _openColorPicker,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: child,
      ),
    );
  }

  Widget _buildCustomGradientColorButton({
    required BuildContext context,
    required bool isSelected,
    required bool isDark,
  }) {
    const size = 36.0;
    final theme = Theme.of(context);

    List<Color> colors = [const Color(0xFF5AB6F0), const Color(0xFF2575C0)];

    if (isSelected &&
        widget.selectedPreset?.isCustom == true &&
        widget.selectedPreset?.isGradient == true &&
        widget.selectedPreset?.gradientColors != null &&
        widget.selectedPreset!.gradientColors!.length >= 2) {
      colors = widget.selectedPreset!.gradientColors!;
    }

    final child = Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [colors[0], colors[0], colors[1], colors[1]],
          stops: const [0.0, 0.5, 0.5, 1.0],
          transform: const GradientRotation(-math.pi / 4),
        ),
      ),
      child: Center(
        child: Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.35),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.palette_rounded,
            size: 14,
            color: Colors.white,
          ),
        ),
      ),
    );

    if (isSelected) {
      return GestureDetector(
        onTap: _openGradientColorPicker,
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
      onTap: _openGradientColorPicker,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.all(3),
        child: child,
      ),
    );
  }
}
