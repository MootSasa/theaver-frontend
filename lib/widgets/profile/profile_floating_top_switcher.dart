import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:motor/motor.dart';
import 'package:provider/provider.dart';

import '../../services/liquid_glass_provider.dart';
import '../../utils/haptic_utils.dart';
import '../settings/settings_floating_header.dart';

Matrix4 _switcherJellyTransform({
  required double velocityX,
  double maxDistortion = 0.55,
  double velocityScale = 12.0,
}) {
  final speed = velocityX.abs();
  final distortion = (speed / velocityScale).clamp(0.0, 1.0) * maxDistortion;
  if (distortion == 0) return Matrix4.identity();
  final scaleX = 1.0 + distortion * 0.28;
  final scaleY = 1.0 - distortion * 0.22;
  return Matrix4.diagonal3Values(scaleX, scaleY, 1.0);
}

/// Круглая плавающая кнопка «Назад» (`44x44`) поверх цветного/градиентного фона профиля.
///
/// Визуально полностью совпадает с верхней кнопкой возврата реального [ProfileScreen]
/// и плавающим переключателем [ProfileFloatingTopSwitcher].
class ProfileFloatingBackButton extends StatelessWidget {
  final VoidCallback onTap;
  final bool glassEnabled;
  final bool isLite;
  final bool isDarkBackdrop;
  final String? tooltip;

  const ProfileFloatingBackButton({
    super.key,
    required this.onTap,
    required this.glassEnabled,
    this.isLite = false,
    this.isDarkBackdrop = true,
    this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    const size = SettingsFloatingHeader.buttonSize;
    final iconColor = isDarkBackdrop
        ? Colors.white.withValues(alpha: 0.94)
        : const Color(0xFF1C1C1E);

    final inner = Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: BorderRadius.circular(size / 2),
        onTap: () {
          HapticUtils.tap();
          onTap();
        },
        child: Center(
          child: iconoir.NavArrowLeft(
            width: 22,
            height: 22,
            color: iconColor,
          ),
        ),
      ),
    );

    Widget button;
    final glassProvider = maybeLiquidGlassProvider(context);
    if (glassEnabled && glassProvider != null) {
      final style = glassProvider.createStyle(
        context: context,
        isDarkOverride: isDarkBackdrop,
        isLiteOverride: isLite,
        color: isDarkBackdrop
            ? const Color(0x38202025)
            : const Color(0x66FFFFFF),
        refractionIndex: 1.15,
        refractionWidth: 22.0,
        shape: const LiquidGlassShape.roundedRectangle(
          cornerRadius: size / 2,
        ),
      );
      button = SizedBox(
        width: size,
        height: size,
        child: LiquidGlassLens(
          style: style,
          child: inner,
        ),
      );
    } else {
      button = SizedBox(
        width: size,
        height: size,
        child: DecoratedBox(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black
                    .withValues(alpha: isDarkBackdrop ? 0.24 : 0.08),
                blurRadius: 12,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDarkBackdrop
                      ? const Color(0x9926262A)
                      : const Color(0xCCFFFFFF),
                  border: Border.all(
                    color: isDarkBackdrop
                        ? Colors.white.withValues(alpha: 0.14)
                        : Colors.black.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                ),
                child: inner,
              ),
            ),
          ),
        ),
      );
    }

    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// Плавающий переключатель разделов с живой стеклянной пилюлей ([LiquidGlassMotionPill]),
/// идентичный по физике и дизайну переключателю на главном экране (`MainScreen`).
///
/// Поддерживает:
/// - Нажатие на вкладку с вылетом и морфингом плавающей линзы-пилюли;
/// - Горизонтальное перетаскивание пальцем с резиновым сопротивлением на краях;
/// - Режим Liquid Glass (с [LiquidGlassLens] + [LiquidGlassMotionPill]) и классический матовый режим.
class ProfileFloatingTopSwitcher extends StatefulWidget {
  final List<String> segments;
  final int selectedIndex;
  final ValueChanged<int> onChanged;
  final bool glassEnabled;
  final bool isLite;
  final bool isDarkBackdrop;
  final double height;
  final double padding;

