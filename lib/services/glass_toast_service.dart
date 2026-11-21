import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../widgets/design_system/theav_design_system.dart';

/// Dual-mode floating toast ("cloud") overlay using [TheavSurfaceStyle]
/// (`context.theav` palette) and safe GPU animations (never wrapping
/// shader-backed glass in [Opacity] or [FadeTransition]).
class GlassToastService {
  static final GlassToastService _instance = GlassToastService._internal();
  factory GlassToastService() => _instance;
  GlassToastService._internal();

  OverlayEntry? _overlayEntry;

  /// Shows a floating toast with optional icon, action button, or error styling.
  void show(
    BuildContext context,
    String message, {
    IconData? icon,
    Widget? iconWidget,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
    bool isError = false,
  }) {
    _removeImmediately();

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    late final OverlayEntry entry;
    entry = OverlayEntry(
      builder: (ctx) => _GlassToastWidget(
        message: message,
        icon: icon,
        iconWidget: iconWidget,
        duration: duration,
        actionLabel: actionLabel,
        onAction: onAction,
        isError: isError,
        onRemove: () => _removeEntry(entry),
      ),
    );

    _overlayEntry = entry;
    overlay.insert(entry);
  }

  /// Convenience helper for error notifications.
  void showError(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    show(
      context,
      message,
      isError: true,
      duration: duration,
    );
  }

  /// Immediately hides and removes the currently visible toast overlay, if any.
  void hide() => _removeImmediately();

  void _removeImmediately() {
    final OverlayEntry? entry = _overlayEntry;
    _overlayEntry = null;
    entry?.remove();
  }

  void _removeEntry(OverlayEntry entry) {
    if (!identical(_overlayEntry, entry)) return;
    _overlayEntry = null;
    entry.remove();
  }
}

class _GlassToastWidget extends StatefulWidget {
  final String message;
  final IconData? icon;
  final Widget? iconWidget;
  final Duration duration;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isError;
  final VoidCallback onRemove;

  const _GlassToastWidget({
    required this.message,
    this.icon,
    this.iconWidget,
    required this.duration,
    this.actionLabel,
    this.onAction,
    required this.isError,
    required this.onRemove,
  });

  @override
  State<_GlassToastWidget> createState() => _GlassToastWidgetState();
}

