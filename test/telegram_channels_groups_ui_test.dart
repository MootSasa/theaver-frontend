import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:iconoir_flutter/iconoir_flutter.dart' as iconoir;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:theaver/l10n/app_localizations.dart';
import 'package:theaver/models/media_album.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/chat_swipe_service.dart';
import 'package:theaver/services/glass_toast_service.dart';
import 'package:theaver/services/liquid_glass_provider.dart';
import 'package:theaver/widgets/chat/channel_bottom_capsule_bar.dart';
import 'package:theaver/widgets/chat/channel_post_card.dart';
import 'package:theaver/widgets/chat/chat_input_bar.dart';
import 'package:theaver/widgets/chat/chat_list_tile_item.dart';
import 'package:theaver/widgets/chat/telegram_avatar_stack.dart';
import 'package:theaver/widgets/message/bubble_tail_painter.dart';
import 'package:theaver/widgets/message/group_message_avatar_row.dart';
import 'package:theaver/widgets/message/media_album_widget.dart';
import 'package:theaver/widgets/message/message_bubble.dart';
import 'package:theaver/widgets/message/message_status_widget.dart';
import 'package:theaver/widgets/message/telegram_service_message_widget.dart';
import 'package:theaver/widgets/tiling/tile_viewport_scope.dart';
import 'package:theaver/widgets/user/avatar_with_status.dart';

const String _k1x1PngBase64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNkYAAAAAYAAjCB0C8AAAAASUVORK5CYII=';

class _TestAppLocalizations extends AppLocalizations {
  _TestAppLocalizations(super.locale);

  @override
  String translate(String key, [Map<String, String>? params]) {
    if (key == 'chat_reply_you') return 'Вы';
    return key;
  }
}

class _TestAppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _TestAppLocalizationsDelegate();

  @override
  bool isSupported(Locale locale) => true;

  @override
  Future<AppLocalizations> load(Locale locale) async =>
      _TestAppLocalizations(locale);

  @override
  bool shouldReload(_TestAppLocalizationsDelegate old) => false;
}

class _OverrideGlassProvider extends LiquidGlassProvider {
  final GlassMode _fixedMode;

  _OverrideGlassProvider(this._fixedMode);

  @override
  GlassMode get mode => _fixedMode;

  @override
  bool get enabled => _fixedMode != GlassMode.disabled;

  @override
  bool get isLite => _fixedMode == GlassMode.lite;

  @override
  bool get isFull => _fixedMode == GlassMode.full;
}

Widget _wrapTestApp(
  Widget child, {
  Brightness brightness = Brightness.light,
  LiquidGlassProvider? glassProvider,
  Size? surfaceSize,
}) {
  final provider = glassProvider ?? _OverrideGlassProvider(GlassMode.disabled);
  final theme = brightness == Brightness.dark
      ? ThemeData.dark(useMaterial3: true)
      : ThemeData.light(useMaterial3: true);

  Widget body = child;
  if (surfaceSize != null) {
    body = SizedBox(
      width: surfaceSize.width,
      height: surfaceSize.height,
      child: child,
    );
  }

  return ChangeNotifierProvider<LiquidGlassProvider>.value(
    value: provider,
    child: MaterialApp(
      theme: theme,
      localizationsDelegates: const [
        _TestAppLocalizationsDelegate(),
        DefaultMaterialLocalizations.delegate,
        DefaultWidgetsLocalizations.delegate,
      ],
      home: Scaffold(body: body),
    ),
  );
}

Message _makeMessage({
  String id = 'msg-1',
  String chatId = 'chat-1',
  String senderId = 'user-1',
  String senderName = 'Alice',
  String content = 'Hello Telegram UI',
  String messageType = 'text',
  bool isEdited = false,
  String? createdAt,
  String? fileUrl,
  Map<String, dynamic>? mediaPayload,
  int viewsCount = 0,
  String? authorSignature,
  String? postAuthorId,
  String? senderRole,
  String? senderAdminTitle,
  bool isFromAnonymousAdmin = false,
  bool isSilent = false,
  int commentsCount = 0,
  bool canComment = false,
  List<RecentReplier> recentRepliers = const [],
}) {
  return Message(
    id: id,
    chatId: chatId,
    senderId: senderId,
    senderName: senderName,
    content: content,
    messageType: messageType,
    isEdited: isEdited,
    createdAt: createdAt ?? '2026-11-18T12:00:00',
    fileUrl: fileUrl,
    mediaPayload: mediaPayload,
    viewsCount: viewsCount,
    authorSignature: authorSignature,
    postAuthorId: postAuthorId,
    senderRole: senderRole,
    senderAdminTitle: senderAdminTitle,
    isFromAnonymousAdmin: isFromAnonymousAdmin,
    isSilent: isSilent,
    commentsCount: commentsCount,
    canComment: canComment,
    recentRepliers: recentRepliers,
  );
}

