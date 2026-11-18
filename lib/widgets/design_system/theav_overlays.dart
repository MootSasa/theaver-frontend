import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../../utils/haptic_utils.dart';
import 'theav_design_system.dart';

/// Opens a dual-mode [TheavModalSheet] that renders crisp translucent glass blur
/// in `full`/`lite` modes and solid matte [TheavPalette.surface] when disabled.
Future<T?> showTheavModalSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  String? title,
  Widget? trailing,
  EdgeInsetsGeometry padding = const EdgeInsets.fromLTRB(16, 10, 16, 20),
  bool isScrollControlled = true,
  bool enableDrag = true,
  bool showCloseButton = false,
  double maxHeightFactor = 0.92,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    enableDrag: enableDrag,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black54,
    builder: (ctx) => TheavModalSheet(
      title: title,
      trailing: trailing,
      padding: padding,
      showCloseButton: showCloseButton,
      maxHeightFactor: maxHeightFactor,
      child: builder(ctx),
    ),
  );
}

/// Dual-mode modal bottom sheet container with drag handle, optional header bar,
/// safe keyboard inset handling, and [TheavPalette] styling.
class TheavModalSheet extends StatelessWidget {
  final Widget child;
  final String? title;
  final Widget? trailing;
  final EdgeInsetsGeometry padding;
  final bool showCloseButton;
  final double maxHeightFactor;

  const TheavModalSheet({
    super.key,
    required this.child,
    this.title,
    this.trailing,
    this.padding = const EdgeInsets.fromLTRB(16, 10, 16, 20),
    this.showCloseButton = false,
    this.maxHeightFactor = 0.92,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final mq = MediaQuery.of(context);
    final blurFilter = style.getBlurFilter(sigma: 22.0);
    final bool hasHeader =
        (title != null && title!.isNotEmpty) || trailing != null || showCloseButton;

    Widget sheet = Container(
      constraints: BoxConstraints(
        maxHeight: mq.size.height * maxHeightFactor,
      ),
      decoration: BoxDecoration(
        color: style.overlayFill,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        border: Border.all(
          color: style.hudBorder,
          width: 0.5,
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
          child: Padding(
            padding: padding,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: EdgeInsets.only(bottom: hasHeader ? 12 : 14),
                    decoration: BoxDecoration(
                      color: palette.onSurface.withValues(alpha: 0.22),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                if (hasHeader) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        if (showCloseButton) ...[
                          TheavHeaderIconButton(
                            size: 36,
                            icon: iconoir.Xmark(
                              width: 18,
                              height: 18,
                              color: palette.onSurface,
                            ),
                            onTap: () => Navigator.of(context).maybePop(),
                          ),
                          const SizedBox(width: 10),
                        ],
                        if (title != null && title!.isNotEmpty)
                          Expanded(
                            child: Text(
                              title!,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: palette.onSurface,
                                fontSize: 17.5,
                                fontWeight: FontWeight.w700,
                                letterSpacing: -0.2,
                              ),
                            ),
                          )
                        else
                          const Spacer(),
                        if (trailing != null) trailing!,
                      ],
                    ),
                  ),
                ],
                Flexible(child: child),
              ],
            ),
          ),
        ),
      ),
    );

    if (blurFilter != null) {
      sheet = ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: BackdropFilter(
          filter: blurFilter,
          child: sheet,
        ),
      );
    }

    return sheet;
  }
}

/// Action button descriptor for [TheavDialog] and [showTheavDialog].
class TheavDialogAction<T> {
  final String label;
  final T? result;
  final VoidCallback? onPressed;
  final bool isDestructive;
  final bool isPrimary;

  const TheavDialogAction({
    required this.label,
    this.result,
    this.onPressed,
    this.isDestructive = false,
    this.isPrimary = false,
  });
}

