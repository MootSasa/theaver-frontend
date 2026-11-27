import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/widgets.dart';

import '../config/app_config.dart';
import '../services/chat_service.dart';
import '../services/database/app_database.dart';
import '../utils/date_time_utils.dart';
import '../utils/image_utils.dart';

/// Media category rendered by [TheavMediaViewer].
enum TheavMediaKind {
  photo,
  video,
  gif,
  avatar,
}

/// Custom contextual action exposed in [TheavMediaViewer]'s overflow menu or bar.
class TheavMediaAction {
  final String id;
  final String label;
  final IconData? icon;
  final bool isDestructive;
  final FutureOr<void> Function(
    BuildContext viewerContext,
    TheavMediaItem item,
    int index,
  ) onSelected;

  const TheavMediaAction({
    required this.id,
    required this.label,
    this.icon,
    this.isDestructive = false,
    required this.onSelected,
  });
}

/// Configuration and callbacks controlling [TheavMediaViewer] behavior.
class TheavMediaViewerConfig {
  final ValueChanged<int>? onPageChanged;

  /// Invoked synchronously with the active index right before the viewer starts
  /// closing (back button, Escape key, or 2D drag-to-dismiss), allowing callers
  /// such as [ProfileScreen] to defer index syncing until close so swipes never
  /// trigger parent rebuilds.
  final ValueChanged<int>? onBeforeCloseSyncIndex;

  final FutureOr<void> Function(BuildContext viewerContext, TheavMediaItem item)?
      onJumpToMessage;
  final FutureOr<void> Function(BuildContext viewerContext, TheavMediaItem item)?
      onForwardItem;
  final FutureOr<bool> Function(
    BuildContext viewerContext,
    TheavMediaItem item,
    int index,
  )? onDeleteItem;
  final List<TheavMediaAction> Function(TheavMediaItem item, int index)?
      extraActionsBuilder;
  final Widget Function(BuildContext context, TheavMediaItem item, int index)?
      bottomAccessoryBuilder;

  /// Optional top-bar primary trailing action (e.g., "Choose new photo" on
  /// self profile avatar gallery).
  final TheavMediaAction? primaryTopAction;

  /// Whether left/right horizontal swipes wrap continuously. Defaults to false.
  final bool loopPages;

  /// When true, renders an avatar-specific fallback title ("Аватар" / [displayName]).
  final String? titleOverride;

  const TheavMediaViewerConfig({
    this.onPageChanged,
    this.onBeforeCloseSyncIndex,
    this.onJumpToMessage,
    this.onForwardItem,
    this.onDeleteItem,
    this.extraActionsBuilder,
    this.bottomAccessoryBuilder,
    this.primaryTopAction,
    this.loopPages = false,
    this.titleOverride,
  });
}

/// Unified descriptor for photos, videos, GIFs, and profile/suggested avatars
/// viewed inside [TheavMediaViewer].
class TheavMediaItem {
  final String id;
  final TheavMediaKind kind;
  final String url;
  final String? localFilePath;
  final Uint8List? memoryBytes;
  final String? thumbUrl;
  final String? thumbBase64;
  final String heroTag;
  final int? width;
  final int? height;
  final int? durationSeconds;
  final int? fileSize;
  final String? fileName;
  final String? senderId;
  final String? senderChatId;
  final String? senderName;
  final String? senderAvatarUrl;
  final bool isAnonymousAdmin;
  final bool isMirroredChannelPost;
  final bool isChannelOrPersonaAuthored;
  final DateTime? timestamp;
  final String? caption;
  final List<MessageEntity> entities;
  final String? messageId;
  final String? chatId;
  final String? groupedId;
  final bool hasProtectedContent;
  final bool isCustomAvatar;
  final String? customBadgeLabel;

  const TheavMediaItem({
    required this.id,
    required this.kind,
    required this.url,
    this.localFilePath,
    this.memoryBytes,
    this.thumbUrl,
    this.thumbBase64,
    required this.heroTag,
    this.width,
    this.height,
    this.durationSeconds,
    this.fileSize,
    this.fileName,
    this.senderId,
    this.senderChatId,
    this.senderName,
    this.senderAvatarUrl,
    this.isAnonymousAdmin = false,
    this.isMirroredChannelPost = false,
    this.isChannelOrPersonaAuthored = false,
    this.timestamp,
    this.caption,
    this.entities = const [],
    this.messageId,
    this.chatId,
    this.groupedId,
    this.hasProtectedContent = false,
    this.isCustomAvatar = false,
    this.customBadgeLabel,
  });

