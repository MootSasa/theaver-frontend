import 'package:flutter/material.dart';

import '../../models/theav_media_item.dart';
import '../media_viewer/theav_media_viewer.dart';
import '../media_viewer/theav_media_viewer_route.dart';

/// Fullscreen photo viewer powered by [TheavMediaViewer].
class FullscreenPhotoViewer extends StatelessWidget {
  final String url;
  final String? tag;
  final String? localFilePath;
  final bool hasProtectedContent;

  const FullscreenPhotoViewer({
    super.key,
    required this.url,
    this.tag,
    this.localFilePath,
    this.hasProtectedContent = false,
  });

  static Future<void> open(
    BuildContext context,
    String url, {
    String? tag,
    String? localFilePath,
    bool hasProtectedContent = false,
  }) {
    if (url.isEmpty) return Future<void>.value();
    return Navigator.of(context, rootNavigator: true).push<void>(
      TheavMediaViewerRoute<void>(
        capturedThemes: InheritedTheme.capture(
          from: context,
          to: Navigator.of(context, rootNavigator: true).context,
        ),
        builder: (_) => FullscreenPhotoViewer(
          url: url,
          tag: tag,
          localFilePath: localFilePath,
          hasProtectedContent: hasProtectedContent,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final item = TheavMediaItem(
      id: 'photo_${tag ?? url}',
      kind: TheavMediaKind.photo,
      url: url,
      localFilePath: localFilePath,
      heroTag: tag ?? 'photo_$url',
      hasProtectedContent: hasProtectedContent,
    );
    return TheavMediaViewer(
      items: <TheavMediaItem>[item],
      initialIndex: 0,
    );
  }
}
