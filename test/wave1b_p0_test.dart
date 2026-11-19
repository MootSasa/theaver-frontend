import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/contacts_service.dart';
import 'package:theaver/services/websocket_service.dart';

void main() {
  group('Wave 1B P0 models & sync helpers', () {
    test('Chat.fromJson maps is_marked_unread to -1 only when unread_count is 0',
        () {
      final marked = Chat.fromJson({
        'id': '10',
        'chat_type': 'private',
        'name': 'Alice',
        'unread_count': 0,
        'is_marked_unread': true,
      });
      expect(marked.unreadCount, -1);

      final withPositiveUnread = Chat.fromJson({
        'id': '11',
        'chat_type': 'group',
        'name': 'Team',
        'unread_count': 4,
        'is_marked_unread': true,
      });
      expect(withPositiveUnread.unreadCount, 4);

      final clean = Chat.fromJson({
        'id': '12',
        'chat_type': 'private',
        'name': 'Bob',
        'unread_count': 0,
        'is_marked_unread': false,
      });
      expect(clean.unreadCount, 0);
    });

    test(
        'ChatDetails.fromJson parses counts, slowmode wait, call & info permissions',
        () {
      final channel = ChatDetails.fromJson({
        'id': '200',
        'chat_type': 'channel',
        'name': 'News',
        'member_count': 5,
        'subscriber_count': 1250,
        'pending_join_requests_count': 3,
        'slow_mode_wait_seconds': 0,
        'is_marked_unread': true,
        'my_role': 'subscriber',
      });
      expect(channel.memberCount, 5);
      expect(channel.subscriberCount, 1250);
      expect(channel.pendingJoinRequestsCount, 3);
      expect(channel.isMarkedUnread, isTrue);
      expect(channel.effectiveMemberCount, 1250);
      expect(channel.canManageCallsEffective, isFalse);
      expect(channel.canChangeInfoEffective, isFalse);

      final groupMemberWithInfo = ChatDetails.fromJson({
        'id': '201',
        'chat_type': 'group',
        'name': 'Dev Chat',
        'member_count': 42,
        'slow_mode_wait_seconds': 18,
        'slow_mode_next_send_date': '2026-11-19T12:00:30Z',
        'my_role': 'member',
        'default_permissions': {
          'can_change_info': true,
        },
      });
      expect(groupMemberWithInfo.effectiveMemberCount, 42);
      expect(groupMemberWithInfo.slowModeWaitSeconds, 18);
      expect(groupMemberWithInfo.slowModeNextSendDate, isNotNull);
      expect(groupMemberWithInfo.canManageCallsEffective, isFalse);
      expect(groupMemberWithInfo.canChangeInfoEffective, isTrue);

      final groupAdminWithCalls = ChatDetails.fromJson({
        'id': '202',
        'chat_type': 'group',
        'name': 'Admin Call Group',
        'my_role': 'admin',
        'my_admin_permissions': {
          'can_manage_video_chats': true,
          'can_change_info': false,
        },
      });
      expect(groupAdminWithCalls.canManageCallsEffective, isTrue);
      expect(groupAdminWithCalls.canChangeInfoEffective, isFalse);

      final groupOwner = ChatDetails.fromJson({
        'id': '203',
        'chat_type': 'group',
        'name': 'Owner Group',
        'my_role': 'owner',
      });
      expect(groupOwner.canManageCallsEffective, isTrue);
      expect(groupOwner.canChangeInfoEffective, isTrue);
    });

    test(
        'ChatService.mergeIncomingMediaPayload preserves voted_option_ids on neutral broadcasts and merges reply_markup',
        () {
      final existingPoll = <String, dynamic>{
        'poll_id': 77,
        'question': 'Favorite DB?',
        'options': [
          {'id': 1, 'text': 'Postgres', 'vote_count': 2},
          {'id': 2, 'text': 'SQLite', 'vote_count': 1},
        ],
        'total_votes': 3,
        'voted_option_ids': [1],
        'reply_markup': {
          'inline_keyboard': [
            [
              {'text': 'Refresh', 'callback_data': 'refresh'}
            ]
          ],
        },
      };

      final neutralBroadcast = <String, dynamic>{
        'poll_id': 77,
        'question': 'Favorite DB?',
        'options': [
          {'id': 1, 'text': 'Postgres', 'vote_count': 3},
          {'id': 2, 'text': 'SQLite', 'vote_count': 1},
        ],
        'total_votes': 4,
      };

      final mergedNeutral = ChatService.mergeIncomingMediaPayload(
        existingPoll,
        neutralBroadcast,
      );
      expect(mergedNeutral?['total_votes'], 4);
      expect(mergedNeutral?['voted_option_ids'], [1]);
      expect(mergedNeutral?['reply_markup'], isNotNull);

      final explicitClearBroadcast = <String, dynamic>{
        ...neutralBroadcast,
        'voted_option_ids': <int>[],
      };
      final mergedCleared = ChatService.mergeIncomingMediaPayload(
        existingPoll,
        explicitClearBroadcast,
      );
      expect(mergedCleared?['voted_option_ids'], isEmpty);

      final markupOnlyEdit = ChatService.mergeIncomingMediaPayload(
        {'file_name': 'report.pdf'},
        null,
        replyMarkup: {
          'inline_keyboard': [
            [
              {'text': 'Open', 'url': 'https://example.com'}
            ]
          ],
        },
      );
      expect(markupOnlyEdit?['file_name'], 'report.pdf');
      expect(markupOnlyEdit?['reply_markup'], isMap);
    });

    test('ContactItem.fromJson & effectiveName follow Telegram priority order',
        () {
      final customNamed = ContactItem.fromJson({
        'id': '1',
        'user_id': '55',
        'contact_user_id': '55',
        'username': 'alice_dev',
        'display_name': 'Alice Server',
        'nickname': 'Ali',
        'custom_first_name': 'Alice',
        'custom_last_name': 'Work',
        'is_verified': true,
      });
      expect(customNamed.contactUserId, '55');
      expect(customNamed.isVerified, isTrue);
      expect(customNamed.effectiveName, 'Alice Work');

      final nickNamed = ContactItem.fromJson({
        'contact_user_id': '56',
        'username': 'bob_dev',
        'display_name': 'Bob Server',
        'nickname': 'Bobby',
      });
      expect(nickNamed.effectiveName, 'Bobby');

      final displayNamed = ContactItem.fromJson({
        'contact_user_id': '57',
        'username': 'carol_dev',
        'display_name': 'Carol Server',
      });
      expect(displayNamed.effectiveName, 'Carol Server');

      final userNamed = ContactItem.fromJson({
        'contact_user_id': '58',
        'username': 'dave_dev',
      });
      expect(userNamed.effectiveName, '@dave_dev');

      final idFallback = ContactItem.fromJson({'contact_user_id': '59'});
      expect(idFallback.effectiveName, 'Пользователь #59');
    });

    test('WebSocketEvent.fromJson maps chat_unread_marked event type', () {
      final evt = WebSocketEvent.fromJson({
        'type': 'chat_unread_marked',
        'data': {
          'chat_id': '12',
          'is_marked_unread': true,
        },
      });
      expect(evt.type, WebSocketEventType.chatUnreadMarked);
      expect(evt.data['chat_id'], '12');
      expect(evt.data['is_marked_unread'], isTrue);
    });
  });
}
