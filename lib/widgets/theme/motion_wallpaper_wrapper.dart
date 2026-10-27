import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../services/tiling_layout_controller.dart';

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

  bool get _shouldAnimate =>
      widget.enabled &&
      _isMobile &&
      !(TilingLayoutController.instance.isWorkspaceMounted && !TilingLayoutController.instance.isSinglePane);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _isMobile = !kIsWeb && (Platform.isAndroid || Platform.isIOS);

    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 16),
    )..addListener(_tick);

    if (_shouldAnimate) {
      _startListening();
    }
  }

  @override
  void didUpdateWidget(covariant MotionWallpaperWrapper oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.enabled != oldWidget.enabled) {
      if (_shouldAnimate) {
        _startListening();
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
    if (_gyroSub != null || !_shouldAnimate) return;
    try {
      _gyroSub = gyroscopeEventStream(samplingPeriod: SensorInterval.uiInterval).listen(
        (GyroscopeEvent event) {
          if (!_shouldAnimate) {
            _stopListening();
            return;
          }
          // Ignore resting sensor micro-noise and hand touch micro-vibration (~0.10 rad/s deadzone)
          if (event.x.abs() < 0.10 && event.y.abs() < 0.10) {
            return;
          }
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

    final prevOffset = _offsetNotifier.value;
    if ((newX - prevOffset.dx).abs() >= 0.25 ||
        (newY - prevOffset.dy).abs() >= 0.25) {
      _offsetNotifier.value = Offset(newX, newY);
    }

    // If movement has settled below visual perception and target is near center,
    // pause the animation loop to conserve CPU/GPU cycles.
    if (diffX < 0.05 && diffY < 0.05 && _targetX.abs() < 0.2 && _targetY.abs() < 0.2) {
      _targetX = 0.0;
      _targetY = 0.0;
      _currentX = 0.0;
      _currentY = 0.0;
      if (_offsetNotifier.value != Offset.zero) {
        _offsetNotifier.value = Offset.zero;
      }
      if (_animController.isAnimating) {
        _animController.stop();
      }
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _shouldAnimate) {
      _startListening();
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
    if (!_shouldAnimate) {
      return RepaintBoundary(child: widget.child);
    }

    return ClipRect(
      child: ValueListenableBuilder<Offset>(
        valueListenable: _offsetNotifier,
        child: RepaintBoundary(child: widget.child),
        builder: (context, offset, staticChild) {
          if (offset == Offset.zero) {
            return staticChild!;
          }
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