  /// Deterministic hero tag shared by chat bubbles, album collage tiles,
  /// channel post cards, and [buildChatMediaTimeline].
  static String heroTagForMessage({
    required String messageId,
    required String rawOrResolvedUrl,
    String prefix = 'chat_media',
  }) {
    final trimmedId = messageId.trim();
    if (trimmedId.isNotEmpty) {
      return '${prefix}_$trimmedId';
    }
    return '${prefix}_$rawOrResolvedUrl';
  }

  /// Resolves [url] for full-resolution network or file loading (stripping `#acrop`).
  String get resolvedUrl {
    final stripped = stripAvatarCropFragment(url) ?? url;
    if (stripped.isEmpty) return '';
    if (stripped.startsWith('data:') ||
        stripped.startsWith('file://') ||
        (stripped.startsWith('/') &&
            !stripped.startsWith('/api/') &&
            !stripped.startsWith('/uploads/') &&
            !stripped.startsWith('/media/') &&
            !stripped.startsWith('/static/'))) {
      return stripped;
    }
    return AppConfig.resolveMediaUrl(stripped) ?? stripped;
  }

  /// Resolves optional thumbnail URL if present.
  String? get resolvedThumbUrl {
    final raw = thumbUrl?.trim() ?? '';
    if (raw.isEmpty) return null;
    if (raw.startsWith('data:') || raw.startsWith('file://')) return raw;
    return AppConfig.resolveMediaUrl(raw) ?? raw;
  }

  /// Whether this GIF uses a video container (`.mp4`, `.webm`, `.mov`, `.mkv`)
  /// rather than an animated raster GIF/WebP image.
  bool get isVideoBackedGif {
    if (kind != TheavMediaKind.gif) return false;
    final clean = (localFilePath ?? resolvedUrl).split('?').first.toLowerCase();
    return clean.endsWith('.mp4') ||
        clean.endsWith('.mov') ||
        clean.endsWith('.webm') ||
        clean.endsWith('.mkv');
  }

  double get aspectRatio {
    final w = width ?? 0;
    final h = height ?? 0;
    if (w > 0 && h > 0) {
      return (w / h).clamp(0.25, 4.0);
    }
    return 1.0;
  }

  bool get hasCaption {
    final c = caption?.trim() ?? '';
    if (c.isEmpty) return false;
    if (c == fileName) return false;
    if (c == url || c == resolvedUrl) return false;
    return true;
  }

  static bool _isVideoExtension(String rawUrl) {
    final clean = rawUrl.split('?').first.split('#').first.toLowerCase();
    return clean.endsWith('.mp4') ||
        clean.endsWith('.mov') ||
        clean.endsWith('.webm') ||
        clean.endsWith('.mkv') ||
        clean.endsWith('.avi') ||
        clean.endsWith('.3gp');
  }

  static bool _isGifExtension(String rawUrl) {
    final clean = rawUrl.split('?').first.split('#').first.toLowerCase();
    return clean.endsWith('.gif');
  }

  static TheavMediaKind classifyMessageKind(Message msg) {
    final mt = msg.messageType.toLowerCase().trim();
    final rawUrl = msg.fileUrl ?? '';
    if (mt == 'gif' || mt == 'animation' || _isGifExtension(rawUrl)) {
      return TheavMediaKind.gif;
    }
    if (mt == 'video' || _isVideoExtension(rawUrl)) {
      return TheavMediaKind.video;
    }
    return TheavMediaKind.photo;
  }

