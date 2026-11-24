import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/avatar_editor_models.dart';
import '../services/sticker_service.dart';
import '../utils/emoji_utils.dart';
import '../widgets/chat/sticker_item_widget.dart';

/// Output returned by [AvatarStudioRenderer].
@immutable
class AvatarRenderedOutput {
  final File? file;
  final Uint8List bytes;
  final String fileName;
  final int width;
  final int height;
  final bool preservedAnimation;

  const AvatarRenderedOutput({
    this.file,
    required this.bytes,
    required this.fileName,
    required this.width,
    required this.height,
    this.preservedAnimation = false,
  });
}

/// Shared exact transform & geometry calculations used by both [AvatarCropCanvas]
/// and [AvatarStudioRenderer] to guarantee 1:1 parity between preview and export.
class AvatarStudioGeometry {
  AvatarStudioGeometry._();

  /// Returns the normalized crop rectangle inside the canonical `1:1` stage square.
  static Rect effectiveCropNormRect(
    AvatarStudioState state,
    Size rawImageSize,
  ) {
    final Size rotSize = rotatedImageSize(rawImageSize, state.quarterTurns);
    switch (state.aspectMode) {
      case AvatarCropAspectMode.square1x1:
        return AvatarStudioState.fullRect;
      case AvatarCropAspectMode.original:
        final Rect r = state.freeRectNormalized;
        if (_isFullRect(r)) {
          return defaultOriginalNormRect(rotSize.width, rotSize.height);
        }
        return _clampNormRect(r, minSize: 0.18);
      case AvatarCropAspectMode.free:
        return _clampNormRect(state.freeRectNormalized, minSize: 0.18);
    }
  }

  /// Rotated image dimensions after applying [quarterTurns] (90-degree steps).
  static Size rotatedImageSize(Size rawImageSize, int quarterTurns) {
    final int q = ((quarterTurns % 4) + 4) % 4;
    if (q.isOdd) {
      return Size(rawImageSize.height, rawImageSize.width);
    }
    return rawImageSize;
  }

  /// Centered inscribed normalized rect inside `1:1` matching `rotW / rotH`.
  static Rect defaultOriginalNormRect(double rotW, double rotH) {
    final double safeW = math.max(1.0, rotW);
    final double safeH = math.max(1.0, rotH);
    final double aspect = safeW / safeH;
    if (aspect >= 1.0) {
      final double h = (1.0 / aspect).clamp(0.18, 1.0).toDouble();
      return Rect.fromLTWH(0.0, (1.0 - h) * 0.5, 1.0, h);
    } else {
      final double w = aspect.clamp(0.18, 1.0).toDouble();
      return Rect.fromLTWH((1.0 - w) * 0.5, 0.0, w, 1.0);
    }
  }

  /// Total rotation in radians (`quarterTurns * 90deg + fineAngleDegrees`).
  static double totalRotationRadians(AvatarStudioState state) {
    final int q = ((state.quarterTurns % 4) + 4) % 4;
    return (q * math.pi * 0.5) + (state.fineAngleDegrees * math.pi / 180.0);
  }

  /// Base scale factor at `scale = 1.0, fineAngle = 0` so the image covers [cropSize].
  static double computeBaseCoverScale({
    required Size cropSize,
    required Size rawImageSize,
    required int quarterTurns,
  }) {
    final Size rotSize = rotatedImageSize(rawImageSize, quarterTurns);
    final double sx = cropSize.width / math.max(1.0, rotSize.width);
    final double sy = cropSize.height / math.max(1.0, rotSize.height);
    return math.max(sx, sy);
  }

  /// Minimum scale multiplier (`>= 1.0`) needed so rotating by [fineAngleDegrees]
  /// never exposes blank triangles inside [cropSize].
  static double computeAutoStraightenScale({
    required Size cropSize,
    required Size rawImageSize,
    required int quarterTurns,
    required double fineAngleDegrees,
    required double baseScale,
  }) {
    if (fineAngleDegrees.abs() <= 1e-4) return 1.0;
    final Size rotSize = rotatedImageSize(rawImageSize, quarterTurns);
    final double phi = fineAngleDegrees * math.pi / 180.0;
    final double cosPhi = math.cos(phi).abs();
    final double sinPhi = math.sin(phi).abs();
    final double denomW = math.max(1e-6, rotSize.width * baseScale);
    final double denomH = math.max(1e-6, rotSize.height * baseScale);
    final double minX = (cropSize.width * cosPhi + cropSize.height * sinPhi) / denomW;
    final double minY = (cropSize.width * sinPhi + cropSize.height * cosPhi) / denomH;
    return math.max(1.0, math.max(minX, minY));
  }

