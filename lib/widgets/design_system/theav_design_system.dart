import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../models/theav_theme.dart';
import '../../services/liquid_glass_provider.dart';
import '../../utils/blur_utils.dart';

export '../../models/theav_theme.dart' show TheavContextExtension, TheavPalette;
export '../../services/liquid_glass_provider.dart' show GlassMode;
export 'theav_controls.dart';
export 'theav_floating_pill_button.dart';
export 'theav_inset_group.dart';
export 'theav_overlays.dart';

/// Forces a subtree (and modals opened from it when propagated) to render with
/// clean matte surfaces without [LiquidGlassLens] or [BackdropFilter] shaders.
class TheavMatteScope extends InheritedWidget {
  final bool enabled;

  const TheavMatteScope({
    super.key,
    this.enabled = true,
    required super.child,
  });

  static bool isActive(BuildContext context, {bool listen = true}) {
    final TheavMatteScope? scope = listen
        ? context.dependOnInheritedWidgetOfExactType<TheavMatteScope>()
        : context.getInheritedWidgetOfExactType<TheavMatteScope>();
    return scope?.enabled ?? false;
  }

  @override
  bool updateShouldNotify(TheavMatteScope oldWidget) =>
      enabled != oldWidget.enabled;
}

/// Resolved surface tokens binding [TheavPalette] (`context.theav`) with the
/// active [GlassMode] (`full` / `lite` / `disabled`) and power-saving state.
class TheavSurfaceStyle {
  final BuildContext context;
  final TheavPalette palette;
  final Brightness brightness;
  final GlassMode mode;
  final bool allowBlur;
  final bool allowMaterialBlur;
  final LiquidGlassProvider? glassProvider;

  const TheavSurfaceStyle._({
    required this.context,
    required this.palette,
    required this.brightness,
    required this.mode,
    required this.allowBlur,
    required this.allowMaterialBlur,
    required this.glassProvider,
  });

  /// Resolves design tokens safely from [context] without throwing if
  /// [LiquidGlassProvider] is absent from the widget tree.
  factory TheavSurfaceStyle.of(BuildContext context, {bool listen = true}) {
    final palette = context.theav;
    final brightness = Theme.of(context).brightness;
    if (TheavMatteScope.isActive(context, listen: listen)) {
      return TheavSurfaceStyle._(
        context: context,
        palette: palette,
        brightness: brightness,
        mode: GlassMode.disabled,
        allowBlur: false,
        allowMaterialBlur: false,
        glassProvider: null,
      );
    }
    final provider = LiquidGlassProvider.maybeOf(context, listen: listen);
    final mode = LiquidGlassProvider.glassModeOf(context, listen: listen);
    final powerAllowsBlur =
        BlurUtils.shouldBlurMaterialHud(context, listen: listen);
    final allowBlur = mode != GlassMode.disabled && powerAllowsBlur;
    final allowMaterialBlur = mode == GlassMode.disabled && powerAllowsBlur;
    return TheavSurfaceStyle._(
      context: context,
      palette: palette,
      brightness: brightness,
      mode: mode,
      allowBlur: allowBlur,
      allowMaterialBlur: allowMaterialBlur,
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

  /// Specular edge highlight for floating Layer 2 glass or frosted HUD surfaces.
  Color get hudBorder => (isGlass || allowMaterialBlur)
      ? (isDark
          ? palette.onSurface.withValues(alpha: isGlass ? 0.16 : 0.12)
          : palette.onSurface.withValues(alpha: isGlass ? 0.10 : 0.08))
      : palette.divider;

  /// Base fill color for floating Layer 2 capsules (`full`, `lite`, or frosted/opaque Material).
  Color get hudFill {
    final base = palette.appBarBackground != Colors.transparent
        ? palette.appBarBackground
        : palette.surface;
    if (isGlass) {
      return base.withValues(alpha: math.min(base.a, isDark ? 0.72 : 0.80));
    }
    return BlurUtils.resolveMaterialHudColor(
      base,
      isDark: isDark,
      blurEnabled: allowMaterialBlur,
    );
  }

  /// Base fill color for modal sheets and dialogs.
  Color get overlayFill => isGlass
      ? palette.surface.withValues(alpha: math.min(palette.surface.a, isDark ? 0.68 : 0.76))
      : Color.alphaBlend(
          palette.primary.withValues(alpha: isDark ? 0.04 : 0.025),
          palette.surface,
        );

  /// Subtle recessed track color for segmented controls and switches.
  Color get trackFill => Color.alphaBlend(
        palette.onSurface.withValues(alpha: isDark ? 0.10 : 0.06),
        palette.surface,
      );

  /// Cached blur filter when hardware blur is permitted for glass or fallback.
  ImageFilter? getBlurFilter({double sigma = 18.0}) {
    if (!allowBlur || sigma <= 0) return null;
    return BlurUtils.createDownsampledBlur(sigma);
  }

  /// Cached single-pass frosted blur filter for floating HUD elements.
  ImageFilter? getMaterialHudBlurFilter({double sigma = 10.0}) {
    if (sigma <= 0) return null;
    if (isGlass) {
      return allowBlur ? BlurUtils.createDownsampledBlur(sigma) : null;
    }
    return allowMaterialBlur ? BlurUtils.createMaterialHudBlur(sigma: sigma) : null;
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
