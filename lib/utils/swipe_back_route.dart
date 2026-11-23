import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../services/tiling_layout_controller.dart';
import '../widgets/tiling/tile_viewport_scope.dart';
import '../widgets/tiling/trackpad_swipe_back_indicator.dart';
import 'haptic_utils.dart';

/// PageRoute с интерактивным жестом свайпа слева направо для возврата
/// (работает на всех платформах).
///
/// **Push**: новый экран выезжает справа налево (с easeOutCubic),
///           предыдущий экран сдвигается влево, уменьшается и затемняется.
/// **Pop**:  текущий экран уезжает вправо, предыдущий возвращается на место.
/// **Свайп**: текущий экран линейно следует за пальцем,
///           предыдущий экран плавно проявляется и сдвигается (параллакс).
class SwipeBackPageRoute<T> extends MaterialPageRoute<T> {
  static const Curve _kPushCurve = Cubic(0.22, 0.82, 0.24, 1.0);
  static const Curve _kPopCurve = Curves.easeInCubic;

  AnimationController? _animationController;
  CurvedAnimation? _curvedPrimary;
  Animation<Offset>? _curvedPrimarySlide;
  Animation<Offset>? _linearPrimarySlide;
  Animation<Offset>? _secondarySlideAnim;
  Animation<double>? _secondaryDimAnim;
  Animation<double>? _boundPrimary;
  Animation<double>? _boundSecondary;

  SwipeBackPageRoute({
    required WidgetBuilder builder,
    RouteSettings? settings,
    bool maintainState = true,
    bool fullscreenDialog = false,
  }) : super(
          builder: builder,
          settings: settings,
          maintainState: maintainState,
          fullscreenDialog: fullscreenDialog,
        );

