import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Renders an SVG wallpaper pattern tiled seamlessly at a delicate, refined scale
/// (~360-390px per tile) matching preview cards and preventing oversized doodles on full screens.
///
/// Uses Telegram's architecture: rasterizes a single pattern tile (with [colorFilter] baked in)
/// into a cached GPU [ui.Image] once, then draws the entire viewport in a single
/// `canvas.drawRect` call with a hardware-repeated [ui.ImageShader].
class TiledWallpaperPattern extends StatefulWidget {
  final String? assetPath;
  final String? filePath;
  final ColorFilter colorFilter;
  final double baseTileWidth;

  const TiledWallpaperPattern({
    Key? key,
    this.assetPath,
    this.filePath,
    required this.colorFilter,
    this.baseTileWidth = 360.0,
  }) : super(key: key);

  static String? computeCacheKey({
    String? assetPath,
    String? filePath,
    required ColorFilter colorFilter,
  }) {
    final source = assetPath ?? filePath;
    if (source == null || source.isEmpty) return null;
    return '${assetPath != null ? "a:" : "f:"}$source|${colorFilter.hashCode}';
  }

  static ui.Image? getCachedTileSync({
    String? assetPath,
    String? filePath,
    required ColorFilter colorFilter,
  }) {
    final key = computeCacheKey(
      assetPath: assetPath,
      filePath: filePath,
      colorFilter: colorFilter,
    );
    if (key == null) return null;
    return _TiledWallpaperPatternState._tileCache[key];
  }

  static Future<ui.Image?> resolveTileImage({
    String? assetPath,
    String? filePath,
    required ColorFilter colorFilter,
  }) {
    return _TiledWallpaperPatternState.resolveStaticTile(
      assetPath: assetPath,
      filePath: filePath,
      colorFilter: colorFilter,
    );
  }

  @override
  State<TiledWallpaperPattern> createState() => _TiledWallpaperPatternState();
}

class _TiledWallpaperPatternState extends State<TiledWallpaperPattern> {
  static const int _kRasterTilePx = 512;
  static const int _kMaxCacheEntries = 12;
  static final Map<String, ui.Image> _tileCache = <String, ui.Image>{};
  static final Map<String, Future<ui.Image?>> _pendingLoads =
      <String, Future<ui.Image?>>{};

  ui.Image? _image;
  String? _currentKey;

  String? _computeKey() => TiledWallpaperPattern.computeCacheKey(
        assetPath: widget.assetPath,
        filePath: widget.filePath,
        colorFilter: widget.colorFilter,
      );

  static Future<ui.Image?> resolveStaticTile({
    String? assetPath,
    String? filePath,
    required ColorFilter colorFilter,
  }) {
    final key = TiledWallpaperPattern.computeCacheKey(
      assetPath: assetPath,
      filePath: filePath,
      colorFilter: colorFilter,
    );
    if (key == null) return Future<ui.Image?>.value(null);
    final cached = _tileCache[key];
    if (cached != null) return Future<ui.Image?>.value(cached);

    final future = _pendingLoads[key] ??= _rasterizeTile(
      assetPath: assetPath,
      filePath: filePath,
      colorFilter: colorFilter,
    );
    return future.then((img) {
      _pendingLoads.remove(key);
      if (img != null) {
        if (_tileCache.length >= _kMaxCacheEntries &&
            !_tileCache.containsKey(key)) {
          final oldestKey = _tileCache.keys.first;
          _tileCache.remove(oldestKey);
        }
        _tileCache[key] = img;
      }
      return img;
    });
  }

  @override
  void initState() {
    super.initState();
    _resolveTileImage();
  }

  @override
  void didUpdateWidget(covariant TiledWallpaperPattern oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.assetPath != widget.assetPath ||
        oldWidget.filePath != widget.filePath ||
        oldWidget.colorFilter != widget.colorFilter) {
      _resolveTileImage();
    }
  }

  void _resolveTileImage() {
    final key = _computeKey();
    _currentKey = key;
    if (key == null) {
      _image = null;
      return;
    }

    final cached = _tileCache[key];
    if (cached != null) {
      _image = cached;
      return;
    }

    resolveStaticTile(
      assetPath: widget.assetPath,
      filePath: widget.filePath,
      colorFilter: widget.colorFilter,
    ).then((img) {
      if (mounted && _currentKey == key && img != null) {
        setState(() {
          _image = img;
        });
      }
    });
  }

  static Future<ui.Image?> _rasterizeTile({
    required String? assetPath,
    required String? filePath,
    required ColorFilter colorFilter,
  }) async {
    try {
      final BytesLoader loader;
      if (assetPath != null && assetPath.isNotEmpty) {
        loader = SvgAssetLoader(assetPath);
      } else if (!kIsWeb && filePath != null && filePath.isNotEmpty) {
        loader = SvgFileLoader(File(filePath) as dynamic);
      } else {
        return null;
      }

      final PictureInfo picInfo = await vg.loadPicture(loader, null);
      final double srcW =
          picInfo.size.width > 0 ? picInfo.size.width : _kRasterTilePx.toDouble();
      final double srcH =
          picInfo.size.height > 0 ? picInfo.size.height : _kRasterTilePx.toDouble();

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      final Rect bounds = Rect.fromLTWH(
        0,
        0,
        _kRasterTilePx.toDouble(),
        _kRasterTilePx.toDouble(),
      );

      canvas.saveLayer(bounds, Paint()..colorFilter = colorFilter);
      canvas.scale(_kRasterTilePx / srcW, _kRasterTilePx / srcH);
      canvas.drawPicture(picInfo.picture);
      canvas.restore();

      final ui.Picture recordedPicture = recorder.endRecording();
      final ui.Image rasterized =
          await recordedPicture.toImage(_kRasterTilePx, _kRasterTilePx);
      recordedPicture.dispose();
      picInfo.picture.dispose();
      return rasterized;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ui.Image? img = _image;
    if (img == null) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        if (w <= 0 || h <= 0) return const SizedBox.shrink();

        final int cols =
            w < 500 ? 1 : math.max(1, (w / widget.baseTileWidth).round());
        final double tileSize = w / cols;

        return RepaintBoundary(
          child: CustomPaint(
            size: Size(w, h),
            painter: _TiledWallpaperShaderPainter(
              image: img,
              tileSize: tileSize,
            ),
          ),
        );
      },
    );
  }
}

class _TiledWallpaperShaderPainter extends CustomPainter {
  final ui.Image image;
  final double tileSize;

  const _TiledWallpaperShaderPainter({
    required this.image,
    required this.tileSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty || tileSize <= 0) return;

    final double scaleX = tileSize / image.width;
    final double scaleY = tileSize / image.height;
    final Float64List matrix = Float64List(16)
      ..[0] = scaleX
      ..[5] = scaleY
      ..[10] = 1.0
      ..[15] = 1.0;

    final Paint paint = Paint()
      ..shader = ui.ImageShader(
        image,
        TileMode.repeated,
        TileMode.repeated,
        matrix,
        filterQuality: FilterQuality.low,
      );

    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(covariant _TiledWallpaperShaderPainter oldDelegate) {
    return oldDelegate.image != image ||
        (oldDelegate.tileSize - tileSize).abs() > 0.05;
  }
}
