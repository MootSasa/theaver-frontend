import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:video_player/video_player.dart';
import 'package:visibility_detector/visibility_detector.dart';
import '../../services/media_cache_manager.dart';
import '../../services/video_note_playback_service.dart';
import 'message_status_widget.dart';

/// Static LRU pool for caching active video note controllers to avoid re-initialization
/// and loading spinners when scrolling back and forth.
class VideoNoteControllerPool {
  static final Map<String, VideoPlayerController> _pool = {};
  static final List<String> _order = [];
  static const int _maxControllers = 12;

  static VideoPlayerController? get(String url) => _pool[url];

  static void put(String url, VideoPlayerController controller) {
    if (_pool.containsKey(url)) return;
    if (_order.length >= _maxControllers) {
      final oldest = _order.removeAt(0);
      final oldCtrl = _pool.remove(oldest);
      try {
        oldCtrl?.dispose();
      } catch (_) {}
    }
    _pool[url] = controller;
    _order.add(url);
  }
}

/// Круглое видеосообщение («кружочек») в стиле Telegram.
/// - Автовоспроизведение без звука (mute, loop) при появлении в чате.
/// - Тап → воспроизведение со звуком с начала, плавное увеличение размера.
/// - Повторный тап во время звука → пауза / продолжение.
/// - Плавный (60 FPS) круговой индикатор прогресса (progress ring) по контуру.
/// - При завершении воспроизведения автоматически переходит к следующему кружку.
/// - При уходе из поля зрения появляется плавающее окно (PiP) в углу экрана.
/// - Отсутствие мерцания и повторной анимации загрузки при скролле (KeepAlive + Cache Pool).
class VideoMessageWidget extends StatefulWidget {
  final String videoUrl;
  final String? messageId;
  final double size;
  final String? senderAvatarUrl;
  final Duration? duration;
  final String? thumbUrl;
  final String? thumbBase64;
  final int? fileSize;
  final bool isMe;
  final bool isRead;
  final int sendStatus;
  final String? timeText;
  final String? senderName;
  final VoidCallback? onRetry;

  const VideoMessageWidget({
    Key? key,
    required this.videoUrl,
    this.messageId,
    this.size = 230.0,
    this.senderAvatarUrl,
    this.duration,
    this.thumbUrl,
    this.thumbBase64,
    this.fileSize,
    this.isMe = false,
    this.isRead = false,
    this.sendStatus = 1,
    this.timeText,
    this.senderName,
    this.onRetry,
  }) : super(key: key);

  @override
  State<VideoMessageWidget> createState() => _VideoMessageWidgetState();
}

