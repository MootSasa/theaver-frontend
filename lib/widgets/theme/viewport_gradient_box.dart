import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Provides a scoped ancestor [GlobalKey] to anchor viewport gradients
/// inside custom preview widgets (such as [ChatPreviewCard]).
class ChatViewportScope extends InheritedWidget {
  final GlobalKey scopeKey;

  const ChatViewportScope({
    Key? key,
    required this.scopeKey,
    required Widget child,
  }) : super(key: key, child: child);

  static GlobalKey? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<ChatViewportScope>()?.scopeKey;
  }

  @override
  bool updateShouldNotify(covariant ChatViewportScope oldWidget) =>
      scopeKey != oldWidget.scopeKey;
}

/// Provides explicit global viewport gradient bounds for widgets rendered in an
/// overlay (such as the separated focused message inside [MessageContextMenu])
/// so their [ViewportGradientBox] shader matches the in-list message pixel-for-pixel.
class ViewportGradientBoundsScope extends InheritedWidget {
  final Rect globalBounds;

  const ViewportGradientBoundsScope({
    Key? key,
    required this.globalBounds,
    required Widget child,
  }) : super(key: key, child: child);

  static Rect? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<ViewportGradientBoundsScope>()
        ?.globalBounds;
  }

  /// Resolves the exact global gradient bounds (`left`, `top`, `right`, `bottom`)
  /// used by [RenderViewportGradientBox] for an in-list message [origin] render object.
  static Rect? resolveFromRenderObject(RenderObject? origin) {
    if (origin == null || !origin.attached) return null;
    try {
      final ancestorViewport = RenderAbstractViewport.maybeOf(origin);
      final viewportBox =
          ancestorViewport is RenderBox ? (ancestorViewport as RenderBox) : null;
      if (viewportBox != null &&
          viewportBox.attached &&
          viewportBox.hasSize &&
          viewportBox.size.height > 10.0) {
        RenderSliverPadding? sliverPadding;
        RenderObject? cur = origin.parent;
        while (cur != null && cur != viewportBox) {
          if (cur is RenderSliverPadding) {
            sliverPadding = cur;
            break;
          }
          cur = cur.parent;
        }
        double topPadding = 0.0;
        double bottomPadding = 0.0;
        final insets = sliverPadding?.resolvedPadding;
        if (insets != null) {
          topPadding = insets.top;
          bottomPadding = insets.bottom;
        }
        final effectiveHeight =
            viewportBox.size.height - topPadding - bottomPadding;
        final double gradientStartInViewport = topPadding;
        final double gradientEndInViewport = (effectiveHeight > 100.0)
            ? (viewportBox.size.height - bottomPadding)
            : viewportBox.size.height;

        final viewportGlobalOrigin = viewportBox.localToGlobal(Offset.zero);
        return Rect.fromLTRB(
          viewportGlobalOrigin.dx,
          viewportGlobalOrigin.dy + gradientStartInViewport,
          viewportGlobalOrigin.dx + viewportBox.size.width,
          viewportGlobalOrigin.dy + gradientEndInViewport,
        );
      }
    } catch (_) {}
    return null;
  }

  @override
  bool updateShouldNotify(covariant ViewportGradientBoundsScope oldWidget) =>
      globalBounds != oldWidget.globalBounds;
}

/// A widget that renders a continuous, viewport-bound linear gradient
/// behind its child clipped to the specified [borderRadius].
///
/// When messages scroll inside a ListView, each bubble acts as a dynamic mask/window
/// revealing its slice of the continuous chat viewport gradient.
///
/// Automatically listens to the ancestor [ScrollPosition] to repaint on each scroll
/// frame with zero layout overhead.
///
/// Supports per-color transparency/alpha so wallpapers and pattern doodles
/// underneath can shine through the bubble.
class ViewportGradientBox extends StatefulWidget {
  final List<Color>? gradientColors;
  final List<double>? gradientStops;
  final Color? solidColor;
  final BorderRadius borderRadius;
  final GlobalKey? viewportScopeKey;
  final Widget child;

  const ViewportGradientBox({
    Key? key,
    required this.child,
    this.gradientColors,
    this.gradientStops,
    this.solidColor,
    this.borderRadius = BorderRadius.zero,
    this.viewportScopeKey,
  }) : super(key: key);

  @override
  State<ViewportGradientBox> createState() => _ViewportGradientBoxState();
}

class _ViewportGradientBoxState extends State<ViewportGradientBox> {
  ScrollPosition? _scrollPosition;
  double _lastScrollPixels = double.nan;

