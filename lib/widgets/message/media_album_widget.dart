import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../config/app_config.dart';
import '../../models/media_album.dart';
import '../../services/database/app_database.dart';
import '../../services/media_cache_manager.dart';
import 'blurred_media_placeholder.dart';
import 'media_album_layout.dart';
import 'media_album_viewer.dart';
import 'media_download_button.dart';

/// Widget rendering a Telegram-style collage bubble for 2–10 media items.
class MediaAlbumWidget extends StatelessWidget {
  final MediaAlbum album;
  final bool isMe;
  final String currentUserId;
  final String? chatType;
  final String? senderName;
  final String Function(String)? formatTime;
  final Function(String url, String name, String type)? onFileTap;
  final bool isHighlighted;
  final String? highlightItemId;

  const MediaAlbumWidget({
    Key? key,
    required this.album,
    required this.isMe,
    required this.currentUserId,
    this.chatType,
    this.senderName,
    this.formatTime,
    this.onFileTap,
    this.isHighlighted = false,
    this.highlightItemId,
  }) : super(key: key);

  void _openViewer(BuildContext context, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => MediaAlbumViewer(
          album: album,
          initialIndex: index,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final albumWidth = (screenWidth * 0.76).clamp(240.0, 380.0);
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
    final showSender = !isMe && senderName != null && senderName!.isNotEmpty;
    final hasTextBubble = album.hasCaption || showSender;
    final bubbleColor = hasTextBubble
        ? (isMe ? theme.colorScheme.primary : theme.colorScheme.secondaryContainer)
        : Colors.transparent;
    final onBubbleColor = isMe
        ? theme.colorScheme.onPrimary
        : theme.colorScheme.onSecondaryContainer;

    final albumContent = Container(
      width: albumWidth,
      decoration: BoxDecoration(
        color: bubbleColor,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (!isMe && senderName != null && senderName!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
              child: Text(
                senderName!,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                  color: theme.colorScheme.primary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          // 1. Mosaic Collage Container
          SizedBox(
            width: albumWidth,
            height: albumHeight,
            child: Stack(
              children: [
                for (int i = 0; i < positions.length; i++)
                  _buildTile(context, album.items[i], positions[i], i),

                // Floating time pill if captionless
                if (!album.hasCaption)
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

          // 2. Caption Text & Meta (if present)
          if (album.hasCaption)
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.caption!,
                    style: TextStyle(
                      color: onBubbleColor,
                      fontSize: 15,
                    ),
                  ),
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
              ),
            ),
        ],
      ),
    );

    final bool shouldHighlightAlbum =
        isHighlighted || (highlightItemId != null && album.items.any((it) => it.id == highlightItemId));

    return AnimatedContainer(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      padding: shouldHighlightAlbum ? const EdgeInsets.all(3) : EdgeInsets.zero,
      decoration: BoxDecoration(
        color: shouldHighlightAlbum
            ? theme.colorScheme.primary.withValues(alpha: 0.18)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(19),
      ),
      child: albumContent,
    );
  }

  Widget _buildTile(
    BuildContext context,
    MediaAlbumItem item,
    AlbumTilePosition pos,
    int index,
  ) {
    return _AlbumTileWidget(
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
      return Icon(Icons.access_time, size: 12, color: color);
    }
    if (album.sendStatus == MessageSendStatus.failed.index) {
      return const Icon(Icons.error_outline, size: 12, color: Colors.redAccent);
    }
    if (album.isRead) {
      return Icon(Icons.done_all, size: 13, color: color);
    }
    return Icon(Icons.done, size: 13, color: color);
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
  File? _cachedFile;
  Uint8List? _cachedFirstFrame;

  @override
  void initState() {
    super.initState();
    _checkCache();
  }

  Future<void> _checkCache() async {
    final rawUrl = widget.item.fileUrl ?? '';
    final resolvedUrl = AppConfig.resolveMediaUrl(rawUrl) ?? rawUrl;
    if (resolvedUrl.isNotEmpty) {
      final f = await MediaCacheManager.instance.getCachedFile(resolvedUrl);
      if (mounted && f != null) {
        setState(() => _cachedFile = f);
        if (widget.item.isVideo && _cachedFirstFrame == null) {
          _extractLocalFirstFrame(f.path);
        }
      }
    }
  }

  Future<void> _extractLocalFirstFrame(String filePath) async {
    if (!Platform.isAndroid) return;
    try {
      const channel = MethodChannel('com.example.app/media_muxer');
      final res = await channel.invokeMethod<Map<dynamic, dynamic>>(
        'getVideoThumbnail',
        {'videoPath': filePath},
      );
      if (res != null && res['thumbnail'] != null && mounted) {
        setState(() {
          _cachedFirstFrame = res['thumbnail'] as Uint8List?;
        });
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
            onTap: widget.onTap,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Blurred placeholder
                BlurredMediaPlaceholder(
                  thumbBase64: item.thumbBase64,
                  aspectRatio: item.aspectRatio,
                ),

                // 2. Real first frame for video (replaces blurred preview when loaded)
                if (item.isVideo) ...[
                  if (_cachedFirstFrame != null)
                    Image.memory(
                      _cachedFirstFrame!,
                      fit: BoxFit.cover,
                    )
                  else if (resolvedThumbUrl != null && resolvedThumbUrl.isNotEmpty)
                    Image.network(
                      resolvedThumbUrl,
                      fit: BoxFit.cover,
                      cacheWidth: 600,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const SizedBox.shrink();
                      },
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                ],

                // 3. Display image if cached or auto-download allowed (for photos)
                if (!item.isVideo) ...[
                  if (_cachedFile != null)
                    Image.file(
                      _cachedFile!,
                      fit: BoxFit.cover,
                    )
                  else if (resolvedUrl.isNotEmpty && autoDownload)
                    Image.network(
                      resolvedUrl,
                      fit: BoxFit.cover,
                      cacheWidth: 600,
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const SizedBox.shrink();
                      },
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    ),
                ],

                // 4. Download button / progress / size pill
                if (resolvedUrl.isNotEmpty)
                  MediaDownloadButton(
                    url: resolvedUrl,
                    fileSize: item.fileSize,
                    isVideo: item.isVideo,
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
