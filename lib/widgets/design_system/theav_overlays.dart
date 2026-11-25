import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../utils/blur_utils.dart';
import '../../utils/haptic_utils.dart';
import 'theav_design_system.dart';

/// Marks subtrees inside [TheavSheetSurface] / [TheavModalSheet] so nested
/// HUD pills never mount a [BackdropFilter] during sheet drag/slide transitions.
class TheavModalSheetScope extends InheritedWidget {
  const TheavModalSheetScope({super.key, required super.child});

  static bool isActive(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TheavModalSheetScope>() !=
        null;
  }

  @override
  bool updateShouldNotify(TheavModalSheetScope oldWidget) => false;
}

/// Transition choreography used when presenting a [showTheavModalSheet] route.
enum TheavSheetTransitionStyle {
  slideFromBottom,
  zoomFromSwitcher,
}

/// Opens a dual-mode [TheavModalSheet] that can be stretched or dismissed via its
/// top handle bar while rendering a real [LiquidGlassLens] surface in
/// `full`/`lite` modes and a crisp Material 3 surface when disabled.
Future<T?> showTheavModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  WidgetBuilder? customSheetBuilder,
  String? title,
  Widget? trailing,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 10, 16, 20),
  bool isScrollControlled = true,
  bool enableDrag = true,
  bool showCloseButton = false,
  double maxHeightFactor = 0.92,
  bool barrierDismissible = true,
  bool useRootNavigator = false,
  TheavSheetTransitionStyle transitionStyle =
      TheavSheetTransitionStyle.slideFromBottom,
}) {
  final NavigatorState navigator =
      Navigator.of(context, rootNavigator: useRootNavigator);
  final bool forceMatte = TheavMatteScope.isActive(context, listen: false);
  final CapturedThemes capturedThemes = InheritedTheme.capture(
    from: context,
    to: navigator.context,
  );
  return navigator.push<T>(
    _TheavModalSheetRoute<T>(
      builder: builder,
      customSheetBuilder: customSheetBuilder,
      capturedThemes: capturedThemes,
      forceMatte: forceMatte,
      title: title,
      trailing: trailing,
      padding: padding,
      enableDrag: enableDrag,
      showCloseButton: showCloseButton,
      maxHeightFactor: maxHeightFactor,
      barrierDismissible: barrierDismissible,
      barrierLabel: Localizations.of<MaterialLocalizations>(
            context,
            MaterialLocalizations,
          )?.modalBarrierDismissLabel ??
          'Dismiss',
      transitionStyle: transitionStyle,
    ),
  );
}

class _SheetVerticalOffset extends SingleChildRenderObjectWidget {
  final double offsetY;

  const _SheetVerticalOffset({
    required this.offsetY,
    required super.child,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderSheetVerticalOffset(offsetY);

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderSheetVerticalOffset renderObject,
  ) {
    renderObject.offsetY = offsetY;
  }
}

class _RenderSheetVerticalOffset extends RenderProxyBox {
  _RenderSheetVerticalOffset(this._offsetY);

  final LayerHandle<TransformLayer> _transformHandle =
      LayerHandle<TransformLayer>();

  double _offsetY;
  double get offsetY => _offsetY;
  set offsetY(double value) {
    if ((_offsetY - value).abs() < 0.001) return;
    _offsetY = value;
    markNeedsPaint();
  }

  @override
  bool get alwaysNeedsCompositing => _offsetY.abs() > 0.01;

  @override
  void paint(PaintingContext context, Offset offset) {
    if (_offsetY.abs() <= 0.01) {
      _transformHandle.layer = null;
      super.paint(context, offset);
      return;
    }
    _transformHandle.layer = context.pushTransform(
      needsCompositing,
      offset,
      Matrix4.translationValues(0.0, _offsetY, 0.0),
      super.paint,
      oldLayer: _transformHandle.layer,
    );
  }

