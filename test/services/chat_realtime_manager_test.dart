import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/services/chat_realtime_manager.dart';
import 'package:theaver/services/websocket_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ChatRealtimeManager Tests', () {
    late ChatRealtimeManager manager;

    setUp(() {
      manager = ChatRealtimeManager();
      manager.init();
    });

    tearDown(() {
      manager.dispose();
    });

    test('bindChat receives newMessage for subscribed chatId', () async {
      WebSocketEvent? receivedEvent;

      final sub = manager.bindChat(
        chatId: 'chat-1',
        onNewMessage: (event) {
          receivedEvent = event;
        },
      );

      // Emit new_message event via WebSocketService
      WebSocketService().emitForTesting(WebSocketEvent(
        type: WebSocketEventType.newMessage,
        data: {
          'chat_id': 'chat-1',
          'message': {
            'id': 'msg-1',
            'chat_id': 'chat-1',
            'sender_id': 'user-1',
            'content': 'Hello world',
            'message_type': 'text',
          },
        },
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(receivedEvent, isNotNull);
      expect(receivedEvent!.data['chat_id'], 'chat-1');

      sub.cancel();
    });

    test('bindChat ignores events for different chatIds', () async {
      bool received = false;

      final sub = manager.bindChat(
        chatId: 'chat-1',
        onNewMessage: (event) {
          received = true;
        },
      );

      // Emit new_message for chat-2
      WebSocketService().emitForTesting(WebSocketEvent(
        type: WebSocketEventType.newMessage,
        data: {
          'chat_id': 'chat-2',
          'message': {
            'id': 'msg-2',
            'chat_id': 'chat-2',
            'sender_id': 'user-2',
            'content': 'Hello other chat',
            'message_type': 'text',
          },
        },
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));

      await Future.delayed(const Duration(milliseconds: 50));

      expect(received, isFalse);

      sub.cancel();
    });

    test('subscription cancel stops receiving events', () async {
      int callCount = 0;

      final sub = manager.bindChat(
        chatId: 'chat-1',
        onMessageEdited: (event) {
          callCount++;
        },
      );

      // Emit first edit
      WebSocketService().emitForTesting(WebSocketEvent(
        type: WebSocketEventType.messageEdited,
        data: {
          'chat_id': 'chat-1',
          'message_id': 'msg-1',
          'content': 'Edited 1',
        },
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));

      await Future.delayed(const Duration(milliseconds: 50));
      expect(callCount, 1);

      // Cancel subscription
      sub.cancel();

      // Emit second edit
      WebSocketService().emitForTesting(WebSocketEvent(
        type: WebSocketEventType.messageEdited,
        data: {
          'chat_id': 'chat-1',
          'message_id': 'msg-1',
          'content': 'Edited 2',
        },
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));

      await Future.delayed(const Duration(milliseconds: 50));
      expect(callCount, 1);
    });

    test('onReconnect is invoked on WebSocket connected event', () async {
      bool reconnected = false;

      final sub = manager.bindChat(
        chatId: 'chat-1',
        onReconnect: () {
          reconnected = true;
        },
      );

      WebSocketService().emitForTesting(WebSocketEvent(
        type: WebSocketEventType.connected,
        data: {'status': 'connected'},
        timestamp: DateTime.now().millisecondsSinceEpoch,
      ));

      await Future.delayed(const Duration(milliseconds: 50));
      expect(reconnected, isTrue);

      sub.cancel();
    });
  });
}
