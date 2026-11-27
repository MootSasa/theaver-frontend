import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../widgets/bot/mini_app_webview_sheet.dart';
import '../../widgets/design_system/theav_design_system.dart';
import '../tiling/trackpad_swipe_back_indicator.dart';

/// Inherited route scope exposing the live transition progress and the ability
/// to temporarily reveal the underlying route during 2D drag-to-dismiss.
class TheavMediaViewerRouteScope extends InheritedWidget {
  final Animation<double> transitionAnimation;
  final ValueChanged<bool> setRestingOpaque;
  final VoidCallback markDragDismissing;

  const TheavMediaViewerRouteScope({
    super.key,
    required this.transitionAnimation,
    required this.setRestingOpaque,
    required this.markDragDismissing,
    required super.child,
  });

  static TheavMediaViewerRouteScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TheavMediaViewerRouteScope>();
  }

  @override
  bool updateShouldNotify(TheavMediaViewerRouteScope oldWidget) =>
      transitionAnimation != oldWidget.transitionAnimation;
}

/// Dynamic-opacity route for [TheavMediaViewer].
///
/// While settled (`AnimationStatus.completed` and not being dragged away), marks
/// its top [OverlayEntry] `opaque = true` so Flutter completely skips painting
/// the heavy underlying `ProfileScreen` / `ChatScreen` on every frame
/// (`0.0 ms/frame`). As soon as a 2D dismiss drag starts (or during push/pop),
/// flips `opaque = false` so the underlying screen shows through seamlessly for
/// a 1:1 reverse [Hero] flight.
class TheavMediaViewerRoute<T> extends PageRoute<T> {
  final WidgetBuilder builder;
  final CapturedThemes? capturedThemes;

  bool _restingOpaque = true;
  bool _isDisposed = false;
  bool _overlaySyncScheduled = false;
  bool _miniAppRegistered = false;
  bool _miniAppSettled = false;
  bool _dismissingFromDrag = false;
  bool _trackpadBlockerRegistered = false;
  CurvedAnimation? _curvedTransition;

  TheavMediaViewerRoute({
    required this.builder,
    this.capturedThemes,
    super.settings,
  });

  /// Always returns `false` so [TransitionRoute] lets us mutate the live
  /// [OverlayEntry.opaque] flag without tripping the `opaque` change assertion.
  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 230);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 200);

  void setRestingOpaque(bool value) {
    if (_isDisposed || _restingOpaque == value) return;
    _restingOpaque = value;
    _scheduleOrSyncOverlayOpaque();
  }

  void _markDragDismissing() {
    _dismissingFromDrag = true;
    setRestingOpaque(false);
  }

  void _handleRouteStatusChanged(AnimationStatus status) {
    if (_isDisposed) return;
    if (status == AnimationStatus.completed) {
      _dismissingFromDrag = false;
      if (!_miniAppSettled) {
        _miniAppSettled = true;
        MiniAppSessionController.instance.markFullScreenSettled();
      }
    } else {
      if (_miniAppSettled) {
        _miniAppSettled = false;
        MiniAppSessionController.instance.unmarkFullScreenSettled();
      }
    }
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

  void _registerTrackpadBlocker() {
    if (_trackpadBlockerRegistered) return;
    _trackpadBlockerRegistered = true;
    TrackpadBackGestureWrapper.pushModalBlocker();
  }

  void _unregisterTrackpadBlocker() {
    if (!_trackpadBlockerRegistered) return;
    _trackpadBlockerRegistered = false;
    TrackpadBackGestureWrapper.popModalBlocker();
  }

  @override
  void install() {
    super.install();
    _registerTrackpadBlocker();
    if (!_miniAppRegistered) {
      _miniAppRegistered = true;
      MiniAppSessionController.instance.registerFullScreenOpen();
    }
    animation?.addStatusListener(_handleRouteStatusChanged);
  }

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    _curvedTransition ??= CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );

    final Widget content = TheavMediaViewerRouteScope(
      transitionAnimation: _curvedTransition!,
      setRestingOpaque: setRestingOpaque,
      markDragDismissing: _markDragDismissing,
      child: TheavMatteScope(
        child: Builder(builder: builder),
      ),
    );
    return capturedThemes != null ? capturedThemes!.wrap(content) : content;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    // Do NOT wrap Hero children in an Opacity saveLayer here: TheavMediaViewer
    // drives backdrop alpha and HUD FadeTransition directly from
    // `transitionAnimation`, keeping Hero flights crisp and offscreen-layer free!
    if (_dismissingFromDrag && animation.status == AnimationStatus.reverse) {
      return child;
    }
    return child;
  }

  @override
  bool didPop(T? result) {
    _unregisterTrackpadBlocker();
    return super.didPop(result);
  }

  @override
  void dispose() {
    _isDisposed = true;
    _unregisterTrackpadBlocker();
    animation?.removeStatusListener(_handleRouteStatusChanged);
    if (_miniAppSettled) {
      _miniAppSettled = false;
      MiniAppSessionController.instance.unmarkFullScreenSettled();
    }
    if (_miniAppRegistered) {
      _miniAppRegistered = false;
      MiniAppSessionController.instance.unregisterFullScreenOpen();
    }
    _curvedTransition?.dispose();
    _curvedTransition = null;
    super.dispose();
  }
}