Chat _makeChat({
  String id = 'chat-1',
  String chatType = 'group',
  String name = 'Design Team',
  String? lastMessage = 'Draft updated',
  String? lastMessageTime = '2026-11-18T12:15:00Z',
  String? lastMessageType = 'text',
  String? lastMessageSenderId,
  String? lastMessageSenderName,
  bool hasActiveCall = false,
  int unreadCount = 0,
}) {
  return Chat(
    id: id,
    chatType: chatType,
    name: name,
    lastMessage: lastMessage,
    lastMessageTime: lastMessageTime,
    lastMessageType: lastMessageType,
    updatedAt: '2026-11-18T12:15:00Z',
    unreadCount: unreadCount,
    lastMessageSenderId: lastMessageSenderId,
    lastMessageSenderName: lastMessageSenderName,
    hasActiveCall: hasActiveCall,
  );
}

Future<void> _setSurface(WidgetTester tester, Size size) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
}

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
  });

  group('Cluster helpers & BubbleTailPainter', () {
    test('groups same sender within 5 minutes and splits beyond boundaries', () {
      final t0 = DateTime(2026, 11, 18, 12, 0, 0);
      final m1 = _makeMessage(
        id: '1',
        senderId: 'alice',
        createdAt: t0.toIso8601String(),
      );
      final m2Within = _makeMessage(
        id: '2',
        senderId: 'alice',
        createdAt: t0.add(const Duration(minutes: 5)).toIso8601String(),
      );
      final m3Over = _makeMessage(
        id: '3',
        senderId: 'alice',
        createdAt: t0
            .add(const Duration(minutes: 5, seconds: 1))
            .toIso8601String(),
      );
      final mBob = _makeMessage(
        id: '4',
        senderId: 'bob',
        senderName: 'Bob',
        createdAt: t0.add(const Duration(minutes: 1)).toIso8601String(),
      );
      final mSystem = _makeMessage(
        id: '5',
        senderId: 'alice',
        messageType: 'system',
        createdAt: t0.add(const Duration(seconds: 30)).toIso8601String(),
      );

      expect(areMessagesInSameSenderCluster(m1, m2Within), isTrue);
      expect(areMessagesInSameSenderCluster(m1, m3Over), isFalse);
      expect(areMessagesInSameSenderCluster(m1, mBob), isFalse);
      expect(areMessagesInSameSenderCluster(m1, mSystem), isFalse);

      // Midnight boundary splits cluster even when timestamps are 2 minutes apart
      final beforeMidnight = _makeMessage(
        id: '6',
        senderId: 'alice',
        createdAt: DateTime(2026, 11, 18, 23, 59, 0).toUtc().toIso8601String(),
      );
      final afterMidnight = _makeMessage(
        id: '7',
        senderId: 'alice',
        createdAt: DateTime(2026, 11, 19, 0, 1, 0).toUtc().toIso8601String(),
      );
      expect(areMessagesInSameSenderCluster(beforeMidnight, afterMidnight), isFalse);
    });

    test('handles anonymous admins and differing adminTitle boundaries', () {
      final t0 = DateTime(2026, 11, 18, 14, 0, 0);
      final anon1 = _makeMessage(
        id: 'a1',
        senderId: 'group-1',
        senderName: 'Core Group',
        isFromAnonymousAdmin: true,
        senderAdminTitle: 'Admin',
        createdAt: t0.toIso8601String(),
      );
      final anon2 = _makeMessage(
        id: 'a2',
        senderId: 'group-1',
        senderName: 'Core Group',
        isFromAnonymousAdmin: true,
        senderAdminTitle: 'Admin',
        createdAt: t0.add(const Duration(minutes: 2)).toIso8601String(),
      );
      final anonDifferentTitle = _makeMessage(
        id: 'a3',
        senderId: 'group-1',
        senderName: 'Core Group',
        isFromAnonymousAdmin: true,
        senderAdminTitle: 'Owner',
        createdAt: t0.add(const Duration(minutes: 3)).toIso8601String(),
      );
      final nonAnonSameId = _makeMessage(
        id: 'u1',
        senderId: 'group-1',
        senderName: 'Core Group',
        isFromAnonymousAdmin: false,
        createdAt: t0.add(const Duration(minutes: 1)).toIso8601String(),
      );

      expect(areMessagesInSameSenderCluster(anon1, anon2), isTrue);
      expect(areMessagesInSameSenderCluster(anon1, anonDifferentTitle), isFalse);
      expect(areMessagesInSameSenderCluster(anon1, nonAnonSameId), isFalse);
    });

    test('isFirstInSenderCluster and isLastInSenderCluster across mixed sequence', () {
      final t0 = DateTime(2026, 11, 18, 15, 0, 0);
      final a1 = _makeMessage(
        id: '1',
        senderId: 'alice',
        createdAt: t0.toIso8601String(),
      );
      final a2 = _makeMessage(
        id: '2',
        senderId: 'alice',
        createdAt: t0.add(const Duration(minutes: 1)).toIso8601String(),
      );
      final a3 = _makeMessage(
        id: '3',
        senderId: 'alice',
        createdAt: t0.add(const Duration(minutes: 2)).toIso8601String(),
      );
      final b1 = _makeMessage(
        id: '4',
        senderId: 'bob',
        senderName: 'Bob',
        createdAt: t0.add(const Duration(minutes: 2, seconds: 30)).toIso8601String(),
      );
      final a4 = _makeMessage(
        id: '5',
        senderId: 'alice',
        createdAt: t0.add(const Duration(minutes: 12)).toIso8601String(),
      );

      expect(isFirstInSenderCluster(current: a1, olderNeighbor: null), isTrue);
      expect(isLastInSenderCluster(current: a1, newerNeighbor: a2), isFalse);

      expect(isFirstInSenderCluster(current: a2, olderNeighbor: a1), isFalse);
      expect(isLastInSenderCluster(current: a2, newerNeighbor: a3), isFalse);

      expect(isFirstInSenderCluster(current: a3, olderNeighbor: a2), isFalse);
      expect(isLastInSenderCluster(current: a3, newerNeighbor: b1), isTrue);

      expect(isFirstInSenderCluster(current: b1, olderNeighbor: a3), isTrue);
      expect(isLastInSenderCluster(current: b1, newerNeighbor: a4), isTrue);

      expect(isFirstInSenderCluster(current: a4, olderNeighbor: b1), isTrue);
      expect(isLastInSenderCluster(current: a4, newerNeighbor: null), isTrue);
    });

    test('computeClusterBubbleBorderRadius matches incoming/outgoing positions', () {
      final incomingFirst = computeClusterBubbleBorderRadius(
        isMe: false,
        isFirstInCluster: true,
        isLastInCluster: false,
      );
      expect(incomingFirst.topLeft.x, 16.0);
      expect(incomingFirst.bottomLeft.x, 6.0);
      expect(incomingFirst.topRight.x, 16.0);
      expect(incomingFirst.bottomRight.x, 16.0);

      final incomingMiddle = computeClusterBubbleBorderRadius(
        isMe: false,
        isFirstInCluster: false,
        isLastInCluster: false,
      );
      expect(incomingMiddle.topLeft.x, 6.0);
      expect(incomingMiddle.bottomLeft.x, 6.0);

      final incomingLast = computeClusterBubbleBorderRadius(
        isMe: false,
        isFirstInCluster: false,
        isLastInCluster: true,
      );
      expect(incomingLast.topLeft.x, 6.0);
      expect(incomingLast.bottomLeft.x, 4.0);

      final outgoingLast = computeClusterBubbleBorderRadius(
        isMe: true,
        isFirstInCluster: false,
        isLastInCluster: true,
      );
      expect(outgoingLast.topRight.x, 6.0);
      expect(outgoingLast.bottomRight.x, 4.0);
      expect(outgoingLast.bottomLeft.x, 16.0);

      final incomingNoTailLast = computeClusterBubbleBorderRadius(
        isMe: false,
        isFirstInCluster: true,
        isLastInCluster: true,
        hasTail: false,
      );
      expect(incomingNoTailLast.bottomLeft.x, 16.0);
    });

    testWidgets('MessageBubble paints BubbleTailPainter only when isLastInCluster',
        (tester) async {
      final msgFirst = _makeMessage(id: 'f1', senderId: 'bob', content: 'First');
      final msgLast = _makeMessage(id: 'f2', senderId: 'bob', content: 'Last');

      await tester.pumpWidget(
        _wrapTestApp(
          Column(
            children: [
              MessageBubble(
                message: msgFirst,
                isMe: false,
                currentUserId: 'me',
                isFirstInCluster: true,
                isLastInCluster: false,
                formatTime: (_) => '12:00',
              ),
              MessageBubble(
                message: msgLast,
                isMe: false,
                currentUserId: 'me',
                isFirstInCluster: false,
                isLastInCluster: true,
                formatTime: (_) => '12:01',
              ),
            ],
          ),
        ),
      );
      await tester.pump();

      final tailPainters = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is BubbleTailPainter,
      );
      expect(tailPainters, findsOneWidget);

      final lastBubbleFinder = find.ancestor(
        of: find.text('Last'),
        matching: find.byType(MessageBubble),
      );
      expect(
        find.descendant(of: lastBubbleFinder, matching: tailPainters),
        findsOneWidget,
      );
    });
  });

  group('ChannelPostCard', () {
    test('formatViewsCount and formatCommentsLabel format compact Telegram strings', () {
      expect(ChannelPostCard.formatViewsCount(0), '0');
      expect(ChannelPostCard.formatViewsCount(942), '942');
      expect(ChannelPostCard.formatViewsCount(1400), '1.4K');
      expect(ChannelPostCard.formatViewsCount(12840), '12.8K');
      expect(ChannelPostCard.formatViewsCount(100000), '100K');
      expect(ChannelPostCard.formatViewsCount(1500000), '1.5M');

      expect(ChannelPostCard.formatCommentsLabel(0), 'Прокомментировать');
      expect(ChannelPostCard.formatCommentsLabel(1), '1 комментарий');
      expect(ChannelPostCard.formatCommentsLabel(3), '3 комментария');
      expect(ChannelPostCard.formatCommentsLabel(5), '5 комментариев');
      expect(ChannelPostCard.formatCommentsLabel(11), '11 комментариев');
      expect(ChannelPostCard.formatCommentsLabel(21), '21 комментарий');
    });

    testWidgets('author state 1 (!signMessages): clean broadcast without author header or signature',
        (tester) async {
      final post = _makeMessage(
        id: 'p1',
        senderId: 'author-1',
        senderName: 'Editor Ivan',
        authorSignature: 'Ivan K.',
        content: 'Official product release',
        viewsCount: 1420,
      );

      await tester.pumpWidget(
        _wrapTestApp(
          ChannelPostCard(
            message: post,
            channelName: 'Product News',
            signMessages: false,
            showAuthorProfiles: false,
            formatTime: (_) => '18:30',
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Official product release'), findsOneWidget);
      expect(find.byType(AvatarWithStatus), findsNothing);
      expect(find.text('Editor Ivan'), findsNothing);
      expect(find.text('Ivan K.'), findsNothing);
      expect(find.text('1.4K'), findsOneWidget);
      expect(find.byType(iconoir.Eye), findsOneWidget);
      expect(find.text('18:30'), findsOneWidget);
    });

    testWidgets('author state 2 (signMessages && !showAuthorProfiles): footer inline signature only',
        (tester) async {
      final post = _makeMessage(
        id: 'p2',
        senderId: 'author-1',
        senderName: 'Editor Ivan',
        authorSignature: 'Ivan K.',
        content: 'Weekly digest',
        viewsCount: 530,
      );

      await tester.pumpWidget(
        _wrapTestApp(
          ChannelPostCard(
            message: post,
            channelName: 'Product News',
            signMessages: true,
            showAuthorProfiles: false,
            formatTime: (_) => '18:35',
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AvatarWithStatus), findsNothing);
      expect(find.text('Ivan K.'), findsOneWidget);
      expect(find.text('530'), findsOneWidget);
      expect(find.text('18:35'), findsOneWidget);
    });

    testWidgets('author state 3 (signMessages && showAuthorProfiles): clickable top author header',
        (tester) async {
      var authorTapped = false;
      final post = _makeMessage(
        id: 'p3',
        senderId: 'author-1',
        postAuthorId: 'author-1',
        senderName: 'Editor Ivan',
        authorSignature: 'Inline Sig Hidden',
        content: 'Deep dive article',
        viewsCount: 2500,
      );

      await tester.pumpWidget(
        _wrapTestApp(
          ChannelPostCard(
            message: post,
            channelName: 'Product News',
            signMessages: true,
            showAuthorProfiles: true,
            formatTime: (_) => '19:00',
            onAuthorTap: () => authorTapped = true,
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(AvatarWithStatus), findsOneWidget);
      expect(find.text('Editor Ivan'), findsOneWidget);
      expect(find.text('Inline Sig Hidden'), findsNothing);

      await tester.tap(find.text('Editor Ivan'));
      await tester.pump();
      expect(authorTapped, isTrue);
    });

    testWidgets('renders comments bar (0 vs N > 0) and circular Share button',
        (tester) async {
      var commentsTapCount = 0;
      var shareTapCount = 0;

      final postNoComments = _makeMessage(
        id: 'p4',
        content: 'Post without comments yet',
        viewsCount: 99,
        commentsCount: 0,
        canComment: true,
      );

      await tester.pumpWidget(
        _wrapTestApp(
          ChannelPostCard(
            message: postNoComments,
            linkedChatId: 'disc-1',
            formatTime: (_) => '10:00',
            onCommentsTap: () => commentsTapCount++,
            onShareTap: () => shareTapCount++,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Прокомментировать'), findsOneWidget);
      expect(find.byType(iconoir.ChatBubble), findsOneWidget);
      expect(find.byType(iconoir.NavArrowRight), findsOneWidget);
      expect(find.byType(TelegramAvatarStack), findsNothing);

      await tester.tap(find.text('Прокомментировать'));
      await tester.pump();
      expect(commentsTapCount, 1);

      await tester.tap(find.byType(iconoir.ShareIos));
      await tester.pump();
      expect(shareTapCount, 1);

      final postWithComments = _makeMessage(
        id: 'p5',
        content: 'Popular discussion post',
        viewsCount: 4200,
        commentsCount: 5,
        canComment: true,
        recentRepliers: const [
          RecentReplier(userId: 'u1', displayName: 'Alice'),
          RecentReplier(userId: 'u2', displayName: 'Bob'),
        ],
      );

      await tester.pumpWidget(
        _wrapTestApp(
          ChannelPostCard(
            message: postWithComments,
            linkedChatId: 'disc-1',
            formatTime: (_) => '10:05',
            onCommentsTap: () => commentsTapCount++,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('5 комментариев'), findsOneWidget);
      expect(find.byType(TelegramAvatarStack), findsOneWidget);
      expect(find.byType(iconoir.NavArrowRight), findsOneWidget);
    });

    testWidgets('stays left-aligned and clamped to 520px inside 1200px wide TileViewportScope',
        (tester) async {
      const wideSize = Size(1200, 800);
      await _setSurface(tester, wideSize);

      final post = _makeMessage(
        id: 'p6',
        content: 'Desktop wide viewport alignment verification text',
        viewsCount: 810,
      );

      await tester.pumpWidget(
        _wrapTestApp(
          TileViewportScope(
            tileId: 'channel-tile',
            isChatTile: true,
            child: Align(
              alignment: Alignment.topLeft,
              child: ChannelPostCard(
                message: post,
                formatTime: (_) => '11:20',
              ),
            ),
          ),
          surfaceSize: wideSize,
        ),
      );
      await tester.pump();

      final bubbleBox = find.byWidgetPredicate(
        (w) => w is MetaData && w.metaData == 'message_bubble_box',
      );
      expect(bubbleBox, findsOneWidget);
      // DecoratedBox inside Container(margin: left 12, right 4) is the visual 520px card.
      final cardSurface = find
          .descendant(of: bubbleBox, matching: find.byType(DecoratedBox))
          .first;
      final cardRect = tester.getRect(cardSurface);
      expect(cardRect.width, lessThanOrEqualTo(520.0));
      expect(cardRect.left, lessThan(40.0));
      expect(cardRect.right, lessThan(650.0));
    });

    testWidgets('renders edge-to-edge MediaAlbumWidget cleanly inside album post',
        (tester) async {
      final p1 = _makeMessage(
        id: 'alb-1',
        messageType: 'image',
        content: 'Album post caption',
        mediaPayload: const {
          'thumb_base64': _k1x1PngBase64,
          'width': 800,
          'height': 600,
        },
        viewsCount: 300,
      );
      final p2 = _makeMessage(
        id: 'alb-2',
        messageType: 'image',
        content: '',
        mediaPayload: const {
          'thumb_base64': _k1x1PngBase64,
          'width': 800,
          'height': 600,
        },
        viewsCount: 300,
      );
      final album = MediaAlbum(
        groupedId: 'grp-alb-1',
        items: [
          MediaAlbumItem(message: p1, index: 0, totalCount: 2),
          MediaAlbumItem(message: p2, index: 1, totalCount: 2),
        ],
        primaryMessage: p1,
        caption: 'Album post caption',
      );

      await tester.pumpWidget(
        _wrapTestApp(
          ChannelPostCard(
            album: album,
            channelName: 'Photo Feed',
            formatTime: (_) => '14:10',
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(MediaAlbumWidget), findsOneWidget);
      expect(find.text('Album post caption'), findsOneWidget);
      expect(find.text('300'), findsOneWidget);
    });
  });

  group('ChannelBottomCapsuleBar', () {
    testWidgets('guest state renders Подписаться across disabled, lite, full glass modes',
        (tester) async {
      for (final mode in const [
        GlassMode.disabled,
        GlassMode.lite,
        GlassMode.full,
      ]) {
        await tester.pumpWidget(
          _wrapTestApp(
            const ChannelBottomCapsuleBar(
              channelId: 'ch-1',
              channelName: 'Tech Channel',
              myRole: 'guest',
              isMember: false,
            ),
            glassProvider: _OverrideGlassProvider(mode),
            brightness:
                mode == GlassMode.full ? Brightness.dark : Brightness.light,
          ),
        );
        await tester.pump();

        expect(find.text('Подписаться'), findsOneWidget);
        expect(find.byType(iconoir.Megaphone), findsOneWidget);
      }
    });

    testWidgets('subscriber state renders mute toggle and optional discussion button',
        (tester) async {
      var discussionOpened = false;

      await tester.pumpWidget(
        _wrapTestApp(
          ChannelBottomCapsuleBar(
            channelId: 'ch-2',
            myRole: 'subscriber',
            isMember: true,
            canPostInChannel: false,
            isMuted: false,
            linkedChatId: 'disc-group-1',
            onOpenDiscussion: () => discussionOpened = true,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Выключить звук'), findsOneWidget);
      expect(find.byType(iconoir.BellOff), findsOneWidget);
      expect(find.byType(iconoir.ChatLines), findsOneWidget);

      await tester.tap(find.byType(iconoir.ChatLines));
      await tester.pump();
      expect(discussionOpened, isTrue);

      await tester.pumpWidget(
        _wrapTestApp(
          const ChannelBottomCapsuleBar(
            channelId: 'ch-2',
            myRole: 'subscriber',
            isMember: true,
            canPostInChannel: false,
            isMuted: true,
            linkedChatId: null,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Включить звук'), findsOneWidget);
      expect(find.byType(iconoir.Bell), findsOneWidget);
      expect(find.byType(iconoir.ChatLines), findsNothing);
    });

    testWidgets('admin state renders ChatInputBar and toggles silent broadcast bell',
        (tester) async {
      bool? toggledSilentValue;

      await tester.pumpWidget(
        _wrapTestApp(
          ChannelBottomCapsuleBar(
            channelId: 'ch-3',
            myRole: 'admin',
            isMember: true,
            canPostInChannel: true,
            isSilentBroadcast: false,
            onToggleSilentBroadcast: (v) => toggledSilentValue = v,
          ),
          brightness: Brightness.dark,
        ),
      );
      await tester.pump();

      expect(find.byType(ChatInputBar), findsOneWidget);
      expect(find.byKey(const ValueKey('silent_bell_on')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('silent_bell_on')));
      await tester.pump(const Duration(milliseconds: 250));

      expect(toggledSilentValue, isTrue);
      expect(find.byKey(const ValueKey('silent_bell_off')), findsOneWidget);

      // Clean up GlassToastService timer before test disposal.
      GlassToastService().hide();
      await tester.pump();
    });
  });

  group('SenderHeaderRow & GroupMessageAvatarRow', () {
    testWidgets('renders flush-right adminTitle ahead of role fallback', (tester) async {
      await tester.pumpWidget(
        _wrapTestApp(
          const SizedBox(
            width: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SenderHeaderRow(
                  senderName: 'Alice',
                  nameColor: Colors.blue,
                  adminTitle: 'Основатель',
                  role: 'owner',
                ),
                SenderHeaderRow(
                  senderName: 'Bob',
                  nameColor: Colors.green,
                  role: 'owner',
                ),
                SenderHeaderRow(
                  senderName: 'Charlie',
                  nameColor: Colors.orange,
                  role: 'admin',
                ),
                SenderHeaderRow(
                  senderName: 'Dan',
                  nameColor: Colors.purple,
                  role: 'member',
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Основатель'), findsOneWidget);
      expect(find.text('владелец'), findsOneWidget);
      expect(find.text('админ'), findsOneWidget);

      final aliceRect = tester.getRect(find.text('Alice'));
      final titleRect = tester.getRect(find.text('Основатель'));
      expect(titleRect.left, greaterThan(aliceRect.right));
    });

    testWidgets('GroupMessageAvatarRow routes anonymous admin tap to onTapGroupAvatar',
        (tester) async {
      var groupTapCount = 0;
      var userTapCount = 0;

      await tester.pumpWidget(
        _wrapTestApp(
          GroupMessageAvatarRow(
            senderId: 'user-99',
            senderName: 'Secret Admin',
            isFromAnonymousAdmin: true,
            groupName: 'Design Group',
            showAvatar: true,
            onTapGroupAvatar: () => groupTapCount++,
            onAvatarTap: () => userTapCount++,
            child: const SizedBox(
              height: 44,
              child: Text('Anonymous post'),
            ),
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.byType(AvatarWithStatus));
      await tester.pump();

      expect(groupTapCount, 1);
      expect(userTapCount, 0);
    });
  });

  group('TelegramServiceMessageWidget & TelegramChatCreatedIntroCard', () {
    testWidgets('renders service events and fires pin/photo/user callbacks', (tester) async {
      String? pinnedMsgId;
      String? tappedUserId;
      String? tappedPhotoUrl;

      final createdMsg = _makeMessage(
        id: 's1',
        messageType: 'system',
        mediaPayload: const {'system_action': 'chat_created', 'title': 'Beta Guild'},
      );
      final photoMsg = _makeMessage(
        id: 's2',
        messageType: 'system',
        mediaPayload: {
          'system_action': 'photo_updated',
          'actor_name': 'Alice',
          'photo_url': 'data:image/png;base64,$_k1x1PngBase64',
        },
      );
      final titleMsg = _makeMessage(
        id: 's3',
        messageType: 'system',
        mediaPayload: const {
          'system_action': 'title_updated',
          'actor_name': 'Bob',
          'title': 'New Title',
        },
      );
      final pinnedMsg = _makeMessage(
        id: 's4',
        messageType: 'system',
        mediaPayload: const {
          'system_action': 'message_pinned',
          'actor_name': 'Alice',
          'pinned_message_id': 'm42',
          'pinned_preview': 'Rules v2',
        },
      );
      final memberMsg = _makeMessage(
        id: 's5',
        senderId: 'u1',
        senderName: 'Alice',
        messageType: 'system',
        mediaPayload: const {
          'system_action': 'member_added',
          'actor_id': 'u1',
          'actor_name': 'Alice',
          'target_id': 'u2',
          'target_name': 'Bob',
        },
      );
      final voiceEndMsg = _makeMessage(
        id: 's6',
        messageType: 'system',
        mediaPayload: const {
          'system_action': 'voice_chat_ended',
          'actor_name': 'Alice',
          'duration_seconds': 754,
        },
      );

      await tester.pumpWidget(
        _wrapTestApp(
          SingleChildScrollView(
            child: Column(
              children: [
                TelegramServiceMessageWidget(message: createdMsg),
                TelegramServiceMessageWidget(
                  message: photoMsg,
                  onTapPhoto: (url) => tappedPhotoUrl = url,
                ),
                TelegramServiceMessageWidget(message: titleMsg),
                TelegramServiceMessageWidget(
                  message: pinnedMsg,
                  onTapPinnedMessage: (id) => pinnedMsgId = id,
                ),
                TelegramServiceMessageWidget(
                  message: memberMsg,
                  onTapUser: (id) => tappedUserId = id,
                ),
                TelegramServiceMessageWidget(message: voiceEndMsg),
              ],
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Группа «Beta Guild» создана'), findsOneWidget);
      expect(find.text('Alice обновил(а) фото группы'), findsOneWidget);
      expect(find.byType(iconoir.Camera), findsOneWidget);
      expect(find.text('Bob изменил(а) название на «New Title»'), findsOneWidget);
      expect(find.text('Alice закрепил(а) сообщение «Rules v2»'), findsOneWidget);
      expect(find.byType(iconoir.Pin), findsOneWidget);
      expect(find.text('Alice завершил(а) голосовой чат (12м 34с)'), findsOneWidget);
      expect(find.byType(iconoir.SoundHigh), findsOneWidget);

      await tester.tap(find.text('Alice закрепил(а) сообщение «Rules v2»'));
      await tester.pump();
      expect(pinnedMsgId, 'm42');

      await tester.tap(find.text('Bob'));
      await tester.pump();
      expect(tappedUserId, 'u2');

      await tester.tap(find.byType(Image).first);
      await tester.pump();
      expect(tappedPhotoUrl, startsWith('data:image/png;base64,'));
    });

    testWidgets('TelegramChatCreatedIntroCard renders channel and group intro cards',
        (tester) async {
      await tester.pumpWidget(
        _wrapTestApp(
          const SingleChildScrollView(
            child: Column(
              children: [
                TelegramChatCreatedIntroCard(
                  isChannel: true,
                  title: 'News Hub',
                  description: 'Daily updates',
                ),
                TelegramChatCreatedIntroCard(
                  isChannel: false,
                  title: 'Dev Crew',
                ),
              ],
            ),
          ),
          brightness: Brightness.dark,
        ),
      );
      await tester.pump();

      expect(find.text('Вы создали канал'), findsOneWidget);
      expect(find.byType(iconoir.Megaphone), findsAtLeastNWidgets(1));
      expect(find.text('Вы создали группу'), findsOneWidget);
      expect(find.byType(iconoir.Group), findsAtLeastNWidgets(1));
    });
  });

  group('ChatListTileItem group/channel tiles & theme contrast', () {
    Future<void> noopSwipe(ChatSwipeAction _) async {}

    testWidgets('group tile renders iconoir.Group, sender prefix, outgoing status, and call badge',
        (tester) async {
      final outgoingGroup = _makeChat(
        id: 'g1',
        chatType: 'group',
        name: 'Engineering',
        lastMessage: 'Shipped PR',
        lastMessageSenderId: 'me',
        lastMessageSenderName: 'Me',
        hasActiveCall: true,
      );

      await tester.pumpWidget(
        _wrapTestApp(
          ChatListTileItem(
            chat: outgoingGroup,
            isSelectMode: false,
            isSelected: false,
            isMuted: false,
            currentUserId: 'me',
            onTap: () {},
            onLongPress: () {},
            onSwipeAction: noopSwipe,
          ),
        ),
      );
      // Do not pumpAndSettle because active call badge repeats its pulse animation.
      await tester.pump();

      expect(find.text('Engineering'), findsOneWidget);
      expect(find.byType(iconoir.Group), findsAtLeastNWidgets(1));
      expect(find.text('Вы: Shipped PR', findRichText: true), findsOneWidget);
      expect(find.byType(MessageStatusWidget), findsOneWidget);
      expect(find.byType(iconoir.SoundHigh), findsOneWidget);

      final incomingGroup = _makeChat(
        id: 'g2',
        chatType: 'group',
        name: 'Design',
        lastMessage: 'Reviewing Figma',
        lastMessageSenderId: 'alice',
        lastMessageSenderName: 'Alice',
        hasActiveCall: false,
      );

      await tester.pumpWidget(
        _wrapTestApp(
          ChatListTileItem(
            chat: incomingGroup,
            isSelectMode: false,
            isSelected: false,
            isMuted: false,
            currentUserId: 'me',
            onTap: () {},
            onLongPress: () {},
            onSwipeAction: noopSwipe,
          ),
          brightness: Brightness.dark,
        ),
      );
      await tester.pump();

      expect(find.text('Alice: Reviewing Figma', findRichText: true), findsOneWidget);
      expect(find.byType(MessageStatusWidget), findsNothing);
    });

    testWidgets('channel tile renders iconoir.Megaphone without sender prefix or outgoing checkmarks',
        (tester) async {
      final channelChat = _makeChat(
        id: 'c1',
        chatType: 'channel',
        name: 'Announcements',
        lastMessage: 'Release 2.0 is live',
        lastMessageSenderId: 'me',
        lastMessageSenderName: 'Founder',
      );

      await tester.pumpWidget(
        _wrapTestApp(
          ChatListTileItem(
            chat: channelChat,
            isSelectMode: false,
            isSelected: false,
            isMuted: true,
            currentUserId: 'me',
            onTap: () {},
            onLongPress: () {},
            onSwipeAction: noopSwipe,
          ),
        ),
      );
      await tester.pump();

      expect(find.text('Announcements'), findsOneWidget);
      expect(find.byType(iconoir.Megaphone), findsAtLeastNWidgets(1));
      expect(find.text('Release 2.0 is live', findRichText: true), findsOneWidget);
      expect(
        find.textContaining('Вы: ', findRichText: true),
        findsNothing,
      );
      expect(
        find.textContaining('Founder: ', findRichText: true),
        findsNothing,
      );
      expect(find.byType(MessageStatusWidget), findsNothing);
      expect(find.byType(iconoir.BellOff), findsOneWidget);
    });
  });
}
