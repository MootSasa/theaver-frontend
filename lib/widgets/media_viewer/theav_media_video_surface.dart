import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:video_player/video_player.dart';

import '../../models/theav_media_item.dart';
import '../../services/media_cache_manager.dart';
import '../../services/media_playback_coordinator.dart';
import '../../services/sticker_service.dart';
import '../../services/video_pip_service.dart';
import '../chat/sticker_item_widget.dart';
import '../message/blurred_media_placeholder.dart';

/// Immutable playback snapshot pushed by [TheavVideoPlaybackBridge] at 60/120Hz
/// so only the bottom video scrubber & buttons repaint without rebuilding the
/// full viewer page.
@immutable
class TheavVideoPlaybackState {
  final bool isInitialized;
  final bool isPlaying;
  final bool isBuffering;
  final bool isMuted;
  final double playbackSpeed;
  final Duration position;
  final Duration duration;
  final Duration bufferedEnd;
  final double? downloadFraction;
  final String? errorMessage;

  const TheavVideoPlaybackState({
    this.isInitialized = false,
    this.isPlaying = false,
    this.isBuffering = false,
    this.isMuted = false,
    this.playbackSpeed = 1.0,
    this.position = Duration.zero,
    this.duration = Duration.zero,
    this.bufferedEnd = Duration.zero,
    this.downloadFraction,
    this.errorMessage,
  });

