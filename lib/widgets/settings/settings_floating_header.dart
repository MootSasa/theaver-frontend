import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import '../../models/theav_theme.dart';
import '../../services/liquid_glass_provider.dart';
import '../../utils/haptic_utils.dart';

/// Safely resolves [LiquidGlassProvider] when present in the widget tree.
LiquidGlassProvider? maybeLiquidGlassProvider(
  BuildContext context, {
  bool listen = true,
}) {
  try {
    return Provider.of<LiquidGlassProvider>(context, listen: listen);
  } catch (_) {
    return null;
  }
}

/// Action descriptor rendered in the trailing floating pill/circle of
/// [SettingsFloatingHeader].
class SettingsHeaderAction {
  /// Icon widget rendered inside a `44x44` circular slot.
  final Widget? icon;

  /// Custom widget rendered directly inside the `44x44` slot (e.g. a
  /// [PopupMenuButton] or progress spinner).
  final Widget? child;

  /// Tap callback invoked when [icon] is used and [enabled] is `true`.
  final VoidCallback? onTap;

  /// Optional tooltip shown on long press or hover.
  final String? tooltip;

  /// Whether the action is interactive.
  final bool enabled;

  /// Optional override for icon foreground color.
  final Color? foregroundColor;

  /// Creates an action item for [SettingsFloatingHeader].
  const SettingsHeaderAction({
    this.icon,
    this.child,
    this.onTap,
    this.tooltip,
    this.enabled = true,
    this.foregroundColor,
  }) : assert(icon != null || child != null);
}

/// Floating Liquid Glass / blurred translucent capsule surface matching
/// Theaver's main screen and profile header pills.
class SettingsFloatingSurface extends StatelessWidget {
  final Widget child;
  final double borderRadius;
  final EdgeInsetsGeometry? padding;

  /// Creates a floating pill or circle surface.
  const SettingsFloatingSurface({
    super.key,
    required this.child,
    this.borderRadius = SettingsFloatingHeader.buttonSize / 2,
    this.padding,
  });

  @override
  Widget build(BuildContext context) {
    final glassProvider = maybeLiquidGlassProvider(context);
    final isGlassEnabled = glassProvider?.enabled ?? false;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final content =
        padding != null ? Padding(padding: padding!, child: child) : child;

    if (isGlassEnabled && glassProvider != null) {
      final style = glassProvider.createStyle(
        context: context,
        cornerRadius: borderRadius,
        refractionIndex: 1.12,
        refractionWidth: 22.0,
      );
      return LiquidGlassLens(
        style: style,
        child: content,
      );
    }

    final themeExt = theme.extension<TheavThemeExtension>();
    final defaultBg = isDark
        ? const Color(0xFF1E1E22)
        : Colors.white;
    final baseColor = themeExt?.palette.appBarBackground;
    final effectiveBg = (baseColor != null && baseColor != Colors.transparent
            ? baseColor
            : defaultBg)
        .withValues(alpha: isDark ? 0.78 : 0.84);

    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.08),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: effectiveBg,
              borderRadius: BorderRadius.circular(borderRadius),
              border: Border.all(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.12)
                    : Colors.black.withValues(alpha: 0.08),
                width: 0.5,
              ),
            ),
            child: content,
          ),
        ),
      ),
    );
  }
}

/// Standalone `44x44` circular floating header button.
class SettingsFloatingCircleButton extends StatelessWidget {
  final Widget icon;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool enabled;

  /// Creates a circular floating header button.
  const SettingsFloatingCircleButton({
    super.key,
    required this.icon,
    this.onTap,
    this.tooltip,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final button = SizedBox(
      width: SettingsFloatingHeader.buttonSize,
      height: SettingsFloatingHeader.buttonSize,
      child: SettingsFloatingSurface(
        borderRadius: SettingsFloatingHeader.buttonSize / 2,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius:
                BorderRadius.circular(SettingsFloatingHeader.buttonSize / 2),
            onTap: enabled && onTap != null
                ? () {
                    HapticUtils.tap();
                    onTap!();
                  }
                : null,
            child: Center(child: icon),
          ),
        ),
      ),
    );

