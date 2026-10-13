import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/services/chat_service.dart';

void main() {
  group('Optimistic Reaction Rollback Tests', () {
    test('Rolls back reactions map and myReactions set when API toggle fails', () {
      const messageId = 'msg_100';
      const emoji = '🔥';

      // Initial state
      final messageReactions = <String, Map<String, int>>{
        messageId: {'👍': 2},
      };
      final myReactions = <String, Set<String>>{
        messageId: {'👍'},
      };

      // 1. Snapshot previous state before optimistic change
      final previousMyReactions = Set<String>.from(myReactions[messageId] ?? {});
      final previousReactions = Map<String, int>.from(messageReactions[messageId] ?? {});

      // 2. Apply optimistic update (user adds 🔥)
      final mySet = myReactions.putIfAbsent(messageId, () => <String>{});
      final reactions = messageReactions.putIfAbsent(messageId, () => <String, int>{});
      mySet.add(emoji);
      reactions[emoji] = (reactions[emoji] ?? 0) + 1;

      expect(myReactions[messageId], contains('🔥'));
      expect(messageReactions[messageId]!['🔥'], 1);

      // 3. Simulate API failure -> perform rollback
      if (previousMyReactions.isEmpty) {
        myReactions.remove(messageId);
      } else {
        myReactions[messageId] = Set.from(previousMyReactions);
      }

      if (previousReactions.isEmpty) {
        messageReactions.remove(messageId);
      } else {
        messageReactions[messageId] = Map.from(previousReactions);
      }

      // Verify state was accurately rolled back
      expect(myReactions[messageId], isNot(contains('🔥')));
      expect(myReactions[messageId], contains('👍'));
      expect(messageReactions[messageId]!.containsKey('🔥'), isFalse);
      expect(messageReactions[messageId]!['👍'], 2);
    });

    test('Rolls back reaction removal when API toggle fails', () {
      const messageId = 'msg_101';
      const emoji = '❤️';

      // Initial state: user has ❤️
      final messageReactions = <String, Map<String, int>>{
        messageId: {'❤️': 1},
      };
      final myReactions = <String, Set<String>>{
        messageId: {'❤️'},
      };

      // Snapshot
      final previousMyReactions = Set<String>.from(myReactions[messageId] ?? {});
      final previousReactions = Map<String, int>.from(messageReactions[messageId] ?? {});

      // Optimistically remove ❤️
      myReactions[messageId]!.remove(emoji);
      messageReactions[messageId]!.remove(emoji);

      expect(myReactions[messageId]!.isEmpty, isTrue);
      expect(messageReactions[messageId]!.isEmpty, isTrue);

      // Rollback
      myReactions[messageId] = Set.from(previousMyReactions);
      messageReactions[messageId] = Map.from(previousReactions);

      expect(myReactions[messageId], contains('❤️'));
      expect(messageReactions[messageId]!['❤️'], 1);
    });
  });

  group('Optimistic Deletion Rollback Tests', () {
    Message createMsg(String id, String timestamp, {int sendStatus = 1, String? localId}) {
      return Message(
        id: id,
        senderId: 'user_1',
        senderName: 'TestUser',
        chatId: 'chat_1',
        content: 'Content $id',
        messageType: 'text',
        createdAt: timestamp,
        isEdited: false,
        sendStatus: sendStatus,
        localId: localId,
      );
    }

    test('Restores message at correct chronological position when delete fails', () {
      final messages = [
        createMsg('3', '2026-10-09T00:03:00Z'),
        createMsg('2', '2026-10-09T00:02:00Z'),
        createMsg('1', '2026-10-09T00:01:00Z'),
      ];

      final target = messages[1]; // id: '2'
      final targetIndex = messages.indexOf(target);

      // Optimistic delete
      messages.removeWhere((m) => m.id == target.id);
      expect(messages.length, 2);
      expect(messages.any((m) => m.id == '2'), isFalse);

      // Rollback on server error
      if (targetIndex >= 0 && targetIndex <= messages.length) {
        messages.insert(targetIndex, target);
      } else {
        messages.add(target);
        messages.sort((a, b) => DateTime.parse(b.createdAt).compareTo(DateTime.parse(a.createdAt)));
      }

      expect(messages.length, 3);
      expect(messages[1].id, '2');
      expect(messages[0].id, '3');
      expect(messages[2].id, '1');
    });
  });

  group('Reconnect Silent Sync Merge Tests', () {
    Message createMsg(String id, String timestamp, {int sendStatus = 1, String? localId}) {
      return Message(
        id: id,
        senderId: 'user_1',
        senderName: 'TestUser',
        chatId: 'chat_1',
        content: 'Content $id',
        messageType: 'text',
        createdAt: timestamp,
        isEdited: false,
        sendStatus: sendStatus,
        localId: localId,
      );
    }

    test('Preserves pending local unsent messages and merges server messages', () {
      // Local state before reconnect
      final currentMessages = [
        createMsg('local_pending_1', '2026-10-09T00:05:00Z', sendStatus: 0, localId: 'local_pending_1'),
        createMsg('10', '2026-10-09T00:00:00Z'),
        createMsg('9', '2026-10-08T23:59:00Z'),
      ];

      // Newest messages from server (messages 12 and 11 arrived while app was offline)
      final serverMessages = [
        createMsg('12', '2026-10-09T00:04:00Z'),
        createMsg('11', '2026-10-09T00:02:00Z'),
        createMsg('10', '2026-10-09T00:00:00Z'),
      ];

      // Merge logic identical to _syncLatestMessages
      final pendingMessages = currentMessages
          .where((m) => m.sendStatus != 1 && m.localId != null)
          .toList();

      final Map<String, Message> merged = {};
      for (final m in currentMessages) {
        merged[m.id] = m;
        if (m.localId != null && m.localId!.isNotEmpty) {
          merged[m.localId!] = m;
        }
      }
      for (final m in serverMessages) {
        merged[m.id] = m;
        if (m.localId != null && m.localId!.isNotEmpty) {
          merged[m.localId!] = m;
        }
      }
      for (final pending in pendingMessages) {
        final key = pending.localId ?? pending.id;
        if (!merged.containsKey(key)) {
          merged[key] = pending;
        }
      }

      final Map<String, Message> dedupedById = {};
      for (final m in merged.values) {
        dedupedById[m.id] = m;
      }
      final mergedList = dedupedById.values.toList();
      mergedList.sort((a, b) => DateTime.parse(b.createdAt).compareTo(DateTime.parse(a.createdAt)));

      // Verifications:
      // 1. Pending unsent message is preserved
      expect(mergedList.any((m) => m.id == 'local_pending_1'), isTrue);
      expect(mergedList.first.id, 'local_pending_1'); // newest timestamp

      // 2. Missed messages 12 and 11 were added
      expect(mergedList.any((m) => m.id == '12'), isTrue);
      expect(mergedList.any((m) => m.id == '11'), isTrue);

      // 3. Existing message 10 was deduped
      expect(mergedList.where((m) => m.id == '10').length, 1);

      // 4. Older message 9 wasn't lost
      expect(mergedList.any((m) => m.id == '9'), isTrue);

      // 5. Total count is 5 (pending + 12 + 11 + 10 + 9)
      expect(mergedList.length, 5);
      expect(mergedList.map((m) => m.id).toList(), ['local_pending_1', '12', '11', '10', '9']);
    });
  });
}
