import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import '../../models/theav_theme.dart';
import '../../services/liquid_glass_provider.dart';
import '../../utils/blur_utils.dart';

/// Collapsible grid of reply keyboard buttons (`reply_markup.keyboard`)
/// displayed below `ChatInputBar` when a bot message provides a custom keyboard.
///
/// Animates geometrically (heightFactor + slide) without applying FadeTransition
/// to the `LiquidGlassLens` container.
class ReplyKeyboardPanel extends StatefulWidget {
  final List<List<Map<String, dynamic>>> rows;
  final ValueChanged<String> onButtonPressed;
  final bool resizeKeyboard;
  final bool isOpen;

  const ReplyKeyboardPanel({
    super.key,
    required this.rows,
    required this.onButtonPressed,
    this.resizeKeyboard = true,
    this.isOpen = true,
  });

  @override
  State<ReplyKeyboardPanel> createState() => _ReplyKeyboardPanelState();
}

class _ReplyKeyboardPanelState extends State<ReplyKeyboardPanel>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _heightFactor;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _innerFade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
      value: (widget.isOpen && widget.rows.isNotEmpty) ? 1.0 : 0.0,
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _heightFactor = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.25),
      end: Offset.zero,
    ).animate(curved);
    _innerFade = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: const Interval(0.2, 1.0, curve: Curves.easeOut),
      ),
    );
  }

  @override
  void didUpdateWidget(covariant ReplyKeyboardPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    final shouldShow = widget.isOpen && widget.rows.isNotEmpty;
    final wasShowing = oldWidget.isOpen && oldWidget.rows.isNotEmpty;
    if (shouldShow != wasShowing) {
      if (shouldShow) {
        _controller.forward();
      } else {
        _controller.reverse();
      }
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        if (_controller.isDismissed && (!widget.isOpen || widget.rows.isEmpty)) {
          return const SizedBox.shrink();
        }
        if (widget.rows.isEmpty) {
          return const SizedBox.shrink();
        }

        final theme = Theme.of(context);
        final isDark = theme.brightness == Brightness.dark;
        final ext = theme.extension<TheavThemeExtension>();
        final colorScheme = theme.colorScheme;
        final bottomPadding = MediaQuery.of(context).padding.bottom;
        final glassProvider = context.watch<LiquidGlassProvider?>();
        final glassEnabled = glassProvider?.enabled ?? false;
        final isLite = glassProvider?.isLite ?? false;

        final Widget gridContent = FadeTransition(
          opacity: _innerFade,
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(10, 8, 10, 8 + bottomPadding),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int r = 0; r < widget.rows.length; r++) ...[
                  if (r > 0) const SizedBox(height: 6),
                  Row(
                    children: [
                      for (int c = 0; c < widget.rows[r].length; c++) ...[
                        if (c > 0) const SizedBox(width: 6),
                        Expanded(
                          child: _buildReplyButton(
                            context,
                            widget.rows[r][c],
                            theme,
                            ext,
                            colorScheme,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ],
            ),
          ),
        );

        Widget panelSurface;
        if (glassEnabled && glassProvider != null) {
          final style = glassProvider.createStyle(
            context: context,
            cornerRadius: 20,
            refractionIndex: 1.1,
            refractionWidth: 24,
            isLiteOverride: isLite,
          );
          panelSurface = Padding(
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: widget.resizeKeyboard ? 220 : 260,
              ),
              child: LiquidGlassLens(
                style: style,
                child: gridContent,
              ),
            ),
          );
        } else {
          panelSurface = Container(
            width: double.infinity,
            constraints: BoxConstraints(
              maxHeight: widget.resizeKeyboard ? 220 : 260,
            ),
            decoration: BoxDecoration(
              color: ext?.glassSurfaceColor ??
                  colorScheme.surfaceContainerLow.withValues(alpha: 0.95),
              border: Border(
                top: BorderSide(
                  color: ext?.glassBorderColor ??
                      (isDark ? Colors.white10 : Colors.black12),
                  width: 0.8,
                ),
              ),
            ),
            child: ClipRect(
              child: BackdropFilter.grouped(
                filter: BlurUtils.createDownsampledBlur(15),
                child: gridContent,
              ),
            ),
          );
        }

        return ClipRect(
          child: Align(
            alignment: Alignment.topCenter,
            heightFactor: _heightFactor.value,
            child: SlideTransition(
              position: _slideAnimation,
              child: panelSurface,
            ),
          ),
        );
      },
    );
  }

  Widget _buildReplyButton(
    BuildContext context,
    Map<String, dynamic> button,
    ThemeData theme,
    TheavThemeExtension? ext,
    ColorScheme colorScheme,
  ) {
    final text = button['text']?.toString() ?? '';
    return SizedBox(
      height: 42,
      child: Material(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.78),
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: text.isEmpty ? null : () => widget.onButtonPressed(text),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: ext?.glassBorderColor ??
                    colorScheme.outlineVariant.withValues(alpha: 0.3),
                width: 0.8,
              ),
            ),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
