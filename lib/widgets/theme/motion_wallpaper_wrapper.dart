import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sensors_plus/sensors_plus.dart';

/// Wraps wallpaper background with smooth gyroscope-driven parallax motion on mobile devices.
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
        setState(() {
          _targetX = 0.0;
          _targetY = 0.0;
          _currentX = 0.0;
          _currentY = 0.0;
        });
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

    if ((newX - _currentX).abs() > 0.01 || (newY - _currentY).abs() > 0.01) {
      setState(() {
        _currentX = newX;
        _currentY = newY;
      });
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isMobile || !widget.enabled) {
      return widget.child;
    }

    return ClipRect(
      child: Transform.scale(
        scale: 1.15,
        child: Transform.translate(
          offset: Offset(_currentX, _currentY),
          child: widget.child,
        ),
      ),
    );
  }
}
