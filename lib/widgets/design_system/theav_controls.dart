import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../utils/haptic_utils.dart';
import 'theav_design_system.dart';

/// Descriptor for one option inside [TheavSegmentedControl].
class TheavSegmentOption<T> {
  final T value;
  final String label;
  final Widget? icon;

  const TheavSegmentOption({
    required this.value,
    required this.label,
    this.icon,
  });
}

/// Sliding pill segmented control supporting both Liquid Glass (with a living
/// spring-driven [LiquidGlassMotionPill] supporting tap and horizontal drag)
/// and borderless Material Matte modes.
class TheavSegmentedControl<T> extends StatefulWidget {
  final List<TheavSegmentOption<T>> options;
  final T selected;
  final ValueChanged<T> onChanged;
  final double height;
  final EdgeInsetsGeometry margin;

  const TheavSegmentedControl({
    super.key,
    required this.options,
    required this.selected,
    required this.onChanged,
    this.height = 38.0,
    this.margin = EdgeInsets.zero,
  });

  @override
  State<TheavSegmentedControl<T>> createState() =>
      _TheavSegmentedControlState<T>();
}

class _TheavSegmentedControlState<T> extends State<TheavSegmentedControl<T>>
    with SingleTickerProviderStateMixin {
  static const double _pillStiffness = 260.0;
  static const double _pillDamping = 28.0;

  late double _fractionalIndex;
  double _indexVel = 0.0;
  double? _targetIndex;
  bool _lifted = false;
  bool _isDragging = false;
  bool _glassVisible = false;
  Ticker? _glideTicker;
  Duration? _lastTickElapsed;
  final LiquidGlassViewController _viewController = LiquidGlassViewController();

  int _selectedIndex() {
    final int idx =
        widget.options.indexWhere((o) => o.value == widget.selected);
    return idx < 0 ? 0 : idx;
  }

  @override
  void initState() {
    super.initState();
    _fractionalIndex = _selectedIndex().toDouble();
    _glideTicker = createTicker(_onGlideTick);
  }

  @override
  void didUpdateWidget(covariant TheavSegmentedControl<T> oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.options.isEmpty) return;
    final int newIdx = _selectedIndex();
    final int maxIdx = widget.options.length - 1;
    if (!_isDragging && oldWidget.selected != widget.selected) {
      _animateToSegment(newIdx);
    } else if (_fractionalIndex > maxIdx) {
      _fractionalIndex = newIdx.toDouble();
      _indexVel = 0.0;
      _targetIndex = null;
      _lifted = false;
    }
  }

  @override
  void dispose() {
    _glideTicker?.dispose();
    _viewController.detach();
    super.dispose();
  }

  void _ensureTicking() {
    final ticker = _glideTicker;
    if (ticker != null && !ticker.isActive) {
      _lastTickElapsed = null;
      ticker.start();
    }
  }

  void _animateToSegment(int index, {bool lift = true}) {
    final double nextTarget = index.toDouble();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _glideTicker?.stop();
      setState(() {
        _fractionalIndex = nextTarget;
        _indexVel = 0.0;
        _targetIndex = null;
        _lifted = false;
      });
      return;
    }
    setState(() {
      _targetIndex = nextTarget;
      if (lift && (nextTarget - _fractionalIndex).abs() > 0.05) {
        _lifted = true;
      } else if (!lift) {
        _lifted = false;
      }
    });
    _ensureTicking();
  }

  void _onGlideTick(Duration elapsed) {
    final Duration last = _lastTickElapsed ?? elapsed;
    final double rawDt = (elapsed - last).inMicroseconds / 1e6;
    _lastTickElapsed = elapsed;
    if (rawDt <= 0.0) return;
    final double dt = math.min(0.04, rawDt);

    final double? target = _targetIndex;
    if (target == null) {
      _glideTicker?.stop();
      return;
    }

    final (double nextX, double nextVel) = liquidGlassSpringStep(
      x: _fractionalIndex,
      vel: _indexVel,
      target: target,
      dt: dt,
      stiffness: _pillStiffness,
      damping: _pillDamping,
    );
    _fractionalIndex = nextX;
    _indexVel = nextVel;

    if ((nextX - target).abs() < 0.14) {
      _lifted = false;
    }
    if ((nextX - target).abs() < 0.002 && nextVel.abs() < 0.01) {
      _fractionalIndex = target;
      _indexVel = 0.0;
      _targetIndex = null;
      _lifted = false;
      _glideTicker?.stop();
    }

    if (mounted) {
      setState(() {});
    }
  }

  void _handleSegmentTap(int index) {
    final option = widget.options[index];
    if (option.value != widget.selected) {
      HapticUtils.selection();
      widget.onChanged(option.value);
      _animateToSegment(index);
    } else if ((_fractionalIndex - index).abs() > 0.01 || _lifted) {
      _animateToSegment(index, lift: false);
    }
  }

  void _handleDragStart(DragStartDetails _) {
    _glideTicker?.stop();
    _targetIndex = null;
    _indexVel = 0.0;
    _isDragging = true;
    setState(() => _lifted = true);
  }

  void _handleDragUpdate(DragUpdateDetails details, double cellW, int count) {
    if (cellW <= 0.1 || count <= 1) return;
    final double rawNext = _fractionalIndex + details.delta.dx / cellW;
    final double maxIdx = (count - 1).toDouble();
    if (rawNext < 0.0) {
      _fractionalIndex = (rawNext * 0.35).clamp(-0.14, 0.0);
    } else if (rawNext > maxIdx) {
      _fractionalIndex =
          (maxIdx + (rawNext - maxIdx) * 0.35).clamp(maxIdx, maxIdx + 0.14);
    } else {
      _fractionalIndex = rawNext;
    }
    final int nearest = _fractionalIndex.round().clamp(0, count - 1);
    if (widget.options[nearest].value != widget.selected) {
      HapticUtils.selection();
      widget.onChanged(widget.options[nearest].value);
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _handleDragFinish(DragEndDetails? details) {
    _isDragging = false;
    if (widget.options.isEmpty) return;
    final int maxIdx = widget.options.length - 1;
    final int snapped = _fractionalIndex.round().clamp(0, maxIdx);
    if (widget.options[snapped].value != widget.selected) {
      HapticUtils.selection();
      widget.onChanged(widget.options[snapped].value);
    }
    _animateToSegment(
      snapped,
      lift: (snapped - _fractionalIndex).abs() >= 0.08,
    );
  }

  Widget _buildSegmentRow(
    TheavPalette palette, {
    required double pad,
    required double cellH,
  }) {
    final int selectedIdx = _selectedIndex();
    return Padding(
      padding: EdgeInsets.all(pad),
      child: Row(
        children: [
          for (int i = 0; i < widget.options.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _handleSegmentTap(i),
                child: SizedBox(
                  height: cellH,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (widget.options[i].icon != null) ...[
                            IconTheme(
                              data: IconThemeData(
                                size: 16,
                                color: i == selectedIdx
                                    ? palette.primary
                                    : palette.subtext,
                              ),
                              child: widget.options[i].icon!,
                            ),
                            const SizedBox(width: 5),
                          ],
                          Flexible(
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 160),
                              style: TextStyle(
                                color: i == selectedIdx
                                    ? palette.onSurface
                                    : palette.subtext,
                                fontSize: 13.5,
                                fontWeight: i == selectedIdx
                                    ? FontWeight.w600
                                    : FontWeight.w500,
                              ),
                              child: Text(
                                widget.options[i].label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
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

  @override
  Widget build(BuildContext context) {
    if (widget.options.isEmpty) return const SizedBox.shrink();
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final int n = widget.options.length;
    final int activeIdx = _selectedIndex();

    if (style.isGlass && style.glassProvider != null) {
      const double pad = 3.5;
      final double cellH = math.max(12.0, widget.height - pad * 2.0);
      final Color trackBg = style.isDark
          ? const Color(0x18FFFFFF)
          : const Color(0x0D000000);
      final Color restPillColor = style.isDark
          ? const Color(0x36FFFFFF)
          : const Color(0x88FFFFFF);
      final double extraW = math.min(6.0, pad * 1.6);
      final double extraH = math.min(5.0, pad * 1.5);

      return Padding(
        padding: widget.margin,
        child: SizedBox(
          height: widget.height,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final double w = constraints.maxWidth.isFinite &&
                      constraints.maxWidth > 0
                  ? constraints.maxWidth
                  : 280.0;
              final double cellW = math.max(1.0, (w - pad * 2.0) / n);
              final double clampedIdx = _fractionalIndex.clamp(
                -0.14,
                (n - 1).toDouble() + 0.14,
              );
              final double pillLeft = pad + clampedIdx * cellW;
              final double pillCX = pillLeft + cellW * 0.5;

              final Widget backgroundLayer = Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: trackBg,
                      borderRadius: BorderRadius.circular(widget.height / 2),
                    ),
                  ),
                  Positioned(
                    left: pillLeft,
                    top: pad,
                    width: cellW,
                    height: cellH,
                    child: AnimatedOpacity(
                      duration: const Duration(milliseconds: 120),
                      opacity: _glassVisible ? 0.32 : 1.0,
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          color: restPillColor,
                          borderRadius: BorderRadius.circular(cellH / 2),
                          boxShadow: style.isDark
                              ? null
                              : [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.06),
                                    blurRadius: 6,
                                    offset: const Offset(0, 1.5),
                                  ),
                                ],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: _buildSegmentRow(
                      palette,
                      pad: pad,
                      cellH: cellH,
                    ),
                  ),
                ],
              );

              return GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragStart: _handleDragStart,
                onHorizontalDragUpdate: (d) => _handleDragUpdate(d, cellW, n),
                onHorizontalDragEnd: _handleDragFinish,
                onHorizontalDragCancel: () => _handleDragFinish(null),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(widget.height / 2),
                  child: LiquidGlassView(
                    controller: _viewController,
                    batch: false,
                    realTimeCapture: false,
                    useSync: true,
                    backgroundWidget: backgroundLayer,
                    child: IgnorePointer(
                      child: LiquidGlassBatch.exclude(
                        child: LiquidGlassMotionPill(
                          center: Offset(pillCX, widget.height * 0.5),
                          active: _lifted,
                          restSize: Size(cellW, cellH),
                          activeSize: Size(cellW + extraW, cellH + extraH),
                          honorBackdropAlpha: true,
                          style: LiquidGlassStyle(
                            shape:
                                const LiquidGlassShape.continuousRoundedRectangle(
                              cornerRadius: 100,
                            ),
                            specular: const LiquidGlassLight.specular(),
                            color: style.isDark
                                ? const Color(0x22FFFFFF)
                                : const Color(0x2CFFFFFF),
                            blur: 0,
                            shadow: const LiquidGlassShadow(inset: 3),
                            refractionIndex: 1.045,
                            refractionWidth: 12,
                            magnification: 1.05,
                            liteGlass: style.isLite,
                          ),
                          onGlassVisibilityChanged: (visible) {
                            if (visible) {
                              _viewController.startRealtimeCapture();
                            } else {
                              _viewController.stopRealtimeCapture();
                            }
                            if (mounted && _glassVisible != visible) {
                              setState(() => _glassVisible = visible);
                            }
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      );
    }

    final double alignmentX =
        n <= 1 ? 0.0 : -1.0 + (2.0 * activeIdx / (n - 1));
    const double mattePad = 3.0;
    return Padding(
      padding: widget.margin,
      child: SizedBox(
        height: widget.height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: style.trackFill,
            borderRadius: BorderRadius.circular(widget.height / 2),
          ),
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(mattePad),
                child: AnimatedAlign(
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment(alignmentX, 0.0),
                  child: FractionallySizedBox(
                    widthFactor: 1.0 / n,
                    heightFactor: 1.0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.surface,
                        borderRadius: BorderRadius.circular(
                          (widget.height - mattePad * 2) / 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(
                              alpha: style.isDark ? 0.24 : 0.07,
                            ),
                            blurRadius: 6,
                            offset: const Offset(0, 1.5),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              _buildSegmentRow(
                palette,
                pad: mattePad,
                cellH: math.max(12.0, widget.height - mattePad * 2),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Tactile Telegram-grade pill toggle switch working consistently in both
/// Liquid Glass and Material Matte modes without depending on [LiquidGlassProvider].
class TheavSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;
  final Color? activeColor;
  final Color? inactiveColor;
  final Color? thumbColor;
  final String? semanticLabel;

  const TheavSwitch({
    super.key,
    required this.value,
    required this.onChanged,
    this.activeColor,
    this.inactiveColor,
    this.thumbColor,
    this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final bool enabled = onChanged != null;

    if (style.isGlass) {
      final Color resolvedActive = activeColor ?? palette.primary;
      final Color resolvedInactive =
          inactiveColor ?? (style.isDark ? Colors.white24 : Colors.black12);
      final Color resolvedThumb = thumbColor ?? palette.onPrimary;

      Widget glassToggle = LiquidGlassSwitch(
        value: value,
        onChanged: enabled
            ? (next) {
                HapticUtils.selection();
                onChanged!(next);
              }
            : (_) {},
        activeColor:
            enabled ? resolvedActive : resolvedActive.withValues(alpha: 0.38),
        inactiveColor: enabled
            ? resolvedInactive
            : (style.isDark ? Colors.white : Colors.black)
                .withValues(alpha: style.isDark ? 0.10 : 0.06),
        thumbColor: enabled
            ? resolvedThumb
            : (thumbColor ?? Colors.white)
                .withValues(alpha: style.isDark ? 0.42 : 0.68),
      );
      if (!enabled) {
        glassToggle = IgnorePointer(
          ignoring: true,
          child: glassToggle,
        );
      }
      if (semanticLabel != null) {
        glassToggle = Semantics(
          label: semanticLabel,
          toggled: value,
          enabled: enabled,
          child: glassToggle,
        );
      }
      return Center(
        widthFactor: 1.0,
        heightFactor: 1.0,
        child: glassToggle,
      );
    }

    final Color activeTrack = activeColor ?? palette.primary;
    final Color inactiveTrack = inactiveColor ??
        Color.alphaBlend(
          palette.onSurface.withValues(alpha: style.isDark ? 0.22 : 0.16),
          palette.surface,
        );
    final Color trackColor = value ? activeTrack : inactiveTrack;
    final Color resolvedThumbColor = thumbColor ??
        (value
            ? palette.onPrimary
            : (style.isDark ? palette.onSurface : Colors.white));

    Widget toggle = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOutCubic,
      width: 48,
      height: 28,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: enabled ? trackColor : trackColor.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: value
              ? activeTrack.withValues(alpha: 0.25)
              : palette.divider,
          width: 0.5,
        ),
      ),
      child: AnimatedAlign(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        alignment: value ? Alignment.centerRight : Alignment.centerLeft,
        child: Container(
          width: 22,
          height: 22,
          decoration: BoxDecoration(
            color: enabled
                ? resolvedThumbColor
                : resolvedThumbColor.withValues(alpha: 0.72),
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: style.isDark ? 0.30 : 0.16),
                blurRadius: 4,
                offset: const Offset(0, 1.5),
              ),
            ],
          ),
        ),
      ),
    );

    if (semanticLabel != null) {
      toggle = Semantics(
        label: semanticLabel,
        toggled: value,
        enabled: enabled,
        child: toggle,
      );
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: enabled
          ? () {
              HapticUtils.selection();
              onChanged!(!value);
            }
          : null,
      child: toggle,
    );
  }
}

/// Animated circular multi-select badge supporting checkmark or numbered (`1..N`)
/// selection badges for chats and media pickers.
class TheavCheckCircle extends StatelessWidget {
  final bool selected;
  final int? index;
  final double size;
  final Color? activeColor;
  final Color? inactiveBorderColor;
  final VoidCallback? onTap;

  const TheavCheckCircle({
    super.key,
    required this.selected,
    this.index,
    this.size = 22.0,
    this.activeColor,
    this.inactiveBorderColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final fillColor = activeColor ?? palette.primary;
    final borderColor =
        inactiveBorderColor ?? palette.onSurface.withValues(alpha: 0.34);

    final badge = AnimatedContainer(
      duration: const Duration(milliseconds: 170),
      curve: Curves.easeOutCubic,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: selected ? fillColor : Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? fillColor : borderColor,
          width: selected ? 1.5 : 1.5,
        ),
      ),
      child: AnimatedScale(
        scale: selected ? 1.0 : 0.5,
        duration: const Duration(milliseconds: 160),
        curve: Curves.easeOutBack,
        child: selected
            ? Center(
                child: index != null
                    ? Text(
                        '${index!}',
                        style: TextStyle(
                          color: palette.onPrimary,
                          fontSize: size * 0.54,
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                        ),
                      )
                    : iconoir.Check(
                        width: size * 0.62,
                        height: size * 0.62,
                        color: palette.onPrimary,
                      ),
              )
            : const SizedBox.shrink(),
      ),
    );

    if (onTap == null) return badge;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        HapticUtils.selection();
        onTap!();
      },
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: badge,
      ),
    );
  }
}

/// Discrete stepped slider with header value readout and tactile ticks
/// (e.g. Telegram slowmode interval selector).
class TheavSteppedSlider extends StatelessWidget {
  final int selectedIndex;
  final List<String> labels;
  final ValueChanged<int>? onChanged;
  final String? title;
  final Color? activeColor;

  const TheavSteppedSlider({
    super.key,
    required this.selectedIndex,
    required this.labels,
    required this.onChanged,
    this.title,
    this.activeColor,
  });

  @override
  Widget build(BuildContext context) {
    if (labels.isEmpty) return const SizedBox.shrink();
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final int safeIndex = selectedIndex.clamp(0, labels.length - 1);
    final Color accent = activeColor ?? palette.primary;
    final int maxIdx = labels.length - 1;
    final bool enabled = onChanged != null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              if (title != null && title!.isNotEmpty)
                Expanded(
                  child: Text(
                    title!,
                    style: TextStyle(
                      color: palette.onSurface,
                      fontSize: 15.5,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 160),
                child: Text(
                  labels[safeIndex],
                  key: ValueKey<int>(safeIndex),
                  style: TextStyle(
                    color: enabled ? accent : accent.withValues(alpha: 0.45),
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final double totalWidth = constraints.maxWidth.clamp(48.0, 2000.0);
              if (style.isGlass && maxIdx > 0) {
                Widget glassSlider = LiquidGlassSlider(
                  value: safeIndex.toDouble(),
                  minimumValue: 0.0,
                  maximumValue: maxIdx.toDouble(),
                  width: totalWidth,
                  activeColor:
                      enabled ? accent : accent.withValues(alpha: 0.38),
                  inactiveColor: enabled
                      ? (style.isDark ? Colors.white24 : Colors.black12)
                      : (style.isDark ? Colors.white : Colors.black)
                          .withValues(alpha: style.isDark ? 0.10 : 0.06),
                  thumbColor: enabled
                      ? Colors.white
                      : Colors.white
                          .withValues(alpha: style.isDark ? 0.45 : 0.70),
                  onChanged: enabled
                      ? (v) {
                          final int nextIdx = v.round().clamp(0, maxIdx);
                          if (nextIdx != safeIndex) {
                            HapticUtils.selection();
                            onChanged!(nextIdx);
                          }
                        }
                      : (_) {},
                );
                if (!enabled) {
                  glassSlider = IgnorePointer(
                    ignoring: true,
                    child: glassSlider,
                  );
                }
                return glassSlider;
              }
              final double usableWidth = (totalWidth - 20.0).clamp(1.0, totalWidth);
              final double fraction = maxIdx > 0 ? safeIndex / maxIdx : 0.0;
              final double activeWidth = usableWidth * fraction;

              void pickFromDx(double dx) {
                if (!enabled || maxIdx <= 0) return;
                final double clamped = ((dx - 10.0) / usableWidth).clamp(0.0, 1.0);
                final int nextIdx = (clamped * maxIdx).round().clamp(0, maxIdx);
                if (nextIdx != safeIndex) {
                  HapticUtils.selection();
                  onChanged!(nextIdx);
                }
              }

              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapDown: enabled ? (d) => pickFromDx(d.localPosition.dx) : null,
                onHorizontalDragUpdate:
                    enabled ? (d) => pickFromDx(d.localPosition.dx) : null,
                child: SizedBox(
                  height: 30,
                  child: Stack(
                    alignment: Alignment.centerLeft,
                    children: [
                      // Track
                      Positioned(
                        left: 10,
                        right: 10,
                        child: Container(
                          height: 4,
                          decoration: BoxDecoration(
                            color: palette.onSurface.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // Active track
                      Positioned(
                        left: 10,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          curve: Curves.easeOutCubic,
                          width: activeWidth,
                          height: 4,
                          decoration: BoxDecoration(
                            color: enabled
                                ? accent
                                : accent.withValues(alpha: 0.42),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                      // Tick dots
                      if (maxIdx > 0)
                        for (int i = 0; i <= maxIdx; i++)
                          Positioned(
                            left: 10 + usableWidth * (i / maxIdx) - 3,
                            child: Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: i <= safeIndex
                                    ? (enabled
                                        ? accent
                                        : accent.withValues(alpha: 0.42))
                                    : palette.onSurface.withValues(alpha: 0.28),
                              ),
                            ),
                          ),
                      // Thumb
                      AnimatedPositioned(
                        duration: const Duration(milliseconds: 140),
                        curve: Curves.easeOutCubic,
                        left: activeWidth,
                        child: Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: palette.surface,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: enabled
                                  ? accent
                                  : accent.withValues(alpha: 0.42),
                              width: 2.5,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.16),
                                blurRadius: 5,
                                offset: const Offset(0, 1.5),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(labels.length, (i) {
              final bool active = i == safeIndex;
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: enabled
                    ? () {
                        if (i != safeIndex) {
                          HapticUtils.selection();
                          onChanged!(i);
                        }
                      }
                    : null,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Text(
                    labels[i],
                    style: TextStyle(
                      color: active ? accent : palette.subtext,
                      fontSize: 11.5,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}