  factory TheavMediaItem.fromMessage(
    Message msg, {
    String? heroTagOverride,
    String? heroPrefix = 'chat_media',
    String? fallbackCaption,
    List<MessageEntity>? fallbackEntities,
    String? localFilePathOverride,
    bool hasProtectedContent = false,
  }) {
    final rawUrl = msg.fileUrl?.trim() ?? '';
    final resolved = AppConfig.resolveMediaUrl(rawUrl) ?? rawUrl;
    final kind = classifyMessageKind(msg);
    final String effectiveId = msg.id.isNotEmpty
        ? msg.id
        : (msg.localId?.isNotEmpty == true ? msg.localId! : resolved);
    final String heroTag = heroTagOverride ??
        heroTagForMessage(
          messageId: effectiveId,
          rawOrResolvedUrl: resolved,
          prefix: heroPrefix ?? 'chat_media',
        );

    final String rawCaption = msg.content.trim().isNotEmpty
        ? msg.content
        : (fallbackCaption ?? '');
    final List<MessageEntity> effectiveEntities = msg.entities.isNotEmpty
        ? msg.entities
        : (fallbackEntities ?? const <MessageEntity>[]);
    final String? cleanCaption = rawCaption.trim().isEmpty ||
            rawCaption.trim() == msg.fileName ||
            rawCaption.trim() == rawUrl ||
            rawCaption.trim() == resolved
        ? null
        : rawCaption;

    final String resolvedSenderName =
        (msg.isChannelOrPersonaAuthored || msg.isMirroredChannelPost)
            ? msg.resolveEffectiveAuthorTitle()
            : (msg.senderChatName?.trim().isNotEmpty == true
                ? msg.senderChatName!.trim()
                : msg.senderName.trim());

    return TheavMediaItem(
      id: effectiveId,
      kind: kind,
      url: rawUrl,
      localFilePath: localFilePathOverride,
      thumbUrl: msg.thumbUrl,
      thumbBase64: msg.thumbBase64,
      heroTag: heroTag,
      width: msg.mediaWidth,
      height: msg.mediaHeight,
      durationSeconds: msg.mediaDuration ?? msg.duration,
      fileSize: msg.mediaFileSize,
      fileName: msg.fileName,
      senderId: msg.senderId,
      senderChatId: msg.senderChatId,
      senderName: resolvedSenderName.isNotEmpty ? resolvedSenderName : null,
      senderAvatarUrl:
          (msg.senderChatAvatarUrl?.trim().isNotEmpty == true)
              ? msg.senderChatAvatarUrl
              : msg.senderAvatarUrl,
      isAnonymousAdmin: msg.isFromAnonymousAdmin,
      isMirroredChannelPost: msg.isMirroredChannelPost,
      isChannelOrPersonaAuthored: msg.isChannelOrPersonaAuthored,
      timestamp: DateTimeUtils.parseUtcDateTime(msg.createdAt),
      caption: cleanCaption,
      entities: effectiveEntities,
      messageId: msg.id.isNotEmpty ? msg.id : msg.localId,
      chatId: msg.chatId,
      groupedId: msg.groupedId,
      hasProtectedContent: hasProtectedContent,
    );
  }

  factory TheavMediaItem.fromDbMessage(
    DbMessage dbMsg, {
    String? heroTagOverride,
    String? chatTitle,
    bool hasProtectedContent = false,
  }) {
    final msg = Message.fromDbMessage(dbMsg);
    final item = TheavMediaItem.fromMessage(
      msg,
      heroTagOverride: heroTagOverride ??
          'profile_media_${dbMsg.serverId ?? dbMsg.localId}',
      hasProtectedContent: hasProtectedContent,
    );
    if ((item.senderName == null || item.senderName!.isEmpty) &&
        chatTitle != null &&
        chatTitle.isNotEmpty) {
      return TheavMediaItem(
        id: item.id,
        kind: item.kind,
        url: item.url,
        localFilePath: item.localFilePath,
        memoryBytes: item.memoryBytes,
        thumbUrl: item.thumbUrl,
        thumbBase64: item.thumbBase64,
        heroTag: item.heroTag,
        width: item.width,
        height: item.height,
        durationSeconds: item.durationSeconds,
        fileSize: item.fileSize,
        fileName: item.fileName,
        senderId: item.senderId,
        senderChatId: item.senderChatId,
        senderName: chatTitle,
        senderAvatarUrl: item.senderAvatarUrl,
        isAnonymousAdmin: item.isAnonymousAdmin,
        isMirroredChannelPost: item.isMirroredChannelPost,
        isChannelOrPersonaAuthored: item.isChannelOrPersonaAuthored,
        timestamp: item.timestamp,
        caption: item.caption,
        entities: item.entities,
        messageId: item.messageId,
        chatId: item.chatId,
        groupedId: item.groupedId,
        hasProtectedContent: item.hasProtectedContent,
      );
    }
    return item;
  }

