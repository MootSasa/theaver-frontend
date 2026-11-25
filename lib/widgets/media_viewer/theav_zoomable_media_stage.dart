import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../utils/haptic_utils.dart';

/// 120 FPS zoomable, pannable, double-tap-interactive, and 2D-dismissible
/// media stage used by [TheavMediaViewer] for photos, videos, GIFs, and avatars.
///
/// Key invariants:
/// - Drives 2D drag-to-dismiss exclusively via [ValueNotifier] + [Transform] so
///   vertical dragging triggers **zero** `setState` rebuilds across [PageView].
/// - Leaves horizontal gestures unobstructed at `1.0x` scale so [PageView]
///   page turns are 1:1 instantaneous.
/// - Supports pinch-to-zoom (`1.0x–4.0x` with rubber-band overscale),
///   focal double-tap zoom (`1.0x <-> 2.5x`), desktop mouse-wheel cursor zoom,
///   and optional left/right third double-tap `±10s` seek on videos.
class TheavZoomableMediaStage extends StatefulWidget {
  final Widget child;
  final bool enableZoom;
  final bool enableDoubleTapSeek;
  final ValueChanged<int>? onDoubleTapSeek;
  final VoidCallback? onSingleTap;
  final ValueChanged<bool>? onZoomStateChanged;
  final VoidCallback? onDismissStart;
  final void Function(Offset offset, double progress)? onDismissUpdate;
  final ValueChanged<bool>? onDismissEnd;

  const TheavZoomableMediaStage({
    super.key,
    required this.child,
    this.enableZoom = true,
    this.enableDoubleTapSeek = false,
    this.onDoubleTapSeek,
    this.onSingleTap,
    this.onZoomStateChanged,
    this.onDismissStart,
    this.onDismissUpdate,
    this.onDismissEnd,
  });

  @override
  State<TheavZoomableMediaStage> createState() =>
      _TheavZoomableMediaStageState();
}

