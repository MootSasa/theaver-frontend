import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:theaver/models/media_album.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/sticker_service.dart';
import 'package:theaver/widgets/chat/sticker_item_widget.dart';
import 'package:theaver/widgets/chat/visible_message_detector.dart';
import 'package:theaver/widgets/message/sticker_message_widget.dart';

Message _createMsg({
  required String id,
  required String content,
  String? groupedId,
  String? fileName,
  String? fileUrl,
  int sendStatus = 1,
  bool isRead = false,
}) {
  return Message(
    id: id,
    chatId: 'chat_test',
    senderId: 'user_other',
    content: content,
    messageType: 'text',
    isEdited: false,
    senderName: 'TestUser',
    createdAt: DateTime.now().toIso8601String(),
    groupedId: groupedId,
    fileName: fileName,
    fileUrl: fileUrl,
    sendStatus: sendStatus,
    isRead: isRead,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  VisibilityDetectorController.instance.updateInterval = Duration.zero;

  group('groupMessagesIntoFeedItems Tests', () {
    test('Empty list returns empty feed items', () {
      final items = groupMessagesIntoFeedItems([]);
      expect(items, isEmpty);
    });

    test('Regular messages are converted to FeedSingleItem', () {
      final msgs = [
        _createMsg(id: 'm1', content: 'Hello'),
        _createMsg(id: 'm2', content: 'World'),
      ];
      final items = groupMessagesIntoFeedItems(msgs);
      expect(items.length, 2);
      expect(items[0], isA<FeedSingleItem>());
      expect((items[0] as FeedSingleItem).message.id, 'm1');
      expect(items[1], isA<FeedSingleItem>());
      expect((items[1] as FeedSingleItem).message.id, 'm2');
    });

    test('Single message with groupedId is treated as single item', () {
      final msgs = [
        _createMsg(id: 'm1', content: 'Photo alone', groupedId: 'album_single'),
      ];
      final items = groupMessagesIntoFeedItems(msgs);
      expect(items.length, 1);
      expect(items[0], isA<FeedSingleItem>());
    });

    test('Consecutive messages with same groupedId are grouped into FeedAlbumItem', () {
      final msgs = [
        _createMsg(id: 'm1', content: 'Photo 1', groupedId: 'album_1'),
        _createMsg(id: 'm2', content: 'Photo 2', groupedId: 'album_1'),
        _createMsg(id: 'm3', content: 'Photo 3', groupedId: 'album_1'),
        _createMsg(id: 'm4', content: 'Independent msg'),
      ];
      final items = groupMessagesIntoFeedItems(msgs, isReversed: true);
      expect(items.length, 2);
      expect(items[0], isA<FeedAlbumItem>());
      final albumItem = items[0] as FeedAlbumItem;
      expect(albumItem.album.groupedId, 'album_1');
      expect(albumItem.album.items.length, 3);
      expect(items[1], isA<FeedSingleItem>());
      expect((items[1] as FeedSingleItem).message.id, 'm4');
    });

    test('Deduplicates duplicate message IDs', () {
      final msgs = [
        _createMsg(id: 'm1', content: 'Hello'),
        _createMsg(id: 'm1', content: 'Hello duplicate'),
        _createMsg(id: 'm2', content: 'World'),
      ];
      final items = groupMessagesIntoFeedItems(msgs);
      expect(items.length, 2);
      expect((items[0] as FeedSingleItem).message.content, 'Hello');
      expect((items[1] as FeedSingleItem).message.id, 'm2');
    });
  });

  group('VisibleMessageDetector Widget Tests', () {
    testWidgets('Triggers onMessageSeen after message remains visible for visibleDuration',
        (WidgetTester tester) async {
      bool seen = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VisibleMessageDetector(
              messageId: 'test_msg_1',
              onMessageSeen: () {
                seen = true;
              },
              visibleDuration: const Duration(milliseconds: 200),
              child: const SizedBox(
                width: 100,
                height: 100,
                child: Text('Visible Message'),
              ),
            ),
          ),
        ),
      );

      // Initially not seen until timer elapses
      expect(seen, isFalse);

      // Fast forward by 250ms
      await tester.pump(const Duration(milliseconds: 250));

      expect(seen, isTrue);
    });

    testWidgets('Cancels seen timer if message is disposed before duration',
        (WidgetTester tester) async {
      bool seen = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: VisibleMessageDetector(
              messageId: 'test_msg_2',
              onMessageSeen: () {
                seen = true;
              },
              visibleDuration: const Duration(milliseconds: 500),
              child: const SizedBox(width: 100, height: 100),
            ),
          ),
        ),
      );

      await tester.pump(const Duration(milliseconds: 100));
      expect(seen, isFalse);

      // Dispose widget
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SizedBox.shrink(),
          ),
        ),
      );

      // Advance time beyond timer
      await tester.pump(const Duration(milliseconds: 600));

      // Callback should never have been triggered
      expect(seen, isFalse);
    });
  });

  group('Warm ImageCache ControlledAnimatedNetworkImage & GifMessageWidget scroll regression', () {
    testWidgets(
      'Defers parent setState from synchronous warm-cache onFirstFrameLoaded without !_dirty assertion',
      (WidgetTester tester) async {
        const String url = 'https://example.com/warm_test_anim.webp';
        late Directory tempDir;
        late File tempFile;
        late ui.Image testImg;
        await tester.runAsync(() async {
          tempDir = await Directory.systemTemp.createTemp('warm_img_probe_');
          tempFile = File('${tempDir.path}/anim.webp');
          await tempFile.writeAsBytes(List<int>.filled(32, 1));
          testImg = await createTestImage(width: 1, height: 1);
        });

        final FileImage cacheKey = FileImage(tempFile);
        StickerService.instance.putRasterFileCacheForTest(url, tempFile);
        PaintingBinding.instance.imageCache.putIfAbsent(
          cacheKey,
          () => OneFrameImageStreamCompleter(
            SynchronousFuture<ImageInfo>(ImageInfo(image: testImg.clone())),
          ),
        );

        addTearDown(() {
          StickerService.instance.removeRasterFileCacheForTest(url);
          PaintingBinding.instance.imageCache.evict(cacheKey);
          testImg.dispose();
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        bool parentLoaded = false;
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: _WarmImageSetStateProbe(
                url: url,
                onLoadedChanged: (val) => parentLoaded = val,
              ),
            ),
          ),
        );

        expect(tester.takeException(), isNull);
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(parentLoaded, isTrue);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );

    testWidgets(
      'Scrolling chat up and back down with warm ImageCache remounts GifMessageWidget cleanly',
      (WidgetTester tester) async {
        const String fullUrl = 'https://example.com/warm_chat_gif_full.gif';
        const String previewUrl = 'https://example.com/warm_chat_gif_prev.gif';
        late Directory tempDir;
        late File fullFile;
        late File previewFile;
        late ui.Image testImg;
        await tester.runAsync(() async {
          tempDir = await Directory.systemTemp.createTemp('warm_gif_scroll_');
          fullFile = File('${tempDir.path}/full.gif');
          previewFile = File('${tempDir.path}/prev.gif');
          await fullFile.writeAsBytes(List<int>.filled(32, 2));
          await previewFile.writeAsBytes(List<int>.filled(32, 3));
          testImg = await createTestImage(width: 1, height: 1);
        });

        final FileImage fullKey = FileImage(fullFile);
        final FileImage previewKey = FileImage(previewFile);
        StickerService.instance.putRasterFileCacheForTest(fullUrl, fullFile);
        StickerService.instance
            .putRasterFileCacheForTest(previewUrl, previewFile);

        PaintingBinding.instance.imageCache.putIfAbsent(
          fullKey,
          () => OneFrameImageStreamCompleter(
            SynchronousFuture<ImageInfo>(ImageInfo(image: testImg.clone())),
          ),
        );
        PaintingBinding.instance.imageCache.putIfAbsent(
          previewKey,
          () => OneFrameImageStreamCompleter(
            SynchronousFuture<ImageInfo>(ImageInfo(image: testImg.clone())),
          ),
        );

        final ScrollController scrollController = ScrollController();

        addTearDown(() {
          scrollController.dispose();
          StickerService.instance.removeRasterFileCacheForTest(fullUrl);
          StickerService.instance.removeRasterFileCacheForTest(previewUrl);
          PaintingBinding.instance.imageCache.evict(fullKey);
          PaintingBinding.instance.imageCache.evict(previewKey);
          testImg.dispose();
          if (tempDir.existsSync()) {
            tempDir.deleteSync(recursive: true);
          }
        });

        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: ListView.builder(
                controller: scrollController,
                reverse: true,
                scrollCacheExtent: const ScrollCacheExtent.pixels(0),
                itemCount: 20,
                itemBuilder: (context, index) {
                  if (index == 0) {
                    return const GifMessageWidget(
                      gifUrl: fullUrl,
                      previewUrl: previewUrl,
                      width: 200,
                      height: 150,
                    );
                  }
                  return const SizedBox(height: 180);
                },
              ),
            ),
          ),
        );

        expect(find.byType(GifMessageWidget), findsOneWidget);
        expect(tester.takeException(), isNull);

        // Scroll up past cacheExtent so index 0 (GifMessageWidget) unmounts.
        scrollController.jumpTo(1500);
        await tester.pump();
        expect(find.byType(GifMessageWidget), findsNothing);
        expect(tester.takeException(), isNull);

        // Scroll back down so GifMessageWidget remounts with warm ImageCache.
        scrollController.jumpTo(0);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 16));
        expect(find.byType(GifMessageWidget), findsOneWidget);
        expect(tester.takeException(), isNull);

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      },
    );
  });
}

class _WarmImageSetStateProbe extends StatefulWidget {
  final String url;
  final ValueChanged<bool> onLoadedChanged;

  const _WarmImageSetStateProbe({
    required this.url,
    required this.onLoadedChanged,
  });

  @override
  State<_WarmImageSetStateProbe> createState() =>
      _WarmImageSetStateProbeState();
}

class _WarmImageSetStateProbeState extends State<_WarmImageSetStateProbe> {
  bool _loaded = false;

  @override
  Widget build(BuildContext context) {
    return ControlledAnimatedNetworkImage(
      url: widget.url,
      width: 100,
      height: 100,
      isAnimatedWebpOrGif: true,
      onFirstFrameLoaded: () {
        if (!mounted || _loaded) return;
        setState(() => _loaded = true);
        widget.onLoadedChanged(_loaded);
      },
    );
  }
}
