import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';

import '../../utils/blur_utils.dart';
import '../../utils/haptic_utils.dart';
import 'theav_design_system.dart';

/// Layer 2 floating HUD surface supporting three rendering modes cleanly:
/// - [GlassMode.full] / [GlassMode.lite]: shader-backed [LiquidGlassLens]
///   (never wrapped in `Opacity` or `FadeTransition`)
/// - [GlassMode.disabled]: single-pass frosted Material HUD (`BackdropFilter.grouped`)
///   when permitted by power saving, or opaque M3 surface + hairline divider.
class TheavFloatingSurface extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;
  final double refractionIndex;
  final double refractionWidth;
  final Color? colorOverride;
  final bool enableFlex;
  final bool enableBlur;

  const TheavFloatingSurface({
    super.key,
    required this.child,
    this.borderRadius = 22.0,
    this.padding,
    this.refractionIndex = 1.12,
    this.refractionWidth = 22.0,
    this.colorOverride,
    this.enableFlex = true,
    this.enableBlur = true,
  });

  @override
  Widget build(BuildContext context) {
    final surfaceStyle = TheavSurfaceStyle.of(context);
    final Widget content =
        padding != null ? Padding(padding: padding!, child: child) : child;

    if (surfaceStyle.isGlass && surfaceStyle.glassProvider != null) {
      final style = surfaceStyle.glassProvider!.createStyle(
        context: context,
        cornerRadius: borderRadius,
        refractionIndex: refractionIndex,
        refractionWidth: refractionWidth,
        color: colorOverride,
      );
      return LayoutBuilder(
        builder: (context, constraints) {
          // `LiquidGlassTouch.flexing` expands `LiquidGlassLens` to
          // `constraints.biggest`, so only enable it when both axes are tight
          // and keep loose containers (e.g. floating pills/toasts) shrink-wrapped.
          final bool allowTightFlex = enableFlex && constraints.isTight;
          return LiquidGlassLens(
            style: style,
            touch: allowTightFlex
                ? const LiquidGlassTouch.flexing(
                    LiquidGlassFlex(
                      stretch: 5,
                      squeeze: 0.72,
                      lean: 0.25,
                      grip: 0.5,
                    ),
                  )
                : null,
            child: content,
          );
        },
      );
    }

    final bool suppressBlur = !enableBlur || TheavModalSheetScope.isActive(context);
    final blurFilter = suppressBlur
        ? null
        : surfaceStyle.getMaterialHudBlurFilter(sigma: 10.0);
    final Color bg = colorOverride != null
        ? (blurFilter != null
            ? BlurUtils.resolveMaterialHudColor(
                colorOverride!,
                isDark: surfaceStyle.isDark,
                blurEnabled: true,
                darkAlpha: 0.86,
                lightAlpha: 0.88,
              )
            : colorOverride!)
        : (blurFilter != null
            ? surfaceStyle.hudFill
            : (surfaceStyle.palette.appBarBackground != Colors.transparent
                ? surfaceStyle.palette.appBarBackground
                : surfaceStyle.palette.surface));

    Widget box = DecoratedBox(
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(borderRadius),
        border: Border.all(
          color: surfaceStyle.hudBorder,
          width: blurFilter != null ? 0.6 : 0.5,
        ),
      ),
      child: content,
    );

    if (blurFilter != null) {
      box = BackdropFilter.grouped(
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
                  Flexible(
                    child: Text(
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
