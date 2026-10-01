import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

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
  AnimationController? _animationController;

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
  Duration get transitionDuration => const Duration(milliseconds: 250);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 250);

  @override
  bool get opaque => true;

  @override
  AnimationController createAnimationController() {
    final controller = super.createAnimationController();
    _animationController = controller;
    return controller;
  }

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final bool isInteractive = popGestureInProgress;

    // === Primary animation: current route entering/leaving ===
    final slideTransition = Tween<Offset>(
      begin: const Offset(1.0, 0.0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: animation,
      curve: isInteractive ? Curves.linear : Curves.easeOutCubic,
      reverseCurve: isInteractive ? Curves.linear : Curves.easeInCubic,
    ));

    // Shadow for the left edge of the current screen
    final shadowAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(animation);

    // === Secondary animation: this route when covered by another ===
    // Parallax effect: -0.3 offset
    final secondarySlide = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.3, 0.0),
    ).animate(CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.linear, // Linear for interactive sync
    ));

    // Dimming overlay on the route below
    final secondaryDim = Tween<double>(
      begin: 0.0,
      end: 0.4,
    ).animate(CurvedAnimation(
      parent: secondaryAnimation,
      curve: Curves.linear,
    ));

    return Stack(
      children: [
        // Dimming overlay for the screen BELOW
        if (secondaryAnimation.value > 0)
          FadeTransition(
            opacity: secondaryDim,
            child: Container(color: Colors.black),
          ),
        
        SlideTransition(
          position: slideTransition,
          child: _SwipeBackGestureDetector(
            animationController: _animationController,
            animation: animation,
            child: Container(
              decoration: BoxDecoration(
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15 * shadowAnimation.value),
                    blurRadius: 20,
                    spreadRadius: 2,
                    offset: const Offset(-5, 0),
                  ),
                ],
              ),
              child: SlideTransition(
                position: secondarySlide,
                child: child,
              ),
            ),
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

  double get _screenWidth => MediaQuery.of(context).size.width;

  bool _canPop() {
    final navigator = Navigator.of(context);
    if (!navigator.canPop()) return false;

    // We allow swipe back even if PopScope(canPop: false) is active,
    // because we want iOS-style "always back" gesture in chats.
    // The PopScope will still handle Android's system back button.
    return true;
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (!_canPop()) return;

    final modalRoute = ModalRoute.of(context);
    if (modalRoute?.isCurrent != true) return;
    if (!widget.animation.isCompleted) return;

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
    final modalRoute = ModalRoute.of(context);
    final isPopBlocked = modalRoute?.popDisposition == RoutePopDisposition.doNotPop;
    final mediaQuery = MediaQuery.of(context);
    final screenHeight = mediaQuery.size.height;
    final screenWidth = mediaQuery.size.width;
    final bottomInset = mediaQuery.viewInsets.bottom;

    return RawGestureDetector(
      gestures: <Type, GestureRecognizerFactory>{
        _BackGestureRecognizer: GestureRecognizerFactoryWithHandlers<_BackGestureRecognizer>(
          () => _BackGestureRecognizer(
            canPop: modalRoute?.canPop ?? false,
            screenHeight: screenHeight,
            screenWidth: screenWidth,
            bottomInset: bottomInset,
            isPopBlocked: isPopBlocked,
          ),
          (_BackGestureRecognizer instance) {
            instance.canPop = modalRoute?.canPop ?? false;
            instance.screenHeight = screenHeight;
            instance.screenWidth = screenWidth;
            instance.bottomInset = bottomInset;
            instance.isPopBlocked = isPopBlocked;
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
  bool canPop;
  double screenHeight;
  double screenWidth;
  double bottomInset;
  bool isPopBlocked;

  _BackGestureRecognizer({
    required this.canPop,
    required this.screenHeight,
    required this.screenWidth,
    required this.bottomInset,
    required this.isPopBlocked,
  });

  bool _isPointInExcludedArea(Offset position) {
    // Top app bar / header area (status bar + floating glass bar) is reserved for buttons
    if (position.dy < 110.0) return true;

    // When keyboard is open, exclude the keyboard + input field area.
    // When keyboard is closed, exclude the bottom 120px where the input field is located.
    final double bottomThreshold =
        screenHeight - (bottomInset > 0 ? bottomInset + 100.0 : 120.0);
    return position.dy > bottomThreshold;
  }

  @override
  bool isPointerAllowed(PointerEvent event) {
    if (!canPop) return false;
    if (_isPointInExcludedArea(event.position)) return false;
    return super.isPointerAllowed(event);
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    if (_isPointInExcludedArea(event.position)) {
      return;
    }
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (!canPop || _isPointInExcludedArea(event.position)) {
      resolve(GestureDisposition.rejected);
      stopTrackingPointer(event.pointer);
      return;
    }

    if (isPopBlocked && event.position.dy > screenHeight * 0.5) {
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
    super.handleEvent(event);
  }
}