  @override
  void applyPaintTransform(RenderObject child, Matrix4 transform) {
    if (_offsetY.abs() > 0.01) {
      transform.translateByDouble(0.0, _offsetY, 0.0, 1.0);
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    if (_offsetY.abs() <= 0.01) {
      return super.hitTestChildren(result, position: position);
    }
    return result.addWithPaintOffset(
      offset: Offset(0.0, _offsetY),
      position: position,
      hitTest: (BoxHitTestResult r, Offset p) =>
          super.hitTestChildren(r, position: p),
    );
  }

  @override
  void dispose() {
    _transformHandle.layer = null;
    super.dispose();
  }
}

class _TheavModalSheetRouteScope extends InheritedWidget {
  final _TheavModalSheetRoute<dynamic> route;

  const _TheavModalSheetRouteScope({
    required this.route,
    required super.child,
  });

  static _TheavModalSheetRoute<dynamic>? maybeRouteOf(BuildContext context) {
    if (!context.mounted) return null;
    return context
        .getInheritedWidgetOfExactType<_TheavModalSheetRouteScope>()
        ?.route;
  }

  @override
  bool updateShouldNotify(_TheavModalSheetRouteScope oldWidget) =>
      !identical(route, oldWidget.route);
}

/// Performance helper allowing edge-to-edge custom routes (e.g. WebView sheets)
/// to toggle overlay opaque culling while resting so Flutter skips painting
/// underlying routes behind the full-screen surface, and to hand off active
/// downward drag offsets/velocities cleanly into route dismissal.
abstract final class TheavSheetRoutePerfControl {
  static void setRestingOpaque(BuildContext context, bool opaque) {
    _TheavModalSheetRouteScope.maybeRouteOf(context)?.setRestingOpaque(opaque);
  }

  static bool prepareDragDismiss(
    BuildContext context, {
    required double dragOffsetPx,
    required double sheetHeight,
    required double velocityPxPerSec,
  }) {
    final route = _TheavModalSheetRouteScope.maybeRouteOf(context);
    if (route != null) {
      return route.prepareDragDismiss(
        dragOffsetPx: dragOffsetPx,
        sheetHeight: sheetHeight,
        velocityPxPerSec: velocityPxPerSec,
      );
    }
    return false;
  }

  /// Disables the route's default downward slide pop animation so opening
  /// the 3D tabs switcher hands off cleanly to its zoom-out cascade without
  /// dragging the live WebView sheet downward first.
  static bool prepareInstantSwitcherDismiss(BuildContext context) {
    final route = _TheavModalSheetRouteScope.maybeRouteOf(context);
    if (route != null) {
      return route.prepareInstantSwitcherDismiss();
    }
    return false;
  }
}

class _TheavModalSheetRoute<T> extends PopupRoute<T> {
  static const Cubic _kSheetEnterCurve = Cubic(0.32, 0.72, 0.0, 1.0);
  static const Cubic _kSheetExitCurve = Cubic(0.24, 0.84, 0.36, 1.0);
  static const Cubic _kSwitcherZoomEnterCurve = Cubic(0.22, 1.0, 0.36, 1.0);

  final WidgetBuilder builder;
  final WidgetBuilder? customSheetBuilder;
  final CapturedThemes capturedThemes;
  final bool forceMatte;
  final String? title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final bool enableDrag;
  final bool showCloseButton;
  final double maxHeightFactor;
  final TheavSheetTransitionStyle transitionStyle;
  @override
  final bool barrierDismissible;
  @override
  final String? barrierLabel;

  bool _restingOpaque = false;
  bool _overlaySyncScheduled = false;
  bool _isDisposed = false;
  bool _dismissingFromDrag = false;
  bool _instantSwitcherDismiss = false;
  double _dragDismissUnitVelocity = 2.6;
  double _dragDismissStartProgress = 1.0;
  double _dragDismissStartOffsetPx = 0.0;
  CurvedAnimation? _curvedAnimation;
  Animation<double>? _curvedParent;

  _TheavModalSheetRoute({
    required this.builder,
    this.customSheetBuilder,
    required this.capturedThemes,
    this.forceMatte = false,
    this.title,
    this.trailing,
    required this.padding,
    required this.enableDrag,
    required this.showCloseButton,
    required this.maxHeightFactor,
    required this.barrierDismissible,
    required this.barrierLabel,
    this.transitionStyle = TheavSheetTransitionStyle.slideFromBottom,
  });

