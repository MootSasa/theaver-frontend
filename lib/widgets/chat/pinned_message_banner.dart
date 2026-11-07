import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';

import '../../models/theav_theme.dart';
import '../../services/chat_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../utils/blur_utils.dart';
import '../../utils/haptic_utils.dart';

/// Compact floating capsule banner displayed directly below the chat AppBar
/// when the chat has one or more pinned messages.
///
/// Supports both:
/// - **Liquid Glass (Full / Lite)**: `LiquidGlassLens` capsule with tactile
///   `LiquidGlassTouch.flexing`, animated strictly geometrically (`ClipRect` +
///   `Align(heightFactor)` + `SlideTransition`) with **NO `FadeTransition` on
///   the glass shape**.
/// - **Material / Classic (Matte)**: `BackdropFilter.grouped` capsule with
///   `TheavPalette` tokens, `0.5px` optical border, and Material `InkWell`.
class PinnedMessageBanner extends StatefulWidget {
  final Message? message;
  final int totalPinnedCount;
  final int currentPinnedIndex;
  final VoidCallback onTap;
  final VoidCallback? onUnpin;
  final bool canUnpin;

  const PinnedMessageBanner({
    super.key,
    required this.message,
    this.totalPinnedCount = 1,
    this.currentPinnedIndex = 0,
    required this.onTap,
    this.onUnpin,
    this.canUnpin = true,
  });

  @override
  State<PinnedMessageBanner> createState() => _PinnedMessageBannerState();
}

