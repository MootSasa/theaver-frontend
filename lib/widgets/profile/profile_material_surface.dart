import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../utils/blur_utils.dart';
import '../design_system/theav_design_system.dart';

/// Shared Material-mode surface, text, accent, and conditional blur tokens for
/// profile buttons, floating pills, info cards, and menus.
///
/// Strictly follows [Theme.of(context).brightness] and [context.theav] instead of
/// locking to dark chrome when a colored profile cover preset is active.
class ProfileMaterialStyle {
  final bool isDark;
  final TheavPalette palette;
  final bool allowBlur;

  const ProfileMaterialStyle._({
    required this.isDark,
    required this.palette,
    required this.allowBlur,
  });

  /// Resolves active Material-mode palette and blur permission from [context].
  factory ProfileMaterialStyle.of(BuildContext context, {bool listen = true}) {
    final theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final TheavPalette palette = context.theav;
    final bool allowBlur = !TheavMatteScope.isActive(context, listen: listen) &&
        BlurUtils.shouldBlurMaterialHud(context, listen: listen);
    return ProfileMaterialStyle._(
      isDark: isDark,
      palette: palette,
      allowBlur: allowBlur,
    );
  }

  Color get buttonFill => BlurUtils.resolveMaterialHudColor(
        Color.alphaBlend(
          palette.primary.withValues(alpha: isDark ? 0.08 : 0.05),
          palette.surface,
        ),
        isDark: isDark,
        blurEnabled: allowBlur,
        darkAlpha: 0.88,
        lightAlpha: 0.92,
      );

  Color get panelFill => BlurUtils.resolveMaterialHudColor(
        Color.alphaBlend(
          palette.primary.withValues(alpha: isDark ? 0.06 : 0.04),
          palette.surface,
        ),
        isDark: isDark,
        blurEnabled: allowBlur,
        darkAlpha: 0.92,
        lightAlpha: 0.94,
      );

  Color get borderColor => palette.divider;
  Color get foreground => palette.onSurface;
  Color get subtext => palette.subtext;
  Color get primary => palette.primary;
  Color get onPrimary => palette.onPrimary;
  Color get destructive => palette.error;

  ui.ImageFilter? blurFilter({double sigma = 14.0}) =>
      allowBlur ? BlurUtils.createMaterialHudBlur(sigma: sigma) : null;

  /// Wraps [child] with [BackdropFilter] only when Material blur is enabled.
  Widget wrapBlur({required Widget child, double sigma = 14.0}) {
    final filter = blurFilter(sigma: sigma);
    if (filter == null) return child;
    return BackdropFilter(
      filter: filter,
      child: child,
    );
  }
}
