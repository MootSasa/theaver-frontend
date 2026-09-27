import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:motor/motor.dart';

import '../../utils/haptic_utils.dart';

/// Создаёт матрицу jelly-трансформации.
Matrix4 _buildJellyTransform({
  required Offset velocity,
  double maxDistortion = 0.35,
  double velocityScale = 500.0,
}) {
  final speed = velocity.distance;
  final direction = speed > 0 ? velocity / speed : Offset.zero;
  final distortionFactor =
      (speed / velocityScale).clamp(0.0, 1.0) * maxDistortion;

  if (distortionFactor == 0) {
    return Matrix4.identity();
  }

  final squashX = 1.0 - (direction.dx.abs() * distortionFactor * 0.5);
  final squashY = 1.0 - (direction.dy.abs() * distortionFactor * 0.5);
  final stretchX = 1.0 + (direction.dy.abs() * distortionFactor * 0.3);
  final stretchY = 1.0 + (direction.dx.abs() * distortionFactor * 0.3);

  final scaleX = squashX * stretchX;
  final scaleY = squashY * stretchY;

  return Matrix4.diagonal3Values(scaleX, scaleY, 1.0);
}

/// Фильтры чатов (Все, Личные, Группы, Каналы) с Liquid Glass эффектом.
class LiquidGlassFilterChips extends StatefulWidget {
  final bool enabled;
  final List<String> filters;
  final int activeFilter;
  final ValueChanged<int> onFilterSelected;
  final List<int> unreadCounts;

  /// Включён ли облегчённый режим
  final bool isLite;

  /// Угол падения света для бликов (от гироскопа или ручной настройки)
  final double? lightAngle;

  const LiquidGlassFilterChips({
    Key? key,
    required this.enabled,
    required this.filters,
    required this.activeFilter,
    required this.onFilterSelected,
    this.unreadCounts = const [],
    this.isLite = false,
    this.lightAngle,
  }) : super(key: key);

  @override
  State<LiquidGlassFilterChips> createState() => _LiquidGlassFilterChipsState();
}

class _LiquidGlassFilterChipsState extends State<LiquidGlassFilterChips> {
  @override
  Widget build(BuildContext context) {
    if (widget.enabled) {
      return _buildGlassFilters(context);
    }
    return _buildClassicFilters(context);
  }

