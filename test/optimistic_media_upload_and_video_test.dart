// ignore_for_file: depend_on_referenced_packages
import 'dart:async';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart' show SynchronousFuture, Uint8List;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';
import 'package:theaver/config/app_config.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/models/theav_media_item.dart';
import 'package:theaver/services/account_manager.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/database/app_database.dart';
import 'package:theaver/services/file_service.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/media_cache_manager.dart';
import 'package:theaver/services/media_send_coordinator.dart';
import 'package:theaver/services/settings_service.dart';
import 'package:theaver/widgets/chat/chat_input_bar.dart';
import 'package:theaver/widgets/media_viewer/theav_media_video_surface.dart';
import 'package:theaver/widgets/message/document_message_widget.dart';
import 'package:theaver/widgets/message/telegram_upload_progress.dart';
import 'package:provider/provider.dart';

class _TestPathProviderPlatform extends Fake
    with MockPlatformInterfaceMixin
    implements PathProviderPlatform {
  final Directory rootDir;
  _TestPathProviderPlatform(this.rootDir);

  @override
  Future<String?> getApplicationCachePath() async => rootDir.path;

  @override
  Future<String?> getApplicationDocumentsPath() async => rootDir.path;

  @override
  Future<String?> getApplicationSupportPath() async => rootDir.path;

  @override
  Future<String?> getTemporaryPath() async => rootDir.path;
}

class _SyncL10nDelegate extends LocalizationsDelegate<AppLocalizations> {
  const _SyncL10nDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(AppLocalizations(locale));

  @override
  bool shouldReload(_SyncL10nDelegate old) => false;
}

class _DummyGlassProvider extends LiquidGlassProvider {
  @override
  GlassMode get mode => GlassMode.disabled;

  @override
  bool get enabled => false;

  @override
  bool get isLite => false;

  @override
  bool get isFull => false;
}

class _FailingVideoPlayerPlatform extends VideoPlayerPlatform
    with MockPlatformInterfaceMixin {
  @override
  Future<void> init() async {}

  @override
  Future<void> dispose(int playerId) async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    throw PlatformException(code: 'video_error', message: 'stream failed');
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => const Stream.empty();
}

class _ScriptedHttpAdapter implements HttpClientAdapter {
  _ScriptedHttpAdapter(this.handler);

  final Future<ResponseBody> Function(RequestOptions options) handler;

  @override
  void close({bool force = false}) {}

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) =>
      handler(options);
}

Uint8List _minimalPngBytes() {
  // Valid 1x1 PNG header + IDAT so pure-Dart PNG sniffer parses (1, 1) reliably.
  return Uint8List.fromList(<int>[
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    0x00, 0x00, 0x00, 0x0D, 0x49, 0x48, 0x44, 0x52,
    0x00, 0x00, 0x00, 0x20, 0x00, 0x00, 0x00, 0x18,
    0x08, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
    0x00,
  ]);
}

