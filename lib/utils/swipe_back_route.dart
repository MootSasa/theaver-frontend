import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';

import '../services/tiling_layout_controller.dart';
import '../widgets/tiling/tile_viewport_scope.dart';
import '../widgets/tiling/trackpad_swipe_back_indicator.dart';
import 'haptic_utils.dart';

final SpringDescription _kSwipeBackSpring = SpringDescription.withDampingRatio(
  mass: 1.0,
  stiffness: 520.0,
  ratio: 1.0,
);

const Tolerance _kSwipeBackSpringTolerance = Tolerance(
  distance: 8e-3,
  velocity: 4e-2,
);

const double _kSwipePopProgressThreshold = 0.30;
const double _kSwipeMinFlingVelocity = 520.0;
const double _kSwipeCancelFlingVelocity = -350.0;
const double _kSwipeUnfocusProgress = 0.03;

/// Critically damped (`ratio = 1.0`) non-rebounding dismiss simulation that
/// completes as soon as the route reaches the right edge (`x <= 0.006`),
/// preventing any overshoot flash or clamped tail delay on fast flings.
class _SwipeDismissSpringSimulation extends Simulation {
  final SpringSimulation _inner;

  _SwipeDismissSpringSimulation({
    required double start,
    required double velocity,
  })  : _inner = SpringSimulation(
          _kSwipeBackSpring,
          start.clamp(0.0, 1.0),
          0.0,
          velocity,
          tolerance: _kSwipeBackSpringTolerance,
        ),
        super(tolerance: _kSwipeBackSpringTolerance);

  @override
  double x(double time) => _inner.x(time).clamp(0.0, 1.0);

  @override
  double dx(double time) => _inner.x(time) <= 0.0 ? 0.0 : _inner.dx(time);

  @override
  bool isDone(double time) => _inner.x(time) <= 0.006 || _inner.isDone(time);
}

/// Tracks active interactive swipe-drag + spring-settle sessions per
/// [NavigatorState] so both primary and secondary transitions stay `1:1` linear
/// until the spring settles, even after `navigator.didStopUserGesture()` is
/// called on finger release to unblock the underlying route immediately.
class _NavigatorLinearSwipeTracker {
  static final Expando<ValueNotifier<int>> _notifiers =
      Expando<ValueNotifier<int>>('NavigatorLinearSwipeTracker');
  static final ValueNotifier<int> _idle = ValueNotifier<int>(0);

  static ValueNotifier<int> notifierFor(NavigatorState? navigator) {
    if (navigator == null) return _idle;
    var existing = _notifiers[navigator];
    if (existing == null) {
      existing = ValueNotifier<int>(0);
      _notifiers[navigator] = existing;
    }
    return existing;
  }

  static VoidCallback begin(NavigatorState? navigator) {
    if (navigator == null) return () {};
    final n = notifierFor(navigator);
    n.value = n.value + 1;
    bool ended = false;
    return () {
      if (ended) return;
      ended = true;
      if (n.value > 0) {
        n.value = n.value - 1;
      }
    };
  }
}

/// Marks an interactive horizontal control (e.g., custom seekbars, waveform
/// scrubbers, color sliders) so the full-screen rightward swipe-back gesture
/// yields when the pointer goes down inside it.
class SwipeBackBlocker extends SingleChildRenderObjectWidget {
  final bool enabled;

  const SwipeBackBlocker({
    super.key,
    this.enabled = true,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderSwipeBackBlocker(enabled: enabled);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderSwipeBackBlocker renderObject,
  ) {
    renderObject.enabled = enabled;
  }
}

class RenderSwipeBackBlocker extends RenderProxyBox {
  bool enabled;

  RenderSwipeBackBlocker({this.enabled = true});
}

class _RouteSwipeBackRegistry {
  final List<_SwipeBackPopScopeState> scopes = <_SwipeBackPopScopeState>[];
}

/// Route-scoped configuration for custom full-screen swipe-back behavior.
///
/// - When [swipeBackEnabled] is `false` (e.g. active message selection mode or
///   voice recording), interactive swipe-back is disabled for the enclosing
///   [ModalRoute].
/// - When [onSwipeBackPop] is provided (e.g. screens with `PopScope(canPop: false)`
///   that return a custom result on back), completing an interactive swipe-back
///   invokes [onSwipeBackPop] instead of a bare `navigator.pop()`.
class SwipeBackPopScope extends StatefulWidget {
  final Widget child;
  final bool swipeBackEnabled;
  final FutureOr<void> Function()? onSwipeBackPop;

  const SwipeBackPopScope({
    super.key,
    required this.child,
    this.swipeBackEnabled = true,
    this.onSwipeBackPop,
  });

  static final Expando<_RouteSwipeBackRegistry> _registry =
      Expando<_RouteSwipeBackRegistry>('SwipeBackPopScope');

  static bool isEnabledForRoute(ModalRoute<dynamic>? route) {
    if (route == null) return true;
    final reg = _registry[route];
    if (reg == null || reg.scopes.isEmpty) return true;
    for (final scope in reg.scopes) {
      if (scope.mounted && !scope.widget.swipeBackEnabled) {
        return false;
      }
    }
    return true;
  }

