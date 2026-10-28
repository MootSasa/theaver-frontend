import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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

/// Состояние верхней закреплённой (sticky) плашки с датой в чате.
@immutable
class StickyDateState {
  final DateTime? day;
  final String label;
  final GlobalKey? sameDaySepKey;
  final GlobalKey? nextDaySepKey;

  const StickyDateState({
    required this.day,
    required this.label,
    this.sameDaySepKey,
    this.nextDaySepKey,
  });

  static const StickyDateState empty = StickyDateState(day: null, label: '');

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is StickyDateState &&
        other.day == day &&
        other.label == label &&
        other.sameDaySepKey == sameDaySepKey &&
        other.nextDaySepKey == nextDaySepKey;
  }

  @override
  int get hashCode => Object.hash(day, label, sameDaySepKey, nextDaySepKey);
}

/// Обёртка для инлайновой плашки даты внутри списка сообщений.
/// Когда плашка доходит до верхней границы чата (`stickySlotKey`), она
/// перестаёт рисоваться в потоке сообщений и передаёт отрисовку верхней
/// закреплённой плашке (`FloatingChatDateHeader`), исключая дублирование
/// и пересоздание виджетов.
class InlineChatDateHeader extends SingleChildRenderObjectWidget {
  final DateTime day;
  final Listenable scrollListenable;
  final GlobalKey stickySlotKey;
  final ValueListenable<StickyDateState> stickyStateListenable;

  const InlineChatDateHeader({
    Key? key,
    required this.day,
    required this.scrollListenable,
    required this.stickySlotKey,
    required this.stickyStateListenable,
    required Widget child,
  }) : super(key: key, child: child);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return RenderInlineChatDateHeader(
      day: day,
      scrollListenable: scrollListenable,
      stickySlotKey: stickySlotKey,
      stickyStateListenable: stickyStateListenable,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant RenderInlineChatDateHeader renderObject,
  ) {
    renderObject
      ..day = day
      ..scrollListenable = scrollListenable
      ..stickySlotKey = stickySlotKey
      ..stickyStateListenable = stickyStateListenable;
  }
}

class RenderInlineChatDateHeader extends RenderProxyBox {
  DateTime _day;
  Listenable _scrollListenable;
  GlobalKey _stickySlotKey;
  ValueListenable<StickyDateState> _stickyStateListenable;

  RenderInlineChatDateHeader({
    required DateTime day,
    required Listenable scrollListenable,
    required GlobalKey stickySlotKey,
    required ValueListenable<StickyDateState> stickyStateListenable,
  })  : _day = day,
        _scrollListenable = scrollListenable,
        _stickySlotKey = stickySlotKey,
        _stickyStateListenable = stickyStateListenable;

  set day(DateTime value) {
    if (_day == value) return;
    _day = value;
    markNeedsPaint();
  }