  CurvedAnimation _obtainCurvedAnimation(Animation<double> parent) {
    if (_curvedAnimation != null && identical(_curvedParent, parent)) {
      return _curvedAnimation!;
    }
    _curvedAnimation?.dispose();
    _curvedParent = parent;
    _curvedAnimation = CurvedAnimation(
      parent: parent,
      curve: transitionStyle == TheavSheetTransitionStyle.zoomFromSwitcher
          ? _kSwitcherZoomEnterCurve
          : _kSheetEnterCurve,
      reverseCurve: _kSheetExitCurve,
    );
    return _curvedAnimation!;
  }

  bool prepareInstantSwitcherDismiss() {
    final ctrl = controller;
    if (_isDisposed || ctrl == null) {
      return false;
    }
    _instantSwitcherDismiss = true;
    _dismissingFromDrag = false;
    ctrl.reverseDuration = Duration.zero;
    setRestingOpaque(false);
    return true;
  }

  bool prepareDragDismiss({
    required double dragOffsetPx,
    required double sheetHeight,
    required double velocityPxPerSec,
  }) {
    final ctrl = controller;
    if (_isDisposed ||
        ctrl == null ||
        sheetHeight <= 1.0 ||
        dragOffsetPx <= 0.5) {
      return false;
    }
    final double startVal =
        (1.0 - (dragOffsetPx / sheetHeight)).clamp(0.01, 1.0);
    _dismissingFromDrag = true;
    _dragDismissStartProgress = startVal;
    _dragDismissStartOffsetPx = dragOffsetPx;
    _dragDismissUnitVelocity =
        (velocityPxPerSec / sheetHeight).clamp(2.2, 8.5);
    ctrl.value = startVal;
    return true;
  }

  void setRestingOpaque(bool value) {
    if (_isDisposed || _restingOpaque == value) return;
    _restingOpaque = value;
    _scheduleOrSyncOverlayOpaque();
  }

  void _handleRouteStatusChanged(AnimationStatus status) {
    if (_isDisposed) return;
    if (status == AnimationStatus.completed) {
      _dismissingFromDrag = false;
    }
    if (!_restingOpaque) return;
    _scheduleOrSyncOverlayOpaque();
  }

