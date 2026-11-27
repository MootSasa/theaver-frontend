import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/database/app_database.dart';
import 'package:theaver/services/dm_parity_service.dart';
import 'package:theaver/services/settings_service.dart';
import 'package:theaver/services/websocket_service.dart';
import 'package:theaver/widgets/message/contact_message_widget.dart';
import 'package:theaver/widgets/message/location_message_widget.dart';
import 'package:theaver/widgets/message/telegram_service_message_widget.dart';
import 'package:theaver/widgets/message/view_once_media_widget.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Wave 2B Drift v15 & Models', () {
    test(
        'Drift schemaVersion 15 persists and updates auto-delete, appearance, burned, and saved tags',
        () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      expect(db.schemaVersion, 16);

      final chat = Chat(
        id: 'chat_1',
        chatType: 'private',
        name: 'Alice',
        updatedAt: '2026-11-19T12:00:00Z',
        messageAutoDeleteTime: 86400,
        appearance: const {'theme_id': 'aurora_blue', 'is_shared': true},
      );
      await db.saveChat(chat.toCompanion());

      var dbChat = await db.getChat('chat_1');
      expect(dbChat, isNotNull);
      expect(dbChat!.messageAutoDeleteTime, 86400);
      expect(dbChat.appearanceJson, contains('aurora_blue'));

      await db.updateChatAutoDeleteTime('chat_1', 604800);
      await db.updateChatAppearanceJson(
        'chat_1',
        jsonEncode({'theme_id': 'sunset_peach', 'is_shared': false}),
      );
      dbChat = await db.getChat('chat_1');
      final roundTripChat = Chat.fromDbChat(dbChat!);
      expect(roundTripChat.messageAutoDeleteTime, 604800);
      expect(roundTripChat.appearance?['theme_id'], 'sunset_peach');

      final msg = Message(
        id: 'msg_1',
        localId: 'loc_1',
        chatId: 'chat_1',
        senderId: 'user_1',
        senderName: 'Alice',
        content: 'Secret photo',
        messageType: 'image',
        fileUrl: 'https://cdn.example.com/secret.jpg',
        isEdited: false,
        createdAt: '2026-11-19T12:01:00Z',
        ttlSeconds: 15,
        isViewOnce: true,
        replyToChatId: 'chat_0',
        replyToChatName: 'Origin Group',
        replyToChatType: 'group',
        effectId: 'fire',
        savedTags: const ['🔥'],
      );
      await db.saveMessage(msg.toCompanion());

      var dbMsg = await db.getMessageByServerId('msg_1');
      expect(dbMsg, isNotNull);
      final roundTripMsg = Message.fromDbMessage(dbMsg!);
      expect(roundTripMsg.ttlSeconds, 15);
      expect(roundTripMsg.isViewOnce, isTrue);
      expect(roundTripMsg.replyToChatId, 'chat_0');
      expect(roundTripMsg.replyToChatName, 'Origin Group');
      expect(roundTripMsg.replyToChatType, 'group');
      expect(roundTripMsg.effectId, 'fire');
      expect(roundTripMsg.savedTags, ['🔥']);

      await db.updateMessageSavedTags('msg_1', ['🔥', '💼']);
      await db.markMessageBurned('msg_1');
      dbMsg = await db.getMessageByServerId('msg_1');
      final burnedMsg = Message.fromDbMessage(dbMsg!);
      expect(burnedMsg.savedTags, ['🔥', '💼']);
      expect(burnedMsg.isBurned, isTrue);
      expect(burnedMsg.fileUrl, isNull);
    });

    test('Message & Chat JSON parsing & isUnsupported allow Wave 2B types', () {
      for (final type in const [
        'location',
        'live_location',
        'venue',
        'contact',
      ]) {
        final m = Message.fromJson({
          'id': 'm_$type',
          'chat_id': 'c1',
          'sender_id': 'u1',
          'content': '',
          'message_type': type,
          'is_edited': false,
          'created_at': '2026-11-19T12:00:00Z',
        });
        expect(m.isUnsupported, isFalse, reason: '$type should be supported');

        final c = Chat.fromJson({
          'id': 'c_$type',
          'chat_type': 'private',
          'name': 'Peer',
          'updated_at': '2026-11-19T12:00:00Z',
          'last_message_type': type,
        });
        expect(
          c.isLastMessageUnsupported,
          isFalse,
          reason: '$type last_message_type should be supported',
        );
      }

      final unsupportedMsg = Message.fromJson({
        'id': 'm_unknown',
        'chat_id': 'c1',
        'sender_id': 'u1',
        'content': '',
        'message_type': 'future_hologram_v9',
        'is_edited': false,
        'created_at': '2026-11-19T12:00:00Z',
      });
      expect(unsupportedMsg.isUnsupported, isTrue);

      final parsed = Message.fromJson({
        'id': '501',
        'chat_id': '10',
        'sender_id': '2',
        'content': 'Cross chat reply',
        'message_type': 'text',
        'is_edited': false,
        'created_at': '2026-11-19T12:00:00Z',
        'is_view_once': true,
        'ttl_seconds': 30,
        'is_burned': false,
        'expires_at': '2026-11-19T12:00:30Z',
        'reply_to_chat_id': '99',
        'reply_to_chat_name': 'Saved Chat',
        'reply_to_chat_type': 'group',
        'effect_id': 'confetti',
        'saved_tags': ['⭐', '📌'],
      });
      expect(parsed.isViewOnce, isTrue);
      expect(parsed.ttlSeconds, 30);
      expect(parsed.replyToChatId, '99');
      expect(parsed.replyToChatName, 'Saved Chat');
      expect(parsed.replyToChatType, 'group');
      expect(parsed.effectId, 'confetti');
      expect(parsed.savedTags, ['⭐', '📌']);

      final copied = parsed.copyWith(isBurned: true, savedTags: ['⭐']);
      expect(copied.isBurned, isTrue);
      expect(copied.savedTags, ['⭐']);
    });

    test('WebSocketEvent, PrivacySettings & DmParityService DTOs parse Wave 2B events',
        () {
      expect(
        WebSocketEvent.fromJson({'type': 'message_burned', 'data': {}}).type,
        WebSocketEventType.messageBurned,
      );
      expect(
        WebSocketEvent.fromJson({'type': 'chat_auto_delete_updated', 'data': {}})
            .type,
        WebSocketEventType.chatAutoDeleteUpdated,
      );
      expect(
        WebSocketEvent.fromJson({'type': 'chat_appearance_updated', 'data': {}})
            .type,
        WebSocketEventType.chatAppearanceUpdated,
      );
      expect(
        WebSocketEvent.fromJson({'type': 'screenshot_taken', 'data': {}}).type,
        WebSocketEventType.screenshotTaken,
      );

      final privacy = PrivacySettings.fromJson({
        'voice_messages_privacy': 'contacts',
        'messages_privacy': 'contacts',
      });
      expect(privacy.voiceMessagesPrivacy, PrivacyVisibility.contacts);
      expect(privacy.messagesPrivacy, PrivacyVisibility.contacts);
      expect(privacy.toJson()['voice_messages_privacy'], 'contacts');
      expect(privacy.toJson()['messages_privacy'], 'contacts');

      final tag = SavedTagItem.fromJson({'tag': '🔥', 'label': 'Важное', 'count': 3});
      expect(tag.tag, '🔥');
      expect(tag.label, 'Важное');
      expect(tag.count, 3);

      final peer = SavedPeerItem.fromJson({
        'saved_peer_key': 'user_9',
        'peer_type': 'user',
        'peer_id': '9',
        'title': 'Мария',
        'message_count': 4,
      });
      expect(peer.title, 'Мария');
      expect(peer.messageCount, 4);

      final group = CommonGroupItem.fromJson({
        'id': '77',
        'name': 'Flutter Devs',
        'participants_count': 12,
      });
      expect(group.id, '77');
      expect(group.participantsCount, 12);

      final cfg = ChatAppearanceConfig.tryParseJsonString(
        '{"theme_id":"aurora_blue","accent_color_id":"5CAEFF","for_both":true}',
      );
      expect(cfg, isNotNull);
      expect(cfg!.isEmpty, isFalse);
      expect(cfg.isShared, isTrue);
      expect(cfg.toJson(includeForBoth: true)['for_both'], isTrue);

      final tr = TranslationResult.fromJson({
        'message_id': '55',
        'chat_id': '10',
        'target_lang': 'ru',
        'source_lang': 'en',
        'translated_text': 'Привет мир',
        'cached': true,
      });
      expect(tr.translatedText, 'Привет мир');
      expect(tr.cached, isTrue);

      const page = SharedMediaPage(
        type: 'media',
        messages: [],
        hasMore: true,
        nextBeforeId: '40',
      );
      expect(page.hasMore, isTrue);
      expect(page.nextBeforeId, '40');
    });
  });

  group('Wave 2B Message Widgets', () {
    testWidgets('ContactMessageWidget displays name and phone number',
        (tester) async {
      final msg = Message(
        id: 'c1',
        chatId: 'chat_1',
        senderId: 'u1',
        senderName: 'Sender',
        content: 'Иван Петров',
        messageType: 'contact',
        isEdited: false,
        createdAt: '2026-11-19T12:00:00Z',
        mediaPayload: const {
          'user_id': '42',
          'first_name': 'Иван',
          'last_name': 'Петров',
          'phone_number': '+79990001122',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ContactMessageWidget(
              message: msg,
              isMe: false,
              textColor: Colors.black,
              subtextColor: Colors.grey,
              accentColor: Colors.blue,
            ),
          ),
        ),
      );

      expect(find.text('Иван Петров'), findsOneWidget);
      expect(find.text('+79990001122'), findsOneWidget);
    });

    testWidgets('ViewOnceMediaWidget renders sealed and burned states',
        (tester) async {
      final sealedMsg = Message(
        id: 'vo_1',
        chatId: 'chat_1',
        senderId: 'u2',
        senderName: 'Peer',
        content: '',
        messageType: 'image',
        fileUrl: 'https://cdn.example.com/1.jpg',
        isEdited: false,
        createdAt: '2026-11-19T12:00:00Z',
        isViewOnce: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ViewOnceMediaWidget(
              message: sealedMsg,
              isMe: false,
              textColor: Colors.black,
              subtextColor: Colors.grey,
              accentColor: Colors.blue,
            ),
          ),
        ),
      );
      expect(find.text('Однократное фото'), findsOneWidget);
      expect(find.text('1'), findsOneWidget);

      final burnedMsg = Message(
        id: 'vo_2',
        chatId: 'chat_1',
        senderId: 'u2',
        senderName: 'Peer',
        content: '',
        messageType: 'image',
        isEdited: false,
        createdAt: '2026-11-19T12:00:00Z',
        isViewOnce: true,
        isBurned: true,
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ViewOnceMediaWidget(
              message: burnedMsg,
              isMe: false,
              textColor: Colors.black,
              subtextColor: Colors.grey,
              accentColor: Colors.blue,
            ),
          ),
        ),
      );
      expect(find.text('Медиа исчезло'), findsOneWidget);
    });

    testWidgets(
        'TelegramServiceMessageWidget renders auto-delete and screenshot service pills',
        (tester) async {
      final autoDeleteMsg = Message(
        id: 'sys_1',
        chatId: 'chat_1',
        senderId: 'u1',
        senderName: 'Анна',
        content: '',
        messageType: 'system',
        isEdited: false,
        createdAt: '2026-11-19T12:00:00Z',
        mediaPayload: const {
          'system_action': 'chat_auto_delete_updated',
          'actor_name': 'Анна',
          'ttl_seconds': 86400,
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TelegramServiceMessageWidget(message: autoDeleteMsg),
          ),
        ),
      );
      expect(
        find.textContaining('установил(а) автоудаление сообщений: 24 ч.'),
        findsOneWidget,
      );

      final screenshotMsg = Message(
        id: 'sys_2',
        chatId: 'chat_1',
        senderId: 'u2',
        senderName: 'Борис',
        content: '',
        messageType: 'system',
        isEdited: false,
        createdAt: '2026-11-19T12:01:00Z',
        mediaPayload: const {
          'action': 'screenshot_taken',
          'actor_name': 'Борис',
        },
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: TelegramServiceMessageWidget(message: screenshotMsg),
          ),
        ),
      );
      expect(find.text('Борис сделал(а) снимок экрана'), findsOneWidget);
    });

    testWidgets('LocationMessageWidget handles missing coordinates safely',
        (tester) async {
      final emptyLocMsg = Message(
        id: 'loc_0',
        chatId: 'chat_1',
        senderId: 'u1',
        senderName: 'Alice',
        content: '',
        messageType: 'location',
        isEdited: false,
        createdAt: '2026-11-19T12:00:00Z',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: LocationMessageWidget(
              message: emptyLocMsg,
              isMe: false,
              textColor: Colors.black,
              subtextColor: Colors.grey,
              accentColor: Colors.blue,
            ),
          ),
        ),
      );
      expect(find.text('Геопозиция недоступна'), findsOneWidget);
    });
  });
}
