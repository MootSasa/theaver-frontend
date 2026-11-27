import 'package:flutter/foundation.dart' show SynchronousFuture;
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/models/chat_draft.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/draft_service.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/services/peer_customization_cache.dart';
import 'package:theaver/services/profile_theme_provider.dart';
import 'package:theaver/widgets/chat/chat_list_tile_item.dart';
import 'package:theaver/widgets/chat/message_reply_info.dart';
import 'package:theaver/widgets/chat/reply_preview_bar.dart';
import 'package:theaver/widgets/message/message_bubble.dart';
import 'package:theaver/widgets/message/message_status_widget.dart';

class _SyncAppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _SyncAppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) =>
      SynchronousFuture<AppLocalizations>(AppLocalizations(locale));

  @override
  bool shouldReload(_SyncAppLocalizationsDelegate old) => false;
}

class _ForcedGlassProvider extends LiquidGlassProvider {
  _ForcedGlassProvider(this._forcedMode);

  final GlassMode _forcedMode;

  @override
  GlassMode get mode => _forcedMode;

  @override
  bool get enabled => _forcedMode != GlassMode.disabled;

  @override
  bool get isLite => _forcedMode == GlassMode.lite;

  @override
  bool get isFull => _forcedMode == GlassMode.full;

  @override
  bool get isSupported => true;
}

