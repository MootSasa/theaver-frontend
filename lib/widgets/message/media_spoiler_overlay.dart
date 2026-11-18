import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../utils/blur_utils.dart';
import '../../utils/haptic_utils.dart';
import 'spoiler_text_widget.dart';

/// Telegram-style animated blur + twinkling dust veil placed over photos,
/// videos, and albums when `hasMediaSpoiler == true`.
///
/// Tapping anywhere on the veiled media reveals the underlying widget cleanly.
class MediaSpoilerOverlay extends StatefulWidget {
  final String messageId;
  final bool hasSpoiler;
  final Widget child;
  final double borderRadius;
  final String? label;

  const MediaSpoilerOverlay({
    super.key,
    required this.messageId,
    required this.hasSpoiler,
    required this.child,
    this.borderRadius = 12.0,
    this.label,
  });

  @override
  State<MediaSpoilerOverlay> createState() => _MediaSpoilerOverlayState();
}

class _MediaSpoilerOverlayState extends State<MediaSpoilerOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _dustController;
  late final AnimationController _revealController;
  late final List<SpoilerParticle> _particles;
  bool _revealed = false;
  Size _lastSize = const Size(220, 220);

  @override
  void initState() {
    super.initState();
    _particles = List<SpoilerParticle>.generate(
      90,
      (_) => SpoilerParticle.create(240, 240, true),
    );
    _dustController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 60),
    )..addListener(_tickParticles);
    _revealController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    if (widget.hasSpoiler) {
      _dustController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant MediaSpoilerOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.messageId != widget.messageId ||
        (!oldWidget.hasSpoiler && widget.hasSpoiler)) {
      _revealed = false;
      _revealController.value = 0.0;
    }
    if (widget.hasSpoiler && !_revealed) {
      if (!_dustController.isAnimating) {
        _dustController.repeat();
      }
    } else if (_dustController.isAnimating) {
      _dustController.stop();
    }
  }

  void _tickParticles() {
    if (!mounted || _revealed || !widget.hasSpoiler) return;
    final w = math.max(_lastSize.width, 40.0);
    final h = math.max(_lastSize.height, 40.0);
    for (final p in _particles) {
      p.updateIdle(w, h);
    }
  }

  void _handleRevealTap() {
    if (_revealed) return;
    HapticUtils.tap();
    setState(() {
      _revealed = true;
    });
    _dustController.stop();
    _revealController.forward();
  }

  @override
  void dispose() {
    _dustController.removeListener(_tickParticles);
    _dustController.dispose();
    _revealController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.hasSpoiler) {
      return widget.child;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.borderRadius),
      child: LayoutBuilder(
        builder: (context, constraints) {
          if (constraints.hasBoundedWidth && constraints.hasBoundedHeight) {
            _lastSize = Size(constraints.maxWidth, constraints.maxHeight);
          }
          return Stack(
            fit: StackFit.passthrough,
            children: [
              widget.child,
              if (!_revealed || _revealController.isAnimating)
                Positioned.fill(
                  child: AnimatedBuilder(
                    animation: _revealController,
                    builder: (context, _) {
                      final double opacity =
                          (1.0 - _revealController.value).clamp(0.0, 1.0);
                      if (opacity <= 0.0) {
                        return const SizedBox.shrink();
                      }
                      final double sigma = 24.0 * opacity;
                      final ImageFilter filter = sigma > 0.5
                          ? BlurUtils.createDownsampledBlur(sigma)
                          : ImageFilter.blur(sigmaX: 0.0, sigmaY: 0.0);

                      return IgnorePointer(
                        ignoring: _revealed,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _handleRevealTap,
                          child: Opacity(
                            opacity: opacity,
                            child: BackdropFilter(
                              filter: filter,
                              child: Container(
                                color: Colors.black.withValues(alpha: 0.28),
                                child: Stack(
                                  children: [
                                    Positioned.fill(
                                      child: CustomPaint(
                                        painter: _MediaSpoilerDustPainter(
                                          repaint: _dustController,
                                          particles: _particles,
                                        ),
                                      ),
                                    ),
                                    Center(
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: Colors.black
                                              .withValues(alpha: 0.52),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                          border: Border.all(
                                            color: Colors.white
                                                .withValues(alpha: 0.22),
                                            width: 0.5,
                                          ),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const iconoir.EyeClosed(
                                              width: 16,
                                              height: 16,
                                              color: Colors.white,
                                            ),
                                            if (widget.label != null &&
                                                widget.label!.isNotEmpty) ...[
                                              const SizedBox(width: 6),
                                              Text(
                                                widget.label!,
                                                style: const TextStyle(
                                                  color: Colors.white,
                                                  fontSize: 12.5,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MediaSpoilerDustPainter extends CustomPainter {
  final List<SpoilerParticle> particles;

  _MediaSpoilerDustPainter({
    required Listenable repaint,
    required this.particles,
  }) : super(repaint: repaint);

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final paint = Paint()..style = PaintingStyle.fill;
    for (final p in particles) {
      final double px = (p.nx * size.width).clamp(0.0, size.width);
      final double py = (p.ny * size.height).clamp(0.0, size.height);
      final double radius = p.sizeTier == 2
          ? 1.75
          : (p.sizeTier == 1 ? 1.35 : 1.0);
      final double alpha = (0.35 + 0.55 * (0.5 + 0.5 * math.sin(p.phase)))
          .clamp(0.15, 0.9);
      paint.color = Colors.white.withValues(alpha: alpha);
      canvas.drawCircle(Offset(px, py), radius, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MediaSpoilerDustPainter oldDelegate) => false;
}