  /// Effective zoom scale applied on top of `baseCoverScale`.
  static double computeEffectiveScale({
    required Size cropSize,
    required Size rawImageSize,
    required AvatarStudioState state,
  }) {
    final double baseScale = computeBaseCoverScale(
      cropSize: cropSize,
      rawImageSize: rawImageSize,
      quarterTurns: state.quarterTurns,
    );
    final double minStraighten = computeAutoStraightenScale(
      cropSize: cropSize,
      rawImageSize: rawImageSize,
      quarterTurns: state.quarterTurns,
      fineAngleDegrees: state.fineAngleDegrees,
      baseScale: baseScale,
    );
    return math.max(state.scale, minStraighten);
  }

  /// Clamps normalized [panOffset] (relative to [stageSide]) so all 4 corners of
  /// [cropSize] remain completely covered by the rotated & scaled source image.
  static Offset clampPanOffset({
    required Offset panOffset,
    required double stageSide,
    required Size cropSize,
    required Size rawImageSize,
    required AvatarStudioState state,
  }) {
    if (stageSide <= 0.0) return Offset.zero;
    final double baseScale = computeBaseCoverScale(
      cropSize: cropSize,
      rawImageSize: rawImageSize,
      quarterTurns: state.quarterTurns,
    );
    final double effScale = computeEffectiveScale(
      cropSize: cropSize,
      rawImageSize: rawImageSize,
      state: state,
    );
    final double fullScale = baseScale * effScale;
    final double totalAngle = totalRotationRadians(state);
    final double cosT = math.cos(totalAngle).abs();
    final double sinT = math.sin(totalAngle).abs();

    final double extentX = (cropSize.width * cosT + cropSize.height * sinT) * 0.5;
    final double extentY = (cropSize.width * sinT + cropSize.height * cosT) * 0.5;
    final double imgHalfW = rawImageSize.width * fullScale * 0.5;
    final double imgHalfH = rawImageSize.height * fullScale * 0.5;

    final double maxPanLocalX = math.max(0.0, imgHalfW - extentX);
    final double maxPanLocalY = math.max(0.0, imgHalfH - extentY);

    final Offset p = Offset(panOffset.dx * stageSide, panOffset.dy * stageSide);
    final double cosNeg = math.cos(-totalAngle);
    final double sinNeg = math.sin(-totalAngle);
    final double rx =
        (p.dx * cosNeg - p.dy * sinNeg).clamp(-maxPanLocalX, maxPanLocalX);
    final double ry =
        (p.dx * sinNeg + p.dy * cosNeg).clamp(-maxPanLocalY, maxPanLocalY);

    final double cosPos = math.cos(totalAngle);
    final double sinPos = math.sin(totalAngle);
    final double clampedX = rx * cosPos - ry * sinPos;
    final double clampedY = rx * sinPos + ry * cosPos;
    return Offset(clampedX / stageSide, clampedY / stageSide);
  }

  static bool _isFullRect(Rect r) {
    return r.left.abs() < 1e-3 &&
        r.top.abs() < 1e-3 &&
        (r.width - 1.0).abs() < 1e-3 &&
        (r.height - 1.0).abs() < 1e-3;
  }

  static Rect _clampNormRect(Rect r, {required double minSize}) {
    final double left = r.left.clamp(0.0, 1.0 - minSize).toDouble();
    final double top = r.top.clamp(0.0, 1.0 - minSize).toDouble();
    final double width = r.width.clamp(minSize, 1.0 - left).toDouble();
    final double height = r.height.clamp(minSize, 1.0 - top).toDouble();
    return Rect.fromLTWH(left, top, width, height);
  }
}

/// Shared canvas drawing routines used identically by live preview & raster export.
class AvatarStudioPaint {
  AvatarStudioPaint._();