    if (tooltip != null && tooltip!.isNotEmpty) {
      return Tooltip(message: tooltip!, child: button);
    }
    return button;
  }
}

/// Floating pill-and-circle header used across all settings screens.
///
/// Renders:
/// - Left: `44x44` circular back button (`iconoir.NavArrowLeft`)
/// - Center: tightly hugging stadium oval title capsule (`minWidth: 120`) that
///   never overlaps side buttons
/// - Right: `44x44` circle (1 action) or multi-button stadium capsule (`N * 44`)
class SettingsFloatingHeader extends StatelessWidget {
  static const double buttonSize = 44.0;
  static const double horizontalPadding = 12.0;
  static const double headerGap = 8.0;
  static const double topOffset = 4.0;
  static const double minTitleWidth = 120.0;
  static const double topClearanceOffset = 60.0;

  /// Screen title shown inside the centered floating oval.
  final String title;

  /// Optional custom widget placed inside the centered oval instead of [title].
  final Widget? titleWidget;

  /// Custom back callback. Defaults to `Navigator.of(context).maybePop()`.
  final VoidCallback? onBack;

  /// Whether to render the left circular back button.
  final bool showBackButton;

  /// Optional trailing action buttons.
  final List<SettingsHeaderAction> actions;

  /// Creates a floating header bar.
  const SettingsFloatingHeader({
    super.key,
    this.title = '',
    this.titleWidget,
    this.onBack,
    this.showBackButton = true,
    this.actions = const [],
  });

  /// Recommended scrollable top padding so content starts below the header
  /// and scrolls smoothly beneath the floating pills.
  static double topClearanceOf(BuildContext context) {
    return MediaQuery.paddingOf(context).top + topClearanceOffset;
  }

