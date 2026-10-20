import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';
import 'package:flutter/material.dart';

/// Renders a high-performance blurred preview placeholder for photos/videos
/// using the micro-thumbnail or a subtle fallback background.
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
  Uint8List? _bytes;
  MemoryImage? _imageProvider;

  @override
  void initState() {
    super.initState();
    _decodeThumb();
  }

  @override
  void didUpdateWidget(covariant BlurredMediaPlaceholder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.thumbBase64 != widget.thumbBase64) {
      _decodeThumb();
    }
  }

  void _decodeThumb() {
    final rawThumb = widget.thumbBase64;
    if (rawThumb == null || rawThumb.isEmpty) {
      _bytes = null;
      _imageProvider = null;
      return;
    }
    try {
      String raw = rawThumb.trim();
      final commaIndex = raw.indexOf(',');
      if (commaIndex != -1) {
        raw = raw.substring(commaIndex + 1);
      }
      final decoded = base64Decode(raw);
      if (decoded.isNotEmpty) {
        _bytes = decoded;
        _imageProvider = MemoryImage(decoded);
      } else {
        _bytes = null;
        _imageProvider = null;
      }
    } catch (_) {
      _bytes = null;
      _imageProvider = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_imageProvider != null && _bytes != null) {
      content = RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Dark neutral base so parent bubble color NEVER bleeds through
            const ColoredBox(color: Color(0xFF181818)),

            // 2. Overscaled and clipped blurred micro-thumbnail (BlurHash-style smooth preview)
            ClipRect(
              child: Transform.scale(
                scale: 1.22,
                child: ImageFiltered(
                  imageFilter: ImageFilter.blur(
                    sigmaX: widget.blurSigma,
                    sigmaY: widget.blurSigma,
                    tileMode: TileMode.clamp,
                  ),
                  child: Image(
                    image: _imageProvider!,
                    fit: widget.fit,
                    gaplessPlayback: true,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
            ),

            // 3. Subtle darkening overlay for download button contrast
            Container(
              color: Colors.black.withValues(alpha: 0.14),
            ),
          ],
        ),
      );
    } else {
      content = Container(
        color: const Color(0xFF181818),
        child: const Center(
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
