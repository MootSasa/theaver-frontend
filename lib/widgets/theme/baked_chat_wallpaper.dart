import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/theav_theme.dart';
import 'four_corner_gradient.dart';
import 'tiled_wallpaper_pattern.dart';

/// Telegram-style pre-baked composite chat wallpaper (`ChatBackgroundDrawable` architecture).
///
/// Why this exists:
/// On Impeller, `RepaintBoundary` retains a `DisplayList` (`ui.Picture`) rather
/// than a rasterized bitmap. Without pre-baking:
/// - **SVG pattern wallpapers** execute 3 full-screen passes on every scroll
///   frame (`Scaffold` background fill + `FourCornerGradientPainter.drawVertices`
///   + `TiledWallpaperPattern` `ImageShader(TileMode.repeated)` with alpha blending).
/// - **Custom photo wallpapers** sample unresized 12MP (`4000×3000`) camera
///   textures without mipmaps (thrashing the GPU texture cache on every pixel),
///   re-execute `ImageFiltered` Gaussian blur passes on every single scroll
///   frame when `blurRadius > 0`, and draw an extra full-screen dimming layer.
///
/// [BakedChatWallpaper] composites all layers (`4-corner gradient + SVG pattern`
/// OR `resized photo + BoxFit.cover + Gaussian blur + dimming`) into **one
/// single opaque GPU [ui.Image] texture ONCE** per `(wallpaperConfig, viewportSize)`.
/// On every scroll frame, the GPU draws just 1 pre-sized texture (`RawImage`),
/// reducing the per-frame GPU cost of SVG and photo wallpapers to that of a
/// simple solid background.
class BakedChatWallpaper extends StatefulWidget {
  const BakedChatWallpaper({
    super.key,
    this.wallpaper,
    this.fallbackWallpaperPath,
  });

  final TheavWallpaper? wallpaper;
  final String? fallbackWallpaperPath;

  @override
  State<BakedChatWallpaper> createState() => _BakedChatWallpaperState();
}

class _BakedChatWallpaperState extends State<BakedChatWallpaper> {
  static const int _kMaxCachedWallpapers = 8;
  static const int _kMaxBakedDimensionPx = 1440;

  static final Map<String, ui.Image> _bakedCache = <String, ui.Image>{};
  static final Map<String, Future<ui.Image?>> _pendingBakes =
      <String, Future<ui.Image?>>{};

  String? _activeKey;
  ui.Image? _activeImage;

  static void _putCache(String key, ui.Image image) {
    if (_bakedCache.length >= _kMaxCachedWallpapers &&
        !_bakedCache.containsKey(key)) {
      final oldest = _bakedCache.keys.first;
      _bakedCache.remove(oldest);
    }
    _bakedCache[key] = image;
  }

  String _buildConfigSignature() {
    final wp = widget.wallpaper;
    final fallback = widget.fallbackWallpaperPath ?? '';
    if (wp == null) {
      return 'legacy_file:$fallback';
    }
    final grad = wp.fourCornerGradient;
    final gradSig = grad == null
        ? 'solid:${wp.backgroundColor.toARGB32()}'
        : 'grad:${grad.topLeft.toARGB32()}_${grad.topRight.toARGB32()}_${grad.bottomLeft.toARGB32()}_${grad.bottomRight.toARGB32()}';
    return '${wp.type}|$gradSig|svg:${wp.assetSvgPath ?? wp.customSvgPath ?? ""}|'
        'pCol:${wp.patternColor.toARGB32()}|pOp:${wp.patternOpacity.toStringAsFixed(3)}|'
        'img:${wp.imagePath ?? wp.imageUrl ?? fallback}|'
        'blur:${wp.blurRadius.toStringAsFixed(1)}|dim:${wp.dimming.toStringAsFixed(2)}';
  }