  factory TheavMediaItem.fromAvatarUrl(
    String rawUrl, {
    required int index,
    String? heroTagPrefix = 'avatar_hero',
    String? displayName,
    bool isCustomAvatar = false,
    String? customBadgeLabel,
    bool hasProtectedContent = false,
  }) {
    final trimmed = rawUrl.trim();
    final prefix = (heroTagPrefix != null && heroTagPrefix.isNotEmpty)
        ? heroTagPrefix
        : 'avatar_hero';
    return TheavMediaItem(
      id: 'avatar_${index}_$trimmed',
      kind: TheavMediaKind.avatar,
      url: trimmed,
      heroTag: '${prefix}_$trimmed',
      senderName: (displayName != null && displayName.trim().isNotEmpty)
          ? displayName.trim()
          : null,
      isCustomAvatar: isCustomAvatar,
      customBadgeLabel: customBadgeLabel,
      hasProtectedContent: hasProtectedContent,
    );
  }
}

/// Flattens a chat/channel message list (single media + grouped albums) into a
/// continuous chronological (oldest -> newest) media timeline suitable for
/// [TheavMediaViewer].
///
/// Excludes round video notes, voice/audio messages, stickers, documents,
/// unsupported items, burned/empty items, and ephemeral view-once media.
List<TheavMediaItem> buildChatMediaTimeline(
  List<Message> messages, {
  required bool isReversed,
  bool hasProtectedContent = false,
  String heroPrefix = 'chat_media',
}) {
  if (messages.isEmpty) return const <TheavMediaItem>[];

  final Iterable<Message> chronological =
      isReversed ? messages.reversed : messages;

  final List<Message> eligible = <Message>[];
  final Set<String> seenKeys = <String>{};

  for (final m in chronological) {
    final String dedupKey = m.id.isNotEmpty ? m.id : (m.localId ?? '');
    if (dedupKey.isNotEmpty && !seenKeys.add(dedupKey)) continue;
    if (m.isUnsupported) continue;
    if (m.isRound || m.isViewOnce || m.isBurned) continue;

    final String mt = m.messageType.toLowerCase().trim();
    if (mt == 'round' ||
        mt == 'voice' ||
        mt == 'audio' ||
        mt == 'sticker' ||
        mt == 'document' ||
        mt == 'file' ||
        mt == 'poll' ||
        mt == 'call' ||
        mt == 'system' ||
        mt == 'dice' ||
        mt == 'location' ||
        mt == 'live_location' ||
        mt == 'venue' ||
        mt == 'contact') {
      continue;
    }

    final rawUrl = m.fileUrl?.trim() ?? '';
    if (rawUrl.isEmpty) continue;

    final bool isKnownVisualType = mt == 'image' ||
        mt == 'photo' ||
        mt == 'video' ||
        mt == 'gif' ||
        mt == 'animation' ||
        TheavMediaItem._isVideoExtension(rawUrl) ||
        TheavMediaItem._isGifExtension(rawUrl) ||
        rawUrl.startsWith('data:image/');
    if (!isKnownVisualType) continue;

    eligible.add(m);
  }

  if (eligible.isEmpty) return const <TheavMediaItem>[];

  // Collect shared captions & entities per groupedId so every tile in an album
  // shows the album caption in the viewer HUD just like Telegram.
  final Map<String, ({String caption, List<MessageEntity> entities})>
      albumCaptions = <String, ({String caption, List<MessageEntity> entities})>{};
  for (final m in eligible) {
    final gid = m.groupedId;
    if (gid == null || gid.isEmpty) continue;
    if (albumCaptions.containsKey(gid)) continue;
    final trimmed = m.content.trim();
    if (trimmed.isNotEmpty &&
        trimmed != m.fileName &&
        trimmed != m.fileUrl) {
      albumCaptions[gid] = (caption: m.content, entities: m.entities);
    }
  }

  return eligible.map((m) {
    final gid = m.groupedId;
    final shared = (gid != null && gid.isNotEmpty) ? albumCaptions[gid] : null;
    return TheavMediaItem.fromMessage(
      m,
      heroPrefix: heroPrefix,
      fallbackCaption: shared?.caption,
      fallbackEntities: shared?.entities,
      hasProtectedContent: hasProtectedContent,
    );
  }).toList(growable: false);
}
