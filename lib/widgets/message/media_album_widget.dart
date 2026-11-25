import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../config/app_config.dart';
import '../../models/media_album.dart';
import '../../models/theav_theme.dart';
import '../../services/contacts_service.dart';
import '../../services/database/app_database.dart';
import '../../services/media_cache_manager.dart';
import 'blurred_media_placeholder.dart';
import 'bubble_tail_painter.dart';
import 'group_message_avatar_row.dart' show GroupMessageAvatarRow;
import 'media_album_layout.dart';
import 'media_album_viewer.dart';
import 'media_download_button.dart';
import 'media_spoiler_overlay.dart';
import 'message_bubble.dart';
import 'message_interactive_state.dart';
import 'message_status_widget.dart';
import 'text_message_widget.dart';
import '../chat/reactions_panel.dart';
import '../tiling/tile_viewport_scope.dart';

/// Widget rendering a Telegram-style collage bubble for 2–10 media items.
class MediaAlbumWidget extends StatelessWidget {
  final MediaAlbum album;
  final bool isMe;
  final String currentUserId;
  final String? chatType;
  final String? senderName;
  final Widget? senderHeaderWidget;
  final Widget? headerWidget;
  final Widget? replyOrForwardWidget;
  final Map<String, int>? reactions;
  final Set<String>? myReactions;
  final ValueChanged<String>? onReactionTap;
  final bool hasAvatarGutter;
  final String Function(String)? formatTime;
  final Function(String url, String name, String type)? onFileTap;
  final bool isHighlighted;
  final bool isSelected;
  final bool isSelectionMode;
  final String? highlightItemId;
  final bool isFirstInCluster;
  final bool isLastInCluster;
  final bool isChannelCard;
  final bool suppressMargin;
  final bool suppressFooter;
  final double? overrideWidth;
  final BorderRadius? overrideBorderRadius;
  final bool hasProtectedContent;
  final ValueChanged<String>? onMentionTap;
  final ValueChanged<String>? onCommandTap;
  final ValueChanged<String>? onHashtagTap;

  const MediaAlbumWidget({
    Key? key,
    required this.album,
    required this.isMe,
    required this.currentUserId,
    this.chatType,
    this.senderName,
    this.senderHeaderWidget,
    this.headerWidget,
    this.replyOrForwardWidget,
    this.reactions,
    this.myReactions,
    this.onReactionTap,
    this.hasAvatarGutter = false,
    this.formatTime,
    this.onFileTap,
    this.isHighlighted = false,
    this.isSelected = false,
    this.isSelectionMode = false,
    this.highlightItemId,
    this.isFirstInCluster = true,
    this.isLastInCluster = true,
    this.isChannelCard = false,
    this.suppressMargin = false,
    this.suppressFooter = false,
    this.overrideWidth,
    this.overrideBorderRadius,
    this.hasProtectedContent = false,
    this.onMentionTap,
    this.onCommandTap,
    this.onHashtagTap,
  }) : super(key: key);

  Widget _buildFallbackSenderName(ThemeData theme) {
    final primary = album.primaryMessage;
    final bool canResolveSender = !isMe &&
        !primary.isChannelOrPersonaAuthored &&
        !primary.isMirroredChannelPost &&
        ContactsService.shouldResolveUserIdentity(
          primary.senderId,
          senderChatId: primary.senderChatId,
          isAnonymousAdmin: primary.isFromAnonymousAdmin,
          isMirroredChannelPost: primary.isMirroredChannelPost,
        );
    Widget buildText(String name) => Text(
          name,
          style: TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 13,
            color: theme.colorScheme.primary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        );
    if (!canResolveSender) {
      return buildText(senderName!);
    }
    return ValueListenableBuilder<int>(
      valueListenable: ContactsService.revisionNotifier,
      builder: (_, __, ___) => buildText(
        ContactsService.resolvePeerName(
          primary.senderId,
          senderName!,
          senderChatId: primary.senderChatId,
          isAnonymousAdmin: primary.isFromAnonymousAdmin,
          isMirroredChannelPost: primary.isMirroredChannelPost,
        ),
      ),
    );
  }

