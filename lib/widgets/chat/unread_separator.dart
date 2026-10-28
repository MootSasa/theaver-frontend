import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import '../../l10n/app_localizations.dart';
import '../../models/theav_theme.dart';
import '../../services/liquid_glass_provider.dart';
import '../../utils/blur_utils.dart';

/// Разделитель «Непрочитанные сообщения» в чате (статичный, как в Telegram)
class UnreadSeparator extends StatelessWidget {
  final int? count;
  final VoidCallback? onTap;

  const UnreadSeparator({
    Key? key,
    this.count,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final glassEnabled = context.watch<LiquidGlassProvider>().enabled;

    final rawLabel = l10n.translate('chat_unread_messages_banner');
    final label = rawLabel == 'chat_unread_messages_banner'
        ? 'Непрочитанные сообщения'
        : rawLabel;

    final bgColor = glassEnabled
        ? (isDark
            ? Colors.white.withValues(alpha: 0.10)
            : Colors.black.withValues(alpha: 0.06))
        : (isDark
            ? theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.65)
            : theme.colorScheme.primaryContainer.withValues(alpha: 0.35));

    final textColor = glassEnabled
        ? (isDark ? Colors.white.withValues(alpha: 0.92) : Colors.black87)
        : theme.colorScheme.primary;

    final lineColor = textColor.withValues(alpha: 0.25);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 16),
      color: bgColor,
      child: Row(
        children: [
          Expanded(child: Container(height: 1, color: lineColor)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              label,
              style: TextStyle(
                color: textColor,
                fontSize: 12.5,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          Expanded(child: Container(height: 1, color: lineColor)),
        ],
      ),
    );
  }
}

/// Дата-разделитель между днями в чате (кликабельная плашка даты)
class DateSeparator extends StatelessWidget {
  final String dateLabel;
  final VoidCallback? onTap;

  const DateSeparator({
    Key? key,
    required this.dateLabel,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final themeExt = theme.extension<TheavThemeExtension>();
    final glassProvider = context.watch<LiquidGlassProvider>();
    final glassEnabled = glassProvider.enabled;

    final badgeBg = themeExt?.palette.chatDateBadge ??
        (isDark
            ? Colors.black.withValues(alpha: 0.42)
            : Colors.black.withValues(alpha: 0.22));
    final badgeText = themeExt?.palette.chatDateBadgeText ?? Colors.white;

    Widget pillContent = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4.5),
      child: Text(
        dateLabel,
        style: TextStyle(
          color: badgeText,
          fontSize: 12,
          fontWeight: FontWeight.w600,
          height: 1.15,
        ),
      ),
    );

    Widget pill;
    if (glassEnabled) {
      pill = ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter.grouped(
          filter: BlurUtils.createDownsampledBlur(12),
          child: Container(
            decoration: BoxDecoration(
              color: isDark
                  ? Colors.black.withValues(alpha: 0.38)
                  : Colors.black.withValues(alpha: 0.26),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: isDark ? 0.14 : 0.22),
                width: 0.6,
              ),
            ),
            child: pillContent,
          ),
        ),
      );
    } else {
      pill = Container(
        decoration: BoxDecoration(
          color: badgeBg,
          borderRadius: BorderRadius.circular(14),
        ),
        child: pillContent,
      );
    }

    if (onTap != null) {
      pill = MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: pill,
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      child: Center(child: pill),
    );
  }
}

/// Плавающая (sticky) плашка с датой вверху экрана чата при прокрутке
class FloatingChatDateHeader extends StatelessWidget {
  final String dateLabel;
  final bool visible;
  final double pushOffset;
  final VoidCallback? onTap;

  const FloatingChatDateHeader({
    Key? key,
    required this.dateLabel,
    required this.visible,
    this.pushOffset = 0.0,
    this.onTap,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final effectiveVisible = visible && dateLabel.isNotEmpty;
    return IgnorePointer(
      ignoring: !effectiveVisible,
      child: AnimatedOpacity(
        opacity: effectiveVisible ? 1.0 : 0.0,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
        child: Transform.translate(
          offset: Offset(0, pushOffset),
          child: DateSeparator(
            dateLabel: dateLabel,
            onTap: onTap,
          ),
        ),
      ),
    );
  }
}

/// FAB кнопка прокрутки вниз с бейджем непрочитанных
class ScrollDownFab extends StatefulWidget {
  final int unreadCount;
  final VoidCallback onPressed;
  final bool visible;

  const ScrollDownFab({
    Key? key,
    required this.unreadCount,
    required this.onPressed,
    this.visible = true,
  }) : super(key: key);

  @override
  State<ScrollDownFab> createState() => _ScrollDownFabState();
}

class _ScrollDownFabState extends State<ScrollDownFab>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
      value: widget.visible ? 1.0 : 0.0,
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(1.5, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    ));
  }

  @override
  void didUpdateWidget(covariant ScrollDownFab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible != oldWidget.visible) {
      if (widget.visible) {
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
        if (_controller.isDismissed && !widget.visible) {
          return const SizedBox.shrink();
        }
        final glassEnabled = context.watch<LiquidGlassProvider>().enabled;
        final theme = Theme.of(context);
        final themeExt = theme.extension<TheavThemeExtension>();
        final isDark = theme.brightness == Brightness.dark;
        final unreadBg = themeExt?.palette.unreadBadge ?? theme.colorScheme.primary;
        final unreadText = themeExt?.palette.unreadBadgeText ?? Colors.white;

        final child = Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            const Icon(Icons.keyboard_arrow_down, size: 28),
            if (widget.unreadCount > 0)
              Positioned(
                top: -4,
                right: -4,
                child: Container(
                  padding: const EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: unreadBg,
                    shape: BoxShape.circle,
                  ),
                  constraints: const BoxConstraints(minWidth: 18, minHeight: 18),
                  child: Text(
                    widget.unreadCount > 99 ? '99+' : '${widget.unreadCount}',
                    style: TextStyle(
                      color: unreadText,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
              ),
          ],
        );

        return IgnorePointer(
          ignoring: !widget.visible,
          child: SlideTransition(
            position: _slideAnimation,
            child: GestureDetector(
              onTap: widget.onPressed,
              child: SizedBox(
                width: 48,
                height: 48,
                child: glassEnabled
                    ? _buildGlassButton(context, isDark, child)
                    : _buildMatteButton(context, isDark, child),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGlassButton(BuildContext context, bool isDark, Widget child) {
    final glassProvider = context.watch<LiquidGlassProvider>();

    final style = glassProvider.createStyle(
      context: context,
      cornerRadius: 24,
      refractionIndex: 1.1,
      refractionWidth: 24,
    );

    return LiquidGlassLens(
      style: style,
      touch: const LiquidGlassTouch.flexing(LiquidGlassFlex(
        stretch: 6,
        squeeze: 0.65,
        lean: 0.3,
        grip: 0.5,
      )),
      child: Center(child: child),
    );
  }

  Widget _buildMatteButton(BuildContext context, bool isDark, Widget child) {
    return ClipOval(
      child: BackdropFilter.grouped(
        filter: BlurUtils.createDownsampledBlur(15),
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: isDark
                ? Colors.black.withValues(alpha: 0.65)
                : Colors.white.withValues(alpha: 0.65),
            border: Border.all(
              color: isDark ? Colors.white10 : Colors.black12,
              width: 0.5,
            ),
          ),
          child: Center(child: child),
        ),
      ),
    );
  }
}