  /// Resolves the foreground color matching [TheavThemeExtension] or brightness.
  static Color foregroundColorOf(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themeExt = theme.extension<TheavThemeExtension>();
    return themeExt?.palette.appBarForeground ??
        (isDark ? Colors.white : const Color(0xFF1C1C1E));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foregroundColor = foregroundColorOf(context);
    final statusBarHeight = MediaQuery.paddingOf(context).top;
    final titleStyle = TextStyle(
      fontSize: 16.5,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
      color: foregroundColor,
      fontFamily: theme.textTheme.titleMedium?.fontFamily,
    );

    final effectiveOnBack = showBackButton
        ? (onBack ?? () => Navigator.of(context).maybePop())
        : null;

    return Padding(
      padding: EdgeInsets.fromLTRB(
        horizontalPadding,
        statusBarHeight + topOffset,
        horizontalPadding,
        0,
      ),
      child: SizedBox(
        height: buttonSize,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final leftWidth = showBackButton ? buttonSize : 0.0;
            final rightWidth = actions.isEmpty
                ? 0.0
                : actions.length * buttonSize;
            final leftOccupied =
                leftWidth > 0 ? leftWidth + headerGap : 0.0;
            final rightOccupied =
                rightWidth > 0 ? rightWidth + headerGap : 0.0;
            final maxUsableWidth =
                math.max(0.0, availableWidth - leftOccupied - rightOccupied);

            final double idealTitleWidth = titleWidget != null
                ? maxUsableWidth
                : _measureTitlePillWidth(
                    context,
                    title,
                    titleStyle,
                  );

            final double clampedMinWidth =
                math.min(minTitleWidth, maxUsableWidth);
            final double targetTitleWidth = maxUsableWidth <= 0
                ? 0.0
                : idealTitleWidth.clamp(clampedMinWidth, maxUsableWidth);

            final double screenCenteredLeft =
                (availableWidth - targetTitleWidth) / 2.0;
            final double minLeft = leftOccupied;
            final double maxLeft = math.max(
              minLeft,
              availableWidth - rightOccupied - targetTitleWidth,
            );
            final double pillLeft =
                screenCenteredLeft.clamp(minLeft, maxLeft);

            return Stack(
              clipBehavior: Clip.none,
              children: [
                if (showBackButton)
                  Positioned(
                    left: 0,
                    top: 0,
                    child: SettingsFloatingCircleButton(
                      tooltip: Localizations.of<MaterialLocalizations>(
                            context,
                            MaterialLocalizations,
                          )?.backButtonTooltip ??
                          'Back',
                      onTap: effectiveOnBack,
                      icon: iconoir.NavArrowLeft(
                        width: 22.0,
                        height: 22.0,
                        color: foregroundColor,
                      ),
                    ),
                  ),
                if (targetTitleWidth > 0 &&
                    (titleWidget != null || title.isNotEmpty))
                  Positioned(
                    left: pillLeft,
                    top: 0,
                    width: targetTitleWidth,
                    height: buttonSize,
                    child: SettingsFloatingSurface(
                      borderRadius: buttonSize / 2,
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Center(
                        child: titleWidget ??
                            Text(
                              title,
                              style: titleStyle,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.center,
                            ),
                      ),
                    ),
                  ),
                if (actions.isNotEmpty)
                  Positioned(
                    right: 0,
                    top: 0,
                    child: _buildActionsCapsule(
                      context,
                      foregroundColor,
                      rightWidth,
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  double _measureTitlePillWidth(
    BuildContext context,
    String text,
    TextStyle style,
  ) {
    if (text.isEmpty) return 0.0;
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    return math.max(minTitleWidth, painter.width.ceilToDouble() + 34.0);
  }

  Widget _buildActionsCapsule(
    BuildContext context,
    Color foregroundColor,
    double totalWidth,
  ) {
    if (actions.length == 1) {
      final action = actions.first;
      if (action.child != null && action.onTap == null) {
        return SizedBox(
          width: buttonSize,
          height: buttonSize,
          child: SettingsFloatingSurface(
            borderRadius: buttonSize / 2,
            child: Center(child: action.child),
          ),
        );
      }
      return SettingsFloatingCircleButton(
        tooltip: action.tooltip,
        enabled: action.enabled,
        onTap: action.onTap,
        icon: action.child ??
            IconTheme(
              data: IconThemeData(
                color: action.foregroundColor ?? foregroundColor,
                size: 22.0,
              ),
              child: action.icon!,
            ),
      );
    }

    return SizedBox(
      width: totalWidth,
      height: buttonSize,
      child: SettingsFloatingSurface(
        borderRadius: buttonSize / 2,
        child: Row(
          children: [
            for (int i = 0; i < actions.length; i++) ...[
              if (i > 0)
                Container(
                  width: 0.5,
                  height: 20.0,
                  color: foregroundColor.withValues(alpha: 0.16),
                ),
              Expanded(
                child: _buildActionSlot(
                  context,
                  actions[i],
                  foregroundColor,
                  i == 0,
                  i == actions.length - 1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildActionSlot(
    BuildContext context,
    SettingsHeaderAction action,
    Color foregroundColor,
    bool isFirst,
    bool isLast,
  ) {
    final radius = BorderRadius.horizontal(
      left: isFirst ? const Radius.circular(buttonSize / 2) : Radius.zero,
      right: isLast ? const Radius.circular(buttonSize / 2) : Radius.zero,
    );

    final inner = action.child ??
        IconTheme(
          data: IconThemeData(
            color: action.enabled
                ? (action.foregroundColor ?? foregroundColor)
                : foregroundColor.withValues(alpha: 0.38),
            size: 21.0,
          ),
          child: action.icon!,
        );

    final widget = Material(
      type: MaterialType.transparency,
      child: InkWell(
        borderRadius: radius,
        onTap: action.enabled && action.onTap != null
            ? () {
                HapticUtils.tap();
                action.onTap!();
              }
            : null,
        child: SizedBox(
          height: buttonSize,
          child: Center(child: inner),
        ),
      ),
    );

    if (action.tooltip != null && action.tooltip!.isNotEmpty) {
      return Tooltip(message: action.tooltip!, child: widget);
    }
    return widget;
  }
}

/// Reusable scaffold that overlays [SettingsFloatingHeader] above [body].
///
/// By default ([padBodyTop] = `false`), scrollable bodies render edge-to-edge
/// underneath the floating pills while receiving top clearance via
/// [MediaQuery.padding.top]. Pass [padBodyTop] = `true` for non-scrollable
/// `Column` bodies that should start cleanly below the header.
class SettingsFloatingScaffold extends StatelessWidget {
  final String title;
  final Widget? titleWidget;
  final Widget body;
  final VoidCallback? onBack;
  final bool showBackButton;
  final List<SettingsHeaderAction> actions;
  final Widget? floatingActionButton;
  final Widget? bottomNavigationBar;
  final Color? backgroundColor;
  final bool padBodyTop;

  /// Creates a settings scaffold with a floating pill-and-circle header.
  const SettingsFloatingScaffold({
    super.key,
    this.title = '',
    this.titleWidget,
    required this.body,
    this.onBack,
    this.showBackButton = true,
    this.actions = const [],
    this.floatingActionButton,
    this.bottomNavigationBar,
    this.backgroundColor,
    this.padBodyTop = false,
  });

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    final topClearance = SettingsFloatingHeader.topClearanceOf(context);
    final effectiveBg = backgroundColor ?? Theme.of(context).scaffoldBackgroundColor;

    final Widget resolvedBody = padBodyTop
        ? Padding(
            padding: EdgeInsets.only(top: topClearance),
            child: body,
          )
        : MediaQuery(
            data: mq.copyWith(
              padding: mq.padding.copyWith(
                top: math.max(mq.padding.top, topClearance),
              ),
            ),
            child: body,
          );

    return Scaffold(
      backgroundColor: effectiveBg,
      floatingActionButton: floatingActionButton,
      bottomNavigationBar: bottomNavigationBar,
      body: Stack(
        children: [
          Positioned.fill(child: resolvedBody),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SettingsFloatingHeader(
              title: title,
              titleWidget: titleWidget,
              onBack: onBack,
              showBackButton: showBackButton,
              actions: actions,
            ),
          ),
        ],
      ),
    );
  }
}

/// Attached bottom sheet container flush with the bottom edge of the screen.
///
/// Full-width on mobile viewports and centered up to `500px` on wide layouts.
class SettingsAttachedSheet extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double maxWidth;
  final double maxHeightFactor;

  /// Creates an attached bottom sheet surface matching Theaver's design tokens.
  const SettingsAttachedSheet({
    super.key,
    required this.child,
    this.padding,
    this.maxWidth = 500.0,
    this.maxHeightFactor = 0.88,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themeExt = theme.extension<TheavThemeExtension>();
    final glassProvider = maybeLiquidGlassProvider(context);
    final isGlassEnabled = glassProvider?.enabled ?? false;
    final baseBg = themeExt?.palette.surface ??
        (isDark ? const Color(0xFF171C24) : Colors.white);
    final sheetBg = baseBg.withValues(alpha: isDark ? 0.90 : 0.94);
    final dividerColor = themeExt?.palette.divider ??
        (isDark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.black.withValues(alpha: 0.08));
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    final maxHeight = MediaQuery.sizeOf(context).height * maxHeightFactor;

    return Align(
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: ClipRRect(
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
            child: BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: isGlassEnabled ? 24 : 18,
                sigmaY: isGlassEnabled ? 24 : 18,
              ),
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: sheetBg,
                  borderRadius:
                      const BorderRadius.vertical(top: Radius.circular(24)),
                  border: Border(
                    top: BorderSide(color: dividerColor, width: 0.8),
                    left: BorderSide(color: dividerColor, width: 0.5),
                    right: BorderSide(color: dividerColor, width: 0.5),
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 10, bottom: 4),
                      child: Container(
                        width: 38,
                        height: 4,
                        decoration: BoxDecoration(
                          color: (isDark ? Colors.white : Colors.black)
                              .withValues(alpha: 0.20),
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Flexible(
                      child: Padding(
                        padding: padding ??
                            EdgeInsets.fromLTRB(
                              20,
                              10,
                              20,
                              math.max(20.0, bottomInset + 12.0),
                            ),
                        child: child,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