  /// Paints the transformed & color-graded [image] centered in [cropRect].
  static void paintPhotoLayer({
    required Canvas canvas,
    required ui.Image image,
    required Rect cropRect,
    required double stageSide,
    required AvatarStudioState state,
    FilterQuality filterQuality = FilterQuality.high,
  }) {
    final Size rawSize = Size(image.width.toDouble(), image.height.toDouble());
    final Size cropSize = cropRect.size;
    final double baseScale = AvatarStudioGeometry.computeBaseCoverScale(
      cropSize: cropSize,
      rawImageSize: rawSize,
      quarterTurns: state.quarterTurns,
    );
    final double effScale = AvatarStudioGeometry.computeAutoStraightenScale(
      cropSize: cropSize,
      rawImageSize: rawSize,
      quarterTurns: state.quarterTurns,
      fineAngleDegrees: state.fineAngleDegrees,
      baseScale: baseScale,
    );
    final double appliedScale = math.max(state.scale, effScale) * baseScale;
    final Offset clampedPan = AvatarStudioGeometry.clampPanOffset(
      panOffset: state.panOffset,
      stageSide: stageSide,
      cropSize: cropSize,
      rawImageSize: rawSize,
      state: state,
    );
    final double totalAngle = AvatarStudioGeometry.totalRotationRadians(state);

    final Paint imagePaint = Paint()
      ..isAntiAlias = true
      ..filterQuality = filterQuality;
    if (state.adjustments.hasColorMatrixEffect) {
      imagePaint.colorFilter = ColorFilter.matrix(
        state.adjustments.toColorMatrix(),
      );
    }

    canvas.save();
    canvas.translate(
      cropRect.center.dx + clampedPan.dx * stageSide,
      cropRect.center.dy + clampedPan.dy * stageSide,
    );
    canvas.rotate(totalAngle);
    canvas.scale(
      (state.flipHorizontal ? -1.0 : 1.0) * appliedScale,
      appliedScale,
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0.0, 0.0, rawSize.width, rawSize.height),
      Rect.fromCenter(
        center: Offset.zero,
        width: rawSize.width,
        height: rawSize.height,
      ),
      imagePaint,
    );
    canvas.restore();
  }

  /// Paints radial edge vignette over [cropRect].
  static void paintVignette({
    required Canvas canvas,
    required Rect cropRect,
    required double vignette,
  }) {
    if (vignette <= 1e-4) return;
    final double radius = math.max(cropRect.width, cropRect.height) * 0.72;
    final Paint paint = Paint()
      ..shader = ui.Gradient.radial(
        cropRect.center,
        math.max(1.0, radius),
        <Color>[
          Colors.transparent,
          Colors.black.withValues(alpha: (vignette * 0.78).clamp(0.0, 0.88)),
        ],
        const <double>[0.42, 1.0],
      );
    canvas.drawRect(cropRect, paint);
  }

  /// Paints normalized [strokes] inside [bounds].
  static void paintBrushStrokes({
    required Canvas canvas,
    required Rect bounds,
    required List<AvatarBrushStroke> strokes,
  }) {
    if (strokes.isEmpty || bounds.isEmpty) return;
    final double minSide = math.min(bounds.width, bounds.height);

    for (final AvatarBrushStroke stroke in strokes) {
      if (stroke.points.isEmpty) continue;
      final double widthPx =
          (stroke.strokeWidthFraction * minSide).clamp(1.5, minSide * 0.16);

      final List<Offset> pts = <Offset>[
        for (final pt in stroke.points)
          Offset(
            bounds.left + pt.dx * bounds.width,
            bounds.top + pt.dy * bounds.height,
          ),
      ];

      if (pts.length == 1) {
        _paintSingleDot(canvas, pts.first, widthPx, stroke);
        continue;
      }

      final Path path = Path()..moveTo(pts.first.dx, pts.first.dy);
      for (int i = 1; i < pts.length - 1; i++) {
        final Offset mid = Offset(
          (pts[i].dx + pts[i + 1].dx) * 0.5,
          (pts[i].dy + pts[i + 1].dy) * 0.5,
        );
        path.quadraticBezierTo(pts[i].dx, pts[i].dy, mid.dx, mid.dy);
      }
      path.lineTo(pts.last.dx, pts.last.dy);

      switch (stroke.style) {
        case AvatarBrushStyle.pen:
          final Paint penPaint = Paint()
            ..color = stroke.color
            ..strokeWidth = widthPx
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..isAntiAlias = true;
          canvas.drawPath(path, penPaint);
          break;

        case AvatarBrushStyle.neon:
          final Paint glowPaint = Paint()
            ..color = stroke.color.withValues(alpha: 0.62)
            ..strokeWidth = widthPx * 2.15
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..maskFilter =
                MaskFilter.blur(BlurStyle.normal, math.max(1.5, widthPx * 0.72))
            ..isAntiAlias = true;
          final Paint corePaint = Paint()
            ..color = Color.lerp(stroke.color, Colors.white, 0.75) ??
                Colors.white
            ..strokeWidth = math.max(1.0, widthPx * 0.62)
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..isAntiAlias = true;
          canvas.drawPath(path, glowPaint);
          canvas.drawPath(path, corePaint);
          break;

        case AvatarBrushStyle.highlighter:
          final Paint markerPaint = Paint()
            ..color = stroke.color.withValues(alpha: 0.42)
            ..strokeWidth = widthPx * 1.9
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round
            ..isAntiAlias = true;
          canvas.drawPath(path, markerPaint);
          break;
      }
    }
  }

  static void _paintSingleDot(
    Canvas canvas,
    Offset center,
    double widthPx,
    AvatarBrushStroke stroke,
  ) {
    switch (stroke.style) {
      case AvatarBrushStyle.pen:
        canvas.drawCircle(
          center,
          widthPx * 0.5,
          Paint()
            ..color = stroke.color
            ..isAntiAlias = true,
        );
        break;
      case AvatarBrushStyle.neon:
        canvas.drawCircle(
          center,
          widthPx * 1.05,
          Paint()
            ..color = stroke.color.withValues(alpha: 0.62)
            ..maskFilter =
                MaskFilter.blur(BlurStyle.normal, math.max(1.5, widthPx * 0.72))
            ..isAntiAlias = true,
        );
        canvas.drawCircle(
          center,
          widthPx * 0.35,
          Paint()
            ..color =
                Color.lerp(stroke.color, Colors.white, 0.75) ?? Colors.white
            ..isAntiAlias = true,
        );
        break;
      case AvatarBrushStyle.highlighter:
        canvas.drawCircle(
          center,
          widthPx * 0.95,
          Paint()
            ..color = stroke.color.withValues(alpha: 0.42)
            ..isAntiAlias = true,
        );
        break;
    }
  }

  /// Measures and lays out [layer] text painter inside [cropSize].
  static ({TextPainter painter, Size boxSize, double padX, double padY, double radius})
      layoutTextLayer({
    required Size cropSize,
    required AvatarTextLayer layer,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    final double minSide = math.min(cropSize.width, cropSize.height);
    final double fontSize =
        (minSide * 0.068 * layer.scale).clamp(10.0, minSide * 0.52);
    final Color fgColor = switch (layer.backgroundMode) {
      AvatarTextBackgroundMode.solid =>
        layer.color.computeLuminance() > 0.58
            ? const Color(0xFF111318)
            : Colors.white,
      AvatarTextBackgroundMode.none || AvatarTextBackgroundMode.translucent =>
        layer.color,
    };

    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: layer.text,
        style: TextStyle(
          color: fgColor,
          fontSize: fontSize,
          fontWeight: layer.bold ? FontWeight.w700 : FontWeight.w500,
          height: 1.18,
          shadows: layer.backgroundMode == AvatarTextBackgroundMode.none
              ? <Shadow>[
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.65),
                    blurRadius: fontSize * 0.18,
                    offset: Offset(0.0, fontSize * 0.05),
                  ),
                ]
              : null,
        ),
      ),
      textAlign: TextAlign.center,
      textDirection: textDirection,
    )..layout(maxWidth: math.max(32.0, cropSize.width * 0.84));

    final double padX =
        layer.backgroundMode == AvatarTextBackgroundMode.none ? 4.0 : fontSize * 0.52;
    final double padY =
        layer.backgroundMode == AvatarTextBackgroundMode.none ? 2.0 : fontSize * 0.28;
    final double radius = fontSize * 0.42;
    return (
      painter: tp,
      boxSize: Size(tp.width + padX * 2, tp.height + padY * 2),
      padX: padX,
      padY: padY,
      radius: radius,
    );
  }

  /// Paints [layer] inside [bounds] at its normalized position, scale & rotation.
  static void paintTextLayer({
    required Canvas canvas,
    required Rect bounds,
    required AvatarTextLayer layer,
    TextDirection textDirection = TextDirection.ltr,
  }) {
    if (layer.text.trim().isEmpty) return;
    final measured = layoutTextLayer(
      cropSize: bounds.size,
      layer: layer,
      textDirection: textDirection,
    );
    final TextPainter tp = measured.painter;
    final Size box = measured.boxSize;
    final Offset center = Offset(
      bounds.left + layer.normX * bounds.width,
      bounds.top + layer.normY * bounds.height,
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(layer.rotation);

    if (layer.backgroundMode != AvatarTextBackgroundMode.none) {
      final Color bgColor = layer.backgroundMode == AvatarTextBackgroundMode.solid
          ? layer.color
          : (layer.color.computeLuminance() > 0.58
              ? Colors.black.withValues(alpha: 0.54)
              : Colors.white.withValues(alpha: 0.78));
      final RRect pill = RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset.zero, width: box.width, height: box.height),
        Radius.circular(measured.radius),
      );
      canvas.drawRRect(
        pill,
        Paint()
          ..color = bgColor
          ..isAntiAlias = true,
      );
    }

    tp.paint(canvas, Offset(-tp.width * 0.5, -tp.height * 0.5));
    canvas.restore();
  }
}

