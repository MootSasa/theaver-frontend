import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:theaver/services/chat_service.dart';
import 'package:theaver/services/database/app_database.dart';
import 'package:theaver/services/websocket_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Drift v13 schema, migration, and DAO queries', () {
    test('upgrades v12 database to v13 idempotently and preserves data',
        () async {
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
                show_author_profiles INTEGER NOT NULL DEFAULT 1
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
                media_payload TEXT
              );
              CREATE TABLE sync_states (
                user_id TEXT NOT NULL PRIMARY KEY,
                last_known_usn INTEGER NOT NULL DEFAULT 0,
                last_sync_at TEXT NOT NULL
              );
              CREATE TABLE banking_cards (
                id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
                card_id TEXT NOT NULL,
                card_number TEXT NOT NULL,
                card_holder TEXT NOT NULL,
                expiry_date TEXT NOT NULL,
                card_type TEXT NOT NULL,
                color_index INTEGER NOT NULL DEFAULT 0,
                created_at TEXT NOT NULL
              );
              INSERT INTO chats (chat_id, chat_type, name, updated_at, show_author_profiles)
              VALUES
                ('ch_1', 'channel', 'Theaver News', '2026-11-18T10:00:00Z', 1),
                ('grp_1', 'group', 'Developers', '2026-11-18T10:01:00Z', 1);
              INSERT INTO messages (local_id, server_id, chat_id, sender_id, content, created_at)
              VALUES ('loc_1', '100', 'ch_1', '10', 'Legacy post', '2026-11-18T10:00:00Z');
              PRAGMA user_version = 12;
            ''');
          },
        ),
      );
      addTearDown(() async => await db.close());

      expect(db.schemaVersion, 15);
      await db.ensureInitialized();

      final versionRow = await db.customSelect('PRAGMA user_version').getSingle();
      expect(versionRow.data['user_version'], 15);

      final channel = await db.getChat('ch_1');
      expect(channel, isNotNull);
      expect(channel!.showAuthorProfiles, isFalse);
      expect(channel.signMessages, isFalse);
      expect(channel.hasActiveCall, isFalse);
      expect(channel.linkedChatId, isNull);

      final group = await db.getChat('grp_1');
      expect(group, isNotNull);
      expect(group!.showAuthorProfiles, isTrue);

      final msg = await db.getMessageByServerId('100');
      expect(msg, isNotNull);
      expect(msg!.content, 'Legacy post');
      expect(msg.viewsCount, 0);
      expect(msg.isFromAnonymousAdmin, isFalse);
      expect(msg.isSilent, isFalse);
      expect(msg.commentsCount, 0);

      final idxRow = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'index' AND name = 'idx_messages_thread_root'",
          )
          .getSingleOrNull();
      expect(idxRow, isNotNull);
    });

    test('persists v13 columns across reopen on disk without duplicate errors',
        () async {
      final tempDir = await Directory.systemTemp.createTemp('drift_v13_test_');
      final dbFile = File('${tempDir.path}/theaver_v13.sqlite');
      addTearDown(() async {
        if (await tempDir.exists()) {
          await tempDir.delete(recursive: true);
        }
      });

      final db1 = AppDatabase.forTesting(NativeDatabase(dbFile));
      await db1.saveChat(
        ChatsCompanion.insert(
          chatId: 'ch_disk',
          chatType: 'channel',
          name: 'Disk Channel',
          updatedAt: '2026-11-18T12:00:00Z',
          signMessages: const Value(true),
          linkedChatId: const Value('grp_disk'),
          myRole: const Value('owner'),
          hasActiveCall: const Value(true),
        ),
      );
      await db1.close();

      final db2 = AppDatabase.forTesting(NativeDatabase(dbFile));
      final loaded = await db2.getChat('ch_disk');
      expect(loaded, isNotNull);
      expect(loaded!.showAuthorProfiles, isFalse);
      expect(loaded.signMessages, isTrue);
      expect(loaded.linkedChatId, 'grp_disk');
      expect(loaded.myRole, 'owner');
      expect(loaded.hasActiveCall, isTrue);
      await db2.close();
    });

    test(
        'watchMessagesForChat excludes thread comments while watchThreadComments filters by root',
        () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async => await db.close());

      await db.saveChat(
        ChatsCompanion.insert(
          chatId: 'grp_disc',
          chatType: 'group',
          name: 'Discussion Group',
          updatedAt: '2026-11-18T12:00:00Z',
          linkedChatId: const Value('ch_main'),
        ),
      );

      final mirroredPost = Message(
        id: '200',
        chatId: 'grp_disc',
        senderId: '0',
        content: 'Channel Post #1',
        messageType: 'text',
        isEdited: false,
        createdAt: '2026-11-18T12:00:00Z',
        senderName: 'News Channel',
        channelPostId: '50',
        viewsCount: 120,
        commentsCount: 2,
      );
      final regularGroupMsg = Message(
        id: '201',
        chatId: 'grp_disc',
        senderId: '7',
        content: 'Regular group message',
        messageType: 'text',
        isEdited: false,
        createdAt: '2026-11-18T12:01:00Z',
        senderName: 'Alice',
      );
      final comment1 = Message(
        id: '202',
        chatId: 'grp_disc',
        senderId: '8',
        content: 'First comment',
        messageType: 'text',
        isEdited: false,
        createdAt: '2026-11-18T12:02:00Z',
        senderName: 'Bob',
        threadRootMessageId: '200',
        replyToMessageId: '200',
      );
      final comment2 = Message(
        id: '203',
        chatId: 'grp_disc',
        senderId: '9',
        content: 'Second comment',
        messageType: 'text',
        isEdited: false,
        createdAt: '2026-11-18T12:03:00Z',
        senderName: 'Carol',
        threadRootMessageId: '200',
        replyToMessageId: '202',
      );

      await db.saveMessages([
        mirroredPost.toCompanion(),
        regularGroupMsg.toCompanion(),
        comment1.toCompanion(),
        comment2.toCompanion(),
      ]);

      final mainFeed = await db.watchMessagesForChat('grp_disc').first;
      expect(mainFeed.map((m) => m.serverId).toList(), ['201', '200']);

      final mainGet = await db.getMessages('grp_disc');
      expect(mainGet.map((m) => m.serverId).toList(), ['201', '200']);

      final commentsStream =
          await db.watchThreadComments('grp_disc', '200').first;
      expect(commentsStream.map((m) => m.serverId).toList(), ['202', '203']);

      final lastMain = await db.getLastMessageForChat('grp_disc');
      expect(lastMain?.serverId, '201');
    });
  });

  group('DTO JSON roundtrips', () {
    test('GroupDefaultPermissions roundtrip and intersection with MemberRestrictions',
        () {
      const defaults = GroupDefaultPermissions(
        canSendMessages: true,
        canSendMedia: true,
        canSendStickersGifs: false,
        canSendPolls: true,
        canPinMessages: false,
        canInviteUsers: true,
        canChangeInfo: false,
      );
      final jsonMap = defaults.toJson();
      final decoded = GroupDefaultPermissions.fromJson(jsonMap);
      expect(decoded, defaults);

      const restrictions = MemberRestrictions(
        canSendMessages: true,
        canSendMedia: false,
        canSendStickersGifs: true,
        canSendPolls: false,
        canPinMessages: true,
        canInviteUsers: false,
        canChangeInfo: false,
      );
      final effective = defaults.intersectWith(restrictions);
      expect(effective.canSendMessages, isTrue);
      expect(effective.canSendMedia, isFalse);
      expect(effective.canSendStickersGifs, isFalse);
      expect(effective.canSendPolls, isFalse);
      expect(effective.canPinMessages, isFalse);
      expect(effective.canInviteUsers, isFalse);
      expect(
        MemberRestrictions.fromJson(restrictions.toJson()),
        restrictions,
      );
      expect(const MemberRestrictions.readOnly().isReadOnly, isTrue);
    });

    test('AdminRights JSON roundtrip and aliases', () {
      const rights = AdminRights(
        canChangeInfo: true,
        canPostMessages: true,
        canEditMessages: false,
        canDeleteMessages: true,
        canBanUsers: true,
        canInviteUsers: true,
        canPinMessages: false,
        canManageCalls: true,
        canAddAdmins: true,
      );
      expect(AdminRights.fromJson(rights.toJson()), rights);

      final fromAliases = AdminRights.fromJson({
        'can_restrict_members': false,
        'can_manage_video_chats': true,
        'can_promote_members': true,
      });
      expect(fromAliases.canBanUsers, isFalse);
      expect(fromAliases.canManageCalls, isTrue);
      expect(fromAliases.canAddAdmins, isTrue);

      const ownerRights = AdminRights.all();
      expect(ownerRights.canAddAdmins, isTrue);
      expect(ownerRights.canEditMessages, isTrue);
      expect(ownerRights.canChangeInfo, isTrue);
    });

    test('ReactionSettings, RecentReplier, LinkedChatSummary, InviteLinkItem', () {
      final reactions = ReactionSettings.fromChatJson({
        'reaction_mode': 'selected',
        'allowed_reactions': ['🔥', '❤️'],
      });
      expect(reactions, isNotNull);
      expect(reactions!.isSelected, isTrue);
      expect(reactions.isReactionAllowed('🔥'), isTrue);
      expect(reactions.isReactionAllowed('👎'), isFalse);
      expect(ReactionSettings.fromJson(reactions.toJson()), reactions);

      const noneReactions = ReactionSettings(mode: 'none');
      expect(noneReactions.isReactionAllowed('🔥'), isFalse);

      final repliers = RecentReplier.parseList(
        jsonEncode([
          {'user_id': '11', 'display_name': 'Ann', 'avatar_url': '/a.png'},
          {'user_id': '12', 'display_name': 'Ben'},
        ]),
      );
      expect(repliers.length, 2);
      expect(repliers.first.avatarUrl, '/a.png');
      expect(repliers.last.avatarUrl, isNull);
      expect(RecentReplier.fromJson(repliers.first.toJson()), repliers.first);

      const linked = LinkedChatSummary(
        id: '99',
        name: 'Comments Chat',
        username: 'comments_chat',
        avatarUrl: '/g.png',
        chatType: 'group',
        memberCount: 42,
      );
      expect(LinkedChatSummary.fromJson(linked.toJson()), linked);

      final invite = InviteLinkItem.fromJson({
        'id': 7,
        'link': 'https://theaver.app/join/abc123',
        'title': 'VIP Invite',
        'uses': 3,
        'max_uses': 10,
        'expires_at': '2030-01-01T00:00:00Z',
        'created_at': '2026-11-18T10:00:00Z',
        'is_revoked': false,
        'requires_approval': true,
      });
      expect(invite.id, 7);
      expect(invite.title, 'VIP Invite');
      expect(invite.requiresApproval, isTrue);
      expect(invite.isActive, isTrue);
      expect(InviteLinkItem.fromJson(invite.toJson()).title, 'VIP Invite');
      expect(invite.copyWith(isRevoked: true).isActive, isFalse);
      expect(invite.copyWith(uses: 10).isLimitReached, isTrue);
    });

    test('PostCommentsResult parses root_post, comments, and linked_chat_id', () {
      final result = PostCommentsResult.fromJson({
        'success': true,
        'linked_chat_id': '88',
        'has_more': true,
        'root_post': {
          'id': '500',
          'chat_id': '88',
          'sender_id': '0',
          'content': 'Root channel post',
          'message_type': 'text',
          'is_edited': false,
          'created_at': '2026-11-18T12:00:00Z',
          'sender_name': 'Channel',
          'channel_post_id': '12',
          'views_count': 340,
          'comments_count': 1,
        },
        'comments': [
          {
            'id': '501',
            'chat_id': '88',
            'sender_id': '4',
            'content': 'Nice post!',
            'message_type': 'text',
            'is_edited': false,
            'created_at': '2026-11-18T12:01:00Z',
            'sender_name': 'User Four',
            'thread_root_message_id': '500',
          },
        ],
      });

      expect(result.success, isTrue);
      expect(result.linkedChatId, '88');
      expect(result.hasMore, isTrue);
      expect(result.rootPost?.channelPostId, '12');
      expect(result.rootPost?.viewsCount, 340);
      expect(result.comments.single.threadRootMessageId, '500');
    });
  });

  group('Chat, ChatDetails, ChatParticipant, and Message models', () {
    test('Chat defaults showAuthorProfiles=false for channels and roundtrips Drift',
        () {
      final defaultChannel = Chat(
        id: '10',
        chatType: 'channel',
        name: 'Channel',
        updatedAt: '2026-11-18T12:00:00Z',
      );
      expect(defaultChannel.showAuthorProfiles, isFalse);

      final parsedChannel = Chat.fromJson({
        'id': '10',
        'chat_type': 'channel',
        'name': 'News',
        'updated_at': '2026-11-18T12:00:00Z',
        'sign_messages': true,
        'linked_chat_id': '',
        'my_role': 'guest',
        'is_member': false,
        'last_message_sender_id': '0',
        'last_message_sender_name': 'News',
        'has_active_call': true,
        'active_call_id': 'call-1',
        'default_permissions': {'can_send_messages': true, 'can_pin_messages': true},
        'reaction_mode': 'selected',
        'allowed_reactions': ['👍'],
      });

      expect(parsedChannel.showAuthorProfiles, isFalse);
      expect(parsedChannel.signMessages, isTrue);
      expect(parsedChannel.linkedChatId, isNull);
      expect(parsedChannel.myRole, 'guest');
      expect(parsedChannel.isMember, isFalse);
      expect(parsedChannel.hasActiveCall, isTrue);
      expect(parsedChannel.activeCallId, 'call-1');
      expect(parsedChannel.defaultPermissions?.canPinMessages, isTrue);
      expect(parsedChannel.reactionSettings?.allowedReactions, ['👍']);
    });

    test('Chat and Message Drift companion roundtrip preserves all v13 fields',
        () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async => await db.close());

      final chat = Chat(
        id: '55',
        chatType: 'channel',
        name: 'Tech Digest',
        updatedAt: '2026-11-18T14:00:00Z',
        showAuthorProfiles: true,
        signMessages: true,
        linkedChatId: '56',
        myRole: 'admin',
        lastMessageSenderId: '9',
        lastMessageSenderName: 'Editor',
        hasActiveCall: true,
        defaultPermissions: const GroupDefaultPermissions(canPinMessages: true),
        reactionSettings: const ReactionSettings(
          mode: 'selected',
          allowedReactions: ['❤️', '🔥'],
        ),
      );
      await db.saveChat(chat.toCompanion());
      final dbChat = await db.getChat('55');
      expect(dbChat, isNotNull);
      final restoredChat = Chat.fromDbChat(dbChat!);
      expect(restoredChat.showAuthorProfiles, isTrue);
      expect(restoredChat.signMessages, isTrue);
      expect(restoredChat.linkedChatId, '56');
      expect(restoredChat.myRole, 'admin');
      expect(restoredChat.isMember, isTrue);
      expect(restoredChat.lastMessageSenderId, '9');
      expect(restoredChat.lastMessageSenderName, 'Editor');
      expect(restoredChat.hasActiveCall, isTrue);
      expect(restoredChat.defaultPermissions?.canPinMessages, isTrue);
      expect(restoredChat.reactionSettings?.mode, 'selected');
      expect(restoredChat.reactionSettings?.allowedReactions, ['❤️', '🔥']);

      final msg = Message.fromJson({
        'id': '700',
        'chat_id': '55',
        'sender_id': '9',
        'content': 'Launch update',
        'message_type': 'text',
        'is_edited': false,
        'created_at': '2026-11-18T14:05:00Z',
        'sender_name': 'Tech Digest',
        'views_count': 42,
        'author_signature': 'Chief Editor',
        'post_author_id': '9',
        'sender_role': 'admin',
        'sender_admin_title': 'Editor',
        'is_from_anonymous_admin': true,
        'is_silent': true,
        'comments_count': 3,
        'can_comment': true,
        'recent_repliers': [
          {'user_id': '2', 'display_name': 'Alex', 'avatar_url': '/u2.png'},
        ],
        'channel_post_id': '700',
        'thread_root_message_id': '699',
      });
      await db.saveMessage(msg.toCompanion());
      final dbMsg = await db.getMessageByServerId('700');
      expect(dbMsg, isNotNull);
      final restoredMsg = Message.fromDbMessage(dbMsg!);
      expect(restoredMsg.viewsCount, 42);
      expect(restoredMsg.authorSignature, 'Chief Editor');
      expect(restoredMsg.postAuthorId, '9');
      expect(restoredMsg.senderRole, 'admin');
      expect(restoredMsg.senderAdminTitle, 'Editor');
      expect(restoredMsg.isFromAnonymousAdmin, isTrue);
      expect(restoredMsg.isSilent, isTrue);
      expect(restoredMsg.commentsCount, 3);
      expect(restoredMsg.canComment, isTrue);
      expect(restoredMsg.recentRepliers.single.displayName, 'Alex');
      expect(restoredMsg.channelPostId, '700');
      expect(restoredMsg.threadRootMessageId, '699');
    });

    test('ChatDetails and ChatParticipant parse new fields and effectivePermissions',
        () {
      final details = ChatDetails.fromJson({
        'id': '30',
        'chat_type': 'group',
        'name': 'Core Group',
        'created_by': '1',
        'created_at': '2026-11-18T10:00:00Z',
        'updated_at': '2026-11-18T10:00:00Z',
        'my_role': 'member',
        'is_member': true,
        'sign_messages': false,
        'linked_chat_id': '29',
        'linked_chat': {
          'id': '29',
          'name': 'Core Channel',
          'chat_type': 'channel',
          'member_count': 500,
        },
        'default_permissions': {
          'can_send_messages': true,
          'can_send_media': true,
          'can_send_polls': true,
        },
        'my_restrictions': {
          'can_send_messages': true,
          'can_send_media': false,
        },
        'restricted_until': '2099-01-01T00:00:00Z',
        'reaction_mode': 'all',
        'slow_mode_interval': 30,
        'history_for_new_members': false,
        'has_active_call': true,
        'active_call_id': 'call-30',
        'participants': [
          {
            'user_id': '5',
            'username': 'mod',
            'display_name': 'Moderator',
            'role': 'admin',
            'admin_title': 'Mod',
            'is_anonymous': true,
            'admin_permissions': {'can_ban_users': true, 'can_add_admins': false},
            'is_banned': false,
          },
        ],
      });

      expect(details.linkedChat?.name, 'Core Channel');
      expect(details.slowModeInterval, 30);
      expect(details.historyForNewMembers, isFalse);
      expect(details.hasActiveCall, isTrue);
      expect(details.activeCallId, 'call-30');
      expect(details.effectivePermissions.canSendMessages, isTrue);
      expect(details.effectivePermissions.canSendMedia, isFalse);

      // Expired restriction restores default permissions
      final unRestricted = details.copyWith(
        restrictedUntil: DateTime.utc(2020, 1, 1),
      );
      expect(unRestricted.effectivePermissions.canSendMedia, isTrue);

      final participant = details.participants.single;
      expect(participant.id, '5');
      expect(participant.adminTitle, 'Mod');
      expect(participant.isAnonymous, isTrue);
      expect(participant.adminPermissions?.canBanUsers, isTrue);
      expect(participant.adminPermissions?.canAddAdmins, isFalse);
      expect(participant.isBanned, isFalse);
    });
  });

  group('WebSocketEvent parsing and ChatService.handleWebSocketEvent Drift sync',
      () {
    test('WebSocketEvent maps new types instead of falling back to connected', () {
      expect(
        WebSocketEvent.fromJson({'type': 'message_views_updated', 'data': {}}).type,
        WebSocketEventType.messageViewsUpdated,
      );
      expect(
        WebSocketEvent.fromJson({'type': 'post_comments_updated', 'data': {}}).type,
        WebSocketEventType.postCommentsUpdated,
      );
      expect(
        WebSocketEvent.fromJson({'type': 'chat_settings_updated', 'data': {}}).type,
        WebSocketEventType.chatSettingsUpdated,
      );
      expect(
        WebSocketEvent.fromJson({'type': 'member_updated', 'data': {}}).type,
        WebSocketEventType.memberUpdated,
      );
      expect(
        WebSocketEvent.fromJson({'type': 'chat_deleted', 'data': {}}).type,
        WebSocketEventType.chatDeleted,
      );
    });

    test('ChatService.handleWebSocketEvent updates views, comments, settings, and membership in Drift',
        () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(() async => await db.close());

      await db.saveChat(
        ChatsCompanion.insert(
          chatId: '100',
          chatType: 'channel',
          name: 'Channel 100',
          updatedAt: '2026-11-18T12:00:00Z',
          myRole: const Value('subscriber'),
        ),
      );
      await db.saveMessage(
        Message(
          id: '1001',
          chatId: '100',
          senderId: '0',
          content: 'Post 1001',
          messageType: 'text',
          isEdited: false,
          createdAt: '2026-11-18T12:00:00Z',
          senderName: 'Channel 100',
          viewsCount: 1,
          commentsCount: 0,
        ).toCompanion(),
      );

      final received = <ChatRealtimeUpdate>[];
      final sub = ChatService.realtimeUpdates.listen(received.add);
      addTearDown(() => sub.cancel());

      await ChatService.handleWebSocketEvent(
        WebSocketEvent.fromJson({
          'type': 'message_views_updated',
          'data': {
            'chat_id': '100',
            'views': [
              {'message_id': '1001', 'views_count': 25},
            ],
          },
        }),
        db: db,
      );
      expect((await db.getMessageByServerId('1001'))?.viewsCount, 25);

      await ChatService.handleWebSocketEvent(
        WebSocketEvent.fromJson({
          'type': 'post_comments_updated',
          'data': {
            'chat_id': '100',
            'message_id': '1001',
            'comments_count': 4,
            'recent_repliers': [
              {'user_id': '2', 'display_name': 'Alice'},
            ],
          },
        }),
        db: db,
      );
      final updatedMsg = await db.getMessageByServerId('1001');
      expect(updatedMsg?.commentsCount, 4);
      expect(
        RecentReplier.parseList(updatedMsg?.recentRepliersJson).single.displayName,
        'Alice',
      );

      await ChatService.handleWebSocketEvent(
        WebSocketEvent.fromJson({
          'type': 'chat_settings_updated',
          'data': {
            'chat_id': '100',
            'sign_messages': true,
            'show_author_profiles': true,
            'linked_chat_id': '101',
            'reaction_mode': 'selected',
            'allowed_reactions': ['🔥'],
          },
        }),
        db: db,
      );
      final updatedChat = await db.getChat('100');
      expect(updatedChat?.signMessages, isTrue);
      expect(updatedChat?.showAuthorProfiles, isTrue);
      expect(updatedChat?.linkedChatId, '101');
      expect(
        ReactionSettings.tryParse(updatedChat?.reactionSettingsJson)?.allowedReactions,
        ['🔥'],
      );

      await ChatService.handleWebSocketEvent(
        WebSocketEvent.fromJson({
          'type': 'member_updated',
          'data': {
            'chat_id': '100',
            'user_id': '42',
            'role': 'admin',
            'action': 'role_changed',
          },
        }),
        db: db,
        currentUserId: '42',
      );
      expect((await db.getChat('100'))?.myRole, 'admin');

      await ChatService.handleWebSocketEvent(
        WebSocketEvent.fromJson({
          'type': 'member_updated',
          'data': {
            'chat_id': '100',
            'user_id': '42',
            'action': 'banned',
          },
        }),
        db: db,
        currentUserId: '42',
      );
      expect(await db.getChat('100'), isNull);

      await Future<void>.delayed(Duration.zero);
      expect(received.length, 5);
    });
  });
}
