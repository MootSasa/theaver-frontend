// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $ChatsTable extends Chats with TableInfo<$ChatsTable, DbChat> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ChatsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _chatIdMeta = const VerificationMeta('chatId');
  @override
  late final GeneratedColumn<String> chatId = GeneratedColumn<String>(
      'chat_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _chatTypeMeta =
      const VerificationMeta('chatType');
  @override
  late final GeneratedColumn<String> chatType = GeneratedColumn<String>(
      'chat_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
      'name', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _avatarUrlMeta =
      const VerificationMeta('avatarUrl');
  @override
  late final GeneratedColumn<String> avatarUrl = GeneratedColumn<String>(
      'avatar_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastMessageMeta =
      const VerificationMeta('lastMessage');
  @override
  late final GeneratedColumn<String> lastMessage = GeneratedColumn<String>(
      'last_message', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastMessageTimeMeta =
      const VerificationMeta('lastMessageTime');
  @override
  late final GeneratedColumn<String> lastMessageTime = GeneratedColumn<String>(
      'last_message_time', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _updatedAtMeta =
      const VerificationMeta('updatedAt');
  @override
  late final GeneratedColumn<String> updatedAt = GeneratedColumn<String>(
      'updated_at', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _unreadCountMeta =
      const VerificationMeta('unreadCount');
  @override
  late final GeneratedColumn<int> unreadCount = GeneratedColumn<int>(
      'unread_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _isOnlineMeta =
      const VerificationMeta('isOnline');
  @override
  late final GeneratedColumn<bool> isOnline = GeneratedColumn<bool>(
      'is_online', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_online" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _lastSeenMeta =
      const VerificationMeta('lastSeen');
  @override
  late final GeneratedColumn<String> lastSeen = GeneratedColumn<String>(
      'last_seen', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isPinnedMeta =
      const VerificationMeta('isPinned');
  @override
  late final GeneratedColumn<bool> isPinned = GeneratedColumn<bool>(
      'is_pinned', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_pinned" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _lastMessageTypeMeta =
      const VerificationMeta('lastMessageType');
  @override
  late final GeneratedColumn<String> lastMessageType = GeneratedColumn<String>(
      'last_message_type', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastMessageIsRoundMeta =
      const VerificationMeta('lastMessageIsRound');
  @override
  late final GeneratedColumn<bool> lastMessageIsRound = GeneratedColumn<bool>(
      'last_message_is_round', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("last_message_is_round" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _lastMessageFileUrlMeta =
      const VerificationMeta('lastMessageFileUrl');
  @override
  late final GeneratedColumn<String> lastMessageFileUrl =
      GeneratedColumn<String>('last_message_file_url', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastMessageGroupedIdMeta =
      const VerificationMeta('lastMessageGroupedId');
  @override
  late final GeneratedColumn<String> lastMessageGroupedId =
      GeneratedColumn<String>('last_message_grouped_id', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _otherUserIdMeta =
      const VerificationMeta('otherUserId');
  @override
  late final GeneratedColumn<String> otherUserId = GeneratedColumn<String>(
      'other_user_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastReadInboxMessageIdMeta =
      const VerificationMeta('lastReadInboxMessageId');
  @override
  late final GeneratedColumn<int> lastReadInboxMessageId = GeneratedColumn<int>(
      'last_read_inbox_message_id', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastReadOutboxMessageIdMeta =
      const VerificationMeta('lastReadOutboxMessageId');
  @override
  late final GeneratedColumn<int> lastReadOutboxMessageId =
      GeneratedColumn<int>('last_read_outbox_message_id', aliasedName, false,
          type: DriftSqlType.int,
          requiredDuringInsert: false,
          defaultValue: const Constant(0));
  static const VerificationMeta _pinnedMessageIdMeta =
      const VerificationMeta('pinnedMessageId');
  @override
  late final GeneratedColumn<int> pinnedMessageId = GeneratedColumn<int>(
      'pinned_message_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _usernameMeta =
      const VerificationMeta('username');
  @override
  late final GeneratedColumn<String> username = GeneratedColumn<String>(
      'username', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isPublicMeta =
      const VerificationMeta('isPublic');
  @override
  late final GeneratedColumn<bool> isPublic = GeneratedColumn<bool>(
      'is_public', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_public" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isBotMeta = const VerificationMeta('isBot');
  @override
  late final GeneratedColumn<bool> isBot = GeneratedColumn<bool>(
      'is_bot', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_bot" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isVerifiedMeta =
      const VerificationMeta('isVerified');
  @override
  late final GeneratedColumn<bool> isVerified = GeneratedColumn<bool>(
      'is_verified', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_verified" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isArchivedMeta =
      const VerificationMeta('isArchived');
  @override
  late final GeneratedColumn<bool> isArchived = GeneratedColumn<bool>(
      'is_archived', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_archived" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _peerCustomizationJsonMeta =
      const VerificationMeta('peerCustomizationJson');
  @override
  late final GeneratedColumn<String> peerCustomizationJson =
      GeneratedColumn<String>('peer_customization_json', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _showAuthorProfilesMeta =
      const VerificationMeta('showAuthorProfiles');
  @override
  late final GeneratedColumn<bool> showAuthorProfiles = GeneratedColumn<bool>(
      'show_author_profiles', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("show_author_profiles" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _signMessagesMeta =
      const VerificationMeta('signMessages');
  @override
  late final GeneratedColumn<bool> signMessages = GeneratedColumn<bool>(
      'sign_messages', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("sign_messages" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _linkedChatIdMeta =
      const VerificationMeta('linkedChatId');
  @override
  late final GeneratedColumn<String> linkedChatId = GeneratedColumn<String>(
      'linked_chat_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _myRoleMeta = const VerificationMeta('myRole');
  @override
  late final GeneratedColumn<String> myRole = GeneratedColumn<String>(
      'my_role', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastMessageSenderIdMeta =
      const VerificationMeta('lastMessageSenderId');
  @override
  late final GeneratedColumn<String> lastMessageSenderId =
      GeneratedColumn<String>('last_message_sender_id', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _lastMessageSenderNameMeta =
      const VerificationMeta('lastMessageSenderName');
  @override
  late final GeneratedColumn<String> lastMessageSenderName =
      GeneratedColumn<String>('last_message_sender_name', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _hasActiveCallMeta =
      const VerificationMeta('hasActiveCall');
  @override
  late final GeneratedColumn<bool> hasActiveCall = GeneratedColumn<bool>(
      'has_active_call', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("has_active_call" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _chatPermissionsJsonMeta =
      const VerificationMeta('chatPermissionsJson');
  @override
  late final GeneratedColumn<String> chatPermissionsJson =
      GeneratedColumn<String>('chat_permissions_json', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _reactionSettingsJsonMeta =
      const VerificationMeta('reactionSettingsJson');
  @override
  late final GeneratedColumn<String> reactionSettingsJson =
      GeneratedColumn<String>('reaction_settings_json', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _hasProtectedContentMeta =
      const VerificationMeta('hasProtectedContent');
  @override
  late final GeneratedColumn<bool> hasProtectedContent = GeneratedColumn<bool>(
      'has_protected_content', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("has_protected_content" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _pinnedMessageIdsJsonMeta =
      const VerificationMeta('pinnedMessageIdsJson');
  @override
  late final GeneratedColumn<String> pinnedMessageIdsJson =
      GeneratedColumn<String>('pinned_message_ids_json', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _messageAutoDeleteTimeMeta =
      const VerificationMeta('messageAutoDeleteTime');
  @override
  late final GeneratedColumn<int> messageAutoDeleteTime = GeneratedColumn<int>(
      'message_auto_delete_time', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _appearanceJsonMeta =
      const VerificationMeta('appearanceJson');
  @override
  late final GeneratedColumn<String> appearanceJson = GeneratedColumn<String>(
      'appearance_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isForumMeta =
      const VerificationMeta('isForum');
  @override
  late final GeneratedColumn<bool> isForum = GeneratedColumn<bool>(
      'is_forum', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_forum" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _participantsHiddenMeta =
      const VerificationMeta('participantsHidden');
  @override
  late final GeneratedColumn<bool> participantsHidden = GeneratedColumn<bool>(
      'participants_hidden', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("participants_hidden" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _hasAggressiveAntiSpamEnabledMeta =
      const VerificationMeta('hasAggressiveAntiSpamEnabled');
  @override
  late final GeneratedColumn<bool> hasAggressiveAntiSpamEnabled =
      GeneratedColumn<bool>(
          'has_aggressive_anti_spam_enabled', aliasedName, false,
          type: DriftSqlType.bool,
          requiredDuringInsert: false,
          defaultConstraints: GeneratedColumn.constraintIsAlways(
              'CHECK ("has_aggressive_anti_spam_enabled" IN (0, 1))'),
          defaultValue: const Constant(false));
  static const VerificationMeta _maxReactionsPerPostMeta =
      const VerificationMeta('maxReactionsPerPost');
  @override
  late final GeneratedColumn<int> maxReactionsPerPost = GeneratedColumn<int>(
      'max_reactions_per_post', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(11));
  static const VerificationMeta _unreadMentionsCountMeta =
      const VerificationMeta('unreadMentionsCount');
  @override
  late final GeneratedColumn<int> unreadMentionsCount = GeneratedColumn<int>(
      'unread_mentions_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _unreadReactionsCountMeta =
      const VerificationMeta('unreadReactionsCount');
  @override
  late final GeneratedColumn<int> unreadReactionsCount = GeneratedColumn<int>(
      'unread_reactions_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  @override
  List<GeneratedColumn> get $columns => [
        chatId,
        chatType,
        name,
        avatarUrl,
        lastMessage,
        lastMessageTime,
        updatedAt,
        unreadCount,
        isOnline,
        lastSeen,
        isPinned,
        lastMessageType,
        lastMessageIsRound,
        lastMessageFileUrl,
        lastMessageGroupedId,
        otherUserId,
        lastReadInboxMessageId,
        lastReadOutboxMessageId,
        pinnedMessageId,
        username,
        isPublic,
        isBot,
        isVerified,
        isArchived,
        peerCustomizationJson,
        showAuthorProfiles,
        signMessages,
        linkedChatId,
        myRole,
        lastMessageSenderId,
        lastMessageSenderName,
        hasActiveCall,
        chatPermissionsJson,
        reactionSettingsJson,
        hasProtectedContent,
        pinnedMessageIdsJson,
        messageAutoDeleteTime,
        appearanceJson,
        isForum,
        participantsHidden,
        hasAggressiveAntiSpamEnabled,
        maxReactionsPerPost,
        unreadMentionsCount,
        unreadReactionsCount
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'chats';
  @override
  VerificationContext validateIntegrity(Insertable<DbChat> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('chat_id')) {
      context.handle(_chatIdMeta,
          chatId.isAcceptableOrUnknown(data['chat_id']!, _chatIdMeta));
    } else if (isInserting) {
      context.missing(_chatIdMeta);
    }
    if (data.containsKey('chat_type')) {
      context.handle(_chatTypeMeta,
          chatType.isAcceptableOrUnknown(data['chat_type']!, _chatTypeMeta));
    } else if (isInserting) {
      context.missing(_chatTypeMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
          _nameMeta, name.isAcceptableOrUnknown(data['name']!, _nameMeta));
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('avatar_url')) {
      context.handle(_avatarUrlMeta,
          avatarUrl.isAcceptableOrUnknown(data['avatar_url']!, _avatarUrlMeta));
    }
    if (data.containsKey('last_message')) {
      context.handle(
          _lastMessageMeta,
          lastMessage.isAcceptableOrUnknown(
              data['last_message']!, _lastMessageMeta));
    }
    if (data.containsKey('last_message_time')) {
      context.handle(
          _lastMessageTimeMeta,
          lastMessageTime.isAcceptableOrUnknown(
              data['last_message_time']!, _lastMessageTimeMeta));
    }
    if (data.containsKey('updated_at')) {
      context.handle(_updatedAtMeta,
          updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta));
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    if (data.containsKey('unread_count')) {
      context.handle(
          _unreadCountMeta,
          unreadCount.isAcceptableOrUnknown(
              data['unread_count']!, _unreadCountMeta));
    }
    if (data.containsKey('is_online')) {
      context.handle(_isOnlineMeta,
          isOnline.isAcceptableOrUnknown(data['is_online']!, _isOnlineMeta));
    }
    if (data.containsKey('last_seen')) {
      context.handle(_lastSeenMeta,
          lastSeen.isAcceptableOrUnknown(data['last_seen']!, _lastSeenMeta));
    }
    if (data.containsKey('is_pinned')) {
      context.handle(_isPinnedMeta,
          isPinned.isAcceptableOrUnknown(data['is_pinned']!, _isPinnedMeta));
    }
    if (data.containsKey('last_message_type')) {
      context.handle(
          _lastMessageTypeMeta,
          lastMessageType.isAcceptableOrUnknown(
              data['last_message_type']!, _lastMessageTypeMeta));
    }
    if (data.containsKey('last_message_is_round')) {
      context.handle(
          _lastMessageIsRoundMeta,
          lastMessageIsRound.isAcceptableOrUnknown(
              data['last_message_is_round']!, _lastMessageIsRoundMeta));
    }
    if (data.containsKey('last_message_file_url')) {
      context.handle(
          _lastMessageFileUrlMeta,
          lastMessageFileUrl.isAcceptableOrUnknown(
              data['last_message_file_url']!, _lastMessageFileUrlMeta));
    }
    if (data.containsKey('last_message_grouped_id')) {
      context.handle(
          _lastMessageGroupedIdMeta,
          lastMessageGroupedId.isAcceptableOrUnknown(
              data['last_message_grouped_id']!, _lastMessageGroupedIdMeta));
    }
    if (data.containsKey('other_user_id')) {
      context.handle(
          _otherUserIdMeta,
          otherUserId.isAcceptableOrUnknown(
              data['other_user_id']!, _otherUserIdMeta));
    }
    if (data.containsKey('last_read_inbox_message_id')) {
      context.handle(
          _lastReadInboxMessageIdMeta,
          lastReadInboxMessageId.isAcceptableOrUnknown(
              data['last_read_inbox_message_id']!,
              _lastReadInboxMessageIdMeta));
    }
    if (data.containsKey('last_read_outbox_message_id')) {
      context.handle(
          _lastReadOutboxMessageIdMeta,
          lastReadOutboxMessageId.isAcceptableOrUnknown(
              data['last_read_outbox_message_id']!,
              _lastReadOutboxMessageIdMeta));
    }
    if (data.containsKey('pinned_message_id')) {
      context.handle(
          _pinnedMessageIdMeta,
          pinnedMessageId.isAcceptableOrUnknown(
              data['pinned_message_id']!, _pinnedMessageIdMeta));
    }
    if (data.containsKey('username')) {
      context.handle(_usernameMeta,
          username.isAcceptableOrUnknown(data['username']!, _usernameMeta));
    }
    if (data.containsKey('is_public')) {
      context.handle(_isPublicMeta,
          isPublic.isAcceptableOrUnknown(data['is_public']!, _isPublicMeta));
    }
    if (data.containsKey('is_bot')) {
      context.handle(
          _isBotMeta, isBot.isAcceptableOrUnknown(data['is_bot']!, _isBotMeta));
    }
    if (data.containsKey('is_verified')) {
      context.handle(
          _isVerifiedMeta,
          isVerified.isAcceptableOrUnknown(
              data['is_verified']!, _isVerifiedMeta));
    }
    if (data.containsKey('is_archived')) {
      context.handle(
          _isArchivedMeta,
          isArchived.isAcceptableOrUnknown(
              data['is_archived']!, _isArchivedMeta));
    }
    if (data.containsKey('peer_customization_json')) {
      context.handle(
          _peerCustomizationJsonMeta,
          peerCustomizationJson.isAcceptableOrUnknown(
              data['peer_customization_json']!, _peerCustomizationJsonMeta));
    }
    if (data.containsKey('show_author_profiles')) {
      context.handle(
          _showAuthorProfilesMeta,
          showAuthorProfiles.isAcceptableOrUnknown(
              data['show_author_profiles']!, _showAuthorProfilesMeta));
    }
    if (data.containsKey('sign_messages')) {
      context.handle(
          _signMessagesMeta,
          signMessages.isAcceptableOrUnknown(
              data['sign_messages']!, _signMessagesMeta));
    }
    if (data.containsKey('linked_chat_id')) {
      context.handle(
          _linkedChatIdMeta,
          linkedChatId.isAcceptableOrUnknown(
              data['linked_chat_id']!, _linkedChatIdMeta));
    }
    if (data.containsKey('my_role')) {
      context.handle(_myRoleMeta,
          myRole.isAcceptableOrUnknown(data['my_role']!, _myRoleMeta));
    }
    if (data.containsKey('last_message_sender_id')) {
      context.handle(
          _lastMessageSenderIdMeta,
          lastMessageSenderId.isAcceptableOrUnknown(
              data['last_message_sender_id']!, _lastMessageSenderIdMeta));
    }
    if (data.containsKey('last_message_sender_name')) {
      context.handle(
          _lastMessageSenderNameMeta,
          lastMessageSenderName.isAcceptableOrUnknown(
              data['last_message_sender_name']!, _lastMessageSenderNameMeta));
    }
    if (data.containsKey('has_active_call')) {
      context.handle(
          _hasActiveCallMeta,
          hasActiveCall.isAcceptableOrUnknown(
              data['has_active_call']!, _hasActiveCallMeta));
    }
    if (data.containsKey('chat_permissions_json')) {
      context.handle(
          _chatPermissionsJsonMeta,
          chatPermissionsJson.isAcceptableOrUnknown(
              data['chat_permissions_json']!, _chatPermissionsJsonMeta));
    }
    if (data.containsKey('reaction_settings_json')) {
      context.handle(
          _reactionSettingsJsonMeta,
          reactionSettingsJson.isAcceptableOrUnknown(
              data['reaction_settings_json']!, _reactionSettingsJsonMeta));
    }
    if (data.containsKey('has_protected_content')) {
      context.handle(
          _hasProtectedContentMeta,
          hasProtectedContent.isAcceptableOrUnknown(
              data['has_protected_content']!, _hasProtectedContentMeta));
    }
    if (data.containsKey('pinned_message_ids_json')) {
      context.handle(
          _pinnedMessageIdsJsonMeta,
          pinnedMessageIdsJson.isAcceptableOrUnknown(
              data['pinned_message_ids_json']!, _pinnedMessageIdsJsonMeta));
    }
    if (data.containsKey('message_auto_delete_time')) {
      context.handle(
          _messageAutoDeleteTimeMeta,
          messageAutoDeleteTime.isAcceptableOrUnknown(
              data['message_auto_delete_time']!, _messageAutoDeleteTimeMeta));
    }
    if (data.containsKey('appearance_json')) {
      context.handle(
          _appearanceJsonMeta,
          appearanceJson.isAcceptableOrUnknown(
              data['appearance_json']!, _appearanceJsonMeta));
    }
    if (data.containsKey('is_forum')) {
      context.handle(_isForumMeta,
          isForum.isAcceptableOrUnknown(data['is_forum']!, _isForumMeta));
    }
    if (data.containsKey('participants_hidden')) {
      context.handle(
          _participantsHiddenMeta,
          participantsHidden.isAcceptableOrUnknown(
              data['participants_hidden']!, _participantsHiddenMeta));
    }
    if (data.containsKey('has_aggressive_anti_spam_enabled')) {
      context.handle(
          _hasAggressiveAntiSpamEnabledMeta,
          hasAggressiveAntiSpamEnabled.isAcceptableOrUnknown(
              data['has_aggressive_anti_spam_enabled']!,
              _hasAggressiveAntiSpamEnabledMeta));
    }
    if (data.containsKey('max_reactions_per_post')) {
      context.handle(
          _maxReactionsPerPostMeta,
          maxReactionsPerPost.isAcceptableOrUnknown(
              data['max_reactions_per_post']!, _maxReactionsPerPostMeta));
    }
    if (data.containsKey('unread_mentions_count')) {
      context.handle(
          _unreadMentionsCountMeta,
          unreadMentionsCount.isAcceptableOrUnknown(
              data['unread_mentions_count']!, _unreadMentionsCountMeta));
    }
    if (data.containsKey('unread_reactions_count')) {
      context.handle(
          _unreadReactionsCountMeta,
          unreadReactionsCount.isAcceptableOrUnknown(
              data['unread_reactions_count']!, _unreadReactionsCountMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {chatId};
  @override
  DbChat map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbChat(
      chatId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}chat_id'])!,
      chatType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}chat_type'])!,
      name: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}name'])!,
      avatarUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}avatar_url']),
      lastMessage: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_message']),
      lastMessageTime: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}last_message_time']),
      updatedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}updated_at'])!,
      unreadCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}unread_count'])!,
      isOnline: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_online'])!,
      lastSeen: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_seen']),
      isPinned: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_pinned'])!,
      lastMessageType: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}last_message_type']),
      lastMessageIsRound: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}last_message_is_round'])!,
      lastMessageFileUrl: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}last_message_file_url']),
      lastMessageGroupedId: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}last_message_grouped_id']),
      otherUserId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}other_user_id']),
      lastReadInboxMessageId: attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}last_read_inbox_message_id'])!,
      lastReadOutboxMessageId: attachedDatabase.typeMapping.read(
          DriftSqlType.int,
          data['${effectivePrefix}last_read_outbox_message_id'])!,
      pinnedMessageId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}pinned_message_id']),
      username: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}username']),
      isPublic: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_public'])!,
      isBot: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_bot'])!,
      isVerified: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_verified'])!,
      isArchived: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_archived'])!,
      peerCustomizationJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}peer_customization_json']),
      showAuthorProfiles: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}show_author_profiles'])!,
      signMessages: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}sign_messages'])!,
      linkedChatId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}linked_chat_id']),
      myRole: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}my_role']),
      lastMessageSenderId: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}last_message_sender_id']),
      lastMessageSenderName: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}last_message_sender_name']),
      hasActiveCall: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}has_active_call'])!,
      chatPermissionsJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}chat_permissions_json']),
      reactionSettingsJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}reaction_settings_json']),
      hasProtectedContent: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}has_protected_content'])!,
      pinnedMessageIdsJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}pinned_message_ids_json']),
      messageAutoDeleteTime: attachedDatabase.typeMapping.read(DriftSqlType.int,
          data['${effectivePrefix}message_auto_delete_time'])!,
      appearanceJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}appearance_json']),
      isForum: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_forum'])!,
      participantsHidden: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}participants_hidden'])!,
      hasAggressiveAntiSpamEnabled: attachedDatabase.typeMapping.read(
          DriftSqlType.bool,
          data['${effectivePrefix}has_aggressive_anti_spam_enabled'])!,
      maxReactionsPerPost: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}max_reactions_per_post'])!,
      unreadMentionsCount: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}unread_mentions_count'])!,
      unreadReactionsCount: attachedDatabase.typeMapping.read(
          DriftSqlType.int, data['${effectivePrefix}unread_reactions_count'])!,
    );
  }

  @override
  $ChatsTable createAlias(String alias) {
    return $ChatsTable(attachedDatabase, alias);
  }
}

class DbChat extends DataClass implements Insertable<DbChat> {
  final String chatId;
  final String chatType;
  final String name;
  final String? avatarUrl;
  final String? lastMessage;
  final String? lastMessageTime;
  final String updatedAt;
  final int unreadCount;
  final bool isOnline;
  final String? lastSeen;
  final bool isPinned;
  final String? lastMessageType;
  final bool lastMessageIsRound;
  final String? lastMessageFileUrl;
  final String? lastMessageGroupedId;
  final String? otherUserId;
  final int lastReadInboxMessageId;
  final int lastReadOutboxMessageId;
  final int? pinnedMessageId;
  final String? username;
  final bool isPublic;
  final bool isBot;
  final bool isVerified;
  final bool isArchived;
  final String? peerCustomizationJson;
  final bool showAuthorProfiles;
  final bool signMessages;
  final String? linkedChatId;
  final String? myRole;
  final String? lastMessageSenderId;
  final String? lastMessageSenderName;
  final bool hasActiveCall;
  final String? chatPermissionsJson;
  final String? reactionSettingsJson;
  final bool hasProtectedContent;
  final String? pinnedMessageIdsJson;
  final int messageAutoDeleteTime;
  final String? appearanceJson;
  final bool isForum;
  final bool participantsHidden;
  final bool hasAggressiveAntiSpamEnabled;
  final int maxReactionsPerPost;
  final int unreadMentionsCount;
  final int unreadReactionsCount;
  const DbChat(
      {required this.chatId,
      required this.chatType,
      required this.name,
      this.avatarUrl,
      this.lastMessage,
      this.lastMessageTime,
      required this.updatedAt,
      required this.unreadCount,
      required this.isOnline,
      this.lastSeen,
      required this.isPinned,
      this.lastMessageType,
      required this.lastMessageIsRound,
      this.lastMessageFileUrl,
      this.lastMessageGroupedId,
      this.otherUserId,
      required this.lastReadInboxMessageId,
      required this.lastReadOutboxMessageId,
      this.pinnedMessageId,
      this.username,
      required this.isPublic,
      required this.isBot,
      required this.isVerified,
      required this.isArchived,
      this.peerCustomizationJson,
      required this.showAuthorProfiles,
      required this.signMessages,
      this.linkedChatId,
      this.myRole,
      this.lastMessageSenderId,
      this.lastMessageSenderName,
      required this.hasActiveCall,
      this.chatPermissionsJson,
      this.reactionSettingsJson,
      required this.hasProtectedContent,
      this.pinnedMessageIdsJson,
      required this.messageAutoDeleteTime,
      this.appearanceJson,
      required this.isForum,
      required this.participantsHidden,
      required this.hasAggressiveAntiSpamEnabled,
      required this.maxReactionsPerPost,
      required this.unreadMentionsCount,
      required this.unreadReactionsCount});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['chat_id'] = Variable<String>(chatId);
    map['chat_type'] = Variable<String>(chatType);
    map['name'] = Variable<String>(name);
    if (!nullToAbsent || avatarUrl != null) {
      map['avatar_url'] = Variable<String>(avatarUrl);
    }
    if (!nullToAbsent || lastMessage != null) {
      map['last_message'] = Variable<String>(lastMessage);
    }
    if (!nullToAbsent || lastMessageTime != null) {
      map['last_message_time'] = Variable<String>(lastMessageTime);
    }
    map['updated_at'] = Variable<String>(updatedAt);
    map['unread_count'] = Variable<int>(unreadCount);
    map['is_online'] = Variable<bool>(isOnline);
    if (!nullToAbsent || lastSeen != null) {
      map['last_seen'] = Variable<String>(lastSeen);
    }
    map['is_pinned'] = Variable<bool>(isPinned);
    if (!nullToAbsent || lastMessageType != null) {
      map['last_message_type'] = Variable<String>(lastMessageType);
    }
    map['last_message_is_round'] = Variable<bool>(lastMessageIsRound);
    if (!nullToAbsent || lastMessageFileUrl != null) {
      map['last_message_file_url'] = Variable<String>(lastMessageFileUrl);
    }
    if (!nullToAbsent || lastMessageGroupedId != null) {
      map['last_message_grouped_id'] = Variable<String>(lastMessageGroupedId);
    }
    if (!nullToAbsent || otherUserId != null) {
      map['other_user_id'] = Variable<String>(otherUserId);
    }
    map['last_read_inbox_message_id'] = Variable<int>(lastReadInboxMessageId);
    map['last_read_outbox_message_id'] = Variable<int>(lastReadOutboxMessageId);
    if (!nullToAbsent || pinnedMessageId != null) {
      map['pinned_message_id'] = Variable<int>(pinnedMessageId);
    }
    if (!nullToAbsent || username != null) {
      map['username'] = Variable<String>(username);
    }
    map['is_public'] = Variable<bool>(isPublic);
    map['is_bot'] = Variable<bool>(isBot);
    map['is_verified'] = Variable<bool>(isVerified);
    map['is_archived'] = Variable<bool>(isArchived);
    if (!nullToAbsent || peerCustomizationJson != null) {
      map['peer_customization_json'] = Variable<String>(peerCustomizationJson);
    }
    map['show_author_profiles'] = Variable<bool>(showAuthorProfiles);
    map['sign_messages'] = Variable<bool>(signMessages);
    if (!nullToAbsent || linkedChatId != null) {
      map['linked_chat_id'] = Variable<String>(linkedChatId);
    }
    if (!nullToAbsent || myRole != null) {
      map['my_role'] = Variable<String>(myRole);
    }
    if (!nullToAbsent || lastMessageSenderId != null) {
      map['last_message_sender_id'] = Variable<String>(lastMessageSenderId);
    }
    if (!nullToAbsent || lastMessageSenderName != null) {
      map['last_message_sender_name'] = Variable<String>(lastMessageSenderName);
    }
    map['has_active_call'] = Variable<bool>(hasActiveCall);
    if (!nullToAbsent || chatPermissionsJson != null) {
      map['chat_permissions_json'] = Variable<String>(chatPermissionsJson);
    }
    if (!nullToAbsent || reactionSettingsJson != null) {
      map['reaction_settings_json'] = Variable<String>(reactionSettingsJson);
    }
    map['has_protected_content'] = Variable<bool>(hasProtectedContent);
    if (!nullToAbsent || pinnedMessageIdsJson != null) {
      map['pinned_message_ids_json'] = Variable<String>(pinnedMessageIdsJson);
    }
    map['message_auto_delete_time'] = Variable<int>(messageAutoDeleteTime);
    if (!nullToAbsent || appearanceJson != null) {
      map['appearance_json'] = Variable<String>(appearanceJson);
    }
    map['is_forum'] = Variable<bool>(isForum);
    map['participants_hidden'] = Variable<bool>(participantsHidden);
    map['has_aggressive_anti_spam_enabled'] =
        Variable<bool>(hasAggressiveAntiSpamEnabled);
    map['max_reactions_per_post'] = Variable<int>(maxReactionsPerPost);
    map['unread_mentions_count'] = Variable<int>(unreadMentionsCount);
    map['unread_reactions_count'] = Variable<int>(unreadReactionsCount);
    return map;
  }

  ChatsCompanion toCompanion(bool nullToAbsent) {
    return ChatsCompanion(
      chatId: Value(chatId),
      chatType: Value(chatType),
      name: Value(name),
      avatarUrl: avatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(avatarUrl),
      lastMessage: lastMessage == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessage),
      lastMessageTime: lastMessageTime == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageTime),
      updatedAt: Value(updatedAt),
      unreadCount: Value(unreadCount),
      isOnline: Value(isOnline),
      lastSeen: lastSeen == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeen),
      isPinned: Value(isPinned),
      lastMessageType: lastMessageType == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageType),
      lastMessageIsRound: Value(lastMessageIsRound),
      lastMessageFileUrl: lastMessageFileUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageFileUrl),
      lastMessageGroupedId: lastMessageGroupedId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageGroupedId),
      otherUserId: otherUserId == null && nullToAbsent
          ? const Value.absent()
          : Value(otherUserId),
      lastReadInboxMessageId: Value(lastReadInboxMessageId),
      lastReadOutboxMessageId: Value(lastReadOutboxMessageId),
      pinnedMessageId: pinnedMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(pinnedMessageId),
      username: username == null && nullToAbsent
          ? const Value.absent()
          : Value(username),
      isPublic: Value(isPublic),
      isBot: Value(isBot),
      isVerified: Value(isVerified),
      isArchived: Value(isArchived),
      peerCustomizationJson: peerCustomizationJson == null && nullToAbsent
          ? const Value.absent()
          : Value(peerCustomizationJson),
      showAuthorProfiles: Value(showAuthorProfiles),
      signMessages: Value(signMessages),
      linkedChatId: linkedChatId == null && nullToAbsent
          ? const Value.absent()
          : Value(linkedChatId),
      myRole:
          myRole == null && nullToAbsent ? const Value.absent() : Value(myRole),
      lastMessageSenderId: lastMessageSenderId == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageSenderId),
      lastMessageSenderName: lastMessageSenderName == null && nullToAbsent
          ? const Value.absent()
          : Value(lastMessageSenderName),
      hasActiveCall: Value(hasActiveCall),
      chatPermissionsJson: chatPermissionsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(chatPermissionsJson),
      reactionSettingsJson: reactionSettingsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(reactionSettingsJson),
      hasProtectedContent: Value(hasProtectedContent),
      pinnedMessageIdsJson: pinnedMessageIdsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(pinnedMessageIdsJson),
      messageAutoDeleteTime: Value(messageAutoDeleteTime),
      appearanceJson: appearanceJson == null && nullToAbsent
          ? const Value.absent()
          : Value(appearanceJson),
      isForum: Value(isForum),
      participantsHidden: Value(participantsHidden),
      hasAggressiveAntiSpamEnabled: Value(hasAggressiveAntiSpamEnabled),
      maxReactionsPerPost: Value(maxReactionsPerPost),
      unreadMentionsCount: Value(unreadMentionsCount),
      unreadReactionsCount: Value(unreadReactionsCount),
    );
  }

  factory DbChat.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbChat(
      chatId: serializer.fromJson<String>(json['chatId']),
      chatType: serializer.fromJson<String>(json['chatType']),
      name: serializer.fromJson<String>(json['name']),
      avatarUrl: serializer.fromJson<String?>(json['avatarUrl']),
      lastMessage: serializer.fromJson<String?>(json['lastMessage']),
      lastMessageTime: serializer.fromJson<String?>(json['lastMessageTime']),
      updatedAt: serializer.fromJson<String>(json['updatedAt']),
      unreadCount: serializer.fromJson<int>(json['unreadCount']),
      isOnline: serializer.fromJson<bool>(json['isOnline']),
      lastSeen: serializer.fromJson<String?>(json['lastSeen']),
      isPinned: serializer.fromJson<bool>(json['isPinned']),
      lastMessageType: serializer.fromJson<String?>(json['lastMessageType']),
      lastMessageIsRound: serializer.fromJson<bool>(json['lastMessageIsRound']),
      lastMessageFileUrl:
          serializer.fromJson<String?>(json['lastMessageFileUrl']),
      lastMessageGroupedId:
          serializer.fromJson<String?>(json['lastMessageGroupedId']),
      otherUserId: serializer.fromJson<String?>(json['otherUserId']),
      lastReadInboxMessageId:
          serializer.fromJson<int>(json['lastReadInboxMessageId']),
      lastReadOutboxMessageId:
          serializer.fromJson<int>(json['lastReadOutboxMessageId']),
      pinnedMessageId: serializer.fromJson<int?>(json['pinnedMessageId']),
      username: serializer.fromJson<String?>(json['username']),
      isPublic: serializer.fromJson<bool>(json['isPublic']),
      isBot: serializer.fromJson<bool>(json['isBot']),
      isVerified: serializer.fromJson<bool>(json['isVerified']),
      isArchived: serializer.fromJson<bool>(json['isArchived']),
      peerCustomizationJson:
          serializer.fromJson<String?>(json['peerCustomizationJson']),
      showAuthorProfiles: serializer.fromJson<bool>(json['showAuthorProfiles']),
      signMessages: serializer.fromJson<bool>(json['signMessages']),
      linkedChatId: serializer.fromJson<String?>(json['linkedChatId']),
      myRole: serializer.fromJson<String?>(json['myRole']),
      lastMessageSenderId:
          serializer.fromJson<String?>(json['lastMessageSenderId']),
      lastMessageSenderName:
          serializer.fromJson<String?>(json['lastMessageSenderName']),
      hasActiveCall: serializer.fromJson<bool>(json['hasActiveCall']),
      chatPermissionsJson:
          serializer.fromJson<String?>(json['chatPermissionsJson']),
      reactionSettingsJson:
          serializer.fromJson<String?>(json['reactionSettingsJson']),
      hasProtectedContent:
          serializer.fromJson<bool>(json['hasProtectedContent']),
      pinnedMessageIdsJson:
          serializer.fromJson<String?>(json['pinnedMessageIdsJson']),
      messageAutoDeleteTime:
          serializer.fromJson<int>(json['messageAutoDeleteTime']),
      appearanceJson: serializer.fromJson<String?>(json['appearanceJson']),
      isForum: serializer.fromJson<bool>(json['isForum']),
      participantsHidden: serializer.fromJson<bool>(json['participantsHidden']),
      hasAggressiveAntiSpamEnabled:
          serializer.fromJson<bool>(json['hasAggressiveAntiSpamEnabled']),
      maxReactionsPerPost:
          serializer.fromJson<int>(json['maxReactionsPerPost']),
      unreadMentionsCount:
          serializer.fromJson<int>(json['unreadMentionsCount']),
      unreadReactionsCount:
          serializer.fromJson<int>(json['unreadReactionsCount']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'chatId': serializer.toJson<String>(chatId),
      'chatType': serializer.toJson<String>(chatType),
      'name': serializer.toJson<String>(name),
      'avatarUrl': serializer.toJson<String?>(avatarUrl),
      'lastMessage': serializer.toJson<String?>(lastMessage),
      'lastMessageTime': serializer.toJson<String?>(lastMessageTime),
      'updatedAt': serializer.toJson<String>(updatedAt),
      'unreadCount': serializer.toJson<int>(unreadCount),
      'isOnline': serializer.toJson<bool>(isOnline),
      'lastSeen': serializer.toJson<String?>(lastSeen),
      'isPinned': serializer.toJson<bool>(isPinned),
      'lastMessageType': serializer.toJson<String?>(lastMessageType),
      'lastMessageIsRound': serializer.toJson<bool>(lastMessageIsRound),
      'lastMessageFileUrl': serializer.toJson<String?>(lastMessageFileUrl),
      'lastMessageGroupedId': serializer.toJson<String?>(lastMessageGroupedId),
      'otherUserId': serializer.toJson<String?>(otherUserId),
      'lastReadInboxMessageId': serializer.toJson<int>(lastReadInboxMessageId),
      'lastReadOutboxMessageId':
          serializer.toJson<int>(lastReadOutboxMessageId),
      'pinnedMessageId': serializer.toJson<int?>(pinnedMessageId),
      'username': serializer.toJson<String?>(username),
      'isPublic': serializer.toJson<bool>(isPublic),
      'isBot': serializer.toJson<bool>(isBot),
      'isVerified': serializer.toJson<bool>(isVerified),
      'isArchived': serializer.toJson<bool>(isArchived),
      'peerCustomizationJson':
          serializer.toJson<String?>(peerCustomizationJson),
      'showAuthorProfiles': serializer.toJson<bool>(showAuthorProfiles),
      'signMessages': serializer.toJson<bool>(signMessages),
      'linkedChatId': serializer.toJson<String?>(linkedChatId),
      'myRole': serializer.toJson<String?>(myRole),
      'lastMessageSenderId': serializer.toJson<String?>(lastMessageSenderId),
      'lastMessageSenderName':
          serializer.toJson<String?>(lastMessageSenderName),
      'hasActiveCall': serializer.toJson<bool>(hasActiveCall),
      'chatPermissionsJson': serializer.toJson<String?>(chatPermissionsJson),
      'reactionSettingsJson': serializer.toJson<String?>(reactionSettingsJson),
      'hasProtectedContent': serializer.toJson<bool>(hasProtectedContent),
      'pinnedMessageIdsJson': serializer.toJson<String?>(pinnedMessageIdsJson),
      'messageAutoDeleteTime': serializer.toJson<int>(messageAutoDeleteTime),
      'appearanceJson': serializer.toJson<String?>(appearanceJson),
      'isForum': serializer.toJson<bool>(isForum),
      'participantsHidden': serializer.toJson<bool>(participantsHidden),
      'hasAggressiveAntiSpamEnabled':
          serializer.toJson<bool>(hasAggressiveAntiSpamEnabled),
      'maxReactionsPerPost': serializer.toJson<int>(maxReactionsPerPost),
      'unreadMentionsCount': serializer.toJson<int>(unreadMentionsCount),
      'unreadReactionsCount': serializer.toJson<int>(unreadReactionsCount),
    };
  }

  DbChat copyWith(
          {String? chatId,
          String? chatType,
          String? name,
          Value<String?> avatarUrl = const Value.absent(),
          Value<String?> lastMessage = const Value.absent(),
          Value<String?> lastMessageTime = const Value.absent(),
          String? updatedAt,
          int? unreadCount,
          bool? isOnline,
          Value<String?> lastSeen = const Value.absent(),
          bool? isPinned,
          Value<String?> lastMessageType = const Value.absent(),
          bool? lastMessageIsRound,
          Value<String?> lastMessageFileUrl = const Value.absent(),
          Value<String?> lastMessageGroupedId = const Value.absent(),
          Value<String?> otherUserId = const Value.absent(),
          int? lastReadInboxMessageId,
          int? lastReadOutboxMessageId,
          Value<int?> pinnedMessageId = const Value.absent(),
          Value<String?> username = const Value.absent(),
          bool? isPublic,
          bool? isBot,
          bool? isVerified,
          bool? isArchived,
          Value<String?> peerCustomizationJson = const Value.absent(),
          bool? showAuthorProfiles,
          bool? signMessages,
          Value<String?> linkedChatId = const Value.absent(),
          Value<String?> myRole = const Value.absent(),
          Value<String?> lastMessageSenderId = const Value.absent(),
          Value<String?> lastMessageSenderName = const Value.absent(),
          bool? hasActiveCall,
          Value<String?> chatPermissionsJson = const Value.absent(),
          Value<String?> reactionSettingsJson = const Value.absent(),
          bool? hasProtectedContent,
          Value<String?> pinnedMessageIdsJson = const Value.absent(),
          int? messageAutoDeleteTime,
          Value<String?> appearanceJson = const Value.absent(),
          bool? isForum,
          bool? participantsHidden,
          bool? hasAggressiveAntiSpamEnabled,
          int? maxReactionsPerPost,
          int? unreadMentionsCount,
          int? unreadReactionsCount}) =>
      DbChat(
        chatId: chatId ?? this.chatId,
        chatType: chatType ?? this.chatType,
        name: name ?? this.name,
        avatarUrl: avatarUrl.present ? avatarUrl.value : this.avatarUrl,
        lastMessage: lastMessage.present ? lastMessage.value : this.lastMessage,
        lastMessageTime: lastMessageTime.present
            ? lastMessageTime.value
            : this.lastMessageTime,
        updatedAt: updatedAt ?? this.updatedAt,
        unreadCount: unreadCount ?? this.unreadCount,
        isOnline: isOnline ?? this.isOnline,
        lastSeen: lastSeen.present ? lastSeen.value : this.lastSeen,
        isPinned: isPinned ?? this.isPinned,
        lastMessageType: lastMessageType.present
            ? lastMessageType.value
            : this.lastMessageType,
        lastMessageIsRound: lastMessageIsRound ?? this.lastMessageIsRound,
        lastMessageFileUrl: lastMessageFileUrl.present
            ? lastMessageFileUrl.value
            : this.lastMessageFileUrl,
        lastMessageGroupedId: lastMessageGroupedId.present
            ? lastMessageGroupedId.value
            : this.lastMessageGroupedId,
        otherUserId: otherUserId.present ? otherUserId.value : this.otherUserId,
        lastReadInboxMessageId:
            lastReadInboxMessageId ?? this.lastReadInboxMessageId,
        lastReadOutboxMessageId:
            lastReadOutboxMessageId ?? this.lastReadOutboxMessageId,
        pinnedMessageId: pinnedMessageId.present
            ? pinnedMessageId.value
            : this.pinnedMessageId,
        username: username.present ? username.value : this.username,
        isPublic: isPublic ?? this.isPublic,
        isBot: isBot ?? this.isBot,
        isVerified: isVerified ?? this.isVerified,
        isArchived: isArchived ?? this.isArchived,
        peerCustomizationJson: peerCustomizationJson.present
            ? peerCustomizationJson.value
            : this.peerCustomizationJson,
        showAuthorProfiles: showAuthorProfiles ?? this.showAuthorProfiles,
        signMessages: signMessages ?? this.signMessages,
        linkedChatId:
            linkedChatId.present ? linkedChatId.value : this.linkedChatId,
        myRole: myRole.present ? myRole.value : this.myRole,
        lastMessageSenderId: lastMessageSenderId.present
            ? lastMessageSenderId.value
            : this.lastMessageSenderId,
        lastMessageSenderName: lastMessageSenderName.present
            ? lastMessageSenderName.value
            : this.lastMessageSenderName,
        hasActiveCall: hasActiveCall ?? this.hasActiveCall,
        chatPermissionsJson: chatPermissionsJson.present
            ? chatPermissionsJson.value
            : this.chatPermissionsJson,
        reactionSettingsJson: reactionSettingsJson.present
            ? reactionSettingsJson.value
            : this.reactionSettingsJson,
        hasProtectedContent: hasProtectedContent ?? this.hasProtectedContent,
        pinnedMessageIdsJson: pinnedMessageIdsJson.present
            ? pinnedMessageIdsJson.value
            : this.pinnedMessageIdsJson,
        messageAutoDeleteTime:
            messageAutoDeleteTime ?? this.messageAutoDeleteTime,
        appearanceJson:
            appearanceJson.present ? appearanceJson.value : this.appearanceJson,
        isForum: isForum ?? this.isForum,
        participantsHidden: participantsHidden ?? this.participantsHidden,
        hasAggressiveAntiSpamEnabled:
            hasAggressiveAntiSpamEnabled ?? this.hasAggressiveAntiSpamEnabled,
        maxReactionsPerPost: maxReactionsPerPost ?? this.maxReactionsPerPost,
        unreadMentionsCount: unreadMentionsCount ?? this.unreadMentionsCount,
        unreadReactionsCount: unreadReactionsCount ?? this.unreadReactionsCount,
      );
  DbChat copyWithCompanion(ChatsCompanion data) {
    return DbChat(
      chatId: data.chatId.present ? data.chatId.value : this.chatId,
      chatType: data.chatType.present ? data.chatType.value : this.chatType,
      name: data.name.present ? data.name.value : this.name,
      avatarUrl: data.avatarUrl.present ? data.avatarUrl.value : this.avatarUrl,
      lastMessage:
          data.lastMessage.present ? data.lastMessage.value : this.lastMessage,
      lastMessageTime: data.lastMessageTime.present
          ? data.lastMessageTime.value
          : this.lastMessageTime,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
      unreadCount:
          data.unreadCount.present ? data.unreadCount.value : this.unreadCount,
      isOnline: data.isOnline.present ? data.isOnline.value : this.isOnline,
      lastSeen: data.lastSeen.present ? data.lastSeen.value : this.lastSeen,
      isPinned: data.isPinned.present ? data.isPinned.value : this.isPinned,
      lastMessageType: data.lastMessageType.present
          ? data.lastMessageType.value
          : this.lastMessageType,
      lastMessageIsRound: data.lastMessageIsRound.present
          ? data.lastMessageIsRound.value
          : this.lastMessageIsRound,
      lastMessageFileUrl: data.lastMessageFileUrl.present
          ? data.lastMessageFileUrl.value
          : this.lastMessageFileUrl,
      lastMessageGroupedId: data.lastMessageGroupedId.present
          ? data.lastMessageGroupedId.value
          : this.lastMessageGroupedId,
      otherUserId:
          data.otherUserId.present ? data.otherUserId.value : this.otherUserId,
      lastReadInboxMessageId: data.lastReadInboxMessageId.present
          ? data.lastReadInboxMessageId.value
          : this.lastReadInboxMessageId,
      lastReadOutboxMessageId: data.lastReadOutboxMessageId.present
          ? data.lastReadOutboxMessageId.value
          : this.lastReadOutboxMessageId,
      pinnedMessageId: data.pinnedMessageId.present
          ? data.pinnedMessageId.value
          : this.pinnedMessageId,
      username: data.username.present ? data.username.value : this.username,
      isPublic: data.isPublic.present ? data.isPublic.value : this.isPublic,
      isBot: data.isBot.present ? data.isBot.value : this.isBot,
      isVerified:
          data.isVerified.present ? data.isVerified.value : this.isVerified,
      isArchived:
          data.isArchived.present ? data.isArchived.value : this.isArchived,
      peerCustomizationJson: data.peerCustomizationJson.present
          ? data.peerCustomizationJson.value
          : this.peerCustomizationJson,
      showAuthorProfiles: data.showAuthorProfiles.present
          ? data.showAuthorProfiles.value
          : this.showAuthorProfiles,
      signMessages: data.signMessages.present
          ? data.signMessages.value
          : this.signMessages,
      linkedChatId: data.linkedChatId.present
          ? data.linkedChatId.value
          : this.linkedChatId,
      myRole: data.myRole.present ? data.myRole.value : this.myRole,
      lastMessageSenderId: data.lastMessageSenderId.present
          ? data.lastMessageSenderId.value
          : this.lastMessageSenderId,
      lastMessageSenderName: data.lastMessageSenderName.present
          ? data.lastMessageSenderName.value
          : this.lastMessageSenderName,
      hasActiveCall: data.hasActiveCall.present
          ? data.hasActiveCall.value
          : this.hasActiveCall,
      chatPermissionsJson: data.chatPermissionsJson.present
          ? data.chatPermissionsJson.value
          : this.chatPermissionsJson,
      reactionSettingsJson: data.reactionSettingsJson.present
          ? data.reactionSettingsJson.value
          : this.reactionSettingsJson,
      hasProtectedContent: data.hasProtectedContent.present
          ? data.hasProtectedContent.value
          : this.hasProtectedContent,
      pinnedMessageIdsJson: data.pinnedMessageIdsJson.present
          ? data.pinnedMessageIdsJson.value
          : this.pinnedMessageIdsJson,
      messageAutoDeleteTime: data.messageAutoDeleteTime.present
          ? data.messageAutoDeleteTime.value
          : this.messageAutoDeleteTime,
      appearanceJson: data.appearanceJson.present
          ? data.appearanceJson.value
          : this.appearanceJson,
      isForum: data.isForum.present ? data.isForum.value : this.isForum,
      participantsHidden: data.participantsHidden.present
          ? data.participantsHidden.value
          : this.participantsHidden,
      hasAggressiveAntiSpamEnabled: data.hasAggressiveAntiSpamEnabled.present
          ? data.hasAggressiveAntiSpamEnabled.value
          : this.hasAggressiveAntiSpamEnabled,
      maxReactionsPerPost: data.maxReactionsPerPost.present
          ? data.maxReactionsPerPost.value
          : this.maxReactionsPerPost,
      unreadMentionsCount: data.unreadMentionsCount.present
          ? data.unreadMentionsCount.value
          : this.unreadMentionsCount,
      unreadReactionsCount: data.unreadReactionsCount.present
          ? data.unreadReactionsCount.value
          : this.unreadReactionsCount,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbChat(')
          ..write('chatId: $chatId, ')
          ..write('chatType: $chatType, ')
          ..write('name: $name, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('lastMessage: $lastMessage, ')
          ..write('lastMessageTime: $lastMessageTime, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('isOnline: $isOnline, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('isPinned: $isPinned, ')
          ..write('lastMessageType: $lastMessageType, ')
          ..write('lastMessageIsRound: $lastMessageIsRound, ')
          ..write('lastMessageFileUrl: $lastMessageFileUrl, ')
          ..write('lastMessageGroupedId: $lastMessageGroupedId, ')
          ..write('otherUserId: $otherUserId, ')
          ..write('lastReadInboxMessageId: $lastReadInboxMessageId, ')
          ..write('lastReadOutboxMessageId: $lastReadOutboxMessageId, ')
          ..write('pinnedMessageId: $pinnedMessageId, ')
          ..write('username: $username, ')
          ..write('isPublic: $isPublic, ')
          ..write('isBot: $isBot, ')
          ..write('isVerified: $isVerified, ')
          ..write('isArchived: $isArchived, ')
          ..write('peerCustomizationJson: $peerCustomizationJson, ')
          ..write('showAuthorProfiles: $showAuthorProfiles, ')
          ..write('signMessages: $signMessages, ')
          ..write('linkedChatId: $linkedChatId, ')
          ..write('myRole: $myRole, ')
          ..write('lastMessageSenderId: $lastMessageSenderId, ')
          ..write('lastMessageSenderName: $lastMessageSenderName, ')
          ..write('hasActiveCall: $hasActiveCall, ')
          ..write('chatPermissionsJson: $chatPermissionsJson, ')
          ..write('reactionSettingsJson: $reactionSettingsJson, ')
          ..write('hasProtectedContent: $hasProtectedContent, ')
          ..write('pinnedMessageIdsJson: $pinnedMessageIdsJson, ')
          ..write('messageAutoDeleteTime: $messageAutoDeleteTime, ')
          ..write('appearanceJson: $appearanceJson, ')
          ..write('isForum: $isForum, ')
          ..write('participantsHidden: $participantsHidden, ')
          ..write(
              'hasAggressiveAntiSpamEnabled: $hasAggressiveAntiSpamEnabled, ')
          ..write('maxReactionsPerPost: $maxReactionsPerPost, ')
          ..write('unreadMentionsCount: $unreadMentionsCount, ')
          ..write('unreadReactionsCount: $unreadReactionsCount')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        chatId,
        chatType,
        name,
        avatarUrl,
        lastMessage,
        lastMessageTime,
        updatedAt,
        unreadCount,
        isOnline,
        lastSeen,
        isPinned,
        lastMessageType,
        lastMessageIsRound,
        lastMessageFileUrl,
        lastMessageGroupedId,
        otherUserId,
        lastReadInboxMessageId,
        lastReadOutboxMessageId,
        pinnedMessageId,
        username,
        isPublic,
        isBot,
        isVerified,
        isArchived,
        peerCustomizationJson,
        showAuthorProfiles,
        signMessages,
        linkedChatId,
        myRole,
        lastMessageSenderId,
        lastMessageSenderName,
        hasActiveCall,
        chatPermissionsJson,
        reactionSettingsJson,
        hasProtectedContent,
        pinnedMessageIdsJson,
        messageAutoDeleteTime,
        appearanceJson,
        isForum,
        participantsHidden,
        hasAggressiveAntiSpamEnabled,
        maxReactionsPerPost,
        unreadMentionsCount,
        unreadReactionsCount
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbChat &&
          other.chatId == this.chatId &&
          other.chatType == this.chatType &&
          other.name == this.name &&
          other.avatarUrl == this.avatarUrl &&
          other.lastMessage == this.lastMessage &&
          other.lastMessageTime == this.lastMessageTime &&
          other.updatedAt == this.updatedAt &&
          other.unreadCount == this.unreadCount &&
          other.isOnline == this.isOnline &&
          other.lastSeen == this.lastSeen &&
          other.isPinned == this.isPinned &&
          other.lastMessageType == this.lastMessageType &&
          other.lastMessageIsRound == this.lastMessageIsRound &&
          other.lastMessageFileUrl == this.lastMessageFileUrl &&
          other.lastMessageGroupedId == this.lastMessageGroupedId &&
          other.otherUserId == this.otherUserId &&
          other.lastReadInboxMessageId == this.lastReadInboxMessageId &&
          other.lastReadOutboxMessageId == this.lastReadOutboxMessageId &&
          other.pinnedMessageId == this.pinnedMessageId &&
          other.username == this.username &&
          other.isPublic == this.isPublic &&
          other.isBot == this.isBot &&
          other.isVerified == this.isVerified &&
          other.isArchived == this.isArchived &&
          other.peerCustomizationJson == this.peerCustomizationJson &&
          other.showAuthorProfiles == this.showAuthorProfiles &&
          other.signMessages == this.signMessages &&
          other.linkedChatId == this.linkedChatId &&
          other.myRole == this.myRole &&
          other.lastMessageSenderId == this.lastMessageSenderId &&
          other.lastMessageSenderName == this.lastMessageSenderName &&
          other.hasActiveCall == this.hasActiveCall &&
          other.chatPermissionsJson == this.chatPermissionsJson &&
          other.reactionSettingsJson == this.reactionSettingsJson &&
          other.hasProtectedContent == this.hasProtectedContent &&
          other.pinnedMessageIdsJson == this.pinnedMessageIdsJson &&
          other.messageAutoDeleteTime == this.messageAutoDeleteTime &&
          other.appearanceJson == this.appearanceJson &&
          other.isForum == this.isForum &&
          other.participantsHidden == this.participantsHidden &&
          other.hasAggressiveAntiSpamEnabled ==
              this.hasAggressiveAntiSpamEnabled &&
          other.maxReactionsPerPost == this.maxReactionsPerPost &&
          other.unreadMentionsCount == this.unreadMentionsCount &&
          other.unreadReactionsCount == this.unreadReactionsCount);
}

class ChatsCompanion extends UpdateCompanion<DbChat> {
  final Value<String> chatId;
  final Value<String> chatType;
  final Value<String> name;
  final Value<String?> avatarUrl;
  final Value<String?> lastMessage;
  final Value<String?> lastMessageTime;
  final Value<String> updatedAt;
  final Value<int> unreadCount;
  final Value<bool> isOnline;
  final Value<String?> lastSeen;
  final Value<bool> isPinned;
  final Value<String?> lastMessageType;
  final Value<bool> lastMessageIsRound;
  final Value<String?> lastMessageFileUrl;
  final Value<String?> lastMessageGroupedId;
  final Value<String?> otherUserId;
  final Value<int> lastReadInboxMessageId;
  final Value<int> lastReadOutboxMessageId;
  final Value<int?> pinnedMessageId;
  final Value<String?> username;
  final Value<bool> isPublic;
  final Value<bool> isBot;
  final Value<bool> isVerified;
  final Value<bool> isArchived;
  final Value<String?> peerCustomizationJson;
  final Value<bool> showAuthorProfiles;
  final Value<bool> signMessages;
  final Value<String?> linkedChatId;
  final Value<String?> myRole;
  final Value<String?> lastMessageSenderId;
  final Value<String?> lastMessageSenderName;
  final Value<bool> hasActiveCall;
  final Value<String?> chatPermissionsJson;
  final Value<String?> reactionSettingsJson;
  final Value<bool> hasProtectedContent;
  final Value<String?> pinnedMessageIdsJson;
  final Value<int> messageAutoDeleteTime;
  final Value<String?> appearanceJson;
  final Value<bool> isForum;
  final Value<bool> participantsHidden;
  final Value<bool> hasAggressiveAntiSpamEnabled;
  final Value<int> maxReactionsPerPost;
  final Value<int> unreadMentionsCount;
  final Value<int> unreadReactionsCount;
  final Value<int> rowid;
  const ChatsCompanion({
    this.chatId = const Value.absent(),
    this.chatType = const Value.absent(),
    this.name = const Value.absent(),
    this.avatarUrl = const Value.absent(),
    this.lastMessage = const Value.absent(),
    this.lastMessageTime = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.unreadCount = const Value.absent(),
    this.isOnline = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.lastMessageType = const Value.absent(),
    this.lastMessageIsRound = const Value.absent(),
    this.lastMessageFileUrl = const Value.absent(),
    this.lastMessageGroupedId = const Value.absent(),
    this.otherUserId = const Value.absent(),
    this.lastReadInboxMessageId = const Value.absent(),
    this.lastReadOutboxMessageId = const Value.absent(),
    this.pinnedMessageId = const Value.absent(),
    this.username = const Value.absent(),
    this.isPublic = const Value.absent(),
    this.isBot = const Value.absent(),
    this.isVerified = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.peerCustomizationJson = const Value.absent(),
    this.showAuthorProfiles = const Value.absent(),
    this.signMessages = const Value.absent(),
    this.linkedChatId = const Value.absent(),
    this.myRole = const Value.absent(),
    this.lastMessageSenderId = const Value.absent(),
    this.lastMessageSenderName = const Value.absent(),
    this.hasActiveCall = const Value.absent(),
    this.chatPermissionsJson = const Value.absent(),
    this.reactionSettingsJson = const Value.absent(),
    this.hasProtectedContent = const Value.absent(),
    this.pinnedMessageIdsJson = const Value.absent(),
    this.messageAutoDeleteTime = const Value.absent(),
    this.appearanceJson = const Value.absent(),
    this.isForum = const Value.absent(),
    this.participantsHidden = const Value.absent(),
    this.hasAggressiveAntiSpamEnabled = const Value.absent(),
    this.maxReactionsPerPost = const Value.absent(),
    this.unreadMentionsCount = const Value.absent(),
    this.unreadReactionsCount = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ChatsCompanion.insert({
    required String chatId,
    required String chatType,
    required String name,
    this.avatarUrl = const Value.absent(),
    this.lastMessage = const Value.absent(),
    this.lastMessageTime = const Value.absent(),
    required String updatedAt,
    this.unreadCount = const Value.absent(),
    this.isOnline = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.isPinned = const Value.absent(),
    this.lastMessageType = const Value.absent(),
    this.lastMessageIsRound = const Value.absent(),
    this.lastMessageFileUrl = const Value.absent(),
    this.lastMessageGroupedId = const Value.absent(),
    this.otherUserId = const Value.absent(),
    this.lastReadInboxMessageId = const Value.absent(),
    this.lastReadOutboxMessageId = const Value.absent(),
    this.pinnedMessageId = const Value.absent(),
    this.username = const Value.absent(),
    this.isPublic = const Value.absent(),
    this.isBot = const Value.absent(),
    this.isVerified = const Value.absent(),
    this.isArchived = const Value.absent(),
    this.peerCustomizationJson = const Value.absent(),
    this.showAuthorProfiles = const Value.absent(),
    this.signMessages = const Value.absent(),
    this.linkedChatId = const Value.absent(),
    this.myRole = const Value.absent(),
    this.lastMessageSenderId = const Value.absent(),
    this.lastMessageSenderName = const Value.absent(),
    this.hasActiveCall = const Value.absent(),
    this.chatPermissionsJson = const Value.absent(),
    this.reactionSettingsJson = const Value.absent(),
    this.hasProtectedContent = const Value.absent(),
    this.pinnedMessageIdsJson = const Value.absent(),
    this.messageAutoDeleteTime = const Value.absent(),
    this.appearanceJson = const Value.absent(),
    this.isForum = const Value.absent(),
    this.participantsHidden = const Value.absent(),
    this.hasAggressiveAntiSpamEnabled = const Value.absent(),
    this.maxReactionsPerPost = const Value.absent(),
    this.unreadMentionsCount = const Value.absent(),
    this.unreadReactionsCount = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : chatId = Value(chatId),
        chatType = Value(chatType),
        name = Value(name),
        updatedAt = Value(updatedAt);
  static Insertable<DbChat> custom({
    Expression<String>? chatId,
    Expression<String>? chatType,
    Expression<String>? name,
    Expression<String>? avatarUrl,
    Expression<String>? lastMessage,
    Expression<String>? lastMessageTime,
    Expression<String>? updatedAt,
    Expression<int>? unreadCount,
    Expression<bool>? isOnline,
    Expression<String>? lastSeen,
    Expression<bool>? isPinned,
    Expression<String>? lastMessageType,
    Expression<bool>? lastMessageIsRound,
    Expression<String>? lastMessageFileUrl,
    Expression<String>? lastMessageGroupedId,
    Expression<String>? otherUserId,
    Expression<int>? lastReadInboxMessageId,
    Expression<int>? lastReadOutboxMessageId,
    Expression<int>? pinnedMessageId,
    Expression<String>? username,
    Expression<bool>? isPublic,
    Expression<bool>? isBot,
    Expression<bool>? isVerified,
    Expression<bool>? isArchived,
    Expression<String>? peerCustomizationJson,
    Expression<bool>? showAuthorProfiles,
    Expression<bool>? signMessages,
    Expression<String>? linkedChatId,
    Expression<String>? myRole,
    Expression<String>? lastMessageSenderId,
    Expression<String>? lastMessageSenderName,
    Expression<bool>? hasActiveCall,
    Expression<String>? chatPermissionsJson,
    Expression<String>? reactionSettingsJson,
    Expression<bool>? hasProtectedContent,
    Expression<String>? pinnedMessageIdsJson,
    Expression<int>? messageAutoDeleteTime,
    Expression<String>? appearanceJson,
    Expression<bool>? isForum,
    Expression<bool>? participantsHidden,
    Expression<bool>? hasAggressiveAntiSpamEnabled,
    Expression<int>? maxReactionsPerPost,
    Expression<int>? unreadMentionsCount,
    Expression<int>? unreadReactionsCount,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (chatId != null) 'chat_id': chatId,
      if (chatType != null) 'chat_type': chatType,
      if (name != null) 'name': name,
      if (avatarUrl != null) 'avatar_url': avatarUrl,
      if (lastMessage != null) 'last_message': lastMessage,
      if (lastMessageTime != null) 'last_message_time': lastMessageTime,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (unreadCount != null) 'unread_count': unreadCount,
      if (isOnline != null) 'is_online': isOnline,
      if (lastSeen != null) 'last_seen': lastSeen,
      if (isPinned != null) 'is_pinned': isPinned,
      if (lastMessageType != null) 'last_message_type': lastMessageType,
      if (lastMessageIsRound != null)
        'last_message_is_round': lastMessageIsRound,
      if (lastMessageFileUrl != null)
        'last_message_file_url': lastMessageFileUrl,
      if (lastMessageGroupedId != null)
        'last_message_grouped_id': lastMessageGroupedId,
      if (otherUserId != null) 'other_user_id': otherUserId,
      if (lastReadInboxMessageId != null)
        'last_read_inbox_message_id': lastReadInboxMessageId,
      if (lastReadOutboxMessageId != null)
        'last_read_outbox_message_id': lastReadOutboxMessageId,
      if (pinnedMessageId != null) 'pinned_message_id': pinnedMessageId,
      if (username != null) 'username': username,
      if (isPublic != null) 'is_public': isPublic,
      if (isBot != null) 'is_bot': isBot,
      if (isVerified != null) 'is_verified': isVerified,
      if (isArchived != null) 'is_archived': isArchived,
      if (peerCustomizationJson != null)
        'peer_customization_json': peerCustomizationJson,
      if (showAuthorProfiles != null)
        'show_author_profiles': showAuthorProfiles,
      if (signMessages != null) 'sign_messages': signMessages,
      if (linkedChatId != null) 'linked_chat_id': linkedChatId,
      if (myRole != null) 'my_role': myRole,
      if (lastMessageSenderId != null)
        'last_message_sender_id': lastMessageSenderId,
      if (lastMessageSenderName != null)
        'last_message_sender_name': lastMessageSenderName,
      if (hasActiveCall != null) 'has_active_call': hasActiveCall,
      if (chatPermissionsJson != null)
        'chat_permissions_json': chatPermissionsJson,
      if (reactionSettingsJson != null)
        'reaction_settings_json': reactionSettingsJson,
      if (hasProtectedContent != null)
        'has_protected_content': hasProtectedContent,
      if (pinnedMessageIdsJson != null)
        'pinned_message_ids_json': pinnedMessageIdsJson,
      if (messageAutoDeleteTime != null)
        'message_auto_delete_time': messageAutoDeleteTime,
      if (appearanceJson != null) 'appearance_json': appearanceJson,
      if (isForum != null) 'is_forum': isForum,
      if (participantsHidden != null) 'participants_hidden': participantsHidden,
      if (hasAggressiveAntiSpamEnabled != null)
        'has_aggressive_anti_spam_enabled': hasAggressiveAntiSpamEnabled,
      if (maxReactionsPerPost != null)
        'max_reactions_per_post': maxReactionsPerPost,
      if (unreadMentionsCount != null)
        'unread_mentions_count': unreadMentionsCount,
      if (unreadReactionsCount != null)
        'unread_reactions_count': unreadReactionsCount,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ChatsCompanion copyWith(
      {Value<String>? chatId,
      Value<String>? chatType,
      Value<String>? name,
      Value<String?>? avatarUrl,
      Value<String?>? lastMessage,
      Value<String?>? lastMessageTime,
      Value<String>? updatedAt,
      Value<int>? unreadCount,
      Value<bool>? isOnline,
      Value<String?>? lastSeen,
      Value<bool>? isPinned,
      Value<String?>? lastMessageType,
      Value<bool>? lastMessageIsRound,
      Value<String?>? lastMessageFileUrl,
      Value<String?>? lastMessageGroupedId,
      Value<String?>? otherUserId,
      Value<int>? lastReadInboxMessageId,
      Value<int>? lastReadOutboxMessageId,
      Value<int?>? pinnedMessageId,
      Value<String?>? username,
      Value<bool>? isPublic,
      Value<bool>? isBot,
      Value<bool>? isVerified,
      Value<bool>? isArchived,
      Value<String?>? peerCustomizationJson,
      Value<bool>? showAuthorProfiles,
      Value<bool>? signMessages,
      Value<String?>? linkedChatId,
      Value<String?>? myRole,
      Value<String?>? lastMessageSenderId,
      Value<String?>? lastMessageSenderName,
      Value<bool>? hasActiveCall,
      Value<String?>? chatPermissionsJson,
      Value<String?>? reactionSettingsJson,
      Value<bool>? hasProtectedContent,
      Value<String?>? pinnedMessageIdsJson,
      Value<int>? messageAutoDeleteTime,
      Value<String?>? appearanceJson,
      Value<bool>? isForum,
      Value<bool>? participantsHidden,
      Value<bool>? hasAggressiveAntiSpamEnabled,
      Value<int>? maxReactionsPerPost,
      Value<int>? unreadMentionsCount,
      Value<int>? unreadReactionsCount,
      Value<int>? rowid}) {
    return ChatsCompanion(
      chatId: chatId ?? this.chatId,
      chatType: chatType ?? this.chatType,
      name: name ?? this.name,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      lastMessage: lastMessage ?? this.lastMessage,
      lastMessageTime: lastMessageTime ?? this.lastMessageTime,
      updatedAt: updatedAt ?? this.updatedAt,
      unreadCount: unreadCount ?? this.unreadCount,
      isOnline: isOnline ?? this.isOnline,
      lastSeen: lastSeen ?? this.lastSeen,
      isPinned: isPinned ?? this.isPinned,
      lastMessageType: lastMessageType ?? this.lastMessageType,
      lastMessageIsRound: lastMessageIsRound ?? this.lastMessageIsRound,
      lastMessageFileUrl: lastMessageFileUrl ?? this.lastMessageFileUrl,
      lastMessageGroupedId: lastMessageGroupedId ?? this.lastMessageGroupedId,
      otherUserId: otherUserId ?? this.otherUserId,
      lastReadInboxMessageId:
          lastReadInboxMessageId ?? this.lastReadInboxMessageId,
      lastReadOutboxMessageId:
          lastReadOutboxMessageId ?? this.lastReadOutboxMessageId,
      pinnedMessageId: pinnedMessageId ?? this.pinnedMessageId,
      username: username ?? this.username,
      isPublic: isPublic ?? this.isPublic,
      isBot: isBot ?? this.isBot,
      isVerified: isVerified ?? this.isVerified,
      isArchived: isArchived ?? this.isArchived,
      peerCustomizationJson:
          peerCustomizationJson ?? this.peerCustomizationJson,
      showAuthorProfiles: showAuthorProfiles ?? this.showAuthorProfiles,
      signMessages: signMessages ?? this.signMessages,
      linkedChatId: linkedChatId ?? this.linkedChatId,
      myRole: myRole ?? this.myRole,
      lastMessageSenderId: lastMessageSenderId ?? this.lastMessageSenderId,
      lastMessageSenderName:
          lastMessageSenderName ?? this.lastMessageSenderName,
      hasActiveCall: hasActiveCall ?? this.hasActiveCall,
      chatPermissionsJson: chatPermissionsJson ?? this.chatPermissionsJson,
      reactionSettingsJson: reactionSettingsJson ?? this.reactionSettingsJson,
      hasProtectedContent: hasProtectedContent ?? this.hasProtectedContent,
      pinnedMessageIdsJson: pinnedMessageIdsJson ?? this.pinnedMessageIdsJson,
      messageAutoDeleteTime:
          messageAutoDeleteTime ?? this.messageAutoDeleteTime,
      appearanceJson: appearanceJson ?? this.appearanceJson,
      isForum: isForum ?? this.isForum,
      participantsHidden: participantsHidden ?? this.participantsHidden,
      hasAggressiveAntiSpamEnabled:
          hasAggressiveAntiSpamEnabled ?? this.hasAggressiveAntiSpamEnabled,
      maxReactionsPerPost: maxReactionsPerPost ?? this.maxReactionsPerPost,
      unreadMentionsCount: unreadMentionsCount ?? this.unreadMentionsCount,
      unreadReactionsCount: unreadReactionsCount ?? this.unreadReactionsCount,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (chatId.present) {
      map['chat_id'] = Variable<String>(chatId.value);
    }
    if (chatType.present) {
      map['chat_type'] = Variable<String>(chatType.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (avatarUrl.present) {
      map['avatar_url'] = Variable<String>(avatarUrl.value);
    }
    if (lastMessage.present) {
      map['last_message'] = Variable<String>(lastMessage.value);
    }
    if (lastMessageTime.present) {
      map['last_message_time'] = Variable<String>(lastMessageTime.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<String>(updatedAt.value);
    }
    if (unreadCount.present) {
      map['unread_count'] = Variable<int>(unreadCount.value);
    }
    if (isOnline.present) {
      map['is_online'] = Variable<bool>(isOnline.value);
    }
    if (lastSeen.present) {
      map['last_seen'] = Variable<String>(lastSeen.value);
    }
    if (isPinned.present) {
      map['is_pinned'] = Variable<bool>(isPinned.value);
    }
    if (lastMessageType.present) {
      map['last_message_type'] = Variable<String>(lastMessageType.value);
    }
    if (lastMessageIsRound.present) {
      map['last_message_is_round'] = Variable<bool>(lastMessageIsRound.value);
    }
    if (lastMessageFileUrl.present) {
      map['last_message_file_url'] = Variable<String>(lastMessageFileUrl.value);
    }
    if (lastMessageGroupedId.present) {
      map['last_message_grouped_id'] =
          Variable<String>(lastMessageGroupedId.value);
    }
    if (otherUserId.present) {
      map['other_user_id'] = Variable<String>(otherUserId.value);
    }
    if (lastReadInboxMessageId.present) {
      map['last_read_inbox_message_id'] =
          Variable<int>(lastReadInboxMessageId.value);
    }
    if (lastReadOutboxMessageId.present) {
      map['last_read_outbox_message_id'] =
          Variable<int>(lastReadOutboxMessageId.value);
    }
    if (pinnedMessageId.present) {
      map['pinned_message_id'] = Variable<int>(pinnedMessageId.value);
    }
    if (username.present) {
      map['username'] = Variable<String>(username.value);
    }
    if (isPublic.present) {
      map['is_public'] = Variable<bool>(isPublic.value);
    }
    if (isBot.present) {
      map['is_bot'] = Variable<bool>(isBot.value);
    }
    if (isVerified.present) {
      map['is_verified'] = Variable<bool>(isVerified.value);
    }
    if (isArchived.present) {
      map['is_archived'] = Variable<bool>(isArchived.value);
    }
    if (peerCustomizationJson.present) {
      map['peer_customization_json'] =
          Variable<String>(peerCustomizationJson.value);
    }
    if (showAuthorProfiles.present) {
      map['show_author_profiles'] = Variable<bool>(showAuthorProfiles.value);
    }
    if (signMessages.present) {
      map['sign_messages'] = Variable<bool>(signMessages.value);
    }
    if (linkedChatId.present) {
      map['linked_chat_id'] = Variable<String>(linkedChatId.value);
    }
    if (myRole.present) {
      map['my_role'] = Variable<String>(myRole.value);
    }
    if (lastMessageSenderId.present) {
      map['last_message_sender_id'] =
          Variable<String>(lastMessageSenderId.value);
    }
    if (lastMessageSenderName.present) {
      map['last_message_sender_name'] =
          Variable<String>(lastMessageSenderName.value);
    }
    if (hasActiveCall.present) {
      map['has_active_call'] = Variable<bool>(hasActiveCall.value);
    }
    if (chatPermissionsJson.present) {
      map['chat_permissions_json'] =
          Variable<String>(chatPermissionsJson.value);
    }
    if (reactionSettingsJson.present) {
      map['reaction_settings_json'] =
          Variable<String>(reactionSettingsJson.value);
    }
    if (hasProtectedContent.present) {
      map['has_protected_content'] = Variable<bool>(hasProtectedContent.value);
    }
    if (pinnedMessageIdsJson.present) {
      map['pinned_message_ids_json'] =
          Variable<String>(pinnedMessageIdsJson.value);
    }
    if (messageAutoDeleteTime.present) {
      map['message_auto_delete_time'] =
          Variable<int>(messageAutoDeleteTime.value);
    }
    if (appearanceJson.present) {
      map['appearance_json'] = Variable<String>(appearanceJson.value);
    }
    if (isForum.present) {
      map['is_forum'] = Variable<bool>(isForum.value);
    }
    if (participantsHidden.present) {
      map['participants_hidden'] = Variable<bool>(participantsHidden.value);
    }
    if (hasAggressiveAntiSpamEnabled.present) {
      map['has_aggressive_anti_spam_enabled'] =
          Variable<bool>(hasAggressiveAntiSpamEnabled.value);
    }
    if (maxReactionsPerPost.present) {
      map['max_reactions_per_post'] = Variable<int>(maxReactionsPerPost.value);
    }
    if (unreadMentionsCount.present) {
      map['unread_mentions_count'] = Variable<int>(unreadMentionsCount.value);
    }
    if (unreadReactionsCount.present) {
      map['unread_reactions_count'] = Variable<int>(unreadReactionsCount.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ChatsCompanion(')
          ..write('chatId: $chatId, ')
          ..write('chatType: $chatType, ')
          ..write('name: $name, ')
          ..write('avatarUrl: $avatarUrl, ')
          ..write('lastMessage: $lastMessage, ')
          ..write('lastMessageTime: $lastMessageTime, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('unreadCount: $unreadCount, ')
          ..write('isOnline: $isOnline, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('isPinned: $isPinned, ')
          ..write('lastMessageType: $lastMessageType, ')
          ..write('lastMessageIsRound: $lastMessageIsRound, ')
          ..write('lastMessageFileUrl: $lastMessageFileUrl, ')
          ..write('lastMessageGroupedId: $lastMessageGroupedId, ')
          ..write('otherUserId: $otherUserId, ')
          ..write('lastReadInboxMessageId: $lastReadInboxMessageId, ')
          ..write('lastReadOutboxMessageId: $lastReadOutboxMessageId, ')
          ..write('pinnedMessageId: $pinnedMessageId, ')
          ..write('username: $username, ')
          ..write('isPublic: $isPublic, ')
          ..write('isBot: $isBot, ')
          ..write('isVerified: $isVerified, ')
          ..write('isArchived: $isArchived, ')
          ..write('peerCustomizationJson: $peerCustomizationJson, ')
          ..write('showAuthorProfiles: $showAuthorProfiles, ')
          ..write('signMessages: $signMessages, ')
          ..write('linkedChatId: $linkedChatId, ')
          ..write('myRole: $myRole, ')
          ..write('lastMessageSenderId: $lastMessageSenderId, ')
          ..write('lastMessageSenderName: $lastMessageSenderName, ')
          ..write('hasActiveCall: $hasActiveCall, ')
          ..write('chatPermissionsJson: $chatPermissionsJson, ')
          ..write('reactionSettingsJson: $reactionSettingsJson, ')
          ..write('hasProtectedContent: $hasProtectedContent, ')
          ..write('pinnedMessageIdsJson: $pinnedMessageIdsJson, ')
          ..write('messageAutoDeleteTime: $messageAutoDeleteTime, ')
          ..write('appearanceJson: $appearanceJson, ')
          ..write('isForum: $isForum, ')
          ..write('participantsHidden: $participantsHidden, ')
          ..write(
              'hasAggressiveAntiSpamEnabled: $hasAggressiveAntiSpamEnabled, ')
          ..write('maxReactionsPerPost: $maxReactionsPerPost, ')
          ..write('unreadMentionsCount: $unreadMentionsCount, ')
          ..write('unreadReactionsCount: $unreadReactionsCount, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MessagesTable extends Messages
    with TableInfo<$MessagesTable, DbMessage> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MessagesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _localIdMeta =
      const VerificationMeta('localId');
  @override
  late final GeneratedColumn<String> localId = GeneratedColumn<String>(
      'local_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _serverIdMeta =
      const VerificationMeta('serverId');
  @override
  late final GeneratedColumn<String> serverId = GeneratedColumn<String>(
      'server_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _chatIdMeta = const VerificationMeta('chatId');
  @override
  late final GeneratedColumn<String> chatId = GeneratedColumn<String>(
      'chat_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _senderIdMeta =
      const VerificationMeta('senderId');
  @override
  late final GeneratedColumn<String> senderId = GeneratedColumn<String>(
      'sender_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _contentMeta =
      const VerificationMeta('content');
  @override
  late final GeneratedColumn<String> content = GeneratedColumn<String>(
      'content', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _messageTypeMeta =
      const VerificationMeta('messageType');
  @override
  late final GeneratedColumn<String> messageType = GeneratedColumn<String>(
      'message_type', aliasedName, false,
      type: DriftSqlType.string,
      requiredDuringInsert: false,
      defaultValue: const Constant('text'));
  static const VerificationMeta _fileUrlMeta =
      const VerificationMeta('fileUrl');
  @override
  late final GeneratedColumn<String> fileUrl = GeneratedColumn<String>(
      'file_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _fileNameMeta =
      const VerificationMeta('fileName');
  @override
  late final GeneratedColumn<String> fileName = GeneratedColumn<String>(
      'file_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _replyToMessageIdMeta =
      const VerificationMeta('replyToMessageId');
  @override
  late final GeneratedColumn<String> replyToMessageId = GeneratedColumn<String>(
      'reply_to_message_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isQuoteMeta =
      const VerificationMeta('isQuote');
  @override
  late final GeneratedColumn<bool> isQuote = GeneratedColumn<bool>(
      'is_quote', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_quote" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _quoteTextMeta =
      const VerificationMeta('quoteText');
  @override
  late final GeneratedColumn<String> quoteText = GeneratedColumn<String>(
      'quote_text', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _quoteOffsetMeta =
      const VerificationMeta('quoteOffset');
  @override
  late final GeneratedColumn<int> quoteOffset = GeneratedColumn<int>(
      'quote_offset', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _quoteLengthMeta =
      const VerificationMeta('quoteLength');
  @override
  late final GeneratedColumn<int> quoteLength = GeneratedColumn<int>(
      'quote_length', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _replyToSenderIdMeta =
      const VerificationMeta('replyToSenderId');
  @override
  late final GeneratedColumn<String> replyToSenderId = GeneratedColumn<String>(
      'reply_to_sender_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _replyToSenderNameMeta =
      const VerificationMeta('replyToSenderName');
  @override
  late final GeneratedColumn<String> replyToSenderName =
      GeneratedColumn<String>('reply_to_sender_name', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _replyToContentMeta =
      const VerificationMeta('replyToContent');
  @override
  late final GeneratedColumn<String> replyToContent = GeneratedColumn<String>(
      'reply_to_content', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _replyToMessageTypeMeta =
      const VerificationMeta('replyToMessageType');
  @override
  late final GeneratedColumn<String> replyToMessageType =
      GeneratedColumn<String>('reply_to_message_type', aliasedName, false,
          type: DriftSqlType.string,
          requiredDuringInsert: false,
          defaultValue: const Constant('text'));
  static const VerificationMeta _isReadMeta = const VerificationMeta('isRead');
  @override
  late final GeneratedColumn<bool> isRead = GeneratedColumn<bool>(
      'is_read', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_read" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isEditedMeta =
      const VerificationMeta('isEdited');
  @override
  late final GeneratedColumn<bool> isEdited = GeneratedColumn<bool>(
      'is_edited', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_edited" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _sendStatusMeta =
      const VerificationMeta('sendStatus');
  @override
  late final GeneratedColumn<int> sendStatus = GeneratedColumn<int>(
      'send_status', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(1));
  static const VerificationMeta _senderNameMeta =
      const VerificationMeta('senderName');
  @override
  late final GeneratedColumn<String> senderName = GeneratedColumn<String>(
      'sender_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _senderAvatarUrlMeta =
      const VerificationMeta('senderAvatarUrl');
  @override
  late final GeneratedColumn<String> senderAvatarUrl = GeneratedColumn<String>(
      'sender_avatar_url', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
      'created_at', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _isForwardMeta =
      const VerificationMeta('isForward');
  @override
  late final GeneratedColumn<bool> isForward = GeneratedColumn<bool>(
      'is_forward', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_forward" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _forwardFromIdMeta =
      const VerificationMeta('forwardFromId');
  @override
  late final GeneratedColumn<String> forwardFromId = GeneratedColumn<String>(
      'forward_from_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _forwardFromNameMeta =
      const VerificationMeta('forwardFromName');
  @override
  late final GeneratedColumn<String> forwardFromName = GeneratedColumn<String>(
      'forward_from_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _forwardFromAvatarUrlMeta =
      const VerificationMeta('forwardFromAvatarUrl');
  @override
  late final GeneratedColumn<String> forwardFromAvatarUrl =
      GeneratedColumn<String>('forward_from_avatar_url', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _senderCustomizationJsonMeta =
      const VerificationMeta('senderCustomizationJson');
  @override
  late final GeneratedColumn<String> senderCustomizationJson =
      GeneratedColumn<String>('sender_customization_json', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _groupedIdMeta =
      const VerificationMeta('groupedId');
  @override
  late final GeneratedColumn<String> groupedId = GeneratedColumn<String>(
      'grouped_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _entitiesMeta =
      const VerificationMeta('entities');
  @override
  late final GeneratedColumn<String> entities = GeneratedColumn<String>(
      'entities', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _reactionsMeta =
      const VerificationMeta('reactions');
  @override
  late final GeneratedColumn<String> reactions = GeneratedColumn<String>(
      'reactions', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _linkPreviewOptionsMeta =
      const VerificationMeta('linkPreviewOptions');
  @override
  late final GeneratedColumn<String> linkPreviewOptions =
      GeneratedColumn<String>('link_preview_options', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _invertMediaMeta =
      const VerificationMeta('invertMedia');
  @override
  late final GeneratedColumn<bool> invertMedia = GeneratedColumn<bool>(
      'invert_media', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("invert_media" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isRoundMeta =
      const VerificationMeta('isRound');
  @override
  late final GeneratedColumn<bool> isRound = GeneratedColumn<bool>(
      'is_round', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_round" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _mediaPayloadMeta =
      const VerificationMeta('mediaPayload');
  @override
  late final GeneratedColumn<String> mediaPayload = GeneratedColumn<String>(
      'media_payload', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _viewsCountMeta =
      const VerificationMeta('viewsCount');
  @override
  late final GeneratedColumn<int> viewsCount = GeneratedColumn<int>(
      'views_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _authorSignatureMeta =
      const VerificationMeta('authorSignature');
  @override
  late final GeneratedColumn<String> authorSignature = GeneratedColumn<String>(
      'author_signature', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _postAuthorIdMeta =
      const VerificationMeta('postAuthorId');
  @override
  late final GeneratedColumn<String> postAuthorId = GeneratedColumn<String>(
      'post_author_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _senderRoleMeta =
      const VerificationMeta('senderRole');
  @override
  late final GeneratedColumn<String> senderRole = GeneratedColumn<String>(
      'sender_role', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _senderAdminTitleMeta =
      const VerificationMeta('senderAdminTitle');
  @override
  late final GeneratedColumn<String> senderAdminTitle = GeneratedColumn<String>(
      'sender_admin_title', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isFromAnonymousAdminMeta =
      const VerificationMeta('isFromAnonymousAdmin');
  @override
  late final GeneratedColumn<bool> isFromAnonymousAdmin = GeneratedColumn<bool>(
      'is_from_anonymous_admin', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_from_anonymous_admin" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _isSilentMeta =
      const VerificationMeta('isSilent');
  @override
  late final GeneratedColumn<bool> isSilent = GeneratedColumn<bool>(
      'is_silent', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_silent" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _commentsCountMeta =
      const VerificationMeta('commentsCount');
  @override
  late final GeneratedColumn<int> commentsCount = GeneratedColumn<int>(
      'comments_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _recentRepliersJsonMeta =
      const VerificationMeta('recentRepliersJson');
  @override
  late final GeneratedColumn<String> recentRepliersJson =
      GeneratedColumn<String>('recent_repliers_json', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _threadRootMessageIdMeta =
      const VerificationMeta('threadRootMessageId');
  @override
  late final GeneratedColumn<String> threadRootMessageId =
      GeneratedColumn<String>('thread_root_message_id', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _hasMediaSpoilerMeta =
      const VerificationMeta('hasMediaSpoiler');
  @override
  late final GeneratedColumn<bool> hasMediaSpoiler = GeneratedColumn<bool>(
      'has_media_spoiler', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("has_media_spoiler" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _expiresAtMeta =
      const VerificationMeta('expiresAt');
  @override
  late final GeneratedColumn<String> expiresAt = GeneratedColumn<String>(
      'expires_at', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _ttlSecondsMeta =
      const VerificationMeta('ttlSeconds');
  @override
  late final GeneratedColumn<int> ttlSeconds = GeneratedColumn<int>(
      'ttl_seconds', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _isViewOnceMeta =
      const VerificationMeta('isViewOnce');
  @override
  late final GeneratedColumn<bool> isViewOnce = GeneratedColumn<bool>(
      'is_view_once', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints: GeneratedColumn.constraintIsAlways(
          'CHECK ("is_view_once" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _viewedAtMeta =
      const VerificationMeta('viewedAt');
  @override
  late final GeneratedColumn<String> viewedAt = GeneratedColumn<String>(
      'viewed_at', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _isBurnedMeta =
      const VerificationMeta('isBurned');
  @override
  late final GeneratedColumn<bool> isBurned = GeneratedColumn<bool>(
      'is_burned', aliasedName, false,
      type: DriftSqlType.bool,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('CHECK ("is_burned" IN (0, 1))'),
      defaultValue: const Constant(false));
  static const VerificationMeta _replyToChatIdMeta =
      const VerificationMeta('replyToChatId');
  @override
  late final GeneratedColumn<String> replyToChatId = GeneratedColumn<String>(
      'reply_to_chat_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _replyToChatNameMeta =
      const VerificationMeta('replyToChatName');
  @override
  late final GeneratedColumn<String> replyToChatName = GeneratedColumn<String>(
      'reply_to_chat_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _replyToChatTypeMeta =
      const VerificationMeta('replyToChatType');
  @override
  late final GeneratedColumn<String> replyToChatType = GeneratedColumn<String>(
      'reply_to_chat_type', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _effectIdMeta =
      const VerificationMeta('effectId');
  @override
  late final GeneratedColumn<String> effectId = GeneratedColumn<String>(
      'effect_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _savedTagsJsonMeta =
      const VerificationMeta('savedTagsJson');
  @override
  late final GeneratedColumn<String> savedTagsJson = GeneratedColumn<String>(
      'saved_tags_json', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _topicIdMeta =
      const VerificationMeta('topicId');
  @override
  late final GeneratedColumn<int> topicId = GeneratedColumn<int>(
      'topic_id', aliasedName, true,
      type: DriftSqlType.int, requiredDuringInsert: false);
  static const VerificationMeta _forwardsCountMeta =
      const VerificationMeta('forwardsCount');
  @override
  late final GeneratedColumn<int> forwardsCount = GeneratedColumn<int>(
      'forwards_count', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _senderChatIdMeta =
      const VerificationMeta('senderChatId');
  @override
  late final GeneratedColumn<String> senderChatId = GeneratedColumn<String>(
      'sender_chat_id', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _senderChatNameMeta =
      const VerificationMeta('senderChatName');
  @override
  late final GeneratedColumn<String> senderChatName = GeneratedColumn<String>(
      'sender_chat_name', aliasedName, true,
      type: DriftSqlType.string, requiredDuringInsert: false);
  static const VerificationMeta _senderChatAvatarUrlMeta =
      const VerificationMeta('senderChatAvatarUrl');
  @override
  late final GeneratedColumn<String> senderChatAvatarUrl =
      GeneratedColumn<String>('sender_chat_avatar_url', aliasedName, true,
          type: DriftSqlType.string, requiredDuringInsert: false);
  @override
  List<GeneratedColumn> get $columns => [
        localId,
        serverId,
        chatId,
        senderId,
        content,
        messageType,
        fileUrl,
        fileName,
        replyToMessageId,
        isQuote,
        quoteText,
        quoteOffset,
        quoteLength,
        replyToSenderId,
        replyToSenderName,
        replyToContent,
        replyToMessageType,
        isRead,
        isEdited,
        sendStatus,
        senderName,
        senderAvatarUrl,
        createdAt,
        isForward,
        forwardFromId,
        forwardFromName,
        forwardFromAvatarUrl,
        senderCustomizationJson,
        groupedId,
        entities,
        reactions,
        linkPreviewOptions,
        invertMedia,
        isRound,
        mediaPayload,
        viewsCount,
        authorSignature,
        postAuthorId,
        senderRole,
        senderAdminTitle,
        isFromAnonymousAdmin,
        isSilent,
        commentsCount,
        recentRepliersJson,
        threadRootMessageId,
        hasMediaSpoiler,
        expiresAt,
        ttlSeconds,
        isViewOnce,
        viewedAt,
        isBurned,
        replyToChatId,
        replyToChatName,
        replyToChatType,
        effectId,
        savedTagsJson,
        topicId,
        forwardsCount,
        senderChatId,
        senderChatName,
        senderChatAvatarUrl
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'messages';
  @override
  VerificationContext validateIntegrity(Insertable<DbMessage> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('local_id')) {
      context.handle(_localIdMeta,
          localId.isAcceptableOrUnknown(data['local_id']!, _localIdMeta));
    } else if (isInserting) {
      context.missing(_localIdMeta);
    }
    if (data.containsKey('server_id')) {
      context.handle(_serverIdMeta,
          serverId.isAcceptableOrUnknown(data['server_id']!, _serverIdMeta));
    }
    if (data.containsKey('chat_id')) {
      context.handle(_chatIdMeta,
          chatId.isAcceptableOrUnknown(data['chat_id']!, _chatIdMeta));
    } else if (isInserting) {
      context.missing(_chatIdMeta);
    }
    if (data.containsKey('sender_id')) {
      context.handle(_senderIdMeta,
          senderId.isAcceptableOrUnknown(data['sender_id']!, _senderIdMeta));
    } else if (isInserting) {
      context.missing(_senderIdMeta);
    }
    if (data.containsKey('content')) {
      context.handle(_contentMeta,
          content.isAcceptableOrUnknown(data['content']!, _contentMeta));
    } else if (isInserting) {
      context.missing(_contentMeta);
    }
    if (data.containsKey('message_type')) {
      context.handle(
          _messageTypeMeta,
          messageType.isAcceptableOrUnknown(
              data['message_type']!, _messageTypeMeta));
    }
    if (data.containsKey('file_url')) {
      context.handle(_fileUrlMeta,
          fileUrl.isAcceptableOrUnknown(data['file_url']!, _fileUrlMeta));
    }
    if (data.containsKey('file_name')) {
      context.handle(_fileNameMeta,
          fileName.isAcceptableOrUnknown(data['file_name']!, _fileNameMeta));
    }
    if (data.containsKey('reply_to_message_id')) {
      context.handle(
          _replyToMessageIdMeta,
          replyToMessageId.isAcceptableOrUnknown(
              data['reply_to_message_id']!, _replyToMessageIdMeta));
    }
    if (data.containsKey('is_quote')) {
      context.handle(_isQuoteMeta,
          isQuote.isAcceptableOrUnknown(data['is_quote']!, _isQuoteMeta));
    }
    if (data.containsKey('quote_text')) {
      context.handle(_quoteTextMeta,
          quoteText.isAcceptableOrUnknown(data['quote_text']!, _quoteTextMeta));
    }
    if (data.containsKey('quote_offset')) {
      context.handle(
          _quoteOffsetMeta,
          quoteOffset.isAcceptableOrUnknown(
              data['quote_offset']!, _quoteOffsetMeta));
    }
    if (data.containsKey('quote_length')) {
      context.handle(
          _quoteLengthMeta,
          quoteLength.isAcceptableOrUnknown(
              data['quote_length']!, _quoteLengthMeta));
    }
    if (data.containsKey('reply_to_sender_id')) {
      context.handle(
          _replyToSenderIdMeta,
          replyToSenderId.isAcceptableOrUnknown(
              data['reply_to_sender_id']!, _replyToSenderIdMeta));
    }
    if (data.containsKey('reply_to_sender_name')) {
      context.handle(
          _replyToSenderNameMeta,
          replyToSenderName.isAcceptableOrUnknown(
              data['reply_to_sender_name']!, _replyToSenderNameMeta));
    }
    if (data.containsKey('reply_to_content')) {
      context.handle(
          _replyToContentMeta,
          replyToContent.isAcceptableOrUnknown(
              data['reply_to_content']!, _replyToContentMeta));
    }
    if (data.containsKey('reply_to_message_type')) {
      context.handle(
          _replyToMessageTypeMeta,
          replyToMessageType.isAcceptableOrUnknown(
              data['reply_to_message_type']!, _replyToMessageTypeMeta));
    }
    if (data.containsKey('is_read')) {
      context.handle(_isReadMeta,
          isRead.isAcceptableOrUnknown(data['is_read']!, _isReadMeta));
    }
    if (data.containsKey('is_edited')) {
      context.handle(_isEditedMeta,
          isEdited.isAcceptableOrUnknown(data['is_edited']!, _isEditedMeta));
    }
    if (data.containsKey('send_status')) {
      context.handle(
          _sendStatusMeta,
          sendStatus.isAcceptableOrUnknown(
              data['send_status']!, _sendStatusMeta));
    }
    if (data.containsKey('sender_name')) {
      context.handle(
          _senderNameMeta,
          senderName.isAcceptableOrUnknown(
              data['sender_name']!, _senderNameMeta));
    }
    if (data.containsKey('sender_avatar_url')) {
      context.handle(
          _senderAvatarUrlMeta,
          senderAvatarUrl.isAcceptableOrUnknown(
              data['sender_avatar_url']!, _senderAvatarUrlMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('is_forward')) {
      context.handle(_isForwardMeta,
          isForward.isAcceptableOrUnknown(data['is_forward']!, _isForwardMeta));
    }
    if (data.containsKey('forward_from_id')) {
      context.handle(
          _forwardFromIdMeta,
          forwardFromId.isAcceptableOrUnknown(
              data['forward_from_id']!, _forwardFromIdMeta));
    }
    if (data.containsKey('forward_from_name')) {
      context.handle(
          _forwardFromNameMeta,
          forwardFromName.isAcceptableOrUnknown(
              data['forward_from_name']!, _forwardFromNameMeta));
    }
    if (data.containsKey('forward_from_avatar_url')) {
      context.handle(
          _forwardFromAvatarUrlMeta,
          forwardFromAvatarUrl.isAcceptableOrUnknown(
              data['forward_from_avatar_url']!, _forwardFromAvatarUrlMeta));
    }
    if (data.containsKey('sender_customization_json')) {
      context.handle(
          _senderCustomizationJsonMeta,
          senderCustomizationJson.isAcceptableOrUnknown(
              data['sender_customization_json']!,
              _senderCustomizationJsonMeta));
    }
    if (data.containsKey('grouped_id')) {
      context.handle(_groupedIdMeta,
          groupedId.isAcceptableOrUnknown(data['grouped_id']!, _groupedIdMeta));
    }
    if (data.containsKey('entities')) {
      context.handle(_entitiesMeta,
          entities.isAcceptableOrUnknown(data['entities']!, _entitiesMeta));
    }
    if (data.containsKey('reactions')) {
      context.handle(_reactionsMeta,
          reactions.isAcceptableOrUnknown(data['reactions']!, _reactionsMeta));
    }
    if (data.containsKey('link_preview_options')) {
      context.handle(
          _linkPreviewOptionsMeta,
          linkPreviewOptions.isAcceptableOrUnknown(
              data['link_preview_options']!, _linkPreviewOptionsMeta));
    }
    if (data.containsKey('invert_media')) {
      context.handle(
          _invertMediaMeta,
          invertMedia.isAcceptableOrUnknown(
              data['invert_media']!, _invertMediaMeta));
    }
    if (data.containsKey('is_round')) {
      context.handle(_isRoundMeta,
          isRound.isAcceptableOrUnknown(data['is_round']!, _isRoundMeta));
    }
    if (data.containsKey('media_payload')) {
      context.handle(
          _mediaPayloadMeta,
          mediaPayload.isAcceptableOrUnknown(
              data['media_payload']!, _mediaPayloadMeta));
    }
    if (data.containsKey('views_count')) {
      context.handle(
          _viewsCountMeta,
          viewsCount.isAcceptableOrUnknown(
              data['views_count']!, _viewsCountMeta));
    }
    if (data.containsKey('author_signature')) {
      context.handle(
          _authorSignatureMeta,
          authorSignature.isAcceptableOrUnknown(
              data['author_signature']!, _authorSignatureMeta));
    }
    if (data.containsKey('post_author_id')) {
      context.handle(
          _postAuthorIdMeta,
          postAuthorId.isAcceptableOrUnknown(
              data['post_author_id']!, _postAuthorIdMeta));
    }
    if (data.containsKey('sender_role')) {
      context.handle(
          _senderRoleMeta,
          senderRole.isAcceptableOrUnknown(
              data['sender_role']!, _senderRoleMeta));
    }
    if (data.containsKey('sender_admin_title')) {
      context.handle(
          _senderAdminTitleMeta,
          senderAdminTitle.isAcceptableOrUnknown(
              data['sender_admin_title']!, _senderAdminTitleMeta));
    }
    if (data.containsKey('is_from_anonymous_admin')) {
      context.handle(
          _isFromAnonymousAdminMeta,
          isFromAnonymousAdmin.isAcceptableOrUnknown(
              data['is_from_anonymous_admin']!, _isFromAnonymousAdminMeta));
    }
    if (data.containsKey('is_silent')) {
      context.handle(_isSilentMeta,
          isSilent.isAcceptableOrUnknown(data['is_silent']!, _isSilentMeta));
    }
    if (data.containsKey('comments_count')) {
      context.handle(
          _commentsCountMeta,
          commentsCount.isAcceptableOrUnknown(
              data['comments_count']!, _commentsCountMeta));
    }
    if (data.containsKey('recent_repliers_json')) {
      context.handle(
          _recentRepliersJsonMeta,
          recentRepliersJson.isAcceptableOrUnknown(
              data['recent_repliers_json']!, _recentRepliersJsonMeta));
    }
    if (data.containsKey('thread_root_message_id')) {
      context.handle(
          _threadRootMessageIdMeta,
          threadRootMessageId.isAcceptableOrUnknown(
              data['thread_root_message_id']!, _threadRootMessageIdMeta));
    }
    if (data.containsKey('has_media_spoiler')) {
      context.handle(
          _hasMediaSpoilerMeta,
          hasMediaSpoiler.isAcceptableOrUnknown(
              data['has_media_spoiler']!, _hasMediaSpoilerMeta));
    }
    if (data.containsKey('expires_at')) {
      context.handle(_expiresAtMeta,
          expiresAt.isAcceptableOrUnknown(data['expires_at']!, _expiresAtMeta));
    }
    if (data.containsKey('ttl_seconds')) {
      context.handle(
          _ttlSecondsMeta,
          ttlSeconds.isAcceptableOrUnknown(
              data['ttl_seconds']!, _ttlSecondsMeta));
    }
    if (data.containsKey('is_view_once')) {
      context.handle(
          _isViewOnceMeta,
          isViewOnce.isAcceptableOrUnknown(
              data['is_view_once']!, _isViewOnceMeta));
    }
    if (data.containsKey('viewed_at')) {
      context.handle(_viewedAtMeta,
          viewedAt.isAcceptableOrUnknown(data['viewed_at']!, _viewedAtMeta));
    }
    if (data.containsKey('is_burned')) {
      context.handle(_isBurnedMeta,
          isBurned.isAcceptableOrUnknown(data['is_burned']!, _isBurnedMeta));
    }
    if (data.containsKey('reply_to_chat_id')) {
      context.handle(
          _replyToChatIdMeta,
          replyToChatId.isAcceptableOrUnknown(
              data['reply_to_chat_id']!, _replyToChatIdMeta));
    }
    if (data.containsKey('reply_to_chat_name')) {
      context.handle(
          _replyToChatNameMeta,
          replyToChatName.isAcceptableOrUnknown(
              data['reply_to_chat_name']!, _replyToChatNameMeta));
    }
    if (data.containsKey('reply_to_chat_type')) {
      context.handle(
          _replyToChatTypeMeta,
          replyToChatType.isAcceptableOrUnknown(
              data['reply_to_chat_type']!, _replyToChatTypeMeta));
    }
    if (data.containsKey('effect_id')) {
      context.handle(_effectIdMeta,
          effectId.isAcceptableOrUnknown(data['effect_id']!, _effectIdMeta));
    }
    if (data.containsKey('saved_tags_json')) {
      context.handle(
          _savedTagsJsonMeta,
          savedTagsJson.isAcceptableOrUnknown(
              data['saved_tags_json']!, _savedTagsJsonMeta));
    }
    if (data.containsKey('topic_id')) {
      context.handle(_topicIdMeta,
          topicId.isAcceptableOrUnknown(data['topic_id']!, _topicIdMeta));
    }
    if (data.containsKey('forwards_count')) {
      context.handle(
          _forwardsCountMeta,
          forwardsCount.isAcceptableOrUnknown(
              data['forwards_count']!, _forwardsCountMeta));
    }
    if (data.containsKey('sender_chat_id')) {
      context.handle(
          _senderChatIdMeta,
          senderChatId.isAcceptableOrUnknown(
              data['sender_chat_id']!, _senderChatIdMeta));
    }
    if (data.containsKey('sender_chat_name')) {
      context.handle(
          _senderChatNameMeta,
          senderChatName.isAcceptableOrUnknown(
              data['sender_chat_name']!, _senderChatNameMeta));
    }
    if (data.containsKey('sender_chat_avatar_url')) {
      context.handle(
          _senderChatAvatarUrlMeta,
          senderChatAvatarUrl.isAcceptableOrUnknown(
              data['sender_chat_avatar_url']!, _senderChatAvatarUrlMeta));
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {localId};
  @override
  DbMessage map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbMessage(
      localId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}local_id'])!,
      serverId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}server_id']),
      chatId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}chat_id'])!,
      senderId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sender_id'])!,
      content: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}content'])!,
      messageType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}message_type'])!,
      fileUrl: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_url']),
      fileName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}file_name']),
      replyToMessageId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}reply_to_message_id']),
      isQuote: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_quote'])!,
      quoteText: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}quote_text']),
      quoteOffset: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}quote_offset'])!,
      quoteLength: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}quote_length'])!,
      replyToSenderId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}reply_to_sender_id']),
      replyToSenderName: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}reply_to_sender_name']),
      replyToContent: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}reply_to_content']),
      replyToMessageType: attachedDatabase.typeMapping.read(DriftSqlType.string,
          data['${effectivePrefix}reply_to_message_type'])!,
      isRead: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_read'])!,
      isEdited: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_edited'])!,
      sendStatus: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}send_status'])!,
      senderName: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sender_name']),
      senderAvatarUrl: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}sender_avatar_url']),
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}created_at'])!,
      isForward: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_forward'])!,
      forwardFromId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}forward_from_id']),
      forwardFromName: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}forward_from_name']),
      forwardFromAvatarUrl: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}forward_from_avatar_url']),
      senderCustomizationJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sender_customization_json']),
      groupedId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}grouped_id']),
      entities: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}entities']),
      reactions: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}reactions']),
      linkPreviewOptions: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}link_preview_options']),
      invertMedia: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}invert_media'])!,
      isRound: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_round'])!,
      mediaPayload: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}media_payload']),
      viewsCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}views_count'])!,
      authorSignature: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}author_signature']),
      postAuthorId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}post_author_id']),
      senderRole: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sender_role']),
      senderAdminTitle: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}sender_admin_title']),
      isFromAnonymousAdmin: attachedDatabase.typeMapping.read(DriftSqlType.bool,
          data['${effectivePrefix}is_from_anonymous_admin'])!,
      isSilent: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_silent'])!,
      commentsCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}comments_count'])!,
      recentRepliersJson: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}recent_repliers_json']),
      threadRootMessageId: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}thread_root_message_id']),
      hasMediaSpoiler: attachedDatabase.typeMapping.read(
          DriftSqlType.bool, data['${effectivePrefix}has_media_spoiler'])!,
      expiresAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}expires_at']),
      ttlSeconds: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}ttl_seconds'])!,
      isViewOnce: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_view_once'])!,
      viewedAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}viewed_at']),
      isBurned: attachedDatabase.typeMapping
          .read(DriftSqlType.bool, data['${effectivePrefix}is_burned'])!,
      replyToChatId: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}reply_to_chat_id']),
      replyToChatName: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}reply_to_chat_name']),
      replyToChatType: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}reply_to_chat_type']),
      effectId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}effect_id']),
      savedTagsJson: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}saved_tags_json']),
      topicId: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}topic_id']),
      forwardsCount: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}forwards_count'])!,
      senderChatId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}sender_chat_id']),
      senderChatName: attachedDatabase.typeMapping.read(
          DriftSqlType.string, data['${effectivePrefix}sender_chat_name']),
      senderChatAvatarUrl: attachedDatabase.typeMapping.read(
          DriftSqlType.string,
          data['${effectivePrefix}sender_chat_avatar_url']),
    );
  }

  @override
  $MessagesTable createAlias(String alias) {
    return $MessagesTable(attachedDatabase, alias);
  }
}

class DbMessage extends DataClass implements Insertable<DbMessage> {
  final String localId;
  final String? serverId;
  final String chatId;
  final String senderId;
  final String content;
  final String messageType;
  final String? fileUrl;
  final String? fileName;
  final String? replyToMessageId;
  final bool isQuote;
  final String? quoteText;
  final int quoteOffset;
  final int quoteLength;
  final String? replyToSenderId;
  final String? replyToSenderName;
  final String? replyToContent;
  final String replyToMessageType;
  final bool isRead;
  final bool isEdited;
  final int sendStatus;
  final String? senderName;
  final String? senderAvatarUrl;
  final String createdAt;
  final bool isForward;
  final String? forwardFromId;
  final String? forwardFromName;
  final String? forwardFromAvatarUrl;
  final String? senderCustomizationJson;
  final String? groupedId;
  final String? entities;
  final String? reactions;
  final String? linkPreviewOptions;
  final bool invertMedia;
  final bool isRound;
  final String? mediaPayload;
  final int viewsCount;
  final String? authorSignature;
  final String? postAuthorId;
  final String? senderRole;
  final String? senderAdminTitle;
  final bool isFromAnonymousAdmin;
  final bool isSilent;
  final int commentsCount;
  final String? recentRepliersJson;
  final String? threadRootMessageId;
  final bool hasMediaSpoiler;
  final String? expiresAt;
  final int ttlSeconds;
  final bool isViewOnce;
  final String? viewedAt;
  final bool isBurned;
  final String? replyToChatId;
  final String? replyToChatName;
  final String? replyToChatType;
  final String? effectId;
  final String? savedTagsJson;
  final int? topicId;
  final int forwardsCount;
  final String? senderChatId;
  final String? senderChatName;
  final String? senderChatAvatarUrl;
  const DbMessage(
      {required this.localId,
      this.serverId,
      required this.chatId,
      required this.senderId,
      required this.content,
      required this.messageType,
      this.fileUrl,
      this.fileName,
      this.replyToMessageId,
      required this.isQuote,
      this.quoteText,
      required this.quoteOffset,
      required this.quoteLength,
      this.replyToSenderId,
      this.replyToSenderName,
      this.replyToContent,
      required this.replyToMessageType,
      required this.isRead,
      required this.isEdited,
      required this.sendStatus,
      this.senderName,
      this.senderAvatarUrl,
      required this.createdAt,
      required this.isForward,
      this.forwardFromId,
      this.forwardFromName,
      this.forwardFromAvatarUrl,
      this.senderCustomizationJson,
      this.groupedId,
      this.entities,
      this.reactions,
      this.linkPreviewOptions,
      required this.invertMedia,
      required this.isRound,
      this.mediaPayload,
      required this.viewsCount,
      this.authorSignature,
      this.postAuthorId,
      this.senderRole,
      this.senderAdminTitle,
      required this.isFromAnonymousAdmin,
      required this.isSilent,
      required this.commentsCount,
      this.recentRepliersJson,
      this.threadRootMessageId,
      required this.hasMediaSpoiler,
      this.expiresAt,
      required this.ttlSeconds,
      required this.isViewOnce,
      this.viewedAt,
      required this.isBurned,
      this.replyToChatId,
      this.replyToChatName,
      this.replyToChatType,
      this.effectId,
      this.savedTagsJson,
      this.topicId,
      required this.forwardsCount,
      this.senderChatId,
      this.senderChatName,
      this.senderChatAvatarUrl});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['local_id'] = Variable<String>(localId);
    if (!nullToAbsent || serverId != null) {
      map['server_id'] = Variable<String>(serverId);
    }
    map['chat_id'] = Variable<String>(chatId);
    map['sender_id'] = Variable<String>(senderId);
    map['content'] = Variable<String>(content);
    map['message_type'] = Variable<String>(messageType);
    if (!nullToAbsent || fileUrl != null) {
      map['file_url'] = Variable<String>(fileUrl);
    }
    if (!nullToAbsent || fileName != null) {
      map['file_name'] = Variable<String>(fileName);
    }
    if (!nullToAbsent || replyToMessageId != null) {
      map['reply_to_message_id'] = Variable<String>(replyToMessageId);
    }
    map['is_quote'] = Variable<bool>(isQuote);
    if (!nullToAbsent || quoteText != null) {
      map['quote_text'] = Variable<String>(quoteText);
    }
    map['quote_offset'] = Variable<int>(quoteOffset);
    map['quote_length'] = Variable<int>(quoteLength);
    if (!nullToAbsent || replyToSenderId != null) {
      map['reply_to_sender_id'] = Variable<String>(replyToSenderId);
    }
    if (!nullToAbsent || replyToSenderName != null) {
      map['reply_to_sender_name'] = Variable<String>(replyToSenderName);
    }
    if (!nullToAbsent || replyToContent != null) {
      map['reply_to_content'] = Variable<String>(replyToContent);
    }
    map['reply_to_message_type'] = Variable<String>(replyToMessageType);
    map['is_read'] = Variable<bool>(isRead);
    map['is_edited'] = Variable<bool>(isEdited);
    map['send_status'] = Variable<int>(sendStatus);
    if (!nullToAbsent || senderName != null) {
      map['sender_name'] = Variable<String>(senderName);
    }
    if (!nullToAbsent || senderAvatarUrl != null) {
      map['sender_avatar_url'] = Variable<String>(senderAvatarUrl);
    }
    map['created_at'] = Variable<String>(createdAt);
    map['is_forward'] = Variable<bool>(isForward);
    if (!nullToAbsent || forwardFromId != null) {
      map['forward_from_id'] = Variable<String>(forwardFromId);
    }
    if (!nullToAbsent || forwardFromName != null) {
      map['forward_from_name'] = Variable<String>(forwardFromName);
    }
    if (!nullToAbsent || forwardFromAvatarUrl != null) {
      map['forward_from_avatar_url'] = Variable<String>(forwardFromAvatarUrl);
    }
    if (!nullToAbsent || senderCustomizationJson != null) {
      map['sender_customization_json'] =
          Variable<String>(senderCustomizationJson);
    }
    if (!nullToAbsent || groupedId != null) {
      map['grouped_id'] = Variable<String>(groupedId);
    }
    if (!nullToAbsent || entities != null) {
      map['entities'] = Variable<String>(entities);
    }
    if (!nullToAbsent || reactions != null) {
      map['reactions'] = Variable<String>(reactions);
    }
    if (!nullToAbsent || linkPreviewOptions != null) {
      map['link_preview_options'] = Variable<String>(linkPreviewOptions);
    }
    map['invert_media'] = Variable<bool>(invertMedia);
    map['is_round'] = Variable<bool>(isRound);
    if (!nullToAbsent || mediaPayload != null) {
      map['media_payload'] = Variable<String>(mediaPayload);
    }
    map['views_count'] = Variable<int>(viewsCount);
    if (!nullToAbsent || authorSignature != null) {
      map['author_signature'] = Variable<String>(authorSignature);
    }
    if (!nullToAbsent || postAuthorId != null) {
      map['post_author_id'] = Variable<String>(postAuthorId);
    }
    if (!nullToAbsent || senderRole != null) {
      map['sender_role'] = Variable<String>(senderRole);
    }
    if (!nullToAbsent || senderAdminTitle != null) {
      map['sender_admin_title'] = Variable<String>(senderAdminTitle);
    }
    map['is_from_anonymous_admin'] = Variable<bool>(isFromAnonymousAdmin);
    map['is_silent'] = Variable<bool>(isSilent);
    map['comments_count'] = Variable<int>(commentsCount);
    if (!nullToAbsent || recentRepliersJson != null) {
      map['recent_repliers_json'] = Variable<String>(recentRepliersJson);
    }
    if (!nullToAbsent || threadRootMessageId != null) {
      map['thread_root_message_id'] = Variable<String>(threadRootMessageId);
    }
    map['has_media_spoiler'] = Variable<bool>(hasMediaSpoiler);
    if (!nullToAbsent || expiresAt != null) {
      map['expires_at'] = Variable<String>(expiresAt);
    }
    map['ttl_seconds'] = Variable<int>(ttlSeconds);
    map['is_view_once'] = Variable<bool>(isViewOnce);
    if (!nullToAbsent || viewedAt != null) {
      map['viewed_at'] = Variable<String>(viewedAt);
    }
    map['is_burned'] = Variable<bool>(isBurned);
    if (!nullToAbsent || replyToChatId != null) {
      map['reply_to_chat_id'] = Variable<String>(replyToChatId);
    }
    if (!nullToAbsent || replyToChatName != null) {
      map['reply_to_chat_name'] = Variable<String>(replyToChatName);
    }
    if (!nullToAbsent || replyToChatType != null) {
      map['reply_to_chat_type'] = Variable<String>(replyToChatType);
    }
    if (!nullToAbsent || effectId != null) {
      map['effect_id'] = Variable<String>(effectId);
    }
    if (!nullToAbsent || savedTagsJson != null) {
      map['saved_tags_json'] = Variable<String>(savedTagsJson);
    }
    if (!nullToAbsent || topicId != null) {
      map['topic_id'] = Variable<int>(topicId);
    }
    map['forwards_count'] = Variable<int>(forwardsCount);
    if (!nullToAbsent || senderChatId != null) {
      map['sender_chat_id'] = Variable<String>(senderChatId);
    }
    if (!nullToAbsent || senderChatName != null) {
      map['sender_chat_name'] = Variable<String>(senderChatName);
    }
    if (!nullToAbsent || senderChatAvatarUrl != null) {
      map['sender_chat_avatar_url'] = Variable<String>(senderChatAvatarUrl);
    }
    return map;
  }

  MessagesCompanion toCompanion(bool nullToAbsent) {
    return MessagesCompanion(
      localId: Value(localId),
      serverId: serverId == null && nullToAbsent
          ? const Value.absent()
          : Value(serverId),
      chatId: Value(chatId),
      senderId: Value(senderId),
      content: Value(content),
      messageType: Value(messageType),
      fileUrl: fileUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(fileUrl),
      fileName: fileName == null && nullToAbsent
          ? const Value.absent()
          : Value(fileName),
      replyToMessageId: replyToMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToMessageId),
      isQuote: Value(isQuote),
      quoteText: quoteText == null && nullToAbsent
          ? const Value.absent()
          : Value(quoteText),
      quoteOffset: Value(quoteOffset),
      quoteLength: Value(quoteLength),
      replyToSenderId: replyToSenderId == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToSenderId),
      replyToSenderName: replyToSenderName == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToSenderName),
      replyToContent: replyToContent == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToContent),
      replyToMessageType: Value(replyToMessageType),
      isRead: Value(isRead),
      isEdited: Value(isEdited),
      sendStatus: Value(sendStatus),
      senderName: senderName == null && nullToAbsent
          ? const Value.absent()
          : Value(senderName),
      senderAvatarUrl: senderAvatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(senderAvatarUrl),
      createdAt: Value(createdAt),
      isForward: Value(isForward),
      forwardFromId: forwardFromId == null && nullToAbsent
          ? const Value.absent()
          : Value(forwardFromId),
      forwardFromName: forwardFromName == null && nullToAbsent
          ? const Value.absent()
          : Value(forwardFromName),
      forwardFromAvatarUrl: forwardFromAvatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(forwardFromAvatarUrl),
      senderCustomizationJson: senderCustomizationJson == null && nullToAbsent
          ? const Value.absent()
          : Value(senderCustomizationJson),
      groupedId: groupedId == null && nullToAbsent
          ? const Value.absent()
          : Value(groupedId),
      entities: entities == null && nullToAbsent
          ? const Value.absent()
          : Value(entities),
      reactions: reactions == null && nullToAbsent
          ? const Value.absent()
          : Value(reactions),
      linkPreviewOptions: linkPreviewOptions == null && nullToAbsent
          ? const Value.absent()
          : Value(linkPreviewOptions),
      invertMedia: Value(invertMedia),
      isRound: Value(isRound),
      mediaPayload: mediaPayload == null && nullToAbsent
          ? const Value.absent()
          : Value(mediaPayload),
      viewsCount: Value(viewsCount),
      authorSignature: authorSignature == null && nullToAbsent
          ? const Value.absent()
          : Value(authorSignature),
      postAuthorId: postAuthorId == null && nullToAbsent
          ? const Value.absent()
          : Value(postAuthorId),
      senderRole: senderRole == null && nullToAbsent
          ? const Value.absent()
          : Value(senderRole),
      senderAdminTitle: senderAdminTitle == null && nullToAbsent
          ? const Value.absent()
          : Value(senderAdminTitle),
      isFromAnonymousAdmin: Value(isFromAnonymousAdmin),
      isSilent: Value(isSilent),
      commentsCount: Value(commentsCount),
      recentRepliersJson: recentRepliersJson == null && nullToAbsent
          ? const Value.absent()
          : Value(recentRepliersJson),
      threadRootMessageId: threadRootMessageId == null && nullToAbsent
          ? const Value.absent()
          : Value(threadRootMessageId),
      hasMediaSpoiler: Value(hasMediaSpoiler),
      expiresAt: expiresAt == null && nullToAbsent
          ? const Value.absent()
          : Value(expiresAt),
      ttlSeconds: Value(ttlSeconds),
      isViewOnce: Value(isViewOnce),
      viewedAt: viewedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(viewedAt),
      isBurned: Value(isBurned),
      replyToChatId: replyToChatId == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToChatId),
      replyToChatName: replyToChatName == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToChatName),
      replyToChatType: replyToChatType == null && nullToAbsent
          ? const Value.absent()
          : Value(replyToChatType),
      effectId: effectId == null && nullToAbsent
          ? const Value.absent()
          : Value(effectId),
      savedTagsJson: savedTagsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(savedTagsJson),
      topicId: topicId == null && nullToAbsent
          ? const Value.absent()
          : Value(topicId),
      forwardsCount: Value(forwardsCount),
      senderChatId: senderChatId == null && nullToAbsent
          ? const Value.absent()
          : Value(senderChatId),
      senderChatName: senderChatName == null && nullToAbsent
          ? const Value.absent()
          : Value(senderChatName),
      senderChatAvatarUrl: senderChatAvatarUrl == null && nullToAbsent
          ? const Value.absent()
          : Value(senderChatAvatarUrl),
    );
  }

  factory DbMessage.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbMessage(
      localId: serializer.fromJson<String>(json['localId']),
      serverId: serializer.fromJson<String?>(json['serverId']),
      chatId: serializer.fromJson<String>(json['chatId']),
      senderId: serializer.fromJson<String>(json['senderId']),
      content: serializer.fromJson<String>(json['content']),
      messageType: serializer.fromJson<String>(json['messageType']),
      fileUrl: serializer.fromJson<String?>(json['fileUrl']),
      fileName: serializer.fromJson<String?>(json['fileName']),
      replyToMessageId: serializer.fromJson<String?>(json['replyToMessageId']),
      isQuote: serializer.fromJson<bool>(json['isQuote']),
      quoteText: serializer.fromJson<String?>(json['quoteText']),
      quoteOffset: serializer.fromJson<int>(json['quoteOffset']),
      quoteLength: serializer.fromJson<int>(json['quoteLength']),
      replyToSenderId: serializer.fromJson<String?>(json['replyToSenderId']),
      replyToSenderName:
          serializer.fromJson<String?>(json['replyToSenderName']),
      replyToContent: serializer.fromJson<String?>(json['replyToContent']),
      replyToMessageType:
          serializer.fromJson<String>(json['replyToMessageType']),
      isRead: serializer.fromJson<bool>(json['isRead']),
      isEdited: serializer.fromJson<bool>(json['isEdited']),
      sendStatus: serializer.fromJson<int>(json['sendStatus']),
      senderName: serializer.fromJson<String?>(json['senderName']),
      senderAvatarUrl: serializer.fromJson<String?>(json['senderAvatarUrl']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
      isForward: serializer.fromJson<bool>(json['isForward']),
      forwardFromId: serializer.fromJson<String?>(json['forwardFromId']),
      forwardFromName: serializer.fromJson<String?>(json['forwardFromName']),
      forwardFromAvatarUrl:
          serializer.fromJson<String?>(json['forwardFromAvatarUrl']),
      senderCustomizationJson:
          serializer.fromJson<String?>(json['senderCustomizationJson']),
      groupedId: serializer.fromJson<String?>(json['groupedId']),
      entities: serializer.fromJson<String?>(json['entities']),
      reactions: serializer.fromJson<String?>(json['reactions']),
      linkPreviewOptions:
          serializer.fromJson<String?>(json['linkPreviewOptions']),
      invertMedia: serializer.fromJson<bool>(json['invertMedia']),
      isRound: serializer.fromJson<bool>(json['isRound']),
      mediaPayload: serializer.fromJson<String?>(json['mediaPayload']),
      viewsCount: serializer.fromJson<int>(json['viewsCount']),
      authorSignature: serializer.fromJson<String?>(json['authorSignature']),
      postAuthorId: serializer.fromJson<String?>(json['postAuthorId']),
      senderRole: serializer.fromJson<String?>(json['senderRole']),
      senderAdminTitle: serializer.fromJson<String?>(json['senderAdminTitle']),
      isFromAnonymousAdmin:
          serializer.fromJson<bool>(json['isFromAnonymousAdmin']),
      isSilent: serializer.fromJson<bool>(json['isSilent']),
      commentsCount: serializer.fromJson<int>(json['commentsCount']),
      recentRepliersJson:
          serializer.fromJson<String?>(json['recentRepliersJson']),
      threadRootMessageId:
          serializer.fromJson<String?>(json['threadRootMessageId']),
      hasMediaSpoiler: serializer.fromJson<bool>(json['hasMediaSpoiler']),
      expiresAt: serializer.fromJson<String?>(json['expiresAt']),
      ttlSeconds: serializer.fromJson<int>(json['ttlSeconds']),
      isViewOnce: serializer.fromJson<bool>(json['isViewOnce']),
      viewedAt: serializer.fromJson<String?>(json['viewedAt']),
      isBurned: serializer.fromJson<bool>(json['isBurned']),
      replyToChatId: serializer.fromJson<String?>(json['replyToChatId']),
      replyToChatName: serializer.fromJson<String?>(json['replyToChatName']),
      replyToChatType: serializer.fromJson<String?>(json['replyToChatType']),
      effectId: serializer.fromJson<String?>(json['effectId']),
      savedTagsJson: serializer.fromJson<String?>(json['savedTagsJson']),
      topicId: serializer.fromJson<int?>(json['topicId']),
      forwardsCount: serializer.fromJson<int>(json['forwardsCount']),
      senderChatId: serializer.fromJson<String?>(json['senderChatId']),
      senderChatName: serializer.fromJson<String?>(json['senderChatName']),
      senderChatAvatarUrl:
          serializer.fromJson<String?>(json['senderChatAvatarUrl']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'localId': serializer.toJson<String>(localId),
      'serverId': serializer.toJson<String?>(serverId),
      'chatId': serializer.toJson<String>(chatId),
      'senderId': serializer.toJson<String>(senderId),
      'content': serializer.toJson<String>(content),
      'messageType': serializer.toJson<String>(messageType),
      'fileUrl': serializer.toJson<String?>(fileUrl),
      'fileName': serializer.toJson<String?>(fileName),
      'replyToMessageId': serializer.toJson<String?>(replyToMessageId),
      'isQuote': serializer.toJson<bool>(isQuote),
      'quoteText': serializer.toJson<String?>(quoteText),
      'quoteOffset': serializer.toJson<int>(quoteOffset),
      'quoteLength': serializer.toJson<int>(quoteLength),
      'replyToSenderId': serializer.toJson<String?>(replyToSenderId),
      'replyToSenderName': serializer.toJson<String?>(replyToSenderName),
      'replyToContent': serializer.toJson<String?>(replyToContent),
      'replyToMessageType': serializer.toJson<String>(replyToMessageType),
      'isRead': serializer.toJson<bool>(isRead),
      'isEdited': serializer.toJson<bool>(isEdited),
      'sendStatus': serializer.toJson<int>(sendStatus),
      'senderName': serializer.toJson<String?>(senderName),
      'senderAvatarUrl': serializer.toJson<String?>(senderAvatarUrl),
      'createdAt': serializer.toJson<String>(createdAt),
      'isForward': serializer.toJson<bool>(isForward),
      'forwardFromId': serializer.toJson<String?>(forwardFromId),
      'forwardFromName': serializer.toJson<String?>(forwardFromName),
      'forwardFromAvatarUrl': serializer.toJson<String?>(forwardFromAvatarUrl),
      'senderCustomizationJson':
          serializer.toJson<String?>(senderCustomizationJson),
      'groupedId': serializer.toJson<String?>(groupedId),
      'entities': serializer.toJson<String?>(entities),
      'reactions': serializer.toJson<String?>(reactions),
      'linkPreviewOptions': serializer.toJson<String?>(linkPreviewOptions),
      'invertMedia': serializer.toJson<bool>(invertMedia),
      'isRound': serializer.toJson<bool>(isRound),
      'mediaPayload': serializer.toJson<String?>(mediaPayload),
      'viewsCount': serializer.toJson<int>(viewsCount),
      'authorSignature': serializer.toJson<String?>(authorSignature),
      'postAuthorId': serializer.toJson<String?>(postAuthorId),
      'senderRole': serializer.toJson<String?>(senderRole),
      'senderAdminTitle': serializer.toJson<String?>(senderAdminTitle),
      'isFromAnonymousAdmin': serializer.toJson<bool>(isFromAnonymousAdmin),
      'isSilent': serializer.toJson<bool>(isSilent),
      'commentsCount': serializer.toJson<int>(commentsCount),
      'recentRepliersJson': serializer.toJson<String?>(recentRepliersJson),
      'threadRootMessageId': serializer.toJson<String?>(threadRootMessageId),
      'hasMediaSpoiler': serializer.toJson<bool>(hasMediaSpoiler),
      'expiresAt': serializer.toJson<String?>(expiresAt),
      'ttlSeconds': serializer.toJson<int>(ttlSeconds),
      'isViewOnce': serializer.toJson<bool>(isViewOnce),
      'viewedAt': serializer.toJson<String?>(viewedAt),
      'isBurned': serializer.toJson<bool>(isBurned),
      'replyToChatId': serializer.toJson<String?>(replyToChatId),
      'replyToChatName': serializer.toJson<String?>(replyToChatName),
      'replyToChatType': serializer.toJson<String?>(replyToChatType),
      'effectId': serializer.toJson<String?>(effectId),
      'savedTagsJson': serializer.toJson<String?>(savedTagsJson),
      'topicId': serializer.toJson<int?>(topicId),
      'forwardsCount': serializer.toJson<int>(forwardsCount),
      'senderChatId': serializer.toJson<String?>(senderChatId),
      'senderChatName': serializer.toJson<String?>(senderChatName),
      'senderChatAvatarUrl': serializer.toJson<String?>(senderChatAvatarUrl),
    };
  }

  DbMessage copyWith(
          {String? localId,
          Value<String?> serverId = const Value.absent(),
          String? chatId,
          String? senderId,
          String? content,
          String? messageType,
          Value<String?> fileUrl = const Value.absent(),
          Value<String?> fileName = const Value.absent(),
          Value<String?> replyToMessageId = const Value.absent(),
          bool? isQuote,
          Value<String?> quoteText = const Value.absent(),
          int? quoteOffset,
          int? quoteLength,
          Value<String?> replyToSenderId = const Value.absent(),
          Value<String?> replyToSenderName = const Value.absent(),
          Value<String?> replyToContent = const Value.absent(),
          String? replyToMessageType,
          bool? isRead,
          bool? isEdited,
          int? sendStatus,
          Value<String?> senderName = const Value.absent(),
          Value<String?> senderAvatarUrl = const Value.absent(),
          String? createdAt,
          bool? isForward,
          Value<String?> forwardFromId = const Value.absent(),
          Value<String?> forwardFromName = const Value.absent(),
          Value<String?> forwardFromAvatarUrl = const Value.absent(),
          Value<String?> senderCustomizationJson = const Value.absent(),
          Value<String?> groupedId = const Value.absent(),
          Value<String?> entities = const Value.absent(),
          Value<String?> reactions = const Value.absent(),
          Value<String?> linkPreviewOptions = const Value.absent(),
          bool? invertMedia,
          bool? isRound,
          Value<String?> mediaPayload = const Value.absent(),
          int? viewsCount,
          Value<String?> authorSignature = const Value.absent(),
          Value<String?> postAuthorId = const Value.absent(),
          Value<String?> senderRole = const Value.absent(),
          Value<String?> senderAdminTitle = const Value.absent(),
          bool? isFromAnonymousAdmin,
          bool? isSilent,
          int? commentsCount,
          Value<String?> recentRepliersJson = const Value.absent(),
          Value<String?> threadRootMessageId = const Value.absent(),
          bool? hasMediaSpoiler,
          Value<String?> expiresAt = const Value.absent(),
          int? ttlSeconds,
          bool? isViewOnce,
          Value<String?> viewedAt = const Value.absent(),
          bool? isBurned,
          Value<String?> replyToChatId = const Value.absent(),
          Value<String?> replyToChatName = const Value.absent(),
          Value<String?> replyToChatType = const Value.absent(),
          Value<String?> effectId = const Value.absent(),
          Value<String?> savedTagsJson = const Value.absent(),
          Value<int?> topicId = const Value.absent(),
          int? forwardsCount,
          Value<String?> senderChatId = const Value.absent(),
          Value<String?> senderChatName = const Value.absent(),
          Value<String?> senderChatAvatarUrl = const Value.absent()}) =>
      DbMessage(
        localId: localId ?? this.localId,
        serverId: serverId.present ? serverId.value : this.serverId,
        chatId: chatId ?? this.chatId,
        senderId: senderId ?? this.senderId,
        content: content ?? this.content,
        messageType: messageType ?? this.messageType,
        fileUrl: fileUrl.present ? fileUrl.value : this.fileUrl,
        fileName: fileName.present ? fileName.value : this.fileName,
        replyToMessageId: replyToMessageId.present
            ? replyToMessageId.value
            : this.replyToMessageId,
        isQuote: isQuote ?? this.isQuote,
        quoteText: quoteText.present ? quoteText.value : this.quoteText,
        quoteOffset: quoteOffset ?? this.quoteOffset,
        quoteLength: quoteLength ?? this.quoteLength,
        replyToSenderId: replyToSenderId.present
            ? replyToSenderId.value
            : this.replyToSenderId,
        replyToSenderName: replyToSenderName.present
            ? replyToSenderName.value
            : this.replyToSenderName,
        replyToContent:
            replyToContent.present ? replyToContent.value : this.replyToContent,
        replyToMessageType: replyToMessageType ?? this.replyToMessageType,
        isRead: isRead ?? this.isRead,
        isEdited: isEdited ?? this.isEdited,
        sendStatus: sendStatus ?? this.sendStatus,
        senderName: senderName.present ? senderName.value : this.senderName,
        senderAvatarUrl: senderAvatarUrl.present
            ? senderAvatarUrl.value
            : this.senderAvatarUrl,
        createdAt: createdAt ?? this.createdAt,
        isForward: isForward ?? this.isForward,
        forwardFromId:
            forwardFromId.present ? forwardFromId.value : this.forwardFromId,
        forwardFromName: forwardFromName.present
            ? forwardFromName.value
            : this.forwardFromName,
        forwardFromAvatarUrl: forwardFromAvatarUrl.present
            ? forwardFromAvatarUrl.value
            : this.forwardFromAvatarUrl,
        senderCustomizationJson: senderCustomizationJson.present
            ? senderCustomizationJson.value
            : this.senderCustomizationJson,
        groupedId: groupedId.present ? groupedId.value : this.groupedId,
        entities: entities.present ? entities.value : this.entities,
        reactions: reactions.present ? reactions.value : this.reactions,
        linkPreviewOptions: linkPreviewOptions.present
            ? linkPreviewOptions.value
            : this.linkPreviewOptions,
        invertMedia: invertMedia ?? this.invertMedia,
        isRound: isRound ?? this.isRound,
        mediaPayload:
            mediaPayload.present ? mediaPayload.value : this.mediaPayload,
        viewsCount: viewsCount ?? this.viewsCount,
        authorSignature: authorSignature.present
            ? authorSignature.value
            : this.authorSignature,
        postAuthorId:
            postAuthorId.present ? postAuthorId.value : this.postAuthorId,
        senderRole: senderRole.present ? senderRole.value : this.senderRole,
        senderAdminTitle: senderAdminTitle.present
            ? senderAdminTitle.value
            : this.senderAdminTitle,
        isFromAnonymousAdmin: isFromAnonymousAdmin ?? this.isFromAnonymousAdmin,
        isSilent: isSilent ?? this.isSilent,
        commentsCount: commentsCount ?? this.commentsCount,
        recentRepliersJson: recentRepliersJson.present
            ? recentRepliersJson.value
            : this.recentRepliersJson,
        threadRootMessageId: threadRootMessageId.present
            ? threadRootMessageId.value
            : this.threadRootMessageId,
        hasMediaSpoiler: hasMediaSpoiler ?? this.hasMediaSpoiler,
        expiresAt: expiresAt.present ? expiresAt.value : this.expiresAt,
        ttlSeconds: ttlSeconds ?? this.ttlSeconds,
        isViewOnce: isViewOnce ?? this.isViewOnce,
        viewedAt: viewedAt.present ? viewedAt.value : this.viewedAt,
        isBurned: isBurned ?? this.isBurned,
        replyToChatId:
            replyToChatId.present ? replyToChatId.value : this.replyToChatId,
        replyToChatName: replyToChatName.present
            ? replyToChatName.value
            : this.replyToChatName,
        replyToChatType: replyToChatType.present
            ? replyToChatType.value
            : this.replyToChatType,
        effectId: effectId.present ? effectId.value : this.effectId,
        savedTagsJson:
            savedTagsJson.present ? savedTagsJson.value : this.savedTagsJson,
        topicId: topicId.present ? topicId.value : this.topicId,
        forwardsCount: forwardsCount ?? this.forwardsCount,
        senderChatId:
            senderChatId.present ? senderChatId.value : this.senderChatId,
        senderChatName:
            senderChatName.present ? senderChatName.value : this.senderChatName,
        senderChatAvatarUrl: senderChatAvatarUrl.present
            ? senderChatAvatarUrl.value
            : this.senderChatAvatarUrl,
      );
  DbMessage copyWithCompanion(MessagesCompanion data) {
    return DbMessage(
      localId: data.localId.present ? data.localId.value : this.localId,
      serverId: data.serverId.present ? data.serverId.value : this.serverId,
      chatId: data.chatId.present ? data.chatId.value : this.chatId,
      senderId: data.senderId.present ? data.senderId.value : this.senderId,
      content: data.content.present ? data.content.value : this.content,
      messageType:
          data.messageType.present ? data.messageType.value : this.messageType,
      fileUrl: data.fileUrl.present ? data.fileUrl.value : this.fileUrl,
      fileName: data.fileName.present ? data.fileName.value : this.fileName,
      replyToMessageId: data.replyToMessageId.present
          ? data.replyToMessageId.value
          : this.replyToMessageId,
      isQuote: data.isQuote.present ? data.isQuote.value : this.isQuote,
      quoteText: data.quoteText.present ? data.quoteText.value : this.quoteText,
      quoteOffset:
          data.quoteOffset.present ? data.quoteOffset.value : this.quoteOffset,
      quoteLength:
          data.quoteLength.present ? data.quoteLength.value : this.quoteLength,
      replyToSenderId: data.replyToSenderId.present
          ? data.replyToSenderId.value
          : this.replyToSenderId,
      replyToSenderName: data.replyToSenderName.present
          ? data.replyToSenderName.value
          : this.replyToSenderName,
      replyToContent: data.replyToContent.present
          ? data.replyToContent.value
          : this.replyToContent,
      replyToMessageType: data.replyToMessageType.present
          ? data.replyToMessageType.value
          : this.replyToMessageType,
      isRead: data.isRead.present ? data.isRead.value : this.isRead,
      isEdited: data.isEdited.present ? data.isEdited.value : this.isEdited,
      sendStatus:
          data.sendStatus.present ? data.sendStatus.value : this.sendStatus,
      senderName:
          data.senderName.present ? data.senderName.value : this.senderName,
      senderAvatarUrl: data.senderAvatarUrl.present
          ? data.senderAvatarUrl.value
          : this.senderAvatarUrl,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      isForward: data.isForward.present ? data.isForward.value : this.isForward,
      forwardFromId: data.forwardFromId.present
          ? data.forwardFromId.value
          : this.forwardFromId,
      forwardFromName: data.forwardFromName.present
          ? data.forwardFromName.value
          : this.forwardFromName,
      forwardFromAvatarUrl: data.forwardFromAvatarUrl.present
          ? data.forwardFromAvatarUrl.value
          : this.forwardFromAvatarUrl,
      senderCustomizationJson: data.senderCustomizationJson.present
          ? data.senderCustomizationJson.value
          : this.senderCustomizationJson,
      groupedId: data.groupedId.present ? data.groupedId.value : this.groupedId,
      entities: data.entities.present ? data.entities.value : this.entities,
      reactions: data.reactions.present ? data.reactions.value : this.reactions,
      linkPreviewOptions: data.linkPreviewOptions.present
          ? data.linkPreviewOptions.value
          : this.linkPreviewOptions,
      invertMedia:
          data.invertMedia.present ? data.invertMedia.value : this.invertMedia,
      isRound: data.isRound.present ? data.isRound.value : this.isRound,
      mediaPayload: data.mediaPayload.present
          ? data.mediaPayload.value
          : this.mediaPayload,
      viewsCount:
          data.viewsCount.present ? data.viewsCount.value : this.viewsCount,
      authorSignature: data.authorSignature.present
          ? data.authorSignature.value
          : this.authorSignature,
      postAuthorId: data.postAuthorId.present
          ? data.postAuthorId.value
          : this.postAuthorId,
      senderRole:
          data.senderRole.present ? data.senderRole.value : this.senderRole,
      senderAdminTitle: data.senderAdminTitle.present
          ? data.senderAdminTitle.value
          : this.senderAdminTitle,
      isFromAnonymousAdmin: data.isFromAnonymousAdmin.present
          ? data.isFromAnonymousAdmin.value
          : this.isFromAnonymousAdmin,
      isSilent: data.isSilent.present ? data.isSilent.value : this.isSilent,
      commentsCount: data.commentsCount.present
          ? data.commentsCount.value
          : this.commentsCount,
      recentRepliersJson: data.recentRepliersJson.present
          ? data.recentRepliersJson.value
          : this.recentRepliersJson,
      threadRootMessageId: data.threadRootMessageId.present
          ? data.threadRootMessageId.value
          : this.threadRootMessageId,
      hasMediaSpoiler: data.hasMediaSpoiler.present
          ? data.hasMediaSpoiler.value
          : this.hasMediaSpoiler,
      expiresAt: data.expiresAt.present ? data.expiresAt.value : this.expiresAt,
      ttlSeconds:
          data.ttlSeconds.present ? data.ttlSeconds.value : this.ttlSeconds,
      isViewOnce:
          data.isViewOnce.present ? data.isViewOnce.value : this.isViewOnce,
      viewedAt: data.viewedAt.present ? data.viewedAt.value : this.viewedAt,
      isBurned: data.isBurned.present ? data.isBurned.value : this.isBurned,
      replyToChatId: data.replyToChatId.present
          ? data.replyToChatId.value
          : this.replyToChatId,
      replyToChatName: data.replyToChatName.present
          ? data.replyToChatName.value
          : this.replyToChatName,
      replyToChatType: data.replyToChatType.present
          ? data.replyToChatType.value
          : this.replyToChatType,
      effectId: data.effectId.present ? data.effectId.value : this.effectId,
      savedTagsJson: data.savedTagsJson.present
          ? data.savedTagsJson.value
          : this.savedTagsJson,
      topicId: data.topicId.present ? data.topicId.value : this.topicId,
      forwardsCount: data.forwardsCount.present
          ? data.forwardsCount.value
          : this.forwardsCount,
      senderChatId: data.senderChatId.present
          ? data.senderChatId.value
          : this.senderChatId,
      senderChatName: data.senderChatName.present
          ? data.senderChatName.value
          : this.senderChatName,
      senderChatAvatarUrl: data.senderChatAvatarUrl.present
          ? data.senderChatAvatarUrl.value
          : this.senderChatAvatarUrl,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbMessage(')
          ..write('localId: $localId, ')
          ..write('serverId: $serverId, ')
          ..write('chatId: $chatId, ')
          ..write('senderId: $senderId, ')
          ..write('content: $content, ')
          ..write('messageType: $messageType, ')
          ..write('fileUrl: $fileUrl, ')
          ..write('fileName: $fileName, ')
          ..write('replyToMessageId: $replyToMessageId, ')
          ..write('isQuote: $isQuote, ')
          ..write('quoteText: $quoteText, ')
          ..write('quoteOffset: $quoteOffset, ')
          ..write('quoteLength: $quoteLength, ')
          ..write('replyToSenderId: $replyToSenderId, ')
          ..write('replyToSenderName: $replyToSenderName, ')
          ..write('replyToContent: $replyToContent, ')
          ..write('replyToMessageType: $replyToMessageType, ')
          ..write('isRead: $isRead, ')
          ..write('isEdited: $isEdited, ')
          ..write('sendStatus: $sendStatus, ')
          ..write('senderName: $senderName, ')
          ..write('senderAvatarUrl: $senderAvatarUrl, ')
          ..write('createdAt: $createdAt, ')
          ..write('isForward: $isForward, ')
          ..write('forwardFromId: $forwardFromId, ')
          ..write('forwardFromName: $forwardFromName, ')
          ..write('forwardFromAvatarUrl: $forwardFromAvatarUrl, ')
          ..write('senderCustomizationJson: $senderCustomizationJson, ')
          ..write('groupedId: $groupedId, ')
          ..write('entities: $entities, ')
          ..write('reactions: $reactions, ')
          ..write('linkPreviewOptions: $linkPreviewOptions, ')
          ..write('invertMedia: $invertMedia, ')
          ..write('isRound: $isRound, ')
          ..write('mediaPayload: $mediaPayload, ')
          ..write('viewsCount: $viewsCount, ')
          ..write('authorSignature: $authorSignature, ')
          ..write('postAuthorId: $postAuthorId, ')
          ..write('senderRole: $senderRole, ')
          ..write('senderAdminTitle: $senderAdminTitle, ')
          ..write('isFromAnonymousAdmin: $isFromAnonymousAdmin, ')
          ..write('isSilent: $isSilent, ')
          ..write('commentsCount: $commentsCount, ')
          ..write('recentRepliersJson: $recentRepliersJson, ')
          ..write('threadRootMessageId: $threadRootMessageId, ')
          ..write('hasMediaSpoiler: $hasMediaSpoiler, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('ttlSeconds: $ttlSeconds, ')
          ..write('isViewOnce: $isViewOnce, ')
          ..write('viewedAt: $viewedAt, ')
          ..write('isBurned: $isBurned, ')
          ..write('replyToChatId: $replyToChatId, ')
          ..write('replyToChatName: $replyToChatName, ')
          ..write('replyToChatType: $replyToChatType, ')
          ..write('effectId: $effectId, ')
          ..write('savedTagsJson: $savedTagsJson, ')
          ..write('topicId: $topicId, ')
          ..write('forwardsCount: $forwardsCount, ')
          ..write('senderChatId: $senderChatId, ')
          ..write('senderChatName: $senderChatName, ')
          ..write('senderChatAvatarUrl: $senderChatAvatarUrl')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
        localId,
        serverId,
        chatId,
        senderId,
        content,
        messageType,
        fileUrl,
        fileName,
        replyToMessageId,
        isQuote,
        quoteText,
        quoteOffset,
        quoteLength,
        replyToSenderId,
        replyToSenderName,
        replyToContent,
        replyToMessageType,
        isRead,
        isEdited,
        sendStatus,
        senderName,
        senderAvatarUrl,
        createdAt,
        isForward,
        forwardFromId,
        forwardFromName,
        forwardFromAvatarUrl,
        senderCustomizationJson,
        groupedId,
        entities,
        reactions,
        linkPreviewOptions,
        invertMedia,
        isRound,
        mediaPayload,
        viewsCount,
        authorSignature,
        postAuthorId,
        senderRole,
        senderAdminTitle,
        isFromAnonymousAdmin,
        isSilent,
        commentsCount,
        recentRepliersJson,
        threadRootMessageId,
        hasMediaSpoiler,
        expiresAt,
        ttlSeconds,
        isViewOnce,
        viewedAt,
        isBurned,
        replyToChatId,
        replyToChatName,
        replyToChatType,
        effectId,
        savedTagsJson,
        topicId,
        forwardsCount,
        senderChatId,
        senderChatName,
        senderChatAvatarUrl
      ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbMessage &&
          other.localId == this.localId &&
          other.serverId == this.serverId &&
          other.chatId == this.chatId &&
          other.senderId == this.senderId &&
          other.content == this.content &&
          other.messageType == this.messageType &&
          other.fileUrl == this.fileUrl &&
          other.fileName == this.fileName &&
          other.replyToMessageId == this.replyToMessageId &&
          other.isQuote == this.isQuote &&
          other.quoteText == this.quoteText &&
          other.quoteOffset == this.quoteOffset &&
          other.quoteLength == this.quoteLength &&
          other.replyToSenderId == this.replyToSenderId &&
          other.replyToSenderName == this.replyToSenderName &&
          other.replyToContent == this.replyToContent &&
          other.replyToMessageType == this.replyToMessageType &&
          other.isRead == this.isRead &&
          other.isEdited == this.isEdited &&
          other.sendStatus == this.sendStatus &&
          other.senderName == this.senderName &&
          other.senderAvatarUrl == this.senderAvatarUrl &&
          other.createdAt == this.createdAt &&
          other.isForward == this.isForward &&
          other.forwardFromId == this.forwardFromId &&
          other.forwardFromName == this.forwardFromName &&
          other.forwardFromAvatarUrl == this.forwardFromAvatarUrl &&
          other.senderCustomizationJson == this.senderCustomizationJson &&
          other.groupedId == this.groupedId &&
          other.entities == this.entities &&
          other.reactions == this.reactions &&
          other.linkPreviewOptions == this.linkPreviewOptions &&
          other.invertMedia == this.invertMedia &&
          other.isRound == this.isRound &&
          other.mediaPayload == this.mediaPayload &&
          other.viewsCount == this.viewsCount &&
          other.authorSignature == this.authorSignature &&
          other.postAuthorId == this.postAuthorId &&
          other.senderRole == this.senderRole &&
          other.senderAdminTitle == this.senderAdminTitle &&
          other.isFromAnonymousAdmin == this.isFromAnonymousAdmin &&
          other.isSilent == this.isSilent &&
          other.commentsCount == this.commentsCount &&
          other.recentRepliersJson == this.recentRepliersJson &&
          other.threadRootMessageId == this.threadRootMessageId &&
          other.hasMediaSpoiler == this.hasMediaSpoiler &&
          other.expiresAt == this.expiresAt &&
          other.ttlSeconds == this.ttlSeconds &&
          other.isViewOnce == this.isViewOnce &&
          other.viewedAt == this.viewedAt &&
          other.isBurned == this.isBurned &&
          other.replyToChatId == this.replyToChatId &&
          other.replyToChatName == this.replyToChatName &&
          other.replyToChatType == this.replyToChatType &&
          other.effectId == this.effectId &&
          other.savedTagsJson == this.savedTagsJson &&
          other.topicId == this.topicId &&
          other.forwardsCount == this.forwardsCount &&
          other.senderChatId == this.senderChatId &&
          other.senderChatName == this.senderChatName &&
          other.senderChatAvatarUrl == this.senderChatAvatarUrl);
}

class MessagesCompanion extends UpdateCompanion<DbMessage> {
  final Value<String> localId;
  final Value<String?> serverId;
  final Value<String> chatId;
  final Value<String> senderId;
  final Value<String> content;
  final Value<String> messageType;
  final Value<String?> fileUrl;
  final Value<String?> fileName;
  final Value<String?> replyToMessageId;
  final Value<bool> isQuote;
  final Value<String?> quoteText;
  final Value<int> quoteOffset;
  final Value<int> quoteLength;
  final Value<String?> replyToSenderId;
  final Value<String?> replyToSenderName;
  final Value<String?> replyToContent;
  final Value<String> replyToMessageType;
  final Value<bool> isRead;
  final Value<bool> isEdited;
  final Value<int> sendStatus;
  final Value<String?> senderName;
  final Value<String?> senderAvatarUrl;
  final Value<String> createdAt;
  final Value<bool> isForward;
  final Value<String?> forwardFromId;
  final Value<String?> forwardFromName;
  final Value<String?> forwardFromAvatarUrl;
  final Value<String?> senderCustomizationJson;
  final Value<String?> groupedId;
  final Value<String?> entities;
  final Value<String?> reactions;
  final Value<String?> linkPreviewOptions;
  final Value<bool> invertMedia;
  final Value<bool> isRound;
  final Value<String?> mediaPayload;
  final Value<int> viewsCount;
  final Value<String?> authorSignature;
  final Value<String?> postAuthorId;
  final Value<String?> senderRole;
  final Value<String?> senderAdminTitle;
  final Value<bool> isFromAnonymousAdmin;
  final Value<bool> isSilent;
  final Value<int> commentsCount;
  final Value<String?> recentRepliersJson;
  final Value<String?> threadRootMessageId;
  final Value<bool> hasMediaSpoiler;
  final Value<String?> expiresAt;
  final Value<int> ttlSeconds;
  final Value<bool> isViewOnce;
  final Value<String?> viewedAt;
  final Value<bool> isBurned;
  final Value<String?> replyToChatId;
  final Value<String?> replyToChatName;
  final Value<String?> replyToChatType;
  final Value<String?> effectId;
  final Value<String?> savedTagsJson;
  final Value<int?> topicId;
  final Value<int> forwardsCount;
  final Value<String?> senderChatId;
  final Value<String?> senderChatName;
  final Value<String?> senderChatAvatarUrl;
  final Value<int> rowid;
  const MessagesCompanion({
    this.localId = const Value.absent(),
    this.serverId = const Value.absent(),
    this.chatId = const Value.absent(),
    this.senderId = const Value.absent(),
    this.content = const Value.absent(),
    this.messageType = const Value.absent(),
    this.fileUrl = const Value.absent(),
    this.fileName = const Value.absent(),
    this.replyToMessageId = const Value.absent(),
    this.isQuote = const Value.absent(),
    this.quoteText = const Value.absent(),
    this.quoteOffset = const Value.absent(),
    this.quoteLength = const Value.absent(),
    this.replyToSenderId = const Value.absent(),
    this.replyToSenderName = const Value.absent(),
    this.replyToContent = const Value.absent(),
    this.replyToMessageType = const Value.absent(),
    this.isRead = const Value.absent(),
    this.isEdited = const Value.absent(),
    this.sendStatus = const Value.absent(),
    this.senderName = const Value.absent(),
    this.senderAvatarUrl = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.isForward = const Value.absent(),
    this.forwardFromId = const Value.absent(),
    this.forwardFromName = const Value.absent(),
    this.forwardFromAvatarUrl = const Value.absent(),
    this.senderCustomizationJson = const Value.absent(),
    this.groupedId = const Value.absent(),
    this.entities = const Value.absent(),
    this.reactions = const Value.absent(),
    this.linkPreviewOptions = const Value.absent(),
    this.invertMedia = const Value.absent(),
    this.isRound = const Value.absent(),
    this.mediaPayload = const Value.absent(),
    this.viewsCount = const Value.absent(),
    this.authorSignature = const Value.absent(),
    this.postAuthorId = const Value.absent(),
    this.senderRole = const Value.absent(),
    this.senderAdminTitle = const Value.absent(),
    this.isFromAnonymousAdmin = const Value.absent(),
    this.isSilent = const Value.absent(),
    this.commentsCount = const Value.absent(),
    this.recentRepliersJson = const Value.absent(),
    this.threadRootMessageId = const Value.absent(),
    this.hasMediaSpoiler = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.ttlSeconds = const Value.absent(),
    this.isViewOnce = const Value.absent(),
    this.viewedAt = const Value.absent(),
    this.isBurned = const Value.absent(),
    this.replyToChatId = const Value.absent(),
    this.replyToChatName = const Value.absent(),
    this.replyToChatType = const Value.absent(),
    this.effectId = const Value.absent(),
    this.savedTagsJson = const Value.absent(),
    this.topicId = const Value.absent(),
    this.forwardsCount = const Value.absent(),
    this.senderChatId = const Value.absent(),
    this.senderChatName = const Value.absent(),
    this.senderChatAvatarUrl = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MessagesCompanion.insert({
    required String localId,
    this.serverId = const Value.absent(),
    required String chatId,
    required String senderId,
    required String content,
    this.messageType = const Value.absent(),
    this.fileUrl = const Value.absent(),
    this.fileName = const Value.absent(),
    this.replyToMessageId = const Value.absent(),
    this.isQuote = const Value.absent(),
    this.quoteText = const Value.absent(),
    this.quoteOffset = const Value.absent(),
    this.quoteLength = const Value.absent(),
    this.replyToSenderId = const Value.absent(),
    this.replyToSenderName = const Value.absent(),
    this.replyToContent = const Value.absent(),
    this.replyToMessageType = const Value.absent(),
    this.isRead = const Value.absent(),
    this.isEdited = const Value.absent(),
    this.sendStatus = const Value.absent(),
    this.senderName = const Value.absent(),
    this.senderAvatarUrl = const Value.absent(),
    required String createdAt,
    this.isForward = const Value.absent(),
    this.forwardFromId = const Value.absent(),
    this.forwardFromName = const Value.absent(),
    this.forwardFromAvatarUrl = const Value.absent(),
    this.senderCustomizationJson = const Value.absent(),
    this.groupedId = const Value.absent(),
    this.entities = const Value.absent(),
    this.reactions = const Value.absent(),
    this.linkPreviewOptions = const Value.absent(),
    this.invertMedia = const Value.absent(),
    this.isRound = const Value.absent(),
    this.mediaPayload = const Value.absent(),
    this.viewsCount = const Value.absent(),
    this.authorSignature = const Value.absent(),
    this.postAuthorId = const Value.absent(),
    this.senderRole = const Value.absent(),
    this.senderAdminTitle = const Value.absent(),
    this.isFromAnonymousAdmin = const Value.absent(),
    this.isSilent = const Value.absent(),
    this.commentsCount = const Value.absent(),
    this.recentRepliersJson = const Value.absent(),
    this.threadRootMessageId = const Value.absent(),
    this.hasMediaSpoiler = const Value.absent(),
    this.expiresAt = const Value.absent(),
    this.ttlSeconds = const Value.absent(),
    this.isViewOnce = const Value.absent(),
    this.viewedAt = const Value.absent(),
    this.isBurned = const Value.absent(),
    this.replyToChatId = const Value.absent(),
    this.replyToChatName = const Value.absent(),
    this.replyToChatType = const Value.absent(),
    this.effectId = const Value.absent(),
    this.savedTagsJson = const Value.absent(),
    this.topicId = const Value.absent(),
    this.forwardsCount = const Value.absent(),
    this.senderChatId = const Value.absent(),
    this.senderChatName = const Value.absent(),
    this.senderChatAvatarUrl = const Value.absent(),
    this.rowid = const Value.absent(),
  })  : localId = Value(localId),
        chatId = Value(chatId),
        senderId = Value(senderId),
        content = Value(content),
        createdAt = Value(createdAt);
  static Insertable<DbMessage> custom({
    Expression<String>? localId,
    Expression<String>? serverId,
    Expression<String>? chatId,
    Expression<String>? senderId,
    Expression<String>? content,
    Expression<String>? messageType,
    Expression<String>? fileUrl,
    Expression<String>? fileName,
    Expression<String>? replyToMessageId,
    Expression<bool>? isQuote,
    Expression<String>? quoteText,
    Expression<int>? quoteOffset,
    Expression<int>? quoteLength,
    Expression<String>? replyToSenderId,
    Expression<String>? replyToSenderName,
    Expression<String>? replyToContent,
    Expression<String>? replyToMessageType,
    Expression<bool>? isRead,
    Expression<bool>? isEdited,
    Expression<int>? sendStatus,
    Expression<String>? senderName,
    Expression<String>? senderAvatarUrl,
    Expression<String>? createdAt,
    Expression<bool>? isForward,
    Expression<String>? forwardFromId,
    Expression<String>? forwardFromName,
    Expression<String>? forwardFromAvatarUrl,
    Expression<String>? senderCustomizationJson,
    Expression<String>? groupedId,
    Expression<String>? entities,
    Expression<String>? reactions,
    Expression<String>? linkPreviewOptions,
    Expression<bool>? invertMedia,
    Expression<bool>? isRound,
    Expression<String>? mediaPayload,
    Expression<int>? viewsCount,
    Expression<String>? authorSignature,
    Expression<String>? postAuthorId,
    Expression<String>? senderRole,
    Expression<String>? senderAdminTitle,
    Expression<bool>? isFromAnonymousAdmin,
    Expression<bool>? isSilent,
    Expression<int>? commentsCount,
    Expression<String>? recentRepliersJson,
    Expression<String>? threadRootMessageId,
    Expression<bool>? hasMediaSpoiler,
    Expression<String>? expiresAt,
    Expression<int>? ttlSeconds,
    Expression<bool>? isViewOnce,
    Expression<String>? viewedAt,
    Expression<bool>? isBurned,
    Expression<String>? replyToChatId,
    Expression<String>? replyToChatName,
    Expression<String>? replyToChatType,
    Expression<String>? effectId,
    Expression<String>? savedTagsJson,
    Expression<int>? topicId,
    Expression<int>? forwardsCount,
    Expression<String>? senderChatId,
    Expression<String>? senderChatName,
    Expression<String>? senderChatAvatarUrl,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (localId != null) 'local_id': localId,
      if (serverId != null) 'server_id': serverId,
      if (chatId != null) 'chat_id': chatId,
      if (senderId != null) 'sender_id': senderId,
      if (content != null) 'content': content,
      if (messageType != null) 'message_type': messageType,
      if (fileUrl != null) 'file_url': fileUrl,
      if (fileName != null) 'file_name': fileName,
      if (replyToMessageId != null) 'reply_to_message_id': replyToMessageId,
      if (isQuote != null) 'is_quote': isQuote,
      if (quoteText != null) 'quote_text': quoteText,
      if (quoteOffset != null) 'quote_offset': quoteOffset,
      if (quoteLength != null) 'quote_length': quoteLength,
      if (replyToSenderId != null) 'reply_to_sender_id': replyToSenderId,
      if (replyToSenderName != null) 'reply_to_sender_name': replyToSenderName,
      if (replyToContent != null) 'reply_to_content': replyToContent,
      if (replyToMessageType != null)
        'reply_to_message_type': replyToMessageType,
      if (isRead != null) 'is_read': isRead,
      if (isEdited != null) 'is_edited': isEdited,
      if (sendStatus != null) 'send_status': sendStatus,
      if (senderName != null) 'sender_name': senderName,
      if (senderAvatarUrl != null) 'sender_avatar_url': senderAvatarUrl,
      if (createdAt != null) 'created_at': createdAt,
      if (isForward != null) 'is_forward': isForward,
      if (forwardFromId != null) 'forward_from_id': forwardFromId,
      if (forwardFromName != null) 'forward_from_name': forwardFromName,
      if (forwardFromAvatarUrl != null)
        'forward_from_avatar_url': forwardFromAvatarUrl,
      if (senderCustomizationJson != null)
        'sender_customization_json': senderCustomizationJson,
      if (groupedId != null) 'grouped_id': groupedId,
      if (entities != null) 'entities': entities,
      if (reactions != null) 'reactions': reactions,
      if (linkPreviewOptions != null)
        'link_preview_options': linkPreviewOptions,
      if (invertMedia != null) 'invert_media': invertMedia,
      if (isRound != null) 'is_round': isRound,
      if (mediaPayload != null) 'media_payload': mediaPayload,
      if (viewsCount != null) 'views_count': viewsCount,
      if (authorSignature != null) 'author_signature': authorSignature,
      if (postAuthorId != null) 'post_author_id': postAuthorId,
      if (senderRole != null) 'sender_role': senderRole,
      if (senderAdminTitle != null) 'sender_admin_title': senderAdminTitle,
      if (isFromAnonymousAdmin != null)
        'is_from_anonymous_admin': isFromAnonymousAdmin,
      if (isSilent != null) 'is_silent': isSilent,
      if (commentsCount != null) 'comments_count': commentsCount,
      if (recentRepliersJson != null)
        'recent_repliers_json': recentRepliersJson,
      if (threadRootMessageId != null)
        'thread_root_message_id': threadRootMessageId,
      if (hasMediaSpoiler != null) 'has_media_spoiler': hasMediaSpoiler,
      if (expiresAt != null) 'expires_at': expiresAt,
      if (ttlSeconds != null) 'ttl_seconds': ttlSeconds,
      if (isViewOnce != null) 'is_view_once': isViewOnce,
      if (viewedAt != null) 'viewed_at': viewedAt,
      if (isBurned != null) 'is_burned': isBurned,
      if (replyToChatId != null) 'reply_to_chat_id': replyToChatId,
      if (replyToChatName != null) 'reply_to_chat_name': replyToChatName,
      if (replyToChatType != null) 'reply_to_chat_type': replyToChatType,
      if (effectId != null) 'effect_id': effectId,
      if (savedTagsJson != null) 'saved_tags_json': savedTagsJson,
      if (topicId != null) 'topic_id': topicId,
      if (forwardsCount != null) 'forwards_count': forwardsCount,
      if (senderChatId != null) 'sender_chat_id': senderChatId,
      if (senderChatName != null) 'sender_chat_name': senderChatName,
      if (senderChatAvatarUrl != null)
        'sender_chat_avatar_url': senderChatAvatarUrl,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MessagesCompanion copyWith(
      {Value<String>? localId,
      Value<String?>? serverId,
      Value<String>? chatId,
      Value<String>? senderId,
      Value<String>? content,
      Value<String>? messageType,
      Value<String?>? fileUrl,
      Value<String?>? fileName,
      Value<String?>? replyToMessageId,
      Value<bool>? isQuote,
      Value<String?>? quoteText,
      Value<int>? quoteOffset,
      Value<int>? quoteLength,
      Value<String?>? replyToSenderId,
      Value<String?>? replyToSenderName,
      Value<String?>? replyToContent,
      Value<String>? replyToMessageType,
      Value<bool>? isRead,
      Value<bool>? isEdited,
      Value<int>? sendStatus,
      Value<String?>? senderName,
      Value<String?>? senderAvatarUrl,
      Value<String>? createdAt,
      Value<bool>? isForward,
      Value<String?>? forwardFromId,
      Value<String?>? forwardFromName,
      Value<String?>? forwardFromAvatarUrl,
      Value<String?>? senderCustomizationJson,
      Value<String?>? groupedId,
      Value<String?>? entities,
      Value<String?>? reactions,
      Value<String?>? linkPreviewOptions,
      Value<bool>? invertMedia,
      Value<bool>? isRound,
      Value<String?>? mediaPayload,
      Value<int>? viewsCount,
      Value<String?>? authorSignature,
      Value<String?>? postAuthorId,
      Value<String?>? senderRole,
      Value<String?>? senderAdminTitle,
      Value<bool>? isFromAnonymousAdmin,
      Value<bool>? isSilent,
      Value<int>? commentsCount,
      Value<String?>? recentRepliersJson,
      Value<String?>? threadRootMessageId,
      Value<bool>? hasMediaSpoiler,
      Value<String?>? expiresAt,
      Value<int>? ttlSeconds,
      Value<bool>? isViewOnce,
      Value<String?>? viewedAt,
      Value<bool>? isBurned,
      Value<String?>? replyToChatId,
      Value<String?>? replyToChatName,
      Value<String?>? replyToChatType,
      Value<String?>? effectId,
      Value<String?>? savedTagsJson,
      Value<int?>? topicId,
      Value<int>? forwardsCount,
      Value<String?>? senderChatId,
      Value<String?>? senderChatName,
      Value<String?>? senderChatAvatarUrl,
      Value<int>? rowid}) {
    return MessagesCompanion(
      localId: localId ?? this.localId,
      serverId: serverId ?? this.serverId,
      chatId: chatId ?? this.chatId,
      senderId: senderId ?? this.senderId,
      content: content ?? this.content,
      messageType: messageType ?? this.messageType,
      fileUrl: fileUrl ?? this.fileUrl,
      fileName: fileName ?? this.fileName,
      replyToMessageId: replyToMessageId ?? this.replyToMessageId,
      isQuote: isQuote ?? this.isQuote,
      quoteText: quoteText ?? this.quoteText,
      quoteOffset: quoteOffset ?? this.quoteOffset,
      quoteLength: quoteLength ?? this.quoteLength,
      replyToSenderId: replyToSenderId ?? this.replyToSenderId,
      replyToSenderName: replyToSenderName ?? this.replyToSenderName,
      replyToContent: replyToContent ?? this.replyToContent,
      replyToMessageType: replyToMessageType ?? this.replyToMessageType,
      isRead: isRead ?? this.isRead,
      isEdited: isEdited ?? this.isEdited,
      sendStatus: sendStatus ?? this.sendStatus,
      senderName: senderName ?? this.senderName,
      senderAvatarUrl: senderAvatarUrl ?? this.senderAvatarUrl,
      createdAt: createdAt ?? this.createdAt,
      isForward: isForward ?? this.isForward,
      forwardFromId: forwardFromId ?? this.forwardFromId,
      forwardFromName: forwardFromName ?? this.forwardFromName,
      forwardFromAvatarUrl: forwardFromAvatarUrl ?? this.forwardFromAvatarUrl,
      senderCustomizationJson:
          senderCustomizationJson ?? this.senderCustomizationJson,
      groupedId: groupedId ?? this.groupedId,
      entities: entities ?? this.entities,
      reactions: reactions ?? this.reactions,
      linkPreviewOptions: linkPreviewOptions ?? this.linkPreviewOptions,
      invertMedia: invertMedia ?? this.invertMedia,
      isRound: isRound ?? this.isRound,
      mediaPayload: mediaPayload ?? this.mediaPayload,
      viewsCount: viewsCount ?? this.viewsCount,
      authorSignature: authorSignature ?? this.authorSignature,
      postAuthorId: postAuthorId ?? this.postAuthorId,
      senderRole: senderRole ?? this.senderRole,
      senderAdminTitle: senderAdminTitle ?? this.senderAdminTitle,
      isFromAnonymousAdmin: isFromAnonymousAdmin ?? this.isFromAnonymousAdmin,
      isSilent: isSilent ?? this.isSilent,
      commentsCount: commentsCount ?? this.commentsCount,
      recentRepliersJson: recentRepliersJson ?? this.recentRepliersJson,
      threadRootMessageId: threadRootMessageId ?? this.threadRootMessageId,
      hasMediaSpoiler: hasMediaSpoiler ?? this.hasMediaSpoiler,
      expiresAt: expiresAt ?? this.expiresAt,
      ttlSeconds: ttlSeconds ?? this.ttlSeconds,
      isViewOnce: isViewOnce ?? this.isViewOnce,
      viewedAt: viewedAt ?? this.viewedAt,
      isBurned: isBurned ?? this.isBurned,
      replyToChatId: replyToChatId ?? this.replyToChatId,
      replyToChatName: replyToChatName ?? this.replyToChatName,
      replyToChatType: replyToChatType ?? this.replyToChatType,
      effectId: effectId ?? this.effectId,
      savedTagsJson: savedTagsJson ?? this.savedTagsJson,
      topicId: topicId ?? this.topicId,
      forwardsCount: forwardsCount ?? this.forwardsCount,
      senderChatId: senderChatId ?? this.senderChatId,
      senderChatName: senderChatName ?? this.senderChatName,
      senderChatAvatarUrl: senderChatAvatarUrl ?? this.senderChatAvatarUrl,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (localId.present) {
      map['local_id'] = Variable<String>(localId.value);
    }
    if (serverId.present) {
      map['server_id'] = Variable<String>(serverId.value);
    }
    if (chatId.present) {
      map['chat_id'] = Variable<String>(chatId.value);
    }
    if (senderId.present) {
      map['sender_id'] = Variable<String>(senderId.value);
    }
    if (content.present) {
      map['content'] = Variable<String>(content.value);
    }
    if (messageType.present) {
      map['message_type'] = Variable<String>(messageType.value);
    }
    if (fileUrl.present) {
      map['file_url'] = Variable<String>(fileUrl.value);
    }
    if (fileName.present) {
      map['file_name'] = Variable<String>(fileName.value);
    }
    if (replyToMessageId.present) {
      map['reply_to_message_id'] = Variable<String>(replyToMessageId.value);
    }
    if (isQuote.present) {
      map['is_quote'] = Variable<bool>(isQuote.value);
    }
    if (quoteText.present) {
      map['quote_text'] = Variable<String>(quoteText.value);
    }
    if (quoteOffset.present) {
      map['quote_offset'] = Variable<int>(quoteOffset.value);
    }
    if (quoteLength.present) {
      map['quote_length'] = Variable<int>(quoteLength.value);
    }
    if (replyToSenderId.present) {
      map['reply_to_sender_id'] = Variable<String>(replyToSenderId.value);
    }
    if (replyToSenderName.present) {
      map['reply_to_sender_name'] = Variable<String>(replyToSenderName.value);
    }
    if (replyToContent.present) {
      map['reply_to_content'] = Variable<String>(replyToContent.value);
    }
    if (replyToMessageType.present) {
      map['reply_to_message_type'] = Variable<String>(replyToMessageType.value);
    }
    if (isRead.present) {
      map['is_read'] = Variable<bool>(isRead.value);
    }
    if (isEdited.present) {
      map['is_edited'] = Variable<bool>(isEdited.value);
    }
    if (sendStatus.present) {
      map['send_status'] = Variable<int>(sendStatus.value);
    }
    if (senderName.present) {
      map['sender_name'] = Variable<String>(senderName.value);
    }
    if (senderAvatarUrl.present) {
      map['sender_avatar_url'] = Variable<String>(senderAvatarUrl.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    if (isForward.present) {
      map['is_forward'] = Variable<bool>(isForward.value);
    }
    if (forwardFromId.present) {
      map['forward_from_id'] = Variable<String>(forwardFromId.value);
    }
    if (forwardFromName.present) {
      map['forward_from_name'] = Variable<String>(forwardFromName.value);
    }
    if (forwardFromAvatarUrl.present) {
      map['forward_from_avatar_url'] =
          Variable<String>(forwardFromAvatarUrl.value);
    }
    if (senderCustomizationJson.present) {
      map['sender_customization_json'] =
          Variable<String>(senderCustomizationJson.value);
    }
    if (groupedId.present) {
      map['grouped_id'] = Variable<String>(groupedId.value);
    }
    if (entities.present) {
      map['entities'] = Variable<String>(entities.value);
    }
    if (reactions.present) {
      map['reactions'] = Variable<String>(reactions.value);
    }
    if (linkPreviewOptions.present) {
      map['link_preview_options'] = Variable<String>(linkPreviewOptions.value);
    }
    if (invertMedia.present) {
      map['invert_media'] = Variable<bool>(invertMedia.value);
    }
    if (isRound.present) {
      map['is_round'] = Variable<bool>(isRound.value);
    }
    if (mediaPayload.present) {
      map['media_payload'] = Variable<String>(mediaPayload.value);
    }
    if (viewsCount.present) {
      map['views_count'] = Variable<int>(viewsCount.value);
    }
    if (authorSignature.present) {
      map['author_signature'] = Variable<String>(authorSignature.value);
    }
    if (postAuthorId.present) {
      map['post_author_id'] = Variable<String>(postAuthorId.value);
    }
    if (senderRole.present) {
      map['sender_role'] = Variable<String>(senderRole.value);
    }
    if (senderAdminTitle.present) {
      map['sender_admin_title'] = Variable<String>(senderAdminTitle.value);
    }
    if (isFromAnonymousAdmin.present) {
      map['is_from_anonymous_admin'] =
          Variable<bool>(isFromAnonymousAdmin.value);
    }
    if (isSilent.present) {
      map['is_silent'] = Variable<bool>(isSilent.value);
    }
    if (commentsCount.present) {
      map['comments_count'] = Variable<int>(commentsCount.value);
    }
    if (recentRepliersJson.present) {
      map['recent_repliers_json'] = Variable<String>(recentRepliersJson.value);
    }
    if (threadRootMessageId.present) {
      map['thread_root_message_id'] =
          Variable<String>(threadRootMessageId.value);
    }
    if (hasMediaSpoiler.present) {
      map['has_media_spoiler'] = Variable<bool>(hasMediaSpoiler.value);
    }
    if (expiresAt.present) {
      map['expires_at'] = Variable<String>(expiresAt.value);
    }
    if (ttlSeconds.present) {
      map['ttl_seconds'] = Variable<int>(ttlSeconds.value);
    }
    if (isViewOnce.present) {
      map['is_view_once'] = Variable<bool>(isViewOnce.value);
    }
    if (viewedAt.present) {
      map['viewed_at'] = Variable<String>(viewedAt.value);
    }
    if (isBurned.present) {
      map['is_burned'] = Variable<bool>(isBurned.value);
    }
    if (replyToChatId.present) {
      map['reply_to_chat_id'] = Variable<String>(replyToChatId.value);
    }
    if (replyToChatName.present) {
      map['reply_to_chat_name'] = Variable<String>(replyToChatName.value);
    }
    if (replyToChatType.present) {
      map['reply_to_chat_type'] = Variable<String>(replyToChatType.value);
    }
    if (effectId.present) {
      map['effect_id'] = Variable<String>(effectId.value);
    }
    if (savedTagsJson.present) {
      map['saved_tags_json'] = Variable<String>(savedTagsJson.value);
    }
    if (topicId.present) {
      map['topic_id'] = Variable<int>(topicId.value);
    }
    if (forwardsCount.present) {
      map['forwards_count'] = Variable<int>(forwardsCount.value);
    }
    if (senderChatId.present) {
      map['sender_chat_id'] = Variable<String>(senderChatId.value);
    }
    if (senderChatName.present) {
      map['sender_chat_name'] = Variable<String>(senderChatName.value);
    }
    if (senderChatAvatarUrl.present) {
      map['sender_chat_avatar_url'] =
          Variable<String>(senderChatAvatarUrl.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MessagesCompanion(')
          ..write('localId: $localId, ')
          ..write('serverId: $serverId, ')
          ..write('chatId: $chatId, ')
          ..write('senderId: $senderId, ')
          ..write('content: $content, ')
          ..write('messageType: $messageType, ')
          ..write('fileUrl: $fileUrl, ')
          ..write('fileName: $fileName, ')
          ..write('replyToMessageId: $replyToMessageId, ')
          ..write('isQuote: $isQuote, ')
          ..write('quoteText: $quoteText, ')
          ..write('quoteOffset: $quoteOffset, ')
          ..write('quoteLength: $quoteLength, ')
          ..write('replyToSenderId: $replyToSenderId, ')
          ..write('replyToSenderName: $replyToSenderName, ')
          ..write('replyToContent: $replyToContent, ')
          ..write('replyToMessageType: $replyToMessageType, ')
          ..write('isRead: $isRead, ')
          ..write('isEdited: $isEdited, ')
          ..write('sendStatus: $sendStatus, ')
          ..write('senderName: $senderName, ')
          ..write('senderAvatarUrl: $senderAvatarUrl, ')
          ..write('createdAt: $createdAt, ')
          ..write('isForward: $isForward, ')
          ..write('forwardFromId: $forwardFromId, ')
          ..write('forwardFromName: $forwardFromName, ')
          ..write('forwardFromAvatarUrl: $forwardFromAvatarUrl, ')
          ..write('senderCustomizationJson: $senderCustomizationJson, ')
          ..write('groupedId: $groupedId, ')
          ..write('entities: $entities, ')
          ..write('reactions: $reactions, ')
          ..write('linkPreviewOptions: $linkPreviewOptions, ')
          ..write('invertMedia: $invertMedia, ')
          ..write('isRound: $isRound, ')
          ..write('mediaPayload: $mediaPayload, ')
          ..write('viewsCount: $viewsCount, ')
          ..write('authorSignature: $authorSignature, ')
          ..write('postAuthorId: $postAuthorId, ')
          ..write('senderRole: $senderRole, ')
          ..write('senderAdminTitle: $senderAdminTitle, ')
          ..write('isFromAnonymousAdmin: $isFromAnonymousAdmin, ')
          ..write('isSilent: $isSilent, ')
          ..write('commentsCount: $commentsCount, ')
          ..write('recentRepliersJson: $recentRepliersJson, ')
          ..write('threadRootMessageId: $threadRootMessageId, ')
          ..write('hasMediaSpoiler: $hasMediaSpoiler, ')
          ..write('expiresAt: $expiresAt, ')
          ..write('ttlSeconds: $ttlSeconds, ')
          ..write('isViewOnce: $isViewOnce, ')
          ..write('viewedAt: $viewedAt, ')
          ..write('isBurned: $isBurned, ')
          ..write('replyToChatId: $replyToChatId, ')
          ..write('replyToChatName: $replyToChatName, ')
          ..write('replyToChatType: $replyToChatType, ')
          ..write('effectId: $effectId, ')
          ..write('savedTagsJson: $savedTagsJson, ')
          ..write('topicId: $topicId, ')
          ..write('forwardsCount: $forwardsCount, ')
          ..write('senderChatId: $senderChatId, ')
          ..write('senderChatName: $senderChatName, ')
          ..write('senderChatAvatarUrl: $senderChatAvatarUrl, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncStatesTable extends SyncStates
    with TableInfo<$SyncStatesTable, DbSyncState> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncStatesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _userIdMeta = const VerificationMeta('userId');
  @override
  late final GeneratedColumn<String> userId = GeneratedColumn<String>(
      'user_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _lastKnownUsnMeta =
      const VerificationMeta('lastKnownUsn');
  @override
  late final GeneratedColumn<int> lastKnownUsn = GeneratedColumn<int>(
      'last_known_usn', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _lastSyncAtMeta =
      const VerificationMeta('lastSyncAt');
  @override
  late final GeneratedColumn<String> lastSyncAt = GeneratedColumn<String>(
      'last_sync_at', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [userId, lastKnownUsn, lastSyncAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_states';
  @override
  VerificationContext validateIntegrity(Insertable<DbSyncState> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('user_id')) {
      context.handle(_userIdMeta,
          userId.isAcceptableOrUnknown(data['user_id']!, _userIdMeta));
    } else if (isInserting) {
      context.missing(_userIdMeta);
    }
    if (data.containsKey('last_known_usn')) {
      context.handle(
          _lastKnownUsnMeta,
          lastKnownUsn.isAcceptableOrUnknown(
              data['last_known_usn']!, _lastKnownUsnMeta));
    }
    if (data.containsKey('last_sync_at')) {
      context.handle(
          _lastSyncAtMeta,
          lastSyncAt.isAcceptableOrUnknown(
              data['last_sync_at']!, _lastSyncAtMeta));
    } else if (isInserting) {
      context.missing(_lastSyncAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {userId};
  @override
  DbSyncState map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbSyncState(
      userId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}user_id'])!,
      lastKnownUsn: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}last_known_usn'])!,
      lastSyncAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}last_sync_at'])!,
    );
  }

  @override
  $SyncStatesTable createAlias(String alias) {
    return $SyncStatesTable(attachedDatabase, alias);
  }
}

class DbSyncState extends DataClass implements Insertable<DbSyncState> {
  final String userId;
  final int lastKnownUsn;
  final String lastSyncAt;
  const DbSyncState(
      {required this.userId,
      required this.lastKnownUsn,
      required this.lastSyncAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['user_id'] = Variable<String>(userId);
    map['last_known_usn'] = Variable<int>(lastKnownUsn);
    map['last_sync_at'] = Variable<String>(lastSyncAt);
    return map;
  }

  SyncStatesCompanion toCompanion(bool nullToAbsent) {
    return SyncStatesCompanion(
      userId: Value(userId),
      lastKnownUsn: Value(lastKnownUsn),
      lastSyncAt: Value(lastSyncAt),
    );
  }

  factory DbSyncState.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbSyncState(
      userId: serializer.fromJson<String>(json['userId']),
      lastKnownUsn: serializer.fromJson<int>(json['lastKnownUsn']),
      lastSyncAt: serializer.fromJson<String>(json['lastSyncAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'userId': serializer.toJson<String>(userId),
      'lastKnownUsn': serializer.toJson<int>(lastKnownUsn),
      'lastSyncAt': serializer.toJson<String>(lastSyncAt),
    };
  }

  DbSyncState copyWith(
          {String? userId, int? lastKnownUsn, String? lastSyncAt}) =>
      DbSyncState(
        userId: userId ?? this.userId,
        lastKnownUsn: lastKnownUsn ?? this.lastKnownUsn,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      );
  DbSyncState copyWithCompanion(SyncStatesCompanion data) {
    return DbSyncState(
      userId: data.userId.present ? data.userId.value : this.userId,
      lastKnownUsn: data.lastKnownUsn.present
          ? data.lastKnownUsn.value
          : this.lastKnownUsn,
      lastSyncAt:
          data.lastSyncAt.present ? data.lastSyncAt.value : this.lastSyncAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbSyncState(')
          ..write('userId: $userId, ')
          ..write('lastKnownUsn: $lastKnownUsn, ')
          ..write('lastSyncAt: $lastSyncAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(userId, lastKnownUsn, lastSyncAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbSyncState &&
          other.userId == this.userId &&
          other.lastKnownUsn == this.lastKnownUsn &&
          other.lastSyncAt == this.lastSyncAt);
}

class SyncStatesCompanion extends UpdateCompanion<DbSyncState> {
  final Value<String> userId;
  final Value<int> lastKnownUsn;
  final Value<String> lastSyncAt;
  final Value<int> rowid;
  const SyncStatesCompanion({
    this.userId = const Value.absent(),
    this.lastKnownUsn = const Value.absent(),
    this.lastSyncAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncStatesCompanion.insert({
    required String userId,
    this.lastKnownUsn = const Value.absent(),
    required String lastSyncAt,
    this.rowid = const Value.absent(),
  })  : userId = Value(userId),
        lastSyncAt = Value(lastSyncAt);
  static Insertable<DbSyncState> custom({
    Expression<String>? userId,
    Expression<int>? lastKnownUsn,
    Expression<String>? lastSyncAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (userId != null) 'user_id': userId,
      if (lastKnownUsn != null) 'last_known_usn': lastKnownUsn,
      if (lastSyncAt != null) 'last_sync_at': lastSyncAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncStatesCompanion copyWith(
      {Value<String>? userId,
      Value<int>? lastKnownUsn,
      Value<String>? lastSyncAt,
      Value<int>? rowid}) {
    return SyncStatesCompanion(
      userId: userId ?? this.userId,
      lastKnownUsn: lastKnownUsn ?? this.lastKnownUsn,
      lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (userId.present) {
      map['user_id'] = Variable<String>(userId.value);
    }
    if (lastKnownUsn.present) {
      map['last_known_usn'] = Variable<int>(lastKnownUsn.value);
    }
    if (lastSyncAt.present) {
      map['last_sync_at'] = Variable<String>(lastSyncAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncStatesCompanion(')
          ..write('userId: $userId, ')
          ..write('lastKnownUsn: $lastKnownUsn, ')
          ..write('lastSyncAt: $lastSyncAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $BankingCardsTable extends BankingCards
    with TableInfo<$BankingCardsTable, DbBankingCard> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $BankingCardsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
      'id', aliasedName, false,
      hasAutoIncrement: true,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultConstraints:
          GeneratedColumn.constraintIsAlways('PRIMARY KEY AUTOINCREMENT'));
  static const VerificationMeta _cardIdMeta = const VerificationMeta('cardId');
  @override
  late final GeneratedColumn<String> cardId = GeneratedColumn<String>(
      'card_id', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _cardNumberMeta =
      const VerificationMeta('cardNumber');
  @override
  late final GeneratedColumn<String> cardNumber = GeneratedColumn<String>(
      'card_number', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _cardHolderMeta =
      const VerificationMeta('cardHolder');
  @override
  late final GeneratedColumn<String> cardHolder = GeneratedColumn<String>(
      'card_holder', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _expiryDateMeta =
      const VerificationMeta('expiryDate');
  @override
  late final GeneratedColumn<String> expiryDate = GeneratedColumn<String>(
      'expiry_date', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _cardTypeMeta =
      const VerificationMeta('cardType');
  @override
  late final GeneratedColumn<String> cardType = GeneratedColumn<String>(
      'card_type', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  static const VerificationMeta _colorIndexMeta =
      const VerificationMeta('colorIndex');
  @override
  late final GeneratedColumn<int> colorIndex = GeneratedColumn<int>(
      'color_index', aliasedName, false,
      type: DriftSqlType.int,
      requiredDuringInsert: false,
      defaultValue: const Constant(0));
  static const VerificationMeta _createdAtMeta =
      const VerificationMeta('createdAt');
  @override
  late final GeneratedColumn<String> createdAt = GeneratedColumn<String>(
      'created_at', aliasedName, false,
      type: DriftSqlType.string, requiredDuringInsert: true);
  @override
  List<GeneratedColumn> get $columns => [
        id,
        cardId,
        cardNumber,
        cardHolder,
        expiryDate,
        cardType,
        colorIndex,
        createdAt
      ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'banking_cards';
  @override
  VerificationContext validateIntegrity(Insertable<DbBankingCard> instance,
      {bool isInserting = false}) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('card_id')) {
      context.handle(_cardIdMeta,
          cardId.isAcceptableOrUnknown(data['card_id']!, _cardIdMeta));
    } else if (isInserting) {
      context.missing(_cardIdMeta);
    }
    if (data.containsKey('card_number')) {
      context.handle(
          _cardNumberMeta,
          cardNumber.isAcceptableOrUnknown(
              data['card_number']!, _cardNumberMeta));
    } else if (isInserting) {
      context.missing(_cardNumberMeta);
    }
    if (data.containsKey('card_holder')) {
      context.handle(
          _cardHolderMeta,
          cardHolder.isAcceptableOrUnknown(
              data['card_holder']!, _cardHolderMeta));
    } else if (isInserting) {
      context.missing(_cardHolderMeta);
    }
    if (data.containsKey('expiry_date')) {
      context.handle(
          _expiryDateMeta,
          expiryDate.isAcceptableOrUnknown(
              data['expiry_date']!, _expiryDateMeta));
    } else if (isInserting) {
      context.missing(_expiryDateMeta);
    }
    if (data.containsKey('card_type')) {
      context.handle(_cardTypeMeta,
          cardType.isAcceptableOrUnknown(data['card_type']!, _cardTypeMeta));
    } else if (isInserting) {
      context.missing(_cardTypeMeta);
    }
    if (data.containsKey('color_index')) {
      context.handle(
          _colorIndexMeta,
          colorIndex.isAcceptableOrUnknown(
              data['color_index']!, _colorIndexMeta));
    }
    if (data.containsKey('created_at')) {
      context.handle(_createdAtMeta,
          createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta));
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DbBankingCard map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DbBankingCard(
      id: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}id'])!,
      cardId: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}card_id'])!,
      cardNumber: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}card_number'])!,
      cardHolder: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}card_holder'])!,
      expiryDate: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}expiry_date'])!,
      cardType: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}card_type'])!,
      colorIndex: attachedDatabase.typeMapping
          .read(DriftSqlType.int, data['${effectivePrefix}color_index'])!,
      createdAt: attachedDatabase.typeMapping
          .read(DriftSqlType.string, data['${effectivePrefix}created_at'])!,
    );
  }

  @override
  $BankingCardsTable createAlias(String alias) {
    return $BankingCardsTable(attachedDatabase, alias);
  }
}

class DbBankingCard extends DataClass implements Insertable<DbBankingCard> {
  final int id;
  final String cardId;
  final String cardNumber;
  final String cardHolder;
  final String expiryDate;
  final String cardType;
  final int colorIndex;
  final String createdAt;
  const DbBankingCard(
      {required this.id,
      required this.cardId,
      required this.cardNumber,
      required this.cardHolder,
      required this.expiryDate,
      required this.cardType,
      required this.colorIndex,
      required this.createdAt});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['card_id'] = Variable<String>(cardId);
    map['card_number'] = Variable<String>(cardNumber);
    map['card_holder'] = Variable<String>(cardHolder);
    map['expiry_date'] = Variable<String>(expiryDate);
    map['card_type'] = Variable<String>(cardType);
    map['color_index'] = Variable<int>(colorIndex);
    map['created_at'] = Variable<String>(createdAt);
    return map;
  }

  BankingCardsCompanion toCompanion(bool nullToAbsent) {
    return BankingCardsCompanion(
      id: Value(id),
      cardId: Value(cardId),
      cardNumber: Value(cardNumber),
      cardHolder: Value(cardHolder),
      expiryDate: Value(expiryDate),
      cardType: Value(cardType),
      colorIndex: Value(colorIndex),
      createdAt: Value(createdAt),
    );
  }

  factory DbBankingCard.fromJson(Map<String, dynamic> json,
      {ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DbBankingCard(
      id: serializer.fromJson<int>(json['id']),
      cardId: serializer.fromJson<String>(json['cardId']),
      cardNumber: serializer.fromJson<String>(json['cardNumber']),
      cardHolder: serializer.fromJson<String>(json['cardHolder']),
      expiryDate: serializer.fromJson<String>(json['expiryDate']),
      cardType: serializer.fromJson<String>(json['cardType']),
      colorIndex: serializer.fromJson<int>(json['colorIndex']),
      createdAt: serializer.fromJson<String>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'cardId': serializer.toJson<String>(cardId),
      'cardNumber': serializer.toJson<String>(cardNumber),
      'cardHolder': serializer.toJson<String>(cardHolder),
      'expiryDate': serializer.toJson<String>(expiryDate),
      'cardType': serializer.toJson<String>(cardType),
      'colorIndex': serializer.toJson<int>(colorIndex),
      'createdAt': serializer.toJson<String>(createdAt),
    };
  }

  DbBankingCard copyWith(
          {int? id,
          String? cardId,
          String? cardNumber,
          String? cardHolder,
          String? expiryDate,
          String? cardType,
          int? colorIndex,
          String? createdAt}) =>
      DbBankingCard(
        id: id ?? this.id,
        cardId: cardId ?? this.cardId,
        cardNumber: cardNumber ?? this.cardNumber,
        cardHolder: cardHolder ?? this.cardHolder,
        expiryDate: expiryDate ?? this.expiryDate,
        cardType: cardType ?? this.cardType,
        colorIndex: colorIndex ?? this.colorIndex,
        createdAt: createdAt ?? this.createdAt,
      );
  DbBankingCard copyWithCompanion(BankingCardsCompanion data) {
    return DbBankingCard(
      id: data.id.present ? data.id.value : this.id,
      cardId: data.cardId.present ? data.cardId.value : this.cardId,
      cardNumber:
          data.cardNumber.present ? data.cardNumber.value : this.cardNumber,
      cardHolder:
          data.cardHolder.present ? data.cardHolder.value : this.cardHolder,
      expiryDate:
          data.expiryDate.present ? data.expiryDate.value : this.expiryDate,
      cardType: data.cardType.present ? data.cardType.value : this.cardType,
      colorIndex:
          data.colorIndex.present ? data.colorIndex.value : this.colorIndex,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DbBankingCard(')
          ..write('id: $id, ')
          ..write('cardId: $cardId, ')
          ..write('cardNumber: $cardNumber, ')
          ..write('cardHolder: $cardHolder, ')
          ..write('expiryDate: $expiryDate, ')
          ..write('cardType: $cardType, ')
          ..write('colorIndex: $colorIndex, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, cardId, cardNumber, cardHolder,
      expiryDate, cardType, colorIndex, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DbBankingCard &&
          other.id == this.id &&
          other.cardId == this.cardId &&
          other.cardNumber == this.cardNumber &&
          other.cardHolder == this.cardHolder &&
          other.expiryDate == this.expiryDate &&
          other.cardType == this.cardType &&
          other.colorIndex == this.colorIndex &&
          other.createdAt == this.createdAt);
}

class BankingCardsCompanion extends UpdateCompanion<DbBankingCard> {
  final Value<int> id;
  final Value<String> cardId;
  final Value<String> cardNumber;
  final Value<String> cardHolder;
  final Value<String> expiryDate;
  final Value<String> cardType;
  final Value<int> colorIndex;
  final Value<String> createdAt;
  const BankingCardsCompanion({
    this.id = const Value.absent(),
    this.cardId = const Value.absent(),
    this.cardNumber = const Value.absent(),
    this.cardHolder = const Value.absent(),
    this.expiryDate = const Value.absent(),
    this.cardType = const Value.absent(),
    this.colorIndex = const Value.absent(),
    this.createdAt = const Value.absent(),
  });
  BankingCardsCompanion.insert({
    this.id = const Value.absent(),
    required String cardId,
    required String cardNumber,
    required String cardHolder,
    required String expiryDate,
    required String cardType,
    this.colorIndex = const Value.absent(),
    required String createdAt,
  })  : cardId = Value(cardId),
        cardNumber = Value(cardNumber),
        cardHolder = Value(cardHolder),
        expiryDate = Value(expiryDate),
        cardType = Value(cardType),
        createdAt = Value(createdAt);
  static Insertable<DbBankingCard> custom({
    Expression<int>? id,
    Expression<String>? cardId,
    Expression<String>? cardNumber,
    Expression<String>? cardHolder,
    Expression<String>? expiryDate,
    Expression<String>? cardType,
    Expression<int>? colorIndex,
    Expression<String>? createdAt,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cardId != null) 'card_id': cardId,
      if (cardNumber != null) 'card_number': cardNumber,
      if (cardHolder != null) 'card_holder': cardHolder,
      if (expiryDate != null) 'expiry_date': expiryDate,
      if (cardType != null) 'card_type': cardType,
      if (colorIndex != null) 'color_index': colorIndex,
      if (createdAt != null) 'created_at': createdAt,
    });
  }

  BankingCardsCompanion copyWith(
      {Value<int>? id,
      Value<String>? cardId,
      Value<String>? cardNumber,
      Value<String>? cardHolder,
      Value<String>? expiryDate,
      Value<String>? cardType,
      Value<int>? colorIndex,
      Value<String>? createdAt}) {
    return BankingCardsCompanion(
      id: id ?? this.id,
      cardId: cardId ?? this.cardId,
      cardNumber: cardNumber ?? this.cardNumber,
      cardHolder: cardHolder ?? this.cardHolder,
      expiryDate: expiryDate ?? this.expiryDate,
      cardType: cardType ?? this.cardType,
      colorIndex: colorIndex ?? this.colorIndex,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (cardId.present) {
      map['card_id'] = Variable<String>(cardId.value);
    }
    if (cardNumber.present) {
      map['card_number'] = Variable<String>(cardNumber.value);
    }
    if (cardHolder.present) {
      map['card_holder'] = Variable<String>(cardHolder.value);
    }
    if (expiryDate.present) {
      map['expiry_date'] = Variable<String>(expiryDate.value);
    }
    if (cardType.present) {
      map['card_type'] = Variable<String>(cardType.value);
    }
    if (colorIndex.present) {
      map['color_index'] = Variable<int>(colorIndex.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<String>(createdAt.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('BankingCardsCompanion(')
          ..write('id: $id, ')
          ..write('cardId: $cardId, ')
          ..write('cardNumber: $cardNumber, ')
          ..write('cardHolder: $cardHolder, ')
          ..write('expiryDate: $expiryDate, ')
          ..write('cardType: $cardType, ')
          ..write('colorIndex: $colorIndex, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $ChatsTable chats = $ChatsTable(this);
  late final $MessagesTable messages = $MessagesTable(this);
  late final $SyncStatesTable syncStates = $SyncStatesTable(this);
  late final $BankingCardsTable bankingCards = $BankingCardsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities =>
      [chats, messages, syncStates, bankingCards];
}

typedef $$ChatsTableCreateCompanionBuilder = ChatsCompanion Function({
  required String chatId,
  required String chatType,
  required String name,
  Value<String?> avatarUrl,
  Value<String?> lastMessage,
  Value<String?> lastMessageTime,
  required String updatedAt,
  Value<int> unreadCount,
  Value<bool> isOnline,
  Value<String?> lastSeen,
  Value<bool> isPinned,
  Value<String?> lastMessageType,
  Value<bool> lastMessageIsRound,
  Value<String?> lastMessageFileUrl,
  Value<String?> lastMessageGroupedId,
  Value<String?> otherUserId,
  Value<int> lastReadInboxMessageId,
  Value<int> lastReadOutboxMessageId,
  Value<int?> pinnedMessageId,
  Value<String?> username,
  Value<bool> isPublic,
  Value<bool> isBot,
  Value<bool> isVerified,
  Value<bool> isArchived,
  Value<String?> peerCustomizationJson,
  Value<bool> showAuthorProfiles,
  Value<bool> signMessages,
  Value<String?> linkedChatId,
  Value<String?> myRole,
  Value<String?> lastMessageSenderId,
  Value<String?> lastMessageSenderName,
  Value<bool> hasActiveCall,
  Value<String?> chatPermissionsJson,
  Value<String?> reactionSettingsJson,
  Value<bool> hasProtectedContent,
  Value<String?> pinnedMessageIdsJson,
  Value<int> messageAutoDeleteTime,
  Value<String?> appearanceJson,
  Value<bool> isForum,
  Value<bool> participantsHidden,
  Value<bool> hasAggressiveAntiSpamEnabled,
  Value<int> maxReactionsPerPost,
  Value<int> unreadMentionsCount,
  Value<int> unreadReactionsCount,
  Value<int> rowid,
});
typedef $$ChatsTableUpdateCompanionBuilder = ChatsCompanion Function({
  Value<String> chatId,
  Value<String> chatType,
  Value<String> name,
  Value<String?> avatarUrl,
  Value<String?> lastMessage,
  Value<String?> lastMessageTime,
  Value<String> updatedAt,
  Value<int> unreadCount,
  Value<bool> isOnline,
  Value<String?> lastSeen,
  Value<bool> isPinned,
  Value<String?> lastMessageType,
  Value<bool> lastMessageIsRound,
  Value<String?> lastMessageFileUrl,
  Value<String?> lastMessageGroupedId,
  Value<String?> otherUserId,
  Value<int> lastReadInboxMessageId,
  Value<int> lastReadOutboxMessageId,
  Value<int?> pinnedMessageId,
  Value<String?> username,
  Value<bool> isPublic,
  Value<bool> isBot,
  Value<bool> isVerified,
  Value<bool> isArchived,
  Value<String?> peerCustomizationJson,
  Value<bool> showAuthorProfiles,
  Value<bool> signMessages,
  Value<String?> linkedChatId,
  Value<String?> myRole,
  Value<String?> lastMessageSenderId,
  Value<String?> lastMessageSenderName,
  Value<bool> hasActiveCall,
  Value<String?> chatPermissionsJson,
  Value<String?> reactionSettingsJson,
  Value<bool> hasProtectedContent,
  Value<String?> pinnedMessageIdsJson,
  Value<int> messageAutoDeleteTime,
  Value<String?> appearanceJson,
  Value<bool> isForum,
  Value<bool> participantsHidden,
  Value<bool> hasAggressiveAntiSpamEnabled,
  Value<int> maxReactionsPerPost,
  Value<int> unreadMentionsCount,
  Value<int> unreadReactionsCount,
  Value<int> rowid,
});

class $$ChatsTableFilterComposer extends Composer<_$AppDatabase, $ChatsTable> {
  $$ChatsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get chatId => $composableBuilder(
      column: $table.chatId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get chatType => $composableBuilder(
      column: $table.chatType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get avatarUrl => $composableBuilder(
      column: $table.avatarUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastMessage => $composableBuilder(
      column: $table.lastMessage, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastMessageTime => $composableBuilder(
      column: $table.lastMessageTime,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get unreadCount => $composableBuilder(
      column: $table.unreadCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isOnline => $composableBuilder(
      column: $table.isOnline, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastSeen => $composableBuilder(
      column: $table.lastSeen, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isPinned => $composableBuilder(
      column: $table.isPinned, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastMessageType => $composableBuilder(
      column: $table.lastMessageType,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get lastMessageIsRound => $composableBuilder(
      column: $table.lastMessageIsRound,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastMessageFileUrl => $composableBuilder(
      column: $table.lastMessageFileUrl,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastMessageGroupedId => $composableBuilder(
      column: $table.lastMessageGroupedId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get otherUserId => $composableBuilder(
      column: $table.otherUserId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastReadInboxMessageId => $composableBuilder(
      column: $table.lastReadInboxMessageId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastReadOutboxMessageId => $composableBuilder(
      column: $table.lastReadOutboxMessageId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get pinnedMessageId => $composableBuilder(
      column: $table.pinnedMessageId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get username => $composableBuilder(
      column: $table.username, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isPublic => $composableBuilder(
      column: $table.isPublic, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isBot => $composableBuilder(
      column: $table.isBot, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isVerified => $composableBuilder(
      column: $table.isVerified, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isArchived => $composableBuilder(
      column: $table.isArchived, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get peerCustomizationJson => $composableBuilder(
      column: $table.peerCustomizationJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get showAuthorProfiles => $composableBuilder(
      column: $table.showAuthorProfiles,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get signMessages => $composableBuilder(
      column: $table.signMessages, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get linkedChatId => $composableBuilder(
      column: $table.linkedChatId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get myRole => $composableBuilder(
      column: $table.myRole, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastMessageSenderId => $composableBuilder(
      column: $table.lastMessageSenderId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastMessageSenderName => $composableBuilder(
      column: $table.lastMessageSenderName,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get hasActiveCall => $composableBuilder(
      column: $table.hasActiveCall, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get chatPermissionsJson => $composableBuilder(
      column: $table.chatPermissionsJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get reactionSettingsJson => $composableBuilder(
      column: $table.reactionSettingsJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get hasProtectedContent => $composableBuilder(
      column: $table.hasProtectedContent,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get pinnedMessageIdsJson => $composableBuilder(
      column: $table.pinnedMessageIdsJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get messageAutoDeleteTime => $composableBuilder(
      column: $table.messageAutoDeleteTime,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get appearanceJson => $composableBuilder(
      column: $table.appearanceJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isForum => $composableBuilder(
      column: $table.isForum, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get participantsHidden => $composableBuilder(
      column: $table.participantsHidden,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get hasAggressiveAntiSpamEnabled => $composableBuilder(
      column: $table.hasAggressiveAntiSpamEnabled,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get maxReactionsPerPost => $composableBuilder(
      column: $table.maxReactionsPerPost,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get unreadMentionsCount => $composableBuilder(
      column: $table.unreadMentionsCount,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get unreadReactionsCount => $composableBuilder(
      column: $table.unreadReactionsCount,
      builder: (column) => ColumnFilters(column));
}

class $$ChatsTableOrderingComposer
    extends Composer<_$AppDatabase, $ChatsTable> {
  $$ChatsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get chatId => $composableBuilder(
      column: $table.chatId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get chatType => $composableBuilder(
      column: $table.chatType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get name => $composableBuilder(
      column: $table.name, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get avatarUrl => $composableBuilder(
      column: $table.avatarUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastMessage => $composableBuilder(
      column: $table.lastMessage, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastMessageTime => $composableBuilder(
      column: $table.lastMessageTime,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get updatedAt => $composableBuilder(
      column: $table.updatedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get unreadCount => $composableBuilder(
      column: $table.unreadCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isOnline => $composableBuilder(
      column: $table.isOnline, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastSeen => $composableBuilder(
      column: $table.lastSeen, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isPinned => $composableBuilder(
      column: $table.isPinned, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastMessageType => $composableBuilder(
      column: $table.lastMessageType,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get lastMessageIsRound => $composableBuilder(
      column: $table.lastMessageIsRound,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastMessageFileUrl => $composableBuilder(
      column: $table.lastMessageFileUrl,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastMessageGroupedId => $composableBuilder(
      column: $table.lastMessageGroupedId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get otherUserId => $composableBuilder(
      column: $table.otherUserId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastReadInboxMessageId => $composableBuilder(
      column: $table.lastReadInboxMessageId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastReadOutboxMessageId => $composableBuilder(
      column: $table.lastReadOutboxMessageId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get pinnedMessageId => $composableBuilder(
      column: $table.pinnedMessageId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get username => $composableBuilder(
      column: $table.username, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isPublic => $composableBuilder(
      column: $table.isPublic, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isBot => $composableBuilder(
      column: $table.isBot, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isVerified => $composableBuilder(
      column: $table.isVerified, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isArchived => $composableBuilder(
      column: $table.isArchived, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get peerCustomizationJson => $composableBuilder(
      column: $table.peerCustomizationJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get showAuthorProfiles => $composableBuilder(
      column: $table.showAuthorProfiles,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get signMessages => $composableBuilder(
      column: $table.signMessages,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get linkedChatId => $composableBuilder(
      column: $table.linkedChatId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get myRole => $composableBuilder(
      column: $table.myRole, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastMessageSenderId => $composableBuilder(
      column: $table.lastMessageSenderId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastMessageSenderName => $composableBuilder(
      column: $table.lastMessageSenderName,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get hasActiveCall => $composableBuilder(
      column: $table.hasActiveCall,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get chatPermissionsJson => $composableBuilder(
      column: $table.chatPermissionsJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get reactionSettingsJson => $composableBuilder(
      column: $table.reactionSettingsJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get hasProtectedContent => $composableBuilder(
      column: $table.hasProtectedContent,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get pinnedMessageIdsJson => $composableBuilder(
      column: $table.pinnedMessageIdsJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get messageAutoDeleteTime => $composableBuilder(
      column: $table.messageAutoDeleteTime,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get appearanceJson => $composableBuilder(
      column: $table.appearanceJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isForum => $composableBuilder(
      column: $table.isForum, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get participantsHidden => $composableBuilder(
      column: $table.participantsHidden,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get hasAggressiveAntiSpamEnabled => $composableBuilder(
      column: $table.hasAggressiveAntiSpamEnabled,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get maxReactionsPerPost => $composableBuilder(
      column: $table.maxReactionsPerPost,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get unreadMentionsCount => $composableBuilder(
      column: $table.unreadMentionsCount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get unreadReactionsCount => $composableBuilder(
      column: $table.unreadReactionsCount,
      builder: (column) => ColumnOrderings(column));
}

class $$ChatsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ChatsTable> {
  $$ChatsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get chatId =>
      $composableBuilder(column: $table.chatId, builder: (column) => column);

  GeneratedColumn<String> get chatType =>
      $composableBuilder(column: $table.chatType, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get avatarUrl =>
      $composableBuilder(column: $table.avatarUrl, builder: (column) => column);

  GeneratedColumn<String> get lastMessage => $composableBuilder(
      column: $table.lastMessage, builder: (column) => column);

  GeneratedColumn<String> get lastMessageTime => $composableBuilder(
      column: $table.lastMessageTime, builder: (column) => column);

  GeneratedColumn<String> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  GeneratedColumn<int> get unreadCount => $composableBuilder(
      column: $table.unreadCount, builder: (column) => column);

  GeneratedColumn<bool> get isOnline =>
      $composableBuilder(column: $table.isOnline, builder: (column) => column);

  GeneratedColumn<String> get lastSeen =>
      $composableBuilder(column: $table.lastSeen, builder: (column) => column);

  GeneratedColumn<bool> get isPinned =>
      $composableBuilder(column: $table.isPinned, builder: (column) => column);

  GeneratedColumn<String> get lastMessageType => $composableBuilder(
      column: $table.lastMessageType, builder: (column) => column);

  GeneratedColumn<bool> get lastMessageIsRound => $composableBuilder(
      column: $table.lastMessageIsRound, builder: (column) => column);

  GeneratedColumn<String> get lastMessageFileUrl => $composableBuilder(
      column: $table.lastMessageFileUrl, builder: (column) => column);

  GeneratedColumn<String> get lastMessageGroupedId => $composableBuilder(
      column: $table.lastMessageGroupedId, builder: (column) => column);

  GeneratedColumn<String> get otherUserId => $composableBuilder(
      column: $table.otherUserId, builder: (column) => column);

  GeneratedColumn<int> get lastReadInboxMessageId => $composableBuilder(
      column: $table.lastReadInboxMessageId, builder: (column) => column);

  GeneratedColumn<int> get lastReadOutboxMessageId => $composableBuilder(
      column: $table.lastReadOutboxMessageId, builder: (column) => column);

  GeneratedColumn<int> get pinnedMessageId => $composableBuilder(
      column: $table.pinnedMessageId, builder: (column) => column);

  GeneratedColumn<String> get username =>
      $composableBuilder(column: $table.username, builder: (column) => column);

  GeneratedColumn<bool> get isPublic =>
      $composableBuilder(column: $table.isPublic, builder: (column) => column);

  GeneratedColumn<bool> get isBot =>
      $composableBuilder(column: $table.isBot, builder: (column) => column);

  GeneratedColumn<bool> get isVerified => $composableBuilder(
      column: $table.isVerified, builder: (column) => column);

  GeneratedColumn<bool> get isArchived => $composableBuilder(
      column: $table.isArchived, builder: (column) => column);

  GeneratedColumn<String> get peerCustomizationJson => $composableBuilder(
      column: $table.peerCustomizationJson, builder: (column) => column);

  GeneratedColumn<bool> get showAuthorProfiles => $composableBuilder(
      column: $table.showAuthorProfiles, builder: (column) => column);

  GeneratedColumn<bool> get signMessages => $composableBuilder(
      column: $table.signMessages, builder: (column) => column);

  GeneratedColumn<String> get linkedChatId => $composableBuilder(
      column: $table.linkedChatId, builder: (column) => column);

  GeneratedColumn<String> get myRole =>
      $composableBuilder(column: $table.myRole, builder: (column) => column);

  GeneratedColumn<String> get lastMessageSenderId => $composableBuilder(
      column: $table.lastMessageSenderId, builder: (column) => column);

  GeneratedColumn<String> get lastMessageSenderName => $composableBuilder(
      column: $table.lastMessageSenderName, builder: (column) => column);

  GeneratedColumn<bool> get hasActiveCall => $composableBuilder(
      column: $table.hasActiveCall, builder: (column) => column);

  GeneratedColumn<String> get chatPermissionsJson => $composableBuilder(
      column: $table.chatPermissionsJson, builder: (column) => column);

  GeneratedColumn<String> get reactionSettingsJson => $composableBuilder(
      column: $table.reactionSettingsJson, builder: (column) => column);

  GeneratedColumn<bool> get hasProtectedContent => $composableBuilder(
      column: $table.hasProtectedContent, builder: (column) => column);

  GeneratedColumn<String> get pinnedMessageIdsJson => $composableBuilder(
      column: $table.pinnedMessageIdsJson, builder: (column) => column);

  GeneratedColumn<int> get messageAutoDeleteTime => $composableBuilder(
      column: $table.messageAutoDeleteTime, builder: (column) => column);

  GeneratedColumn<String> get appearanceJson => $composableBuilder(
      column: $table.appearanceJson, builder: (column) => column);

  GeneratedColumn<bool> get isForum =>
      $composableBuilder(column: $table.isForum, builder: (column) => column);

  GeneratedColumn<bool> get participantsHidden => $composableBuilder(
      column: $table.participantsHidden, builder: (column) => column);

  GeneratedColumn<bool> get hasAggressiveAntiSpamEnabled => $composableBuilder(
      column: $table.hasAggressiveAntiSpamEnabled, builder: (column) => column);

  GeneratedColumn<int> get maxReactionsPerPost => $composableBuilder(
      column: $table.maxReactionsPerPost, builder: (column) => column);

  GeneratedColumn<int> get unreadMentionsCount => $composableBuilder(
      column: $table.unreadMentionsCount, builder: (column) => column);

  GeneratedColumn<int> get unreadReactionsCount => $composableBuilder(
      column: $table.unreadReactionsCount, builder: (column) => column);
}

class $$ChatsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $ChatsTable,
    DbChat,
    $$ChatsTableFilterComposer,
    $$ChatsTableOrderingComposer,
    $$ChatsTableAnnotationComposer,
    $$ChatsTableCreateCompanionBuilder,
    $$ChatsTableUpdateCompanionBuilder,
    (DbChat, BaseReferences<_$AppDatabase, $ChatsTable, DbChat>),
    DbChat,
    PrefetchHooks Function()> {
  $$ChatsTableTableManager(_$AppDatabase db, $ChatsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ChatsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ChatsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ChatsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> chatId = const Value.absent(),
            Value<String> chatType = const Value.absent(),
            Value<String> name = const Value.absent(),
            Value<String?> avatarUrl = const Value.absent(),
            Value<String?> lastMessage = const Value.absent(),
            Value<String?> lastMessageTime = const Value.absent(),
            Value<String> updatedAt = const Value.absent(),
            Value<int> unreadCount = const Value.absent(),
            Value<bool> isOnline = const Value.absent(),
            Value<String?> lastSeen = const Value.absent(),
            Value<bool> isPinned = const Value.absent(),
            Value<String?> lastMessageType = const Value.absent(),
            Value<bool> lastMessageIsRound = const Value.absent(),
            Value<String?> lastMessageFileUrl = const Value.absent(),
            Value<String?> lastMessageGroupedId = const Value.absent(),
            Value<String?> otherUserId = const Value.absent(),
            Value<int> lastReadInboxMessageId = const Value.absent(),
            Value<int> lastReadOutboxMessageId = const Value.absent(),
            Value<int?> pinnedMessageId = const Value.absent(),
            Value<String?> username = const Value.absent(),
            Value<bool> isPublic = const Value.absent(),
            Value<bool> isBot = const Value.absent(),
            Value<bool> isVerified = const Value.absent(),
            Value<bool> isArchived = const Value.absent(),
            Value<String?> peerCustomizationJson = const Value.absent(),
            Value<bool> showAuthorProfiles = const Value.absent(),
            Value<bool> signMessages = const Value.absent(),
            Value<String?> linkedChatId = const Value.absent(),
            Value<String?> myRole = const Value.absent(),
            Value<String?> lastMessageSenderId = const Value.absent(),
            Value<String?> lastMessageSenderName = const Value.absent(),
            Value<bool> hasActiveCall = const Value.absent(),
            Value<String?> chatPermissionsJson = const Value.absent(),
            Value<String?> reactionSettingsJson = const Value.absent(),
            Value<bool> hasProtectedContent = const Value.absent(),
            Value<String?> pinnedMessageIdsJson = const Value.absent(),
            Value<int> messageAutoDeleteTime = const Value.absent(),
            Value<String?> appearanceJson = const Value.absent(),
            Value<bool> isForum = const Value.absent(),
            Value<bool> participantsHidden = const Value.absent(),
            Value<bool> hasAggressiveAntiSpamEnabled = const Value.absent(),
            Value<int> maxReactionsPerPost = const Value.absent(),
            Value<int> unreadMentionsCount = const Value.absent(),
            Value<int> unreadReactionsCount = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ChatsCompanion(
            chatId: chatId,
            chatType: chatType,
            name: name,
            avatarUrl: avatarUrl,
            lastMessage: lastMessage,
            lastMessageTime: lastMessageTime,
            updatedAt: updatedAt,
            unreadCount: unreadCount,
            isOnline: isOnline,
            lastSeen: lastSeen,
            isPinned: isPinned,
            lastMessageType: lastMessageType,
            lastMessageIsRound: lastMessageIsRound,
            lastMessageFileUrl: lastMessageFileUrl,
            lastMessageGroupedId: lastMessageGroupedId,
            otherUserId: otherUserId,
            lastReadInboxMessageId: lastReadInboxMessageId,
            lastReadOutboxMessageId: lastReadOutboxMessageId,
            pinnedMessageId: pinnedMessageId,
            username: username,
            isPublic: isPublic,
            isBot: isBot,
            isVerified: isVerified,
            isArchived: isArchived,
            peerCustomizationJson: peerCustomizationJson,
            showAuthorProfiles: showAuthorProfiles,
            signMessages: signMessages,
            linkedChatId: linkedChatId,
            myRole: myRole,
            lastMessageSenderId: lastMessageSenderId,
            lastMessageSenderName: lastMessageSenderName,
            hasActiveCall: hasActiveCall,
            chatPermissionsJson: chatPermissionsJson,
            reactionSettingsJson: reactionSettingsJson,
            hasProtectedContent: hasProtectedContent,
            pinnedMessageIdsJson: pinnedMessageIdsJson,
            messageAutoDeleteTime: messageAutoDeleteTime,
            appearanceJson: appearanceJson,
            isForum: isForum,
            participantsHidden: participantsHidden,
            hasAggressiveAntiSpamEnabled: hasAggressiveAntiSpamEnabled,
            maxReactionsPerPost: maxReactionsPerPost,
            unreadMentionsCount: unreadMentionsCount,
            unreadReactionsCount: unreadReactionsCount,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String chatId,
            required String chatType,
            required String name,
            Value<String?> avatarUrl = const Value.absent(),
            Value<String?> lastMessage = const Value.absent(),
            Value<String?> lastMessageTime = const Value.absent(),
            required String updatedAt,
            Value<int> unreadCount = const Value.absent(),
            Value<bool> isOnline = const Value.absent(),
            Value<String?> lastSeen = const Value.absent(),
            Value<bool> isPinned = const Value.absent(),
            Value<String?> lastMessageType = const Value.absent(),
            Value<bool> lastMessageIsRound = const Value.absent(),
            Value<String?> lastMessageFileUrl = const Value.absent(),
            Value<String?> lastMessageGroupedId = const Value.absent(),
            Value<String?> otherUserId = const Value.absent(),
            Value<int> lastReadInboxMessageId = const Value.absent(),
            Value<int> lastReadOutboxMessageId = const Value.absent(),
            Value<int?> pinnedMessageId = const Value.absent(),
            Value<String?> username = const Value.absent(),
            Value<bool> isPublic = const Value.absent(),
            Value<bool> isBot = const Value.absent(),
            Value<bool> isVerified = const Value.absent(),
            Value<bool> isArchived = const Value.absent(),
            Value<String?> peerCustomizationJson = const Value.absent(),
            Value<bool> showAuthorProfiles = const Value.absent(),
            Value<bool> signMessages = const Value.absent(),
            Value<String?> linkedChatId = const Value.absent(),
            Value<String?> myRole = const Value.absent(),
            Value<String?> lastMessageSenderId = const Value.absent(),
            Value<String?> lastMessageSenderName = const Value.absent(),
            Value<bool> hasActiveCall = const Value.absent(),
            Value<String?> chatPermissionsJson = const Value.absent(),
            Value<String?> reactionSettingsJson = const Value.absent(),
            Value<bool> hasProtectedContent = const Value.absent(),
            Value<String?> pinnedMessageIdsJson = const Value.absent(),
            Value<int> messageAutoDeleteTime = const Value.absent(),
            Value<String?> appearanceJson = const Value.absent(),
            Value<bool> isForum = const Value.absent(),
            Value<bool> participantsHidden = const Value.absent(),
            Value<bool> hasAggressiveAntiSpamEnabled = const Value.absent(),
            Value<int> maxReactionsPerPost = const Value.absent(),
            Value<int> unreadMentionsCount = const Value.absent(),
            Value<int> unreadReactionsCount = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              ChatsCompanion.insert(
            chatId: chatId,
            chatType: chatType,
            name: name,
            avatarUrl: avatarUrl,
            lastMessage: lastMessage,
            lastMessageTime: lastMessageTime,
            updatedAt: updatedAt,
            unreadCount: unreadCount,
            isOnline: isOnline,
            lastSeen: lastSeen,
            isPinned: isPinned,
            lastMessageType: lastMessageType,
            lastMessageIsRound: lastMessageIsRound,
            lastMessageFileUrl: lastMessageFileUrl,
            lastMessageGroupedId: lastMessageGroupedId,
            otherUserId: otherUserId,
            lastReadInboxMessageId: lastReadInboxMessageId,
            lastReadOutboxMessageId: lastReadOutboxMessageId,
            pinnedMessageId: pinnedMessageId,
            username: username,
            isPublic: isPublic,
            isBot: isBot,
            isVerified: isVerified,
            isArchived: isArchived,
            peerCustomizationJson: peerCustomizationJson,
            showAuthorProfiles: showAuthorProfiles,
            signMessages: signMessages,
            linkedChatId: linkedChatId,
            myRole: myRole,
            lastMessageSenderId: lastMessageSenderId,
            lastMessageSenderName: lastMessageSenderName,
            hasActiveCall: hasActiveCall,
            chatPermissionsJson: chatPermissionsJson,
            reactionSettingsJson: reactionSettingsJson,
            hasProtectedContent: hasProtectedContent,
            pinnedMessageIdsJson: pinnedMessageIdsJson,
            messageAutoDeleteTime: messageAutoDeleteTime,
            appearanceJson: appearanceJson,
            isForum: isForum,
            participantsHidden: participantsHidden,
            hasAggressiveAntiSpamEnabled: hasAggressiveAntiSpamEnabled,
            maxReactionsPerPost: maxReactionsPerPost,
            unreadMentionsCount: unreadMentionsCount,
            unreadReactionsCount: unreadReactionsCount,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$ChatsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $ChatsTable,
    DbChat,
    $$ChatsTableFilterComposer,
    $$ChatsTableOrderingComposer,
    $$ChatsTableAnnotationComposer,
    $$ChatsTableCreateCompanionBuilder,
    $$ChatsTableUpdateCompanionBuilder,
    (DbChat, BaseReferences<_$AppDatabase, $ChatsTable, DbChat>),
    DbChat,
    PrefetchHooks Function()>;
typedef $$MessagesTableCreateCompanionBuilder = MessagesCompanion Function({
  required String localId,
  Value<String?> serverId,
  required String chatId,
  required String senderId,
  required String content,
  Value<String> messageType,
  Value<String?> fileUrl,
  Value<String?> fileName,
  Value<String?> replyToMessageId,
  Value<bool> isQuote,
  Value<String?> quoteText,
  Value<int> quoteOffset,
  Value<int> quoteLength,
  Value<String?> replyToSenderId,
  Value<String?> replyToSenderName,
  Value<String?> replyToContent,
  Value<String> replyToMessageType,
  Value<bool> isRead,
  Value<bool> isEdited,
  Value<int> sendStatus,
  Value<String?> senderName,
  Value<String?> senderAvatarUrl,
  required String createdAt,
  Value<bool> isForward,
  Value<String?> forwardFromId,
  Value<String?> forwardFromName,
  Value<String?> forwardFromAvatarUrl,
  Value<String?> senderCustomizationJson,
  Value<String?> groupedId,
  Value<String?> entities,
  Value<String?> reactions,
  Value<String?> linkPreviewOptions,
  Value<bool> invertMedia,
  Value<bool> isRound,
  Value<String?> mediaPayload,
  Value<int> viewsCount,
  Value<String?> authorSignature,
  Value<String?> postAuthorId,
  Value<String?> senderRole,
  Value<String?> senderAdminTitle,
  Value<bool> isFromAnonymousAdmin,
  Value<bool> isSilent,
  Value<int> commentsCount,
  Value<String?> recentRepliersJson,
  Value<String?> threadRootMessageId,
  Value<bool> hasMediaSpoiler,
  Value<String?> expiresAt,
  Value<int> ttlSeconds,
  Value<bool> isViewOnce,
  Value<String?> viewedAt,
  Value<bool> isBurned,
  Value<String?> replyToChatId,
  Value<String?> replyToChatName,
  Value<String?> replyToChatType,
  Value<String?> effectId,
  Value<String?> savedTagsJson,
  Value<int?> topicId,
  Value<int> forwardsCount,
  Value<String?> senderChatId,
  Value<String?> senderChatName,
  Value<String?> senderChatAvatarUrl,
  Value<int> rowid,
});
typedef $$MessagesTableUpdateCompanionBuilder = MessagesCompanion Function({
  Value<String> localId,
  Value<String?> serverId,
  Value<String> chatId,
  Value<String> senderId,
  Value<String> content,
  Value<String> messageType,
  Value<String?> fileUrl,
  Value<String?> fileName,
  Value<String?> replyToMessageId,
  Value<bool> isQuote,
  Value<String?> quoteText,
  Value<int> quoteOffset,
  Value<int> quoteLength,
  Value<String?> replyToSenderId,
  Value<String?> replyToSenderName,
  Value<String?> replyToContent,
  Value<String> replyToMessageType,
  Value<bool> isRead,
  Value<bool> isEdited,
  Value<int> sendStatus,
  Value<String?> senderName,
  Value<String?> senderAvatarUrl,
  Value<String> createdAt,
  Value<bool> isForward,
  Value<String?> forwardFromId,
  Value<String?> forwardFromName,
  Value<String?> forwardFromAvatarUrl,
  Value<String?> senderCustomizationJson,
  Value<String?> groupedId,
  Value<String?> entities,
  Value<String?> reactions,
  Value<String?> linkPreviewOptions,
  Value<bool> invertMedia,
  Value<bool> isRound,
  Value<String?> mediaPayload,
  Value<int> viewsCount,
  Value<String?> authorSignature,
  Value<String?> postAuthorId,
  Value<String?> senderRole,
  Value<String?> senderAdminTitle,
  Value<bool> isFromAnonymousAdmin,
  Value<bool> isSilent,
  Value<int> commentsCount,
  Value<String?> recentRepliersJson,
  Value<String?> threadRootMessageId,
  Value<bool> hasMediaSpoiler,
  Value<String?> expiresAt,
  Value<int> ttlSeconds,
  Value<bool> isViewOnce,
  Value<String?> viewedAt,
  Value<bool> isBurned,
  Value<String?> replyToChatId,
  Value<String?> replyToChatName,
  Value<String?> replyToChatType,
  Value<String?> effectId,
  Value<String?> savedTagsJson,
  Value<int?> topicId,
  Value<int> forwardsCount,
  Value<String?> senderChatId,
  Value<String?> senderChatName,
  Value<String?> senderChatAvatarUrl,
  Value<int> rowid,
});

class $$MessagesTableFilterComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get localId => $composableBuilder(
      column: $table.localId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get chatId => $composableBuilder(
      column: $table.chatId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get senderId => $composableBuilder(
      column: $table.senderId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get messageType => $composableBuilder(
      column: $table.messageType, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fileUrl => $composableBuilder(
      column: $table.fileUrl, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get fileName => $composableBuilder(
      column: $table.fileName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get replyToMessageId => $composableBuilder(
      column: $table.replyToMessageId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isQuote => $composableBuilder(
      column: $table.isQuote, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get quoteText => $composableBuilder(
      column: $table.quoteText, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get quoteOffset => $composableBuilder(
      column: $table.quoteOffset, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get quoteLength => $composableBuilder(
      column: $table.quoteLength, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get replyToSenderId => $composableBuilder(
      column: $table.replyToSenderId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get replyToSenderName => $composableBuilder(
      column: $table.replyToSenderName,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get replyToContent => $composableBuilder(
      column: $table.replyToContent,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get replyToMessageType => $composableBuilder(
      column: $table.replyToMessageType,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isRead => $composableBuilder(
      column: $table.isRead, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isEdited => $composableBuilder(
      column: $table.isEdited, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get sendStatus => $composableBuilder(
      column: $table.sendStatus, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get senderName => $composableBuilder(
      column: $table.senderName, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get senderAvatarUrl => $composableBuilder(
      column: $table.senderAvatarUrl,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isForward => $composableBuilder(
      column: $table.isForward, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get forwardFromId => $composableBuilder(
      column: $table.forwardFromId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get forwardFromName => $composableBuilder(
      column: $table.forwardFromName,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get forwardFromAvatarUrl => $composableBuilder(
      column: $table.forwardFromAvatarUrl,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get senderCustomizationJson => $composableBuilder(
      column: $table.senderCustomizationJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get groupedId => $composableBuilder(
      column: $table.groupedId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get entities => $composableBuilder(
      column: $table.entities, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get reactions => $composableBuilder(
      column: $table.reactions, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get linkPreviewOptions => $composableBuilder(
      column: $table.linkPreviewOptions,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get invertMedia => $composableBuilder(
      column: $table.invertMedia, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isRound => $composableBuilder(
      column: $table.isRound, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get mediaPayload => $composableBuilder(
      column: $table.mediaPayload, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get viewsCount => $composableBuilder(
      column: $table.viewsCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get authorSignature => $composableBuilder(
      column: $table.authorSignature,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get postAuthorId => $composableBuilder(
      column: $table.postAuthorId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get senderRole => $composableBuilder(
      column: $table.senderRole, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get senderAdminTitle => $composableBuilder(
      column: $table.senderAdminTitle,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isFromAnonymousAdmin => $composableBuilder(
      column: $table.isFromAnonymousAdmin,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isSilent => $composableBuilder(
      column: $table.isSilent, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get commentsCount => $composableBuilder(
      column: $table.commentsCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get recentRepliersJson => $composableBuilder(
      column: $table.recentRepliersJson,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get threadRootMessageId => $composableBuilder(
      column: $table.threadRootMessageId,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get hasMediaSpoiler => $composableBuilder(
      column: $table.hasMediaSpoiler,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get expiresAt => $composableBuilder(
      column: $table.expiresAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get ttlSeconds => $composableBuilder(
      column: $table.ttlSeconds, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isViewOnce => $composableBuilder(
      column: $table.isViewOnce, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get viewedAt => $composableBuilder(
      column: $table.viewedAt, builder: (column) => ColumnFilters(column));

  ColumnFilters<bool> get isBurned => $composableBuilder(
      column: $table.isBurned, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get replyToChatId => $composableBuilder(
      column: $table.replyToChatId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get replyToChatName => $composableBuilder(
      column: $table.replyToChatName,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get replyToChatType => $composableBuilder(
      column: $table.replyToChatType,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get effectId => $composableBuilder(
      column: $table.effectId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get savedTagsJson => $composableBuilder(
      column: $table.savedTagsJson, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get topicId => $composableBuilder(
      column: $table.topicId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get forwardsCount => $composableBuilder(
      column: $table.forwardsCount, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get senderChatId => $composableBuilder(
      column: $table.senderChatId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get senderChatName => $composableBuilder(
      column: $table.senderChatName,
      builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get senderChatAvatarUrl => $composableBuilder(
      column: $table.senderChatAvatarUrl,
      builder: (column) => ColumnFilters(column));
}

class $$MessagesTableOrderingComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get localId => $composableBuilder(
      column: $table.localId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get serverId => $composableBuilder(
      column: $table.serverId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get chatId => $composableBuilder(
      column: $table.chatId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get senderId => $composableBuilder(
      column: $table.senderId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get content => $composableBuilder(
      column: $table.content, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get messageType => $composableBuilder(
      column: $table.messageType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fileUrl => $composableBuilder(
      column: $table.fileUrl, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get fileName => $composableBuilder(
      column: $table.fileName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get replyToMessageId => $composableBuilder(
      column: $table.replyToMessageId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isQuote => $composableBuilder(
      column: $table.isQuote, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get quoteText => $composableBuilder(
      column: $table.quoteText, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get quoteOffset => $composableBuilder(
      column: $table.quoteOffset, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get quoteLength => $composableBuilder(
      column: $table.quoteLength, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get replyToSenderId => $composableBuilder(
      column: $table.replyToSenderId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get replyToSenderName => $composableBuilder(
      column: $table.replyToSenderName,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get replyToContent => $composableBuilder(
      column: $table.replyToContent,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get replyToMessageType => $composableBuilder(
      column: $table.replyToMessageType,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isRead => $composableBuilder(
      column: $table.isRead, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isEdited => $composableBuilder(
      column: $table.isEdited, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get sendStatus => $composableBuilder(
      column: $table.sendStatus, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get senderName => $composableBuilder(
      column: $table.senderName, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get senderAvatarUrl => $composableBuilder(
      column: $table.senderAvatarUrl,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isForward => $composableBuilder(
      column: $table.isForward, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get forwardFromId => $composableBuilder(
      column: $table.forwardFromId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get forwardFromName => $composableBuilder(
      column: $table.forwardFromName,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get forwardFromAvatarUrl => $composableBuilder(
      column: $table.forwardFromAvatarUrl,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get senderCustomizationJson => $composableBuilder(
      column: $table.senderCustomizationJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get groupedId => $composableBuilder(
      column: $table.groupedId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get entities => $composableBuilder(
      column: $table.entities, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get reactions => $composableBuilder(
      column: $table.reactions, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get linkPreviewOptions => $composableBuilder(
      column: $table.linkPreviewOptions,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get invertMedia => $composableBuilder(
      column: $table.invertMedia, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isRound => $composableBuilder(
      column: $table.isRound, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get mediaPayload => $composableBuilder(
      column: $table.mediaPayload,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get viewsCount => $composableBuilder(
      column: $table.viewsCount, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get authorSignature => $composableBuilder(
      column: $table.authorSignature,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get postAuthorId => $composableBuilder(
      column: $table.postAuthorId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get senderRole => $composableBuilder(
      column: $table.senderRole, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get senderAdminTitle => $composableBuilder(
      column: $table.senderAdminTitle,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isFromAnonymousAdmin => $composableBuilder(
      column: $table.isFromAnonymousAdmin,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isSilent => $composableBuilder(
      column: $table.isSilent, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get commentsCount => $composableBuilder(
      column: $table.commentsCount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get recentRepliersJson => $composableBuilder(
      column: $table.recentRepliersJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get threadRootMessageId => $composableBuilder(
      column: $table.threadRootMessageId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get hasMediaSpoiler => $composableBuilder(
      column: $table.hasMediaSpoiler,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get expiresAt => $composableBuilder(
      column: $table.expiresAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get ttlSeconds => $composableBuilder(
      column: $table.ttlSeconds, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isViewOnce => $composableBuilder(
      column: $table.isViewOnce, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get viewedAt => $composableBuilder(
      column: $table.viewedAt, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<bool> get isBurned => $composableBuilder(
      column: $table.isBurned, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get replyToChatId => $composableBuilder(
      column: $table.replyToChatId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get replyToChatName => $composableBuilder(
      column: $table.replyToChatName,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get replyToChatType => $composableBuilder(
      column: $table.replyToChatType,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get effectId => $composableBuilder(
      column: $table.effectId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get savedTagsJson => $composableBuilder(
      column: $table.savedTagsJson,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get topicId => $composableBuilder(
      column: $table.topicId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get forwardsCount => $composableBuilder(
      column: $table.forwardsCount,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get senderChatId => $composableBuilder(
      column: $table.senderChatId,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get senderChatName => $composableBuilder(
      column: $table.senderChatName,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get senderChatAvatarUrl => $composableBuilder(
      column: $table.senderChatAvatarUrl,
      builder: (column) => ColumnOrderings(column));
}

class $$MessagesTableAnnotationComposer
    extends Composer<_$AppDatabase, $MessagesTable> {
  $$MessagesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get localId =>
      $composableBuilder(column: $table.localId, builder: (column) => column);

  GeneratedColumn<String> get serverId =>
      $composableBuilder(column: $table.serverId, builder: (column) => column);

  GeneratedColumn<String> get chatId =>
      $composableBuilder(column: $table.chatId, builder: (column) => column);

  GeneratedColumn<String> get senderId =>
      $composableBuilder(column: $table.senderId, builder: (column) => column);

  GeneratedColumn<String> get content =>
      $composableBuilder(column: $table.content, builder: (column) => column);

  GeneratedColumn<String> get messageType => $composableBuilder(
      column: $table.messageType, builder: (column) => column);

  GeneratedColumn<String> get fileUrl =>
      $composableBuilder(column: $table.fileUrl, builder: (column) => column);

  GeneratedColumn<String> get fileName =>
      $composableBuilder(column: $table.fileName, builder: (column) => column);

  GeneratedColumn<String> get replyToMessageId => $composableBuilder(
      column: $table.replyToMessageId, builder: (column) => column);

  GeneratedColumn<bool> get isQuote =>
      $composableBuilder(column: $table.isQuote, builder: (column) => column);

  GeneratedColumn<String> get quoteText =>
      $composableBuilder(column: $table.quoteText, builder: (column) => column);

  GeneratedColumn<int> get quoteOffset => $composableBuilder(
      column: $table.quoteOffset, builder: (column) => column);

  GeneratedColumn<int> get quoteLength => $composableBuilder(
      column: $table.quoteLength, builder: (column) => column);

  GeneratedColumn<String> get replyToSenderId => $composableBuilder(
      column: $table.replyToSenderId, builder: (column) => column);

  GeneratedColumn<String> get replyToSenderName => $composableBuilder(
      column: $table.replyToSenderName, builder: (column) => column);

  GeneratedColumn<String> get replyToContent => $composableBuilder(
      column: $table.replyToContent, builder: (column) => column);

  GeneratedColumn<String> get replyToMessageType => $composableBuilder(
      column: $table.replyToMessageType, builder: (column) => column);

  GeneratedColumn<bool> get isRead =>
      $composableBuilder(column: $table.isRead, builder: (column) => column);

  GeneratedColumn<bool> get isEdited =>
      $composableBuilder(column: $table.isEdited, builder: (column) => column);

  GeneratedColumn<int> get sendStatus => $composableBuilder(
      column: $table.sendStatus, builder: (column) => column);

  GeneratedColumn<String> get senderName => $composableBuilder(
      column: $table.senderName, builder: (column) => column);

  GeneratedColumn<String> get senderAvatarUrl => $composableBuilder(
      column: $table.senderAvatarUrl, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<bool> get isForward =>
      $composableBuilder(column: $table.isForward, builder: (column) => column);

  GeneratedColumn<String> get forwardFromId => $composableBuilder(
      column: $table.forwardFromId, builder: (column) => column);

  GeneratedColumn<String> get forwardFromName => $composableBuilder(
      column: $table.forwardFromName, builder: (column) => column);

  GeneratedColumn<String> get forwardFromAvatarUrl => $composableBuilder(
      column: $table.forwardFromAvatarUrl, builder: (column) => column);

  GeneratedColumn<String> get senderCustomizationJson => $composableBuilder(
      column: $table.senderCustomizationJson, builder: (column) => column);

  GeneratedColumn<String> get groupedId =>
      $composableBuilder(column: $table.groupedId, builder: (column) => column);

  GeneratedColumn<String> get entities =>
      $composableBuilder(column: $table.entities, builder: (column) => column);

  GeneratedColumn<String> get reactions =>
      $composableBuilder(column: $table.reactions, builder: (column) => column);

  GeneratedColumn<String> get linkPreviewOptions => $composableBuilder(
      column: $table.linkPreviewOptions, builder: (column) => column);

  GeneratedColumn<bool> get invertMedia => $composableBuilder(
      column: $table.invertMedia, builder: (column) => column);

  GeneratedColumn<bool> get isRound =>
      $composableBuilder(column: $table.isRound, builder: (column) => column);

  GeneratedColumn<String> get mediaPayload => $composableBuilder(
      column: $table.mediaPayload, builder: (column) => column);

  GeneratedColumn<int> get viewsCount => $composableBuilder(
      column: $table.viewsCount, builder: (column) => column);

  GeneratedColumn<String> get authorSignature => $composableBuilder(
      column: $table.authorSignature, builder: (column) => column);

  GeneratedColumn<String> get postAuthorId => $composableBuilder(
      column: $table.postAuthorId, builder: (column) => column);

  GeneratedColumn<String> get senderRole => $composableBuilder(
      column: $table.senderRole, builder: (column) => column);

  GeneratedColumn<String> get senderAdminTitle => $composableBuilder(
      column: $table.senderAdminTitle, builder: (column) => column);

  GeneratedColumn<bool> get isFromAnonymousAdmin => $composableBuilder(
      column: $table.isFromAnonymousAdmin, builder: (column) => column);

  GeneratedColumn<bool> get isSilent =>
      $composableBuilder(column: $table.isSilent, builder: (column) => column);

  GeneratedColumn<int> get commentsCount => $composableBuilder(
      column: $table.commentsCount, builder: (column) => column);

  GeneratedColumn<String> get recentRepliersJson => $composableBuilder(
      column: $table.recentRepliersJson, builder: (column) => column);

  GeneratedColumn<String> get threadRootMessageId => $composableBuilder(
      column: $table.threadRootMessageId, builder: (column) => column);

  GeneratedColumn<bool> get hasMediaSpoiler => $composableBuilder(
      column: $table.hasMediaSpoiler, builder: (column) => column);

  GeneratedColumn<String> get expiresAt =>
      $composableBuilder(column: $table.expiresAt, builder: (column) => column);

  GeneratedColumn<int> get ttlSeconds => $composableBuilder(
      column: $table.ttlSeconds, builder: (column) => column);

  GeneratedColumn<bool> get isViewOnce => $composableBuilder(
      column: $table.isViewOnce, builder: (column) => column);

  GeneratedColumn<String> get viewedAt =>
      $composableBuilder(column: $table.viewedAt, builder: (column) => column);

  GeneratedColumn<bool> get isBurned =>
      $composableBuilder(column: $table.isBurned, builder: (column) => column);

  GeneratedColumn<String> get replyToChatId => $composableBuilder(
      column: $table.replyToChatId, builder: (column) => column);

  GeneratedColumn<String> get replyToChatName => $composableBuilder(
      column: $table.replyToChatName, builder: (column) => column);

  GeneratedColumn<String> get replyToChatType => $composableBuilder(
      column: $table.replyToChatType, builder: (column) => column);

  GeneratedColumn<String> get effectId =>
      $composableBuilder(column: $table.effectId, builder: (column) => column);

  GeneratedColumn<String> get savedTagsJson => $composableBuilder(
      column: $table.savedTagsJson, builder: (column) => column);

  GeneratedColumn<int> get topicId =>
      $composableBuilder(column: $table.topicId, builder: (column) => column);

  GeneratedColumn<int> get forwardsCount => $composableBuilder(
      column: $table.forwardsCount, builder: (column) => column);

  GeneratedColumn<String> get senderChatId => $composableBuilder(
      column: $table.senderChatId, builder: (column) => column);

  GeneratedColumn<String> get senderChatName => $composableBuilder(
      column: $table.senderChatName, builder: (column) => column);

  GeneratedColumn<String> get senderChatAvatarUrl => $composableBuilder(
      column: $table.senderChatAvatarUrl, builder: (column) => column);
}

class $$MessagesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $MessagesTable,
    DbMessage,
    $$MessagesTableFilterComposer,
    $$MessagesTableOrderingComposer,
    $$MessagesTableAnnotationComposer,
    $$MessagesTableCreateCompanionBuilder,
    $$MessagesTableUpdateCompanionBuilder,
    (DbMessage, BaseReferences<_$AppDatabase, $MessagesTable, DbMessage>),
    DbMessage,
    PrefetchHooks Function()> {
  $$MessagesTableTableManager(_$AppDatabase db, $MessagesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MessagesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MessagesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MessagesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> localId = const Value.absent(),
            Value<String?> serverId = const Value.absent(),
            Value<String> chatId = const Value.absent(),
            Value<String> senderId = const Value.absent(),
            Value<String> content = const Value.absent(),
            Value<String> messageType = const Value.absent(),
            Value<String?> fileUrl = const Value.absent(),
            Value<String?> fileName = const Value.absent(),
            Value<String?> replyToMessageId = const Value.absent(),
            Value<bool> isQuote = const Value.absent(),
            Value<String?> quoteText = const Value.absent(),
            Value<int> quoteOffset = const Value.absent(),
            Value<int> quoteLength = const Value.absent(),
            Value<String?> replyToSenderId = const Value.absent(),
            Value<String?> replyToSenderName = const Value.absent(),
            Value<String?> replyToContent = const Value.absent(),
            Value<String> replyToMessageType = const Value.absent(),
            Value<bool> isRead = const Value.absent(),
            Value<bool> isEdited = const Value.absent(),
            Value<int> sendStatus = const Value.absent(),
            Value<String?> senderName = const Value.absent(),
            Value<String?> senderAvatarUrl = const Value.absent(),
            Value<String> createdAt = const Value.absent(),
            Value<bool> isForward = const Value.absent(),
            Value<String?> forwardFromId = const Value.absent(),
            Value<String?> forwardFromName = const Value.absent(),
            Value<String?> forwardFromAvatarUrl = const Value.absent(),
            Value<String?> senderCustomizationJson = const Value.absent(),
            Value<String?> groupedId = const Value.absent(),
            Value<String?> entities = const Value.absent(),
            Value<String?> reactions = const Value.absent(),
            Value<String?> linkPreviewOptions = const Value.absent(),
            Value<bool> invertMedia = const Value.absent(),
            Value<bool> isRound = const Value.absent(),
            Value<String?> mediaPayload = const Value.absent(),
            Value<int> viewsCount = const Value.absent(),
            Value<String?> authorSignature = const Value.absent(),
            Value<String?> postAuthorId = const Value.absent(),
            Value<String?> senderRole = const Value.absent(),
            Value<String?> senderAdminTitle = const Value.absent(),
            Value<bool> isFromAnonymousAdmin = const Value.absent(),
            Value<bool> isSilent = const Value.absent(),
            Value<int> commentsCount = const Value.absent(),
            Value<String?> recentRepliersJson = const Value.absent(),
            Value<String?> threadRootMessageId = const Value.absent(),
            Value<bool> hasMediaSpoiler = const Value.absent(),
            Value<String?> expiresAt = const Value.absent(),
            Value<int> ttlSeconds = const Value.absent(),
            Value<bool> isViewOnce = const Value.absent(),
            Value<String?> viewedAt = const Value.absent(),
            Value<bool> isBurned = const Value.absent(),
            Value<String?> replyToChatId = const Value.absent(),
            Value<String?> replyToChatName = const Value.absent(),
            Value<String?> replyToChatType = const Value.absent(),
            Value<String?> effectId = const Value.absent(),
            Value<String?> savedTagsJson = const Value.absent(),
            Value<int?> topicId = const Value.absent(),
            Value<int> forwardsCount = const Value.absent(),
            Value<String?> senderChatId = const Value.absent(),
            Value<String?> senderChatName = const Value.absent(),
            Value<String?> senderChatAvatarUrl = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MessagesCompanion(
            localId: localId,
            serverId: serverId,
            chatId: chatId,
            senderId: senderId,
            content: content,
            messageType: messageType,
            fileUrl: fileUrl,
            fileName: fileName,
            replyToMessageId: replyToMessageId,
            isQuote: isQuote,
            quoteText: quoteText,
            quoteOffset: quoteOffset,
            quoteLength: quoteLength,
            replyToSenderId: replyToSenderId,
            replyToSenderName: replyToSenderName,
            replyToContent: replyToContent,
            replyToMessageType: replyToMessageType,
            isRead: isRead,
            isEdited: isEdited,
            sendStatus: sendStatus,
            senderName: senderName,
            senderAvatarUrl: senderAvatarUrl,
            createdAt: createdAt,
            isForward: isForward,
            forwardFromId: forwardFromId,
            forwardFromName: forwardFromName,
            forwardFromAvatarUrl: forwardFromAvatarUrl,
            senderCustomizationJson: senderCustomizationJson,
            groupedId: groupedId,
            entities: entities,
            reactions: reactions,
            linkPreviewOptions: linkPreviewOptions,
            invertMedia: invertMedia,
            isRound: isRound,
            mediaPayload: mediaPayload,
            viewsCount: viewsCount,
            authorSignature: authorSignature,
            postAuthorId: postAuthorId,
            senderRole: senderRole,
            senderAdminTitle: senderAdminTitle,
            isFromAnonymousAdmin: isFromAnonymousAdmin,
            isSilent: isSilent,
            commentsCount: commentsCount,
            recentRepliersJson: recentRepliersJson,
            threadRootMessageId: threadRootMessageId,
            hasMediaSpoiler: hasMediaSpoiler,
            expiresAt: expiresAt,
            ttlSeconds: ttlSeconds,
            isViewOnce: isViewOnce,
            viewedAt: viewedAt,
            isBurned: isBurned,
            replyToChatId: replyToChatId,
            replyToChatName: replyToChatName,
            replyToChatType: replyToChatType,
            effectId: effectId,
            savedTagsJson: savedTagsJson,
            topicId: topicId,
            forwardsCount: forwardsCount,
            senderChatId: senderChatId,
            senderChatName: senderChatName,
            senderChatAvatarUrl: senderChatAvatarUrl,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String localId,
            Value<String?> serverId = const Value.absent(),
            required String chatId,
            required String senderId,
            required String content,
            Value<String> messageType = const Value.absent(),
            Value<String?> fileUrl = const Value.absent(),
            Value<String?> fileName = const Value.absent(),
            Value<String?> replyToMessageId = const Value.absent(),
            Value<bool> isQuote = const Value.absent(),
            Value<String?> quoteText = const Value.absent(),
            Value<int> quoteOffset = const Value.absent(),
            Value<int> quoteLength = const Value.absent(),
            Value<String?> replyToSenderId = const Value.absent(),
            Value<String?> replyToSenderName = const Value.absent(),
            Value<String?> replyToContent = const Value.absent(),
            Value<String> replyToMessageType = const Value.absent(),
            Value<bool> isRead = const Value.absent(),
            Value<bool> isEdited = const Value.absent(),
            Value<int> sendStatus = const Value.absent(),
            Value<String?> senderName = const Value.absent(),
            Value<String?> senderAvatarUrl = const Value.absent(),
            required String createdAt,
            Value<bool> isForward = const Value.absent(),
            Value<String?> forwardFromId = const Value.absent(),
            Value<String?> forwardFromName = const Value.absent(),
            Value<String?> forwardFromAvatarUrl = const Value.absent(),
            Value<String?> senderCustomizationJson = const Value.absent(),
            Value<String?> groupedId = const Value.absent(),
            Value<String?> entities = const Value.absent(),
            Value<String?> reactions = const Value.absent(),
            Value<String?> linkPreviewOptions = const Value.absent(),
            Value<bool> invertMedia = const Value.absent(),
            Value<bool> isRound = const Value.absent(),
            Value<String?> mediaPayload = const Value.absent(),
            Value<int> viewsCount = const Value.absent(),
            Value<String?> authorSignature = const Value.absent(),
            Value<String?> postAuthorId = const Value.absent(),
            Value<String?> senderRole = const Value.absent(),
            Value<String?> senderAdminTitle = const Value.absent(),
            Value<bool> isFromAnonymousAdmin = const Value.absent(),
            Value<bool> isSilent = const Value.absent(),
            Value<int> commentsCount = const Value.absent(),
            Value<String?> recentRepliersJson = const Value.absent(),
            Value<String?> threadRootMessageId = const Value.absent(),
            Value<bool> hasMediaSpoiler = const Value.absent(),
            Value<String?> expiresAt = const Value.absent(),
            Value<int> ttlSeconds = const Value.absent(),
            Value<bool> isViewOnce = const Value.absent(),
            Value<String?> viewedAt = const Value.absent(),
            Value<bool> isBurned = const Value.absent(),
            Value<String?> replyToChatId = const Value.absent(),
            Value<String?> replyToChatName = const Value.absent(),
            Value<String?> replyToChatType = const Value.absent(),
            Value<String?> effectId = const Value.absent(),
            Value<String?> savedTagsJson = const Value.absent(),
            Value<int?> topicId = const Value.absent(),
            Value<int> forwardsCount = const Value.absent(),
            Value<String?> senderChatId = const Value.absent(),
            Value<String?> senderChatName = const Value.absent(),
            Value<String?> senderChatAvatarUrl = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              MessagesCompanion.insert(
            localId: localId,
            serverId: serverId,
            chatId: chatId,
            senderId: senderId,
            content: content,
            messageType: messageType,
            fileUrl: fileUrl,
            fileName: fileName,
            replyToMessageId: replyToMessageId,
            isQuote: isQuote,
            quoteText: quoteText,
            quoteOffset: quoteOffset,
            quoteLength: quoteLength,
            replyToSenderId: replyToSenderId,
            replyToSenderName: replyToSenderName,
            replyToContent: replyToContent,
            replyToMessageType: replyToMessageType,
            isRead: isRead,
            isEdited: isEdited,
            sendStatus: sendStatus,
            senderName: senderName,
            senderAvatarUrl: senderAvatarUrl,
            createdAt: createdAt,
            isForward: isForward,
            forwardFromId: forwardFromId,
            forwardFromName: forwardFromName,
            forwardFromAvatarUrl: forwardFromAvatarUrl,
            senderCustomizationJson: senderCustomizationJson,
            groupedId: groupedId,
            entities: entities,
            reactions: reactions,
            linkPreviewOptions: linkPreviewOptions,
            invertMedia: invertMedia,
            isRound: isRound,
            mediaPayload: mediaPayload,
            viewsCount: viewsCount,
            authorSignature: authorSignature,
            postAuthorId: postAuthorId,
            senderRole: senderRole,
            senderAdminTitle: senderAdminTitle,
            isFromAnonymousAdmin: isFromAnonymousAdmin,
            isSilent: isSilent,
            commentsCount: commentsCount,
            recentRepliersJson: recentRepliersJson,
            threadRootMessageId: threadRootMessageId,
            hasMediaSpoiler: hasMediaSpoiler,
            expiresAt: expiresAt,
            ttlSeconds: ttlSeconds,
            isViewOnce: isViewOnce,
            viewedAt: viewedAt,
            isBurned: isBurned,
            replyToChatId: replyToChatId,
            replyToChatName: replyToChatName,
            replyToChatType: replyToChatType,
            effectId: effectId,
            savedTagsJson: savedTagsJson,
            topicId: topicId,
            forwardsCount: forwardsCount,
            senderChatId: senderChatId,
            senderChatName: senderChatName,
            senderChatAvatarUrl: senderChatAvatarUrl,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$MessagesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $MessagesTable,
    DbMessage,
    $$MessagesTableFilterComposer,
    $$MessagesTableOrderingComposer,
    $$MessagesTableAnnotationComposer,
    $$MessagesTableCreateCompanionBuilder,
    $$MessagesTableUpdateCompanionBuilder,
    (DbMessage, BaseReferences<_$AppDatabase, $MessagesTable, DbMessage>),
    DbMessage,
    PrefetchHooks Function()>;
typedef $$SyncStatesTableCreateCompanionBuilder = SyncStatesCompanion Function({
  required String userId,
  Value<int> lastKnownUsn,
  required String lastSyncAt,
  Value<int> rowid,
});
typedef $$SyncStatesTableUpdateCompanionBuilder = SyncStatesCompanion Function({
  Value<String> userId,
  Value<int> lastKnownUsn,
  Value<String> lastSyncAt,
  Value<int> rowid,
});

class $$SyncStatesTableFilterComposer
    extends Composer<_$AppDatabase, $SyncStatesTable> {
  $$SyncStatesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get lastKnownUsn => $composableBuilder(
      column: $table.lastKnownUsn, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get lastSyncAt => $composableBuilder(
      column: $table.lastSyncAt, builder: (column) => ColumnFilters(column));
}

class $$SyncStatesTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncStatesTable> {
  $$SyncStatesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get userId => $composableBuilder(
      column: $table.userId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get lastKnownUsn => $composableBuilder(
      column: $table.lastKnownUsn,
      builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get lastSyncAt => $composableBuilder(
      column: $table.lastSyncAt, builder: (column) => ColumnOrderings(column));
}

class $$SyncStatesTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncStatesTable> {
  $$SyncStatesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get userId =>
      $composableBuilder(column: $table.userId, builder: (column) => column);

  GeneratedColumn<int> get lastKnownUsn => $composableBuilder(
      column: $table.lastKnownUsn, builder: (column) => column);

  GeneratedColumn<String> get lastSyncAt => $composableBuilder(
      column: $table.lastSyncAt, builder: (column) => column);
}

class $$SyncStatesTableTableManager extends RootTableManager<
    _$AppDatabase,
    $SyncStatesTable,
    DbSyncState,
    $$SyncStatesTableFilterComposer,
    $$SyncStatesTableOrderingComposer,
    $$SyncStatesTableAnnotationComposer,
    $$SyncStatesTableCreateCompanionBuilder,
    $$SyncStatesTableUpdateCompanionBuilder,
    (DbSyncState, BaseReferences<_$AppDatabase, $SyncStatesTable, DbSyncState>),
    DbSyncState,
    PrefetchHooks Function()> {
  $$SyncStatesTableTableManager(_$AppDatabase db, $SyncStatesTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncStatesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncStatesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncStatesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<String> userId = const Value.absent(),
            Value<int> lastKnownUsn = const Value.absent(),
            Value<String> lastSyncAt = const Value.absent(),
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncStatesCompanion(
            userId: userId,
            lastKnownUsn: lastKnownUsn,
            lastSyncAt: lastSyncAt,
            rowid: rowid,
          ),
          createCompanionCallback: ({
            required String userId,
            Value<int> lastKnownUsn = const Value.absent(),
            required String lastSyncAt,
            Value<int> rowid = const Value.absent(),
          }) =>
              SyncStatesCompanion.insert(
            userId: userId,
            lastKnownUsn: lastKnownUsn,
            lastSyncAt: lastSyncAt,
            rowid: rowid,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$SyncStatesTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $SyncStatesTable,
    DbSyncState,
    $$SyncStatesTableFilterComposer,
    $$SyncStatesTableOrderingComposer,
    $$SyncStatesTableAnnotationComposer,
    $$SyncStatesTableCreateCompanionBuilder,
    $$SyncStatesTableUpdateCompanionBuilder,
    (DbSyncState, BaseReferences<_$AppDatabase, $SyncStatesTable, DbSyncState>),
    DbSyncState,
    PrefetchHooks Function()>;
typedef $$BankingCardsTableCreateCompanionBuilder = BankingCardsCompanion
    Function({
  Value<int> id,
  required String cardId,
  required String cardNumber,
  required String cardHolder,
  required String expiryDate,
  required String cardType,
  Value<int> colorIndex,
  required String createdAt,
});
typedef $$BankingCardsTableUpdateCompanionBuilder = BankingCardsCompanion
    Function({
  Value<int> id,
  Value<String> cardId,
  Value<String> cardNumber,
  Value<String> cardHolder,
  Value<String> expiryDate,
  Value<String> cardType,
  Value<int> colorIndex,
  Value<String> createdAt,
});

class $$BankingCardsTableFilterComposer
    extends Composer<_$AppDatabase, $BankingCardsTable> {
  $$BankingCardsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cardId => $composableBuilder(
      column: $table.cardId, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cardNumber => $composableBuilder(
      column: $table.cardNumber, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cardHolder => $composableBuilder(
      column: $table.cardHolder, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get expiryDate => $composableBuilder(
      column: $table.expiryDate, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get cardType => $composableBuilder(
      column: $table.cardType, builder: (column) => ColumnFilters(column));

  ColumnFilters<int> get colorIndex => $composableBuilder(
      column: $table.colorIndex, builder: (column) => ColumnFilters(column));

  ColumnFilters<String> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnFilters(column));
}

class $$BankingCardsTableOrderingComposer
    extends Composer<_$AppDatabase, $BankingCardsTable> {
  $$BankingCardsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
      column: $table.id, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cardId => $composableBuilder(
      column: $table.cardId, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cardNumber => $composableBuilder(
      column: $table.cardNumber, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cardHolder => $composableBuilder(
      column: $table.cardHolder, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get expiryDate => $composableBuilder(
      column: $table.expiryDate, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get cardType => $composableBuilder(
      column: $table.cardType, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<int> get colorIndex => $composableBuilder(
      column: $table.colorIndex, builder: (column) => ColumnOrderings(column));

  ColumnOrderings<String> get createdAt => $composableBuilder(
      column: $table.createdAt, builder: (column) => ColumnOrderings(column));
}

class $$BankingCardsTableAnnotationComposer
    extends Composer<_$AppDatabase, $BankingCardsTable> {
  $$BankingCardsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cardId =>
      $composableBuilder(column: $table.cardId, builder: (column) => column);

  GeneratedColumn<String> get cardNumber => $composableBuilder(
      column: $table.cardNumber, builder: (column) => column);

  GeneratedColumn<String> get cardHolder => $composableBuilder(
      column: $table.cardHolder, builder: (column) => column);

  GeneratedColumn<String> get expiryDate => $composableBuilder(
      column: $table.expiryDate, builder: (column) => column);

  GeneratedColumn<String> get cardType =>
      $composableBuilder(column: $table.cardType, builder: (column) => column);

  GeneratedColumn<int> get colorIndex => $composableBuilder(
      column: $table.colorIndex, builder: (column) => column);

  GeneratedColumn<String> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$BankingCardsTableTableManager extends RootTableManager<
    _$AppDatabase,
    $BankingCardsTable,
    DbBankingCard,
    $$BankingCardsTableFilterComposer,
    $$BankingCardsTableOrderingComposer,
    $$BankingCardsTableAnnotationComposer,
    $$BankingCardsTableCreateCompanionBuilder,
    $$BankingCardsTableUpdateCompanionBuilder,
    (
      DbBankingCard,
      BaseReferences<_$AppDatabase, $BankingCardsTable, DbBankingCard>
    ),
    DbBankingCard,
    PrefetchHooks Function()> {
  $$BankingCardsTableTableManager(_$AppDatabase db, $BankingCardsTable table)
      : super(TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$BankingCardsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$BankingCardsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$BankingCardsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback: ({
            Value<int> id = const Value.absent(),
            Value<String> cardId = const Value.absent(),
            Value<String> cardNumber = const Value.absent(),
            Value<String> cardHolder = const Value.absent(),
            Value<String> expiryDate = const Value.absent(),
            Value<String> cardType = const Value.absent(),
            Value<int> colorIndex = const Value.absent(),
            Value<String> createdAt = const Value.absent(),
          }) =>
              BankingCardsCompanion(
            id: id,
            cardId: cardId,
            cardNumber: cardNumber,
            cardHolder: cardHolder,
            expiryDate: expiryDate,
            cardType: cardType,
            colorIndex: colorIndex,
            createdAt: createdAt,
          ),
          createCompanionCallback: ({
            Value<int> id = const Value.absent(),
            required String cardId,
            required String cardNumber,
            required String cardHolder,
            required String expiryDate,
            required String cardType,
            Value<int> colorIndex = const Value.absent(),
            required String createdAt,
          }) =>
              BankingCardsCompanion.insert(
            id: id,
            cardId: cardId,
            cardNumber: cardNumber,
            cardHolder: cardHolder,
            expiryDate: expiryDate,
            cardType: cardType,
            colorIndex: colorIndex,
            createdAt: createdAt,
          ),
          withReferenceMapper: (p0) => p0
              .map((e) => (e.readTable(table), BaseReferences(db, table, e)))
              .toList(),
          prefetchHooksCallback: null,
        ));
}

typedef $$BankingCardsTableProcessedTableManager = ProcessedTableManager<
    _$AppDatabase,
    $BankingCardsTable,
    DbBankingCard,
    $$BankingCardsTableFilterComposer,
    $$BankingCardsTableOrderingComposer,
    $$BankingCardsTableAnnotationComposer,
    $$BankingCardsTableCreateCompanionBuilder,
    $$BankingCardsTableUpdateCompanionBuilder,
    (
      DbBankingCard,
      BaseReferences<_$AppDatabase, $BankingCardsTable, DbBankingCard>
    ),
    DbBankingCard,
    PrefetchHooks Function()>;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$ChatsTableTableManager get chats =>
      $$ChatsTableTableManager(_db, _db.chats);
  $$MessagesTableTableManager get messages =>
      $$MessagesTableTableManager(_db, _db.messages);
  $$SyncStatesTableTableManager get syncStates =>
      $$SyncStatesTableTableManager(_db, _db.syncStates);
  $$BankingCardsTableTableManager get bankingCards =>
      $$BankingCardsTableTableManager(_db, _db.bankingCards);
}