Widget _wrapTestApp(Widget child) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<LiquidGlassProvider>.value(
        value: _DummyGlassProvider(),
      ),
    ],
    child: MaterialApp(
      locale: const Locale('ru'),
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        _SyncL10nDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: Scaffold(body: child),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tempDir;
  late HttpClientAdapter originalCacheAdapter;

  setUpAll(() {
    originalCacheAdapter = MediaCacheManager.instance.dioForTesting.httpClientAdapter;
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    tempDir = await Directory.systemTemp.createTemp('optimistic_media_test_');
    PathProviderPlatform.instance = _TestPathProviderPlatform(tempDir);

    await AccountManager().init();
    if (AccountManager().hasAccount('test_user_001')) {
      await AccountManager().removeAccount('test_user_001');
    }
    await AccountManager().addAccount(Account(
      userId: 'test_user_001',
      token: 'test_token_offline_mode',
      username: 'admin',
      displayName: 'Test Admin',
      lastLogin: DateTime.now(),
    ));

    await AppDatabase.closeAll();
    AppDatabase.setActiveUser('test_user_001');
    AppDatabase.setTestingInstance(
      'test_user_001',
      AppDatabase.forTesting(NativeDatabase.memory(), userId: 'test_user_001'),
    );

    await AppDatabase().saveChat(ChatsCompanion.insert(
      chatId: 'chat_1',
      chatType: 'private',
      name: 'Test Peer',
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    ));

    MediaCacheManager.instance.clearMemoryCache();
    MediaSendCoordinator.instance.resetForTesting();
  });

  tearDown(() async {
    MediaCacheManager.instance.dioForTesting.httpClientAdapter = originalCacheAdapter;
    MediaSendCoordinator.instance.resetForTesting();
    MediaCacheManager.instance.clearMemoryCache();
    await AppDatabase.closeAll();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  group('1. AppConfig.isLocalFilePath & Video Format Guards', () {
    test('preserves Unix, Windows, and file:// local paths without rewriting', () {
      const localPaths = [
        '/mnt/wsl/Glinuxhomevhdx/clip.mp4',
        '/data/user/0/app.theaver/files/outbox_files/test.jpg',
        '/storage/emulated/0/Download/doc.pdf',
        r'C:\Users\mootsasa\Videos\sample.mp4',
        'file:///var/mobile/Containers/clip.mp4',
        'content://media/external/video/media/42',
      ];

      for (final path in localPaths) {
        expect(AppConfig.isLocalFilePath(path), isTrue, reason: 'local: $path');
        expect(AppConfig.resolveMediaUrl(path), path);
      }

      expect(AppConfig.isLocalFilePath('/media/videos/clip.mp4'), isFalse);
      expect(AppConfig.isLocalFilePath('/api/files/download/videos/clip.mp4'), isFalse);
      expect(
        AppConfig.resolveMediaUrl('/media/videos/clip.mp4'),
        'https://storage.theaver.app/media/videos/clip.mp4',
      );
    });

    test('FileService.shouldSeedUploadedFile skips transcoded non-MP4 sources', () {
      final movFile = File(p.join(tempDir.path, 'iphone_clip.mov'));
      final webmFile = File(p.join(tempDir.path, 'screen.webm'));
      final mp4File = File(p.join(tempDir.path, 'direct.mp4'));
      final jpgFile = File(p.join(tempDir.path, 'photo.jpg'));

      final mp4Result = UploadResult(
        fileId: 1,
        objectName: 'videos/out.mp4',
        url: 'https://storage.theaver.app/media/videos/out.mp4',
        fileName: 'out.mp4',
        mimeType: 'video/mp4',
        size: 1024,
      );
      final jpgResult = UploadResult(
        fileId: 2,
        objectName: 'images/out.jpg',
        url: 'https://storage.theaver.app/media/images/out.jpg',
        fileName: 'out.jpg',
        mimeType: 'image/jpeg',
        size: 512,
      );

      expect(FileService.shouldSeedUploadedFile(movFile, mp4Result), isFalse);
      expect(FileService.shouldSeedUploadedFile(webmFile, mp4Result), isFalse);
      expect(FileService.shouldSeedUploadedFile(mp4File, mp4Result), isTrue);
      expect(FileService.shouldSeedUploadedFile(jpgFile, jpgResult), isTrue);
    });
  });

  group('2. MediaCacheManager Deduplication & Authenticated Fallback', () {
    test('deduplicates concurrent /media/ downloads directly via /api/files/download and falls back from expired presigned 403', () async {
      final expectedBytes = Uint8List.fromList(List<int>.generate(256, (i) => i % 251));
      int directHits = 0;
      int apiFallbackHits = 0;
      String? capturedAuthHeader;

      MediaCacheManager.instance.dioForTesting.httpClientAdapter = _ScriptedHttpAdapter(
        (options) async {
          final urlStr = options.uri.toString();
          if (urlStr.contains('/api/files/download/')) {
            apiFallbackHits++;
            capturedAuthHeader = options.headers['Authorization']?.toString();
            await Future<void>.delayed(const Duration(milliseconds: 25));
            return ResponseBody.fromBytes(
              expectedBytes,
              200,
              headers: {
                Headers.contentLengthHeader: ['${expectedBytes.length}'],
              },
            );
          }
          if (urlStr.contains('/presigned')) {
            return ResponseBody.fromString('{"error":"forbidden"}', 403);
          }
          directHits++;
          await Future<void>.delayed(const Duration(milliseconds: 20));
          return ResponseBody.fromString('AccessDenied', 403);
        },
      );

      // 1) Unsigned /media/ URL goes straight to authenticated /api/files/download
      // and deduplicates concurrent callers to 1 network request.
      const protectedUrl = 'https://storage.theaver.app/media/videos/test_private.mp4';
      final results = await Future.wait([
        MediaCacheManager.instance.downloadMedia(protectedUrl),
        MediaCacheManager.instance.downloadMedia(protectedUrl),
      ]);

      expect(results[0], isNotNull);
      expect(results[1], isNotNull);
      expect(results[0]!.path, results[1]!.path);
      expect(await results[0]!.readAsBytes(), expectedBytes);
      expect(directHits, 0);
      expect(apiFallbackHits, 1);
      expect(capturedAuthHeader, 'Bearer test_token_offline_mode');

      // 2) Expired presigned URL returns 403 -> falls back to /api/files/download.
      const expiredPresignedUrl =
          'https://storage.theaver.app/media/videos/expired_private.mp4?X-Amz-Signature=deadbeef';
      final expiredFile = await MediaCacheManager.instance.downloadMedia(
        expiredPresignedUrl,
      );
      expect(expiredFile, isNotNull);
      expect(await expiredFile!.readAsBytes(), expectedBytes);
      expect(directHits, 1);
      expect(apiFallbackHits, 2);
    });
  });

  group('3. Optimistic Media Sending, Progress, Sibling Wait, Cancel, Failure & Retry', () {
    test('enqueue single image & document inserts Frame-0 DB rows, streams progress, confirms & cleans up', () async {
      final photoFile = File(p.join(tempDir.path, 'sample.png'));
      await photoFile.writeAsBytes(_minimalPngBytes());
      final docFile = File(p.join(tempDir.path, 'report.pdf'));
      await docFile.writeAsBytes(Uint8List.fromList(List.filled(2048, 65)));

      final photoGate = Completer<void>();
      final events = <MediaSendEvent>[];
      final sub = MediaSendCoordinator.instance.events.listen(events.add);

      MediaSendCoordinator.instance.configureForTesting(
        uploadOverride: (file, {onSendBytes, cancelToken}) async {
          onSendBytes?.call(512, 1024);
          if (file.path.endsWith('.png')) {
            await photoGate.future;
          }
          onSendBytes?.call(1024, 1024);
          return UploadResult(
            fileId: 10,
            objectName: 'files/${p.basename(file.path)}',
            url: 'https://storage.theaver.app/media/files/${p.basename(file.path)}',
            fileName: p.basename(file.path),
            mimeType: file.path.endsWith('.png') ? 'image/png' : 'application/pdf',
            size: 1024,
          );
        },
        sendSingleRpcOverride: (chatId, localId, content, messageType, fileUrl,
            fileName, mediaPayload, groupedId, isRound, duration, waveform) async {
          return {
            'success': true,
            'message': Message(
              id: 'srv_$localId',
              chatId: chatId,
              senderId: 'test_user_001',
              content: content,
              messageType: messageType,
              isEdited: false,
              createdAt: DateTime.now().toUtc().toIso8601String(),
              senderName: 'Test Admin',
              fileUrl: fileUrl,
              fileName: fileName,
              localId: localId,
              sendStatus: 1,
            ),
          };
        },
      );

      final inserted = await MediaSendCoordinator.instance.enqueueMediaOrFiles(
        chatId: 'chat_1',
        files: [photoFile],
        caption: 'Look at this',
      );
      expect(inserted.length, 1);
      final msg = inserted.first;
      expect(msg.sendStatus, 0);
      expect(msg.messageType, 'image');
      expect(msg.mediaWidth, 32);
      expect(msg.mediaHeight, 24);
      expect(MediaSendCoordinator.instance.getChatSendStatusOverride('chat_1'), 0);

      // Pump microtasks so upload callback emits 512/1024 while blocked on gate.
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final snap = MediaSendCoordinator.instance.currentProgress(msg.localId!);
      expect(snap, isNotNull);
      expect(snap!.sentBytes, 512);
      expect(snap.fraction, closeTo(0.5, 0.01));

      photoGate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 40));

      final confirmedRow = await AppDatabase().getMessageByLocalId(msg.localId!);
      expect(confirmedRow, isNotNull);
      expect(confirmedRow!.sendStatus, 1);
      expect(confirmedRow.serverId, 'srv_${msg.localId}');
      expect(MediaSendCoordinator.instance.getChatSendStatusOverride('chat_1'), isNull);
      expect(
        events.any((e) => e.type == MediaSendEventType.replacedWithServer),
        isTrue,
      );

      // Also verify document flow sets sendStatus == 0 then 1 cleanly.
      final docInserted = await MediaSendCoordinator.instance.enqueueMediaOrFiles(
        chatId: 'chat_1',
        files: [docFile],
        asDocument: true,
      );
      expect(docInserted.first.messageType, 'file');
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final docRow = await AppDatabase().getMessageByLocalId(docInserted.first.localId!);
      expect(docRow!.sendStatus, 1);

      await sub.cancel();
    });

    test('album shows waitingAlbumSiblings (checkmark), preserves uploaded tiles on retry, and downgrades 2->1 on cancel', () async {
      final f1 = File(p.join(tempDir.path, 'a1.png'))..writeAsBytesSync(_minimalPngBytes());
      final f2 = File(p.join(tempDir.path, 'a2.png'))..writeAsBytesSync(_minimalPngBytes());
      final f3 = File(p.join(tempDir.path, 'a3.png'))..writeAsBytesSync(_minimalPngBytes());

      final f2Gate = Completer<void>();
      bool failF2Once = true;
      int f1Uploads = 0;
      int f2Uploads = 0;
      int f3Uploads = 0;

      MediaSendCoordinator.instance.configureForTesting(
        uploadOverride: (file, {onSendBytes, cancelToken}) async {
          final name = p.basename(file.path);
          if (name.contains('a1.png')) {
            f1Uploads++;
            onSendBytes?.call(100, 100);
          } else if (name.contains('a2.png')) {
            f2Uploads++;
            onSendBytes?.call(40, 100);
            if (!f2Gate.isCompleted) {
              await f2Gate.future;
            }
            if (failF2Once) {
              failF2Once = false;
              throw const FileUploadException('Simulated transient network drop');
            }
            onSendBytes?.call(100, 100);
          } else {
            f3Uploads++;
            onSendBytes?.call(50, 100);
            final c = Completer<void>();
            cancelToken?.whenCancel.then((_) {
              if (!c.isCompleted) c.complete();
            });
            await c.future;
            throw const FileUploadCancelledException();
          }
          return UploadResult(
            fileId: name.hashCode.abs(),
            objectName: 'images/$name',
            url: 'https://storage.theaver.app/media/images/$name',
            fileName: name,
            mimeType: 'image/png',
            size: 100,
          );
        },
        sendAlbumRpcOverride: (chatId, groupedId, items, caption) async {
          final now = DateTime.now().toUtc().toIso8601String();
          return {
            'success': true,
            'grouped_id': groupedId,
            'messages': items.map((it) {
              final lid = it['local_id']?.toString() ?? '';
              return Message(
                id: 'srv_$lid',
                chatId: chatId,
                senderId: 'test_user_001',
                content: it['content']?.toString() ?? '',
                messageType: 'image',
                isEdited: false,
                createdAt: now,
                senderName: 'Test Admin',
                fileUrl: it['file_url']?.toString(),
                fileName: it['file_name']?.toString(),
                localId: lid,
                groupedId: groupedId,
                sendStatus: 1,
              );
            }).toList(),
          };
        },
      );

      final inserted = await MediaSendCoordinator.instance.enqueueMediaOrFiles(
        chatId: 'chat_1',
        files: [f1, f2, f3],
        caption: 'Trip photos',
      );
      expect(inserted.length, 3);
      final groupedId = inserted.first.groupedId!;
      final id1 = inserted[0].localId!;
      final id2 = inserted[1].localId!;
      final id3 = inserted[2].localId!;

      // Let tile 1 finish while tile 2 pauses on gate and tile 3 is in flight.
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(
        MediaSendCoordinator.instance.currentProgress(id1)!.phase,
        OutgoingUploadPhase.waitingAlbumSiblings,
      );

      // Cancel tile 3 while tile 2 fails.
      await MediaSendCoordinator.instance.cancelUpload(id3);
      expect(await AppDatabase().getMessageByLocalId(id3), isNull);

      f2Gate.complete();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      final row2Failed = await AppDatabase().getMessageByLocalId(id2);
      expect(row2Failed!.sendStatus, 2);
      expect(MediaSendCoordinator.instance.getChatSendStatusOverride('chat_1'), 2);
      expect(f1Uploads, 1);
      expect(f2Uploads, 1);
      expect(f3Uploads, 1);

      // Retry album: tile 1 MUST skip byte upload (already saved remote_file_url);
      // only tile 2 re-uploads and then album sends with 2 surviving items!
      final retryDoneFuture = MediaSendCoordinator.instance.events
          .firstWhere((e) =>
              e.type == MediaSendEventType.replacedWithServer &&
              e.groupedId == groupedId)
          .timeout(const Duration(seconds: 3));
      await MediaSendCoordinator.instance.retryAlbum('chat_1', groupedId);
      await retryDoneFuture;

      expect(f1Uploads, 1);
      expect(f2Uploads, 2);
      expect((await AppDatabase().getMessageByLocalId(id1))!.sendStatus, 1);
      expect((await AppDatabase().getMessageByLocalId(id2))!.sendStatus, 1);
      expect(MediaSendCoordinator.instance.getChatSendStatusOverride('chat_1'), isNull);
    });

    test('cancelling one item of a 2-item album downgrades the survivor to standalone', () async {
      final f1 = File(p.join(tempDir.path, 'pair1.png'))..writeAsBytesSync(_minimalPngBytes());
      final f2 = File(p.join(tempDir.path, 'pair2.png'))..writeAsBytesSync(_minimalPngBytes());
      final uploadGate = Completer<void>();

      MediaSendCoordinator.instance.configureForTesting(
        uploadOverride: (file, {onSendBytes, cancelToken}) async {
          if (file.path.contains('pair1')) {
            final c = Completer<void>();
            cancelToken?.whenCancel.then((_) {
              if (!c.isCompleted) c.complete();
            });
            await c.future;
            throw const FileUploadCancelledException();
          }
          await uploadGate.future;
          return UploadResult(
            fileId: 99,
            objectName: 'images/pair2.png',
            url: 'https://storage.theaver.app/media/images/pair2.png',
            fileName: 'pair2.png',
            mimeType: 'image/png',
            size: 128,
          );
        },
        sendSingleRpcOverride: (chatId, localId, content, messageType, fileUrl,
            fileName, mediaPayload, groupedId, isRound, duration, waveform) async {
          return {
            'success': true,
            'message': Message(
              id: 'srv_$localId',
              chatId: chatId,
              senderId: 'test_user_001',
              content: content,
              messageType: messageType,
              isEdited: false,
              createdAt: DateTime.now().toUtc().toIso8601String(),
              senderName: 'Test Admin',
              fileUrl: fileUrl,
              fileName: fileName,
              localId: localId,
              groupedId: groupedId,
              sendStatus: 1,
            ),
          };
        },
      );

      final inserted = await MediaSendCoordinator.instance.enqueueMediaOrFiles(
        chatId: 'chat_1',
        files: [f1, f2],
        caption: 'Preserved caption',
      );
      expect(inserted.length, 2);
      final id1 = inserted[0].localId!;
      final id2 = inserted[1].localId!;
      expect(inserted[0].groupedId, isNotNull);

      // Cancel primary tile -> survivor inherits caption and loses groupedId!
      await MediaSendCoordinator.instance.cancelUpload(id1);
      final survivor = await AppDatabase().getMessageByLocalId(id2);
      expect(survivor, isNotNull);
      expect(survivor!.groupedId, isNull);
      expect(survivor.content, 'Preserved caption');

      final soleDoneFuture = MediaSendCoordinator.instance.events
          .firstWhere((e) =>
              e.type == MediaSendEventType.replacedWithServer &&
              e.localIds.contains(id2))
          .timeout(const Duration(seconds: 3));
      uploadGate.complete();
      await soleDoneFuture;
      final sent = await AppDatabase().getMessageByLocalId(id2);
      expect(sent!.sendStatus, 1);
    });
  });

  group('4. UI Widgets: TelegramRadialUploadIndicator, DocumentMessageWidget, ChatInputBar & VideoSurface', () {
    testWidgets('TelegramMediaUploadOverlay shows byte progress, checkmark on sibling wait, and Retry on failure', (tester) async {
      late File f;
      final uploadGate = Completer<void>();

      late String lid;
      await tester.runAsync(() async {
        f = File(p.join(tempDir.path, 'ui.png'))..writeAsBytesSync(_minimalPngBytes());
        MediaSendCoordinator.instance.configureForTesting(
          uploadOverride: (file, {onSendBytes, cancelToken}) async {
            onSendBytes?.call(1024, 4096);
            await uploadGate.future;
            throw const FileUploadException('upload fail');
          },
        );
        final inserted = await MediaSendCoordinator.instance.enqueueMediaOrFiles(
          chatId: 'chat_1',
          files: [f],
        );
        lid = inserted.first.localId!;
        await Future<void>.delayed(const Duration(milliseconds: 20));
      });

      await tester.pumpWidget(_wrapTestApp(
        SizedBox(
          width: 240,
          height: 180,
          child: TelegramMediaUploadOverlay(
            localId: lid,
            chatId: 'chat_1',
            fileSize: 4096,
            sendStatus: 0,
          ),
        ),
      ));
      await tester.pump();

      expect(find.byIcon(Icons.close_rounded), findsOneWidget);
      expect(find.textContaining('/'), findsOneWidget);

      await tester.runAsync(() async {
        final failedFuture = MediaSendCoordinator.instance.events
            .firstWhere((e) =>
                e.type == MediaSendEventType.failed && e.localIds.contains(lid))
            .timeout(const Duration(seconds: 3));
        uploadGate.complete();
        await failedFuture;
      });
      await tester.pump();

      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);

      // DocumentMessageWidget while sendStatus == 2 renders Retry indicator cleanly.
      await tester.pumpWidget(_wrapTestApp(
        DocumentMessageWidget(
          fileUrl: f.path,
          fileName: 'ui.pdf',
          fileSize: 4096,
          localId: lid,
          sendStatus: 2,
        ),
      ));
      await tester.pump();
      expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('ChatInputBar renders no blocking LinearProgressIndicator during normal chat composition', (tester) async {
      final controller = TextEditingController();
      await tester.pumpWidget(_wrapTestApp(
        ChatInputBar(
          controller: controller,
          onSend: () {},
          isUploading: false,
        ),
      ));
      await tester.pump();
      expect(find.byType(LinearProgressIndicator), findsNothing);
      controller.dispose();
    });

    testWidgets('TheavMediaVideoSurface stays idle when isActive is false and shows Retry on network failure', (tester) async {
      final prevPlatform = VideoPlayerPlatform.instance;
      VideoPlayerPlatform.instance = _FailingVideoPlayerPlatform();
      addTearDown(() => VideoPlayerPlatform.instance = prevPlatform);

      int httpHits = 0;
      MediaCacheManager.instance.dioForTesting.httpClientAdapter = _ScriptedHttpAdapter(
        (options) async {
          httpHits++;
          return ResponseBody.fromString('not found', 404);
        },
      );

      const item = TheavMediaItem(
        id: 'vid_1',
        kind: TheavMediaKind.video,
        url: 'https://storage.theaver.app/media/videos/broken.mp4',
        heroTag: 'hero_vid_1',
      );

      await tester.pumpWidget(_wrapTestApp(
        const SizedBox(
          width: 320,
          height: 320,
          child: TheavMediaVideoSurface(
            item: item,
            isActive: false,
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 50));
      expect(httpHits, 0);

      // Activate page -> triggers load & falls back cleanly to matte Retry UI on error.
      await tester.pumpWidget(_wrapTestApp(
        const SizedBox(
          width: 320,
          height: 320,
          child: TheavMediaVideoSurface(
            item: item,
            isActive: true,
          ),
        ),
      ));
      for (int i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 25)),
        );
        await tester.pump(const Duration(milliseconds: 50));
        if (find.text('Повторить').evaluate().isNotEmpty) break;
      }
      expect(httpHits, greaterThan(0));
      expect(find.text('Повторить'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });

  group('5. Single-Pass Media Caching & Zero Sender Re-Downloads', () {
    test('concurrent downloads across canonical URL variants share 1 HTTP GET', () async {
      final payload = Uint8List.fromList(List<int>.generate(512, (i) => i % 253));
      int httpHits = 0;

      MediaCacheManager.instance.dioForTesting.httpClientAdapter = _ScriptedHttpAdapter(
        (options) async {
          httpHits++;
          await Future<void>.delayed(const Duration(milliseconds: 25));
          return ResponseBody.fromBytes(
            payload,
            200,
            headers: {
              Headers.contentLengthHeader: ['${payload.length}'],
            },
          );
        },
      );

      final results = await Future.wait([
        MediaCacheManager.instance.downloadMedia('/media/videos/net.mp4'),
        MediaCacheManager.instance.downloadMedia(
          'https://storage.theaver.app/media/videos/net.mp4?X-Amz-Signature=abc123',
        ),
      ]);

      expect(results[0], isNotNull);
      expect(results[1], isNotNull);
      expect(results[0]!.path, results[1]!.path);
      expect(httpHits, 1);

      // Subsequent reads across API proxy & localhost forms hit disk cache with 0 network I/O.
      final apiHit = await MediaCacheManager.instance.downloadMedia(
        'https://api.theaver.app/api/files/download/videos/net.mp4',
      );
      final localMinioHit = await MediaCacheManager.instance.getCachedFile(
        'http://localhost:9000/media/videos/net.mp4',
      );
      expect(apiHit!.path, results[0]!.path);
      expect(localMinioHit!.path, results[0]!.path);
      expect(httpHits, 1);
    });

    testWidgets('sender pre-seeds cache before RPC so WS echo triggers 0 downloads (single, transcoded .mov & album)', (tester) async {
      int cacheHttpHits = 0;
      MediaCacheManager.instance.dioForTesting.httpClientAdapter = _ScriptedHttpAdapter(
        (options) async {
          cacheHttpHits++;
          return ResponseBody.fromString('unexpected download', 500);
        },
      );

      await tester.runAsync(() async {
        await SettingsService().init();
        await SettingsService().saveStorageSettings(
          StorageSettings(
            autoDownloadPhotosOnWifi: true,
            autoDownloadVideosOnWifi: true,
            autoDownloadFilesOnWifi: true,
            autoDownloadAudioOnWifi: true,
            autoDownloadPhotosOnCellular: false,
            autoDownloadVideosOnCellular: false,
            autoDownloadFilesOnCellular: false,
            autoDownloadAudioOnCellular: false,
            autoDownloadPhotosOnRoaming: false,
            autoDownloadVideosOnRoaming: false,
            autoDownloadFilesOnRoaming: false,
            autoDownloadAudioOnRoaming: false,
          ),
        );
      });
      addTearDown(
        () => SettingsService().saveStorageSettings(StorageSettings.defaults()),
      );

      late final Completer<void> singleRpcEntered;
      late final Completer<void> singleRpcRelease;
      late final Completer<void> albumRpcEntered;
      late final Completer<void> albumRpcRelease;

      late File docFile;
      late File movFile;
      late File a1File;
      late File a2File;
      const docUrl = 'https://storage.theaver.app/media/files/sender_doc.pdf';
      const movUrl = 'https://storage.theaver.app/media/videos/iphone_clip.mp4';
      const a1Url = 'https://storage.theaver.app/media/images/alb1.png';
      const a2Url = 'https://storage.theaver.app/media/images/alb2.png';

      await tester.runAsync(() async {
        singleRpcEntered = Completer<void>();
        singleRpcRelease = Completer<void>();
        albumRpcEntered = Completer<void>();
        albumRpcRelease = Completer<void>();
        docFile = File(p.join(tempDir.path, 'sender_doc.pdf'))
          ..writeAsBytesSync(Uint8List.fromList(List.filled(2048, 77)));
        movFile = File(p.join(tempDir.path, 'iphone_clip.mov'))
          ..writeAsBytesSync(Uint8List.fromList(List.filled(1024, 55)));
        a1File = File(p.join(tempDir.path, 'alb1.png'))
          ..writeAsBytesSync(_minimalPngBytes());
        a2File = File(p.join(tempDir.path, 'alb2.png'))
          ..writeAsBytesSync(_minimalPngBytes());

        MediaSendCoordinator.instance.configureForTesting(
          uploadOverride: (file, {onSendBytes, cancelToken}) async {
            final base = p.basename(file.path);
            if (base.contains('sender_doc.pdf')) {
              return UploadResult(
                fileId: 101,
                objectName: 'files/sender_doc.pdf',
                url: docUrl,
                fileName: 'sender_doc.pdf',
                mimeType: 'application/pdf',
                size: 2048,
              );
            }
            if (base.contains('iphone_clip.mov')) {
              return UploadResult(
                fileId: 102,
                objectName: 'videos/iphone_clip.mp4',
                url: movUrl,
                fileName: 'iphone_clip.mp4',
                mimeType: 'video/mp4',
                size: 1024,
              );
            }
            if (base.contains('alb1.png')) {
              return UploadResult(
                fileId: 103,
                objectName: 'images/alb1.png',
                url: a1Url,
                fileName: 'alb1.png',
                mimeType: 'image/png',
                size: 128,
              );
            }
            if (base.contains('alb2.png')) {
              return UploadResult(
                fileId: 104,
                objectName: 'images/alb2.png',
                url: a2Url,
                fileName: 'alb2.png',
                mimeType: 'image/png',
                size: 128,
              );
            }
            return UploadResult(
              fileId: base.hashCode.abs(),
              objectName: 'images/$base',
              url: 'https://storage.theaver.app/media/images/$base',
              fileName: base,
              mimeType: 'image/png',
              size: 128,
            );
          },
          sendSingleRpcOverride: (chatId, localId, content, messageType, fileUrl,
              fileName, mediaPayload, groupedId, isRound, duration, waveform) async {
            if (fileUrl == docUrl && !singleRpcEntered.isCompleted) {
              singleRpcEntered.complete();
              await singleRpcRelease.future;
            }
            return {
              'success': true,
              'message': Message(
                id: 'srv_$localId',
                chatId: chatId,
                senderId: 'test_user_001',
                content: content,
                messageType: messageType,
                isEdited: false,
                createdAt: DateTime.now().toUtc().toIso8601String(),
                senderName: 'Test Admin',
                fileUrl: fileUrl,
                fileName: fileName,
                localId: localId,
                sendStatus: 1,
              ),
            };
          },
          sendAlbumRpcOverride: (chatId, groupedId, items, caption) async {
            if (!albumRpcEntered.isCompleted) {
              albumRpcEntered.complete();
            }
            await albumRpcRelease.future;
            final now = DateTime.now().toUtc().toIso8601String();
            return {
              'success': true,
              'grouped_id': groupedId,
              'messages': items.map((it) {
                final lid = it['local_id']?.toString() ?? '';
                return Message(
                  id: 'srv_$lid',
                  chatId: chatId,
                  senderId: 'test_user_001',
                  content: it['content']?.toString() ?? '',
                  messageType: 'image',
                  isEdited: false,
                  createdAt: now,
                  senderName: 'Test Admin',
                  fileUrl: it['file_url']?.toString(),
                  fileName: it['file_name']?.toString(),
                  localId: lid,
                  groupedId: groupedId,
                  sendStatus: 1,
                );
              }).toList(),
            };
          },
        );

        await MediaSendCoordinator.instance.enqueueMediaOrFiles(
          chatId: 'chat_1',
          files: [docFile],
          asDocument: true,
        );
        await singleRpcEntered.future.timeout(const Duration(seconds: 3));

        // While single RPC is still in flight (WS echo window!), cache must ALREADY be seeded.
        expect(MediaCacheManager.instance.getCachedFileSync(docUrl), isNotNull);
        expect(
          MediaCacheManager.instance.getCachedFileSync('/media/files/sender_doc.pdf'),
          isNotNull,
        );
      });

      // Mounting DocumentMessageWidget in settled (WS echoed) state hits Frame-0 sync cache -> 0 downloads!
      await tester.pumpWidget(_wrapTestApp(
        const DocumentMessageWidget(
          fileUrl: docUrl,
          fileName: 'sender_doc.pdf',
          fileSize: 2048,
          localId: 'ws_echo_doc',
          sendStatus: 1,
        ),
      ));
      await tester.pump();
      expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
      expect(cacheHttpHits, 0);

      await tester.runAsync(() async {
        singleRpcRelease.complete();

        // Also test transcoded .mov -> .mp4 pre-RPC seeding and album pre-RPC seeding.
        await MediaSendCoordinator.instance.enqueueMediaOrFiles(
          chatId: 'chat_1',
          files: [movFile],
        );
        final movCached = await _waitForSeededFile(movUrl);
        expect(movCached, isNotNull);
        expect(MediaCacheManager.instance.getCachedFileSync(movUrl), isNotNull);

        await MediaSendCoordinator.instance.enqueueMediaOrFiles(
          chatId: 'chat_1',
          files: [a1File, a2File],
        );
        await albumRpcEntered.future.timeout(const Duration(seconds: 3));
        expect(MediaCacheManager.instance.getCachedFileSync(a1Url), isNotNull);
        expect(MediaCacheManager.instance.getCachedFileSync(a2Url), isNotNull);

        albumRpcRelease.complete();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });

      expect(cacheHttpHits, 0);
      await tester.pumpWidget(const SizedBox.shrink());
    });

    testWidgets('DocumentMessageWidget downloads file once into MediaCacheManager without auto-duplicating into Downloads', (tester) async {
      final pdfBytes = Uint8List.fromList(List<int>.filled(4096, 66));
      int httpHits = 0;
      late Directory downloadsDir;

      MediaCacheManager.instance.dioForTesting.httpClientAdapter = _ScriptedHttpAdapter(
        (options) async {
          httpHits++;
          return ResponseBody.fromBytes(
            pdfBytes,
            200,
            headers: {
              Headers.contentLengthHeader: ['${pdfBytes.length}'],
            },
          );
        },
      );

      await tester.runAsync(() async {
        downloadsDir = Directory(p.join(tempDir.path, 'system_downloads'))
          ..createSync(recursive: true);
        await SettingsService().init();
        await SettingsService().saveStorageSettings(
          StorageSettings(
            autoDownloadPhotosOnWifi: false,
            autoDownloadVideosOnWifi: false,
            autoDownloadFilesOnWifi: false,
            autoDownloadAudioOnWifi: false,
            autoDownloadPhotosOnCellular: false,
            autoDownloadVideosOnCellular: false,
            autoDownloadFilesOnCellular: false,
            autoDownloadAudioOnCellular: false,
            autoDownloadPhotosOnRoaming: false,
            autoDownloadVideosOnRoaming: false,
            autoDownloadFilesOnRoaming: false,
            autoDownloadAudioOnRoaming: false,
            downloadPath: downloadsDir.path,
          ),
        );
      });
      addTearDown(
        () => SettingsService().saveStorageSettings(StorageSettings.defaults()),
      );

      const remoteDocUrl = 'https://storage.theaver.app/media/files/single_pass.pdf';
      await tester.pumpWidget(_wrapTestApp(
        const DocumentMessageWidget(
          fileUrl: remoteDocUrl,
          fileName: 'single_pass.pdf',
          fileSize: 5 * 1024 * 1024,
          localId: 'doc_dl_1',
          sendStatus: 1,
        ),
      ));
      await tester.pump();
      expect(httpHits, 0);

      await tester.tap(find.byType(IconButton));
      await tester.pump();
      for (int i = 0; i < 40; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)),
        );
        await tester.pump(const Duration(milliseconds: 20));
        if (find.byIcon(Icons.more_vert_rounded).evaluate().isNotEmpty) break;
      }

      expect(find.byIcon(Icons.more_vert_rounded), findsOneWidget);
      expect(httpHits, 1);
      expect(downloadsDir.listSync(), isEmpty);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  });
}

Future<File?> _waitForSeededFile(String url) async {
  for (int i = 0; i < 50; i++) {
    final f = MediaCacheManager.instance.getCachedFileSync(url);
    if (f != null) return f;
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
  return MediaCacheManager.instance.getCachedFile(url);
}
