import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// Renders a high-performance blurred preview placeholder for photos/videos
/// using the micro-thumbnail or a subtle fallback background.
///
/// Pre-bakes the Gaussian blur (`sigma = 18`) and `0.14` dark overlay into a
/// compact `64×64` GPU [ui.Image] once per thumbnail (cached in an LRU map),
/// avoiding a live `ImageFiltered` (`ImageFilterLayer`) offscreen blur pass on
/// every scroll frame in Impeller.
class BlurredMediaPlaceholder extends StatefulWidget {
  final String? thumbBase64;
  final double aspectRatio;
  final BoxFit fit;
  final BorderRadius? borderRadius;
  final double blurSigma;

  const BlurredMediaPlaceholder({
    Key? key,
    this.thumbBase64,
    this.aspectRatio = 1.0,
    this.fit = BoxFit.cover,
    this.borderRadius,
    this.blurSigma = 18.0,
  }) : super(key: key);

  @override
  State<BlurredMediaPlaceholder> createState() =>
      _BlurredMediaPlaceholderState();
}

class _BlurredMediaPlaceholderState extends State<BlurredMediaPlaceholder> {
  static const int _kBakedSizePx = 160;
  static const int _kMaxCacheEntries = 64;
  static final Map<int, ui.Image> _bakedThumbCache = <int, ui.Image>{};
  static final Map<int, Future<ui.Image?>> _pendingBakes =
      <int, Future<ui.Image?>>{};

  ui.Image? _bakedImage;
  int? _currentCacheKey;

  @override
  void initState() {
    super.initState();
    _resolveBakedThumb();
  }

  @override
  void didUpdateWidget(covariant BlurredMediaPlaceholder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thumbBase64 != widget.thumbBase64 ||
        oldWidget.blurSigma != widget.blurSigma) {
      _resolveBakedThumb();
    }
  }

  void _resolveBakedThumb() {
    final rawThumb = widget.thumbBase64;
    if (rawThumb == null || rawThumb.isEmpty) {
      _bakedImage = null;
      _currentCacheKey = null;
      return;
    }

    final int key = Object.hash(rawThumb, widget.blurSigma.round());
    _currentCacheKey = key;

    final ui.Image? cached = _bakedThumbCache[key];
    if (cached != null) {
      _bakedImage = cached;
      return;
    }

    final Future<ui.Image?> future = _pendingBakes[key] ??= _bakeThumb(
      rawThumb: rawThumb,
      blurSigma: widget.blurSigma,
    );

    future.then((img) {
      _pendingBakes.remove(key);
      if (img != null) {
        if (_bakedThumbCache.length >= _kMaxCacheEntries &&
            !_bakedThumbCache.containsKey(key)) {
          _bakedThumbCache.remove(_bakedThumbCache.keys.first);
        }
        _bakedThumbCache[key] = img;
      }
      if (mounted && _currentCacheKey == key && img != null) {
        setState(() {
          _bakedImage = img;
        });
      }
    });
  }

  static Future<ui.Image?> _bakeThumb({
    required String rawThumb,
    required double blurSigma,
  }) async {
    try {
      String raw = rawThumb.trim();
      final int commaIndex = raw.indexOf(',');
      if (commaIndex != -1) {
        raw = raw.substring(commaIndex + 1);
      }
      final decodedBytes = base64Decode(raw);
      if (decodedBytes.isEmpty) return null;

      final ui.Codec codec = await ui.instantiateImageCodec(decodedBytes);
      final ui.FrameInfo frame = await codec.getNextFrame();
      final ui.Image srcImg = frame.image;

      final ui.PictureRecorder recorder = ui.PictureRecorder();
      final Canvas canvas = Canvas(recorder);
      final double size = _kBakedSizePx.toDouble();
      final Rect rect = Rect.fromLTWH(0, 0, size, size);

      // 1. Dark neutral base
      canvas.drawRect(rect, Paint()..color = const Color(0xFF181818));

      // 2. Overscaled blurred micro-thumbnail in 160x160 space
      final double scaledSigma = (blurSigma * 0.625).clamp(4.0, 20.0);
      canvas.saveLayer(
        rect,
        Paint()
          ..imageFilter = ui.ImageFilter.blur(
            sigmaX: scaledSigma,
            sigmaY: scaledSigma,
            tileMode: TileMode.clamp,
          ),
      );
      final Rect overscaledRect = Rect.fromCenter(
        center: rect.center,
        width: size * 1.22,
        height: size * 1.22,
      );
      paintImage(
        canvas: canvas,
        rect: overscaledRect,
        image: srcImg,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      );
      canvas.restore();

      // 3. Subtle darkening overlay for download button contrast
      canvas.drawRect(
        rect,
        Paint()..color = Colors.black.withValues(alpha: 0.14),
      );

      final ui.Picture picture = recorder.endRecording();
      final ui.Image baked = await picture.toImage(_kBakedSizePx, _kBakedSizePx);
      picture.dispose();
      srcImg.dispose();
      return baked;
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    final ui.Image? baked = _bakedImage;
    if (baked != null) {
      content = RawImage(
        image: baked,
        fit: widget.fit,
        width: double.infinity,
        height: double.infinity,
        filterQuality: FilterQuality.medium,
      );
    } else {
      content = const ColoredBox(
        color: Color(0xFF181818),
        child: Center(
          child: Icon(
            Icons.image_outlined,
            color: Colors.white24,
            size: 32,
          ),
        ),
      );
    }

    if (widget.borderRadius != null) {
      content = ClipRRect(
        borderRadius: widget.borderRadius!,
        child: content,
      );
    }

    return content;
  }
}
