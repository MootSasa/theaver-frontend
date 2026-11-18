import 'dart:async';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

import '../widgets/design_system/theav_design_system.dart';

/// Dual-mode floating toast ("cloud") overlay using [TheavSurfaceStyle]
/// (`context.theav` palette) and safe GPU animations (no [Opacity] around
/// [LiquidGlassLens]).
class GlassToastService {
  static final GlassToastService _instance = GlassToastService._internal();
  factory GlassToastService() => _instance;
  GlassToastService._internal();

  OverlayEntry? _overlayEntry;
  Timer? _timer;

  /// Shows a floating toast with optional icon, action button, or error styling.
  void show(
    BuildContext context,
    String message, {
    IconData? icon,
    Widget? iconWidget,
    Duration duration = const Duration(seconds: 3),
    String? actionLabel,
    VoidCallback? onAction,
    bool isError = false,
  }) {
    _hide();

    final overlay = Overlay.maybeOf(context);
    if (overlay == null) return;

    _overlayEntry = OverlayEntry(
      builder: (ctx) => _GlassToastWidget(
        message: message,
        icon: icon,
        iconWidget: iconWidget,
        actionLabel: actionLabel,
        onAction: onAction,
        isError: isError,
        onDismiss: _hide,
      ),
    );

    overlay.insert(_overlayEntry!);
    _timer = Timer(duration, _hide);
  }

  /// Convenience helper for error notifications.
  void showError(
    BuildContext context,
    String message, {
    Duration duration = const Duration(seconds: 3),
  }) {
    show(
      context,
      message,
      isError: true,
      duration: duration,
    );
  }

  /// Hides the currently visible toast overlay, if any.
  void hide() => _hide();

  void _hide() {
    _overlayEntry?.remove();
    _overlayEntry = null;
    _timer?.cancel();
    _timer = null;
  }
}

class _GlassToastWidget extends StatefulWidget {
  final String message;
  final IconData? icon;
  final Widget? iconWidget;
  final String? actionLabel;
  final VoidCallback? onAction;
  final bool isError;
  final VoidCallback onDismiss;

  const _GlassToastWidget({
    required this.message,
    this.icon,
    this.iconWidget,
    this.actionLabel,
    this.onAction,
    required this.isError,
    required this.onDismiss,
  });

  @override
  State<_GlassToastWidget> createState() => _GlassToastWidgetState();
}

class _GlassToastWidgetState extends State<_GlassToastWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _progress;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    );
    _progress = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = TheavSurfaceStyle.of(context, listen: false);
    final palette = style.palette;

    final Color? fillOverride = widget.isError
        ? Color.alphaBlend(
            palette.error.withValues(alpha: style.isDark ? 0.24 : 0.14),
            style.hudFill,
          )
        : null;

    final Widget pill = GestureDetector(
      onTap: widget.onDismiss,
      child: TheavFloatingSurface(
        borderRadius: 24,
        refractionIndex: 1.08,
        refractionWidth: 18,
        colorOverride: fillOverride,
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
            child: _buildContent(palette),
          ),
        ),
      ),
    );

    final Animation<Offset> slide = Tween<Offset>(
      begin: const Offset(0, 0.32),
      end: Offset.zero,
    ).animate(_progress);

    // Never wrap shader-backed LiquidGlassLens in Opacity or FadeTransition.
    final Widget animatedPill = style.isFull
        ? SlideTransition(
            position: slide,
            child: ScaleTransition(
              scale: Tween<double>(begin: 0.92, end: 1.0).animate(_progress),
              child: pill,
            ),
          )
        : SlideTransition(
            position: slide,
            child: FadeTransition(
              opacity: _progress,
              child: pill,
            ),
          );

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 96),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: animatedPill,
          ),
        ),
      ),
    );
  }

  Widget _buildContent(TheavPalette palette) {
    final Color iconColor =
        widget.isError ? palette.error : palette.primary;

    final Widget? leadingIcon = widget.iconWidget ??
        (widget.icon != null
            ? Icon(widget.icon, color: iconColor, size: 19)
            : (widget.isError
                ? iconoir.WarningTriangle(
                    width: 19,
                    height: 19,
                    color: palette.error,
                  )
                : null));

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (leadingIcon != null) ...[
          leadingIcon,
          const SizedBox(width: 10),
        ],
        Flexible(
          child: Text(
            widget.message,
            style: TextStyle(
              color: palette.onSurface,
              fontSize: 14.5,
              fontWeight: FontWeight.w500,
              height: 1.3,
            ),
          ),
        ),
        if (widget.actionLabel != null &&
            widget.actionLabel!.isNotEmpty &&
            widget.onAction != null) ...[
          const SizedBox(width: 12),
          GestureDetector(
            onTap: () {
              widget.onDismiss();
              widget.onAction?.call();
            },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: palette.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                widget.actionLabel!,
                style: TextStyle(
                  color: palette.primary,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}
