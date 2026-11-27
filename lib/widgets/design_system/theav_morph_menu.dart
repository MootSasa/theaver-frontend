import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:motor/motor.dart';

import '../../utils/haptic_utils.dart';
import 'theav_design_system.dart';

typedef TheavMorphMenuBuilder<T> = Widget Function(
  BuildContext context,
  void Function([T? result]) close,
);

/// Opens a compact morphing popover expanding smoothly from the anchor widget's
/// global [Rect] using [LiquidGlassMorph] in glass modes or a spring-eased
/// [TheavFloatingSurface] in Material mode.
///
/// Designed to replace heavy bottom sheets for menus like language selection,
/// country dial pickers, and compact help popovers without hurting Liquid Glass
/// shader performance.
Future<T?> openTheavMorphPopover<T>({
  required BuildContext anchorContext,
  required double menuWidth,
  required double menuHeight,
  required TheavMorphMenuBuilder<T> menuBuilder,
  Widget Function(BuildContext context)? collapsedBuilder,
  double cornerRadius = 22.0,
  double screenMargin = 12.0,
}) {
  final renderObj = anchorContext.findRenderObject();
  final overlayState = Overlay.of(anchorContext, rootOverlay: false);
  final overlayBox = overlayState.context.findRenderObject() as RenderBox?;

  Rect anchorRect;
  if (renderObj is RenderBox &&
      renderObj.hasSize &&
      overlayBox != null &&
      overlayBox.hasSize) {
    final topLeft =
        renderObj.localToGlobal(Offset.zero, ancestor: overlayBox);
    anchorRect = topLeft & renderObj.size;
  } else {
    final size = overlayBox?.size ?? MediaQuery.sizeOf(anchorContext);
    anchorRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2),
      width: 44,
      height: 44,
    );
  }

  final completer = Completer<T?>();
  late OverlayEntry entry;

  entry = OverlayEntry(
    builder: (overlayCtx) {
      return _TheavMorphPopoverOverlay<T>(
        anchorRect: anchorRect,
        requestedWidth: menuWidth,
        requestedHeight: menuHeight,
        cornerRadius: cornerRadius,
        screenMargin: screenMargin,
        collapsedBuilder: collapsedBuilder,
        menuBuilder: menuBuilder,
        onDisposed: ([T? result]) {
          if (entry.mounted) {
            entry.remove();
          }
          if (!completer.isCompleted) {
            completer.complete(result);
          }
        },
      );
    },
  );

  overlayState.insert(entry);
  return completer.future;
}

/// Interactive wrapper that measures its child's [Rect] and morphs it directly
/// into a compact floating popover menu when tapped.
class TheavMorphMenuButton<T> extends StatefulWidget {
  final Widget child;
  final double menuWidth;
  final double menuHeight;
  final TheavMorphMenuBuilder<T> menuBuilder;
  final Widget Function(BuildContext context)? collapsedBuilder;
  final ValueChanged<T?>? onResult;
  final double cornerRadius;
  final bool enabled;

  const TheavMorphMenuButton({
    super.key,
    required this.child,
    required this.menuWidth,
    required this.menuHeight,
    required this.menuBuilder,
    this.collapsedBuilder,
    this.onResult,
    this.cornerRadius = 22.0,
    this.enabled = true,
  });

  @override
  State<TheavMorphMenuButton<T>> createState() => _TheavMorphMenuButtonState<T>();
}

class _TheavMorphMenuButtonState<T> extends State<TheavMorphMenuButton<T>> {
  final GlobalKey _anchorKey = GlobalKey();
  bool _opening = false;

  Future<void> _handleTap() async {
    if (!widget.enabled || _opening) return;
    _opening = true;
    HapticUtils.tap();
    try {
      final anchorCtx = _anchorKey.currentContext ?? context;
      final res = await openTheavMorphPopover<T>(
        anchorContext: anchorCtx,
        menuWidth: widget.menuWidth,
        menuHeight: widget.menuHeight,
        cornerRadius: widget.cornerRadius,
        collapsedBuilder: widget.collapsedBuilder,
        menuBuilder: widget.menuBuilder,
      );
      if (mounted) {
        widget.onResult?.call(res);
      }
    } finally {
      _opening = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: _anchorKey,
      behavior: HitTestBehavior.opaque,
      onTap: widget.enabled ? _handleTap : null,
      child: widget.child,
    );
  }
}

class _TheavMorphPopoverOverlay<T> extends StatefulWidget {
  final Rect anchorRect;
  final double requestedWidth;
  final double requestedHeight;
  final double cornerRadius;
  final double screenMargin;
  final Widget Function(BuildContext context)? collapsedBuilder;
  final TheavMorphMenuBuilder<T> menuBuilder;
  final void Function([T? result]) onDisposed;