  void _ensureBaked({
    required double logicalW,
    required double logicalH,
    required double dpr,
  }) {
    final int qW = ((logicalW / 16.0).ceil() * 16).clamp(64, 4096);
    final int qH = ((logicalH / 16.0).ceil() * 16).clamp(64, 4096);
    final String key = '${_buildConfigSignature()}@${qW}x$qH';

    if (_activeKey == key && _activeImage != null) {
      return;
    }
    _activeKey = key;

    final ui.Image? cached = _bakedCache[key];
    if (cached != null) {
      _activeImage = cached;
      return;
    }

    final double effectiveScale = dpr.clamp(1.0, 2.25);
    final double rawPxW = qW * effectiveScale;
    final double rawPxH = qH * effectiveScale;
    final double maxDim = math.max(rawPxW, rawPxH);
    final double clampFactor =
        maxDim > _kMaxBakedDimensionPx ? (_kMaxBakedDimensionPx / maxDim) : 1.0;
    final int targetPxW =
        (rawPxW * clampFactor).round().clamp(64, _kMaxBakedDimensionPx);
    final int targetPxH =
        (rawPxH * clampFactor).round().clamp(64, _kMaxBakedDimensionPx);

    final Future<ui.Image?> future = _pendingBakes[key] ??= _bakeWallpaper(
      wp: widget.wallpaper,
      fallbackPath: widget.fallbackWallpaperPath,
      logicalW: qW.toDouble(),
      logicalH: qH.toDouble(),
      targetPxW: targetPxW,
      targetPxH: targetPxH,
    );

    future.then((img) {
      _pendingBakes.remove(key);
      if (img != null) {
        _putCache(key, img);
      }
      if (mounted && _activeKey == key && img != null) {
        setState(() {
          _activeImage = img;
        });
      }
    });
  }

  static Future<ui.Image?> _bakeWallpaper({
    required TheavWallpaper? wp,
    required String? fallbackPath,
    required double logicalW,
    required double logicalH,
    required int targetPxW,
    required int targetPxH,
  }) async {
    try {
      if (wp == null) {
        if (kIsWeb || fallbackPath == null || fallbackPath.isEmpty) return null;
        final file = File(fallbackPath);
        if (!file.existsSync()) return null;
        final provider = ResizeImage.resizeIfNeeded(
          _kMaxBakedDimensionPx,
          null,
          FileImage(file),
        );
        final ui.Image? decoded = await _resolveProviderImage(provider);
        if (decoded == null) return null;
        return _bakePhotoWallpaper(
          photo: decoded,
          targetPxW: targetPxW,
          targetPxH: targetPxH,
          blurRadius: 0.0,
          dimming: 0.0,
          fallbackColor: const Color(0xFF121212),
        );
      }

      if (wp.type == 'image') {
        final baseProvider = wp.getImageProvider(fallbackPath: fallbackPath);
        if (baseProvider != null) {
          const int decodeMaxPx = _kMaxBakedDimensionPx;
          final resizedProvider = ResizeImage.resizeIfNeeded(
            decodeMaxPx,
            null,
            baseProvider,
          );
          final ui.Image? decoded = await _resolveProviderImage(resizedProvider);
          if (decoded != null) {
            final double pxScale = targetPxW / math.max(1.0, logicalW);
            return _bakePhotoWallpaper(
              photo: decoded,
              targetPxW: targetPxW,
              targetPxH: targetPxH,
              blurRadius: wp.blurRadius * pxScale,
              dimming: wp.dimming,
              fallbackColor: wp.backgroundColor,
              fourCornerGradient: wp.fourCornerGradient,
            );
          }
        }
      }

      // Pattern or gradient wallpaper
      ui.Image? patternTile;
      final String? assetSvg = wp.assetSvgPath;
      final String? customSvg = wp.customSvgPath;
      if (wp.patternOpacity > 0) {
        final ColorFilter filter = ColorFilter.mode(
          wp.patternColor.withValues(alpha: wp.patternOpacity),
          BlendMode.srcIn,
        );
        if (assetSvg != null && assetSvg.isNotEmpty) {
          patternTile = await TiledWallpaperPattern.resolveTileImage(
            assetPath: assetSvg,
            colorFilter: filter,
          );
        } else if (!kIsWeb &&
            customSvg != null &&
            customSvg.isNotEmpty &&
            File(customSvg).existsSync()) {
          patternTile = await TiledWallpaperPattern.resolveTileImage(
            filePath: customSvg,
            colorFilter: filter,
          );
        }
      }

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      final Size targetSize = Size(targetPxW.toDouble(), targetPxH.toDouble());

      // 1. Draw base 4-corner gradient or solid color
      if (wp.fourCornerGradient != null) {
        final grad = wp.fourCornerGradient!;
        FourCornerGradientPainter(
          topLeft: grad.topLeft,
          topRight: grad.topRight,
          bottomLeft: grad.bottomLeft,
          bottomRight: grad.bottomRight,
        ).paint(canvas, targetSize);
      } else {
        canvas.drawRect(
          Offset.zero & targetSize,
          Paint()..color = wp.backgroundColor,
        );
      }

      // 2. Draw tiled SVG pattern on top into the same single bitmap
      if (patternTile != null && logicalW > 0) {
        final int cols =
            logicalW < 500 ? 1 : math.max(1, (logicalW / 360.0).round());
        final double logicalTileSize = logicalW / cols;
        final double pxScale = targetPxW / logicalW;
        final double pxTileSize = logicalTileSize * pxScale;
        final double scaleX = pxTileSize / patternTile.width;
        final double scaleY = pxTileSize / patternTile.height;
        final Float64List matrix = Float64List(16)
          ..[0] = scaleX
          ..[5] = scaleY
          ..[10] = 1.0
          ..[15] = 1.0;

        final Paint patternPaint = Paint()
          ..shader = ui.ImageShader(
            patternTile,
            TileMode.repeated,
            TileMode.repeated,
            matrix,
            filterQuality: FilterQuality.low,
          );
        canvas.drawRect(Offset.zero & targetSize, patternPaint);
      }

      final ui.Picture picture = recorder.endRecording();
      final ui.Image baked = await picture.toImage(targetPxW, targetPxH);
      picture.dispose();
      return baked;
    } catch (_) {
      return null;
    }
  }

