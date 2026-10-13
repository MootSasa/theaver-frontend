import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'liquid_glass_provider.dart';

/// Service to show beautiful glass toasts ("clouds") throughout the app.
class GlassToastService {
  static final GlassToastService _instance = GlassToastService._internal();
  factory GlassToastService() => _instance;
  GlassToastService._internal();

  OverlayEntry? _overlayEntry;
  Timer? _timer;

  /// Shows a glass toast with the given [message], [icon], or [iconWidget].
  void show(
    BuildContext context,
    String message, {
    IconData? icon,
    Widget? iconWidget,
    Duration duration = const Duration(seconds: 3),
  }) {
    _hide();

    _overlayEntry = OverlayEntry(
      builder: (context) => _GlassToastWidget(
        message: message,
        icon: icon,
        iconWidget: iconWidget,
        onDismiss: _hide,
      ),
    );

    final overlay = Overlay.of(context);
    overlay.insert(_overlayEntry!);

    _timer = Timer(duration, _hide);
  }

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
  final VoidCallback onDismiss;

  const _GlassToastWidget({
    required this.message,
    this.icon,
    this.iconWidget,
    required this.onDismiss,
  });

  @override
  State<_GlassToastWidget> createState() => _GlassToastWidgetState();
}

class _GlassToastWidgetState extends State<_GlassToastWidget> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _opacity;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );

    _opacity = Tween<double>(begin: 0, end: 1).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeIn),
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
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    
    // We use context.read because we don't expect the mode to change while the toast is visible
    final glassProvider = Provider.of<LiquidGlassProvider>(context, listen: false);
    final isGlassEnabled = glassProvider.enabled;

    return SafeArea(
      child: Align(
        alignment: Alignment.bottomCenter,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 100), // Positioned above the input field
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Opacity(
                opacity: _opacity.value,
                child: child,
              );
            },
            child: Material(
              color: Colors.transparent,
              child: IntrinsicWidth(
                child: IntrinsicHeight(
                  child: isGlassEnabled 
                    ? _buildMatteGlass(isDark, theme, glassProvider) 
                    : _buildClassicBlur(isDark, theme),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Matte glass effect using LiquidGlass (for Glass design)
  Widget _buildMatteGlass(bool isDark, ThemeData theme, LiquidGlassProvider glassProvider) {
    final style = glassProvider.createStyle(
      blur: 25.0,
      refractionIndex: 1.05,
      refractionWidth: 15.0,
      color: isDark 
          ? Colors.black.withValues(alpha: 0.5) 
          : Colors.white.withValues(alpha: 0.5),
      shape: const LiquidGlassShape.continuousRoundedRectangle(
        cornerRadius: 24,
      ),
    );

    return LiquidGlassLens(
      style: style,
      child: _buildContent(theme),
    );
  }

  /// Classic blur effect using BackdropFilter (for Classic design)
  Widget _buildClassicBlur(bool isDark, ThemeData theme) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(24),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          decoration: BoxDecoration(
            color: isDark 
                ? Colors.black.withValues(alpha: 0.6) 
                : Colors.white.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.black12,
              width: 0.5,
            ),
          ),
          child: _buildContent(theme),
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.iconWidget != null) ...[
            widget.iconWidget!,
            const SizedBox(width: 12),
          ] else if (widget.icon != null) ...[
            Icon(widget.icon, color: theme.colorScheme.onSurface, size: 20),
            const SizedBox(width: 12),
          ],
          Flexible(
            child: Text(
              widget.message,
              style: TextStyle(
                color: theme.colorScheme.onSurface,
                fontSize: 15,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