class _PinnedMessageBannerState extends State<PinnedMessageBanner>
    with SingleTickerProviderStateMixin {
  static const double _kBannerHeight = 46.0;
  static const double _kCornerRadius = 22.0;

  late final AnimationController _appearController;
  late final Animation<double> _heightFactor;
  late final Animation<Offset> _slideAnimation;

  Message? _cachedMessage;
  int _lastIndex = 0;
  int _slideDirection = 1; // 1 = scrolling down to next pin, -1 = scrolling up

  @override
  void initState() {
    super.initState();
    _cachedMessage = widget.message;
    _lastIndex = widget.currentPinnedIndex;

    _appearController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    );
    final curved = CurvedAnimation(
      parent: _appearController,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    _heightFactor = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, -0.35),
      end: Offset.zero,
    ).animate(curved);

    if (widget.message != null) {
      _appearController.forward();
    }
  }

  @override
  void didUpdateWidget(covariant PinnedMessageBanner oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentPinnedIndex != _lastIndex) {
      _slideDirection = widget.currentPinnedIndex > _lastIndex ? 1 : -1;
      _lastIndex = widget.currentPinnedIndex;
    }
    if (widget.message != null) {
      _cachedMessage = widget.message;
      if (!_appearController.isAnimating && _appearController.value < 1.0) {
        _appearController.forward();
      }
    } else if (oldWidget.message != null && widget.message == null) {
      _appearController.reverse();
    }
  }

  @override
  void dispose() {
    _appearController.dispose();
    super.dispose();
  }

  String _formatPreview(Message msg) {
    final text = msg.content.trim();
    if (text.isNotEmpty) return text;
    switch (msg.messageType) {
      case 'image':
      case 'photo':
        return '📷 Фотография';
      case 'video':
        return msg.isRound ? '🎥 Видеосообщение' : '🎬 Видео';
      case 'voice':
        return '🎤 Голосовое сообщение';
      case 'audio':
        return '🎵 Аудиозапись';
      case 'poll':
        return '📊 Опрос';
      case 'file':
      case 'document':
        return '📎 ${msg.fileName ?? 'Файл'}';
      default:
        return 'Сообщение';
    }
  }

  Widget _buildInnerContent(BuildContext context, Message msg) {
    final theme = Theme.of(context);
    final themeExt = theme.extension<TheavThemeExtension>();
    final palette = themeExt?.palette;
    final accentColor = palette?.chatReplyLine ?? theme.colorScheme.primary;
    final titleColor = palette?.chatReplyTitle ?? accentColor;
    final textColor =
        (palette?.chatReplyText ?? theme.colorScheme.onSurface)
            .withValues(alpha: 0.85);

    final headerLabel = widget.totalPinnedCount > 1
        ? 'Закреплённое сообщение #${widget.currentPinnedIndex + 1}'
        : 'Закреплённое сообщение';

    final int clampedTotal = widget.totalPinnedCount.clamp(1, 5);
    final int activeSegment = widget.currentPinnedIndex % clampedTotal;

    return SizedBox(
      height: _kBannerHeight,
      child: Padding(
        padding: const EdgeInsets.only(left: 14, right: 6),
        child: Row(
          children: [
            // Animated vertical accent indicator bar (single or multi-segment)
            SizedBox(
              width: 3.5,
              height: 30,
              child: widget.totalPinnedCount > 1
                  ? Column(
                      children: List.generate(clampedTotal, (idx) {
                        final isActive = idx == activeSegment;
                        return Expanded(
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            curve: Curves.easeOutCubic,
                            margin: const EdgeInsets.symmetric(vertical: 1.0),
                            decoration: BoxDecoration(
                              color: isActive
                                  ? accentColor
                                  : accentColor.withValues(alpha: 0.25),
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        );
                      }),
                    )
                  : Container(
                      decoration: BoxDecoration(
                        color: accentColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
            ),
            const SizedBox(width: 10),
            // Animated inner text (Fade + vertical Slide inside the lens)
            Expanded(
              child: ClipRect(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 200),
                  switchInCurve: Curves.easeOutCubic,
                  switchOutCurve: Curves.easeInCubic,
                  transitionBuilder: (child, animation) {
                    final isIncoming =
                        child.key == ValueKey<String>('${msg.id}_${widget.currentPinnedIndex}');
                    final dy = isIncoming
                        ? 0.35 * _slideDirection
                        : -0.35 * _slideDirection;
                    return FadeTransition(
                      opacity: animation,
                      child: SlideTransition(
                        position: Tween<Offset>(
                          begin: Offset(0.0, dy),
                          end: Offset.zero,
                        ).animate(animation),
                        child: child,
                      ),
                    );
                  },
                  child: Column(
                    key: ValueKey<String>('${msg.id}_${widget.currentPinnedIndex}'),
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          iconoir.Pin(
                            width: 12,
                            height: 12,
                            color: titleColor,
                          ),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              headerLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: titleColor,
                                height: 1.15,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _formatPreview(msg),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          color: textColor,
                          height: 1.15,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (widget.canUnpin && widget.onUnpin != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                tooltip: 'Открепить сообщение',
                icon: iconoir.Xmark(
                  width: 18,
                  height: 18,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                ),
                onPressed: () {
                  HapticUtils.tap();
                  widget.onUnpin?.call();
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildCapsule(BuildContext context, Message msg) {
    final glassProvider = context.watch<LiquidGlassProvider?>();
    final glassEnabled = glassProvider?.enabled ?? false;
    final theme = Theme.of(context);
    final themeExt = theme.extension<TheavThemeExtension>();
    final isDark = theme.brightness == Brightness.dark;

    final inner = _buildInnerContent(context, msg);

    if (glassEnabled && glassProvider != null) {
      final style = glassProvider.createStyle(
        context: context,
        cornerRadius: _kCornerRadius,
        refractionIndex: 1.1,
        refractionWidth: 24.0,
      );
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            HapticUtils.tap();
            widget.onTap();
          },
          child: LiquidGlassLens(
            style: style,
            touch: const LiquidGlassTouch.flexing(
              LiquidGlassFlex(
                stretch: 4,
                squeeze: 0.75,
                lean: 0.2,
                grip: 0.5,
              ),
            ),
            child: inner,
          ),
        ),
      );
    }

    // Material / Classic (Matte) mode
    final defaultBg = isDark
        ? Colors.black.withValues(alpha: 0.68)
        : Colors.white.withValues(alpha: 0.76);
    final matteBg = themeExt?.palette.explicitChatInputBackground ?? defaultBg;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(_kCornerRadius),
        child: BackdropFilter.grouped(
          filter: BlurUtils.createDownsampledBlur(15),
          child: Container(
            decoration: BoxDecoration(
              color: matteBg,
              borderRadius: BorderRadius.circular(_kCornerRadius),
              border: Border.all(
                color: isDark ? Colors.white10 : Colors.black12,
                width: 0.5,
              ),
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(_kCornerRadius),
                onTap: () {
                  HapticUtils.tap();
                  widget.onTap();
                },
                child: inner,
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _appearController,
      builder: (context, _) {
        final msg = widget.message ?? _cachedMessage;
        if ((_appearController.isDismissed && widget.message == null) ||
            msg == null) {
          return const SizedBox.shrink();
        }
        return IgnorePointer(
          ignoring: widget.message == null,
          child: ClipRect(
            child: Align(
              alignment: Alignment.topCenter,
              heightFactor: _heightFactor.value,
              child: SlideTransition(
                position: _slideAnimation,
                child: _buildCapsule(context, msg),
              ),
            ),
          ),
        );
      },
    );
  }
}
