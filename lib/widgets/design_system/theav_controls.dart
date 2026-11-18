import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../utils/haptic_utils.dart';
import 'theav_design_system.dart';

/// Descriptor for one option inside [TheavSegmentedControl].
class TheavSegmentOption<T> {
  final T value;
  final String label;
  final Widget? icon;

  const TheavSegmentOption({
    required this.value,
    required this.label,
    this.icon,
  });
}

/// Sliding pill segmented control supporting both Liquid Glass and Material Matte
/// modes without Material tab bar scaffolding.
class TheavSegmentedControl<T> extends StatelessWidget {
  final List<TheavSegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final double height;
  final EdgeInsetsGeometry margin;

  const TheavSegmentedControl({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.height = 38.0,
    this.margin = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    if (options.isEmpty) return const SizedBox.shrink();
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final int selectedIndex = options.indexWhere((o) => o.value == selected);
    final int activeIdx = selectedIndex < 0 ? 0 : selectedIndex;
    final double alignmentX = options.length <= 1
        ? 0.0
        : -1.0 + (2.0 * activeIdx / (options.length - 1));

    return Padding(
      padding: margin,
      child: Container(
        height: height,
        padding: const EdgeInsets.all(3.0),
        decoration: BoxDecoration(
          color: style.trackFill,
          borderRadius: BorderRadius.circular(height / 2),
          border: Border.all(
            color: palette.divider,
            width: 0.5,
          ),
        ),
        child: Stack(
          children: [
            AnimatedAlign(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment(alignmentX, 0.0),
              child: FractionallySizedBox(
                widthFactor: 1.0 / options.length,
                heightFactor: 1.0,
                child: style.isGlass && style.glassProvider != null
                    ? LiquidGlassLens(
                        style: style.glassProvider!.createStyle(
                          context: context,
                          cornerRadius: (height - 6) / 2,
                          refractionIndex: 1.12,
                          refractionWidth: 18.0,
                          color: style.isDark
                              ? const Color(0x38FFFFFF)
                              : const Color(0x52FFFFFF),
                        ),
                        child: const SizedBox.expand(),
                      )
                    : DecoratedBox(
                        decoration: BoxDecoration(
                          color: palette.surface,
                          borderRadius: BorderRadius.circular((height - 6) / 2),
                          border: Border.all(
                            color: palette.divider,
                            width: 0.5,
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black
                                  .withValues(alpha: style.isDark ? 0.24 : 0.07),
                              blurRadius: 6,
                              offset: const Offset(0, 1.5),
                            ),
                          ],
                        ),
                      ),
              ),
            ),
            Row(
              children: options.map((opt) {
                final isSelected = opt.value == selected;
                final textColor = isSelected
                    ? palette.onSurface
                    : palette.subtext;
                return Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      if (!isSelected) {
                        HapticUtils.selection();
                        onChanged(opt.value);
                      }
                    },
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            if (opt.icon != null) ...[
                              IconTheme(
                                data: IconThemeData(
                                  size: 16,
                                  color: isSelected
                                      ? palette.primary
                                      : palette.subtext,
                                ),
                                child: opt.icon!,
                              ),
                              const SizedBox(width: 5),
                            ],
                            Flexible(
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 160),
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 13.5,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                ),
                                child: Text(
                                  opt.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ],
        ),
      ),
    );
  }
}

/// Tactile Telegram-grade pill toggle switch working consistently in both
/// Liquid Glass and Material Matte modes without depending on [LiquidGlassProvider].
class TheavSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? thumbColor;
  final String? semanticLabel;

  const TheavSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final bool enabled = onChanged != null;

    if (style.isGlass) {
      final Color resolvedActive = activeColor ?? palette.primary;
      final Color resolvedInactive =
          inactiveColor ?? (style.isDark ? Colors.white24 : Colors.black12);
      final Color resolvedThumb = thumbColor ?? palette.onPrimary;

      Widget glassToggle = LiquidGlassSwitch(
        value: value,
        onChanged: enabled
            ? (next) {
                HapticUtils.selection();
                onChanged!(next);
              }
            : (_) {},
        activeColor:
            enabled ? resolvedActive : resolvedActive.withValues(alpha: 0.38),
        inactiveColor: enabled
            ? resolvedInactive
            : (style.isDark ? Colors.white : Colors.black)
                .withValues(alpha: style.isDark ? 0.10 : 0.06),
        thumbColor: enabled
            ? resolvedThumb
            : (thumbColor ?? Colors.white)
                .withValues(alpha: style.isDark ? 0.42 : 0.68),
      );
      if (!enabled) {
        glassToggle = IgnorePointer(
          ignoring: true,
          child: glassToggle,
        );
      }
      if (semanticLabel != null) {
        glassToggle = Semantics(
          label: semanticLabel,
          toggled: value,
          enabled: enabled,
          child: glassToggle,
        );
      }
      return Center(
        widthFactor: 1.0,
        heightFactor: 1.0,
        child: glassToggle,
      );
    }

    final Color activeTrack = activeColor ?? palette.primary;
    final Color inactiveTrack = inactiveColor ??
        Color.alphaBlend(
          palette.onSurface.withValues(alpha: style.isDark ? 0.22 : 0.16),
          palette.surface,
        );
    final Color trackColor = value ? activeTrack : inactiveTrack;
    final Color resolvedThumbColor = thumbColor ??
        (value
            ? palette.onPrimary
            : (style.isDark ? palette.onSurface : Colors.white));

    Widget toggle = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: 48,
      height: 28,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: enabled ? trackColor : trackColor.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value
              ? activeTrack.withValues(alpha: 0.25)
              : palette.divider,
          width: 0.5,
        ),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: enabled
                ? resolvedThumbColor
                : resolvedThumbColor.withValues(alpha: 0.72),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: style.isDark ? 0.30 : 0.16),
                blurRadius: 4,
                offset: const Offset(0, 1.5),
              ),
            ],
          ),
        ),
      ),
    );

    if (semanticLabel != null) {
      toggle = Semantics(
        label: semanticLabel,
        toggled: value,
        enabled: enabled,
        child: toggle,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled
          ? () {
              HapticUtils.selection();
              onChanged!(!value);
            }
          : null,
      child: toggle,
    );
  }
}

