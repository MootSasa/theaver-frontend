import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../../models/profile_customization.dart';
import '../chat/sticker_item_widget.dart';

/// Wraps a circular user avatar with an animated procedural (or media) decoration frame.
///
/// Performance guarantees:
/// - Automatically pauses animations when [animate] is false, [avatarDiameter] < 36,
///   system reduce-motion is enabled, or fast scrolling defers heavy work
///   (`Scrollable.recommendDeferredLoadingForContext`), rendering a clean `t = 0.25` frame.
/// - Wraps the decoration overlay in [RepaintBoundary] and [IgnorePointer].
class AvatarDecorationFrame extends StatefulWidget {
  final AvatarDecorationPreset? decoration;
  final double avatarDiameter;
  final Widget child;
  final bool animate;
  final double opacity;

  const AvatarDecorationFrame({
    super.key,
    required this.decoration,
    required this.avatarDiameter,
    required this.child,
    this.animate = true,
    this.opacity = 1.0,
  });

  @override
  AvatarDecorationFrameState createState() => AvatarDecorationFrameState();
}

class AvatarDecorationFrameState extends State<AvatarDecorationFrame>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @visibleForTesting
  double get debugAnimationValue => _controller.value;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
      value: 0.25,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimationState();
  }

  @override
  void didUpdateWidget(covariant AvatarDecorationFrame oldWidget) {
    super.didUpdateWidget(oldWidget);
    final presetChanged = oldWidget.decoration?.id != widget.decoration?.id;
    if (oldWidget.decoration != widget.decoration ||
        oldWidget.animate != widget.animate ||
        oldWidget.avatarDiameter != widget.avatarDiameter ||
        oldWidget.opacity != widget.opacity) {
      _syncAnimationState(resetStaticPhase: presetChanged);
    }
  }

  bool _shouldAnimate(BuildContext context) {
    final dec = widget.decoration;
    if (dec == null || widget.opacity <= 0.001) return false;
    if (!widget.animate || !dec.isAnimated) return false;
    if (widget.avatarDiameter < 36.0) return false;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) return false;
    if (Scrollable.recommendDeferredLoadingForContext(context)) return false;
    return true;
  }

  void _syncAnimationState({bool resetStaticPhase = false}) {
    if (!mounted) return;
    if (_shouldAnimate(context)) {
      if (!_controller.isAnimating) {
        _controller.repeat();
      }
    } else {
      if (_controller.isAnimating) {
        _controller.stop();
      }
      if (resetStaticPhase) {
        _controller.value = 0.25;
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dec = widget.decoration;
    if (dec == null || widget.opacity <= 0.001) {
      return widget.child;
    }

    final shouldAnimate = _shouldAnimate(context);
    final outerSize = widget.avatarDiameter * 1.24;

    Widget overlay;
    if (dec.isMedia) {
      overlay = SizedBox(
        width: outerSize,
        height: outerSize,
        child: StickerMediaView(
          fileUrl: dec.mediaUrl,
          format: dec.mediaFormat,
          width: outerSize,
          height: outerSize,
          animate: shouldAnimate,
          fit: BoxFit.contain,
        ),
      );
    } else {
      final style =
          dec.proceduralStyle.isNotEmpty ? dec.proceduralStyle : dec.id;
      overlay = AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return CustomPaint(
            size: Size(outerSize, outerSize),
            painter: _ProceduralDecorationPainter(
              style: style,
              primary: dec.primaryColor,
              secondary: dec.secondaryColor,
              progress: _controller.value,
              opacity: widget.opacity.clamp(0.0, 1.0),
              avatarDiameter: widget.avatarDiameter,
            ),
          );
        },
      );
    }

    if (widget.opacity < 0.999) {
      overlay = Opacity(opacity: widget.opacity.clamp(0.0, 1.0), child: overlay);
    }

    return SizedBox(
      width: outerSize,
      height: outerSize,
      child: Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          widget.child,
          Positioned.fill(
            child: RepaintBoundary(
              child: IgnorePointer(
                child: Center(child: overlay),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProceduralDecorationPainter extends CustomPainter {
  final String style;
  final Color primary;
  final Color secondary;
  final double progress;
  final double opacity;
  final double avatarDiameter;

  const _ProceduralDecorationPainter({
    required this.style,
    required this.primary,
    required this.secondary,
    required this.progress,
    required this.opacity,
    required this.avatarDiameter,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0.001) return;
    final center = Offset(size.width / 2, size.height / 2);
    final avatarRadius = avatarDiameter / 2;
    final ringRadius = avatarRadius * 1.09;
    final strokeW = (avatarDiameter * 0.055).clamp(1.6, 5.2);
    final angle = progress * math.pi * 2;

    switch (style) {
      case 'aurora_halo':
        _paintAuroraHalo(canvas, center, ringRadius, strokeW, angle);
        break;
      case 'sakura_petals':
        _paintSakuraPetals(canvas, center, ringRadius, strokeW, angle);
        break;
      case 'cyber_grid':
        _paintCyberGrid(canvas, center, ringRadius, strokeW, angle);
        break;
      case 'golden_laurel':
        _paintGoldenLaurel(canvas, center, ringRadius, strokeW);
        break;
      case 'frost_crystal':
        _paintFrostCrystal(canvas, center, ringRadius, strokeW, angle);
        break;
      case 'prism_glass':
        _paintPrismGlass(canvas, center, ringRadius, strokeW, angle);
        break;
      case 'ember_flame':
        _paintEmberFlame(canvas, center, ringRadius, strokeW, angle);
        break;
      case 'starlight_orbit':
        _paintStarlightOrbit(canvas, center, ringRadius, strokeW, angle);
        break;
      case 'neon_pulse':
      default:
        _paintNeonPulse(canvas, center, ringRadius, strokeW, angle);
        break;
    }
  }

  void _paintSweepRing(
    Canvas canvas,
    Offset center,
    double radius,
    double strokeWidth,
    double rotation,
    List<Color> colors, {
    List<double>? stops,
    double blurSigma = 0.0,
  }) {
    final rect = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = SweepGradient(
        colors: colors,
        stops: stops,
        transform: GradientRotation(rotation),
      ).createShader(rect);
    if (blurSigma > 0) {
      paint.maskFilter = MaskFilter.blur(BlurStyle.normal, blurSigma);
    }
    canvas.drawCircle(center, radius, paint);
  }

  void _paintNeonPulse(
    Canvas canvas,
    Offset center,
    double ringRadius,
    double strokeW,
    double angle,
  ) {
    final pulse = 0.5 + 0.5 * math.sin(angle * 2);
    final colors = [
      primary.withValues(alpha: opacity),
      secondary.withValues(alpha: opacity),
      primary.withValues(alpha: opacity),
    ];
    _paintSweepRing(
      canvas,
      center,
      ringRadius + 0.8 * pulse,
      strokeW * (1.5 + 0.4 * pulse),
      angle,
      colors,
      blurSigma: strokeW * 1.1,
    );
    _paintSweepRing(canvas, center, ringRadius, strokeW, angle, colors);
  }

  void _paintAuroraHalo(
    Canvas canvas,
    Offset center,
    double ringRadius,
    double strokeW,
    double angle,
  ) {
    final c1 = primary.withValues(alpha: 0.9 * opacity);
    final c2 = secondary.withValues(alpha: 0.9 * opacity);
    final clear = primary.withValues(alpha: 0.08 * opacity);
    _paintSweepRing(
      canvas,
      center,
      ringRadius + strokeW * 0.35,
      strokeW * 1.6,
      angle,
      [c1, clear, c2, clear, c1],
      blurSigma: strokeW * 0.9,
    );
    _paintSweepRing(
      canvas,
      center,
      ringRadius - strokeW * 0.1,
      strokeW * 0.95,
      -angle * 0.7,
      [c2, c1.withValues(alpha: 0.4 * opacity), c2],
    );
  }

  void _paintSakuraPetals(
    Canvas canvas,
    Offset center,
    double ringRadius,
    double strokeW,
    double angle,
  ) {
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW * 0.7
      ..color = primary.withValues(alpha: 0.55 * opacity);
    canvas.drawCircle(center, ringRadius * 0.98, ringPaint);

    const petalCount = 7;
    final petalW = strokeW * 1.45;
    final petalH = strokeW * 0.92;
    for (int i = 0; i < petalCount; i++) {
      final theta = angle + (i * math.pi * 2 / petalCount);
      final wobble = math.sin(angle * 2 + i * 1.3) * (strokeW * 0.45);
      final pos = Offset(
        center.dx + (ringRadius + wobble) * math.cos(theta),
        center.dy + (ringRadius + wobble) * math.sin(theta),
      );
      canvas.save();
      canvas.translate(pos.dx, pos.dy);
      canvas.rotate(theta + math.pi / 4 + i * 0.5);
      final pPaint = Paint()
        ..shader = LinearGradient(
          colors: [
            secondary.withValues(alpha: 0.95 * opacity),
            primary.withValues(alpha: 0.9 * opacity),
          ],
        ).createShader(Rect.fromCenter(center: Offset.zero, width: petalW, height: petalH));
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: petalW, height: petalH),
        pPaint,
      );
      canvas.restore();
    }
  }

  void _paintCyberGrid(
    Canvas canvas,
    Offset center,
    double ringRadius,
    double strokeW,
    double angle,
  ) {
    final arcRect = Rect.fromCircle(center: center, radius: ringRadius);
    final primaryPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt
      ..strokeWidth = strokeW * 0.95
      ..color = primary.withValues(alpha: 0.92 * opacity);

    final minorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = strokeW * 0.55
      ..color = secondary.withValues(alpha: 0.75 * opacity);

    const segments = 6;
    const gap = 0.22;
    const sweep = (math.pi * 2 / segments) - gap;
    for (int i = 0; i < segments; i++) {
      final start = angle + i * (math.pi * 2 / segments);
      canvas.drawArc(arcRect, start, sweep, false, primaryPaint);
    }

    final innerRect = Rect.fromCircle(center: center, radius: ringRadius * 0.945);
    const minorSegments = 12;
    const minorSweep = (math.pi * 2 / minorSegments) * 0.42;
    for (int i = 0; i < minorSegments; i++) {
      final start = -angle * 0.5 + i * (math.pi * 2 / minorSegments);
      canvas.drawArc(innerRect, start, minorSweep, false, minorPaint);
    }
  }

  void _paintGoldenLaurel(
    Canvas canvas,
    Offset center,
    double ringRadius,
    double strokeW,
  ) {
    final basePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW * 0.55
      ..color = secondary.withValues(alpha: 0.65 * opacity);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: ringRadius * 0.98),
      0.22,
      math.pi * 2 - 0.44,
      false,
      basePaint,
    );

    final leafPaint = Paint()..style = PaintingStyle.fill;
    const leavesPerSide = 8;
    for (int side in [-1, 1]) {
      for (int i = 0; i < leavesPerSide; i++) {
        final t = i / (leavesPerSide - 1);
        final theta = (math.pi / 2) + side * (0.28 + t * 2.15);
        final pos = Offset(
          center.dx + ringRadius * math.cos(theta),
          center.dy + ringRadius * math.sin(theta),
        );
        canvas.save();
        canvas.translate(pos.dx, pos.dy);
        canvas.rotate(theta + side * 0.55);
        leafPaint.color = Color.lerp(primary, secondary, t)!
            .withValues(alpha: 0.95 * opacity);
        canvas.drawOval(
          Rect.fromCenter(
            center: Offset.zero,
            width: strokeW * 1.45,
            height: strokeW * 0.75,
          ),
          leafPaint,
        );
        canvas.restore();
      }
    }
  }

  void _paintFrostCrystal(
    Canvas canvas,
    Offset center,
    double ringRadius,
    double strokeW,
    double angle,
  ) {
    _paintSweepRing(
      canvas,
      center,
      ringRadius,
      strokeW * 0.85,
      angle * 0.5,
      [
        primary.withValues(alpha: 0.85 * opacity),
        secondary.withValues(alpha: 0.95 * opacity),
        primary.withValues(alpha: 0.85 * opacity),
      ],
    );

    final crystalPaint = Paint()
      ..color = secondary.withValues(alpha: 0.95 * opacity)
      ..strokeWidth = (strokeW * 0.42).clamp(1.0, 2.0)
      ..strokeCap = StrokeCap.round;

    const count = 6;
    for (int i = 0; i < count; i++) {
      final theta = angle * 0.65 + i * (math.pi * 2 / count);
      final r = ringRadius + strokeW * 0.65;
      final pt = Offset(center.dx + r * math.cos(theta), center.dy + r * math.sin(theta));
      final arm = strokeW * 0.95;
      for (int a = 0; a < 3; a++) {
        final aTheta = theta + a * (math.pi / 3);
        final d = Offset(math.cos(aTheta) * arm, math.sin(aTheta) * arm);
        canvas.drawLine(pt - d, pt + d, crystalPaint);
      }
    }
  }

  void _paintPrismGlass(
    Canvas canvas,
    Offset center,
    double ringRadius,
    double strokeW,
    double angle,
  ) {
    final rainbow = [
      primary.withValues(alpha: 0.92 * opacity),
      const Color(0xFFFFD740).withValues(alpha: 0.92 * opacity),
      const Color(0xFF00E676).withValues(alpha: 0.92 * opacity),
      secondary.withValues(alpha: 0.92 * opacity),
      primary.withValues(alpha: 0.92 * opacity),
    ];
    _paintSweepRing(canvas, center, ringRadius, strokeW * 1.15, angle, rainbow);
    _paintSweepRing(
      canvas,
      center,
      ringRadius,
      strokeW * 0.45,
      -angle,
      [
        Colors.white.withValues(alpha: 0.85 * opacity),
        Colors.white.withValues(alpha: 0.0),
        Colors.white.withValues(alpha: 0.55 * opacity),
        Colors.white.withValues(alpha: 0.0),
        Colors.white.withValues(alpha: 0.85 * opacity),
      ],
    );
  }

  void _paintEmberFlame(
    Canvas canvas,
    Offset center,
    double ringRadius,
    double strokeW,
    double angle,
  ) {
    _paintSweepRing(
      canvas,
      center,
      ringRadius,
      strokeW * 1.15,
      angle * 1.2,
      [
        primary.withValues(alpha: 0.95 * opacity),
        secondary.withValues(alpha: 0.95 * opacity),
        primary.withValues(alpha: 0.5 * opacity),
        primary.withValues(alpha: 0.95 * opacity),
      ],
      blurSigma: strokeW * 0.45,
    );

    final sparkPaint = Paint()..style = PaintingStyle.fill;
    const sparkCount = 8;
    for (int i = 0; i < sparkCount; i++) {
      final theta = angle * 1.4 + i * (math.pi * 2 / sparkCount);
      final lift = 0.5 + 0.5 * math.sin(angle * 3 + i * 1.7);
      final r = ringRadius + strokeW * (0.4 + 0.9 * lift);
      final pos = Offset(center.dx + r * math.cos(theta), center.dy + r * math.sin(theta));
      sparkPaint.color = Color.lerp(primary, secondary, lift)!
          .withValues(alpha: (0.45 + 0.55 * lift) * opacity);
      canvas.drawCircle(pos, strokeW * (0.35 + 0.35 * lift), sparkPaint);
    }
  }

  void _paintStarlightOrbit(
    Canvas canvas,
    Offset center,
    double ringRadius,
    double strokeW,
    double angle,
  ) {
    final orbitPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeW * 0.65
      ..color = primary.withValues(alpha: 0.65 * opacity);

    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(-0.35);
    canvas.drawOval(
      Rect.fromCenter(
        center: Offset.zero,
        width: ringRadius * 2.14,
        height: ringRadius * 1.78,
      ),
      orbitPaint,
    );
    canvas.restore();

    canvas.drawCircle(
      center,
      ringRadius * 0.98,
      orbitPaint..color = secondary.withValues(alpha: 0.45 * opacity),
    );

    final starPaint = Paint()..style = PaintingStyle.fill;
    for (int i = 0; i < 4; i++) {
      final theta = angle + i * (math.pi / 2);
      final pos = Offset(
        center.dx + ringRadius * math.cos(theta),
        center.dy + ringRadius * math.sin(theta),
      );
      final twinkle = 0.6 + 0.4 * math.sin(angle * 3 + i);
      starPaint.color = (i.isEven ? secondary : Colors.white)
          .withValues(alpha: twinkle * opacity);
      canvas.drawCircle(pos, strokeW * 0.52 * twinkle, starPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _ProceduralDecorationPainter oldDelegate) {
    return oldDelegate.style != style ||
        oldDelegate.primary != primary ||
        oldDelegate.secondary != secondary ||
        oldDelegate.progress != progress ||
        oldDelegate.opacity != opacity ||
        oldDelegate.avatarDiameter != avatarDiameter;
  }
}