  MediaAlbumWidget copyWithKey(Key? newKey) {
    return MediaAlbumWidget(
      key: newKey,
      album: album,
      isMe: isMe,
      currentUserId: currentUserId,
      chatType: chatType,
      senderName: senderName,
      senderHeaderWidget: senderHeaderWidget,
      headerWidget: headerWidget,
      replyOrForwardWidget: replyOrForwardWidget,
      reactions: reactions,
      myReactions: myReactions,
      onReactionTap: onReactionTap,
      hasAvatarGutter: hasAvatarGutter,
      formatTime: formatTime,
      onFileTap: onFileTap,
      isHighlighted: false,
      isSelected: false,
      isSelectionMode: false,
      highlightItemId: null,
      isFirstInCluster: isFirstInCluster,
      isLastInCluster: isLastInCluster,
      isChannelCard: isChannelCard,
      suppressMargin: suppressMargin,
      suppressFooter: suppressFooter,
      overrideWidth: overrideWidth,
      overrideBorderRadius: overrideBorderRadius,
      hasProtectedContent: hasProtectedContent,
      onMentionTap: onMentionTap,
      onCommandTap: onCommandTap,
      onHashtagTap: onHashtagTap,
    );
  }

  void _openViewer(BuildContext context, int index) {
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => MediaAlbumViewer(
          album: album,
          initialIndex: index,
          hasProtectedContent: hasProtectedContent,
        ),
      ),
    );
  }

  AlbumTilePosition _resolveTilePosition({
    required AlbumTilePosition pos,
    required BorderRadius outerRadius,
    required bool applyTopCorners,
    required bool applyBottomCorners,
  }) {
    final BorderRadius base = pos.borderRadius;
    final BorderRadius resolved = BorderRadius.only(
      topLeft: applyTopCorners && base.topLeft != Radius.zero
          ? outerRadius.topLeft
          : base.topLeft,
      topRight: applyTopCorners && base.topRight != Radius.zero
          ? outerRadius.topRight
          : base.topRight,
      bottomLeft: applyBottomCorners && base.bottomLeft != Radius.zero
          ? outerRadius.bottomLeft
          : base.bottomLeft,
      bottomRight: applyBottomCorners && base.bottomRight != Radius.zero
          ? outerRadius.bottomRight
          : base.bottomRight,
    );
    if (resolved == base) return pos;
    return AlbumTilePosition(
      left: pos.left,
      top: pos.top,
      width: pos.width,
      height: pos.height,
      borderRadius: resolved,
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = TileViewportScope.widthOf(context) -
        (hasAvatarGutter ? GroupMessageAvatarRow.gutterWidth : 0.0);
    final double minAlbumWidth =
        math.min(220.0, math.max(180.0, screenWidth - 16.0));
    final double albumWidth = (overrideWidth != null && overrideWidth! > 0)
        ? overrideWidth!
        : (screenWidth * 0.76).clamp(minAlbumWidth, 380.0);
    // Dynamic height based on count
    final albumHeight = album.items.length <= 2
        ? albumWidth * 0.72
        : (album.items.length <= 4 ? albumWidth * 0.88 : albumWidth * 1.05);

    final positions = MediaAlbumLayoutCalculator.computePositions(
      items: album.items,
      totalWidth: albumWidth,
      totalHeight: albumHeight,
      isMe: isMe,
    );

    final theme = Theme.of(context);
    final themeExt = theme.extension<TheavThemeExtension>();
    final bool shouldHighlightAlbum = isSelected ||
        isHighlighted ||
        (highlightItemId != null &&
            album.items.any((it) => it.id == highlightItemId));

    final Widget? resolvedHeaderWidget =
        headerWidget ?? senderHeaderWidget;
    final bool showSender = !isChannelCard &&
        (resolvedHeaderWidget != null ||
            (!isMe && senderName != null && senderName!.isNotEmpty));
    final bool showReplyOrForward =
        !isChannelCard && replyOrForwardWidget != null;
    final bool hasTopBubbleSection = showSender || showReplyOrForward;
    final bool hasTextBubble =
        !isChannelCard && (album.hasCaption || hasTopBubbleSection);
    final Color bubbleColor = hasTextBubble
        ? (shouldHighlightAlbum
            ? (isMe
                ? (themeExt?.palette.chatBubbleOutgoingSelected ??
                    theme.colorScheme.primary)
                : (themeExt?.palette.chatBubbleIncomingSelected ??
                    theme.colorScheme.secondaryContainer))
            : (isMe
                ? (themeExt?.palette.chatBubbleOutgoing ??
                    theme.colorScheme.primary)
                : (themeExt?.palette.chatBubbleIncoming ??
                    theme.colorScheme.secondaryContainer)))
        : Colors.transparent;
    final Color onBubbleColor = isMe
        ? (themeExt?.palette.chatBubbleOutgoingText ?? theme.colorScheme.onPrimary)
        : (themeExt?.palette.chatBubbleIncomingText ??
            theme.colorScheme.onSecondaryContainer);

    final double baseBubbleRadius = themeExt?.bubbleRadius ?? 16.0;
    final bool showTail = !isChannelCard &&
        overrideBorderRadius == null &&
        isLastInCluster &&
        hasTextBubble;
    final BorderRadius effectiveBorderRadius = overrideBorderRadius ??
        (isChannelCard
            ? const BorderRadius.vertical(top: Radius.circular(16.0))
            : computeClusterBubbleBorderRadius(
                isMe: isMe,
                isFirstInCluster: isFirstInCluster,
                isLastInCluster: isLastInCluster,
                outerRadius: baseBubbleRadius,
                innerRadius: 6.0,
                tailCornerRadius: 4.0,
                hasTail: showTail,
              ));

    final bool applyTopTileCorners = isChannelCard || !hasTopBubbleSection;
    final bool applyBottomTileCorners = isChannelCard || !album.hasCaption;

    final Widget albumBox = MetaData(
      metaData: 'message_bubble_box',
      child: Container(
        width: albumWidth,
        decoration: BoxDecoration(
          color: bubbleColor,
          borderRadius: effectiveBorderRadius,
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSender)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  10,
                  6,
                  10,
                  showReplyOrForward ? 2 : 4,
                ),
                child: resolvedHeaderWidget ??
                    _buildFallbackSenderName(theme),
              ),
            if (showReplyOrForward)
              Padding(
                padding: EdgeInsets.fromLTRB(
                  8,
                  showSender ? 2 : 6,
                  8,
                  6,
                ),
                child: replyOrForwardWidget!,
              ),
            // 1. Mosaic Collage Container
            SizedBox(
              width: albumWidth,
              height: albumHeight,
              child: Stack(
                children: [
                  Positioned.fill(
                    child: MediaSpoilerOverlay(
                      messageId: album.primaryMessage.id,
                      hasSpoiler: album.hasMediaSpoiler,
                      borderRadius: 0.0,
                      child: Stack(
                        children: [
                          for (int i = 0; i < positions.length; i++)
                            _buildTile(
                              context,
                              album.items[i],
                              _resolveTilePosition(
                                pos: positions[i],
                                outerRadius: effectiveBorderRadius,
                                applyTopCorners: applyTopTileCorners,
                                applyBottomCorners: applyBottomTileCorners,
                              ),
                              i,
                            ),
                        ],
                      ),
                    ),
                  ),

                  // Floating time pill if captionless
                  if (!isChannelCard && !suppressFooter && !album.hasCaption)
                    Positioned(
                      bottom: 6,
                      right: 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              _getTimeString(),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                            if (isMe) ...[
                              const SizedBox(width: 3),
                              _buildStatusIcon(),
                            ],
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),

            // 2. Caption Text & Meta (if present and not handled externally by ChannelPostCard)
            if (!isChannelCard && album.hasCaption)
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MetaData(
                      metaData: 'message_selectable_content',
                      child: TextMessageWidget(
                        text: album.caption!,
                        entities: album.entities,
                        isMe: isMe,
                        style: TextStyle(
                          color: onBubbleColor,
                          fontSize: 15,
                        ),
                        onMentionTap: onMentionTap,
                        onCommandTap: onCommandTap,
                        onHashtagTap: onHashtagTap,
                      ),
                    ),
                    if (!suppressFooter) ...[
                      const SizedBox(height: 4),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          Text(
                            _getTimeString(),
                            style: TextStyle(
                              color: onBubbleColor.withValues(alpha: 0.7),
                              fontSize: 11,
                            ),
                          ),
                          if (isMe) ...[
                            const SizedBox(width: 4),
                            _buildStatusIcon(color: onBubbleColor),
                          ],
                        ],
                      ),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );

    final EdgeInsets effectiveMargin = suppressMargin
        ? EdgeInsets.zero
        : EdgeInsets.only(
            top: isFirstInCluster ? 4.0 : 2.0,
            bottom: isLastInCluster ? 4.0 : 2.0,
            left: hasAvatarGutter ? 0.0 : 8.0,
            right: 8.0,
          );

    final Widget albumContent = Padding(
      padding: effectiveMargin,
      child: showTail
          ? Stack(
              clipBehavior: Clip.none,
              children: [
                albumBox,
                Positioned(
                  right: isMe ? -BubbleTailPainter.horizontalOutset : null,
                  left: isMe ? null : -BubbleTailPainter.horizontalOutset,
                  bottom: 0.0,
                  child: IgnorePointer(
                    child: CustomPaint(
                      size: BubbleTailPainter.defaultSize,
                      painter: BubbleTailPainter(
                        color: bubbleColor,
                        isMe: isMe,
                        cornerRadius: math.min(baseBubbleRadius, 4.0),
                      ),
                    ),
                  ),
                ),
              ],
            )
          : albumBox,
    );

    final primaryMsg = album.primaryMessage;
    final String interactiveAlbumKey =
        (primaryMsg.localId != null && primaryMsg.localId!.isNotEmpty)
            ? primaryMsg.localId!
            : (primaryMsg.id.isNotEmpty
                ? primaryMsg.id
                : 'album_${primaryMsg.createdAt}');

    if (isChannelCard) {
      return MessageInteractiveScope(
        messageKey: interactiveAlbumKey,
        child: albumContent,
      );
    }

    final Map<String, int> effectiveReactions =
        reactions ?? primaryMsg.reactions;
    final Set<String> effectiveMyReactions =
        myReactions ?? primaryMsg.myReactions;
    final bool hasAlbumReactions = effectiveReactions.isNotEmpty;

    final Widget albumWithReactions = hasAlbumReactions
        ? Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment:
                isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              albumContent,
              Padding(
                padding: EdgeInsets.only(
                  top: 2.0,
                  bottom: 2.0,
                  left: hasAvatarGutter ? 4.0 : 12.0,
                  right: 12.0,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: albumWidth),
                  child: MessageReactionsRow(
                    reactions: effectiveReactions,
                    myReactions: effectiveMyReactions,
                    onTap: onReactionTap,
                  ),
                ),
              ),
            ],
          )
        : albumContent;

    final Widget alignedAlbum = Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: albumWithReactions,
    );

    final Color rowHighlightColor = themeExt?.palette.messageSelectionOverlay ??
        theme.colorScheme.primary.withValues(alpha: 0.18);

    Widget rowContent = alignedAlbum;
    if (isSelectionMode && !hasAvatarGutter) {
      rowContent = Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 10.0, right: 2.0),
            child: MessageSelectionCheckbox(isSelected: isSelected),
          ),
          Expanded(child: alignedAlbum),
        ],
      );
    } else if (isSelectionMode) {
      rowContent = IgnorePointer(
        child: alignedAlbum,
      );
    }

    return MessageInteractiveScope(
      messageKey: interactiveAlbumKey,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 240),
        curve: Curves.easeOutCubic,
        width: double.infinity,
        color: (!hasAvatarGutter && shouldHighlightAlbum)
            ? rowHighlightColor
            : Colors.transparent,
        child: rowContent,
      ),
    );
  }

  Widget _buildTile(
    BuildContext context,
    MediaAlbumItem item,
    AlbumTilePosition pos,
    int index,
  ) {
    return _AlbumTileWidget(
      key: ValueKey('album_tile_${item.id}_${item.fileUrl}'),
      item: item,
      pos: pos,
      index: index,
      isHighlighted: highlightItemId != null && item.id == highlightItemId,
      onTap: () => _openViewer(context, index),
    );
  }

  String _getTimeString() {
    try {
      if (formatTime != null) return formatTime!(album.createdAt);
      final dt = DateTime.parse(album.createdAt);
      final hour = dt.hour.toString().padLeft(2, '0');
      final minute = dt.minute.toString().padLeft(2, '0');
      return '$hour:$minute';
    } catch (_) {
      return '';
    }
  }

  Widget _buildStatusIcon({Color color = Colors.white}) {
    if (album.sendStatus == MessageSendStatus.sending.index) {
      return iconoir.Clock(width: 12, height: 12, color: color);
    }
    if (album.sendStatus == MessageSendStatus.failed.index) {
      return const iconoir.WarningCircle(
        width: 12,
        height: 12,
        color: Colors.redAccent,
      );
    }
    return MessageStatusWidget(
      isRead: album.isRead,
      isOutgoing: isMe,
      colorOverride: color,
    );
  }
}