/// Animated circular multi-select badge supporting checkmark or numbered (`1..N`)
/// selection badges for chats and media pickers.
class TheavCheckCircle extends StatelessWidget {
  final bool selected;
  final int? index;
  final double size;
  final Color? activeColor;
  final Color? inactiveBorderColor;
  final VoidCallback? onTap;

  const TheavCheckCircle({
    super.key,
    required this.selected,
    this.index,
    this.size = 22.0,
    this.activeColor,
    this.inactiveBorderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final fillColor = activeColor ?? palette.primary;
    final borderColor =
        inactiveBorderColor ?? palette.onSurface.withValues(alpha: 0.34);

    final badge = AnimatedContainer(
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected ? fillColor : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? fillColor : borderColor,
          width: selected ? 1.5 : 1.5,
        ),
      ),
      child: AnimatedScale(
        scale: selected ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutBack,
        child: selected
            ? Center(
                child: index != null
                    ? Text(
                        '${index!}',
                        style: TextStyle(
                          color: palette.onPrimary,
                          fontSize: size * 0.54,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                        ),
                      )
                    : iconoir.Check(
                        width: size * 0.62,
                        height: size * 0.62,
                        color: palette.onPrimary,
                      ),
              )
            : const SizedBox.shrink(),
      ),
    );

    if (onTap == null) return badge;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticUtils.selection();
        onTap!();
      },
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: badge,
      ),
    );
  }
}

/// Discrete stepped slider with header value readout and tactile ticks
/// (e.g. Telegram slowmode interval selector).
class TheavSteppedSlider extends StatelessWidget {
  final int selectedIndex;
  final List<String> labels;
  final ValueChanged<int>? onChanged;
  final String? title;
  final Color? activeColor;

