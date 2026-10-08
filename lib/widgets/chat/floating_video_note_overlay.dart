import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../services/media_playback_coordinator.dart';
import '../../services/video_note_playback_service.dart';

/// Draggable, Telegram-style floating circular video note overlay (PiP).
/// Displays in the corner when the actively playing video note scrolls out of view.
class FloatingVideoNoteOverlay extends StatefulWidget {
  const FloatingVideoNoteOverlay({Key? key}) : super(key: key);

  @override
  State<FloatingVideoNoteOverlay> createState() => _FloatingVideoNoteOverlayState();
}

class _FloatingVideoNoteOverlayState extends State<FloatingVideoNoteOverlay>
    with SingleTickerProviderStateMixin {
  final VideoNotePlaybackService _service = VideoNotePlaybackService();
  static const double _kSize = 114.0;
  static const double _kEdgeMargin = 12.0;

  VideoPlayerController? _observedController;
  Offset? _position;
  late AnimationController _snapController;
  Animation<Offset>? _snapAnimation;
  double _prevProgress = 0.0;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onServiceUpdate);
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
    )..addListener(() {
        if (_snapAnimation != null) {
          setState(() {
            _position = _snapAnimation!.value;
          });
        }
      });
    _attachControllerListener();
  }

  @override
  void dispose() {
    _snapController.dispose();
    _detachControllerListener();
    _service.removeListener(_onServiceUpdate);
    super.dispose();
  }

  void _attachControllerListener() {
    final ctrl = _service.activeController;
    if (_observedController != ctrl) {
      _detachControllerListener();
      _observedController = ctrl;
      _observedController?.addListener(_onVideoTick);
    }
  }

  void _detachControllerListener() {
    _observedController?.removeListener(_onVideoTick);
    _observedController = null;
  }

  void _onVideoTick() {
    if (!mounted) return;
    final ctrl = _observedController;
    if (ctrl != null && ctrl.value.isInitialized) {
      // Completion is handled by VideoNotePlaybackService centrally.
      if (_service.isFloating) {
        setState(() {});
      }
    }
  }

  void _onServiceUpdate() {
    _attachControllerListener();
    if (!_service.isFloating) {
      _position = null;
    }
    if (mounted) setState(() {});
  }

  Offset _getDefaultPosition(Size screenSize, double topPadding) {
    final saved = _service.floatingPosition;
    if (saved != null) {
      return saved;
    }
    return Offset(screenSize.width - _kSize - _kEdgeMargin, topPadding + 60);
  }

  double _calculateOpacity(double x, double screenWidth) {
    if (x < 0) {
      final offScreen = -x;
      return (1.0 - (offScreen / (_kSize * 1.1))).clamp(0.0, 1.0);
    }
    final rightThreshold = screenWidth - _kSize;
    if (x > rightThreshold) {
      final offScreen = x - rightThreshold;
      return (1.0 - (offScreen / (_kSize * 1.1))).clamp(0.0, 1.0);
    }
    return 1.0;
  }

  void _onPanStart(DragStartDetails details) {
    if (_isDismissing) return;
    if (_snapController.isAnimating) {
      _snapController.stop();
    }
  }

  void _onPanUpdate(DragUpdateDetails details, Size screenSize, double topPadding, double bottomPadding) {
    if (_isDismissing) return;
    final minTop = topPadding;
    final maxTop = math.max(minTop, screenSize.height - _kSize - bottomPadding);
    const minLeft = -_kSize - 20.0;
    final maxLeft = screenSize.width + 20.0;

    final current = _position ?? _getDefaultPosition(screenSize, topPadding);
    final newX = (current.dx + details.delta.dx).clamp(minLeft, maxLeft);
    final newY = (current.dy + details.delta.dy).clamp(minTop, maxTop);

    setState(() {
      _position = Offset(newX, newY);
    });
  }

  void _onPanEnd(DragEndDetails details, Size screenSize, double topPadding, double bottomPadding) {
    if (_isDismissing) return;
    final current = _position ?? _getDefaultPosition(screenSize, topPadding);
    final minTop = topPadding;
    final maxTop = math.max(minTop, screenSize.height - _kSize - bottomPadding);
    final targetY = current.dy.clamp(minTop, maxTop);

    final velocityX = details.velocity.pixelsPerSecond.dx;
    final centerX = current.dx + _kSize / 2;
    final screenCenterX = screenSize.width / 2;

    // Detect swipe / fling off-screen to the left or right to dismiss playback
    final bool isDismissLeft = current.dx < -30.0 || (velocityX < -500 && current.dx < 80.0);
    final bool isDismissRight = current.dx > (screenSize.width - _kSize + 30.0) ||
        (velocityX > 500 && current.dx > (screenSize.width - _kSize - 80.0));

    if (isDismissLeft || isDismissRight) {
      _isDismissing = true;
      final targetX = isDismissLeft ? -_kSize - 50.0 : screenSize.width + 50.0;
      final targetOffset = Offset(targetX, targetY);

      _snapAnimation = Tween<Offset>(begin: current, end: targetOffset).animate(
        CurvedAnimation(parent: _snapController, curve: Curves.easeInCubic),
      );
      _snapController.duration = const Duration(milliseconds: 180);
      _snapController.forward(from: 0.0).then((_) {
        _isDismissing = false;
        _position = null;
        _snapController.duration = const Duration(milliseconds: 260);
        MediaPlaybackCoordinator.instance.stopAll();
      });
      return;
    }

    // Magnetic snap to nearest edge (left or right), factoring in swipe velocity
    final double targetX;
    if (velocityX < -350) {
      targetX = _kEdgeMargin;
    } else if (velocityX > 350) {
      targetX = screenSize.width - _kSize - _kEdgeMargin;
    } else if (centerX < screenCenterX) {
      targetX = _kEdgeMargin;
    } else {
      targetX = screenSize.width - _kSize - _kEdgeMargin;
    }

    final targetOffset = Offset(targetX, targetY);

    _snapController.duration = const Duration(milliseconds: 260);
    _snapAnimation = Tween<Offset>(begin: current, end: targetOffset).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeOutCubic),
    );
    _snapController.forward(from: 0.0).then((_) {
      if (mounted) {
        _service.updateFloatingPosition(targetOffset);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    if (!_service.isFloating || _service.activeController == null) {
      return const SizedBox.shrink();
    }

    final controller = _service.activeController!;
    if (!controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    final mediaQuery = MediaQuery.of(context);
    final screenSize = mediaQuery.size;
    final topPadding = mediaQuery.padding.top + 40.0;
    final bottomPadding = mediaQuery.padding.bottom + 80.0;

    _position ??= _getDefaultPosition(screenSize, topPadding);
    final currentPos = _position!;

    final duration = controller.value.duration;
    final position = controller.value.position;
    final double targetProgress = (duration.inMilliseconds > 0)
        ? (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;

    final animatedBeginProgress = (targetProgress < _prevProgress) ? 0.0 : _prevProgress;
    _prevProgress = targetProgress;

    return Stack(
      fit: StackFit.loose,
      children: [
        Positioned(
          left: currentPos.dx,
          top: currentPos.dy,
          child: Opacity(
            opacity: _calculateOpacity(currentPos.dx, screenSize.width),
            child: GestureDetector(
              onPanStart: _onPanStart,
              onPanUpdate: (d) => _onPanUpdate(d, screenSize, topPadding, bottomPadding),
              onPanEnd: (d) => _onPanEnd(d, screenSize, topPadding, bottomPadding),
              onTap: () {
                if (_isDismissing) return;
                MediaPlaybackCoordinator.instance.togglePlayPause();
              },
            child: Material(
              type: MaterialType.transparency,
              child: Container(
                width: _kSize,
                height: _kSize,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.35),
                      blurRadius: 14,
                      spreadRadius: 2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 1. Circular Video Player
                    ClipOval(
                      child: SizedBox(
                        width: _kSize,
                        height: _kSize,
                        child: FittedBox(
                          fit: BoxFit.cover,
                          child: SizedBox(
                            width: controller.value.size.width > 0
                                ? controller.value.size.width
                                : _kSize,
                            height: controller.value.size.height > 0
                                ? controller.value.size.height
                                : _kSize,
                            child: VideoPlayer(controller),
                          ),
                        ),
                      ),
                    ),

                    // 1.1 Play indicator overlay when paused
                    if (!controller.value.isPlaying)
                      IgnorePointer(
                        child: Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.55),
                            shape: BoxShape.circle,
                          ),
                          child: const Center(
                            child: Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                          ),
                        ),
                      ),

                    // 2. Smooth Circular Progress Ring
                    Positioned.fill(
                      child: IgnorePointer(
                        child: TweenAnimationBuilder<double>(
                          tween: Tween<double>(
                              end: !controller.value.isPlaying ? 4.5 : 0.0),
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          builder: (context, animatedInset, _) {
                            return TweenAnimationBuilder<double>(
                              tween: Tween<double>(
                                  begin: animatedBeginProgress,
                                  end: targetProgress),
                              duration: const Duration(milliseconds: 250),
                              curve: Curves.linear,
                              builder: (context, smoothProgress, _) {
                                return CustomPaint(
                                  painter: _FloatingProgressPainter(
                                    progress: smoothProgress,
                                    color: Colors.white,
                                    strokeWidth: 2.5,
                                    inset: animatedInset,
                                  ),
                                );
                              },
                            );
                          },
                        ),
                      ),
                    ),

                    // 3. Subtle Outer Glass Border
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                              width: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // 4. Close Button in Top Corner
                    Positioned(
                      top: 2,
                      right: 2,
                      child: GestureDetector(
                        onTap: () {
                          MediaPlaybackCoordinator.instance.stopAll();
                        },
                        child: Container(
                          width: 26,
                          height: 26,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.65),
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.3),
                              width: 1.0,
                            ),
                          ),
                          child: const Center(
                            child: Icon(
                              Icons.close,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ],
  );
  }
}

class _FloatingProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;
  final double inset;

  const _FloatingProgressPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
    this.inset = 0.0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.max(0.0, (size.width - strokeWidth) / 2 - inset);

    // Subtle background track ring
    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.22)
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke;
    canvas.drawCircle(center, radius, trackPaint);

    if (progress <= 0.0) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    const startAngle = -3.141592653589793 / 2; // 12 o'clock
    final sweepAngle = 2 * 3.141592653589793 * progress.clamp(0.0, 1.0);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _FloatingProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth ||
        oldDelegate.inset != inset;
  }
}
