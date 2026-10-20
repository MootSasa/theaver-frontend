import 'package:flutter/material.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:rive/rive.dart';
import '../../services/media_cache_manager.dart';

/// Interactive Telegram-style download button for media files.
/// Displays downloaded byte progress (e.g. "4.2 MB / 400 MB" or "400 MB"),
/// animated circular progress, and cancel button during active download with
/// smooth Rive download-to-cross icon morphing.
class MediaDownloadButton extends StatefulWidget {
  final String url;
  final int? fileSize;
  final bool isVideo;
  final bool autoDownload;
  final VoidCallback? onDownloaded;
  final VoidCallback? onPlayVideo;

  const MediaDownloadButton({
    Key? key,
    required this.url,
    this.fileSize,
    this.isVideo = false,
    this.autoDownload = false,
    this.onDownloaded,
    this.onPlayVideo,
  }) : super(key: key);

  @override
  State<MediaDownloadButton> createState() => MediaDownloadButtonState();
}

class MediaDownloadButtonState extends State<MediaDownloadButton> {
  bool _isDownloaded = false;
  bool _isDownloading = false;
  double _progress = 0.0;
  String _progressByteText = '';

  ValueNotifier<DownloadByteProgress>? _byteNotifier;
  Artboard? _artboard;
  RiveAnimationController? _currentRiveController;
  String _currentAnimName = 'idle_download';

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  void _onRiveInit(Artboard artboard) {
    _artboard = artboard;
    final initialAnim = _isDownloading ? 'idle_cross' : 'idle_download';
    _setRiveAnimation(initialAnim);
  }

  void _setRiveAnimation(String animationName) {
    if (_artboard == null) return;
    if (_currentRiveController != null) {
      _artboard!.removeController(_currentRiveController!);
      _currentRiveController!.dispose();
      _currentRiveController = null;
    }
    _currentAnimName = animationName;
    _currentRiveController = SimpleAnimation(animationName);
    _artboard!.addController(_currentRiveController!);
  }

  void _triggerMorph(bool toDownloading) {
    if (_artboard == null) return;
    if (_currentRiveController != null) {
      _artboard!.removeController(_currentRiveController!);
      _currentRiveController!.dispose();
      _currentRiveController = null;
    }
    final animName = toDownloading ? 'download_to_cross' : 'cross_to_download';
    final targetIdle = toDownloading ? 'idle_cross' : 'idle_download';
    _currentAnimName = animName;

    _currentRiveController = OneShotAnimation(
      animName,
      autoplay: true,
      onStop: () {
        if (mounted && _currentAnimName == animName) {
          _setRiveAnimation(targetIdle);
        }
      },
    );
    _artboard!.addController(_currentRiveController!);
  }