  static FutureOr<void> Function()? popCallbackForRoute(
    ModalRoute<dynamic>? route,
  ) {
    if (route == null) return null;
    final reg = _registry[route];
    if (reg == null || reg.scopes.isEmpty) return null;
    for (int i = reg.scopes.length - 1; i >= 0; i--) {
      final scope = reg.scopes[i];
      if (scope.mounted && scope.widget.onSwipeBackPop != null) {
        return scope.widget.onSwipeBackPop;
      }
    }
    return null;
  }

  @override
  State<SwipeBackPopScope> createState() => _SwipeBackPopScopeState();
}

class _SwipeBackPopScopeState extends State<SwipeBackPopScope> {
  ModalRoute<dynamic>? _registeredRoute;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextRoute = ModalRoute.of(context);
    if (!identical(nextRoute, _registeredRoute)) {
      _unregisterFrom(_registeredRoute);
      _registeredRoute = nextRoute;
      _registerOn(nextRoute);
    }
  }

  void _registerOn(ModalRoute<dynamic>? route) {
    if (route == null) return;
    var reg = SwipeBackPopScope._registry[route];
    if (reg == null) {
      reg = _RouteSwipeBackRegistry();
      SwipeBackPopScope._registry[route] = reg;
    }
    if (!reg.scopes.contains(this)) {
      reg.scopes.add(this);
    }
  }

  void _unregisterFrom(ModalRoute<dynamic>? route) {
    if (route == null) return;
    final reg = SwipeBackPopScope._registry[route];
    reg?.scopes.remove(this);
  }

