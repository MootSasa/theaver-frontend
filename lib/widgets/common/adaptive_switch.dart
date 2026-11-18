import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import '../../models/theav_theme.dart';
import '../../services/liquid_glass_provider.dart';
import '../design_system/theav_controls.dart';

/// Адаптивный переключатель (Switch), использующий [LiquidGlassSwitch]
/// при включённом Liquid Glass дизайне и [TheavSwitch] при выключенном.
class AdaptiveSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? thumbColor;

  const AdaptiveSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
  });

  @override
  Widget build(BuildContext context) {
    return TheavSwitch(
      value: value,
      onChanged: onChanged,
      activeColor: activeColor,
      inactiveColor: inactiveColor,
      thumbColor: thumbColor,
    );
  }
}

/// Адаптивный ползунок (Slider), использующий [LiquidGlassSlider]
/// при включённом Liquid Glass дизайне и стилизованный [Slider] при выключенном.
class AdaptiveSlider extends StatelessWidget {
  final double value;
  final ValueChanged<double>? onChanged;
  final ValueChanged<double>? onChangeStart;
  final ValueChanged<double>? onChangeEnd;
  final double min;
  final double max;
  final int? divisions;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? thumbColor;
  final String? label;

  const AdaptiveSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.onChangeStart,
    this.onChangeEnd,
    this.min = 0.0,
    this.max = 1.0,
    this.divisions,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
    this.label,
  });

  double _snapValue(double raw) {
    final double clamped = raw.clamp(min, max).toDouble();
    if (divisions == null || divisions! <= 0 || max <= min) {
      return clamped;
    }
    final double step = (max - min) / divisions!;
    final double snapped = min + ((clamped - min) / step).round() * step;
    return snapped.clamp(min, max).toDouble();
  }

  @override
  Widget build(BuildContext context) {
    final glassMode = LiquidGlassProvider.glassModeOf(context);
    final palette = context.theav;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bool enabled = onChanged != null;
    if (glassMode != GlassMode.disabled) {
      final Color resolvedActive = activeColor ?? palette.primary;
      final Color resolvedInactive =
          inactiveColor ?? (isDark ? Colors.white24 : Colors.black12);
      final Color resolvedThumb = thumbColor ?? Colors.white;

      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.hasBoundedWidth ? constraints.maxWidth : 280.0;
          Widget slider = LiquidGlassSlider(
            value: value.clamp(min, max).toDouble(),
            onChanged: enabled ? (v) => onChanged!(_snapValue(v)) : (_) {},
            onChangeStart: enabled ? onChangeStart : null,
            onChangeEnd: enabled
                ? (v) {
                    onChangeEnd?.call(_snapValue(v));
                  }
                : null,
            minimumValue: min,
            maximumValue: max,
            width: width,
            activeColor: enabled
                ? resolvedActive
                : resolvedActive.withValues(alpha: 0.38),
            inactiveColor: enabled
                ? resolvedInactive
                : (isDark ? Colors.white : Colors.black)
                    .withValues(alpha: isDark ? 0.10 : 0.06),
            thumbColor: enabled
                ? resolvedThumb
                : resolvedThumb.withValues(alpha: isDark ? 0.45 : 0.70),
          );
          if (!enabled) {
            slider = IgnorePointer(
              ignoring: true,
              child: slider,
            );
          }
          return slider;
        },
      );
    }
    return Slider(
      value: value.clamp(min, max),
      onChanged: onChanged,
      onChangeStart: onChangeStart,
      onChangeEnd: onChangeEnd,
      min: min,
      max: max,
      divisions: divisions,
      activeColor: activeColor ?? palette.primary,
      label: label,
    );
  }
}

/// Адаптивный SwitchListTile, использующий [AdaptiveSwitch].
class AdaptiveSwitchListTile extends StatelessWidget {
  final Widget? title;
  final Widget? subtitle;
  final Widget? secondary;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final EdgeInsetsGeometry? contentPadding;
  final bool dense;
  final bool isThreeLine;
  final Color? activeColor;
  final Color? activeTrackColor;

  const AdaptiveSwitchListTile({
    super.key,
    this.title,
    this.subtitle,
    this.secondary,
    required this.value,
    required this.onChanged,
    this.contentPadding,
    this.dense = false,
    this.isThreeLine = false,
    this.activeColor,
    this.activeTrackColor,
  });

  const AdaptiveSwitchListTile.adaptive({
    super.key,
    this.title,
    this.subtitle,
    this.secondary,
    required this.value,
    required this.onChanged,
    this.contentPadding,
    this.dense = false,
    this.isThreeLine = false,
    this.activeColor,
    this.activeTrackColor,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      enabled: onChanged != null,
      title: title,
      subtitle: subtitle,
      leading: secondary,
      contentPadding: contentPadding,
      dense: dense,
      isThreeLine: isThreeLine,
      trailing: AdaptiveSwitch(
        value: value,
        onChanged: onChanged,
        activeColor: activeColor ?? activeTrackColor,
      ),
      onTap: onChanged != null ? () => onChanged!(!value) : null,
    );
  }
}