  void _scheduleOrSyncOverlayOpaque() {
    if (_isDisposed || navigator == null) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      if (_overlaySyncScheduled) return;
      _overlaySyncScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _overlaySyncScheduled = false;
        if (!_isDisposed && navigator != null) {
          _syncOverlayOpaque();
        }
      });
      return;
    }
    _syncOverlayOpaque();
  }

  void _syncOverlayOpaque() {
    if (_isDisposed || overlayEntries.isEmpty) return;
    final bool shouldBeOpaque =
        _restingOpaque && animation?.status == AnimationStatus.completed;
    overlayEntries.first.opaque = false;
    overlayEntries.last.opaque = shouldBeOpaque;
  }

  @override
  void install() {
    super.install();
    animation?.addStatusListener(_handleRouteStatusChanged);
  }

  @override
  Simulation? createSimulation({required bool forward}) {
    final ctrl = controller;
    if (!forward && _dismissingFromDrag && ctrl != null) {
      return SpringSimulation(
        SpringDescription.withDampingRatio(
          mass: 1.0,
          stiffness: 420.0,
          ratio: 1.0,
        ),
        ctrl.value,
        -0.001,
        -_dragDismissUnitVelocity,
        tolerance: const Tolerance(velocity: 0.01, distance: 0.001),
      );
    }
    return super.createSimulation(forward: forward);
  }

  @override
  void dispose() {
    _isDisposed = true;
    animation?.removeStatusListener(_handleRouteStatusChanged);
    _curvedAnimation?.dispose();
    _curvedAnimation = null;
    _curvedParent = null;
    super.dispose();
  }

  @override
  Color? get barrierColor => Colors.black54;

  @override
  bool get opaque =>
      _restingOpaque && animation?.status == AnimationStatus.completed;

  @override
  Duration get transitionDuration =>
      transitionStyle == TheavSheetTransitionStyle.zoomFromSwitcher
          ? const Duration(milliseconds: 240)
          : const Duration(milliseconds: 280);

  @override
  Duration get reverseTransitionDuration => _instantSwitcherDismiss
      ? Duration.zero
      : const Duration(milliseconds: 220);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final Widget page = customSheetBuilder != null
        ? customSheetBuilder!(context)
        : TheavModalSheet(
            title: title,
            trailing: trailing,
            padding: padding,
            showCloseButton: showCloseButton,
            maxHeightFactor: maxHeightFactor,
            enableDrag: enableDrag,
            child: Builder(builder: builder),
          );
    final Widget scopedPage =
        forceMatte ? TheavMatteScope(child: page) : page;
    return _TheavModalSheetRouteScope(
      route: this,
      child: capturedThemes.wrap(scopedPage),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnim) {
      return Align(
        alignment: Alignment.bottomCenter,
        child: SizedBox(width: double.infinity, child: child),
      );
    }

    final curved = _obtainCurvedAnimation(animation);
    return Align(
      alignment: Alignment.bottomCenter,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, innerChild) {
          if (_dismissingFromDrag) {
            final double curHeight = MediaQuery.sizeOf(context).height;
            final double denom = math.max(0.01, _dragDismissStartProgress);
            final double ratio = (animation.value / denom).clamp(0.0, 1.0);
            final double offsetPx =
                curHeight + (_dragDismissStartOffsetPx - curHeight) * ratio;
            return _SheetVerticalOffset(
              offsetY: offsetPx,
              child: innerChild!,
            );
          }
          if (_instantSwitcherDismiss) {
            return animation.value <= 0.001
                ? const SizedBox.shrink()
                : innerChild!;
          }
          if (transitionStyle == TheavSheetTransitionStyle.zoomFromSwitcher &&
              (animation.status == AnimationStatus.forward ||
                  animation.status == AnimationStatus.completed)) {
            final double progress = curved.value.clamp(0.0, 1.0);
            if (progress >= 0.9999) {
              return innerChild!;
            }
            final double scale = 0.94 + 0.06 * progress;
            final double dy = (1.0 - progress) * 22.0;
            return Transform.translate(
              offset: Offset(0.0, dy),
              child: Transform.scale(
                scale: scale,
                alignment: Alignment.center,
                child: innerChild,
              ),
            );
          }
          final double progress = curved.value.clamp(0.0, 1.0);
          return FractionalTranslation(
            translation: Offset(0.0, 1.0 - progress),
            transformHitTests: true,
            child: innerChild,
          );
        },
        child: SizedBox(width: double.infinity, child: child),
      ),
    );
  }
}

/// Dual-mode bottom sheet surface rendering a real [LiquidGlassLens] in
/// `full`/`lite` modes (with library-native [LiquidGlassFlexDeform] stretch)
/// and a crisp Material 3 surface when glass is disabled.
///
/// Never wraps [LiquidGlassLens] in `Opacity`, `FadeTransition`, `ClipRRect`,
/// or `BackdropFilter`, and disables Android stretch overscroll so the lens
/// shader never turns black or shifts.
class TheavSheetSurface extends StatelessWidget {
  final Widget child;
  final double cornerRadius;
  final double stretchPx;
  final double maxStretch;
  final BoxConstraints? constraints;
  final Color? matteColor;
  final Color? glassTintOverride;
  final bool disableOverscrollStretch;
  final bool attachedToBottom;

