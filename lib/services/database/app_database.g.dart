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
        otherUserId
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
      this.otherUserId});
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
          Value<String?> otherUserId = const Value.absent()}) =>
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
          ..write('otherUserId: $otherUserId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
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
      otherUserId);
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
          other.otherUserId == this.otherUserId);
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
        groupedId,
        entities,
        reactions,
        linkPreviewOptions,
        invertMedia,
        isRound,
        mediaPayload
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
  final String? groupedId;
  final String? entities;
  final String? reactions;
  final String? linkPreviewOptions;
  final bool invertMedia;
  final bool isRound;
  final String? mediaPayload;
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
      this.groupedId,
      this.entities,
      this.reactions,
      this.linkPreviewOptions,
      required this.invertMedia,
      required this.isRound,
      this.mediaPayload});
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
      groupedId: serializer.fromJson<String?>(json['groupedId']),
      entities: serializer.fromJson<String?>(json['entities']),
      reactions: serializer.fromJson<String?>(json['reactions']),
      linkPreviewOptions:
          serializer.fromJson<String?>(json['linkPreviewOptions']),
      invertMedia: serializer.fromJson<bool>(json['invertMedia']),
      isRound: serializer.fromJson<bool>(json['isRound']),
      mediaPayload: serializer.fromJson<String?>(json['mediaPayload']),
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
      'groupedId': serializer.toJson<String?>(groupedId),
      'entities': serializer.toJson<String?>(entities),
      'reactions': serializer.toJson<String?>(reactions),
      'linkPreviewOptions': serializer.toJson<String?>(linkPreviewOptions),
      'invertMedia': serializer.toJson<bool>(invertMedia),
      'isRound': serializer.toJson<bool>(isRound),
      'mediaPayload': serializer.toJson<String?>(mediaPayload),
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
          Value<String?> groupedId = const Value.absent(),
          Value<String?> entities = const Value.absent(),
          Value<String?> reactions = const Value.absent(),
          Value<String?> linkPreviewOptions = const Value.absent(),
          bool? invertMedia,
          bool? isRound,
          Value<String?> mediaPayload = const Value.absent()}) =>
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
          ..write('groupedId: $groupedId, ')
          ..write('entities: $entities, ')
          ..write('reactions: $reactions, ')
          ..write('linkPreviewOptions: $linkPreviewOptions, ')
          ..write('invertMedia: $invertMedia, ')
          ..write('isRound: $isRound, ')
          ..write('mediaPayload: $mediaPayload')
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
        groupedId,
        entities,
        reactions,
        linkPreviewOptions,
        invertMedia,
        isRound,
        mediaPayload
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
          other.groupedId == this.groupedId &&
          other.entities == this.entities &&
          other.reactions == this.reactions &&
          other.linkPreviewOptions == this.linkPreviewOptions &&
          other.invertMedia == this.invertMedia &&
          other.isRound == this.isRound &&
          other.mediaPayload == this.mediaPayload);
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
  final Value<String?> groupedId;
  final Value<String?> entities;
  final Value<String?> reactions;
  final Value<String?> linkPreviewOptions;
  final Value<bool> invertMedia;
  final Value<bool> isRound;
  final Value<String?> mediaPayload;
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
    this.groupedId = const Value.absent(),
    this.entities = const Value.absent(),
    this.reactions = const Value.absent(),
    this.linkPreviewOptions = const Value.absent(),
    this.invertMedia = const Value.absent(),
    this.isRound = const Value.absent(),
    this.mediaPayload = const Value.absent(),
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
    this.groupedId = const Value.absent(),
    this.entities = const Value.absent(),
    this.reactions = const Value.absent(),
    this.linkPreviewOptions = const Value.absent(),
    this.invertMedia = const Value.absent(),
    this.isRound = const Value.absent(),
    this.mediaPayload = const Value.absent(),
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
    Expression<String>? groupedId,
    Expression<String>? entities,
    Expression<String>? reactions,
    Expression<String>? linkPreviewOptions,
    Expression<bool>? invertMedia,
    Expression<bool>? isRound,
    Expression<String>? mediaPayload,
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
      if (groupedId != null) 'grouped_id': groupedId,
      if (entities != null) 'entities': entities,
      if (reactions != null) 'reactions': reactions,
      if (linkPreviewOptions != null)
        'link_preview_options': linkPreviewOptions,
      if (invertMedia != null) 'invert_media': invertMedia,
      if (isRound != null) 'is_round': isRound,
      if (mediaPayload != null) 'media_payload': mediaPayload,
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
      Value<String?>? groupedId,
      Value<String?>? entities,
      Value<String?>? reactions,
      Value<String?>? linkPreviewOptions,
      Value<bool>? invertMedia,
      Value<bool>? isRound,
      Value<String?>? mediaPayload,
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
      groupedId: groupedId ?? this.groupedId,
      entities: entities ?? this.entities,
      reactions: reactions ?? this.reactions,
      linkPreviewOptions: linkPreviewOptions ?? this.linkPreviewOptions,
      invertMedia: invertMedia ?? this.invertMedia,
      isRound: isRound ?? this.isRound,
      mediaPayload: mediaPayload ?? this.mediaPayload,
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
          ..write('groupedId: $groupedId, ')
          ..write('entities: $entities, ')
          ..write('reactions: $reactions, ')
          ..write('linkPreviewOptions: $linkPreviewOptions, ')
          ..write('invertMedia: $invertMedia, ')
          ..write('isRound: $isRound, ')
          ..write('mediaPayload: $mediaPayload, ')
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
  Value<String?> groupedId,
  Value<String?> entities,
  Value<String?> reactions,
  Value<String?> linkPreviewOptions,
  Value<bool> invertMedia,
  Value<bool> isRound,
  Value<String?> mediaPayload,
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
  Value<String?> groupedId,
  Value<String?> entities,
  Value<String?> reactions,
  Value<String?> linkPreviewOptions,
  Value<bool> invertMedia,
  Value<bool> isRound,
  Value<String?> mediaPayload,
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
            Value<String?> groupedId = const Value.absent(),
            Value<String?> entities = const Value.absent(),
            Value<String?> reactions = const Value.absent(),
            Value<String?> linkPreviewOptions = const Value.absent(),
            Value<bool> invertMedia = const Value.absent(),
            Value<bool> isRound = const Value.absent(),
            Value<String?> mediaPayload = const Value.absent(),
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
            groupedId: groupedId,
            entities: entities,
            reactions: reactions,
            linkPreviewOptions: linkPreviewOptions,
            invertMedia: invertMedia,
            isRound: isRound,
            mediaPayload: mediaPayload,
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
            Value<String?> groupedId = const Value.absent(),
            Value<String?> entities = const Value.absent(),
            Value<String?> reactions = const Value.absent(),
            Value<String?> linkPreviewOptions = const Value.absent(),
            Value<bool> invertMedia = const Value.absent(),
            Value<bool> isRound = const Value.absent(),
            Value<String?> mediaPayload = const Value.absent(),
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
            groupedId: groupedId,
            entities: entities,
            reactions: reactions,
            linkPreviewOptions: linkPreviewOptions,
            invertMedia: invertMedia,
            isRound: isRound,
            mediaPayload: mediaPayload,
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
