import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../utils/haptic_utils.dart';
import 'theav_design_system.dart';

class _TheavSpringCurve extends Curve {
  const _TheavSpringCurve();

  static final SpringSimulation _sim = SpringSimulation(
    const SpringDescription(mass: 1.0, stiffness: 360.0, damping: 28.0),
    0.0,
    1.0,
    0.0,
  );

  @override
  double transformInternal(double t) {
    if (t <= 0.0) return 0.0;
    if (t >= 1.0) return 1.0;
    final double raw = _sim.x(t * 0.52);
    // Smoothly blend to exact 1.0 near the end of the normalized duration.
    final double blend = ((t - 0.82) / 0.18).clamp(0.0, 1.0);
    return raw * (1.0 - blend) + 1.0 * blend;
  }
}

class _SheetScrollBehavior extends ScrollBehavior {
  const _SheetScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics(parent: AlwaysScrollableScrollPhysics());
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

/// Opens a dual-mode, spring-animated [TheavModalSheet] that responds to
/// upward rubber-band stretch and velocity-based downward dismissal while
/// rendering crisp frosted glass blur in `full`/`lite` modes and M3 tonal
/// surface when disabled.
Future<T?> showTheavModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  Widget? trailing,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 10, 16, 20),
  bool isScrollControlled = true,
  bool enableDrag = true,
  bool showCloseButton = false,
  double maxHeightFactor = 0.92,
  bool barrierDismissible = true,
  bool useRootNavigator = false,
}) {
  return Navigator.of(context, rootNavigator: useRootNavigator).push<T>(
    _TheavSpringModalSheetRoute<T>(
      builder: builder,
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
    ),
  );
}

class _TheavSpringModalSheetRoute<T> extends PopupRoute<T> {
  final WidgetBuilder builder;
  final String? title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final bool enableDrag;
  final bool showCloseButton;
  final double maxHeightFactor;
  @override
  final bool barrierDismissible;
  @override
  final String? barrierLabel;

  _TheavSpringModalSheetRoute({
    required this.builder,
    this.title,
    this.trailing,
    required this.padding,
    required this.enableDrag,
    required this.showCloseButton,
    required this.maxHeightFactor,
    required this.barrierDismissible,
    required this.barrierLabel,
  });

  @override
  Color? get barrierColor => Colors.black54;

  @override
  bool get opaque => false;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 360);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 230);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Align(
      alignment: Alignment.bottomCenter,
      child: TheavModalSheet(
        title: title,
        trailing: trailing,
        padding: padding,
        showCloseButton: showCloseButton,
        maxHeightFactor: maxHeightFactor,
        enableDrag: enableDrag,
        child: Builder(builder: builder),
      ),
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
    if (disableAnim) return child;

    if (animation.status == AnimationStatus.reverse) {
      final rev = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FractionalTranslation(
        translation: Offset(0.0, 1.0 - rev.value),
        child: child,
      );
    }

    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, childWidget) {
        final double springVal = const _TheavSpringCurve().transform(
          animation.value.clamp(0.0, 1.0),
        );
        final double dy = math.max(0.0, 1.0 - springVal);
        final double overshoot = math.max(0.0, springVal - 1.0);
        Widget current = FractionalTranslation(
          translation: Offset(0.0, dy),
          child: childWidget,
        );
        if (overshoot > 0.0001) {
          current = Transform.scale(
            alignment: Alignment.bottomCenter,
            scaleY: 1.0 + overshoot * 0.55,
            scaleX: 1.0 - overshoot * 0.10,
            child: current,
          );
        }
        return current;
      },
    );
  }
}