  @override
  void didUpdateWidget(covariant MediaDownloadButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.url != widget.url ||
        oldWidget.autoDownload != widget.autoDownload) {
      _checkStatus();
    }
  }

  Future<void> _checkStatus() async {
    final cached = await MediaCacheManager.instance.getCachedFile(widget.url);
    if (!mounted) return;
    if (cached != null) {
      setState(() {
        _isDownloaded = true;
        _isDownloading = false;
        _progress = 1.0;
        _progressByteText = '';
      });
      return;
    }

    final downloading = MediaCacheManager.instance.isDownloading(widget.url);
    _byteNotifier?.removeListener(_onProgressListener);
    _byteNotifier = MediaCacheManager.instance.getByteProgressNotifier(widget.url);
    _byteNotifier?.addListener(_onProgressListener);

    // Also check if partial file exists on disk to show saved progress when paused
    final partial = await MediaCacheManager.instance.getPartialProgress(
      widget.url,
      totalSize: widget.fileSize,
    );

    if (!mounted) return;

    final currentFraction = downloading
        ? (_byteNotifier?.value.fraction ?? 0.0)
        : (partial?.fraction ?? _byteNotifier?.value.fraction ?? 0.0);
    final currentText = downloading
        ? (_byteNotifier?.value.formatProgress() ?? '')
        : (partial?.formatProgress() ?? _byteNotifier?.value.formatProgress() ?? '');

    setState(() {
      _isDownloaded = false;
      _isDownloading = downloading;
      _progress = currentFraction;
      _progressByteText = currentText;
    });

    if (downloading) {
      _setRiveAnimation('idle_cross');
    } else {
      _setRiveAnimation('idle_download');
      if (widget.autoDownload &&
          partial == null &&
          !MediaCacheManager.instance.wasCancelledByUser(widget.url)) {
        _startDownload();
      }
    }
  }

  void _onProgressListener() {
    if (!mounted) return;
    final bp = _byteNotifier?.value;
    if (bp == null) return;

    final val = bp.fraction;
    final downloading = val > 0.0 && val < 1.0 && MediaCacheManager.instance.isDownloading(widget.url);

    if (_isDownloading != downloading) {
      _triggerMorph(downloading);
    }

    setState(() {
      _progress = val;
      _progressByteText = bp.formatProgress();
      _isDownloading = downloading;
      if (val >= 1.0) {
        _isDownloaded = true;
        _progressByteText = '';
        widget.onDownloaded?.call();
      }
    });
  }

  @override
  void dispose() {
    _byteNotifier?.removeListener(_onProgressListener);
    _currentRiveController?.dispose();
    super.dispose();
  }

  void handleTap() {
    if (_isDownloading) {
      _cancelDownload();
    } else if (_isDownloaded && widget.isVideo) {
      widget.onPlayVideo?.call();
    } else if (!_isDownloaded) {
      _startDownload();
    }
  }

  Future<void> _startDownload() async {
    if (_isDownloading) return;
    setState(() {
      _isDownloading = true;
      if (_progress <= 0.0) _progress = 0.01;
    });
    _triggerMorph(true);

    final file = await MediaCacheManager.instance.downloadMedia(
      widget.url,
      expectedTotalSize: widget.fileSize,
      onProgress: (p) {
        if (mounted) {
          setState(() {
            _progress = p;
          });
        }
      },
      onByteProgress: (bp) {
        if (mounted) {
          setState(() {
            _progress = bp.fraction;
            _progressByteText = bp.formatProgress();
          });
        }
      },
    );

    if (!mounted) return;
    if (file != null) {
      setState(() {
        _isDownloaded = true;
        _isDownloading = false;
        _progress = 1.0;
        _progressByteText = '';
      });
      widget.onDownloaded?.call();
    } else {
      setState(() {
        _isDownloading = false;
      });
      _triggerMorph(false);
    }
  }

  void _cancelDownload() {
    MediaCacheManager.instance.cancelDownload(widget.url, byUser: true);
    if (mounted) {
      setState(() {
        _isDownloading = false;
      });
      _triggerMorph(false);
    }
  }

  Widget _buildIcon() {
    if (_isDownloaded && widget.isVideo) {
      return const iconoir.Play(
        color: Colors.white,
        width: 18,
        height: 18,
      );
    }

    return SizedBox(
      width: 20,
      height: 20,
      child: RiveAnimation.asset(
        'assets/animations/download_to_cross.riv',
        fit: BoxFit.contain,
        onInit: _onRiveInit,
        placeHolder: _isDownloading
            ? const iconoir.Xmark(
                color: Colors.white,
                width: 14,
                height: 14,
              )
            : const iconoir.ArrowDown(
                color: Colors.white,
                width: 18,
                height: 18,
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isDownloaded && !widget.isVideo) {
      // Photo is downloaded; no button needed over it
      return const SizedBox.shrink();
    }

    // Determine label: "4.2 MB / 400 MB" during download/paused, or total size "400 MB"
    String displayText = '';
    if (_isDownloading || _progress > 0.0) {
      if (_progressByteText.isNotEmpty) {
        displayText = _progressByteText;
      } else if (widget.fileSize != null && widget.fileSize! > 0) {
        final rec = (_progress * widget.fileSize!).round();
        displayText =
            '${MediaCacheManager.formatBytes(rec)} / ${MediaCacheManager.formatBytes(widget.fileSize!)}';
      }
    } else if (widget.fileSize != null && widget.fileSize! > 0) {
      displayText = MediaCacheManager.formatBytes(widget.fileSize!);
    }

    return Center(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: handleTap,
          borderRadius: BorderRadius.circular(30),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.55),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.2),
                width: 0.8,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 32,
                  height: 32,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (_isDownloading || (_progress > 0.0 && !_isDownloaded))
                        CircularProgressIndicator(
                          value: _progress.clamp(0.05, 1.0),
                          strokeWidth: 2.5,
                          valueColor:
                              const AlwaysStoppedAnimation<Color>(Colors.white),
                          backgroundColor:
                              Colors.white.withValues(alpha: 0.2),
                        ),
                      _buildIcon(),
                    ],
                  ),
                ),
                if (displayText.isNotEmpty && !_isDownloaded) ...[
                  const SizedBox(width: 6),
                  Text(
                    displayText,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.2,
                    ),
                  ),
                  const SizedBox(width: 4),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