  static Future<ui.Image?> _bakePhotoWallpaper({
    required ui.Image photo,
    required int targetPxW,
    required int targetPxH,
    required double blurRadius,
    required double dimming,
    required Color fallbackColor,
    FourCornerGradient? fourCornerGradient,
  }) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final Canvas canvas = Canvas(recorder);
    final Size targetSize = Size(targetPxW.toDouble(), targetPxH.toDouble());
    final Rect dstRect = Offset.zero & targetSize;

    // 1. Base background in case photo has transparency
    if (fourCornerGradient != null) {
      FourCornerGradientPainter(
        topLeft: fourCornerGradient.topLeft,
        topRight: fourCornerGradient.topRight,
        bottomLeft: fourCornerGradient.bottomLeft,
        bottomRight: fourCornerGradient.bottomRight,
      ).paint(canvas, targetSize);
    } else {
      canvas.drawRect(dstRect, Paint()..color = fallbackColor);
    }

    // 2. Photo with BoxFit.cover and optional baked Gaussian blur
    if (blurRadius > 0) {
      final double sigma = (blurRadius * 0.65).clamp(1.0, 64.0);
      canvas.saveLayer(
        dstRect,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: sigma,
            sigmaY: sigma,
            tileMode: TileMode.clamp,
          ),
      );
      paintImage(
        canvas: canvas,
        rect: dstRect,
        image: photo,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
      canvas.restore();
    } else {
      paintImage(
        canvas: canvas,
        rect: dstRect,
        image: photo,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
    }

    // 3. Baked dimming overlay
    if (dimming > 0) {
      canvas.drawRect(
        dstRect,
        Paint()..color = Colors.black.withValues(alpha: dimming.clamp(0.0, 1.0)),
      );
    }

    final ui.Picture picture = recorder.endRecording();
    final ui.Image baked = await picture.toImage(targetPxW, targetPxH);
    picture.dispose();
    return baked;
  }

  static Future<ui.Image?> _resolveProviderImage(
    ImageProvider provider,
  ) {
    final Completer<ui.Image?> completer = Completer<ui.Image?>();
    final ImageStream stream = provider.resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (ImageInfo info, bool _) {
        stream.removeListener(listener);
        if (!completer.isCompleted) {
          completer.complete(info.image);
        }
      },
      onError: (Object _, StackTrace? __) {
        stream.removeListener(listener);
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      },
    );
    stream.addListener(listener);
    return completer.future;
  }

  Widget _buildLightweightFallback(TheavWallpaper? wp) {
    if (wp == null) {
      return const SizedBox.expand();
    }
    if (wp.fourCornerGradient != null) {
      final grad = wp.fourCornerGradient!;
      return CustomPaint(
        painter: FourCornerGradientPainter(
          topLeft: grad.topLeft,
          topRight: grad.topRight,
          bottomLeft: grad.bottomLeft,
          bottomRight: grad.bottomRight,
        ),
        child: const SizedBox.expand(),
      );
    }
    return ColoredBox(
      color: wp.backgroundColor,
      child: const SizedBox.expand(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double dpr = View.maybeOf(context)?.devicePixelRatio ??
        MediaQuery.maybeDevicePixelRatioOf(context) ??
        1.0;

    return LayoutBuilder(
      builder: (context, constraints) {
        final double w = constraints.maxWidth;
        final double h = constraints.maxHeight;
        if (w <= 0 || h <= 0 || !w.isFinite || !h.isFinite) {
          return const SizedBox.shrink();
        }

        _ensureBaked(logicalW: w, logicalH: h, dpr: dpr);

        final ui.Image? img = _activeImage;
        if (img == null) {
          return _buildLightweightFallback(widget.wallpaper);
        }

        return RawImage(
          image: img,
          width: w,
          height: h,
          fit: BoxFit.fill,
          filterQuality: FilterQuality.low,
        );
      },
    );
  }
}
