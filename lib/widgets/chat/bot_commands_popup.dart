import 'dart:math' as math;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:liquid_glass_easy/liquid_glass_easy.dart';
import 'package:provider/provider.dart';
import '../../models/theav_theme.dart';
import '../../services/bot_service.dart';
import '../../services/liquid_glass_provider.dart';
import '../../utils/blur_utils.dart';

/// Floating Liquid Glass popup menu rendered above `ChatInputBar` when the user
/// taps the `/` bot commands button or types `/` at the start of the input.
///
/// Features Telegram-style scroll-driven physics without a header:
/// - Scrolling down (finger moves up) expands the top edge upward up to 65% of screen height,
///   then scrolls the inner list of commands.
/// - Scrolling up (finger moves down) scrolls the list back to top, and once at offset 0,
///   moves the top edge of the panel downward until it closes completely.
/// - Strictly adheres to Liquid Glass rules: NO FadeTransition/Opacity on the
///   `LiquidGlassLens` shape itself (animated purely via geometry/height), with
///   fade applied only to the inner command rows when collapsing near 0px.
class BotCommandsPopup extends StatefulWidget {
  final List<BotCommand> commands;
  final String filterQuery;
  final ValueChanged<BotCommand> onSelectCommand;
  final VoidCallback? onClose;
  final bool isOpen;

  const BotCommandsPopup({
    super.key,
    required this.commands,
    this.filterQuery = '',
    required this.onSelectCommand,
    this.onClose,
    this.isOpen = true,
  });

  @override
  State<BotCommandsPopup> createState() => _BotCommandsPopupState();
}