/// High-resolution raster exporter for [TheavAvatarEditorScreen] and
/// [AvatarEmojiConstructorView].
class AvatarStudioRenderer {
  AvatarStudioRenderer._();

  static const int defaultMaxDimension = 1600;
  static const int jpegQuality = 90;
  static const int maxFileSizeBytes = 3 * 1024 * 1024;

  /// Returns `true` when [bytes] represent a GIF or animated WebP file.
  static bool isAnimatedMediaBytes(Uint8List bytes, [String fileName = '']) {
    final String lower = fileName.trim().toLowerCase();
    if (bytes.length >= 6) {
      // GIF87a / GIF89a
      if (bytes[0] == 0x47 &&
          bytes[1] == 0x49 &&
          bytes[2] == 0x46 &&
          bytes[3] == 0x38 &&
          (bytes[4] == 0x37 || bytes[4] == 0x39) &&
          bytes[5] == 0x61) {
        return true;
      }
    }
    if (lower.endsWith('.gif') && bytes.isNotEmpty) {
      return true;
    }

    // WebP RIFF container: inspect VP8X animation flag or ANIM chunk.
    if (bytes.length >= 21 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      int offset = 12;
      final int scanLimit = math.min(bytes.length - 8, 512);
      while (offset <= scanLimit) {
        final String chunkId = String.fromCharCodes(
          bytes.sublist(offset, offset + 4),
        );
        final int chunkSize = bytes[offset + 4] |
            (bytes[offset + 5] << 8) |
            (bytes[offset + 6] << 16) |
            (bytes[offset + 7] << 24);
        if (chunkId == 'ANIM') return true;
        if (chunkId == 'VP8X' && offset + 8 < bytes.length) {
          final int flags = bytes[offset + 8];
          if ((flags & 0x02) != 0) return true;
        }
        final int step = 8 + chunkSize + (chunkSize.isOdd ? 1 : 0);
        if (step <= 8) break;
        offset += step;
      }
    }
    return false;
  }

