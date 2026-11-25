import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import '../../config/app_config.dart';
import '../../models/theav_media_item.dart';
import '../../services/media_cache_manager.dart';
import '../media_viewer/theav_media_viewer.dart';
import 'blurred_media_placeholder.dart';
import 'media_download_button.dart';
import 'telegram_upload_progress.dart';

/// Widget for displaying photo and video message previews with blurred
/// preview placeholder, managed progressive download, and size pill.
class MediaMessageWidget extends StatefulWidget {
  final String mediaType; // 'photo' or 'video'
  final String url; // URL to the media file
  final String? localId;
  final String? chatId;
  final int sendStatus;
  final String? thumbnailUrl; // Optional thumbnail URL for videos
  final String? thumbBase64;
  final int? fileSize;
  final int? duration;
  final double? aspectRatio;
  final String? heroTag;
  final VoidCallback? onCancelUpload;
  final VoidCallback? onRetry;
  final VoidCallback? onTap; // Callback when the media is tapped

  const MediaMessageWidget({
    Key? key,
    required this.mediaType,
    required this.url,
    this.localId,
    this.chatId,
    this.sendStatus = 1,
    this.thumbnailUrl,
    this.thumbBase64,
    this.fileSize,
    this.duration,
    this.aspectRatio,
    this.heroTag,
    this.onCancelUpload,
    this.onRetry,
    this.onTap,
  }) : super(key: key);

  @override
  State<MediaMessageWidget> createState() => _MediaMessageWidgetState();
}

class _MediaMessageWidgetState extends State<MediaMessageWidget> {
  final GlobalKey<MediaDownloadButtonState> _downloadButtonKey =
      GlobalKey<MediaDownloadButtonState>();
  File? _cachedFile;

  @override
  void initState() {
    super.initState();
    _checkCache();
  }

