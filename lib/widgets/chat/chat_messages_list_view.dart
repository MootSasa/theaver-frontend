import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'chat_messages_shimmer.dart';

/// Unified message list view for chat screens supporting reverse scrolling,
/// top shader mask for floating glass app bar, empty state, and Telegram-style loading shimmer.
class ChatMessagesListView extends StatelessWidget {
  final bool isLoading;
  final int itemCount;
  final IndexedWidgetBuilder itemBuilder;
  final ScrollController? scrollController;
  final double topPadding;
  final double bottomPadding;
  final Widget? emptyIcon;
  final String? emptyTitle;
  final String? emptySubtitle;
  final Widget? typingIndicator;
  final bool reverse;
  final bool enableTopShaderMask;
  final bool isLoadingMore;
  final bool isChannel;

  const ChatMessagesListView({
    Key? key,
    required this.isLoading,
    required this.itemCount,
    required this.itemBuilder,
    this.scrollController,
    this.topPadding = 90.0,
    this.bottomPadding = 16.0,
    this.emptyIcon,
    this.emptyTitle,
    this.emptySubtitle,
    this.typingIndicator,
    this.reverse = true,
    this.enableTopShaderMask = true,
    this.isLoadingMore = false,
    this.isChannel = false,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (isLoading && itemCount == 0) {
      content = ChatMessagesShimmerSkeleton(
        key: const ValueKey('chat_shimmer_loading'),
        topPadding: topPadding,
        bottomPadding: bottomPadding,
        isChannel: isChannel,
      );
    } else if (itemCount == 0) {
      content = Center(
        key: const ValueKey('chat_empty_state'),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            emptyIcon ??
                iconoir.ChatBubbleEmpty(
                  width: 64,
                  height: 64,
                  color: Colors.grey[400],
                ),
            const SizedBox(height: 16),
            Text(
              emptyTitle ?? 'No messages yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: Colors.grey[600],
              ),
            ),
            if (emptySubtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                emptySubtitle!,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ],
        ),
      );
    } else {
      final totalCount = itemCount + (isLoadingMore ? 1 : 0);

      content = ListView.builder(
        key: const ValueKey('chat_messages_list'),
        controller: scrollController,
        reverse: reverse,
        cacheExtent: 500.0,
        addRepaintBoundaries: false,
        padding: EdgeInsets.only(
          top: topPadding,
          left: 8,
          right: 8,
          bottom: bottomPadding,
        ),
        itemCount: totalCount,
        itemBuilder: (context, index) {
          if (isLoadingMore && index == itemCount) {
            return const ChatHistoryLoadMoreShimmer();
          }
          return itemBuilder(context, index);
        },
      );
    }

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 220),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: content,
    );
  }
}