  set scrollListenable(Listenable value) {
    if (identical(_scrollListenable, value)) return;
    if (attached) {
      _scrollListenable.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _scrollListenable = value;
  }

  set stickySlotKey(GlobalKey value) {
    if (_stickySlotKey == value) return;
    _stickySlotKey = value;
    markNeedsPaint();
  }

  set stickyStateListenable(ValueListenable<StickyDateState> value) {
    if (identical(_stickyStateListenable, value)) return;
    if (attached) {
      _stickyStateListenable.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _stickyStateListenable = value;
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _scrollListenable.addListener(markNeedsPaint);
    _stickyStateListenable.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _scrollListenable.removeListener(markNeedsPaint);
    _stickyStateListenable.removeListener(markNeedsPaint);
    super.detach();
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (child == null || !hasSize) return false;
    final stickyBox =
        _stickySlotKey.currentContext?.findRenderObject() as RenderBox?;
    if (stickyBox != null && stickyBox.attached && stickyBox.hasSize) {
      final stickyTopY = stickyBox.localToGlobal(Offset.zero).dy;
      final myTopY = localToGlobal(Offset.zero).dy;
      if (myTopY <= stickyTopY + 0.5) {
        return false;
      }
    }
    return super.hitTest(result, position: position);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    final stickyBox =
        _stickySlotKey.currentContext?.findRenderObject() as RenderBox?;
    if (stickyBox != null && stickyBox.attached && stickyBox.hasSize) {
      final stickyTopY = stickyBox.localToGlobal(Offset.zero).dy;
      final myTopY = localToGlobal(Offset.zero).dy;
      if (myTopY <= stickyTopY + 0.5) {
        final stickyDay = _stickyStateListenable.value.day;
        if (stickyDay != null && !_day.isAfter(stickyDay)) {
          // Плашка уже примагничена к верху чата (или вытеснена более новой датой)
          return;
        }
        // Переходный кадр в момент пересечения границы: фиксируем ровно на stickyTopY
        context.paintChild(child!, offset + Offset(0, stickyTopY - myTopY));
        return;
      }
    }
    context.paintChild(child!, offset);
  }
}

/// Верхняя закреплённая (sticky) плашка с датой в чате.
/// Отображается только тогда, когда инлайновая плашка соответствующего дня
/// достигла верха чата или ушла выше него. Плавный сдвиг (push) следующей
/// плашкой выполняется напрямую на этапе отрисовки (paint) без пересоздания виджетов.
class FloatingChatDateHeader extends StatelessWidget {
  final StickyDateState state;
  final Listenable scrollListenable;
  final bool hiddenBySelectionMode;
  final ValueChanged<DateTime>? onTapDay;

  const FloatingChatDateHeader({
    Key? key,
    required this.state,
    required this.scrollListenable,
    this.hiddenBySelectionMode = false,
    this.onTapDay,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final day = state.day;
    return _StickyChatDateRenderWidget(
      state: state,
      scrollListenable: scrollListenable,
      hiddenBySelectionMode: hiddenBySelectionMode,
      child: DateSeparator(
        dateLabel: state.label,
        onTap: (day != null && onTapDay != null) ? () => onTapDay!(day) : null,
      ),
    );
  }
}

class _StickyChatDateRenderWidget extends SingleChildRenderObjectWidget {
  final StickyDateState state;
  final Listenable scrollListenable;
  final bool hiddenBySelectionMode;

  const _StickyChatDateRenderWidget({
    Key? key,
    required this.state,
    required this.scrollListenable,
    required this.hiddenBySelectionMode,
    required Widget child,
  }) : super(key: key, child: child);

  @override
  RenderObject createRenderObject(BuildContext context) {
    return _RenderStickyChatDateHeader(
      state: state,
      scrollListenable: scrollListenable,
      hiddenBySelectionMode: hiddenBySelectionMode,
    );
  }

  @override
  void updateRenderObject(
    BuildContext context,
    covariant _RenderStickyChatDateHeader renderObject,
  ) {
    renderObject
      ..state = state
      ..scrollListenable = scrollListenable
      ..hiddenBySelectionMode = hiddenBySelectionMode;
  }
}

class _RenderStickyChatDateHeader extends RenderProxyBox {
  StickyDateState _state;
  Listenable _scrollListenable;
  bool _hiddenBySelectionMode;

  _RenderStickyChatDateHeader({
    required StickyDateState state,
    required Listenable scrollListenable,
    required bool hiddenBySelectionMode,
  })  : _state = state,
        _scrollListenable = scrollListenable,
        _hiddenBySelectionMode = hiddenBySelectionMode;

  set state(StickyDateState value) {
    if (_state == value) return;
    _state = value;
    markNeedsPaint();
  }

  set scrollListenable(Listenable value) {
    if (identical(_scrollListenable, value)) return;
    if (attached) {
      _scrollListenable.removeListener(markNeedsPaint);
      value.addListener(markNeedsPaint);
    }
    _scrollListenable = value;
  }

  set hiddenBySelectionMode(bool value) {
    if (_hiddenBySelectionMode == value) return;
    _hiddenBySelectionMode = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _scrollListenable.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _scrollListenable.removeListener(markNeedsPaint);
    super.detach();
  }

  double? _computePushOffset() {
    if (_hiddenBySelectionMode || _state.day == null || _state.label.isEmpty) {
      return null;
    }
    if (!hasSize || size.height <= 0) return null;

    final stickyTopY = localToGlobal(Offset.zero).dy;

    // Если инлайновая плашка этого же дня находится в пределах экрана ниже stickyTopY,
    // она рисует себя сама в потоке сообщений — верхнюю плашку рисовать не нужно.
    final sameDayBox =
        _state.sameDaySepKey?.currentContext?.findRenderObject() as RenderBox?;
    if (sameDayBox != null && sameDayBox.attached && sameDayBox.hasSize) {
      final sameDayTopY = sameDayBox.localToGlobal(Offset.zero).dy;
      if (sameDayTopY > stickyTopY + 0.5) {
        return null;
      }
    }

    // Если снизу подходит инлайновая плашка следующего (более нового) дня,
    // плавно сдвигаем текущую верхнюю плашку вверх.
    final nextDayBox =
        _state.nextDaySepKey?.currentContext?.findRenderObject() as RenderBox?;
    if (nextDayBox != null && nextDayBox.attached && nextDayBox.hasSize) {
      final nextTopY = nextDayBox.localToGlobal(Offset.zero).dy;
      final h = size.height;
      if (nextTopY <= stickyTopY + 0.5) {
        return null;
      }
      if (nextTopY < stickyTopY + h) {
        return (nextTopY - (stickyTopY + h)).clamp(-h, 0.0);
      }
    }

    return 0.0;
  }

  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    if (child == null) return false;
    final pushOffset = _computePushOffset();
    if (pushOffset == null) return false;
    final shiftedPosition = position - Offset(0, pushOffset);
    if (!size.contains(shiftedPosition)) return false;
    return result.addWithPaintOffset(
      offset: Offset(0, pushOffset),
      position: position,
      hitTest: (BoxHitTestResult result, Offset transformed) {
        return child!.hitTest(result, position: transformed);
      },
    );
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    if (child == null) return;
    final pushOffset = _computePushOffset();
    if (pushOffset == null) return;
    if (pushOffset < -0.1) {
      context.pushClipRect(
        needsCompositing,
        offset,
        Offset.zero & size,
        (PaintingContext ctx, Offset ofs) {
          ctx.paintChild(child!, ofs + Offset(0, pushOffset));
        },
      );
    } else {
      context.paintChild(child!, offset);
    }
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
