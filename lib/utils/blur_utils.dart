import 'dart:ui' as ui;

/// Cached [ui.ImageFilter.blur] helper to avoid allocating new filter objects on every build.
class BlurUtils {
  BlurUtils._();

  static final Map<int, ui.ImageFilter> _cache = <int, ui.ImageFilter>{};

  static ui.ImageFilter createDownsampledBlur(
    double sigma, {
    double scale = 0.25,
    ui.TileMode tileMode = ui.TileMode.decal,
  }) {
    if (sigma <= 0.0) {
      return ui.ImageFilter.blur(sigmaX: 0.0, sigmaY: 0.0, tileMode: tileMode);
    }
    final int key = Object.hash((sigma * 100).round(), tileMode);
    final ui.ImageFilter? cached = _cache[key];
    if (cached != null) return cached;

    final ui.ImageFilter filter = ui.ImageFilter.blur(
      sigmaX: sigma,
      sigmaY: sigma,
      tileMode: tileMode,
    );

    if (_cache.length > 64) {
      _cache.clear();
    }
    return _cache[key] = filter;
  }
}
