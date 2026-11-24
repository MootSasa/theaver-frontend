import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../utils/haptic_utils.dart';
import '../../utils/swipe_back_route.dart';

/// Horizontal precision rotation wheel (`-45°` .. `+45°`) with degree tick marks,
/// soft snap to `0°`, and whole-degree tactile haptics.
class AvatarRotationDial extends StatefulWidget {
  final double angleDegrees;
  final ValueChanged<double> onChanged;
  final VoidCallback? onInteractionStart;
  final VoidCallback? onInteractionEnd;
  final Color? accentColor;

  const AvatarRotationDial({
    super.key,
    required this.angleDegrees,
    required this.onChanged,
    this.onInteractionStart,
    this.onInteractionEnd,
    this.accentColor,
  });

  @override
  State<AvatarRotationDial> createState() => _AvatarRotationDialState();
}

class _AvatarRotationDialState extends State<AvatarRotationDial> {
  static const double _minAngle = -45.0;
  static const double _maxAngle = 45.0;
  static const double _snapThreshold = 1.15;
  static const double _degPerPixel = 0.26;

  double _rawAngle = 0.0;
  int _lastWholeDegree = 0;
  bool _wasZero = true;

  @override
  void initState() {
    super.initState();
    _syncFromWidget();
  }

  @override
  void didUpdateWidget(covariant AvatarRotationDial oldWidget) {
    super.didUpdateWidget(oldWidget);
    if ((oldWidget.angleDegrees - widget.angleDegrees).abs() > 1e-3) {
      _lastWholeDegree = widget.angleDegrees.round();
      _wasZero = widget.angleDegrees.abs() <= 0.05;
    }
  }

  void _syncFromWidget() {
    _rawAngle = widget.angleDegrees.clamp(_minAngle, _maxAngle);
    _lastWholeDegree = _rawAngle.round();
    _wasZero = _rawAngle.abs() <= 0.05;
  }

  void _handleDragStart(DragStartDetails details) {
    _syncFromWidget();
    widget.onInteractionStart?.call();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    _rawAngle = (_rawAngle - details.delta.dx * _degPerPixel)
        .clamp(_minAngle, _maxAngle)
        .toDouble();
    final double effective = _rawAngle.abs() < _snapThreshold ? 0.0 : _rawAngle;
    final int whole = effective.round();
    final bool isZeroNow = effective == 0.0;

    if (whole != _lastWholeDegree || (isZeroNow && !_wasZero)) {
      HapticUtils.selection();
    }
    _lastWholeDegree = whole;
    _wasZero = isZeroNow;
    widget.onChanged(effective);
  }

  void _handleDragEnd([DragEndDetails? _]) {
    widget.onInteractionEnd?.call();
  }

  void _resetToZero() {
    if (widget.angleDegrees.abs() <= 0.01) return;
    HapticUtils.selection();
    widget.onInteractionStart?.call();
    widget.onChanged(0.0);
    widget.onInteractionEnd?.call();
  }

  String _formatAngle(double deg) {
    final int rounded = deg.round();
    if (rounded == 0) return '0°';
    return rounded > 0 ? '+$rounded°' : '$rounded°';
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = accentColorOrDefault(context);
    final bool isNonZero = widget.angleDegrees.abs() > 0.05;

    return SwipeBackBlocker(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _resetToZero,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: isNonZero
                    ? accent.withValues(alpha: 0.20)
                    : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: isNonZero
                      ? accent.withValues(alpha: 0.55)
                      : Colors.white.withValues(alpha: 0.14),
                  width: 0.6,
                ),
              ),
              child: Text(
                _formatAngle(widget.angleDegrees),
                style: TextStyle(
                  color: isNonZero ? accent : Colors.white.withValues(alpha: 0.78),
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _handleDragStart,
            onHorizontalDragUpdate: _handleDragUpdate,
            onHorizontalDragEnd: _handleDragEnd,
            onHorizontalDragCancel: _handleDragEnd,
            onDoubleTap: _resetToZero,
            child: SizedBox(
              height: 36,
              width: double.infinity,
              child: ShaderMask(
                shaderCallback: (Rect bounds) {
                  return const LinearGradient(
                    colors: <Color>[
                      Colors.transparent,
                      Colors.white,
                      Colors.white,
                      Colors.transparent,
                    ],
                    stops: <double>[0.0, 0.14, 0.86, 1.0],
                  ).createShader(bounds);
                },
                blendMode: BlendMode.dstIn,
                child: CustomPaint(
                  painter: _RotationDialPainter(
                    angleDegrees: widget.angleDegrees,
                    accentColor: accent,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Color accentColorOrDefault(BuildContext context) {
    return widget.accentColor ?? const Color(0xFF38BDF8);
  }
}

class _RotationDialPainter extends CustomPainter {
  final double angleDegrees;
  final Color accentColor;

  _RotationDialPainter({
    required this.angleDegrees,
    required this.accentColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double centerX = size.width * 0.5;
    final double bottomY = size.height - 4.0;
    const double pxPerDegree = 6.5;

    final Paint minorPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.32)
      ..strokeWidth = 1.0
      ..strokeCap = StrokeCap.round;

    final Paint majorPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.82)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    final Paint zeroDotPaint = Paint()
      ..color = accentColor
      ..isAntiAlias = true;

    for (int deg = -45; deg <= 45; deg++) {
      final double dx = centerX + (deg - angleDegrees) * pxPerDegree;
      if (dx < -4.0 || dx > size.width + 4.0) continue;

      final bool isZero = deg == 0;
      final bool isMajor15 = deg % 15 == 0;
      final bool isMid5 = deg % 5 == 0;
      final double tickH = isZero
          ? 16.0
          : (isMajor15 ? 14.0 : (isMid5 ? 10.0 : 6.0));

      final double distNorm =
          ((dx - centerX).abs() / math.max(1.0, centerX)).clamp(0.0, 1.0);
      final double fade = (1.0 - distNorm * 0.6).clamp(0.25, 1.0);

      final Paint paint = (isMid5 ? majorPaint : minorPaint);
      final Color origColor = paint.color;
      paint.color = origColor.withValues(alpha: origColor.a * fade);

      canvas.drawLine(
        Offset(dx, bottomY),
        Offset(dx, bottomY - tickH),
        paint,
      );
      paint.color = origColor;

      if (isZero) {
        canvas.drawCircle(Offset(dx, bottomY - tickH - 4.5), 2.2, zeroDotPaint);
      }
    }

    // Fixed center reference needle.
    final Paint needlePaint = Paint()
      ..color = angleDegrees.abs() > 0.05 ? accentColor : Colors.white
      ..strokeWidth = 2.2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(
      Offset(centerX, bottomY + 1.0),
      Offset(centerX, bottomY - 21.0),
      needlePaint,
    );
  }

  @override
  bool shouldRepaint(covariant _RotationDialPainter oldDelegate) {
    return oldDelegate.angleDegrees != angleDegrees ||
        oldDelegate.accentColor != accentColor;
  }
}
