import 'package:flutter/material.dart';

import '../../models/media_album.dart';
import '../../models/theav_media_item.dart';
import '../media_viewer/theav_media_viewer.dart';

/// Fullscreen multi-media viewer for grouped albums powered by [TheavMediaViewer].
class MediaAlbumViewer extends StatelessWidget {
  final MediaAlbum album;
  final int initialIndex;
  final bool hasProtectedContent;

  const MediaAlbumViewer({
    super.key,
    required this.album,
    this.initialIndex = 0,
    this.hasProtectedContent = false,
  });

  @override
  Widget build(BuildContext context) {
    final List<TheavMediaItem> items = album.items
        .map(
          (item) => TheavMediaItem.fromMessage(
            item.message,
            fallbackCaption: album.caption,
            fallbackEntities: album.entities,
            hasProtectedContent: hasProtectedContent,
          ),
        )
        .toList(growable: false);

    return TheavMediaViewer(
      items: items,
      initialIndex: initialIndex,
    );
  }
}
