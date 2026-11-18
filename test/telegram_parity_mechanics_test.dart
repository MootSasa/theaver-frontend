import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/models/profile_customization.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/utils/entity_parser.dart';
import 'package:theaver/widgets/chat/chat_selection_header.dart';
import 'package:theaver/widgets/chat/pinned_message_banner.dart';
import 'package:theaver/widgets/chat/telegram_delete_messages_sheet.dart';
import 'package:theaver/widgets/user/avatar_decoration_frame.dart';
import 'package:theaver/widgets/user/avatar_with_status.dart';

bool _hasUnpairedUtf16Surrogate(String value) {
  final units = value.codeUnits;
  for (int i = 0; i < units.length; i++) {
    final unit = units[i];
    if (unit >= 0xD800 && unit <= 0xDBFF) {
      if (i + 1 >= units.length) return true;
      final next = units[i + 1];
      if (next < 0xDC00 || next > 0xDFFF) return true;
      i++;
    } else if (unit >= 0xDC00 && unit <= 0xDFFF) {
      return true;
    }
  }
  return false;
}

void main() {
  group('Telegram parity models & EntityParser', () {
    test('Chat.fromJson and ChatDetails.fromJson parse protected content & multi-pins', () {
      final chat = Chat.fromJson({
        'id': '101',
        'chat_type': 'channel',
        'name': 'Protected Channel',
        'has_protected_content': true,
        'pinned_message_ids': [501, 502, 503],
      });

      expect(chat.id, '101');
      expect(chat.chatType, 'channel');
      expect(chat.hasProtectedContent, isTrue);
      expect(chat.pinnedMessageIds, [501, 502, 503]);

      final details = ChatDetails.fromJson({
        'id': '101',
        'chat_type': 'group',
        'name': 'Protected Group',
        'has_protected_content': true,
        'pinned_message_ids': ['601', '602'],
      });

      expect(details.hasProtectedContent, isTrue);
      expect(details.pinnedMessageIds, [601, 602]);
    });

    test('Message.fromJson, ScheduledMessage.fromJson, and ChatJoinRequest.fromJson', () {
      final message = Message.fromJson({
        'id': '700',
        'chat_id': '101',
        'sender_id': '42',
        'content': 'Spoiler photo',
        'message_type': 'image',
        'created_at': '2026-11-18T12:00:00Z',
        'has_media_spoiler': true,
      });
      expect(message.hasMediaSpoiler, isTrue);

      final scheduled = ScheduledMessage.fromJson({
        'id': '800',
        'chat_id': '101',
        'sender_id': '42',
        'content': 'Wait until online',
        'message_type': 'text',
        'has_media_spoiler': true,
        'send_when_online': true,
        'is_silent': true,
        'schedule_at': '2026-11-19T09:00:00Z',
        'created_at': '2026-11-18T12:00:00Z',
      });
      expect(scheduled.hasMediaSpoiler, isTrue);
      expect(scheduled.sendWhenOnline, isTrue);
      expect(scheduled.isSilent, isTrue);
      expect(scheduled.toMessage().hasMediaSpoiler, isTrue);

      final joinRequest = ChatJoinRequest.fromJson({
        'id': '9',
        'user_id': '42',
        'username': 'alice',
        'display_name': 'Alice Doe',
        'invite_link_id': 7,
        'requested_at': '2026-11-18T12:00:00Z',
      });
      expect(joinRequest.id, '9');
      expect(joinRequest.userId, '42');
      expect(joinRequest.username, 'alice');
      expect(joinRequest.displayName, 'Alice Doe');
      expect(joinRequest.inviteLinkId, 7);
      expect(joinRequest.requestedAt, isNotNull);
    });

    test('EntityParser.snapUtf16Offset and safeSubstring never split surrogate pairs', () {
      const text = 'Hi 👋🏽 world';
      // Index 4 splits '👋' (high surrogate at 3, low surrogate at 4).
      final snapped = EntityParser.snapUtf16Offset(text, 4);
      expect(snapped, isNot(equals(4)));
      expect(snapped >= 3 && snapped <= text.length, isTrue);

      for (int i = 0; i <= text.length + 2; i++) {
        final sub = EntityParser.safeSubstring(text, 0, i);
        expect(_hasUnpairedUtf16Surrogate(sub), isFalse);
      }

      expect(_hasUnpairedUtf16Surrogate(EntityParser.safeSubstring(text, 4)), isFalse);
    });
  });

  group('Telegram parity UI widgets', () {
    testWidgets('ChatMessageSelectionHeader Variant A renders 2 islands and hides copy/forward when protected',
        (tester) async {
      var cancelled = false;
      var copied = false;
      var forwarded = false;
      var deleted = false;

      Widget buildHeader({required bool hasProtectedContent}) {
        return MaterialApp(
          home: Scaffold(
            body: SafeArea(
              child: ChatMessageSelectionHeader(
                selectedCount: 2,
                hasProtectedContent: hasProtectedContent,
                onCancel: () => cancelled = true,
                onReply: () {},
                onCopy: () => copied = true,
                onPin: () {},
                onForward: () => forwarded = true,
                onDelete: () => deleted = true,
              ),
            ),
          ),
        );
      }

      // Unprotected chat: all 5 actions + 2 islands visible.
      await tester.pumpWidget(buildHeader(hasProtectedContent: false));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat_message_selection_left_island')), findsOneWidget);
      expect(find.byKey(const Key('chat_message_selection_right_island')), findsOneWidget);
      expect(find.byKey(const Key('msg_sel_action_reply')), findsOneWidget);
      expect(find.byKey(const Key('msg_sel_action_copy')), findsOneWidget);
      expect(find.byKey(const Key('msg_sel_action_pin')), findsOneWidget);
      expect(find.byKey(const Key('msg_sel_action_forward')), findsOneWidget);
      expect(find.byKey(const Key('msg_sel_action_delete')), findsOneWidget);

      await tester.tap(find.byKey(const Key('msg_sel_action_copy')));
      await tester.tap(find.byKey(const Key('msg_sel_action_forward')));
      await tester.tap(find.byKey(const Key('msg_sel_action_delete')));
      await tester.pump();
      expect(copied, isTrue);
      expect(forwarded, isTrue);
      expect(deleted, isTrue);

      // Protected content chat: copy and forward must be hidden.
      await tester.pumpWidget(buildHeader(hasProtectedContent: true));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('chat_message_selection_left_island')), findsOneWidget);
      expect(find.byKey(const Key('chat_message_selection_right_island')), findsOneWidget);
      expect(find.byKey(const Key('msg_sel_action_copy')), findsNothing);
      expect(find.byKey(const Key('msg_sel_action_forward')), findsNothing);
      expect(find.byKey(const Key('msg_sel_action_reply')), findsOneWidget);
      expect(find.byKey(const Key('msg_sel_action_pin')), findsOneWidget);
      expect(find.byKey(const Key('msg_sel_action_delete')), findsOneWidget);

      await tester.tap(find.byKey(const Key('chat_message_selection_left_island')));
      await tester.pump();
      expect(cancelled, isTrue);
    });

    testWidgets('PinnedMessageBanner shows pinned list button when totalPinnedCount > 1',
        (tester) async {
      final pinnedMsg = Message.fromJson({
        'id': '11',
        'chat_id': '1',
        'sender_id': '2',
        'content': 'Важное объявление',
        'message_type': 'text',
        'created_at': '2026-11-18T12:00:00Z',
      });
      var openedList = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PinnedMessageBanner(
              message: pinnedMsg,
              totalPinnedCount: 3,
              currentPinnedIndex: 0,
              canUnpin: true,
              onTap: () {},
              onUnpin: () {},
              onOpenPinnedList: () => openedList = true,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final listBtn = find.byKey(const Key('pinned_banner_list_btn'));
      expect(listBtn, findsOneWidget);
      await tester.tap(listBtn);
      await tester.pump();
      expect(openedList, isTrue);

      // Single pinned message with unpin permission hides the list button.
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: PinnedMessageBanner(
              message: pinnedMsg,
              totalPinnedCount: 1,
              currentPinnedIndex: 0,
              canUnpin: true,
              onTap: () {},
              onUnpin: () {},
              onOpenPinnedList: () {},
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('pinned_banner_list_btn')), findsNothing);
    });

    testWidgets('showTelegramDeleteMessagesSheet handles DM revoke toggle and Group moderation options',
        (tester) async {
      TelegramDeleteMessagesResult? dmResult;
      TelegramDeleteMessagesResult? modResult;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => Column(
                children: [
                  ElevatedButton(
                    onPressed: () async {
                      dmResult = await showTelegramDeleteMessagesSheet(
                        context: context,
                        messageCount: 1,
                        chatType: 'private',
                        peerName: 'Алиса',
                        canRevoke: true,
                        defaultRevoke: false,
                      );
                    },
                    child: const Text('OpenDMDelete'),
                  ),
                  ElevatedButton(
                    onPressed: () async {
                      modResult = await showTelegramDeleteMessagesSheet(
                        context: context,
                        messageCount: 2,
                        chatType: 'group',
                        canRevoke: true,
                        canModerateOther: true,
                        targetAuthorName: 'Спамер',
                      );
                    },
                    child: const Text('OpenGroupModDelete'),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

      // 1. DM revoke flow
      await tester.tap(find.text('OpenDMDelete'));
      await tester.pumpAndSettle();
      expect(find.text('Также удалить для Алиса'), findsOneWidget);
      await tester.tap(find.text('Также удалить для Алиса'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить'));
      await tester.pumpAndSettle();

      expect(dmResult, isNotNull);
      expect(dmResult!.confirmed, isTrue);
      expect(dmResult!.revoke, isTrue);
      expect(dmResult!.reportSpam, isFalse);

      // 2. Group moderation flow
      await tester.tap(find.text('OpenGroupModDelete'));
      await tester.pumpAndSettle();
      expect(find.text('Модерация участника'), findsOneWidget);
      expect(find.text('Пожаловаться на спам'), findsOneWidget);
      expect(find.text('Удалить все от Спамер'), findsOneWidget);
      expect(find.text('Заблокировать Спамер'), findsOneWidget);

      await tester.tap(find.text('Пожаловаться на спам'));
      await tester.tap(find.text('Заблокировать Спамер'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Удалить (2)'));
      await tester.pumpAndSettle();

      expect(modResult, isNotNull);
      expect(modResult!.confirmed, isTrue);
      expect(modResult!.reportSpam, isTrue);
      expect(modResult!.banUser, isTrue);
      expect(modResult!.deleteAllFromUser, isFalse);
    });

    testWidgets(
        'AvatarWithStatus renders online indicator on top of avatar frame when isOnline is true and omits it when false',
        (tester) async {
      const preset = AvatarDecorationPreset(
        id: 'neon_ring',
        nameKey: 'Neon Ring',
        isAnimated: false,
      );

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: AvatarWithStatus(
                avatarUrl: null,
                name: 'Alex',
                radius: 24,
                isOnline: true,
                animateDecoration: false,
                decorationOverride: preset,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final frameFinder = find.byType(AvatarDecorationFrame);
      final indicatorFinder = find.byKey(const ValueKey('avatar_online_indicator'));
      final clipPathFinder = find.descendant(
        of: find.byType(AvatarWithStatus),
        matching: find.byType(ClipPath),
      );

      expect(frameFinder, findsOneWidget);
      expect(indicatorFinder, findsOneWidget);
      expect(clipPathFinder, findsOneWidget);

      final outerStack = tester.widget<Stack>(
        find.ancestor(
          of: indicatorFinder,
          matching: find.byType(Stack),
        ).first,
      );
      expect(outerStack.children.length, 2);
      expect(outerStack.children[0], isA<ClipPath>());
      expect(outerStack.children[1], isA<Positioned>());
      expect(
        find.descendant(of: clipPathFinder, matching: frameFinder),
        findsOneWidget,
      );

      final renderClipPath = tester.renderObject<RenderClipPath>(clipPathFinder);
      final clipBounds =
          renderClipPath.clipper!.getClip(renderClipPath.size).getBounds();
      expect(renderClipPath.size, const Size(48, 48));
      expect(clipBounds.width, greaterThan(48));
      expect(clipBounds.height, greaterThan(48));

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: Center(
              child: AvatarWithStatus(
                avatarUrl: null,
                name: 'Alex',
                radius: 24,
                isOnline: false,
                animateDecoration: false,
                decorationOverride: preset,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(frameFinder, findsOneWidget);
      expect(indicatorFinder, findsNothing);
      expect(clipPathFinder, findsNothing);
    });
  });
}
