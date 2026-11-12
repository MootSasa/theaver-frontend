import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/services/notifications/notification_payload.dart';

void main() {
  group('normalizePushPayload', () {
    test('flat FCM data map is kept', () {
      final data = normalizePushPayload(<String, dynamic>{'chat_id': '5', 'type': 'new_message'});
      expect(data['chat_id'], '5');
      expect(data['type'], 'new_message');
    });

    test('HMS onNotificationOpenedApp extras are unpacked', () {
      final data = normalizePushPayload(<String, dynamic>{
        'extras': <String, dynamic>{'chat_id': '7', 'chat_name': 'Команда'},
      });
      expect(data['chat_id'], '7');
      expect(data['chat_name'], 'Команда');
    });

    test('HMS remoteMessage.dataOfMap JSON string is unpacked', () {
      final data = normalizePushPayload(<String, dynamic>{
        'remoteMessage': <String, dynamic>{
          'dataOfMap': jsonEncode(<String, String>{'chat_id': '9', 'type': 'new_message'}),
        },
      });
      expect(data['chat_id'], '9');
    });

    test('top-level data JSON string is unpacked', () {
      final data = normalizePushPayload(<String, dynamic>{
        'data': jsonEncode(<String, String>{'chat_id': '3'}),
      });
      expect(data['chat_id'], '3');
    });

    test('local JSON payload string is decoded', () {
      final data = normalizePushPayload(jsonEncode(<String, dynamic>{'chat_id': '11', 'is_group': true}));
      expect(data['chat_id'], '11');
      expect(data['is_group'], true);
    });

    test('legacy bare chat id payload', () {
      final data = normalizePushPayload('15');
      expect(data['chat_id'], '15');
      expect(data['type'], 'new_message');
    });
  });

  group('ChatMessageNotification', () {
    test('fromWebSocket extracts message, sender and media fallback text', () {
      final m = ChatMessageNotification.fromWebSocket(<String, dynamic>{
        'chat_id': 42,
        'chat_name': 'Команда',
        'is_group': true,
        'message': <String, dynamic>{
          'id': 1001,
          'sender_id': 7,
          'sender_name': 'Иван',
          'message_type': 'voice',
          'content': '',
        },
      })!;
      expect(m.chatId, '42');
      expect(m.messageId, '1001');
      expect(m.senderId, '7');
      expect(m.text, '🎤 Голосовое сообщение');
      expect(m.isGroup, isTrue);
    });

    test('fromWebSocket without chat id returns null', () {
      expect(ChatMessageNotification.fromWebSocket(<String, dynamic>{'message': <String, dynamic>{}}), isNull);
    });

    test('fromPush maps backend payload incl. channel and mention flags', () {
      final m = ChatMessageNotification.fromPush(<String, dynamic>{
        'type': 'new_message',
        'chat_id': '8',
        'chat_name': 'Новости',
        'sender_name': 'Админ',
        'message_text': 'Пост',
        'chat_type': 'channel',
        'is_group': 'true',
        'is_mention': 'true',
        'id': '55',
      })!;
      expect(m.isChannel, isTrue);
      expect(m.isGroup, isFalse);
      expect(m.isMention, isTrue);
      expect(m.messageId, '55');
      expect(m.toTapPayload()['chat_type'], 'channel');
    });
  });
}