/// Shows a dual-mode [TheavDialog] replacing standard [AlertDialog].
Future<T?> showTheavDialog<T>({
  required BuildContext context,
  String? title,
  String? message,
  Widget? content,
  Widget? icon,
  List<TheavDialogAction<T>>? actions,
  List<Widget>? customActions,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: Colors.black54,
    builder: (ctx) => TheavDialog<T>(
      title: title,
      message: message,
      content: content,
      icon: icon,
      actions: actions,
      customActions: customActions,
    ),
  );
}

/// Dual-mode modal dialog built with [TheavPalette] tokens instead of stock
/// Material [AlertDialog].
class TheavDialog<T> extends StatelessWidget {
  final String? title;
  final String? message;
  final Widget? content;
  final Widget? icon;
  final List<TheavDialogAction<T>>? actions;
  final List<Widget>? customActions;

  const TheavDialog({
    super.key,
    this.title,
    this.message,
    this.content,
    this.icon,
    this.actions,
    this.customActions,
  });

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context);
    final palette = style.palette;
    final blurFilter = style.getBlurFilter(sigma: 22.0);
    final resolvedActions = actions ?? const [];

    Widget card = Container(
      constraints: const BoxConstraints(maxWidth: 344),
      decoration: BoxDecoration(
        color: style.overlayFill,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: style.hudBorder,
          width: 0.5,
        ),
        boxShadow: style.floatingShadow,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (icon != null) ...[
                Center(
                  child: IconTheme(
                    data: IconThemeData(color: palette.primary, size: 28),
                    child: icon!,
                  ),
                ),
                const SizedBox(height: 12),
              ],
              if (title != null && title!.isNotEmpty)
                Text(
                  title!,
                  style: TextStyle(
                    color: palette.onSurface,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2,
                  ),
                ),
              if (message != null && message!.isNotEmpty) ...[
                if (title != null && title!.isNotEmpty) const SizedBox(height: 8),
                Text(
                  message!,
                  style: TextStyle(
                    color: palette.subtext,
                    fontSize: 14.5,
                    height: 1.4,
                  ),
                ),
              ],
              if (content != null) ...[
                if ((title != null && title!.isNotEmpty) ||
                    (message != null && message!.isNotEmpty))
                  const SizedBox(height: 14),
                content!,
              ],
              if (resolvedActions.isNotEmpty ||
                  (customActions != null && customActions!.isNotEmpty)) ...[
                const SizedBox(height: 18),
                if (customActions != null && customActions!.isNotEmpty)
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: customActions!,
                  )
                else
                  Wrap(
                    alignment: WrapAlignment.end,
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final action in resolvedActions)
                        _DialogActionButton<T>(action: action),
                    ],
                  ),
              ],
            ],
          ),
        ),
      ),
    );

    if (blurFilter != null) {
      card = ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: blurFilter,
          child: card,
        ),
      );
    }

    return Center(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          24,
          24,
          24,
          24 + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: card,
      ),
    );
  }
}

class _DialogActionButton<T> extends StatelessWidget {
  final TheavDialogAction<T> action;

  const _DialogActionButton({required this.action});

  @override
  Widget build(BuildContext context) {
    final palette = context.theav;
    final bool filled = action.isPrimary || action.isDestructive;
    final Color bgColor = action.isDestructive
        ? palette.error.withValues(alpha: 0.14)
        : (action.isPrimary
            ? palette.primary
            : palette.onSurface.withValues(alpha: 0.06));
    final Color fgColor = action.isDestructive
        ? palette.error
        : (action.isPrimary ? palette.onPrimary : palette.onSurface);

    return Material(
      color: filled ? bgColor : palette.onSurface.withValues(alpha: 0.05),
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () {
          HapticUtils.tap();
          if (action.onPressed != null) {
            action.onPressed!();
          } else {
            Navigator.of(context).pop(action.result);
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Text(
            action.label,
            style: TextStyle(
              color: fgColor,
              fontSize: 14.5,
              fontWeight: filled ? FontWeight.w600 : FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}