class _VideoMessageWidgetState extends State<VideoMessageWidget>
    with AutomaticKeepAliveClientMixin {
  VideoPlayerController? _controller;
  int _initSession = 0;
  bool _hasError = false;
  bool _isPlayingWithSound = false;
  bool get _isPausedWithSound =>
      _isPlayingWithSound && !(_controller?.value.isPlaying ?? false);
  double _prevProgress = 0.0;
  final VideoNotePlaybackService _playbackService = VideoNotePlaybackService();

  bool _isCached = false;
  bool _isDownloading = false;
  double _downloadProgress = 0.0;
  ValueNotifier<double>? _progressNotifier;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _playbackService.addListener(_onPlaybackServiceUpdate);
    _initializeVideoPlayer();
  }

  @override
  void didUpdateWidget(VideoMessageWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _initSession++;
      _detachProgressListener();
      _controller?.removeListener(_onVideoUpdate);
      _controller = null;
      _hasError = false;
      _isPlayingWithSound = false;
      _prevProgress = 0.0;
      _isCached = false;
      _isDownloading = false;
      _initializeVideoPlayer();
    }
  }

  void _onPlaybackServiceUpdate() {
    if (!mounted || widget.messageId == null) return;
    final activeId = _playbackService.activeMessageId;
    final isThisActive = activeId == widget.messageId;
    if (isThisActive) {
      if (!_isPlayingWithSound && _controller != null && _controller!.value.isInitialized) {
        final isAlreadyPlaying = _controller!.value.isPlaying;
        _startSoundPlayback(restart: !isAlreadyPlaying);
      } else {
        setState(() {});
      }
    } else {
      if (_isPlayingWithSound) {
        _revertToMutedLoop();
      }
    }
  }

  void _detachProgressListener() {
    _progressNotifier?.removeListener(_onDownloadProgress);
    _progressNotifier = null;
  }

  void _onDownloadProgress() {
    if (!mounted || _progressNotifier == null) return;
    setState(() {
      _downloadProgress = _progressNotifier!.value;
    });
  }

  Future<void> _initializeVideoPlayer() async {
    final currentSession = ++_initSession;
    if (widget.videoUrl.isEmpty) {
      if (mounted && currentSession == _initSession) {
        setState(() => _hasError = true);
      }
      return;
    }

    // 1. Check Controller Pool for instantaneous zero-delay restore
    final cached = VideoNoteControllerPool.get(widget.videoUrl);
    if (cached != null && cached.value.isInitialized) {
      _controller = cached;
      _controller!.addListener(_onVideoUpdate);
      _isCached = true;
      final isCurrentlyActive = (widget.messageId != null && _playbackService.activeMessageId == widget.messageId) ||
          _playbackService.activeController == cached;
      if (isCurrentlyActive) {
        _isPlayingWithSound = true;
      }
      if (mounted) {
        setState(() {
          _hasError = false;
        });
      }
      if (!_controller!.value.isPlaying) {
        _controller!.play();
      }
      return;
    }

    final url = widget.videoUrl;
    final uri = Uri.tryParse(url);
    final isNetwork = uri != null && (uri.scheme == 'http' || uri.scheme == 'https');

    if (!isNetwork) {
      final filePath = url.startsWith('file://') ? Uri.parse(url).toFilePath() : url;
      final file = File(filePath);
      if (!await file.exists()) {
        debugPrint('[VideoMessageWidget] File does not exist: $filePath');
        final baseName = p.basename(filePath);
        try {
          final cacheDir = await MediaCacheManager.instance.getMediaCacheDirectory();
          final candidate = File(p.join(cacheDir.path, baseName));
          if (await candidate.exists()) {
            _isCached = true;
            await _initControllerFromFile(candidate, currentSession);
            return;
          }
        } catch (_) {}

        if (mounted && currentSession == _initSession) {
          setState(() => _hasError = true);
        }
        return;
      }
      _isCached = true;
      await _initControllerFromFile(file, currentSession);
      return;
    }

    // Check disk cache
    final cachedDiskFile = await MediaCacheManager.instance.getCachedFile(url);
    if (cachedDiskFile != null && await cachedDiskFile.exists()) {
      _isCached = true;
      await _initControllerFromFile(cachedDiskFile, currentSession);
      return;
    }

    _isCached = false;

    // Check if in-flight download exists
    if (MediaCacheManager.instance.isDownloading(url)) {
      _detachProgressListener();
      _progressNotifier = MediaCacheManager.instance.getProgressNotifier(url);
      _progressNotifier?.addListener(_onDownloadProgress);
      if (mounted && currentSession == _initSession) {
        setState(() {
          _isDownloading = true;
          _downloadProgress = _progressNotifier?.value ?? 0.0;
        });
      }
      return;
    }

    // Check auto-download policy
    final autoDownload = widget.isMe || MediaCacheManager.instance.shouldAutoDownload(
      messageType: 'video',
      fileSize: widget.fileSize,
    );

    if (autoDownload) {
      _startDownload(currentSession);
    } else {
      if (mounted && currentSession == _initSession) {
        setState(() {
          _isDownloading = false;
        });
      }
    }
  }

  Future<void> _startDownload([int? session]) async {
    final currentSession = session ?? _initSession;
    if (_isDownloading) return;
    setState(() {
      _isDownloading = true;
      _downloadProgress = 0.0;
    });

    _detachProgressListener();
    _progressNotifier = MediaCacheManager.instance.getProgressNotifier(widget.videoUrl);
    _progressNotifier?.addListener(_onDownloadProgress);

    final file = await MediaCacheManager.instance.downloadFile(widget.videoUrl);
    if (!mounted || currentSession != _initSession) return;

    _detachProgressListener();
    if (file != null && await file.exists()) {
      setState(() {
        _isDownloading = false;
        _isCached = true;
      });
      await _initControllerFromFile(file, currentSession);
    } else {
      setState(() {
        _isDownloading = false;
        _isCached = false;
      });
    }
  }

  void _cancelDownload() {
    MediaCacheManager.instance.cancelDownload(widget.videoUrl);
    _detachProgressListener();
    if (mounted) {
      setState(() {
        _isDownloading = false;
      });
    }
  }

  Future<void> _initControllerFromFile(File file, int session) async {
    try {
      final controller = VideoPlayerController.file(file);
      await controller.initialize();
      await controller.setLooping(true);
      await controller.setVolume(0.0);

      if (!mounted || session != _initSession) {
        await controller.dispose();
        return;
      }

      _controller = controller;
      _controller!.addListener(_onVideoUpdate);
      VideoNoteControllerPool.put(widget.videoUrl, controller);

      final isCurrentlyActive = (widget.messageId != null && _playbackService.activeMessageId == widget.messageId) ||
          _playbackService.activeController == controller;
      if (isCurrentlyActive) {
        _isPlayingWithSound = true;
        await controller.setLooping(false);
        await controller.setVolume(1.0);
      }

      setState(() {
        _hasError = false;
      });
      _controller!.play();
    } catch (e) {
      debugPrint('[VideoMessageWidget] Controller init failed: $e');
      if (mounted && session == _initSession) {
        setState(() => _hasError = true);
      }
    }
  }

  void _onVideoUpdate() {
    if (!mounted) return;
    if (!_isPlayingWithSound) return;

    final controller = _controller;
    if (controller != null && controller.value.isInitialized) {
      final position = controller.value.position;
      final duration = controller.value.duration;

      final bool isCompleted = (duration.inMilliseconds > 0) &&
          (position >= duration || (!controller.value.isPlaying && position >= duration - const Duration(milliseconds: 150)));
      if (isCompleted) {
        _revertToMutedLoop();
        if (widget.messageId != null && _playbackService.activeMessageId == widget.messageId) {
          _playbackService.onVideoCompleted(widget.messageId!);
        }
        return;
      }
    }

    setState(() {});
  }

  void _startSoundPlayback({bool restart = true}) {
    if (_controller == null || !_controller!.value.isInitialized) return;
    if (restart) {
      _controller?.pause();
      _controller?.seekTo(Duration.zero);
      _prevProgress = 0.0;
    }
    _controller?.setLooping(false);
    _controller?.setVolume(1.0);
    if (!(_controller?.value.isPlaying ?? false)) {
      _controller?.play();
    }
    setState(() {
      _isPlayingWithSound = true;
    });
  }

  void _revertToMutedLoop() {
    if (_controller == null || !_controller!.value.isInitialized) return;
    _controller?.seekTo(Duration.zero);
    _controller?.setLooping(true);
    _controller?.setVolume(0.0);
    if (!_controller!.value.isPlaying) {
      _controller?.play();
    }
    setState(() {
      _isPlayingWithSound = false;
      _prevProgress = 0.0;
    });
  }

  @override
  void dispose() {
    _initSession++;
    _playbackService.removeListener(_onPlaybackServiceUpdate);
    if (widget.messageId != null) {
      _playbackService.setInView(widget.messageId!, false);
    }
    _controller?.removeListener(_onVideoUpdate);
    // Note: Controller is preserved in VideoNoteControllerPool for instant scroll restore
    _controller = null;
    super.dispose();
  }

  void _handleTap() {
    if (!_isCached) {
      if (_isDownloading) {
        _cancelDownload();
      } else {
        _startDownload();
      }
      return;
    }

    if (_controller == null || !_controller!.value.isInitialized) return;

    if (_isPlayingWithSound) {
      _playbackService.togglePlayPause();
    } else {
      if (widget.messageId != null) {
        _playbackService.setActivePlayback(
          messageId: widget.messageId!,
          videoUrl: widget.videoUrl,
          controller: _controller!,
          senderName: widget.isMe ? null : widget.senderName,
          initialInView: true,
        );
      }
      if (!_isPlayingWithSound) {
        _startSoundPlayback();
      }
    }
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(1, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  Widget _buildDurationPill(String durationText) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _isPlayingWithSound ? Icons.volume_up_rounded : Icons.play_arrow_rounded,
            size: 13,
            color: Colors.white.withValues(alpha: 0.85),
          ),
          const SizedBox(width: 3),
          Text(
            durationText,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimePill(BuildContext context) {
    final hasTime = widget.timeText != null && widget.timeText!.isNotEmpty;
    if (!hasTime && !widget.isMe) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.15),
          width: 0.8,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (hasTime)
            Text(
              widget.timeText!,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          if (widget.isMe) ...[
            if (hasTime) const SizedBox(width: 4),
            if (widget.sendStatus == 0)
              const SizedBox(
                width: 10,
                height: 10,
                child: CircularProgressIndicator(
                  strokeWidth: 1.2,
                  color: Colors.white70,
                ),
              )
            else if (widget.sendStatus == 2)
              GestureDetector(
                onTap: widget.onRetry,
                child: const iconoir.WarningCircle(
                  width: 13,
                  height: 13,
                  color: Colors.redAccent,
                ),
              )
            else
              MessageStatusWidget(
                isRead: widget.isRead,
                isOutgoing: widget.isMe,
                colorOverride: Colors.white,
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);

    final screenWidth = MediaQuery.of(context).size.width;
    // Passive size is slightly smaller (~188px), expands to ~260px on active sound playback
    final double passiveDiameter = math.min(192.0, screenWidth * 0.52);
    final double activeDiameter = math.min(265.0, screenWidth * 0.74);
    final double effectiveDiameter = _isPlayingWithSound ? activeDiameter : passiveDiameter;

    final isInitialized = _controller != null && _controller!.value.isInitialized;
    final duration = _controller?.value.duration ?? widget.duration ?? Duration.zero;
    final position = _controller?.value.position ?? Duration.zero;

    final double progress;
    if (duration.inMilliseconds > 0 && isInitialized) {
      progress = (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);
    } else {
      progress = 0.0;
    }

    final animatedBeginProgress = (progress < _prevProgress) ? 0.0 : _prevProgress;
    _prevProgress = progress;

    final String durationText;
    if (_isPlayingWithSound && isInitialized) {
      durationText = _formatDuration(duration - position);
    } else if (duration.inSeconds > 0) {
      durationText = _formatDuration(duration);
    } else if (widget.duration != null && widget.duration!.inSeconds > 0) {
      durationText = _formatDuration(widget.duration!);
    } else {
      durationText = '0:00';
    }

    final bool isFloatingActive = _playbackService.isFloating &&
        widget.messageId != null &&
        _playbackService.activeMessageId == widget.messageId;

    return VisibilityDetector(
      key: Key('vnote_${widget.messageId ?? widget.videoUrl}'),
      onVisibilityChanged: (info) {
        final inView = info.visibleFraction >= 0.15;
        if (widget.messageId != null) {
          _playbackService.setInView(widget.messageId!, inView);
        }
        // Pause muted background video decoding when scrolled off-screen
        // to prevent multiple concurrent hardware decoders from degrading scroll performance.
        // Active playback videos (with sound or in floating PiP) must NEVER be paused by visibility detector.
        final bool isActiveVideo = (widget.messageId != null && _playbackService.activeMessageId == widget.messageId) ||
            (_controller != null && _playbackService.activeController == _controller) ||
            _isPlayingWithSound;

        if (!isActiveVideo && _controller != null && _controller!.value.isInitialized) {
          if (!inView && _controller!.value.isPlaying) {
            _controller!.pause();
          } else if (inView && !_controller!.value.isPlaying && !_hasError) {
            _controller!.play();
          }
        }
      },
      child: RepaintBoundary(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            GestureDetector(
              onTap: _handleTap,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                width: effectiveDiameter,
                height: effectiveDiameter,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.28),
                      blurRadius: 12,
                      spreadRadius: 1,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    // 1. Circular Video / Placeholder / Error (No spinning loader!)
                    ClipOval(
                      child: SizedBox(
                        width: effectiveDiameter,
                        height: effectiveDiameter,
                        child: _hasError
                            ? Container(
                                color: Colors.black87,
                                child: Center(
                                  child: widget.onRetry != null
                                      ? IconButton(
                                          icon: const Icon(Icons.refresh, color: Colors.white70, size: 36),
                                          onPressed: () {
                                            setState(() {
                                              _hasError = false;
                                            });
                                            _initializeVideoPlayer();
                                          },
                                        )
                                      : const Icon(Icons.error_outline, color: Colors.white70, size: 36),
                                ),
                              )
                            : (!_isCached || !isInitialized)
                                ? _buildPlaceholder(effectiveDiameter)
                                 : isFloatingActive
                                     ? Container(
                                         color: const Color(0xFF1C1C1E),
                                         child: const Center(
                                           child: Icon(
                                             Icons.picture_in_picture_alt_rounded,
                                             color: Colors.white54,
                                             size: 38,
                                           ),
                                         ),
                                       )
                                     : FittedBox(
                                         fit: BoxFit.cover,
                                         child: SizedBox(
                                           width: _controller!.value.size.width > 0
                                               ? _controller!.value.size.width
                                               : effectiveDiameter,
                                           height: _controller!.value.size.height > 0
                                               ? _controller!.value.size.height
                                               : effectiveDiameter,
                                           child: VideoPlayer(_controller!),
                                         ),
                                       ),
                      ),
                    ),

                    // 2. Play / Pause Overlay Icon when paused with sound
                    if (_isPlayingWithSound && _isPausedWithSound)
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.55),
                          shape: BoxShape.circle,
                        ),
                        child: const Center(
                          child: Icon(Icons.play_arrow, color: Colors.white, size: 28),
                        ),
                      ),

                    // 3. Smooth Circular Progress Ring around edge (Active during sound playback)
                    if (_isPlayingWithSound && isInitialized)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: TweenAnimationBuilder<double>(
                            tween: Tween<double>(begin: animatedBeginProgress, end: progress),
                            duration: const Duration(milliseconds: 250),
                            curve: Curves.linear,
                            builder: (context, smoothProgress, _) {
                              return CustomPaint(
                                painter: _CircularProgressPainter(
                                  progress: smoothProgress,
                                  color: Colors.white,
                                  strokeWidth: 3.0,
                                ),
                              );
                            },
                          ),
                        ),
                      ),

                    // 4. Subtle Outer Border
                    Positioned.fill(
                      child: IgnorePointer(
                        child: Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 1.2,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 5.0),
            AnimatedContainer(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              width: effectiveDiameter,
              padding: const EdgeInsets.symmetric(horizontal: 4.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildDurationPill(durationText),
                  _buildTimePill(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlaceholder(double diameter) {
    Widget? baseImage;
    if (widget.thumbBase64 != null && widget.thumbBase64!.isNotEmpty) {
      try {
        final bytes = base64Decode(widget.thumbBase64!);
        baseImage = Image.memory(
          bytes,
          fit: BoxFit.cover,
          width: diameter,
          height: diameter,
        );
      } catch (_) {}
    } else if (widget.thumbUrl != null && widget.thumbUrl!.isNotEmpty) {
      baseImage = CachedNetworkImage(
        imageUrl: widget.thumbUrl!,
        fit: BoxFit.cover,
        width: diameter,
        height: diameter,
      );
    }

    return Stack(
      alignment: Alignment.center,
      children: [
        if (baseImage != null)
          ClipOval(
            child: ImageFiltered(
              imageFilter: ui.ImageFilter.blur(sigmaX: 16, sigmaY: 16),
              child: Transform.scale(
                scale: 1.15,
                child: SizedBox(
                  width: diameter,
                  height: diameter,
                  child: baseImage,
                ),
              ),
            ),
          )
        else
          Container(
            width: diameter,
            height: diameter,
            color: const Color(0xFF1C1C1E),
          ),

        // Dark dimming overlay
        Container(
          width: diameter,
          height: diameter,
          color: Colors.black.withValues(alpha: 0.35),
        ),

        // Center Action Button (Download / Progress / Initializing)
        Container(
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.65),
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.3),
              width: 1.5,
            ),
          ),
          child: Center(
            child: _isDownloading
                ? Stack(
                    alignment: Alignment.center,
                    children: [
                      SizedBox(
                        width: 32,
                        height: 32,
                        child: CircularProgressIndicator(
                          value: _downloadProgress > 0.05 ? _downloadProgress : null,
                          strokeWidth: 2.5,
                          valueColor: const AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                      const Icon(
                        Icons.close_rounded,
                        size: 18,
                        color: Colors.white,
                      ),
                    ],
                  )
                : !_isCached
                    ? Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.arrow_downward_rounded,
                            size: 22,
                            color: Colors.white,
                          ),
                          if (widget.fileSize != null && widget.fileSize! > 0)
                            Text(
                              MediaCacheManager.formatBytes(widget.fileSize!),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      )
                    : const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.0,
                          valueColor: AlwaysStoppedAnimation<Color>(Colors.white70),
                        ),
                      ),
          ),
        ),
      ],
    );
  }
}

class _CircularProgressPainter extends CustomPainter {
  final double progress;
  final Color color;
  final double strokeWidth;

  _CircularProgressPainter({
    required this.progress,
    required this.color,
    required this.strokeWidth,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (progress <= 0.0) return;

    final paint = Paint()
      ..color = color
      ..strokeWidth = strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    const startAngle = -math.pi / 2; // 12 o'clock
    final sweepAngle = 2 * math.pi * progress.clamp(0.0, 1.0);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      startAngle,
      sweepAngle,
      false,
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _CircularProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.color != color ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