  TheavVideoPlaybackState copyWith({
    bool? isInitialized,
    bool? isPlaying,
    bool? isBuffering,
    bool? isMuted,
    double? playbackSpeed,
    Duration? position,
    Duration? duration,
    Duration? bufferedEnd,
    double? downloadFraction,
    bool clearDownloadFraction = false,
    String? errorMessage,
    bool clearError = false,
  }) {
    return TheavVideoPlaybackState(
      isInitialized: isInitialized ?? this.isInitialized,
      isPlaying: isPlaying ?? this.isPlaying,
      isBuffering: isBuffering ?? this.isBuffering,
      isMuted: isMuted ?? this.isMuted,
      playbackSpeed: playbackSpeed ?? this.playbackSpeed,
      position: position ?? this.position,
      duration: duration ?? this.duration,
      bufferedEnd: bufferedEnd ?? this.bufferedEnd,
      downloadFraction: clearDownloadFraction
          ? null
          : (downloadFraction ?? this.downloadFraction),
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Control & telemetry bridge between [TheavMediaVideoSurface] and
/// [TheavMediaHud] / [VideoPipService].
class TheavVideoPlaybackBridge {
  final ValueNotifier<TheavVideoPlaybackState> state =
      ValueNotifier<TheavVideoPlaybackState>(const TheavVideoPlaybackState());

  Future<void> Function()? _onTogglePlayPause;
  Future<void> Function(Duration position)? _onSeekTo;
  Future<void> Function(Duration delta)? _onSeekRelative;
  Future<void> Function(double speed)? _onSetSpeed;
  Future<void> Function()? _onToggleMute;
  VideoPlayerController? Function()? _onDetachForPip;

  void _attach({
    required Future<void> Function() onTogglePlayPause,
    required Future<void> Function(Duration position) onSeekTo,
    required Future<void> Function(Duration delta) onSeekRelative,
    required Future<void> Function(double speed) onSetSpeed,
    required Future<void> Function() onToggleMute,
    required VideoPlayerController? Function() onDetachForPip,
  }) {
    _onTogglePlayPause = onTogglePlayPause;
    _onSeekTo = onSeekTo;
    _onSeekRelative = onSeekRelative;
    _onSetSpeed = onSetSpeed;
    _onToggleMute = onToggleMute;
    _onDetachForPip = onDetachForPip;
  }

  void _detach() {
    _onTogglePlayPause = null;
    _onSeekTo = null;
    _onSeekRelative = null;
    _onSetSpeed = null;
    _onToggleMute = null;
    _onDetachForPip = null;
  }

  Future<void> togglePlayPause() async => _onTogglePlayPause?.call();
  Future<void> seekTo(Duration position) async => _onSeekTo?.call(position);
  Future<void> seekRelative(Duration delta) async =>
      _onSeekRelative?.call(delta);
  Future<void> setSpeed(double speed) async => _onSetSpeed?.call(speed);
  Future<void> toggleMute() async => _onToggleMute?.call();
  VideoPlayerController? detachControllerForPip() =>
      _onDetachForPip?.call();

  void dispose() {
    _detach();
    state.dispose();
  }
}

/// Fullscreen video & GIF surface for [TheavMediaViewer].
///
/// - Renders raster GIFs/WebPs with [ControlledAnimatedNetworkImage] (`animate: isActive`).
/// - Renders videos & MP4-backed GIFs via [VideoPlayer], adopting live PiP
///   controllers instantaneously from [VideoPipService] when expanded.
/// - Downloads uncached files via [MediaCacheManager] with a crisp matte progress
///   ring over the instant blurred/thumbnail poster, or falls back to streaming.
class TheavMediaVideoSurface extends StatefulWidget {
  final TheavMediaItem item;
  final bool isActive;
  final bool enableHero;
  final TheavVideoPlaybackBridge? bridge;

  const TheavMediaVideoSurface({
    super.key,
    required this.item,
    required this.isActive,
    this.enableHero = true,
    this.bridge,
  });

  @override
  State<TheavMediaVideoSurface> createState() =>
      _TheavMediaVideoSurfaceState();
}

class _TheavMediaVideoSurfaceState extends State<TheavMediaVideoSurface> {
  VideoPlayerController? _controller;
  ValueNotifier<DownloadByteProgress>? _downloadNotifier;
  Uint8List? _cachedFirstFrame;
  bool _isInitializing = false;
  bool _isDisposed = false;
  bool _isMuted = false;

  bool get _isRasterGif =>
      widget.item.kind == TheavMediaKind.gif && !widget.item.isVideoBackedGif;

  bool get _isGifLoop => widget.item.kind == TheavMediaKind.gif;

  @override
  void initState() {
    super.initState();
    _isMuted = _isGifLoop;
    _bindBridge();
    if (!_isRasterGif) {
      _extractLocalThumbIfAny();
      _initVideoController();
    }
  }

  @override
  void didUpdateWidget(covariant TheavMediaVideoSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.bridge != widget.bridge) {
      oldWidget.bridge?._detach();
      _bindBridge();
    }
    if (oldWidget.item.id != widget.item.id ||
        oldWidget.item.url != widget.item.url) {
      _disposeControllerOnly();
      _detachDownloadProgress();
      _cachedFirstFrame = null;
      _isMuted = _isGifLoop;
      widget.bridge?.state.value = TheavVideoPlaybackState(isMuted: _isMuted);
      if (!_isRasterGif) {
        _extractLocalThumbIfAny();
        _initVideoController();
      }
      return;
    }

    if (oldWidget.isActive != widget.isActive && !_isRasterGif) {
      final ctrl = _controller;
      if (ctrl != null && ctrl.value.isInitialized) {
        if (widget.isActive) {
          if (!_isMuted) {
            unawaited(MediaPlaybackCoordinator.instance.stopAll());
          }
          unawaited(ctrl.play());
        } else {
          unawaited(ctrl.pause());
        }
        _syncBridgeFromController();
      }
    }
  }

  @override
  void dispose() {
    _isDisposed = true;
    widget.bridge?._detach();
    _detachDownloadProgress();
    _disposeControllerOnly();
    super.dispose();
  }

  void _bindBridge() {
    widget.bridge?._attach(
      onTogglePlayPause: _togglePlayPause,
      onSeekTo: _seekTo,
      onSeekRelative: _seekRelative,
      onSetSpeed: _setSpeed,
      onToggleMute: _toggleMute,
      onDetachForPip: _detachControllerForPip,
    );
  }

  void _disposeControllerOnly() {
    final prev = _controller;
    _controller = null;
    if (prev != null) {
      prev.removeListener(_onControllerTick);
      try {
        prev.dispose();
      } catch (_) {}
    }
  }

  void _detachDownloadProgress() {
    _downloadNotifier?.removeListener(_onDownloadProgressTick);
    _downloadNotifier = null;
  }

  void _extractLocalThumbIfAny() {
    final localPath = widget.item.localFilePath;
    if (localPath != null && localPath.isNotEmpty) {
      _cachedFirstFrame =
          MediaCacheManager.instance.getCachedVideoThumbnailSync(localPath);
    }
    if (_cachedFirstFrame == null) {
      final resolved = widget.item.resolvedUrl;
      final cached = MediaCacheManager.instance.getCachedFileSync(resolved);
      if (cached != null) {
        _cachedFirstFrame = MediaCacheManager.instance
            .getCachedVideoThumbnailSync(cached.path);
      }
    }
  }

  Future<void> _initVideoController() async {
    if (_isInitializing || _isDisposed) return;
    _isInitializing = true;
    final String itemId = widget.item.id;

    try {
      // 1. Instant adoption from active PiP without any re-buffering.
      final VideoPlayerController? pipController =
          VideoPipService.instance.takeControllerForFullscreen(itemId);
      if (pipController != null) {
        _attachInitializedController(pipController, alreadyInitialized: true);
        return;
      }

      // 2. Resolve cached/local file or stream URL.
      final String resolvedUrl = widget.item.resolvedUrl;
      File? localFile;
      if (!kIsWeb &&
          widget.item.localFilePath != null &&
          widget.item.localFilePath!.isNotEmpty) {
        final f = File(widget.item.localFilePath!);
        if (await f.exists() && await f.length() > 0) {
          localFile = f;
        }
      }

      if (localFile == null && !kIsWeb && resolvedUrl.isNotEmpty) {
        localFile = await MediaCacheManager.instance.getCachedFile(resolvedUrl);
      }

      if (!mounted || _isDisposed || widget.item.id != itemId) return;

      if (localFile == null && !kIsWeb && resolvedUrl.startsWith('http')) {
        // Check/start background download so the user sees progress, OR stream directly.
        // We stream immediately for instant playback AND start cache download silently.
        _startBackgroundCacheDownload(resolvedUrl);
      }

      final VideoPlayerController controller;
      if (localFile != null) {
        controller = VideoPlayerController.file(localFile);
      } else {
        final uri = Uri.tryParse(resolvedUrl);
        if (uri == null) {
          widget.bridge?.state.value = widget.bridge!.state.value
              .copyWith(errorMessage: 'Invalid video URL');
          return;
        }
        controller = VideoPlayerController.networkUrl(uri);
      }

      _controller = controller;
      controller.addListener(_onControllerTick);
      await controller.initialize();

      if (!mounted || _isDisposed || widget.item.id != itemId || !identical(_controller, controller)) {
        if (!identical(_controller, controller)) {
          try {
            controller.removeListener(_onControllerTick);
            await controller.dispose();
          } catch (_) {}
        }
        return;
      }

      await _configureAndPlay(controller);
    } catch (e) {
      if (mounted && !_isDisposed && widget.item.id == itemId) {
        widget.bridge?.state.value = widget.bridge!.state.value.copyWith(
          errorMessage: e.toString(),
          clearDownloadFraction: true,
        );
      }
    } finally {
      _isInitializing = false;
    }
  }

  void _startBackgroundCacheDownload(String resolvedUrl) {
    _detachDownloadProgress();
    final notifier = MediaCacheManager.instance.getByteProgressNotifier(resolvedUrl);
    _downloadNotifier = notifier;
    notifier.addListener(_onDownloadProgressTick);
    if (!MediaCacheManager.instance.isDownloading(resolvedUrl)) {
      unawaited(
        MediaCacheManager.instance.downloadFile(
          resolvedUrl,
          expectedTotalSize: widget.item.fileSize,
        ),
      );
    }
  }

  void _onDownloadProgressTick() {
    final notifier = _downloadNotifier;
    if (!mounted || _isDisposed || notifier == null) return;
    final val = notifier.value.fraction;
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) {
      widget.bridge?.state.value = widget.bridge!.state.value.copyWith(
        downloadFraction: val >= 1.0 ? null : val,
        clearDownloadFraction: val >= 1.0,
      );
    }
  }

  void _attachInitializedController(
    VideoPlayerController controller, {
    required bool alreadyInitialized,
  }) {
    _controller = controller;
    controller.addListener(_onControllerTick);
    _isMuted = controller.value.volume <= 0.01;
    if (alreadyInitialized && widget.isActive) {
      unawaited(_configureAndPlay(controller, resetAudioState: false));
    } else {
      _syncBridgeFromController();
      if (mounted) setState(() {});
    }
  }

  Future<void> _configureAndPlay(
    VideoPlayerController controller, {
    bool resetAudioState = true,
  }) async {
    final Duration total = controller.value.duration;
    final bool shouldLoop =
        _isGifLoop || (total > Duration.zero && total <= const Duration(seconds: 10));
    await controller.setLooping(shouldLoop);
    if (resetAudioState) {
      if (_isGifLoop) {
        _isMuted = true;
        await controller.setVolume(0.0);
      } else {
        await controller.setVolume(_isMuted ? 0.0 : 1.0);
      }
    }
    if (widget.isActive) {
      if (!_isMuted) {
        await MediaPlaybackCoordinator.instance.stopAll();
      }
      if (!controller.value.isPlaying) {
        await controller.play();
      }
    }
    _syncBridgeFromController();
    if (mounted) setState(() {});
  }

  void _onControllerTick() {
    if (!mounted || _isDisposed) return;
    _syncBridgeFromController();
  }

  void _syncBridgeFromController() {
    final ctrl = _controller;
    final bridge = widget.bridge;
    if (ctrl == null || bridge == null) return;
    final v = ctrl.value;
    Duration bufferedEnd = Duration.zero;
    if (v.buffered.isNotEmpty) {
      bufferedEnd = v.buffered.last.end;
    }
    bridge.state.value = bridge.state.value.copyWith(
      isInitialized: v.isInitialized,
      isPlaying: v.isPlaying,
      isBuffering: v.isBuffering,
      isMuted: v.volume <= 0.01,
      playbackSpeed: v.playbackSpeed,
      position: v.position,
      duration: v.duration,
      bufferedEnd: bufferedEnd,
      clearDownloadFraction: v.isInitialized,
      clearError: true,
    );
  }

  Future<void> _togglePlayPause() async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    if (ctrl.value.isPlaying) {
      await ctrl.pause();
    } else {
      if (!_isMuted) {
        await MediaPlaybackCoordinator.instance.stopAll();
      }
      if (ctrl.value.duration > Duration.zero &&
          ctrl.value.position >=
              ctrl.value.duration - const Duration(milliseconds: 220)) {
        await ctrl.seekTo(Duration.zero);
      }
      await ctrl.play();
    }
    _syncBridgeFromController();
  }