  const TheavSheetSurface({
    super.key,
    required this.child,
    this.cornerRadius = 24.0,
    this.stretchPx = 0.0,
    this.maxStretch = 40.0,
    this.constraints,
    this.matteColor,
    this.glassTintOverride,
    this.disableOverscrollStretch = true,
    this.attachedToBottom = true,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final Widget materialChild = Material(
      type: MaterialType.transparency,
      child: child,
    );
    final Widget wrappedChild = TheavModalSheetScope(
      child: disableOverscrollStretch
          ? ScrollConfiguration(
              behavior:
                  const MaterialScrollBehavior().copyWith(overscroll: false),
              child: materialChild,
            )
          : materialChild,
    );

    if (style.isGlass && style.glassProvider != null) {
      final Color glassTint = glassTintOverride ??
          (style.isDark
              ? style.palette.surface.withValues(alpha: 0.56)
              : style.palette.surface.withValues(alpha: 0.72));
      final glassStyle = style.glassProvider!.createStyle(
        context: context,
        cornerRadius: cornerRadius,
        color: glassTint,
        refractionIndex: 1.06,
        refractionWidth: 16.0,
        borderWidth: 1.15,
      );
      final double clampedStretch = stretchPx.clamp(0.0, maxStretch);
      final double pressProgress =
          (clampedStretch / math.max(1.0, maxStretch)).clamp(0.0, 1.0);

      return Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: 0.0,
            right: 0.0,
            top: 0.0,
            bottom: attachedToBottom ? -cornerRadius : 0.0,
            child: LayoutBuilder(
              builder: (context, box) {
                final Size deformedSize = box.biggest;
                if (!deformedSize.width.isFinite ||
                    !deformedSize.height.isFinite ||
                    deformedSize.isEmpty) {
                  return LiquidGlassLens(
                    style: glassStyle,
                    child: const SizedBox.expand(),
                  );
                }
                final double restHeight =
                    math.max(1.0, deformedSize.height - clampedStretch);
                final Size restSize = Size(deformedSize.width, restHeight);
                final LiquidGlassFlexDeform deform = clampedStretch > 0.01
                    ? LiquidGlassFlexDeform(
                        left: 0.0,
                        right: 0.0,
                        top: clampedStretch,
                        bottom: 0.0,
                        childScaleX: 1.0,
                        childScaleY: 1.0,
                        childTranslateX: 0.0,
                        childTranslateY: 0.0,
                        pressAmount: pressProgress * 0.45,
                      )
                    : LiquidGlassFlexDeform.none;

                return LiquidGlassLens(
                  style: glassStyle,
                  deform: deform,
                  restSize: restSize,
                  child: const SizedBox.expand(),
                );
              },
            ),
          ),
          Container(
            constraints: constraints,
            width: double.infinity,
            child: wrappedChild,
          ),
        ],
      );
    }

    return Container(
      constraints: constraints,
      width: double.infinity,
      decoration: BoxDecoration(
        color: matteColor ?? style.overlayFill,
        borderRadius: attachedToBottom
            ? BorderRadius.vertical(top: Radius.circular(cornerRadius))
            : BorderRadius.circular(cornerRadius),
        border: Border.all(
          color: style.hairlineBorder,
          width: 0.5,
        ),
        boxShadow: style.floatingShadow,
      ),
      clipBehavior: Clip.antiAlias,
      child: wrappedChild,
    );
  }
}

/// Dual-mode modal bottom sheet container with handle-only drag/stretch,
/// optional header bar, safe keyboard inset handling, and [TheavPalette]
/// styling.
class TheavModalSheet extends StatefulWidget {
  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final bool showCloseButton;
  final double maxHeightFactor;
  final bool enableDrag;

  const TheavModalSheet({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 20),
    this.showCloseButton = false,
    this.maxHeightFactor = 0.92,
    this.enableDrag = true,
  });

  @override
  State<TheavModalSheet> createState() => _TheavModalSheetState();
}

