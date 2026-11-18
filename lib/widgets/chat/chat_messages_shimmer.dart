import 'package:flutter/material.dart';
import '../../models/theav_theme.dart';
import '../tiling/tile_viewport_scope.dart';

/// Telegram-style shimmer skeleton for chat messages when loading a chat
/// that has no local cached messages yet.
class ChatMessagesShimmerSkeleton extends StatefulWidget {
  final double topPadding;
  final double bottomPadding;
  final bool isChannel;

  const ChatMessagesShimmerSkeleton({
    super.key,
    this.topPadding = 90.0,
    this.bottomPadding = 76.0,
    this.isChannel = false,
  });

  @override
  State<ChatMessagesShimmerSkeleton> createState() =>
      _ChatMessagesShimmerSkeletonState();
}

class _ChatMessagesShimmerSkeletonState
    extends State<ChatMessagesShimmerSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmerController;

  static const List<_SkeletonBubbleSpec> _chatSpecs = [
    _SkeletonBubbleSpec(isMe: true, widthFactor: 0.48, height: 42, lines: 1),
    _SkeletonBubbleSpec(isMe: false, widthFactor: 0.68, height: 64, lines: 2),
    _SkeletonBubbleSpec(isMe: false, widthFactor: 0.42, height: 42, lines: 1),
    _SkeletonBubbleSpec(isMe: true, widthFactor: 0.72, height: 82, lines: 3),
    _SkeletonBubbleSpec(isMe: false, widthFactor: 0.56, height: 58, lines: 2),
    _SkeletonBubbleSpec(isMe: true, widthFactor: 0.38, height: 42, lines: 1),
    _SkeletonBubbleSpec(isMe: false, widthFactor: 0.64, height: 64, lines: 2),
    _SkeletonBubbleSpec(isMe: true, widthFactor: 0.54, height: 58, lines: 2),
  ];

  static const List<_ChannelSkeletonSpec> _channelCardSpecs = [
    _ChannelSkeletonSpec(
      mediaHeight: 168,
      lines: 2,
      hasCommentsBar: true,
    ),
    _ChannelSkeletonSpec(
      mediaHeight: 0,
      lines: 3,
      hasCommentsBar: false,
    ),
    _ChannelSkeletonSpec(
      mediaHeight: 146,
      lines: 2,
      hasCommentsBar: false,
    ),
    _ChannelSkeletonSpec(
      mediaHeight: 0,
      lines: 2,
      hasCommentsBar: false,
    ),
  ];

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      if (_shimmerController.isAnimating) {
        _shimmerController.stop();
      }
      _shimmerController.value = 0.35;
    } else if (!_shimmerController.isAnimating) {
      _shimmerController.repeat();
    }
  }

  @override
  void dispose() {
    _shimmerController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final palette = theme.extension<TheavThemeExtension>()?.palette;

    final incomingBase = palette?.chatBubbleIncoming ??
        (isDark
            ? const Color(0xFF1F242B).withValues(alpha: 0.72)
            : Colors.white.withValues(alpha: 0.78));
    final outgoingBase = (palette?.chatBubbleOutgoing ??
            theme.colorScheme.primary)
        .withValues(alpha: isDark ? 0.32 : 0.24);

    if (widget.isChannel) {
      final cardWidth = (TileViewportScope.widthOf(context) - 56).clamp(
        260.0,
        520.0,
      );

      return IgnorePointer(
        child: AnimatedBuilder(
          animation: _shimmerController,
          builder: (context, _) {
            final shimmerValue = _shimmerController.value;
            return ListView.builder(
              reverse: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.only(
                top: widget.topPadding,
                bottom: widget.bottomPadding,
                left: 12,
                right: 12,
              ),
              itemCount: _channelCardSpecs.length,
              itemBuilder: (context, index) {
                final spec =
                    _channelCardSpecs[index % _channelCardSpecs.length];
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 5.0),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: SizedBox(
                      width: cardWidth,
                      child: _ShimmerChannelPostCard(
                        spec: spec,
                        isDark: isDark,
                        baseColor: incomingBase,
                        shimmerProgress: shimmerValue,
                      ),
                    ),
                  ),
                );
              },
            );
          },
        ),
      );
    }

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _shimmerController,
        builder: (context, _) {
          final shimmerValue = _shimmerController.value;
          return ListView.builder(
            reverse: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: EdgeInsets.only(
              top: widget.topPadding,
              bottom: widget.bottomPadding,
              left: 12,
              right: 12,
            ),
            itemCount: _chatSpecs.length,
            itemBuilder: (context, index) {
              final spec = _chatSpecs[index % _chatSpecs.length];
              return Padding(
                padding: const EdgeInsets.symmetric(vertical: 4.0),
                child: Align(
                  alignment: spec.isMe
                      ? Alignment.centerRight
                      : Alignment.centerLeft,
                  child: FractionallySizedBox(
                    widthFactor: spec.widthFactor,
                    child: _ShimmerBubbleBox(
                      height: spec.height,
                      lines: spec.lines,
                      isMe: spec.isMe,
                      isDark: isDark,
                      baseColor: spec.isMe ? outgoingBase : incomingBase,
                      shimmerProgress: shimmerValue,
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// Compact Telegram-style shimmer skeleton shown at the top of the reversed
/// message list when loading older messages (`isLoadingMore == true`).
class ChatHistoryLoadMoreShimmer extends StatefulWidget {
  const ChatHistoryLoadMoreShimmer({super.key});

  @override
  State<ChatHistoryLoadMoreShimmer> createState() =>
      _ChatHistoryLoadMoreShimmerState();
}

class _ChatHistoryLoadMoreShimmerState extends State<ChatHistoryLoadMoreShimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      if (_controller.isAnimating) {
        _controller.stop();
      }
      _controller.value = 0.35;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
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
    final palette = theme.extension<TheavThemeExtension>()?.palette;
    final incomingBase = palette?.chatBubbleIncoming ??
        (isDark
            ? const Color(0xFF1F242B).withValues(alpha: 0.65)
            : Colors.white.withValues(alpha: 0.72));
    final outgoingBase = (palette?.chatBubbleOutgoing ??
            theme.colorScheme.primary)
        .withValues(alpha: isDark ? 0.28 : 0.20);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final p = _controller.value;
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                  widthFactor: 0.52,
                  child: _ShimmerBubbleBox(
                    height: 44,
                    lines: 1,
                    isMe: false,
                    isDark: isDark,
                    baseColor: incomingBase,
                    shimmerProgress: p,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: FractionallySizedBox(
                  widthFactor: 0.42,
                  child: _ShimmerBubbleBox(
                    height: 40,
                    lines: 1,
                    isMe: true,
                    isDark: isDark,
                    baseColor: outgoingBase,
                    shimmerProgress: p,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SkeletonBubbleSpec {
  final bool isMe;
  final double widthFactor;
  final double height;
  final int lines;

  const _SkeletonBubbleSpec({
    required this.isMe,
    required this.widthFactor,
    required this.height,
    required this.lines,
  });
}

class _ChannelSkeletonSpec {
  final double mediaHeight;
  final int lines;
  final bool hasCommentsBar;

  const _ChannelSkeletonSpec({
    required this.mediaHeight,
    required this.lines,
    required this.hasCommentsBar,
  });
}

class _ShimmerChannelPostCard extends StatelessWidget {
  final _ChannelSkeletonSpec spec;
  final bool isDark;
  final Color baseColor;
  final double shimmerProgress;

  const _ShimmerChannelPostCard({
    required this.spec,
    required this.isDark,
    required this.baseColor,
    required this.shimmerProgress,
  });

  @override
  Widget build(BuildContext context) {
    final highlightColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.55);
    final lineBaseColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.07);
    final mediaBaseColor = isDark
        ? Colors.white.withValues(alpha: 0.13)
        : Colors.black.withValues(alpha: 0.09);
    final dividerColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.08);
    final sweepOffset = (shimmerProgress * 2.4) - 1.2;

    return Container(
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (spec.mediaHeight > 0)
                Container(
                  width: double.infinity,
                  height: spec.mediaHeight,
                  color: mediaBaseColor,
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (int i = 0; i < spec.lines; i++) ...[
                      if (i > 0) const SizedBox(height: 8),
                      FractionallySizedBox(
                        widthFactor: i == spec.lines - 1 && spec.lines > 1
                            ? 0.64
                            : (i == 0 ? 0.94 : 0.85),
                        child: Container(
                          height: 11,
                          decoration: BoxDecoration(
                            color: lineBaseColor,
                            borderRadius: BorderRadius.circular(5.5),
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        Container(
                          width: 44,
                          height: 10,
                          decoration: BoxDecoration(
                            color: lineBaseColor,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 34,
                          height: 10,
                          decoration: BoxDecoration(
                            color: lineBaseColor,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              if (spec.hasCommentsBar) ...[
                Divider(height: 0.5, thickness: 0.5, color: dividerColor),
                SizedBox(
                  height: 42,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 34,
                          height: 18,
                          child: Stack(
                            children: [
                              Positioned(
                                left: 0,
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: mediaBaseColor,
                                  ),
                                ),
                              ),
                              Positioned(
                                left: 12,
                                child: Container(
                                  width: 18,
                                  height: 18,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: lineBaseColor,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          width: 118,
                          height: 10,
                          decoration: BoxDecoration(
                            color: lineBaseColor,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                        const Spacer(),
                        Container(
                          width: 14,
                          height: 14,
                          decoration: BoxDecoration(
                            color: lineBaseColor,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ],
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(sweepOffset - 0.6, -0.3),
                  end: Alignment(sweepOffset + 0.6, 0.3),
                  colors: [
                    Colors.transparent,
                    highlightColor,
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ShimmerBubbleBox extends StatelessWidget {
  final double height;
  final int lines;
  final bool isMe;
  final bool isDark;
  final Color baseColor;
  final double shimmerProgress;

  const _ShimmerBubbleBox({
    required this.height,
    required this.lines,
    required this.isMe,
    required this.isDark,
    required this.baseColor,
    required this.shimmerProgress,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.only(
      topLeft: const Radius.circular(18),
      topRight: const Radius.circular(18),
      bottomLeft: Radius.circular(isMe ? 18 : 5),
      bottomRight: Radius.circular(isMe ? 5 : 18),
    );

    final highlightColor = isDark
        ? Colors.white.withValues(alpha: 0.12)
        : Colors.white.withValues(alpha: 0.55);
    final lineBaseColor = isDark
        ? Colors.white.withValues(alpha: 0.10)
        : Colors.black.withValues(alpha: 0.07);

    final sweepOffset = (shimmerProgress * 2.4) - 1.2;

    return Container(
      height: height,
      decoration: BoxDecoration(
        color: baseColor,
        borderRadius: borderRadius,
      ),
      clipBehavior: Clip.antiAlias,
      child: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                for (int i = 0; i < lines; i++)
                  FractionallySizedBox(
                    widthFactor: i == lines - 1 && lines > 1
                        ? 0.62
                        : (i == 0 ? 0.92 : 0.84),
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: lineBaseColor,
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment(sweepOffset - 0.6, -0.3),
                  end: Alignment(sweepOffset + 0.6, 0.3),
                  colors: [
                    Colors.transparent,
                    highlightColor,
                    Colors.transparent,
                  ],
                  stops: const [0.0, 0.5, 1.0],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Telegram-style entrance animation for newly arriving or newly sent messages
/// in the chat list (smooth slide up + subtle scale + fade).
class TelegramMessageEntrance extends StatefulWidget {
  final Widget child;
  final bool animate;
  final bool isMe;
  final Duration duration;

  const TelegramMessageEntrance({
    super.key,
    required this.child,
    this.animate = true,
    this.isMe = true,
    this.duration = const Duration(milliseconds: 220),
  });

  @override
  State<TelegramMessageEntrance> createState() =>
      _TelegramMessageEntranceState();
}

class _TelegramMessageEntranceState extends State<TelegramMessageEntrance>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;
  late final Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: widget.animate ? 0.0 : 1.0,
    );
    final curved = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(curved);
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0.0, 0.18),
      end: Offset.zero,
    ).animate(curved);
    _scaleAnimation = Tween<double>(begin: 0.96, end: 1.0).animate(curved);

    if (widget.animate) {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.animate && _controller.value == 1.0) {
      return widget.child;
    }
    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: ScaleTransition(
          scale: _scaleAnimation,
          alignment:
              widget.isMe ? Alignment.bottomRight : Alignment.bottomLeft,
          child: widget.child,
        ),
      ),
    );
  }
}
