import 'dart:io';
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:video_player/video_player.dart';
import '../../config/app_config.dart';
import '../../models/media_album.dart';
import '../../services/media_cache_manager.dart';
import 'blurred_media_placeholder.dart';
import 'media_download_button.dart';

/// Fullscreen multi-media viewer for albums with swipe navigation,
/// cached playback, and bottom thumbnail strip.
class MediaAlbumViewer extends StatefulWidget {
  final MediaAlbum album;
  final int initialIndex;

  const MediaAlbumViewer({
    Key? key,
    required this.album,
    this.initialIndex = 0,
  }) : super(key: key);

  @override
  State<MediaAlbumViewer> createState() => _MediaAlbumViewerState();
}

class _MediaAlbumViewerState extends State<MediaAlbumViewer> {
  late PageController _pageController;
  late int _currentIndex;
  final Map<int, VideoPlayerController> _videoControllers = {};
  final Map<int, File> _cachedFiles = {};

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, widget.album.items.length - 1);
    _pageController = PageController(initialPage: _currentIndex);
    _loadAllCacheStates();
  }

  Future<void> _loadAllCacheStates() async {
    for (int i = 0; i < widget.album.items.length; i++) {
      await _checkItemCache(i, autoPlayIfCurrent: i == _currentIndex);
    }
  }

  Future<void> _checkItemCache(int index, {bool autoPlayIfCurrent = true}) async {
    if (index < 0 || index >= widget.album.items.length) return;
    final item = widget.album.items[index];
    final rawUrl = item.fileUrl ?? '';
    final resolvedUrl = AppConfig.resolveMediaUrl(rawUrl) ?? rawUrl;
    if (resolvedUrl.isEmpty) return;

    final file = await MediaCacheManager.instance.getCachedFile(resolvedUrl);
    if (!mounted) return;
    if (file != null) {
      setState(() {
        _cachedFiles[index] = file;
      });
      if (item.isVideo && autoPlayIfCurrent && index == _currentIndex) {
        _initVideoIfNeeded(index);
      }
    }
  }

  void _initVideoIfNeeded(int index) {
    if (index < 0 || index >= widget.album.items.length) return;
    final item = widget.album.items[index];
    final cachedFile = _cachedFiles[index];
    if (item.isVideo && cachedFile != null && !_videoControllers.containsKey(index)) {
      final controller = VideoPlayerController.file(
        cachedFile,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
      _videoControllers[index] = controller;
      controller.initialize().then((_) {
        if (mounted) {
          setState(() {});
          if (_currentIndex == index) {
            controller.play();
          }
        }
      });
    }
  }

  void _onPageChanged(int index) {
    // Pause previous video if any
    final prev = _videoControllers[_currentIndex];
    if (prev != null && prev.value.isPlaying) {
      prev.pause();
    }

    setState(() {
      _currentIndex = index;
    });

    if (_cachedFiles.containsKey(index)) {
      _initVideoIfNeeded(index);
      final currentCtrl = _videoControllers[index];
      if (currentCtrl != null && currentCtrl.value.isInitialized && !currentCtrl.value.isPlaying) {
        currentCtrl.play();
      }
    } else {
      _checkItemCache(index, autoPlayIfCurrent: true);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    for (final c in _videoControllers.values) {
      c.dispose();
    }
    _videoControllers.clear();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.album.items;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // 1. Page view for media items
          PageView.builder(
            controller: _pageController,
            onPageChanged: _onPageChanged,
            itemCount: items.length,
            itemBuilder: (context, index) {
              final item = items[index];
              if (item.isVideo) {
                return _buildVideoItem(item, index);
              } else {
                return _buildPhotoItem(item, index);
              }
            },
          ),

          // 2. Top app bar with back button and counter
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.7),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    IconButton(
                      icon: const iconoir.ArrowLeft(
                        color: Colors.white,
                        width: 24,
                        height: 24,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_currentIndex + 1} / ${items.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const Spacer(),
                  ],
                ),
              ),
            ),
          ),

          // 3. Bottom thumbnail navigation strip and caption
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 8),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.8),
                      Colors.transparent,
                    ],
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (widget.album.hasCaption) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        child: Text(
                          widget.album.caption!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 14,
                          ),
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    SizedBox(
                      height: 54,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: items.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 8),
                        itemBuilder: (context, index) {
                          final item = items[index];
                          final isSelected = index == _currentIndex;
                          final cachedFile = _cachedFiles[index];
                          final rawThumb = item.thumbUrl ?? '';
                          final resolvedThumb = rawThumb.isNotEmpty
                              ? (AppConfig.resolveMediaUrl(rawThumb) ?? rawThumb)
                              : null;

                          return GestureDetector(
                            onTap: () {
                              _pageController.animateToPage(
                                index,
                                duration: const Duration(milliseconds: 250),
                                curve: Curves.easeInOut,
                              );
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 48,
                              height: 48,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(
                                  color: isSelected
                                      ? Theme.of(context).colorScheme.primary
                                      : Colors.transparent,
                                  width: 2.5,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    BlurredMediaPlaceholder(
                                      thumbBase64: item.thumbBase64,
                                    ),
                                    if (!item.isVideo && cachedFile != null)
                                      Image.file(
                                        cachedFile,
                                        fit: BoxFit.cover,
                                        gaplessPlayback: true,
                                      )
                                    else if (item.isVideo &&
                                        cachedFile != null &&
                                        resolvedThumb != null &&
                                        resolvedThumb.isNotEmpty)
                                      Image.network(
                                        resolvedThumb,
                                        fit: BoxFit.cover,
                                        errorBuilder: (_, __, ___) =>
                                            const SizedBox.shrink(),
                                      ),
                                    if (item.isVideo)
                                      const Center(
                                        child: iconoir.Play(
                                          color: Colors.white,
                                          width: 14,
                                          height: 14,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoItem(MediaAlbumItem item, int index) {
    final rawUrl = item.fileUrl ?? '';
    final resolvedUrl = AppConfig.resolveMediaUrl(rawUrl) ?? rawUrl;
    final cachedFile = _cachedFiles[index];

    if (cachedFile == null) {
      return Center(
        child: AspectRatio(
          aspectRatio: item.aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              BlurredMediaPlaceholder(
                thumbBase64: item.thumbBase64,
                aspectRatio: item.aspectRatio,
                fit: BoxFit.contain,
              ),
              if (resolvedUrl.isNotEmpty)
                MediaDownloadButton(
                  url: resolvedUrl,
                  fileSize: item.fileSize,
                  isVideo: false,
                  onDownloaded: () => _checkItemCache(index),
                ),
            ],
          ),
        ),
      );
    }

    return InteractiveViewer(
      minScale: 0.8,
      maxScale: 3.5,
      child: Center(
        child: Image.file(
          cachedFile,
          fit: BoxFit.contain,
          gaplessPlayback: true,
        ),
      ),
    );
  }

  Widget _buildVideoItem(MediaAlbumItem item, int index) {
    final rawUrl = item.fileUrl ?? '';
    final resolvedUrl = AppConfig.resolveMediaUrl(rawUrl) ?? rawUrl;
    final cachedFile = _cachedFiles[index];

    if (cachedFile == null) {
      return Center(
        child: AspectRatio(
          aspectRatio: item.aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              BlurredMediaPlaceholder(
                thumbBase64: item.thumbBase64,
                aspectRatio: item.aspectRatio,
                fit: BoxFit.contain,
              ),
              if (resolvedUrl.isNotEmpty)
                MediaDownloadButton(
                  url: resolvedUrl,
                  fileSize: item.fileSize,
                  isVideo: true,
                  onDownloaded: () => _checkItemCache(index, autoPlayIfCurrent: true),
                  onPlayVideo: () => _initVideoIfNeeded(index),
                ),
            ],
          ),
        ),
      );
    }

    final controller = _videoControllers[index];
    if (controller == null || !controller.value.isInitialized) {
      _initVideoIfNeeded(index);
      final rawThumb = item.thumbUrl ?? '';
      final resolvedThumb = rawThumb.isNotEmpty
          ? (AppConfig.resolveMediaUrl(rawThumb) ?? rawThumb)
          : null;
      return Center(
        child: Stack(
          alignment: Alignment.center,
          children: [
            BlurredMediaPlaceholder(
              thumbBase64: item.thumbBase64,
              aspectRatio: item.aspectRatio,
            ),
            if (resolvedThumb != null && resolvedThumb.isNotEmpty)
              Image.network(
                resolvedThumb,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            const CircularProgressIndicator(color: Colors.white),
          ],
        ),
      );
    }

    return Center(
      child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: Stack(
          alignment: Alignment.center,
          children: [
            VideoPlayer(controller),
            GestureDetector(
              onTap: () {
                setState(() {
                  controller.value.isPlaying
                      ? controller.pause()
                      : controller.play();
                });
              },
              child: AnimatedOpacity(
                opacity: controller.value.isPlaying ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Container(
                  width: 64,
                  height: 64,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: const Center(
                    child: iconoir.Play(
                      color: Colors.white,
                      width: 32,
                      height: 32,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