class _TheavModalSheetState extends State<TheavModalSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _reboundController;
  ModalRoute<dynamic>? _enclosingRoute;
  double _dragOffset = 0.0;
  double _reboundFrom = 0.0;
  bool _didHapticThreshold = false;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleHardwareKey);
    _reboundController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 210),
    )..addListener(() {
        if (!mounted) return;
        final t = Curves.easeOutCubic.transform(_reboundController.value);
        setState(() {
          _dragOffset = _reboundFrom * (1.0 - t);
        });
      });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _enclosingRoute = ModalRoute.of(context);
  }

  @override
  void deactivate() {
    _enclosingRoute = null;
    super.deactivate();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleHardwareKey);
    _reboundController.dispose();
    super.dispose();
  }

  bool _handleHardwareKey(KeyEvent event) {
    if (!mounted || !context.mounted || _isDismissing) return false;
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape) {
      return false;
    }
    final route = _enclosingRoute;
    if (route == null ||
        !route.isCurrent ||
        !route.isActive ||
        !route.barrierDismissible) {
      return false;
    }
    _isDismissing = true;
    Navigator.of(context).maybePop();
    return true;
  }

  void _onDragStart() {
    if (!widget.enableDrag || _isDismissing) return;
    _reboundController.stop();
    _didHapticThreshold = false;
  }

  void _onDragDelta(double deltaY) {
    if (!widget.enableDrag || _isDismissing) return;
    setState(() {
      _dragOffset += deltaY;
    });
    final double height = context.size?.height ?? 360.0;
    final double threshold = math.min(120.0, height * 0.28);
    if (_dragOffset >= threshold && !_didHapticThreshold) {
      _didHapticThreshold = true;
      HapticUtils.selection();
    } else if (_dragOffset < threshold * 0.8 && _didHapticThreshold) {
      _didHapticThreshold = false;
    }
  }

  void _onDragEnd(double velocityY) {
    if (!widget.enableDrag || _isDismissing) return;
    final double height = context.size?.height ?? 360.0;
    final double dismissThreshold = math.min(120.0, height * 0.28);
    if (velocityY > 650.0 ||
        (_dragOffset >= dismissThreshold && velocityY > -200.0)) {
      _isDismissing = true;
      Navigator.of(context).maybePop();
      return;
    }

    if (_dragOffset.abs() < 0.5) {
      if (_dragOffset != 0.0) {
        setState(() => _dragOffset = 0.0);
      }
      return;
    }

    _reboundFrom = _dragOffset;
    _reboundController.forward(from: 0.0).whenComplete(() {
      if (mounted && _dragOffset != 0.0) {
        setState(() => _dragOffset = 0.0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final mq = MediaQuery.of(context);
    final bool hasHeader = (widget.title != null && widget.title!.isNotEmpty) ||
        widget.trailing != null ||
        widget.showCloseButton;
    final EdgeInsets resolvedPadding =
        widget.padding.resolve(Directionality.of(context));

    // Handle-only rubber-band stretch when pulling up (_dragOffset < 0) vs 1:1 pull down.
    const double maxStretch = 40.0;
    final double rawPullUp = _dragOffset < 0 ? -_dragOffset : 0.0;
    final double dampedStretch = rawPullUp > 0
        ? maxStretch * (1.0 - math.exp(-rawPullUp / 95.0))
        : 0.0;
    final double stretchProgress =
        (dampedStretch / maxStretch).clamp(0.0, 1.0);
    final double translateY = _dragOffset > 0 ? _dragOffset : 0.0;
    final double handleWidth = _dragOffset > 0
        ? 36.0 + (_dragOffset / 120.0).clamp(0.0, 1.0) * 10.0
        : 36.0 + stretchProgress * 8.0;

    final double baseMaxHeight = mq.size.height * widget.maxHeightFactor;
    final double effectiveMaxHeight =
        math.min(mq.size.height * 0.97, baseMaxHeight + dampedStretch);

    final Widget sheet = TheavSheetSurface(
      cornerRadius: 24.0,
      stretchPx: dampedStretch,
      maxStretch: maxStretch,
      constraints: BoxConstraints(
        maxHeight: effectiveMaxHeight,
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: mq.viewInsets.bottom + dampedStretch,
          ),
          child: Padding(
            padding: EdgeInsets.only(
              left: resolvedPadding.left,
              right: resolvedPadding.right,
              bottom: resolvedPadding.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: GestureDetector(
                    key: const ValueKey('theav_sheet_drag_handle'),
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart:
                        widget.enableDrag ? (_) => _onDragStart() : null,
                    onVerticalDragUpdate: widget.enableDrag
                        ? (d) => _onDragDelta(d.delta.dy)
                        : null,
                    onVerticalDragEnd: widget.enableDrag
                        ? (d) => _onDragEnd(d.velocity.pixelsPerSecond.dy)
                        : null,
                    onVerticalDragCancel:
                        widget.enableDrag ? () => _onDragEnd(0.0) : null,
                    child: SizedBox(
                      width: 112,
                      child: Padding(
                        padding: EdgeInsets.only(
                          top: math.max(10.0, resolvedPadding.top),
                          bottom: hasHeader ? 12.0 : 14.0,
                        ),
                        child: Center(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 90),
                            width: handleWidth,
                            height: 4,
                            decoration: BoxDecoration(
                              color:
                                  palette.onSurface.withValues(alpha: 0.24),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                if (hasHeader) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        if (widget.showCloseButton) ...[
                          TheavHeaderIconButton(
                            size: 36,
                            icon: iconoir.Xmark(
                              width: 18,
                              height: 18,
                              color: palette.onSurface,
                            ),
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                          const SizedBox(width: 10),
                        ],
                        if (widget.title != null && widget.title!.isNotEmpty)
                          Expanded(
                            child: Text(
                              widget.title!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.onSurface,
                                fontSize: 17.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                          )
                        else
                          const Spacer(),
                        if (widget.trailing != null) widget.trailing!,
                      ],
                    ),
                  ),
                ],
                Flexible(
                  child: widget.child,
                ),
              ],
            ),
          ),
        ),
      ),
    );

    return _SheetVerticalOffset(
      offsetY: translateY,
      child: sheet,
    );
  }
}

/// Action button descriptor for [TheavDialog] and [showTheavDialog].
class TheavDialogAction<T> {
  final String label;
  final T? result;
  final VoidCallback? onPressed;
  final bool isDestructive;
  final bool isPrimary;

  const TheavDialogAction({
    required this.label,
    this.result,
    this.onPressed,
    this.isDestructive = false,
    this.isPrimary = false,
  });
}

/// Shows a dual-mode [TheavDialog] replacing standard [AlertDialog].
Future<T?> showTheavDialog<T>({
  required BuildContext context,
  String? title,
  String? message,
  Widget? content,
  Widget? icon,
  List<TheavDialogAction<T>>? actions,
  List<Widget>? customActions,
  bool barrierDismissible = true,
}) {
  final bool isGlass = TheavSurfaceStyle.of(context, listen: false).isGlass;
  final bool forceMatte = TheavMatteScope.isActive(context, listen: false);
  final CapturedThemes capturedThemes = InheritedTheme.capture(
    from: context,
    to: Navigator.of(context, rootNavigator: true).context,
  );
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: Localizations.of<MaterialLocalizations>(
          context,
          MaterialLocalizations,
        )?.modalBarrierDismissLabel ??
        'Dismiss',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 220),
    pageBuilder: (ctx, animation, secondaryAnimation) {
      final bool disableAnim = MediaQuery.maybeDisableAnimationsOf(ctx) ?? false;
      Widget buildDialog(double op) => TheavDialog<T>(
            title: title,
            message: message,
            content: content,
            icon: icon,
            actions: actions,
            customActions: customActions,
            opacity: op,
          );
      final Widget dialogChild = (!isGlass || disableAnim)
          ? buildDialog(1.0)
          : AnimatedBuilder(
              animation: animation,
              builder: (animCtx, _) {
                final bool isReversing =
                    animation.status == AnimationStatus.reverse;
                final double op = (isReversing
                        ? Curves.easeInCubic
                        : Curves.easeOutCubic)
                    .transform(animation.value)
                    .clamp(0.0, 1.0);
                return buildDialog(op);
              },
            );
      final Widget scoped =
          forceMatte ? TheavMatteScope(child: dialogChild) : dialogChild;
      return capturedThemes.wrap(scoped);
    },
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final disableAnim = MediaQuery.maybeDisableAnimationsOf(ctx) ?? false;
      if (disableAnim) return child;
      final isReversing = animation.status == AnimationStatus.reverse;
      final curved = CurvedAnimation(
        parent: animation,
        curve: isReversing ? Curves.easeInCubic : Curves.easeOutCubic,
      );
      final Widget scaled = ScaleTransition(
        scale: Tween<double>(begin: 0.93, end: 1.0).animate(curved),
        child: child,
      );
      if (isGlass) return scaled;
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: isReversing ? Curves.easeInCubic : Curves.easeOutCubic,
        ),
        child: scaled,
      );
    },
  );
}