/// Dual-mode modal bottom sheet container with spring rubber-band stretch,
/// drag handle, optional header bar, safe keyboard inset handling, and
/// [TheavPalette] styling.
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
  late final AnimationController _springController;
  double _dragOffset = 0.0;
  bool _didHapticThreshold = false;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    _springController = AnimationController.unbounded(vsync: this)
      ..addListener(() {
        if (!mounted) return;
        setState(() {
          _dragOffset = _springController.value;
        });
      });
  }

  @override
  void dispose() {
    _springController.dispose();
    super.dispose();
  }

  void _onDragStart() {
    if (!widget.enableDrag || _isDismissing) return;
    _springController.stop();
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

    if (_dragOffset.abs() < 0.5 && velocityY.abs() < 20.0) {
      if (_dragOffset != 0.0) {
        setState(() => _dragOffset = 0.0);
      }
      return;
    }

    final SpringDescription spring = _dragOffset < 0
        ? const SpringDescription(mass: 1.0, stiffness: 520.0, damping: 24.0)
        : const SpringDescription(mass: 1.0, stiffness: 460.0, damping: 26.0);
    final sim = SpringSimulation(
      spring,
      _dragOffset,
      0.0,
      velocityY.clamp(-2000.0, 2000.0),
    );
    _springController.animateWith(sim).whenComplete(() {
      if (mounted && _dragOffset.abs() < 0.05) {
        setState(() => _dragOffset = 0.0);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final mq = MediaQuery.of(context);
    final blurFilter = style.getBlurFilter(sigma: 26.0);
    final bool hasHeader = (widget.title != null && widget.title!.isNotEmpty) ||
        widget.trailing != null ||
        widget.showCloseButton;

    // Asymmetric rubber-band stretch when pulling up (_dragOffset < 0) vs 1:1 pull down.
    const double maxStretch = 38.0;
    final double rawPullUp = _dragOffset < 0 ? -_dragOffset : 0.0;
    final double dampedStretch = rawPullUp > 0
        ? maxStretch * (1.0 - math.exp(-rawPullUp / 95.0))
        : 0.0;
    final double stretchProgress =
        (dampedStretch / maxStretch).clamp(0.0, 1.0);
    final double translateY = _dragOffset > 0 ? _dragOffset : 0.0;
    final double scaleY = 1.0 + stretchProgress * 0.042;
    final double scaleX = 1.0 - stretchProgress * 0.010;
    final double extraBottomSkirt = dampedStretch * 0.35;
    final double handleWidth = _dragOffset > 0
        ? 36.0 + (_dragOffset / 120.0).clamp(0.0, 1.0) * 10.0
        : 36.0 + stretchProgress * 8.0;

    final Color borderColor = style.isGlass
        ? (style.isDark
            ? Colors.white.withValues(alpha: 0.16)
            : Colors.black.withValues(alpha: 0.08))
        : style.hairlineBorder;
    final double borderWidth = style.isGlass ? 0.6 : 0.5;

    Widget sheet = Container(
      constraints: BoxConstraints(
        maxHeight: mq.size.height * widget.maxHeightFactor,
      ),
      decoration: BoxDecoration(
        color: style.overlayFill,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: borderColor,
          width: borderWidth,
        ),
        boxShadow: style.floatingShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: mq.viewInsets.bottom + extraBottomSkirt,
            ),
            child: Padding(
              padding: widget.padding,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 90),
                      width: handleWidth,
                      height: 4,
                      margin: EdgeInsets.only(bottom: hasHeader ? 12 : 14),
                      decoration: BoxDecoration(
                        color: palette.onSurface.withValues(alpha: 0.24),
                        borderRadius: BorderRadius.circular(2),
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
                    child: ScrollConfiguration(
                      behavior: const _SheetScrollBehavior(),
                      child: widget.child,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    if (blurFilter != null) {
      sheet = ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: blurFilter,
          child: sheet,
        ),
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onVerticalDragStart: widget.enableDrag ? (_) => _onDragStart() : null,
      onVerticalDragUpdate:
          widget.enableDrag ? (d) => _onDragDelta(d.delta.dy) : null,
      onVerticalDragEnd: widget.enableDrag
          ? (d) => _onDragEnd(d.velocity.pixelsPerSecond.dy)
          : null,
      onVerticalDragCancel: widget.enableDrag ? () => _onDragEnd(0.0) : null,
      child: NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (!widget.enableDrag || _isDismissing) return false;
          if (notification.metrics.axis != Axis.vertical) return false;
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            _onDragStart();
          } else if (notification is OverscrollNotification &&
              notification.dragDetails != null) {
            // Overscroll < 0 at top edge pulls the sheet down; > 0 at bottom edge stretches up.
            _onDragDelta(-notification.overscroll);
          } else if (notification is ScrollEndNotification) {
            if (_dragOffset != 0.0) {
              _onDragEnd(
                notification.dragDetails?.velocity.pixelsPerSecond.dy ?? 0.0,
              );
            }
          }
          return false;
        },
        child: Transform.translate(
          offset: Offset(0.0, translateY),
          child: Transform.scale(
            alignment: Alignment.bottomCenter,
            scaleY: scaleY,
            scaleX: scaleX,
            child: sheet,
          ),
        ),
      ),
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
    pageBuilder: (ctx, animation, secondaryAnimation) => TheavDialog<T>(
      title: title,
      message: message,
      content: content,
      icon: icon,
      actions: actions,
      customActions: customActions,
    ),
    transitionBuilder: (ctx, animation, secondaryAnimation, child) {
      final disableAnim = MediaQuery.maybeDisableAnimationsOf(ctx) ?? false;
      if (disableAnim) return child;
      final isReversing = animation.status == AnimationStatus.reverse;
      final curved = CurvedAnimation(
        parent: animation,
        curve: isReversing ? Curves.easeInCubic : Curves.easeOutBack,
      );
      return FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: isReversing ? Curves.easeInCubic : Curves.easeOutCubic,
        ),
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.93, end: 1.0).animate(curved),
          child: child,
        ),
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

  const TheavDialog({
    super.key,
    this.title,
    this.message,
    this.content,
    this.icon,
    this.actions,
    this.customActions,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final blurFilter = style.getBlurFilter(sigma: 26.0);
    final resolvedActions = actions ?? const [];
    final Color borderColor = style.isGlass
        ? (style.isDark
            ? Colors.white.withValues(alpha: 0.16)
            : Colors.black.withValues(alpha: 0.08))
        : style.hairlineBorder;

    Widget card = Container(
      constraints: const BoxConstraints(maxWidth: 344),
      decoration: BoxDecoration(
        color: style.overlayFill,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: borderColor,
          width: style.isGlass ? 0.6 : 0.5,
        ),
        boxShadow: style.floatingShadow,
      ),
      child: Material(
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
      ),
    );

    if (blurFilter != null) {
      card = ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: blurFilter,
          child: card,
        ),
      );
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
