import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/models/media_album.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/widgets/message/media_album_widget.dart';

Message _createMsg({
  required String id,
  required String content,
  String? groupedId,
  String? fileUrl,
  String? fileName,
}) {
  return Message(
    id: id,
    chatId: 'chat_test',
    senderId: 'user_other',
    content: content,
    messageType: fileUrl != null ? 'image' : 'text',
    isEdited: false,
    senderName: 'TestUser',
    createdAt: DateTime.now().toIso8601String(),
    groupedId: groupedId,
    fileUrl: fileUrl,
    fileName: fileName,
    sendStatus: 1,
    isRead: false,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Unread Divider and Feed Index Tests', () {
    test('Resolves _firstUnreadFeedIndex when unread target is a regular message', () {
      final messages = [
        _createMsg(id: 'm1', content: 'Newest'),
        _createMsg(id: 'm2', content: 'Middle unread'),
        _createMsg(id: 'm3', content: 'Oldest read'),
      ];

      final feedItems = groupMessagesIntoFeedItems(messages, isReversed: true);
      const firstUnreadMessageId = 'm2';

      final unreadIndex = feedItems.indexWhere((item) =>
          item.id == firstUnreadMessageId ||
          (item is FeedAlbumItem &&
              item.album.items.any((ai) => ai.id == firstUnreadMessageId)));

      expect(unreadIndex, 1);
    });

    test('Resolves _firstUnreadFeedIndex when unread target is inside a media album', () {
      final messages = [
        _createMsg(id: 'm1', content: 'Newest text'),
        _createMsg(id: 'p1', content: '', groupedId: 'album_1', fileUrl: 'http://img1.jpg'),
        _createMsg(id: 'p2', content: '', groupedId: 'album_1', fileUrl: 'http://img2.jpg'),
        _createMsg(id: 'p3', content: '', groupedId: 'album_1', fileUrl: 'http://img3.jpg'),
        _createMsg(id: 'm2', content: 'Older text'),
      ];

      final feedItems = groupMessagesIntoFeedItems(messages, isReversed: true);
      // feedItems:
      // index 0 -> m1
      // index 1 -> FeedAlbumItem (p1, p2, p3)
      // index 2 -> m2
      expect(feedItems.length, 3);
      expect(feedItems[1], isA<FeedAlbumItem>());

      // When the first unread message is p2 (inside the album)
      const firstUnreadMessageId = 'p2';
      final unreadIndex = feedItems.indexWhere((item) =>
          item.id == firstUnreadMessageId ||
          (item is FeedAlbumItem &&
              item.album.items.any((ai) => ai.id == firstUnreadMessageId)));

      expect(unreadIndex, 1);
    });

    test('Clamps scroll offset safely within maxScrollExtent', () {
      const estimatedItemHeight = 90.0;
      const targetIndex = 50; // index 50 = 4500px
      const currentMaxScroll = 1200.0;

      final targetOffset =
          (targetIndex * estimatedItemHeight).clamp(0.0, currentMaxScroll);

      expect(targetOffset, 1200.0);
    });
  });

  group('MediaAlbumWidget Highlighting Tests', () {
    testWidgets('Renders highlighted album and specific tile highlight', (tester) async {
      final albumMessages = [
        _createMsg(id: 'img_1', content: '', groupedId: 'grp_1', fileUrl: null),
        _createMsg(id: 'img_2', content: '', groupedId: 'grp_1', fileUrl: null),
      ];
      final feedItems = groupMessagesIntoFeedItems(albumMessages, isReversed: false);
      final album = (feedItems.first as FeedAlbumItem).album;

      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(
            colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
          ),
          home: Scaffold(
            body: MediaAlbumWidget(
              album: album,
              isMe: false,
              currentUserId: 'me',
              isHighlighted: true,
              highlightItemId: 'img_2',
            ),
          ),
        ),
      );

      // Verify widget builds without error
      expect(find.byType(MediaAlbumWidget), findsOneWidget);

      // Verify AnimatedContainer exists for highlight animation
      expect(find.byType(AnimatedContainer), findsWidgets);
    });
  });
}