  /// Decodes raw image bytes into a GPU [ui.Image].
  static Future<ui.Image> decodeImage(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    try {
      final ui.FrameInfo frame = await codec.getNextFrame();
      return frame.image;
    } finally {
      codec.dispose();
    }
  }

  /// Renders the edited avatar state into compressed JPEG (or fallback PNG)
  /// bytes & a temporary file, or preserves animated GIF/WebP bytes verbatim
  /// when `!state.hasEditsForAnimationPreservation`.
  static Future<AvatarRenderedOutput> renderEditedAvatar({
    required Uint8List sourceBytes,
    required String sourceFileName,
    required AvatarStudioState state,
    int maxDimension = defaultMaxDimension,
    TextDirection textDirection = TextDirection.ltr,
  }) async {
    final bool isAnimated = isAnimatedMediaBytes(sourceBytes, sourceFileName);
    if (isAnimated && !state.hasEditsForAnimationPreservation) {
      final ui.Image probe = await decodeImage(sourceBytes);
      final int w = probe.width;
      final int h = probe.height;
      probe.dispose();

      final String ext =
          sourceFileName.toLowerCase().endsWith('.webp') ? '.webp' : '.gif';
      final String outName =
          'avatar_studio_${DateTime.now().millisecondsSinceEpoch}$ext';
      final File? file = await _writeTempFile(sourceBytes, outName);
      return AvatarRenderedOutput(
        file: file,
        bytes: sourceBytes,
        fileName: outName,
        width: w,
        height: h,
        preservedAnimation: true,
      );
    }

    final ui.Image sourceImage = await decodeImage(sourceBytes);
    final List<ui.Image> ownedStickerImages = <ui.Image>[];
    final Map<String, ui.Image> resolvedStickers = <String, ui.Image>{};

    try {
      for (final AvatarStickerLayer layer in state.stickers) {
        final String? url = layer.stickerUrl;
        if (url != null && url.isNotEmpty && !resolvedStickers.containsKey(url)) {
          final loaded = await _loadStickerImage(
            url: url,
            format: layer.stickerFormat,
            targetPx: 512,
          );
          if (loaded != null) {
            resolvedStickers[url] = loaded.image;
            if (loaded.owned) {
              ownedStickerImages.add(loaded.image);
            }
          }
        }
      }

      final Size rawSize = Size(
        sourceImage.width.toDouble(),
        sourceImage.height.toDouble(),
      );
      final Rect normRect = AvatarStudioGeometry.effectiveCropNormRect(
        state,
        rawSize,
      );
      final double cropAspect =
          normRect.width / math.max(1e-6, normRect.height);

      final double baseUnitScale = AvatarStudioGeometry.computeBaseCoverScale(
        cropSize: normRect.size,
        rawImageSize: rawSize,
        quarterTurns: state.quarterTurns,
      );
      final double effScale = AvatarStudioGeometry.computeEffectiveScale(
        cropSize: normRect.size,
        rawImageSize: rawSize,
        state: state,
      );
      final double sourceCoveredW =
          normRect.width / math.max(1e-6, baseUnitScale * effScale);
      final double sourceCoveredH =
          normRect.height / math.max(1e-6, baseUnitScale * effScale);
      final double sourceLong = math.max(sourceCoveredW, sourceCoveredH);
      final double rawMaxSide = math.max(rawSize.width, rawSize.height);
      final int minDim =
          rawMaxSide >= 480 ? math.min(480, maxDimension) : math.max(1, rawMaxSide.round());
      final int targetLong =
          sourceLong.round().clamp(minDim, maxDimension).toInt();

      final int outW;
      final int outH;
      if (cropAspect >= 1.0) {
        outW = targetLong;
        outH = math.max(1, (targetLong / cropAspect).round());
      } else {
        outH = targetLong;
        outW = math.max(1, (targetLong * cropAspect).round());
      }

      final Rect outBounds = Rect.fromLTWH(0.0, 0.0, outW.toDouble(), outH.toDouble());
      final double exportStageSide = outW / math.max(1e-6, normRect.width);

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder, outBounds);
      canvas.drawRect(outBounds, Paint()..color = Colors.black);

      AvatarStudioPaint.paintPhotoLayer(
        canvas: canvas,
        image: sourceImage,
        cropRect: outBounds,
        stageSide: exportStageSide,
        state: state,
        filterQuality: FilterQuality.high,
      );

      AvatarStudioPaint.paintVignette(
        canvas: canvas,
        cropRect: outBounds,
        vignette: state.adjustments.vignette,
      );

      AvatarStudioPaint.paintBrushStrokes(
        canvas: canvas,
        bounds: outBounds,
        strokes: state.strokes,
      );

      for (final AvatarStickerLayer layer in state.stickers) {
        _paintStickerLayer(
          canvas: canvas,
          bounds: outBounds,
          layer: layer,
          stickerImages: resolvedStickers,
          textDirection: textDirection,
        );
      }

      for (final AvatarTextLayer layer in state.textLayers) {
        AvatarStudioPaint.paintTextLayer(
          canvas: canvas,
          bounds: outBounds,
          layer: layer,
          textDirection: textDirection,
        );
      }

      final ui.Picture picture = recorder.endRecording();
      late final ui.Image rendered;
      try {
        rendered = await picture.toImage(outW, outH);
      } finally {
        picture.dispose();
      }

      late final Uint8List pngBytes;
      try {
        final ByteData? bd =
            await rendered.toByteData(format: ui.ImageByteFormat.png);
        if (bd == null) {
          throw StateError('Failed to encode rendered avatar to PNG bytes');
        }
        pngBytes = bd.buffer.asUint8List();
      } finally {
        rendered.dispose();
      }

      final encoded = await _compressOutputBytes(
        pngBytes,
        prefix: 'avatar_studio',
        preferJpeg: true,
      );
      final File? outFile = await _writeTempFile(encoded.bytes, encoded.fileName);
      return AvatarRenderedOutput(
        file: outFile,
        bytes: encoded.bytes,
        fileName: encoded.fileName,
        width: outW,
        height: outH,
      );
    } finally {
      sourceImage.dispose();
      for (final ui.Image img in ownedStickerImages) {
        img.dispose();
      }
    }
  }

  /// Renders an emoji / sticker / monogram constructor avatar at [size]x[size].
  static Future<AvatarRenderedOutput> renderEmojiConstructorAvatar({
    required AvatarEmojiConstructorConfig config,
    int size = 1080,
    TextDirection textDirection = TextDirection.ltr,
  }) async {
    final int safeSize = size.clamp(128, 2048);
    final double dim = safeSize.toDouble();
    final Rect bounds = Rect.fromLTWH(0.0, 0.0, dim, dim);

    final List<Color> colors = config.gradientColors.length >= 2
        ? config.gradientColors
        : <Color>[
            config.gradientColors.isNotEmpty
                ? config.gradientColors.first
                : const Color(0xFF4FACFE),
            config.gradientColors.isNotEmpty
                ? config.gradientColors.first
                : const Color(0xFF00F2FE),
          ];

    ({ui.Image image, bool owned})? loadedSticker;
    if (config.stickerUrl != null && config.stickerUrl!.isNotEmpty) {
      loadedSticker = await _loadStickerImage(
        url: config.stickerUrl!,
        format: config.stickerFormat,
        targetPx: (dim * config.foregroundScale).round().clamp(128, 1024),
      );
    }

    try {
      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder, bounds);

      final ui.Shader bgShader = config.isRadial
          ? ui.Gradient.radial(
              Offset(dim * 0.5, dim * 0.5),
              dim * 0.72,
              colors,
              _evenStops(colors.length),
            )
          : ui.Gradient.linear(
              Offset.zero,
              Offset(dim, dim),
              colors,
              _evenStops(colors.length),
            );
      canvas.drawRect(bounds, Paint()..shader = bgShader);

      final double fgBox = dim * config.foregroundScale.clamp(0.45, 0.95);
      final Offset center = Offset(dim * 0.5, dim * 0.5);

      if (loadedSticker != null) {
        final ui.Image stImg = loadedSticker.image;
        final double aspect =
            stImg.width / math.max(1.0, stImg.height.toDouble());
        final double drawW = aspect >= 1.0 ? fgBox : fgBox * aspect;
        final double drawH = aspect >= 1.0 ? fgBox / aspect : fgBox;
        canvas.drawImageRect(
          stImg,
          Rect.fromLTWH(0.0, 0.0, stImg.width.toDouble(), stImg.height.toDouble()),
          Rect.fromCenter(center: center, width: drawW, height: drawH),
          Paint()
            ..isAntiAlias = true
            ..filterQuality = FilterQuality.high,
        );
      } else if (config.monogramText != null &&
          config.monogramText!.trim().isNotEmpty) {
        final String text = config.monogramText!.trim();
        final double charFactor = text.length <= 1
            ? 0.72
            : (text.length == 2 ? 0.58 : 0.44);
        final TextPainter tp = TextPainter(
          text: TextSpan(
            text: text,
            style: TextStyle(
              color: Colors.white,
              fontSize: fgBox * charFactor,
              fontWeight: FontWeight.w800,
              letterSpacing: text.length > 1 ? -1.5 : 0.0,
              height: 1.0,
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: textDirection,
          maxLines: 1,
        )..layout(maxWidth: dim * 0.9);
        tp.paint(
          canvas,
          Offset(center.dx - tp.width * 0.5, center.dy - tp.height * 0.5),
        );
      } else {
        final String emoji =
            (config.emoji != null && config.emoji!.trim().isNotEmpty)
                ? config.emoji!.trim()
                : '😎';
        final TextPainter tp = TextPainter(
          text: TextSpan(
            text: emoji,
            style: EmojiUtils.emojiTextStyle(
              fontSize: fgBox * 0.84,
              height: 1.0,
            ),
          ),
          textAlign: TextAlign.center,
          textDirection: textDirection,
          maxLines: 1,
        )..layout();
        tp.paint(
          canvas,
          Offset(center.dx - tp.width * 0.5, center.dy - tp.height * 0.5),
        );
      }

      final ui.Picture picture = recorder.endRecording();
      late final ui.Image rendered;
      try {
        rendered = await picture.toImage(safeSize, safeSize);
      } finally {
        picture.dispose();
      }

      late final Uint8List pngBytes;
      try {
        final ByteData? bd =
            await rendered.toByteData(format: ui.ImageByteFormat.png);
        if (bd == null) {
          throw StateError('Failed to encode constructor avatar to PNG');
        }
        pngBytes = bd.buffer.asUint8List();
      } finally {
        rendered.dispose();
      }

      final encoded = await _compressOutputBytes(
        pngBytes,
        prefix: 'avatar_constructor',
        preferJpeg: false,
      );
      final File? outFile = await _writeTempFile(encoded.bytes, encoded.fileName);
      return AvatarRenderedOutput(
        file: outFile,
        bytes: encoded.bytes,
        fileName: encoded.fileName,
        width: safeSize,
        height: safeSize,
      );
    } finally {
      if (loadedSticker != null && loadedSticker.owned) {
        loadedSticker.image.dispose();
      }
    }
  }

  static void _paintStickerLayer({
    required Canvas canvas,
    required Rect bounds,
    required AvatarStickerLayer layer,
    required Map<String, ui.Image> stickerImages,
    required TextDirection textDirection,
  }) {
    final double minSide = math.min(bounds.width, bounds.height);
    final double targetSide = minSide * 0.24 * layer.scale;
    final Offset center = Offset(
      bounds.left + layer.normX * bounds.width,
      bounds.top + layer.normY * bounds.height,
    );

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(layer.rotation);

    final ui.Image? stImg =
        layer.stickerUrl != null ? stickerImages[layer.stickerUrl] : null;
    if (stImg != null) {
      final double aspect =
          stImg.width / math.max(1.0, stImg.height.toDouble());
      final double drawW = aspect >= 1.0 ? targetSide : targetSide * aspect;
      final double drawH = aspect >= 1.0 ? targetSide / aspect : targetSide;
      canvas.drawImageRect(
        stImg,
        Rect.fromLTWH(0.0, 0.0, stImg.width.toDouble(), stImg.height.toDouble()),
        Rect.fromCenter(center: Offset.zero, width: drawW, height: drawH),
        Paint()
          ..isAntiAlias = true
          ..filterQuality = FilterQuality.high,
      );
    } else if (layer.emoji != null && layer.emoji!.isNotEmpty) {
      final TextPainter tp = TextPainter(
        text: TextSpan(
          text: layer.emoji,
          style: EmojiUtils.emojiTextStyle(
            fontSize: targetSide * 0.84,
            height: 1.0,
          ),
        ),
        textAlign: TextAlign.center,
        textDirection: textDirection,
        maxLines: 1,
      )..layout();
      tp.paint(canvas, Offset(-tp.width * 0.5, -tp.height * 0.5));
    }

    canvas.restore();
  }

  static Future<({ui.Image image, bool owned})?> _loadStickerImage({
    required String url,
    required String format,
    required int targetPx,
  }) async {
    try {
      if (StickerMediaView.isLottieUrlOrFormat(url, format)) {
        final ui.Image? baked = await StickerService.instance.getBakedFirstFrame(
          url,
          targetPx: targetPx.clamp(128, 512),
        );
        if (baked != null) {
          // Shared cache in StickerService owns baked frames.
          return (image: baked, owned: false);
        }
        return null;
      }

      if (!kIsWeb) {
        final File? rasterFile =
            StickerService.instance.getCachedRasterFileSync(url) ??
                await StickerService.instance.getOrDownloadRasterFile(url);
        if (rasterFile != null && await rasterFile.exists()) {
          final Uint8List bytes = await rasterFile.readAsBytes();
          if (bytes.isNotEmpty) {
            final ui.Image decoded = await decodeImage(bytes);
            return (image: decoded, owned: true);
          }
        }
      }
    } catch (e) {
      debugPrint('[AvatarStudioRenderer] Sticker load failed ($url): $e');
    }
    return null;
  }

  static List<double>? _evenStops(int count) {
    if (count < 2) return null;
    return List<double>.generate(
      count,
      (i) => i / (count - 1),
      growable: false,
    );
  }

  static Future<({Uint8List bytes, String fileName})> _compressOutputBytes(
    Uint8List pngBytes, {
    required String prefix,
    required bool preferJpeg,
  }) async {
    final int ts = DateTime.now().millisecondsSinceEpoch;
    if (!preferJpeg && pngBytes.length <= maxFileSizeBytes) {
      return (bytes: pngBytes, fileName: '${prefix}_$ts.png');
    }

    int quality = jpegQuality;
    Uint8List bestBytes = pngBytes;
    bool compressedToJpeg = false;

    try {
      Uint8List result = await FlutterImageCompress.compressWithList(
        pngBytes,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (result.isNotEmpty) {
        bestBytes = result;
        compressedToJpeg = true;
      }
      while (bestBytes.length > maxFileSizeBytes && quality > 10) {
        quality -= 10;
        result = await FlutterImageCompress.compressWithList(
          pngBytes,
          quality: quality,
          format: CompressFormat.jpeg,
        );
        if (result.isNotEmpty) {
          bestBytes = result;
        } else {
          break;
        }
      }
    } catch (_) {
      // Headless tests / Windows / Linux where FlutterImageCompress is unimplemented.
    }

    final String ext = compressedToJpeg ? '.jpg' : '.png';
    return (bytes: bestBytes, fileName: '${prefix}_$ts$ext');
  }

  static Future<File?> _writeTempFile(Uint8List bytes, String fileName) async {
    if (kIsWeb) return null;
    try {
      Directory dir;
      try {
        dir = await getTemporaryDirectory();
      } catch (_) {
        dir = Directory.systemTemp;
      }
      final File outFile = File(p.join(dir.path, fileName));
      await outFile.writeAsBytes(bytes, flush: true);
      return outFile;
    } catch (e) {
      debugPrint('[AvatarStudioRenderer] Temp file write skipped: $e');
      return null;
    }
  }
}
