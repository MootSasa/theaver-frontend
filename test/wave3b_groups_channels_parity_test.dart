import 'package:drift/drift.dart' show Migrator;
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/database/app_database.dart';
import 'package:theaver/services/groups_channels_parity_service.dart';
import 'package:theaver/services/screen_protection_service.dart';
import 'package:theaver/services/websocket_service.dart';
import 'package:theaver/widgets/chat/groups_channels_parity_widgets.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Wave 3B Models & Permissions', () {
    test('GroupDefaultPermissions & MemberRestrictions 15 keys and legacy fallback', () {
      const defaults = GroupDefaultPermissions(
        canSendMessages: true,
        canSendPhotos: true,
        canSendVideos: false,
        canSendMusic: true,
        canSendFiles: false,
        canSendVoiceNotes: true,
        canSendVideoNotes: false,
        canSendStickersGifs: true,
        canSendPolls: false,
        canAddWebPagePreviews: true,
        canInviteUsers: false,
        canPinMessages: true,
        canChangeInfo: false,
        canManageTopics: true,
      );
      final roundTrip = GroupDefaultPermissions.fromJson(defaults.toJson());
      expect(roundTrip.canSendMessages, isTrue);
      expect(roundTrip.canSendPhotos, isTrue);
      expect(roundTrip.canSendVideos, isFalse);
      expect(roundTrip.canSendMusic, isTrue);
      expect(roundTrip.canSendFiles, isFalse);
      expect(roundTrip.canSendVoiceNotes, isTrue);
      expect(roundTrip.canSendVideoNotes, isFalse);
      expect(roundTrip.canSendStickersGifs, isTrue);
      expect(roundTrip.canSendPolls, isFalse);
      expect(roundTrip.canAddWebPagePreviews, isTrue);
      expect(roundTrip.canInviteUsers, isFalse);
      expect(roundTrip.canPinMessages, isTrue);
      expect(roundTrip.canChangeInfo, isFalse);
      expect(roundTrip.canManageTopics, isTrue);

      // Legacy fallback: can_send_media: false collapses granular media flags
      final legacyBlocked = GroupDefaultPermissions.fromJson(const {
        'can_send_messages': true,
        'can_send_media': false,
      });
      expect(legacyBlocked.canSendPhotos, isFalse);
      expect(legacyBlocked.canSendVideos, isFalse);
      expect(legacyBlocked.canSendMusic, isFalse);
      expect(legacyBlocked.canSendFiles, isFalse);
      expect(legacyBlocked.canSendVoiceNotes, isFalse);
      expect(legacyBlocked.canSendVideoNotes, isFalse);

      // Intersection with MemberRestrictions
      final intersected = defaults.intersectWith(
        const MemberRestrictions(
          canSendMessages: true,
          canSendMedia: false,
          canSendPhotos: false,
          canSendMusic: false,
          canSendVoiceNotes: false,
          canSendStickersGifs: false,
          canAddWebPagePreviews: false,
          canPinMessages: false,
          canManageTopics: false,
        ),
      );
      expect(intersected.canSendPhotos, isFalse);
      expect(intersected.canSendMusic, isFalse);
      expect(intersected.canSendVoiceNotes, isFalse);
      expect(intersected.canSendStickersGifs, isFalse);
      expect(intersected.canAddWebPagePreviews, isFalse);
      expect(intersected.canPinMessages, isFalse);
      expect(intersected.canManageTopics, isFalse);
    });

    test('AdminRights.canManageTopics, ChatDetails.canManageTopicsEffective & ReactionSettings.maxReactionsPerPost', () {
      final admin = AdminRights.fromJson(const {
        'can_manage_chat': true,
        'can_manage_topics': true,
      });
      expect(admin.canManageTopics, isTrue);
      expect(admin.toJson()['can_manage_topics'], isTrue);

      final detailsAdmin = ChatDetails.fromJson(const {
        'id': '10',
        'name': 'Forum Group',
        'chat_type': 'group',
        'is_forum': true,
        'is_member': true,
        'my_role': 'admin',
        'my_admin_permissions': {'can_manage_topics': true},
        'default_permissions': {'can_manage_topics': false},
      });
      expect(detailsAdmin.isForum, isTrue);
      expect(detailsAdmin.canManageTopicsEffective, isTrue);

      final detailsMember = ChatDetails.fromJson(const {
        'id': '10',
        'name': 'Forum Group',
        'chat_type': 'group',
        'is_forum': true,
        'is_member': true,
        'my_role': 'member',
        'default_permissions': {'can_manage_topics': false},
      });
      expect(detailsMember.canManageTopicsEffective, isFalse);

      final reactions = ReactionSettings.fromJson(const {
        'mode': 'selected',
        'allowed_reactions': ['👍', '🔥'],
        'max_reactions_per_post': 4,
      });
      expect(reactions.maxReactionsPerPost, 4);
      expect(reactions.toJson()['max_reactions_per_post'], 4);
    });

    test('Chat, Message, PostCommentsResult & WebSocketEventType Wave 3B parsing', () {
      final chat = Chat.fromJson(const {
        'id': '55',
        'chat_type': 'group',
        'name': 'Supergroup',
        'is_forum': true,
        'participants_hidden': true,
        'has_aggressive_anti_spam_enabled': true,
        'max_reactions_per_post': 5,
        'unread_mentions_count': 3,
        'unread_reactions_count': 2,
        'my_send_as_chat_id': '99',
        'updated_at': '2026-11-19T12:00:00Z',
      });
      expect(chat.isForum, isTrue);
      expect(chat.participantsHidden, isTrue);
      expect(chat.hasAggressiveAntiSpamEnabled, isTrue);
      expect(chat.maxReactionsPerPost, 5);
      expect(chat.unreadMentionsCount, 3);
      expect(chat.unreadReactionsCount, 2);
      expect(chat.mySendAsChatId, '99');

      final msg = Message.fromJson(const {
        'id': '701',
        'chat_id': '55',
        'sender_id': '12',
        'sender_name': 'Tester',
        'content': 'Channel-signed post',
        'message_type': 'text',
        'created_at': '2026-11-19T12:05:00Z',
        'topic_id': 42,
        'forwards_count': 17,
        'sender_chat_id': '99',
        'sender_chat_name': 'News Channel',
        'sender_chat_avatar_url': '/avatars/news.png',
      });
      expect(msg.topicId, 42);
      expect(msg.forwardsCount, 17);
      expect(msg.senderChatId, '99');
      expect(msg.senderChatName, 'News Channel');
      expect(msg.senderChatAvatarUrl, '/avatars/news.png');

      final copied = msg.copyWith(forwardsCount: 25, topicId: 43);
      expect(copied.forwardsCount, 25);
      expect(copied.topicId, 43);

      const commentsRes = PostCommentsResult(
        linkedChatId: '88',
        canComment: false,
        hasMore: true,
      );
      expect(commentsRes.canComment, isFalse);
      expect(commentsRes.linkedChatId, '88');

      expect(
        WebSocketEvent.fromJson(const {'type': 'forum_topic_updated'}).type,
        WebSocketEventType.forumTopicUpdated,
      );
      expect(
        WebSocketEvent.fromJson(const {'type': 'unread_badges_updated'}).type,
        WebSocketEventType.unreadBadgesUpdated,
      );
    });

    test('Wave 3B parity DTOs deserialize cleanly', () {
      final topic = ForumTopic.fromJson(const {
        'id': 1,
        'chat_id': '55',
        'title': 'General',
        'icon_color': 0xFF6FB9F0,
        'icon_emoji': '💬',
        'is_general': true,
        'is_closed': false,
        'is_pinned': true,
        'unread_count': 4,
      });
      expect(topic.id, 1);
      expect(topic.title, 'General');
      expect(topic.isGeneral, isTrue);
      expect(topic.isPinned, isTrue);
      expect(topic.unreadCount, 4);

      final logEvent = AdminLogEvent.fromJson(const {
        'id': 9,
        'chat_id': '55',
        'action': 'pin_message',
        'actor_id': '2',
        'actor_name': 'Mod',
        'target_message_id': '700',
        'new_value': {'pinned': true},
        'created_at': '2026-11-19T12:10:00Z',
      });
      expect(logEvent.action, 'pin_message');
      expect(logEvent.newValue?['pinned'], isTrue);

      final importer = InviteLinkImporter.fromJson(const {
        'user_id': '14',
        'username': 'alice',
        'display_name': 'Alice',
        'via_join_request': true,
      });
      expect(importer.userId, '14');
      expect(importer.viaJoinRequest, isTrue);

      final peer = SendAsPeer.fromJson(const {
        'peer_type': 'channel',
        'id': '99',
        'chat_id': '99',
        'name': 'Official Blog',
        'username': 'official',
        'is_verified': true,
        'is_selected': true,
      });
      expect(peer.isChannel, isTrue);
      expect(peer.isVerified, isTrue);
      expect(peer.isSelected, isTrue);

      final chStats = ChannelStats.fromJson(const {
        'stats': {
          'subscribers_count': 1200,
          'notifications_enabled_percent': 64.5,
          'joined_7d': 80,
          'left_7d': 12,
          'total_views': 5400,
          'avg_views_per_post': 270.0,
          'daily_growth': [
            {'date': '2026-11-18', 'joined': 20, 'left': 2, 'net': 18},
          ],
          'top_posts': [
            {'message_id': '701', 'content': 'Top', 'views_count': 900},
          ],
        },
      });
      expect(chStats.subscribersCount, 1200);
      expect(chStats.dailyGrowth.single.joined, 20);
      expect(chStats.topPosts.single.viewsCount, 900);

      final postStats = PostStats.fromJson(const {
        'chat_id': '99',
        'message_id': '701',
        'views_count': 500,
        'unique_viewers': 410,
        'forwards_count': 22,
        'comments_count': 18,
        'reactions_total': 45,
        'engagement_rate': 17.5,
        'reactions_breakdown': [
          {'emoji': '🔥', 'count': 30},
        ],
      });
      expect(postStats.engagementRate, 17.5);
      expect(postStats.reactionsBreakdown.single.emoji, '🔥');

      final similar = SimilarChannelItem.fromJson(const {
        'id': '123',
        'name': 'Tech Digest',
        'username': 'techdigest',
        'subscriber_count': 3400,
        'overlap_count': 42,
      });
      expect(similar.id, '123');
      expect(similar.overlapCount, 42);

      final addRes = AddMembersResult.fromJson(const {
        'success': true,
        'added_user_ids': ['21'],
        'skipped_privacy_user_ids': ['22'],
      });
      expect(addRes.addedUserIds, ['21']);
      expect(addRes.skippedPrivacyUserIds, ['22']);

      final badgeRes = UnreadBadgeItemsResult.fromJson(
        const {
          'count': 2,
          'message_ids': ['801', '802'],
          'mentions': [
            {'id': '801'},
            {'id': '802'},
          ],
        },
        itemsKey: 'mentions',
      );
      expect(badgeRes.count, 2);
      expect(badgeRes.messageIds, ['801', '802']);
    });
  });

  group('Wave 3B Drift v16 & Migration', () {
    test('Drift v16 supports topicId filtering, forwardsCount, unread badges & updateChatSettings', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      expect(db.schemaVersion, 16);

      final forumChat = Chat(
        id: 'forum_1',
        chatType: 'group',
        name: 'Flutter Devs',
        updatedAt: '2026-11-19T12:00:00Z',
        isForum: true,
        participantsHidden: false,
        hasAggressiveAntiSpamEnabled: false,
        maxReactionsPerPost: 11,
      );
      await db.saveChat(forumChat.toCompanion());

      await db.updateChatSettings(
        'forum_1',
        participantsHidden: true,
        hasAggressiveAntiSpamEnabled: true,
        maxReactionsPerPost: 6,
      );
      await db.updateChatUnreadBadges(
        'forum_1',
        unreadMentionsCount: 4,
        unreadReactionsCount: 7,
      );

      final savedChatRow = await db.getChat('forum_1');
      expect(savedChatRow, isNotNull);
      final restoredChat = Chat.fromDbChat(savedChatRow!);
      expect(restoredChat.isForum, isTrue);
      expect(restoredChat.participantsHidden, isTrue);
      expect(restoredChat.hasAggressiveAntiSpamEnabled, isTrue);
      expect(restoredChat.maxReactionsPerPost, 6);
      expect(restoredChat.unreadMentionsCount, 4);
      expect(restoredChat.unreadReactionsCount, 7);

      final mGeneral = Message(
        id: 'm_gen',
        localId: 'loc_gen',
        chatId: 'forum_1',
        senderId: 'u1',
        senderName: 'Alice',
        content: 'General topic message',
        messageType: 'text',
        isEdited: false,
        createdAt: '2026-11-19T12:01:00Z',
        topicId: 1,
        forwardsCount: 2,
        senderChatId: 'chan_9',
        senderChatName: 'News',
        senderChatAvatarUrl: '/news.png',
      );
      final mTopic5 = Message(
        id: 'm_t5',
        localId: 'loc_t5',
        chatId: 'forum_1',
        senderId: 'u2',
        senderName: 'Bob',
        content: 'Topic 5 message',
        messageType: 'text',
        isEdited: false,
        createdAt: '2026-11-19T12:02:00Z',
        topicId: 5,
        forwardsCount: 0,
      );
      await db.saveMessages([mGeneral.toCompanion(), mTopic5.toCompanion()]);

      final topic5Only = await db.getMessages('forum_1', topicId: 5);
      expect(topic5Only.length, 1);
      expect(topic5Only.single.serverId, 'm_t5');

      await db.updateMessagesForwards({'m_gen': 19});
      final updatedGenRow = await db.getMessageByServerId('m_gen');
      final updatedGen = Message.fromDbMessage(updatedGenRow!);
      expect(updatedGen.forwardsCount, 19);
      expect(updatedGen.senderChatId, 'chan_9');
      expect(updatedGen.senderChatName, 'News');
      expect(updatedGen.senderChatAvatarUrl, '/news.png');
    });

    test('Migrating v15 -> v16 preserves chats/messages and adds Wave 3B defaults', () async {
      final db = AppDatabase.forTesting(
        NativeDatabase.memory(
          setup: (rawDb) {
            rawDb.execute('''
              CREATE TABLE chats (
                chat_id TEXT NOT NULL PRIMARY KEY,
                chat_type TEXT NOT NULL,
                name TEXT NOT NULL,
                avatar_url TEXT,
                last_message TEXT,
                last_message_time TEXT,
                updated_at TEXT NOT NULL,
                unread_count INTEGER NOT NULL DEFAULT 0,
                is_online INTEGER NOT NULL DEFAULT 0,
                last_seen TEXT,
                is_pinned INTEGER NOT NULL DEFAULT 0,
                last_message_type TEXT,
                last_message_is_round INTEGER NOT NULL DEFAULT 0,
                last_message_file_url TEXT,
                last_message_grouped_id TEXT,
                other_user_id TEXT,
                last_read_inbox_message_id INTEGER NOT NULL DEFAULT 0,
                last_read_outbox_message_id INTEGER NOT NULL DEFAULT 0,
                pinned_message_id INTEGER,
                username TEXT,
                is_public INTEGER NOT NULL DEFAULT 0,
                is_bot INTEGER NOT NULL DEFAULT 0,
                is_verified INTEGER NOT NULL DEFAULT 0,
                is_archived INTEGER NOT NULL DEFAULT 0,
                peer_customization_json TEXT,
                show_author_profiles INTEGER NOT NULL DEFAULT 0,
                sign_messages INTEGER NOT NULL DEFAULT 0,
                linked_chat_id TEXT,
                my_role TEXT,
                last_message_sender_id TEXT,
                last_message_sender_name TEXT,
                has_active_call INTEGER NOT NULL DEFAULT 0,
                chat_permissions_json TEXT,
                reaction_settings_json TEXT,
                has_protected_content INTEGER NOT NULL DEFAULT 0,
                pinned_message_ids_json TEXT,
                message_auto_delete_time INTEGER NOT NULL DEFAULT 0,
                appearance_json TEXT
              );
              CREATE TABLE messages (
                local_id TEXT NOT NULL PRIMARY KEY,
                server_id TEXT,
                chat_id TEXT NOT NULL,
                sender_id TEXT NOT NULL,
                content TEXT NOT NULL,
                message_type TEXT NOT NULL DEFAULT 'text',
                file_url TEXT,
                file_name TEXT,
                reply_to_message_id TEXT,
                is_quote INTEGER NOT NULL DEFAULT 0,
                quote_text TEXT,
                quote_offset INTEGER NOT NULL DEFAULT 0,
                quote_length INTEGER NOT NULL DEFAULT 0,
                reply_to_sender_id TEXT,
                reply_to_sender_name TEXT,
                reply_to_content TEXT,
                reply_to_message_type TEXT NOT NULL DEFAULT 'text',
                is_read INTEGER NOT NULL DEFAULT 0,
                is_edited INTEGER NOT NULL DEFAULT 0,
                send_status INTEGER NOT NULL DEFAULT 1,
                sender_name TEXT,
                sender_avatar_url TEXT,
                created_at TEXT NOT NULL,
                is_forward INTEGER NOT NULL DEFAULT 0,
                forward_from_id TEXT,
                forward_from_name TEXT,
                forward_from_avatar_url TEXT,
                sender_customization_json TEXT,
                grouped_id TEXT,
                entities TEXT,
                reactions TEXT,
                link_preview_options TEXT,
                invert_media INTEGER NOT NULL DEFAULT 0,
                is_round INTEGER NOT NULL DEFAULT 0,
                media_payload TEXT,
                views_count INTEGER NOT NULL DEFAULT 0,
                author_signature TEXT,
                post_author_id TEXT,
                sender_role TEXT,
                sender_admin_title TEXT,
                is_from_anonymous_admin INTEGER NOT NULL DEFAULT 0,
                is_silent INTEGER NOT NULL DEFAULT 0,
                comments_count INTEGER NOT NULL DEFAULT 0,
                recent_repliers_json TEXT,
                thread_root_message_id TEXT,
                has_media_spoiler INTEGER NOT NULL DEFAULT 0,
                expires_at TEXT,
                ttl_seconds INTEGER NOT NULL DEFAULT 0,
                is_view_once INTEGER NOT NULL DEFAULT 0,
                viewed_at TEXT,
                is_burned INTEGER NOT NULL DEFAULT 0,
                reply_to_chat_id TEXT,
                reply_to_chat_name TEXT,
                reply_to_chat_type TEXT,
                effect_id TEXT,
                saved_tags_json TEXT
              );
              INSERT INTO chats (chat_id, chat_type, name, updated_at)
              VALUES ('c15', 'group', 'Old v15 Group', '2026-11-19T00:00:00Z');
              INSERT INTO messages (local_id, server_id, chat_id, sender_id, content, created_at)
              VALUES ('l15', 's15', 'c15', 'u1', 'Before v16', '2026-11-19T00:01:00Z');
              PRAGMA user_version = 15;
            ''');
          },
        ),
      );
      addTearDown(db.close);

      await db.ensureInitialized();
      final vRow = await db.customSelect('PRAGMA user_version').getSingle();
      expect(vRow.data['user_version'], Migrator(db).database.schemaVersion);
      expect(vRow.data['user_version'], 16);

      final chat = await db.getChat('c15');
      expect(chat, isNotNull);
      expect(chat!.isForum, isFalse);
      expect(chat.maxReactionsPerPost, 11);

      final msg = await db.getMessageByServerId('s15');
      expect(msg, isNotNull);
      expect(msg!.forwardsCount, 0);
      expect(msg.topicId, isNull);
    });
  });

  group('Wave 3B ScreenProtectionService & Widgets', () {
    test('ScreenProtectionService ref-counts acquire/release/sync over MethodChannel', () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final calls = <bool>[];
      const channel = MethodChannel('app.theaver.messenger/screen_security');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'setSecureFlag') {
          final args = Map<String, dynamic>.from(call.arguments as Map);
          calls.add(args['enabled'] == true);
        }
        return true;
      });
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null);
        await ScreenProtectionService.instance.resetForTesting();
        debugDefaultTargetPlatformOverride = null;
      });

      final svc = ScreenProtectionService.instance;
      await svc.resetForTesting();
      calls.clear();

      await svc.acquire('chat_a');
      expect(svc.activeOwnerCount, 1);
      expect(svc.isSecured, isTrue);
      expect(calls, [true]);

      await svc.acquire('chat_b');
      expect(svc.activeOwnerCount, 2);
      expect(calls, [true]); // Already secured, no redundant channel call

      await svc.sync('chat_a', false);
      expect(svc.activeOwnerCount, 1);
      expect(svc.isSecured, isTrue);
      expect(calls, [true]); // Still held by chat_b

      await svc.release('chat_b');
      expect(svc.activeOwnerCount, 0);
      expect(svc.isSecured, isFalse);
      expect(calls, [true, false]);
    });

    testWidgets('UnreadJumpFabsColumn renders @ and heart badges and triggers callbacks', (tester) async {
      int mentionsTaps = 0;
      int mentionsLongPresses = 0;
      int reactionsTaps = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: UnreadJumpFabsColumn(
              unreadMentionsCount: 5,
              unreadReactionsCount: 2,
              onMentionsTap: () => mentionsTaps++,
              onMentionsLongPress: () => mentionsLongPresses++,
              onReactionsTap: () => reactionsTaps++,
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('unread_mentions_fab')), findsOneWidget);
      expect(find.byKey(const ValueKey('unread_reactions_fab')), findsOneWidget);
      expect(find.text('5'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('unread_mentions_fab')));
      await tester.pump();
      expect(mentionsTaps, 1);

      await tester.longPress(find.byKey(const ValueKey('unread_mentions_fab')));
      await tester.pump();
      expect(mentionsLongPresses, 1);

      await tester.tap(find.byKey(const ValueKey('unread_reactions_fab')));
      await tester.pump();
      expect(reactionsTaps, 1);
    });

    testWidgets('ChannelGrowthChart renders empty and populated states without errors', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChannelGrowthChart(points: []),
          ),
        ),
      );
      expect(find.text('Недостаточно данных за период'), findsOneWidget);

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: ChannelGrowthChart(
              points: [
                ChannelDailyGrowthPoint(date: '2026-11-17', joined: 12, left: 2, net: 10),
                ChannelDailyGrowthPoint(date: '2026-11-18', joined: 25, left: 4, net: 21),
                ChannelDailyGrowthPoint(date: '2026-11-19', joined: 18, left: 3, net: 15),
              ],
            ),
          ),
        ),
      );
      expect(find.text('Присоединились'), findsOneWidget);
      expect(find.text('Покинули'), findsOneWidget);
    });

    testWidgets('SendAsPeerSelectorPill hides for <=1 peer and opens when >1 peers', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: SendAsPeerSelectorPill(
              peers: [SendAsPeer(peerType: 'user', id: '1', name: 'Me')],
            ),
          ),
        ),
      );
      expect(find.byType(Tooltip), findsNothing);

      int tapped = 0;
      const channelPeer = SendAsPeer(
        peerType: 'channel',
        id: '99',
        chatId: '99',
        name: 'My Blog',
        isSelected: true,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SendAsPeerSelectorPill(
              peers: const [
                SendAsPeer(peerType: 'user', id: '1', name: 'Me'),
                channelPeer,
              ],
              selectedPeer: channelPeer,
              onTap: () => tapped++,
            ),
          ),
        ),
      );
      expect(find.byType(Tooltip), findsOneWidget);
      await tester.tap(find.byType(SendAsPeerSelectorPill));
      await tester.pump();
      expect(tapped, 1);
    });
  });
}