class _AlbumTileWidget extends StatefulWidget {
  final MediaAlbumItem item;
  final AlbumTilePosition pos;
  final int index;
  final bool isHighlighted;
  final VoidCallback onTap;

  const _AlbumTileWidget({
    Key? key,
    required this.item,
    required this.pos,
    required this.index,
    this.isHighlighted = false,
    required this.onTap,
  }) : super(key: key);

  @override
  State<_AlbumTileWidget> createState() => _AlbumTileWidgetState();
}

class _AlbumTileWidgetState extends State<_AlbumTileWidget> {
  final GlobalKey<MediaDownloadButtonState> _downloadButtonKey =
      GlobalKey<MediaDownloadButtonState>();
  File? _cachedFile;
  Uint8List? _cachedFirstFrame;

  @override
  void initState() {
    super.initState();
    _syncCacheImmediate();
    _checkCache();
  }

  @override
  void didUpdateWidget(covariant _AlbumTileWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.fileUrl != widget.item.fileUrl) {
      _cachedFile = null;
      _cachedFirstFrame = null;
      _syncCacheImmediate();
      _checkCache();
    }
  }

  void _syncCacheImmediate() {
    final rawUrl = widget.item.fileUrl ?? '';
    final resolvedUrl = AppConfig.resolveMediaUrl(rawUrl) ?? rawUrl;
    if (resolvedUrl.isEmpty) return;
    final syncFile =
        MediaCacheManager.instance.getCachedFileSync(resolvedUrl) ??
            MediaCacheManager.instance.getCachedFileSync(rawUrl);
    if (syncFile != null) {
      _cachedFile = syncFile;
      if (widget.item.isVideo) {
        _cachedFirstFrame = MediaCacheManager.instance
            .getCachedVideoThumbnailSync(syncFile.path);
      }
    }
  }

  Future<void> _checkCache() async {
    final rawUrl = widget.item.fileUrl ?? '';
    final resolvedUrl = AppConfig.resolveMediaUrl(rawUrl) ?? rawUrl;
    if (resolvedUrl.isNotEmpty) {
      final f = await MediaCacheManager.instance.getCachedFile(resolvedUrl);
      if (mounted && f != null) {
        if (_cachedFile?.path != f.path) {
          setState(() => _cachedFile = f);
        }
        if (widget.item.isVideo && _cachedFirstFrame == null) {
          final syncThumb =
              MediaCacheManager.instance.getCachedVideoThumbnailSync(f.path);
          if (syncThumb != null) {
            setState(() => _cachedFirstFrame = syncThumb);
          } else {
            _extractLocalFirstFrame(f.path);
          }
        }
      }
    }
  }

  Future<void> _extractLocalFirstFrame(String filePath) async {
    if (kIsWeb || !Platform.isAndroid) return;
    try {
      const channel = MethodChannel('com.example.app/media_muxer');
      final res = await channel.invokeMethod<Map<dynamic, dynamic>>(
        'getVideoThumbnail',
        {'videoPath': filePath},
      );
      final bytes = res != null ? res['thumbnail'] as Uint8List? : null;
      if (bytes != null) {
        MediaCacheManager.instance.cacheVideoThumbnail(filePath, bytes);
        if (mounted) {
          setState(() {
            _cachedFirstFrame = bytes;
          });
        }
      }
    } catch (_) {}
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final item = widget.item;
    final pos = widget.pos;
    final isCached = _cachedFile != null;
    final rawUrl = item.fileUrl ?? '';
    final resolvedUrl = AppConfig.resolveMediaUrl(rawUrl) ?? rawUrl;
    final rawThumbUrl = item.thumbUrl ?? '';
    final resolvedThumbUrl = rawThumbUrl.isNotEmpty
        ? (AppConfig.resolveMediaUrl(rawThumbUrl) ?? rawThumbUrl)
        : null;
    final autoDownload = MediaCacheManager.instance.shouldAutoDownload(
      messageType: item.isVideo ? 'video' : 'image',
      fileSize: item.fileSize,
    );

    return Positioned(
      left: pos.left,
      top: pos.top,
      width: pos.width,
      height: pos.height,
      child: ClipRRect(
        borderRadius: pos.borderRadius,
        child: Container(
          color: const Color(0xFF181818),
          child: GestureDetector(
            onTap: () {
              if (!isCached) {
                _downloadButtonKey.currentState?.handleTap();
                return;
              }
              widget.onTap();
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Blurred placeholder (only mounted until opaque media is ready)
                if (!((!item.isVideo && _cachedFile != null) ||
                    (item.isVideo && isCached && _cachedFirstFrame != null)))
                  BlurredMediaPlaceholder(
                    thumbBase64: item.thumbBase64,
                    aspectRatio: item.aspectRatio,
                  ),

                // 2. Real first frame for video ONLY after video is cached locally
                if (item.isVideo && isCached) ...[
                  if (_cachedFirstFrame != null)
                    Image.memory(
                      _cachedFirstFrame!,
                      fit: BoxFit.cover,
                      filterQuality: FilterQuality.low,
                      gaplessPlayback: true,
                    )
                  else if (resolvedThumbUrl != null && resolvedThumbUrl.isNotEmpty)
                    Image.network(
                      resolvedThumbUrl,
                      fit: BoxFit.cover,
                      cacheWidth: 600,
                      filterQuality: FilterQuality.low,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const SizedBox.shrink();
                      },
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                ],

                // 3. Display photo ONLY after file is cached locally on disk
                if (!item.isVideo && _cachedFile != null)
                  Image.file(
                    _cachedFile!,
                    cacheWidth: (pos.width * MediaQuery.devicePixelRatioOf(context))
                        .round()
                        .clamp(180, 960),
                    filterQuality: FilterQuality.low,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),

                // 4. Download button / progress / size pill
                if (resolvedUrl.isNotEmpty && (!isCached || item.isVideo))
                  MediaDownloadButton(
                    key: _downloadButtonKey,
                    url: resolvedUrl,
                    fileSize: item.fileSize,
                    isVideo: item.isVideo,
                    autoDownload: autoDownload,
                    onDownloaded: _checkCache,
                    onPlayVideo: widget.onTap,
                  ),

                // 5. Video duration badge (top-left)
                if (item.isVideo)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.6),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const iconoir.Play(
                            color: Colors.white,
                            width: 10,
                            height: 10,
                          ),
                          if (item.duration != null && item.duration! > 0) ...[
                            const SizedBox(width: 3),
                            Text(
                              _formatDuration(item.duration!),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                // 6. Highlight border & glow overlay when this specific tile is targeted
                if (widget.isHighlighted)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.35),
                          border: Border.all(
                            color: Theme.of(context).colorScheme.primary,
                            width: 3.0,
                          ),
                          borderRadius: pos.borderRadius,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