class _TheavZoomableMediaStageState extends State<TheavZoomableMediaStage>
    with TickerProviderStateMixin {
  static const double _kMinScale = 1.0;
  static const double _kMaxScale = 4.0;
  static const double _kDoubleTapScale = 2.5;
  static const double _kDismissDistanceThreshold = 92.0;
  static const double _kDismissVelocityThreshold = 620.0;

  late final TransformationController _transformController =
      TransformationController();
  late final AnimationController _matrixAnimController;
  late final AnimationController _dismissSpringController;

  Animation<Matrix4>? _matrixAnim;
  Animation<Offset>? _dismissOffsetAnim;

  final ValueNotifier<Offset> _dismissOffsetNotifier =
      ValueNotifier<Offset>(Offset.zero);

  // Active pointer tracking for 2-finger pinch starting cleanly at 1.0x.
  final Map<int, Offset> _activePointers = <int, Offset>{};
  bool _isPinching = false;
  double _pinchStartScale = 1.0;
  double _pinchStartDistance = 1.0;
  Offset _pinchStartFocalLocal = Offset.zero;
  Matrix4 _pinchStartMatrix = Matrix4.identity();

  // Panning when zoomed > 1.02x.
  bool _isZoomed = false;
  Offset _lastPanFocal = Offset.zero;

  // 2D drag-to-dismiss state at 1.0x.
  bool _isDismissDragging = false;

  // Double-tap focus & video seek ripple state.
  Offset? _lastTapLocalPos;
  int? _seekFeedbackSeconds;
  Timer? _seekFeedbackTimer;

  Size _stageSize = Size.zero;

  @override
  void initState() {
    super.initState();
    _matrixAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(_onMatrixAnimTick);
    _dismissSpringController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 210),
    )..addListener(_onDismissSpringTick);
    _transformController.addListener(_onTransformChanged);
  }

  @override
  void dispose() {
    _seekFeedbackTimer?.cancel();
    _transformController.removeListener(_onTransformChanged);
    _transformController.dispose();
    _matrixAnimController.dispose();
    _dismissSpringController.dispose();
    _dismissOffsetNotifier.dispose();
    super.dispose();
  }

  double get _currentScale => _transformController.value.getMaxScaleOnAxis();

  void _onTransformChanged() {
    final bool zoomedNow = _currentScale > 1.02;
    if (zoomedNow != _isZoomed) {
      _isZoomed = zoomedNow;
      widget.onZoomStateChanged?.call(zoomedNow);
      if (mounted) setState(() {});
    }
  }

  void _onMatrixAnimTick() {
    if (_matrixAnim != null) {
      _transformController.value = _matrixAnim!.value;
    }
  }

  void _onDismissSpringTick() {
    if (_dismissOffsetAnim != null) {
      final offset = _dismissOffsetAnim!.value;
      _dismissOffsetNotifier.value = offset;
      widget.onDismissUpdate?.call(offset, _progressForOffset(offset));
    }
  }

  double _progressForOffset(Offset offset) =>
      (offset.dy.abs() / 280.0).clamp(0.0, 1.0);

  void _animateMatrixTo(Matrix4 target) {
    _matrixAnimController.stop();
    _matrixAnim = Matrix4Tween(
      begin: _transformController.value.clone(),
      end: target,
    ).animate(
      CurvedAnimation(
        parent: _matrixAnimController,
        curve: Curves.easeOutCubic,
      ),
    );
    _matrixAnimController.forward(from: 0.0);
  }

  Matrix4 _clampMatrix(Matrix4 matrix) {
    final double scale = matrix.getMaxScaleOnAxis().clamp(_kMinScale, _kMaxScale);
    if ((scale - 1.0).abs() < 0.01) {
      return Matrix4.identity();
    }
    final double w = _stageSize.width;
    final double h = _stageSize.height;
    if (w <= 0 || h <= 0) return matrix;

    final col3 = matrix.getColumn(3);
    final double minTx = w * (1.0 - scale);
    final double minTy = h * (1.0 - scale);
    final double tx = col3.x.clamp(math.min(minTx, 0.0), 0.0);
    final double ty = col3.y.clamp(math.min(minTy, 0.0), 0.0);

    return Matrix4.identity()
      ..translateByDouble(tx, ty, 0.0, 1.0)
      ..scaleByDouble(scale, scale, 1.0, 1.0);
  }

  Matrix4 _zoomMatrixAroundPoint({
    required Matrix4 baseMatrix,
    required double targetScale,
    required Offset focalLocal,
  }) {
    final double currentScale = baseMatrix.getMaxScaleOnAxis();
    if (currentScale <= 0.001) return Matrix4.identity();
    final col3 = baseMatrix.getColumn(3);
    final double contentX = (focalLocal.dx - col3.x) / currentScale;
    final double contentY = (focalLocal.dy - col3.y) / currentScale;
    final double nextTx = focalLocal.dx - contentX * targetScale;
    final double nextTy = focalLocal.dy - contentY * targetScale;

    final candidate = Matrix4.identity()
      ..translateByDouble(nextTx, nextTy, 0.0, 1.0)
      ..scaleByDouble(targetScale, targetScale, 1.0, 1.0);
    return _clampMatrix(candidate);
  }

  void _handleDoubleTap() {
    if (!widget.enableZoom) return;
    final Size size = _stageSize;
    final Offset focal = _lastTapLocalPos ??
        Offset(size.width * 0.5, size.height * 0.5);

    if (widget.enableDoubleTapSeek &&
        !_isZoomed &&
        size.width > 0 &&
        widget.onDoubleTapSeek != null) {
      final double relX = focal.dx / size.width;
      if (relX < 0.32) {
        _triggerSeekFeedback(-10);
        widget.onDoubleTapSeek!(-10);
        return;
      }
      if (relX > 0.68) {
        _triggerSeekFeedback(10);
        widget.onDoubleTapSeek!(10);
        return;
      }
    }

    HapticUtils.selection();
    if (_isZoomed) {
      _animateMatrixTo(Matrix4.identity());
    } else {
      final target = _zoomMatrixAroundPoint(
        baseMatrix: Matrix4.identity(),
        targetScale: _kDoubleTapScale,
        focalLocal: focal,
      );
      _animateMatrixTo(target);
    }
  }

  void _triggerSeekFeedback(int deltaSeconds) {
    HapticUtils.selection();
    _seekFeedbackTimer?.cancel();
    if (mounted) {
      setState(() => _seekFeedbackSeconds = deltaSeconds);
    }
    _seekFeedbackTimer = Timer(const Duration(milliseconds: 620), () {
      if (mounted) {
        setState(() => _seekFeedbackSeconds = null);
      }
    });
  }

  // ---- Multi-touch pinch handling via Listener ----

  void _onPointerDown(PointerDownEvent event) {
    _activePointers[event.pointer] = event.localPosition;
    if (!widget.enableZoom) return;

    if (_activePointers.length == 2) {
      // Cancel any single-finger 2D dismiss drag cleanly if a second finger lands.
      if (_isDismissDragging) {
        _cancelDismissDragSmoothly();
      }
      final pts = _activePointers.values.toList(growable: false);
      _isPinching = true;
      _matrixAnimController.stop();
      _pinchStartFocalLocal = (pts[0] + pts[1]) * 0.5;
      _pinchStartDistance = math.max(12.0, (pts[0] - pts[1]).distance);
      _pinchStartMatrix = _transformController.value.clone();
      _pinchStartScale = _pinchStartMatrix.getMaxScaleOnAxis();
    }
  }

  void _onPointerMove(PointerMoveEvent event) {
    if (_activePointers.containsKey(event.pointer)) {
      _activePointers[event.pointer] = event.localPosition;
    }
    if (!_isPinching || _activePointers.length < 2 || !widget.enableZoom) {
      return;
    }

    final pts = _activePointers.values.take(2).toList(growable: false);
    final Offset currentFocal = (pts[0] + pts[1]) * 0.5;
    final double currentDist = math.max(12.0, (pts[0] - pts[1]).distance);
    final double rawScale = _pinchStartScale * (currentDist / _pinchStartDistance);
    // Allow subtle rubber-band overscale while fingers are down.
    final double elasticScale = rawScale < _kMinScale
        ? _kMinScale - (_kMinScale - rawScale) * 0.25
        : (rawScale > _kMaxScale
            ? _kMaxScale + (rawScale - _kMaxScale) * 0.22
            : rawScale);
    final double clampedElastic = elasticScale.clamp(0.84, 4.75);

    final col3 = _pinchStartMatrix.getColumn(3);
    final double contentX = (_pinchStartFocalLocal.dx - col3.x) / _pinchStartScale;
    final double contentY = (_pinchStartFocalLocal.dy - col3.y) / _pinchStartScale;
    final double nextTx = currentFocal.dx - contentX * clampedElastic;
    final double nextTy = currentFocal.dy - contentY * clampedElastic;

    final nextMatrix = Matrix4.identity()
      ..translateByDouble(nextTx, nextTy, 0.0, 1.0)
      ..scaleByDouble(clampedElastic, clampedElastic, 1.0, 1.0);

    _transformController.value = clampedElastic > _kMinScale
        ? nextMatrix
        : (Matrix4.identity()
          ..translateByDouble(
            currentFocal.dx - _stageSize.width * 0.5 * clampedElastic,
            currentFocal.dy - _stageSize.height * 0.5 * clampedElastic,
            0.0,
            1.0,
          )
          ..scaleByDouble(clampedElastic, clampedElastic, 1.0, 1.0));
  }

  void _onPointerUpOrCancel(int pointer) {
    _activePointers.remove(pointer);
    if (_isPinching && _activePointers.length < 2) {
      _isPinching = false;
      final s = _currentScale;
      if (s < 1.04) {
        _animateMatrixTo(Matrix4.identity());
      } else if (s > _kMaxScale) {
        _animateMatrixTo(_clampMatrix(_transformController.value));
      } else {
        final clamped = _clampMatrix(_transformController.value);
        if (clamped != _transformController.value) {
          _animateMatrixTo(clamped);
        }
      }
    }
  }

  void _onPointerSignal(PointerSignalEvent event) {
    if (!widget.enableZoom || event is! PointerScrollEvent) return;
    final dy = event.scrollDelta.dy;
    if (dy == 0.0) return;
    _matrixAnimController.stop();

    final double factor = dy < 0 ? 1.16 : (1.0 / 1.16);
    final double targetScale =
        (_currentScale * factor).clamp(_kMinScale, _kMaxScale);
    if (targetScale <= 1.02) {
      _transformController.value = Matrix4.identity();
      return;
    }
    _transformController.value = _zoomMatrixAroundPoint(
      baseMatrix: _transformController.value,
      targetScale: targetScale,
      focalLocal: event.localPosition,
    );
  }

  // ---- Zoomed pan vs 2D drag-to-dismiss ----

  void _onVerticalDragStart(DragStartDetails details) {
    if (_isPinching || _isZoomed || _activePointers.length >= 2) return;
    _dismissSpringController.stop();
    _isDismissDragging = true;
    widget.onDismissStart?.call();
  }

  void _onVerticalDragUpdate(DragUpdateDetails details) {
    if (!_isDismissDragging || _isPinching || _isZoomed) return;
    final next = _dismissOffsetNotifier.value +
        Offset(details.delta.dx * 0.65, details.delta.dy);
    _dismissOffsetNotifier.value = next;
    widget.onDismissUpdate?.call(next, _progressForOffset(next));
  }

  void _onVerticalDragEnd(DragEndDetails details) {
    if (!_isDismissDragging) return;
    _isDismissDragging = false;
    final offset = _dismissOffsetNotifier.value;
    final vy = details.primaryVelocity ?? 0.0;
    final bool shouldDismiss = offset.dy.abs() >= _kDismissDistanceThreshold ||
        vy.abs() >= _kDismissVelocityThreshold;
    if (shouldDismiss) {
      HapticUtils.selection();
      widget.onDismissEnd?.call(true);
    } else {
      _cancelDismissDragSmoothly();
    }
  }

  void _cancelDismissDragSmoothly({bool onlyIfActive = false}) {
    if (onlyIfActive && !_isDismissDragging) return;
    _isDismissDragging = false;
    final startOffset = _dismissOffsetNotifier.value;
    if (startOffset == Offset.zero) {
      widget.onDismissEnd?.call(false);
      return;
    }
    _dismissOffsetAnim = Tween<Offset>(
      begin: startOffset,
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _dismissSpringController,
        curve: Curves.easeOutCubic,
      ),
    );
    _dismissSpringController.forward(from: 0.0).whenComplete(() {
      if (mounted) {
        _dismissOffsetNotifier.value = Offset.zero;
        widget.onDismissEnd?.call(false);
      }
    });
  }

  void _onZoomedPanStart(DragStartDetails details) {
    if (!_isZoomed || _isPinching) return;
    _matrixAnimController.stop();
    _lastPanFocal = details.localPosition;
  }

  void _onZoomedPanUpdate(DragUpdateDetails details) {
    if (!_isZoomed || _isPinching) return;
    final delta = details.localPosition - _lastPanFocal;
    _lastPanFocal = details.localPosition;
    final m = _transformController.value.clone();
    final col3 = m.getColumn(3);
    final s = m.getMaxScaleOnAxis();
    final translated = Matrix4.identity()
      ..translateByDouble(col3.x + delta.dx, col3.y + delta.dy, 0.0, 1.0)
      ..scaleByDouble(s, s, 1.0, 1.0);
    _transformController.value = _clampMatrix(translated);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        _stageSize = constraints.biggest;
        return Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: _onPointerDown,
          onPointerMove: _onPointerMove,
          onPointerUp: (e) => _onPointerUpOrCancel(e.pointer),
          onPointerCancel: (e) => _onPointerUpOrCancel(e.pointer),
          onPointerSignal: _onPointerSignal,
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: widget.onSingleTap,
            onDoubleTapDown: (details) =>
                _lastTapLocalPos = details.localPosition,
            onDoubleTap: _handleDoubleTap,
            // Notice: horizontal swipe belongs natively to PageView when not zoomed;
            // only VerticalDrag (tracking both dx & dy 2D offset) or zoomed Pan is active.
            onVerticalDragStart: _isZoomed ? null : _onVerticalDragStart,
            onVerticalDragUpdate: _isZoomed ? null : _onVerticalDragUpdate,
            onVerticalDragEnd: _isZoomed ? null : _onVerticalDragEnd,
            onVerticalDragCancel:
                _isZoomed ? null : () => _cancelDismissDragSmoothly(onlyIfActive: true),
            onPanStart: _isZoomed ? _onZoomedPanStart : null,
            onPanUpdate: _isZoomed ? _onZoomedPanUpdate : null,
            child: Stack(
              fit: StackFit.expand,
              children: [
                ValueListenableBuilder<Offset>(
                  valueListenable: _dismissOffsetNotifier,
                  builder: (context, dragOffset, child) {
                    final double p = _progressForOffset(dragOffset);
                    final double dragScale = 1.0 - p * 0.22;
                    return Transform.translate(
                      offset: dragOffset,
                      child: Transform.scale(
                        scale: dragScale,
                        child: child,
                      ),
                    );
                  },
                  child: ValueListenableBuilder<Matrix4>(
                    valueListenable: _transformController,
                    builder: (context, matrix, child) {
                      return Transform(
                        transform: matrix,
                        child: child,
                      );
                    },
                    child: RepaintBoundary(
                      child: widget.child,
                    ),
                  ),
                ),
                if (_seekFeedbackSeconds != null)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Align(
                        alignment: _seekFeedbackSeconds! < 0
                            ? Alignment.centerLeft
                            : Alignment.centerRight,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 28),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(0xCC101218),
                              borderRadius: BorderRadius.circular(24),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.12),
                                width: 1.0,
                              ),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_seekFeedbackSeconds! < 0) ...[
                                  const Icon(
                                    Icons.fast_rewind_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Text(
                                  '${_seekFeedbackSeconds!.abs()} с',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 13.5,
                                    fontWeight: FontWeight.w600,
                                    decoration: TextDecoration.none,
                                  ),
                                ),
                                if (_seekFeedbackSeconds! > 0) ...[
                                  const SizedBox(width: 6),
                                  const Icon(
                                    Icons.fast_forward_rounded,
                                    color: Colors.white,
                                    size: 20,
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