  const _TheavMorphPopoverOverlay({
    required this.anchorRect,
    required this.requestedWidth,
    required this.requestedHeight,
    required this.cornerRadius,
    required this.screenMargin,
    this.collapsedBuilder,
    required this.menuBuilder,
    required this.onDisposed,
  });

  @override
  State<_TheavMorphPopoverOverlay<T>> createState() =>
      _TheavMorphPopoverOverlayState<T>();
}

class _TheavMorphPopoverOverlayState<T>
    extends State<_TheavMorphPopoverOverlay<T>> {
  bool _expanded = false;
  bool _closing = false;
  Timer? _closeTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_closing) {
        setState(() => _expanded = true);
      }
    });
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    super.dispose();
  }

  void _close([T? result]) {
    if (_closing) return;
    _closing = true;
    final disableAnim = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (disableAnim || !_expanded) {
      widget.onDisposed(result);
      return;
    }
    setState(() => _expanded = false);
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 185), () {
      widget.onDisposed(result);
    });
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final screenSize = mq.size;
    final safeTop = mq.padding.top + widget.screenMargin;
    final safeBottom =
        math.max(mq.padding.bottom, mq.viewInsets.bottom) + widget.screenMargin;
    final maxW = math.max(120.0, screenSize.width - widget.screenMargin * 2);
    final maxH = math.max(120.0, screenSize.height - safeTop - safeBottom);

    final double menuW = widget.requestedWidth.clamp(
      math.min(widget.anchorRect.width, maxW),
      maxW,
    );
    final double menuH = widget.requestedHeight.clamp(
      math.min(widget.anchorRect.height, maxH),
      maxH,
    );

    final double spaceBelow = screenSize.height - safeBottom - widget.anchorRect.top;
    final double spaceAbove = widget.anchorRect.bottom - safeTop;
    final bool openUpward = spaceBelow < menuH && spaceAbove > spaceBelow;

    final double centerRatio = screenSize.width > 0
        ? widget.anchorRect.center.dx / screenSize.width
        : 0.5;
    final double boxW = math.max(menuW, widget.anchorRect.width);
    final double boxH = math.max(menuH, widget.anchorRect.height);

    final double alignX;
    final double rawLeft;
    if (centerRatio > 0.64) {
      alignX = 1.0;
      rawLeft = widget.anchorRect.right - boxW;
    } else if (centerRatio < 0.36) {
      alignX = -1.0;
      rawLeft = widget.anchorRect.left;
    } else {
      alignX = 0.0;
      rawLeft = widget.anchorRect.center.dx - boxW / 2;
    }

    final double clampedLeft = rawLeft.clamp(
      widget.screenMargin,
      math.max(widget.screenMargin, screenSize.width - widget.screenMargin - boxW),
    );
    final double rawTop = openUpward
        ? (widget.anchorRect.bottom - boxH)
        : widget.anchorRect.top;
    final double clampedTop = rawTop.clamp(
      safeTop,
      math.max(safeTop, screenSize.height - safeBottom - boxH),
    );

    final Alignment morphAlignment = Alignment(alignX, openUpward ? 1.0 : -1.0);
    final surfaceStyle = TheavSurfaceStyle.of(context);
    final palette = surfaceStyle.palette;

    final Widget collapsedChild = SizedBox(
      width: math.min(widget.anchorRect.width, boxW),
      height: math.min(widget.anchorRect.height, boxH),
      child: widget.collapsedBuilder != null
          ? widget.collapsedBuilder!(context)
          : const SizedBox.shrink(),
    );

    final Widget expandedContent = SizedBox(
      width: menuW,
      height: menuH,
      child: Material(
        type: MaterialType.transparency,
        child: widget.menuBuilder(context, _close),
      ),
    );

    Widget morphBody;
    if (surfaceStyle.isGlass && surfaceStyle.glassProvider != null) {
      final glassStyle = surfaceStyle.glassProvider!.createStyle(
        context: context,
        cornerRadius: widget.cornerRadius,
        refractionIndex: 1.12,
        refractionWidth: 22.0,
        color: surfaceStyle.isDark
            ? palette.surface.withValues(alpha: 0.56)
            : palette.surface.withValues(alpha: 0.76),
      );

      morphBody = SizedBox(
        width: boxW,
        height: boxH,
        child: LiquidGlassBatch(
          child: LiquidGlassMorph(
            alignment: morphAlignment,
            motion: LiquidGlassMorphMotion.fluid,
            smoothness: 28,
            style: glassStyle,
            child: _expanded
                ? KeyedSubtree(
                    key: const ValueKey<String>('morph_expanded'),
                    child: expandedContent,
                  )
                : KeyedSubtree(
                    key: const ValueKey<String>('morph_collapsed'),
                    child: collapsedChild,
                  ),
          ),
        ),
      );
    } else {
      final startW = widget.anchorRect.width.clamp(36.0, menuW);
      final startH = widget.anchorRect.height.clamp(36.0, menuH);
      morphBody = SizedBox(
        width: boxW,
        height: boxH,
        child: Align(
          alignment: morphAlignment,
          child: SingleMotionBuilder(
            value: _expanded ? 1.0 : 0.0,
            motion: const Motion.snappySpring(snapToEnd: true),
            builder: (ctx, rawT, _) {
              final t = rawT.clamp(0.0, 1.0);
              final curW = startW + (menuW - startW) * t;
              final curH = startH + (menuH - startH) * t;
              final double curRadius = widget.cornerRadius +
                  ((math.min(startW, startH) / 2 - widget.cornerRadius) *
                      (1.0 - t));
              return SizedBox(
                width: curW,
                height: curH,
                child: TheavFloatingSurface(
                  borderRadius: curRadius,
                  enableFlex: false,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(curRadius),
                    child: OverflowBox(
                      alignment: morphAlignment,
                      minWidth: menuW,
                      maxWidth: menuW,
                      minHeight: menuH,
                      maxHeight: menuH,
                      child: t < 0.15 ? collapsedChild : expandedContent,
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    final stack = PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _close();
      },
      child: Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: () => _close(),
            ),
          ),
          Positioned(
            left: clampedLeft,
            top: clampedTop,
            child: morphBody,
          ),
        ],
      ),
    );

    return BackdropGroup.of(context) == null
        ? BackdropGroup(child: stack)
        : stack;
  }
}

