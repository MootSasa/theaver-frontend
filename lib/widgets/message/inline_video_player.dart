import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:video_player/video_player.dart';
import '../../services/media_cache_manager.dart';
import '../../services/media_playback_coordinator.dart';

/// Inline video player for chat messages
/// Shows a thumbnail with play button, expands to play inline
class InlineVideoPlayer extends StatefulWidget {
  final String url;
  final bool autoplay;

  const InlineVideoPlayer({
    Key? key,
    required this.url,
    this.autoplay = false,
  }) : super(key: key);

  @override
  State<InlineVideoPlayer> createState() => _InlineVideoPlayerState();
}

class _InlineVideoPlayerState extends State<InlineVideoPlayer> {
  VideoPlayerController? _controller;
  bool _isInitialized = false;
  bool _isPlaying = false;
  bool _showControls = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    MediaPlaybackCoordinator.instance.addListener(_onCoordinatorChanged);
    _initController();
  }

  void _onCoordinatorChanged() {
    if (!mounted) return;
    if (MediaPlaybackCoordinator.instance.hasActiveMedia &&
        (_controller?.value.isPlaying ?? false)) {
      _controller?.pause();
    }
  }

  Future<void> _initController() async {
    final currentUrl = widget.url;
    try {
      final cachedFile = await MediaCacheManager.instance.getCachedFile(currentUrl);
      if (!mounted || widget.url != currentUrl) return;

      final controller = cachedFile != null && await cachedFile.exists()
          ? VideoPlayerController.file(cachedFile)
          : VideoPlayerController.networkUrl(Uri.parse(currentUrl));

      if (!mounted || widget.url != currentUrl) {
        controller.dispose();
        return;
      }

      _controller = controller;
      await controller.initialize();

      if (!mounted || widget.url != currentUrl) {
        controller.dispose();
        return;
      }

      setState(() {
        _isInitialized = true;
        _error = null;
      });
      if (widget.autoplay) {
        await MediaPlaybackCoordinator.instance.stopAll();
        if (!mounted || widget.url != currentUrl) return;
        controller.play();
        _isPlaying = true;
      }
      controller.addListener(_onVideoUpdate);
    } catch (error) {
      if (mounted && widget.url == currentUrl) {
        setState(() {
          _error = error.toString();
        });
      }
    }
  }

  void _onVideoUpdate() {
    if (!mounted) return;
    setState(() {
      _isPlaying = _controller?.value.isPlaying ?? false;
    });
  }

  @override
  void dispose() {
    MediaPlaybackCoordinator.instance.removeListener(_onCoordinatorChanged);
    _controller?.removeListener(_onVideoUpdate);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(InlineVideoPlayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url) {
      _controller?.removeListener(_onVideoUpdate);
      _controller?.dispose();
      _isInitialized = false;
      _error = null;
      _initController();
    }
  }

  void _togglePlayPause() {
    if (_controller == null || !_isInitialized) return;
    final wasPlaying = _controller!.value.isPlaying;
    if (!wasPlaying) {
      MediaPlaybackCoordinator.instance.stopAll();
    }
    setState(() {
      if (wasPlaying) {
        _controller!.pause();
      } else {
        _controller!.play();
      }
      _showControls = true;
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60);
    final seconds = duration.inSeconds.remainder(60);
    if (hours > 0) {
      return '$hours:${twoDigits(minutes)}:${twoDigits(seconds)}';
    }
    return '${twoDigits(minutes)}:${twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    if (_error != null) {
      return _buildErrorWidget();
    }

    if (!_isInitialized) {
      return _buildLoadingWidget();
    }

    final aspectRatio = _controller!.value.aspectRatio;
    final duration = _controller!.value.duration;
    final position = _controller!.value.position;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: GestureDetector(
        onTap: _toggleControls,
        child: Stack(
          alignment: Alignment.bottomCenter,
          children: [
            // Video frame
            AspectRatio(
              aspectRatio: aspectRatio,
              child: VideoPlayer(_controller!),
            ),

            // Play/Pause button overlay
            if (_showControls)
              GestureDetector(
                onTap: _togglePlayPause,
                child: Container(
                  color: Colors.black.withValues(alpha: 0.3),
                  child: Center(
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: _isPlaying
                          ? const iconoir.Pause(
                              key: ValueKey('pause'),
                              color: Colors.white,
                              width: 48,
                              height: 48,
                            )
                          : const iconoir.Play(
                              key: ValueKey('play'),
                              color: Colors.white,
                              width: 48,
                              height: 48,
                            ),
                    ),
                  ),
                ),
              ),

            // Bottom controls bar
            if (_showControls)
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.7),
                      ],
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // Progress bar
                      VideoProgressIndicator(
                        _controller!,
                        allowScrubbing: true,
                        colors: VideoProgressColors(
                          playedColor: Theme.of(context).colorScheme.primary,
                          bufferedColor: Colors.white.withValues(alpha: 0.3),
                          backgroundColor: Colors.white.withValues(alpha: 0.2),
                        ),
                      ),
                      // Time labels
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(position),
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 11,
                            ),
                          ),
                          Text(
                            _formatDuration(duration),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 11,
                            ),
                          ),
                        ],
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

  Widget _buildLoadingWidget() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Center(
        child: CircularProgressIndicator(color: Colors.white54),
      ),
    );
  }

  Widget _buildErrorWidget() {
    return Container(
      height: 200,
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const iconoir.WarningCircle(color: Colors.white54, width: 40, height: 40),
          const SizedBox(height: 8),
          Text(
            'Ошибка загрузки видео',
            style: TextStyle(color: Colors.grey[400], fontSize: 13),
          ),
        ],
      ),
    );
  }
}