class _BotCommandsPopupState extends State<BotCommandsPopup>
    with SingleTickerProviderStateMixin {
  static const double _kItemHeight = 44.0;
  static const double _kDividerHeight = 1.0;
  static const double _kVerticalPadding = 8.0;
  static const double _kInitialMaxHeight = 220.0;
  static const double _kCornerRadius = 20.0;

  late final ScrollController _scrollController;
  late final AnimationController _heightAnimController;
  Animation<double>? _heightAnimation;

  double _currentHeight = 0.0;
  bool _isClosing = false;
  TimerOrWheelSettle? _wheelSettle;

  List<BotCommand> get _filteredCommands {
    final q = widget.filterQuery.trim().toLowerCase();
    if (q.isEmpty || q == '/') return widget.commands;
    final clean = q.startsWith('/') ? q.substring(1) : q;
    return widget.commands.where((cmd) {
      final c = cmd.command.toLowerCase();
      final d = cmd.description.toLowerCase();
      return c.contains(clean) || d.contains(clean);
    }).toList();
  }

  double _computeContentHeight(int count) {
    if (count <= 0) return 0.0;
    return count * _kItemHeight +
        math.max(0, count - 1) * _kDividerHeight +
        _kVerticalPadding;
  }

  double _computeInitialHeight(int count) {
    final contentH = _computeContentHeight(count);
    return math.min(contentH, _kInitialMaxHeight);
  }

  double _computeMaxExpandedHeight(BuildContext context, int count) {
    final contentH = _computeContentHeight(count);
    final screenH = MediaQuery.sizeOf(context).height;
    final maxAllowed = math.max(_kInitialMaxHeight, screenH * 0.65);
    return math.min(contentH, maxAllowed);
  }

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    _heightAnimController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 240),
    )..addListener(() {
        if (_heightAnimation != null && mounted) {
          setState(() {
            _currentHeight = _heightAnimation!.value;
          });
        }
      });

    if (widget.isOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final count = _filteredCommands.length;
        if (count > 0) {
          _animateHeightTo(_computeInitialHeight(count));
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant BotCommandsPopup oldWidget) {
    super.didUpdateWidget(oldWidget);
    final filtered = _filteredCommands;

    if (widget.isOpen != oldWidget.isOpen) {
      if (widget.isOpen && filtered.isNotEmpty) {
        _isClosing = false;
        _animateHeightTo(_computeInitialHeight(filtered.length));
      } else if (!widget.isOpen) {
        _animateHeightTo(0.0);
      }
      return;
    }

    if (widget.filterQuery != oldWidget.filterQuery ||
        widget.commands.length != oldWidget.commands.length) {
      if (widget.isOpen && !_isClosing) {
        if (filtered.isEmpty) {
          _animateHeightTo(0.0);
        } else {
          final targetInit = _computeInitialHeight(filtered.length);
          final maxExp = _computeMaxExpandedHeight(context, filtered.length);
          final clamped = _currentHeight <= 1.0
              ? targetInit
              : _currentHeight.clamp(targetInit, maxExp);
          _animateHeightTo(clamped);
        }
      }
    }
  }

  void _animateHeightTo(
    double target, {
    Duration duration = const Duration(milliseconds: 240),
    Curve curve = Curves.easeOutCubic,
    VoidCallback? onCompleted,
  }) {
    _heightAnimController.stop();
    _heightAnimController.duration = duration;
    _heightAnimation = Tween<double>(
      begin: _currentHeight,
      end: target,
    ).animate(CurvedAnimation(
      parent: _heightAnimController,
      curve: curve,
    ));
    _heightAnimController.forward(from: 0.0).whenComplete(() {
      if (onCompleted != null && mounted) {
        onCompleted();
      }
    });
  }

  void _triggerClose() {
    if (_isClosing) return;
    _isClosing = true;
    _animateHeightTo(
      0.0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOutCubic,
      onCompleted: () {
        _isClosing = false;
        widget.onClose?.call();
      },
    );
  }

  /// Applies scroll delta (positive `scrollDelta` = scrolling down the list / moving finger up;
  /// negative `scrollDelta` = scrolling up the list / moving finger down to pull top edge down).
  void _applyScrollDelta(double scrollDelta, BuildContext context, int count) {
    if (_isClosing || count == 0) return;
    _heightAnimController.stop();

    final maxExpanded = _computeMaxExpandedHeight(context, count);
    final currentOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;
    final maxScroll = _scrollController.hasClients
        ? _scrollController.position.maxScrollExtent
        : 0.0;

    if (scrollDelta > 0) {
      // Scrolling DOWN the list:
      // 1. First move the top edge of the panel UP until maxExpanded
      double remaining = scrollDelta;
      if (_currentHeight < maxExpanded) {
        final grow = math.min(remaining, maxExpanded - _currentHeight);
        setState(() {
          _currentHeight += grow;
        });
        remaining -= grow;
      }
      // 2. Then scroll the inner list downward
      if (remaining > 0 && _scrollController.hasClients && maxScroll > 0) {
        final nextOffset = (currentOffset + remaining).clamp(0.0, maxScroll);
        _scrollController.jumpTo(nextOffset);
      }
    } else if (scrollDelta < 0) {
      // Scrolling UP the list (moving finger down):
      double pullDown = -scrollDelta;
      // 1. First scroll the inner list back to 0
      if (_scrollController.hasClients && currentOffset > 0) {
        final scrollconsume = math.min(pullDown, currentOffset);
        _scrollController.jumpTo(currentOffset - scrollconsume);
        pullDown -= scrollconsume;
      }
      // 2. Once at the top of the list (offset == 0), move the top edge of the panel DOWN
      if (pullDown > 0) {
        final nextHeight = math.max(0.0, _currentHeight - pullDown);
        setState(() {
          _currentHeight = nextHeight;
        });
        if (nextHeight <= 6.0) {
          _triggerClose();
        }
      }
    }
  }

  void _handleDragEnd(DragEndDetails details, BuildContext context, int count) {
    if (_isClosing || count == 0) return;
    final vy = details.primaryVelocity ?? 0.0; // positive = finger moving down
    final initialH = _computeInitialHeight(count);
    final maxExpanded = _computeMaxExpandedHeight(context, count);
    final currentOffset =
        _scrollController.hasClients ? _scrollController.offset : 0.0;

    // If at the top of the list and dragged down past threshold or flung downward -> close
    if (currentOffset <= 0.5) {
      if (_currentHeight < initialH * 0.55 ||
          (vy > 480.0 && _currentHeight <= initialH + 24.0)) {
        _triggerClose();
        return;
      }
    }

    // If flung upward -> expand to maxExpanded
    if (vy < -380.0 && _currentHeight < maxExpanded) {
      _animateHeightTo(maxExpanded);
      return;
    }

    // If flung downward while expanded -> collapse to initialH (or close if already near initialH)
    if (vy > 480.0 && currentOffset <= 0.5 && _currentHeight > initialH) {
      _animateHeightTo(initialH);
      return;
    }

    // Settle to nearest snap point if below initialH
    if (_currentHeight < initialH) {
      _animateHeightTo(initialH);
    } else if (_currentHeight > initialH && _currentHeight < maxExpanded) {
      final mid = (initialH + maxExpanded) * 0.5;
      _animateHeightTo(_currentHeight >= mid ? maxExpanded : initialH);
    }
  }

  void _handlePointerSignal(
    PointerSignalEvent event,
    BuildContext context,
    int count,
  ) {
    if (event is PointerScrollEvent) {
      // event.scrollDelta.dy > 0 means wheel scrolled down (list moves down)
      // event.scrollDelta.dy < 0 means wheel scrolled up (list moves up / top edge goes down)
      _applyScrollDelta(event.scrollDelta.dy, context, count);
      _wheelSettle?.cancel();
      if (_currentHeight > 0 &&
          _currentHeight < _computeInitialHeight(count) * 0.35) {
        _triggerClose();
      }
    }
  }

  @override
  void dispose() {
    _wheelSettle?.cancel();
    _heightAnimController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredCommands;
    if (filtered.isEmpty || (_currentHeight <= 0.5 && !widget.isOpen)) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final ext = theme.extension<TheavThemeExtension>();
    final colorScheme = theme.colorScheme;
    final glassProvider = context.watch<LiquidGlassProvider?>();
    final glassEnabled = glassProvider?.enabled ?? false;
    final isLite = glassProvider?.isLite ?? false;

    final double visibleHeight = math.max(0.0, _currentHeight);
    if (visibleHeight <= 0.5) {
      return const SizedBox.shrink();
    }

    // Inner content opacity: fade ONLY the inner list items when the panel is nearly closed (< 48px),
    // NEVER fade the LiquidGlassLens itself.
    final double innerContentOpacity = (visibleHeight / 48.0).clamp(0.0, 1.0);

    final Widget commandList = Opacity(
      opacity: innerContentOpacity,
      child: NotificationListener<ScrollNotification>(
        onNotification: (_) => true,
        child: ListView.separated(
          controller: _scrollController,
          physics: const NeverScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(vertical: 4),
          itemCount: filtered.length,
          separatorBuilder: (context, index) => Divider(
            height: _kDividerHeight,
            indent: 14,
            endIndent: 14,
            color: colorScheme.outlineVariant.withValues(alpha: 0.15),
          ),
          itemBuilder: (context, index) {
            final cmd = filtered[index];
            return SizedBox(
              height: _kItemHeight,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: () => widget.onSelectCommand(cmd),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        Text(
                          cmd.normalizedCommand,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.w700,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            cmd.description,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );

    Widget panelBody;
    if (glassEnabled && glassProvider != null) {
      final style = glassProvider.createStyle(
        context: context,
        cornerRadius: _kCornerRadius,
        refractionIndex: 1.1,
        refractionWidth: 24,
        isLiteOverride: isLite,
      );
      panelBody = LiquidGlassLens(
        style: style,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(_kCornerRadius),
          child: commandList,
        ),
      );
    } else {
      panelBody = ClipRRect(
        borderRadius: BorderRadius.circular(_kCornerRadius),
        child: BackdropFilter.grouped(
          filter: BlurUtils.createDownsampledBlur(15),
          child: Container(
            decoration: BoxDecoration(
              color: ext?.glassSurfaceColor ??
                  (isDark
                      ? Colors.black.withValues(alpha: 0.68)
                      : Colors.white.withValues(alpha: 0.78)),
              borderRadius: BorderRadius.circular(_kCornerRadius),
              border: Border.all(
                color: ext?.glassBorderColor ??
                    (isDark ? Colors.white10 : Colors.black12),
                width: 0.6,
              ),
            ),
            child: commandList,
          ),
        ),
      );
    }

    return Listener(
      onPointerSignal: (event) =>
          _handlePointerSignal(event, context, filtered.length),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onVerticalDragUpdate: (details) {
          final dy = details.primaryDelta ?? 0.0;
          // Dragging finger UP (dy < 0) = scrolling down the list (+delta)
          // Dragging finger DOWN (dy > 0) = scrolling up the list (-delta)
          _applyScrollDelta(-dy, context, filtered.length);
        },
        onVerticalDragEnd: (details) =>
            _handleDragEnd(details, context, filtered.length),
        child: Container(
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          height: visibleHeight,
          width: double.infinity,
          child: panelBody,
        ),
      ),
    );
  }
}

class TimerOrWheelSettle {
  void cancel() {}
}