/// Presents a compact centered card inside [TheavMatteScope] for rare secondary
/// dialogs (e.g. OAuth 2FA or link confirmation) without full-screen glass blur.
Future<T?> showTheavCompactModalCard<T>({
  required BuildContext context,
  required String title,
  required Widget Function(BuildContext cardCtx) builder,
  double maxWidth = 356.0,
  bool barrierDismissible = true,
}) {
  return Navigator.of(context).push<T>(
    PageRouteBuilder<T>(
      opaque: false,
      barrierDismissible: barrierDismissible,
      barrierColor: Colors.black54,
      barrierLabel: title,
      transitionDuration: const Duration(milliseconds: 220),
      reverseTransitionDuration: const Duration(milliseconds: 170),
      pageBuilder: (routeCtx, animation, secondaryAnimation) {
        return TheavMatteScope(
          child: Builder(
            builder: (matteCtx) {
              final palette = matteCtx.theav;
              final bottomInset = MediaQuery.viewInsetsOf(matteCtx).bottom;
              final maxH = MediaQuery.sizeOf(matteCtx).height * 0.78;
              return SafeArea(
                child: AnimatedPadding(
                  duration: const Duration(milliseconds: 160),
                  curve: Curves.easeOutCubic,
                  padding: EdgeInsets.fromLTRB(
                    20,
                    20,
                    20,
                    math.max(20.0, bottomInset + 16.0),
                  ),
                  child: Center(
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        maxWidth: maxWidth,
                        maxHeight: maxH,
                      ),
                      child: TheavSheetSurface(
                        cornerRadius: 24.0,
                        constraints: BoxConstraints(maxHeight: maxH),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Padding(
                              padding: const EdgeInsets.fromLTRB(18, 16, 12, 8),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      title,
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w700,
                                        letterSpacing: -0.25,
                                        color: palette.onSurface,
                                      ),
                                    ),
                                  ),
                                  GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      HapticUtils.tap();
                                      Navigator.of(matteCtx).maybePop();
                                    },
                                    child: Container(
                                      width: 34,
                                      height: 34,
                                      decoration: BoxDecoration(
                                        color: palette.onSurface
                                            .withValues(alpha: 0.08),
                                        shape: BoxShape.circle,
                                      ),
                                      alignment: Alignment.center,
                                      child: iconoir.Xmark(
                                        width: 17,
                                        height: 17,
                                        color: palette.onSurface,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            Divider(
                              height: 0.5,
                              thickness: 0.5,
                              color: palette.divider,
                            ),
                            Flexible(
                              child: SingleChildScrollView(
                                padding: const EdgeInsets.fromLTRB(
                                  18,
                                  14,
                                  18,
                                  18,
                                ),
                                child: builder(matteCtx),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
      transitionsBuilder: (ctx, animation, _, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: const Cubic(0.22, 1.0, 0.36, 1.0),
          reverseCurve: Curves.easeInCubic,
        );
        return ScaleTransition(
          scale: Tween<double>(begin: 0.94, end: 1.0).animate(curved),
          child: child,
        );
      },
    ),
  );
}