Widget _wrapTestWidget(Widget child, {Locale locale = const Locale('ru')}) {
  return MultiProvider(
    providers: [
      ChangeNotifierProvider<ProfileThemeProvider>.value(
        value: ProfileThemeProvider(),
      ),
      ChangeNotifierProvider<LiquidGlassProvider>.value(
        value: _ForcedGlassProvider(GlassMode.disabled),
      ),
      ChangeNotifierProvider<PeerCustomizationCache>.value(
        value: PeerCustomizationCache(),
      ),
    ],
    child: MaterialApp(
      locale: locale,
      supportedLocales: const [Locale('ru'), Locale('en')],
      localizationsDelegates: const [
        _SyncAppLocalizationsDelegate(),
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData.light(useMaterial3: true),
      home: Scaffold(body: Center(child: child)),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final service = DraftService();
    service.clearAllForTesting();
    await service.init(userId: 'user-1');
  });

  group('Drafts Model & Service Parity', () {
    test('ChatDraft with empty text and replyToMessageId is treated as empty', () {
      final replyOnly = ChatDraft(
        text: '',
        replyToMessageId: '10',
        isQuote: false,
      );
      expect(replyOnly.isEmpty, isTrue);
      expect(replyOnly.isNotEmpty, isFalse);

      final whitespaceReply = ChatDraft(
        text: '   \n\t ',
        replyToMessageId: '10',
      );
      expect(whitespaceReply.isEmpty, isTrue);
    });

    test('switchAccount isolates drafts per user ID', () async {
      final service = DraftService();
      service.saveDraft('chat-a', text: 'Draft user 1', immediate: true);
      expect(service.getDraft('chat-a')?.text, 'Draft user 1');

      await service.switchAccount('user-2');
      expect(service.getDraft('chat-a'), isNull);
      expect(service.getPublishedDraft('chat-a'), isNull);

      service.saveDraft('chat-b', text: 'Draft user 2', immediate: true);
      expect(service.getDraft('chat-b')?.text, 'Draft user 2');

      await service.switchAccount('user-1');
      expect(service.getDraft('chat-a')?.text, 'Draft user 1');
      expect(service.getDraft('chat-b'), isNull);
    });

    test(':topic: and comments: scopes stay local-only and never pollute parent chat preview', () async {
      final service = DraftService();
      final topicScope = DraftService.topicKey('group-1', 77);
      final commentsScope = DraftService.commentsKey('chan-1', '501');

      expect(DraftService.isLocalOnlyScopeKey(topicScope), isTrue);
      expect(DraftService.isLocalOnlyScopeKey(commentsScope), isTrue);
      expect(DraftService.isLocalOnlyScopeKey('group-1'), isFalse);

      service.saveDraft(topicScope, text: 'Topic draft', immediate: true);
      service.saveDraft(commentsScope, text: 'Comment draft', immediate: true);

      expect(service.getDraft(topicScope)?.text, 'Topic draft');
      expect(service.getDraft(commentsScope)?.text, 'Comment draft');
      expect(service.getPublishedDraft('group-1'), isNull);
      expect(service.getPublishedDraft('chan-1'), isNull);
      expect(service.draftsNotifier.value.containsKey(topicScope), isFalse);
      expect(service.draftsNotifier.value.containsKey(commentsScope), isFalse);
      expect(service.draftsNotifier.value.containsKey('group-1'), isFalse);
      expect(service.draftsNotifier.value.containsKey('chan-1'), isFalse);
    });

    test('clearLocalDraftOnSend cancels pending timer and populateFromChats(authoritative: true) prunes stale synced drafts while keeping local scopes', () async {
      final service = DraftService();
      final topicScope = DraftService.topicKey('group-1', 5);
      final commentsScope = DraftService.commentsKey('chan-1', '99');

      service.saveDraft(topicScope, text: 'Keep local topic');
      service.saveDraft(commentsScope, text: 'Keep local comments');

      // Start debounced draft (not immediately published), then send immediately.
      service.saveDraft(
        'chat-send',
        text: 'About to send',
        replyToMessageId: '12',
      );
      expect(service.getDraft('chat-send')?.text, 'About to send');
      service.clearLocalDraftOnSend('chat-send');
      expect(service.getDraft('chat-send'), isNull);
      expect(service.getPublishedDraft('chat-send'), isNull);

      // Add stale published draft on chat-stale, then sync authoritatively without it.
      service.saveDraft('chat-stale', text: 'Old server draft', immediate: true);
      service.saveDraft('chat-live', text: 'Keep synced draft', immediate: true);

      service.populateFromChats([
        Chat(
          id: 'chat-stale',
          chatType: 'private',
          name: 'Stale Peer',
          updatedAt: '2026-11-24T12:00:00Z',
          draft: null,
        ),
        Chat(
          id: 'chat-live',
          chatType: 'private',
          name: 'Live Peer',
          updatedAt: '2026-11-24T12:00:00Z',
          draft: ChatDraft(
            text: 'Keep synced draft',
            updatedAt: DateTime.utc(2026, 11, 24, 12, 0),
          ),
        ),
      ], authoritative: true);

      expect(service.getDraft('chat-stale'), isNull);
      expect(service.getPublishedDraft('chat-stale'), isNull);
      expect(service.getPublishedDraft('chat-live')?.text, 'Keep synced draft');
      expect(service.getDraft(topicScope)?.text, 'Keep local topic');
      expect(service.getDraft(commentsScope)?.text, 'Keep local comments');
    });
  });

  group('ChatListTileItem Draft Rendering', () {
    testWidgets('hides draft on read-only subscriber channel, suppresses outgoing checkmark when draft active, and never renders ellipsis fallback', (tester) async {
      final service = DraftService();
      service.saveDraft('ro-chan', text: 'Should stay hidden', immediate: true);
      service.saveDraft('dm-chat', text: 'Unsent DM text', immediate: true);

      final roChannel = Chat(
        id: 'ro-chan',
        chatType: 'channel',
        name: 'News Channel',
        myRole: 'member',
        lastMessage: 'Channel post',
        lastMessageTime: '2026-11-24T10:00:00Z',
        updatedAt: '2026-11-24T10:00:00Z',
      );

      final dmChat = Chat(
        id: 'dm-chat',
        chatType: 'private',
        name: 'Alex',
        lastMessage: 'Sent message',
        lastMessageSenderId: 'user-1',
        lastMessageTime: '2026-11-24T10:00:00Z',
        updatedAt: '2026-11-24T10:00:00Z',
      );

      await tester.pumpWidget(
        _wrapTestWidget(
          Column(
            children: [
              ChatListTileItem(
                chat: roChannel,
                isSelectMode: false,
                isSelected: false,
                isMuted: false,
                currentUserId: 'user-1',
                onTap: () {},
                onLongPress: () {},
                onSwipeAction: (_) async {},
              ),
              ChatListTileItem(
                chat: dmChat,
                isSelectMode: false,
                isSelected: false,
                isMuted: false,
                currentUserId: 'user-1',
                onTap: () {},
                onLongPress: () {},
                onSwipeAction: (_) async {},
              ),
            ],
          ),
        ),
      );

      expect(find.textContaining('Should stay hidden'), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              w.text.toPlainText().contains('Should stay hidden'),
        ),
        findsNothing,
      );
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is RichText && w.text.toPlainText().contains('Channel post'),
        ),
        findsOneWidget,
      );
      expect(
        find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains('...'),
        ),
        findsNothing,
      );
      // DM shows draft text via RichText, so outgoing MessageStatusWidget is suppressed.
      expect(find.byType(MessageStatusWidget), findsNothing);
      expect(
        find.byWidgetPredicate(
          (w) =>
              w is RichText &&
              w.text.toPlainText().contains('Unsent DM text'),
        ),
        findsOneWidget,
      );
    });
  });

  group('Channel Attribution & Comment Bubble Parity', () {
    test('Message.resolveEffectiveAuthorTitle always attributes channel or persona instead of personal name', () {
      final channelPost = Message(
        id: '10',
        chatId: 'chan-1',
        senderId: 'user-1',
        senderName: 'Admin Human',
        senderChatId: 'chan-1',
        senderChatName: 'Official Channel',
        content: 'Post text',
        messageType: 'text',
        isEdited: false,
        createdAt: '2026-11-24T10:00:00Z',
      );
      expect(
        channelPost.resolveEffectiveAuthorTitle(chatName: 'Fallback', chatType: 'channel'),
        'Official Channel',
      );

      final mirroredPost = Message(
        id: '11',
        chatId: 'group-1',
        senderId: 'user-1',
        senderName: 'Admin Human',
        channelPostId: '50',
        content: 'Mirrored channel post',
        messageType: 'text',
        isEdited: false,
        createdAt: '2026-11-24T10:00:00Z',
      );
      expect(mirroredPost.isMirroredChannelPost, isTrue);
      expect(
        mirroredPost.resolveEffectiveAuthorTitle(
          chatName: 'Channel Title',
          chatType: 'group',
        ),
        'Channel Title',
      );

      final sendAsChannelMsg = Message(
        id: '12',
        chatId: 'group-1',
        senderId: 'user-1',
        senderName: 'Human Author',
        senderChatId: 'chan-99',
        senderChatName: 'Guest Channel',
        content: 'Reply as channel',
        messageType: 'text',
        isEdited: false,
        createdAt: '2026-11-24T10:00:00Z',
      );
      expect(sendAsChannelMsg.isChannelOrPersonaAuthored, isTrue);
      expect(sendAsChannelMsg.resolveEffectiveAuthorTitle(), 'Guest Channel');
    });

    testWidgets('MessageBubble does not render Комментарий к посту for thread comments', (tester) async {
      final threadComment = Message(
        id: '201',
        chatId: 'group-1',
        senderId: 'user-2',
        senderName: 'Commenter',
        threadRootMessageId: '100',
        content: 'Just a regular discussion reply',
        messageType: 'text',
        isEdited: false,
        createdAt: '2026-11-24T10:00:00Z',
      );

      await tester.pumpWidget(
        _wrapTestWidget(
          MessageBubble(
            message: threadComment,
            isMe: false,
            currentUserId: 'user-1',
            chatType: 'group',
            chatTitle: 'Discussion Group',
            formatTime: (_) => '10:00',
          ),
        ),
      );

      expect(find.textContaining('Комментарий к посту'), findsNothing);
      expect(find.textContaining('Just a regular discussion reply'), findsOneWidget);
    });

    testWidgets('ReplyPreviewBar and MessageReplyInfo display Channel name rather than Вы or personal admin name', (tester) async {
      final mirroredChannelPost = Message(
        id: '300',
        chatId: 'group-1',
        senderId: 'user-1',
        senderName: 'Personal Admin',
        channelPostId: '50',
        senderChatId: 'chan-1',
        senderChatName: 'Tech Channel',
        content: 'Channel announcement',
        messageType: 'text',
        isEdited: false,
        createdAt: '2026-11-24T10:00:00Z',
      );

      const channelReplyInfo = ReplyInfo(
        messageId: '300',
        senderId: '0',
        senderName: 'Tech Channel',
        content: 'Channel announcement',
        messageType: 'text',
      );

      await tester.pumpWidget(
        _wrapTestWidget(
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ReplyPreviewBar(
                replyToMessage: mirroredChannelPost,
                currentUserId: 'user-1',
                onClose: () {},
              ),
              const SizedBox(height: 12),
              const MessageReplyInfo(
                replyInfo: channelReplyInfo,
                currentUserId: 'user-1',
              ),
            ],
          ),
        ),
      );

      expect(find.text('Tech Channel'), findsNWidgets(2));
      expect(find.text('Personal Admin'), findsNothing);
      expect(find.text('Вы'), findsNothing);
    });
  });
}