  const TheavSteppedSlider({
    super.key,
    required this.selectedIndex,
    required this.labels,
    required this.onChanged,
    this.title,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final int safeIndex = selectedIndex.clamp(0, labels.length - 1);
    final Color accent = activeColor ?? palette.primary;
    final int maxIdx = labels.length - 1;
    final bool enabled = onChanged != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (title != null && title!.isNotEmpty)
                Expanded(
                  child: Text(
                    title!,
                    style: TextStyle(
                      color: palette.onSurface,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: Text(
                  labels[safeIndex],
                  key: ValueKey<int>(safeIndex),
                  style: TextStyle(
                    color: enabled ? accent : accent.withValues(alpha: 0.45),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final double totalWidth = constraints.maxWidth.clamp(48.0, 2000.0);
              if (style.isGlass && maxIdx > 0) {
                Widget glassSlider = LiquidGlassSlider(
                  value: safeIndex.toDouble(),
                  minimumValue: 0.0,
                  maximumValue: maxIdx.toDouble(),
                  width: totalWidth,
                  activeColor:
                      enabled ? accent : accent.withValues(alpha: 0.38),
                  inactiveColor: enabled
                      ? (style.isDark ? Colors.white24 : Colors.black12)
                      : (style.isDark ? Colors.white : Colors.black)
                          .withValues(alpha: style.isDark ? 0.10 : 0.06),
                  thumbColor: enabled
                      ? Colors.white
                      : Colors.white
                          .withValues(alpha: style.isDark ? 0.45 : 0.70),
                  onChanged: enabled
                      ? (v) {
                          final int nextIdx = v.round().clamp(0, maxIdx);
                          if (nextIdx != safeIndex) {
                            HapticUtils.selection();
                            onChanged!(nextIdx);
                          }
                        }
                      : (_) {},
                );
                if (!enabled) {
                  glassSlider = IgnorePointer(
                    ignoring: true,
                    child: glassSlider,
                  );
                }
                return glassSlider;
              }
              final double usableWidth = (totalWidth - 20.0).clamp(1.0, totalWidth);
              final double fraction = maxIdx > 0 ? safeIndex / maxIdx : 0.0;
              final double activeWidth = usableWidth * fraction;

              void pickFromDx(double dx) {
                if (!enabled || maxIdx <= 0) return;
                final double clamped = ((dx - 10.0) / usableWidth).clamp(0.0, 1.0);
                final int nextIdx = (clamped * maxIdx).round().clamp(0, maxIdx);
                if (nextIdx != safeIndex) {
                  HapticUtils.selection();
                  onChanged!(nextIdx);
                }
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: enabled ? (d) => pickFromDx(d.localPosition.dx) : null,
                onHorizontalDragUpdate:
                    enabled ? (d) => pickFromDx(d.localPosition.dx) : null,
                child: SizedBox(
                  height: 30,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // Track
                      Positioned(
                        left: 10,
                        right: 10,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: palette.onSurface.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // Active track
                      Positioned(
                        left: 10,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          curve: Curves.easeOutCubic,
                          width: activeWidth,
                          height: 4,
                          decoration: BoxDecoration(
                            color: enabled
                                ? accent
                                : accent.withValues(alpha: 0.42),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // Tick dots
                      if (maxIdx > 0)
                        for (int i = 0; i <= maxIdx; i++)
                          Positioned(
                            left: 10 + usableWidth * (i / maxIdx) - 3,
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i <= safeIndex
                                    ? (enabled
                                        ? accent
                                        : accent.withValues(alpha: 0.42))
                                    : palette.onSurface.withValues(alpha: 0.28),
                              ),
                            ),
                          ),
                      // Thumb
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOutCubic,
                        left: activeWidth,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: palette.surface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: enabled
                                  ? accent
                                  : accent.withValues(alpha: 0.42),
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.16),
                                blurRadius: 5,
                                offset: const Offset(0, 1.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(labels.length, (i) {
              final bool active = i == safeIndex;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: enabled
                    ? () {
                        if (i != safeIndex) {
                          HapticUtils.selection();
                          onChanged!(i);
                        }
                      }
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: active ? accent : palette.subtext,
                      fontSize: 11.5,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
