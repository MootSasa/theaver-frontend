import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Wraps wallpaper background with smooth gyroscope-driven parallax motion on mobile devices.
///
/// Uses [ValueNotifier] and [RepaintBoundary] to avoid widget tree rebuilds and expensive
/// wallpaper/SVG re-rasterization on every frame, eliminating FPS drops and lag.
class MotionWallpaperWrapper extends StatefulWidget {
  final Widget child;
  final bool enabled;
  final double maxOffset;

  const MotionWallpaperWrapper({
    Key? key,
    required this.child,
    this.enabled = true,
    this.maxOffset = 22.0,
  }) : super(key: key);

  @override
  State<MotionWallpaperWrapper> createState() => _MotionWallpaperWrapperState();
}

class _MotionWallpaperWrapperState extends State<MotionWallpaperWrapper>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  StreamSubscription<GyroscopeEvent>? _gyroSub;
  double _targetX = 0.0;
  double _targetY = 0.0;
  double _currentX = 0.0;
  double _currentY = 0.0;
  late AnimationController _animController;
  final ValueNotifier<Offset> _offsetNotifier = ValueNotifier<Offset>(Offset.zero);
  bool _isMobile = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_tick);

    if (widget.enabled && _isMobile) {
      _startListening();
      _animController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant MotionWallpaperWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled) {
      if (widget.enabled && _isMobile) {
        _startListening();
        if (!_animController.isAnimating) _animController.repeat();
      } else {
        _stopListening();
        _animController.stop();
        _targetX = 0.0;
        _targetY = 0.0;
        _currentX = 0.0;
        _currentY = 0.0;
        _offsetNotifier.value = Offset.zero;
      }
    }
  }

  void _startListening() {
    if (_gyroSub != null) return;
    try {
      _gyroSub = gyroscopeEventStream(samplingPeriod: SensorInterval.uiInterval).listen(
        (GyroscopeEvent event) {
          // Gyroscope gives rad/s
          // event.y controls horizontal tilt, event.x controls vertical tilt
          final double dx = event.y * 3.5;
          final double dy = event.x * 3.5;

          _targetX = (_targetX + dx).clamp(-widget.maxOffset, widget.maxOffset);
          _targetY = (_targetY + dy).clamp(-widget.maxOffset, widget.maxOffset);

          // Resume ticker if stopped due to idle
          if (!_animController.isAnimating && mounted) {
            _animController.repeat();
          }
        },
        onError: (_) {},
        cancelOnError: false,
      );
    } catch (_) {}
  }

  void _stopListening() {
    _gyroSub?.cancel();
    _gyroSub = null;
  }

  void _tick() {
    if (!mounted) return;
    // Spring decay towards center
    _targetX *= 0.985;
    _targetY *= 0.985;

    // Smooth exponential damping
    final newX = _currentX + (_targetX - _currentX) * 0.12;
    final newY = _currentY + (_targetY - _currentY) * 0.12;

    final diffX = (newX - _currentX).abs();
    final diffY = (newY - _currentY).abs();

    _currentX = newX;
    _currentY = newY;
    _offsetNotifier.value = Offset(newX, newY);

    // If movement has settled below visual perception and target is near center,
    // pause the animation loop to conserve CPU/GPU cycles.
    if (diffX < 0.005 && diffY < 0.005 && _targetX.abs() < 0.01 && _targetY.abs() < 0.01) {
      if (_animController.isAnimating) {
        _animController.stop();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && widget.enabled && _isMobile) {
      _startListening();
      if (!_animController.isAnimating) _animController.repeat();
    } else if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _stopListening();
      _animController.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _stopListening();
    _animController.dispose();
    _offsetNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isMobile || !widget.enabled) {
      return widget.child;
    }

    return ClipRect(
      child: ValueListenableBuilder<Offset>(
        valueListenable: _offsetNotifier,
        child: RepaintBoundary(child: widget.child),
        builder: (context, offset, staticChild) {
          return Transform.scale(
            scale: 1.15,
            child: Transform.translate(
              offset: offset,
              child: staticChild,
            ),
          );
        },
      ),
    );
  }
}
