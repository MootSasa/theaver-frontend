import 'dart:io' show File;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:photo_view/photo_view.dart';
import '../../config/app_config.dart';
import '../../services/media_cache_manager.dart';

/// Full-screen photo viewer with pinch-to-zoom, swipe-to-dismiss, and disk cache support
class FullscreenPhotoViewer extends StatefulWidget {
  final String url;
  final String? tag;
  final String? localFilePath;

  const FullscreenPhotoViewer({
    Key? key,
    required this.url,
    this.tag,
    this.localFilePath,
  }) : super(key: key);

  /// Open the viewer as a full-screen dialog
  static Future<void> open(
    BuildContext context,
    String url, {
    String? tag,
    String? localFilePath,
  }) {
    return Navigator.of(context).push(
      PageRouteBuilder(
        opaque: false,
        fullscreenDialog: true,
        transitionDuration: const Duration(milliseconds: 250),
        reverseTransitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, animation, secondaryAnimation) =>
            FullscreenPhotoViewer(url: url, tag: tag, localFilePath: localFilePath),
        transitionsBuilder: (context, animation, secondaryAnimation, child) {
          return FadeTransition(
            opacity: animation,
            child: child,
          );
        },
      ),
    );
  }

  @override
  State<FullscreenPhotoViewer> createState() => _FullscreenPhotoViewerState();
}

class _FullscreenPhotoViewerState extends State<FullscreenPhotoViewer> {
  File? _cachedFile;

  @override
  void initState() {
    super.initState();
    if (widget.localFilePath != null && widget.localFilePath!.isNotEmpty) {
      final f = File(widget.localFilePath!);
      if (f.existsSync()) {
        _cachedFile = f;
      }
    }
    if (_cachedFile == null) {
      _checkLocalCache();
    }
  }

  Future<void> _checkLocalCache() async {
    final f = await MediaCacheManager.instance.getCachedFile(widget.url);
    if (f != null && mounted) {
      setState(() => _cachedFile = f);
    }
  }

  ImageProvider _imageProvider() {
    if (_cachedFile != null && _cachedFile!.existsSync()) {
      return FileImage(_cachedFile!);
    }

    final url = widget.url;

    // Support data: URLs (base64)
    if (url.startsWith('data:')) {
      try {
        final commaIndex = url.indexOf(',');
        final base64Str = url.substring(commaIndex + 1);
        final bytes = Uri.parse('data:;base64,$base64Str')
            .data!
            .contentAsBytes();
        return MemoryImage(bytes);
      } catch (_) {
        return CachedNetworkImageProvider(url);
      }
    }
    if (url.startsWith('file://')) {
      return FileImage(File(Uri.parse(url).toFilePath()));
    }
    if (url.startsWith('/') && !url.startsWith('//')) {
      return FileImage(File(url));
    }

    final resolved = AppConfig.resolveMediaUrl(url) ?? url;
    return CachedNetworkImageProvider(resolved);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.black.withValues(alpha: 0.5),
        elevation: 0,
        leading: IconButton(
          icon: const iconoir.Xmark(color: Colors.white, width: 24, height: 24),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: GestureDetector(
        onVerticalDragEnd: (details) {
          // Swipe down to dismiss
          if (details.primaryVelocity != null && details.primaryVelocity! > 500) {
            Navigator.pop(context);
          }
        },
        child: PhotoView(
          imageProvider: _imageProvider(),
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3.0,
          heroAttributes: widget.tag != null ? PhotoViewHeroAttributes(tag: widget.tag!) : null,
          loadingBuilder: (context, event) => Center(
            child: CircularProgressIndicator(
              value: event?.cumulativeBytesLoaded != null &&
                      event?.expectedTotalBytes != null
                  ? event!.cumulativeBytesLoaded / event.expectedTotalBytes!
                  : null,
              color: Colors.white,
            ),
          ),
          errorBuilder: (context, error, stackTrace) => const Center(
            child: iconoir.MediaImage(color: Colors.white54, width: 64, height: 64),
          ),
        ),
      ),
    );
  }
}
