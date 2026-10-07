import '../services/chat_service.dart';

/// Single item within a media album
class MediaAlbumItem {
  final Message message;
  final int index;
  final int totalCount;

  const MediaAlbumItem({
    required this.message,
    required this.index,
    required this.totalCount,
  });

  String get id => message.id;
  String? get fileUrl => message.fileUrl;
  String get messageType => message.messageType;
  bool get isVideo =>
      messageType == 'video' ||
      (message.fileUrl != null &&
          (message.fileUrl!.endsWith('.mp4') ||
              message.fileUrl!.endsWith('.mov') ||
              message.fileUrl!.endsWith('.webm') ||
              message.fileUrl!.endsWith('.mkv')));

  Map<String, dynamic> get mediaPayload => message.mediaPayload ?? {};

  String? get thumbBase64 => mediaPayload['thumb_base64'] as String?;
  String? get thumbUrl => mediaPayload['thumb_url'] as String? ?? mediaPayload['thumbnail_url'] as String?;
  int? get width => (mediaPayload['width'] as num?)?.toInt();
  int? get height => (mediaPayload['height'] as num?)?.toInt();
  int? get duration => (mediaPayload['duration'] as num?)?.toInt();
  int? get fileSize => (mediaPayload['file_size'] as num?)?.toInt();

  double get aspectRatio {
    final w = width ?? 0;
    final h = height ?? 0;
    if (w > 0 && h > 0) {
      return (w / h).clamp(0.4, 2.5);
    }
    return 1.0;
  }
}

/// A collection of 2–10 photos/videos grouped together under a common grouped_id
class MediaAlbum {
  final String groupedId;
  final List<MediaAlbumItem> items;
  final Message primaryMessage;
  final String? caption;
  final List<MessageEntity> entities;

  MediaAlbum({
    required this.groupedId,
    required this.items,
    required this.primaryMessage,
    this.caption,
    this.entities = const [],
  });

  String get id => primaryMessage.id;
  String get senderId => primaryMessage.senderId;
  String get chatId => primaryMessage.chatId;
  String get createdAt => primaryMessage.createdAt;
  bool get isRead => primaryMessage.isRead;
  int get sendStatus => primaryMessage.sendStatus;
  bool get hasCaption => caption != null && caption!.trim().isNotEmpty;
}

/// Abstract representation of an item in the chat feed
abstract class FeedItem {
  String get id;
  String get createdAt;
}

/// A standalone single message
class FeedSingleItem extends FeedItem {
  final Message message;

  FeedSingleItem(this.message);

  @override
  String get id => message.id;

  @override
  String get createdAt => message.createdAt;
}

/// A grouped media album item containing 2-10 media messages
class FeedAlbumItem extends FeedItem {
  final MediaAlbum album;

  FeedAlbumItem(this.album);

  @override
  String get id => album.id;

  @override
  String get createdAt => album.createdAt;
}

/// Utility to group consecutive messages sharing the same grouped_id into MediaAlbums.
/// [isReversed] indicates if the feed is ordered newest first (index 0 is newest).
List<FeedItem> groupMessagesIntoFeedItems(
  List<Message> messages, {
  bool isReversed = true,
}) {
  if (messages.isEmpty) return const [];

  final seenIds = <String>{};
  final dedupedMessages = <Message>[];
  for (final m in messages) {
    if (seenIds.add(m.id)) {
      dedupedMessages.add(m);
    }
  }

  final List<FeedItem> result = [];
  int i = 0;

  while (i < dedupedMessages.length) {
    final current = dedupedMessages[i];
    final gid = current.groupedId;

    if (gid == null || gid.isEmpty) {
      result.add(FeedSingleItem(current));
      i++;
      continue;
    }

    // Collect all consecutive messages with the same groupedId
    final List<Message> group = [current];
    int j = i + 1;
    while (j < dedupedMessages.length && dedupedMessages[j].groupedId == gid) {
      group.add(dedupedMessages[j]);
      j++;
    }

    if (group.length == 1) {
      // Single message with groupedId is displayed as normal message
      result.add(FeedSingleItem(current));
      i = j;
      continue;
    }

    // When the feed is reversed (newest first), the group has messages in reverse order.
    // In albums, we want items in chronological order: oldest to newest.
    final orderedGroup = isReversed ? group.reversed.toList() : group;

    // Find caption and entities: the item that has non-empty text
    String? caption;
    List<MessageEntity> entities = const [];
    Message primary = group.first;

    for (final m in orderedGroup) {
      final content = m.content.trim();
      final isFilename = m.fileName != null && content == m.fileName;
      final isFileurl = m.fileUrl != null && content == m.fileUrl;
      if (content.isNotEmpty && !isFilename && !isFileurl) {
        caption = content;
        entities = m.entities;
        primary = m;
        break;
      }
    }

    final albumItems = List.generate(orderedGroup.length, (idx) {
      return MediaAlbumItem(
        message: orderedGroup[idx],
        index: idx,
        totalCount: orderedGroup.length,
      );
    });

    final album = MediaAlbum(
      groupedId: gid,
      items: albumItems,
      primaryMessage: primary,
      caption: caption,
      entities: entities,
    );

    result.add(FeedAlbumItem(album));
    i = j;
  }

  return result;
}
