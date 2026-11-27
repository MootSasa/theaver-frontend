import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/models/profile_customization.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/widgets/message/group_message_avatar_row.dart';
import 'package:theaver/widgets/user/avatar_with_status.dart';

Message _buildMessage({
  required String id,
  required String senderId,
  required DateTime createdAt,
  String messageType = 'text',
}) {
  return Message(
    id: id,
    chatId: 'group_1',
    senderId: senderId,
    senderName: 'User $senderId',
    content: 'Hello $id',
    messageType: messageType,
    isEdited: false,
    createdAt: createdAt.toUtc().toIso8601String(),
  );
}

void main() {
  test('Sender cluster helpers group consecutive messages within 5 min on same local day', () {
    final t0 = DateTime(2026, 11, 14, 14, 0, 0);
    final t2 = DateTime(2026, 11, 14, 14, 2, 0);
    final t6 = DateTime(2026, 11, 14, 14, 6, 0);
    final nextDay = DateTime(2026, 11, 15, 0, 1, 0);

    final m1 = _buildMessage(id: '1', senderId: 'u1', createdAt: t0);
    final m2 = _buildMessage(id: '2', senderId: 'u1', createdAt: t2);
    final m3SameTooLate = _buildMessage(id: '3', senderId: 'u1', createdAt: t6);
    final m4DiffUser = _buildMessage(id: '4', senderId: 'u2', createdAt: t2);
    final m5System = _buildMessage(id: '5', senderId: 'u1', createdAt: t2, messageType: 'system');
    final m6NextDay = _buildMessage(
      id: '6',
      senderId: 'u1',
      createdAt: DateTime(2026, 11, 14, 23, 59, 0),
    );
    final m7NextDay = _buildMessage(id: '7', senderId: 'u1', createdAt: nextDay);

    expect(areMessagesInSameSenderCluster(m1, m2), isTrue);
    expect(areMessagesInSameSenderCluster(m2, m3SameTooLate), isTrue); // |t6 - t2| = 4 min <= 5 min
    expect(areMessagesInSameSenderCluster(m1, m3SameTooLate), isFalse); // 6 min > 5 min
    expect(areMessagesInSameSenderCluster(m1, m4DiffUser), isFalse);
    expect(areMessagesInSameSenderCluster(m1, m5System), isFalse);
    expect(areMessagesInSameSenderCluster(m6NextDay, m7NextDay), isFalse);

    expect(isFirstInSenderCluster(current: m1, olderNeighbor: null), isTrue);
    expect(isFirstInSenderCluster(current: m2, olderNeighbor: m1), isFalse);
    expect(isFirstInSenderCluster(current: m3SameTooLate, olderNeighbor: m1), isTrue);

    expect(isLastInSenderCluster(current: m1, newerNeighbor: m2), isFalse);
    expect(isLastInSenderCluster(current: m2, newerNeighbor: m4DiffUser), isTrue);
    expect(isLastInSenderCluster(current: m2, newerNeighbor: null), isTrue);
  });

  testWidgets('GroupMessageAvatarRow mounts AvatarWithStatus only when showAvatar is true', (tester) async {
    var tapped = false;
    final badge = UserBadge.builtInDefaults.first;
    final cust = PeerCustomization(
      badge: badge,
      emojiStatus: const EmojiStatusData(type: 'unicode', emoji: '✨'),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              GroupMessageAvatarRow(
                senderId: 'u1',
                senderName: 'Alice',
                showAvatar: true,
                customizationOverride: cust,
                onAvatarTap: () => tapped = true,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SenderHeaderRow(
                      senderName: 'Alice',
                      nameColor: Colors.blue,
                      customization: cust,
                    ),
                    const Text('Bubble 1'),
                  ],
                ),
              ),
              const GroupMessageAvatarRow(
                senderId: 'u1',
                senderName: 'Alice',
                showAvatar: false,
                child: Text('Bubble 2'),
              ),
            ],
          ),
        ),
      ),
    );

    expect(find.byType(AvatarWithStatus), findsOneWidget);
    expect(find.text('CREATOR'), findsOneWidget);
    expect(find.text('✨'), findsOneWidget);

    await tester.tap(find.byType(AvatarWithStatus));
    expect(tapped, isTrue);
  });
}
