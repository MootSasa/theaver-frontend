import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/power_saving_provider.dart';

/// Cached [ui.ImageFilter.blur] and frosted Material HUD helpers.
class BlurUtils {
  BlurUtils._();

  static final Map<int, ui.ImageFilter> _cache = <int, ui.ImageFilter>{};

  static ui.ImageFilter createDownsampledBlur(
    double sigma, {
    double scale = 0.25,
    ui.TileMode tileMode = ui.TileMode.clamp,
  }) {
    if (sigma <= 0.0) {
      return ui.ImageFilter.blur(sigmaX: 0.0, sigmaY: 0.0, tileMode: tileMode);
    }
    final double clampedScale = scale.clamp(0.1, 1.0);
    final double effectiveSigma =
        (sigma * (0.4 + clampedScale * 0.6)).clamp(1.0, 14.0);
    final int key = Object.hash((effectiveSigma * 100).round(), tileMode);
    final ui.ImageFilter? cached = _cache[key];
    if (cached != null) return cached;

    final ui.ImageFilter filter = ui.ImageFilter.blur(
      sigmaX: effectiveSigma,
      sigmaY: effectiveSigma,
      tileMode: tileMode,
    );

    if (_cache.length > 64) {
      _cache.clear();
    }
    return _cache[key] = filter;
  }

  /// Cached single-pass frosted blur filter for Material mode floating HUD surfaces.
  static ui.ImageFilter createMaterialHudBlur({
    double sigma = 10.0,
    ui.TileMode tileMode = ui.TileMode.clamp,
  }) {
    if (sigma <= 0.0) {
      return ui.ImageFilter.blur(sigmaX: 0.0, sigmaY: 0.0, tileMode: tileMode);
    }
    final double effectiveSigma = sigma.clamp(1.0, 16.0);
    final int key = Object.hash(0x4D4154, (effectiveSigma * 100).round(), tileMode);
    final ui.ImageFilter? cached = _cache[key];
    if (cached != null) return cached;

    final ui.ImageFilter filter = ui.ImageFilter.blur(
      sigmaX: effectiveSigma,
      sigmaY: effectiveSigma,
      tileMode: tileMode,
    );

    if (_cache.length > 64) {
      _cache.clear();
    }
    return _cache[key] = filter;
  }

  /// Returns whether Material HUD surfaces are allowed to use single-pass frosted blur.
  static bool shouldBlurMaterialHud(BuildContext context, {bool listen = true}) {
    try {
      return Provider.of<PowerSavingProvider>(context, listen: listen).allowBlur;
    } catch (_) {
      return PowerSavingProvider.instance.allowBlur;
    }
  }

  /// Resolves a frosted translucent color when [blurEnabled] is true,
  /// or an opaque matte surface color when power saving disables blur.
  static Color resolveMaterialHudColor(
    Color base, {
    required bool isDark,
    required bool blurEnabled,
    double darkAlpha = 0.78,
    double lightAlpha = 0.84,
  }) {
    if (!blurEnabled) {
      return base.a >= 0.65 && base.a < 1.0 ? base.withValues(alpha: 1.0) : base;
    }
    final targetAlpha = isDark ? darkAlpha : lightAlpha;
    if (base.a <= targetAlpha) {
      return base;
    }
    return base.withValues(alpha: targetAlpha);
  }
}
