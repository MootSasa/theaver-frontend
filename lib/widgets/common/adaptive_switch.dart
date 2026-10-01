import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import '../../services/liquid_glass_provider.dart';

/// Адаптивный переключатель (Switch), использующий [LiquidGlassSwitch]
/// из библиотеки liquid_glass_easy при включённом Liquid Glass дизайне,
/// и стандартный Material [Switch] при выключенном.
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
    final isGlass = context.watch<LiquidGlassProvider>().enabled;
    if (isGlass && onChanged != null) {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      return LiquidGlassSwitch(
        value: value,
        onChanged: onChanged!,
        activeColor: activeColor ?? (isDark ? const Color(0xFF0088CC) : const Color(0xFF34C759)),
        inactiveColor: inactiveColor ?? (isDark ? Colors.white24 : Colors.black12),
        thumbColor: thumbColor ?? Colors.white,
      );
    }
    return Switch(
      value: value,
      onChanged: onChanged,
      activeThumbColor: activeColor,
    );
  }
}

/// Адаптивный ползунок (Slider), использующий [LiquidGlassSlider]
/// из библиотеки liquid_glass_easy при включённом Liquid Glass дизайне,
/// и стандартный Material [Slider] при выключенном.
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

  @override
  Widget build(BuildContext context) {
    final isGlass = context.watch<LiquidGlassProvider>().enabled;
    if (isGlass && onChanged != null) {
      final theme = Theme.of(context);
      final isDark = theme.brightness == Brightness.dark;
      return LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.hasBoundedWidth ? constraints.maxWidth : 280.0;
          return LiquidGlassSlider(
            value: value.clamp(min, max),
            onChanged: onChanged!,
            onChangeStart: onChangeStart,
            onChangeEnd: onChangeEnd,
            minimumValue: min,
            maximumValue: max,
            width: width,
            activeColor: activeColor ?? (isDark ? const Color(0xFF0088CC) : theme.colorScheme.primary),
            inactiveColor: inactiveColor ?? (isDark ? Colors.white24 : Colors.black12),
            thumbColor: thumbColor ?? Colors.white,
          );
        },
      );
    }
    return Slider(
      value: value,
      onChanged: onChanged,
      onChangeStart: onChangeStart,
      onChangeEnd: onChangeEnd,
      min: min,
      max: max,
      divisions: divisions,
      activeColor: activeColor,
      label: label,
    );
  }
}

/// Адаптивный SwitchListTile, использующий [AdaptiveSwitch] (с [LiquidGlassSwitch])
/// при включённом Liquid Glass дизайне, и стандартный Material [SwitchListTile] при выключенном.
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
    final isGlass = context.watch<LiquidGlassProvider>().enabled;
    if (isGlass) {
      return ListTile(
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
    return SwitchListTile(
      title: title,
      subtitle: subtitle,
      secondary: secondary,
      value: value,
      onChanged: onChanged,
      contentPadding: contentPadding,
      dense: dense,
      isThreeLine: isThreeLine,
      activeThumbColor: activeColor,
      activeTrackColor: activeTrackColor,
    );
  }
}