class _GlassToastWidgetState extends State<_GlassToastWidget>
    with TickerProviderStateMixin {
  static const double _offscreenOffsetY = 140.0;
  static const double _dropletSize = 38.0;
  static const double _morphFieldMaxHeight = 160.0;

  late final AnimationController _flightController;
  Timer? _autoHideTimer;
  bool _didInitMode = false;
  bool _disableAnimations = false;
  bool _useGlassMorph = false;
  bool _expanded = false;
  bool _closing = false;
  bool _morphDone = true;

  @override
  void initState() {
    super.initState();
    _flightController = AnimationController.unbounded(vsync: this, value: 0.0);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitMode) return;
    _didInitMode = true;

    final style = TheavSurfaceStyle.of(context, listen: false);
    _disableAnimations = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    _useGlassMorph =
        !_disableAnimations && style.isGlass && style.glassProvider != null;

    _startAutoHideTimer();

    if (_disableAnimations) {
      _expanded = true;
      _flightController.value = 1.0;
      return;
    }

    if (_useGlassMorph) {
      // Seed `LiquidGlassMorph` on frame 0 as a 38x38 droplet off-screen so
      // `_seeded` settles before switching to the capsule target on frame 1.
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _closing) return;
        SchedulerBinding.instance.addPostFrameCallback((_) {
          if (!mounted || _closing || _expanded) return;
          setState(() => _expanded = true);
          _launchUpward();
        });
        SchedulerBinding.instance.scheduleFrame();
      });
    } else {
      _expanded = true;
      _launchUpward();
    }
  }

  @override
  void dispose() {
    _autoHideTimer?.cancel();
    _flightController.dispose();
    super.dispose();
  }

  void _startAutoHideTimer() {
    _autoHideTimer?.cancel();
    _autoHideTimer = Timer(widget.duration, _beginDismiss);
  }

  void _launchUpward() {
    const spring = SpringDescription(
      mass: 1.0,
      stiffness: 250.0,
      damping: 22.5,
    );
    _flightController.animateWith(
      SpringSimulation(spring, _flightController.value, 1.0, 0.0),
    );
  }

  void _beginDismiss() {
    if (_closing || !mounted) return;
    _closing = true;
    _autoHideTimer?.cancel();
    _autoHideTimer = null;

    if (_disableAnimations) {
      widget.onRemove();
      return;
    }

    if (_useGlassMorph && _expanded) {
      _morphDone = false;
      setState(() => _expanded = false);
    } else {
      _morphDone = true;
    }

    _flightController
        .animateTo(
          0.0,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeInCubic,
        )
        .whenCompleteOrCancel(_maybeCompleteDismiss);
  }

  void _handleMorphEnd() {
    _morphDone = true;
    _maybeCompleteDismiss();
  }

  void _maybeCompleteDismiss() {
    if (!mounted || !_closing) return;
    if (_flightController.isAnimating || !_morphDone) return;
    widget.onRemove();
  }

  void _handleVerticalDragStart(DragStartDetails details) {
    if (_closing) return;
    _autoHideTimer?.cancel();
    _flightController.stop();
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (_closing) return;
    final double currentDy =
        (1.0 - _flightController.value) * _offscreenOffsetY;
    final double delta =
        details.delta.dy >= 0 ? details.delta.dy : details.delta.dy * 0.22;
    final double nextDy = (currentDy + delta).clamp(-18.0, 220.0);
    _flightController.value = 1.0 - (nextDy / _offscreenOffsetY);
  }

  void _handleVerticalDragEnd(DragEndDetails details) {
    if (_closing) return;
    final double currentDy =
        (1.0 - _flightController.value) * _offscreenOffsetY;
    final double velocityY = details.primaryVelocity ?? 0.0;
    if (currentDy > 28.0 || velocityY > 260.0) {
      _beginDismiss();
      return;
    }
    _launchUpward();
    _startAutoHideTimer();
  }

  void _handleVerticalDragCancel() {
    if (_closing) return;
    _launchUpward();
    _startAutoHideTimer();
  }

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context, listen: false);
    final palette = style.palette;

    final Color? fillOverride = widget.isError
        ? Color.alphaBlend(
            palette.error.withValues(alpha: style.isDark ? 0.24 : 0.14),
            style.hudFill,
          )
        : null;

    final Widget pillInner = GestureDetector(
      key: const ValueKey<String>('glass_toast_pill'),
      behavior: HitTestBehavior.opaque,
      onTap: _beginDismiss,
      onVerticalDragStart: _handleVerticalDragStart,
      onVerticalDragUpdate: _handleVerticalDragUpdate,
      onVerticalDragEnd: _handleVerticalDragEnd,
      onVerticalDragCancel: _handleVerticalDragCancel,
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          child: _buildContent(palette),
        ),
      ),
    );

    final Widget body;
    if (style.isGlass && style.glassProvider != null && _useGlassMorph) {
      final glassStyle = style.glassProvider!.createStyle(
        context: context,
        cornerRadius: 24,
        refractionIndex: 1.08,
        refractionWidth: 18,
        color: fillOverride,
      );

      const Widget seedDroplet = IgnorePointer(
        key: ValueKey<String>('glass_toast_seed'),
        child: SizedBox(width: _dropletSize, height: _dropletSize),
      );

      final Widget expandedContent = IgnorePointer(
        key: const ValueKey<String>('glass_toast_expanded'),
        ignoring: _closing,
        child: pillInner,
      );

      body = LayoutBuilder(
        builder: (context, constraints) {
          final double fieldWidth = constraints.maxWidth.isFinite
              ? math.min(constraints.maxWidth, 420.0)
              : 360.0;
          return AnimatedBuilder(
            animation: _flightController,
            builder: (context, child) {
              final double dy =
                  (1.0 - _flightController.value) * _offscreenOffsetY;
              return Transform.translate(
                offset: Offset(0.0, dy),
                child: child,
              );
            },
            child: LiquidGlassBatch.exclude(
              child: SizedBox(
                width: fieldWidth,
                height: _morphFieldMaxHeight,
                child: LiquidGlassMorph(
                  alignment: Alignment.bottomCenter,
                  smoothness: 22,
                  style: glassStyle,
                  motion: const LiquidGlassMorphMotion(
                    stiffness: 260,
                    damping: 24.0,
                    stretch: 0.45,
                    anchor: Alignment.bottomCenter,
                    advanced: LiquidGlassMorphAdvanced(
                      sourceFollows: true,
                      newScaleFrom: 0.86,
                      oldScaleTo: 0.85,
                      contentBlur: 7.0,
                      contentInStart: 0.24,
                      contentInEnd: 0.78,
                      contentOutEnd: 0.34,
                      thickenBlur: 0.35,
                      thickenRefraction: 0.30,
                    ),
                  ),
                  onEnd: _handleMorphEnd,
                  child: _expanded ? expandedContent : seedDroplet,
                ),
              ),
            ),
          );
        },
      );
    } else if (style.isGlass && style.glassProvider != null) {
      // Reduced-motion glass fallback: shrink-wrapped lens with no flight.
      body = TheavFloatingSurface(
        borderRadius: 24,
        refractionIndex: 1.08,
        refractionWidth: 18,
        colorOverride: fillOverride,
        enableFlex: false,
        child: pillInner,
      );
    } else {
      final Widget mattePill = TheavFloatingSurface(
        borderRadius: 24,
        refractionIndex: 1.08,
        refractionWidth: 18,
        colorOverride: fillOverride,
        child: pillInner,
      );

      body = AnimatedBuilder(
        animation: _flightController,
        builder: (context, child) {
          final double v = _flightController.value;
          final double clamped = v.clamp(0.0, 1.0);
          final double dy = (1.0 - v) * 96.0;
          final double scale = 0.84 + 0.16 * clamped;
          return Transform.translate(
            offset: Offset(0.0, dy),
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.bottomCenter,
              child: Opacity(
                opacity: clamped,
                child: child,
              ),
            ),
          );
        },
        child: mattePill,
      );
    }

    return SafeArea(
      key: const ValueKey<String>('glass_toast_overlay'),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: body,
          ),
        ),
      ),
    );
  }

  Widget _buildContent(TheavPalette palette) {
    final Color iconColor =
        widget.isError ? palette.error : palette.primary;

    final Widget? leadingIcon = widget.iconWidget ??
        (widget.icon != null
            ? Icon(widget.icon, color: iconColor, size: 19)
            : (widget.isError
                ? iconoir.WarningTriangle(
                    width: 19,
                    height: 19,
                    color: palette.error,
                  )
                : null));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leadingIcon != null) ...[
          leadingIcon,
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Text(
            widget.message,
            style: TextStyle(
              color: palette.onSurface,
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
        ),
        if (widget.actionLabel != null &&
            widget.actionLabel!.isNotEmpty &&
            widget.onAction != null) ...[
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () {
              _beginDismiss();
              widget.onAction?.call();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: palette.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.actionLabel!,
                style: TextStyle(
                  color: palette.primary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
