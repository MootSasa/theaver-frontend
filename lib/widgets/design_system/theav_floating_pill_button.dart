import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../utils/haptic_utils.dart';
import 'theav_design_system.dart';

/// Layer 2 floating HUD surface supporting three rendering modes cleanly:
/// - [GlassMode.full]: shader-backed [LiquidGlassLens] (never wrapped in
///   `Opacity` or `FadeTransition`)
/// - [GlassMode.lite]: [ClipRRect] + cached [BackdropFilter] + `0.5dp` rim
/// - [GlassMode.disabled]: M3 matte solid surface + `0.5dp` hairline divider
class TheavFloatingSurface extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final double refractionIndex;
  final double refractionWidth;
  final Color? colorOverride;

  const TheavFloatingSurface({
    super.key,
    required this.child,
    this.borderRadius = 22.0,
    this.padding,
    this.refractionIndex = 1.12,
    this.refractionWidth = 22.0,
    this.colorOverride,
  });

  @override
  Widget build(BuildContext context) {
    final surfaceStyle = TheavSurfaceStyle.of(context);
    final Widget content =
        padding != null ? Padding(padding: padding!, child: child) : child;

    if (surfaceStyle.isFull && surfaceStyle.glassProvider != null) {
      final style = surfaceStyle.glassProvider!.createStyle(
        context: context,
        cornerRadius: borderRadius,
        refractionIndex: refractionIndex,
        refractionWidth: refractionWidth,
        color: colorOverride,
      );
      return LiquidGlassLens(
        style: style,
        child: content,
      );
    }

    final Color bg = colorOverride ?? surfaceStyle.hudFill;
    final blurFilter = surfaceStyle.getBlurFilter(sigma: 18.0);

    Widget box = DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: surfaceStyle.hudBorder,
          width: 0.5,
        ),
      ),
      child: content,
    );

    if (blurFilter != null) {
      box = BackdropFilter(
        filter: blurFilter,
        child: box,
      );
    }

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: surfaceStyle.floatingShadow,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: box,
      ),
    );
  }
}

/// Standard `44x44` circular Layer 2 header icon button matching the 3-part HUD.
class TheavHeaderIconButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool enabled;
  final Color? foregroundColor;
  final Color? backgroundColor;
  final double size;
  final int badgeCount;

  const TheavHeaderIconButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.enabled = true,
    this.foregroundColor,
    this.backgroundColor,
    this.size = 44.0,
    this.badgeCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final Color fg = foregroundColor ?? palette.appBarForeground;
    final Color effectiveFg = enabled ? fg : fg.withValues(alpha: 0.36);

    Widget button = SizedBox(
      width: size,
      height: size,
      child: TheavFloatingSurface(
        borderRadius: size / 2,
        colorOverride: backgroundColor,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(size / 2),
            onTap: enabled && onTap != null
                ? () {
                    HapticUtils.tap();
                    onTap!();
                  }
                : null,
            child: Center(
              child: IconTheme(
                data: IconThemeData(color: effectiveFg, size: 20),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: effectiveFg),
                  child: icon,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    if (badgeCount > 0) {
      button = Stack(
        clipBehavior: Clip.none,
        children: [
          button,
          Positioned(
            top: -2,
            right: -2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
              constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
              decoration: BoxDecoration(
                color: palette.unreadBadge,
                borderRadius: BorderRadius.circular(9),
                border: Border.all(color: palette.surface, width: 1.5),
              ),
              child: Center(
                child: Text(
                  badgeCount > 99 ? '99+' : '$badgeCount',
                  style: TextStyle(
                    color: palette.unreadBadgeText,
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    height: 1.0,
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (tooltip != null && tooltip!.isNotEmpty) {
      button = Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// Capsule HUD action pill supporting icon + label in Layer 2 glass or matte style.
class TheavFloatingPillButton extends StatelessWidget {
  final String label;
  final Widget? icon;
  final VoidCallback? onTap;
  final bool isPrimary;
  final bool isDestructive;
  final bool enabled;
  final double height;
  final EdgeInsetsGeometry padding;

  const TheavFloatingPillButton({
    super.key,
    required this.label,
    this.icon,
    this.onTap,
    this.isPrimary = false,
    this.isDestructive = false,
    this.enabled = true,
    this.height = 44.0,
    this.padding = const EdgeInsets.symmetric(horizontal: 16),
  });

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final Color? fillOverride = isPrimary
        ? palette.primary
        : (isDestructive ? palette.error.withValues(alpha: 0.14) : null);
    final Color fg = isPrimary
        ? palette.onPrimary
        : (isDestructive ? palette.error : palette.onSurface);
    final Color effectiveFg = enabled ? fg : fg.withValues(alpha: 0.42);

    return SizedBox(
      height: height,
      child: TheavFloatingSurface(
        borderRadius: height / 2,
        colorOverride: fillOverride,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(height / 2),
            onTap: enabled && onTap != null
                ? () {
                    HapticUtils.tap();
                    onTap!();
                  }
                : null,
            child: Padding(
              padding: padding,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    IconTheme(
                      data: IconThemeData(color: effectiveFg, size: 18),
                      child: icon!,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: effectiveFg,
                      fontSize: 14.5,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.1,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
