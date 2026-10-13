import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;

/// Unified message list view for chat screens supporting reverse scrolling,
/// top shader mask for floating glass app bar, empty state, and loading spinner.
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
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (itemCount == 0) {
      return Center(
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
    }

    final totalCount = itemCount + (isLoadingMore ? 1 : 0);

    final listView = ListView.builder(
      controller: scrollController,
      reverse: reverse,
      cacheExtent: 600.0,
      padding: EdgeInsets.only(
        top: topPadding,
        left: 8,
        right: 8,
        bottom: bottomPadding,
      ),
      itemCount: totalCount,
      itemBuilder: (context, index) {
        if (isLoadingMore && index == itemCount) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12.0),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }
        return itemBuilder(context, index);
      },
    );

    final content = typingIndicator != null
        ? Column(
            children: [
              typingIndicator!,
              Expanded(child: listView),
            ],
          )
        : listView;

    return content;
  }
}