  @override
  Duration get transitionDuration => const Duration(milliseconds: 300);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 260);

  @override
  bool get opaque => true;

  @override
  AnimationController createAnimationController() {
    final controller = super.createAnimationController();
    _animationController = controller;
    return controller;
  }

  void _ensureAnimations(
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    if (!identical(_boundPrimary, animation)) {
      _curvedPrimary?.dispose();
      _boundPrimary = animation;
      _curvedPrimary = CurvedAnimation(
        parent: animation,
        curve: _kPushCurve,
        reverseCurve: _kPopCurve,
      );
      final slideTween = Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      );
      _curvedPrimarySlide = slideTween.animate(_curvedPrimary!);
      _linearPrimarySlide = slideTween.animate(animation);
    }
    if (!identical(_boundSecondary, secondaryAnimation)) {
      _boundSecondary = secondaryAnimation;
      _secondarySlideAnim = Tween<Offset>(
        begin: Offset.zero,
        end: const Offset(-0.28, 0.0),
      ).animate(secondaryAnimation);
      _secondaryDimAnim = Tween<double>(
        begin: 0.0,
        end: 0.35,
      ).animate(secondaryAnimation);
    }
  }

  @override
  void dispose() {
    _curvedPrimary?.dispose();
    _curvedPrimary = null;
    _boundPrimary = null;
    _boundSecondary = null;
    super.dispose();
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    _ensureAnimations(animation, secondaryAnimation);
    final bool isInteractive = popGestureInProgress;
    final bool showEdgeShadow =
        animation.value > 0.002 && animation.value < 0.998;
    final Animation<Offset> activePrimarySlide =
        isInteractive ? _linearPrimarySlide! : _curvedPrimarySlide!;

    return Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        if (secondaryAnimation.value > 0.001)
          IgnorePointer(
            child: FadeTransition(
              opacity: _secondaryDimAnim!,
              child: const ColoredBox(color: Colors.black),
            ),
          ),
        SlideTransition(
          position: activePrimarySlide,
          child: Stack(
            fit: StackFit.passthrough,
            clipBehavior: Clip.none,
            children: [
              if (showEdgeShadow)
                Positioned(
                  left: -16.0,
                  top: 0.0,
                  bottom: 0.0,
                  width: 16.0,
                  child: IgnorePointer(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            Colors.transparent,
                            Colors.black
                                .withValues(alpha: 0.14 * animation.value),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              _SwipeBackGestureDetector(
                animationController: _animationController,
                animation: animation,
                child: SlideTransition(
                  position: _secondarySlideAnim!,
                  child: RepaintBoundary(child: child),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Детектор свайпа по всей ширине экрана с распознаванием направления dX > 2*dY.
class _SwipeBackGestureDetector extends StatefulWidget {
  final Widget child;
  final AnimationController? animationController;
  final Animation<double> animation;

  const _SwipeBackGestureDetector({
    required this.child,
    required this.animationController,
    required this.animation,
  });

  @override
  State<_SwipeBackGestureDetector> createState() =>
      _SwipeBackGestureDetectorState();
}

class _SwipeBackGestureDetectorState extends State<_SwipeBackGestureDetector> {
  bool _isActive = false;
  double _dragOffset = 0.0;
  
  static const double _kPopThreshold = 0.35;
  static const double _kMinFlingVelocity = 500.0;

  double get _screenWidth => TileViewportScope.widthOf(context);

  bool _canPop() {
    if (!mounted) return false;
    if (_isActive) return true;
    if (TilingLayoutController.instance.isPopTransitionActive) return false;
    final modalRoute = ModalRoute.of(context);
    if (modalRoute?.isCurrent != true) return false;
    final secAnim = modalRoute?.secondaryAnimation;
    if (secAnim != null && secAnim.status != AnimationStatus.dismissed) {
      return false;
    }
    if (!widget.animation.isCompleted) return false;
    final navigator = Navigator.maybeOf(context);
    if (navigator == null ||
        !navigator.canPop() ||
        navigator.userGestureInProgress) {
      return false;
    }

    // We allow swipe back even if PopScope(canPop: false) is active,
    // because we want iOS-style "always back" gesture in chats.
    // The PopScope will still handle Android's system back button.
    return true;
  }

  bool _isPopBlocked() {
    if (!mounted) return false;
    final modalRoute = ModalRoute.of(context);
    return modalRoute?.popDisposition == RoutePopDisposition.doNotPop;
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (!_canPop()) return;

    Navigator.of(context).didStartUserGesture();

    setState(() {
      _isActive = true;
      _dragOffset = 0.0;
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isActive) return;
    
    _dragOffset += details.delta.dx;
    // Limit to rightward movement
    final offset = math.max(0.0, _dragOffset);
    final progress = (offset / _screenWidth).clamp(0.0, 1.0);
    
    if (widget.animationController != null) {
      // Direct manipulation 1:1 without triggering widget tree rebuilds
      widget.animationController!.value = 1.0 - progress;
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!_isActive) return;

    final progress = (math.max(0.0, _dragOffset) / _screenWidth).clamp(0.0, 1.0);
    final velocity = details.primaryVelocity ?? 0.0;

    final shouldPop = progress > _kPopThreshold || velocity > _kMinFlingVelocity;
    final navigator = Navigator.of(context);
    final modalRoute = ModalRoute.of(context);

    if (shouldPop) {
      HapticUtils.impact();
      TilingLayoutController.instance.recordBackTransition();
      // Use spring to finish the slide
      final simulation = SpringSimulation(
        const SpringDescription(mass: 1.0, stiffness: 400, damping: 28),
        widget.animationController!.value,
        0.0,
        -velocity / _screenWidth,
      );
      widget.animationController!.animateWith(simulation).then((_) {
        if (mounted) {
          navigator.didStopUserGesture();
          if (modalRoute?.isCurrent == true) {
            TilingLayoutController.instance.recordBackTransition();
            navigator.pop();
          }
        }
      });
    } else {
      // Spring back to full screen
      final simulation = SpringSimulation(
        const SpringDescription(mass: 1.0, stiffness: 400, damping: 28),
        widget.animationController!.value,
        1.0,
        -velocity / _screenWidth,
      );
      widget.animationController!.animateWith(simulation).then((_) {
        if (mounted) {
          navigator.didStopUserGesture();
        }
      });
    }

    setState(() {
      _isActive = false;
    });
  }

  void _onHorizontalDragCancel() {
    if (!_isActive) return;
    final navigator = Navigator.of(context);
    final simulation = SpringSimulation(
      const SpringDescription(mass: 1.0, stiffness: 400, damping: 28),
      widget.animationController!.value,
      1.0,
      0.0,
    );
    widget.animationController!.animateWith(simulation).then((_) {
      if (mounted) {
        navigator.didStopUserGesture();
      }
    });
    setState(() {
      _isActive = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final tileSize = TileViewportScope.sizeOf(context);
    final screenHeight = tileSize.height;
    final screenWidth = tileSize.width;
    final bottomInset = TileViewportScope.viewInsetsOf(context).bottom;
    final isInsideTile = TileViewportScope.maybeTileIdOf(context) != null;
    final sysLeftInset = MediaQuery.systemGestureInsetsOf(context).left;
    final platform = Theme.of(context).platform;
    final isMobile =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    final leftEdgeInset = isMobile ? math.max(28.0, sysLeftInset) : 0.0;

    Widget detector = RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        _BackGestureRecognizer: GestureRecognizerFactoryWithHandlers<_BackGestureRecognizer>(
          () => _BackGestureRecognizer(
            canPopGetter: _canPop,
            isPopBlockedGetter: _isPopBlocked,
            screenHeight: screenHeight,
            screenWidth: screenWidth,
            bottomInset: bottomInset,
            leftEdgeInset: leftEdgeInset,
          ),
          (_BackGestureRecognizer instance) {
            instance.canPopGetter = _canPop;
            instance.isPopBlockedGetter = _isPopBlocked;
            instance.screenHeight = screenHeight;
            instance.screenWidth = screenWidth;
            instance.bottomInset = bottomInset;
            instance.leftEdgeInset = leftEdgeInset;
            instance.onStart = _onHorizontalDragStart;
            instance.onUpdate = _onHorizontalDragUpdate;
            instance.onEnd = _onHorizontalDragEnd;
            instance.onCancel = _onHorizontalDragCancel;
          },
        ),
      },
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );

    if (!isInsideTile) {
      detector = TrackpadBackGestureWrapper(
        canTriggerBack: _canPop,
        onTriggerBack: () {
          if (_canPop() && !_isPopBlocked()) {
            Navigator.of(context).maybePop();
          }
        },
        child: detector,
      );
    }

    return detector;
  }
}

/// Переиспользуемый детектор интерактивного свайпа назад (1:1 с пальцем + пружинная физика),
/// используемый для закрытия корневого экрана чата в однооконном режиме тайлинговой архитектуры.
class InteractiveSwipeBackGestureDetector extends StatefulWidget {
  final Widget child;
  final AnimationController animationController;
  final bool Function() canSwipeBack;
  final bool Function()? isPopBlocked;
  final VoidCallback? onDragStart;
  final VoidCallback onDismissed;
  final VoidCallback? onRestored;
  final Size? viewportSizeOverride;

  const InteractiveSwipeBackGestureDetector({
    super.key,
    required this.child,
    required this.animationController,
    required this.canSwipeBack,
    required this.onDismissed,
    this.isPopBlocked,
    this.onDragStart,
    this.onRestored,
    this.viewportSizeOverride,
  });

  @override
  State<InteractiveSwipeBackGestureDetector> createState() =>
      _InteractiveSwipeBackGestureDetectorState();
}

class _InteractiveSwipeBackGestureDetectorState
    extends State<InteractiveSwipeBackGestureDetector> {
  bool _isActive = false;
  double _dragOffset = 0.0;

  static const double _kPopThreshold = 0.35;
  static const double _kMinFlingVelocity = 500.0;

  Size get _effectiveSize =>
      widget.viewportSizeOverride ?? TileViewportScope.sizeOf(context);

  double get _screenWidth {
    final w = _effectiveSize.width;
    return w > 0 ? w : 1.0;
  }

  bool _canSwipe() {
    if (!mounted) return false;
    if (_isActive) return true;
    return widget.canSwipeBack();
  }

  bool _isBlocked() {
    if (!mounted) return false;
    return widget.isPopBlocked?.call() ?? false;
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (!_canSwipe()) return;
    _isActive = true;
    _dragOffset = 0.0;
    widget.onDragStart?.call();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isActive) return;

    _dragOffset += details.delta.dx;
    final offset = math.max(0.0, _dragOffset);
    final progress = (offset / _screenWidth).clamp(0.0, 1.0);

    widget.animationController.value = 1.0 - progress;
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!_isActive) return;
    _isActive = false;

    final progress =
        (math.max(0.0, _dragOffset) / _screenWidth).clamp(0.0, 1.0);
    final velocity = details.primaryVelocity ?? 0.0;

    final shouldDismiss =
        progress > _kPopThreshold || velocity > _kMinFlingVelocity;

    if (shouldDismiss) {
      HapticUtils.impact();
      TilingLayoutController.instance.recordBackTransition();
      final simulation = SpringSimulation(
        const SpringDescription(mass: 1.0, stiffness: 400, damping: 28),
        widget.animationController.value,
        0.0,
        -velocity / _screenWidth,
      );
      widget.animationController.animateWith(simulation).then((_) {
        if (mounted) {
          widget.onDismissed();
        }
      });
    } else {
      final simulation = SpringSimulation(
        const SpringDescription(mass: 1.0, stiffness: 400, damping: 28),
        widget.animationController.value,
        1.0,
        -velocity / _screenWidth,
      );
      widget.animationController.animateWith(simulation).then((_) {
        if (mounted) {
          widget.onRestored?.call();
        }
      });
    }
  }

  void _onHorizontalDragCancel() {
    if (!_isActive) return;
    _isActive = false;

    final simulation = SpringSimulation(
      const SpringDescription(mass: 1.0, stiffness: 400, damping: 28),
      widget.animationController.value,
      1.0,
      0.0,
    );
    widget.animationController.animateWith(simulation).then((_) {
      if (mounted) {
        widget.onRestored?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final tileSize = _effectiveSize;
    final screenHeight = tileSize.height;
    final screenWidth = tileSize.width;
    final bottomInset = TileViewportScope.viewInsetsOf(context).bottom;
    final sysLeftInset = MediaQuery.systemGestureInsetsOf(context).left;
    final platform = Theme.of(context).platform;
    final isMobile =
        platform == TargetPlatform.android || platform == TargetPlatform.iOS;
    final leftEdgeInset = isMobile ? math.max(28.0, sysLeftInset) : 0.0;

    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        _BackGestureRecognizer:
            GestureRecognizerFactoryWithHandlers<_BackGestureRecognizer>(
          () => _BackGestureRecognizer(
            canPopGetter: _canSwipe,
            isPopBlockedGetter: _isBlocked,
            screenHeight: screenHeight,
            screenWidth: screenWidth,
            bottomInset: bottomInset,
            leftEdgeInset: leftEdgeInset,
          ),
          (_BackGestureRecognizer instance) {
            instance.canPopGetter = _canSwipe;
            instance.isPopBlockedGetter = _isBlocked;
            instance.screenHeight = screenHeight;
            instance.screenWidth = screenWidth;
            instance.bottomInset = bottomInset;
            instance.leftEdgeInset = leftEdgeInset;
            instance.onStart = _onHorizontalDragStart;
            instance.onUpdate = _onHorizontalDragUpdate;
            instance.onEnd = _onHorizontalDragEnd;
            instance.onCancel = _onHorizontalDragCancel;
          },
        ),
      },
      behavior: HitTestBehavior.translucent,
      child: widget.child,
    );
  }
}

/// Распознаватель полноэкранного свайпа назад (как в Telegram).
/// Работает по всей площади экрана за исключением нижней зоны ввода/клавиатуры,
/// и уступает арену жестов внутренним скроллируемым виджетам (PageView, Slider и т.д.).
class _BackGestureRecognizer extends HorizontalDragGestureRecognizer {
  bool Function() canPopGetter;
  bool Function() isPopBlockedGetter;
  double screenHeight;
  double screenWidth;
  double bottomInset;
  double leftEdgeInset;
  bool _gestureAccepted = false;

  _BackGestureRecognizer({
    required this.canPopGetter,
    required this.isPopBlockedGetter,
    required this.screenHeight,
    required this.screenWidth,
    required this.bottomInset,
    this.leftEdgeInset = 0.0,
  });

  bool _isAllowedDeviceKind(PointerDeviceKind kind) {
    // Only allow touch and stylus for 1:1 finger slide-back.
    // On desktop, mouse drags must NOT trigger slide-back (prevents text selection / accidental pops),
    // and trackpad two-finger swipe is handled by TrackpadBackGestureWrapper.
    return kind == PointerDeviceKind.touch ||
        kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus;
  }

  bool _isPointInExcludedArea(Offset localPosition, {bool isPointerDown = false}) {
    // Exclude the left system edge zone on mobile at touch start so Android/iOS
    // system edge-back gesture never triggers both system back and custom swipe-back.
    if (isPointerDown && leftEdgeInset > 0 && localPosition.dx < leftEdgeInset) {
      return true;
    }

    // Top app bar / header area (status bar + floating glass bar) is reserved for buttons
    if (localPosition.dy < 110.0) return true;

    // When keyboard is open, exclude the keyboard + input field area.
    // When keyboard is closed, exclude the bottom 120px where the input field is located.
    final double bottomThreshold =
        screenHeight - (bottomInset > 0 ? bottomInset + 100.0 : 120.0);
    return localPosition.dy > bottomThreshold;
  }

  @override
  bool isPointerAllowed(PointerEvent event) {
    if (!canPopGetter()) return false;
    if (!_isAllowedDeviceKind(event.kind)) return false;
    if (_isPointInExcludedArea(event.localPosition, isPointerDown: true)) {
      return false;
    }
    if (isPopBlockedGetter() && event.localPosition.dy > screenHeight * 0.5) {
      return false;
    }
    return super.isPointerAllowed(event);
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (!_isAllowedDeviceKind(event.kind)) {
      return;
    }
    if (_isPointInExcludedArea(event.localPosition, isPointerDown: true)) {
      return;
    }
    _gestureAccepted = false;
    super.addAllowedPointer(event);
  }

  @override
  void acceptGesture(int pointer) {
    _gestureAccepted = true;
    super.acceptGesture(pointer);
  }

  @override
  void rejectGesture(int pointer) {
    _gestureAccepted = false;
    super.rejectGesture(pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (!_gestureAccepted) {
      if (!canPopGetter() ||
          !_isAllowedDeviceKind(event.kind) ||
          _isPointInExcludedArea(event.localPosition)) {
        resolve(GestureDisposition.rejected);
        stopTrackingPointer(event.pointer);
        return;
      }

      if (isPopBlockedGetter() && event.localPosition.dy > screenHeight * 0.5) {
        resolve(GestureDisposition.rejected);
        stopTrackingPointer(event.pointer);
        return;
      }

      if (event is PointerMoveEvent) {
        final double dx = event.delta.dx;
        final double dy = event.delta.dy;

        // Отклоняем при движении влево или диагональном/вертикальном свайпе
        if (dx < -0.1 || dy.abs() > dx.abs() * 0.8) {
          resolve(GestureDisposition.rejected);
          stopTrackingPointer(event.pointer);
          return;
        }
        // При движении вправо НЕ вызываем принудительный resolve(accepted),
        // чтобы дать внутренним виджетам (PageView) возможность обработать свой скролл.
        // Если внутренний виджет не может скроллиться (или достиг границы),
        // Flutter естественным образом отдаёт победу в арене жестов _BackGestureRecognizer.
      }
    }
    super.handleEvent(event);
  }
}