  @override
  void didUpdateWidget(covariant MediaMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _cachedFile = null;
      _checkCache();
    }
  }

  Future<void> _checkCache() async {
    final resolvedUrl = AppConfig.resolveMediaUrl(widget.url) ?? widget.url;
    if (resolvedUrl.isNotEmpty) {
      final f = await MediaCacheManager.instance.getCachedFile(resolvedUrl);
      if (mounted && f != null) {
        setState(() => _cachedFile = f);
      }
    }
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  void _handleMediaTap(BuildContext context) {
    if (widget.onTap != null) {
      widget.onTap!.call();
      return;
    }
    final resolvedUrl = AppConfig.resolveMediaUrl(widget.url) ?? widget.url;
    final tag = widget.heroTag ?? 'media_$resolvedUrl';
    final isVideo = widget.mediaType == 'video';
    TheavMediaViewer.open<void>(
      context,
      items: <TheavMediaItem>[
        TheavMediaItem(
          id: tag,
          kind: isVideo ? TheavMediaKind.video : TheavMediaKind.photo,
          url: resolvedUrl,
          localFilePath: _cachedFile?.path,
          thumbUrl: widget.thumbnailUrl,
          thumbBase64: widget.thumbBase64,
          durationSeconds: widget.duration,
          fileSize: widget.fileSize,
          heroTag: tag,
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final isCached = _cachedFile != null;
    final isUploadingOrFailed = widget.sendStatus != 1;
    return GestureDetector(
      onTap: () {
        if (!isUploadingOrFailed && !isCached) {
          _downloadButtonKey.currentState?.handleTap();
          return;
        }
        _handleMediaTap(context);
      },
      child: _buildMediaPreview(),
    );
  }

  Widget _buildMediaPreview() {
    switch (widget.mediaType) {
      case 'photo':
        return _buildImagePreview();
      case 'video':
        return _buildVideoPreview();
      default:
        return const SizedBox.shrink();
    }
  }

  Widget _buildImagePreview() {
    final resolvedUrl = AppConfig.resolveMediaUrl(widget.url) ?? widget.url;
    final ratio = widget.aspectRatio ?? 1.33;
    final isCached = _cachedFile != null;
    final isUploadingOrFailed = widget.sendStatus != 1;
    final autoDownload = MediaCacheManager.instance.shouldAutoDownload(
      messageType: 'image',
      fileSize: widget.fileSize,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(10.0),
      child: AspectRatio(
        aspectRatio: ratio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Blurred preview placeholder
            BlurredMediaPlaceholder(
              thumbBase64: widget.thumbBase64,
              aspectRatio: ratio,
            ),

            // 2. Full local image
            if (_cachedFile != null)
              if (widget.heroTag != null && widget.heroTag!.isNotEmpty)
                Hero(
                  tag: widget.heroTag!,
                  child: Image.file(
                    _cachedFile!,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                )
              else
                Image.file(
                  _cachedFile!,
                  fit: BoxFit.cover,
                  gaplessPlayback: true,
                ),

            if (isUploadingOrFailed &&
                widget.localId != null &&
                widget.localId!.isNotEmpty)
              TelegramMediaUploadOverlay(
                localId: widget.localId!,
                chatId: widget.chatId,
                fileSize: widget.fileSize,
                sendStatus: widget.sendStatus,
                onCancel: widget.onCancelUpload,
                onRetry: widget.onRetry,
              )
            // 3. Download button with size pill if needed
            else if (!isUploadingOrFailed && resolvedUrl.isNotEmpty && !isCached)
              MediaDownloadButton(
                key: _downloadButtonKey,
                url: resolvedUrl,
                fileSize: widget.fileSize,
                isVideo: false,
                autoDownload: autoDownload,
                onDownloaded: _checkCache,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoPreview() {
    final resolvedUrl = AppConfig.resolveMediaUrl(widget.url) ?? widget.url;
    final resolvedThumbUrl = widget.thumbnailUrl != null && widget.thumbnailUrl!.isNotEmpty
        ? (AppConfig.resolveMediaUrl(widget.thumbnailUrl!) ?? widget.thumbnailUrl!)
        : null;
    final ratio = widget.aspectRatio ?? 1.33;
    final isUploadingOrFailed = widget.sendStatus != 1;
    final autoDownload = MediaCacheManager.instance.shouldAutoDownload(
      messageType: 'video',
      fileSize: widget.fileSize,
    );

    return ClipRRect(
      borderRadius: BorderRadius.circular(10.0),
      child: AspectRatio(
        aspectRatio: ratio,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Blurred preview placeholder
            BlurredMediaPlaceholder(
              thumbBase64: widget.thumbBase64,
              aspectRatio: ratio,
            ),

            // 2. Video thumbnail rendered immediately (including authenticated fallback)
            RemoteVideoThumbnailImage(
              thumbUrl: resolvedThumbUrl,
              cacheWidth: 800,
            ),

            if (isUploadingOrFailed &&
                widget.localId != null &&
                widget.localId!.isNotEmpty)
              TelegramMediaUploadOverlay(
                localId: widget.localId!,
                chatId: widget.chatId,
                fileSize: widget.fileSize,
                sendStatus: widget.sendStatus,
                onCancel: widget.onCancelUpload,
                onRetry: widget.onRetry,
              )
            else if (!isUploadingOrFailed && resolvedUrl.isNotEmpty)
              MediaDownloadButton(
                key: _downloadButtonKey,
                url: resolvedUrl,
                fileSize: widget.fileSize,
                isVideo: true,
                autoDownload: autoDownload,
                onDownloaded: _checkCache,
                onPlayVideo: () => _handleMediaTap(context),
              ),

            // 4. Video duration pill in top-left
            if (!isUploadingOrFailed &&
                widget.duration != null &&
                widget.duration! > 0)
              Positioned(
                top: 8,
                left: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const iconoir.Play(
                        color: Colors.white,
                        width: 10,
                        height: 10,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        _formatDuration(widget.duration!),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}