  @override
  void dispose() {
    _unregisterFrom(_registeredRoute);
    _registeredRoute = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Shared Telegram-grade [PageTransitionsBuilder] providing full-screen
/// interactive swipe-back, `-0.28` underlying parallax, and top-mounted scrim
/// dimming for all [MaterialPageRoute]s.
class TelegramSwipeBackPageTransitionsBuilder extends PageTransitionsBuilder {
  const TelegramSwipeBackPageTransitionsBuilder();

  @override
  Duration get transitionDuration => SwipeBackPageRoute.kPushDuration;

  @override
  Duration get reverseTransitionDuration => SwipeBackPageRoute.kPopDuration;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      SwipeBackPageRoute.delegatedTransitionBuilder;

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return SwipeBackPageRoute.buildSharedTransitions<T>(
      route: route,
      context: context,
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

/// PageRoute с интерактивным жестом свайпа слева направо для возврата
/// (работает на всех платформах, кинематика идентична Telegram ActionBarLayout).
///
/// **Push**: новый экран выезжает справа налево, предыдущий экран сдвигается
///           на `-28%` влево и плавно затемняется сверху (`Color(0x47000000)`).
/// **Pop**:  текущий экран уезжает вправо, предыдущий возвращается на место.
/// **Свайп**: текущий экран линейно `1:1` следует за пальцем по всей площади
///           экрана, предыдущий экран плавно проявляется и сдвигается.
class SwipeBackPageRoute<T> extends MaterialPageRoute<T> {
  static const Curve kPushCurve = Cubic(0.22, 0.82, 0.24, 1.0);
  static const Curve kPopCurve = Curves.easeInCubic;
  static const Duration kPushDuration = Duration(milliseconds: 300);
  static const Duration kPopDuration = Duration(milliseconds: 260);
  static const Color kScrimColor = Color(0x47000000);
  static const Offset kSecondaryParallaxOffset = Offset(-0.28, 0.0);

  SwipeBackPageRoute({
    required super.builder,
    super.settings,
    super.maintainState = true,
    super.fullscreenDialog = false,
  });

  @override
  Duration get transitionDuration => kPushDuration;

  @override
  Duration get reverseTransitionDuration => kPopDuration;

  @override
  bool get opaque => true;

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      delegatedTransitionBuilder;

  static AnimationController? _controllerOf<R>(PageRoute<R> route) {
    // ignore: invalid_use_of_protected_member
    return route.controller;
  }

  /// Delegated secondary transition applied to the covered underlying route
  /// when a [SwipeBackPageRoute] or [MaterialPageRoute] is pushed above it.
  static Widget? delegatedTransitionBuilder(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    bool allowSnapshotting,
    Widget? child,
  ) {
    if (child == null) return null;
    return _TelegramSecondaryParallaxTransition(
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }

  /// Wraps [child] with secondary `-0.28` parallax + top-mounted dimming scrim
  /// (used by desktop transition builders when `secondaryAnimation` is active).
  static Widget buildSecondaryParallax({
    required Animation<double> secondaryAnimation,
    required Widget child,
  }) {
    return _TelegramSecondaryParallaxTransition(
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }

  /// Wraps a route's content in the interactive swipe-back + trackpad detector
  /// so custom/desktop [PageTransitionsBuilder]s also support swipe-back.
  static Widget wrapWithSwipeBackDetector<R>({
    required PageRoute<R> route,
    required Animation<double> animation,
    required Widget child,
  }) {
    return _SwipeBackGestureDetector(
      route: route,
      animationController: _controllerOf<R>(route),
      animation: animation,
      child: child,
    );
  }

  /// Shared primary + secondary + interactive swipe-back transition tree used
  /// by both [SwipeBackPageRoute] and [TelegramSwipeBackPageTransitionsBuilder].
  static Widget buildSharedTransitions<R>({
    required PageRoute<R> route,
    required BuildContext context,
    required Animation<double> animation,
    required Animation<double> secondaryAnimation,
    required Widget child,
  }) {
    return _TelegramPrimaryRouteTransition<R>(
      route: route,
      animationController: _controllerOf<R>(route),
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return buildSharedTransitions<T>(
      route: this,
      context: context,
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      child: child,
    );
  }
}

class _TelegramPrimaryRouteTransition<T> extends StatefulWidget {
  final PageRoute<T> route;
  final AnimationController? animationController;
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  const _TelegramPrimaryRouteTransition({
    super.key,
    required this.route,
    required this.animationController,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  @override
  State<_TelegramPrimaryRouteTransition<T>> createState() =>
      _TelegramPrimaryRouteTransitionState<T>();
}

class _TelegramPrimaryRouteTransitionState<T>
    extends State<_TelegramPrimaryRouteTransition<T>> {
  static final ValueNotifier<bool> _kIdleGestureNotifier =
      ValueNotifier<bool>(false);
  static final Tween<Offset> _kPrimarySlideTween = Tween<Offset>(
    begin: const Offset(1.0, 0.0),
    end: Offset.zero,
  );

  CurvedAnimation? _curvedPrimary;
  late Animation<Offset> _curvedPrimarySlide;
  late Animation<Offset> _linearPrimarySlide;

  @override
  void initState() {
    super.initState();
    _bindPrimaryAnimation();
  }

  @override
  void didUpdateWidget(covariant _TelegramPrimaryRouteTransition<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.animation, widget.animation)) {
      _curvedPrimary?.dispose();
      _bindPrimaryAnimation();
    }
  }

  void _bindPrimaryAnimation() {
    _curvedPrimary = CurvedAnimation(
      parent: widget.animation,
      curve: SwipeBackPageRoute.kPushCurve,
      reverseCurve: SwipeBackPageRoute.kPopCurve,
    );
    _curvedPrimarySlide = _kPrimarySlideTween.animate(_curvedPrimary!);
    _linearPrimarySlide = _kPrimarySlideTween.animate(widget.animation);
  }

  @override
  void dispose() {
    _curvedPrimary?.dispose();
    _curvedPrimary = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navigator = widget.route.navigator ?? Navigator.maybeOf(context);
    final gestureNotifier =
        navigator?.userGestureInProgressNotifier ?? _kIdleGestureNotifier;
    final settleNotifier = _NavigatorLinearSwipeTracker.notifierFor(navigator);
    final mergedListenable =
        Listenable.merge(<Listenable>[gestureNotifier, settleNotifier]);

    final Widget innerContent = Stack(
      fit: StackFit.passthrough,
      clipBehavior: Clip.none,
      children: [
        AnimatedBuilder(
          animation: widget.animation,
          builder: (context, _) {
            final double v = widget.animation.value;
            if (v <= 0.002 || v >= 0.998) {
              return const SizedBox.shrink();
            }
            return Positioned(
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
                        Colors.black.withValues(alpha: 0.14 * v),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
        _SwipeBackGestureDetector(
          route: widget.route,
          animationController: widget.animationController,
          animation: widget.animation,
          child: _TelegramSecondaryParallaxTransition(
            secondaryAnimation: widget.secondaryAnimation,
            child: RepaintBoundary(child: widget.child),
          ),
        ),
      ],
    );

    return ListenableBuilder(
      listenable: mergedListenable,
      builder: (context, child) {
        final bool isInteractive = gestureNotifier.value ||
            settleNotifier.value > 0 ||
            widget.route.popGestureInProgress;
        final Animation<Offset> activeSlide =
            isInteractive ? _linearPrimarySlide : _curvedPrimarySlide;
        return SlideTransition(
          position: activeSlide,
          child: child,
        );
      },
      child: innerContent,
    );
  }
}

/// Secondary parallax (`Offset.zero -> Offset(-0.28, 0.0)`) and top-mounted
/// dimming scrim (`Color(0x47000000)`) that sits **above** [child] as a sibling
/// inside [SlideTransition] (never wrapping [child] in [Opacity] or
/// [FadeTransition], keeping `LiquidGlassLens` 100% safe).
class _TelegramSecondaryParallaxTransition extends StatefulWidget {
  final Animation<double> secondaryAnimation;
  final Widget child;

  const _TelegramSecondaryParallaxTransition({
    required this.secondaryAnimation,
    required this.child,
  });

  @override
  State<_TelegramSecondaryParallaxTransition> createState() =>
      _TelegramSecondaryParallaxTransitionState();
}

class _TelegramSecondaryParallaxTransitionState
    extends State<_TelegramSecondaryParallaxTransition> {
  static final ValueNotifier<bool> _kIdleGestureNotifier =
      ValueNotifier<bool>(false);
  static final Tween<Offset> _kSecondarySlideTween = Tween<Offset>(
    begin: Offset.zero,
    end: SwipeBackPageRoute.kSecondaryParallaxOffset,
  );

  CurvedAnimation? _curvedSecondary;
  late Animation<Offset> _curvedSecondarySlide;
  late Animation<Offset> _linearSecondarySlide;

  @override
  void initState() {
    super.initState();
    _bindSecondaryAnimation();
  }

  @override
  void didUpdateWidget(covariant _TelegramSecondaryParallaxTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.secondaryAnimation, widget.secondaryAnimation)) {
      _curvedSecondary?.dispose();
      _bindSecondaryAnimation();
    }
  }

  void _bindSecondaryAnimation() {
    _curvedSecondary = CurvedAnimation(
      parent: widget.secondaryAnimation,
      curve: SwipeBackPageRoute.kPushCurve,
      reverseCurve: SwipeBackPageRoute.kPopCurve,
    );
    _curvedSecondarySlide = _kSecondarySlideTween.animate(_curvedSecondary!);
    _linearSecondarySlide =
        _kSecondarySlideTween.animate(widget.secondaryAnimation);
  }

  @override
  void dispose() {
    _curvedSecondary?.dispose();
    _curvedSecondary = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final navigator = Navigator.maybeOf(context);
    final gestureNotifier =
        navigator?.userGestureInProgressNotifier ?? _kIdleGestureNotifier;
    final settleNotifier = _NavigatorLinearSwipeTracker.notifierFor(navigator);
    final mergedListenable =
        Listenable.merge(<Listenable>[gestureNotifier, settleNotifier]);

    return ListenableBuilder(
      listenable: mergedListenable,
      builder: (context, child) {
        final bool isLinear =
            gestureNotifier.value || settleNotifier.value > 0;
        final Animation<Offset> activeSlide =
            isLinear ? _linearSecondarySlide : _curvedSecondarySlide;
        final Animation<double> activeDim =
            isLinear ? widget.secondaryAnimation : _curvedSecondary!;

        return SlideTransition(
          position: activeSlide,
          transformHitTests: false,
          child: Stack(
            fit: StackFit.passthrough,
            clipBehavior: Clip.none,
            children: [
              child!,
              AnimatedBuilder(
                animation: activeDim,
                builder: (context, scrimBox) {
                  if (activeDim.value <= 0.001) {
                    return const SizedBox.shrink();
                  }
                  return IgnorePointer(
                    child: FadeTransition(
                      opacity: activeDim,
                      child: scrimBox,
                    ),
                  );
                },
                child: const ColoredBox(color: SwipeBackPageRoute.kScrimColor),
              ),
            ],
          ),
        );
      },
      child: widget.child,
    );
  }
}

class _SwipeBackTargetMarker extends SingleChildRenderObjectWidget {
  final bool Function() canClaimGetter;

  const _SwipeBackTargetMarker({
    super.key,
    required this.canClaimGetter,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderSwipeBackTargetMarker(canClaimGetter: canClaimGetter);
  }

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderSwipeBackTargetMarker renderObject,
  ) {
    renderObject.canClaimGetter = canClaimGetter;
  }
}

class _RenderSwipeBackTargetMarker extends RenderProxyBox {
  bool Function() canClaimGetter;

  _RenderSwipeBackTargetMarker({required this.canClaimGetter});
}

double _resolveLeftEdgeInset(BuildContext context) {
  final platform = Theme.of(context).platform;
  if (platform == TargetPlatform.android) {
    return math.max(0.0, MediaQuery.systemGestureInsetsOf(context).left);
  }
  return 0.0;
}

/// Детектор свайпа по всей площади экрана с кумулятивным порогом направления.
class _SwipeBackGestureDetector extends StatefulWidget {
  final Widget child;
  final PageRoute<dynamic>? route;
  final AnimationController? animationController;
  final Animation<double> animation;

  const _SwipeBackGestureDetector({
    required this.child,
    this.route,
    required this.animationController,
    required this.animation,
  });

  @override
  State<_SwipeBackGestureDetector> createState() =>
      _SwipeBackGestureDetectorState();
}

class _SwipeBackGestureDetectorState extends State<_SwipeBackGestureDetector> {
  final GlobalKey _markerKey = GlobalKey();
  _BackGestureRecognizer? _recognizer;
  VoidCallback? _endLinearSettle;

  bool _isActive = false;
  bool _isDismissingBySwipe = false;
  bool _didUnfocusOnDrag = false;
  double _dragOffset = 0.0;

  @override
  void dispose() {
    _endLinearSettle?.call();
    _endLinearSettle = null;
    super.dispose();
  }

  double get _screenWidth {
    final w = TileViewportScope.widthOf(context);
    return w > 0 ? w : 1.0;
  }

  ModalRoute<dynamic>? get _effectiveRoute =>
      widget.route ?? ModalRoute.of(context);

  RenderObject? _resolveOwnMarkerRenderObject() =>
      _markerKey.currentContext?.findRenderObject();

  bool _canPop() {
    if (!mounted) return false;
    if (_isActive) return true;
    if (_isDismissingBySwipe) return false;
    if (widget.animationController == null) return false;
    if (TilingLayoutController.instance.isPopTransitionActive) return false;
    final modalRoute = _effectiveRoute;
    if (modalRoute?.isCurrent != true) return false;
    if (!SwipeBackPopScope.isEnabledForRoute(modalRoute)) return false;
    final navigator = modalRoute?.navigator ?? Navigator.maybeOf(context);
    if (navigator == null ||
        !navigator.canPop() ||
        navigator.userGestureInProgress) {
      return false;
    }
    final secAnim = modalRoute?.secondaryAnimation;
    if (secAnim != null &&
        secAnim.status != AnimationStatus.dismissed &&
        secAnim.status != AnimationStatus.reverse) {
      return false;
    }
    if (!widget.animation.isCompleted) return false;
    return true;
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (!_canPop()) return;
    final navigator = _effectiveRoute?.navigator ?? Navigator.of(context);
    _endLinearSettle?.call();
    _endLinearSettle = _NavigatorLinearSwipeTracker.begin(navigator);
    navigator.didStartUserGesture();

    setState(() {
      _isActive = true;
      _didUnfocusOnDrag = false;
      _dragOffset = 0.0;
    });
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isActive) return;

    _dragOffset += details.delta.dx;
    final offset = math.max(0.0, _dragOffset);
    final progress = (offset / _screenWidth).clamp(0.0, 1.0);

    if (!_didUnfocusOnDrag && progress > _kSwipeUnfocusProgress) {
      _didUnfocusOnDrag = true;
      FocusManager.instance.primaryFocus?.unfocus();
    }

    final controller = widget.animationController;
    if (controller != null) {
      controller.value = 1.0 - progress;
    }
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!_isActive) return;

    final controller = widget.animationController;
    final navigator = _effectiveRoute?.navigator ?? Navigator.of(context);
    final modalRoute = _effectiveRoute;
    final settleFinisher = _endLinearSettle;
    _endLinearSettle = null;

    if (controller == null) {
      if (navigator.userGestureInProgress) {
        navigator.didStopUserGesture();
      }
      settleFinisher?.call();
      setState(() => _isActive = false);
      return;
    }

    final progress =
        (math.max(0.0, _dragOffset) / _screenWidth).clamp(0.0, 1.0);
    final velocity = details.primaryVelocity ?? 0.0;

    final shouldPop = (progress >= _kSwipePopProgressThreshold ||
            velocity >= _kSwipeMinFlingVelocity) &&
        velocity > _kSwipeCancelFlingVelocity;

    if (shouldPop) {
      HapticUtils.impact();
      if (!_didUnfocusOnDrag) {
        _didUnfocusOnDrag = true;
        FocusManager.instance.primaryFocus?.unfocus();
      }
      setState(() {
        _isActive = false;
        _isDismissingBySwipe = true;
      });

      final double startValue = controller.value.clamp(0.0, 1.0);
      final double unitVelocity = math.min(0.0, -velocity / _screenWidth);

      // Stop userGestureInProgress immediately so the underlying route is not
      // wrapped in IgnorePointer while `_NavigatorLinearSwipeTracker` keeps
      // both primary and secondary transitions 1:1 linear through spring settle.
      if (navigator.mounted && navigator.userGestureInProgress) {
        navigator.didStopUserGesture();
      }

      void finishDismissState() {
        settleFinisher?.call();
        if (mounted) {
          setState(() => _isDismissingBySwipe = false);
        } else {
          _isDismissingBySwipe = false;
        }
      }

      if (modalRoute?.isCurrent != true) {
        finishDismissState();
        return;
      }

      final customPop = SwipeBackPopScope.popCallbackForRoute(modalRoute);
      if (customPop == null) {
        TilingLayoutController.instance.recordInteractiveSwipePopCompleted();
        navigator.pop();
        if (controller.value > 0.006) {
          controller
              .animateBackWith(
                _SwipeDismissSpringSimulation(
                  start: startValue,
                  velocity: unitVelocity,
                ),
              )
              .whenComplete(finishDismissState);
        } else {
          finishDismissState();
        }
      } else {
        unawaited(
          TilingLayoutController.instance.runInteractiveSwipePop(() async {
            final res = customPop();
            if (res is Future<void>) {
              await res;
            }
            if (modalRoute?.isActive == false) {
              if (controller.value > 0.006) {
                await controller.animateBackWith(
                  _SwipeDismissSpringSimulation(
                    start: startValue,
                    velocity: unitVelocity,
                  ),
                );
              }
              finishDismissState();
            } else if (mounted && modalRoute?.isCurrent == true) {
              // Custom pop handler kept the route active -> spring back cleanly.
              if (mounted) {
                setState(() => _isDismissingBySwipe = false);
              }
              _animateSpringCancel(
                controller,
                navigator,
                0.0,
                onComplete: settleFinisher,
              );
            } else {
              finishDismissState();
            }
          }),
        );
      }
    } else {
      setState(() {
        _isActive = false;
      });
      _animateSpringCancel(
        controller,
        navigator,
        -velocity / _screenWidth,
        onComplete: settleFinisher,
      );
    }
  }

  void _onHorizontalDragCancel() {
    if (!_isActive) return;
    final settleFinisher = _endLinearSettle;
    _endLinearSettle = null;
    setState(() {
      _isActive = false;
    });
    final controller = widget.animationController;
    final navigator = _effectiveRoute?.navigator ?? Navigator.of(context);
    if (controller == null) {
      if (navigator.userGestureInProgress) {
        navigator.didStopUserGesture();
      }
      settleFinisher?.call();
      return;
    }
    _animateSpringCancel(
      controller,
      navigator,
      0.0,
      onComplete: settleFinisher,
    );
  }

  void _animateSpringCancel(
    AnimationController controller,
    NavigatorState navigator,
    double unitVelocity, {
    VoidCallback? onComplete,
  }) {
    bool completed = false;

    void finishCancel() {
      if (completed) return;
      completed = true;
      if (controller.isAnimating) {
        controller.stop();
      }
      if (controller.value != 1.0) {
        controller.value = 1.0;
      }
      if (navigator.mounted && navigator.userGestureInProgress) {
        navigator.didStopUserGesture();
      }
      onComplete?.call();
    }

    if (controller.value >= 0.999) {
      finishCancel();
      return;
    }

    final simulation = SpringSimulation(
      _kSwipeBackSpring,
      controller.value.clamp(0.0, 1.0),
      1.0,
      unitVelocity,
      tolerance: _kSwipeBackSpringTolerance,
    );
    controller.animateWith(simulation).whenComplete(finishCancel);
  }

  @override
  Widget build(BuildContext context) {
    final isInsideTile = TileViewportScope.maybeTileIdOf(context) != null;
    final leftEdgeInset = _resolveLeftEdgeInset(context);

    Widget detector = _SwipeBackTargetMarker(
      key: _markerKey,
      canClaimGetter: _canPop,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerMove: (event) => _recognizer?.preRouteMoveCheck(event),
        child: RawGestureDetector(
          gestures: <Type, GestureRecognizerFactory>{
            _BackGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<_BackGestureRecognizer>(
              () => _BackGestureRecognizer(
                canPopGetter: _canPop,
                leftEdgeInset: leftEdgeInset,
                ownMarkerGetter: _resolveOwnMarkerRenderObject,
              ),
              (_BackGestureRecognizer instance) {
                _recognizer = instance;
                instance.canPopGetter = _canPop;
                instance.leftEdgeInset = leftEdgeInset;
                instance.ownMarkerGetter = _resolveOwnMarkerRenderObject;
                instance.onStart = _onHorizontalDragStart;
                instance.onUpdate = _onHorizontalDragUpdate;
                instance.onEnd = _onHorizontalDragEnd;
                instance.onCancel = _onHorizontalDragCancel;
              },
            ),
          },
          behavior: HitTestBehavior.translucent,
          child: IgnorePointer(
            ignoring: _isDismissingBySwipe,
            child: widget.child,
          ),
        ),
      ),
    );

    if (!isInsideTile) {
      detector = TrackpadBackGestureWrapper(
        canTriggerBack: _canPop,
        onTriggerBack: () {
          if (_canPop()) {
            final modalRoute = _effectiveRoute;
            final customPop = SwipeBackPopScope.popCallbackForRoute(modalRoute);
            if (customPop != null) {
              customPop();
            } else {
              Navigator.of(context).maybePop();
            }
          }
        },
        child: detector,
      );
    }

    return detector;
  }
}

/// Переиспользуемый детектор интерактивного свайпа назад (`1:1` с пальцем +
/// критически демпфированная пружина), используемый для закрытия тайлов чатов
/// и встроенных вкладок `MainScreen`.
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
  final GlobalKey _markerKey = GlobalKey();
  _BackGestureRecognizer? _recognizer;

  bool _isActive = false;
  bool _isDismissing = false;
  bool _didUnfocusOnDrag = false;
  double _dragOffset = 0.0;

  Size get _effectiveSize =>
      widget.viewportSizeOverride ?? TileViewportScope.sizeOf(context);

  double get _screenWidth {
    final w = _effectiveSize.width;
    return w > 0 ? w : 1.0;
  }

  RenderObject? _resolveOwnMarkerRenderObject() =>
      _markerKey.currentContext?.findRenderObject();

  bool _canSwipe() {
    if (!mounted) return false;
    if (_isActive) return true;
    if (_isDismissing) return false;
    return widget.canSwipeBack();
  }

  void _onHorizontalDragStart(DragStartDetails details) {
    if (!_canSwipe()) return;
    _isActive = true;
    _didUnfocusOnDrag = false;
    _dragOffset = 0.0;
    widget.onDragStart?.call();
  }

  void _onHorizontalDragUpdate(DragUpdateDetails details) {
    if (!_isActive) return;

    _dragOffset += details.delta.dx;
    final offset = math.max(0.0, _dragOffset);
    final progress = (offset / _screenWidth).clamp(0.0, 1.0);

    if (!_didUnfocusOnDrag && progress > _kSwipeUnfocusProgress) {
      _didUnfocusOnDrag = true;
      FocusManager.instance.primaryFocus?.unfocus();
    }

    widget.animationController.value = 1.0 - progress;
  }

  void _onHorizontalDragEnd(DragEndDetails details) {
    if (!_isActive) return;
    _isActive = false;

    final progress =
        (math.max(0.0, _dragOffset) / _screenWidth).clamp(0.0, 1.0);
    final velocity = details.primaryVelocity ?? 0.0;

    final shouldDismiss = (progress >= _kSwipePopProgressThreshold ||
            velocity >= _kSwipeMinFlingVelocity) &&
        velocity > _kSwipeCancelFlingVelocity;

    final controller = widget.animationController;

    if (shouldDismiss) {
      HapticUtils.impact();
      if (!_didUnfocusOnDrag) {
        _didUnfocusOnDrag = true;
        FocusManager.instance.primaryFocus?.unfocus();
      }
      setState(() => _isDismissing = true);

      final double startValue = controller.value.clamp(0.0, 1.0);
      final double unitVelocity = math.min(0.0, -velocity / _screenWidth);

      void finalize() {
        if (controller.isAnimating) {
          controller.stop();
        }
        if (controller.value != 0.0) {
          controller.value = 0.0;
        }
        if (mounted) {
          setState(() => _isDismissing = false);
          TilingLayoutController.instance.recordInteractiveSwipePopCompleted();
          widget.onDismissed();
        } else {
          _isDismissing = false;
        }
      }

      if (startValue <= 0.006) {
        finalize();
        return;
      }

      controller
          .animateBackWith(
            _SwipeDismissSpringSimulation(
              start: startValue,
              velocity: unitVelocity,
            ),
          )
          .whenComplete(finalize);
    } else {
      final simulation = SpringSimulation(
        _kSwipeBackSpring,
        controller.value.clamp(0.0, 1.0),
        1.0,
        -velocity / _screenWidth,
        tolerance: _kSwipeBackSpringTolerance,
      );
      controller.animateWith(simulation).whenComplete(() {
        if (controller.value != 1.0) {
          controller.value = 1.0;
        }
        if (mounted) {
          widget.onRestored?.call();
        }
      });
    }
  }

  void _onHorizontalDragCancel() {
    if (!_isActive) return;
    _isActive = false;

    final controller = widget.animationController;
    final simulation = SpringSimulation(
      _kSwipeBackSpring,
      controller.value.clamp(0.0, 1.0),
      1.0,
      0.0,
      tolerance: _kSwipeBackSpringTolerance,
    );
    controller.animateWith(simulation).whenComplete(() {
      if (controller.value != 1.0) {
        controller.value = 1.0;
      }
      if (mounted) {
        widget.onRestored?.call();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final leftEdgeInset = _resolveLeftEdgeInset(context);

    return _SwipeBackTargetMarker(
      key: _markerKey,
      canClaimGetter: _canSwipe,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerMove: (event) => _recognizer?.preRouteMoveCheck(event),
        child: RawGestureDetector(
          gestures: <Type, GestureRecognizerFactory>{
            _BackGestureRecognizer:
                GestureRecognizerFactoryWithHandlers<_BackGestureRecognizer>(
              () => _BackGestureRecognizer(
                canPopGetter: _canSwipe,
                leftEdgeInset: leftEdgeInset,
                ownMarkerGetter: _resolveOwnMarkerRenderObject,
              ),
              (_BackGestureRecognizer instance) {
                _recognizer = instance;
                instance.canPopGetter = _canSwipe;
                instance.leftEdgeInset = leftEdgeInset;
                instance.ownMarkerGetter = _resolveOwnMarkerRenderObject;
                instance.onStart = _onHorizontalDragStart;
                instance.onUpdate = _onHorizontalDragUpdate;
                instance.onEnd = _onHorizontalDragEnd;
                instance.onCancel = _onHorizontalDragCancel;
              },
            ),
          },
          behavior: HitTestBehavior.translucent,
          child: IgnorePointer(
            ignoring: _isDismissing,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}

/// Распознаватель полноэкранного свайпа назад (паритет с Telegram `ActionBarLayout`).
///
/// - Накапливает кумулятивное смещение `(_cumDx, _cumDy)` от точки касания без
///   ложных срабатываний на квантованном шуме 120–240Hz экранов.
/// - Проверяет под точкой касания горизонтальные `RenderViewportBase` (`PageView`,
///   `TabBarView`, горизонтальные `ListView`), `Slider` и [SwipeBackBlocker]:
///   уступает арену, если вьюпорт может скроллиться влево (`pixels > minScrollExtent + 0.5`),
///   и бесшовно перехватывает свайп назад на левом краю (`page == 0` / `offset == 0`).
class _BackGestureRecognizer extends HorizontalDragGestureRecognizer {
  bool Function() canPopGetter;
  double leftEdgeInset;
  RenderObject? Function()? ownMarkerGetter;

  int? _trackedPointer;
  Offset _downGlobalPos = Offset.zero;
  double _cumDx = 0.0;
  double _cumDy = 0.0;
  bool _directionAccepted = false;
  bool _directionRejected = false;

  _BackGestureRecognizer({
    required this.canPopGetter,
    this.leftEdgeInset = 0.0,
    this.ownMarkerGetter,
  }) {
    onlyAcceptDragOnThreshold = true;
  }

  bool _isAllowedDeviceKind(PointerDeviceKind kind) {
    // Only allow touch and stylus for 1:1 finger slide-back.
    // On desktop, mouse drags must NOT trigger slide-back (prevents text selection / accidental pops),
    // and trackpad two-finger swipe is handled by TrackpadBackGestureWrapper.
    return kind == PointerDeviceKind.touch ||
        kind == PointerDeviceKind.stylus ||
        kind == PointerDeviceKind.invertedStylus;
  }

  bool _canHorizontalViewportScrollOnRightDrag(RenderViewportBase viewport) {
    final offset = viewport.offset;
    if (!offset.hasPixels) return false;
    if (offset is ScrollMetrics) {
      final ScrollMetrics metrics = offset as ScrollMetrics;
      if (!metrics.hasContentDimensions) {
        return offset.pixels > 0.5;
      }
      if (viewport.axisDirection == AxisDirection.left) {
        return offset.pixels < metrics.maxScrollExtent - 0.5;
      }
      return offset.pixels > metrics.minScrollExtent + 0.5;
    }
    return offset.pixels > 0.5;
  }

  RenderViewportBase? _findHorizontalViewportUnderHandler(
    RenderObject root,
    Offset globalPosition, [
    int depth = 0,
  ]) {
    if (depth > 8) return null;
    if (root is RenderViewportBase) {
      if (root.axis != Axis.horizontal || !root.hasSize) return null;
      final local = root.globalToLocal(globalPosition);
      if (!(Offset.zero & root.size).contains(local)) return null;
      return root;
    }
    RenderObject? onlyChild;
    int childCount = 0;
    root.visitChildren((child) {
      childCount++;
      onlyChild ??= child;
    });
    if (childCount == 1 && onlyChild != null) {
      return _findHorizontalViewportUnderHandler(
        onlyChild!,
        globalPosition,
        depth + 1,
      );
    }
    return null;
  }

  bool _hasHorizontalBlockerAt(Offset globalPosition, int viewId) {
    final hitResult = HitTestResult();
    WidgetsBinding.instance.hitTestInView(hitResult, globalPosition, viewId);
    final ownMarker = ownMarkerGetter?.call();

    for (final entry in hitResult.path) {
      final target = entry.target;
      if (ownMarker != null && identical(target, ownMarker)) {
        // Stop once we reach our own detector boundary so ancestor viewports
        // outside this route/navigator never block inner route swipe-back.
        break;
      }
      if (target is _RenderSwipeBackTargetMarker && target.canClaimGetter()) {
        // Yield to a deeper nested active swipe-back detector.
        return true;
      }
      if (target is RenderSwipeBackBlocker && target.enabled) {
        return true;
      }
      if (target is RenderBox) {
        final typeName = target.runtimeType.toString();
        if (typeName.contains('Slider')) {
          return true;
        }
      }
      if (target is RenderViewportBase && target.axis == Axis.horizontal) {
        if (_canHorizontalViewportScrollOnRightDrag(target)) {
          return true;
        }
      }
      if (target is RenderSemanticsGestureHandler) {
        // Scrollable's RawGestureDetector sits outside RenderViewportBase and
        // hits even over transparent/empty space inside PageView / TabBarView.
        final viewport = _findHorizontalViewportUnderHandler(
          target,
          globalPosition,
        );
        if (viewport != null &&
            _canHorizontalViewportScrollOnRightDrag(viewport)) {
          return true;
        }
      }
    }
    return false;
  }

  @override
  bool isPointerAllowed(PointerEvent event) {
    if (!canPopGetter()) return false;
    if (!_isAllowedDeviceKind(event.kind)) return false;
    if (leftEdgeInset > 0 && event.position.dx < leftEdgeInset) {
      return false;
    }
    if (event is PointerDownEvent &&
        _hasHorizontalBlockerAt(event.position, event.viewId)) {
      return false;
    }
    return super.isPointerAllowed(event);
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _trackedPointer = event.pointer;
    _downGlobalPos = event.position;
    _cumDx = 0.0;
    _cumDy = 0.0;
    _directionAccepted = false;
    _directionRejected = false;
    super.addAllowedPointer(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) {
    return _cumDx >= 14.0 && _cumDx > _cumDy.abs() * 2.2;
  }

  void _evaluateCumulativeMove(PointerMoveEvent event) {
    _cumDx = event.position.dx - _downGlobalPos.dx;
    _cumDy = event.position.dy - _downGlobalPos.dy;

    // Reject early only when cumulative displacement clearly moves leftward
    // (e.g. SwipeToReply) or predominantly vertically (vertical scroll).
    if (_cumDx < -8.0 ||
        (_cumDy.abs() > 14.0 && _cumDy.abs() > math.max(0.0, _cumDx) * 0.65)) {
      _directionRejected = true;
      _trackedPointer = null;
      resolve(GestureDisposition.rejected);
      stopTrackingPointer(event.pointer);
      return;
    }

    // Proactively win the gesture arena once cumulative rightward motion
    // reaches 14px inside a ~24.4° horizontal cone.
    if (_cumDx >= 14.0 && _cumDx > _cumDy.abs() * 2.2) {
      _directionAccepted = true;
      resolve(GestureDisposition.accepted);
    }
  }

  /// Runs from an enclosing [Listener.onPointerMove] before [GestureBinding]
  /// dispatches to [PointerRouter], ensuring `_BackGestureRecognizer` beats an
  /// inner `PageView` at `page == 0` even on large single-frame move deltas.
  void preRouteMoveCheck(PointerMoveEvent event) {
    if (event.pointer != _trackedPointer ||
        _directionAccepted ||
        _directionRejected) {
      return;
    }
    if (!_isAllowedDeviceKind(event.kind)) return;
    _evaluateCumulativeMove(event);
  }

  @override
  void rejectGesture(int pointer) {
    if (pointer == _trackedPointer) {
      _directionRejected = true;
      _trackedPointer = null;
    }
    super.rejectGesture(pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event.pointer == _trackedPointer &&
        !_directionAccepted &&
        !_directionRejected &&
        event is PointerMoveEvent) {
      _evaluateCumulativeMove(event);
      if (_directionRejected) {
        return;
      }
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (event.pointer == _trackedPointer) {
        _trackedPointer = null;
      }
    }
    super.handleEvent(event);
  }
}
