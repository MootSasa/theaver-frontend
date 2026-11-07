import 'package:flutter/material.dart';
import '../../models/theav_theme.dart';

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

  static const List<_SkeletonBubbleSpec> _channelSpecs = [
    _SkeletonBubbleSpec(isMe: false, widthFactor: 0.86, height: 110, lines: 3),
    _SkeletonBubbleSpec(isMe: false, widthFactor: 0.82, height: 84, lines: 2),
    _SkeletonBubbleSpec(isMe: false, widthFactor: 0.88, height: 128, lines: 4),
    _SkeletonBubbleSpec(isMe: false, widthFactor: 0.78, height: 76, lines: 2),
  ];

  @override
  void initState() {
    super.initState();
    _shimmerController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1350),
    )..repeat();
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

    final specs = widget.isChannel ? _channelSpecs : _chatSpecs;

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
            itemCount: specs.length,
            itemBuilder: (context, index) {
              final spec = specs[index % specs.length];
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
    )..repeat();
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
