import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../models/theav_theme.dart';
import '../../services/liquid_glass_provider.dart';
import '../../services/power_saving_provider.dart';
import '../../utils/blur_utils.dart';

export '../../models/theav_theme.dart' show TheavContextExtension, TheavPalette;
export '../../services/liquid_glass_provider.dart' show GlassMode;
export 'theav_controls.dart';
export 'theav_floating_pill_button.dart';
export 'theav_inset_group.dart';
export 'theav_overlays.dart';

/// Resolved surface tokens binding [TheavPalette] (`context.theav`) with the
/// active [GlassMode] (`full` / `lite` / `disabled`) and power-saving state.
class TheavSurfaceStyle {
  final BuildContext context;
  final TheavPalette palette;
  final Brightness brightness;
  final GlassMode mode;
  final bool allowBlur;
  final LiquidGlassProvider? glassProvider;

  const TheavSurfaceStyle._({
    required this.context,
    required this.palette,
    required this.brightness,
    required this.mode,
    required this.allowBlur,
    required this.glassProvider,
  });

  /// Resolves design tokens safely from [context] without throwing if
  /// [LiquidGlassProvider] is absent from the widget tree.
  factory TheavSurfaceStyle.of(BuildContext context, {bool listen = true}) {
    final palette = context.theav;
    final brightness = Theme.of(context).brightness;
    final provider = LiquidGlassProvider.maybeOf(context, listen: listen);
    final mode = LiquidGlassProvider.glassModeOf(context, listen: listen);
    final allowBlur =
        mode != GlassMode.disabled && PowerSavingProvider.instance.allowBlur;
    return TheavSurfaceStyle._(
      context: context,
      palette: palette,
      brightness: brightness,
      mode: mode,
      allowBlur: allowBlur,
      glassProvider: provider,
    );
  }

  bool get isDark => brightness == Brightness.dark;
  bool get isGlass => mode != GlassMode.disabled;
  bool get isFull => mode == GlassMode.full && glassProvider != null;
  bool get isLite => mode == GlassMode.lite;
  bool get isMatte => mode == GlassMode.disabled;

  /// Elevated Layer 1 card surface color (never blurred inside scroll views).
  Color get cardSurface => palette.surface;

  /// Hairline divider/border color tuned to the active palette.
  Color get hairlineBorder => palette.divider;

  /// Specular edge highlight for floating Layer 2 glass surfaces.
  Color get hudBorder => isGlass
      ? (isDark
          ? palette.onSurface.withValues(alpha: 0.16)
          : palette.onSurface.withValues(alpha: 0.10))
      : palette.divider;

  /// Base fill color for floating Layer 2 capsules (`lite` or `disabled`).
  Color get hudFill {
    final base = palette.appBarBackground != Colors.transparent
        ? palette.appBarBackground
        : palette.surface;
    if (isGlass) {
      return base.withValues(alpha: isDark ? 0.72 : 0.80);
    }
    return base;
  }

  /// Base fill color for modal sheets and dialogs.
  Color get overlayFill => isGlass
      ? palette.surface.withValues(alpha: isDark ? 0.86 : 0.90)
      : palette.surface;

  /// Subtle recessed track color for segmented controls and switches.
  Color get trackFill => Color.alphaBlend(
        palette.onSurface.withValues(alpha: isDark ? 0.10 : 0.06),
        palette.surface,
      );

  /// Cached blur filter when hardware blur is permitted.
  ImageFilter? getBlurFilter({double sigma = 18.0}) {
    if (!allowBlur || sigma <= 0) return null;
    return BlurUtils.createDownsampledBlur(sigma);
  }

  /// Subtle shadow used by Layer 2 pills and overlays without muddy glow.
  List<BoxShadow> get floatingShadow => [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
          blurRadius: 16,
          offset: const Offset(0, 4),
        ),
      ];
}
