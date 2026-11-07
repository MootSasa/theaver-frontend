import 'package:flutter/material.dart';
import '../models/theav_theme.dart' as model;

export '../models/theav_theme.dart' hide TheavTheme;

/// Lightweight design-token adapter over [model.TheavPalette] (`context.theav`)
/// providing flat, zero-AI-slop semantic tokens (`secondaryBg`, `inputBg`,
/// `dividerColor`, `accent`, `textPrimary`, `textSecondary`) for sticker,
/// custom emoji, GIF, and tiling sidecar components.
class TheavThemeData {
  final model.TheavPalette palette;
  final Brightness brightness;
  final ColorScheme colorScheme;

  const TheavThemeData({
    required this.palette,
    required this.brightness,
    required this.colorScheme,
  });

  Color get accent => palette.primary;
  Color get secondaryBg => palette.surface;
  Color get inputBg => palette.chatInputBackground;
  Color get dividerColor => palette.divider;
  Color get textPrimary => palette.onSurface;
  Color get textSecondary => palette.subtext;
}

class TheavTheme {
  const TheavTheme._();

  static TheavThemeData of(BuildContext context) {
    final materialTheme = Theme.of(context);
    return TheavThemeData(
      palette: context.theav,
      brightness: materialTheme.brightness,
      colorScheme: materialTheme.colorScheme,
    );
  }
}