  Widget _buildClassicFilters(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;
    final theme = Theme.of(context);

    final bgColor = isDark ? const Color(0xFF2C2C2E) : Colors.white;
    final borderColor = isDark
        ? Colors.white.withValues(alpha: 0.08)
        : Colors.black.withValues(alpha: 0.04);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Container(
        height: 36,
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: borderColor, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.2)
                  : Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (int i = 0; i < widget.filters.length; i++)
              Expanded(
                child: _ClassicFilterChip(
                  label: widget.filters[i],
                  unreadCount: i < widget.unreadCounts.length
                      ? widget.unreadCounts[i]
                      : 0,
                  isActive: widget.activeFilter == i,
                  isDark: isDark,
                  theme: theme,
                  onTap: () {
                    HapticUtils.selection();
                    widget.onFilterSelected(i);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Glass-версия на базе LiquidGlassLens
  Widget _buildGlassFilters(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;
    final theme = Theme.of(context);

    final shape = LiquidGlassShape.continuousRoundedRectangle(
      cornerRadius: 18,
      clipQuality: LiquidGlassClipQuality.exact,
      borderWidth: 0.7,
      lightIntensity: 0.9,
      lightDirection: widget.lightAngle ?? 62.0,
      borderType: const OpticalBorder(
        borderSaturation: 1.1,
        ambientIntensity: 0.85,
        borderSolidity: 0.95,
      ),
    );

    final style = LiquidGlassStyle(
      shape: shape,
      appearance: LiquidGlassAppearance(
        color: isDark ? const Color(0x33202025) : const Color(0x8FFFFFFF),
        blur: const LiquidGlassBlur(sigmaX: 5, sigmaY: 5),
        shadow: const LiquidGlassShadow(blur: 8, opacity: 0.12),
      ),
      refraction: const LiquidGlassRefraction(
        distortion: 0.05,
        distortionWidth: 20,
      ),
      liteGlass: widget.isLite ? LiquidGlassLitePickup.surface : null,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: SizedBox(
        height: 36,
        child: LiquidGlassLens(
          style: style,
          child: _FilterIndicator(
            tabIndex: widget.activeFilter,
            tabCount: widget.filters.length,
            onTabChanged: widget.onFilterSelected,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                for (var i = 0; i < widget.filters.length; i++)
                  Expanded(
                    child: _GlassFilterChip(
                      label: widget.filters[i],
                      unreadCount: i < widget.unreadCounts.length
                          ? widget.unreadCounts[i]
                          : 0,
                      isActive: widget.activeFilter == i,
                      isDark: isDark,
                      theme: theme,
                      onTap: () {
                        HapticUtils.selection();
                        widget.onFilterSelected(i);
                      },
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Glass-фильтр
// ============================================================

class _GlassFilterChip extends StatelessWidget {
  const _GlassFilterChip({
    required this.label,
    required this.unreadCount,
    required this.isActive,
    required this.isDark,
    required this.theme,
    required this.onTap,
  });

  final String label;
  final int unreadCount;
  final bool isActive;
  final bool isDark;
  final ThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = isActive
        ? theme.colorScheme.primary
        : (isDark ? Colors.white54 : Colors.black54);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Semantics(
        button: true,
        label: label,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedScale(
                scale: isActive ? 1.05 : 1.0,
                duration: const Duration(milliseconds: 150),
                child: Text(
                  label,
                  maxLines: 1,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: textColor,
                    fontSize: 13,
                    fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (unreadCount > 0) ...[
                const SizedBox(width: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 5, vertical: 1),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(minWidth: 16),
                  child: Text(
                    '$unreadCount',
                    style: TextStyle(
                      color: isDark ? Colors.black : Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// Classic-фильтр (без glass)
// ============================================================

class _ClassicFilterChip extends StatelessWidget {
  const _ClassicFilterChip({
    required this.label,
    required this.unreadCount,
    required this.isActive,
    required this.isDark,
    required this.theme,
    required this.onTap,
  });

  final String label;
  final int unreadCount;
  final bool isActive;
  final bool isDark;
  final ThemeData theme;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final textColor = isActive
        ? theme.colorScheme.primary
        : (isDark ? Colors.white70 : Colors.black54);

    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 13,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            if (unreadCount > 0) ...[
              const SizedBox(width: 4),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(10),
                ),
                constraints: const BoxConstraints(minWidth: 16),
                child: Text(
                  '$unreadCount',
                  style: TextStyle(
                    color: isDark ? Colors.black : Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ============================================================
// Скользящий glass-индикатор
// ============================================================

class _FilterIndicator extends StatefulWidget {
  const _FilterIndicator({
    required this.child,
    required this.tabIndex,
    required this.tabCount,
    required this.onTabChanged,
  });

  final int tabIndex;
  final int tabCount;
  final Widget child;
  final ValueChanged<int> onTabChanged;

  @override
  State<_FilterIndicator> createState() => _FilterIndicatorState();
}

class _FilterIndicatorState extends State<_FilterIndicator> {
  bool _isDragging = false;

  late double xAlign = _computeXAlignmentForTab(widget.tabIndex);

  double _computeXAlignmentForTab(int tabIndex) {
    if (widget.tabCount <= 1) return 0;
    final relativeTabIndex =
        (tabIndex / (widget.tabCount - 1)).clamp(0.0, 1.0);
    return (relativeTabIndex * 2) - 1; // от -1 до 1
  }

  @override
  void didUpdateWidget(covariant _FilterIndicator oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.tabIndex != widget.tabIndex ||
        oldWidget.tabCount != widget.tabCount) {
      setState(() {
        xAlign = _computeXAlignmentForTab(widget.tabIndex);
      });
    }
  }

  double _getAlignmentFromGlobalPosition(Offset globalPosition) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.width <= 0) return 0;
    final localPosition = box.globalToLocal(globalPosition);

    final indicatorWidth = 1.0 / widget.tabCount;
    final draggableRange = 1.0 - indicatorWidth;
    final padding = indicatorWidth / 2;

    final rawRelativeX =
        (localPosition.dx / box.size.width).clamp(0.0, 1.0);
    final normalizedX = (rawRelativeX - padding) / draggableRange;

    final adjustedRelativeX = _applyRubberBandResistance(normalizedX);
    return (adjustedRelativeX * 2) - 1;
  }

  double _applyRubberBandResistance(double value) {
    const double resistance = 0.4;
    const double maxOverdrag = 0.3;

    if (value < 0) {
      final overdrag = -value;
      final resistedOverdrag = overdrag * resistance;
      return -resistedOverdrag.clamp(0.0, maxOverdrag);
    } else if (value > 1) {
      final overdrag = value - 1;
      final resistedOverdrag = overdrag * resistance;
      return 1 + resistedOverdrag.clamp(0.0, maxOverdrag);
    } else {
      return value;
    }
  }

  void _onDragDown(DragDownDetails details) {
    setState(() {
      xAlign = _getAlignmentFromGlobalPosition(details.globalPosition);
    });
  }

  void _onDragUpdate(DragUpdateDetails details) {
    setState(() {
      _isDragging = true;
      xAlign = _getAlignmentFromGlobalPosition(details.globalPosition);
    });
  }

  void _onDragEnd(DragEndDetails details) {
    setState(() {
      _isDragging = false;
    });

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize || box.size.width <= 0) return;
    final currentRelativeX = (xAlign + 1) / 2;
    final tabWidth = 1.0 / widget.tabCount;

    final indicatorWidth = 1.0 / widget.tabCount;
    final draggableRange = 1.0 - indicatorWidth;
    final velocityX =
        (details.velocity.pixelsPerSecond.dx / box.size.width) /
            draggableRange;

    int targetTabIndex;

    if (currentRelativeX < 0) {
      targetTabIndex = 0;
    } else if (currentRelativeX > 1) {
      targetTabIndex = widget.tabCount - 1;
    } else {
      const velocityThreshold = 0.5;
      if (velocityX.abs() > velocityThreshold) {
        final projectedX =
            (currentRelativeX + velocityX * 0.3).clamp(0.0, 1.0);
        targetTabIndex =
            (projectedX / tabWidth).round().clamp(0, widget.tabCount - 1);

        final currentTabIndex =
            (currentRelativeX / tabWidth).round().clamp(0, widget.tabCount - 1);
        if (velocityX > velocityThreshold &&
            targetTabIndex <= currentTabIndex &&
            currentTabIndex < widget.tabCount - 1) {
          targetTabIndex = currentTabIndex + 1;
        } else if (velocityX < -velocityThreshold &&
            targetTabIndex >= currentTabIndex &&
            currentTabIndex > 0) {
          targetTabIndex = currentTabIndex - 1;
        }
      } else {
        targetTabIndex =
            (currentRelativeX / tabWidth).round().clamp(0, widget.tabCount - 1);
      }
    }

    xAlign = _computeXAlignmentForTab(targetTabIndex);

    if (targetTabIndex != widget.tabIndex) {
      widget.onTabChanged(targetTabIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final brightness = MediaQuery.platformBrightnessOf(context);
    final isDark = brightness == Brightness.dark;
    final indicatorColor = isDark
        ? const Color(0x38FFFFFF)
        : const Color(0x2EAEAEB2);

    return GestureDetector(
      onHorizontalDragDown: _onDragDown,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      onHorizontalDragCancel: () => setState(() {
        _isDragging = false;
      }),
      child: VelocityMotionBuilder(
        converter: const SingleMotionConverter(),
        value: xAlign,
        motion: _isDragging
            ? const Motion.interactiveSpring(snapToEnd: true)
            : const Motion.bouncySpring(snapToEnd: true),
        builder: (context, value, velocity, child) {
          final alignment = Alignment(value.clamp(-1.0, 1.0), 0);
          return Stack(
            children: [
              // Sliding soft-pill indicator
              Positioned.fill(
                left: 3,
                right: 3,
                top: 3,
                bottom: 3,
                child: Align(
                  alignment: alignment,
                  child: FractionallySizedBox(
                    widthFactor:
                        widget.tabCount > 0 ? (1.0 / widget.tabCount) : 1.0,
                    child: Transform(
                      alignment: Alignment.center,
                      transform: _buildJellyTransform(
                        velocity: Offset(velocity, 0),
                        maxDistortion: 0.35,
                        velocityScale: 500,
                      ),
                      child: Container(
                        decoration: BoxDecoration(
                          color: indicatorColor,
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              child!,
            ],
          );
        },
        child: widget.child,
      ),
    );
  }
}
