import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/models/chat_draft.dart';
import 'package:theaver/services/draft_service.dart';
import 'package:theaver/services/chat_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final service = DraftService();
    service.clearAllForTesting();
    await service.init();
  });

  group('ChatDraft Model Tests', () {
    test('toJson and fromJson serialize correctly', () {
      final now = DateTime.now();
      final draft = ChatDraft(
        text: 'Hello world',
        replyToMessageId: 'msg-123',
        quoteText: 'quoted line',
        isQuote: true,
        updatedAt: now,
      );

      final json = draft.toJson();
      expect(json['text'], 'Hello world');
      expect(json['reply_to_message_id'], 'msg-123');
      expect(json['quote_text'], 'quoted line');
      expect(json['is_quote'], true);

      final restored = ChatDraft.fromJson(json);
      expect(restored.text, 'Hello world');
      expect(restored.replyToMessageId, 'msg-123');
      expect(restored.quoteText, 'quoted line');
      expect(restored.isQuote, true);
      expect(restored.isNotEmpty, true);
      expect(restored.isEmpty, false);
    });

    test('isEmpty and isNotEmpty logic', () {
      final emptyDraft = ChatDraft(text: '   ');
      expect(emptyDraft.isEmpty, true);
      expect(emptyDraft.isNotEmpty, false);

      final draftWithReply = ChatDraft(text: '', replyToMessageId: '42');
      expect(draftWithReply.isEmpty, false);
      expect(draftWithReply.isNotEmpty, true);
    });
  });

  group('DraftService Local and Memory State', () {
    test('saveDraft updates memory cache and draftsNotifier immediately', () {
      final service = DraftService();
      expect(service.getDraft('chat-1'), isNull);

      service.saveDraft(
        'chat-1',
        text: 'Draft for chat 1',
        replyToMessageId: 'reply-1',
      );

      final draft = service.getDraft('chat-1');
      expect(draft, isNotNull);
      expect(draft!.text, 'Draft for chat 1');
      expect(draft.replyToMessageId, 'reply-1');
      expect(service.draftsNotifier.value['chat-1']?.text, 'Draft for chat 1');
    });

    test('saveDraft with empty content deletes the draft', () {
      final service = DraftService();
      service.saveDraft('chat-2', text: 'Some text');
      expect(service.getDraft('chat-2'), isNotNull);

      service.saveDraft('chat-2', text: '');
      expect(service.getDraft('chat-2'), isNull);
      expect(service.draftsNotifier.value.containsKey('chat-2'), isFalse);
    });

    test('deleteDraft removes from cache and draftsNotifier', () {
      final service = DraftService();
      service.saveDraft('chat-3', text: 'Draft 3');
      expect(service.getDraft('chat-3'), isNotNull);

      service.deleteDraft('chat-3');
      expect(service.getDraft('chat-3'), isNull);
      expect(service.draftsNotifier.value.containsKey('chat-3'), isFalse);
    });

    test('populateFromChats sets drafts from chats list without overwriting newer existing drafts', () {
      final service = DraftService();
      
      final chatWithoutDraft = Chat(
        id: 'c1',
        chatType: 'private',
        name: 'User 1',
        unreadCount: 0,
        updatedAt: '2026-01-01',
      );

      final chatWithDraft = Chat(
        id: 'c2',
        chatType: 'group',
        name: 'Group 2',
        unreadCount: 0,
        updatedAt: '2026-01-01',
        draft: ChatDraft(text: 'Server draft text', updatedAt: DateTime.parse('2026-01-01T10:00:00Z')),
      );

      service.populateFromChats([chatWithoutDraft, chatWithDraft]);

      expect(service.getDraft('c1'), isNull);
      expect(service.getDraft('c2')?.text, 'Server draft text');
      expect(service.draftsNotifier.value['c2']?.text, 'Server draft text');
    });

    test('handleDraftEvent updates or removes draft correctly from incoming WebSocket event', () {
      final service = DraftService();

      // Incoming update event
      service.handleDraftEvent('chat-ws', {
        'text': 'Ws draft',
        'reply_to_message_id': 'ws-reply',
        'updated_at': DateTime.now().toIso8601String(),
      });

      expect(service.getDraft('chat-ws')?.text, 'Ws draft');
      expect(service.getDraft('chat-ws')?.replyToMessageId, 'ws-reply');

      // Incoming delete event (null draft)
      service.handleDraftEvent('chat-ws', null);
      expect(service.getDraft('chat-ws'), isNull);
    });
  });
}
