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

/// A RenderBox widget that renders a continuous, viewport-bound linear gradient
/// behind its child clipped to the specified [borderRadius].
///
/// When messages scroll inside a ListView, each bubble acts as a dynamic mask/window
/// revealing its slice of the continuous full-screen gradient.
///
/// Supports per-color transparency/alpha so wallpapers and pattern doodles
/// underneath can shine through the bubble.
class ViewportGradientBox extends SingleChildRenderObjectWidget {
  final List<Color>? gradientColors;
  final List<double>? gradientStops;
  final Color? solidColor;
  final BorderRadius borderRadius;
  final GlobalKey? viewportScopeKey;

  const ViewportGradientBox({
    Key? key,
    required Widget child,
    this.gradientColors,
    this.gradientStops,
    this.solidColor,
    this.borderRadius = BorderRadius.zero,
    this.viewportScopeKey,
  }) : super(key: key, child: child);

  @override
  RenderViewportGradientBox createRenderObject(BuildContext context) {
    final effectiveScopeKey = viewportScopeKey ?? ChatViewportScope.of(context);
    final mediaQuerySize = MediaQuery.maybeSizeOf(context);

    return RenderViewportGradientBox(
      gradientColors: gradientColors,
      gradientStops: gradientStops,
      solidColor: solidColor,
      borderRadius: borderRadius,
      viewportScopeKey: effectiveScopeKey,
      fallbackScreenSize: mediaQuerySize,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    RenderViewportGradientBox renderObject,
  ) {
    final effectiveScopeKey = viewportScopeKey ?? ChatViewportScope.of(context);
    final mediaQuerySize = MediaQuery.maybeSizeOf(context);

    renderObject
      ..gradientColors = gradientColors
      ..gradientStops = gradientStops
      ..solidColor = solidColor
      ..borderRadius = borderRadius
      ..viewportScopeKey = effectiveScopeKey
      ..fallbackScreenSize = mediaQuerySize;
  }
}

class RenderViewportGradientBox extends RenderProxyBox {
  List<Color>? _gradientColors;
  List<double>? _gradientStops;
  Color? _solidColor;
  BorderRadius _borderRadius;
  GlobalKey? _viewportScopeKey;
  Size? _fallbackScreenSize;

  RenderViewportGradientBox({
    RenderBox? child,
    List<Color>? gradientColors,
    List<double>? gradientStops,
    Color? solidColor,
    BorderRadius borderRadius = BorderRadius.zero,
    GlobalKey? viewportScopeKey,
    Size? fallbackScreenSize,
  })  : _gradientColors = gradientColors,
        _gradientStops = gradientStops,
        _solidColor = solidColor,
        _borderRadius = borderRadius,
        _viewportScopeKey = viewportScopeKey,
        _fallbackScreenSize = fallbackScreenSize,
        super(child);

  List<Color>? get gradientColors => _gradientColors;
  set gradientColors(List<Color>? val) {
    if (_gradientColors == val) return;
    _gradientColors = val;
    markNeedsPaint();
  }

  List<double>? get gradientStops => _gradientStops;
  set gradientStops(List<double>? val) {
    if (_gradientStops == val) return;
    _gradientStops = val;
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

    final bool hasValidGradient = _gradientColors != null && _gradientColors!.length >= 2;

    if (hasValidGradient) {
      double topInCanvas = 0.0;
      double bottomInCanvas = 0.0;
      double centerXInCanvas = 0.0;

      // 1. Check if anchored to a custom scoped ancestor (e.g. ChatPreviewCard)
      RenderBox? scopeBox;
      final scopeContext = _viewportScopeKey?.currentContext;
      if (scopeContext != null && scopeContext.findRenderObject() is RenderBox) {
        scopeBox = scopeContext.findRenderObject() as RenderBox;
      }

      if (scopeBox != null && scopeBox.attached && scopeBox.hasSize) {
        final originInScope = localToGlobal(Offset.zero, ancestor: scopeBox);
        topInCanvas = offset.dy - originInScope.dy;
        bottomInCanvas = topInCanvas + scopeBox.size.height;
        centerXInCanvas = offset.dx - originInScope.dx + scopeBox.size.width * 0.5;
      } else {
        // 2. Full-screen viewport binding
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

      final shader = ui.Gradient.linear(
        Offset(centerXInCanvas, topInCanvas),
        Offset(centerXInCanvas, bottomInCanvas),
        _gradientColors!,
        _gradientStops,
      );

      final paint = Paint()
        ..shader = shader
        ..isAntiAlias = true;

      canvas.drawRRect(rrect, paint);
    } else if (_solidColor != null && _solidColor != Colors.transparent) {
      final paint = Paint()
        ..color = _solidColor!
        ..isAntiAlias = true;

      canvas.drawRRect(rrect, paint);
    }

    // Paint child content (text, timestamp, sender, icons) over the bubble background
    super.paint(context, offset);
  }
}
