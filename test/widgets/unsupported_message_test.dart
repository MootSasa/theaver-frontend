import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/models/theav_theme.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/widgets/message/message_bubble.dart';
import 'package:theaver/widgets/message/unsupported_message_widget.dart';

void main() {
  group('Unsupported Message Detection Tests', () {
    test('Message.isUnsupported returns false for supported types', () {
      const supported = [
        'text',
        'image',
        'photo',
        'video',
        'voice',
        'audio',
        'round',
        'poll',
        'document',
        'file',
      ];
      for (final type in supported) {
        final msg = Message(
          id: '1',
          chatId: 'c1',
          senderId: 'u1',
          content: 'test',
          messageType: type,
          isEdited: false,
          createdAt: '2026-10-20T20:00:00Z',
          senderName: 'Alice',
        );
        expect(msg.isUnsupported, isFalse, reason: 'Expected $type to be supported');
      }
    });

    test('Message.isUnsupported returns true for unsupported types', () {
      const unsupported = [
        'unsupported',
        'sticker',
        'gif',
        'story',
        'giveaway',
        'invoice',
        'stars_gift',
        'future_unknown_type',
      ];
      for (final type in unsupported) {
        final msg = Message(
          id: '1',
          chatId: 'c1',
          senderId: 'u1',
          content: 'test',
          messageType: type,
          isEdited: false,
          createdAt: '2026-10-20T20:00:00Z',
          senderName: 'Alice',
        );
        expect(msg.isUnsupported, isTrue, reason: 'Expected $type to be unsupported');
      }
    });

    test('Chat.isLastMessageUnsupported detection', () {
      final chatSupported = Chat(
        id: 'c1',
        chatType: 'private',
        name: 'Alice',
        lastMessageType: 'text',
        updatedAt: '2026-10-20T20:00:00Z',
      );
      expect(chatSupported.isLastMessageUnsupported, isFalse);

      final chatUnsupported = Chat(
        id: 'c2',
        chatType: 'private',
        name: 'Bob',
        lastMessageType: 'sticker',
        updatedAt: '2026-10-20T20:00:00Z',
      );
      expect(chatUnsupported.isLastMessageUnsupported, isTrue);

      final chatExplicitUnsupported = Chat(
        id: 'c3',
        chatType: 'private',
        name: 'Charlie',
        lastMessageType: 'unsupported',
        updatedAt: '2026-10-20T20:00:00Z',
      );
      expect(chatExplicitUnsupported.isLastMessageUnsupported, isTrue);
    });

    test('ReplyInfo.isUnsupported detection', () {
      const replySupported = ReplyInfo(
        messageId: 'm1',
        senderId: 'u1',
        senderName: 'Alice',
        content: 'hello',
        messageType: 'text',
      );
      expect(replySupported.isUnsupported, isFalse);

      const replyUnsupported = ReplyInfo(
        messageId: 'm2',
        senderId: 'u2',
        senderName: 'Bob',
        content: 'cool sticker',
        messageType: 'sticker',
      );
      expect(replyUnsupported.isUnsupported, isTrue);
    });
  });

  group('UnsupportedMessageWidget UI Tests', () {
    testWidgets('Renders UnsupportedMessageWidget inside MessageBubble', (WidgetTester tester) async {
      final msg = Message(
        id: 'msg_unsupported_1',
        chatId: 'chat_1',
        senderId: 'user_other',
        senderName: 'Alice',
        content: 'Raw payload or content from newer version',
        messageType: 'giveaway',
        isEdited: false,
        createdAt: '2026-10-20T20:00:00Z',
      );

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
          ],
          home: Scaffold(
            body: MessageBubble(
              message: msg,
              isMe: false,
              currentUserId: 'user_me',
              formatTime: (ts) => '20:00',
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check that UnsupportedMessageWidget is rendered
      expect(find.byType(UnsupportedMessageWidget), findsOneWidget);

      // Raw content should NOT be displayed
      expect(find.text('Raw payload or content from newer version'), findsNothing);

      // Action button should be present
      expect(find.byType(TextButton), findsOneWidget);
    });
  });
}