  Future<void> _seekTo(Duration position) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    final maxMs = ctrl.value.duration.inMilliseconds;
    final targetMs = position.inMilliseconds.clamp(0, maxMs);
    await ctrl.seekTo(Duration(milliseconds: targetMs));
    _syncBridgeFromController();
  }

  Future<void> _seekRelative(Duration delta) async {
    final ctrl = _controller;
    if (ctrl == null || !ctrl.value.isInitialized) return;
    await _seekTo(ctrl.value.position + delta);
  }

  Future<void> _setSpeed(double speed) async {
    final ctrl = _controller;
    if (ctrl != null && ctrl.value.isInitialized) {
      await ctrl.setPlaybackSpeed(speed);
      _syncBridgeFromController();
    }
  }

  Future<void> _toggleMute() async {
    final ctrl = _controller;
    _isMuted = !_isMuted;
    if (ctrl != null && ctrl.value.isInitialized) {
      if (!_isMuted) {
        await MediaPlaybackCoordinator.instance.stopAll();
      }
      await ctrl.setVolume(_isMuted ? 0.0 : 1.0);
      _syncBridgeFromController();
    }
  }

  VideoPlayerController? _detachControllerForPip() {
    final ctrl = _controller;
    if (ctrl == null) return null;
    _controller = null;
    ctrl.removeListener(_onControllerTick);
    return ctrl;
  }

  Widget _wrapHeroIfNeeded(Widget child) {
    if (!widget.enableHero || widget.item.heroTag.isEmpty) {
      return child;
    }
    return Hero(
      tag: widget.item.heroTag,
      child: child,
    );
  }

  Widget _buildPosterFallback() {
    final resolvedThumb = widget.item.resolvedThumbUrl;
    return AspectRatio(
      aspectRatio: widget.item.aspectRatio,
      child: Stack(
        fit: StackFit.expand,
        children: [
          BlurredMediaPlaceholder(
            thumbBase64: widget.item.thumbBase64,
            aspectRatio: widget.item.aspectRatio,
            fit: BoxFit.contain,
          ),
          if (_cachedFirstFrame != null)
            Image.memory(
              _cachedFirstFrame!,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              gaplessPlayback: true,
            )
          else if (resolvedThumb != null && resolvedThumb.isNotEmpty)
            Image.network(
              resolvedThumb,
              fit: BoxFit.contain,
              filterQuality: FilterQuality.medium,
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isRasterGif) {
      final rawResolved = StickerService.resolveUrl(widget.item.resolvedUrl);
      final Widget gifWidget = Center(
        child: _wrapHeroIfNeeded(
          AspectRatio(
            aspectRatio: widget.item.aspectRatio,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (widget.item.thumbBase64 != null &&
                    widget.item.thumbBase64!.isNotEmpty)
                  BlurredMediaPlaceholder(
                    thumbBase64: widget.item.thumbBase64,
                    aspectRatio: widget.item.aspectRatio,
                    fit: BoxFit.contain,
                  ),
                ControlledAnimatedNetworkImage(
                  url: rawResolved,
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.medium,
                  isAnimatedWebpOrGif: true,
                  animate: widget.isActive,
                  errorBuilder: (_) => const Center(
                    child: iconoir.MediaImage(
                      color: Colors.white54,
                      width: 56,
                      height: 56,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      return gifWidget;
    }

    final ctrl = _controller;
    final bridgeState = widget.bridge?.state;

    if (ctrl == null || !ctrl.value.isInitialized) {
      return Center(
        child: _wrapHeroIfNeeded(
          Stack(
            alignment: Alignment.center,
            children: [
              _buildPosterFallback(),
              if (bridgeState != null)
                ValueListenableBuilder<TheavVideoPlaybackState>(
                  valueListenable: bridgeState,
                  builder: (_, s, __) {
                    if (s.errorMessage != null) {
                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xCC101218),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: const iconoir.WarningCircle(
                          color: Colors.white70,
                          width: 34,
                          height: 34,
                        ),
                      );
                    }
                    return _MatteLoadingRing(progress: s.downloadFraction);
                  },
                )
              else
                const _MatteLoadingRing(),
            ],
          ),
        ),
      );
    }

    final double ar =
        ctrl.value.aspectRatio > 0.1 ? ctrl.value.aspectRatio : widget.item.aspectRatio;

    return Center(
      child: _wrapHeroIfNeeded(
        AspectRatio(
          aspectRatio: ar,
          child: Stack(
            fit: StackFit.expand,
            children: [
              VideoPlayer(ctrl),
              if (bridgeState != null)
                ValueListenableBuilder<TheavVideoPlaybackState>(
                  valueListenable: bridgeState,
                  builder: (_, s, __) {
                    if (s.isBuffering) {
                      return const Center(child: _MatteLoadingRing());
                    }
                    if (!s.isPlaying && !_isGifLoop) {
                      return Center(
                        child: GestureDetector(
                          onTap: _togglePlayPause,
                          child: Container(
                            width: 66,
                            height: 66,
                            decoration: BoxDecoration(
                              color: const Color(0xB3101218),
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.14),
                                width: 1.0,
                              ),
                            ),
                            alignment: Alignment.center,
                            child: const iconoir.Play(
                              color: Colors.white,
                              width: 30,
                              height: 30,
                            ),
                          ),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _MatteLoadingRing extends StatelessWidget {
  final double? progress;

  const _MatteLoadingRing({this.progress});

  @override
  Widget build(BuildContext context) {
    final p = progress;
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: const Color(0xB3101218),
        shape: BoxShape.circle,
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.12),
          width: 1.0,
        ),
      ),
      alignment: Alignment.center,
      child: SizedBox(
        width: 28,
        height: 28,
        child: CircularProgressIndicator(
          value: (p != null && p > 0.01 && p < 1.0) ? p : null,
          strokeWidth: 2.6,
          color: Colors.white,
          backgroundColor: Colors.white.withValues(alpha: 0.22),
        ),
      ),
    );
  }
}
