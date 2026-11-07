import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/services/bot_service.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/search_service.dart';
import 'package:theaver/widgets/chat/bot_commands_popup.dart';
import 'package:theaver/widgets/chat/bot_welcome_card.dart';
import 'package:theaver/widgets/chat/pinned_message_banner.dart';
import 'package:theaver/widgets/chat/reply_keyboard_panel.dart';
import 'package:theaver/widgets/common/peer_badges_widget.dart';
import 'package:theaver/widgets/message/inline_keyboard_widget.dart';

void main() {
  group('Phase 1: Unified Search & PeerBadgesRow', () {
    test('UnifiedSearchResult.fromJson parses my_peers, global_peers, and messages', () {
      final json = {
        'success': true,
        'query': 'bot',
        'type': 'all',
        'my_peers': [
          {
            'peer_type': 'user',
            'id': '42',
            'chat_id': '100',
            'name': 'BotMother',
            'username': 'BotMother',
            'is_bot': true,
            'is_verified': true,
            'is_member': true,
          },
        ],
        'global_peers': [
          {
            'peer_type': 'channel',
            'id': '200',
            'chat_id': '200',
            'name': 'Theaver News',
            'username': 'theaver_news',
            'description': 'Official announcements',
            'is_public': true,
            'is_verified': true,
            'member_count': 1250,
            'is_member': false,
          },
        ],
        'messages': [
          {
            'id': '901',
            'content': 'Hello from @BotMother',
            'chat_id': '100',
            'chat_type': 'private',
            'chat_name': 'BotMother',
            'sender_id': '42',
            'sender_name': 'BotMother',
            'created_at': '2026-10-31T10:00:00Z',
          },
        ],
      };

      final res = UnifiedSearchResult.fromJson(json);
      expect(res.isEmpty, isFalse);
      expect(res.myPeers, hasLength(1));
      expect(res.myPeers.first.name, 'BotMother');
      expect(res.myPeers.first.isBot, isTrue);
      expect(res.myPeers.first.isVerified, isTrue);
      expect(res.myPeers.first.toUser().isBot, isTrue);

      expect(res.globalPeers, hasLength(1));
      expect(res.globalPeers.first.type, 'channel');
      expect(res.globalPeers.first.isPublic, isTrue);
      expect(res.globalPeers.first.memberCount, 1250);
      expect(res.globalPeers.first.toChannel().username, 'theaver_news');

      expect(res.messages, hasLength(1));
      expect(res.messages.first.content, 'Hello from @BotMother');
    });

    testWidgets('PeerBadgesRow renders BOT badge and Verified check icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: PeerBadgesRow(
              isBot: true,
              isVerified: true,
            ),
          ),
        ),
      );

      expect(find.text('BOT'), findsOneWidget);
    });
  });

  group('Phase 3 & 4: HWM Read State, Pinned Messages & Forwards', () {
    test('Chat.fromJson & ChatDetails.fromJson parse HWM, pinned_message, and badges', () {
      final chatJson = {
        'id': '55',
        'chat_type': 'group',
        'name': 'Developers',
        'updated_at': '2026-10-31T12:00:00Z',
        'unread_count': 3,
        'last_read_inbox_message_id': 120,
        'last_read_outbox_message_id': 125,
        'pinned_message_id': 110,
        'username': 'theaver_devs',
        'is_public': true,
        'is_verified': true,
        'pinned_message': {
          'id': '110',
          'chat_id': '55',
          'sender_id': '1',
          'sender_name': 'Alice',
          'content': 'Welcome to the group!',
          'message_type': 'text',
          'created_at': '2026-10-31T11:00:00Z',
        },
      };

      final chat = Chat.fromJson(chatJson);
      expect(chat.lastReadInboxMessageId, 120);
      expect(chat.lastReadOutboxMessageId, 125);
      expect(chat.pinnedMessageId, 110);
      expect(chat.pinnedMessage, isNotNull);
      expect(chat.pinnedMessage!.content, 'Welcome to the group!');
      expect(chat.username, 'theaver_devs');
      expect(chat.isPublic, isTrue);
      expect(chat.isVerified, isTrue);

      final details = ChatDetails.fromJson({
        ...chatJson,
        'created_by': '1',
        'created_at': '2026-10-31T09:00:00Z',
        'participants': [
          {
            'id': '42',
            'username': 'helper_bot',
            'display_name': 'Helper Bot',
            'role': 'admin',
            'is_bot': true,
            'is_verified': true,
          },
        ],
      });
      expect(details.lastReadInboxMessageId, 120);
      expect(details.lastReadOutboxMessageId, 125);
      expect(details.pinnedMessageId, 110);
      expect(details.isVerified, isTrue);
      expect(details.participants.first.isBot, isTrue);
      expect(details.participants.first.isVerified, isTrue);
    });

    testWidgets('PinnedMessageBanner displays pinned message content and triggers callbacks', (tester) async {
      var tapped = false;
      final msg = Message(
        id: '110',
        chatId: '55',
        senderId: '1',
        senderName: 'Alice',
        content: 'Release 2.0 is live',
        messageType: 'text',
        isEdited: false,
        createdAt: '2026-10-31T11:00:00Z',
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PinnedMessageBanner(
              message: msg,
              totalPinnedCount: 2,
              currentPinnedIndex: 0,
              onTap: () => tapped = true,
            ),
          ),
        ),
      );

      expect(find.textContaining('Закреплённое сообщение'), findsOneWidget);
      expect(find.text('Release 2.0 is live'), findsOneWidget);

      await tester.tap(find.text('Release 2.0 is live'));
      expect(tapped, isTrue);
    });
  });

  group('Phase 5: Bot API v7, Keyboards, Commands & @BotMother UI', () {
    test('BotInfo.fromJson and MessageReplyMarkup parse inline and reply keyboards', () {
      final botInfo = BotInfo.fromJson({
        'user_id': '42',
        'username': 'BotMother',
        'about': 'Official bot creator for Theaver',
        'description': 'Use /newbot to create a bot and get an HTTP token.',
        'commands': [
          {'command': '/newbot', 'description': 'Create a new bot'},
          {'command': 'mybots', 'description': 'Manage your bots'},
        ],
      });

      expect(botInfo.userId, '42');
      expect(botInfo.aboutText, 'Official bot creator for Theaver');
      expect(botInfo.commands, hasLength(2));
      expect(botInfo.commands[0].normalizedCommand, '/newbot');
      expect(botInfo.commands[1].normalizedCommand, '/mybots');

      final msg = Message.fromJson({
        'id': '500',
        'chat_id': '100',
        'sender_id': '42',
        'sender_name': 'BotMother',
        'content': 'Here is your token:',
        'message_type': 'text',
        'created_at': '2026-10-31T12:00:00Z',
        'reply_markup': {
          'inline_keyboard': [
            [
              {'text': 'Copy Token', 'copy_text': {'text': '123456:ABC-DEF'}},
              {'text': 'Revoke', 'callback_data': 'revoke_42'},
            ],
          ],
        },
      });

      final inlineRows = msg.inlineKeyboard;
      expect(inlineRows, hasLength(1));
      expect(inlineRows.first[0]['copy_text']['text'], '123456:ABC-DEF');
      expect(inlineRows.first[1]['callback_data'], 'revoke_42');
    });

    testWidgets('InlineKeyboardWidget, BotWelcomeCard, BotCommandsPopup, and ReplyKeyboardPanel render properly', (tester) async {
      String? selectedCommand;
      String? pressedReplyButton;

      const botInfo = BotInfo(
        userId: '42',
        username: 'BotMother',
        about: 'Create and manage Theaver bots',
        commands: [
          BotCommand(command: 'newbot', description: 'Create a new bot'),
          BotCommand(command: 'token', description: 'Generate token'),
        ],
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Column(
              children: [
                Expanded(
                  child: BotWelcomeCard(
                    botName: 'BotMother',
                    botUsername: 'BotMother',
                    botInfo: botInfo,
                    onCommandTap: (cmd) => selectedCommand = cmd,
                  ),
                ),
                BotCommandsPopup(
                  commands: botInfo.commands,
                  onSelectCommand: (cmd) => selectedCommand = cmd.normalizedCommand,
                ),
                ReplyKeyboardPanel(
                  rows: const [
                    [
                      {'text': '/newbot'},
                      {'text': '/mybots'},
                    ],
                  ],
                  onButtonPressed: (text) => pressedReplyButton = text,
                ),
                const InlineKeyboardWidget(
                  chatId: '100',
                  messageId: '500',
                  rows: [
                    [
                      {
                        'text': 'Copy API Token',
                        'copy_text': {'text': '123:TOKEN'},
                      },
                    ],
                  ],
                ),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Что умеет этот бот?'), findsOneWidget);
      expect(find.text('Команды бота'), findsOneWidget);
      expect(find.text('Copy API Token'), findsOneWidget);

      await tester.tap(find.text('/mybots'));
      expect(pressedReplyButton, '/mybots');
      expect(selectedCommand, isNull);
    });
  });
}
