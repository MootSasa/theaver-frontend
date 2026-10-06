import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';
import '../../config/app_config.dart';

/// Реальная размытая миниатюра «кружка» (видеосообщения) размером с иконку для списка чатов.
class RoundVideoThumbnail extends StatefulWidget {
  final String? videoUrl;
  final double size;

  const RoundVideoThumbnail({
    Key? key,
    required this.videoUrl,
    this.size = 18.0,
  }) : super(key: key);

  @override
  State<RoundVideoThumbnail> createState() => _RoundVideoThumbnailState();
}

class _RoundVideoThumbnailState extends State<RoundVideoThumbnail> {
  File? _cachedThumbFile;
  VideoPlayerController? _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _loadThumbnail();
  }

  @override
  void didUpdateWidget(RoundVideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _controller?.dispose();
      _controller = null;
      _isInitialized = false;
      _cachedThumbFile = null;
      _loadThumbnail();
    }
  }

  Future<void> _loadThumbnail() async {
    final rawUrl = widget.videoUrl;
    if (rawUrl == null || rawUrl.isEmpty) return;

    try {
      // 1. Check if local .thumb.jpg exists directly for local path
      if (!rawUrl.startsWith('http://') && !rawUrl.startsWith('https://')) {
        final localPath =
            rawUrl.startsWith('file://') ? Uri.parse(rawUrl).toFilePath() : rawUrl;
        final directThumb = File('$localPath.thumb.jpg');
        if (await directThumb.exists()) {
          if (mounted) setState(() => _cachedThumbFile = directThumb);
          return;
        }
      }

      // 2. Check temporary directory for cached thumbnail by filename
      final uri = Uri.tryParse(rawUrl);
      final fileName = uri != null && uri.pathSegments.isNotEmpty
          ? uri.pathSegments.last
          : rawUrl.split(Platform.pathSeparator).last;

      if (fileName.isNotEmpty) {
        final tempDir = await getTemporaryDirectory();
        final candidate = File('${tempDir.path}/$fileName.thumb.jpg');
        if (await candidate.exists()) {
          if (mounted) setState(() => _cachedThumbFile = candidate);
          return;
        }

        // Also check if local video file exists in tempDir
        final localVideoCandidate = File('${tempDir.path}/$fileName');
        if (await localVideoCandidate.exists()) {
          final candidateThumb = File('${localVideoCandidate.path}.thumb.jpg');
          if (await candidateThumb.exists()) {
            if (mounted) setState(() => _cachedThumbFile = candidateThumb);
            return;
          }
        }
      }

      // 3. If no image file found, initialize lightweight VideoPlayerController to show first frame
      final resolvedUrl = AppConfig.resolveMediaUrl(rawUrl) ?? rawUrl;
      final resolvedUri = Uri.tryParse(resolvedUrl);

      VideoPlayerController controller;
      if (resolvedUri != null &&
          (resolvedUri.scheme == 'http' || resolvedUri.scheme == 'https')) {
        controller = VideoPlayerController.networkUrl(resolvedUri);
      } else {
        final filePath = resolvedUrl.startsWith('file://')
            ? Uri.parse(resolvedUrl).toFilePath()
            : resolvedUrl;
        final file = File(filePath);
        if (!await file.exists()) return;
        controller = VideoPlayerController.file(file);
      }

      await controller.initialize();
      await controller.setVolume(0.0);

      if (mounted) {
        setState(() {
          _controller = controller;
          _isInitialized = true;
        });
      } else {
        await controller.dispose();
      }
    } catch (e) {
      debugPrint('[RoundVideoThumbnail] Init note: $e');
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final size = widget.size;

    Widget previewContent;
    if (_cachedThumbFile != null) {
      previewContent = Image.file(
        _cachedThumbFile!,
        width: size,
        height: size,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _buildFallback(primary),
      );
    } else if (_isInitialized && _controller != null) {
      previewContent = FittedBox(
        fit: BoxFit.cover,
        child: SizedBox(
          width: _controller!.value.size.width > 0
              ? _controller!.value.size.width
              : size,
          height: _controller!.value.size.height > 0
              ? _controller!.value.size.height
              : size,
          child: VideoPlayer(_controller!),
        ),
      );
    } else {
      previewContent = _buildFallback(primary);
    }

    return SizedBox(
      width: size,
      height: size,
      child: ClipOval(
        child: Stack(
          alignment: Alignment.center,
          children: [
            // 1. Real Video Thumbnail blurred
            ImageFiltered(
              imageFilter: ImageFilter.blur(sigmaX: 1.5, sigmaY: 1.5),
              child: SizedBox(
                width: size,
                height: size,
                child: previewContent,
              ),
            ),

            // 2. Dark translucent tint for contrast
            Container(
              width: size,
              height: size,
              color: Colors.black.withValues(alpha: 0.25),
            ),

            // 3. Play Icon in the center
            Icon(
              Icons.play_arrow_rounded,
              size: size * 0.65,
              color: Colors.white,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFallback(Color primary) {
    return Container(
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            primary.withValues(alpha: 0.5),
            primary.withValues(alpha: 0.2),
          ],
        ),
      ),
    );
  }
}