  static bool _hasDistinctGradient(List<Color>? colors) {
    if (colors == null || colors.length < 2) return false;
    final first = colors.first;
    for (int i = 1; i < colors.length; i++) {
      if (colors[i] != first) return true;
    }
    return false;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _updateScrollListener();
  }

  @override
  void didUpdateWidget(covariant ViewportGradientBox oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateScrollListener();
  }

  void _updateScrollListener() {
    final bool hasGradient = _hasDistinctGradient(widget.gradientColors);
    if (!hasGradient) {
      if (_scrollPosition != null) {
        _scrollPosition!.removeListener(_onScroll);
        _scrollPosition = null;
      }
      return;
    }

    final newPosition = Scrollable.maybeOf(context)?.position;
    if (_scrollPosition != newPosition) {
      _scrollPosition?.removeListener(_onScroll);
      _scrollPosition = newPosition;
      _lastScrollPixels = newPosition?.pixels ?? double.nan;
      _scrollPosition?.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    _scrollPosition?.removeListener(_onScroll);
    _scrollPosition = null;
    super.dispose();
  }

  void _onScroll() {
    final pos = _scrollPosition;
    if (pos != null && pos.hasPixels) {
      final pixels = pos.pixels;
      if (!_lastScrollPixels.isNaN && (pixels - _lastScrollPixels).abs() < 10.0) {
        return;
      }
      _lastScrollPixels = pixels;
    }
    final ro = context.findRenderObject();
    if (ro is RenderViewportGradientBox && ro.attached) {
      if (ro.isVisibleInViewport) {
        ro.markNeedsPaint();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectiveScopeKey =
        widget.viewportScopeKey ?? ChatViewportScope.of(context);
    final globalGradientBounds = ViewportGradientBoundsScope.maybeOf(context);
    final mediaQuerySize = MediaQuery.maybeSizeOf(context);
    final bool hasGradient = _hasDistinctGradient(widget.gradientColors);
    final Color? effectiveSolidColor = hasGradient
        ? widget.solidColor
        : ((widget.gradientColors != null && widget.gradientColors!.isNotEmpty)
            ? widget.gradientColors!.first
            : widget.solidColor);

    return _RawViewportGradientBox(
      gradientColors: hasGradient ? widget.gradientColors : null,
      gradientStops: hasGradient ? widget.gradientStops : null,
      solidColor: effectiveSolidColor,
      borderRadius: widget.borderRadius,
      viewportScopeKey: effectiveScopeKey,
      globalGradientBounds: globalGradientBounds,
      fallbackScreenSize: mediaQuerySize,
      child: hasGradient ? RepaintBoundary(child: widget.child) : widget.child,
    );
  }
}

class _RawViewportGradientBox extends SingleChildRenderObjectWidget {
  final List<Color>? gradientColors;
  final List<double>? gradientStops;
  final Color? solidColor;
  final BorderRadius borderRadius;
  final GlobalKey? viewportScopeKey;
  final Rect? globalGradientBounds;
  final Size? fallbackScreenSize;

  const _RawViewportGradientBox({
    Key? key,
    required Widget child,
    this.gradientColors,
    this.gradientStops,
    this.solidColor,
    this.borderRadius = BorderRadius.zero,
    this.viewportScopeKey,
    this.globalGradientBounds,
    this.fallbackScreenSize,
  }) : super(key: key, child: child);

  @override
  RenderViewportGradientBox createRenderObject(BuildContext context) {
    return RenderViewportGradientBox(
      gradientColors: gradientColors,
      gradientStops: gradientStops,
      solidColor: solidColor,
      borderRadius: borderRadius,
      viewportScopeKey: viewportScopeKey,
      globalGradientBounds: globalGradientBounds,
      fallbackScreenSize: fallbackScreenSize,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderViewportGradientBox renderObject,
  ) {
    renderObject
      ..gradientColors = gradientColors
      ..gradientStops = gradientStops
      ..solidColor = solidColor
      ..borderRadius = borderRadius
      ..viewportScopeKey = viewportScopeKey
      ..globalGradientBounds = globalGradientBounds
      ..fallbackScreenSize = fallbackScreenSize;
  }
}

class RenderViewportGradientBox extends RenderProxyBox {
  List<Color>? _gradientColors;
  List<double>? _gradientStops;
  List<double>? _effectiveStops;
  Color? _solidColor;
  BorderRadius _borderRadius;
  GlobalKey? _viewportScopeKey;
  Rect? _globalGradientBounds;
  Size? _fallbackScreenSize;

  final Paint _gradientPaint = Paint()..isAntiAlias = true;
  final Paint _solidPaint = Paint()..isAntiAlias = true;

  RenderBox? _cachedViewportBox;
  RenderSliverPadding? _cachedSliverPadding;
  bool _ancestorsResolved = false;

  RenderViewportGradientBox({
    RenderBox? child,
    List<Color>? gradientColors,
    List<double>? gradientStops,
    Color? solidColor,
    BorderRadius borderRadius = BorderRadius.zero,
    GlobalKey? viewportScopeKey,
    Rect? globalGradientBounds,
    Size? fallbackScreenSize,
  })  : _gradientColors = gradientColors,
        _gradientStops = gradientStops,
        _solidColor = solidColor,
        _borderRadius = borderRadius,
        _viewportScopeKey = viewportScopeKey,
        _globalGradientBounds = globalGradientBounds,
        _fallbackScreenSize = fallbackScreenSize,
        super(child) {
    _updateEffectiveStops();
  }

  void _updateEffectiveStops() {
    if (_gradientColors == null || _gradientColors!.length < 2) {
      _effectiveStops = null;
      return;
    }
    final int colorCount = _gradientColors!.length;
    if (_gradientStops != null && _gradientStops!.length == colorCount) {
      _effectiveStops = _gradientStops;
    } else {
      _effectiveStops = List<double>.generate(colorCount, (i) => i / (colorCount - 1));
    }
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _ancestorsResolved = false;
  }

  @override
  void detach() {
    _cachedViewportBox = null;
    _cachedSliverPadding = null;
    _ancestorsResolved = false;
    super.detach();
  }

  void _resolveAncestors() {
    if (_ancestorsResolved) return;
    _ancestorsResolved = true;
    final ancestorViewport = RenderAbstractViewport.maybeOf(this);
    _cachedViewportBox = ancestorViewport is RenderBox
        ? (ancestorViewport as RenderBox)
        : null;
    if (_cachedViewportBox != null) {
      RenderObject? cur = parent;
      while (cur != null && cur != _cachedViewportBox) {
        if (cur is RenderSliverPadding) {
          _cachedSliverPadding = cur;
          break;
        }
        cur = cur.parent;
      }
    }
  }

  bool get isVisibleInViewport {
    if (!hasSize) return false;
    _resolveAncestors();
    final viewportBox = _cachedViewportBox;
    if (viewportBox != null && viewportBox.attached && viewportBox.hasSize) {
      final pos = localToGlobal(Offset.zero, ancestor: viewportBox);
      return pos.dy + size.height >= -16.0 &&
          pos.dy <= viewportBox.size.height + 16.0;
    }
    return true;
  }

  List<Color>? get gradientColors => _gradientColors;
  set gradientColors(List<Color>? val) {
    if (_gradientColors == val) return;
    _gradientColors = val;
    _updateEffectiveStops();
    markNeedsPaint();
  }

  List<double>? get gradientStops => _gradientStops;
  set gradientStops(List<double>? val) {
    if (_gradientStops == val) return;
    _gradientStops = val;
    _updateEffectiveStops();
    markNeedsPaint();
  }

  Color? get solidColor => _solidColor;
  set solidColor(Color? val) {
    if (_solidColor == val) return;
    _solidColor = val;
    markNeedsPaint();
  }

  BorderRadius get borderRadius => _borderRadius;
  set borderRadius(BorderRadius val) {
    if (_borderRadius == val) return;
    _borderRadius = val;
    markNeedsPaint();
  }

  GlobalKey? get viewportScopeKey => _viewportScopeKey;
  set viewportScopeKey(GlobalKey? val) {
    if (_viewportScopeKey == val) return;
    _viewportScopeKey = val;
    markNeedsPaint();
  }

  Rect? get globalGradientBounds => _globalGradientBounds;
  set globalGradientBounds(Rect? val) {
    if (_globalGradientBounds == val) return;
    _globalGradientBounds = val;
    markNeedsPaint();
  }

  Size? get fallbackScreenSize => _fallbackScreenSize;
  set fallbackScreenSize(Size? val) {
    if (_fallbackScreenSize == val) return;
    _fallbackScreenSize = val;
    markNeedsPaint();
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final canvas = context.canvas;
    final Rect rect = offset & size;
    final RRect rrect = _borderRadius.toRRect(rect);

    try {
      final bool hasValidGradient = _gradientColors != null && _gradientColors!.length >= 2;

      if (hasValidGradient) {
        double topInCanvas = offset.dy;
        double bottomInCanvas = offset.dy + size.height;
        double centerXInCanvas = offset.dx + size.width * 0.5;

        // 1. Check if anchored to a custom scoped ancestor (e.g. ChatPreviewCard)
        RenderBox? scopeBox;
        final scopeContext = _viewportScopeKey?.currentContext;
        if (scopeContext != null && scopeContext.findRenderObject() is RenderBox) {
          scopeBox = scopeContext.findRenderObject() as RenderBox;
        }

        if (scopeBox != null && scopeBox.attached && scopeBox.hasSize && scopeBox.size.height > 10.0) {
          final originInScope = localToGlobal(Offset.zero, ancestor: scopeBox);
          topInCanvas = offset.dy - originInScope.dy;
          bottomInCanvas = topInCanvas + scopeBox.size.height;
          centerXInCanvas = offset.dx - originInScope.dx + scopeBox.size.width * 0.5;
        } else {
          // 2. Check if inside a scrolling viewport (ListView in chat screens)
          _resolveAncestors();
          final RenderBox? viewportBox = (_cachedViewportBox != null && _cachedViewportBox!.attached)
              ? _cachedViewportBox
              : null;

          if (viewportBox != null && viewportBox.hasSize && viewportBox.size.height > 10.0) {
            final posInViewport = localToGlobal(Offset.zero, ancestor: viewportBox);

            // Cached sliver padding (topPadding / bottomPadding of chat list)
            double topPadding = 0.0;
            double bottomPadding = 0.0;
            final insets = _cachedSliverPadding?.resolvedPadding;
            if (insets != null) {
              topPadding = insets.top;
              bottomPadding = insets.bottom;
            }

            final effectiveHeight = viewportBox.size.height - topPadding - bottomPadding;
            final double gradientStartInViewport = topPadding;
            final double gradientEndInViewport = (effectiveHeight > 100.0)
                ? (viewportBox.size.height - bottomPadding)
                : viewportBox.size.height;

            topInCanvas = offset.dy - (posInViewport.dy - gradientStartInViewport);
            bottomInCanvas = offset.dy + (gradientEndInViewport - posInViewport.dy);
            centerXInCanvas = offset.dx - posInViewport.dx + viewportBox.size.width * 0.5;
          } else if (_globalGradientBounds != null && _globalGradientBounds!.height > 10.0) {
            // 2b. Overlay widget anchored to an in-list message's resolved viewport gradient bounds
            final globalPos = localToGlobal(Offset.zero);
            final bounds = _globalGradientBounds!;
            topInCanvas = offset.dy - (globalPos.dy - bounds.top);
            bottomInCanvas = offset.dy + (bounds.bottom - globalPos.dy);
            centerXInCanvas = offset.dx - (globalPos.dx - bounds.center.dx);
          } else {
            // 3. Fallback: Full screen dimensions
            final globalPos = localToGlobal(Offset.zero);
            double screenH = _fallbackScreenSize?.height ?? 0.0;
            double screenW = _fallbackScreenSize?.width ?? 0.0;

            if (screenH <= 0.0 || screenW <= 0.0) {
              try {
                final view = WidgetsBinding.instance.platformDispatcher.views.first;
                screenH = view.physicalSize.height / view.devicePixelRatio;
                screenW = view.physicalSize.width / view.devicePixelRatio;
              } catch (_) {
                screenH = 800.0;
                screenW = 390.0;
              }
            }

            topInCanvas = offset.dy - globalPos.dy;
            bottomInCanvas = topInCanvas + screenH;
            centerXInCanvas = offset.dx - globalPos.dx + screenW * 0.5;
          }
        }

        // Safety: Ensure start and end offsets are distinct and finite
        if (!topInCanvas.isFinite || !bottomInCanvas.isFinite || (bottomInCanvas - topInCanvas).abs() < 1.0) {
          topInCanvas = offset.dy;
          bottomInCanvas = offset.dy + size.height;
          centerXInCanvas = offset.dx + size.width * 0.5;
        }

        final List<double> stops = _effectiveStops ?? const [0.0, 1.0];

        final shader = ui.Gradient.linear(
          Offset(centerXInCanvas, topInCanvas),
          Offset(centerXInCanvas, bottomInCanvas),
          _gradientColors!,
          stops,
        );

        _gradientPaint.shader = shader;
        canvas.drawRRect(rrect, _gradientPaint);
      } else if (_solidColor != null && _solidColor != Colors.transparent) {
        _solidPaint.color = _solidColor!;
        canvas.drawRRect(rrect, _solidPaint);
      }
    } catch (e) {
      debugPrint('ViewportGradientBox.paint error: $e');
      if (_solidColor != null && _solidColor != Colors.transparent) {
        _solidPaint.color = _solidColor!;
        canvas.drawRRect(rrect, _solidPaint);
      }
    } finally {
      // Paint child content (text, timestamp, sender, icons) over the bubble background.
      super.paint(context, offset);
    }
  }
}
