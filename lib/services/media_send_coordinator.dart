import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../utils/local_media_inspector.dart';
import 'account_manager.dart';
import 'auth_service.dart';
import 'chat_service.dart';
import 'database/app_database.dart';
import 'file_service.dart';
import 'media_cache_manager.dart';
import 'sync_service.dart';

/// Lifecycle phase for an optimistic outgoing media or file message.
enum OutgoingUploadPhase {
  preparing,
  uploading,
  waitingAlbumSiblings,
  sendingRpc,
  sent,
  failed,
  cancelled,
}

/// Snapshot of upload progress and current phase for a single local message.
class OutgoingUploadProgress {
  final String localId;
  final String chatId;
  final String? groupedId;
  final int sentBytes;
  final int totalBytes;
  final double fraction;
  final OutgoingUploadPhase phase;
  final String? errorMessage;

  const OutgoingUploadProgress({
    required this.localId,
    required this.chatId,
    this.groupedId,
    required this.sentBytes,
    required this.totalBytes,
    required this.fraction,
    required this.phase,
    this.errorMessage,
  });

  bool get isCancelable =>
      phase == OutgoingUploadPhase.preparing ||
      phase == OutgoingUploadPhase.uploading ||
      phase == OutgoingUploadPhase.waitingAlbumSiblings;

  bool get isWaitingSiblings => phase == OutgoingUploadPhase.waitingAlbumSiblings;

  bool get isFailed => phase == OutgoingUploadPhase.failed;

  bool get isActive =>
      phase == OutgoingUploadPhase.preparing ||
      phase == OutgoingUploadPhase.uploading ||
      phase == OutgoingUploadPhase.waitingAlbumSiblings ||
      phase == OutgoingUploadPhase.sendingRpc;