/// Dual-mode modal dialog built with [TheavPalette] tokens instead of stock
/// Material [AlertDialog].
class TheavDialog<T> extends StatelessWidget {
  final String? title;
  final String? message;
  final Widget? content;
  final Widget? icon;
  final List<TheavDialogAction<T>>? actions;
  final List<Widget>? customActions;
  final double opacity;

  const TheavDialog({
    super.key,
    this.title,
    this.message,
    this.content,
    this.icon,
    this.actions,
    this.customActions,
    this.opacity = 1.0,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final double op = opacity.clamp(0.0, 1.0);
    final resolvedActions = actions ?? const [];

    final Widget innerContent = Material(
      type: MaterialType.transparency,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (icon != null) ...[
              Center(
                child: IconTheme(
                  data: IconThemeData(color: palette.primary, size: 28),
                  child: icon!,
                ),
              ),
              const SizedBox(height: 12),
            ],
            if (title != null && title!.isNotEmpty)
              Text(
                title!,
                style: TextStyle(
                  color: palette.onSurface,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                  letterSpacing: -0.2,
                ),
              ),
            if (message != null && message!.isNotEmpty) ...[
              if (title != null && title!.isNotEmpty) const SizedBox(height: 8),
              Text(
                message!,
                style: TextStyle(
                  color: palette.subtext,
                  fontSize: 14.5,
                  height: 1.4,
                ),
              ),
            ],
            if (content != null) ...[
              if ((title != null && title!.isNotEmpty) ||
                  (message != null && message!.isNotEmpty))
                const SizedBox(height: 14),
              content!,
            ],
            if (resolvedActions.isNotEmpty ||
                (customActions != null && customActions!.isNotEmpty)) ...[
              const SizedBox(height: 18),
              if (customActions != null && customActions!.isNotEmpty)
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: customActions!,
                )
              else
                Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final action in resolvedActions)
                      _DialogActionButton<T>(action: action),
                  ],
                ),
            ],
          ],
        ),
      ),
    );

    Widget card;
    if (style.isGlass && style.glassProvider != null) {
      final baseGlassStyle = style.glassProvider!.createStyle(
        context: context,
        cornerRadius: 22.0,
        refractionIndex: 1.09,
        refractionWidth: 20.0,
        borderWidth: 1.1,
        color: style.hudFill.withValues(alpha: style.isDark ? 0.80 : 0.86),
      );
      card = ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 344),
        child: LiquidGlassLens(
          opacity: op,
          style: style.glassProvider!.scaleStyleForLensOpacity(
            baseGlassStyle,
            op,
          ),
          child: op < 0.999
              ? Opacity(opacity: op, child: innerContent)
              : innerContent,
        ),
      );
    } else {
      final blurFilter = style.isGlass
          ? style.getBlurFilter(sigma: 26.0)
          : style.getMaterialHudBlurFilter(sigma: 12.0);
      final Color dialogBg = (!style.isGlass && blurFilter != null)
          ? BlurUtils.resolveMaterialHudColor(
              style.overlayFill,
              isDark: style.isDark,
              blurEnabled: true,
              darkAlpha: 0.84,
              lightAlpha: 0.88,
            )
          : style.overlayFill;
      final Color borderColor = (style.isGlass || blurFilter != null)
          ? (style.isDark
              ? Colors.white.withValues(alpha: style.isGlass ? 0.16 : 0.12)
              : Colors.black.withValues(alpha: style.isGlass ? 0.08 : 0.07))
          : style.hairlineBorder;

      card = Container(
        constraints: const BoxConstraints(maxWidth: 344),
        decoration: BoxDecoration(
          color: dialogBg,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: borderColor,
            width: (style.isGlass || blurFilter != null) ? 0.6 : 0.5,
          ),
          boxShadow: style.floatingShadow,
        ),
        child: innerContent,
      );

      if (blurFilter != null) {
        card = ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter.grouped(
            filter: blurFilter,
            child: card,
          ),
        );
      }
      if (op < 0.999) {
        card = Opacity(opacity: op, child: card);
      }
    }

    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: card,
      ),
    );
  }
}

class _DialogActionButton<T> extends StatelessWidget {
  final TheavDialogAction<T> action;

  const _DialogActionButton({required this.action});

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final bool filled = action.isPrimary || action.isDestructive;
    final Color bgColor = action.isDestructive
        ? palette.error.withValues(alpha: 0.14)
        : (action.isPrimary
            ? palette.primary
            : palette.onSurface.withValues(alpha: 0.06));
    final Color fgColor = action.isDestructive
        ? palette.error
        : (action.isPrimary ? palette.onPrimary : palette.onSurface);

    return Material(
      color: filled ? bgColor : palette.onSurface.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticUtils.tap();
          if (action.onPressed != null) {
            action.onPressed!();
          } else {
            Navigator.of(context).pop(action.result);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            action.label,
            style: TextStyle(
              color: fgColor,
              fontSize: 14.5,
              fontWeight: filled ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
