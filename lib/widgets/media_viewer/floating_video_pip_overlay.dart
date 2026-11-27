import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:video_player/video_player.dart';

import '../../models/theav_media_item.dart';
import '../../services/deep_link_service.dart';
import '../../services/video_pip_service.dart';
import '../../utils/haptic_utils.dart';
import 'theav_media_viewer.dart';

/// Draggable, corner-snapping, pinch-resizable floating in-app video PiP card.
///
/// Zero blur, zero `LiquidGlassLens`, zero overhead (`SizedBox.shrink()`) when
/// inactive. Mounted globally in `main.dart`'s root overlay [Stack].
class FloatingVideoPipOverlay extends StatefulWidget {
  const FloatingVideoPipOverlay({super.key});

  @override
  State<FloatingVideoPipOverlay> createState() =>
      _FloatingVideoPipOverlayState();
}

class _FloatingVideoPipOverlayState extends State<FloatingVideoPipOverlay>
    with SingleTickerProviderStateMixin {
  static const double _kEdgeMargin = 12.0;

  final VideoPipService _service = VideoPipService.instance;
  late final AnimationController _snapController;

  Animation<Offset>? _snapAnim;
  VideoPlayerController? _observedController;
  Offset? _position;
  bool _showControls = false;
  Timer? _hideControlsTimer;
  bool _isDismissing = false;
  double _pinchBaseScale = 1.0;

  @override
  void initState() {
    super.initState();
    _snapController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(_onSnapTick);
    _service.addListener(_onServiceChanged);
    _attachVideoListener();
  }

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _detachVideoListener();
    _service.removeListener(_onServiceChanged);
    _snapController.dispose();
    super.dispose();
  }

  void _onServiceChanged() {
    _attachVideoListener();
    if (!_service.isActive) {
      _position = null;
      _showControls = false;
      _isDismissing = false;
    }
    if (mounted) setState(() {});
  }

  void _attachVideoListener() {
    final ctrl = _service.controller;
    if (!identical(ctrl, _observedController)) {
      _detachVideoListener();
      _observedController = ctrl;
      ctrl?.addListener(_onVideoTick);
    }
  }

  void _detachVideoListener() {
    _observedController?.removeListener(_onVideoTick);
    _observedController = null;
  }

  void _onVideoTick() {
    if (mounted && _service.isActive) {
      setState(() {});
    }
  }

  void _onSnapTick() {
    if (_snapAnim != null && mounted) {
      setState(() {
        _position = _snapAnim!.value;
      });
    }
  }

  Size _cardSizeFor(double aspectRatio, double widthScale) {
    final double baseWidth = aspectRatio < 0.9 ? 132.0 : 196.0;
    final double w = (baseWidth * widthScale).clamp(112.0, 290.0);
    final double h = (w / aspectRatio).clamp(86.0, 280.0);
    return Size(w, h);
  }

  Offset _defaultPosition(Size screen, Size cardSize, EdgeInsets pad) {
    final saved = _service.floatingPosition;
    if (saved != null) return saved;
    return Offset(
      screen.width - cardSize.width - _kEdgeMargin,
      pad.top + 64.0,
    );
  }

  double _edgeFadeAlpha(double x, double screenWidth, double cardWidth) {
    if (x < 0) {
      return (1.0 - (-x / (cardWidth * 0.95))).clamp(0.15, 1.0);
    }
    final double rightEdge = screenWidth - cardWidth;
    if (x > rightEdge) {
      return (1.0 - ((x - rightEdge) / (cardWidth * 0.95))).clamp(0.15, 1.0);
    }
    return 1.0;
  }

  void _snapToNearestCorner(
    Size screen,
    Size cardSize,
    EdgeInsets pad,
    Velocity velocity,
  ) {
    final current = _position ?? _defaultPosition(screen, cardSize, pad);
    final vx = velocity.pixelsPerSecond.dx;
    final bool flingOffLeft =
        vx < -520 && current.dx < _kEdgeMargin * 2;
    final bool flingOffRight = vx > 520 &&
        current.dx > screen.width - cardSize.width - _kEdgeMargin * 2;
    final bool draggedOffScreen = current.dx < -cardSize.width * 0.42 ||
        current.dx > screen.width - cardSize.width * 0.58;

    if (flingOffLeft || flingOffRight || draggedOffScreen) {
      _isDismissing = true;
      HapticUtils.selection();
      final double exitX =
          (current.dx + cardSize.width * 0.5 < screen.width * 0.5)
              ? -cardSize.width - 24.0
              : screen.width + 24.0;
      _snapAnim = Tween<Offset>(
        begin: current,
        end: Offset(exitX, current.dy),
      ).animate(
        CurvedAnimation(parent: _snapController, curve: Curves.easeOutCubic),
      );
      _snapController.forward(from: 0.0).whenComplete(() {
        unawaited(_service.close());
      });
      return;
    }

    const double leftX = _kEdgeMargin;
    final double rightX = math.max(
      leftX,
      screen.width - cardSize.width - _kEdgeMargin,
    );
    final double minTop = pad.top + 8.0;
    final double maxTop = math.max(
      minTop,
      screen.height - cardSize.height - math.max(pad.bottom, 16.0) - 64.0,
    );

    final double targetX =
        (current.dx + cardSize.width * 0.5 < screen.width * 0.5)
            ? leftX
            : rightX;
    final double targetY =
        (current.dy + cardSize.height * 0.5 < screen.height * 0.5)
            ? minTop + 56.0
            : maxTop;
    final Offset target = Offset(
      targetX,
      targetY.clamp(minTop, maxTop),
    );
    _service.updatePosition(target);

    _snapAnim = Tween<Offset>(begin: current, end: target).animate(
      CurvedAnimation(parent: _snapController, curve: Curves.easeOutCubic),
    );
    _snapController.forward(from: 0.0);
  }

  void _toggleControlsAutoHide() {
    _hideControlsTimer?.cancel();
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _hideControlsTimer = Timer(const Duration(seconds: 3), () {
        if (mounted && _showControls) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  void _expandToFullscreen() {
    final item = _service.item;
    if (item == null) return;
    final nav = DeepLinkService().navigatorKey.currentState ??
        Navigator.maybeOf(context, rootNavigator: true);
    if (nav == null) return;
    final playlist = _service.playlist;
    final idx = _service.itemIndex;
    final cfg = _service.viewerConfig;
    HapticUtils.tap();
    TheavMediaViewer.open<void>(
      nav.context,
      items: playlist.isNotEmpty ? playlist : [item],
      initialIndex: idx,
      config: cfg ?? const TheavMediaViewerConfig(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ctrl = _service.controller;
    final item = _service.item;
    if (ctrl == null || item == null) {
      return const SizedBox.shrink();
    }

    final mq = MediaQuery.of(context);
    final size = mq.size;
    final pad = mq.padding;
    final cardSize = _cardSizeFor(_service.aspectRatio, _service.widthScale);
    final pos = _position ?? _defaultPosition(size, cardSize, pad);
    final double alpha = _edgeFadeAlpha(pos.dx, size.width, cardSize.width);

    final v = ctrl.value;
    final double progress = (v.isInitialized && v.duration.inMilliseconds > 0)
        ? (v.position.inMilliseconds / v.duration.inMilliseconds)
            .clamp(0.0, 1.0)
        : 0.0;

    return Positioned(
      left: pos.dx,
      top: pos.dy,
      width: cardSize.width,
      height: cardSize.height,
      child: RepaintBoundary(
        child: GestureDetector(
          onTap: _toggleControlsAutoHide,
          onDoubleTap: _expandToFullscreen,
          onScaleStart: (d) {
            if (_isDismissing) return;
            _snapController.stop();
            _pinchBaseScale = _service.widthScale;
          },
          onScaleUpdate: (d) {
            if (_isDismissing) return;
            if (d.pointerCount >= 2 && (d.scale - 1.0).abs() > 0.02) {
              _service.updateWidthScale(_pinchBaseScale * d.scale);
              return;
            }
            final minTop = pad.top + 4.0;
            final maxTop = math.max(
              minTop,
              size.height - cardSize.height - math.max(pad.bottom, 12.0),
            );
            final next = (_position ?? pos) + d.focalPointDelta;
            setState(() {
              _position = Offset(
                next.dx.clamp(-cardSize.width - 20.0, size.width + 20.0),
                next.dy.clamp(minTop, maxTop),
              );
            });
          },
          onScaleEnd: (d) {
            if (_isDismissing) return;
            _snapToNearestCorner(size, cardSize, pad, d.velocity);
          },
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF101218).withValues(alpha: alpha),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.16 * alpha),
                width: 1.0,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.48 * alpha),
                  blurRadius: 18,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(15),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  VideoPlayer(ctrl),
                  if (_showControls)
                    Container(
                      color: const Color(0x78000000),
                      child: Stack(
                        children: [
                          Positioned(
                            top: 6,
                            left: 6,
                            child: _PipMiniButton(
                              onTap: _expandToFullscreen,
                              child: const Icon(
                                Icons.open_in_full_rounded,
                                color: Colors.white,
                                size: 15,
                              ),
                            ),
                          ),
                          Positioned(
                            top: 6,
                            right: 6,
                            child: _PipMiniButton(
                              onTap: () => unawaited(_service.close()),
                              child: const iconoir.Xmark(
                                color: Colors.white,
                                width: 15,
                                height: 15,
                              ),
                            ),
                          ),
                          Center(
                            child: _PipMiniButton(
                              size: 40,
                              onTap: () =>
                                  unawaited(_service.togglePlayPause()),
                              child: v.isPlaying
                                  ? const iconoir.Pause(
                                      color: Colors.white,
                                      width: 20,
                                      height: 20,
                                    )
                                  : const iconoir.Play(
                                      color: Colors.white,
                                      width: 20,
                                      height: 20,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    height: 2.5,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        ColoredBox(
                          color: Colors.white.withValues(alpha: 0.18),
                        ),
                        FractionallySizedBox(
                          alignment: Alignment.centerLeft,
                          widthFactor: progress,
                          child: const ColoredBox(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PipMiniButton extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  final double size;

  const _PipMiniButton({
    required this.onTap,
    required this.child,
    this.size = 28.0,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: const Color(0xB3101218),
          shape: BoxShape.circle,
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.14),
            width: 0.8,
          ),
        ),
        alignment: Alignment.center,
        child: child,
      ),
    );
  }
}
