import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:visibility_detector/visibility_detector.dart';
import 'package:theaver/models/media_album.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/widgets/chat/visible_message_detector.dart';

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
}