  OutgoingUploadProgress copyWith({
    String? groupedId,
    bool clearGroupedId = false,
    int? sentBytes,
    int? totalBytes,
    double? fraction,
    OutgoingUploadPhase? phase,
    String? errorMessage,
    bool clearError = false,
  }) {
    return OutgoingUploadProgress(
      localId: localId,
      chatId: chatId,
      groupedId: clearGroupedId ? null : (groupedId ?? this.groupedId),
      sentBytes: sentBytes ?? this.sentBytes,
      totalBytes: totalBytes ?? this.totalBytes,
      fraction: fraction ?? this.fraction,
      phase: phase ?? this.phase,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

/// Types of lifecycle events broadcast to active chat feeds.
enum MediaSendEventType {
  inserted,
  updated,
  replacedWithServer,
  failed,
  cancelled,
  albumDowngradedToSingle,
}

/// Event emitted on [MediaSendCoordinator.events] whenever an optimistic
/// outgoing message/album changes state.
class MediaSendEvent {
  final MediaSendEventType type;
  final String chatId;
  final String? threadRootMessageId;
  final List<String> localIds;
  final List<Message> messages;
  final String? groupedId;

  const MediaSendEvent({
    required this.type,
    required this.chatId,
    this.threadRootMessageId,
    required this.localIds,
    this.messages = const [],
    this.groupedId,
  });
}

class _TrackedUploadItem {
  final String localId;
  final String chatId;
  String? groupedId;
  final String? threadRootMessageId;
  String content;
  String messageType;
  final bool isRound;
  final String? fileName;
  String? localFilePath;
  int totalBytes;
  String? remoteFileUrl;
  Map<String, dynamic>? remoteMediaPayload;
  UploadResult? uploadResult;
  Map<String, dynamic> extraPayload;
  List<int>? waveform;
  int? duration;
  List<MessageEntity> entities;
  bool invertMedia;
  String? replyToMessageId;
  String? replyToChatId;
  bool isQuote;
  String? quoteText;
  int quoteOffset;
  int quoteLength;
  bool hasMediaSpoiler;
  bool isSilent;
  bool isViewOnce;
  int ttlSeconds;
  String? effectId;
  int? topicId;
  String? sendAsChatId;
  String? sendAsMode;
  bool sendAsAnonymous;
  OutgoingUploadPhase phase;
  CancelToken? cancelToken;
  bool cancelled = false;
  int lastEmitMs = 0;
  double lastEmitFraction = -1;

  _TrackedUploadItem({
    required this.localId,
    required this.chatId,
    this.groupedId,
    this.threadRootMessageId,
    required this.content,
    required this.messageType,
    this.isRound = false,
    this.fileName,
    this.localFilePath,
    required this.totalBytes,
    this.remoteFileUrl,
    this.remoteMediaPayload,
    Map<String, dynamic>? extraPayload,
    this.waveform,
    this.duration,
    this.entities = const [],
    this.invertMedia = false,
    this.replyToMessageId,
    this.replyToChatId,
    this.isQuote = false,
    this.quoteText,
    this.quoteOffset = 0,
    this.quoteLength = 0,
    this.hasMediaSpoiler = false,
    this.isSilent = false,
    this.isViewOnce = false,
    this.ttlSeconds = 0,
    this.effectId,
    this.topicId,
    this.sendAsChatId,
    this.sendAsMode,
    this.sendAsAnonymous = false,
    this.phase = OutgoingUploadPhase.uploading,
  }) : extraPayload = extraPayload ?? <String, dynamic>{};
}

class _TrackedAlbumJob {
  final String chatId;
  String groupedId;
  final String? threadRootMessageId;
  final List<_TrackedUploadItem> items;
  bool running = false;

  _TrackedAlbumJob({
    required this.chatId,
    required this.groupedId,
    this.threadRootMessageId,
    required this.items,
  });
}

typedef UploadFileOverride = Future<UploadResult> Function(
  File file, {
  void Function(int sentBytes, int totalBytes)? onSendBytes,
  CancelToken? cancelToken,
});

typedef SendSingleRpcOverride = Future<Map<String, dynamic>> Function(
  String chatId,
  String localId,
  String content,
  String messageType,
  String fileUrl,
  String? fileName,
  Map<String, dynamic>? mediaPayload,
  String? groupedId,
  bool isRound,
  int? duration,
  List<int>? waveform,
);

typedef SendAlbumRpcOverride = Future<Map<String, dynamic>> Function(
  String chatId,
  String groupedId,
  List<Map<String, dynamic>> items,
  String? caption,
);

typedef SendPostCommentRpcOverride = Future<Message?> Function(
  String channelId,
  String threadRootMessageId,
  String localId,
  String content,
  String messageType,
  String fileUrl,
  String? fileName,
  Map<String, dynamic>? mediaPayload,
  String? groupedId,
  bool isRound,
  int? duration,
  List<int>? waveform,
);

/// Global singleton orchestrating Telegram-style optimistic outgoing media/file
/// sends, independent of individual chat screen lifecycles.
class MediaSendCoordinator {
  MediaSendCoordinator._internal();
  static final MediaSendCoordinator instance = MediaSendCoordinator._internal();

  static const int _maxAlbumItems = 10;
  static const int _albumUploadConcurrency = 2;
  static const _uuid = Uuid();

  final Map<String, ValueNotifier<OutgoingUploadProgress>> _progressNotifiers =
      {};
  final Map<String, _TrackedUploadItem> _items = {};
  final Map<String, _TrackedAlbumJob> _albums = {};
  final Map<String, Set<String>> _chatActiveLocalIds = {};
  final Map<String, Set<String>> _chatFailedLocalIds = {};
  final StreamController<MediaSendEvent> _eventController =
      StreamController<MediaSendEvent>.broadcast();

  /// Incremented whenever the active or failed set changes so chat list tiles can rebuild.
  final ValueNotifier<int> revisionNotifier = ValueNotifier<int>(0);

  FileService? _fileServiceOverride;
  UploadFileOverride? _uploadOverride;
  SendSingleRpcOverride? _sendSingleRpcOverride;
  SendAlbumRpcOverride? _sendAlbumRpcOverride;
  SendPostCommentRpcOverride? _sendPostCommentOverride;

  Stream<MediaSendEvent> get events => _eventController.stream;

  /// Test-only hook for driving deterministic upload progress, errors, cancel, and retry.
  @visibleForTesting
  void configureForTesting({
    FileService? fileService,
    UploadFileOverride? uploadOverride,
    SendSingleRpcOverride? sendSingleRpcOverride,
    SendAlbumRpcOverride? sendAlbumRpcOverride,
    SendPostCommentRpcOverride? sendPostCommentOverride,
  }) {
    _fileServiceOverride = fileService;
    _uploadOverride = uploadOverride;
    _sendSingleRpcOverride = sendSingleRpcOverride;
    _sendAlbumRpcOverride = sendAlbumRpcOverride;
    _sendPostCommentOverride = sendPostCommentOverride;
  }

  /// Clears in-memory tracking state and test overrides.
  @visibleForTesting
  void resetForTesting() {
    for (final item in _items.values) {
      try {
        item.cancelToken?.cancel('resetForTesting');
      } catch (_) {}
    }
    _items.clear();
    _albums.clear();
    _chatActiveLocalIds.clear();
    _chatFailedLocalIds.clear();
    for (final n in _progressNotifiers.values) {
      n.dispose();
    }
    _progressNotifiers.clear();
    _fileServiceOverride = null;
    _uploadOverride = null;
    _sendSingleRpcOverride = null;
    _sendAlbumRpcOverride = null;
    _sendPostCommentOverride = null;
    revisionNotifier.value++;
  }

  /// All [localId]s currently uploading or sending RPC in memory.
  Set<String> get activeLocalIds {
    return _items.values
        .where((item) => !item.cancelled && _isPhaseActive(item.phase))
        .map((item) => item.localId)
        .toSet();
  }

  static bool _isPhaseActive(OutgoingUploadPhase phase) {
    return phase == OutgoingUploadPhase.preparing ||
        phase == OutgoingUploadPhase.uploading ||
        phase == OutgoingUploadPhase.waitingAlbumSiblings ||
        phase == OutgoingUploadPhase.sendingRpc;
  }

  /// Latest cached progress snapshot for [localId], if any.
  OutgoingUploadProgress? currentProgress(String localId) =>
      _progressNotifiers[localId]?.value;

  /// Reactive progress notifier for a local outgoing bubble or album item.
  ValueNotifier<OutgoingUploadProgress> progressFor(
    String localId, {
    String? chatId,
    String? groupedId,
    int? totalBytes,
    int? sendStatus,
  }) {
    final existing = _progressNotifiers[localId];
    if (existing != null) {
      if (sendStatus == 2 &&
          !existing.value.isFailed &&
          _items[localId] == null) {
        existing.value = existing.value.copyWith(
          phase: OutgoingUploadPhase.failed,
        );
      }
      return existing;
    }

    final tracked = _items[localId];
    final initialPhase = tracked?.phase ??
        (sendStatus == 2
            ? OutgoingUploadPhase.failed
            : (sendStatus == 1
                ? OutgoingUploadPhase.sent
                : OutgoingUploadPhase.uploading));
    final notifier = ValueNotifier<OutgoingUploadProgress>(
      OutgoingUploadProgress(
        localId: localId,
        chatId: tracked?.chatId ?? chatId ?? '',
        groupedId: tracked?.groupedId ?? groupedId,
        sentBytes: 0,
        totalBytes: tracked?.totalBytes ?? totalBytes ?? 0,
        fraction: initialPhase == OutgoingUploadPhase.waitingAlbumSiblings ||
                initialPhase == OutgoingUploadPhase.sent
            ? 1.0
            : 0.0,
        phase: initialPhase,
      ),
    );
    _progressNotifiers[localId] = notifier;
    return notifier;
  }

  /// Returns `0` when [chatId] has active outgoing uploads, `2` when it has failed
  /// outgoing uploads, or `null` when all sends are settled.
  int? getChatSendStatusOverride(String chatId) {
    final active = _chatActiveLocalIds[chatId];
    if (active != null && active.isNotEmpty) return 0;
    final failed = _chatFailedLocalIds[chatId];
    if (failed != null && failed.isNotEmpty) return 2;
    return null;
  }

  /// Enqueues one or more local media files or documents for immediate chat
  /// insertion and background upload.
  Future<List<Message>> enqueueMediaOrFiles({
    required String chatId,
    required List<File> files,
    bool asDocument = false,
    String caption = '',
    Map<String, String>? captionsByPath,
    List<MessageEntity>? entities,
    bool invertMedia = false,
    String? replyToMessageId,
    bool isQuote = false,
    String? quoteText,
    int quoteOffset = 0,
    int quoteLength = 0,
    String? replyToSenderId,
    String? replyToSenderName,
    String? replyToContent,
    String replyToMessageType = 'text',
    String? replyToChatId,
    String? replyToChatName,
    String? replyToChatType,
    String? effectId,
    bool isSilent = false,
    bool hasMediaSpoiler = false,
    bool isViewOnce = false,
    int ttlSeconds = 0,
    int? topicId,
    String? sendAsChatId,
    String? sendAsMode,
    bool sendAsAnonymous = false,
    String? threadRootMessageId,
    String? senderId,
    String? senderName,
    String? senderAvatarUrl,
    String? senderChatName,
    String? senderChatAvatarUrl,
  }) async {
    if (files.isEmpty) return const [];

    final identity = await _resolveSenderIdentity(
      senderId: senderId,
      senderName: senderName,
      senderAvatarUrl: senderAvatarUrl,
    );

    final stagedEntries =
        <({String localId, File originalFile, OutboxStagedFile staged})>[];
    for (final f in files) {
      final localId = _uuid.v4();
      final staged = await LocalMediaInspector.stageAndInspect(
        f,
        localId: localId,
        asDocument: asDocument,
      );
      stagedEntries.add((
        localId: localId,
        originalFile: f,
        staged: staged,
      ));
    }

    // Group contiguous non-document visual media items (`image`, `video`, `gif`) into
    // albums of 2..10 items; documents or singletons become standalone messages.
    final batches =
        <List<({String localId, File originalFile, OutboxStagedFile staged})>>[];
    if (asDocument) {
      for (final entry in stagedEntries) {
        batches.add([entry]);
      }
    } else {
      var visualBuffer =
          <({String localId, File originalFile, OutboxStagedFile staged})>[];
      void flushVisual() {
        while (visualBuffer.length > _maxAlbumItems) {
          batches.add(visualBuffer.sublist(0, _maxAlbumItems));
          visualBuffer = visualBuffer.sublist(_maxAlbumItems);
        }
        if (visualBuffer.isNotEmpty) {
          batches.add(List.of(visualBuffer));
          visualBuffer.clear();
        }
      }

      for (final entry in stagedEntries) {
        final t = entry.staged.messageType;
        if (t == 'image' || t == 'video' || t == 'gif') {
          visualBuffer.add(entry);
        } else {
          flushVisual();
          batches.add([entry]);
        }
      }
      flushVisual();
    }

    final allInserted = <Message>[];
    final syncService = SyncService();

    for (var bIdx = 0; bIdx < batches.length; bIdx++) {
      final batch = batches[bIdx];
      final bool isAlbum = batch.length >= 2;
      final String? groupedId = isAlbum
          ? 'album_${DateTime.now().microsecondsSinceEpoch}_$bIdx'
          : null;
      final batchTracked = <_TrackedUploadItem>[];
      final batchMessages = <Message>[];

      for (var i = 0; i < batch.length; i++) {
        final entry = batch[i];
        final staged = entry.staged;
        final origCaption = captionsByPath?[entry.originalFile.path]?.trim() ?? '';
        final itemCaption = origCaption.isNotEmpty
            ? origCaption
            : (bIdx == 0 && i == 0 ? caption.trim() : '');
        final itemEntities =
            itemCaption.isNotEmpty ? (entities ?? const <MessageEntity>[]) : const <MessageEntity>[];

        final payloadMap = _buildInitialMediaPayload(
          staged: staged,
          albumOrder: isAlbum ? i : null,
          sendAsChatId: sendAsChatId,
          sendAsMode: sendAsMode,
          topicId: topicId,
        );

        final dbMsg = await syncService.createPendingMessage(
          localIdOverride: entry.localId,
          chatId: chatId,
          senderId: identity.senderId,
          content: itemCaption,
          messageType: staged.messageType,
          fileUrl: staged.file.path,
          fileName: staged.fileName,
          replyToMessageId: i == 0 ? replyToMessageId : null,
          isQuote: i == 0 && isQuote,
          quoteText: i == 0 ? quoteText : null,
          quoteOffset: i == 0 ? quoteOffset : 0,
          quoteLength: i == 0 ? quoteLength : 0,
          replyToSenderId: i == 0 ? replyToSenderId : null,
          replyToSenderName: i == 0 ? replyToSenderName : null,
          replyToContent: i == 0 ? replyToContent : null,
          replyToMessageType: i == 0 ? replyToMessageType : 'text',
          replyToChatId: i == 0 ? replyToChatId : null,
          replyToChatName: i == 0 ? replyToChatName : null,
          replyToChatType: i == 0 ? replyToChatType : null,
          entities: itemEntities,
          invertMedia: i == 0 && invertMedia,
          groupedId: groupedId,
          mediaPayload: payloadMap,
          isSilent: isSilent,
          threadRootMessageId: threadRootMessageId,
          hasMediaSpoiler: hasMediaSpoiler,
          effectId: i == 0 ? effectId : null,
          isViewOnce: isViewOnce,
          ttlSeconds: ttlSeconds,
          senderName: identity.senderName,
          senderAvatarUrl: identity.senderAvatarUrl,
          isFromAnonymousAdmin: sendAsAnonymous,
          topicId: topicId,
          senderChatId: sendAsChatId,
          senderChatName: senderChatName,
          senderChatAvatarUrl: senderChatAvatarUrl,
          isOwn: true,
        );

        final msg = Message.fromDbMessage(dbMsg);
        batchMessages.add(msg);
        allInserted.add(msg);

        final tracked = _TrackedUploadItem(
          localId: entry.localId,
          chatId: chatId,
          groupedId: groupedId,
          threadRootMessageId: threadRootMessageId,
          content: itemCaption,
          messageType: staged.messageType,
          fileName: staged.fileName,
          localFilePath: staged.file.path,
          totalBytes: staged.fileSize,
          extraPayload: payloadMap,
          entities: itemEntities,
          invertMedia: i == 0 && invertMedia,
          replyToMessageId: i == 0 ? replyToMessageId : null,
          replyToChatId: i == 0 ? replyToChatId : null,
          isQuote: i == 0 && isQuote,
          quoteText: i == 0 ? quoteText : null,
          quoteOffset: i == 0 ? quoteOffset : 0,
          quoteLength: i == 0 ? quoteLength : 0,
          hasMediaSpoiler: hasMediaSpoiler,
          isSilent: isSilent,
          isViewOnce: isViewOnce,
          ttlSeconds: ttlSeconds,
          effectId: i == 0 ? effectId : null,
          topicId: topicId,
          sendAsChatId: sendAsChatId,
          sendAsMode: sendAsMode,
          sendAsAnonymous: sendAsAnonymous,
          phase: OutgoingUploadPhase.uploading,
        );
        _registerTrackedItem(tracked);
        batchTracked.add(tracked);
      }

      _emitEvent(MediaSendEvent(
        type: MediaSendEventType.inserted,
        chatId: chatId,
        threadRootMessageId: threadRootMessageId,
        localIds: batchMessages.map((m) => m.localId ?? m.id).toList(),
        messages: batchMessages,
        groupedId: groupedId,
      ));

      if (isAlbum && groupedId != null) {
        final job = _TrackedAlbumJob(
          chatId: chatId,
          groupedId: groupedId,
          threadRootMessageId: threadRootMessageId,
          items: batchTracked,
        );
        _albums[groupedId] = job;
        unawaited(_runAlbumJob(job));
      } else {
        unawaited(_runSingleJob(batchTracked.first));
      }
    }

    return allInserted;
  }

  /// Enqueues a recorded voice note for immediate insertion and background upload.
  Future<Message> enqueueVoiceNote({
    required String chatId,
    required File audioFile,
    required int durationSeconds,
    List<int>? waveform,
    String? replyToMessageId,
    bool isQuote = false,
    String? quoteText,
    int quoteOffset = 0,
    int quoteLength = 0,
    String? replyToSenderId,
    String? replyToSenderName,
    String? replyToContent,
    String replyToMessageType = 'text',
    String? replyToChatId,
    String? replyToChatName,
    String? replyToChatType,
    bool isSilent = false,
    bool isViewOnce = false,
    int ttlSeconds = 0,
    int? topicId,
    String? sendAsChatId,
    String? sendAsMode,
    bool sendAsAnonymous = false,
    String? threadRootMessageId,
    String? senderId,
    String? senderName,
    String? senderAvatarUrl,
    String? senderChatName,
    String? senderChatAvatarUrl,
  }) async {
    final localId = _uuid.v4();
    final staged = await LocalMediaInspector.stageAndInspect(
      audioFile,
      localId: localId,
      asDocument: true,
    );
    return _enqueueAudioOrRoundInternal(
      localId: localId,
      chatId: chatId,
      stagedFile: staged.file,
      fileName: staged.fileName,
      fileSize: staged.fileSize,
      messageType: 'voice',
      isRound: false,
      durationSeconds: durationSeconds,
      waveform: waveform,
      replyToMessageId: replyToMessageId,
      isQuote: isQuote,
      quoteText: quoteText,
      quoteOffset: quoteOffset,
      quoteLength: quoteLength,
      replyToSenderId: replyToSenderId,
      replyToSenderName: replyToSenderName,
      replyToContent: replyToContent,
      replyToMessageType: replyToMessageType,
      replyToChatId: replyToChatId,
      replyToChatName: replyToChatName,
      replyToChatType: replyToChatType,
      isSilent: isSilent,
      isViewOnce: isViewOnce,
      ttlSeconds: ttlSeconds,
      topicId: topicId,
      sendAsChatId: sendAsChatId,
      sendAsMode: sendAsMode,
      sendAsAnonymous: sendAsAnonymous,
      threadRootMessageId: threadRootMessageId,
      senderId: senderId,
      senderName: senderName,
      senderAvatarUrl: senderAvatarUrl,
      senderChatName: senderChatName,
      senderChatAvatarUrl: senderChatAvatarUrl,
    );
  }

  /// Enqueues a recorded round video note for immediate insertion and background upload.
  Future<Message> enqueueRoundVideoNote({
    required String chatId,
    required File videoFile,
    required int durationSeconds,
    List<int>? waveform,
    String? replyToMessageId,
    bool isQuote = false,
    String? quoteText,
    int quoteOffset = 0,
    int quoteLength = 0,
    String? replyToSenderId,
    String? replyToSenderName,
    String? replyToContent,
    String replyToMessageType = 'text',
    String? replyToChatId,
    String? replyToChatName,
    String? replyToChatType,
    bool isSilent = false,
    bool isViewOnce = false,
    int ttlSeconds = 0,
    int? topicId,
    String? sendAsChatId,
    String? sendAsMode,
    bool sendAsAnonymous = false,
    String? threadRootMessageId,
    String? senderId,
    String? senderName,
    String? senderAvatarUrl,
    String? senderChatName,
    String? senderChatAvatarUrl,
  }) async {
    final localId = _uuid.v4();
    final staged = await LocalMediaInspector.stageAndInspect(
      videoFile,
      localId: localId,
      asDocument: false,
      preferVideo: true,
    );
    return _enqueueAudioOrRoundInternal(
      localId: localId,
      chatId: chatId,
      stagedFile: staged.file,
      fileName: staged.fileName,
      fileSize: staged.fileSize,
      messageType: 'video',
      isRound: true,
      durationSeconds: staged.durationSeconds ?? durationSeconds,
      waveform: waveform,
      replyToMessageId: replyToMessageId,
      isQuote: isQuote,
      quoteText: quoteText,
      quoteOffset: quoteOffset,
      quoteLength: quoteLength,
      replyToSenderId: replyToSenderId,
      replyToSenderName: replyToSenderName,
      replyToContent: replyToContent,
      replyToMessageType: replyToMessageType,
      replyToChatId: replyToChatId,
      replyToChatName: replyToChatName,
      replyToChatType: replyToChatType,
      isSilent: isSilent,
      isViewOnce: isViewOnce,
      ttlSeconds: ttlSeconds,
      topicId: topicId,
      sendAsChatId: sendAsChatId,
      sendAsMode: sendAsMode,
      sendAsAnonymous: sendAsAnonymous,
      threadRootMessageId: threadRootMessageId,
      senderId: senderId,
      senderName: senderName,
      senderAvatarUrl: senderAvatarUrl,
      senderChatName: senderChatName,
      senderChatAvatarUrl: senderChatAvatarUrl,
      width: staged.width,
      height: staged.height,
    );
  }

  Future<Message> _enqueueAudioOrRoundInternal({
    required String localId,
    required String chatId,
    required File stagedFile,
    required String fileName,
    required int fileSize,
    required String messageType,
    required bool isRound,
    required int durationSeconds,
    List<int>? waveform,
    String? replyToMessageId,
    bool isQuote = false,
    String? quoteText,
    int quoteOffset = 0,
    int quoteLength = 0,
    String? replyToSenderId,
    String? replyToSenderName,
    String? replyToContent,
    String replyToMessageType = 'text',
    String? replyToChatId,
    String? replyToChatName,
    String? replyToChatType,
    bool isSilent = false,
    bool isViewOnce = false,
    int ttlSeconds = 0,
    int? topicId,
    String? sendAsChatId,
    String? sendAsMode,
    bool sendAsAnonymous = false,
    String? threadRootMessageId,
    String? senderId,
    String? senderName,
    String? senderAvatarUrl,
    String? senderChatName,
    String? senderChatAvatarUrl,
    int? width,
    int? height,
  }) async {
    final identity = await _resolveSenderIdentity(
      senderId: senderId,
      senderName: senderName,
      senderAvatarUrl: senderAvatarUrl,
    );

    final payloadMap = <String, dynamic>{
      'local_file_path': stagedFile.path,
      'file_size': fileSize,
      'file_name': fileName,
      if (durationSeconds > 0) 'duration': durationSeconds,
      if (waveform != null && waveform.isNotEmpty) 'waveform': waveform,
      if (width != null && width > 0) 'width': width,
      if (height != null && height > 0) 'height': height,
      if (isRound) 'is_round': true,
      if (topicId != null && topicId > 0) 'topic_id': topicId,
      if (sendAsChatId != null && sendAsChatId.isNotEmpty)
        'send_as_chat_id': sendAsChatId,
      if (sendAsMode != null && sendAsMode.isNotEmpty)
        'send_as_mode': sendAsMode,
    };

    final dbMsg = await SyncService().createPendingMessage(
      localIdOverride: localId,
      chatId: chatId,
      senderId: identity.senderId,
      content: '',
      messageType: messageType,
      fileUrl: stagedFile.path,
      fileName: fileName,
      replyToMessageId: replyToMessageId,
      isQuote: isQuote,
      quoteText: quoteText,
      quoteOffset: quoteOffset,
      quoteLength: quoteLength,
      replyToSenderId: replyToSenderId,
      replyToSenderName: replyToSenderName,
      replyToContent: replyToContent,
      replyToMessageType: replyToMessageType,
      replyToChatId: replyToChatId,
      replyToChatName: replyToChatName,
      replyToChatType: replyToChatType,
      isRound: isRound,
      waveform: waveform,
      duration: durationSeconds,
      mediaPayload: payloadMap,
      isSilent: isSilent,
      threadRootMessageId: threadRootMessageId,
      isViewOnce: isViewOnce,
      ttlSeconds: ttlSeconds,
      senderName: identity.senderName,
      senderAvatarUrl: identity.senderAvatarUrl,
      isFromAnonymousAdmin: sendAsAnonymous,
      topicId: topicId,
      senderChatId: sendAsChatId,
      senderChatName: senderChatName,
      senderChatAvatarUrl: senderChatAvatarUrl,
      isOwn: true,
    );

    final msg = Message.fromDbMessage(dbMsg);
    final tracked = _TrackedUploadItem(
      localId: localId,
      chatId: chatId,
      threadRootMessageId: threadRootMessageId,
      content: '',
      messageType: messageType,
      isRound: isRound,
      fileName: fileName,
      localFilePath: stagedFile.path,
      totalBytes: fileSize,
      extraPayload: payloadMap,
      waveform: waveform,
      duration: durationSeconds,
      replyToMessageId: replyToMessageId,
      replyToChatId: replyToChatId,
      isQuote: isQuote,
      quoteText: quoteText,
      quoteOffset: quoteOffset,
      quoteLength: quoteLength,
      isSilent: isSilent,
      isViewOnce: isViewOnce,
      ttlSeconds: ttlSeconds,
      topicId: topicId,
      sendAsChatId: sendAsChatId,
      sendAsMode: sendAsMode,
      sendAsAnonymous: sendAsAnonymous,
      phase: OutgoingUploadPhase.uploading,
    );
    _registerTrackedItem(tracked);

    _emitEvent(MediaSendEvent(
      type: MediaSendEventType.inserted,
      chatId: chatId,
      threadRootMessageId: threadRootMessageId,
      localIds: [localId],
      messages: [msg],
    ));

    unawaited(_runSingleJob(tracked));
    return msg;
  }

  /// Cancels an active or failed single upload or album item and removes it locally.
  Future<void> cancelUpload(String localId) async {
    final item = _items[localId];
    if (item != null) {
      item.cancelled = true;
      try {
        item.cancelToken?.cancel('cancelled_by_user');
      } catch (_) {}
      _setPhase(item, OutgoingUploadPhase.cancelled);
    }

    final db = AppDatabase();
    final dbRow = await db.getMessageByLocalId(localId);
    final chatId = item?.chatId ?? dbRow?.chatId ?? '';
    final groupedId = item?.groupedId ?? dbRow?.groupedId;
    final threadRootId =
        item?.threadRootMessageId ?? dbRow?.threadRootMessageId;
    final cancelledContent = item?.content ?? dbRow?.content ?? '';
    final stagedPath = item?.localFilePath ?? dbRow?.fileUrl;

    await db.deleteMessage(localId);
    await LocalMediaInspector.cleanupStagedFile(stagedPath);

    _clearTrackingForLocalId(localId, chatId);

    if (chatId.isNotEmpty && (threadRootId == null || threadRootId.isEmpty)) {
      await db.refreshChatLastMessageFromDb(chatId, allowClear: true);
    }

    _emitEvent(MediaSendEvent(
      type: MediaSendEventType.cancelled,
      chatId: chatId,
      threadRootMessageId: threadRootId,
      localIds: [localId],
      groupedId: groupedId,
    ));

    // If an album drops from 2 items to 1 surviving item, convert the survivor into
    // a standalone single message cleanly.
    if (groupedId != null && groupedId.isNotEmpty) {
      final job = _albums[groupedId];
      if (job != null) {
        final surviving = job.items.where((i) => !i.cancelled).toList();
        if (surviving.isEmpty) {
          _albums.remove(groupedId);
        } else if (surviving.length == 1) {
          final sole = surviving.first;
          _albums.remove(groupedId);
          sole.groupedId = null;
          if (sole.content.trim().isEmpty && cancelledContent.trim().isNotEmpty) {
            sole.content = cancelledContent;
          }
          await db.updateLocalMessageFields(
            sole.localId,
            groupedId: const Value(null),
            content: sole.content,
          );
          final refreshedRow = await db.getMessageByLocalId(sole.localId);
          final updatedMsg =
              refreshedRow != null ? [Message.fromDbMessage(refreshedRow)] : const <Message>[];
          _updateNotifier(
            sole.localId,
            (p) => p.copyWith(clearGroupedId: true),
          );
          _emitEvent(MediaSendEvent(
            type: MediaSendEventType.albumDowngradedToSingle,
            chatId: chatId,
            threadRootMessageId: threadRootId,
            localIds: [sole.localId],
            messages: updatedMsg,
            groupedId: groupedId,
          ));
        }
      } else if (chatId.isNotEmpty) {
        final remainingRows = await db.getMessagesByGroupedId(chatId, groupedId);
        if (remainingRows.length == 1) {
          final soleRow = remainingRows.first;
          final nextContent = soleRow.content.trim().isEmpty &&
                  cancelledContent.trim().isNotEmpty
              ? cancelledContent
              : soleRow.content;
          await db.updateLocalMessageFields(
            soleRow.localId,
            groupedId: const Value(null),
            content: nextContent,
          );
          final refreshed = await db.getMessageByLocalId(soleRow.localId);
          _emitEvent(MediaSendEvent(
            type: MediaSendEventType.albumDowngradedToSingle,
            chatId: chatId,
            threadRootMessageId: threadRootId,
            localIds: [soleRow.localId],
            messages:
                refreshed != null ? [Message.fromDbMessage(refreshed)] : const [],
            groupedId: groupedId,
          ));
        }
      }
    }
  }

  /// Cancels an entire outgoing album cleanly.
  Future<void> cancelAlbum(String chatId, String groupedId) async {
    final job = _albums.remove(groupedId);
    final localIds = <String>[];

    if (job != null) {
      for (final item in job.items) {
        item.cancelled = true;
        try {
          item.cancelToken?.cancel('album_cancelled');
        } catch (_) {}
        localIds.add(item.localId);
        _setPhase(item, OutgoingUploadPhase.cancelled);
        await LocalMediaInspector.cleanupStagedFile(item.localFilePath);
        _clearTrackingForLocalId(item.localId, chatId);
      }
    } else {
      final rows = await AppDatabase().getMessagesByGroupedId(chatId, groupedId);
      for (final r in rows) {
        localIds.add(r.localId);
        await LocalMediaInspector.cleanupStagedFile(r.fileUrl);
        _clearTrackingForLocalId(r.localId, chatId);
      }
    }

    if (localIds.isNotEmpty) {
      await AppDatabase().deleteMessagesBatch(localIds);
      await AppDatabase().refreshChatLastMessageFromDb(chatId, allowClear: true);
      _emitEvent(MediaSendEvent(
        type: MediaSendEventType.cancelled,
        chatId: chatId,
        threadRootMessageId: job?.threadRootMessageId,
        localIds: localIds,
        groupedId: groupedId,
      ));
    }
  }

  /// Retries a failed message (or its whole album when [localId] belongs to one).
  Future<void> retryMessage(String localId) async {
    final existingItem = _items[localId];
    if (existingItem != null && existingItem.groupedId != null) {
      await retryAlbum(existingItem.chatId, existingItem.groupedId!);
      return;
    }

    final db = AppDatabase();
    final dbRow = await db.getMessageByLocalId(localId);
    if (dbRow == null) return;
    if (dbRow.groupedId != null && dbRow.groupedId!.isNotEmpty) {
      await retryAlbum(dbRow.chatId, dbRow.groupedId!);
      return;
    }

    final tracked = existingItem ?? _reconstructFromDbRow(dbRow);
    tracked.cancelled = false;
    tracked.phase = OutgoingUploadPhase.uploading;
    await db.updateLocalMessageFields(localId, sendStatus: 0);
    _registerTrackedItem(tracked);

    final updatedRow = await db.getMessageByLocalId(localId);
    _emitEvent(MediaSendEvent(
      type: MediaSendEventType.updated,
      chatId: tracked.chatId,
      threadRootMessageId: tracked.threadRootMessageId,
      localIds: [localId],
      messages: updatedRow != null ? [Message.fromDbMessage(updatedRow)] : const [],
    ));

    unawaited(_runSingleJob(tracked));
  }

  /// Retries all unsent items in [groupedId], skipping byte upload for any tile
  /// that already persisted its `remote_file_url`.
  Future<void> retryAlbum(String chatId, String groupedId) async {
    final existingJob = _albums[groupedId];
    final db = AppDatabase();
    _TrackedAlbumJob job;

    if (existingJob != null) {
      if (existingJob.running) return;
      job = existingJob;
      final remaining = job.items.where((i) => !i.cancelled).toList();
      if (remaining.isEmpty) return;
      for (final item in remaining) {
        item.phase = (item.remoteFileUrl != null && item.remoteFileUrl!.isNotEmpty)
            ? OutgoingUploadPhase.waitingAlbumSiblings
            : OutgoingUploadPhase.uploading;
        await db.updateLocalMessageFields(item.localId, sendStatus: 0);
        _registerTrackedItem(item);
      }
    } else {
      final rows = await db.getMessagesByGroupedId(chatId, groupedId);
      if (rows.isEmpty) return;
      final reconstructed = <_TrackedUploadItem>[];
      for (final row in rows) {
        final item = _reconstructFromDbRow(row);
        item.phase = (item.remoteFileUrl != null && item.remoteFileUrl!.isNotEmpty)
            ? OutgoingUploadPhase.waitingAlbumSiblings
            : OutgoingUploadPhase.uploading;
        await db.updateLocalMessageFields(row.localId, sendStatus: 0);
        _registerTrackedItem(item);
        reconstructed.add(item);
      }
      reconstructed.sort((a, b) {
        final ao = (a.extraPayload['album_order'] as num?)?.toInt() ?? 0;
        final bo = (b.extraPayload['album_order'] as num?)?.toInt() ?? 0;
        return ao.compareTo(bo);
      });
      job = _TrackedAlbumJob(
        chatId: chatId,
        groupedId: groupedId,
        threadRootMessageId: reconstructed.first.threadRootMessageId,
        items: reconstructed,
      );
      _albums[groupedId] = job;
    }

    final refreshedRows = await db.getMessagesByGroupedId(chatId, groupedId);
    _emitEvent(MediaSendEvent(
      type: MediaSendEventType.updated,
      chatId: chatId,
      threadRootMessageId: job.threadRootMessageId,
      localIds: refreshedRows.map((r) => r.localId).toList(),
      messages: refreshedRows.map(Message.fromDbMessage).toList(),
      groupedId: groupedId,
    ));

    unawaited(_runAlbumJob(job));
  }

  Future<void> _runSingleJob(_TrackedUploadItem item) async {
    try {
      String? remoteUrl = item.remoteFileUrl;
      Map<String, dynamic>? uploadPayload = item.remoteMediaPayload;
      File? uploadedLocalFile;

      if (remoteUrl == null || remoteUrl.isEmpty) {
        final localPath = item.localFilePath;
        if (localPath == null || localPath.isEmpty) {
          throw const FileUploadException('Local media file path is missing');
        }
        final file = File(localPath);
        if (!await file.exists()) {
          throw FileUploadException('Local file no longer exists: $localPath');
        }

        final uploadResult = await _uploadTrackedItem(item, file);
        if (item.cancelled) return;

        uploadedLocalFile = file;
        remoteUrl = uploadResult.url;
        uploadPayload = uploadResult.toMediaPayload();
        item.remoteFileUrl = remoteUrl;
        item.remoteMediaPayload = uploadPayload;
        item.uploadResult = uploadResult;
        if ((item.duration == null || item.duration! <= 0) &&
            uploadResult.duration > 0) {
          item.duration = uploadResult.duration;
        }

        // Seed MediaCacheManager BEFORE sending the RPC so an early WebSocket
        // echo on the sender device never triggers a re-download.
        if (!kIsWeb && remoteUrl.isNotEmpty) {
          await MediaCacheManager.instance.seedCacheFromFile(
            remoteUrl,
            file,
            deleteSourceIfTemp: false,
            preserveSourceExtension: !FileService.shouldSeedUploadedFile(
              file,
              uploadResult,
            ),
          );
        }
      }

      if (item.cancelled) return;
      _setPhase(item, OutgoingUploadPhase.sendingRpc);

      final rpcPayload = _buildRpcMediaPayload(item, uploadPayload);
      final rpcResult = await _sendSingleMessageRpc(item, remoteUrl, rpcPayload);

      if (item.cancelled) return;

      if (rpcResult['success'] != true) {
        await _markItemFailed(
          item,
          rpcResult['message']?.toString() ?? 'Failed to send message',
        );
        return;
      }

      final sentMsg = rpcResult['message'];
      final serverId = sentMsg is Message ? sentMsg.id : '';
      final finalRemoteUrl = (sentMsg is Message &&
              sentMsg.fileUrl != null &&
              sentMsg.fileUrl!.isNotEmpty)
          ? sentMsg.fileUrl!
          : remoteUrl;

      // Alias-seed finalRemoteUrl only if the RPC response normalized it to a different key.
      if (!kIsWeb &&
          uploadedLocalFile != null &&
          item.uploadResult != null &&
          finalRemoteUrl.isNotEmpty &&
          MediaCacheManager.instance.canonicalCacheKey(finalRemoteUrl) !=
              MediaCacheManager.instance.canonicalCacheKey(remoteUrl)) {
        await MediaCacheManager.instance.seedCacheFromFile(
          finalRemoteUrl,
          uploadedLocalFile,
          deleteSourceIfTemp: false,
          preserveSourceExtension: !FileService.shouldSeedUploadedFile(
            uploadedLocalFile,
            item.uploadResult!,
          ),
        );
      }

      final persistedPayloadStr = rpcPayload != null && rpcPayload.isNotEmpty
          ? jsonEncode(rpcPayload)
          : null;
      if (serverId.isNotEmpty) {
        await SyncService().confirmMessageSent(
          item.localId,
          serverId,
          remoteFileUrl: finalRemoteUrl,
          mediaPayload: persistedPayloadStr,
        );
      } else {
        await AppDatabase().updateLocalMessageFields(
          item.localId,
          fileUrl: finalRemoteUrl,
          mediaPayload: persistedPayloadStr,
          sendStatus: 1,
        );
      }

      if (item.threadRootMessageId == null || item.threadRootMessageId!.isEmpty) {
        await AppDatabase().refreshChatLastMessageFromDb(item.chatId);
      }

      _setPhase(item, OutgoingUploadPhase.sent);
      _clearTrackingForLocalId(item.localId, item.chatId);
      await LocalMediaInspector.cleanupStagedFile(item.localFilePath);

      final normalizedMsg = sentMsg is Message
          ? sentMsg.copyWith(
              localId: item.localId,
              sendStatus: 1,
            )
          : null;

      _emitEvent(MediaSendEvent(
        type: MediaSendEventType.replacedWithServer,
        chatId: item.chatId,
        threadRootMessageId: item.threadRootMessageId,
        localIds: [item.localId],
        messages: normalizedMsg != null ? [normalizedMsg] : const [],
        groupedId: item.groupedId,
      ));
    } on FileUploadCancelledException {
      return;
    } catch (e) {
      if (item.cancelled) return;
      await _markItemFailed(item, e.toString());
    }
  }

  Future<void> _runAlbumJob(_TrackedAlbumJob job) async {
    if (job.running) return;
    job.running = true;

    try {
      final activeItems = job.items.where((i) => !i.cancelled).toList();
      if (activeItems.isEmpty) return;

      // Upload up to 2 files concurrently using a shared index cursor.
      int nextIndex = 0;
      bool anyUploadFailed = false;
      final Map<String, File> localFilesById = {};
      final Map<String, UploadResult> uploadResultsById = {};

      Future<void> worker() async {
        while (true) {
          if (nextIndex >= activeItems.length) return;
          final item = activeItems[nextIndex++];
          if (item.cancelled) continue;

          if (item.remoteFileUrl != null && item.remoteFileUrl!.isNotEmpty) {
            _setPhase(
              item,
              OutgoingUploadPhase.waitingAlbumSiblings,
              sentBytes: item.totalBytes,
              fraction: 1.0,
            );
            continue;
          }

          final localPath = item.localFilePath;
          if (localPath == null || localPath.isEmpty) {
            anyUploadFailed = true;
            await _markItemFailed(item, 'Local file path missing');
            continue;
          }
          final file = File(localPath);
          if (!await file.exists()) {
            if (item.cancelled) continue;
            anyUploadFailed = true;
            await _markItemFailed(item, 'File missing: $localPath');
            continue;
          }
          if (item.cancelled) continue;

          try {
            final res = await _uploadTrackedItem(item, file);
            if (item.cancelled) continue;

            localFilesById[item.localId] = file;
            uploadResultsById[item.localId] = res;
            item.remoteFileUrl = res.url;
            item.remoteMediaPayload = res.toMediaPayload();
            item.uploadResult = res;

            if (!kIsWeb && res.url.isNotEmpty) {
              await MediaCacheManager.instance.seedCacheFromFile(
                res.url,
                file,
                deleteSourceIfTemp: false,
                preserveSourceExtension: !FileService.shouldSeedUploadedFile(
                  file,
                  res,
                ),
              );
            }

            // Persist remote URL in DB so any partial-retry skips already-uploaded tiles.
            final partialPayload = Map<String, dynamic>.from(item.extraPayload)
              ..['remote_file_url'] = res.url
              ..['remote_media_payload'] = item.remoteMediaPayload;
            await AppDatabase().updateLocalMessageFields(
              item.localId,
              mediaPayload: jsonEncode(partialPayload),
            );

            _setPhase(
              item,
              OutgoingUploadPhase.waitingAlbumSiblings,
              sentBytes: item.totalBytes,
              fraction: 1.0,
            );
          } on FileUploadCancelledException {
            continue;
          } catch (e) {
            if (!item.cancelled) {
              anyUploadFailed = true;
              await _markItemFailed(item, e.toString());
            }
          }
        }
      }

      final workers = List.generate(
        _albumUploadConcurrency.clamp(1, activeItems.length),
        (_) => worker(),
      );
      await Future.wait(workers);

      final surviving = job.items.where((i) => !i.cancelled).toList();
      if (surviving.isEmpty || anyUploadFailed) {
        if (anyUploadFailed) {
          for (final item in surviving) {
            _chatActiveLocalIds[job.chatId]?.remove(item.localId);
          }
          revisionNotifier.value++;
        }
        return;
      }

      // If cancellations reduced an album to a single file, finish cleanly via
      // standalone message RPC.
      if (surviving.length == 1) {
        final sole = surviving.first;
        sole.groupedId = null;
        _albums.remove(job.groupedId);
        await _runSingleJob(sole);
        return;
      }

      // All siblings finished upload -> mark all as sendingRpc & submit album.
      for (final item in surviving) {
        _setPhase(item, OutgoingUploadPhase.sendingRpc);
      }

      final primary = surviving.first;
      final rpcResult = await _sendAlbumRpc(job, surviving);

      final currentSurviving = job.items.where((i) => !i.cancelled).toList();
      if (currentSurviving.isEmpty) return;

      if (rpcResult['success'] != true) {
        final errMsg =
            rpcResult['message']?.toString() ?? 'Failed to send media album';
        for (final item in currentSurviving) {
          await _markItemFailed(item, errMsg);
        }
        return;
      }

      final serverMessages =
          (rpcResult['messages'] as List<dynamic>? ?? const <dynamic>[])
              .whereType<Message>()
              .toList();
      final byLocalId = <String, Message>{};
      for (final sm in serverMessages) {
        final lid = sm.localId;
        if (lid != null && lid.isNotEmpty) {
          byLocalId[lid] = sm;
        }
      }

      final confirmedMessages = <Message>[];
      for (var i = 0; i < currentSurviving.length; i++) {
        final item = currentSurviving[i];
        final matched = byLocalId[item.localId] ??
            (i < serverMessages.length ? serverMessages[i] : null);
        final remoteUrl = (matched?.fileUrl != null && matched!.fileUrl!.isNotEmpty)
            ? matched.fileUrl!
            : (item.remoteFileUrl ?? '');
        final localFile = localFilesById[item.localId];
        final ur = uploadResultsById[item.localId];
        if (!kIsWeb &&
            localFile != null &&
            ur != null &&
            remoteUrl.isNotEmpty &&
            MediaCacheManager.instance.canonicalCacheKey(remoteUrl) !=
                MediaCacheManager.instance.canonicalCacheKey(
                  item.remoteFileUrl ?? '',
                )) {
          await MediaCacheManager.instance.seedCacheFromFile(
            remoteUrl,
            localFile,
            deleteSourceIfTemp: false,
            preserveSourceExtension: !FileService.shouldSeedUploadedFile(
              localFile,
              ur,
            ),
          );
        }

        final serverPayload = _buildRpcMediaPayload(item, item.remoteMediaPayload);
        final serverPayloadStr =
            serverPayload != null && serverPayload.isNotEmpty
                ? jsonEncode(serverPayload)
                : null;
        if (matched != null && matched.id.isNotEmpty) {
          await SyncService().confirmMessageSent(
            item.localId,
            matched.id,
            remoteFileUrl: remoteUrl.isNotEmpty ? remoteUrl : null,
            mediaPayload: serverPayloadStr,
          );
          confirmedMessages.add(
            matched.copyWith(localId: item.localId, sendStatus: 1),
          );
        } else {
          await AppDatabase().updateLocalMessageFields(
            item.localId,
            fileUrl: remoteUrl.isNotEmpty ? remoteUrl : null,
            mediaPayload: serverPayloadStr,
            sendStatus: 1,
          );
        }

        _setPhase(item, OutgoingUploadPhase.sent);
        _clearTrackingForLocalId(item.localId, item.chatId);
        await LocalMediaInspector.cleanupStagedFile(item.localFilePath);
      }

      _albums.remove(job.groupedId);
      if (primary.threadRootMessageId == null ||
          primary.threadRootMessageId!.isEmpty) {
        await AppDatabase().refreshChatLastMessageFromDb(job.chatId);
      }

      _emitEvent(MediaSendEvent(
        type: MediaSendEventType.replacedWithServer,
        chatId: job.chatId,
        threadRootMessageId: job.threadRootMessageId,
        localIds: currentSurviving.map((i) => i.localId).toList(),
        messages: confirmedMessages,
        groupedId: job.groupedId,
      ));
    } catch (e) {
      for (final item in job.items.where((i) => !i.cancelled)) {
        await _markItemFailed(item, e.toString());
      }
    } finally {
      job.running = false;
    }
  }

  Future<UploadResult> _uploadTrackedItem(
    _TrackedUploadItem item,
    File file,
  ) async {
    if (item.cancelled || (item.cancelToken?.isCancelled ?? false)) {
      throw const FileUploadCancelledException();
    }
    final token = item.cancelToken ??= CancelToken();
    _setPhase(
      item,
      OutgoingUploadPhase.uploading,
      sentBytes: 0,
      fraction: 0.0,
    );

    void onSendBytes(int sent, int total) {
      if (item.cancelled) return;
      final effectiveTotal = total > 0 ? total : item.totalBytes;
      final fraction =
          effectiveTotal > 0 ? (sent / effectiveTotal).clamp(0.0, 1.0) : 0.0;
      final nowMs = DateTime.now().millisecondsSinceEpoch;
      final shouldEmit = item.lastEmitFraction < 0 ||
          fraction >= 1.0 ||
          (fraction - item.lastEmitFraction).abs() >= 0.01 ||
          (nowMs - item.lastEmitMs) >= 32;
      if (!shouldEmit) return;

      item.lastEmitMs = nowMs;
      item.lastEmitFraction = fraction;
      item.totalBytes = effectiveTotal;
      _updateNotifier(
        item.localId,
        (p) => p.copyWith(
          sentBytes: sent,
          totalBytes: effectiveTotal,
          fraction: fraction,
          phase: OutgoingUploadPhase.uploading,
          clearError: true,
        ),
      );
    }

    if (_uploadOverride != null) {
      return await _uploadOverride!(
        file,
        onSendBytes: onSendBytes,
        cancelToken: token,
      );
    }

    final fileService = _fileServiceOverride ?? FileService();
    return await fileService.uploadFile(
      file,
      cancelToken: token,
      seedCache: false,
      allowDeleteTempSource: false,
      onSendBytes: onSendBytes,
    );
  }

  Future<Map<String, dynamic>> _sendSingleMessageRpc(
    _TrackedUploadItem item,
    String remoteUrl,
    Map<String, dynamic>? rpcPayload,
  ) async {
    final threadRoot = item.threadRootMessageId;
    if (threadRoot != null && threadRoot.isNotEmpty) {
      if (_sendPostCommentOverride != null) {
        final comment = await _sendPostCommentOverride!(
          item.chatId,
          threadRoot,
          item.localId,
          item.content,
          item.messageType,
          remoteUrl,
          item.fileName,
          rpcPayload,
          item.groupedId,
          item.isRound,
          item.duration,
          item.waveform,
        );
        return {
          'success': comment != null,
          if (comment != null) 'message': comment,
          if (comment == null) 'message': 'Failed to post comment',
        };
      }
      final comment = await ChatService.sendPostComment(
        channelId: item.chatId,
        messageId: threadRoot,
        content: item.content,
        localId: item.localId,
        replyToMessageId: item.replyToMessageId,
        isQuote: item.isQuote,
        quoteText: item.quoteText,
        quoteOffset: item.quoteOffset,
        quoteLength: item.quoteLength,
        entities: item.entities,
        fileUrl: remoteUrl,
        fileName: item.fileName,
        messageType: item.messageType,
        hasMediaSpoiler: item.hasMediaSpoiler,
        groupedId: item.groupedId,
        mediaPayload: rpcPayload,
        isRound: item.isRound,
        duration: item.duration,
        waveform: item.waveform,
        sendAsChatId: item.sendAsChatId,
        sendAsMode: item.sendAsMode,
        sendAsAnonymous: item.sendAsAnonymous,
        isSilent: item.isSilent,
      );
      return {
        'success': comment != null,
        if (comment != null) 'message': comment,
        if (comment == null) 'message': 'Failed to post comment',
      };
    }

    if (_sendSingleRpcOverride != null) {
      return await _sendSingleRpcOverride!(
        item.chatId,
        item.localId,
        item.content,
        item.messageType,
        remoteUrl,
        item.fileName,
        rpcPayload,
        item.groupedId,
        item.isRound,
        item.duration,
        item.waveform,
      );
    }

    return await ChatService.sendMessage(
      chatId: item.chatId,
      content: item.content,
      messageType: item.messageType,
      fileUrl: remoteUrl,
      fileName: item.fileName,
      replyToMessageId: item.replyToMessageId,
      replyToChatId: item.replyToChatId,
      localId: item.localId,
      isQuote: item.isQuote,
      quoteText: item.quoteText,
      quoteOffset: item.quoteOffset,
      quoteLength: item.quoteLength,
      entities: item.entities,
      invertMedia: item.invertMedia,
      isRound: item.isRound,
      waveform: item.waveform,
      duration: item.duration,
      groupedId: item.groupedId,
      mediaPayload: rpcPayload,
      isSilent: item.isSilent,
      sendAsAnonymous: item.sendAsAnonymous,
      hasMediaSpoiler: item.hasMediaSpoiler,
      isViewOnce: item.isViewOnce,
      ttlSeconds: item.ttlSeconds,
      effectId: item.effectId,
      topicId: item.topicId,
      sendAsChatId: item.sendAsChatId,
      sendAsMode: item.sendAsMode,
    );
  }

  Future<Map<String, dynamic>> _sendAlbumRpc(
    _TrackedAlbumJob job,
    List<_TrackedUploadItem> surviving,
  ) async {
    final threadRoot = job.threadRootMessageId;
    if (threadRoot != null && threadRoot.isNotEmpty) {
      final results = <Message>[];
      for (final item in surviving) {
        final res = await _sendSingleMessageRpc(
          item,
          item.remoteFileUrl ?? '',
          _buildRpcMediaPayload(item, item.remoteMediaPayload),
        );
        if (res['success'] != true || res['message'] is! Message) {
          return {
            'success': false,
            'message': res['message']?.toString() ?? 'Failed to post comment',
          };
        }
        results.add(res['message'] as Message);
      }
      return {
        'success': true,
        'grouped_id': job.groupedId,
        'messages': results,
      };
    }

    final primary = surviving.first;
    final itemsPayload = surviving.map((item) {
      final rpcMedia = _buildRpcMediaPayload(item, item.remoteMediaPayload);
      return <String, dynamic>{
        'local_id': item.localId,
        'file_url': item.remoteFileUrl ?? '',
        'file_name': item.fileName ?? '',
        'message_type': item.messageType,
        if (item.content.isNotEmpty) 'content': item.content,
        if (rpcMedia != null && rpcMedia.isNotEmpty) 'media_payload': rpcMedia,
      };
    }).toList();

    final caption = primary.content.isNotEmpty ? primary.content : null;

    if (_sendAlbumRpcOverride != null) {
      return await _sendAlbumRpcOverride!(
        job.chatId,
        job.groupedId,
        itemsPayload,
        caption,
      );
    }

    return await ChatService.sendMediaAlbum(
      chatId: job.chatId,
      items: itemsPayload,
      groupedId: job.groupedId,
      caption: caption,
      entities: primary.entities,
      invertMedia: primary.invertMedia,
      replyToMessageId: primary.replyToMessageId,
      replyToChatId: primary.replyToChatId,
      effectId: primary.effectId,
      isSilent: primary.isSilent,
      sendAsAnonymous: primary.sendAsAnonymous,
      hasMediaSpoiler: primary.hasMediaSpoiler,
      topicId: primary.topicId,
      sendAsChatId: primary.sendAsChatId,
      sendAsMode: primary.sendAsMode,
    );
  }

  Future<void> _markItemFailed(
    _TrackedUploadItem item,
    String errorMessage,
  ) async {
    await SyncService().markMessageFailed(item.localId);
    _setPhase(item, OutgoingUploadPhase.failed, errorMessage: errorMessage);
    _chatActiveLocalIds[item.chatId]?.remove(item.localId);
    _chatFailedLocalIds
        .putIfAbsent(item.chatId, () => <String>{})
        .add(item.localId);
    revisionNotifier.value++;

    final row = await AppDatabase().getMessageByLocalId(item.localId);
    _emitEvent(MediaSendEvent(
      type: MediaSendEventType.failed,
      chatId: item.chatId,
      threadRootMessageId: item.threadRootMessageId,
      localIds: [item.localId],
      messages: row != null ? [Message.fromDbMessage(row)] : const [],
      groupedId: item.groupedId,
    ));
  }

  _TrackedUploadItem _reconstructFromDbRow(DbMessage row) {
    Map<String, dynamic> payload = {};
    if (row.mediaPayload != null && row.mediaPayload!.isNotEmpty) {
      try {
        final dec = jsonDecode(row.mediaPayload!);
        if (dec is Map) {
          payload = Map<String, dynamic>.from(dec);
        }
      } catch (_) {}
    }

    List<int>? waveform;
    if (payload['waveform'] is List) {
      waveform = (payload['waveform'] as List).map((e) => (e as num).toInt()).toList();
    }
    List<MessageEntity> entities = const [];
    if (row.entities != null && row.entities!.isNotEmpty) {
      try {
        final dec = jsonDecode(row.entities!);
        if (dec is List) {
          entities = dec
              .whereType<Map>()
              .map((e) => MessageEntity.fromJson(Map<String, dynamic>.from(e)))
              .toList();
        }
      } catch (_) {}
    }

    final rawRemoteUrl = payload['remote_file_url']?.toString();
    final rawRemoteMedia = payload['remote_media_payload'] is Map
        ? Map<String, dynamic>.from(payload['remote_media_payload'] as Map)
        : null;

    return _TrackedUploadItem(
      localId: row.localId,
      chatId: row.chatId,
      groupedId: row.groupedId,
      threadRootMessageId: row.threadRootMessageId,
      content: row.content,
      messageType: row.messageType,
      isRound: row.isRound,
      fileName: row.fileName,
      localFilePath: payload['local_file_path']?.toString() ?? row.fileUrl,
      totalBytes: (payload['file_size'] as num?)?.toInt() ?? 0,
      remoteFileUrl:
          (rawRemoteUrl != null && rawRemoteUrl.isNotEmpty) ? rawRemoteUrl : null,
      remoteMediaPayload: rawRemoteMedia,
      extraPayload: payload,
      waveform: waveform,
      duration: (payload['duration'] as num?)?.toInt(),
      entities: entities,
      invertMedia: row.invertMedia,
      replyToMessageId: row.replyToMessageId,
      replyToChatId: row.replyToChatId,
      isQuote: row.isQuote,
      quoteText: row.quoteText,
      quoteOffset: row.quoteOffset,
      quoteLength: row.quoteLength,
      hasMediaSpoiler: row.hasMediaSpoiler,
      isSilent: row.isSilent,
      isViewOnce: row.isViewOnce,
      ttlSeconds: row.ttlSeconds,
      effectId: row.effectId,
      topicId: row.topicId ?? (payload['topic_id'] as num?)?.toInt(),
      sendAsChatId: row.senderChatId ?? payload['send_as_chat_id']?.toString(),
      sendAsMode: payload['send_as_mode']?.toString(),
      sendAsAnonymous: row.isFromAnonymousAdmin,
      phase: OutgoingUploadPhase.uploading,
    );
  }

  Map<String, dynamic> _buildInitialMediaPayload({
    required OutboxStagedFile staged,
    int? albumOrder,
    String? sendAsChatId,
    String? sendAsMode,
    int? topicId,
  }) {
    return <String, dynamic>{
      'local_file_path': staged.file.path,
      'file_size': staged.fileSize,
      'file_name': staged.fileName,
      'mime_type': staged.mimeType,
      if (staged.width != null && staged.width! > 0) 'width': staged.width,
      if (staged.height != null && staged.height! > 0) 'height': staged.height,
      if (staged.durationSeconds != null && staged.durationSeconds! > 0)
        'duration': staged.durationSeconds,
      if (albumOrder != null) 'album_order': albumOrder,
      if (topicId != null && topicId > 0) 'topic_id': topicId,
      if (sendAsChatId != null && sendAsChatId.isNotEmpty)
        'send_as_chat_id': sendAsChatId,
      if (sendAsMode != null && sendAsMode.isNotEmpty)
        'send_as_mode': sendAsMode,
    };
  }

  Map<String, dynamic>? _buildRpcMediaPayload(
    _TrackedUploadItem item,
    Map<String, dynamic>? uploadPayload,
  ) {
    final map = <String, dynamic>{};
    if (uploadPayload != null) {
      map.addAll(uploadPayload);
    }
    for (final entry in item.extraPayload.entries) {
      if (entry.key == 'local_file_path' ||
          entry.key == 'original_path' ||
          entry.key == 'remote_file_url' ||
          entry.key == 'remote_media_payload' ||
          entry.key == 'album_order' ||
          entry.key == 'send_as_chat_id' ||
          entry.key == 'send_as_mode' ||
          entry.key == 'topic_id') {
        continue;
      }
      map.putIfAbsent(entry.key, () => entry.value);
    }
    return map.isNotEmpty ? map : null;
  }

  void _registerTrackedItem(_TrackedUploadItem item) {
    if (item.cancelToken == null || item.cancelToken!.isCancelled) {
      item.cancelToken = CancelToken();
    }
    _items[item.localId] = item;
    _chatFailedLocalIds[item.chatId]?.remove(item.localId);
    _chatActiveLocalIds
        .putIfAbsent(item.chatId, () => <String>{})
        .add(item.localId);
    _updateNotifier(
      item.localId,
      (p) => p.copyWith(
        groupedId: item.groupedId,
        totalBytes: item.totalBytes,
        phase: item.phase,
        fraction: item.phase == OutgoingUploadPhase.waitingAlbumSiblings ? 1.0 : 0.0,
        clearError: true,
      ),
      fallbackChatId: item.chatId,
    );
    revisionNotifier.value++;
  }

  void _clearTrackingForLocalId(String localId, String chatId) {
    _items.remove(localId);
    _chatActiveLocalIds[chatId]?.remove(localId);
    _chatFailedLocalIds[chatId]?.remove(localId);
    revisionNotifier.value++;
  }

  void _setPhase(
    _TrackedUploadItem item,
    OutgoingUploadPhase phase, {
    int? sentBytes,
    double? fraction,
    String? errorMessage,
  }) {
    item.phase = phase;
    _updateNotifier(
      item.localId,
      (p) => p.copyWith(
        groupedId: item.groupedId,
        phase: phase,
        sentBytes: sentBytes ?? p.sentBytes,
        fraction: fraction ?? p.fraction,
        errorMessage: errorMessage,
        clearError: errorMessage == null,
      ),
      fallbackChatId: item.chatId,
    );
  }

  void _updateNotifier(
    String localId,
    OutgoingUploadProgress Function(OutgoingUploadProgress current) transform, {
    String? fallbackChatId,
  }) {
    final notifier = _progressNotifiers[localId] ??
        ValueNotifier<OutgoingUploadProgress>(
          OutgoingUploadProgress(
            localId: localId,
            chatId: _items[localId]?.chatId ?? fallbackChatId ?? '',
            groupedId: _items[localId]?.groupedId,
            sentBytes: 0,
            totalBytes: _items[localId]?.totalBytes ?? 0,
            fraction: 0.0,
            phase: _items[localId]?.phase ?? OutgoingUploadPhase.uploading,
          ),
        );
    _progressNotifiers[localId] = notifier;
    notifier.value = transform(notifier.value);
  }

  void _emitEvent(MediaSendEvent event) {
    if (!_eventController.isClosed) {
      _eventController.add(event);
    }
  }

  Future<({String senderId, String? senderName, String? senderAvatarUrl})>
      _resolveSenderIdentity({
    String? senderId,
    String? senderName,
    String? senderAvatarUrl,
  }) async {
    final acct = AccountManager().currentAccount;
    final resolvedId = (senderId != null && senderId.isNotEmpty)
        ? senderId
        : (acct?.userId ?? await AuthService.getUserId() ?? '');
    final resolvedName = (senderName != null && senderName.isNotEmpty)
        ? senderName
        : acct?.displayName;
    final resolvedAvatar =
        (senderAvatarUrl != null && senderAvatarUrl.isNotEmpty)
            ? senderAvatarUrl
            : acct?.avatarUrl;
    return (
      senderId: resolvedId,
      senderName: resolvedName,
      senderAvatarUrl: resolvedAvatar,
    );
  }
}
