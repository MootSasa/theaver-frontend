import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import '../../services/tiling_layout_controller.dart';

/// Тонкий разделитель (1–2px) между тайлами с всегда видимой ручкой-капсулой
/// (в стиле iPadOS Split View) и расширенной зоной захвата, накладываемой поверх стыка
/// (`14px` вдоль всей линии и `28×64px` вокруг центральной капсулы).
class TileResizeDivider extends StatefulWidget {
  /// Физическая ширина видимого стыка между тайлами.
  static const double kSeamThickness = 1.0;

  /// Ширина/высота оверлейного контейнера разделителя в `Stack`.
  static const double kOverlaySpan = 28.0;

  /// Ширина зоны захвата вдоль всей разделительной линии.
  static const double kLineHitSpan = 14.0;

  /// Поперечный и продольный размер расширенной зоны захвата вокруг центральной капсулы.
  static const double kHandleHitThickness = 28.0;
  static const double kHandleHitLength = 64.0;

  /// Ось разделительной линии:
  /// - [Axis.vertical] — вертикальная линия между левым и правым тайлом (движение по X)
  /// - [Axis.horizontal] — горизонтальная линия между верхним и нижним тайлом (движение по Y)
  final Axis lineAxis;
  final ValueChanged<double> onDelta;
  final VoidCallback? onDoubleTap;

  const TileResizeDivider({
    super.key,
    required this.lineAxis,
    required this.onDelta,
    this.onDoubleTap,
  });

  @override
  State<TileResizeDivider> createState() => _TileResizeDividerState();
}

class _TileResizeDividerState extends State<TileResizeDivider> {
  int _hoverCount = 0;
  bool _isDragging = false;

  bool get _isHovered => _hoverCount > 0;

  void _onEnterZone() {
    setState(() => _hoverCount++);
  }

  void _onExitZone() {
    setState(() => _hoverCount = (_hoverCount - 1).clamp(0, 10));
  }

  void _startDrag() {
    setState(() => _isDragging = true);
    TilingLayoutController.instance.setResizingDivider(true);
  }

  void _endDrag() {
    if (_isDragging) {
      setState(() => _isDragging = false);
    }
    TilingLayoutController.instance.setResizingDivider(false);
  }

  @override
  void dispose() {
    if (_isDragging) {
      TilingLayoutController.instance.setResizingDivider(false);
    }
    super.dispose();
  }

  Widget _wrapWithResizeGestures({
    required bool isVerticalLine,
    required MouseCursor cursor,
    required Widget child,
  }) {
    return MouseRegion(
      cursor: cursor,
      onEnter: (_) => _onEnterZone(),
      onExit: (_) => _onExitZone(),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onDoubleTap: widget.onDoubleTap,
        onHorizontalDragStart: isVerticalLine ? (_) => _startDrag() : null,
        onHorizontalDragUpdate: isVerticalLine
            ? (details) => widget.onDelta(details.delta.dx)
            : null,
        onHorizontalDragEnd: isVerticalLine ? (_) => _endDrag() : null,
        onHorizontalDragCancel: isVerticalLine ? _endDrag : null,
        onVerticalDragStart: !isVerticalLine ? (_) => _startDrag() : null,
        onVerticalDragUpdate: !isVerticalLine
            ? (details) => widget.onDelta(details.delta.dy)
            : null,
        onVerticalDragEnd: !isVerticalLine ? (_) => _endDrag() : null,
        onVerticalDragCancel: !isVerticalLine ? _endDrag : null,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final isActive = _isHovered || _isDragging;

    final baseLineColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.black.withValues(alpha: 0.10);
    final activeLineColor = primary.withValues(alpha: _isDragging ? 0.80 : 0.50);

    final idlePillColor = isDark
        ? const Color(0xB8FFFFFF)
        : const Color(0x8A1C1C1E);
    final pillBorderColor = isDark
        ? Colors.black.withValues(alpha: 0.35)
        : Colors.white.withValues(alpha: 0.65);

    final isVerticalLine = widget.lineAxis == Axis.vertical;
    final cursor = isVerticalLine
        ? SystemMouseCursors.resizeLeftRight
        : SystemMouseCursors.resizeUpDown;

    final double pillThickness = _isDragging
        ? 6.5
        : (_isHovered ? 6.0 : 5.0);
    final double pillLength = _isDragging
        ? 52.0
        : (_isHovered ? 46.0 : 38.0);

    return SizedBox(
      width: isVerticalLine ? TileResizeDivider.kOverlaySpan : double.infinity,
      height: isVerticalLine ? double.infinity : TileResizeDivider.kOverlaySpan,
      child: Stack(
        alignment: Alignment.center,
        children: [
          // 1. Тонкая 1–2px разделительная линия
          IgnorePointer(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              width: isVerticalLine ? (isActive ? 2.0 : 1.0) : double.infinity,
              height: isVerticalLine ? double.infinity : (isActive ? 2.0 : 1.0),
              color: isActive ? activeLineColor : baseLineColor,
            ),
          ),

          // 2. Полоса захвата (14px) вдоль всей границы
          _wrapWithResizeGestures(
            isVerticalLine: isVerticalLine,
            cursor: cursor,
            child: SizedBox(
              width: isVerticalLine
                  ? TileResizeDivider.kLineHitSpan
                  : double.infinity,
              height: isVerticalLine
                  ? double.infinity
                  : TileResizeDivider.kLineHitSpan,
            ),
          ),

          // 3. Расширенная зона захвата (28×64px) вокруг всегда видимой центральной ручки-капсулы
          _wrapWithResizeGestures(
            isVerticalLine: isVerticalLine,
            cursor: cursor,
            child: SizedBox(
              width: isVerticalLine
                  ? TileResizeDivider.kHandleHitThickness
                  : TileResizeDivider.kHandleHitLength,
              height: isVerticalLine
                  ? TileResizeDivider.kHandleHitLength
                  : TileResizeDivider.kHandleHitThickness,
              child: Center(
                child: AnimatedScale(
                  scale: _isDragging ? 1.08 : 1.0,
                  duration: const Duration(milliseconds: 150),
                  curve: Curves.easeOutBack,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 150),
                    curve: Curves.easeOutCubic,
                    width: isVerticalLine ? pillThickness : pillLength,
                    height: isVerticalLine ? pillLength : pillThickness,
                    decoration: BoxDecoration(
                      color: isActive ? primary : idlePillColor,
                      borderRadius: BorderRadius.circular(pillThickness),
                      border: Border.all(
                        color: isActive
                            ? primary.withValues(alpha: 0.9)
                            : pillBorderColor,
                        width: 0.75,
                      ),
                      boxShadow: [
                        if (isActive)
                          BoxShadow(
                            color: primary.withValues(
                              alpha: _isDragging ? 0.50 : 0.35,
                            ),
                            blurRadius: _isDragging ? 10 : 6,
                          )
                        else
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.18),
                            blurRadius: 3,
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