  const ProfileFloatingTopSwitcher({
    super.key,
    required this.segments,
    required this.selectedIndex,
    required this.onChanged,
    required this.glassEnabled,
    this.isLite = false,
    this.isDarkBackdrop = true,
    this.height = SettingsFloatingHeader.buttonSize,
    this.padding = 4.0,
  }) : assert(segments.length >= 2);

  @override
  State<ProfileFloatingTopSwitcher> createState() =>
      _ProfileFloatingTopSwitcherState();
}

class _ProfileFloatingTopSwitcherState
    extends State<ProfileFloatingTopSwitcher> {
  bool _isDown = false;
  bool _isDragging = false;
  late double _xAlign = _alignForIndex(widget.selectedIndex);

  double _alignForIndex(int index) {
    final count = widget.segments.length;
    if (count <= 1) return 0.0;
    final clamped = index.clamp(0, count - 1);
    return (clamped / (count - 1)) * 2.0 - 1.0;
  }

  @override
  void didUpdateWidget(covariant ProfileFloatingTopSwitcher oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging &&
        (oldWidget.selectedIndex != widget.selectedIndex ||
            oldWidget.segments.length != widget.segments.length)) {
      _xAlign = _alignForIndex(widget.selectedIndex);
    }
  }

  double _applyRubberBand(double normalized) {
    const resistance = 0.35;
    const maxOverdrag = 0.24;
    if (normalized < 0.0) {
      return -((-normalized) * resistance).clamp(0.0, maxOverdrag);
    }
    if (normalized > 1.0) {
      return 1.0 + ((normalized - 1.0) * resistance).clamp(0.0, maxOverdrag);
    }
    return normalized;
  }

  double _alignmentFromGlobal(Offset globalPos) {
    final renderObj = context.findRenderObject();
    if (renderObj is! RenderBox || renderObj.size.width <= 0) {
      return _alignForIndex(widget.selectedIndex);
    }
    final local = renderObj.globalToLocal(globalPos);
    final count = widget.segments.length;
    final indicatorFrac = 1.0 / count;
    final draggableRange = math.max(0.001, 1.0 - indicatorFrac);
    final halfPad = indicatorFrac / 2.0;

    final rawFrac = (local.dx / renderObj.size.width).clamp(0.0, 1.0);
    final normalized = (rawFrac - halfPad) / draggableRange;
    final resisted = _applyRubberBand(normalized);
    return resisted * 2.0 - 1.0;
  }

  void _handleDragStart(DragStartDetails details) {
    setState(() {
      _isDown = true;
      _isDragging = true;
      _xAlign = _alignmentFromGlobal(details.globalPosition);
    });
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    setState(() {
      _isDragging = true;
      _xAlign = _alignmentFromGlobal(details.globalPosition);
    });
  }

  void _handleDragEnd(DragEndDetails details) {
    final renderObj = context.findRenderObject();
    final count = widget.segments.length;
    final currentFrac = (_xAlign + 1.0) / 2.0;

    int targetIndex;
    if (currentFrac <= 0.0) {
      targetIndex = 0;
    } else if (currentFrac >= 1.0) {
      targetIndex = count - 1;
    } else {
      double velocityNorm = 0.0;
      if (renderObj is RenderBox && renderObj.size.width > 0) {
        final range = math.max(0.001, 1.0 - 1.0 / count);
        velocityNorm =
            (details.velocity.pixelsPerSecond.dx / renderObj.size.width) /
                range;
      }
      final projected = (currentFrac + velocityNorm * 0.22).clamp(0.0, 1.0);
      targetIndex = (projected * (count - 1)).round().clamp(0, count - 1);
    }

    setState(() {
      _isDragging = false;
      _isDown = false;
      _xAlign = _alignForIndex(targetIndex);
    });

    if (targetIndex != widget.selectedIndex) {
      HapticUtils.selection();
      widget.onChanged(targetIndex);
    }
  }

  void _handleDragCancel() {
    setState(() {
      _isDragging = false;
      _isDown = false;
      _xAlign = _alignForIndex(widget.selectedIndex);
    });
  }

  @override
  Widget build(BuildContext context) {
    final count = widget.segments.length;
    final clampedSelected = widget.selectedIndex.clamp(0, count - 1);
    final targetAlign = _alignForIndex(clampedSelected);
    final outerRadius = widget.height / 2.0;

    final selectedTextColor =
        widget.isDarkBackdrop ? Colors.white : const Color(0xFF1C1C1E);
    final unselectedTextColor = widget.isDarkBackdrop
        ? Colors.white.withValues(alpha: 0.68)
        : const Color(0xFF1C1C1E).withValues(alpha: 0.58);

    // Цвет покоящейся пилюли совпадает с LiquidGlassTabPillStyle.rest на MainScreen
    final restPillColor = widget.isDarkBackdrop
        ? const Color(0x38FFFFFF)
        : const Color(0x2EAEAEB2);

    final glassProvider = maybeLiquidGlassProvider(context);
    final useGlass = widget.glassEnabled && glassProvider != null;

    return SizedBox(
      height: widget.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.maxWidth;
          final pad = widget.padding;
          final innerW = math.max(1.0, width - pad * 2.0);
          final cellW = innerW / count;
          final cellH = math.max(1.0, widget.height - pad * 2.0);
          final travel = math.max(0.0, innerW - cellW);

          Widget labelsRow = Row(
            children: [
              for (int i = 0; i < count; i++)
                Expanded(
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTapDown: (_) => setState(() => _isDown = true),
                    onTapCancel: () => setState(() => _isDown = false),
                    onTap: () {
                      setState(() {
                        _isDown = false;
                        _xAlign = _alignForIndex(i);
                      });
                      if (i != clampedSelected) {
                        HapticUtils.selection();
                        widget.onChanged(i);
                      }
                    },
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: AnimatedDefaultTextStyle(
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutCubic,
                          style: TextStyle(
                            fontFamily: Theme.of(context)
                                .textTheme
                                .titleMedium
                                ?.fontFamily,
                            fontSize: 14.0,
                            letterSpacing: -0.2,
                            fontWeight: i == clampedSelected
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: i == clampedSelected
                                ? selectedTextColor
                                : unselectedTextColor,
                          ),
                          child: Text(
                            widget.segments[i],
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          );

          return GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: _handleDragStart,
            onHorizontalDragUpdate: _handleDragUpdate,
            onHorizontalDragEnd: _handleDragEnd,
            onHorizontalDragCancel: _handleDragCancel,
            child: VelocityMotionBuilder(
              converter: const SingleMotionConverter(),
              value: _xAlign,
              motion: _isDragging
                  ? const Motion.interactiveSpring(snapToEnd: true)
                  : const Motion.snappySpring(
                      snapToEnd: true,
                      duration: Duration(milliseconds: 300),
                    ),
              builder: (context, animatedAlign, velocity, _) {
                final norm = (animatedAlign + 1.0) / 2.0;
                final centerX = pad + cellW / 2.0 + norm * travel;
                final center = Offset(centerX, widget.height / 2.0);
                final isGliding = (animatedAlign - targetAlign).abs() > 0.05;
                final pillActive = _isDown || _isDragging || isGliding;

                if (useGlass) {
                  final capsuleStyle = glassProvider.createStyle(
                    context: context,
                    isDarkOverride: widget.isDarkBackdrop,
                    isLiteOverride: widget.isLite,
                    color: widget.isDarkBackdrop
                        ? const Color(0x38202025)
                        : const Color(0x66FFFFFF),
                    refractionIndex: 1.15,
                    refractionWidth: 22.0,
                    shape: LiquidGlassShape.continuousRoundedRectangle(
                      cornerRadius: outerRadius,
                    ),
                  );

                  final movingPillStyle = LiquidGlassStyle(
                    shape: LiquidGlassShape.continuousRoundedRectangle(
                      cornerRadius: (cellH + 12.0) / 2.0,
                    ),
                    color: widget.isDarkBackdrop
                        ? const Color(0x22FFFFFF)
                        : const Color(0x36FFFFFF),
                    blur: 0.0,
                    refractionIndex: 1.14,
                    refractionWidth: 18.0,
                    liteGlass: widget.isLite,
                  );

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // 1. Базовая стеклянная капсула переключателя
                      Positioned.fill(
                        child: LiquidGlassLens(
                          style: capsuleStyle,
                          child: const SizedBox.expand(),
                        ),
                      ),
                      // 2. Плавающая живая пилюля Liquid Glass (с вылетом за края и jelly-деформацией)
                      Positioned.fill(
                        child: LiquidGlassBatch.exclude(
                          child: LiquidGlassMotionPill(
                            center: center,
                            active: pillActive,
                            restSize: Size(cellW, cellH),
                            activeSize: Size(cellW + 14.0, cellH + 12.0),
                            style: movingPillStyle,
                            cover: ColoredBox(color: restPillColor),
                          ),
                        ),
                      ),
                      // 3. Кликабельные подписи поверх пилюли
                      Positioned.fill(
                        child: Padding(
                          padding: EdgeInsets.all(pad),
                          child: labelsRow,
                        ),
                      ),
                    ],
                  );
                }

                // Классический матовый режим с пружинным скольжением пилюли
                return DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(outerRadius),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(
                          alpha: widget.isDarkBackdrop ? 0.24 : 0.08,
                        ),
                        blurRadius: 12,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(outerRadius),
                    child: BackdropFilter(
                      filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(outerRadius),
                          color: widget.isDarkBackdrop
                              ? const Color(0x9926262A)
                              : const Color(0xCCFFFFFF),
                          border: Border.all(
                            color: widget.isDarkBackdrop
                                ? Colors.white.withValues(alpha: 0.14)
                                : Colors.black.withValues(alpha: 0.08),
                            width: 0.5,
                          ),
                        ),
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            Positioned(
                              left: centerX - cellW / 2.0,
                              top: pad,
                              width: cellW,
                              height: cellH,
                              child: Transform(
                                alignment: Alignment.center,
                                transform: _switcherJellyTransform(
                                  velocityX: velocity,
                                ),
                                child: DecoratedBox(
                                  decoration: BoxDecoration(
                                    color: restPillColor,
                                    borderRadius:
                                        BorderRadius.circular(cellH / 2.0),
                                  ),
                                ),
                              ),
                            ),
                            Positioned.fill(
                              child: Padding(
                                padding: EdgeInsets.all(pad),
                                child: labelsRow,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}

/// Полупрозрачная карточка секции поверх фона/градиента профиля,
/// выполненная по визуальному рецепту `LiquidGlassInfoPanel` на реальном `ProfileScreen`.
class ProfileGlassSection extends StatelessWidget {
  final String? title;
  final List<Widget> children;
  final EdgeInsetsGeometry margin;
  final bool glassEnabled;
  final bool isLite;
  final bool isDarkBackdrop;
  final Color? accentColor;
  final double dividerIndent;

  const ProfileGlassSection({
    super.key,
    this.title,
    required this.children,
    this.margin = const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
    required this.glassEnabled,
    this.isLite = false,
    this.isDarkBackdrop = true,
    this.accentColor,
    this.dividerIndent = 52.0,
  });

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) return const SizedBox.shrink();

    final baseTheme = Theme.of(context);
    final targetBrightness =
        isDarkBackdrop ? Brightness.dark : Brightness.light;
    final primaryText =
        isDarkBackdrop ? Colors.white : const Color(0xFF1C1C1E);
    final secondaryText = isDarkBackdrop
        ? Colors.white.withValues(alpha: 0.62)
        : const Color(0xFF6C6C70);
    final sectionHeaderColor = isDarkBackdrop
        ? Colors.white.withValues(alpha: 0.78)
        : const Color(0xFF5C5C62);
    final dividerColor = isDarkBackdrop
        ? Colors.white.withValues(alpha: 0.09)
        : Colors.black.withValues(alpha: 0.07);
    final effectiveAccent = accentColor ??
        (isDarkBackdrop ? const Color(0xFF64B5F6) : const Color(0xFF0088CC));

    final adaptedScheme = ColorScheme.fromSeed(
      seedColor: effectiveAccent,
      brightness: targetBrightness,
    ).copyWith(
      primary: effectiveAccent,
      onSurface: primaryText,
      onSurfaceVariant: secondaryText,
    );

    final sectionTheme = baseTheme.copyWith(
      brightness: targetBrightness,
      colorScheme: adaptedScheme,
      iconTheme: IconThemeData(color: primaryText),
      listTileTheme: ListTileThemeData(
        iconColor: primaryText,
        textColor: primaryText,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        titleTextStyle: baseTheme.textTheme.bodyLarge?.copyWith(
          fontSize: 15.5,
          fontWeight: FontWeight.w500,
          color: primaryText,
        ),
        subtitleTextStyle: baseTheme.textTheme.bodySmall?.copyWith(
          fontSize: 12.5,
          color: secondaryText,
        ),
      ),
    );

    final rowsColumn = Theme(
      data: sectionTheme,
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (int i = 0; i < children.length; i++) ...[
              children[i],
              if (i < children.length - 1)
                Divider(
                  height: 1,
                  thickness: 0.5,
                  indent: dividerIndent,
                  endIndent: 16,
                  color: dividerColor,
                ),
            ],
          ],
        ),
      ),
    );

    Widget card;
    LiquidGlassProvider? glassProvider;
    try {
      glassProvider = context.watch<LiquidGlassProvider>();
    } catch (_) {}

    if (glassEnabled && glassProvider != null) {
      final style = glassProvider.createStyle(
        context: context,
        isDarkOverride: isDarkBackdrop,
        isLiteOverride: isLite,
        color: isDarkBackdrop
            ? const Color(0x38202025)
            : const Color(0x66FFFFFF),
        refractionIndex: 1.15,
        refractionWidth: 22.0,
        shape: const LiquidGlassShape.continuousRoundedRectangle(
          cornerRadius: 24,
        ),
      );
      card = LiquidGlassLens(
        style: style,
        child: DecoratedBox(
          decoration: isDarkBackdrop
              ? const BoxDecoration()
              : BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.08),
                    width: 0.5,
                  ),
                ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(24),
            child: rowsColumn,
          ),
        ),
      );
    } else {
      card = DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          boxShadow: [
            BoxShadow(
              color: Colors.black
                  .withValues(alpha: isDarkBackdrop ? 0.18 : 0.06),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(22),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: isDarkBackdrop
                    ? const Color(0x8C222228)
                    : const Color(0xC2FFFFFF),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: isDarkBackdrop
                      ? Colors.white.withValues(alpha: 0.12)
                      : Colors.black.withValues(alpha: 0.08),
                  width: 0.5,
                ),
              ),
              child: rowsColumn,
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: margin,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null && title!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8, top: 6),
              child: Text(
                title!,
                style: TextStyle(
                  fontSize: 13.0,
                  fontWeight: FontWeight.w600,
                  letterSpacing: -0.1,
                  color: sectionHeaderColor,
                ),
              ),
            ),
          card,
        ],
      ),
    );
  }
}
